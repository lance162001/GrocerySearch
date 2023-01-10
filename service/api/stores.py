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

store_router = APIRouter()

@store_router.get("/stores", response_model=List[schemas.Store])
async def get_all_stores(sess: Session=Depends(get_db)):
    return sess.query(models.Store).all()

@store_router.get("/stores/{sid}", response_model=schemas.Store)
async def get_store(sid: int, sess: Session=Depends(get_db)):
    store = sess.query(models.Store).get(sid)
    if store:
        return store
    else:
        raise HTTPException(404, detail=f"Store with id {id} not found")
        


