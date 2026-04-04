"""
Verify that tracked_items and user_points tables exist with correct columns
after bootstrap runs.

Run with:  pytest tests/test_tracking_schema.py -v
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

from sqlalchemy import inspect as sa_inspect

import models  # noqa: F401
from models.base import Base, engine
from models.bootstrap import ensure_runtime_schema


def _col_names(inspector, table: str) -> set[str]:
    return {col["name"] for col in inspector.get_columns(table)}


def setup_module(_module):
    Base.metadata.create_all(engine)
    ensure_runtime_schema()


def test_tracked_items_table_exists():
    inspector = sa_inspect(engine)
    assert "tracked_items" in inspector.get_table_names()


def test_tracked_items_columns():
    inspector = sa_inspect(engine)
    cols = _col_names(inspector, "tracked_items")
    assert {"id", "user_id", "product_id", "created_at"} <= cols


def test_user_points_table_exists():
    inspector = sa_inspect(engine)
    assert "user_points" in inspector.get_table_names()


def test_user_points_columns():
    inspector = sa_inspect(engine)
    cols = _col_names(inspector, "user_points")
    assert {"id", "user_id", "points", "updated_at"} <= cols


def test_tracked_items_user_id_index():
    inspector = sa_inspect(engine)
    indexes = inspector.get_indexes("tracked_items")
    index_names = {idx["name"] for idx in indexes}
    assert "ix_tracked_items_user_id" in index_names


def test_tracked_items_user_product_unique_index():
    inspector = sa_inspect(engine)
    indexes = inspector.get_indexes("tracked_items")
    for idx in indexes:
        if idx["name"] == "ix_tracked_items_user_product":
            assert idx["unique"]
            assert set(idx["column_names"]) == {"user_id", "product_id"}
            return
    assert False, "ix_tracked_items_user_product index not found"
