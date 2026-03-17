"""Shared constants, regex helpers, and seed-data setup for the scraper."""

from __future__ import annotations

import re
from typing import Tuple

from sqlalchemy.orm import Session

from models import Company, Store, Tag
from models.base import Base, engine


# ---------------------------------------------------------------------------
# Category / tag constants
# ---------------------------------------------------------------------------

WF_CATEGORIES = [
    "produce", "dairy-eggs", "meat", "prepared-foods",
    "pantry-essentials", "breads-rolls-bakery", "desserts",
    "frozen-foods", "snacks-chips-salsas-dips", "seafood", "beverages",
]

TJ_CATEGORIES = [
    "Fresh Fruits and Veggies", "Dairy & Eggs",
    "Meat, Seafood & Plant-based", "For the Pantry", "Bakery",
    "Candies & Cookies", "From The Freezer",
    ["Chips, Crackers & Crunchy Bites", "Nuts, Dried Fruits, Seeds",
     "Bars, Jerky &... Surprises"],
]

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


# ---------------------------------------------------------------------------
# Database seed data
# ---------------------------------------------------------------------------

def setup_seed_data(sess: Session) -> tuple[list, dict[str, int]]:
    """Insert initial companies, stores, tags and return (stores, tag-id map)."""
    to_add = [
        Company(
            logo_url="https://external-content.duckduckgo.com/iu/?u=http%3A%2F%2Fwww.sott.net%2Fimage%2Fimage%2Fs5%2F102602%2Ffull%2Fwholefoods.png&f=1&nofb=1",
            name="Whole Foods",
        ),
        Company(
            logo_url="https://logos-world.net/wp-content/uploads/2022/02/Trader-Joes-Emblem.png",
            name="Trader Joes",
        ),
        Company(
            logo_url="https://images.wegmans.com/is/image/wegmanscsprod/Wegmans-Logo-Icon-thumb?fmt=webp-alpha",
            name="Wegmans",
        ),
        Store(company_id=1, scraper_id=10413, address="442 Washington St",
              zipcode="02482", town="Wellesley", state="Massachusetts"),
        Store(company_id=2, scraper_id=509, address="958 Highland Ave",
              zipcode="02494", town="Needham", state="Massachusetts"),
        Store(company_id=1, scraper_id=10319, address="300 Legacy Pl",
              zipcode="02026", town="Dedham", state="Massachusetts"),
        Store(company_id=2, scraper_id=512, address="375 Russell St",
              zipcode="01035", town="Hadley", state="Massachusetts"),
        Store(company_id=1, scraper_id=10156, address="575 Worcester Rd",
              zipcode="01701", town="Framingham", state="Massachusetts"),
        Store(company_id=1, scraper_id=10145, address="525 N Lamar Blvd",
              zipcode="78703", town="Austin", state="Texas"),
        Store(company_id=3, scraper_id=57, address="169 University Ave",
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
    return {t.name: t.id for t in sess.query(Tag).all()}
