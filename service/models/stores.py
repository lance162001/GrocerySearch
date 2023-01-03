from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from .base import Base, BaseModel
from datetime import datetime

class Store(Base, BaseModel):
    __tablename__ = 'stores'
    last_updated = Column(DateTime, default=datetime.now())
    name = Column(String(50))
    brand = Column(String(50))
    state = Column(String(50))
    town = Column(String(50))
    address = Column(String(50))
    products = relationship("Product", backref="store")
    active = Column(Boolean)