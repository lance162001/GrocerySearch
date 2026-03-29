import os
from typing import List

import Levenshtein
from fastapi import APIRouter, Depends
from fastapi.exceptions import HTTPException
from fastapi_pagination import Page, add_pagination
from fastapi_pagination.ext.sqlalchemy import paginate
from sqlalchemy import select, or_
from sqlalchemy.orm import Session
from sqlalchemy.sql.expression import func

from . import get_db, escape_like
import models
import schemas

store_router = APIRouter()


def _logo_url(company: models.Company) -> str:
    name = f"company_{company.id}.png"
    path = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'static', 'logos', name)
    return f"/static/logos/{name}" if os.path.exists(path) else str(company.logo_url)


def similar(a: str, b: str) -> float:
    return Levenshtein.ratio(a.lower(), b.lower())


@store_router.get("/stores", response_model=List[schemas.Store])
async def get_all_stores(sess: Session = Depends(get_db)):
    return sess.query(models.Store).all()


@store_router.get("/stores/{id}/products", response_model=List[schemas.Product_Instance])
async def get_products_from_store(id: int, sess: Session = Depends(get_db)):
    product_instances = sess.query(models.Product_Instance).filter(
        models.Product_Instance.store_id == id
    ).all()
    if not product_instances:
        raise HTTPException(404, detail=f"Product from store with id {id} not found")
    return product_instances


@store_router.get("/stores/search", response_model=Page[schemas.Store])
async def store_search(search: str | None = "", sess: Session = Depends(get_db)):
    if search == "":
        return paginate(sess, select(models.Store))
    escaped = escape_like(search)
    return paginate(
        sess,
        select(models.Store).where(
            or_(
                models.Store.address.like(f"%{escaped}%", escape="\\"),
                models.Store.zipcode.like(f"%{escaped}%", escape="\\"),
                models.Store.state.like(f"%{escaped}%", escape="\\"),
                models.Store.town.like(f"%{escaped}%", escape="\\"),
            )
        ),
    )


@store_router.get("/company/{id}", response_model=schemas.Company)
async def get_company(id: int, sess: Session = Depends(get_db)):
    company = sess.get(models.Company, id)
    if not company:
        raise HTTPException(404, detail=f"Company with id {id} not found")
    return schemas.Company(id=int(company.id), name=str(company.name), logo_url=_logo_url(company))


@store_router.get("/company", response_model=List[schemas.Company])
async def get_all_companies(sess: Session = Depends(get_db)):
    companies = sess.query(models.Company).all()
    return [schemas.Company(id=int(c.id), name=str(c.name), logo_url=_logo_url(c)) for c in companies]


@store_router.post("/stores/product_search", response_model=Page[schemas.Product_Details])
async def full_product_search(
    ids: List[int],
    tags: List[int] | None = None,
    search: str | None = "",
    on_sale: bool = False,
    has_spread: bool = False,
    sess: Session = Depends(get_db),
):
    s = (
        select(models.Product, models.Product_Instance)
        .where(models.Product.id == models.Product_Instance.product_id)
        .where(models.Product_Instance.store_id.in_(ids))
    )

    tags = tags or []

    if search:
        escaped = escape_like(search)
        s = s.where(
            or_(
                models.Product.name.ilike(f"%{escaped}%", escape="\\"),
                models.Product.brand.ilike(f"%{escaped}%", escape="\\"),
                models.Product.tags.any(
                    models.Tag_Instance.tag_id.in_(
                        select(models.Tag.id).where(
                            models.Tag.name.ilike(f"%{escaped}%", escape="\\")
                        )
                    )
                ),
            )
        )

    for tag_id in tags:
        s = s.where(models.Product.tags.any(models.Tag_Instance.tag_id == tag_id))

    if on_sale:
        latest_pricepoint_id = (
            select(func.max(models.PricePoint.id))
            .where(models.PricePoint.instance_id == models.Product_Instance.id)
            .correlate(models.Product_Instance)
            .scalar_subquery()
        )
        s = s.where(
            select(models.PricePoint.id)
            .where(
                models.PricePoint.id == latest_pricepoint_id,
                or_(
                    func.coalesce(models.PricePoint.sale_price, "") != "",
                    func.coalesce(models.PricePoint.member_price, "") != "",
                ),
            )
            .exists()
        )

    if has_spread:
        # Find product names (case-insensitive) that appear in stores from more
        # than one company among the selected store IDs.  These are the products
        # most likely to form cross-store price-spread pairs on the Flutter side.
        multi_company_names = (
            select(func.lower(models.Product.name).label("nm"))
            .join(
                models.Product_Instance,
                models.Product_Instance.product_id == models.Product.id,
            )
            .where(models.Product_Instance.store_id.in_(ids))
            .group_by(func.lower(models.Product.name))
            .having(func.count(func.distinct(models.Product.company_id)) > 1)
        )
        s = s.where(func.lower(models.Product.name).in_(multi_company_names))

    s = s.order_by(func.length(models.Product.name))
    return paginate(sess, s)


@store_router.post("/stores/suggest", response_model=schemas.StoreSuggestionResponse)
async def suggest_store(
    payload: schemas.StoreSuggestionRequest,
    sess: Session = Depends(get_db),
):
    """Save a user-submitted store suggestion flagged as TODO."""
    company = sess.get(models.Company, payload.company_id)
    if not company:
        raise HTTPException(404, detail=f"Company {payload.company_id} not found")

    suggestion = models.StoreSuggestion(
        company_id=payload.company_id,
        address=payload.address,
        town=payload.town,
        state=payload.state,
        zipcode=payload.zipcode,
        status="todo",
    )
    sess.add(suggestion)
    sess.commit()
    sess.refresh(suggestion)

    return schemas.StoreSuggestionResponse(
        id=int(suggestion.id),
        company_id=int(suggestion.company_id),
        address=str(suggestion.address),
        town=str(suggestion.town),
        state=str(suggestion.state),
        zipcode=str(suggestion.zipcode),
        status=str(suggestion.status),
        created_at=suggestion.created_at,
    )


add_pagination(store_router)