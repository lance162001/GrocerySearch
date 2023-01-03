from .products import Product
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime



class Store(BaseModel):
    id: Optional[int]
    last_updated: datetime
    name: str
    brand: str
    state: str
    town: str
    address: str
    products: List[Product] = []
    active: str


    class Config:
        orm_mode = True # lets pydantic convert SQLAlchemy object <-> JSON