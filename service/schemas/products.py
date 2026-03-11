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
    tags: List[Tag_Instance] = []


class Product_Instance(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    store_id: int
    price_points: List[PricePoint] = []


class Product_Details(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    Product: Product
    Product_Instance: Product_Instance