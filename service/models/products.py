import enum
from sqlalchemy import Column, Integer, String, Boolean, DateTime, Enum, ForeignKey
from sqlalchemy.orm import relationship
from .base import Base, BaseModel
from datetime import datetime
from sqlalchemy.orm import relationship


class PricePoint(Base, BaseModel):
    __tablename__ = 'pricepoints'
    product_id = Column(Integer, ForeignKey("products.id"))
    product = relationship("Product", backref="price_history")
    member_price = Column(Integer)
    sale_price = Column(Integer)
    base_price = Column(Integer)
    size = Column(String(50))
    timestamp = Column(DateTime, default=datetime.now())


class Product(Base, BaseModel):
    __tablename__ = 'products'
    name = Column(String(50))
    brand = Column(String(50))
    last_updated = Column(DateTime, default=datetime.now())
    store_id = Column(Integer)
    price_history: relationship("PricePoint", backref="product")
    member_price = Column(Integer)
    sale_price = Column(Integer)
    base_price = Column(Integer)
    size = Column(String(50))
    picture_url = Column(String(255))
    active = Column(Boolean)