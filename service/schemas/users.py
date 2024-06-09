from .products import Product
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime

class User(BaseModel):
	id: Optional[int]
	recent_zipcode: str
	class Config:
		from_attributes = True # lets pydantic convert SQLAlchemy object <-> JSON

class Saved_Store(BaseModel):
	store_id: str
	member: bool
	user_id: str
	class Config:
		from_attributes = True # lets pydantic convert SQLAlchemy object <-> JSON

class Saved_Product(BaseModel):
	product_id: str
	bundle_id: str
	class Config:
		from_attributes = True # lets pydantic convert SQLAlchemy object <-> JSON

class Product_Bundle(BaseModel):
	id: str
	user_id: str
	name: str
	date_created: Optional[datetime]
	products: List[Saved_Product] = []
	class Config:
		from_attributes = True # lets pydantic convert SQLAlchemy object <-> JSON

class Store_Visit(BaseModel):
	store_id: str
	product_bundle_id: str
	date_visited: Optional[datetime]
	class Config:
		from_attributes = True # lets pydantic convert SQLAlchemy object <-> JSON