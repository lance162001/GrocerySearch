from fastapi import APIRouter
from sqlalchemy.orm import sessionmaker

from models.base import Base, engine

router = APIRouter()

Base.metadata.create_all(engine)
SessionLocal = sessionmaker(bind=engine)


def get_db():
    """
    Get SQLAlchemy database session
    """
    database = SessionLocal()
    try:
        yield database
    finally:
        database.close()

@router.get("/")
async def root():
    return {"message": "Welcome to this grocery thing"}

from .products import product_router
from .stores import store_router
from .users import user_router

router.include_router(product_router)
router.include_router(store_router)
router.include_router(user_router)