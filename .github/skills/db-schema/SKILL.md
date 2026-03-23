---
name: db-schema
description: 'Explain or update the GrocerySearch database schema. Use for db schema, database tables, SQLAlchemy models, foreign keys, relationships, SQLite storage, persisted entities, schema changes, and API-vs-DB schema questions in the backend service.'
argument-hint: 'What part of the schema do you need explained or changed?'
user-invocable: true
---

# GrocerySearch DB Schema

## When to Use
- Explain the current database schema for the backend service.
- Find the source of truth for tables, columns, and foreign keys.
- Distinguish persisted SQLAlchemy models from Pydantic API schemas.
- Plan or implement a schema change safely across models, API contracts, and bootstrap code.
- Audit relationships used by search, bundles, saved stores, visits, or scraper persistence.

## What This Skill Covers
- Runtime database backend and initialization path.
- SQLAlchemy model files under `service/models/` as the persistence source of truth.
- Pydantic models under `service/schemas/` as API contracts layered on top of the DB.
- Known schema caveats, including ad hoc migrations and API/model mismatches.

Use the detailed table and relationship map in [schema-map](./references/schema-map.md).

## Procedure
1. Classify the request.
   - If the user is asking about persisted tables, columns, keys, or relationships, use `service/models/` first.
   - If the user is asking about request or response payloads, use `service/schemas/` and the FastAPI routes.
   - If the user is asking for a schema change, inspect both the model layer and every API or scraper path that reads or writes the affected entities.

2. Anchor the answer in the actual runtime schema.
   - Start with `service/models/base.py` for the database URL and engine setup.
   - Check `service/api/__init__.py` and `service/scraper.py` to see how tables are created or lightly migrated.
   - Use the model files to confirm exact table names, inherited `id` columns, composite primary keys, and foreign keys.

3. Explain the entity graph in product terms.
   - Products belong to companies and appear in stores through `product_instances`.
   - Prices are historical `price_points` attached to product instances.
   - Tags are many-to-many with products through `tag_instances`.
   - Users save stores, build bundles, and log visits through the user-related tables.

4. If the task is a schema change, update the full path.
   - Change the SQLAlchemy model in `service/models/`.
   - Update bootstrap or lightweight migration logic if existing databases must pick up the change.
   - Update any Pydantic schema in `service/schemas/` if the field is exposed through the API.
   - Update route logic, scraper persistence, or query code that assumes the old shape.
   - Search for direct field usage before finishing.

5. Call out caveats explicitly.
   - This repo does not use Alembic or versioned migrations.
   - `Base.metadata.create_all(engine)` creates missing tables but does not safely evolve existing ones.
   - The scraper currently contains one manual schema evolution step for `products.raw_name`.
   - Some API payloads expose fields that are not persisted directly and should be described as such.

6. Write all DDL and SQL to be PostgreSQL-compatible.
   - The production database is **PostgreSQL**; local development may use SQLite. DDL must be valid on both where possible, and PostgreSQL must never be broken.
   - **Boolean defaults**: use `DEFAULT TRUE` / `DEFAULT FALSE`, never `DEFAULT 1` / `DEFAULT 0`. PostgreSQL rejects integer literals as boolean defaults with a `DatatypeMismatch` error.
   - **Timestamp type**: use `TIMESTAMP`, not `DATETIME`. PostgreSQL has no `DATETIME` type; using it raises `UndefinedObject`.
   - **Date/time casts**: use `CAST(x AS DATE)` rather than the SQLite-only `date(x)` function (the bootstrap already branches on `"postgresql" in db_url` for this — keep that pattern).
   - **Partial indexes**: `WHERE` clauses in `CREATE INDEX` are supported by PostgreSQL but not SQLite; wrap them in `_run_ddl_statements` so failures are logged and non-fatal on SQLite.
   - **`ALTER TABLE … ADD COLUMN`**: PostgreSQL does not allow `NOT NULL` columns without a `DEFAULT` unless the table is empty. Always supply a default or make the column nullable when adding to an existing table via `_ensure_column`.
   - **`AUTOINCREMENT`**: use SQLAlchemy's `Integer` primary key without explicit `AUTOINCREMENT`; SQLAlchemy emits the correct dialect-specific syntax automatically.
   - **String length**: PostgreSQL enforces `VARCHAR(n)` limits strictly; ensure lengths are not under-sized for real data before committing a schema change.

## Quality Checks
- Use exact table and column names from the model layer.
- Separate DB schema facts from API schema facts.
- Mention composite keys when they exist.
- Mention the storage backend and creation path when explaining how the schema is materialized.
- When changing schema, verify all affected query paths and note whether old databases need manual migration help.

## Schema Change Checklist
1. Identify whether the change affects persisted storage, API payloads, or both.
2. Update the SQLAlchemy model first and confirm the exact table and foreign key impact.
3. Search for direct reads and writes of the affected field across API routes, scrapers, and helper scripts.
4. Update Pydantic schemas only where the field is part of the public API.
5. Decide how existing databases will be upgraded, because `create_all` is not a full migration strategy.
6. Check derived query logic that depends on latest price points, bundle joins, saved stores, or visit history.
7. If the change is backward-incompatible, state the data migration or rollout risk explicitly.
8. **PostgreSQL compatibility check** — before finishing any DDL or raw SQL:
   - Boolean defaults use `TRUE`/`FALSE`, not `1`/`0`.
   - Timestamp columns use `TIMESTAMP`, not `DATETIME` (PostgreSQL has no `DATETIME` type).
   - New `NOT NULL` columns added to existing tables have a `DEFAULT` value.
   - Date/time conversion uses `CAST(… AS DATE)` (branch on `"postgresql" in db_url` for SQLite fallbacks).
   - `ALTER TABLE` syntax is standard SQL, not SQLite-specific.
   - `VARCHAR(n)` lengths are adequate for the expected data.

## Key Files
- `service/models/base.py`
- `service/models/products.py`
- `service/models/stores.py`
- `service/models/users.py`
- `service/api/__init__.py`
- `service/scraper.py`
- `service/schemas/`

## Output Expectations
- For explanation requests: return a concise table and relationship summary with caveats.
- For change requests: describe the impacted files, make the code changes, and state any migration risk clearly.

## Example Prompts
- Explain the persisted schema for products, product instances, and price points.
- Compare the DB schema and API schemas for store visits and identify mismatches.
- Add a new persisted field to bundles and update the API safely.
- Show which tables support user saved stores, bundles, and visits.