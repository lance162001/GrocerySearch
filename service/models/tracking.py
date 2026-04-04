from sqlalchemy import Column, DateTime, ForeignKey, Integer
from sqlalchemy.sql import func

from .base import Base, BaseModel


class Tracked_Item(Base, BaseModel):
    __tablename__ = "tracked_items"
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    product_id = Column(Integer, ForeignKey("products.id"), nullable=False)
    created_at = Column(DateTime, server_default=func.now())


class User_Points(Base, BaseModel):
    __tablename__ = "user_points"
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, unique=True)
    points = Column(Integer, nullable=False, default=0, server_default="0")
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())
