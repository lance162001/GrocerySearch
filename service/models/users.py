from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey, PrimaryKeyConstraint
from sqlalchemy.orm import relationship
from .base import Base, BaseModel
from datetime import datetime


class User(Base, BaseModel):
    __tablename__ = 'users'
    recent_zipcode = Column(String(5))

class Saved_Store(Base):
    __tablename__ = 'saved_stores'
    store_id = Column(Integer, ForeignKey("stores.id"))
    member = Column(Boolean)
    user_id = Column(Integer, ForeignKey("users.id"))
    __table_args__ = (PrimaryKeyConstraint("store_id","user_id"), {})

class Saved_Product(Base):
    __tablename__ = 'saved_products'
    product_id = Column(Integer, ForeignKey("products.id"))
    bundle_id = Column(Integer, ForeignKey("product_bundles.id"))
    bundle = relationship("Product_Bundle", back_populates="products")
    __table_args__ = (PrimaryKeyConstraint("product_id","bundle_id"), {})

class Product_Bundle(Base, BaseModel):
    __tablename__ = 'product_bundles'
    user_id = Column(Integer, ForeignKey("users.id"))
    name = Column(String(255))
    created_at = Column(DateTime, default=datetime.now())
    products = relationship("Saved_Product", back_populates="bundle")

class Store_Visit(Base, BaseModel):
    __tablename__ = 'store_visits'
    product_bundle_id = Column(Integer, ForeignKey("product_bundles.id"))
    user_id = Column(Integer, ForeignKey("users.id"))
    created_at = Column(DateTime, default=datetime.now())