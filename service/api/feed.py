"""Feed endpoint — returns a mixed card feed for the Markup redesign."""

import random
import re
from typing import Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from sqlalchemy import func, distinct

from . import get_db
import models
from schemas.feed import (
    FeedResponse,
    FeedPriceReveal,
    FeedSavingsCard,
    FeedSavingsItem,
    FeedCommunityCard,
    PriceComparison,
)

feed_router = APIRouter()

_price_pattern = re.compile(r"-?\d+(?:\.\d+)?")


def _parse_price(value: Optional[str]) -> Optional[float]:
    if value is None:
        return None
    match = _price_pattern.search(str(value).replace(",", ""))
    if not match:
        return None
    return float(match.group(0))


def _effective_price(pp) -> Optional[float]:
    return (
        _parse_price(pp.member_price)
        or _parse_price(pp.sale_price)
        or _parse_price(pp.base_price)
    )


def _get_store_ids_for_zipcode(zipcode: Optional[str], sess: Session) -> Optional[list]:
    """Return store IDs for a zipcode, or None to indicate 'all stores'."""
    if not zipcode:
        return None
    store_ids = [
        row[0]
        for row in sess.query(models.Store.id).filter(models.Store.zipcode == zipcode).all()
    ]
    if not store_ids:
        return None  # fall back to all stores
    return store_ids


def _build_price_reveal_cards(sess: Session, store_ids: Optional[list]) -> list[FeedPriceReveal]:
    """
    Find products that appear in 2+ different company chains and have
    a meaningful price spread (max_savings > $0.50).
    """
    # Query product instances with their latest price points, grouped by product
    # Step 1: get product_ids that have instances in 2+ distinct companies
    instance_q = sess.query(
        models.Product_Instance.product_id,
        func.count(distinct(models.Store.company_id)).label("company_count"),
    ).join(
        models.Store, models.Product_Instance.store_id == models.Store.id
    )

    if store_ids is not None:
        instance_q = instance_q.filter(models.Product_Instance.store_id.in_(store_ids))

    multi_company_rows = (
        instance_q.group_by(models.Product_Instance.product_id)
        .having(func.count(distinct(models.Store.company_id)) >= 2)
        .all()
    )

    eligible_product_ids = [row[0] for row in multi_company_rows]
    if not eligible_product_ids:
        return []

    # Step 2: for each eligible product, get latest price per company
    cards = []
    for product_id in eligible_product_ids:
        product = sess.get(models.Product, product_id)
        if not product:
            continue

        instances = (
            sess.query(models.Product_Instance)
            .filter(models.Product_Instance.product_id == product_id)
            .all()
        )
        if store_ids is not None:
            instances = [i for i in instances if i.store_id in store_ids]

        # Collect best price per company
        company_prices: dict[int, dict] = {}  # company_id -> {price, chain, size}
        for inst in instances:
            store = sess.get(models.Store, inst.store_id)
            if not store:
                continue
            company = sess.get(models.Company, store.company_id)
            if not company:
                continue

            latest_pp = (
                sess.query(models.PricePoint)
                .filter(models.PricePoint.instance_id == inst.id)
                .order_by(models.PricePoint.created_at.desc())
                .first()
            )
            if not latest_pp:
                continue
            price = _effective_price(latest_pp)
            if price is None:
                continue

            cid = company.id
            if cid not in company_prices or price < company_prices[cid]["price"]:
                company_prices[cid] = {
                    "price": price,
                    "chain": company.name or company.slug,
                    "size": latest_pp.size or "",
                }

        if len(company_prices) < 2:
            continue

        prices_sorted = sorted(company_prices.items(), key=lambda x: x[1]["price"])
        best_price = prices_sorted[0][1]["price"]
        worst_price = prices_sorted[-1][1]["price"]
        max_savings = round(worst_price - best_price, 2)

        if max_savings < 0.50:
            continue

        price_comparisons = []
        for cid, info in company_prices.items():
            price_comparisons.append(
                PriceComparison(
                    chain=info["chain"],
                    company_id=cid,
                    price=info["price"],
                    is_best=(info["price"] == best_price),
                    diff_from_best=round(info["price"] - best_price, 2),
                )
            )

        # Use the size from the best-priced company
        best_size = prices_sorted[0][1]["size"]

        cards.append(
            FeedPriceReveal(
                product_id=product.id,
                product_name=product.name or product.raw_name or "",
                brand=product.brand or "",
                size=best_size,
                picture_url=product.picture_url,
                prices=price_comparisons,
                max_savings=max_savings,
            )
        )

    # Sort descending by max_savings for most impactful cards first
    cards.sort(key=lambda c: c.max_savings, reverse=True)
    return cards


def _build_savings_card(
    price_reveals: list[FeedPriceReveal],
) -> Optional[FeedSavingsCard]:
    """Build a savings ranking card from the top 5 price reveal cards."""
    if not price_reveals:
        return None

    items = []
    for reveal in price_reveals[:5]:
        prices_sorted = sorted(reveal.prices, key=lambda p: p.price)
        cheapest = prices_sorted[0]
        expensive = prices_sorted[-1]
        savings_pct = (
            round((expensive.price - cheapest.price) / expensive.price * 100, 1)
            if expensive.price > 0
            else 0.0
        )
        items.append(
            FeedSavingsItem(
                product_id=reveal.product_id,
                product_name=reveal.product_name,
                cheap_chain=cheapest.chain,
                expensive_chain=expensive.chain,
                savings=reveal.max_savings,
                savings_pct=savings_pct,
            )
        )

    return FeedSavingsCard(items=items)


def _build_community_card(sess: Session) -> Optional[FeedCommunityCard]:
    """Pick a random product pair for a grouping judgement challenge."""
    # Pick two random products from the DB
    total = sess.query(func.count(models.Product.id)).scalar() or 0
    if total < 2:
        return None

    # Pick a random product as the subject
    offset = random.randint(0, total - 1)
    product = sess.query(models.Product).offset(offset).first()
    if not product:
        return None

    # Pick a different random product as the target
    target = None
    attempts = 0
    while attempts < 5:
        t_offset = random.randint(0, total - 1)
        candidate = sess.query(models.Product).offset(t_offset).first()
        if candidate and candidate.id != product.id:
            target = candidate
            break
        attempts += 1

    if not target:
        return None

    return FeedCommunityCard(
        judgement_type="grouping",
        product_id=product.id,
        product_name=product.name or product.raw_name or "",
        product_brand=product.brand or "",
        target_product_id=target.id,
        target_product_name=target.name or target.raw_name or "",
        target_product_brand=target.brand or "",
    )


@feed_router.get("/feed", response_model=FeedResponse)
async def get_feed(
    page: int = Query(default=1, ge=1),
    size: int = Query(default=10, ge=1, le=50),
    zipcode: Optional[str] = Query(default=None),
    sess: Session = Depends(get_db),
):
    store_ids = _get_store_ids_for_zipcode(zipcode, sess)

    # Build raw price reveal cards (all of them — we paginate below)
    all_reveals = _build_price_reveal_cards(sess, store_ids)

    # Savings card from top 5 reveals
    savings_card = _build_savings_card(all_reveals)

    # Community challenge card
    community_card = _build_community_card(sess)

    # Interleave into a flat list (positions 0-based):
    #   position 3 -> savings card
    #   position 6 -> community card
    #   all others -> price reveal cards

    reveal_iter = iter(all_reveals)
    interleaved: list = []
    reveal_idx = 0

    # We'll build enough items to cover (page * size) + some buffer so we can
    # slice the requested page.  In practice we just build all items up to
    # page * size + 2 (for the two special cards that shift positions).
    max_position = page * size + 2

    pos = 0
    savings_inserted = False
    community_inserted = False

    while pos < max_position:
        if pos == 3 and not savings_inserted and savings_card is not None:
            interleaved.append(savings_card.model_dump())
            savings_inserted = True
        elif pos == 6 and not community_inserted and community_card is not None:
            interleaved.append(community_card.model_dump())
            community_inserted = True
        else:
            try:
                reveal = next(reveal_iter)
                interleaved.append(reveal.model_dump())
            except StopIteration:
                break
        pos += 1

    # Paginate
    start = (page - 1) * size
    end = start + size
    page_items = interleaved[start:end]
    has_more = len(interleaved) > end or len(all_reveals) > (end - (1 if savings_inserted else 0) - (1 if community_inserted else 0))

    return FeedResponse(
        items=page_items,
        page=page,
        has_more=has_more,
    )
