# Loading States & Lazy Pagination — Design Spec

**Date:** 2026-03-28
**Scope:** Flutter frontend only (`app/`)

## Goal

Replace bare `CircularProgressIndicator` spinners with shimmer skeleton screens, and reduce the product page size from 100 to 20 so the first batch of results appears faster.

## New Components

### `app/lib/widgets/product_card_skeleton.dart`

A `ProductCardSkeleton` stateless widget that mirrors the real product card structure:
- 40×40 image placeholder block
- Three text line placeholders (72%, 44%, 30% width)
- Two chip placeholders

Wrapped in `Shimmer.fromColors(baseColor: Color(0xFFf0f0f0), highlightColor: Color(0xFFe0e0e0))` from the `shimmer` package.

### `app/lib/widgets/store_card_skeleton.dart`

A `StoreCardSkeleton` stateless widget matching the store grid card:
- 48×48 logo placeholder block
- Town name line placeholder
- Address line placeholder

Same shimmer wrap as above.

## Changes to Existing Files

### `pubspec.yaml`

Add `shimmer: ^3.0.0` to `dependencies`.

### `product_search.dart`

1. **Page size:** `pageLength` constant: `100` → `20`
2. **Initial load state:** Inside `FutureBuilder`, when `snapshot.connectionState == ConnectionState.waiting`, render a `ListView` of 5 `ProductCardSkeleton` widgets instead of `CircularProgressIndicator`. Apply decreasing opacity to the skeletons (1.0, 1.0, 0.8, 0.55, 0.3) to suggest the list extends further.
3. **Load-more state:** Change `itemCount` from `groupedProducts.length` to `groupedProducts.length + (_isLoadingMore ? 3 : 0)`. For indices ≥ `groupedProducts.length`, render `ProductCardSkeleton` with decreasing opacity (1.0, 0.65, 0.35) instead of a real card. The existing `_isLoadingMore` flag drives this with no new state needed.

### `main_search.dart`

**Initial load state:** Inside `FutureBuilder`, when `snapshot.connectionState == ConnectionState.waiting`, render a `GridView` of 8 `StoreCardSkeleton` widgets using the same `crossAxisCount` and spacing/padding as the real grid, so the layout doesn't shift when data arrives.

## What Does Not Change

- Scroll trigger logic (`scroll_utils.dart`) — unchanged
- `_isLoadingMore`, `_hasMore`, `_loadMoreProducts` logic — unchanged except `pageLength`
- Widget tests — existing tests use `TestGroceryApi` and don't hit the `FutureBuilder` loading state; no new tests needed for the skeleton widgets (pure presentational, no logic)
- Error states — unchanged (still show error text on `snapshot.hasError`)

## Package

`shimmer ^3.0.0` — no transitive dependencies; compatible with `sdk: '>=3.0.0 <4.0.0'`.
Import is confined to the two new skeleton widgets only.
