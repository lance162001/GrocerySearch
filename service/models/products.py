from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey, PrimaryKeyConstraint
from sqlalchemy.orm import relationship
from .base import Base, BaseModel
from datetime import datetime

class PricePoint(Base, BaseModel):
    __tablename__ = 'price_points'
    member_price = Column(Integer)
    sale_price = Column(Integer)
    base_price = Column(Integer)
    size = Column(String(50))
    created_at = Column(DateTime, default=datetime.now())
    instance = relationship('Product_Instance', back_populates="price_points")
    instance_id = Column(Integer, ForeignKey('product_instances.id'))

class Product(Base,BaseModel):
    __tablename__ = 'products'
    name = Column(String(100))
    brand = Column(String(100))
    company_id = Column(Integer, ForeignKey("companies.id"))
    picture_url = Column(String(255))
    tags = relationship('Tag_Instance', back_populates='product')
    
class Product_Instance(Base, BaseModel):
    __tablename__ = 'product_instances'
    store_id = Column(Integer, ForeignKey("stores.id"))
    product_id = Column(Integer, ForeignKey("products.id"))
    price_points = relationship('PricePoint', back_populates="instance")

class Tag(Base,BaseModel):
    __tablename__ = 'tags'
    name = Column(String(50))

class Tag_Instance(Base, BaseModel):
    __tablename__ = 'tag_instances'
    product_id = Column(Integer, ForeignKey('products.id'))
    product = relationship("Product", back_populates='tags')
    tag_id = Column(Integer, ForeignKey("tags.id"))