from typing import Dict, List, Optional, Tuple
import random
import re
import time

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from fastapi_pagination import Page, add_pagination
from fastapi_pagination.ext.sqlalchemy import paginate
from sqlalchemy import or_, select, func, and_, case

from . import get_db
import models
import schemas

# Same list as the Flutter staples screen.
_STAPLE_NAMES = [
    'milk', 'eggs', 'bread', 'rice', 'pasta', 'flour', 'sugar', 'butter',
    'cheese', 'yogurt', 'chicken', 'bananas', 'apples', 'onions', 'potatoes',
    'tomatoes', 'garlic', 'olive oil', 'salt', 'pepper',
]


# ---------------------------------------------------------------------------
# Heuristic helpers – score unjudged products by proximity to labelled ones
# ---------------------------------------------------------------------------

def _word_set(text: str) -> frozenset:
    """Lowercase alphabetic tokens from *text*, rough-singular-normalised."""
    if not text:
        return frozenset()
    words = re.findall(r'[a-z]+', text.lower())
    # Cheap plural normalisation so 'eggs' ↔ 'egg' match in Jaccard.
    out = []
    for w in words:
        if len(w) > 3 and w.endswith('s') and not w.endswith('ss'):
            w = w[:-1]
        out.append(w)
    return frozenset(out)


def _jaccard(a: frozenset, b: frozenset) -> float:
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)


def _staple_heuristic_score(
    cand_name_words: frozenset,
    cand_brand_words: frozenset,
    pos_profiles: list,
    neg_profiles: list,
) -> float:
    """Return a 0–1 score (1 = likely staple, 0 = likely not).

    Uses average Jaccard similarity to confirmed positives vs negatives,
    weighted 70% name / 30% brand.  Returns 0.5 when no signal.
    """
    if not pos_profiles and not neg_profiles:
        return 0.5

    def _avg_sim(profiles):
        if not profiles:
            return 0.0
        total = 0.0
        for nw, bw in profiles:
            name_sim = _jaccard(cand_name_words, nw)
            brand_sim = _jaccard(cand_brand_words, bw)
            total += 0.7 * name_sim + 0.3 * brand_sim
        return total / len(profiles)

    avg_pos = _avg_sim(pos_profiles)
    avg_neg = _avg_sim(neg_profiles)
    denom = avg_pos + avg_neg
    if denom < 1e-9:
        return 0.5
    return avg_pos / denom


def _staple_confidence_py(product_name: str, staple: str) -> float:
    """Server-side port of Flutter's _stapleConfidence(). Lower score = better match."""
    name = (product_name or "").lower().strip()
    query = staple.lower().strip()
    if name == query:
        return 0.0
    words = name.split()
    query_words = query.split()
    if len(words) <= len(query_words) + 1 and query in name:
        return 0.1
    if name.startswith(query):
        return 0.2
    pattern = r'\b' + re.escape(query) + r'\b'
    if re.search(pattern, name):
        extra_words = len(words) - len(query_words)
        return 0.3 + extra_words * 0.05
    if query in name:
        return 0.7 + len(words) * 0.02
    return 1.0


def _load_staple_labels(sess: Session, staple_name: str):
    """Return *(pos_profiles, neg_profiles)* for a staple name.

    Each profile is a ``(name_word_set, brand_word_set)`` tuple for a product
    with a net-positive or net-negative judgement score.
    """
    rows = (
        sess.query(
            models.Product.name,
            models.Product.brand,
            func.sum(
                case((models.LabelJudgement.approved == True, 1), else_=0)
            ).label("approvals"),
            func.sum(
                case((models.LabelJudgement.approved == False, 1), else_=0)
            ).label("denials"),
        )
        .join(
            models.LabelJudgement,
            models.LabelJudgement.product_id == models.Product.id,
        )
        .filter(
            models.LabelJudgement.judgement_type == "staple",
            models.LabelJudgement.staple_name == staple_name,
        )
        .group_by(models.Product.id)
        .all()
    )
    positives: list = []
    negatives: list = []
    for name, brand, approvals, denials in rows:
        net = (approvals or 0) - (denials or 0)
        profile = (_word_set(name or ""), _word_set(brand or ""))
        if net > 0:
            positives.append(profile)
        elif net < 0:
            negatives.append(profile)
    return positives, negatives


# ---------------------------------------------------------------------------
# In-process TTL cache for staple heuristics (expensive to recompute)
# ---------------------------------------------------------------------------
_heuristics_cache: Optional[Tuple[float, List[schemas.StapleHeuristic]]] = None
_HEURISTICS_TTL = 3600.0  # recompute at most once per hour

product_router = APIRouter()


@product_router.get("/products", response_model=Page[schemas.Product])
async def get_all_products(sess: Session = Depends(get_db)):
    return paginate(sess, select(models.Product))


@product_router.get("/products/instance", response_model=Page[schemas.Product_Instance])
async def get_all_product_instances(sess: Session = Depends(get_db)):
    return paginate(sess, select(models.Product_Instance))


@product_router.get("/products/multiple", response_model=List[schemas.Product])
async def get_products_by_ids(ids: List[int], sess: Session = Depends(get_db)):
    products = []
    for product_id in ids:
        product = sess.get(models.Product, product_id)
        if product is None:
            raise HTTPException(404, detail=f"Product with id {product_id} not found")
        products.append(product)
    return products


@product_router.get("/products/tags", response_model=List[schemas.Tag])
async def get_all_tags(sess: Session = Depends(get_db)):
    return sess.query(models.Tag).all()


def _product_to_schema(product: models.Product) -> schemas.Product:
    return schemas.Product(
        id=product.id,
        brand=str(product.brand or ""),
        name=str(product.name or ""),
        company_id=int(product.company_id),
        picture_url=str(product.picture_url or ""),
        variation_group=product.variation_group,
        tags=[schemas.Tag_Instance(tag_id=int(t.tag_id)) for t in (product.tags or [])],
    )


@product_router.get(
    "/products/judgement-candidates",
    response_model=List[schemas.JudgementCandidate],
)
async def get_judgement_candidates(
    judgement_type: str = Query(..., pattern="^(staple|grouping)$"),
    user_id: int = Query(...),
    count: int = Query(5, ge=1, le=20),
    sess: Session = Depends(get_db),
):
    """Return random products for a user to judge.

    For 'staple': random products not yet staple-judged by this user.
    For 'grouping': random product pairs sharing a normalized name prefix
    that this user hasn't judged yet.
    """
    already_judged = (
        select(models.LabelJudgement.product_id)
        .where(
            models.LabelJudgement.user_id == user_id,
            models.LabelJudgement.judgement_type == judgement_type,
        )
    )

    if judgement_type == "staple":
        # Products already judged by this user for ANY staple name
        already_judged_staple = (
            select(
                models.LabelJudgement.product_id,
                models.LabelJudgement.staple_name,
            )
            .where(
                models.LabelJudgement.user_id == user_id,
                models.LabelJudgement.judgement_type == "staple",
            )
        )
        judged_pairs = {
            (r[0], r[1])
            for r in sess.execute(already_judged_staple).all()
        }

        # Pick random staple names and find matching products.
        # When existing labels are available, prioritise products where
        # the heuristic score is closest to 0.5 (highest uncertainty).
        shuffled_staples = list(_STAPLE_NAMES)
        random.shuffle(shuffled_staples)

        candidates: List[schemas.JudgementCandidate] = []
        for staple_name in shuffled_staples:
            if len(candidates) >= count:
                break

            pos_profiles, neg_profiles = _load_staple_labels(
                sess, staple_name,
            )

            products = (
                sess.query(models.Product)
                .filter(models.Product.name.ilike(f"%{staple_name}%"))
                .limit(400)
                .all()
            )

            unjudged = [
                p for p in products
                if (p.id, staple_name) not in judged_pairs
            ]

            if pos_profiles or neg_profiles:
                # Score by uncertainty — most uncertain first.
                scored = []
                for p in unjudged:
                    h = _staple_heuristic_score(
                        _word_set(p.name or ""),
                        _word_set(p.brand or ""),
                        pos_profiles,
                        neg_profiles,
                    )
                    uncertainty = 1.0 - abs(h - 0.5) * 2
                    scored.append((p, h, uncertainty))
                scored.sort(key=lambda x: -x[2])

                for p, h, _ in scored:
                    if len(candidates) >= count:
                        break
                    candidates.append(
                        schemas.JudgementCandidate(
                            product=_product_to_schema(p),
                            staple_name=staple_name,
                            heuristic_score=round(h, 3),
                        )
                    )
            else:
                # No labels yet — fall back to random.
                for p in unjudged:
                    if len(candidates) >= count:
                        break
                    candidates.append(
                        schemas.JudgementCandidate(
                            product=_product_to_schema(p),
                            staple_name=staple_name,
                        )
                    )
        return candidates

    # grouping: find pairs of same-brand products with similar names
    already_judged_pairs = (
        sess.query(
            models.LabelJudgement.product_id,
            models.LabelJudgement.target_product_id,
        )
        .filter(
            models.LabelJudgement.user_id == user_id,
            models.LabelJudgement.judgement_type == "grouping",
        )
        .all()
    )
    judged_pair_set = {(r[0], r[1]) for r in already_judged_pairs}
    judged_pair_set |= {(r[1], r[0]) for r in already_judged_pairs}

    # Pick random products and find potential grouping partners
    anchor_products = (
        sess.query(models.Product)
        .order_by(func.random())
        .limit(count * 5)
        .all()
    )

    candidates: List[schemas.JudgementCandidate] = []
    seen_pairs: set = set()
    for anchor in anchor_products:
        if len(candidates) >= count:
            break
        # Find products with similar names (same first word, different id)
        first_word = (anchor.name or "").split()[0].lower() if anchor.name else ""
        if len(first_word) < 2:
            continue
        similar = (
            sess.query(models.Product)
            .filter(
                models.Product.id != anchor.id,
                models.Product.name.ilike(f"{first_word}%"),
            )
            .order_by(func.random())
            .limit(1)
            .first()
        )
        if similar is None:
            continue
        pair_key = tuple(sorted((anchor.id, similar.id)))
        if pair_key in seen_pairs:
            continue
        if (anchor.id, similar.id) in judged_pair_set:
            continue
        seen_pairs.add(pair_key)
        candidates.append(
            schemas.JudgementCandidate(
                product=_product_to_schema(anchor),
                target_product=_product_to_schema(similar),
            )
        )

    return candidates


@product_router.post("/products/judgement", response_model=schemas.JudgementResponse)
async def submit_judgement(
    payload: schemas.JudgementRequest,
    sess: Session = Depends(get_db),
):
    """Record a user's staple or grouping judgement."""
    if payload.judgement_type not in ("staple", "grouping"):
        raise HTTPException(400, detail="judgement_type must be 'staple' or 'grouping'")
    if payload.judgement_type == "grouping" and payload.target_product_id is None:
        raise HTTPException(400, detail="target_product_id is required for grouping judgements")
    if payload.judgement_type == "staple" and not payload.staple_name:
        raise HTTPException(400, detail="staple_name is required for staple judgements")

    product = sess.get(models.Product, payload.product_id)
    if not product:
        raise HTTPException(404, detail=f"Product {payload.product_id} not found")
    if payload.target_product_id is not None:
        target = sess.get(models.Product, payload.target_product_id)
        if not target:
            raise HTTPException(404, detail=f"Target product {payload.target_product_id} not found")

    judgement = models.LabelJudgement(
        user_id=payload.user_id,
        product_id=payload.product_id,
        judgement_type=payload.judgement_type,
        staple_name=payload.staple_name,
        target_product_id=payload.target_product_id,
        approved=payload.approved,
        flavour=payload.flavour,
    )
    sess.add(judgement)
    sess.commit()
    sess.refresh(judgement)

    return schemas.JudgementResponse(
        id=int(judgement.id),
        user_id=int(judgement.user_id),
        product_id=int(judgement.product_id),
        judgement_type=str(judgement.judgement_type),
        staple_name=judgement.staple_name,
        target_product_id=int(judgement.target_product_id) if judgement.target_product_id else None,
        approved=bool(judgement.approved),
        flavour=judgement.flavour,
        created_at=judgement.created_at,
    )


@product_router.get(
    "/products/staple-judgements",
    response_model=List[schemas.StapleJudgementSummary],
)
async def get_staple_judgements(
    sess: Session = Depends(get_db),
):
    """Return aggregated staple judgement counts across all users."""
    rows = (
        sess.query(
            models.LabelJudgement.product_id,
            models.LabelJudgement.staple_name,
            func.sum(case((models.LabelJudgement.approved == True, 1), else_=0)).label("approvals"),
            func.sum(case((models.LabelJudgement.approved == False, 1), else_=0)).label("denials"),
        )
        .filter(
            models.LabelJudgement.judgement_type == "staple",
            models.LabelJudgement.staple_name.isnot(None),
        )
        .group_by(models.LabelJudgement.product_id, models.LabelJudgement.staple_name)
        .all()
    )
    return [
        schemas.StapleJudgementSummary(
            product_id=r.product_id,
            staple_name=r.staple_name,
            approvals=r.approvals,
            denials=r.denials,
        )
        for r in rows
    ]


@product_router.get(
    "/products/staples",
    response_model=Dict[str, List[schemas.Product_Details]],
)
async def get_staple_products_bulk(
    store_ids: List[int] = Query(default=[]),
    top_n: int = Query(default=12, ge=1, le=30),
    sess: Session = Depends(get_db),
):
    """Return top-ranked staple products per category, scored entirely server-side.

    Scoring mirrors the Flutter client's former _selectStapleProducts():
    - confidence based on product name vs staple keyword (ported from Dart)
    - boosted/penalised by crowdsourced judgements and cached heuristic scores
    - guaranteed at least one product per selected store (phase 1)
    - filled to top_n distinct products by score (phase 2)
    - variation-group deduplication to avoid redundant flavours
    - cross-staple claimed set so the same product doesn't appear in two cards

    Returns all store instances for each selected product so the Flutter client
    can show per-store price comparisons.  The client only needs trivial
    session-denial filtering after receiving this response.
    """
    result: Dict[str, List[schemas.Product_Details]] = {name: [] for name in _STAPLE_NAMES}
    if not store_ids:
        return result

    # --- Load aggregated staple judgements (one indexed query) ---
    judgement_rows = (
        sess.query(
            models.LabelJudgement.product_id,
            models.LabelJudgement.staple_name,
            func.sum(case((models.LabelJudgement.approved == True, 1), else_=0)).label("approvals"),
            func.sum(case((models.LabelJudgement.approved == False, 1), else_=0)).label("denials"),
        )
        .filter(
            models.LabelJudgement.judgement_type == "staple",
            models.LabelJudgement.staple_name.isnot(None),
        )
        .group_by(models.LabelJudgement.product_id, models.LabelJudgement.staple_name)
        .all()
    )
    # {staple_name: {product_id: net_score}}
    judgements: Dict[str, Dict[int, int]] = {}
    for product_id, staple_name, approvals, denials in judgement_rows:
        net = (approvals or 0) - (denials or 0)
        judgements.setdefault(staple_name, {})[int(product_id)] = net

    # --- Heuristics from in-process TTL cache (reuses get_staple_heuristics logic) ---
    global _heuristics_cache
    now = time.monotonic()
    heuristic_list: List[schemas.StapleHeuristic] = (
        _heuristics_cache[1]
        if _heuristics_cache is not None and now - _heuristics_cache[0] < _HEURISTICS_TTL
        else []
    )
    # {(staple_name, product_id) -> score}
    heuristics: Dict[Tuple[str, int], float] = {
        (h.staple_name, h.product_id): h.score for h in heuristic_list
    }

    # --- Single DB query ordered by name length (shorter = more specific) ---
    s = (
        select(models.Product, models.Product_Instance)
        .where(models.Product.id == models.Product_Instance.product_id)
        .where(models.Product_Instance.store_id.in_(store_ids))
        .where(
            or_(*(models.Product.name.ilike(f"%{name}%") for name in _STAPLE_NAMES))
        )
        .order_by(func.length(models.Product.name))
    )
    rows = sess.execute(s).all()

    # --- Group rows by staple, capping candidates at _MAX_PER_STAPLE unique products ---
    _MAX_PER_STAPLE = 100
    # staple_name -> {product_id: (Product model, min_effective_price)}
    staple_products: Dict[str, Dict[int, Tuple]] = {name: {} for name in _STAPLE_NAMES}
    # staple_name -> {product_id: set of store_ids}
    staple_product_stores: Dict[str, Dict[int, set]] = {name: {} for name in _STAPLE_NAMES}
    # (staple_name, product_id, store_id) -> (Product model, Product_Instance model)
    all_rows: Dict[Tuple, Tuple] = {}

    for p, pi in rows:
        pid = int(p.id)
        sid = int(pi.store_id)
        p_name_lower = (p.name or "").lower()
        for staple_name in _STAPLE_NAMES:
            if staple_name not in p_name_lower:
                continue
            sp = staple_products[staple_name]
            # Admit new products up to the cap; always include all instances
            # of products already in the candidate list.
            if pid not in sp:
                if len(sp) >= _MAX_PER_STAPLE:
                    continue
                sp[pid] = (p, float("inf"))
            # Track cheapest effective price across stores for tie-breaking.
            cur_p, cur_min = sp[pid]
            for pp in pi.price_points or []:
                try:
                    effective = float(pp.sale_price or pp.base_price or "inf")
                    if effective < cur_min:
                        cur_min = effective
                except (ValueError, TypeError):
                    pass
            sp[pid] = (cur_p, cur_min)
            staple_product_stores[staple_name].setdefault(pid, set()).add(sid)
            all_rows[(staple_name, pid, sid)] = (p, pi)

    # --- Score, rank, and select per staple with cross-staple deduplication ---
    # claimed_product_ids prevents the same product appearing in two cards
    # (e.g. "whole wheat bread" shouldn't show in both 'bread' and 'wheat').
    claimed_product_ids: set = set()

    for staple_name in _STAPLE_NAMES:
        sp = staple_products[staple_name]
        if not sp:
            continue

        staple_judgements = judgements.get(staple_name, {})

        def _score(pid: int, p, min_price: float) -> Tuple[float, float]:
            conf = _staple_confidence_py(p.name or "", staple_name)
            j = staple_judgements.get(pid)
            h = heuristics.get((staple_name, pid))
            if j is not None and j > 0:
                conf -= 0.5
            if j is None and h is not None:
                conf -= (h - 0.5) * 0.6
            return (conf, min_price if min_price != float("inf") else 1e9)

        # Filter denied (net < 0) and already-claimed products, then rank.
        candidates = sorted(
            [
                (pid, p, min_price)
                for pid, (p, min_price) in sp.items()
                if staple_judgements.get(pid, 0) >= 0
                and pid not in claimed_product_ids
            ],
            key=lambda x: _score(x[0], x[1], x[2]),
        )

        selected_ids: set = set()
        claimed_vg: set = set()

        def can_select(pid: int, p) -> bool:
            if pid in selected_ids:
                return True
            vg = p.variation_group
            return not (vg and vg in claimed_vg)

        def mark_selected(pid: int, p) -> None:
            selected_ids.add(pid)
            vg = p.variation_group
            if vg:
                claimed_vg.add(vg)

        # Phase 1: guarantee at least one distinct product per selected store.
        for sid in store_ids:
            if len(selected_ids) >= top_n:
                break
            for pid, p, _ in candidates:
                if sid in staple_product_stores[staple_name].get(pid, set()) and can_select(pid, p):
                    mark_selected(pid, p)
                    break

        # Phase 2: fill remaining slots with the highest-scored products.
        for pid, p, _ in candidates:
            if len(selected_ids) >= top_n:
                break
            if can_select(pid, p):
                mark_selected(pid, p)

        claimed_product_ids.update(selected_ids)

        # Build response: all store instances for selected products, in score order.
        for pid, p_m, _ in candidates:
            if pid not in selected_ids:
                continue
            for sid in store_ids:
                row = all_rows.get((staple_name, pid, sid))
                if row is None:
                    continue
                _, pi_m = row
                result[staple_name].append(
                    schemas.Product_Details(
                        Product=schemas.Product(
                            id=p_m.id,
                            brand=str(p_m.brand or ""),
                            name=str(p_m.name or ""),
                            company_id=int(p_m.company_id),
                            picture_url=str(p_m.picture_url or ""),
                            variation_group=p_m.variation_group,
                            tags=[schemas.Tag_Instance(tag_id=int(t.tag_id)) for t in (p_m.tags or [])],
                        ),
                        Product_Instance=schemas.Product_Instance(
                            store_id=int(pi_m.store_id),
                            price_points=[
                                schemas.PricePoint(
                                    base_price=str(pp.base_price or "0"),
                                    sale_price=pp.sale_price,
                                    member_price=pp.member_price,
                                    size=pp.size,
                                    created_at=pp.created_at,
                                )
                                for pp in (pi_m.price_points or [])
                            ],
                        ),
                    )
                )

    return result


@product_router.get(
    "/products/staple-heuristics",
    response_model=List[schemas.StapleHeuristic],
)
async def get_staple_heuristics(
    sess: Session = Depends(get_db),
):
    """Heuristic staple scores inferred from existing user labels.

    Results are cached in-process for up to one hour to avoid re-running
    the expensive per-staple DB + Python scoring on every page load.
    """
    global _heuristics_cache
    now = time.monotonic()
    if _heuristics_cache is not None and now - _heuristics_cache[0] < _HEURISTICS_TTL:
        return _heuristics_cache[1]

    results: List[schemas.StapleHeuristic] = []
    for staple_name in _STAPLE_NAMES:
        pos_profiles, neg_profiles = _load_staple_labels(sess, staple_name)
        if not pos_profiles and not neg_profiles:
            continue

        products = (
            sess.query(models.Product)
            .filter(models.Product.name.ilike(f"%{staple_name}%"))
            .limit(400)
            .all()
        )

        for p in products:
            score = _staple_heuristic_score(
                _word_set(p.name or ""),
                _word_set(p.brand or ""),
                pos_profiles,
                neg_profiles,
            )
            results.append(
                schemas.StapleHeuristic(
                    product_id=p.id,
                    staple_name=staple_name,
                    score=round(score, 3),
                )
            )

    _heuristics_cache = (now, results)
    return results


@product_router.get(
    "/products/grouping-judgements",
    response_model=List[schemas.GroupingJudgementSummary],
)
async def get_grouping_judgements(
    sess: Session = Depends(get_db),
):
    """Return aggregated grouping judgement counts across all users."""
    rows = (
        sess.query(
            models.LabelJudgement.product_id,
            models.LabelJudgement.target_product_id,
            func.sum(case((models.LabelJudgement.approved == True, 1), else_=0)).label("approvals"),
            func.sum(case((models.LabelJudgement.approved == False, 1), else_=0)).label("denials"),
        )
        .filter(
            models.LabelJudgement.judgement_type == "grouping",
            models.LabelJudgement.target_product_id.isnot(None),
        )
        .group_by(
            models.LabelJudgement.product_id,
            models.LabelJudgement.target_product_id,
        )
        .all()
    )
    return [
        schemas.GroupingJudgementSummary(
            product_id=r.product_id,
            target_product_id=r.target_product_id,
            approvals=r.approvals,
            denials=r.denials,
        )
        for r in rows
    ]


@product_router.get(
    "/products/{product_id}/variations",
    response_model=List[schemas.Product_Details],
)
async def get_product_variations(
    product_id: int,
    store_ids: List[int] = Query(default=[]),
    sess: Session = Depends(get_db),
):
    """Return other products in the same variation group, with price info
    scoped to the given store IDs."""
    product = sess.get(models.Product, product_id)
    if not product:
        raise HTTPException(404, detail=f"Product {product_id} not found")
    if not product.variation_group:
        return []

    q = (
        select(models.Product, models.Product_Instance)
        .where(models.Product.id == models.Product_Instance.product_id)
        .where(models.Product.variation_group == product.variation_group)
        .where(models.Product.id != product_id)
    )
    if store_ids:
        q = q.where(models.Product_Instance.store_id.in_(store_ids))
    q = q.order_by(func.length(models.Product.name))

    rows = sess.execute(q).all()
    return [
        schemas.Product_Details(
            Product=schemas.Product(
                id=p.id,
                brand=str(p.brand or ""),
                name=str(p.name or ""),
                company_id=int(p.company_id),
                picture_url=str(p.picture_url or ""),
                variation_group=p.variation_group,
                tags=[schemas.Tag_Instance(tag_id=int(t.tag_id)) for t in (p.tags or [])],
            ),
            Product_Instance=schemas.Product_Instance(
                store_id=int(pi.store_id),
                price_points=[
                    schemas.PricePoint(
                        base_price=str(pp.base_price or "0"),
                        sale_price=pp.sale_price,
                        member_price=pp.member_price,
                        size=pp.size,
                        created_at=pp.created_at,
                    )
                    for pp in (pi.price_points or [])
                ],
            ),
        )
        for p, pi in rows
    ]


add_pagination(product_router)