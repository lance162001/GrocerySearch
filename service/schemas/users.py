from .products import Product
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime

class User(BaseModel):
	id: Optional[int]
	recent_zipcode: str
	class Config:
		from_attributes = True # lets pydantic convert SQLAlchemy object <-> JSON

class Saved_Store(BaseModel):
	store_id: str
	member: bool
	user_id: str
	class Config:
		from_attributes = True # lets pydantic convert SQLAlchemy object <-> JSON

class Saved_Product(BaseModel):
	product_id: str
	bundle_id: str
	class Config:
		from_attributes = True # lets pydantic convert SQLAlchemy object <-> JSON

class Product_Bundle(BaseModel):
	id: str
	user_id: str
	name: str
	date_created: Optional[datetime]
	products: List[Saved_Product] = []
	class Config:
		from_attributes = True # lets pydantic convert SQLAlchemy object <-> JSON

class Store_Visit(BaseModel):
	store_id: str
	product_bundle_id: str
	date_visited: Optional[datetime]
	class Config:
		from_attributes = True # lets pydantic convert SQLAlchemy object <-> JSON


class BundleCreateRequest(BaseModel):
	name: str


class BundleProductAddRequest(BaseModel):
	product_id: int


class SavedStoreUpsertRequest(BaseModel):
	store_id: int
	member: bool = False


class BundleSummary(BaseModel):
	id: int
	user_id: int
	name: str
	created_at: Optional[datetime]


class SavedStoreSummary(BaseModel):
	store_id: int
	member: bool
	user_id: int


class PlanProductLine(BaseModel):
	product_id: int
	product_name: str
	brand: str
	best_store_id: int
	best_price: float


class PlanStoreSummary(BaseModel):
	store_id: int
	item_count: int
	total: float


class SingleStorePlan(BaseModel):
	store_id: int
	total: float


class BundlePlanResponse(BaseModel):
	bundle_id: int
	bundle_name: str
	item_count: int
	missing_product_ids: List[int]
	single_store_best: Optional[SingleStorePlan]
	split_store_total: float
	split_by_store: List[PlanStoreSummary]
	lines: List[PlanProductLine]
	estimated_savings_vs_best_single: Optional[float]


class VisitCreateRequest(BaseModel):
	store_id: Optional[int] = None


class VisitResponse(BaseModel):
	id: int
	bundle_id: int
	user_id: int
	created_at: Optional[datetime]
	store_id: Optional[int] = None