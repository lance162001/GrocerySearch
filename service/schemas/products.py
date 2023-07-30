from datetime import datetime
from typing import Optional, List

from pydantic import BaseModel

class PricePoint(BaseModel):
	base_price: str
	sale_price: Optional[str]
	member_price: Optional[str]
	size: Optional[str]
	created_at: Optional[datetime]
	class Config:
		orm_mode = True

class Tag(BaseModel):
	id: Optional[int]
	name: str
	class Config:
		orm_mode = True

class Tag_Instance(BaseModel):
	tag_id: int
	class Config:
		orm_mode = True

class Product(BaseModel):
	id: Optional[int]
	brand: str
	name: str
	company_id: int
	picture_url: str
	tags: List[Tag_Instance] = []
	class Config:
		orm_mode = True


class Product_Instance(BaseModel):
	store_id: int
	price_points: List[PricePoint] = []
	class Config:
		orm_mode = True

class Product_Details(BaseModel):
	Product: Product
	Product_Instance: Product_Instance 
	class Config:
		orm_mode = True