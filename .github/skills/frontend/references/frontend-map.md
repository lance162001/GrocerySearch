# GrocerySearch Frontend Map

## Scope
- Active Flutter frontend root: `app/`
- Flutter package name for imports: `flutter_front_end`
- Default backend mode: local, controlled by `USE_LOCAL_BACKEND`

## Runtime Composition
- App bootstrap and provider wiring: `app/lib/main.dart`
- Backend environment resolution: `app/lib/config/app_environment.dart`
- Route constants: `app/lib/config/app_routes.dart`
- Shared app state: `app/lib/state/app_state.dart`
- Shared backend client: `app/lib/services/grocery_api.dart`

## Major Screens

### Store selection
- File: `app/lib/main_search.dart`
- Role: search stores, toggle selected stores, persist saved stores, and launch product search
- Typical changes: store search UI, selected-store filtering, saved-store persistence behavior

### Product search
- File: `app/lib/product_search.dart`
- Role: fetch products for selected stores, apply search and tag filters, support sale-only and price-spread views, and add items to cart
- Typical changes: filter controls, result cards, price comparison UI, infinite scroll, add-to-cart behavior

### Checkout
- File: `app/lib/check_out.dart`
- Role: show to-do and finished cart items by store, compute totals, and save the current cart as a bundle
- Typical changes: cart grouping, move-to-finished flow, totals, bundle-save UX

### Bundle planner
- File: `app/lib/bundle_plan.dart`
- Role: load user bundle summaries and details, inspect per-store pricing, and add products to bundles
- Typical changes: dashboard requests, bundle detail rendering, store/member controls, add-product actions

## Shared Models And Helpers
- Domain models: `app/lib/models/grocery_models.dart`
- Price parsing and formatting: `app/lib/utils/price_utils.dart`
- Scroll helpers: `app/lib/utils/scroll_utils.dart`
- Shared image widget: `app/lib/widgets/product_image.dart`
- Store badge row widget: `app/lib/widgets/store_row.dart`

## State Ownership
- `AppState` owns bootstrapped user metadata, selected stores, active tags, cart contents, cart quantities, and the current search term.
- Screen-local state should stay local when it only controls temporary UI behavior such as pending form values, loading flags, or local sort and filter toggles.
- Network fetches should stay in `GroceryApi` so widget tests can replace them with `TestGroceryApi`.

## Testing Workflow
- Broad frontend flow coverage: `app/test/frontend_flows_test.dart`
- Other frontend-focused tests: `app/test/widget_test.dart`, `app/test/app_state_test.dart`, `app/test/price_utils_test.dart`
- Test harness pattern: inject `Provider<AppEnvironment>`, `Provider<GroceryApi>`, and `ChangeNotifierProvider<AppState>` with fake data
- Avoid real HTTP in widget tests; the existing flow tests use `TestGroceryApi` for this reason

## Local Commands
```bash
cd app
flutter pub get
flutter analyze
flutter test
flutter test test/frontend_flows_test.dart -r expanded
flutter run -d chrome
flutter run -d chrome --dart-define=USE_LOCAL_BACKEND=false
```

## Common Pitfalls
- Editing the wrong layer: move shared app behavior into `AppState` or `GroceryApi` instead of duplicating it across widgets.
- Forgetting the package name: keep imports under `package:flutter_front_end/...`.
- Real network calls in tests: widget tests should use the fake API harness.
- Layout regressions on narrow widths: rows with badges, icons, and price labels are easy to overflow.
- Backend-mode assumptions: asset and API URLs are derived from `AppEnvironment`, not hard-coded per widget.