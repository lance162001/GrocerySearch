from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from .base import Base, BaseModel
from datetime import datetime

# class Store(Base, BaseModel):
#     __tablename__ = 'stores'
#     brand = Column(String(20))
#     address = Column(String(50))
#     zipcode = Column(String(5))
#     products = relationship("Product", backref="store")


class Store(Base, BaseModel):
    __tablename__ = 'stores'
    address = Column(String(50))
    zipcode = Column(String(5))
    company_id = Column(Integer, ForeignKey("companies.id"))
    scraper_id = Column(Integer)

class Company(Base, BaseModel):
    __tablename__ = 'companies'
    logo_url = Column(String(255))
    name = Column(String(100))

