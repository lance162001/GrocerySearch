"""Wegmans scraper — uses the Algolia search API behind wegmans.com."""

from __future__ import annotations

import json
import logging
from typing import Optional
from urllib.request import Request, urlopen

from sqlalchemy.orm import Session

from models import Product, Product_Instance, PricePoint, Tag_Instance
from .utils import (
    CANONICAL_CATEGORIES,
    DIET_TYPES,
    DEFAULT_USER_AGENT,
    extract_size_and_clean_name,
)

logger = logging.getLogger(__name__)

_WG_COMPANY_ID = 3

_ALGOLIA_APP_ID = "QGPPR19V8V"
_ALGOLIA_API_KEY = "9a10b1401634e9a6e55161c3a60c200d"
_ALGOLIA_URL = (
    f"https://{_ALGOLIA_APP_ID.lower()}-dsn.algolia.net/1/indexes/*/queries"
    f"?x-algolia-api-key={_ALGOLIA_API_KEY}"
    f"&x-algolia-application-id={_ALGOLIA_APP_ID}"
)

_PAGE_SIZE = 100

WG_FALLBACK_IMAGE = (
    "https://upload.wikimedia.org/wikipedia/commons/thumb/4/43/"
    "Wegmans_logo.svg/1200px-Wegmans_logo.svg.png"
)

# Mapping from Wegmans Algolia facet department names to canonical categories.
_DEPARTMENT_MAP: dict[str, str] = {
    "Produce": "produce",
    "Dairy": "dairy-eggs",
    "Meat": "meat",
    "Deli & Meals": "prepared-foods",
    "Prepared Foods": "prepared-foods",
    "Pantry": "pantry",
    "Bakery": "bakery",
    "Desserts": "desserts",
    "Frozen": "frozen",
    "Snacks": "snacks",
    "Seafood": "seafood",
    "Beverages": "beverages",
}


def scrape_wegmans(
    store_id: int,
    store_code: int,
    sess: Session,
    tags: dict[str, int],
    collector: Optional[dict] = None,
) -> None:
    """Scrape all products for a single Wegmans store and persist results."""
    if collector is None:
        collector = {"products": [], "product_instances": [], "price_points": []}

    raw_products = _fetch_all_products(store_code)

    for raw in raw_products:
        _persist_product(raw, store_id, sess, tags, collector)

    sess.commit()


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _build_request_body(store_code: int, query: str, page: int) -> dict:
    """Build the Algolia multi-query request body for a given page."""
    filters = (
        f"storeNumber:{store_code} AND fulfilmentType:instore "
        f"AND excludeFromWeb:false AND isSoldAtStore:true"
    )
    return {
        "requests": [
            {
                "indexName": "products",
                "analytics": False,
                "attributesToHighlight": [],
                "clickAnalytics": False,
                "facets": ["department"],
                "filters": filters,
                "hitsPerPage": _PAGE_SIZE,
                "page": page,
                "query": query,
            }
        ]
    }


def _fetch_all_products(store_code: int) -> list[dict]:
    """Page through the Algolia API and return de-duped product dicts."""
    products: list[dict] = []
    seen_skus: set[str] = set()
    page = 0

    while True:
        body = _build_request_body(store_code, "", page)
        try:
            json_bytes = json.dumps(body).encode("utf-8")
            req = Request(_ALGOLIA_URL, json_bytes)
            req.add_header("User-Agent", DEFAULT_USER_AGENT)
            req.add_header("Content-Type", "application/json")
            req.add_header("Origin", "https://www.wegmans.com")
            req.add_header("Referer", "https://www.wegmans.com/")
            response = urlopen(req)
            result = json.loads(response.read())["results"][0]
            hits = result.get("hits", [])
        except Exception as exc:
            logger.warning("Wegmans fetch failed (page=%d): %s", page, exc)
            break

        if not hits:
            break

        for hit in hits:
            sku = hit.get("sku") or hit.get("objectID", "")
            if sku and sku not in seen_skus:
                seen_skus.add(sku)
                products.append(hit)

        logger.debug("Wegmans page=%d fetched=%d total=%d", page, len(hits), len(products))

        nb_pages = result.get("nbPages", 0)
        page += 1
        if page >= nb_pages:
            break

    return products


def _persist_product(
    raw: dict,
    store_id: int,
    sess: Session,
    tags: dict[str, int],
    collector: dict,
) -> None:
    """Upsert a single Wegmans product + instance + price-point."""
    raw_full_name = str(raw.get("name", "") or raw.get("productName", ""))
    if not raw_full_name:
        return

    size, cleaned_name = extract_size_and_clean_name(raw_full_name)
    cleaned_name = cleaned_name.title()

    prod = sess.query(Product).filter(
        Product.raw_name == raw_full_name,
        Product.company_id == _WG_COMPANY_ID,
    ).first()

    images = raw.get("images") or []
    image = images[0] if images else WG_FALLBACK_IMAGE

    if prod is None:
        brand = (raw.get("consumerBrandName") or raw.get("brand") or "Wegmans").title()

        prod = Product(
            company_id=_WG_COMPANY_ID,
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
        tag_instances: list[Tag_Instance] = []
        name_lower = raw_full_name.lower()
        for diet in DIET_TYPES:
            if diet in name_lower:
                tag_instances.append(Tag_Instance(product_id=prod.id, tag_id=tags[diet]))

        popular_tags = raw.get("popularTags") or []
        for ptag in popular_tags:
            tag_id = tags.get(ptag.lower())
            if tag_id is not None:
                tag_instances.append(Tag_Instance(product_id=prod.id, tag_id=tag_id))

        # Department → canonical category tag
        department = raw.get("department", "")
        canonical = _DEPARTMENT_MAP.get(department)
        if canonical and canonical in tags:
            tag_instances.append(Tag_Instance(product_id=prod.id, tag_id=tags[canonical]))

        sess.add_all(tag_instances)

    # Update thumbnail if it's still the fallback
    if prod.picture_url == WG_FALLBACK_IMAGE and image != WG_FALLBACK_IMAGE:
        prod.picture_url = image

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

    # Record a new price point
    instore = raw.get("price_inStore") or {}
    loyalty = raw.get("price_inStoreLoyalty") or {}
    base_price = instore.get("amount")
    sale_price = None
    member_price = loyalty.get("amount") if loyalty else None

    # When a loyalty discount exists, the regular price is the base and
    # the loyalty price acts as a sale/member price.
    if member_price and base_price and member_price < base_price:
        sale_price = member_price
        member_price = None

    # Use the size extracted from the name; fall back to Algolia field
    if size == "N/A":
        size = raw.get("packSize") or "N/A"

    pricepoint = PricePoint(
        base_price=base_price,
        sale_price=sale_price,
        member_price=member_price,
        size=size,
        instance_id=inst.id,
    )
    collector["price_points"].append(pricepoint)
    sess.add(pricepoint)
    # Commit per-product so the write lock is released between products,
    # allowing concurrent scraper threads (WF, TJ) to interleave writes.
    sess.commit()
