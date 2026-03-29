"""Grocery Wordle game API.

Daily target product is chosen deterministically by sha256(game_date) % pool_size.
No new database tables are required.  Game state is owned by the client.
"""

import hashlib
import re
from datetime import date
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import case, func, or_, select
from sqlalchemy.orm import Session

from . import get_db, escape_like
import models

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

_CATEGORY_TAGS = {
    'produce', 'dairy & eggs', 'meat', 'prepared foods', 'pantry',
    'bakery', 'desserts', 'frozen', 'snacks', 'seafood', 'beverages',
}

_MAX_GUESSES = 8

_ATTRIBUTE_LABELS = {
    'company':    'Company',
    'category':   'Category',
    'price':      'Price',
    'size_value': 'Size',
    'size_unit':  'Unit',
    'staple':     'Staple',
    'brand':      'Brand',
    'name':       'Name',
}

# Stop-words ignored when comparing product names
_NAME_STOP_WORDS = {
    'a', 'an', 'the', 'of', 'with', 'and', 'or', 'in', 'for',
    'to', 'no', 'on', 'by', 'at', '&',
}

# ---------------------------------------------------------------------------
# Pydantic schemas
# ---------------------------------------------------------------------------

class GuessRequest(BaseModel):
    product_id: int
    game_date: str   # "YYYY-MM-DD"
    round: int = 0   # 0 = daily; 1+ = infinite bonus rounds


class GameSearchResult(BaseModel):
    id: int
    name: str
    brand: str
    company_name: str
    picture_url: str


class AttributeResult(BaseModel):
    key: str
    label: str
    value: str
    match: str  # "exact" | "close" | "none"
    direction: Optional[str] = None  # "higher" | "lower" — only for price


class GuessResponse(BaseModel):
    guess: GameSearchResult
    attributes: list[AttributeResult]
    is_correct: bool


class RevealResponse(BaseModel):
    product: GameSearchResult
    staple_name: Optional[str]
    category: Optional[str]
    price: str
    size_unit: Optional[str]


class GameDailyResponse(BaseModel):
    game_date: str
    max_guesses: int
    attribute_labels: list[str]


class HintResponse(BaseModel):
    key: str
    label: str
    value: str


# Priority order for hint reveals — most strategically useful first
_HINT_PRIORITY = ['company', 'category', 'price', 'brand', 'staple', 'size_unit', 'size_value', 'name']

# ---------------------------------------------------------------------------
# Pool cache — keyed by date string; stale keys are never accessed again
# ---------------------------------------------------------------------------

_pool_cache: dict[str, list[int]] = {}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _get_product_pool(db: Session, game_date: str) -> list[int]:
    """Return sorted list of eligible product IDs, cached per calendar day."""
    if game_date in _pool_cache:
        return _pool_cache[game_date]

    has_price = (
        select(models.Product_Instance.product_id)
        .join(models.PricePoint, models.PricePoint.instance_id == models.Product_Instance.id)
        .distinct()
        .scalar_subquery()
    )
    has_category = (
        select(models.Tag_Instance.product_id)
        .join(models.Tag, models.Tag_Instance.tag_id == models.Tag.id)
        .where(models.Tag.name.in_(_CATEGORY_TAGS))
        .distinct()
        .scalar_subquery()
    )
    # Only include products with a net-approved staple label so the pool
    # stays small and every answer is a recognisable, nameable item.
    has_staple = (
        select(models.LabelJudgement.product_id)
        .where(
            models.LabelJudgement.judgement_type == 'staple',
            models.LabelJudgement.staple_name.isnot(None),
        )
        .group_by(
            models.LabelJudgement.product_id,
            models.LabelJudgement.staple_name,
        )
        .having(
            func.sum(case((models.LabelJudgement.approved == True, 1), else_=0))
            - func.sum(case((models.LabelJudgement.approved == False, 1), else_=0))
            > 0
        )
        .distinct()
        .scalar_subquery()
    )

    rows = (
        db.query(models.Product.id)
        .filter(
            models.Product.picture_url.isnot(None),
            models.Product.picture_url != '',
            models.Product.brand.isnot(None),
            models.Product.brand != '',
            models.Product.id.in_(has_price),
            models.Product.id.in_(has_category),
            models.Product.id.in_(has_staple),
        )
        .order_by(models.Product.id)
        .all()
    )
    pool = [r[0] for r in rows]
    _pool_cache[game_date] = pool
    return pool


def _get_daily_product_id(pool: list[int], game_date: str, round: int = 0) -> int:
    if not pool:
        raise HTTPException(503, detail="No eligible products in pool")
    seed = game_date if round == 0 else f'{game_date}:{round}'
    digest = int(hashlib.sha256(seed.encode()).hexdigest(), 16)
    return pool[digest % len(pool)]


def _parse_price_float(raw: Optional[str]) -> Optional[float]:
    if not raw:
        return None
    cleaned = re.sub(r'[^0-9.]', '', raw.strip())
    try:
        return float(cleaned) if cleaned else None
    except ValueError:
        return None


# Multi-word unit must be checked before single-word patterns.
_UNIT_RE = re.compile(
    r'fl\.?\s*oz'
    r'|oz'
    r'|lbs?'
    r'|lb'
    r'|ct'
    r'|count'
    r'|grams?'
    r'|gr?'
    r'|kg'
    r'|ml'
    r'|liters?'
    r'|gallons?'
    r'|gal'
    r'|quarts?'
    r'|qt'
    r'|pints?'
    r'|pt'
    r'|pack'
    r'|pk',
    re.IGNORECASE,
)

_UNIT_NORMALIZE: dict[str, str] = {
    'fl oz': 'fl oz',
    'oz': 'oz',
    'lb': 'lb', 'lbs': 'lb',
    'ct': 'ct', 'count': 'ct',
    'g': 'g', 'gr': 'g', 'gram': 'g', 'grams': 'g',
    'kg': 'kg',
    'ml': 'ml',
    'l': 'l', 'liter': 'l', 'liters': 'l',
    'gal': 'gal', 'gallon': 'gal', 'gallons': 'gal',
    'qt': 'qt', 'quart': 'qt', 'quarts': 'qt',
    'pt': 'pt', 'pint': 'pt', 'pints': 'pt',
    'pk': 'pk', 'pack': 'pk',
}


def _extract_size_unit(size_str: Optional[str]) -> Optional[str]:
    if not size_str:
        return None
    if re.search(r'fl\.?\s*oz', size_str, re.IGNORECASE):
        return 'fl oz'
    m = _UNIT_RE.search(size_str)
    if not m:
        return None
    raw = m.group(0).lower().strip()
    return _UNIT_NORMALIZE.get(raw, raw)


def _name_tokens(name: str) -> list[str]:
    """Lowercase alphabetic tokens, stop-words removed."""
    return [
        t for t in re.findall(r"[a-z0-9]+(?:'[a-z]+)?", name.lower())
        if t not in _NAME_STOP_WORDS
    ]


def _compare_names(g_name: str, t_name: str) -> tuple[str, str]:
    """Return (match, value) for the name attribute.

    value = shared words joined by spaces, or the guess name if none.
    match: exact if names are identical, close if ≥1 word shared, else none.
    """
    g_tokens = _name_tokens(g_name)
    t_tokens = _name_tokens(t_name)
    shared = [t for t in g_tokens if t in set(t_tokens)]
    if g_name.strip().lower() == t_name.strip().lower():
        return 'exact', g_name
    if shared:
        return 'close', ' '.join(shared)
    return 'none', g_name


def _extract_size_value(size_str: Optional[str]) -> Optional[float]:
    """Return the leading numeric value from a size string (e.g. '32 fl oz' → 32.0)."""
    if not size_str:
        return None
    m = re.search(r'(\d+(?:\.\d+)?)', size_str.strip())
    if not m:
        return None
    try:
        return float(m.group(1))
    except ValueError:
        return None


def _get_category(db: Session, product_id: int) -> Optional[str]:
    row = (
        db.query(models.Tag.name)
        .join(models.Tag_Instance, models.Tag_Instance.tag_id == models.Tag.id)
        .filter(
            models.Tag_Instance.product_id == product_id,
            models.Tag.name.in_(_CATEGORY_TAGS),
        )
        .first()
    )
    return row[0] if row else None


def _get_staple_name(db: Session, product_id: int) -> Optional[str]:
    """Return the most net-approved staple label for this product, or None."""
    row = (
        db.query(
            models.LabelJudgement.staple_name,
            func.sum(
                case((models.LabelJudgement.approved == True, 1), else_=0)
            ).label('approvals'),
            func.sum(
                case((models.LabelJudgement.approved == False, 1), else_=0)
            ).label('denials'),
        )
        .filter(
            models.LabelJudgement.product_id == product_id,
            models.LabelJudgement.judgement_type == 'staple',
            models.LabelJudgement.staple_name.isnot(None),
        )
        .group_by(models.LabelJudgement.staple_name)
        .order_by(
            (
                func.sum(case((models.LabelJudgement.approved == True, 1), else_=0))
                - func.sum(case((models.LabelJudgement.approved == False, 1), else_=0))
            ).desc()
        )
        .first()
    )
    if row is None:
        return None
    staple_name, approvals, denials = row
    net = (approvals or 0) - (denials or 0)
    return staple_name if net > 0 else None


def _load_product_detail(db: Session, product_id: int) -> dict:
    product = db.get(models.Product, product_id)
    if product is None:
        raise HTTPException(404, detail=f"Product {product_id} not found")

    company = db.get(models.Company, product.company_id)
    company_name = company.name if company else ''

    pp = (
        db.query(models.PricePoint)
        .join(models.Product_Instance,
              models.PricePoint.instance_id == models.Product_Instance.id)
        .filter(models.Product_Instance.product_id == product_id)
        .order_by(models.PricePoint.collected_on.desc(), models.PricePoint.id.desc())
        .first()
    )
    size_str = pp.size if pp else None
    price_val: Optional[float] = (
        _parse_price_float(pp.member_price)
        or _parse_price_float(pp.sale_price)
        or _parse_price_float(pp.base_price)
    ) if pp else None

    return {
        'product': product,
        'company_id': product.company_id,
        'company_name': company_name,
        'price': price_val,
        'size_str': size_str,
        'size_value': _extract_size_value(size_str),
        'size_unit': _extract_size_unit(size_str),
        'category': _get_category(db, product_id),
        'staple_name': _get_staple_name(db, product_id),
    }


def _compare_attributes(
    guess_detail: dict,
    target_detail: dict,
) -> list[AttributeResult]:
    results: list[AttributeResult] = []

    # 1. Company
    g_cid = guess_detail['company_id']
    t_cid = target_detail['company_id']
    results.append(AttributeResult(
        key='company',
        label=_ATTRIBUTE_LABELS['company'],
        value=guess_detail['company_name'] or '',
        match='exact' if g_cid is not None and g_cid == t_cid else 'none',
    ))

    # 2. Category
    g_cat = (guess_detail['category'] or '').lower()
    t_cat = (target_detail['category'] or '').lower()
    results.append(AttributeResult(
        key='category',
        label=_ATTRIBUTE_LABELS['category'],
        value=guess_detail['category'] or 'Unknown',
        match='exact' if g_cat and g_cat == t_cat else 'none',
    ))

    # 3. Price — exact ≤$0.50, close ≤$3.00 + direction, else none + direction
    g_price: Optional[float] = guess_detail['price']
    t_price: Optional[float] = target_detail['price']
    price_str = f'${g_price:.2f}' if g_price is not None else 'N/A'
    if g_price is None or t_price is None:
        price_match = 'none'
        price_dir = None
    else:
        diff = abs(g_price - t_price)
        if diff <= 0.50:
            price_match = 'exact'
            price_dir = None
        elif diff <= 3.00:
            price_match = 'close'
            price_dir = 'higher' if t_price > g_price else 'lower'
        else:
            price_match = 'none'
            price_dir = 'higher' if t_price > g_price else 'lower'
    results.append(AttributeResult(
        key='price',
        label=_ATTRIBUTE_LABELS['price'],
        value=price_str,
        match=price_match,
        direction=price_dir,
    ))

    # 4. Size value — exact within 15%, close within 2×, else none + direction
    g_sv: Optional[float] = guess_detail['size_value']
    t_sv: Optional[float] = target_detail['size_value']
    if g_sv is not None and g_sv == int(g_sv):
        sv_str = str(int(g_sv))
    elif g_sv is not None:
        sv_str = f'{g_sv:.1f}'
    else:
        sv_str = 'N/A'
    if g_sv is None or t_sv is None:
        sv_match = 'none'
        sv_dir = None
    elif g_sv == t_sv:
        sv_match = 'exact'
        sv_dir = None
    else:
        sv_dir = 'higher' if t_sv > g_sv else 'lower'
        ratio = max(g_sv, t_sv) / min(g_sv, t_sv) if min(g_sv, t_sv) > 0 else float('inf')
        if ratio <= 1.15:
            sv_match = 'exact'
            sv_dir = None
        elif ratio <= 2.0:
            sv_match = 'close'
        else:
            sv_match = 'none'
    results.append(AttributeResult(
        key='size_value',
        label=_ATTRIBUTE_LABELS['size_value'],
        value=sv_str,
        match=sv_match,
        direction=sv_dir,
    ))

    # 5. Size unit
    g_unit = (guess_detail['size_unit'] or '').lower()
    t_unit = (target_detail['size_unit'] or '').lower()
    results.append(AttributeResult(
        key='size_unit',
        label=_ATTRIBUTE_LABELS['size_unit'],
        value=guess_detail['size_unit'] or 'N/A',
        match='exact' if g_unit and g_unit == t_unit else 'none',
    ))

    # 6. Staple — same name = exact; both None = exact (both non-staple); else none
    g_staple = guess_detail['staple_name']
    t_staple = target_detail['staple_name']
    if g_staple is not None and t_staple is not None and g_staple.lower() == t_staple.lower():
        staple_match = 'exact'
        staple_value = g_staple
    elif g_staple is None and t_staple is None:
        staple_match = 'exact'
        staple_value = 'No'
    else:
        staple_match = 'none'
        staple_value = g_staple if g_staple is not None else 'No'
    results.append(AttributeResult(
        key='staple',
        label=_ATTRIBUTE_LABELS['staple'],
        value=staple_value,
        match=staple_match,
    ))

    # 7. Brand
    g_brand = (guess_detail['product'].brand or '').strip().lower()
    t_brand = (target_detail['product'].brand or '').strip().lower()
    results.append(AttributeResult(
        key='brand',
        label=_ATTRIBUTE_LABELS['brand'],
        value=guess_detail['product'].brand or '',
        match='exact' if g_brand and g_brand == t_brand else 'none',
    ))

    # 8. Name — shared meaningful words between guess and target names
    name_match, name_value = _compare_names(
        guess_detail['product'].name or '',
        target_detail['product'].name or '',
    )
    results.append(AttributeResult(
        key='name',
        label=_ATTRIBUTE_LABELS['name'],
        value=name_value,
        match=name_match,
    ))

    return results


# ---------------------------------------------------------------------------
# Router
# ---------------------------------------------------------------------------

game_router = APIRouter(prefix='/game')


@game_router.get('/daily', response_model=GameDailyResponse)
def get_daily_info(
    game_date: Optional[str] = Query(default=None),
    db: Session = Depends(get_db),
):
    """Return game metadata for a given date. The target product is not revealed."""
    if game_date is None:
        game_date = date.today().isoformat()
    try:
        date.fromisoformat(game_date)
    except ValueError:
        raise HTTPException(400, detail='game_date must be YYYY-MM-DD')
    return GameDailyResponse(
        game_date=game_date,
        max_guesses=_MAX_GUESSES,
        attribute_labels=list(_ATTRIBUTE_LABELS.values()),
    )


@game_router.get('/search', response_model=list[GameSearchResult])
def game_search(
    q: str = Query(min_length=1),
    limit: int = Query(default=10, le=25),
    company: Optional[str] = Query(default=None),
    db: Session = Depends(get_db),
):
    """Autocomplete search for guesses — lightweight, name+brand match."""
    q_esc = escape_like(q)
    query = (
        db.query(models.Product, models.Company)
        .join(models.Company, models.Company.id == models.Product.company_id)
        .filter(
            or_(
                models.Product.name.ilike(f'%{q_esc}%', escape="\\"),
                models.Product.brand.ilike(f'%{q_esc}%', escape="\\"),
            ),
            models.Product.picture_url.isnot(None),
            models.Product.picture_url != '',
        )
    )
    if company:
        query = query.filter(models.Company.name.ilike(escape_like(company), escape="\\"))
    products = (
        query
        .order_by(
            # Names that start with the query appear first
            case((models.Product.name.ilike(f'{q_esc}%', escape="\\"), 0), else_=1),
            func.length(models.Product.name),
        )
        .limit(limit)
        .all()
    )
    return [
        GameSearchResult(
            id=p.id,
            name=p.name,
            brand=p.brand or '',
            company_name=c.name or '',
            picture_url=p.picture_url or '',
        )
        for p, c in products
    ]


@game_router.post('/guess', response_model=GuessResponse)
def submit_guess(
    body: GuessRequest,
    db: Session = Depends(get_db),
):
    """Evaluate a guess against today's product and return attribute comparison."""
    try:
        date.fromisoformat(body.game_date)
    except ValueError:
        raise HTTPException(400, detail='game_date must be YYYY-MM-DD')

    pool = _get_product_pool(db, body.game_date)
    target_id = _get_daily_product_id(pool, body.game_date, body.round)

    guess_detail = _load_product_detail(db, body.product_id)
    target_detail = _load_product_detail(db, target_id)

    attributes = _compare_attributes(guess_detail, target_detail)
    is_correct = all(a.match == 'exact' for a in attributes)

    gp = guess_detail['product']
    return GuessResponse(
        guess=GameSearchResult(
            id=gp.id,
            name=gp.name,
            brand=gp.brand or '',
            company_name=guess_detail['company_name'],
            picture_url=gp.picture_url or '',
        ),
        attributes=attributes,
        is_correct=is_correct,
    )


@game_router.get('/reveal', response_model=RevealResponse)
def reveal_answer(
    game_date: Optional[str] = Query(default=None),
    round: int = Query(default=0),
    db: Session = Depends(get_db),
):
    """Return the target product. Client calls this only after the game ends."""
    if game_date is None:
        game_date = date.today().isoformat()
    try:
        date.fromisoformat(game_date)
    except ValueError:
        raise HTTPException(400, detail='game_date must be YYYY-MM-DD')

    pool = _get_product_pool(db, game_date)
    target_id = _get_daily_product_id(pool, game_date, round)
    detail = _load_product_detail(db, target_id)
    product = detail['product']

    price_val: Optional[float] = detail['price']
    price_str = f'${price_val:.2f}' if price_val is not None else 'N/A'

    return RevealResponse(
        product=GameSearchResult(
            id=product.id,
            name=product.name,
            brand=product.brand or '',
            company_name=detail['company_name'],
            picture_url=product.picture_url or '',
        ),
        staple_name=detail['staple_name'],
        category=detail['category'],
        price=price_str,
        size_unit=detail['size_unit'],
    )


@game_router.get('/hint', response_model=HintResponse)
def get_hint(
    game_date: Optional[str] = Query(default=None),
    round: int = Query(default=0),
    skip: str = Query(default=''),  # comma-separated attribute keys already revealed
    db: Session = Depends(get_db),
):
    """Reveal one attribute of the target product. Client passes already-used keys in `skip`."""
    if game_date is None:
        game_date = date.today().isoformat()
    try:
        date.fromisoformat(game_date)
    except ValueError:
        raise HTTPException(400, detail='game_date must be YYYY-MM-DD')

    pool = _get_product_pool(db, game_date)
    target_id = _get_daily_product_id(pool, game_date, round)
    detail = _load_product_detail(db, target_id)
    product = detail['product']

    sv = detail['size_value']
    sv_str = str(int(sv)) if sv is not None and sv == int(sv) else (f'{sv:.1f}' if sv is not None else 'N/A')
    price_val: Optional[float] = detail['price']

    attr_values = {
        'company':    detail['company_name'] or 'Unknown',
        'category':   detail['category'] or 'Unknown',
        'price':      f'${price_val:.2f}' if price_val is not None else 'N/A',
        'brand':      product.brand or 'Unknown',
        'staple':     detail['staple_name'] or 'None',
        'size_unit':  detail['size_unit'] or 'N/A',
        'size_value': sv_str,
        'name':       product.name or 'Unknown',
    }

    skip_keys = {k.strip() for k in skip.split(',') if k.strip()}
    for key in _HINT_PRIORITY:
        if key not in skip_keys:
            return HintResponse(
                key=key,
                label=_ATTRIBUTE_LABELS[key],
                value=attr_values[key],
            )

    raise HTTPException(400, detail='No hints remaining')
