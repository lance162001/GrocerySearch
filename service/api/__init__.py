from fastapi import APIRouter
from sqlalchemy import text
from sqlalchemy.orm import sessionmaker

from models.base import Base, engine

Base.metadata.create_all(engine)
SessionLocal = sessionmaker(bind=engine)

# Ad-hoc migrations: add columns if they don't exist yet.
# PostgreSQL 9.6+ supports ADD COLUMN IF NOT EXISTS; SQLite (< 3.37) does not,
# so we try the IF NOT EXISTS form first and fall back to a bare ALTER TABLE
# (whose failure when the column already exists we then swallow).
_migrations = [
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS firebase_uid VARCHAR(128)",
    "ALTER TABLE label_judgements ADD COLUMN IF NOT EXISTS staple_name VARCHAR(50)",
    "ALTER TABLE products ADD COLUMN IF NOT EXISTS variation_group VARCHAR(200)",
    "ALTER TABLE label_judgements ADD COLUMN IF NOT EXISTS flavour VARCHAR(50)",
]
for _stmt in _migrations:
    with engine.connect() as _conn:
        try:
            _conn.execute(text(_stmt))
            _conn.commit()
        except Exception:
            # SQLite < 3.37 doesn't support IF NOT EXISTS; retry without it.
            _bare = _stmt.replace(" IF NOT EXISTS", "")
            with engine.connect() as _conn2:
                try:
                    _conn2.execute(text(_bare))
                    _conn2.commit()
                except Exception:
                    pass  # column already exists

_perf_indexes = [
    # Needed for the variation-group lookup and staple-card deduplication.
    "CREATE INDEX IF NOT EXISTS ix_products_variation_group ON products (variation_group)",
    # Critical for the staples bulk query and every product name search.
    "CREATE INDEX IF NOT EXISTS ix_products_name ON products (name)",
    # Critical for store-scoped product lookups (staples, search, checkout).
    "CREATE INDEX IF NOT EXISTS ix_product_instances_store_id ON product_instances (store_id)",
    # Needed for the product → instance join in search queries.
    "CREATE INDEX IF NOT EXISTS ix_product_instances_product_id ON product_instances (product_id)",
    # Needed for _load_staple_labels and the heuristics endpoint.
    "CREATE INDEX IF NOT EXISTS ix_lj_type_staple ON label_judgements (judgement_type, staple_name)",
    # Speeds up per-store cache lookups by store_id.
    "CREATE INDEX IF NOT EXISTS ix_staple_store_cache_store ON staple_store_cache (store_id)",
]
for _idx_ddl in _perf_indexes:
    try:
        with engine.connect() as _conn:
            _conn.execute(text(_idx_ddl))
            _conn.commit()
    except Exception:
        pass

# Ensure store_suggestions table exists (create_all handles it, but be safe).
Base.metadata.create_all(engine)


def get_db():
    """Yield a SQLAlchemy session, ensuring it is closed after use."""
    database = SessionLocal()
    try:
        yield database
    finally:
        database.close()


router = APIRouter()


@router.get("/")
async def root():
    return {"message": "Welcome to GrocerySearch"}


# Sub-routers — imported after get_db is defined so they can reference it.
from .products import product_router  # noqa: E402
from .stores import store_router  # noqa: E402
from .users import user_router  # noqa: E402
from .admin import admin_router  # noqa: E402

router.include_router(product_router)
router.include_router(store_router)
router.include_router(user_router)
router.include_router(admin_router)