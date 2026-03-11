"""Scraper entry-point — orchestrates per-store scrapers and manages scheduling."""

from __future__ import annotations

import logging
import sys
import threading
import time
from datetime import datetime

import schedule
from sqlalchemy import inspect, text
from sqlalchemy.orm import Session

import emailer
from models import Company, Store, Tag
from models.base import Base, engine
from scrapers import scrape_whole_foods, scrape_trader_joes
from scrapers.utils import setup_seed_data, load_existing_tags

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(name)s] %(levelname)s: %(message)s")
logger = logging.getLogger(__name__)


def _new_collector() -> dict:
    return {"products": [], "product_instances": [], "price_points": [], "stores": [], "companies": []}


def _scrape_stores(stores: list, tags: dict[str, int], collector: dict) -> None:
    """Scrape all stores, running WF and TJ chains in parallel threads."""
    wf_stores = [s for s in stores if s.company_id == 1]
    tj_stores = [s for s in stores if s.company_id == 2]

    def _run_wf():
        sess = Session(engine)
        try:
            for store in wf_stores:
                scrape_whole_foods(store.id, store.scraper_id, sess, tags, collector)
        finally:
            sess.close()

    def _run_tj():
        sess = Session(engine)
        try:
            for store in tj_stores:
                scrape_trader_joes(store.id, store.scraper_id, sess, tags, collector)
        finally:
            sess.close()

    wf_thread = threading.Thread(target=_run_wf, name="wf-scraper")
    tj_thread = threading.Thread(target=_run_tj, name="tj-scraper")
    wf_thread.start()
    tj_thread.start()
    wf_thread.join()
    tj_thread.join()


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

    sess = Session(engine)
    try:
        stores = sess.query(Store).all()
        if not stores:
            stores, tags = setup_seed_data(sess)
        else:
            tags = load_existing_tags(sess)

        collector["stores"] = stores
        collector["companies"] = sess.query(Company).all()

        _scrape_stores(stores, tags, collector)

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

debug = len(sys.argv) > 1 and sys.argv[1] in ("debug", "d")

if __name__ == "__main__":
    logger.info("Starting scraper (debug=%s)", debug)
    ensure_schema()

    if debug:
        scheduled_job()
    else:
        while True:
            schedule.run_pending()
            time.sleep(1)
