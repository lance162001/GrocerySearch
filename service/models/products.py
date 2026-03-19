from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey, PrimaryKeyConstraint, Text
from sqlalchemy.orm import relationship
from .base import Base, BaseModel
from datetime import datetime

class PricePoint(Base, BaseModel):
    __tablename__ = 'price_points'
    member_price = Column(String(10))
    sale_price = Column(String(10))
    base_price = Column(String(10))
    size = Column(String(50))
    created_at = Column(DateTime, default=datetime.now)
    instance = relationship('Product_Instance', back_populates="price_points")
    instance_id = Column(Integer, ForeignKey('product_instances.id'))

class Product(Base,BaseModel):
    __tablename__ = 'products'
    raw_name = Column(String(300))
    name = Column(String(200))
    brand = Column(String(100))
    company_id = Column(Integer, ForeignKey("companies.id"))
    picture_url = Column(String(500))
    variation_group = Column(String(200), nullable=True, index=True)
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
    product_id = Column(Integer, ForeignKey('products.id'), index=True)
    product = relationship("Product", back_populates='tags')
    tag_id = Column(Integer, ForeignKey("tags.id"))


class LabelJudgement(Base, BaseModel):
    __tablename__ = 'label_judgements'
    user_id = Column(Integer, ForeignKey('users.id'), index=True)
    product_id = Column(Integer, ForeignKey('products.id'), index=True)
    judgement_type = Column(String(20))  # 'staple' or 'grouping'
    staple_name = Column(String(50), nullable=True)  # which staple category (e.g. 'milk')
    target_product_id = Column(Integer, ForeignKey('products.id'), nullable=True)
    approved = Column(Boolean, nullable=False)
    flavour = Column(String(50), nullable=True)  # 'flavour' when grouping is a flavor/variation
    created_at = Column(DateTime, default=datetime.now)


class StapleStoreCache(Base):
    """Per-(store, staple) cache of ranked product candidates.

    ``ranked_json`` is a JSON array of objects::

        [{"product_id": 123, "score": 0.35, "variation_group": "..."}, ...]

    ordered best-first (lowest score = best match).  Denied products are
    excluded at write time so serving only needs to merge + dedup.
    ``computed_at`` allows staleness checks at serve time.
    """
    __tablename__ = "staple_store_cache"
    __table_args__ = (
        PrimaryKeyConstraint("store_id", "staple_name"),
    )
    store_id = Column(Integer, ForeignKey("stores.id"), nullable=False)
    staple_name = Column(String(64), nullable=False)
    ranked_json = Column(Text, nullable=False, default="[]")
    computed_at = Column(DateTime, default=datetime.utcnow)