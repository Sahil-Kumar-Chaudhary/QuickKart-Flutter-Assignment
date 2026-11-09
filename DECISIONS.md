# Decisions & trade-offs

## 1. Cart reconciliation policy (Feature 1, part B)

- **When does reconciliation run, and why there?**
  - Once per checkout attempt, inside `CheckoutController.placeOrder()` **before**
    any order request is built. Reason: the moment of truth is payment — the user
    must never be charged a price they didn't see, and the server will reject
    inconsistent carts anyway. Reconciling *in the cart screen* as an idle
    side-effect would hammer the server while typing and could silently rewrite
    the cart while the user is editing quantities.
  - It also runs on demand from the cart screen (the "Price & availability
    changed" review banner calls `check()`), so a user can pre-flight their cart
    without starting a checkout.
- **What does the user see for each kind of change?** (`CartChange.requiresUserReview`)
  - *Price lowered*: applied silently, no prompt.
  - *Price increased*: blocks the order; review banner says e.g.
    "Shimla Apple is now ₹159 (was ₹129)." The order is not placed.
  - *Quantity reduced* (stock or max-per-order): blocks the order; the line is
    clamped to what the server allows and the banner says so.
  - *Out of stock / no longer sold*: block the order; the line disappears from
    the reconciled cart and the banner names the removed product.
  - *Coupon removed/expired*: blocks the order; the banner mentions the coupon.
  - The banner lists **all** changes together (one banner, one review), not one
    popup per change.
- **What happens to out-of-stock / discontinued items?** They are removed from
  the reconciled cart. We do not keep a ghost line "added later if back in
  stock" — that surprises users at payment time.
- **Offline-built carts:** the reconciler needs the server (`ApiException` on
  unreachable), so checkout cannot even start reconciliation offline: the user
  gets the standard "check your connection" failure with the cart untouched.
  A cart built entirely offline (cache-only product pages) is treated exactly
  like an online one — there is nothing special at checkout, because the
  reconciler will sync it at order time.
- **Alternatives considered and rejected:**
  - *Periodic background re-reconcile while shopping*: rejected — noisy,
    battery-wasteful, and it can rewrite the cart under the user's fingers.
  - *Optimistic checkout ("order then fix")*: rejected — the user may be charged
    for a stale price before we know anything changed.

## 2. Safe checkout & idempotency

- **How are duplicate orders prevented?** (`CheckoutController`)
  - A reentrancy guard so a second tap while a request is in flight cannot even
    build a second request.
  - The request payload is built once via `OrderApi.requestBody(cart, pricing)`
    and fingerprinted as `jsonEncode(body)`. An idempotency key
    (`ck-<base36-time>-<base36-random>`) is generated **per fingerprint** and
    stored in controller state.
  - The key is sent as the `Idempotency-Key` header on `POST /v1/orders`. On a
    *timeout or lost response*, the key is **kept**; one immediate retry uses
    the *same* key, so the server returns the original order instead of
    creating a second one. If the user taps again later with the same cart, the
    same key is reused. The key is cleared only on success, or on a 422
    `IDEMPOTENCY_KEY_REUSED` (where we re-reconcile and start a fresh round).
- **What does the user see on timeout / lost response?**
  - After two timeouts with the same key: an honest snack/popup wording along
    "…your order **may have been** placed" plus intact idempotency protection.
    No fake success, no silent retry storm.
- **Edge cases handled:**
  - 409/422 during placement (world changed mid-flight): re-reconcile, update
    the local cart, ask for review — never surface a raw HTTP error.
  - Order response loss (`orderResponseLossRate` chaos): the kept key makes the
    next attempt a read, not a duplicate write.
  - Store closing mid-session: `placeOrder` refuses **before any request**.
- **Edge cases you know you did NOT handle:**
  - The idempotency key lives only in memory; if the app is killed between
    request and response, a restart generates a new key (server-side window is
    unbounded until expiry). Persistence would need a store write per attempt.
  - A user who changes the cart *between* two timeout-retries gets a fresh
    fingerprint → a fresh key; the server may end up with two orders for two
    intentionally different carts — this is documented, deliberate behaviour,
    not a bug we can fix client-side.

## 3. Remote config, updates & kill switch (Feature 2)

- **Caching strategy and failure behaviour:** (`ConfigRepository.load`)
  - The fully **raw** JSON of the last good response is persisted under
    `config.last_good_v1` (raw, because parsing rules change between app
    versions). Startup reads the network first; on any failure it falls back to
    the persisted values; if both fail, the in-code defaults are used. `load()`
    **never throws** — a config outage can never make the app fail to boot.
- **How live updates propagate, and how you avoid leaks:**
  - The mock server broadcasts config changes; `AppConfigController.build()`
    subscribes once and cancels the subscription in `ref.onDispose` (plus a
    `_disposed` guard). There is exactly one app-level listener living for the
    app's lifetime — screens watch the controller and never subscribe directly
    (BUG-12 taught us that lesson).
  - Publishes that happen *before* the first `read()` of the controller are
    missed by design (the broadcast does not replay). `main.dart` hydrates the
    controller from the server snapshot before the first frame, so app start
    never misses; widget tests mirror that hydration in their helpers.
- **Force / optional update UX:** (`UpdateGate`, `UpdatePolicy`)
  - `UpdatePolicy.evaluate` compares the app version (`1.4.0`, overridable via
    `appVersionProvider` for tests) to `min_supported_version` / `latest_version`
    segment by segment; **malformed or missing values degrade to "no update
    required"** — a broken console entry must never lock paying customers out.
  - *Required*: a full-screen, non-dismissible page wrapping the **Navigator**
    (via `MaterialApp.builder`), so pushed routes stay covered too. One button
    → `update_url`. The URL is opened with `url_launcher`; `canLaunchUrl` and
    plugin errors degrade to a snackbar with the raw link — a bad link must not
    crash the gate.
  - *Optional*: a top banner with **Later** / **Update now**. "Later" stores
    `latest_version` under `app_update.dismissed_version`; the gate stays quiet
    for that exact version (even re-published) and returns when a newer one
    lands. The dismissal reloads on app start, so restarts don't re-nag. While
    the persisted dismissal is still loading, the gate stays out of the way to
    avoid a wrong flash.
- **Store closed UX:**
  - Home: a prominent ribbon with the **server-provided `store_closed_message`**
    at the top; browsing stays fully available.
  - Cart: the same message as a banner, and **the place-order button is dead**
    (`onPressed: null`) — checkout is impossible without a request even if the
    user tries to outsmart the UI; `CheckoutController` re-checks the live
    config before building a request, so a mid-session close is respected
    within the next frame.
  - Reopening re-enables everything live; no restart.
- **Server-driven home: robustness to bad config:** (`HomeLayout.parse`)
  - `home_sections` drives the order: `banner → categories → deals →
    all_products`. Unknown section ids are ignored, duplicates keep the first
    occurrence, malformed/empty JSON falls back to the default layout
    (`categories` + `all_products`).
  - A malformed `home_banner` is skipped entirely; banner colors parse with a
    brand-color fallback.
  - The deals row is a `FutureProvider` whose error/loading states render *empty*
    — a fitting a broken deals fetch can never break the home screen.
  - The all-products section re-hosts the paginated catalog grid **as slivers**
    inside the home scroll view (scroll-position-driven `loadMore` is shared
    via the same `catalogControllerProvider('all')` source as category pages).
  - Publishing a new layout reorders the live screen within one frame (verified
    by a mid-session test), no restart.

## 4. Feature 3 (if attempted)

- Not attempted; Part A and B + all Part C sub-features were prioritised
  (kill switch already includes live "closing while the cart is open", which
  covers the riskiest documented behaviour).

## 5. Other decisions

- Packages added (and why):
  - `url_launcher ^6.3.0` — required for the forced-update "Update now" button
    to open the store page. It is the canonical Flutter way to launch external
    URLs; writing a custom platform channel would duplicate a well-tested
    package for no benefit.
- Refactors made (and why):
  - Home screen rewritten from a hard-coded `PaginatedCatalogView` to a
    slivers-based `CustomScrollView` so a *server-ordered* section list can put
    the infinite-scroll product grid anywhere in the order (a nested
    scrollable can't live inside another scroll view's sliver list).
  - Test harness gained a generic `overrides` list (and `AppConfigController`
    hydration helpers) so every Feature-2 widget test mirrors what `main.dart`
    does at boot.
  - `update_gate_state.dart` keeps dismissal persistence isolated from the
    presentational gate widget.

## 6. Looking ahead

- **One more week:** persist the idempotency key; hide "add" on non-orderable
  products; reuse the reconciler for a per-category price-mismatch badge; warm
  the config repository before `runApp` with a timeout budget; track
  `last_good` versions per schema and migrate.
- **At 10k DAU, what breaks first?** The per-storecart-fingerprint→key map in
  `CheckoutController` is per-container: process restarts lose it. First sure
  break is the mock-server-shaped batch product fetch (50 ids/request) — real
  traffic needs caching with ETags. Next: `SharedPreferences` on every config
  change would chew disk; move storage off the UI thread.
- **Hotfix without a store release:** exactly this Feature 2 wiring — bump
  `min_supported_version` for a hard gate, or `store_open: false` + message for
  an instant freeze, or re-`home_sections` for cosmetic containment, all within
  seconds of publishing config.
