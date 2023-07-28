from .products import Product
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime



# class Store(BaseModel):
#     id: Optional[int]
#     last_updated: Optional[datetime]
#     brand: str
#     address: str
#     zipcode: str
#     products: List[Product] = []

#     class Config:
#         orm_mode = True # lets pydantic convert SQLAlchemy object <-> JSON


class Company(BaseModel):
	id: Optional[int]
	logo_url: str
	name: str

class Store(BaseModel):
	id: Optional[int]
	company_id: int
	scraper_id: int
	address: str
	zipcode: str
	class Config:
		orm_mode = True # lets pydantic convert SQLAlchemy object <-> JSON
