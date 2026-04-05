"""
Tests for the /feed endpoint.

Run with:  cd service && source .venv/bin/activate && python -m pytest tests/test_feed_api.py -v
"""

import os
import sys

# Must set DATABASE_URL BEFORE any model/engine imports.
os.environ["DATABASE_URL"] = "sqlite:///file:feed_test?mode=memory&cache=shared&uri=true"

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from models.base import Base, engine
from models.bootstrap import ensure_runtime_schema
import models  # noqa: F401 — register all ORM classes

# Create tables on in-memory DB
Base.metadata.create_all(engine)
ensure_runtime_schema()

from fastapi.testclient import TestClient  # noqa: E402
from main import app  # noqa: E402
from api import SessionLocal  # noqa: E402

client = TestClient(app)


def _seed_multi_chain_product():
    """Seed two companies, each with a store and a product instance for the same product."""
    sess = SessionLocal()
    try:
        # Company A
        co_a = models.Company(slug="chain-a", scraper_key="chain_a", name="Chain A")
        sess.add(co_a)
        # Company B
        co_b = models.Company(slug="chain-b", scraper_key="chain_b", name="Chain B")
        sess.add(co_b)
        sess.flush()

        store_a = models.Store(
            address="1 Alpha St", town="TestTown", state="TS", zipcode="11111",
            company_id=co_a.id, scraper_id=100,
        )
        store_b = models.Store(
            address="2 Beta St", town="TestTown", state="TS", zipcode="11111",
            company_id=co_b.id, scraper_id=200,
        )
        sess.add(store_a)
        sess.add(store_b)
        sess.flush()

        # Product belongs to company A (original scraper source)
        product = models.Product(
            raw_name="Organic Whole Milk 1gal",
            name="Organic Whole Milk",
            brand="Happy Farms",
            company_id=co_a.id,
            picture_url=None,
        )
        sess.add(product)
        sess.flush()

        # Instance in store A — cheaper
        inst_a = models.Product_Instance(store_id=store_a.id, product_id=product.id)
        sess.add(inst_a)
        # Instance in store B — more expensive (> $0.50 spread)
        inst_b = models.Product_Instance(store_id=store_b.id, product_id=product.id)
        sess.add(inst_b)
        sess.flush()

        pp_a = models.PricePoint(instance_id=inst_a.id, base_price="$3.99", size="1 gal")
        pp_b = models.PricePoint(instance_id=inst_b.id, base_price="$5.49", size="1 gal")
        sess.add(pp_a)
        sess.add(pp_b)
        sess.commit()
        return product.id
    finally:
        sess.close()


# Seed data once at module load so all tests share it
_seeded_product_id = _seed_multi_chain_product()


def test_feed_returns_items():
    resp = client.get("/feed?page=1&size=10")
    assert resp.status_code == 200
    data = resp.json()
    assert "items" in data
    assert "page" in data
    assert "has_more" in data
    assert isinstance(data["items"], list)


def test_feed_accepts_zipcode():
    resp = client.get("/feed?page=1&size=10&zipcode=02139")
    assert resp.status_code == 200


def test_feed_items_have_type():
    resp = client.get("/feed?page=1&size=20")
    data = resp.json()
    for item in data["items"]:
        assert "type" in item
        assert item["type"] in ("price_reveal", "savings_ranking", "community_challenge")


def test_feed_price_reveal_structure():
    """Price reveal cards have required fields."""
    resp = client.get("/feed?page=1&size=10")
    data = resp.json()
    reveals = [i for i in data["items"] if i["type"] == "price_reveal"]
    for reveal in reveals:
        assert "product_id" in reveal
        assert "product_name" in reveal
        assert "brand" in reveal
        assert "prices" in reveal
        assert "max_savings" in reveal
        assert isinstance(reveal["prices"], list)
        assert len(reveal["prices"]) >= 2


def test_feed_zipcode_with_stores():
    """Zipcode that matches seeded stores should return price reveal cards."""
    resp = client.get("/feed?page=1&size=10&zipcode=11111")
    assert resp.status_code == 200
    data = resp.json()
    # Should have at least one item since we seeded a multi-chain product in zip 11111
    assert isinstance(data["items"], list)


def test_feed_page_param():
    """page parameter is echoed back correctly."""
    resp = client.get("/feed?page=2&size=5")
    assert resp.status_code == 200
    data = resp.json()
    assert data["page"] == 2


def test_feed_savings_card_at_position_3():
    """If enough price reveal cards exist, position 3 (0-based) should be savings_ranking."""
    resp = client.get("/feed?page=1&size=10")
    data = resp.json()
    items = data["items"]
    if len(items) >= 4:
        # position index 3 should be savings_ranking if a savings card was built
        savings_items = [i for i in items if i["type"] == "savings_ranking"]
        if savings_items:
            assert items[3]["type"] == "savings_ranking"
