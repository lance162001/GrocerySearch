# Markup: GrocerySearch UX Redesign

**Date:** 2026-04-03
**Status:** Approved

## Problem

GrocerySearch's core value — revealing that the same product costs significantly different amounts at different stores — is buried behind two mandatory gates (Google sign-in + store selection) and requires the user to already know what they want to search for. Users don't understand the app's purpose, don't know what to do, and bounce before reaching any "aha moment." The interface is too busy with 13 screens, 5 search filters, a cart/checkout flow, and community features hidden in overflow menus.

## Solution

Rebrand to **Markup** and rebuild the frontend around a 4-tab architecture (Feed, Search, Tracking, Play) with zero gates. The app opens directly to a curated price comparison feed that delivers the aha moment in 3 seconds. Authentication and location are opt-in, triggered only when the user wants to save something.

## Target Users

- **Primary: The budget optimizer** — "I had no idea I was overpaying for eggs. This app just saved me money." The aha is seeing price differences on things they already buy.
- **Secondary: The curious shopper** — "Whoa, Trader Joe's butter is half the price of Whole Foods." The aha is discovering surprising price facts.

## Branding

- **Name:** Markup (short, memorable, directly references price markups — the core insight the app reveals. Has personality and a slightly cheeky "we're exposing the truth" tone.)
- **Color palette:** Keep existing dark green (#1b4332) primary, medium green (#2D6A4F), light green (#95D5B2). Add orange (#c45200) as accent for price-up/sale states.
- **Text contrast:** All body text #111 (near-black) minimum. Secondary text #555. Must pass WCAG AA.

---

## Tab 1: Feed (Home)

The default landing screen. No sign-in, no store selection, no setup required.

### Layout

- **Top bar:** "Markup" wordmark (left), search bar (center, tappable — navigates to Search tab), profile icon (right)
- **Location banner:** "Showing prices from all regions" with "Set your area" link. Dismissible but persistent until location is set.
- **Infinite-scrolling card feed** with paginated backend loading

### Card Types

Cards are served by a new backend endpoint that curates interesting comparisons. Mix ratio target: ~60% price reveals, ~20% savings rankings, ~20% community challenges.

**Price Reveal Card:**
- Product name (bold, 18px, #111)
- Side-by-side price comparison across 2-3 chains
- Best price highlighted with green background (#E9F7EE) and "Best price" label
- Most expensive shown with orange background (#fff8f0) and "+$X more" label
- Action row: "Price history" and "Track price" pill buttons

**Biggest Savings This Week Card:**
- Ranked list of 3-5 items with the largest price spreads
- Each row: product icon, product name, chain comparison, "Save $X" and "X% less"
- Tapping a row navigates to that product's search result

**Community Challenge Card (inline):**
- Same format as Play tab challenges (Product Match or Staple Check)
- Green left border to distinguish from price content
- Answering inline earns points; card animates out and next card loads

### Location Flow

1. **Default:** Chain-level prices from all regions. Banner: "Showing prices from all regions"
2. **Set area:** User taps "Set your area" → enters zip code or allows geolocation
3. **With area set:** Banner updates to "Prices near [ZIP]" — results show specific store locations with addresses
4. **Persistence:** Location saved to local storage (anonymous) or user profile (signed in)
5. **Transparency:** Every price card shows which chain the price is from. When location is set, specific store location shown.

---

## Tab 2: Search

Intentional search for specific products. Accessible via the Search tab or tapping the search bar on the Feed.

### Layout

- **Search bar:** Active with cursor, back arrow to return to previous tab
- **Location context:** Small text "Prices from all regions · Change" below search bar
- **Filter chips:** Horizontally scrollable row: On Sale, Biggest Spreads, Organic, Dairy Free, Vegan, Gluten Free. Chips sourced from existing Tags system. Selected chips get green fill (#E9F7EE, border #95D5B2), unselected gray (#f5f5f5, border #e0e0e0).
- **Sort + count row:** Left: "24 results". Right: "Sort: Best savings ▼" — dropdown with options: Best savings, Price low→high, Price high→low.
- **Results list:** Scrollable, infinite-load

### Search Result Cards

Each card represents one product grouped across stores (not one card per store):

- Product image (56x56), product name (bold, 15px, #111), brand + size
- Best price prominently displayed (22px, bold, #1b4332) with "at [Chain]"
- Other store prices as small pill chips below (gray for moderate, orange for expensive)
- Green "Save $X" badge (top-right) showing max savings across chains
- Best deal result gets green left border (#1b4332)
- Sale items get orange "SALE" badge next to name, sale price in orange with strikethrough original
- Action row: "History" and "Track" links

### What's Removed from Current Search

- Store selection gate (search works immediately across all chains)
- Quantity steppers (not needed for price discovery)
- "Add to cart" action (replaced by "Track")
- Tags modal (replaced by inline filter chips)
- Sort dropdown as a prominent element (now subtle right-aligned text)
- Price Spread toggle (replaced by "Biggest Spreads" filter chip)

---

## Tab 3: Tracking

Replaces the cart/bundle/checkout flow. Users track items to monitor prices over time.

### Layout

- **Header:** "Tracking" title, "Edit" link (for bulk remove)
- **Sign-in nudge** (anonymous users only): "Sign in to get price drop alerts by email" with sign-in button. Soft, dismissible.
- **Tracked items list** with price change badges

### Tracked Item States

**Price Drop (green left border):**
- "PRICE DROP" badge (white on #1b4332) + timestamp
- Product name, chain, new price, old price (strikethrough)

**Price Up (orange left border):**
- "PRICE UP" badge (white on #c45200) + timestamp
- Product name, chain, new price, old price (strikethrough)
- Smart suggestion: "Cheaper at [Chain] ($X) →" link

**Stable (no border):**
- Product name, chain + "Best price" label
- Current price, "Stable X wks" indicator

### Item Detail View (tap any tracked item)

- Back arrow + product name header
- **Price history chart:** 90-day line chart with one line per chain. Best-price chain as solid green line, others as dashed gray/orange.
- **Current prices table:** Ranked 1/2/3 with chain name, price, and diff from best ("Best" badge or "+$X")
- **Actions:** "Stop tracking" (red) and "Share" (green)

### Data Architecture

- Anonymous users: tracked items stored in local storage
- Signed-in users: tracked items persisted to backend (replaces SavedProducts/ProductBundles)
- Price change detection: backend compares latest scrape prices against previous for tracked items
- No "savings estimate" — individual price changes speak for themselves

---

## Tab 4: Play

Community features and the daily game, elevated from hidden overflow menus into a dedicated tab.

### Layout

- **Header:** "Play" title, points badge (top-right, green pill: "🏆 142 pts")
- **Daily Price Guess** card (top, prominent)
- **Quick Challenges** section heading with explanation
- **One Product Match card** at a time
- **One Staple Check card** at a time
- **Your Impact** stats card

### Daily Price Guess

Same existing Wordle-style game, better placement:
- Game icon, title, description
- "Play" button (green pill)
- Streak and total wins stats below

### Product Match Challenge

Renamed from "Same or Different" for clarity:
- Label: "PRODUCT MATCH · +5 pts"
- Explanation: "Are these the same product from different stores? Matching them lets us compare their prices."
- Two product cards side-by-side with "=?" between them
- Buttons: "Same product" (green), "Different" (red), "Skip" (gray)
- After answering, next challenge animates in
- One at a time — no wall of challenges

### Staple Check Challenge

- Label: "STAPLE CHECK · +3 pts"
- Explanation: "Should this count as a basic grocery staple? This helps us build better price comparisons for everyday items."
- Single product card with name, brand, size, category
- Buttons: "Yes, it's a staple" (green), "No" (red), "Skip" (gray)
- One at a time

### Points System

- Product Match: +5 pts per answer
- Staple Check: +3 pts per answer
- Daily game win: +10 pts
- Points displayed in header, lightweight — not a currency, just motivation
- No store, no redemption — purely engagement metric

### Your Impact Stats

- Labels submitted (total count)
- Accuracy (% agreement with consensus)
- Monthly rank (#N this month)
- Provides the feedback loop that was missing — users see their contributions matter

---

## Profile (Top-Right Icon)

Not a tab — accessed via the profile icon in the top bar on any screen.

### Contents

- Sign in / Sign out (Google OAuth)
- Location settings (set/change zip code or geolocation)
- Newsletter preferences (existing functionality)
- Suggest a store (existing form)

---

## Authentication Architecture

- **Anonymous-first:** App works fully without sign-in. Feed, Search, and Play all function for anonymous users.
- **Tracking without sign-in:** Items tracked via local storage. Functional but no email alerts.
- **Soft prompts:** Sign-in prompted at two points only:
  1. Tracking tab: "Sign in to get price drop alerts by email"
  2. Profile icon: standard sign-in option
- **On sign-in:** Local tracked items merged with server-side user profile. Anonymous user ID created on first API call for points/judgements.

---

## Screens Removed

| Current Screen | Replacement |
|---|---|
| Sign-In Page (mandatory gate) | Profile icon (optional) |
| Store Search (mandatory gate) | Location banner (optional) |
| Staples Overview | Staple products surface in Feed |
| Check Out | Removed — no cart |
| Bundle Plan | Tracking tab |
| Shared Bundle | Deferred — share tracked list later |
| Chart Page | Inline in Tracking item detail |
| Label Judgement (hidden) | Play tab challenges + Feed inline cards |
| Game Page (hidden) | Play tab, prominently placed |

## Screens Added/Changed

| New Screen | Purpose |
|---|---|
| Feed (home) | Curated price comparison feed, zero-friction entry |
| Search (redesigned) | Simplified filters, grouped results, no gates |
| Tracking | Price monitoring with change alerts |
| Play | Community challenges + game hub |
| Item Detail | Price history chart + cross-chain prices |
| Profile | Settings, auth, location in one place |

---

## Backend Changes Required

### New Endpoints

- **`GET /feed`** — Returns paginated feed items (price reveals, savings rankings, community challenges). Curated by largest price spreads, recent price changes, and items needing judgements. Accepts optional `zipcode` or `lat/lng` for location filtering.
- **`GET /price-changes`** — Returns price changes for a user's tracked items since last check. Compares latest scrape data against previous prices.
- **`POST /track`** — Save a tracked item for a user. Accepts product ID and optional store preference.
- **`DELETE /track/{product_id}`** — Remove a tracked item.
- **`GET /tracked`** — List all tracked items for a user with current prices and change status.

### Modified Endpoints

- **`GET /products`** — Remove store_ids as required parameter. Default to all stores/chains. Add `chain` filter option alongside existing `store_ids`.
- **`GET /staple-products`** — No longer a separate flow; staple items fed into the feed generation.

### Points System

- New `user_points` table: user_id, points, updated_at
- Existing judgement submission endpoints updated to increment points (+5 grouping, +3 staple)
- New `GET /points/{user_id}` endpoint for fetching score and stats

### No Schema-Breaking Changes

- Existing tables (Products, ProductInstances, PricePoints, etc.) remain unchanged
- ProductBundles/SavedProducts tables kept but deprecated in favor of new tracked items
- New tables added additively: `tracked_items`, `user_points`, `feed_cache`

---

## What's Explicitly Out of Scope

- Push notifications (web or mobile) — email alerts only for now
- Personalized feed (based on user behavior) — static curation by price spread first
- Social features (following users, shared lists) — deferred
- Store-level price precision on feed (chain-level only until user sets location)
- Unsubscribe page changes — keep as-is, still functional
