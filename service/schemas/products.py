from datetime import datetime
from typing import Optional, List

from pydantic import BaseModel, ConfigDict


class PricePoint(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    base_price: str
    sale_price: Optional[str] = None
    member_price: Optional[str] = None
    size: Optional[str] = None
    created_at: Optional[datetime] = None


class Tag(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: Optional[int] = None
    name: str


class Tag_Instance(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    tag_id: int


class Product(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: Optional[int] = None
    brand: str
    name: str
    company_id: int
    picture_url: str
    variation_group: Optional[str] = None
    tags: List[Tag_Instance] = []


class Product_Instance(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    store_id: int
    price_points: List[PricePoint] = []


class Product_Details(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    Product: Product
    Product_Instance: Product_Instance


class JudgementRequest(BaseModel):
    user_id: int
    product_id: int
    judgement_type: str  # 'staple' or 'grouping'
    staple_name: Optional[str] = None
    target_product_id: Optional[int] = None
    approved: bool
    flavour: Optional[str] = None


class JudgementResponse(BaseModel):
    id: int
    user_id: int
    product_id: int
    judgement_type: str
    staple_name: Optional[str] = None
    target_product_id: Optional[int] = None
    approved: bool
    flavour: Optional[str] = None
    created_at: Optional[datetime] = None


class JudgementCandidate(BaseModel):
    """A product presented for staple or grouping judgement."""
    product: Product
    staple_name: Optional[str] = None
    target_product: Optional[Product] = None
    heuristic_score: Optional[float] = None


class StapleJudgementSummary(BaseModel):
    """Aggregated staple judgement for a product."""
    product_id: int
    staple_name: str
    approvals: int
    denials: int


class GroupingJudgementSummary(BaseModel):
    """Aggregated grouping judgement for a product pair."""
    product_id: int
    target_product_id: int
    approvals: int
    denials: int


class StapleHeuristic(BaseModel):
    """Predicted staple score for a product inferred from existing labels."""
    product_id: int
    staple_name: str
    score: float