# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

GrocerySearch is a grocery price comparison app with:
- **Python FastAPI backend** (`service/`) — REST API, web scrapers, email newsletter
- **Flutter web frontend** (`app/`) — product search, cart/bundle management, user dashboard
- **SQLite (dev) / PostgreSQL (prod)** for persistence

## Commands

### Backend

```bash
cd service
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# Run API (hot reload)
uvicorn main:app --reload --host 127.0.0.1 --port 8000
# API docs: http://localhost:8000/docs

# Run scraper once (debug mode)
python scraper.py --debug

# Run tests
pytest tests/test_bootstrap_coverage.py
```

### Frontend

```bash
cd app
flutter pub get
flutter run -d chrome                                    # local backend
flutter run -d chrome --dart-define=USE_LOCAL_BACKEND=false  # hosted backend
flutter analyze   # lint + type check
flutter test      # all widget tests
```

### Docker (production)

```bash
cd service
cp .env.prod.example .env.prod  # fill in secrets
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build
```

## Architecture

### Data flow

```
Flutter app → GroceryApi (HTTP) → FastAPI → SQLAlchemy → SQLite/PostgreSQL
                                         ↑
                              Scrapers (Selenium/Algolia) → persistence.py
```

### Backend structure (`service/`)

- **`main.py`** — FastAPI app, mounts static files, registers routers
- **`api/`** — route handlers: `products.py` (search, staples), `stores.py`, `users.py`, `admin.py`
- **`models/`** — SQLAlchemy ORM models (source of truth for schema); `bootstrap.py` handles table creation and lightweight migrations
- **`schemas/`** — Pydantic request/response models (API contracts on top of DB)
- **`scrapers/`** — one file per chain (`whole_foods.py`, `trader_joes.py`, `wegmans.py`); results persisted via `persistence.py`
- **`scraper.py`** — scheduler (daily 10:30 AM), runs scrapers in parallel threads, triggers email on completion
- **`emailer.py`** — newsletter generation via Jinja2 templates

### Frontend structure (`app/lib/`)

- **`main.dart`** — provider setup, theme definition, route registration
- **`state/app_state.dart`** — single source of truth for selected stores, active tags, cart contents, user metadata
- **`services/grocery_api.dart`** — the only HTTP boundary; all backend calls go through here
- **`config/app_environment.dart`** — backend URL selection (local vs. hosted)
- **Screens**: `main_search.dart` (store select) → `product_search.dart` → `check_out.dart` → `bundle_plan.dart`
- **Tests**: `app/test/frontend_flows_test.dart` — highest-value flow reference; uses `TestGroceryApi` fake (no real HTTP)

### Key entity relationships

- `Products` → belong to `Companies`; appear in `Stores` via `ProductInstances`
- `PricePoints` — historical prices attached to `ProductInstances` (collected daily)
- `Tags` ↔ `Products` via `TagInstances` (many-to-many)
- `Users` → `SavedStores`, `ProductBundles` → `SavedProducts`
- `ScraperStatus` — single-row admin status tracker

## Schema / Database Rules

Production is **PostgreSQL**; dev uses SQLite. DDL must be valid on both:
- Boolean defaults: `DEFAULT TRUE` / `DEFAULT FALSE` (not `1`/`0`)
- Timestamp columns: `TIMESTAMP` (not `DATETIME`)
- New `NOT NULL` columns on existing tables must have a `DEFAULT`
- Date functions: `CAST(x AS DATE)` (branch on `"postgresql" in db_url` for SQLite fallbacks)
- No Alembic — `Base.metadata.create_all()` creates missing tables but does not evolve existing ones; use `_ensure_column` pattern from `bootstrap.py` for additive migrations

## Frontend Rules

- Business state belongs in `AppState`, not spread across screens
- New HTTP calls go in `GroceryApi`, not inlined in widgets
- Use existing models from `grocery_models.dart`; do not add ad hoc map parsing in widgets
- Guard async UI actions with `mounted` checks before navigation or snackbars
- Color palette: dark green (`#1b4332`) primary; never add indigo/purple hex values (legacy palette). Prefer `Theme.of(context).colorScheme.primary` over hardcoding hex
- Widget tests inject `TestGroceryApi` — do not use real `HttpClient` in tests
- Flutter package name is `flutter_front_end` — preserve this import prefix

## Custom Skills

Invoke these with `/frontend` or `/db-schema` for guided workflows:
- `/frontend` — Flutter UI changes, provider state, screen flows, widget tests
- `/db-schema` — schema explanation, safe schema changes, migration risk assessment
