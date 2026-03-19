from typing import Dict, List, Optional, Tuple
import asyncio
import json
import logging
import random
import re
import time
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session, selectinload
from fastapi_pagination import Page, add_pagination
from fastapi_pagination.ext.sqlalchemy import paginate
from sqlalchemy import or_, select, func, and_, case

from . import get_db, SessionLocal
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

# ---------------------------------------------------------------------------
# Per-store staple cache backed by the DB (staple_store_cache table).
# Each row holds a ranked JSON list of candidates for one (store, staple).
# The cache is refreshed in the background; stale rows are served as-is
# while a new computation runs so no user request ever blocks on a recompute.
# ---------------------------------------------------------------------------
_STORE_CACHE_TTL_SECONDS = 3600  # rows older than this are considered stale
_logger = logging.getLogger(__name__)

# Prevents multiple concurrent refreshes for the same (store_id, staple_name).
_refresh_in_flight: set = set()


def _now_utc() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _compute_store_staple_candidates(
    sess: Session,
    store_id: int,
    staple_name: str,
    judgements: Dict[int, int],
    heuristics: Dict[Tuple[str, int], float],
) -> list:
    """Return a scored, sorted candidate list for one (store_id, staple_name).

    Each entry: {"product_id": int, "score": float, "variation_group": str|None}.
    Denied products (net judgement < 0) are excluded.
    """
    rows = (
        sess.query(models.Product)
        .join(models.Product_Instance, models.Product_Instance.product_id == models.Product.id)
        .filter(
            models.Product_Instance.store_id == store_id,
            models.Product.name.ilike(f"%{staple_name}%"),
        )
        .distinct(models.Product.id)
        .all()
    )
    staple_judgements = judgements  # already scoped to this staple by caller
    candidates = []
    for p in rows:
        pid = int(p.id)
        j = staple_judgements.get(pid)
        if j is not None and j < 0:
            continue  # user community denied this product for this staple
        conf = _staple_confidence_py(p.name or "", staple_name)
        h = heuristics.get((staple_name, pid))
        if j is not None and j > 0:
            conf -= 0.5
        if j is None and h is not None:
            conf -= (h - 0.5) * 0.6
        candidates.append({
            "product_id": pid,
            "score": round(conf, 4),
            "variation_group": p.variation_group,
        })
    candidates.sort(key=lambda x: x["score"])
    return candidates


def _write_store_staple_cache(sess: Session, store_id: int, staple_name: str, candidates: list) -> None:
    entry = sess.get(models.StapleStoreCache, {"store_id": store_id, "staple_name": staple_name})
    if entry is None:
        entry = models.StapleStoreCache(store_id=store_id, staple_name=staple_name)
        sess.add(entry)
    entry.ranked_json = json.dumps(candidates)
    entry.computed_at = _now_utc()
    sess.commit()


def _load_all_judgements() -> Dict[str, Dict[int, int]]:
    """Return {staple_name: {product_id: net_score}} using a fresh DB session."""
    with SessionLocal() as sess:
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
    result: Dict[str, Dict[int, int]] = {}
    for product_id, staple_name, approvals, denials in rows:
        if staple_name:
            net = (approvals or 0) - (denials or 0)
            result.setdefault(staple_name, {})[int(product_id)] = net
    return result


def _load_all_heuristics() -> Dict[Tuple[str, int], float]:
    """Return {(staple_name, product_id): score} using a fresh DB session."""
    global _heuristics_cache
    now = time.monotonic()
    if _heuristics_cache is not None and now - _heuristics_cache[0] < _HEURISTICS_TTL:
        return {(h.staple_name, h.product_id): h.score for h in _heuristics_cache[1]}

    results: List[schemas.StapleHeuristic] = []
    with SessionLocal() as sess:
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
                results.append(schemas.StapleHeuristic(
                    product_id=p.id,
                    staple_name=staple_name,
                    score=round(score, 3),
                ))
    _heuristics_cache = (now, results)
    return {(h.staple_name, h.product_id): h.score for h in results}


def _refresh_store_staple_sync(store_id: int, staple_name: str) -> None:
    """Synchronously recompute and persist one (store, staple) cache entry."""
    judgements = _load_all_judgements()
    heuristics = _load_all_heuristics()
    staple_j = judgements.get(staple_name, {})
    with SessionLocal() as sess:
        candidates = _compute_store_staple_candidates(sess, store_id, staple_name, staple_j, heuristics)
        _write_store_staple_cache(sess, store_id, staple_name, candidates)


async def _bg_refresh_store_staple(store_id: int, staple_name: str) -> None:
    """Async wrapper: run the sync refresh in the default thread-pool executor."""
    key = (store_id, staple_name)
    if key in _refresh_in_flight:
        return
    _refresh_in_flight.add(key)
    try:
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, _refresh_store_staple_sync, store_id, staple_name)
    except Exception:
        _logger.exception("Background staple cache refresh failed for store=%s staple=%s", store_id, staple_name)
    finally:
        _refresh_in_flight.discard(key)


def _all_store_ids_sync() -> List[int]:
    with SessionLocal() as sess:
        return [r[0] for r in sess.query(models.Store.id).all()]


def _schedule_full_refresh() -> None:
    """Fire-and-forget: refresh every (store, staple) pair in the background."""
    async def _run_all():
        store_ids = await asyncio.get_event_loop().run_in_executor(None, _all_store_ids_sync)
        tasks = [
            _bg_refresh_store_staple(sid, sname)
            for sid in store_ids
            for sname in _STAPLE_NAMES
        ]
        await asyncio.gather(*tasks)

    try:
        loop = asyncio.get_event_loop()
        if loop.is_running():
            asyncio.ensure_future(_run_all())
        else:
            loop.run_until_complete(_run_all())
    except RuntimeError:
        pass  # no event loop yet (e.g. during import) — skip


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

    # Invalidate heuristics cache and pre-emptively refresh all per-store staple
    # caches in the background so no user request pays the recompute cost.
    global _heuristics_cache
    _heuristics_cache = None
    _schedule_full_refresh()

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
    """Return top-ranked staple products per category, served from per-store DB cache.

    Each (store, staple) pair has a precomputed ranked candidate list stored in
    the ``staple_store_cache`` table.  This endpoint merges those per-store lists,
    applies cross-staple deduplication, and fetches full product+price details only
    for the selected products — a much smaller DB hit than the old full scan.

    Stale or missing cache entries are refreshed in the background (not blocking
    the current request); the caller receives the best available data immediately.
    """
    result: Dict[str, List[schemas.Product_Details]] = {name: [] for name in _STAPLE_NAMES}
    if not store_ids:
        return result

    now_dt = _now_utc()
    stale_pairs: List[Tuple[int, str]] = []

    # --- Load per-store cache rows for all requested (store, staple) pairs ---
    # {staple_name: {product_id: {"score": float, "variation_group": str|None}}}
    staple_candidates: Dict[str, Dict[int, dict]] = {name: {} for name in _STAPLE_NAMES}
    # {staple_name: {product_id: set_of_store_ids}}
    staple_product_stores: Dict[str, Dict[int, set]] = {name: {} for name in _STAPLE_NAMES}

    cache_rows = (
        sess.query(models.StapleStoreCache)
        .filter(models.StapleStoreCache.store_id.in_(store_ids))
        .all()
    )
    cache_index: Dict[Tuple[int, str], models.StapleStoreCache] = {
        (r.store_id, r.staple_name): r for r in cache_rows
    }

    for sid in store_ids:
        for staple_name in _STAPLE_NAMES:
            row = cache_index.get((sid, staple_name))
            if row is None:
                stale_pairs.append((sid, staple_name))
                continue
            age = (now_dt - row.computed_at).total_seconds() if row.computed_at else float("inf")
            if age > _STORE_CACHE_TTL_SECONDS:
                stale_pairs.append((sid, staple_name))
                # Still use the stale data — refresh happens in the background below.
            try:
                candidates = json.loads(row.ranked_json or "[]")
            except Exception:
                candidates = []
            for entry in candidates:
                pid = entry["product_id"]
                existing = staple_candidates[staple_name].get(pid)
                if existing is None or entry["score"] < existing["score"]:
                    staple_candidates[staple_name][pid] = {
                        "score": entry["score"],
                        "variation_group": entry.get("variation_group"),
                    }
                staple_product_stores[staple_name].setdefault(pid, set()).add(sid)

    # --- Trigger background refresh for stale / missing entries ---
    for sid, staple_name in stale_pairs:
        asyncio.ensure_future(_bg_refresh_store_staple(sid, staple_name))

    # --- Option A: Run full cross-staple selection from in-memory cache data
    # BEFORE issuing any DB query.  The cache already has scores + store sets,
    # so we don't need the DB to decide which ~240 products to keep.
    # This avoids JOINing all 11 000+ candidate rows just to discard 97% of them.
    claimed_product_ids: set = set()
    per_staple_selections: Dict[str, set] = {}

    for staple_name in _STAPLE_NAMES:
        cands = staple_candidates[staple_name]
        if not cands:
            per_staple_selections[staple_name] = set()
            continue

        sorted_cands = sorted(cands.items(), key=lambda x: x[1]["score"])

        selected_ids: set = set()
        claimed_vg: set = set()

        def _can_select(pid: int, vg, _sel=selected_ids, _vg=claimed_vg) -> bool:
            return pid in _sel or not (vg and vg in _vg)

        def _mark(pid: int, vg, _sel=selected_ids, _vg=claimed_vg) -> None:
            _sel.add(pid)
            if vg:
                _vg.add(vg)

        # Exclude products already claimed by an earlier staple category.
        available = [(pid, meta) for pid, meta in sorted_cands if pid not in claimed_product_ids]

        # Phase 1: guarantee at least one product per selected store.
        for sid in store_ids:
            if len(selected_ids) >= top_n:
                break
            for pid, meta in available:
                if sid in staple_product_stores[staple_name].get(pid, set()) and _can_select(pid, meta["variation_group"]):
                    _mark(pid, meta["variation_group"])
                    break

        # Phase 2: fill remaining slots with best-scored products.
        for pid, meta in available:
            if len(selected_ids) >= top_n:
                break
            if _can_select(pid, meta["variation_group"]):
                _mark(pid, meta["variation_group"])

        claimed_product_ids.update(selected_ids)
        per_staple_selections[staple_name] = selected_ids

    if not claimed_product_ids:
        return result

    # --- Option B: Fetch only the ~240 selected products, with tags and
    # price_points loaded eagerly in two bulk IN queries (no N+1 lazy loads). ---
    product_rows = sess.execute(
        select(models.Product)
        .options(selectinload(models.Product.tags))
        .where(models.Product.id.in_(list(claimed_product_ids)))
    ).scalars().all()
    product_map: Dict[int, models.Product] = {int(p.id): p for p in product_rows}

    instance_rows = sess.execute(
        select(models.Product_Instance)
        .options(selectinload(models.Product_Instance.price_points))
        .where(models.Product_Instance.store_id.in_(store_ids))
        .where(models.Product_Instance.product_id.in_(list(claimed_product_ids)))
    ).scalars().all()
    instance_map: Dict[Tuple[int, int], models.Product_Instance] = {
        (int(pi.product_id), int(pi.store_id)): pi for pi in instance_rows
    }

    # --- Build response using pre-selected IDs and fully-loaded ORM objects ---
    for staple_name in _STAPLE_NAMES:
        selected_ids = per_staple_selections.get(staple_name, set())
        if not selected_ids:
            continue
        cands = staple_candidates[staple_name]
        for pid, _ in sorted(cands.items(), key=lambda x: x[1]["score"]):
            if pid not in selected_ids or pid not in product_map:
                continue
            p_m = product_map[pid]
            for sid in store_ids:
                pi_m = instance_map.get((pid, sid))
                if pi_m is None:
                    continue
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
    heuristics = _load_all_heuristics()
    return [
        schemas.StapleHeuristic(product_id=pid, staple_name=sname, score=score)
        for (sname, pid), score in heuristics.items()
    ]


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