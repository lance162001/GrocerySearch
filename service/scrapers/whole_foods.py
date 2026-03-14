"""Whole Foods Market scraper."""

from __future__ import annotations

import json
import logging
from typing import Optional
from urllib.request import Request, urlopen

from sqlalchemy.orm import Session

from models import Product, Product_Instance, PricePoint, Tag_Instance
from .utils import (
    WF_CATEGORIES,
    CANONICAL_CATEGORIES,
    DIET_TYPES,
    DEFAULT_USER_AGENT,
    extract_size_and_clean_name,
)

logger = logging.getLogger(__name__)

WF_FALLBACK_IMAGE = (
    "https://external-content.duckduckgo.com/iu/?u=http%3A%2F%2Fwww.sott.net"
    "%2Fimage%2Fimage%2Fs5%2F102602%2Ffull%2Fwholefoods.png&f=1&nofb=1"
)
_WF_COMPANY_ID = 1
_PAGE_SIZE = 60


def scrape_whole_foods(
    store_id: int,
    store_code: int,
    sess: Session,
    tags: dict[str, int],
    collector: Optional[dict] = None,
) -> None:
    """Scrape every category for a single Whole Foods store and persist results."""
    if collector is None:
        collector = {"products": [], "product_instances": [], "price_points": []}

    slugs: set[str] = set()

    for category in WF_CATEGORIES:
        raw_products = _fetch_category(store_code, category, slugs)
        for raw in raw_products:
            _persist_product(raw, category, store_id, sess, tags, collector)

    sess.commit()


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _fetch_category(store_code: int, category: str, seen_slugs: set[str]) -> list[dict]:
    """Page through the WF API for *category* and return de-duped raw dicts."""
    base_url = (
        f"https://www.wholefoodsmarket.com/api/products/category/{category}"
        f"?leafCategory={category}&store={store_code}&limit={_PAGE_SIZE}&offset="
    )
    products: list[dict] = []
    offset = 0

    while True:
        try:
            req = Request(base_url + str(offset))
            req.add_header("User-Agent", DEFAULT_USER_AGENT)
            response = urlopen(req)
            results = json.loads(response.read()).get("results", [])
        except Exception as exc:
            logger.warning("WF fetch failed (category=%s, offset=%d): %s", category, offset, exc)
            break

        if not results:
            break

        for item in results:
            slug = item.get("slug")
            if slug and slug not in seen_slugs:
                seen_slugs.add(slug)
                products.append(item)

        logger.debug("WF category=%s offset=%d fetched=%d", category, offset, len(results))
        offset += _PAGE_SIZE

    return products


def _persist_product(
    raw: dict,
    category: str,
    store_id: int,
    sess: Session,
    tags: dict[str, int],
    collector: dict,
) -> None:
    """Upsert a single product + instance + price-point from raw API data."""
    raw_full_name = str(raw.get("name", ""))
    size, cleaned_name = extract_size_and_clean_name(raw_full_name)

    # Edge-case fixup carried over from original logic
    brand_raw = raw.get("brand", "")
    if cleaned_name.startswith("PB") and brand_raw == "Renpure" and len(cleaned_name) >= 5:
        size = cleaned_name[-5]

    cleaned_name = cleaned_name.title()

    prod = sess.query(Product).filter(Product.raw_name == raw_full_name).first()

    if prod is None:
        brand = (brand_raw or "Whole Foods Market").title()
        image = raw.get("imageThumbnail", WF_FALLBACK_IMAGE)

        prod = Product(
            company_id=_WF_COMPANY_ID,
            raw_name=raw_full_name,
            name=cleaned_name,
            brand=brand,
            picture_url=image,
            tags=[],
        )
        collector["products"].append(prod)
        sess.add(prod)
        sess.flush()

        # Diet / characteristic tags
        name_lower = raw_full_name.lower()
        tag_instances = []
        for diet in DIET_TYPES:
            if diet in name_lower:
                tag_instances.append(Tag_Instance(product_id=prod.id, tag_id=tags[diet]))

        if raw.get("isLocal"):
            tag_instances.append(Tag_Instance(product_id=prod.id, tag_id=tags["local"]))

        # Category tag
        cat_index = WF_CATEGORIES.index(category)
        tag_instances.append(
            Tag_Instance(product_id=prod.id, tag_id=tags[CANONICAL_CATEGORIES[cat_index]])
        )
        sess.add_all(tag_instances)

    # Upsert product instance
    inst = (
        sess.query(Product_Instance)
        .filter(Product_Instance.store_id == store_id, Product_Instance.product_id == prod.id)
        .first()
    )
    if inst is None:
        inst = Product_Instance(store_id=store_id, product_id=prod.id)
        collector["product_instances"].append(inst)
        sess.add(inst)
        sess.flush()

    # Always record a new price point
    pricepoint = PricePoint(
        base_price=raw.get("regularPrice"),
        sale_price=raw.get("salePrice"),
        member_price=raw.get("incrementalSalePrice"),
        size=size,
        instance_id=inst.id,
    )
    collector["price_points"].append(pricepoint)
    sess.add(pricepoint)
    # Commit per-product so the write lock is released between products,
    # allowing concurrent scraper threads (WG, TJ) to interleave writes.
    sess.commit()
