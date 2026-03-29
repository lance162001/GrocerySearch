"""Wegmans scraper — uses the Algolia search API behind wegmans.com."""

from __future__ import annotations

import json
import logging
import os
import re
from typing import Any, Optional, cast
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from sqlalchemy.orm import Session

from models import Product, Product_Instance, Tag_Instance
from .persistence import StorePersistenceCache, snapshot_instance, snapshot_price_point, snapshot_product
from .utils import (
    CANONICAL_CATEGORIES,
    DIET_TYPES,
    DEFAULT_USER_AGENT,
    extract_size_and_clean_name,
    normalize_size_string,
    strip_brand_from_name,
)

logger = logging.getLogger(__name__)

_WG_COMPANY_ID = 3

_ALGOLIA_APP_ID = os.environ.get("ALGOLIA_APP_ID", "QGPPR19V8V")
_ALGOLIA_API_KEY = os.environ["ALGOLIA_API_KEY"]
_ALGOLIA_URL = (
    f"https://{_ALGOLIA_APP_ID.lower()}-dsn.algolia.net/1/indexes/*/queries"
    f"?x-algolia-api-key={_ALGOLIA_API_KEY}"
    f"&x-algolia-application-id={_ALGOLIA_APP_ID}"
)
_ALGOLIA_BROWSE_URL = (
    f"https://{_ALGOLIA_APP_ID.lower()}-dsn.algolia.net/1/indexes/products/browse"
    f"?x-algolia-api-key={_ALGOLIA_API_KEY}"
    f"&x-algolia-application-id={_ALGOLIA_APP_ID}"
)

# Algolia caps paginated search at this many hits per query.
_ALGOLIA_MAX_HITS = 1000
_PAGE_SIZE = 100

_WEGMANS_PREFIX_PATTERN = re.compile(r"^wegmans(?:\s+brand)?\b[\s,:-]*", re.IGNORECASE)
_FAMILY_PACK_SUFFIX_PATTERN = re.compile(r"[\s,:-]*family\s+pack\s*$", re.IGNORECASE)
_SOLD_BY_SUFFIX_PATTERN = re.compile(r"[\s,]+sold\s+by\s+the\s+\w+\s*$", re.IGNORECASE)
_DUPLICATE_WORD_PATTERN = re.compile(r"\b(\w+)\s+\1\b", re.IGNORECASE)

# Maps Wegmans certification strings to canonical tag names.
_CERTIFICATION_TAG_MAP: dict[str, str] = {
    "organic": "organic",
    "usda organic": "organic",
    "certified organic": "organic",
    "kosher": "kosher",
    "kosher certified": "kosher",
    "kosher dairy": "kosher",
    "kosher pareve": "kosher",
    "vegan": "vegan",
    "certified vegan": "vegan",
    "vegetarian": "vegetarian",
    "gluten free": "gluten free",
    "gluten-free": "gluten free",
    "certified gluten free": "gluten free",
    "certified gluten-free": "gluten free",
    "dairy free": "dairy free",
    "dairy-free": "dairy free",
}

WG_FALLBACK_IMAGE = (
    "https://upload.wikimedia.org/wikipedia/commons/thumb/4/43/"
    "Wegmans_logo.svg/1200px-Wegmans_logo.svg.png"
)

# Mapping from Wegmans Algolia facet department/subDepartment names (browse API)
# and categories.lvl0/lvl1 leaf names (search API fallback) to canonical categories.
_DEPARTMENT_MAP: dict[str, str] = {
    # Produce
    "Produce": "produce",
    "Produce & Floral": "produce",
    "Floral": "produce",
    # Dairy / eggs
    "Dairy": "dairy & eggs",
    "Cheese": "dairy & eggs",
    "Eggs": "dairy & eggs",
    # Meat
    "Meat": "meat",
    "Poultry": "meat",
    # Prepared / deli
    "Deli & Meals": "prepared foods",
    "Deli": "prepared foods",
    "Prepared Foods": "prepared foods",
    # Pantry (catch-all for shelf-stable grocery)
    "Pantry": "pantry",
    "International Foods": "pantry",
    "Bulk": "pantry",
    "Organic & Natural": "pantry",
    "Breakfast": "pantry",
    "Soups & Broths": "pantry",
    "Baking & Baking Ingredients": "pantry",
    "Condiments & Sauces": "pantry",
    "Pasta, Grains & Beans": "pantry",
    # Bakery
    "Bakery": "bakery",
    "Breads & Rolls": "bakery",
    # Desserts
    "Desserts": "desserts",
    "Cakes & Pies": "desserts",
    # Frozen
    "Frozen": "frozen",
    # Snacks
    "Snacks": "snacks",
    "Chips & Snack Foods": "snacks",
    "Protein & Snack Bars": "snacks",
    "Candy": "snacks",
    # Seafood
    "Seafood": "seafood",
    # Beverages
    "Beverages": "beverages",
    "Beer & Wine": "beverages",
    "Beer, Wine & Spirits": "beverages",
    "Wine, Beer & Spirits": "beverages",
    "Wine": "beverages",
    "Beer": "beverages",
    "Coffee & Tea": "beverages",
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
    cache = StorePersistenceCache(sess, store_id, _WG_COMPANY_ID, collector)

    raw_products = _fetch_all_products(store_code)

    skipped = 0
    for raw in raw_products:
        try:
            _persist_product(raw, store_id, sess, tags, collector, cache)
        except Exception as exc:
            sess.rollback()
            cache = StorePersistenceCache(sess, store_id, _WG_COMPANY_ID, collector)
            skipped += 1
            logger.warning(
                "Wegmans: skipped product %r due to error: %s",
                raw.get("name", "?")[:80],
                exc,
            )

    if skipped:
        logger.warning("Wegmans store %s: skipped %d products due to errors", store_code, skipped)
    sess.commit()


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _store_filters(store_code: int) -> str:
    return (
        f"storeNumber:{store_code} AND fulfilmentType:instore "
        f"AND excludeFromWeb:false AND isSoldAtStore:true"
    )


def _make_request(url: str, body: dict) -> dict:
    """POST *body* to *url* and return parsed JSON. Propagates HTTP errors."""
    json_bytes = json.dumps(body).encode("utf-8")
    req = Request(url, json_bytes)
    req.add_header("User-Agent", DEFAULT_USER_AGENT)
    req.add_header("Content-Type", "application/json")
    req.add_header("Origin", "https://www.wegmans.com")
    req.add_header("Referer", "https://www.wegmans.com/")
    return json.loads(urlopen(req).read())


def _build_search_body(
    store_code: int, query: str, page: int,
    category_filter: Optional[str] = None,
) -> dict:
    """Build the Algolia multi-query request body for a paginated search."""
    req_obj: dict = {
        "indexName": "products",
        "analytics": False,
        "attributesToHighlight": [],
        "clickAnalytics": False,
        "facets": ["categoryPageId"],
        "filters": _store_filters(store_code),
        "hitsPerPage": _PAGE_SIZE,
        "page": page,
        "query": query,
    }
    if category_filter is not None:
        req_obj["facetFilters"] = [[f"categoryPageId:{category_filter}"]]
    return {"requests": [req_obj]}


def _fetch_all_products(store_code: int) -> list[dict]:
    """Return de-duped products for a store, maximising coverage.

    Strategy:
    1. Try the Algolia Browse API — no pagination cap, returns every record.
    2. If the Browse API is unauthorized, fall back to department-partitioned
       search queries (each capped at _ALGOLIA_MAX_HITS).  Departments with
       more than _ALGOLIA_MAX_HITS products are further split by alpha prefix.
    """
    products: list[dict] = []
    seen_skus: set[str] = set()

    if _fetch_via_browse(store_code, products, seen_skus):
        logger.info("Wegmans: browse API returned %d products", len(products))
        return products

    logger.info("Wegmans: falling back to categoryPageId leaf-partitioned search")
    leaf_categories = _get_leaf_categories(store_code)

    if not leaf_categories:
        logger.warning("Wegmans: no leaf categories found; falling back to blank query (capped at %d)", _ALGOLIA_MAX_HITS)
        _fetch_search_pages(store_code, "", None, products, seen_skus)
        return products

    for cat, count in leaf_categories:
        if count <= _ALGOLIA_MAX_HITS:
            _fetch_search_pages(store_code, "", None, products, seen_skus, category_filter=cat)
        else:
            # Unlikely given 97%+ of leaves are <1000, but sub-partition by letter to be safe.
            logger.info(
                "Wegmans: leaf category '%s' has %d products; sub-partitioning by letter",
                cat,
                count,
            )
            for letter in "abcdefghijklmnopqrstuvwxyz0123456789":
                _fetch_search_pages(store_code, letter, None, products, seen_skus, category_filter=cat)

    logger.info(
        "Wegmans: category-partitioned search returned %d products", len(products)
    )
    return products


def _fetch_via_browse(
    store_code: int, products: list[dict], seen_skus: set[str]
) -> bool:
    """Use the Algolia Browse API (cursor-based, no hit cap) to fetch all products.

    Returns True on success, False if the API is unavailable/unauthorized.
    """
    cursor: Optional[str] = None

    while True:
        body: dict = {
            "query": "",
            "filters": _store_filters(store_code),
            "hitsPerPage": _PAGE_SIZE,
        }
        if cursor:
            body["cursor"] = cursor

        try:
            result = _make_request(_ALGOLIA_BROWSE_URL, body)
        except HTTPError as exc:
            if exc.code in (401, 403):
                logger.info(
                    "Wegmans browse API not authorized (HTTP %d); falling back",
                    exc.code,
                )
                return False
            logger.warning("Wegmans browse API HTTP %d: %s", exc.code, exc)
            # Treat a partial result as a successful-enough run.
            return len(products) > 0
        except Exception as exc:
            logger.warning("Wegmans browse API error: %s", exc)
            return len(products) > 0

        hits = result.get("hits", [])
        for hit in hits:
            sku = hit.get("sku") or hit.get("objectID", "")
            if sku and sku not in seen_skus:
                seen_skus.add(sku)
                products.append(hit)

        logger.debug(
            "Wegmans browse: fetched=%d running_total=%d", len(hits), len(products)
        )
        cursor = result.get("cursor")
        if not cursor or not hits:
            break

    return True


def _get_leaf_categories(store_code: int) -> list[tuple[str, int]]:
    """Return (category_path, count) pairs for leaf-level categories.

    Leaf categories are `categoryPageId` paths that have no child paths in the
    returned facet set — i.e. no other path starts with "<this path> > ".
    Every leaf category has at most *_ALGOLIA_MAX_HITS* products so it can be
    fetched in a single paginated search sequence.
    """
    body = _build_search_body(store_code, "", 0)
    body["requests"][0]["hitsPerPage"] = 0  # only need facet counts
    try:
        result = _make_request(_ALGOLIA_URL, body)["results"][0]
        all_cats: dict[str, int] = result.get("facets", {}).get("categoryPageId", {})
    except Exception as exc:
        logger.warning("Wegmans: failed to fetch category counts: %s", exc)
        return []

    cat_set = set(all_cats)
    leaves = [
        (cat, count)
        for cat, count in all_cats.items()
        if not any(other.startswith(cat + " > ") for other in cat_set)
    ]
    logger.info("Wegmans: found %d leaf categories (from %d total)", len(leaves), len(all_cats))
    return leaves


def _fetch_search_pages(
    store_code: int,
    query: str,
    dept_filter: Optional[str],  # kept for back-compat; ignored — use category_filter
    products: list[dict],
    seen_skus: set[str],
    category_filter: Optional[str] = None,
) -> None:
    """Paginate through Algolia search results (≤ _ALGOLIA_MAX_HITS per query)."""
    page = 0
    while True:
        body = _build_search_body(store_code, query, page, category_filter)
        try:
            result = _make_request(_ALGOLIA_URL, body)["results"][0]
            hits = result.get("hits", [])
        except Exception as exc:
            logger.warning(
                "Wegmans search failed (category=%r, query=%r, page=%d): %s",
                category_filter,
                query,
                page,
                exc,
            )
            break

        if not hits:
            break

        for hit in hits:
            sku = hit.get("sku") or hit.get("objectID", "")
            if sku and sku not in seen_skus:
                seen_skus.add(sku)
                products.append(hit)

        nb_pages = result.get("nbPages", 0)
        page += 1
        if page >= nb_pages:
            break


def _normalize_wegmans_name(name: str) -> str:
    """Strip Wegmans-specific branding markers from a cleaned product name."""
    normalized = _WEGMANS_PREFIX_PATTERN.sub("", name.strip())
    normalized = _FAMILY_PACK_SUFFIX_PATTERN.sub("", normalized)
    normalized = _SOLD_BY_SUFFIX_PATTERN.sub("", normalized)
    normalized = _DUPLICATE_WORD_PATTERN.sub(r"\1", normalized)
    normalized = re.sub(r"\s{2,}", " ", normalized).strip(" ,-/")
    return normalized or name.strip()


def _persist_product(
    raw: dict,
    store_id: int,
    sess: Session,
    tags: dict[str, int],
    collector: dict,
    cache: StorePersistenceCache,
) -> None:
    """Upsert a single Wegmans product + instance + price-point."""
    raw_full_name = str(raw.get("name", "") or raw.get("productName", ""))
    if not raw_full_name:
        return

    size, cleaned_name = extract_size_and_clean_name(raw_full_name)
    cleaned_name = _normalize_wegmans_name(cleaned_name)
    brand_raw = raw.get("consumerBrandName") or raw.get("brand") or "Wegmans"
    # Strip brand prefix from product name so cross-store product matching works.
    cleaned_name = strip_brand_from_name(cleaned_name, brand_raw)
    cleaned_name = cleaned_name.title()

    prod = cache.get_product(raw_full_name, cleaned_name)

    images = raw.get("images") or []
    image = images[0] if images else WG_FALLBACK_IMAGE

    if prod is None:
        brand = brand_raw.title()

        prod = Product(
            company_id=_WG_COMPANY_ID,
            raw_name=raw_full_name,
            name=cleaned_name,
            brand=brand,
            picture_url=image,
            tags=[],
        )
        sess.add(prod)
        sess.flush()
        cache.remember_product(prod)
        created_product = True

        # Diet / characteristic tags
        tag_instances: list[Tag_Instance] = []
        added_tags: set[str] = set()
        # Normalize hyphens so "Gluten-Free" matches the "gluten free" tag.
        name_lower_normalized = raw_full_name.lower().replace("-", " ")
        for diet in DIET_TYPES:
            if diet in name_lower_normalized and diet not in added_tags:
                tag_instances.append(Tag_Instance(product_id=prod.id, tag_id=tags[diet]))
                added_tags.add(diet)

        # popularTags from Algolia — normalize hyphens before lookup.
        popular_tags = raw.get("popularTags") or []
        for ptag in popular_tags:
            normalized = ptag.lower().replace("-", " ")
            tag_id = tags.get(normalized)
            if tag_id is not None and normalized not in added_tags:
                tag_instances.append(Tag_Instance(product_id=prod.id, tag_id=tag_id))
                added_tags.add(normalized)

        # Certifications list (e.g. "USDA Organic", "Kosher Certified").
        certifications = raw.get("certifications") or []
        for cert in certifications:
            mapped = _CERTIFICATION_TAG_MAP.get(cert.lower().strip())
            if mapped and mapped not in added_tags:
                tag_id = tags.get(mapped)
                if tag_id is not None:
                    tag_instances.append(Tag_Instance(product_id=prod.id, tag_id=tag_id))
                    added_tags.add(mapped)

        # Local tag.
        if raw.get("isLocal") and "local" in tags:
            tag_instances.append(Tag_Instance(product_id=prod.id, tag_id=tags["local"]))

        # Department → canonical category tag.
        # Browse API uses `department`/`subDepartment`; the search API fallback
        # uses `categories.lvl0` (top-level) and `categories.lvl1` (path like
        # "Grocery > Chips & Snack Foods") — extract the leaf from lvl1.
        department = raw.get("department") or ""
        sub_dept = raw.get("subDepartment") or ""
        cats = raw.get("categories") or {}
        if not department:
            department = cats.get("lvl0") or ""
        if not sub_dept and cats.get("lvl1"):
            sub_dept = str(cats["lvl1"]).split(" > ")[-1].strip()
        canonical = _DEPARTMENT_MAP.get(department) or _DEPARTMENT_MAP.get(sub_dept)
        if canonical and canonical in tags:
            tag_instances.append(Tag_Instance(product_id=prod.id, tag_id=tags[canonical]))
        elif not canonical and (department or sub_dept):
            logger.debug(
                "Wegmans: unmapped department %r / %r for %r",
                department, sub_dept, raw_full_name[:60],
            )

        sess.add_all(tag_instances)
    else:
        created_product = False

    # Update thumbnail if it's still the fallback
    if cast(str | None, prod.picture_url) == WG_FALLBACK_IMAGE and image != WG_FALLBACK_IMAGE:
        prod.picture_url = cast(Any, image)

    # Upsert product instance
    inst = cache.get_instance(int(prod.id))
    created_instance = False
    if inst is None:
        inst = Product_Instance(store_id=store_id, product_id=prod.id)
        sess.add(inst)
        sess.flush()
        cache.remember_instance(inst)
        created_instance = True

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

    # Use the size extracted from the name; fall back to Algolia field.
    # For items sold by weight the packSize is an approximate "1 lb." placeholder —
    # replace it with "per lb" to accurately reflect pricing.
    if size == "N/A":
        if raw.get("isSoldByWeight"):
            size = "per lb"
        else:
            raw_pack = raw.get("packSize") or ""
            size = normalize_size_string(raw_pack) if raw_pack else "N/A"

    price_point, created_price_point, updated_price_point = cache.upsert_daily_price_point(
        base_price=base_price,
        sale_price=sale_price,
        member_price=member_price,
        size=size,
        instance_id=inst.id,
    )
    # Commit per-product so the write lock is released between products,
    # allowing concurrent scraper threads (WF, TJ) to interleave writes.
    sess.commit()
    if created_product:
        collector["products"].append(snapshot_product(prod))
    if created_instance:
        collector["product_instances"].append(snapshot_instance(inst))
    if created_price_point:
        collector["price_points"].append(snapshot_price_point(price_point))
    if updated_price_point:
        collector["updated_price_points"] += 1
