from .products import Product
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime

class Company(BaseModel):
	id: Optional[int]
	logo_url: str
	name: str
	class Config:
		orm_mode = True # lets pydantic convert SQLAlchemy object <-> JSON

class Store(BaseModel):
	id: Optional[int]
	company_id: int
	scraper_id: int
	address: str
	town: str
	state: str
	zipcode: str
	class Config:
		orm_mode = True # lets pydantic convert SQLAlchemy object <-> JSON
