from fastapi import APIRouter

from typing import List

from fastapi import APIRouter, Depends
from fastapi.encoders import jsonable_encoder
from sqlalchemy.orm import Session

from . import get_db

import models
import schemas
import random
import datetime

product_router = APIRouter()

@product_router.get("/products", response_model=List[schemas.Product])
async def get_all_products(sess: Session=Depends(get_db)):
    return sess.query(models.Product).all()

@product_router.get("/products/store/{sid}")
async def get_products_from_store(sid: int, sess: Session=Depends(get_db)):
    return sess.query(models.Product).filter(models.Product.store == sid).all()
