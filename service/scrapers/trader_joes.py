"""Trader Joe's scraper."""

from __future__ import annotations

import json
import logging
from typing import Optional
from urllib.request import Request, urlopen

from sqlalchemy.orm import Session

from models import Product, Product_Instance, PricePoint, Store, Tag_Instance
from .utils import (
    TJ_CATEGORIES,
    CANONICAL_CATEGORIES,
    DEFAULT_USER_AGENT,
    extract_size_and_clean_name,
)

logger = logging.getLogger(__name__)

_TJ_COMPANY_ID = 2

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

    raw_products = _fetch_all_products(store_code)

    for raw in raw_products:
        _persist_product(raw, store_id, sess, tags, collector)

    sess.commit()


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

def _fetch_all_products(store_code: int) -> list[dict]:
    """Page through the TJ GraphQL API and return all product dicts."""
    headers = {
        "User-Agent": DEFAULT_USER_AGENT,
        "Host": "www.traderjoes.com",
        "Origin": "https://www.traderjoes.com",
    }
    url = "https://www.traderjoes.com/api/graphql"
    body = {
        "operationName": "SearchProducts",
        "query": _TJ_GRAPHQL_QUERY,
        "variables": {
            "availability": "1",
            "categoryId": 8,
            "characteristics": [],
            "currentPage": 0,
            "pageSize": 100,
            "published": "1",
            "storeCode": str(store_code),
        },
    }

    products: list[dict] = []
    while True:
        try:
            json_bytes = json.dumps(body).encode("utf-8")
            req = Request(url, json_bytes, headers)
            response = urlopen(req)
            items = json.loads(response.read())["data"]["products"]["items"]
        except Exception as exc:
            logger.warning("TJ fetch failed (page=%d): %s", body["variables"]["currentPage"], exc)
            break

        if not items:
            break

        products.extend(items)
        logger.debug("TJ page=%d fetched=%d", body["variables"]["currentPage"], len(items))
        body["variables"]["currentPage"] += 1

    return products


def _persist_product(
    raw: dict,
    store_id: int,
    sess: Session,
    tags: dict[str, int],
    collector: dict,
) -> None:
    """Upsert a single TJ product + instance + price-point."""
    name = raw.get("item_title", "")

    prod = sess.query(Product).filter(Product.name == name, Product.company_id == _TJ_COMPANY_ID).first()

    if prod is None:
        prod = Product(
            brand="Trader Joes",
            name=name,
            company_id=_TJ_COMPANY_ID,
            picture_url=f"traderjoes.com{raw.get('primary_image', '')}",
        )
        collector["products"].append(prod)
        sess.add(prod)
        sess.flush()

        # Characteristic tags
        tag_instances = []
        characteristics = raw.get("item_characteristics") or []
        for char in characteristics:
            tag_id = tags.get(char.lower())
            if tag_id is not None:
                tag_instances.append(Tag_Instance(product_id=prod.id, tag_id=tag_id))

        # Category tag
        try:
            hierarchy_name = raw["category_hierarchy"][2]["name"]
        except (KeyError, IndexError):
            hierarchy_name = ""

        for index, tj_cat in enumerate(TJ_CATEGORIES):
            if isinstance(tj_cat, list):
                if hierarchy_name in tj_cat:
                    tag_instances.append(
                        Tag_Instance(product_id=prod.id, tag_id=tags[CANONICAL_CATEGORIES[index]])
                    )
            elif hierarchy_name == tj_cat:
                tag_instances.append(
                    Tag_Instance(product_id=prod.id, tag_id=tags[CANONICAL_CATEGORIES[index]])
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

    pricepoint = PricePoint(
        base_price=raw.get("retail_price"),
        sale_price=None,
        member_price=None,
        size=f"{raw.get('sales_size', '')} {raw.get('sales_uom_description', '')}".strip(),
        instance_id=inst.id,
    )
    collector["price_points"].append(pricepoint)
    sess.add(pricepoint)
