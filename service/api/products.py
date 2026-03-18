from typing import List, Optional
import random
import re

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from fastapi_pagination import Page, add_pagination
from fastapi_pagination.ext.sqlalchemy import paginate
from sqlalchemy import select, func, and_, case

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
    "/products/staple-heuristics",
    response_model=List[schemas.StapleHeuristic],
)
async def get_staple_heuristics(
    sess: Session = Depends(get_db),
):
    """Heuristic staple scores inferred from existing user labels.

    For each staple name that has labelled products, scores other matching
    products by their similarity to confirmed positives and distance from
    confirmed negatives.
    """
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