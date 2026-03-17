from .products import PricePoint, Product_Instance
from pydantic import BaseModel, ConfigDict
from typing import Optional, List
from datetime import datetime


class User(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: Optional[int] = None
    recent_zipcode: str


class Saved_Store(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    store_id: int
    member: bool
    user_id: int


class Saved_Product(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    product_id: int
    bundle_id: int


class Product_Bundle(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    user_id: int
    name: str
    date_created: Optional[datetime] = None
    products: List[Saved_Product] = []


class Store_Visit(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    store_id: int
    product_bundle_id: int
    date_visited: Optional[datetime] = None


class BundleCreateRequest(BaseModel):
    name: str


class LookupOrCreateRequest(BaseModel):
    firebase_uid: str


class BundleProductAddRequest(BaseModel):
    product_id: int


class SavedStoreUpsertRequest(BaseModel):
    store_id: int
    member: bool = False


class BundleSummary(BaseModel):
    id: int
    user_id: int
    name: str
    created_at: Optional[datetime] = None


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
    single_store_best: Optional[SingleStorePlan] = None
    split_store_total: float
    split_by_store: List[PlanStoreSummary]
    lines: List[PlanProductLine]
    estimated_savings_vs_best_single: Optional[float] = None


class VisitCreateRequest(BaseModel):
    store_id: Optional[int] = None


class VisitResponse(BaseModel):
    id: int
    bundle_id: int
    user_id: int
    created_at: Optional[datetime] = None
    store_id: Optional[int] = None


class BundleProductDetail(BaseModel):
    """A product inside a bundle, with its latest price points across stores."""
    model_config = ConfigDict(from_attributes=True)

    product_id: int
    name: str
    brand: str
    picture_url: str
    instances: List[Product_Instance] = []


class BundleDetailResponse(BaseModel):
    """Full bundle detail including every product and its price points."""
    id: int
    user_id: int
    name: str
    created_at: Optional[datetime] = None
    product_count: int
    products: List[BundleProductDetail] = []


class BundleSummaryWithProducts(BaseModel):
    """Bundle summary returned when listing a user's bundles (includes product count)."""
    id: int
    user_id: int
    name: str
    created_at: Optional[datetime] = None
    product_count: int
    product_ids: List[int] = []


class UserDashboard(BaseModel):
    user_id: int
    recent_zipcode: str
    bundle_count: int
    saved_store_count: int
    visit_count: int