from __future__ import annotations

from datetime import date, datetime

from sqlalchemy.orm import Session

from models import PricePoint, Product, Product_Instance


def ensure_collector_shape(collector: dict) -> dict:
    collector.setdefault("products", [])
    collector.setdefault("product_instances", [])
    collector.setdefault("price_points", [])
    collector.setdefault("stores", [])
    collector.setdefault("companies", [])
    collector.setdefault("updated_price_points", 0)
    return collector


class StorePersistenceCache:
    """Cache store-scoped ORM lookups during scraper ingestion."""

    def __init__(self, sess: Session, store_id: int, company_id: int, collector: dict):
        self.sess = sess
        self.store_id = store_id
        self.company_id = company_id
        self.collector = ensure_collector_shape(collector)
        self.today = date.today()
        self.products_by_raw_name: dict[str, Product] = {}
        self.instances_by_product_id: dict[int, Product_Instance] = {}
        self.price_points_by_instance_id: dict[int, PricePoint] = {}
        self._load_existing()

    @staticmethod
    def product_key(raw_name: str | None, fallback_name: str | None = None) -> str:
        return (raw_name or fallback_name or "").strip().lower()

    def _load_existing(self) -> None:
        rows = (
            self.sess.query(Product, Product_Instance)
            .join(Product_Instance, Product_Instance.product_id == Product.id)
            .filter(
                Product.company_id == self.company_id,
                Product_Instance.store_id == self.store_id,
            )
            .all()
        )

        instance_ids: list[int] = []
        for product, instance in rows:
            key = self.product_key(product.raw_name, product.name)
            if key:
                self.products_by_raw_name[key] = product
            self.instances_by_product_id[int(product.id)] = instance
            instance_ids.append(int(instance.id))

        if not instance_ids:
            return

        todays_points = (
            self.sess.query(PricePoint)
            .filter(
                PricePoint.instance_id.in_(instance_ids),
                PricePoint.collected_on == self.today,
            )
            .order_by(PricePoint.id.desc())
            .all()
        )
        for price_point in todays_points:
            self.price_points_by_instance_id.setdefault(int(price_point.instance_id), price_point)

    def get_product(self, raw_name: str | None, fallback_name: str | None = None) -> Product | None:
        return self.products_by_raw_name.get(self.product_key(raw_name, fallback_name))

    def remember_product(self, product: Product) -> None:
        key = self.product_key(product.raw_name, product.name)
        if key:
            self.products_by_raw_name[key] = product

    def get_instance(self, product_id: int) -> Product_Instance | None:
        return self.instances_by_product_id.get(product_id)

    def remember_instance(self, instance: Product_Instance) -> None:
        self.instances_by_product_id[int(instance.product_id)] = instance

    def upsert_daily_price_point(
        self,
        *,
        instance_id: int,
        base_price: object,
        sale_price: object,
        member_price: object,
        size: str,
    ) -> tuple[PricePoint, bool, bool]:
        price_point = self.price_points_by_instance_id.get(instance_id)
        new_values = {
            "base_price": None if base_price is None else str(base_price),
            "sale_price": None if sale_price in (None, "") else str(sale_price),
            "member_price": None if member_price in (None, "") else str(member_price),
            "size": size,
        }

        if price_point is None:
            price_point = PricePoint(
                instance_id=instance_id,
                collected_on=self.today,
                created_at=datetime.now(),
                **new_values,
            )
            self.sess.add(price_point)
            self.collector["price_points"].append(price_point)
            self.price_points_by_instance_id[instance_id] = price_point
            return price_point, True, False

        changed = any(getattr(price_point, field) != value for field, value in new_values.items())
        if changed:
            for field, value in new_values.items():
                setattr(price_point, field, value)
            price_point.created_at = datetime.now()
            self.collector["updated_price_points"] += 1
        return price_point, False, changed
