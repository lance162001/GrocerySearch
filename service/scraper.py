"""Scraper entry-point — orchestrates per-store scrapers and manages scheduling."""

from __future__ import annotations

import argparse
import logging
import threading
import time
from collections import defaultdict
from datetime import datetime
from typing import Any, Callable, cast

import schedule
from sqlalchemy.orm import Session

import emailer
from models import Company, Store, Tag
from models.base import engine
from models.bootstrap import ensure_runtime_schema
from models.stores import ScraperStatus
from scrapers import scrape_whole_foods, scrape_trader_joes, scrape_wegmans
from scrapers.persistence import ensure_collector_shape
from scrapers.utils import setup_seed_data, load_existing_tags, compute_variation_groups

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(name)s] %(levelname)s: %(message)s")
logger = logging.getLogger(__name__)

def _write_status(status: str, **extra: object) -> None:
    """Persist scraper status to the database so the admin dashboard can read it."""
    sess = Session(engine, expire_on_commit=False)
    try:
        row = sess.get(ScraperStatus, 1)
        if row is None:
            row = ScraperStatus(id=1)
            sess.add(row)
        setattr(row, "status", status)
        setattr(row, "updated_at", datetime.now())
        for key, val in extra.items():
            if hasattr(row, key):
                setattr(row, key, val)
        sess.commit()
    except Exception:
        sess.rollback()
        logger.warning("Failed to write scraper status to DB", exc_info=True)
    finally:
        sess.close()


def _new_session() -> Session:
    # Collector entries are read after worker sessions commit and close.
    return Session(engine, expire_on_commit=False)


def _new_collector() -> dict:
    return ensure_collector_shape({})


_SCRAPER_REGISTRY: dict[str, dict[str, object]] = {
    "whole_foods": {
        "aliases": {"wf", "wholefoods", "whole_foods", "whole-foods"},
        "label": "WF",
        "scrape": scrape_whole_foods,
    },
    "trader_joes": {
        "aliases": {"tj", "traderjoes", "trader_joes", "trader-joes"},
        "label": "TJ",
        "scrape": scrape_trader_joes,
    },
    "wegmans": {
        "aliases": {"wg", "wegmans"},
        "label": "WG",
        "scrape": scrape_wegmans,
    },
}


def _normalize_company_token(raw: str) -> str:
    return raw.strip().lower().replace("_", "-").replace(" ", "-")


def _store_company_id(store: Store) -> int:
    return int(cast(Any, store.company_id))


def _resolve_only_company_ids(companies: list[Company], raw_filters: list[str] | None) -> set[int] | None:
    if not raw_filters:
        return None

    alias_map: dict[str, int] = {}
    for company in companies:
        scraper_key = str(company.scraper_key or "")
        normalized_scraper_key = _normalize_company_token(scraper_key)
        normalized_name = _normalize_company_token(str(company.name or ""))
        normalized_slug = _normalize_company_token(str(company.slug or ""))
        alias_map[str(company.id)] = int(company.id)
        for token in filter(None, {normalized_scraper_key, normalized_name, normalized_slug}):
            alias_map[token] = int(company.id)
        registry_entry = _SCRAPER_REGISTRY.get(scraper_key)
        if registry_entry is not None:
            for alias in cast(set[str], registry_entry["aliases"]):
                alias_map[_normalize_company_token(str(alias))] = int(company.id)

    resolved: set[int] = set()
    for raw_filter in raw_filters:
        token = _normalize_company_token(raw_filter)
        if token not in alias_map:
            raise SystemExit(
                f"Unknown company '{raw_filter}'. Use a company id, slug, name, or registered scraper alias."
            )
        resolved.add(alias_map[token])
    return resolved


def _scrape_stores(stores: list, companies_by_id: dict[int, Company], tags: dict[str, int], collector: dict,
                   only: set[int] | None = None) -> None:
    """Scrape all active stores, running one worker thread per company.

    If *only* is provided, skip companies not in the set.
    """
    grouped_stores: dict[int, list[Store]] = defaultdict(list)
    for store in stores:
        store_company_id = _store_company_id(store)
        if only is not None and store_company_id not in only:
            continue
        grouped_stores[store_company_id].append(store)

    threads: list[threading.Thread] = []
    worker_errors: list[tuple[str, Exception]] = []
    worker_errors_lock = threading.Lock()

    def _run_company(company: Company, company_stores: list[Store], scrape_fn: Callable[..., None], label: str) -> None:
        logger.info("%s thread starting: %d store(s) to scrape", label, len(company_stores))
        sess = _new_session()
        try:
            for store in company_stores:
                logger.info("%s: scraping store id=%s scraper_id=%s", label, store.id, store.scraper_id)
                t0 = datetime.now()
                try:
                    scrape_fn(store.id, store.scraper_id, sess, tags, collector)
                    logger.info(
                        "%s: finished store id=%s in %.1fs",
                        label,
                        store.id,
                        (datetime.now() - t0).total_seconds(),
                    )
                except Exception:
                    logger.error(
                        "%s: store id=%s failed after %.1fs",
                        label,
                        store.id,
                        (datetime.now() - t0).total_seconds(),
                        exc_info=True,
                    )
                    raise
        except Exception as exc:
            sess.rollback()
            with worker_errors_lock:
                worker_errors.append((label, exc))
        finally:
            sess.close()
        logger.info("%s thread done", label)

    for company_id, company_stores in grouped_stores.items():
        company = companies_by_id.get(company_id)
        if company is None or company.is_active is False:
            continue
        registry_entry = _SCRAPER_REGISTRY.get(str(company.scraper_key or ""))
        if registry_entry is None:
            logger.warning("Skipping company id=%s name=%s; unknown scraper_key=%r", company_id, company.name, company.scraper_key)
            continue
        thread = threading.Thread(
            target=_run_company,
            args=(company, company_stores, cast(Callable[..., None], registry_entry["scrape"]), str(registry_entry["label"])),
            name=f"scraper-{company.scraper_key}",
        )
        thread.start()
        threads.append(thread)

    for thread in threads:
        thread.join()

    if worker_errors:
        labels = ", ".join(sorted({label for label, _ in worker_errors}))
        raise RuntimeError(f"Scraper worker failure for: {labels}") from worker_errors[0][1]


def ensure_schema() -> None:
    """Create tables and run lightweight migrations."""
    ensure_runtime_schema()


@schedule.repeat(schedule.every().day.at("10:30"))
def scheduled_job() -> None:
    collector = _new_collector()
    logger.info("Scraping started")
    start = datetime.now()
    _write_status("running", started_at=start)

    sess = _new_session()
    try:
        stores = sess.query(Store).filter(Store.is_active.isnot(False)).all()
        if not stores:
            stores, tags = setup_seed_data(sess)
        else:
            tags = load_existing_tags(sess)
        companies = (
            sess.query(Company)
            .filter(Company.is_active.isnot(False))
            .all()
        )
        only_ids = _resolve_only_company_ids(companies, only_filters)
        stores_to_scrape = [s for s in stores if only_ids is None or _store_company_id(s) in only_ids]

        logger.info(
            "Scraping %d store(s): %s",
            len(stores_to_scrape),
            ", ".join(f"id={s.id} company={s.company_id}" for s in stores_to_scrape),
        )
        collector["stores"] = stores_to_scrape
        collector["companies"] = companies

        _scrape_stores(stores_to_scrape, {int(c.id): c for c in companies}, tags, collector, only=only_ids)
        logger.info(
            "All stores done — products=%d instances=%d inserted_price_points=%d updated_price_points=%d",
            len(collector["products"]),
            len(collector["product_instances"]),
            len(collector["price_points"]),
            int(collector.get("updated_price_points", 0)),
        )
        variation_sess = _new_session()
        try:
            compute_variation_groups(variation_sess)
        finally:
            variation_sess.close()

        summary = (
            f"GS Scraper Daily Run\n"
            f"Started: {start:%A, %d %B %Y %I:%M%p}\n"
            f"Ended: {datetime.now():%A, %d %B %Y %I:%M%p}\n"
            f"Companies scraped: {len({_store_company_id(s) for s in stores_to_scrape})}\n"
            f"Stores scraped: {len(stores_to_scrape)}\n"
            f"New products: {len(collector['products'])}\n"
            f"New instances: {len(collector['product_instances'])}\n"
            f"New price points: {len(collector['price_points'])}\n"
            f"Updated same-day price points: {int(collector.get('updated_price_points', 0))}\n"
        )
        for p in collector["products"]:
            summary += f"\n  {p.name} | {p.brand} | company_id={p.company_id}"

        try:
            emailer.simple_send(summary)
        except Exception as exc:
            if debug:
                logger.warning("Summary email skipped in debug mode: %s", exc)
            else:
                logger.warning("Summary email skipped: %s", exc)

        try:
            emailer.send(collector)
        except Exception as exc:
            if debug:
                logger.warning("Newsletter skipped in debug mode: %s", exc)
            else:
                logger.error("Newsletter delivery failed: %s", exc, exc_info=True)
                raise
    except Exception as exc:
        logger.error("Scraping run failed: %s", exc, exc_info=True)
        _write_status("error", started_at=start, error=str(exc)[:500])
        raise
    finally:
        sess.close()

    _write_status(
        "idle",
        started_at=start,
        last_finished=datetime.now(),
        companies_scraped=len({_store_company_id(s) for s in stores_to_scrape}),
        stores_scraped=len(stores_to_scrape),
        new_products=len(collector["products"]),
        new_instances=len(collector["product_instances"]),
        new_price_points=len(collector["price_points"]),
        updated_price_points=int(collector.get("updated_price_points", 0)),
    )
    logger.info("Scraping finished")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="GrocerySearch scraper")
    parser.add_argument(
        "--debug", "-d", action="store_true",
        help="Run once immediately instead of on the daily schedule.",
    )
    parser.add_argument(
        "--only", nargs="+", metavar="COMPANY",
        help=(
            "Only scrape the listed companies. "
            "Accepted values: company id, slug, name, or registered scraper alias."
        ),
    )
    parser.add_argument(
        "--run-once", action="store_true",
        help="Run one scrape pass and exit (no scheduler loop).",
    )
    parser.add_argument(
        "--run-on-start", action="store_true",
        help="Run one scrape pass immediately, then continue with the scheduler loop.",
    )
    parser.add_argument(
        "--verbose", "-v", action="store_true",
        help="Enable verbose output, including SQLAlchemy SQL logs.",
    )
    return parser.parse_args()


args = _parse_args()
debug = args.debug
run_once = args.run_once
run_on_start = args.run_on_start

if args.verbose:
    engine.echo = True
else:
    logging.getLogger("sqlalchemy").setLevel(logging.WARNING)

only_filters: list[str] | None = args.only or None
if only_filters:
    logger.info("Filtering requested for companies: %s", only_filters)

if __name__ == "__main__":
    logger.info(
        "Starting scraper (debug=%s, run_once=%s, run_on_start=%s, only=%s)",
        debug,
        run_once,
        run_on_start,
        only_filters,
    )
    ensure_schema()

    if debug or run_once:
        scheduled_job()
    else:
        if run_on_start:
            scheduled_job()
        while True:
            schedule.run_pending()
            time.sleep(1)
