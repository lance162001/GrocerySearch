from __future__ import annotations

import argparse
import re
import sqlite3
from pathlib import Path


ROOT = Path(__file__).resolve().parent
DB_PATH = ROOT / "app.db"


PACKAGED_HINTS = {
    "oz",
    "fz",
    "ml",
    "liter",
    "gram",
    "kg",
    "pack",
    "pk",
    "count",
    "ct",
    "bottle",
    "jar",
    "can",
    "bag",
    "box",
    "dozen",
}

POUND_KEYWORDS = {
    "onion",
    "potato",
    "sweet potato",
    "yam",
    "turnip",
    "beet",
    "carrot",
    "parsnip",
    "ginger",
    "garlic",
    "shallot",
    "banana",
    "apple",
    "pear",
    "plum",
    "peach",
    "nectarine",
    "grape",
    "cherry",
    "steak",
    "chuck",
    "sirloin",
    "brisket",
    "ribeye",
    "ground beef",
    "beef",
    "pork",
    "lamb",
    "chicken breast",
    "chicken thigh",
    "drumstick",
    "tenderloin",
    "sausage",
    "turkey breast",
    "salmon",
    "cod",
    "tilapia",
    "shrimp",
    "scallop",
    "mussel",
    "clam",
    "fillet",
    "bulk",
    "salad bar",
    "olive bar",
    "hot bar",
}

EACH_KEYWORDS = {
    "lemon",
    "lime",
    "avocado",
    "mango",
    "papaya",
    "pineapple",
    "coconut",
    "cantaloupe",
    "honeydew",
    "watermelon",
    "eggplant",
    "cucumber",
    "zucchini",
    "squash",
    "pepper",
    "head",
    "romaine",
    "lettuce",
    "celery",
    "cauliflower",
    "broccoli",
    "cabbage",
    "bunch",
    "single",
}

LB_FRIENDLY_CATEGORIES = {"meat", "seafood"}
EACH_FRIENDLY_CATEGORIES = {
    "dairy & eggs",
    "pantry",
    "bakery",
    "desserts",
    "frozen",
    "beverages",
}


def _normalize(text: str) -> str:
    lowered = text.lower()
    lowered = lowered.replace("fl oz", "fz")
    lowered = re.sub(r"[^a-z0-9\s]", " ", lowered)
    return re.sub(r"\s+", " ", lowered).strip()


def _contains_phrase(phrase_set: set[str], text: str) -> list[str]:
    matches: list[str] = []
    for phrase in phrase_set:
        pattern = rf"\b{re.escape(phrase)}\b"
        if re.search(pattern, text):
            matches.append(phrase)
    return sorted(matches)


def guess_unit(name: str, raw_name: str, brand: str, categories: list[str]) -> tuple[str, str, float]:
    joined = _normalize(" ".join([name or "", raw_name or "", brand or ""]))

    lb_score = 0
    each_score = 1  # mild default toward each for packaged retail items
    reasons: list[str] = []

    pound_matches = _contains_phrase(POUND_KEYWORDS, joined)
    each_matches = _contains_phrase(EACH_KEYWORDS, joined)
    packaged_matches = _contains_phrase(PACKAGED_HINTS, joined)

    if pound_matches:
        lb_score += 3 + len(pound_matches)
        reasons.append(f"pound keywords: {', '.join(pound_matches[:4])}")

    if each_matches:
        each_score += 3 + len(each_matches)
        reasons.append(f"each keywords: {', '.join(each_matches[:4])}")

    if packaged_matches:
        each_score += 4
        reasons.append("packaged/unit hints in name")

    category_set = {c.lower() for c in categories}
    if category_set & LB_FRIENDLY_CATEGORIES:
        lb_score += 3
        reasons.append("category suggests weighted item")
    if category_set & EACH_FRIENDLY_CATEGORIES:
        each_score += 2
        reasons.append("category suggests unit item")

    if "produce" in category_set:
        lb_score += 1
        each_score += 1

    guess = "per_pound" if lb_score > each_score else "per_each"
    total = max(1, lb_score + each_score)
    confidence = round(max(lb_score, each_score) / total, 3)

    if not reasons:
        reasons.append("default fallback")

    return guess, "; ".join(reasons), confidence


def fetch_na_products(conn: sqlite3.Connection) -> list[dict]:
    query = """
    SELECT
        p.id,
        p.name,
        p.raw_name,
        p.brand,
        COUNT(*) AS na_price_point_rows,
        GROUP_CONCAT(DISTINCT t.name) AS category_tags
    FROM price_points pp
    JOIN product_instances pi ON pi.id = pp.instance_id
    JOIN products p ON p.id = pi.product_id
    LEFT JOIN tag_instances ti ON ti.product_id = p.id
    LEFT JOIN tags t ON t.id = ti.tag_id
    WHERE TRIM(LOWER(COALESCE(pp.size, ''))) IN ('n/a', 'na')
    GROUP BY p.id, p.name, p.raw_name, p.brand
    ORDER BY p.id
    """
    conn.row_factory = sqlite3.Row
    rows = conn.execute(query).fetchall()

    out = []
    for row in rows:
        categories = []
        if row["category_tags"]:
            categories = [token.strip() for token in row["category_tags"].split(",") if token.strip()]
        out.append(
            {
                "product_id": row["id"],
                "name": row["name"] or "",
                "raw_name": row["raw_name"] or "",
                "brand": row["brand"] or "",
                "na_price_point_rows": row["na_price_point_rows"],
                "category_tags": categories,
            }
        )
    return out


def _db_size_value(guess: str) -> str:
    return "per lb" if guess == "per_pound" else "each"


def apply_guesses(conn: sqlite3.Connection, records: list[dict], dry_run: bool) -> tuple[int, int, int]:
    updated_products = 0
    updated_price_points = 0
    each_count = 0
    per_lb_count = 0

    for record in records:
        guess, _, _ = guess_unit(
            name=record["name"],
            raw_name=record["raw_name"],
            brand=record["brand"],
            categories=record["category_tags"],
        )
        db_value = _db_size_value(guess)

        if db_value == "per lb":
            per_lb_count += 1
        else:
            each_count += 1

        cursor = conn.execute(
            """
            UPDATE price_points
            SET size = ?
            WHERE instance_id IN (
                SELECT id FROM product_instances WHERE product_id = ?
            )
              AND TRIM(LOWER(COALESCE(size, ''))) IN ('n/a', 'na')
            """,
            (db_value, record["product_id"]),
        )

        if cursor.rowcount > 0:
            updated_products += 1
            updated_price_points += cursor.rowcount

    if dry_run:
        conn.rollback()
    else:
        conn.commit()

    return updated_products, updated_price_points, each_count, per_lb_count


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Guess N/A units and write directly into price_points.size"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Compute and print results without committing database changes.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    if not DB_PATH.exists():
        raise FileNotFoundError(f"SQLite DB not found at {DB_PATH}")

    with sqlite3.connect(DB_PATH) as conn:
        records = fetch_na_products(conn)
        updated_products, updated_price_points, each_count, per_lb_count = apply_guesses(
            conn=conn,
            records=records,
            dry_run=args.dry_run,
        )

    mode = "DRY RUN" if args.dry_run else "COMMITTED"
    print(
        f"{mode}: guessed {len(records)} products | "
        f"updated products={updated_products} | "
        f"updated price_points={updated_price_points} | "
        f"guesses(each={each_count}, per_lb={per_lb_count})"
    )


if __name__ == "__main__":
    main()