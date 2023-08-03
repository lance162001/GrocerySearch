from fastapi import APIRouter

from typing import List

from fastapi import APIRouter, Depends
from fastapi.encoders import jsonable_encoder
from sqlalchemy.orm import Session
from fastapi_pagination import Page, add_pagination
from fastapi_pagination.ext.sqlalchemy import paginate
from . import get_db

from sqlalchemy import select

import models
import schemas
import random
import datetime

product_router = APIRouter()

@product_router.get("/products", response_model=Page[schemas.Product])
async def get_all_products(sess: Session=Depends(get_db)):
    return paginate(sess, select(models.Product))

@product_router.get("/products/instance", response_model=Page[schemas.Product_Instance])
async def get_all_product_instances(sess: Session=Depends(get_db)):
    return paginate(sess, select(models.Product_Instance))

@product_router.get("/products/multiple", response_model=List[schemas.Product])
async def get_products_by_ids(ids: List[int], sess: Session=Depends(get_db)):
    p = []
    q = sess.query(models.Product)
    for id in ids:
        p.append(q.get(id))
    if len(p) != len(q):
        raise HTTPException(404, detail=f"Product with id {id} not found")
    return p
    
@product_router.get("/products/tags", response_model=List[schemas.Tag])
async def get_all_tags(sess: Session=Depends(get_db)):
    t = sess.query(models.Tag).all()
    return t

add_pagination(product_router)