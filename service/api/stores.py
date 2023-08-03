from fastapi import APIRouter, BackgroundTasks

from typing import List

from fastapi import APIRouter, Depends
from fastapi.encoders import jsonable_encoder
from sqlalchemy.orm import Session, load_only

from . import get_db

import models
import schemas
import random
import datetime
#import scraper
import requests
from fastapi.exceptions import HTTPException

from fastapi_pagination import Page, add_pagination#, paginate
from fastapi_pagination.ext.sqlalchemy import paginate


from difflib import SequenceMatcher
import Levenshtein

from sqlalchemy import select, desc, or_

#scraper.debug_mode = True
store_router = APIRouter()

def similar(a, b):
    return Levenshtein.ratio(a.lower(),b.lower())

@store_router.get("/stores", response_model=List[schemas.Store])
async def get_all_stores(sess: Session=Depends(get_db)):
    return sess.query(models.Store).all()

@store_router.get("/stores/{id}/products", response_model=List[schemas.Product_Instance])
async def get_products_from_store(id: int, sess: Session=Depends(get_db)):
    product_instances = sess.query(models.Product_Instance).filter(store_id==id).all()
    if product_instances == []:
        raise HTTPException(404, detail=f"Product from store with id {id} not found")
    return product_instances

@store_router.get("/stores/search", response_model=Page[schemas.Store])
async def store_search(search: str | None = "", sess: Session=Depends(get_db)):
    # def sim(a):
    #     return max(similar(a.address,search),similar(a.zipcode,search))
    # q = sess.query(models.Store)
    # if len(search) == 5 and search.isalnum:
    #     stores = q.filter(models.Store.zipcode == zipcode).all()
    # elif search == "":
    #     stores = q.all()
    # else:
    #     stores = q.all()
    #     stores.sort(key=sim,reverse=True)
    # return paginate(stores)
    if search == "":
        return paginate(sess, select(models.Store))
    else:
        return paginate(sess, select(models.Store)
            .where(
                or_(models.Store.address.like(f"%{search}%"),
                    models.Store.zipcode.like(f"%{search}%"),
                    models.Store.state.like(f"%{search}%"),
                    models.Store.town.like(f"%{search}%"),
                )
            )
        )
        

@store_router.get("/company/{id}", response_model=schemas.Company)
async def get_company(id: int, sess: Session=Depends(get_db)):
    company = sess.query(models.Company).get(id)
    if company:
        return company
    else:
        raise HTTPException(404, detail=f"Company with id {id} not found")

@store_router.get("/company", response_model=List[schemas.Company])
async def get_all_companies(sess: Session=Depends(get_db)):
    out = sess.query(models.Company).all()
    return out

@store_router.post("/stores/product_search", response_model=Page[schemas.Product_Details] )
async def full_product_search(ids: List[int], tags: List[int] | None = [], search: str | None = "", sess: Session=Depends(get_db)):
    s = select(models.Product, models.Product_Instance).where(
        models.Product.id == models.Product_Instance.product_id).where(
        models.Product_Instance.store_id.in_(ids) ).where(
        models.Product.name.like(f"%{search}%")
        )
    for i in tags:
        s = s.where(models.Product.tags.any(models.Tag_Instance.tag_id == i))

    return paginate(sess,s)
    # def sim(a):
    #     return similar(a.Product.name,search)
    # rows = sess.execute(s).all()
    # out = []
    # if tags != []:
    #     for r in rows:
    #         if tags in r.Product.tags:
    #             out.append(r)
    # else:
    # out = rows
    # if search != "":
    #     out.sort(key=sim,reverse=True)
    # return paginate(out)
    # if search == "":
    #     return paginate(sess,
    #     select(models.Product,models.Product_Instance)
    #     .where(
    #         models.Product.id == models.Product_Instance.product_id, 
    #         models.Product_Instance.store_id.in_(ids),
    #         )
    #     )


add_pagination(store_router)