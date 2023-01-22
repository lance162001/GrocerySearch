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



@product_router.get("/products/{keyword}", response_model=List[schemas.Product])
async def search_for_products(keyword: str, sess: Session=Depends(get_db)):
    return sess.query(models.Product).filter( keyword in models.Product.name ).all()