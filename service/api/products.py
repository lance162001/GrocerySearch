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

@product_router.get("/products/{id}", response_model=schemas.Product)
async def get_product(id: int, sess: Session=Depends(get_db)):
    p = sess.query(models.Product).get(id)
    if p:
        return p
    else:
        raise HTTPException(404, detail=f"Product with id {id} not found")

@product_router.get("/products/multiple", response_model=List[schemas.Product])
async def get_products_by_ids(ids: List[int], sess: Session=Depends(get_db)):
    p = []
    q = Session.query(models.Product)
    for id in ids:
        p.append(q.get(id))
    if len(p) != len(q):
        raise HTTPException(404, detail=f"Product with id {id} not found")
    return p

# @product_router.get("/products/tag/{id}", response_model=schemas.Tag)
# async def get_tag(id: int, sess: Session=Depends(get_db)):
#     t = sess.query(models.Tag).get(id)
#     if t:
#         return t
#     else:
#         raise HTTPException(404, detail=f"Tag with id {id} not found")

@product_router.get("/products/tag", response_model=schemas.Tag)
async def get_all_tags(sess: Session=Depends(get_db)):
    t = sess.query(models.Tag).all()
    return t


# @product_router.get("/products/{zip}/{keyword}", response_model=List[schemas.Product])
# async def search_for_products(keyword: str, sess: Session=Depends(get_db)):
#     return sess.query(models.Product).filter( keyword in models.Product.name ).all()


add_pagination(product_router)