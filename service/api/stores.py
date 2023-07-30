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

from sqlalchemy import select, desc

#scraper.debug_mode = True
store_router = APIRouter()

def similar(a, b):
    return SequenceMatcher(None, a.lower(), b.lower()).real_quick_ratio()

@store_router.get("/stores", response_model=List[schemas.Store])
async def get_all_stores(sess: Session=Depends(get_db)):
    return sess.query(models.Store).all()

@store_router.get("/stores/{id}", response_model=schemas.Store)
async def get_store(id: int, sess: Session=Depends(get_db)):
    store = sess.query(models.Store).get(id)
    if store:
        return store
    else:
        raise HTTPException(404, detail=f"Store with id {id} not found")

@store_router.get("/stores/{id}/products", response_model=List[schemas.Product_Instance])
async def get_products_from_store(id: int, sess: Session=Depends(get_db)):
    product_instances = sess.query(models.Product_Instance).filter(store_id==id).all()
    if product_instances == []:
        raise HTTPException(404, detail=f"Product from store with id {id} not found")
    return product_instances

@store_router.get("/stores/{zipcode}", response_model=List[schemas.Store])
async def get_stores_by_zipcode(zipcode: str, sess: Session=Depends(get_db)):
    q = sess.query(models.Store)
    stores = q.filter(models.Store.zipcode == zipcode).all()
    if stores == []:
        raise HTTPException(404, detail=f"Stores with zipcode {zipcode} not found")
        # key = "nYA0zVQY9dkfDrn6x9TvUaamjelpmGyeed1lEpoBLzAYi3NseTZBu20n8mL6WKuc"
        # route = f"https://www.zipcodeapi.com/rest/{key}/radius.json/{zipcode}/5/miles?minimal"
        # r = requests.get(route)
        # if r.status_code == 200:
        #     zipcodes = r.json()['zip_codes']
        #     closest_stores = sess.query(models.Store).filter(models.Product.zipcode in zipcodes)
        # else:
        #     closest_stores = []
        #     for brand in ["Whole Foods","Trader Joes"]:
        #         closest_stores.append(sess.query(models.Store).filter(models.Product.company == brand).first())
        # return closest_stores
    else:
        return stores

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
    print("------\n",out[0],"\n------")
    return out

# now add search and filtering by tags
@store_router.post("/stores/full_products", response_model=Page[schemas.Product_Details] )
async def get_full_products(ids: List[int], tags: List[str] | None = [], search: str | None = "", sess: Session=Depends(get_db)):
    if search == "":
        return paginate(sess,
        select(models.Product,models.Product_Instance)
        .where(
            models.Product.id == models.Product_Instance.product_id, 
            models.Product_Instance.store_id.in_(ids),
            )
        )
    return paginate(sess,
        select(models.Product,models.Product_Instance)
        .where(
            models.Product.id == models.Product_Instance.product_id, 
            models.Product_Instance.store_id.in_(ids),
            models.Product.name.like(f"%{search}%")
        )
    )

add_pagination(store_router)