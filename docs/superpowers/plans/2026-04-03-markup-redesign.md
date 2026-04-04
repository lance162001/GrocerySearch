# Markup Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebrand GrocerySearch to "Markup" with a 4-tab frontend (Feed, Search, Tracking, Play), anonymous-first auth, and new backend endpoints for feed curation, price tracking, and points.

**Architecture:** Backend-first approach. Add new DB tables and endpoints without breaking existing ones, then rebuild the Flutter frontend around a tab-based shell. Existing screens are replaced, not modified — old files are deleted after new ones are working. The existing API contract is preserved for backwards compatibility during development.

**Tech Stack:** Python/FastAPI/SQLAlchemy (backend), Flutter/Dart (frontend), SQLite (dev) / PostgreSQL (prod)

**Spec:** `docs/superpowers/specs/2026-04-03-basket-redesign-design.md`

---

## File Map

### Backend — New Files
- `service/models/tracking.py` — Tracked_Item and User_Points ORM models
- `service/schemas/tracking.py` — Pydantic schemas for tracking & points
- `service/schemas/feed.py` — Pydantic schemas for feed endpoint
- `service/api/feed.py` — Feed endpoint router
- `service/api/tracking.py` — Tracking endpoints router

### Backend — Modified Files
- `service/models/bootstrap.py` — Register new tables, ensure columns
- `service/api/__init__.py` — Register new routers
- `service/api/products.py` — Make store_ids optional on product search
- `service/api/users.py` — Add points increment to judgement endpoint
- `service/schemas/products.py` — Add chain filter field

### Frontend — New Files
- `app/lib/screens/feed_screen.dart` — Feed tab
- `app/lib/screens/search_screen.dart` — Redesigned search tab
- `app/lib/screens/tracking_screen.dart` — Tracking tab
- `app/lib/screens/tracking_detail_screen.dart` — Item detail with price history
- `app/lib/screens/play_screen.dart` — Play tab with game + challenges
- `app/lib/screens/profile_sheet.dart` — Profile bottom sheet
- `app/lib/widgets/feed_price_reveal_card.dart` — Price reveal card widget
- `app/lib/widgets/feed_savings_card.dart` — Biggest savings card widget
- `app/lib/widgets/feed_community_card.dart` — Inline community challenge card
- `app/lib/widgets/search_result_card.dart` — Grouped search result card
- `app/lib/widgets/tracked_item_card.dart` — Tracked item list card
- `app/lib/widgets/challenge_card.dart` — Product match / staple check card
- `app/lib/widgets/location_banner.dart` — Location opt-in banner
- `app/lib/widgets/filter_chips_bar.dart` — Horizontal scrollable filter chips
- `app/lib/services/location_service.dart` — Local storage for location/zip
- `app/lib/services/tracking_service.dart` — Local storage for anonymous tracking
- `app/lib/state/markup_state.dart` — New app state for Markup
- `app/lib/config/markup_theme.dart` — Theme constants and colors

### Frontend — Modified Files
- `app/lib/main.dart` — New route setup, tab shell, remove auth gate
- `app/lib/config/app_routes.dart` — New route constants
- `app/lib/services/grocery_api.dart` — New API methods for feed, tracking, points
- `app/lib/models/grocery_models.dart` — New model classes (FeedItem, TrackedItem, etc.)

### Frontend — Deleted After Migration
- `app/lib/main_search.dart` (replaced by feed_screen + search_screen)
- `app/lib/product_search.dart` (replaced by search_screen)
- `app/lib/staples_overview.dart` (staples surface in feed)
- `app/lib/check_out.dart` (no cart)
- `app/lib/bundle_plan.dart` (replaced by tracking)
- `app/lib/shared_bundle_page.dart` (deferred)
- `app/lib/chart.dart` (inline in tracking detail)
- `app/lib/label_judgement.dart` (replaced by play_screen)

---

## Task 1: Backend — Tracked Items & Points Schema

**Files:**
- Create: `service/models/tracking.py`
- Modify: `service/models/bootstrap.py`
- Test: `service/tests/test_tracking_schema.py`

- [ ] **Step 1: Write the failing test for new tables**

```python
# service/tests/test_tracking_schema.py
import pytest
from sqlalchemy import inspect
from models.base import engine, Base


def test_tracked_items_table_exists():
    insp = inspect(engine)
    assert "tracked_items" in insp.get_table_names()
    cols = {c["name"] for c in insp.get_columns("tracked_items")}
    assert cols >= {"id", "user_id", "product_id", "created_at"}


def test_user_points_table_exists():
    insp = inspect(engine)
    assert "user_points" in insp.get_table_names()
    cols = {c["name"] for c in insp.get_columns("user_points")}
    assert cols >= {"id", "user_id", "points", "updated_at"}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd service && python -m pytest tests/test_tracking_schema.py -v`
Expected: FAIL — tables don't exist yet

- [ ] **Step 3: Create the tracking models**

```python
# service/models/tracking.py
from sqlalchemy import Column, Integer, ForeignKey, DateTime, func
from models.base import Base


class Tracked_Item(Base):
    __tablename__ = "tracked_items"
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    product_id = Column(Integer, ForeignKey("products.id"), nullable=False)
    created_at = Column(DateTime, server_default=func.now())

    __table_args__ = (
        {"sqlite_autoincrement": True},
    )


class User_Points(Base):
    __tablename__ = "user_points"
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, unique=True)
    points = Column(Integer, nullable=False, default=0)
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        {"sqlite_autoincrement": True},
    )
```

- [ ] **Step 4: Register models in bootstrap**

In `service/models/bootstrap.py`, add import at top:

```python
import models.tracking  # noqa: F401 — registers tables with Base
```

This ensures `Base.metadata.create_all()` picks up the new tables.

- [ ] **Step 5: Add unique constraint and indexes via bootstrap**

In `service/models/bootstrap.py`, inside `ensure_runtime_schema()`, add after existing index creation:

```python
_safe_create_index(
    "ix_tracked_items_user_id",
    "tracked_items",
    ["user_id"],
)
_safe_create_index(
    "ix_tracked_items_user_product",
    "tracked_items",
    ["user_id", "product_id"],
    unique=True,
)
```

- [ ] **Step 6: Run test to verify it passes**

Run: `cd service && python -m pytest tests/test_tracking_schema.py -v`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add service/models/tracking.py service/models/bootstrap.py service/tests/test_tracking_schema.py
git commit -m "feat: add tracked_items and user_points DB tables"
```

---

## Task 2: Backend — Tracking Schemas & Endpoints

**Files:**
- Create: `service/schemas/tracking.py`
- Create: `service/api/tracking.py`
- Modify: `service/api/__init__.py`
- Test: `service/tests/test_tracking_api.py`

- [ ] **Step 1: Create Pydantic schemas for tracking**

```python
# service/schemas/tracking.py
from pydantic import BaseModel
from datetime import datetime
from typing import Optional


class TrackRequest(BaseModel):
    user_id: int
    product_id: int


class TrackedItemResponse(BaseModel):
    id: int
    user_id: int
    product_id: int
    product_name: str
    brand: str
    picture_url: Optional[str] = None
    company_name: str
    company_id: int
    current_price: Optional[float] = None
    previous_price: Optional[float] = None
    price_change: Optional[str] = None  # "drop", "up", or None
    price_change_at: Optional[datetime] = None
    stable_weeks: Optional[int] = None
    cheapest_chain: Optional[str] = None
    cheapest_price: Optional[float] = None
    created_at: datetime

    class Config:
        from_attributes = True


class TrackedItemDetail(TrackedItemResponse):
    """Extended detail with all-store prices and history."""
    all_store_prices: list  # [{chain, store_id, price, is_best}]
    price_history: list  # [{timestamp, chain, price}]


class PointsResponse(BaseModel):
    user_id: int
    points: int
    labels_submitted: int
    accuracy: Optional[float] = None
    monthly_rank: Optional[int] = None
```

- [ ] **Step 2: Write the failing test for tracking endpoints**

```python
# service/tests/test_tracking_api.py
import pytest
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)


@pytest.fixture(autouse=True)
def _setup_user():
    """Create a test user."""
    resp = client.post("/users/create")
    assert resp.status_code == 200
    return resp.json()["id"]


def test_track_item(_setup_user):
    user_id = _setup_user
    resp = client.post("/tracking/track", json={"user_id": user_id, "product_id": 1})
    assert resp.status_code == 200
    data = resp.json()
    assert data["product_id"] == 1
    assert data["user_id"] == user_id


def test_list_tracked_items(_setup_user):
    user_id = _setup_user
    client.post("/tracking/track", json={"user_id": user_id, "product_id": 1})
    resp = client.get(f"/tracking/tracked?user_id={user_id}")
    assert resp.status_code == 200
    items = resp.json()
    assert len(items) >= 1


def test_untrack_item(_setup_user):
    user_id = _setup_user
    client.post("/tracking/track", json={"user_id": user_id, "product_id": 1})
    resp = client.delete(f"/tracking/track/{1}?user_id={user_id}")
    assert resp.status_code == 200
    # Verify it's gone
    resp = client.get(f"/tracking/tracked?user_id={user_id}")
    items = resp.json()
    product_ids = [i["product_id"] for i in items]
    assert 1 not in product_ids


def test_track_duplicate_is_idempotent(_setup_user):
    user_id = _setup_user
    client.post("/tracking/track", json={"user_id": user_id, "product_id": 1})
    resp = client.post("/tracking/track", json={"user_id": user_id, "product_id": 1})
    assert resp.status_code == 200
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd service && python -m pytest tests/test_tracking_api.py -v`
Expected: FAIL — endpoint doesn't exist

- [ ] **Step 4: Implement tracking router**

```python
# service/api/tracking.py
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from sqlalchemy import func, text
from datetime import datetime, timedelta

from api import get_db
from models.tracking import Tracked_Item, User_Points
from models.products import Product, Product_Instance, Price_Point, Company
from schemas.tracking import (
    TrackRequest,
    TrackedItemResponse,
    TrackedItemDetail,
    PointsResponse,
)

router = APIRouter(prefix="/tracking", tags=["tracking"])


@router.post("/track", response_model=TrackedItemResponse)
def track_item(req: TrackRequest, db: Session = Depends(get_db)):
    existing = (
        db.query(Tracked_Item)
        .filter_by(user_id=req.user_id, product_id=req.product_id)
        .first()
    )
    if existing:
        return _tracked_item_response(db, existing)

    item = Tracked_Item(user_id=req.user_id, product_id=req.product_id)
    db.add(item)
    db.commit()
    db.refresh(item)
    return _tracked_item_response(db, item)


@router.delete("/track/{product_id}")
def untrack_item(
    product_id: int,
    user_id: int = Query(...),
    db: Session = Depends(get_db),
):
    item = (
        db.query(Tracked_Item)
        .filter_by(user_id=user_id, product_id=product_id)
        .first()
    )
    if not item:
        raise HTTPException(404, "Not tracking this item")
    db.delete(item)
    db.commit()
    return {"status": "ok"}


@router.get("/tracked", response_model=list[TrackedItemResponse])
def list_tracked(
    user_id: int = Query(...),
    db: Session = Depends(get_db),
):
    items = (
        db.query(Tracked_Item)
        .filter_by(user_id=user_id)
        .order_by(Tracked_Item.created_at.desc())
        .all()
    )
    return [_tracked_item_response(db, it) for it in items]


@router.get("/tracked/{product_id}", response_model=TrackedItemDetail)
def tracked_detail(
    product_id: int,
    user_id: int = Query(...),
    db: Session = Depends(get_db),
):
    item = (
        db.query(Tracked_Item)
        .filter_by(user_id=user_id, product_id=product_id)
        .first()
    )
    if not item:
        raise HTTPException(404, "Not tracking this item")
    return _tracked_item_detail(db, item)


@router.get("/points", response_model=PointsResponse)
def get_points(user_id: int = Query(...), db: Session = Depends(get_db)):
    row = db.query(User_Points).filter_by(user_id=user_id).first()
    points = row.points if row else 0

    from models.products import Label_Judgement

    labels_submitted = (
        db.query(func.count(Label_Judgement.id))
        .filter_by(user_id=user_id)
        .scalar()
    )
    return PointsResponse(
        user_id=user_id,
        points=points,
        labels_submitted=labels_submitted or 0,
    )


# ── helpers ──────────────────────────────────────────────


def _latest_prices_for_product(db: Session, product_id: int):
    """Get latest price per instance for a product, with store/company info."""
    instances = (
        db.query(Product_Instance)
        .filter_by(product_id=product_id)
        .all()
    )
    results = []
    for inst in instances:
        pp = (
            db.query(Price_Point)
            .filter_by(instance_id=inst.id)
            .order_by(Price_Point.created_at.desc())
            .first()
        )
        if not pp:
            continue
        from models.stores import Store, Company as CompanyModel

        store = db.query(Store).get(inst.store_id)
        company = db.query(CompanyModel).get(store.company_id) if store else None
        price = _lowest_price(pp)
        results.append(
            {
                "instance_id": inst.id,
                "store_id": inst.store_id,
                "company_id": company.id if company else None,
                "chain": company.name if company else "Unknown",
                "price": price,
                "price_point": pp,
            }
        )
    return results


def _lowest_price(pp: Price_Point) -> float:
    prices = []
    for attr in ("base_price", "sale_price", "member_price"):
        val = getattr(pp, attr, None)
        if val:
            try:
                prices.append(float(val.replace("$", "").replace(",", "")))
            except (ValueError, AttributeError):
                pass
    return min(prices) if prices else 0.0


def _price_change_info(db: Session, product_id: int):
    """Compare last two price points to detect change."""
    instances = (
        db.query(Product_Instance)
        .filter_by(product_id=product_id)
        .all()
    )
    if not instances:
        return None, None, None, None

    # Find cheapest current instance
    best = None
    best_price = float("inf")
    for inst in instances:
        pp = (
            db.query(Price_Point)
            .filter_by(instance_id=inst.id)
            .order_by(Price_Point.created_at.desc())
            .first()
        )
        if pp:
            p = _lowest_price(pp)
            if p < best_price:
                best_price = p
                best = (inst, pp)

    if not best:
        return None, None, None, None

    inst, latest_pp = best
    prev_pp = (
        db.query(Price_Point)
        .filter_by(instance_id=inst.id)
        .order_by(Price_Point.created_at.desc())
        .offset(1)
        .first()
    )
    if not prev_pp:
        return best_price, None, None, None

    prev_price = _lowest_price(prev_pp)
    if best_price < prev_price:
        return best_price, prev_price, "drop", latest_pp.created_at
    elif best_price > prev_price:
        return best_price, prev_price, "up", latest_pp.created_at
    return best_price, None, None, None


def _stable_weeks(db: Session, product_id: int) -> int:
    """How many weeks the cheapest price has been unchanged."""
    instances = (
        db.query(Product_Instance).filter_by(product_id=product_id).all()
    )
    if not instances:
        return 0
    # Get recent price points for cheapest instance
    all_pps = []
    for inst in instances:
        pps = (
            db.query(Price_Point)
            .filter_by(instance_id=inst.id)
            .order_by(Price_Point.created_at.desc())
            .limit(30)
            .all()
        )
        all_pps.extend(pps)
    if not all_pps:
        return 0
    all_pps.sort(key=lambda p: p.created_at, reverse=True)
    current = _lowest_price(all_pps[0])
    weeks = 0
    for pp in all_pps[1:]:
        if _lowest_price(pp) == current:
            weeks = max(weeks, (all_pps[0].created_at - pp.created_at).days // 7)
        else:
            break
    return weeks


def _tracked_item_response(db: Session, item: Tracked_Item) -> dict:
    product = db.query(Product).get(item.product_id)
    if not product:
        raise HTTPException(404, "Product not found")

    from models.stores import Company as CompanyModel

    company = db.query(CompanyModel).get(product.company_id)
    current_price, prev_price, change, change_at = _price_change_info(
        db, item.product_id
    )
    stable = _stable_weeks(db, item.product_id) if not change else None

    # Find cheapest chain
    prices = _latest_prices_for_product(db, item.product_id)
    cheapest = min(prices, key=lambda x: x["price"]) if prices else None

    return {
        "id": item.id,
        "user_id": item.user_id,
        "product_id": item.product_id,
        "product_name": product.name,
        "brand": product.brand or "",
        "picture_url": product.picture_url,
        "company_name": company.name if company else "Unknown",
        "company_id": product.company_id,
        "current_price": current_price,
        "previous_price": prev_price,
        "price_change": change,
        "price_change_at": change_at,
        "stable_weeks": stable,
        "cheapest_chain": cheapest["chain"] if cheapest else None,
        "cheapest_price": cheapest["price"] if cheapest else None,
        "created_at": item.created_at,
    }


def _tracked_item_detail(db: Session, item: Tracked_Item) -> dict:
    base = _tracked_item_response(db, item)
    prices = _latest_prices_for_product(db, item.product_id)
    best_price = min((p["price"] for p in prices), default=0)

    all_store_prices = [
        {
            "chain": p["chain"],
            "store_id": p["store_id"],
            "price": p["price"],
            "is_best": p["price"] == best_price,
        }
        for p in sorted(prices, key=lambda x: x["price"])
    ]

    # Price history: last 90 days
    cutoff = datetime.utcnow() - timedelta(days=90)
    instances = (
        db.query(Product_Instance)
        .filter_by(product_id=item.product_id)
        .all()
    )
    history = []
    for inst in instances:
        from models.stores import Store, Company as CompanyModel

        store = db.query(Store).get(inst.store_id)
        company = db.query(CompanyModel).get(store.company_id) if store else None
        pps = (
            db.query(Price_Point)
            .filter(
                Price_Point.instance_id == inst.id,
                Price_Point.created_at >= cutoff,
            )
            .order_by(Price_Point.created_at)
            .all()
        )
        for pp in pps:
            history.append(
                {
                    "timestamp": pp.created_at.isoformat(),
                    "chain": company.name if company else "Unknown",
                    "price": _lowest_price(pp),
                }
            )

    base["all_store_prices"] = all_store_prices
    base["price_history"] = sorted(history, key=lambda h: h["timestamp"])
    return base
```

- [ ] **Step 5: Register router in `service/api/__init__.py`**

Add after existing router imports:

```python
from api.tracking import router as tracking_router
router.include_router(tracking_router)
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd service && python -m pytest tests/test_tracking_api.py -v`
Expected: PASS (all 4 tests)

- [ ] **Step 7: Commit**

```bash
git add service/schemas/tracking.py service/api/tracking.py service/api/__init__.py service/tests/test_tracking_api.py
git commit -m "feat: add tracking endpoints — track, untrack, list, detail, points"
```

---

## Task 3: Backend — Feed Endpoint

**Files:**
- Create: `service/schemas/feed.py`
- Create: `service/api/feed.py`
- Modify: `service/api/__init__.py`
- Test: `service/tests/test_feed_api.py`

- [ ] **Step 1: Create feed schemas**

```python
# service/schemas/feed.py
from pydantic import BaseModel
from typing import Optional


class PriceComparison(BaseModel):
    chain: str
    company_id: int
    price: float
    is_best: bool
    diff_from_best: Optional[float] = None


class FeedPriceReveal(BaseModel):
    type: str = "price_reveal"
    product_id: int
    product_name: str
    brand: str
    size: str
    picture_url: Optional[str] = None
    prices: list[PriceComparison]
    max_savings: float


class FeedSavingsItem(BaseModel):
    product_id: int
    product_name: str
    cheap_chain: str
    expensive_chain: str
    savings: float
    savings_pct: float


class FeedSavingsCard(BaseModel):
    type: str = "savings_ranking"
    items: list[FeedSavingsItem]


class FeedCommunityCard(BaseModel):
    type: str = "community_challenge"
    judgement_type: str  # "grouping" or "staple"
    product_id: int
    product_name: str
    product_brand: str
    staple_name: Optional[str] = None
    target_product_id: Optional[int] = None
    target_product_name: Optional[str] = None
    target_product_brand: Optional[str] = None


class FeedResponse(BaseModel):
    items: list  # mix of FeedPriceReveal, FeedSavingsCard, FeedCommunityCard
    page: int
    has_more: bool
```

- [ ] **Step 2: Write the failing test**

```python
# service/tests/test_feed_api.py
import pytest
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)


def test_feed_returns_items():
    resp = client.get("/feed?page=1&size=10")
    assert resp.status_code == 200
    data = resp.json()
    assert "items" in data
    assert "page" in data
    assert "has_more" in data
    assert isinstance(data["items"], list)


def test_feed_accepts_zipcode():
    resp = client.get("/feed?page=1&size=10&zipcode=02139")
    assert resp.status_code == 200


def test_feed_items_have_type():
    resp = client.get("/feed?page=1&size=20")
    data = resp.json()
    for item in data["items"]:
        assert "type" in item
        assert item["type"] in ("price_reveal", "savings_ranking", "community_challenge")
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd service && python -m pytest tests/test_feed_api.py -v`
Expected: FAIL — endpoint doesn't exist

- [ ] **Step 4: Implement feed router**

```python
# service/api/feed.py
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from sqlalchemy import func, distinct
from typing import Optional
import random

from api import get_db
from models.products import (
    Product,
    Product_Instance,
    Price_Point,
    Label_Judgement,
)
from models.stores import Store, Company
from schemas.feed import (
    FeedPriceReveal,
    FeedSavingsCard,
    FeedSavingsItem,
    FeedCommunityCard,
    FeedResponse,
    PriceComparison,
)

router = APIRouter(prefix="/feed", tags=["feed"])


@router.get("", response_model=FeedResponse)
def get_feed(
    page: int = Query(1, ge=1),
    size: int = Query(10, ge=1, le=50),
    zipcode: Optional[str] = None,
    db: Session = Depends(get_db),
):
    # Build store filter if zipcode provided
    store_filter = None
    if zipcode:
        store_ids = [
            s.id
            for s in db.query(Store.id).filter(Store.zipcode == zipcode).all()
        ]
        if store_ids:
            store_filter = store_ids

    reveals = _generate_price_reveals(db, store_filter, page, size)
    savings = _generate_savings_card(db, store_filter)
    challenges = _generate_community_cards(db, count=2)

    # Interleave: reveals with savings and community cards mixed in
    items = []
    reveal_iter = iter(reveals)
    for i in range(size):
        # Every 4th item is a savings card or community card
        if i == 3 and savings:
            items.append(savings.model_dump())
        elif i == 6 and challenges:
            items.append(challenges[0].model_dump() if challenges else next(reveal_iter, None))
        else:
            r = next(reveal_iter, None)
            if r:
                items.append(r.model_dump())

    items = [i for i in items if i is not None]
    has_more = len(reveals) >= size

    return FeedResponse(items=items, page=page, has_more=has_more)


def _generate_price_reveals(
    db: Session, store_filter: list[int] | None, page: int, size: int
) -> list[FeedPriceReveal]:
    """Find products with biggest price spreads across chains."""
    # Get products that appear in multiple companies
    query = (
        db.query(Product.id)
        .join(Product_Instance, Product_Instance.product_id == Product.id)
        .join(Store, Store.id == Product_Instance.store_id)
    )
    if store_filter:
        query = query.filter(Store.id.in_(store_filter))

    query = (
        query.group_by(Product.id)
        .having(func.count(distinct(Store.company_id)) >= 2)
        .limit(size * 3)  # fetch extra to allow filtering
        .offset((page - 1) * size * 3)
    )
    product_ids = [row[0] for row in query.all()]
    random.shuffle(product_ids)

    reveals = []
    for pid in product_ids[:size]:
        reveal = _build_price_reveal(db, pid, store_filter)
        if reveal and reveal.max_savings > 0.5:  # Only interesting spreads
            reveals.append(reveal)
    reveals.sort(key=lambda r: r.max_savings, reverse=True)
    return reveals[:size]


def _build_price_reveal(
    db: Session, product_id: int, store_filter: list[int] | None
) -> FeedPriceReveal | None:
    product = db.query(Product).get(product_id)
    if not product:
        return None

    inst_query = db.query(Product_Instance).filter_by(product_id=product_id)
    if store_filter:
        inst_query = inst_query.filter(Product_Instance.store_id.in_(store_filter))
    instances = inst_query.all()

    # Get best price per company
    company_prices: dict[int, tuple[float, str]] = {}
    for inst in instances:
        pp = (
            db.query(Price_Point)
            .filter_by(instance_id=inst.id)
            .order_by(Price_Point.created_at.desc())
            .first()
        )
        if not pp:
            continue
        store = db.query(Store).get(inst.store_id)
        if not store:
            continue
        company = db.query(Company).get(store.company_id)
        if not company:
            continue
        price = _lowest_price_val(pp)
        if price <= 0:
            continue
        existing = company_prices.get(company.id)
        if not existing or price < existing[0]:
            company_prices[company.id] = (price, company.name, company.id)

    if len(company_prices) < 2:
        return None

    sorted_prices = sorted(company_prices.values(), key=lambda x: x[0])
    best_price = sorted_prices[0][0]

    comparisons = []
    for price, chain, cid in sorted_prices[:3]:
        comparisons.append(
            PriceComparison(
                chain=chain,
                company_id=cid,
                price=round(price, 2),
                is_best=price == best_price,
                diff_from_best=round(price - best_price, 2) if price != best_price else None,
            )
        )

    max_savings = round(sorted_prices[-1][0] - sorted_prices[0][0], 2)

    # Get size from latest price point
    any_inst = instances[0] if instances else None
    latest_pp = (
        db.query(Price_Point)
        .filter_by(instance_id=any_inst.id)
        .order_by(Price_Point.created_at.desc())
        .first()
    ) if any_inst else None

    return FeedPriceReveal(
        product_id=product_id,
        product_name=product.name,
        brand=product.brand or "",
        size=latest_pp.size if latest_pp else "",
        picture_url=product.picture_url,
        prices=comparisons,
        max_savings=max_savings,
    )


def _generate_savings_card(
    db: Session, store_filter: list[int] | None
) -> FeedSavingsCard | None:
    """Top 5 products with biggest savings this week."""
    # Reuse price reveal logic, take top 5 by savings
    reveals = _generate_price_reveals(db, store_filter, page=1, size=20)
    if not reveals:
        return None
    top = reveals[:5]
    items = []
    for r in top:
        prices_sorted = sorted(r.prices, key=lambda p: p.price)
        if len(prices_sorted) < 2:
            continue
        cheap = prices_sorted[0]
        expensive = prices_sorted[-1]
        if expensive.price <= 0:
            continue
        items.append(
            FeedSavingsItem(
                product_id=r.product_id,
                product_name=r.product_name,
                cheap_chain=cheap.chain,
                expensive_chain=expensive.chain,
                savings=r.max_savings,
                savings_pct=round((r.max_savings / expensive.price) * 100),
            )
        )
    if not items:
        return None
    return FeedSavingsCard(items=items)


def _generate_community_cards(
    db: Session, count: int = 2
) -> list[FeedCommunityCard]:
    """Random judgement candidates for the feed."""
    cards = []
    # Grouping challenge
    products = (
        db.query(Product)
        .filter(Product.brand.isnot(None), Product.brand != "")
        .order_by(func.random())
        .limit(count * 2)
        .all()
    )
    if len(products) >= 2:
        cards.append(
            FeedCommunityCard(
                judgement_type="grouping",
                product_id=products[0].id,
                product_name=products[0].name,
                product_brand=products[0].brand or "",
                target_product_id=products[1].id,
                target_product_name=products[1].name,
                target_product_brand=products[1].brand or "",
            )
        )
    return cards[:count]


def _lowest_price_val(pp: Price_Point) -> float:
    prices = []
    for attr in ("base_price", "sale_price", "member_price"):
        val = getattr(pp, attr, None)
        if val:
            try:
                prices.append(float(val.replace("$", "").replace(",", "")))
            except (ValueError, AttributeError):
                pass
    return min(prices) if prices else 0.0
```

- [ ] **Step 5: Register feed router in `service/api/__init__.py`**

```python
from api.feed import router as feed_router
router.include_router(feed_router)
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd service && python -m pytest tests/test_feed_api.py -v`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add service/schemas/feed.py service/api/feed.py service/api/__init__.py service/tests/test_feed_api.py
git commit -m "feat: add /feed endpoint with price reveals, savings, and community cards"
```

---

## Task 4: Backend — Points System & Modified Judgements

**Files:**
- Modify: `service/api/products.py`
- Test: `service/tests/test_points.py`

- [ ] **Step 1: Write the failing test**

```python
# service/tests/test_points.py
import pytest
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)


@pytest.fixture
def user_id():
    resp = client.post("/users/create")
    return resp.json()["id"]


def test_points_start_at_zero(user_id):
    resp = client.get(f"/tracking/points?user_id={user_id}")
    assert resp.status_code == 200
    assert resp.json()["points"] == 0


def test_judgement_awards_points(user_id):
    # Submit a staple judgement (+3 points)
    client.post(
        "/products/judgement",
        json={
            "user_id": user_id,
            "product_id": 1,
            "judgement_type": "staple",
            "staple_name": "milk",
            "approved": True,
        },
    )
    resp = client.get(f"/tracking/points?user_id={user_id}")
    assert resp.json()["points"] == 3
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd service && python -m pytest tests/test_points.py -v`
Expected: FAIL — points not incremented on judgement

- [ ] **Step 3: Add points increment to judgement endpoint**

In `service/api/products.py`, find the `submit_judgement` function (the `POST /products/judgement` handler). After the `db.commit()` call that saves the judgement, add:

```python
# Award points
from models.tracking import User_Points

pts = 5 if req.judgement_type == "grouping" else 3
user_pts = db.query(User_Points).filter_by(user_id=req.user_id).first()
if user_pts:
    user_pts.points += pts
else:
    user_pts = User_Points(user_id=req.user_id, points=pts)
    db.add(user_pts)
db.commit()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd service && python -m pytest tests/test_points.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add service/api/products.py service/tests/test_points.py
git commit -m "feat: award points on judgement submission (+5 grouping, +3 staple)"
```

---

## Task 5: Backend — Make Product Search Work Without Store IDs

**Files:**
- Modify: `service/api/stores.py`
- Test: `service/tests/test_product_search_no_stores.py`

- [ ] **Step 1: Write the failing test**

```python
# service/tests/test_product_search_no_stores.py
import pytest
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)


def test_product_search_empty_store_ids():
    """Search should work with empty store IDs — returns all."""
    resp = client.post(
        "/stores/product_search",
        json={"ids": [], "tags": [], "search": "milk", "on_sale": False, "has_spread": False},
    )
    assert resp.status_code == 200


def test_product_search_with_chain_filter():
    """Search should accept optional chain (company_id) filter."""
    resp = client.post(
        "/stores/product_search",
        json={"ids": [], "tags": [], "search": "milk", "on_sale": False, "has_spread": False, "company_ids": [1]},
    )
    assert resp.status_code == 200
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd service && python -m pytest tests/test_product_search_no_stores.py -v`
Expected: FAIL or 422 — empty ids not handled, company_ids not accepted

- [ ] **Step 3: Modify product_search to handle empty store IDs and chain filter**

In `service/api/stores.py`, find the `product_search` endpoint. The request body model needs updating. Find the inline model or schema class used for the request body. Add `company_ids: list[int] = []` field.

In the query logic, change the store ID filter from required to conditional:

```python
# Instead of always filtering by store IDs:
if body.ids:
    query = query.filter(Product_Instance.store_id.in_(body.ids))
elif body.company_ids:
    # Filter by company/chain instead
    chain_store_ids = [
        s.id for s in db.query(Store.id).filter(Store.company_id.in_(body.company_ids)).all()
    ]
    if chain_store_ids:
        query = query.filter(Product_Instance.store_id.in_(chain_store_ids))
# If neither is provided, no store filter — search all stores
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd service && python -m pytest tests/test_product_search_no_stores.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add service/api/stores.py service/tests/test_product_search_no_stores.py
git commit -m "feat: allow product search without store IDs, add company_ids chain filter"
```

---

## Task 6: Frontend — Theme, Routes, and New State

**Files:**
- Create: `app/lib/config/markup_theme.dart`
- Create: `app/lib/state/markup_state.dart`
- Modify: `app/lib/config/app_routes.dart`

- [ ] **Step 1: Create theme constants**

```dart
// app/lib/config/markup_theme.dart
import 'package:flutter/material.dart';

abstract final class MarkupColors {
  static const darkGreen = Color(0xFF1b4332);
  static const mediumGreen = Color(0xFF2D6A4F);
  static const lightGreen = Color(0xFF95D5B2);
  static const bgGreen = Color(0xFFE9F7EE);
  static const orange = Color(0xFFc45200);
  static const bgOrange = Color(0xFFFFF8F0);
  static const textPrimary = Color(0xFF111111);
  static const textSecondary = Color(0xFF555555);
  static const textHint = Color(0xFF888888);
  static const surface = Color(0xFFFAFAFA);
  static const cardBg = Colors.white;
}

ThemeData markupTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: MarkupColors.darkGreen,
      primary: MarkupColors.darkGreen,
      secondary: MarkupColors.mediumGreen,
      surface: MarkupColors.surface,
    ),
    scaffoldBackgroundColor: MarkupColors.surface,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: MarkupColors.textPrimary,
      elevation: 0,
    ),
    cardTheme: CardTheme(
      color: MarkupColors.cardBg,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    fontFamily: null, // system default
  );
}
```

- [ ] **Step 2: Create new MarkupState**

```dart
// app/lib/state/markup_state.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_front_end/services/grocery_api.dart';
import 'package:flutter_front_end/models/grocery_models.dart';

class MarkupState extends ChangeNotifier {
  final GroceryApi api;

  // Auth
  int? currentUserId;
  bool isSignedIn = false;

  // Location
  String? zipcode;
  bool locationSet = false;

  // Tags & companies (metadata)
  List<Tag> tags = [];
  List<Company> companies = [];

  // Feed
  List<dynamic> feedItems = [];
  int feedPage = 1;
  bool feedHasMore = true;
  bool feedLoading = false;

  // Search
  String searchTerm = '';
  List<int> activeTagIds = [];
  bool onSaleOnly = false;
  bool biggestSpreadsOnly = false;
  String sortBy = 'best_savings';

  // Tracking (local for anonymous)
  List<int> localTrackedProductIds = [];

  // Points
  int points = 0;

  MarkupState({required this.api});

  Future<void> initialize() async {
    tags = await api.fetchTags();
    companies = await api.fetchCompanies();
    notifyListeners();
  }

  void setZipcode(String? zip) {
    zipcode = zip;
    locationSet = zip != null && zip.isNotEmpty;
    notifyListeners();
  }

  void setUserId(int id) {
    currentUserId = id;
    isSignedIn = true;
    notifyListeners();
  }

  void toggleTag(int tagId) {
    if (activeTagIds.contains(tagId)) {
      activeTagIds.remove(tagId);
    } else {
      activeTagIds.add(tagId);
    }
    notifyListeners();
  }

  void setSearchTerm(String term) {
    searchTerm = term;
    notifyListeners();
  }

  void setSortBy(String sort) {
    sortBy = sort;
    notifyListeners();
  }

  void toggleOnSale() {
    onSaleOnly = !onSaleOnly;
    notifyListeners();
  }

  void toggleBiggestSpreads() {
    biggestSpreadsOnly = !biggestSpreadsOnly;
    notifyListeners();
  }

  void trackProductLocally(int productId) {
    if (!localTrackedProductIds.contains(productId)) {
      localTrackedProductIds.add(productId);
      notifyListeners();
    }
  }

  void untrackProductLocally(int productId) {
    localTrackedProductIds.remove(productId);
    notifyListeners();
  }

  void addPoints(int pts) {
    points += pts;
    notifyListeners();
  }
}
```

- [ ] **Step 3: Update routes**

```dart
// app/lib/config/app_routes.dart
abstract final class AppRoutes {
  // New Markup routes
  static const feed = '/';
  static const search = '/search';
  static const tracking = '/tracking';
  static const trackingDetail = '/tracking/detail';
  static const play = '/play';

  // Kept routes
  static const game = '/game';
  static const unsubscribe = '/unsubscribe';
  static const suggestStore = '/suggest-store';
  static const preferences = '/preferences';

  // Legacy routes (kept for backwards compat during migration)
  static const storeSearch = '/stores';
  static const chart = '/chart';
  static const bundlePlan = '/bundle-plan';
  static const staplesOverview = '/staples';
  static const checkout = '/checkout';
  static const labelJudgement = '/label-judgement';
  static const sharedBundle = '/shared-bundle';
}
```

- [ ] **Step 4: Run analyze to verify no errors**

Run: `cd app && flutter analyze`
Expected: No errors (warnings ok)

- [ ] **Step 5: Commit**

```bash
git add app/lib/config/markup_theme.dart app/lib/state/markup_state.dart app/lib/config/app_routes.dart
git commit -m "feat: add Markup theme, state, and route constants"
```

---

## Task 7: Frontend — API Client Updates

**Files:**
- Modify: `app/lib/services/grocery_api.dart`
- Modify: `app/lib/models/grocery_models.dart`

- [ ] **Step 1: Add new model classes**

Add to bottom of `app/lib/models/grocery_models.dart`:

```dart
class FeedPriceComparison {
  final String chain;
  final int companyId;
  final double price;
  final bool isBest;
  final double? diffFromBest;

  FeedPriceComparison({
    required this.chain,
    required this.companyId,
    required this.price,
    required this.isBest,
    this.diffFromBest,
  });

  factory FeedPriceComparison.fromJson(Map<String, dynamic> json) {
    return FeedPriceComparison(
      chain: json['chain'] ?? '',
      companyId: json['company_id'] ?? 0,
      price: (json['price'] ?? 0).toDouble(),
      isBest: json['is_best'] ?? false,
      diffFromBest: json['diff_from_best']?.toDouble(),
    );
  }
}

class FeedItem {
  final String type;
  final Map<String, dynamic> data;

  FeedItem({required this.type, required this.data});

  factory FeedItem.fromJson(Map<String, dynamic> json) {
    return FeedItem(type: json['type'] ?? '', data: json);
  }
}

class TrackedItem {
  final int id;
  final int productId;
  final String productName;
  final String brand;
  final String? pictureUrl;
  final String companyName;
  final double? currentPrice;
  final double? previousPrice;
  final String? priceChange; // "drop", "up", null
  final DateTime? priceChangeAt;
  final int? stableWeeks;
  final String? cheapestChain;
  final double? cheapestPrice;

  TrackedItem({
    required this.id,
    required this.productId,
    required this.productName,
    required this.brand,
    this.pictureUrl,
    required this.companyName,
    this.currentPrice,
    this.previousPrice,
    this.priceChange,
    this.priceChangeAt,
    this.stableWeeks,
    this.cheapestChain,
    this.cheapestPrice,
  });

  factory TrackedItem.fromJson(Map<String, dynamic> json) {
    return TrackedItem(
      id: json['id'],
      productId: json['product_id'],
      productName: json['product_name'] ?? '',
      brand: json['brand'] ?? '',
      pictureUrl: json['picture_url'],
      companyName: json['company_name'] ?? '',
      currentPrice: json['current_price']?.toDouble(),
      previousPrice: json['previous_price']?.toDouble(),
      priceChange: json['price_change'],
      priceChangeAt: json['price_change_at'] != null
          ? DateTime.tryParse(json['price_change_at'])
          : null,
      stableWeeks: json['stable_weeks'],
      cheapestChain: json['cheapest_chain'],
      cheapestPrice: json['cheapest_price']?.toDouble(),
    );
  }
}

class TrackedItemDetail extends TrackedItem {
  final List<Map<String, dynamic>> allStorePrices;
  final List<Map<String, dynamic>> priceHistory;

  TrackedItemDetail({
    required super.id,
    required super.productId,
    required super.productName,
    required super.brand,
    super.pictureUrl,
    required super.companyName,
    super.currentPrice,
    super.previousPrice,
    super.priceChange,
    super.priceChangeAt,
    super.stableWeeks,
    super.cheapestChain,
    super.cheapestPrice,
    required this.allStorePrices,
    required this.priceHistory,
  });

  factory TrackedItemDetail.fromJson(Map<String, dynamic> json) {
    return TrackedItemDetail(
      id: json['id'],
      productId: json['product_id'],
      productName: json['product_name'] ?? '',
      brand: json['brand'] ?? '',
      pictureUrl: json['picture_url'],
      companyName: json['company_name'] ?? '',
      currentPrice: json['current_price']?.toDouble(),
      previousPrice: json['previous_price']?.toDouble(),
      priceChange: json['price_change'],
      priceChangeAt: json['price_change_at'] != null
          ? DateTime.tryParse(json['price_change_at'])
          : null,
      stableWeeks: json['stable_weeks'],
      cheapestChain: json['cheapest_chain'],
      cheapestPrice: json['cheapest_price']?.toDouble(),
      allStorePrices: List<Map<String, dynamic>>.from(json['all_store_prices'] ?? []),
      priceHistory: List<Map<String, dynamic>>.from(json['price_history'] ?? []),
    );
  }
}
```

- [ ] **Step 2: Add new API methods**

Add to `app/lib/services/grocery_api.dart` in the `GroceryApi` class:

```dart
// ── Feed ──

Future<Map<String, dynamic>> fetchFeed({int page = 1, int size = 10, String? zipcode}) async {
  final params = {'page': '$page', 'size': '$size'};
  if (zipcode != null) params['zipcode'] = zipcode;
  final uri = environment.uri('/feed', params);
  final resp = await get(uri);
  return resp;
}

// ── Tracking ──

Future<Map<String, dynamic>> trackProduct(int userId, int productId) async {
  final uri = environment.uri('/tracking/track');
  return await post(uri, {'user_id': userId, 'product_id': productId});
}

Future<void> untrackProduct(int userId, int productId) async {
  final uri = environment.uri('/tracking/track/$productId', {'user_id': '$userId'});
  final response = await _client.delete(uri).timeout(_timeout);
  if (response.statusCode != 200) {
    throw Exception('Failed to untrack product');
  }
}

Future<List<TrackedItem>> fetchTrackedItems(int userId) async {
  final uri = environment.uri('/tracking/tracked', {'user_id': '$userId'});
  final resp = await get(uri);
  final list = resp is List ? resp : [];
  return list.map<TrackedItem>((j) => TrackedItem.fromJson(j)).toList();
}

Future<TrackedItemDetail> fetchTrackedDetail(int userId, int productId) async {
  final uri = environment.uri('/tracking/tracked/$productId', {'user_id': '$userId'});
  final resp = await get(uri);
  return TrackedItemDetail.fromJson(resp);
}

Future<Map<String, dynamic>> fetchPoints(int userId) async {
  final uri = environment.uri('/tracking/points', {'user_id': '$userId'});
  return await get(uri);
}

// ── Product search (updated: store_ids now optional) ──

Future<List<Product>> searchProducts({
  String search = '',
  List<int> storeIds = const [],
  List<int> tagIds = const [],
  List<int> companyIds = const [],
  bool onSaleOnly = false,
  bool hasSpread = false,
  int page = 1,
  int size = 20,
}) async {
  final uri = environment.uri('/stores/product_search', {'page': '$page', 'size': '$size'});
  final body = {
    'ids': storeIds,
    'tags': tagIds,
    'search': search,
    'on_sale': onSaleOnly,
    'has_spread': hasSpread,
    'company_ids': companyIds,
  };
  final resp = await post(uri, body);
  final items = resp['items'] as List? ?? [];
  return items.map<Product>((j) => Product.fromJson(j)).toList();
}
```

- [ ] **Step 3: Run analyze**

Run: `cd app && flutter analyze`
Expected: No errors

- [ ] **Step 4: Commit**

```bash
git add app/lib/models/grocery_models.dart app/lib/services/grocery_api.dart
git commit -m "feat: add feed, tracking, and points API methods + model classes"
```

---

## Task 8: Frontend — App Shell with Tab Navigation

**Files:**
- Modify: `app/lib/main.dart`
- Create: `app/lib/screens/feed_screen.dart` (placeholder)
- Create: `app/lib/screens/search_screen.dart` (placeholder)
- Create: `app/lib/screens/tracking_screen.dart` (placeholder)
- Create: `app/lib/screens/play_screen.dart` (placeholder)

- [ ] **Step 1: Create placeholder screens**

Each screen follows the same pattern. Create all four:

```dart
// app/lib/screens/feed_screen.dart
import 'package:flutter/material.dart';

class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Feed — coming soon'));
  }
}
```

```dart
// app/lib/screens/search_screen.dart
import 'package:flutter/material.dart';

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Search — coming soon'));
  }
}
```

```dart
// app/lib/screens/tracking_screen.dart
import 'package:flutter/material.dart';

class TrackingScreen extends StatelessWidget {
  const TrackingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Tracking — coming soon'));
  }
}
```

```dart
// app/lib/screens/play_screen.dart
import 'package:flutter/material.dart';

class PlayScreen extends StatelessWidget {
  const PlayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Play — coming soon'));
  }
}
```

- [ ] **Step 2: Rebuild main.dart with tab shell**

Replace the root widget and routing in `app/lib/main.dart`. The key changes:

1. Remove the auth gate (`_SignInPage` as mandatory first screen)
2. Use `MarkupState` instead of `AppState`
3. Root widget is a `Scaffold` with `BottomNavigationBar` and `IndexedStack` of 4 tab screens
4. Keep legacy routes for `/game`, `/unsubscribe`, etc.

The new root widget:

```dart
class MarkupApp extends StatelessWidget {
  const MarkupApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Markup',
      theme: markupTheme(),
      home: const MarkupShell(),
      routes: {
        AppRoutes.game: (_) => const GamePage(),
        AppRoutes.unsubscribe: (_) => const UnsubscribePage(),
        AppRoutes.suggestStore: (_) => const SuggestStorePage(),
        AppRoutes.preferences: (_) => const PreferencesPage(),
      },
    );
  }
}

class MarkupShell extends StatefulWidget {
  const MarkupShell({super.key});

  @override
  State<MarkupShell> createState() => _MarkupShellState();
}

class _MarkupShellState extends State<MarkupShell> {
  int _currentIndex = 0;

  final _screens = const [
    FeedScreen(),
    SearchScreen(),
    TrackingScreen(),
    PlayScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Feed'),
          NavigationDestination(icon: Icon(Icons.search), selectedIcon: Icon(Icons.search), label: 'Search'),
          NavigationDestination(icon: Icon(Icons.notifications_outlined), selectedIcon: Icon(Icons.notifications), label: 'Tracking'),
          NavigationDestination(icon: Icon(Icons.sports_esports_outlined), selectedIcon: Icon(Icons.sports_esports), label: 'Play'),
        ],
      ),
    );
  }
}
```

Replace the `ChangeNotifierProvider` to use `MarkupState`, and update `main()` to not require auth before showing the app.

- [ ] **Step 3: Run the app to verify tab navigation works**

Run: `cd app && flutter run -d chrome`
Expected: App opens to Feed tab with "Feed — coming soon". Bottom nav shows 4 tabs, all tappable.

- [ ] **Step 4: Commit**

```bash
git add app/lib/main.dart app/lib/screens/
git commit -m "feat: Markup app shell with 4-tab bottom navigation"
```

---

## Task 9: Frontend — Feed Screen

**Files:**
- Modify: `app/lib/screens/feed_screen.dart`
- Create: `app/lib/widgets/feed_price_reveal_card.dart`
- Create: `app/lib/widgets/feed_savings_card.dart`
- Create: `app/lib/widgets/feed_community_card.dart`
- Create: `app/lib/widgets/location_banner.dart`

- [ ] **Step 1: Create location banner widget**

```dart
// app/lib/widgets/location_banner.dart
import 'package:flutter/material.dart';
import 'package:flutter_front_end/config/markup_theme.dart';

class LocationBanner extends StatelessWidget {
  final String? zipcode;
  final VoidCallback onSetArea;

  const LocationBanner({super.key, this.zipcode, required this.onSetArea});

  @override
  Widget build(BuildContext context) {
    final label = zipcode != null ? 'Prices near $zipcode' : 'Showing prices from all regions';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: MarkupColors.bgGreen,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on, size: 16, color: MarkupColors.darkGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 13, color: MarkupColors.darkGreen)),
          ),
          GestureDetector(
            onTap: onSetArea,
            child: Text(
              zipcode != null ? 'Change' : 'Set your area',
              style: const TextStyle(
                fontSize: 13,
                color: MarkupColors.darkGreen,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Create price reveal card**

```dart
// app/lib/widgets/feed_price_reveal_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_front_end/config/markup_theme.dart';

class FeedPriceRevealCard extends StatelessWidget {
  final String productName;
  final String brand;
  final String size;
  final List<Map<String, dynamic>> prices; // [{chain, price, is_best, diff_from_best}]
  final VoidCallback? onTrack;
  final VoidCallback? onHistory;

  const FeedPriceRevealCard({
    super.key,
    required this.productName,
    required this.brand,
    required this.size,
    required this.prices,
    this.onTrack,
    this.onHistory,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 3, offset: const Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PRICE REVEAL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: MarkupColors.textHint, letterSpacing: 1)),
          const SizedBox(height: 8),
          Text(productName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: MarkupColors.textPrimary)),
          if (size.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text('$brand · $size', style: const TextStyle(fontSize: 12, color: MarkupColors.textSecondary)),
          ],
          const SizedBox(height: 12),
          Row(
            children: prices.take(3).map((p) => Expanded(child: _priceChip(p))).toList(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (onHistory != null)
                _actionPill('📊 Price history', onHistory!),
              const SizedBox(width: 8),
              if (onTrack != null)
                _actionPill('🔔 Track price', onTrack!),
            ],
          ),
        ],
      ),
    );
  }

  Widget _priceChip(Map<String, dynamic> p) {
    final isBest = p['is_best'] == true;
    final price = (p['price'] as num).toDouble();
    final diff = p['diff_from_best'] as num?;
    final chain = p['chain'] as String? ?? '';

    Color bg = isBest ? MarkupColors.bgGreen : (diff != null && diff > 2 ? MarkupColors.bgOrange : const Color(0xFFF5F5F5));
    Color priceColor = isBest ? MarkupColors.darkGreen : (diff != null && diff > 2 ? MarkupColors.orange : MarkupColors.textPrimary);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: !isBest && diff != null && diff > 2 ? Border.all(color: const Color(0xFFF0E0C0)) : null,
      ),
      child: Column(
        children: [
          Text(chain, style: TextStyle(fontSize: 12, color: MarkupColors.textSecondary, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text('\$${price.toStringAsFixed(2)}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: priceColor)),
          const SizedBox(height: 2),
          Text(
            isBest ? 'Best price' : (diff != null ? '+\$${diff.toStringAsFixed(2)} more' : ''),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: priceColor),
          ),
        ],
      ),
    );
  }

  Widget _actionPill(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: MarkupColors.bgGreen, borderRadius: BorderRadius.circular(16)),
        child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MarkupColors.darkGreen)),
      ),
    );
  }
}
```

- [ ] **Step 3: Create savings card and community card widgets**

Create `app/lib/widgets/feed_savings_card.dart` and `app/lib/widgets/feed_community_card.dart` following the same pattern as the price reveal card. The savings card renders a list of `FeedSavingsItem` rows. The community card renders the product match / staple check challenge with Same/Different/Skip buttons.

(Detailed code follows the exact mockup structure from the spec — savings card shows product name, chain comparison, "Save $X" and "X% less"; community card shows two products side-by-side with action buttons.)

- [ ] **Step 4: Implement the full FeedScreen**

```dart
// app/lib/screens/feed_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_front_end/state/markup_state.dart';
import 'package:flutter_front_end/widgets/location_banner.dart';
import 'package:flutter_front_end/widgets/feed_price_reveal_card.dart';
import 'package:flutter_front_end/widgets/feed_savings_card.dart';
import 'package:flutter_front_end/widgets/feed_community_card.dart';
import 'package:flutter_front_end/config/markup_theme.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  bool _hasMore = true;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _loadFeed();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadFeed() async {
    if (_loading) return;
    setState(() => _loading = true);
    final state = context.read<MarkupState>();
    try {
      final resp = await state.api.fetchFeed(page: 1, size: 10, zipcode: state.zipcode);
      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(resp['items'] ?? []);
        _hasMore = resp['has_more'] ?? false;
        _page = 1;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    final state = context.read<MarkupState>();
    try {
      final resp = await state.api.fetchFeed(page: _page + 1, size: 10, zipcode: state.zipcode);
      if (!mounted) return;
      setState(() {
        _items.addAll(List<Map<String, dynamic>>.from(resp['items'] ?? []));
        _hasMore = resp['has_more'] ?? false;
        _page += 1;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MarkupState>();
    return SafeArea(
      child: Column(
        children: [
          // Top bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Text('Markup', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: MarkupColors.darkGreen)),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      // Navigate to search tab
                      // Parent shell handles this via callback
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(color: const Color(0xFFF0F0F0), borderRadius: BorderRadius.circular(24)),
                      child: const Text('🔍 Search any product...', style: TextStyle(fontSize: 14, color: MarkupColors.textHint)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => _showProfile(context),
                  child: const CircleAvatar(radius: 16, backgroundColor: Color(0xFFE0E0E0), child: Icon(Icons.person, size: 18, color: MarkupColors.textHint)),
                ),
              ],
            ),
          ),
          // Location banner
          LocationBanner(zipcode: state.zipcode, onSetArea: () => _showSetArea(context, state)),
          // Feed
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadFeed,
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _items.length + (_loading ? 1 : 0),
                itemBuilder: (ctx, i) {
                  if (i >= _items.length) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator(color: MarkupColors.darkGreen)),
                    );
                  }
                  return _buildFeedCard(_items[i]);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedCard(Map<String, dynamic> item) {
    switch (item['type']) {
      case 'price_reveal':
        return FeedPriceRevealCard(
          productName: item['product_name'] ?? '',
          brand: item['brand'] ?? '',
          size: item['size'] ?? '',
          prices: List<Map<String, dynamic>>.from(item['prices'] ?? []),
        );
      case 'savings_ranking':
        return FeedSavingsCard(items: List<Map<String, dynamic>>.from(item['items'] ?? []));
      case 'community_challenge':
        return FeedCommunityCard(data: item);
      default:
        return const SizedBox.shrink();
    }
  }

  void _showSetArea(BuildContext context, MarkupState state) {
    final controller = TextEditingController(text: state.zipcode ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set your area'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Enter zip code'),
          keyboardType: TextInputType.number,
          maxLength: 5,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              state.setZipcode(controller.text.isEmpty ? null : controller.text);
              Navigator.pop(ctx);
              _loadFeed();
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
  }

  void _showProfile(BuildContext context) {
    // Profile sheet — implemented in Task 13
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
```

- [ ] **Step 5: Run the app to verify feed loads**

Run: `cd app && flutter run -d chrome`
Expected: Feed tab shows location banner and loads cards from the API (or shows empty state gracefully if no data).

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/feed_screen.dart app/lib/widgets/
git commit -m "feat: Feed screen with price reveal, savings, and community cards"
```

---

## Task 10: Frontend — Search Screen

**Files:**
- Modify: `app/lib/screens/search_screen.dart`
- Create: `app/lib/widgets/search_result_card.dart`
- Create: `app/lib/widgets/filter_chips_bar.dart`

- [ ] **Step 1: Create filter chips bar**

```dart
// app/lib/widgets/filter_chips_bar.dart
import 'package:flutter/material.dart';
import 'package:flutter_front_end/config/markup_theme.dart';

class FilterChipsBar extends StatelessWidget {
  final bool onSaleActive;
  final bool biggestSpreadsActive;
  final List<String> tagNames;
  final List<int> activeTagIds;
  final VoidCallback onToggleOnSale;
  final VoidCallback onToggleSpreads;
  final Function(int) onToggleTag;

  const FilterChipsBar({
    super.key,
    required this.onSaleActive,
    required this.biggestSpreadsActive,
    required this.tagNames,
    required this.activeTagIds,
    required this.onToggleOnSale,
    required this.onToggleSpreads,
    required this.onToggleTag,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _chip('On Sale', onSaleActive, onToggleOnSale),
          const SizedBox(width: 6),
          _chip('Biggest Spreads', biggestSpreadsActive, onToggleSpreads),
          ...tagNames.asMap().entries.map((e) {
            final idx = e.key;
            final name = e.value;
            return Padding(
              padding: const EdgeInsets.only(left: 6),
              child: _chip(name, activeTagIds.contains(idx), () => onToggleTag(idx)),
            );
          }),
        ],
      ),
    );
  }

  Widget _chip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: active ? MarkupColors.bgGreen : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? MarkupColors.lightGreen : const Color(0xFFE0E0E0)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            color: active ? MarkupColors.darkGreen : MarkupColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Create search result card**

```dart
// app/lib/widgets/search_result_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_front_end/config/markup_theme.dart';

class SearchResultCard extends StatelessWidget {
  final String productName;
  final String brand;
  final String size;
  final String? pictureUrl;
  final double bestPrice;
  final String bestChain;
  final List<Map<String, dynamic>> otherPrices; // [{chain, price}]
  final double maxSavings;
  final bool isBestDeal;
  final bool isOnSale;
  final double? originalPrice;
  final VoidCallback? onTrack;
  final VoidCallback? onHistory;
  final VoidCallback? onTap;

  const SearchResultCard({
    super.key,
    required this.productName,
    required this.brand,
    required this.size,
    this.pictureUrl,
    required this.bestPrice,
    required this.bestChain,
    required this.otherPrices,
    required this.maxSavings,
    this.isBestDeal = false,
    this.isOnSale = false,
    this.originalPrice,
    this.onTrack,
    this.onHistory,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 3, offset: const Offset(0, 1))],
          border: isBestDeal ? const Border(left: BorderSide(color: MarkupColors.darkGreen, width: 3)) : null,
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Product image
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(8)),
                  child: pictureUrl != null
                      ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(pictureUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.egg, color: MarkupColors.textHint)))
                      : const Icon(Icons.shopping_bag_outlined, color: MarkupColors.textHint),
                ),
                const SizedBox(width: 12),
                // Product info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(productName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: MarkupColors.textPrimary))),
                          if (isOnSale)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: MarkupColors.orange, borderRadius: BorderRadius.circular(4)),
                              child: const Text('SALE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('$brand · $size', style: const TextStyle(fontSize: 12, color: MarkupColors.textSecondary)),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text('\$${bestPrice.toStringAsFixed(2)}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: isOnSale ? MarkupColors.orange : MarkupColors.darkGreen)),
                          if (isOnSale && originalPrice != null) ...[
                            const SizedBox(width: 6),
                            Text('\$${originalPrice!.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, color: MarkupColors.textHint, decoration: TextDecoration.lineThrough)),
                          ],
                          const SizedBox(width: 8),
                          Text('at $bestChain', style: const TextStyle(fontSize: 12, color: MarkupColors.textSecondary)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: otherPrices.map((p) {
                          final price = (p['price'] as num).toDouble();
                          final isExpensive = price > bestPrice * 1.3;
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isExpensive ? MarkupColors.bgOrange : const Color(0xFFF5F5F5),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${p['chain']} \$${price.toStringAsFixed(2)}',
                              style: TextStyle(fontSize: 11, color: isExpensive ? MarkupColors.orange : MarkupColors.textSecondary),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                // Savings badge
                if (maxSavings > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: MarkupColors.bgGreen, borderRadius: BorderRadius.circular(10)),
                    child: Text('Save \$${maxSavings.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MarkupColors.darkGreen)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                if (onHistory != null)
                  GestureDetector(onTap: onHistory, child: const Text('📊 History', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MarkupColors.darkGreen))),
                if (onTrack != null) ...[
                  const SizedBox(width: 16),
                  GestureDetector(onTap: onTrack, child: const Text('🔔 Track', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MarkupColors.darkGreen))),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Implement full SearchScreen**

The search screen uses `searchProducts()` from the API client, renders results as `SearchResultCard` widgets, includes `FilterChipsBar` at top, and a sort dropdown. Full implementation follows the spec: search bar, location context line, filter chips, "X results" + sort row, then scrollable results.

Key behaviors:
- Search triggers on submit (not on every keystroke)
- Results are product-grouped (the backend handles grouping via `has_spread`)
- First result gets `isBestDeal: true`
- Infinite scroll pagination

- [ ] **Step 4: Run the app and test search**

Run: `cd app && flutter run -d chrome`
Expected: Search tab shows search bar, filter chips, and loads results on query submission.

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/search_screen.dart app/lib/widgets/search_result_card.dart app/lib/widgets/filter_chips_bar.dart
git commit -m "feat: Search screen with filter chips, sort, and grouped result cards"
```

---

## Task 11: Frontend — Tracking Screen + Detail

**Files:**
- Modify: `app/lib/screens/tracking_screen.dart`
- Create: `app/lib/screens/tracking_detail_screen.dart`
- Create: `app/lib/widgets/tracked_item_card.dart`

- [ ] **Step 1: Create tracked item card widget**

The card shows product name, chain, current price, and one of three states: PRICE DROP (green left border + badge), PRICE UP (orange left border + badge + cheaper suggestion), or Stable (no border + "Stable X wks"). Follow the exact spec layout.

- [ ] **Step 2: Implement TrackingScreen**

The screen:
- Header with "Tracking" title and "Edit" link
- Sign-in nudge banner (shown when `state.currentUserId == null`)
- List of tracked items from API (signed in) or local storage (anonymous)
- Tapping an item navigates to `TrackingDetailScreen`

For anonymous users, tracked product IDs come from `MarkupState.localTrackedProductIds`. The screen fetches current prices directly via the products API.

For signed-in users, tracked items come from `api.fetchTrackedItems(userId)`.

- [ ] **Step 3: Implement TrackingDetailScreen**

The detail screen:
- Back arrow + product name
- Price history chart (use `fl_chart` or a simple `CustomPaint` line chart)
- Current prices table ranked by price
- "Stop tracking" and "Share" buttons

Data comes from `api.fetchTrackedDetail(userId, productId)`.

- [ ] **Step 4: Run and test tracking flow**

Run: `cd app && flutter run -d chrome`
Expected: Tracking tab shows empty state or tracked items. Tapping an item opens detail with price history.

- [ ] **Step 5: Commit**

```bash
git add app/lib/screens/tracking_screen.dart app/lib/screens/tracking_detail_screen.dart app/lib/widgets/tracked_item_card.dart
git commit -m "feat: Tracking screen with item cards, detail view, and price history"
```

---

## Task 12: Frontend — Play Screen

**Files:**
- Modify: `app/lib/screens/play_screen.dart`
- Create: `app/lib/widgets/challenge_card.dart`

- [ ] **Step 1: Create challenge card widget**

A reusable card for both Product Match and Staple Check challenges:

```dart
// app/lib/widgets/challenge_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_front_end/config/markup_theme.dart';

enum ChallengeType { productMatch, stapleCheck }

class ChallengeCard extends StatelessWidget {
  final ChallengeType type;
  final int points;
  final String productName;
  final String productBrand;
  final String? targetProductName;
  final String? targetProductBrand;
  final String? stapleName;
  final Function(bool approved) onAnswer;
  final VoidCallback onSkip;

  const ChallengeCard({
    super.key,
    required this.type,
    required this.points,
    required this.productName,
    required this.productBrand,
    this.targetProductName,
    this.targetProductBrand,
    this.stapleName,
    required this.onAnswer,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final isMatch = type == ChallengeType.productMatch;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 3, offset: const Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                isMatch ? '🏷️ PRODUCT MATCH' : '🥛 STAPLE CHECK',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: MarkupColors.textHint, letterSpacing: 1),
              ),
              Text(' · +$points pts', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: MarkupColors.darkGreen)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isMatch
                ? 'Are these the same product from different stores? Matching them lets us compare their prices.'
                : 'Should this count as a basic grocery staple? This helps us build better price comparisons for everyday items.',
            style: const TextStyle(fontSize: 13, color: MarkupColors.textSecondary),
          ),
          const SizedBox(height: 10),
          if (isMatch) ...[
            Row(
              children: [
                Expanded(child: _productBox(productName, productBrand)),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('=?', style: TextStyle(fontSize: 16, color: MarkupColors.textHint))),
                Expanded(child: _productBox(targetProductName ?? '', targetProductBrand ?? '')),
              ],
            ),
          ] else ...[
            _productBox(productName, '$productBrand${stapleName != null ? '\nCategory: $stapleName' : ''}'),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _actionButton(isMatch ? '✓ Same product' : '👍 Yes, it\'s a staple', MarkupColors.bgGreen, MarkupColors.darkGreen, () => onAnswer(true))),
              const SizedBox(width: 8),
              Expanded(child: _actionButton(isMatch ? '✗ Different' : '👎 No', const Color(0xFFFFF0F0), MarkupColors.orange, () => onAnswer(false))),
              const SizedBox(width: 8),
              Expanded(child: _actionButton('Skip', const Color(0xFFF0F0F0), MarkupColors.textSecondary, onSkip)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _productBox(String name, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MarkupColors.textPrimary), textAlign: TextAlign.center),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: MarkupColors.textSecondary), textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }

  Widget _actionButton(String label, Color bg, Color textColor, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textColor), textAlign: TextAlign.center),
      ),
    );
  }
}
```

- [ ] **Step 2: Implement PlayScreen**

The screen shows:
1. Points badge in header
2. Daily Price Guess card (links to existing game page via `Navigator.pushNamed(context, AppRoutes.game)`)
3. One Product Match challenge card
4. One Staple Check challenge card
5. "Your Impact" stats at bottom

Data: challenges come from existing `api.fetchJudgementCandidates()`. Points from `api.fetchPoints()`. On answer, call `api.submitJudgement()` then load next challenge.

- [ ] **Step 3: Run and test play tab**

Run: `cd app && flutter run -d chrome`
Expected: Play tab shows game card, one of each challenge type, and impact stats.

- [ ] **Step 4: Commit**

```bash
git add app/lib/screens/play_screen.dart app/lib/widgets/challenge_card.dart
git commit -m "feat: Play screen with daily game, challenges, points, and impact stats"
```

---

## Task 13: Frontend — Profile Sheet & Auth Updates

**Files:**
- Create: `app/lib/screens/profile_sheet.dart`
- Modify: `app/lib/screens/feed_screen.dart` (wire up profile button)
- Modify: `app/lib/main.dart` (remove old auth gate references)

- [ ] **Step 1: Create profile bottom sheet**

```dart
// app/lib/screens/profile_sheet.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_front_end/state/markup_state.dart';
import 'package:flutter_front_end/config/markup_theme.dart';
import 'package:flutter_front_end/config/app_routes.dart';
import 'package:flutter_front_end/services/auth_service.dart';

void showProfileSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => const ProfileSheet(),
  );
}

class ProfileSheet extends StatelessWidget {
  const ProfileSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MarkupState>();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Profile', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: MarkupColors.textPrimary)),
            const SizedBox(height: 20),
            if (!state.isSignedIn)
              ListTile(
                leading: const Icon(Icons.login, color: MarkupColors.darkGreen),
                title: const Text('Sign in with Google'),
                onTap: () async {
                  Navigator.pop(context);
                  final authService = AuthService();
                  final user = await authService.signInWithGoogle();
                  if (user != null) {
                    final userId = await state.api.fetchOrCreateUserId();
                    state.setUserId(userId);
                  }
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.logout, color: MarkupColors.textSecondary),
                title: const Text('Sign out'),
                onTap: () async {
                  Navigator.pop(context);
                  final authService = AuthService();
                  await authService.signOut();
                },
              ),
            ListTile(
              leading: const Icon(Icons.location_on_outlined, color: MarkupColors.textSecondary),
              title: Text(state.locationSet ? 'Location: ${state.zipcode}' : 'Set location'),
              onTap: () {
                Navigator.pop(context);
                // Trigger location dialog from parent
              },
            ),
            ListTile(
              leading: const Icon(Icons.email_outlined, color: MarkupColors.textSecondary),
              title: const Text('Newsletter preferences'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, AppRoutes.preferences);
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_business_outlined, color: MarkupColors.textSecondary),
              title: const Text('Suggest a store'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, AppRoutes.suggestStore);
              },
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Wire profile button in FeedScreen**

In `app/lib/screens/feed_screen.dart`, update `_showProfile`:

```dart
void _showProfile(BuildContext context) {
  showProfileSheet(context);
}
```

Add the import: `import 'package:flutter_front_end/screens/profile_sheet.dart';`

- [ ] **Step 3: Run and test profile**

Run: `cd app && flutter run -d chrome`
Expected: Tapping profile icon opens bottom sheet with sign in, location, newsletter, suggest store options.

- [ ] **Step 4: Commit**

```bash
git add app/lib/screens/profile_sheet.dart app/lib/screens/feed_screen.dart app/lib/main.dart
git commit -m "feat: Profile sheet with auth, location, newsletter, and suggest store"
```

---

## Task 14: Clean Up — Remove Legacy Screens

**Files:**
- Delete: `app/lib/main_search.dart`
- Delete: `app/lib/product_search.dart`
- Delete: `app/lib/staples_overview.dart`
- Delete: `app/lib/check_out.dart`
- Delete: `app/lib/bundle_plan.dart`
- Delete: `app/lib/shared_bundle_page.dart`
- Delete: `app/lib/chart.dart`
- Delete: `app/lib/label_judgement.dart`
- Modify: `app/lib/main.dart` — remove old route registrations
- Modify: `app/lib/state/app_state.dart` — keep file but mark deprecated
- Delete: `app/lib/widgets/top_level_navigation.dart` (replaced by bottom nav)
- Delete: `app/lib/widgets/overflow_menu_nudge.dart` (no overflow menu)
- Delete: `app/lib/widgets/hint_banner.dart` (no hints system)

- [ ] **Step 1: Remove old route registrations from main.dart**

Remove all legacy route entries from the `MaterialApp.routes` map that point to deleted screens. Keep routes for `/game`, `/unsubscribe`, `/suggest-store`, `/preferences`.

- [ ] **Step 2: Delete legacy screen files**

```bash
rm app/lib/main_search.dart app/lib/product_search.dart app/lib/staples_overview.dart
rm app/lib/check_out.dart app/lib/bundle_plan.dart app/lib/shared_bundle_page.dart
rm app/lib/chart.dart app/lib/label_judgement.dart
rm app/lib/widgets/top_level_navigation.dart app/lib/widgets/overflow_menu_nudge.dart app/lib/widgets/hint_banner.dart
```

- [ ] **Step 3: Run analyze to verify no broken imports**

Run: `cd app && flutter analyze`
Expected: No errors. Fix any remaining import references to deleted files.

- [ ] **Step 4: Run existing tests**

Run: `cd app && flutter test`
Expected: Tests that reference old screens may fail — update `frontend_flows_test.dart` to use new screens, or mark legacy tests as skipped with a TODO comment. New test coverage will be added per-screen in future work.

- [ ] **Step 5: Commit**

```bash
git add -A app/lib/ app/test/
git commit -m "chore: remove legacy screens replaced by Markup redesign"
```

---

## Task 15: Integration Test — Full User Journey

**Files:**
- Create: `app/test/markup_flow_test.dart`

- [ ] **Step 1: Write integration test for the core flow**

```dart
// app/test/markup_flow_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter_front_end/main.dart';
import 'package:flutter_front_end/state/markup_state.dart';
import 'package:flutter_front_end/services/grocery_api.dart';

// Use a TestGroceryApi that returns canned data
class TestMarkupApi extends GroceryApi {
  TestMarkupApi() : super(/* test environment */);

  @override
  Future<Map<String, dynamic>> fetchFeed({int page = 1, int size = 10, String? zipcode}) async {
    return {
      'items': [
        {
          'type': 'price_reveal',
          'product_id': 1,
          'product_name': 'Large Eggs',
          'brand': 'Store Brand',
          'size': '12 ct',
          'prices': [
            {'chain': 'Aldi', 'company_id': 1, 'price': 2.99, 'is_best': true, 'diff_from_best': null},
            {'chain': 'Whole Foods', 'company_id': 2, 'price': 5.49, 'is_best': false, 'diff_from_best': 2.50},
          ],
          'max_savings': 2.50,
        },
      ],
      'page': 1,
      'has_more': false,
    };
  }

  @override
  Future<List<Tag>> fetchTags() async => [];

  @override
  Future<List<Company>> fetchCompanies() async => [];
}

void main() {
  testWidgets('App opens to Feed with price reveal card', (tester) async {
    final api = TestMarkupApi();
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => MarkupState(api: api),
        child: const MarkupApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify we see the Markup branding
    expect(find.text('Markup'), findsOneWidget);

    // Verify feed loaded
    expect(find.text('Large Eggs'), findsOneWidget);
    expect(find.text('\$2.99'), findsOneWidget);
  });

  testWidgets('Bottom nav switches tabs', (tester) async {
    final api = TestMarkupApi();
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => MarkupState(api: api),
        child: const MarkupApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Tap Search tab
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    // Tap Tracking tab
    await tester.tap(find.text('Tracking'));
    await tester.pumpAndSettle();

    // Tap Play tab
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
  });
}
```

- [ ] **Step 2: Run the test**

Run: `cd app && flutter test test/markup_flow_test.dart`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add app/test/markup_flow_test.dart
git commit -m "test: add Markup integration test for feed load and tab navigation"
```
