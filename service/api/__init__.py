from fastapi import APIRouter
from sqlalchemy.orm import sessionmaker

from models.base import engine
from models.bootstrap import ensure_runtime_schema

ensure_runtime_schema()
SessionLocal = sessionmaker(bind=engine)


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
from .game import game_router  # noqa: E402

router.include_router(product_router)
router.include_router(store_router)
router.include_router(user_router)
router.include_router(admin_router)
router.include_router(game_router)