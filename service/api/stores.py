from fastapi import APIRouter, BackgroundTasks

from typing import List

from fastapi import APIRouter, Depends
from fastapi.encoders import jsonable_encoder
from sqlalchemy.orm import Session

from . import get_db

import models
import schemas
import random
import datetime
import scraper
import requests
from fastapi.exceptions import HTTPException

scraper.debug_mode = True
store_router = APIRouter()

@store_router.get("/stores", response_model=List[schemas.Store])
async def get_all_stores(sess: Session=Depends(get_db)):
    return sess.query(models.Store).all()

@store_router.get("/store_by_id/{sid}", response_model=schemas.Store)
async def get_store(sid: int, sess: Session=Depends(get_db)):
    store = sess.query(models.Store).get(sid)
    if store:
        return store
    else:
        raise HTTPException(404, detail=f"Store with id {id} not found")

@store_router.get("/stores/{zipcode}", response_model=schemas.Store)
async def get_stores_by_zipcode(zipcode: str, background_tasks: BackgroundTasks, sess: Session=Depends(get_db)):
    key = "nYA0zVQY9dkfDrn6x9TvUaamjelpmGyeed1lEpoBLzAYi3NseTZBu20n8mL6WKuc"
    route = f"https://www.zipcodeapi.com/rest/{key}/radius.json/{zipcode}/5/miles?minimal"
    stores = sess.query(models.Store).filter(models.Product.zipcode == zipcode).all()
    if stores == None:
        r = requests.get(route)
        if r.status_code == 200:
            zipcodes = r.json()['zip_codes']
            closest_stores = sess.query(models.Store).filter(models.Product.zipcode in zipcodes)
            background_tasks.add_task(scraper.get_location,zipcode)
        else:
            closest_stores = []
            for brand in ["Whole Foods","Trader Joes"]:
                closest_stores.append(sess.query(models.Store).filter(models.Product.company == brand).first())
        return closest_stores
    else:
        return stores