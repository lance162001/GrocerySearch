from typing import Optional
from pydantic import BaseModel


class PriceComparison(BaseModel):
    chain: str
    company_id: int
    price: float
    is_best: bool
    diff_from_best: Optional[float] = None


class FeedPriceReveal(BaseModel):
    type: str = "price_reveal"
    product_id: int
    product_name: str
    brand: str
    size: str
    picture_url: Optional[str] = None
    prices: list[PriceComparison]
    max_savings: float


class FeedSavingsItem(BaseModel):
    product_id: int
    product_name: str
    cheap_chain: str
    expensive_chain: str
    savings: float
    savings_pct: float


class FeedSavingsCard(BaseModel):
    type: str = "savings_ranking"
    items: list[FeedSavingsItem]


class FeedCommunityCard(BaseModel):
    type: str = "community_challenge"
    judgement_type: str  # "grouping" or "staple"
    product_id: int
    product_name: str
    product_brand: str
    staple_name: Optional[str] = None
    target_product_id: Optional[int] = None
    target_product_name: Optional[str] = None
    target_product_brand: Optional[str] = None


class FeedResponse(BaseModel):
    items: list  # mix of card types serialized as dicts
    page: int
    has_more: bool
