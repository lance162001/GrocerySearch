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
    town = Column(String(50))
    state = Column(String(25))
    zipcode = Column(String(5))
    company_id = Column(Integer, ForeignKey("companies.id"))
    scraper_id = Column(Integer)

class Company(Base, BaseModel):
    __tablename__ = 'companies'
    logo_url = Column(String(255))
    name = Column(String(100))


class StoreSuggestion(Base, BaseModel):
    __tablename__ = 'store_suggestions'
    company_id = Column(Integer, ForeignKey('companies.id'), nullable=False)
    address = Column(String(50))
    town = Column(String(50))
    state = Column(String(25))
    zipcode = Column(String(5))
    status = Column(String(20), default='todo')  # 'todo', 'done', 'rejected'
    created_at = Column(DateTime, default=datetime.now)


class ScraperStatus(Base):
    """Single-row table holding the latest scraper run status."""
    __tablename__ = 'scraper_status'
    id = Column(Integer, primary_key=True, default=1)
    status = Column(String(20))           # idle, running, error
    updated_at = Column(DateTime)
    started_at = Column(DateTime, nullable=True)
    last_finished = Column(DateTime, nullable=True)
    stores_scraped = Column(Integer, nullable=True)
    new_products = Column(Integer, nullable=True)
    new_instances = Column(Integer, nullable=True)
    new_price_points = Column(Integer, nullable=True)
    error = Column(String(500), nullable=True)

