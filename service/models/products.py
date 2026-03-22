from datetime import date, datetime

from sqlalchemy import (
    Boolean,
    Column,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    PrimaryKeyConstraint,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import relationship
from .base import Base, BaseModel

class PricePoint(Base, BaseModel):
    __tablename__ = 'price_points'
    __table_args__ = (
        UniqueConstraint('instance_id', 'collected_on', name='uq_price_points_instance_collected_on'),
        Index('ix_price_points_instance_created_at', 'instance_id', 'created_at'),
    )
    member_price = Column(String(10))
    sale_price = Column(String(10))
    base_price = Column(String(10))
    size = Column(String(50))
    created_at = Column(DateTime, default=datetime.now)
    collected_on = Column(Date, nullable=False, default=date.today, index=True)
    instance = relationship('Product_Instance', back_populates="price_points")
    instance_id = Column(Integer, ForeignKey('product_instances.id'), index=True)

class Product(Base,BaseModel):
    __tablename__ = 'products'
    __table_args__ = (
        UniqueConstraint('company_id', 'raw_name', name='uq_products_company_raw_name'),
        Index('ix_products_company_name', 'company_id', 'name'),
    )
    raw_name = Column(String(300), index=True)
    name = Column(String(200), index=True)
    brand = Column(String(100))
    company_id = Column(Integer, ForeignKey("companies.id"), index=True)
    picture_url = Column(String(500))
    variation_group = Column(String(200), nullable=True, index=True)
    tags = relationship('Tag_Instance', back_populates='product')
    
class Product_Instance(Base, BaseModel):
    __tablename__ = 'product_instances'
    __table_args__ = (
        UniqueConstraint('store_id', 'product_id', name='uq_product_instances_store_product'),
    )
    store_id = Column(Integer, ForeignKey("stores.id"), index=True)
    product_id = Column(Integer, ForeignKey("products.id"), index=True)
    price_points = relationship('PricePoint', back_populates="instance")

class Tag(Base,BaseModel):
    __tablename__ = 'tags'
    name = Column(String(50), unique=True, index=True)

class Tag_Instance(Base, BaseModel):
    __tablename__ = 'tag_instances'
    __table_args__ = (
        UniqueConstraint('product_id', 'tag_id', name='uq_tag_instances_product_tag'),
    )
    product_id = Column(Integer, ForeignKey('products.id'), index=True)
    product = relationship("Product", back_populates='tags')
    tag_id = Column(Integer, ForeignKey("tags.id"), index=True)


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