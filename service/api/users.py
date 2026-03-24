import re
import secrets
from collections import defaultdict
from datetime import datetime
from typing import Dict, List, Optional

from fastapi import APIRouter, Depends
from fastapi.exceptions import HTTPException
from fastapi.responses import HTMLResponse
from sqlalchemy import func, select
from sqlalchemy.orm import Session, joinedload

from . import get_db
import models
import schemas

user_router = APIRouter()

_price_pattern = re.compile(r"-?\d+(?:\.\d+)?")


@user_router.get("/users/unsubscribe", response_class=HTMLResponse, include_in_schema=False)
async def unsubscribe_newsletter(token: str, sess: Session = Depends(get_db)):
    """Unsubscribe a user from newsletters using a one-click token link."""
    if token == "test-do-not-unsubscribe":
        return HTMLResponse(
            content="<h2>Test unsubscribe — no action taken.</h2>",
            status_code=200,
        )
    user = sess.query(models.User).filter(models.User.unsubscribe_token == token).first()
    if user is None:
        return HTMLResponse(
            content=(
                "<h2>Link invalid</h2>"
                "<p>That unsubscribe link is invalid or already expired.</p>"
            ),
            status_code=404,
        )

    setattr(user, "newsletter_opt_in", False)
    setattr(user, "newsletter_unsubscribed_at", datetime.now())
    sess.commit()

    return HTMLResponse(
        content=(
            "<h2>You are unsubscribed</h2>"
            "<p>You will no longer receive GrocerySearch newsletter emails.</p>"
        ),
        status_code=200,
    )


def _parse_price(value: Optional[str]) -> Optional[float]:
    if value is None:
        return None
    match = _price_pattern.search(str(value).replace(",", ""))
    if not match:
        return None
    return float(match.group(0))


def _effective_price(
    member_price: Optional[str],
    sale_price: Optional[str],
    base_price: Optional[str],
) -> Optional[float]:
    return _parse_price(member_price) or _parse_price(sale_price) or _parse_price(base_price)


def _get_or_create_user(user_id: int, sess: Session) -> models.User:
    user = sess.get(models.User, user_id)
    if user:
        return user
    user = models.User(id=user_id, recent_zipcode="00000")
    sess.add(user)
    sess.commit()
    sess.refresh(user)
    return user


@user_router.get("/users/{user_id}/newsletter", response_model=schemas.NewsletterStatus)
async def get_newsletter_status(user_id: int, sess: Session = Depends(get_db)):
    """Return the newsletter opt-in status and frequency for a user."""
    user = _get_or_create_user(user_id, sess)
    return schemas.NewsletterStatus(
        opted_in=bool(user.newsletter_opt_in),
        frequency=str(getattr(user, 'newsletter_frequency', None) or 'weekly'),
    )


@user_router.post("/users/{user_id}/newsletter", response_model=schemas.NewsletterStatus)
async def update_newsletter_status(
    user_id: int,
    payload: schemas.NewsletterUpdateRequest,
    sess: Session = Depends(get_db),
):
    """Subscribe or unsubscribe a user from the newsletter, and optionally set frequency."""
    user = _get_or_create_user(user_id, sess)
    setattr(user, "newsletter_opt_in", payload.opt_in)
    if not payload.opt_in:
        setattr(user, "newsletter_unsubscribed_at", datetime.now())
    if payload.frequency is not None:
        if payload.frequency not in ('daily', 'weekly'):
            raise HTTPException(400, detail="frequency must be 'daily' or 'weekly'")
        setattr(user, "newsletter_frequency", payload.frequency)
    sess.commit()
    return schemas.NewsletterStatus(
        opted_in=payload.opt_in,
        frequency=str(getattr(user, 'newsletter_frequency', None) or 'weekly'),
    )


@user_router.post("/users/create", response_model=schemas.User)
async def create_user(sess: Session = Depends(get_db)):
    user = models.User(recent_zipcode="00000")
    sess.add(user)
    sess.commit()
    sess.refresh(user)
    return schemas.User(id=int(user.id), recent_zipcode=str(user.recent_zipcode))


@user_router.post("/users/lookup-or-create", response_model=schemas.User)
async def lookup_or_create_user(
    payload: schemas.LookupOrCreateRequest,
    sess: Session = Depends(get_db),
):
    """Return the backend user for the given Firebase UID, creating one if needed."""
    firebase_uid = payload.firebase_uid.strip()
    if not firebase_uid:
        raise HTTPException(400, detail="firebase_uid is required")

    user = sess.query(models.User).filter(models.User.firebase_uid == firebase_uid).first()
    if user is None:
        user = models.User(recent_zipcode="00000", firebase_uid=firebase_uid, email=payload.email)
        sess.add(user)
        sess.commit()
        sess.refresh(user)
    elif payload.email and not user.email:
        user.email = payload.email
        sess.commit()

    return schemas.User(id=int(user.id), recent_zipcode=str(user.recent_zipcode))


@user_router.post("/users/{user_id}/bundles", response_model=schemas.BundleSummary)
async def create_bundle(
    user_id: int,
    payload: schemas.BundleCreateRequest,
    sess: Session = Depends(get_db),
):
    name = payload.name.strip()
    if not name:
        raise HTTPException(400, detail="Bundle name is required")

    _get_or_create_user(user_id, sess)
    bundle = models.Product_Bundle(user_id=user_id, name=name)
    sess.add(bundle)
    sess.commit()
    sess.refresh(bundle)
    return schemas.BundleSummary(
        id=int(bundle.id),
        user_id=int(bundle.user_id),
        name=str(bundle.name),
        created_at=bundle.created_at,
    )


@user_router.post("/bundles/{bundle_id}/products", response_model=schemas.BundleSummary)
async def add_product_to_bundle(
    bundle_id: int,
    payload: schemas.BundleProductAddRequest,
    sess: Session = Depends(get_db),
):
    bundle = sess.get(models.Product_Bundle, bundle_id)
    if not bundle:
        raise HTTPException(404, detail=f"Bundle with id {bundle_id} not found")

    product = sess.get(models.Product, payload.product_id)
    if not product:
        raise HTTPException(404, detail=f"Product with id {payload.product_id} not found")

    existing = (
        sess.query(models.Saved_Product)
        .filter(
            models.Saved_Product.bundle_id == bundle_id,
            models.Saved_Product.product_id == payload.product_id,
        )
        .first()
    )
    if not existing:
        sess.add(models.Saved_Product(bundle_id=bundle_id, product_id=payload.product_id))
        sess.commit()

    return schemas.BundleSummary(
        id=int(bundle.id),
        user_id=int(bundle.user_id),
        name=str(bundle.name),
        created_at=bundle.created_at,
    )


@user_router.post("/bundles/{bundle_id}/share", response_model=schemas.ShareTokenResponse)
async def create_bundle_share_link(bundle_id: int, sess: Session = Depends(get_db)):
    """Generate (or return the existing) share token for a bundle."""
    bundle = sess.get(models.Product_Bundle, bundle_id)
    if not bundle:
        raise HTTPException(404, detail=f"Bundle with id {bundle_id} not found")
    if not bundle.share_token:
        bundle.share_token = secrets.token_urlsafe(32)
        sess.commit()
    return schemas.ShareTokenResponse(bundle_id=int(bundle.id), token=str(bundle.share_token))


@user_router.post("/users/{user_id}/saved-stores", response_model=schemas.SavedStoreSummary)
async def upsert_saved_store(
    user_id: int,
    payload: schemas.SavedStoreUpsertRequest,
    sess: Session = Depends(get_db),
):
    _get_or_create_user(user_id, sess)

    store = sess.get(models.Store, payload.store_id)
    if not store:
        raise HTTPException(404, detail=f"Store with id {payload.store_id} not found")

    saved_store = (
        sess.query(models.Saved_Store)
        .filter(models.Saved_Store.user_id == user_id, models.Saved_Store.store_id == payload.store_id)
        .first()
    )
    if saved_store:
        saved_store.member = payload.member
    else:
        saved_store = models.Saved_Store(user_id=user_id, store_id=payload.store_id, member=payload.member)
        sess.add(saved_store)

    sess.commit()
    return schemas.SavedStoreSummary(
        store_id=int(saved_store.store_id),
        member=bool(saved_store.member),
        user_id=int(saved_store.user_id),
    )


@user_router.get("/users/{user_id}/saved-stores", response_model=List[schemas.SavedStoreSummary])
async def list_saved_stores(user_id: int, sess: Session = Depends(get_db)):
    _get_or_create_user(user_id, sess)

    saved_stores = (
        sess.query(models.Saved_Store)
        .filter(models.Saved_Store.user_id == user_id)
        .order_by(models.Saved_Store.store_id.asc())
        .all()
    )

    return [
        schemas.SavedStoreSummary(
            store_id=int(saved.store_id),
            member=bool(saved.member),
            user_id=int(saved.user_id),
        )
        for saved in saved_stores
    ]


@user_router.get("/users/{user_id}/dashboard", response_model=schemas.UserDashboard)
async def get_user_dashboard(user_id: int, sess: Session = Depends(get_db)):
    user = _get_or_create_user(user_id, sess)
    bundle_count = (
        sess.query(func.count(models.Product_Bundle.id))
        .filter(models.Product_Bundle.user_id == user_id)
        .scalar()
    )
    saved_store_count = (
        sess.query(func.count(models.Saved_Store.store_id))
        .filter(models.Saved_Store.user_id == user_id)
        .scalar()
    )
    visit_count = (
        sess.query(func.count(models.Store_Visit.id))
        .filter(models.Store_Visit.user_id == user_id)
        .scalar()
    )
    return schemas.UserDashboard(
        user_id=int(user.id),
        recent_zipcode=str(user.recent_zipcode),
        bundle_count=int(bundle_count or 0),
        saved_store_count=int(saved_store_count or 0),
        visit_count=int(visit_count or 0),
    )


@user_router.get("/users/{user_id}/bundles", response_model=List[schemas.BundleSummaryWithProducts])
async def list_user_bundles(user_id: int, sess: Session = Depends(get_db)):
    _get_or_create_user(user_id, sess)
    bundles = (
        sess.query(models.Product_Bundle)
        .options(joinedload(models.Product_Bundle.products))
        .filter(models.Product_Bundle.user_id == user_id)
        .order_by(models.Product_Bundle.created_at.desc())
        .all()
    )
    return [
        schemas.BundleSummaryWithProducts(
            id=int(b.id),
            user_id=int(b.user_id),
            name=str(b.name),
            created_at=b.created_at,
            product_count=len(b.products),
            product_ids=[int(p.product_id) for p in b.products],
        )
        for b in bundles
    ]


@user_router.get("/users/{user_id}/visits", response_model=List[schemas.VisitResponse])
async def list_user_visits(user_id: int, sess: Session = Depends(get_db)):
    _get_or_create_user(user_id, sess)
    visits = (
        sess.query(models.Store_Visit)
        .filter(models.Store_Visit.user_id == user_id)
        .order_by(models.Store_Visit.created_at.desc())
        .limit(20)
        .all()
    )
    return [
        schemas.VisitResponse(
            id=int(v.id),
            bundle_id=int(v.product_bundle_id),
            user_id=int(v.user_id),
            created_at=v.created_at,
        )
        for v in visits
    ]


def _build_bundle_product_details(
    bundle: models.Product_Bundle,
    sess: Session,
) -> List[schemas.BundleProductDetail]:
    """Resolve every product in a bundle with its full price history across all instances."""
    product_ids = [int(sp.product_id) for sp in bundle.products]
    if not product_ids:
        return []

    rows = (
        sess.query(models.Product, models.Product_Instance, models.PricePoint)
        .join(models.Product_Instance, models.Product_Instance.product_id == models.Product.id)
        .outerjoin(models.PricePoint, models.PricePoint.instance_id == models.Product_Instance.id)
        .filter(models.Product.id.in_(product_ids))
        .order_by(models.Product.id, models.Product_Instance.id, models.PricePoint.created_at)
        .all()
    )

    products_map: Dict[int, dict] = {}
    for product, instance, price_point in rows:
        pid = int(product.id)
        if pid not in products_map:
            products_map[pid] = {
                "product_id": pid,
                "name": str(product.name),
                "brand": str(product.brand),
                "picture_url": str(product.picture_url or ""),
                "instances": {},
            }
        inst_id = int(instance.id)
        if inst_id not in products_map[pid]["instances"]:
            products_map[pid]["instances"][inst_id] = {
                "store_id": int(instance.store_id),
                "price_points": [],
            }
        if price_point is not None:
            products_map[pid]["instances"][inst_id]["price_points"].append(
                schemas.PricePoint(
                    base_price=str(price_point.base_price or ""),
                    sale_price=price_point.sale_price,
                    member_price=price_point.member_price,
                    size=price_point.size,
                    created_at=price_point.created_at,
                )
            )

    result = []
    for pid in product_ids:
        if pid not in products_map:
            continue
        pm = products_map[pid]
        instances = [
            schemas.Product_Instance(store_id=inst["store_id"], price_points=inst["price_points"])
            for inst in pm["instances"].values()
        ]
        result.append(
            schemas.BundleProductDetail(
                product_id=pm["product_id"],
                name=pm["name"],
                brand=pm["brand"],
                picture_url=pm["picture_url"],
                instances=instances,
            )
        )
    return result


@user_router.get("/bundles/shared/{token}", response_model=schemas.SharedBundleResponse)
async def get_shared_bundle(token: str, sess: Session = Depends(get_db)):
    """Public endpoint — returns a shared bundle by its share token."""
    bundle = (
        sess.query(models.Product_Bundle)
        .options(joinedload(models.Product_Bundle.products))
        .filter(models.Product_Bundle.share_token == token)
        .first()
    )
    if not bundle:
        raise HTTPException(404, detail="Bundle not found or link has expired")

    products = _build_bundle_product_details(bundle, sess)

    items = [
        schemas.SharedBundleProductItem(
            product_id=p.product_id,
            name=p.name,
            brand=p.brand,
            picture_url=p.picture_url,
            instances=p.instances,
        )
        for p in products
    ]

    return schemas.SharedBundleResponse(
        bundle_id=int(bundle.id),
        name=str(bundle.name),
        created_at=bundle.created_at,
        product_count=len(bundle.products),
        products=items,
    )


@user_router.get("/bundles/{bundle_id}/detail", response_model=schemas.BundleDetailResponse)
async def get_bundle_detail(bundle_id: int, sess: Session = Depends(get_db)):
    bundle = (
        sess.query(models.Product_Bundle)
        .options(joinedload(models.Product_Bundle.products))
        .get(bundle_id)
    )
    if not bundle:
        raise HTTPException(404, detail=f"Bundle with id {bundle_id} not found")

    products = _build_bundle_product_details(bundle, sess)

    return schemas.BundleDetailResponse(
        id=int(bundle.id),
        user_id=int(bundle.user_id),
        name=str(bundle.name),
        created_at=bundle.created_at,
        product_count=len(bundle.products),
        products=products,
    )


@user_router.get("/bundles/{bundle_id}/plan", response_model=schemas.BundlePlanResponse)
async def build_bundle_plan(
    bundle_id: int,
    use_saved_stores: bool = True,
    sess: Session = Depends(get_db),
):
    bundle = sess.get(models.Product_Bundle, bundle_id)
    if not bundle:
        raise HTTPException(404, detail=f"Bundle with id {bundle_id} not found")

    product_ids = [int(p.product_id) for p in bundle.products]
    if not product_ids:
        raise HTTPException(400, detail="Bundle has no products")

    latest_pricepoint_id = (
        select(func.max(models.PricePoint.id))
        .where(models.PricePoint.instance_id == models.Product_Instance.id)
        .correlate(models.Product_Instance)
        .scalar_subquery()
    )

    store_ids: Optional[List[int]] = None
    if use_saved_stores:
        saved = (
            sess.query(models.Saved_Store)
            .filter(models.Saved_Store.user_id == bundle.user_id)
            .all()
        )
        store_ids = [int(s.store_id) for s in saved]
        if not store_ids:
            raise HTTPException(400, detail="No saved stores for this user")

    query = (
        sess.query(
            models.Product_Instance.product_id,
            models.Product_Instance.store_id,
            models.Product.name,
            models.Product.brand,
            models.PricePoint.member_price,
            models.PricePoint.sale_price,
            models.PricePoint.base_price,
        )
        .join(models.Product, models.Product.id == models.Product_Instance.product_id)
        .join(models.PricePoint, models.PricePoint.id == latest_pricepoint_id)
        .filter(models.Product_Instance.product_id.in_(product_ids))
    )

    if store_ids is not None:
        query = query.filter(models.Product_Instance.store_id.in_(store_ids))

    rows = query.all()

    by_product: Dict[int, List[dict]] = defaultdict(list)
    by_store_totals: Dict[int, dict] = defaultdict(lambda: {"total": 0.0, "item_count": 0, "products": set()})

    for row in rows:
        price = _effective_price(row.member_price, row.sale_price, row.base_price)
        if price is None:
            continue
        by_product[int(row.product_id)].append({
            "product_id": int(row.product_id),
            "store_id": int(row.store_id),
            "product_name": str(row.name),
            "brand": str(row.brand),
            "price": float(price),
        })

    for product_id, options in by_product.items():
        per_store_best: Dict[int, float] = {}
        for option in options:
            sid = option["store_id"]
            per_store_best[sid] = min(per_store_best.get(sid, option["price"]), option["price"])
        for sid, best_price in per_store_best.items():
            by_store_totals[sid]["total"] += best_price
            by_store_totals[sid]["products"].add(product_id)

    item_count = len(product_ids)
    missing_product_ids = [pid for pid in product_ids if pid not in by_product]

    # Build the per-product "split shopping" plan (cheapest option per product)
    lines: List[schemas.PlanProductLine] = []
    split_store_accumulator: Dict[int, dict] = defaultdict(lambda: {"total": 0.0, "item_count": 0})
    split_store_total = 0.0

    for product_id, options in by_product.items():
        best_option = min(options, key=lambda x: x["price"])
        split_store_total += best_option["price"]
        split_store_accumulator[best_option["store_id"]]["total"] += best_option["price"]
        split_store_accumulator[best_option["store_id"]]["item_count"] += 1
        lines.append(
            schemas.PlanProductLine(
                product_id=product_id,
                product_name=best_option["product_name"],
                brand=best_option["brand"],
                best_store_id=best_option["store_id"],
                best_price=round(best_option["price"], 2),
            )
        )

    split_by_store = [
        schemas.PlanStoreSummary(store_id=sid, item_count=data["item_count"], total=round(data["total"], 2))
        for sid, data in sorted(split_store_accumulator.items(), key=lambda x: x[1]["total"])
    ]

    # Find best single-store option (store that carries all items)
    single_store_best = None
    for sid, data in by_store_totals.items():
        if len(data["products"]) == item_count:
            total = round(data["total"], 2)
            if single_store_best is None or total < single_store_best.total:
                single_store_best = schemas.SingleStorePlan(store_id=sid, total=total)

    estimated_savings_vs_best_single = None
    if single_store_best is not None:
        estimated_savings_vs_best_single = round(single_store_best.total - split_store_total, 2)

    return schemas.BundlePlanResponse(
        bundle_id=int(bundle.id),
        bundle_name=str(bundle.name),
        item_count=item_count,
        missing_product_ids=missing_product_ids,
        single_store_best=single_store_best,
        split_store_total=round(split_store_total, 2),
        split_by_store=split_by_store,
        lines=lines,
        estimated_savings_vs_best_single=estimated_savings_vs_best_single,
    )


@user_router.post("/bundles/{bundle_id}/visit", response_model=schemas.VisitResponse)
async def log_bundle_visit(
    bundle_id: int,
    payload: schemas.VisitCreateRequest,
    sess: Session = Depends(get_db),
):
    bundle = sess.get(models.Product_Bundle, bundle_id)
    if not bundle:
        raise HTTPException(404, detail=f"Bundle with id {bundle_id} not found")

    if payload.store_id is not None:
        store = sess.get(models.Store, payload.store_id)
        if not store:
            raise HTTPException(404, detail=f"Store with id {payload.store_id} not found")

    visit = models.Store_Visit(product_bundle_id=bundle_id, user_id=bundle.user_id)
    sess.add(visit)
    sess.commit()
    sess.refresh(visit)

    return schemas.VisitResponse(
        id=int(visit.id),
        bundle_id=int(visit.product_bundle_id),
        user_id=int(visit.user_id),
        created_at=visit.created_at,
        store_id=payload.store_id,
    )

