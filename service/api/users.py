import re
from collections import defaultdict
from typing import Dict, List, Optional

from fastapi import APIRouter, Depends
from fastapi.exceptions import HTTPException
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from . import get_db

import models
import schemas

user_router = APIRouter()


_price_pattern = re.compile(r"-?\d+(?:\.\d+)?")


def _parse_price(value: Optional[str]) -> Optional[float]:
	if value is None:
		return None
	match = _price_pattern.search(str(value).replace(",", ""))
	if not match:
		return None
	return float(match.group(0))


def _effective_price(member_price: Optional[str], sale_price: Optional[str], base_price: Optional[str]) -> Optional[float]:
	return _parse_price(member_price) or _parse_price(sale_price) or _parse_price(base_price)


def _get_or_create_user(user_id: int, sess: Session) -> models.User:
	user = sess.query(models.User).get(user_id)
	if user:
		return user
	user = models.User(id=user_id, recent_zipcode="00000")
	sess.add(user)
	sess.commit()
	sess.refresh(user)
	return user


@user_router.post("/users/create", response_model=schemas.User)
async def create_user(sess: Session = Depends(get_db)):
	user = models.User(recent_zipcode="00000")
	sess.add(user)
	sess.commit()
	sess.refresh(user)
	return schemas.User(id=int(user.id), recent_zipcode=str(user.recent_zipcode))


@user_router.post("/users/{user_id}/bundles", response_model=schemas.BundleSummary)
async def create_bundle(user_id: int, payload: schemas.BundleCreateRequest, sess: Session = Depends(get_db)):
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
async def add_product_to_bundle(bundle_id: int, payload: schemas.BundleProductAddRequest, sess: Session = Depends(get_db)):
	bundle = sess.query(models.Product_Bundle).get(bundle_id)
	if not bundle:
		raise HTTPException(404, detail=f"Bundle with id {bundle_id} not found")

	product = sess.query(models.Product).get(payload.product_id)
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


@user_router.post("/users/{user_id}/saved-stores", response_model=schemas.SavedStoreSummary)
async def upsert_saved_store(user_id: int, payload: schemas.SavedStoreUpsertRequest, sess: Session = Depends(get_db)):
	_get_or_create_user(user_id, sess)

	store = sess.query(models.Store).get(payload.store_id)
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


@user_router.get("/bundles/{bundle_id}/plan", response_model=schemas.BundlePlanResponse)
async def build_bundle_plan(bundle_id: int, use_saved_stores: bool = True, sess: Session = Depends(get_db)):
	bundle = sess.query(models.Product_Bundle).get(bundle_id)
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
		product_id = int(row.product_id)
		store_id = int(row.store_id)
		price = _effective_price(row.member_price, row.sale_price, row.base_price)
		if price is None:
			continue

		entry = {
			"product_id": product_id,
			"store_id": store_id,
			"product_name": str(row.name),
			"brand": str(row.brand),
			"price": float(price),
		}
		by_product[product_id].append(entry)

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
		schemas.PlanStoreSummary(
			store_id=sid,
			item_count=data["item_count"],
			total=round(data["total"], 2),
		)
		for sid, data in sorted(split_store_accumulator.items(), key=lambda x: x[1]["total"])
	]

	single_store_candidates = []
	for sid, data in by_store_totals.items():
		coverage = len(data["products"])
		if coverage == item_count:
			single_store_candidates.append((sid, data["total"]))

	single_store_best = None
	if single_store_candidates:
		sid, total = min(single_store_candidates, key=lambda x: x[1])
		single_store_best = schemas.SingleStorePlan(store_id=sid, total=round(total, 2))

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
async def log_bundle_visit(bundle_id: int, payload: schemas.VisitCreateRequest, sess: Session = Depends(get_db)):
	bundle = sess.query(models.Product_Bundle).get(bundle_id)
	if not bundle:
		raise HTTPException(404, detail=f"Bundle with id {bundle_id} not found")

	if payload.store_id is not None:
		store = sess.query(models.Store).get(payload.store_id)
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

