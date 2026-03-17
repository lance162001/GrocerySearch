from fastapi import APIRouter
from sqlalchemy import text
from sqlalchemy.orm import sessionmaker

from models.base import Base, engine

Base.metadata.create_all(engine)
SessionLocal = sessionmaker(bind=engine)

# Ad-hoc migration: add firebase_uid to users if it doesn't exist yet.
with engine.connect() as _conn:
    try:
        _conn.execute(text("ALTER TABLE users ADD COLUMN firebase_uid VARCHAR(128)"))
        _conn.commit()
    except Exception:
        pass  # column already exists

# Ad-hoc migration: add staple_name to label_judgements if it doesn't exist yet.
with engine.connect() as _conn:
    try:
        _conn.execute(text("ALTER TABLE label_judgements ADD COLUMN staple_name VARCHAR(50)"))
        _conn.commit()
    except Exception:
        pass  # column already exists

# Ad-hoc migration: add variation_group to products if it doesn't exist yet.
with engine.connect() as _conn:
    try:
        _conn.execute(text("ALTER TABLE products ADD COLUMN variation_group VARCHAR(200)"))
        _conn.commit()
    except Exception:
        pass  # column already exists

try:
    with engine.connect() as _conn:
        _conn.execute(text("CREATE INDEX IF NOT EXISTS ix_products_variation_group ON products (variation_group)"))
        _conn.commit()
except Exception:
    pass

# Ad-hoc migration: add flavour to label_judgements if it doesn't exist yet.
with engine.connect() as _conn:
    try:
        _conn.execute(text("ALTER TABLE label_judgements ADD COLUMN flavour VARCHAR(50)"))
        _conn.commit()
    except Exception:
        pass  # column already exists

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

router.include_router(product_router)
router.include_router(store_router)
router.include_router(user_router)