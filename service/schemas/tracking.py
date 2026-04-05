"""Pydantic schemas for the price-tracking feature."""

from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, ConfigDict


class TrackRequest(BaseModel):
    user_id: int
    product_id: int


class StorePriceInfo(BaseModel):
    chain: str
    store_id: int
    price: float
    is_best: bool = False


class PriceHistoryPoint(BaseModel):
    timestamp: datetime
    chain: str
    price: float


class TrackedItemResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    user_id: int
    product_id: int
    product_name: str
    brand: str
    picture_url: Optional[str] = None
    company_name: Optional[str] = None
    company_id: Optional[int] = None
    current_price: Optional[float] = None
    previous_price: Optional[float] = None
    price_change: Optional[str] = None  # "drop", "up", or None
    price_change_at: Optional[datetime] = None
    stable_weeks: Optional[int] = None
    cheapest_chain: Optional[str] = None
    cheapest_price: Optional[float] = None
    created_at: Optional[datetime] = None


class TrackedItemDetail(TrackedItemResponse):
    all_store_prices: List[StorePriceInfo] = []
    price_history: List[PriceHistoryPoint] = []


class PointsResponse(BaseModel):
    user_id: int
    points: int = 0
    labels_submitted: int = 0
    accuracy: Optional[float] = None
    monthly_rank: Optional[int] = None
