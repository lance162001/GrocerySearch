"""Endpoints for price-tracking (tracked items, points)."""

import re
from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from . import get_db
import models
import schemas

tracking_router = APIRouter()

_price_pattern = re.compile(r"-?\d+(?:\.\d+)?")


def _parse_price(value: Optional[str]) -> Optional[float]:
    if value is None:
        return None
    match = _price_pattern.search(str(value).replace(",", ""))
    if not match:
        return None
    return float(match.group(0))


def _effective_price(pp) -> Optional[float]:
    """Return the best available price from a PricePoint row."""
    return (
        _parse_price(pp.member_price)
        or _parse_price(pp.sale_price)
        or _parse_price(pp.base_price)
    )


def _get_or_create_user(user_id: int, sess: Session) -> models.User:
    user = sess.get(models.User, user_id)
    if user:
        return user
    user = models.User(id=user_id, recent_zipcode="00000")
    sess.add(user)
    sess.commit()
    sess.refresh(user)
    return user


# ------------------------------------------------------------------
# POST /tracking/track  — idempotent add
# ------------------------------------------------------------------
@tracking_router.post("/tracking/track", response_model=schemas.TrackedItemResponse)
async def track_item(payload: schemas.TrackRequest, sess: Session = Depends(get_db)):
    _get_or_create_user(payload.user_id, sess)

    product = sess.get(models.Product, payload.product_id)
    if not product:
        raise HTTPException(404, detail=f"Product {payload.product_id} not found")

    existing = (
        sess.query(models.Tracked_Item)
        .filter(
            models.Tracked_Item.user_id == payload.user_id,
            models.Tracked_Item.product_id == payload.product_id,
        )
        .first()
    )
    if not existing:
        existing = models.Tracked_Item(
            user_id=payload.user_id, product_id=payload.product_id
        )
        sess.add(existing)
        sess.commit()
        sess.refresh(existing)

    return _build_tracked_response(existing, product, sess)


# ------------------------------------------------------------------
# DELETE /tracking/track/{product_id}?user_id=X
# ------------------------------------------------------------------
@tracking_router.delete("/tracking/track/{product_id}")
async def untrack_item(product_id: int, user_id: int, sess: Session = Depends(get_db)):
    tracked = (
        sess.query(models.Tracked_Item)
        .filter(
            models.Tracked_Item.user_id == user_id,
            models.Tracked_Item.product_id == product_id,
        )
        .first()
    )
    if not tracked:
        raise HTTPException(404, detail="Tracked item not found")
    sess.delete(tracked)
    sess.commit()
    return {"ok": True}


# ------------------------------------------------------------------
# GET /tracking/tracked?user_id=X
# ------------------------------------------------------------------
@tracking_router.get("/tracking/tracked", response_model=list[schemas.TrackedItemResponse])
async def list_tracked_items(user_id: int, sess: Session = Depends(get_db)):
    _get_or_create_user(user_id, sess)
    tracked_rows = (
        sess.query(models.Tracked_Item)
        .filter(models.Tracked_Item.user_id == user_id)
        .order_by(models.Tracked_Item.created_at.desc())
        .all()
    )
    results = []
    for ti in tracked_rows:
        product = sess.get(models.Product, ti.product_id)
        if not product:
            continue
        results.append(_build_tracked_response(ti, product, sess))
    return results


# ------------------------------------------------------------------
# GET /tracking/tracked/{product_id}?user_id=X
# ------------------------------------------------------------------
@tracking_router.get("/tracking/tracked/{product_id}", response_model=schemas.TrackedItemDetail)
async def tracked_item_detail(product_id: int, user_id: int, sess: Session = Depends(get_db)):
    tracked = (
        sess.query(models.Tracked_Item)
        .filter(
            models.Tracked_Item.user_id == user_id,
            models.Tracked_Item.product_id == product_id,
        )
        .first()
    )
    if not tracked:
        raise HTTPException(404, detail="Tracked item not found")

    product = sess.get(models.Product, product_id)
    if not product:
        raise HTTPException(404, detail="Product not found")

    base = _build_tracked_response(tracked, product, sess)

    # all_store_prices — latest price per instance/store
    instances = (
        sess.query(models.Product_Instance)
        .filter(models.Product_Instance.product_id == product_id)
        .all()
    )
    all_store_prices = []
    # Collect (store_id, price, chain) for all instances first to determine is_best
    _store_price_rows = []
    for inst in instances:
        latest_pp = (
            sess.query(models.PricePoint)
            .filter(models.PricePoint.instance_id == inst.id)
            .order_by(models.PricePoint.created_at.desc())
            .first()
        )
        if not latest_pp:
            continue
        price = _effective_price(latest_pp)
        if price is None:
            continue
        store = sess.get(models.Store, inst.store_id)
        chain = ""
        if store:
            company = sess.get(models.Company, store.company_id)
            chain = company.name if company else ""
        _store_price_rows.append((inst.store_id, price, chain))

    # Determine the best (lowest) price
    best_price = min((r[1] for r in _store_price_rows), default=None)
    for store_id, price, chain in _store_price_rows:
        all_store_prices.append(
            schemas.StorePriceInfo(
                chain=chain,
                store_id=store_id,
                price=price,
                is_best=(best_price is not None and price == best_price),
            )
        )

    # price_history — all price points across all instances, last 90 days, chronological
    from datetime import timedelta
    cutoff = datetime.utcnow() - timedelta(days=90)
    price_history = []
    price_points = (
        sess.query(models.PricePoint, models.Product_Instance)
        .join(models.Product_Instance, models.PricePoint.instance_id == models.Product_Instance.id)
        .filter(
            models.Product_Instance.product_id == product_id,
            models.PricePoint.created_at >= cutoff,
        )
        .order_by(models.PricePoint.created_at.asc())
        .all()
    )
    for pp, inst in price_points:
        price = _effective_price(pp)
        if price is not None and pp.created_at is not None:
            store = sess.get(models.Store, inst.store_id)
            chain = ""
            if store:
                company = sess.get(models.Company, store.company_id)
                chain = company.name if company else ""
            price_history.append(
                schemas.PriceHistoryPoint(timestamp=pp.created_at, chain=chain, price=price)
            )

    return schemas.TrackedItemDetail(
        **base.model_dump(),
        all_store_prices=all_store_prices,
        price_history=price_history,
    )


# ------------------------------------------------------------------
# GET /tracking/points?user_id=X
# ------------------------------------------------------------------
@tracking_router.get("/tracking/points", response_model=schemas.PointsResponse)
async def get_points(user_id: int, sess: Session = Depends(get_db)):
    _get_or_create_user(user_id, sess)

    user_points = (
        sess.query(models.User_Points)
        .filter(models.User_Points.user_id == user_id)
        .first()
    )
    points = user_points.points if user_points else 0

    labels_submitted = (
        sess.query(models.LabelJudgement)
        .filter(models.LabelJudgement.user_id == user_id)
        .count()
    )

    # Accuracy: fraction of labels that agree with majority consensus
    # For now, return 0.0 if no labels; a future task can refine this
    accuracy = 0.0

    return schemas.PointsResponse(
        user_id=user_id,
        points=points,
        labels_submitted=labels_submitted,
        accuracy=accuracy,
        monthly_rank=None,
    )


# ------------------------------------------------------------------
# Helper: build a TrackedItemResponse from a Tracked_Item + Product
# ------------------------------------------------------------------
def _build_tracked_response(
    tracked: models.Tracked_Item,
    product: models.Product,
    sess: Session,
) -> schemas.TrackedItemResponse:
    """Enrich a tracked item with current price info."""

    # Find company info via product.company_id
    company_name: Optional[str] = None
    company_id: Optional[int] = product.company_id
    if company_id:
        company = sess.get(models.Company, company_id)
        if company:
            company_name = company.name

    # Collect latest price points per instance for this product
    instances = (
        sess.query(models.Product_Instance)
        .filter(models.Product_Instance.product_id == product.id)
        .all()
    )

    current_price: Optional[float] = None
    previous_price: Optional[float] = None
    price_change: Optional[str] = None  # "drop", "up", or None
    price_change_at: Optional[datetime] = None
    stable_weeks: Optional[int] = None
    cheapest_chain: Optional[str] = None
    cheapest_price: Optional[float] = None

    best_current: Optional[float] = None
    best_current_store_id: Optional[int] = None

    for inst in instances:
        # latest two price points for this instance
        recent_pps = (
            sess.query(models.PricePoint)
            .filter(models.PricePoint.instance_id == inst.id)
            .order_by(models.PricePoint.created_at.desc())
            .limit(2)
            .all()
        )
        if not recent_pps:
            continue

        latest_price = _effective_price(recent_pps[0])
        if latest_price is None:
            continue

        # Track cheapest across all stores
        if cheapest_price is None or latest_price < cheapest_price:
            cheapest_price = latest_price
            store = sess.get(models.Store, inst.store_id)
            if store:
                co = sess.get(models.Company, store.company_id)
                cheapest_chain = co.name if co else None

        # Use the most-recently-collected price as "current"
        if best_current is None or latest_price < best_current:
            best_current = latest_price
            best_current_store_id = inst.store_id

            # price change detection from this instance
            if len(recent_pps) >= 2:
                prev = _effective_price(recent_pps[1])
                if prev is not None:
                    previous_price = prev
                    if latest_price < prev:
                        price_change = "drop"
                    elif latest_price > prev:
                        price_change = "up"
                    else:
                        price_change = None
                    price_change_at = recent_pps[0].created_at

    current_price = best_current

    # Stable weeks: count consecutive weeks with the same price
    if best_current is not None and best_current_store_id is not None:
        # Get the instance for the best-priced store
        best_inst = (
            sess.query(models.Product_Instance)
            .filter(
                models.Product_Instance.product_id == product.id,
                models.Product_Instance.store_id == best_current_store_id,
            )
            .first()
        )
        if best_inst:
            all_pps = (
                sess.query(models.PricePoint)
                .filter(models.PricePoint.instance_id == best_inst.id)
                .order_by(models.PricePoint.created_at.desc())
                .all()
            )
            weeks = 0
            for pp in all_pps:
                p = _effective_price(pp)
                if p is not None and p == best_current:
                    weeks += 1
                else:
                    break
            # Each price point is roughly one collection day; approximate weeks
            stable_weeks = max(weeks // 7, 0) if weeks > 0 else 0
            # If we have at least one matching price point, count as at least 0 weeks
            # (price has been stable for the period of all matching points)

    return schemas.TrackedItemResponse(
        id=tracked.id,
        user_id=tracked.user_id,
        product_id=tracked.product_id,
        product_name=product.name or "",
        brand=product.brand or "",
        picture_url=product.picture_url,
        company_name=company_name,
        company_id=company_id,
        current_price=current_price,
        previous_price=previous_price,
        price_change=price_change,
        price_change_at=price_change_at,
        stable_weeks=stable_weeks,
        cheapest_chain=cheapest_chain,
        cheapest_price=cheapest_price,
        created_at=tracked.created_at,
    )
