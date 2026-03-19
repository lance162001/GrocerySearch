"""Scraper entry-point — orchestrates per-store scrapers and manages scheduling."""

from __future__ import annotations

import argparse
import logging
import threading
import time
from datetime import datetime

import schedule
from sqlalchemy import inspect, text
from sqlalchemy.orm import Session

import emailer
from models import Company, Store, Tag
from models.base import Base, engine
from models.stores import ScraperStatus
from scrapers import scrape_whole_foods, scrape_trader_joes, scrape_wegmans
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
        row.status = status
        row.updated_at = datetime.now()
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
    return {"products": [], "product_instances": [], "price_points": [], "stores": [], "companies": []}


_COMPANY_ALIASES: dict[str, int] = {
    "wf": 1, "wholefoods": 1, "whole_foods": 1,
    "tj": 2, "traderjoes": 2, "trader_joes": 2,
    "wg": 3, "wegmans": 3,
}


def _scrape_stores(stores: list, tags: dict[str, int], collector: dict,
                   only: set[int] | None = None) -> None:
    """Scrape all stores, running WF, TJ, and WG chains in parallel threads.

    If *only* is provided, skip companies not in the set.
    """
    wf_stores = [s for s in stores if s.company_id == 1] if (only is None or 1 in only) else []
    tj_stores = [s for s in stores if s.company_id == 2] if (only is None or 2 in only) else []
    wg_stores = [s for s in stores if s.company_id == 3] if (only is None or 3 in only) else []

    def _run_wf():
        sess = _new_session()
        try:
            for store in wf_stores:
                scrape_whole_foods(store.id, store.scraper_id, sess, tags, collector)
        finally:
            sess.close()

    def _run_tj():
        sess = _new_session()
        try:
            for store in tj_stores:
                scrape_trader_joes(store.id, store.scraper_id, sess, tags, collector)
        finally:
            sess.close()

    def _run_wg():
        sess = _new_session()
        try:
            for store in wg_stores:
                scrape_wegmans(store.id, store.scraper_id, sess, tags, collector)
        finally:
            sess.close()

    wf_thread = threading.Thread(target=_run_wf, name="wf-scraper")
    tj_thread = threading.Thread(target=_run_tj, name="tj-scraper")
    wg_thread = threading.Thread(target=_run_wg, name="wg-scraper")
    wf_thread.start()
    tj_thread.start()
    wg_thread.start()
    wf_thread.join()
    tj_thread.join()
    wg_thread.join()


def ensure_schema() -> None:
    """Create tables and run lightweight migrations."""
    Base.metadata.create_all(engine)
    inspector = inspect(engine)
    product_columns = {col["name"] for col in inspector.get_columns("products")}
    if "raw_name" not in product_columns:
        with engine.begin() as conn:
            conn.execute(text("ALTER TABLE products ADD COLUMN raw_name VARCHAR(300)"))

    # Widen varchar columns that were previously too narrow for real product data.
    # PostgreSQL enforces column widths; SQLite does not, so this only matters in prod.
    db_url = str(engine.url)
    if "postgresql" in db_url:
        col_type_map = {
            col["name"]: str(col["type"]) for col in inspector.get_columns("products")
        }
        with engine.begin() as conn:
            if "VARCHAR(100)" in col_type_map.get("name", "").upper() or \
               "character varying(100)" in col_type_map.get("name", "").lower():
                conn.execute(text("ALTER TABLE products ALTER COLUMN name TYPE VARCHAR(200)"))
                logger.info("Migrated products.name to VARCHAR(200)")
            if "VARCHAR(150)" in col_type_map.get("raw_name", "").upper() or \
               "character varying(150)" in col_type_map.get("raw_name", "").lower():
                conn.execute(text("ALTER TABLE products ALTER COLUMN raw_name TYPE VARCHAR(300)"))
                logger.info("Migrated products.raw_name to VARCHAR(300)")
            if "VARCHAR(255)" in col_type_map.get("picture_url", "").upper() or \
               "character varying(255)" in col_type_map.get("picture_url", "").lower():
                conn.execute(text("ALTER TABLE products ALTER COLUMN picture_url TYPE VARCHAR(500)"))
                logger.info("Migrated products.picture_url to VARCHAR(500)")


@schedule.repeat(schedule.every().day.at("10:30"))
def scheduled_job() -> None:
    collector = _new_collector()
    logger.info("Scraping started")
    start = datetime.now()
    _write_status("running", started_at=start)

    sess = _new_session()
    try:
        stores = sess.query(Store).all()
        if not stores:
            stores, tags = setup_seed_data(sess)
        else:
            tags = load_existing_tags(sess)

        collector["stores"] = stores
        collector["companies"] = sess.query(Company).all()

        _scrape_stores(stores, tags, collector, only=only_ids)

        # Assign variation groups based on brand + product-type suffix.
        variation_sess = _new_session()
        try:
            compute_variation_groups(variation_sess)
        finally:
            variation_sess.close()

        summary = (
            f"GS Scraper Daily Run\n"
            f"Started: {start:%A, %d %B %Y %I:%M%p}\n"
            f"Ended: {datetime.now():%A, %d %B %Y %I:%M%p}\n"
            f"Stores scraped: {len(stores)}\n"
            f"New products: {len(collector['products'])}\n"
            f"New instances: {len(collector['product_instances'])}\n"
            f"New price points: {len(collector['price_points'])}\n"
        )
        for p in collector["products"]:
            summary += f"\n  {p.name} | {p.brand} | company_id={p.company_id}"

        try:
            emailer.simple_send(summary)
            emailer.send(collector)
        except Exception as exc:
            if debug:
                logger.warning("Email skipped in debug mode: %s", exc)
            else:
                raise
    except Exception as exc:
        _write_status("error", started_at=start, error=str(exc)[:500])
        raise
    finally:
        sess.close()

    _write_status(
        "idle",
        started_at=start,
        last_finished=datetime.now(),
        stores_scraped=len(stores),
        new_products=len(collector["products"]),
        new_instances=len(collector["product_instances"]),
        new_price_points=len(collector["price_points"]),
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
            "Accepted names: wf/wholefoods/whole_foods, tj/traderjoes/trader_joes, wg/wegmans."
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

only_ids: set[int] | None = None
if args.only:
    only_ids = set()
    for name in args.only:
        key = name.lower().replace("-", "_")
        if key not in _COMPANY_ALIASES:
            raise SystemExit(f"Unknown company '{name}'. Choose from: {', '.join(sorted(_COMPANY_ALIASES))}")
        only_ids.add(_COMPANY_ALIASES[key])
    logger.info("Filtering to company ids: %s", only_ids)

if __name__ == "__main__":
    logger.info(
        "Starting scraper (debug=%s, run_once=%s, run_on_start=%s, only=%s)",
        debug,
        run_once,
        run_on_start,
        only_ids,
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
