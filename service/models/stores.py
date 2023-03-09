from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from .base import Base, BaseModel
from datetime import datetime

class StoreBrands(str, enum.Enum):
    wf = 'Whole Foods',

class StoreBrand(Base):

class Store(Base, BaseModel):
    __tablename__ = 'stores'
    brand = Column(String(20))
    address = Column(String(50))
    zipcode = Column(String(5))
    storewithproducts = Column(Integer, ForeignKey("storewithproducts.id"))

class StoreWithProducts(Base, BaseModel):
    __tablename__ = 'storeswithproducts'
    products = relationship("Product", backref="store")
    store = relationship("Store", backref="storewithproducts")
