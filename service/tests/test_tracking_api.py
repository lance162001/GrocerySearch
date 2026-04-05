"""
Tests for the /tracking/* endpoints.

Run with:  cd service && source .venv/bin/activate && python -m pytest tests/test_tracking_api.py -v
"""

import os
import sys

# Must set DATABASE_URL BEFORE any model/engine imports.
# Use a shared-cache named in-memory DB so all connections share the same tables.
os.environ["DATABASE_URL"] = "sqlite:///file:tracking_test?mode=memory&cache=shared&uri=true"

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from datetime import datetime

from sqlalchemy.orm import Session

# Now import models/base — engine will use our in-memory DB
from models.base import Base, engine
from models.bootstrap import ensure_runtime_schema
import models  # noqa: F401 — register all ORM classes

# Create tables on in-memory DB
Base.metadata.create_all(engine)
ensure_runtime_schema()

# Now import the app (which uses the same engine via models.base)
from fastapi.testclient import TestClient  # noqa: E402
from main import app  # noqa: E402
from api import SessionLocal  # noqa: E402

client = TestClient(app)


def _seed_product() -> int:
    """Insert a company, store, product, product_instance, and price points.
    Returns the product id.
    """
    sess = SessionLocal()
    try:
        company = models.Company(slug="test-co", scraper_key="test", name="TestCo")
        sess.add(company)
        sess.flush()

        store = models.Store(
            address="1 Main St", town="TestTown", state="TS", zipcode="00000",
            company_id=company.id, scraper_id=1,
        )
        sess.add(store)
        sess.flush()

        product = models.Product(
            raw_name="Test Oats", name="Test Oats", brand="BrandX",
            company_id=company.id, picture_url="https://img.test/oats.png",
        )
        sess.add(product)
        sess.flush()

        instance = models.Product_Instance(store_id=store.id, product_id=product.id)
        sess.add(instance)
        sess.flush()

        # Two price points so we can test price change detection
        pp1 = models.PricePoint(
            instance_id=instance.id, base_price="$3.99",
            created_at=datetime(2026, 3, 1),
            collected_on=datetime(2026, 3, 1).date(),
        )
        pp2 = models.PricePoint(
            instance_id=instance.id, base_price="$4.49",
            created_at=datetime(2026, 3, 8),
            collected_on=datetime(2026, 3, 8).date(),
        )
        sess.add_all([pp1, pp2])
        sess.commit()
        return int(product.id)
    finally:
        sess.close()


def _create_user() -> int:
    resp = client.post("/users/create")
    assert resp.status_code == 200
    return resp.json()["id"]


# ---- Fixtures seeded once per module ----

_user_id: int = 0
_product_id: int = 0


def setup_module(_module):
    global _user_id, _product_id
    _user_id = _create_user()
    _product_id = _seed_product()


# ---- Tests ----


def test_track_item():
    resp = client.post("/tracking/track", json={
        "user_id": _user_id,
        "product_id": _product_id,
    })
    assert resp.status_code == 200
    data = resp.json()
    assert data["product_id"] == _product_id
    assert data["user_id"] == _user_id
    assert data["product_name"] == "Test Oats"
    assert data["brand"] == "BrandX"
    # Should have detected a price
    assert data["current_price"] is not None


def test_track_duplicate_is_idempotent():
    # Track same item again — should succeed, not error
    resp = client.post("/tracking/track", json={
        "user_id": _user_id,
        "product_id": _product_id,
    })
    assert resp.status_code == 200
    data = resp.json()
    assert data["product_id"] == _product_id


def test_list_tracked_items():
    resp = client.get(f"/tracking/tracked?user_id={_user_id}")
    assert resp.status_code == 200
    items = resp.json()
    assert isinstance(items, list)
    assert any(item["product_id"] == _product_id for item in items)


def test_tracked_item_detail():
    resp = client.get(f"/tracking/tracked/{_product_id}?user_id={_user_id}")
    assert resp.status_code == 200
    data = resp.json()
    assert data["product_id"] == _product_id
    assert "all_store_prices" in data
    assert "price_history" in data
    assert len(data["price_history"]) >= 2  # we seeded two price points


def test_untrack_item():
    resp = client.delete(f"/tracking/track/{_product_id}?user_id={_user_id}")
    assert resp.status_code == 200

    # Verify removed
    resp = client.get(f"/tracking/tracked?user_id={_user_id}")
    assert resp.status_code == 200
    items = resp.json()
    assert not any(item["product_id"] == _product_id for item in items)


def test_untrack_nonexistent_returns_404():
    resp = client.delete(f"/tracking/track/999999?user_id={_user_id}")
    assert resp.status_code == 404


def test_track_nonexistent_product_returns_404():
    resp = client.post("/tracking/track", json={
        "user_id": _user_id,
        "product_id": 999999,
    })
    assert resp.status_code == 404


def test_points_endpoint():
    resp = client.get(f"/tracking/points?user_id={_user_id}")
    assert resp.status_code == 200
    data = resp.json()
    assert data["user_id"] == _user_id
    assert "points" in data
    assert "labels_submitted" in data
    assert "accuracy" in data
