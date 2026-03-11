from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from fastapi_pagination import Page, add_pagination
from fastapi_pagination.ext.sqlalchemy import paginate
from sqlalchemy import select

from . import get_db
import models
import schemas

product_router = APIRouter()


@product_router.get("/products", response_model=Page[schemas.Product])
async def get_all_products(sess: Session = Depends(get_db)):
    return paginate(sess, select(models.Product))


@product_router.get("/products/instance", response_model=Page[schemas.Product_Instance])
async def get_all_product_instances(sess: Session = Depends(get_db)):
    return paginate(sess, select(models.Product_Instance))


@product_router.get("/products/multiple", response_model=List[schemas.Product])
async def get_products_by_ids(ids: List[int], sess: Session = Depends(get_db)):
    products = []
    for product_id in ids:
        product = sess.get(models.Product, product_id)
        if product is None:
            raise HTTPException(404, detail=f"Product with id {product_id} not found")
        products.append(product)
    return products


@product_router.get("/products/tags", response_model=List[schemas.Tag])
async def get_all_tags(sess: Session = Depends(get_db)):
    return sess.query(models.Tag).all()


add_pagination(product_router)