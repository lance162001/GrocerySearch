from .products import Product
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime



class Store(BaseModel):
    id: Optional[int]
    last_updated: datetime
    company: str
    address: str
    zipcode: str
    products: List[Product] = []

    class Config:
        orm_mode = True # lets pydantic convert SQLAlchemy object <-> JSON