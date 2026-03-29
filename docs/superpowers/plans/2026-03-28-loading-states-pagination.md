# Loading States & Lazy Pagination Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace bare spinners with shimmer skeleton screens and shrink the product page size from 100 to 20 for faster time-to-first-content.

**Architecture:** Add the `shimmer` package, create two new skeleton widgets (`ProductCardSkeleton`, `StoreCardSkeleton`), then wire them into the two `FutureBuilder` loading states and the existing `_isLoadingMore` inline list expansion.

**Tech Stack:** Flutter, `shimmer ^3.0.0` (pub.dev), existing `provider` state, existing `FutureBuilder` pattern.

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `app/pubspec.yaml` | Add shimmer dependency |
| Create | `app/lib/widgets/product_card_skeleton.dart` | Shimmer placeholder matching real product card layout |
| Create | `app/lib/widgets/store_card_skeleton.dart` | Shimmer placeholder matching store grid card layout |
| Modify | `app/lib/product_search.dart` | Page size 100→20, initial load skeleton, load-more inline skeletons |
| Modify | `app/lib/main_search.dart` | Store grid initial load skeleton |

---

## Task 1: Add shimmer package

**Files:**
- Modify: `app/pubspec.yaml`

- [ ] **Step 1: Add dependency**

In `app/pubspec.yaml`, add `shimmer: ^3.0.0` to the `dependencies` block. Place it alphabetically after `provider`:

```yaml
dependencies:
  cached_network_image: ^3.2.3
  confetti: ^0.7.0
  firebase_auth: ^6.2.0
  firebase_core: ^4.5.0
  fl_chart: ^1.2.0
  flutter:
    sdk: flutter
  google_sign_in: ^7.2.0
  http: '>=1.1.0 <2.0.0'
  provider: ^6.1.2
  shimmer: ^3.0.0
  url_launcher: ^6.3.2
```

- [ ] **Step 2: Install the package**

```bash
cd app && flutter pub get
```

Expected output: `Resolving dependencies... shimmer 3.0.0` in the output, ending with `Changed N dependencies!`.

- [ ] **Step 3: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock
git commit -m "feat: add shimmer package for loading skeleton animations"
```

---

## Task 2: Create ProductCardSkeleton widget

**Files:**
- Create: `app/lib/widgets/product_card_skeleton.dart`

The real product card (`ProductBox`) has: 40×40 image, then a column with a name line, brand line, size line, and a price row. Below the card the list item wraps chips (best store, other stores). The skeleton mirrors this structure.

- [ ] **Step 1: Create the file**

Create `app/lib/widgets/product_card_skeleton.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class ProductCardSkeleton extends StatelessWidget {
  const ProductCardSkeleton({super.key, this.opacity = 1.0});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Shimmer.fromColors(
        baseColor: const Color(0xFFf0f0f0),
        highlightColor: const Color(0xFFe0e0e0),
        child: Card(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Image placeholder
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Text lines
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _line(double.infinity, 12),
                          const SizedBox(height: 6),
                          _line(160, 10),
                          const SizedBox(height: 6),
                          _line(80, 10),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Price placeholder
                    _line(48, 16),
                  ],
                ),
                const SizedBox(height: 8),
                // Chip row
                Row(
                  children: [
                    _chip(100),
                    const SizedBox(width: 8),
                    _chip(72),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _line(double width, double height) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
        ),
      );

  Widget _chip(double width) => Container(
        width: width,
        height: 22,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
        ),
      );
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd app && flutter analyze lib/widgets/product_card_skeleton.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add app/lib/widgets/product_card_skeleton.dart
git commit -m "feat: add ProductCardSkeleton shimmer widget"
```

---

## Task 3: Create StoreCardSkeleton widget

**Files:**
- Create: `app/lib/widgets/store_card_skeleton.dart`

The real store card (in `main_search.dart`) shows: a 58×58 company logo image, then town text (bold 12px), state text (11px), address text (10px italic). The skeleton mirrors this.

- [ ] **Step 1: Create the file**

Create `app/lib/widgets/store_card_skeleton.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class StoreCardSkeleton extends StatelessWidget {
  const StoreCardSkeleton({super.key, this.opacity = 1.0});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Shimmer.fromColors(
        baseColor: const Color(0xFFf0f0f0),
        highlightColor: const Color(0xFFe0e0e0),
        child: Card(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xFFE4E4E7)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo placeholder
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 6),
                // Town line
                Container(
                  width: 56,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 4),
                // Address line
                Container(
                  width: 72,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd app && flutter analyze lib/widgets/store_card_skeleton.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add app/lib/widgets/store_card_skeleton.dart
git commit -m "feat: add StoreCardSkeleton shimmer widget"
```

---

## Task 4: Wire ProductCardSkeleton into product_search.dart (initial load + page size)

**Files:**
- Modify: `app/lib/product_search.dart`

Two changes in this task: reduce page size and replace the initial load spinner.

- [ ] **Step 1: Change page size**

In `app/lib/product_search.dart` line 34, change:

```dart
static const int pageLength = 100;
```

to:

```dart
static const int pageLength = 20;
```

- [ ] **Step 2: Add the import**

Add this import near the top of the file, after the existing widget imports:

```dart
import 'package:flutter_front_end/widgets/product_card_skeleton.dart';
```

- [ ] **Step 3: Replace the initial load spinner**

Find the `FutureBuilder` builder (around line 989 in the original file). The last branch currently reads:

```dart
          return const Center(child: CircularProgressIndicator());
```

Replace it with a `ListView` of 5 skeletons with decreasing opacity:

```dart
          return ListView(
            padding: const EdgeInsets.all(1),
            children: const [
              ProductCardSkeleton(opacity: 1.0),
              ProductCardSkeleton(opacity: 1.0),
              ProductCardSkeleton(opacity: 0.8),
              ProductCardSkeleton(opacity: 0.55),
              ProductCardSkeleton(opacity: 0.3),
            ],
          );
```

- [ ] **Step 4: Verify no analysis errors**

```bash
cd app && flutter analyze lib/product_search.dart
```

Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add app/lib/product_search.dart
git commit -m "feat: shimmer skeleton for product search initial load, page size 100→20"
```

---

## Task 5: Wire ProductCardSkeleton into product_search.dart (load-more)

**Files:**
- Modify: `app/lib/product_search.dart`

When `_isLoadingMore` is true, append 3 skeleton cards at the bottom of the `ListView.builder` instead of nothing.

- [ ] **Step 1: Change itemCount**

Find the `ListView.builder` (the one with `controller: scrollController`). Its `itemCount` currently reads:

```dart
              itemCount: groupedProducts.length,
```

Change it to:

```dart
              itemCount: groupedProducts.length + (_isLoadingMore ? 3 : 0),
```

- [ ] **Step 2: Add skeleton rendering to itemBuilder**

The `itemBuilder` currently starts with:

```dart
              itemBuilder: (context, index) {
                final group = groupedProducts[index];
```

Replace just those two opening lines with:

```dart
              itemBuilder: (context, index) {
                if (index >= groupedProducts.length) {
                  const opacities = [1.0, 0.65, 0.35];
                  final skeletonIndex = index - groupedProducts.length;
                  return ProductCardSkeleton(
                    opacity: opacities[skeletonIndex],
                  );
                }
                final group = groupedProducts[index];
```

- [ ] **Step 3: Verify no analysis errors**

```bash
cd app && flutter analyze lib/product_search.dart
```

Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add app/lib/product_search.dart
git commit -m "feat: inline shimmer skeletons for product load-more pagination"
```

---

## Task 6: Wire StoreCardSkeleton into main_search.dart

**Files:**
- Modify: `app/lib/main_search.dart`

Replace the centered `CircularProgressIndicator` at line 382 with a `GridView` of 8 skeleton cards using the same responsive `crossAxisCount` and spacing already computed in the `build` method.

- [ ] **Step 1: Add the import**

Add this import near the top of `app/lib/main_search.dart`, after the existing widget imports:

```dart
import 'package:flutter_front_end/widgets/store_card_skeleton.dart';
```

- [ ] **Step 2: Replace the loading state**

Find the loading branch of the `FutureBuilder<List<Store>>` (line 382 in the original). It currently reads:

```dart
                return const Center(child: CircularProgressIndicator());
```

Replace it with a skeleton grid that matches the real grid's layout parameters:

```dart
                const skeletonOpacities = [
                  1.0, 1.0, 1.0, 0.7, 0.7, 0.7, 0.4, 0.4,
                ];
                return GridView.builder(
                  itemCount: skeletonOpacities.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    childAspectRatio: 1.35,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                  ),
                  shrinkWrap: true,
                  primary: false,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  itemBuilder: (context, index) =>
                      StoreCardSkeleton(opacity: skeletonOpacities[index]),
                );
```

- [ ] **Step 3: Verify no analysis errors**

```bash
cd app && flutter analyze lib/main_search.dart
```

Expected: `No issues found!`

- [ ] **Step 4: Run all widget tests**

```bash
cd app && flutter test
```

Expected: all tests pass. The existing tests use `TestGroceryApi` and resolve futures immediately, so they bypass the loading branch — no failures expected.

- [ ] **Step 5: Commit**

```bash
git add app/lib/main_search.dart
git commit -m "feat: shimmer skeleton grid for store search initial load"
```

---

## Verification

After all tasks are committed, do a quick manual check:

```bash
cd app && flutter run -d chrome
```

1. Open the **Stores** tab — confirm 8 shimmer cards appear briefly before real store cards load.
2. Type a search query in **Products** — confirm 5 shimmer cards appear while results load.
3. Scroll to the bottom of a product list — confirm 3 shimmer cards appear while the next page loads, then get replaced by real cards.
4. Confirm existing error states still show text (not a spinner or skeleton) on network failure.
