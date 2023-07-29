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

#scraper.debug_mode = True
store_router = APIRouter()

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