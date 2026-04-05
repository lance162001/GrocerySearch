"""
Tests for points awarded when submitting judgements.

Run with:  cd service && source .venv/bin/activate && python -m pytest tests/test_points.py -v
"""

import os
import sys

# Must set DATABASE_URL BEFORE any model/engine imports.
os.environ["DATABASE_URL"] = "sqlite:///file:points_test?mode=memory&cache=shared&uri=true"

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from models.base import Base, engine
from models.bootstrap import ensure_runtime_schema
import models  # noqa: F401 — register all ORM classes

Base.metadata.create_all(engine)
ensure_runtime_schema()

from fastapi.testclient import TestClient  # noqa: E402
from main import app  # noqa: E402
from api import SessionLocal  # noqa: E402

client = TestClient(app)


def _seed_product() -> int:
    """Insert a minimal company + product. Returns the product id."""
    sess = SessionLocal()
    try:
        company = models.Company(slug="pts-co", scraper_key="pts", name="PtsCo")
        sess.add(company)
        sess.flush()

        product = models.Product(
            raw_name="Pts Milk", name="Pts Milk", brand="PtsBrand",
            company_id=company.id, picture_url="https://img.test/milk.png",
        )
        sess.add(product)
        sess.flush()

        product2 = models.Product(
            raw_name="Pts Eggs", name="Pts Eggs", brand="PtsBrand",
            company_id=company.id, picture_url="https://img.test/eggs.png",
        )
        sess.add(product2)
        sess.flush()

        sess.commit()
        return int(product.id), int(product2.id)
    finally:
        sess.close()


_product_id: int = 0
_product_id2: int = 0


def setup_module(_module):
    global _product_id, _product_id2
    _product_id, _product_id2 = _seed_product()


def test_points_start_at_zero():
    resp = client.post("/users/create")
    user_id = resp.json()["id"]
    resp = client.get(f"/tracking/points?user_id={user_id}")
    assert resp.status_code == 200
    assert resp.json()["points"] == 0


def test_judgement_awards_staple_points():
    resp = client.post("/users/create")
    user_id = resp.json()["id"]
    # Submit a staple judgement (+3 points)
    client.post(
        "/products/judgement",
        json={
            "user_id": user_id,
            "product_id": _product_id,
            "judgement_type": "staple",
            "staple_name": "milk",
            "approved": True,
        },
    )
    resp = client.get(f"/tracking/points?user_id={user_id}")
    assert resp.json()["points"] == 3


def test_grouping_judgement_awards_five_points():
    resp = client.post("/users/create")
    user_id = resp.json()["id"]
    client.post(
        "/products/judgement",
        json={
            "user_id": user_id,
            "product_id": _product_id,
            "judgement_type": "grouping",
            "staple_name": None,
            "target_product_id": _product_id2,
            "approved": True,
        },
    )
    resp = client.get(f"/tracking/points?user_id={user_id}")
    assert resp.json()["points"] == 5
