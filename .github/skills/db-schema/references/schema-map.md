# GrocerySearch Schema Map

## Runtime Storage
- Default database: `service/app.db`
- Override: `DATABASE_URL`
- Engine setup: `service/models/base.py`
- Table creation on API startup: `service/api/__init__.py`
- Table creation plus one lightweight migration: `service/scraper.py`

## Source Of Truth
- Persisted schema: SQLAlchemy models in `service/models/`
- API contracts: Pydantic models in `service/schemas/`

Do not treat `service/schemas/` as the database schema. Those files describe request and response payloads, not the underlying table layout.

## Tables

### companies
- Inherits `id` from `BaseModel`
- Columns: `logo_url`, `name`
- Referenced by: `stores.company_id`, `products.company_id`

### stores
- Inherits `id`
- Columns: `address`, `town`, `state`, `zipcode`, `company_id`, `scraper_id`
- Foreign keys: `company_id -> companies.id`
- Used by: `product_instances.store_id`, `saved_stores.store_id`

### products
- Inherits `id`
- Columns: `raw_name`, `name`, `brand`, `company_id`, `picture_url`
- Foreign keys: `company_id -> companies.id`
- Related join tables: `tag_instances`, `saved_products`

### product_instances
- Inherits `id`
- Columns: `store_id`, `product_id`
- Foreign keys: `store_id -> stores.id`, `product_id -> products.id`
- Role: bridge between a logical product and a specific store listing

### price_points
- Inherits `id`
- Columns: `member_price`, `sale_price`, `base_price`, `size`, `created_at`, `instance_id`
- Foreign keys: `instance_id -> product_instances.id`
- Role: historical pricing snapshots for a product instance

### tags
- Inherits `id`
- Columns: `name`

### tag_instances
- Inherits `id`
- Columns: `product_id`, `tag_id`
- Foreign keys: `product_id -> products.id`, `tag_id -> tags.id`
- Role: many-to-many join between products and tags

### users
- Inherits `id`
- Columns: `recent_zipcode`

### saved_stores
- Composite primary key: `store_id`, `user_id`
- Columns: `store_id`, `member`, `user_id`
- Foreign keys: `store_id -> stores.id`, `user_id -> users.id`
- Role: per-user saved stores with a membership flag

### product_bundles
- Inherits `id`
- Columns: `user_id`, `name`, `created_at`
- Foreign keys: `user_id -> users.id`
- Role: a saved shopping bundle owned by a user

### saved_products
- Composite primary key: `product_id`, `bundle_id`
- Columns: `product_id`, `bundle_id`
- Foreign keys: `product_id -> products.id`, `bundle_id -> product_bundles.id`
- Role: many-to-many join between bundles and products

### store_visits
- Inherits `id`
- Columns: `product_bundle_id`, `user_id`, `created_at`
- Foreign keys: `product_bundle_id -> product_bundles.id`, `user_id -> users.id`
- Role: logs that a user visited a store context for a bundle

## Relationship Summary
- `Company 1 -> many Store`
- `Company 1 -> many Product`
- `Store 1 -> many Product_Instance`
- `Product 1 -> many Product_Instance`
- `Product_Instance 1 -> many PricePoint`
- `Product many -> many Tag` through `Tag_Instance`
- `User 1 -> many Product_Bundle`
- `User many -> many Store` through `Saved_Store`
- `Product_Bundle many -> many Product` through `Saved_Product`
- `User 1 -> many Store_Visit`
- `Product_Bundle 1 -> many Store_Visit`

## Initialization And Migration Notes
- The API imports `Base` and runs `Base.metadata.create_all(engine)` during startup.
- The scraper also runs `Base.metadata.create_all(engine)` and then checks whether `products.raw_name` exists.
- If `raw_name` is missing, the scraper issues `ALTER TABLE products ADD COLUMN raw_name VARCHAR(150)`.
- There is no versioned migration framework in the repo.

## Important Caveats
- Existing databases will not pick up most column changes automatically; `create_all` only creates missing tables.
- `Store_Visit` does not persist `store_id`, even though the visit request and response schemas allow a `store_id` field.
- Some ORM relationships are defined only on one side, so relationship coverage is not a complete substitute for reading foreign keys.
- The API often computes derived views, such as latest price points per product instance, that are not separate tables.

## Change Impact Guide
- If you change `products`, review product search, scraper persistence, and bundle-detail assembly.
- If you change `product_instances` or `price_points`, review latest-price queries in both store search and bundle planning.
- If you change `saved_stores`, `product_bundles`, `saved_products`, or `store_visits`, review `service/api/users.py` first.
- If you change `stores` or `companies`, review search filters, logo URL generation, and scraper seed data.

## Fast Lookup
- Storage config: `service/models/base.py`
- Table bootstrap: `service/api/__init__.py`
- Lightweight migration logic: `service/scraper.py`
- Product and pricing tables: `service/models/products.py`
- Store and company tables: `service/models/stores.py`
- User, bundle, saved-store, and visit tables: `service/models/users.py`