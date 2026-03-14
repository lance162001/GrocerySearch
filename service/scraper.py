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
from scrapers import scrape_whole_foods, scrape_trader_joes, scrape_wegmans
from scrapers.utils import setup_seed_data, load_existing_tags

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(name)s] %(levelname)s: %(message)s")
logger = logging.getLogger(__name__)


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
            conn.execute(text("ALTER TABLE products ADD COLUMN raw_name VARCHAR(150)"))


@schedule.repeat(schedule.every().day.at("10:30"))
def scheduled_job() -> None:
    collector = _new_collector()
    logger.info("Scraping started")
    start = datetime.now()

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
    finally:
        sess.close()

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
        "--verbose", "-v", action="store_true",
        help="Enable verbose output, including SQLAlchemy SQL logs.",
    )
    return parser.parse_args()


args = _parse_args()
debug = args.debug

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
    logger.info("Starting scraper (debug=%s, only=%s)", debug, only_ids)
    ensure_schema()

    if debug:
        scheduled_job()
    else:
        while True:
            schedule.run_pending()
            time.sleep(1)
