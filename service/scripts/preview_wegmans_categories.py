"""Dry-run preview of Wegmans category tag bootstrap.

Fetches all products from Algolia, maps department → canonical category using
the same _DEPARTMENT_MAP as the scraper, then reports:
  - How many existing DB products would gain a category tag
  - Distribution across categories
  - Sample of unmapped departments so the map can be improved

No database writes are performed.
"""
import os
import sys
import json
from collections import Counter, defaultdict
from urllib.request import Request, urlopen

# Allow running from the service/ directory
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from models.base import engine
from sqlalchemy import text

# ── Algolia config (mirrors scrapers/wegmans.py) ──────────────────────────────

_APP_ID  = os.environ.get("ALGOLIA_APP_ID", "QGPPR19V8V")
_API_KEY = os.environ["ALGOLIA_API_KEY"]
_ALGOLIA_URL = (
    f"https://{_APP_ID.lower()}-dsn.algolia.net/1/indexes/*/queries"
    f"?x-algolia-api-key={_API_KEY}"
    f"&x-algolia-application-id={_APP_ID}"
)
_BROWSE_URL = (
    f"https://{_APP_ID.lower()}-dsn.algolia.net/1/indexes/products/browse"
    f"?x-algolia-api-key={_API_KEY}"
    f"&x-algolia-application-id={_APP_ID}"
)

_DEPARTMENT_MAP: dict[str, str] = {
    "Produce": "produce",
    "Produce & Floral": "produce",
    "Dairy": "dairy & eggs",
    "Cheese": "dairy & eggs",
    "Eggs": "dairy & eggs",
    "Meat": "meat",
    "Poultry": "meat",
    "Deli & Meals": "prepared foods",
    "Prepared Foods": "prepared foods",
    "Pantry": "pantry",
    "International Foods": "pantry",
    "Bulk": "pantry",
    "Organic & Natural": "pantry",
    "Bakery": "bakery",
    "Breads & Rolls": "bakery",
    "Desserts": "desserts",
    "Cakes & Pies": "desserts",
    "Frozen": "frozen",
    "Snacks": "snacks",
    "Seafood": "seafood",
    "Beverages": "beverages",
    "Beer & Wine": "beverages",
    "Beer, Wine & Spirits": "beverages",
    "Wine, Beer & Spirits": "beverages",
    "Wine": "beverages",
    "Beer": "beverages",
    "Coffee & Tea": "beverages",
    # Grocery is a catch-all; map sub-categories from lvl1
    "Pantry": "pantry",
    "Chips & Snack Foods": "snacks",
    "Protein & Snack Bars": "snacks",
    "Candy": "snacks",
    "Breakfast": "pantry",
    "Soups & Broths": "pantry",
    "Baking & Baking Ingredients": "pantry",
    "Condiments & Sauces": "pantry",
    "Pasta, Grains & Beans": "pantry",
    "Deli": "prepared foods",
}


_STORE_CODE = 57   # Wegmans scraper_id from DB
_PAGE_SIZE  = 100

_STORE_FILTERS = (
    f"storeNumber:{_STORE_CODE} AND fulfilmentType:instore "
    f"AND excludeFromWeb:false AND isSoldAtStore:true"
)

_DEFAULT_UA = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
)


def _post(url: str, body: dict) -> dict:
    data = json.dumps(body).encode("utf-8")
    req = Request(url, data)
    req.add_header("User-Agent", _DEFAULT_UA)
    req.add_header("Content-Type", "application/json")
    req.add_header("Origin", "https://www.wegmans.com")
    req.add_header("Referer", "https://www.wegmans.com/")
    return json.loads(urlopen(req, timeout=30).read())


def _get_leaf_categories() -> list[tuple[str, int]]:
    body = {"requests": [{
        "indexName": "products",
        "analytics": False,
        "attributesToHighlight": [],
        "facets": ["categoryPageId"],
        "filters": _STORE_FILTERS,
        "hitsPerPage": 0,
        "page": 0,
        "query": "",
    }]}
    result = _post(_ALGOLIA_URL, body)
    facets = result["results"][0].get("facets", {}).get("categoryPageId", {})
    all_paths = set(facets.keys())
    leaves = [
        (path, count)
        for path, count in facets.items()
        if not any(other.startswith(path + " > ") for other in all_paths)
    ]
    return leaves


def _fetch_category(cat: str) -> list[dict]:
    hits: list[dict] = []
    page = 0
    while True:
        body = {"requests": [{
            "indexName": "products",
            "analytics": False,
            "attributesToHighlight": [],
            "facetFilters": [[f"categoryPageId:{cat}"]],
            "filters": _STORE_FILTERS,
            "hitsPerPage": _PAGE_SIZE,
            "page": page,
            "query": "",
        }]}
        result = _post(_ALGOLIA_URL, body)
        batch = result["results"][0].get("hits", [])
        hits.extend(batch)
        total_pages = result["results"][0].get("nbPages", 1)
        page += 1
        if page >= total_pages:
            break
    return hits


def fetch_all_algolia() -> list[dict]:
    """Fetch via browse API; fall back to category-partitioned search."""
    # Try browse first
    hits: list[dict] = []
    seen: set[str] = set()
    cursor: str | None = None
    try:
        while True:
            body: dict = {
                "query": "",
                "filters": _STORE_FILTERS,
                "hitsPerPage": 1000,
            }
            if cursor:
                body["cursor"] = cursor
            result = _post(_BROWSE_URL, body)
            for h in result.get("hits", []):
                sku = h.get("sku") or h.get("objectID", "")
                if sku and sku not in seen:
                    seen.add(sku)
                    hits.append(h)
            cursor = result.get("cursor")
            page_n = len(hits) // 1000 + 1
            print(f"  browse page {page_n}: {len(hits)} total", flush=True)
            if not cursor or not result.get("hits"):
                break
        print(f"  browse API succeeded: {len(hits)} products")
        return hits
    except Exception as exc:
        print(f"  browse API unavailable ({exc}), falling back to category search...")

    # Fall back to category-partitioned search
    leaves = _get_leaf_categories()
    print(f"  {len(leaves)} leaf categories found")
    for i, (cat, count) in enumerate(leaves, 1):
        batch = _fetch_category(cat)
        for h in batch:
            sku = h.get("sku") or h.get("objectID", "")
            if sku and sku not in seen:
                seen.add(sku)
                hits.append(h)
        print(f"  [{i}/{len(leaves)}] {cat}: {count} → got {len(batch)}  (total {len(hits)})", flush=True)
    return hits


def main() -> None:
    # Load existing Wegmans SKUs from DB
    print("Loading existing Wegmans products from DB...")
    with engine.connect() as conn:
        rows = conn.execute(text(
            "SELECT id, raw_name FROM products WHERE company_id = 3"
        )).fetchall()
    db_count = len(rows)
    print(f"  {db_count} Wegmans products in DB\n")

    # Fetch from Algolia
    print("Fetching from Algolia (this may take a minute)...")
    hits = fetch_all_algolia()
    print(f"  {len(hits)} hits total from Algolia\n")

    # Map each hit to a canonical category
    category_counts: Counter = Counter()
    unmapped_dept_counts: Counter = Counter()
    would_tag = 0

    for hit in hits:
        # Algolia search hits expose category hierarchy via `categories.lvl0/lvl1`
        # (the scraper's browse API returned `department`/`subDepartment` instead).
        cats = hit.get("categories") or {}
        dept = cats.get("lvl0") or ""
        lvl1 = cats.get("lvl1") or ""
        sub  = lvl1.split(" > ")[-1] if lvl1 else ""
        canonical = _DEPARTMENT_MAP.get(dept) or _DEPARTMENT_MAP.get(sub)
        if canonical:
            category_counts[canonical] += 1
            would_tag += 1
        else:
            label = dept or sub or "(none)"
            unmapped_dept_counts[label] += 1

    # Summary
    print("=" * 55)
    print(f"Products that WOULD receive a category tag: {would_tag:,}")
    print(f"Products with no mappable department:       {len(hits) - would_tag:,}")
    print()
    print("Category distribution (Algolia → canonical):")
    print("-" * 45)
    for cat, count in sorted(category_counts.items(), key=lambda x: -x[1]):
        bar = "█" * min(30, count // max(1, max(category_counts.values()) // 30))
        print(f"  {cat:<20} {count:>6,}  {bar}")
    print()
    if unmapped_dept_counts:
        print("Top unmapped departments (consider extending _DEPARTMENT_MAP):")
        for dept, count in unmapped_dept_counts.most_common(15):
            print(f"  {dept:<40} {count:>5,}")


if __name__ == "__main__":
    main()
