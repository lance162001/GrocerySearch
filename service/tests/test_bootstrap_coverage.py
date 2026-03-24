"""
Ensure every non-trivial column added to a SQLAlchemy model is also covered by
an _ensure_column() call in bootstrap.py.

This catches the recurring bug where a developer adds a column to models/users.py
(or any other model) but forgets to add the corresponding _ensure_column migration,
causing 500 errors in production because the existing Postgres DB lacks the column.

Run with:  pytest service/tests/test_bootstrap_coverage.py
"""
import os
import sys

# Make sure `service/` is on the path so model imports work.
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

# Point SQLAlchemy at an in-memory SQLite DB so no real Postgres is needed.
os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

from sqlalchemy import inspect as sa_inspect

import models  # noqa: F401 – registers all ORM classes via __init__.py
from models.base import Base, engine
from models.bootstrap import _ENSURED_COLUMNS, ensure_runtime_schema

# Columns that are created by Base.metadata.create_all() on a fresh DB and
# therefore do NOT need an _ensure_column entry (they exist from day one).
# Primary keys and relationship-only columns are always covered; list any
# additional table-level columns here if they were present since schema v1.
_BOOTSTRAP_EXEMPT: set[tuple[str, str]] = {
    # primary keys / surrogate ids
    ("users", "id"),
    ("saved_stores", "store_id"),
    ("saved_stores", "user_id"),
    ("saved_stores", "member"),
    ("saved_products", "product_id"),
    ("saved_products", "bundle_id"),
    ("product_bundles", "id"),
    ("product_bundles", "user_id"),
    ("product_bundles", "name"),
    ("product_bundles", "created_at"),
    ("store_visits", "id"),
    ("store_visits", "product_bundle_id"),
    ("store_visits", "user_id"),
    ("store_visits", "created_at"),
    # original columns present since schema v1
    ("users", "recent_zipcode"),
    ("products", "id"),
    ("products", "name"),
    ("products", "company_id"),
    ("products", "picture_url"),
    ("products", "unit_price"),
    ("products", "unit_type"),
    ("products", "size"),
    ("products", "size_unit"),
    ("product_instances", "id"),
    ("product_instances", "store_id"),
    ("product_instances", "product_id"),
    ("product_instances", "scraper_id"),
    ("price_points", "id"),
    ("price_points", "instance_id"),
    ("price_points", "price"),
    ("price_points", "sale_price"),
    ("price_points", "created_at"),
    ("stores", "id"),
    ("stores", "name"),
    ("stores", "company_id"),
    ("stores", "scraper_id"),
    ("stores", "zipcode"),
    ("stores", "address"),
    ("companies", "id"),
    ("companies", "name"),
    ("tags", "id"),
    ("tags", "name"),
    ("tag_instances", "id"),
    ("tag_instances", "product_id"),
    ("tag_instances", "tag_id"),
    ("label_judgements", "id"),
    ("label_judgements", "product_id"),
    ("label_judgements", "judgement_type"),
    ("label_judgements", "created_at"),
    ("scraper_status", "id"),
    ("scraper_status", "started_at"),
    ("scraper_status", "finished_at"),
    ("scraper_status", "status"),
    ("scraper_status", "products_scraped"),
    ("staple_store_cache", "id"),
    ("staple_store_cache", "store_id"),
    ("staple_store_cache", "product_id"),
    ("staple_store_cache", "confidence"),
    ("staple_store_cache", "created_at"),
    ("staple_store_cache", "staple_name"),
    # additional v1 columns (present in all production DBs before _ensure_column was introduced)
    ("companies", "logo_url"),
    ("label_judgements", "approved"),
    ("label_judgements", "target_product_id"),
    ("label_judgements", "user_id"),
    ("price_points", "base_price"),
    ("price_points", "member_price"),
    ("price_points", "size"),
    ("products", "brand"),
    ("scraper_status", "error"),
    ("scraper_status", "last_finished"),
    ("scraper_status", "new_instances"),
    ("scraper_status", "new_price_points"),
    ("scraper_status", "new_products"),
    ("scraper_status", "stores_scraped"),
    ("scraper_status", "updated_at"),
    ("staple_store_cache", "computed_at"),
    ("staple_store_cache", "ranked_json"),
    ("store_suggestions", "id"),
    ("store_suggestions", "address"),
    ("store_suggestions", "company_id"),
    ("store_suggestions", "created_at"),
    ("store_suggestions", "state"),
    ("store_suggestions", "status"),
    ("store_suggestions", "town"),
    ("store_suggestions", "zipcode"),
    ("stores", "state"),
    ("stores", "town"),
}


def test_all_model_columns_are_migrated() -> None:
    """Every column that isn't schema-v1 must have an _ensure_column entry."""
    # Create a fresh in-memory schema (simulates a brand-new DB on first deploy).
    Base.metadata.create_all(engine)

    # Run bootstrap so _ENSURED_COLUMNS is populated.
    ensure_runtime_schema()

    inspector = sa_inspect(engine)
    missing: list[str] = []

    for table_name in inspector.get_table_names():
        for col in inspector.get_columns(table_name):
            pair = (table_name, col["name"])
            if pair in _BOOTSTRAP_EXEMPT:
                continue
            if pair not in _ENSURED_COLUMNS:
                missing.append(f"{table_name}.{col['name']}")

    assert not missing, (
        "The following model columns have no _ensure_column() migration in "
        "bootstrap.py. Add them or add to _BOOTSTRAP_EXEMPT if they existed "
        "since schema v1:\n  " + "\n  ".join(sorted(missing))
    )
