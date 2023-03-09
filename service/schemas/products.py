from datetime import datetime
from typing import Optional, List

from pydantic import BaseModel

class PricePoint(BaseModel):
    base_price: str
    sale_price: str
    member_price: str
    size: str
    last_updated: datetime

    class Config:
        orm_mode = True # lets pydantic convert SQLAlchemy object <-> JSON

class Product(BaseModel):
    id: Optional[int]
    last_updated: datetime
    brand: str
    name: str
    store_id = int
    price_history: List[PricePoint] = []
    member_price: str
    sale_price: str
    base_price: str
    size: str
    picture_url: str

    class Config:
        orm_mode = True # lets pydantic convert SQLAlchemy object <-> JSON