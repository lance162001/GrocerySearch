---
name: frontend
description: 'Explain or update the GrocerySearch Flutter frontend. Use for Flutter UI work in app/, widget screens, provider state, GroceryApi integration, navigation, store selection, product search, checkout, bundle planner, frontend tests, and UI regression debugging.'
argument-hint: 'What frontend screen, behavior, or test flow do you need explained or changed?'
user-invocable: true
---

# GrocerySearch Frontend

## When to Use
- Explain how the active Flutter frontend is structured.
- Change UI behavior in store selection, product search, checkout, or bundle planning.
- Update shared frontend state, API integration, or route wiring.
- Add or adjust widget tests for frontend flows.
- Debug regressions in provider state, fake API test wiring, or Flutter layout behavior.

## What This Skill Covers
- The active Flutter app under `app/`, not any removed or legacy frontend directory.
- Provider-based app composition in `app/lib/main.dart` and `app/lib/state/app_state.dart`.
- Backend access through `app/lib/services/grocery_api.dart`.
- Major user flows in `app/lib/main_search.dart`, `app/lib/product_search.dart`, `app/lib/check_out.dart`, and `app/lib/bundle_plan.dart`.
- Frontend flow tests in `app/test/frontend_flows_test.dart` and related widget tests.

Use the file and workflow map in [frontend-map](./references/frontend-map.md).

## Procedure
1. Classify the frontend change.
   - Store selection work usually starts in `app/lib/main_search.dart`.
   - Search result, filter, spread, or add-to-cart work usually starts in `app/lib/product_search.dart`.
   - Cart movement or bundle-save work usually starts in `app/lib/check_out.dart`.
   - Bundle detail, user dashboard, or manual bundle editing work usually starts in `app/lib/bundle_plan.dart`.
   - Shared state or cross-screen behavior usually starts in `app/lib/state/app_state.dart`.

2. Anchor behavior in the shared runtime wiring.
   - Check `app/lib/main.dart` first for provider setup and route registration.
   - Treat `AppState` as the source of truth for selected stores, active tags, cart contents, and bootstrapped user metadata.
   - Treat `GroceryApi` as the only shared network boundary unless the request is specifically about local-only widget state.

3. Keep environment and API assumptions explicit.
   - Backend selection is controlled by `AppEnvironment` in `app/lib/config/app_environment.dart`.
   - Prefer reusing `GroceryApi` methods instead of inlining new HTTP calls in widgets.
   - Preserve the package import prefix `flutter_front_end`; it is still the Flutter package name.

4. Match the existing test seams.
   - Widget tests should prefer injecting `TestGroceryApi`, `AppState`, and providers instead of hitting real HTTP.
   - Use `app/test/frontend_flows_test.dart` as the highest-value flow reference for store selection, search filters, checkout, and bundle planner behavior.
   - If a change affects shared state or flow navigation, update or add a widget test instead of relying only on manual browser checks.

5. Verify the change at the right level.
   - Run `flutter analyze` for compile and lint validation.
   - Run a focused widget test file first when the change is screen-specific.
   - Run `flutter test` when the change touches shared state, routes, or reusable UI helpers.

## Quality Checks
- Keep business state in `AppState`, not duplicated across multiple screens.
- Keep backend calls in `GroceryApi` unless there is a strong reason to isolate a one-off fetch path.
- Reuse existing models from `app/lib/models/grocery_models.dart` instead of introducing ad hoc map parsing in widgets.
- Guard async UI actions with mounted checks where navigation or snackbars happen after awaits.
- For widget tests, avoid real `HttpClient` usage and prefer the fake API harness already used in the repo.
- On narrow layouts, check for `Row` overflow and long text clipping when adding new badges, buttons, or metadata.

## Frontend Change Checklist
1. Identify the primary screen or shared layer that owns the behavior.
2. Trace whether the data belongs in local widget state, `AppState`, or `GroceryApi`.
3. Update the relevant screen and any shared widgets or utils it depends on.
4. Search for the same product, store, cart, or bundle behavior in other screens before finishing.
5. Add or update widget tests when behavior changes across routes or shared state.
6. Run `flutter analyze` and the most relevant `flutter test` target.

## Key Files
- `app/lib/main.dart`
- `app/lib/config/app_environment.dart`
- `app/lib/state/app_state.dart`
- `app/lib/services/grocery_api.dart`
- `app/lib/main_search.dart`
- `app/lib/product_search.dart`
- `app/lib/check_out.dart`
- `app/lib/bundle_plan.dart`
- `app/test/frontend_flows_test.dart`

## Output Expectations
- For explanation requests: summarize the relevant screen, state path, API path, and test coverage.
- For change requests: make the code changes, mention the affected flow, and report what validation was run.
- For debugging requests: identify whether the fault is in widget layout, provider state, fake API wiring, or backend contract assumptions.

## Example Prompts
- Explain how store selection flows into product search and checkout.
- Add a new product search filter and cover it with a widget test.
- Debug a checkout cart regression that only appears after saving a bundle.
- Show where the frontend decides between the local and hosted backend.