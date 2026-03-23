from __future__ import annotations

import logging

from sqlalchemy import inspect, text

from .base import Base, engine

logger = logging.getLogger(__name__)


def _has_column(inspector, table_name: str, column_name: str) -> bool:
    return column_name in {col["name"] for col in inspector.get_columns(table_name)}


def _ensure_column(table_name: str, column_name: str, ddl: str) -> None:
    inspector = inspect(engine)
    if _has_column(inspector, table_name, column_name):
        return
    with engine.begin() as conn:
        conn.execute(text(f"ALTER TABLE {table_name} ADD COLUMN {ddl}"))
    logger.info("Migrated %s.%s", table_name, column_name)


def _run_ddl_statements(statements: list[str]) -> None:
    for statement in statements:
        try:
            with engine.begin() as conn:
                conn.execute(text(statement))
        except Exception:
            logger.warning("Failed DDL statement: %s", statement)


def _backfill_company_metadata() -> None:
    updates = [
        ("whole-foods", "whole_foods", "Whole Foods"),
        ("trader-joes", "trader_joes", "Trader Joes"),
        ("wegmans", "wegmans", "Wegmans"),
    ]
    with engine.begin() as conn:
        for slug, scraper_key, name in updates:
            conn.execute(
                text(
                    """
                    UPDATE companies
                    SET slug = COALESCE(NULLIF(slug, ''), :slug),
                        scraper_key = COALESCE(NULLIF(scraper_key, ''), :scraper_key),
                        is_active = COALESCE(is_active, TRUE)
                    WHERE lower(name) = lower(:name)
                    """
                ),
                {"slug": slug, "scraper_key": scraper_key, "name": name},
            )


def _backfill_product_raw_names() -> None:
    with engine.begin() as conn:
        conn.execute(
            text(
                """
                UPDATE products
                SET raw_name = name
                WHERE raw_name IS NULL OR trim(raw_name) = ''
                """
            )
        )


def _backfill_price_point_collection_dates() -> None:
    db_url = str(engine.url)
    if "postgresql" in db_url:
        statement = """
            UPDATE price_points
            SET collected_on = CAST(created_at AS DATE)
            WHERE collected_on IS NULL
        """
    else:
        statement = """
            UPDATE price_points
            SET collected_on = date(created_at)
            WHERE collected_on IS NULL
        """
    with engine.begin() as conn:
        conn.execute(text(statement))


def _dedupe_same_day_price_points() -> None:
    with engine.begin() as conn:
        conn.execute(
            text(
                """
                DELETE FROM price_points
                WHERE id IN (
                    SELECT pp.id
                    FROM price_points pp
                    JOIN (
                        SELECT instance_id, collected_on, MAX(id) AS keep_id
                        FROM price_points
                        GROUP BY instance_id, collected_on
                        HAVING COUNT(*) > 1
                    ) dup
                      ON dup.instance_id = pp.instance_id
                     AND dup.collected_on = pp.collected_on
                    WHERE pp.id != dup.keep_id
                )
                """
            )
        )


def _migrate_product_varchars() -> None:
    inspector = inspect(engine)
    db_url = str(engine.url)
    if "postgresql" not in db_url:
        return

    col_type_map = {col["name"]: str(col["type"]) for col in inspector.get_columns("products")}
    statements: list[str] = []
    if "VARCHAR(100)" in col_type_map.get("name", "").upper() or "character varying(100)" in col_type_map.get("name", "").lower():
        statements.append("ALTER TABLE products ALTER COLUMN name TYPE VARCHAR(200)")
    if "VARCHAR(150)" in col_type_map.get("raw_name", "").upper() or "character varying(150)" in col_type_map.get("raw_name", "").lower():
        statements.append("ALTER TABLE products ALTER COLUMN raw_name TYPE VARCHAR(300)")
    if "VARCHAR(255)" in col_type_map.get("picture_url", "").upper() or "character varying(255)" in col_type_map.get("picture_url", "").lower():
        statements.append("ALTER TABLE products ALTER COLUMN picture_url TYPE VARCHAR(500)")
    _run_ddl_statements(statements)


def ensure_runtime_schema() -> None:
    """Create tables, backfill new columns, and add indexes for larger scrape history."""
    Base.metadata.create_all(engine)

    _ensure_column("users", "firebase_uid", "firebase_uid VARCHAR(128)")
    _ensure_column("users", "email", "email VARCHAR(255)")
    _ensure_column("users", "newsletter_opt_in", "newsletter_opt_in BOOLEAN DEFAULT TRUE")
    _ensure_column("users", "newsletter_unsubscribed_at", "newsletter_unsubscribed_at TIMESTAMP")
    _ensure_column("users", "unsubscribe_token", "unsubscribe_token VARCHAR(64)")
    _ensure_column("product_bundles", "share_token", "share_token VARCHAR(64)")
    _ensure_column("label_judgements", "staple_name", "staple_name VARCHAR(50)")
    _ensure_column("products", "variation_group", "variation_group VARCHAR(200)")
    _ensure_column("label_judgements", "flavour", "flavour VARCHAR(50)")
    _ensure_column("products", "raw_name", "raw_name VARCHAR(300)")
    _ensure_column("companies", "slug", "slug VARCHAR(50)")
    _ensure_column("companies", "scraper_key", "scraper_key VARCHAR(50)")
    _ensure_column("companies", "is_active", "is_active BOOLEAN DEFAULT TRUE")
    _ensure_column("stores", "is_active", "is_active BOOLEAN DEFAULT TRUE")
    _ensure_column("scraper_status", "companies_scraped", "companies_scraped INTEGER")
    _ensure_column("scraper_status", "updated_price_points", "updated_price_points INTEGER")
    _ensure_column("price_points", "collected_on", "collected_on DATE")

    _backfill_company_metadata()
    _backfill_product_raw_names()
    _backfill_price_point_collection_dates()
    _dedupe_same_day_price_points()
    _migrate_product_varchars()

    perf_indexes = [
        "CREATE INDEX IF NOT EXISTS ix_products_variation_group ON products (variation_group)",
        "CREATE INDEX IF NOT EXISTS ix_products_name ON products (name)",
        "CREATE INDEX IF NOT EXISTS ix_products_company_name ON products (company_id, name)",
        "CREATE INDEX IF NOT EXISTS ix_products_company_raw_name ON products (company_id, raw_name)",
        "CREATE INDEX IF NOT EXISTS ix_product_instances_store_id ON product_instances (store_id)",
        "CREATE INDEX IF NOT EXISTS ix_product_instances_product_id ON product_instances (product_id)",
        "CREATE INDEX IF NOT EXISTS ix_price_points_instance_created_at ON price_points (instance_id, created_at)",
        "CREATE INDEX IF NOT EXISTS ix_price_points_instance_collected_on ON price_points (instance_id, collected_on)",
        "CREATE INDEX IF NOT EXISTS ix_lj_type_staple ON label_judgements (judgement_type, staple_name)",
        "CREATE INDEX IF NOT EXISTS ix_staple_store_cache_store ON staple_store_cache (store_id)",
        "CREATE UNIQUE INDEX IF NOT EXISTS uq_stores_company_scraper_idx ON stores (company_id, scraper_id)",
        "CREATE UNIQUE INDEX IF NOT EXISTS uq_product_instances_store_product_idx ON product_instances (store_id, product_id)",
        "CREATE UNIQUE INDEX IF NOT EXISTS uq_price_points_instance_collected_on_idx ON price_points (instance_id, collected_on)",
        "CREATE UNIQUE INDEX IF NOT EXISTS uq_tag_instances_product_tag_idx ON tag_instances (product_id, tag_id)",
        "CREATE UNIQUE INDEX IF NOT EXISTS uq_companies_slug_idx ON companies (slug)",
        "CREATE UNIQUE INDEX IF NOT EXISTS uq_tags_name_idx ON tags (name)",
        "CREATE UNIQUE INDEX IF NOT EXISTS uq_products_company_raw_name_idx ON products (company_id, raw_name) WHERE raw_name IS NOT NULL AND raw_name <> ''",
    ]
    _run_ddl_statements(perf_indexes)
