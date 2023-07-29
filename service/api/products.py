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

@product_router.get("/products/instance", response_model=List[schemas.Product_Instance])
async def get_all_product_instances(sess: Session=Depends(get_db)):
    return sess.query(models.Product_Instance).all()

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

# @product_router.post("/products", status_code=201)
# async def post_product(item: schemas.Product, Session = Depends(get_db)):
#     SQLitem = models.Product(
#         brand = item.brand,
#         name = item.name,
#         company_id = item.company_id,
#         picture_url = item.picture_url,
#         tags = item.tags
#     )
#     Session.add(SQLitem)
#     Session.commit()
#     Session.refresh(SQLitem)
#     return SQLitem

# @product_router.put("/products/{id}", status_code=200)
# async def update_product(id: int, item: schemas.Product, Session=Depends(get_db)):
#     p = sess.query(models.Product).get(id)
#     if p == None:
#         raise HTTPException(404, detail=f"Product with id {id} not found")
#     Session.delete(p)
#     newProduct = models.Product(
#         brand = item.brand,
#         name = item.name,
#         company_id = item.company_id,
#         picture_url = item.picture_url,
#         tags = item.tags
#     )
#     Session.add(newProduct)
#     Session.commit()
#     Session.refresh(newProduct)
#     return newProduct


# @product_router.post("/products/instance", status_code=201)
# async def post_product_instance(item: schemas.Product_Instance, Session = Depends(get_db)):
#     SQLitem = models.Product_Instance(
#         store_id = item.store_id,
#         product_id = item.product_id,
#         price_history = item.price_history
#     )
#     Session.add(SQLitem)
#     Session.commit()
#     Session.refresh(SQLitem)
#     return SQLitem

# @product_router.put("/products/instance/{id}", status_code=200)
# async def update_product_instance(id: int, item: schemas.Product_Instance, Session = Depends(get_db)):
#     p_instance = sess.query(models.Product_Instance).get(id)
#     if p_instance == None:
#         raise HTTPException(404, detail=f"Product Instance with id {id} not found")
#     Session.delete(p_instance)
#     newP_Instance = models.Product_Instance(
#         store_id = item.store_id,
#         product_id = item.product_id,
#         price_history = item.price_history
#     )
#     Session.add(newP_Instance)
#     Session.commit()
#     Session.refresh(newP_Instance)
#     return newP_Instance

# @product_router.post("/products/tag", status_code=201)
# async def post_tag(item: schemas.Tag, Session = Depends(get_db)):
#     SQLitem = models.Tag(
#         name = item.name
#     )
#     Session.add(SQLitem)
#     Session.commit()
#     Session.refresh(SQLitem)
#     return SQLitem

@product_router.get("/products/tag/{id}", response_model=schemas.Tag)
async def get_tag(id: int, sess: Session=Depends(get_db)):
    t = sess.query(models.Tag).get(id)
    if t:
        return t
    else:
        raise HTTPException(404, detail=f"Tag with id {id} not found")

@product_router.get("/products/tag", response_model=schemas.Tag)
async def get_all_tags(id: int, sess: Session=Depends(get_db)):
    t = sess.query(models.Tag).all()
    return t

# @product_router.put("products/tag/{id}", status_code=200)
# async def update_tag(id: int, item: schemas.Tag, Session = Depends(get_db)):
#     t = sess.query(models.Tag).get(id)
#     if t == None:
#         raise HTTPException(404, detail=f"Tag with id {id} not found")
#     Session.delete(t)
#     newT = models.Tag(
#         name = item.name
#     )
#     Session.add(newT)
#     Session.commit()
#     Session.refresh(newT)
#     return newT

# @product_router.post("/products/tag/instance")
# async def post_tag_instance(item: schemas.Tag_Instance, Session = Depends(get_db)):
#     SQLitem = models.Tag_Instance(
#         product_id = item.product_id,
#         tag_id = item.tag_id
#     )
#     Session.add(SQLitem)
#     Session.commit()
#     Session.refresh(SQLitem)
#     return SQLitem

# @product_router.delete("/products/tag/instance/{id}", status_code=200)
# async def delete_tag_instance(pid: int, sid: int, Session = Depends(get_db)):
#     t_instance = sess.query(models.Tag_Instance).filter(
#         Tag_Instance.product_id==pid and Tag_Instance.store_id==sid).first()
#     if t_instance == None:
#         raise HTTPException(404, detail=f"Tag Instance with pid / sid {pid} / {sid} not found")
#     Session.delete(t_instance)
#     Session.commit()
#     return "Done"

# @product_router.get("/products/{zip}/{keyword}", response_model=List[schemas.Product])
# async def search_for_products(keyword: str, sess: Session=Depends(get_db)):
#     return sess.query(models.Product).filter( keyword in models.Product.name ).all()