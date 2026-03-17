"""Trader Joe's scraper."""

from __future__ import annotations

import json
import logging
import os
import time
from typing import Optional
from urllib.request import Request, urlopen

from curl_cffi import requests
from sqlalchemy.orm import Session

from models import Product, Product_Instance, PricePoint, Store, Tag_Instance
from .utils import (
    TJ_CATEGORIES,
    TJ_CATEGORY_TO_CANONICAL,
    CANONICAL_CATEGORIES,
    DEFAULT_USER_AGENT,
    extract_size_and_clean_name,
    normalize_size_string,
)

logger = logging.getLogger(__name__)

_TJ_COMPANY_ID = 2
_TJ_PRODUCTS_URL = "https://www.traderjoes.com/home/products"
_TJ_GRAPHQL_URL = "https://www.traderjoes.com/api/graphql"
_TJ_IMPERSONATE_BROWSER = "chrome"
_TJ_PRODUCTS_STATIC_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "static", "products")

_TJ_GRAPHQL_QUERY = """\
query SearchProducts($categoryId: String, $currentPage: Int, $pageSize: Int, \
$characteristics: [String], $storeCode: String, $availability: String = "1", \
$published: String = "1") {
  products(
    filter: {store_code: {eq: $storeCode}, published: {eq: $published}, \
availability: {match: $availability}, category_id: {eq: $categoryId}, \
item_characteristics: {in: $characteristics}}
    sort: {popularity: DESC}
    currentPage: $currentPage
    pageSize: $pageSize
  ) {
    items {
      sku
      item_title
      category_hierarchy { id name __typename }
      primary_image
      primary_image_meta { url metadata __typename }
      sales_size
      sales_uom_description
      price_range {
        minimum_price { final_price { currency value __typename } __typename }
        __typename
      }
      retail_price
      fun_tags
      item_characteristics
      __typename
    }
    total_count
    pageInfo: page_info { currentPage: current_page totalPages: total_pages __typename }
    aggregations { attribute_code label count options { label value count __typename } __typename }
    __typename
  }
}
"""


def scrape_trader_joes(
    store_id: int,
    store_code: int,
    sess: Session,
    tags: dict[str, int],
    collector: Optional[dict] = None,
) -> None:
    """Scrape all products for a single Trader Joe's store."""
    if collector is None:
        collector = {"products": [], "product_instances": [], "price_points": []}

    img_session = requests.Session(impersonate=_TJ_IMPERSONATE_BROWSER)
    try:
        raw_products = _fetch_all_products(store_code, img_session)
        for raw in raw_products:
            _persist_product(raw, store_id, sess, tags, collector, img_session)
        sess.commit()
    finally:
        img_session.close()


def search_for_store(search_term: str, existing_stores: list[Store], sess: Session) -> bool:
    """Look up a TJ store by address/zip and add it if not already present.

    Returns True if a new store was added.
    """
    headers = {"User-Agent": DEFAULT_USER_AGENT}
    url = "https://alphaapi.brandify.com/rest/locatorsearch"
    body = {
        "request": {
            "appkey": "8BC3433A-60FC-11E3-991D-B2EE0C70A832",
            "formdata": {
                "geoip": "false",
                "dataview": "store_default",
                "limit": 1,
                "geolocs": {
                    "geoloc": [{"addressline": search_term, "country": "US", "latitude": "", "longitude": ""}]
                },
                "searchradius": "500",
                "where": {"warehouse": {"distinctfrom": "1"}},
                "false": "0",
            },
        }
    }
    json_bytes = json.dumps(body).encode("utf-8")
    req = Request(url, json_bytes, headers)
    response = urlopen(req)
    results = json.loads(response.read())["collection"][0]

    new_store = Store(
        company_id=_TJ_COMPANY_ID,
        scraper_id=results["clientkey"],
        address=results["address1"],
        state=results["state"],
        town=results["town"],
        zipcode=results["postalcode"],
    )

    if any(s.scraper_id == new_store.scraper_id for s in existing_stores):
        return False

    sess.add(new_store)
    sess.commit()
    return True


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _download_tj_image(sku: str, image_path: str, session: requests.Session) -> Optional[str]:
    """Download a TJ product image and return the local static URL, or None on failure."""
    os.makedirs(_TJ_PRODUCTS_STATIC_DIR, exist_ok=True)
    filename = f"tj_{sku}.png"
    filepath = os.path.join(_TJ_PRODUCTS_STATIC_DIR, filename)
    if os.path.exists(filepath):
        return f"/static/products/{filename}"
    url = f"https://www.traderjoes.com{image_path}"
    try:
        response = session.get(url, timeout=15)
        response.raise_for_status()
        with open(filepath, "wb") as f:
            f.write(response.content)
        return f"/static/products/{filename}"
    except Exception as exc:
        logger.warning("TJ image download failed (sku=%s): %s", sku, exc)
        return None


def _fetch_all_products(store_code: int, session: requests.Session) -> list[dict]:
    """Page through the TJ GraphQL API and return all product dicts."""
    headers = {
        "User-Agent": DEFAULT_USER_AGENT,
        "Content-Type": "application/json",
        "Origin": "https://www.traderjoes.com",
        "Referer": _TJ_PRODUCTS_URL,
    }
    body = {
        "operationName": "SearchProducts",
        "query": _TJ_GRAPHQL_QUERY,
        "variables": {
            "availability": "1",
            "categoryId": 8,
            "characteristics": [],
            "currentPage": 1,
            "pageSize": 100,
            "published": "1",
            "storeCode": str(store_code),
        },
    }

    products: list[dict] = []
    total_pages: int | None = None
    # Akamai blocks non-browser TLS fingerprints on this endpoint, so prime
    # the session with the products page and reuse the impersonated client.
    session.get(_TJ_PRODUCTS_URL, headers={"Referer": "https://www.traderjoes.com/"}, timeout=30)

    while True:
        current_page = body["variables"]["currentPage"]
        data = None
        for attempt in range(3):
            try:
                response = session.post(_TJ_GRAPHQL_URL, headers=headers, json=body, timeout=30)
                response.raise_for_status()
                data = response.json()["data"]["products"]
                break
            except Exception as exc:
                if attempt < 2:
                    time.sleep(2 ** attempt)
                else:
                    logger.warning("TJ fetch failed after 3 attempts (page=%d): %s", current_page, exc)

        if data is None:
            break

        items = data.get("items") or []
        if total_pages is None:
            total_pages = (data.get("pageInfo") or {}).get("totalPages")
            total_count = data.get("total_count", "?")
            logger.info("TJ store=%s: %s products across %s pages", store_code, total_count, total_pages)

        if not items:
            break

        products.extend(items)
        logger.debug("TJ page=%d/%s fetched=%d cumulative=%d", current_page, total_pages, len(items), len(products))

        if total_pages is not None and current_page >= total_pages:
            break
        body["variables"]["currentPage"] += 1

    if total_pages is not None and len(products) == 0:
        logger.warning("TJ store=%s: no products returned", store_code)

    return products


def _persist_product(
    raw: dict,
    store_id: int,
    sess: Session,
    tags: dict[str, int],
    collector: dict,
    img_session: Optional[requests.Session] = None,
) -> None:
    """Upsert a single TJ product + instance + price-point."""
    name = raw.get("item_title", "")
    sku = str(raw.get("sku", ""))
    image_path = raw.get("primary_image", "")

    prod = sess.query(Product).filter(Product.name == name, Product.company_id == _TJ_COMPANY_ID).first()

    is_new = prod is None
    if prod is None:
        if img_session is not None and image_path:
            picture_url = _download_tj_image(sku, image_path, img_session) or f"https://traderjoes.com{image_path}"
        else:
            picture_url = f"https://traderjoes.com{image_path}"
        prod = Product(
            brand="Trader Joes",
            name=name,
            company_id=_TJ_COMPANY_ID,
            picture_url=picture_url,
        )
    elif img_session is not None and image_path and isinstance(prod.picture_url, str) and prod.picture_url.startswith("https://traderjoes.com"):
        local_url = _download_tj_image(sku, image_path, img_session)
        if local_url:
            prod.picture_url = local_url

    if is_new:
        collector["products"].append(prod)
        sess.add(prod)
        sess.flush()

        # Characteristic tags — normalise to lower-case with spaces so strings
        # like "Gluten-Free" and "gluten free" both match the tag keys.
        tag_instances = []
        characteristics = raw.get("item_characteristics") or []
        for char in characteristics:
            normalised = str(char).lower().replace("-", " ").strip()
            tag_id = tags.get(normalised)
            if tag_id is not None:
                tag_instances.append(Tag_Instance(product_id=prod.id, tag_id=tag_id))

        # Category tag — walk the full hierarchy from most-specific to most-general
        # so every product gets a tag even when a leaf name isn't in the map.
        canonical_cat: str | None = None
        for node in reversed(raw.get("category_hierarchy") or []):
            canonical_cat = TJ_CATEGORY_TO_CANONICAL.get(node.get("name", ""))
            if canonical_cat:
                break
        if canonical_cat and canonical_cat in tags:
            tag_instances.append(Tag_Instance(product_id=prod.id, tag_id=tags[canonical_cat]))

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

    raw_size = f"{raw.get('sales_size', '')} {raw.get('sales_uom_description', '')}".strip()
    pricepoint = PricePoint(
        base_price=raw.get("retail_price"),
        sale_price=None,
        member_price=None,
        size=normalize_size_string(raw_size) or raw_size,
        instance_id=inst.id,
    )
    collector["price_points"].append(pricepoint)
    sess.add(pricepoint)
    # Commit per-product so the write lock is released between products,
    # allowing concurrent scraper threads (WF, WG) to interleave writes.
    sess.commit()
