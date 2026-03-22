"""Shared constants, regex helpers, and seed-data setup for the scraper."""

from __future__ import annotations

import logging
import re
from typing import Any, Tuple, cast

from sqlalchemy.orm import Session

from models import Company, Store, Tag
from models.base import Base, engine


# ---------------------------------------------------------------------------
# Category / tag constants
# ---------------------------------------------------------------------------

WF_CATEGORIES = [
    "produce", "dairy-eggs", "meat", "seafood", "prepared-foods",
    "pantry-essentials", "breads-rolls-bakery", "desserts",
    "frozen-foods", "snacks-chips-salsas-dips", "beverages",
    "beer-wine-spirits", "floral-plants",
]

# Explicit WF-slug → canonical-category mapping (used instead of fragile index arithmetic).
WF_CATEGORY_TO_CANONICAL: dict[str, str] = {
    "produce": "produce",
    "dairy-eggs": "dairy-eggs",
    "meat": "meat",
    "seafood": "seafood",
    "prepared-foods": "prepared-foods",
    "pantry-essentials": "pantry",
    "breads-rolls-bakery": "bakery",
    "desserts": "desserts",
    "frozen-foods": "frozen",
    "snacks-chips-salsas-dips": "snacks",
    "beverages": "beverages",
    "beer-wine-spirits": "beverages",
    "floral-plants": "produce",
}

TJ_CATEGORIES = [
    "Fresh Fruits and Veggies", "Dairy & Eggs",
    "Meat, Seafood & Plant-based", "For the Pantry", "Bakery",
    "Candies & Cookies", "From The Freezer",
    ["Chips, Crackers & Crunchy Bites", "Nuts, Dried Fruits, Seeds",
     "Bars, Jerky &... Surprises"],
]

# Maps TJ category names (at any hierarchy level) to canonical categories.
# Walking the full hierarchy catches both department names ("Dairy & Eggs") and
# leaf names ("Cheese") so every product gets a category tag.
TJ_CATEGORY_TO_CANONICAL: dict[str, str] = {
    # Department level (hierarchy[1])
    "Fresh Fruits and Veggies": "produce",
    "Flowers & Plants": "produce",
    "Dairy & Eggs": "dairy-eggs",
    "Meat, Seafood & Plant-based": "meat",
    "For the Pantry": "pantry",
    "Bakery": "bakery",
    "Candies & Cookies": "desserts",
    "Sweets, Snacks & Pantry": "snacks",
    "From The Freezer": "frozen",
    "Beverages": "beverages",
    "Coffee & Tea": "beverages",
    "Wine, Beer & Spirits": "beverages",
    "Health & Beauty": "pantry",
    "Household": "pantry",
    # Sub-department / leaf level (hierarchy[2])
    "Cheese": "dairy-eggs",
    "Milk, Cream & More": "dairy-eggs",
    "Eggs": "dairy-eggs",
    "Meat & Poultry": "meat",
    "Seafood": "seafood",
    "Fish": "seafood",
    "Plant-Based Proteins": "meat",
    "Fresh Bread & Rolls": "bakery",
    "Chips, Crackers & Crunchy Bites": "snacks",
    "Nuts, Dried Fruits, Seeds": "snacks",
    "Bars, Jerky &... Surprises": "snacks",
    "Frozen Meals & Sides": "frozen",
    "Frozen Appetizers & Snacks": "frozen",
    "Frozen Desserts": "frozen",
    "Frozen Breakfast": "frozen",
    "Frozen Meat, Seafood & Poultry": "frozen",
    "Frozen Vegetables & Fruit": "frozen",
    "Frozen Pizza & Pasta": "frozen",
    "Juice & Ciders": "beverages",
    "Water, Soda & Sparkling": "beverages",
    "Wine": "beverages",
    "Beer": "beverages",
    "Spirits": "beverages",
}

CANONICAL_CATEGORIES = [
    "produce", "dairy-eggs", "meat", "prepared-foods", "pantry",
    "bakery", "desserts", "frozen", "snacks", "seafood", "beverages",
]

DIET_TYPES = [
    "organic", "vegan", "kosher", "gluten free", "dairy free", "vegetarian",
]

DEFAULT_USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/102.0.0.0 Safari/537.36"
)


# ---------------------------------------------------------------------------
# Size extraction
# ---------------------------------------------------------------------------

_SIZE_PATTERN = re.compile(
    r"(?P<value>\d+(?:\.\d+)?|\.\d+)\s*"
    r"(?P<unit>"
    r"fl\.?\s*oz|fluid\s*ounces?|fz|oz|ounces?"
    r"|lb|lbs|pounds?"
    r"|grams?|gr|g|kg|kilograms?"
    r"|ml|milliliters?|lt|l|liters?"
    r"|gallons?|gal|gl"
    r"|quarts?|qt|pints?|pt"
    r"|ct|count|pk|packs?"
    r"|ea|each"
    r")\b",
    re.IGNORECASE,
)

_UNIT_ALIASES: dict[str, str] = {
    "fluid ounce": "fl oz", "fluid ounces": "fl oz", "fl oz": "fl oz",
    "fz": "fl oz",
    "ounce": "oz", "ounces": "oz", "oz": "oz",
    "lb": "lb", "lbs": "lb", "pound": "lb", "pounds": "lb",
    "gram": "gram", "grams": "gram", "gr": "gram", "g": "gram",
    "kilogram": "kg", "kilograms": "kg", "kg": "kg",
    "milliliter": "ml", "milliliters": "ml", "ml": "ml",
    "liter": "l", "liters": "l", "lt": "l", "l": "l",
    "gallon": "gal", "gallons": "gal", "gal": "gal", "gl": "gal",
    "quart": "qt", "quarts": "qt", "qt": "qt",
    "pint": "pint", "pints": "pint", "pt": "pint",
    "ct": "ct", "count": "ct",
    "pk": "pk", "pack": "pk", "packs": "pk",
    "ea": "each", "each": "each",
}


def extract_size_and_clean_name(raw_name: str | None) -> Tuple[str, str]:
    """Return ``(size_string, cleaned_name)`` from a raw product name."""
    if not raw_name:
        return "N/A", "N/A"

    match = _SIZE_PATTERN.search(raw_name)
    if match is None:
        return "N/A", raw_name

    unit_raw = match.group("unit").lower().replace(".", "")
    normalized_unit = _UNIT_ALIASES.get(unit_raw, unit_raw)
    value = match.group("value")

    cleaned = _SIZE_PATTERN.sub("", raw_name, count=1)
    cleaned = re.sub(r"\s{2,}", " ", cleaned).strip(" ,-/")
    if len(cleaned) < 4:
        cleaned = raw_name

    return f"{value} {normalized_unit}", cleaned


def normalize_size_string(size: str) -> str:
    """Normalize a bare size string from an API field through the unit alias table.

    Converts values like ``"10 ounce"``, ``"1 Lb"``, ``"7.8 Oz"`` to the
    canonical forms used by ``extract_size_and_clean_name`` (``"10 oz"``,
    ``"1 lb"``, ``"7.8 oz"``), making sizes comparable across stores.
    Returns the original string unchanged if no known unit is found.
    """
    if not size or size in ("N/A", "n/a"):
        return size
    m = _SIZE_PATTERN.search(size)
    if m is None:
        return size
    unit_raw = m.group("unit").lower().replace(".", "")
    unit = _UNIT_ALIASES.get(unit_raw, unit_raw)
    return f"{m.group('value')} {unit}"


def strip_brand_from_name(name: str, brand: str) -> str:
    """Remove a leading brand prefix from a cleaned product name.

    Handles both ``"Brand, Product Name"`` (comma-separated, common at Whole
    Foods) and ``"Brand Product Name"`` (space-separated, common at Wegmans).
    Returns *name* unchanged if no matching prefix is found or stripping
    would leave an empty string.
    """
    if not brand or not name:
        return name
    brand_lower = brand.lower()
    name_lower = name.lower()
    # Comma-separated: "Brand, Product" or "Brand,Product"
    if name_lower.startswith(brand_lower + ","):
        stripped = name[len(brand) + 1:].lstrip()
        if stripped:
            return stripped
    # Space-separated: "Brand Product"
    elif name_lower.startswith(brand_lower + " "):
        stripped = name[len(brand) + 1:]
        if stripped:
            return stripped
    return name


# ---------------------------------------------------------------------------
# Database seed data
# ---------------------------------------------------------------------------

def setup_seed_data(sess: Session) -> tuple[list, dict[str, int]]:
    """Insert initial companies, stores, tags and return (stores, tag-id map)."""
    whole_foods = Company(
        slug="whole-foods",
        scraper_key="whole_foods",
        logo_url="https://external-content.duckduckgo.com/iu/?u=http%3A%2F%2Fwww.sott.net%2Fimage%2Fimage%2Fs5%2F102602%2Ffull%2Fwholefoods.png&f=1&nofb=1",
        name="Whole Foods",
    )
    trader_joes = Company(
        slug="trader-joes",
        scraper_key="trader_joes",
        logo_url="https://logos-world.net/wp-content/uploads/2022/02/Trader-Joes-Emblem.png",
        name="Trader Joes",
    )
    wegmans = Company(
        slug="wegmans",
        scraper_key="wegmans",
        logo_url="https://images.wegmans.com/is/image/wegmanscsprod/Wegmans-Logo-Icon-thumb?fmt=webp-alpha",
        name="Wegmans",
    )

    sess.add_all([whole_foods, trader_joes, wegmans])
    sess.flush()

    to_add = [
        Store(company_id=whole_foods.id, scraper_id=10413, address="442 Washington St",
              zipcode="02482", town="Wellesley", state="Massachusetts"),
        Store(company_id=trader_joes.id, scraper_id=509, address="958 Highland Ave",
              zipcode="02494", town="Needham", state="Massachusetts"),
        Store(company_id=whole_foods.id, scraper_id=10319, address="300 Legacy Pl",
              zipcode="02026", town="Dedham", state="Massachusetts"),
        Store(company_id=trader_joes.id, scraper_id=512, address="375 Russell St",
              zipcode="01035", town="Hadley", state="Massachusetts"),
        Store(company_id=whole_foods.id, scraper_id=10156, address="575 Worcester Rd",
              zipcode="01701", town="Framingham", state="Massachusetts"),
        Store(company_id=whole_foods.id, scraper_id=10145, address="525 N Lamar Blvd",
              zipcode="78703", town="Austin", state="Texas"),
        Store(company_id=wegmans.id, scraper_id=57, address="169 University Ave",
              zipcode="02090", town="Westwood", state="Massachusetts"),
    ]

    tags: dict[str, int] = {}
    tag_id = 1
    for name in CANONICAL_CATEGORIES + DIET_TYPES:
        tags[name] = tag_id
        tag_id += 1
        to_add.append(Tag(name=name))
    to_add.append(Tag(name="local"))
    tags["local"] = tag_id

    sess.add_all(to_add)
    sess.commit()
    return sess.query(Store).all(), tags


def load_existing_tags(sess: Session) -> dict[str, int]:
    """Load the tag-name→id mapping from an already-seeded database."""
    return {str(t.name): int(t.id) for t in sess.query(Tag).all()}


# ---------------------------------------------------------------------------
# Variation-group computation
# ---------------------------------------------------------------------------

def _variation_base_name(name: str) -> str:
    """Extract the base product type from a product name.

    The heuristic keeps the longest *suffix* of the name that is likely
    the product-type noun phrase, stripping leading flavour / style
    modifiers.  The result is lower-cased and whitespace-normalised.
    """
    # Strip punctuation from each word for cleaner matching.
    words = [w.strip(",.;:") for w in name.lower().split()]
    words = [w for w in words if w]
    if len(words) <= 1:
        return name.lower().strip()
    # Return the last two words for names with 3+ words,
    # the last word for 2-word names.
    if len(words) >= 3:
        return " ".join(words[-2:])
    return words[-1]


def _variation_pre_comma_base(name: str) -> str | None:
    """If *name* contains a comma and the text before it has 2+ words,
    return that prefix as a base-name candidate.  Handles the common
    ``"Cheese Crackers, Original"`` naming convention.
    """
    if "," not in name:
        return None
    pre = name.split(",")[0].strip().lower()
    if len(pre.split()) >= 2:
        return pre
    return None


def compute_variation_groups(sess: Session, *, batch_size: int = 5000) -> int:
    """Assign ``variation_group`` to products that are flavour / style
    variations of each other.

    Two products share a variation group when they have the **same brand**
    (case-insensitive, at least 2 chars) and the same *base product name*.

    The algorithm uses two strategies layered together:
    1. **Last-2-words**: groups products whose names end with the same two
       words (e.g. "… Energy Drink").
    2. **Pre-comma prefix**: for products not already grouped, groups those
       whose names share the same text before the first comma (e.g.
       "Cheese Crackers, Original" and "Cheese Crackers, Extra Toasty").

    Groups with only one member are cleared back to ``NULL`` so the column
    is only set when true variations exist.

    Returns the number of products updated.
    """
    from collections import defaultdict
    from models.products import Product

    logger = logging.getLogger(__name__)

    # 1. Load all products with a usable brand.
    products = (
        sess.query(Product)
        .filter(Product.brand.isnot(None), Product.brand != "")
        .all()
    )
    logger.info("variation-groups: processing %d branded products", len(products))

    # 2. Group by brand.
    by_brand: dict[str, list] = defaultdict(list)
    for prod in products:
        brand = prod.brand.strip()
        if len(brand) < 2:
            continue
        by_brand[brand.lower()].append(prod)

    # 3. For each brand, assign variation groups with two passes.
    assigned: dict[int, str] = {}  # product_id -> group key

    for brand, prods in by_brand.items():
        if len(prods) < 2:
            continue

        # Pass 1: last-2-words strategy.
        l2w_buckets: dict[str, list] = defaultdict(list)
        for prod in prods:
            base = _variation_base_name(prod.name or "")
            if base:
                l2w_buckets[base].append(prod)
        for base, members in l2w_buckets.items():
            if len(members) >= 2:
                key = f"{brand}::{base}"
                for prod in members:
                    assigned[prod.id] = key

        # Pass 2: pre-comma prefix for products not yet assigned.
        pc_buckets: dict[str, list] = defaultdict(list)
        for prod in prods:
            if prod.id in assigned:
                continue
            pc_base = _variation_pre_comma_base(prod.name or "")
            if pc_base:
                pc_buckets[pc_base].append(prod)
        for base, members in pc_buckets.items():
            if len(members) >= 2:
                key = f"{brand}::{base}"
                for prod in members:
                    assigned[prod.id] = key

    # 4. Apply assignments.
    updated = 0
    for prod in products:
        target = assigned.get(prod.id)
        if cast(str | None, prod.variation_group) != target:
            prod.variation_group = cast(Any, target)
            updated += 1

    # 5. Clear variation_group for products with no brand (safety sweep).
    cleared = (
        sess.query(Product)
        .filter(
            Product.variation_group.isnot(None),
            (Product.brand.is_(None) | (Product.brand == "")),
        )
        .all()
    )
    for prod in cleared:
        prod.variation_group = cast(Any, None)
        updated += 1

    sess.commit()
    logger.info("variation-groups: updated %d products", updated)
    return updated
