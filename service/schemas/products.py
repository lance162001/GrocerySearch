from datetime import datetime
from typing import Optional, List

from pydantic import BaseModel

class PricePoint(BaseModel):
    base_price: int
    sale_price: int
    member_price: int
    size: str
    timestamp: datetime

class Product(BaseModel):
    id: Optional[int]
    last_updated: datetime
    name: str
    store_id = int
    price_history: List[PricePoint] = []
    member_price: int
    sale_price: int
    base_price: int
    size: str
    picture_url: str
    active: bool

    class Config:
        orm_mode = True # lets pydantic convert SQLAlchemy object <-> JSON