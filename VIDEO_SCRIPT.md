# QuickKart demo video script

**Length target:** 5½–6½ min. Camera on for the whole recording + screen share,
English. Record on Loom / Drive / YouTube-unlisted, then **test the link in an
incognito window**. Rehearse once with a timer; cut hard at 7:00.

App prep before recording: reset the server (**Reset ALL server data** in Dev
tools), reset latency, run the app fresh (`flutter run`), keep it in foreground.

---

## 0. Intro (≈ 20 s) — camera shot

"Hi, this is QuickKart. Over this assignment I fixed all 13 seeded bugs
test-first — a failing test committed before every fix — and shipped Feature 1,
offline cart reconciliation with safe idempotent checkout, and Feature 2,
remote control without a release: a kill switch, forced/optional updates and a
server-driven home. Everything is pushed with full history; the docs
(`BUGS.md`, `DECISIONS.md`, `AI_LOG.md`) live at the repo root."

Switch to screen share now.

## 1. Conflict flow (≈ 70 s) — Dev tools → **Create conflicts for my cart** → checkout

1. Home → open Dev tools (bug icon in the app bar). Show the chaos cards.
2. Add **Toned Milk (₹29)** and **Farm Eggs (₹54)** to the cart.
3. Tap **Create conflicts for my cart**: the server now disagrees with the cart
   on price, stock limits and availability.
4. Open the cart → tap **Place order**.
5. Point at the **"Price & availability changed"** banner: one review card
   listing every change in words — e.g. "Farm Eggs is now limited to 3 per
   order", "price changed for Toned Milk". Note: price *drops* apply silently;
   increases, quantity cuts, removals and coupon changes ask the user. The
   order was not placed.
6. Tap **Got it** (the local cart is already the reconciled one), then place
   the order again → the order success screen, at the *server's* prices.

**Why:** reconciliation runs once inside checkout, right before the request is
built, so the user can never be charged an amount they didn't see; a review
banner (not a per-product popup storm) blocks anything they'd disagree with.

## 2. Lost response → only one order exists (≈ 55 s)

1. Dev tools → **Lost order responses** → tap **Lose next**, close Dev tools.
2. Place order with whatever is in the cart. The request has already hit the
   server; the response dies on the wire. Show the honest message — "…please
   check again in a moment" wording that does NOT claim success or failure.
3. Open Dev tools → show **order count is exactly 1** despite the failure.
4. Tap **Place order** again with the same cart → order success. My Orders
   still shows **exactly one order**.

**Why:** every order request carries an **Idempotency-Key** derived from the
exact cart+pricing payload. On timeout we keep the same key and retry once, so
the server deduplicates: the retry is a read that returns the original order.

## 3. Offline start (≈ 50 s)

1. Dev tools → turn on **Offline (no internet)** → close Dev tools → kill the
   app → relaunch.
2. The home loads from the on-device cache with the amber
   "You are offline. Showing saved products." ribbon. Mention the offline cache
   is keyed per category (one category can never leak another's rows).
3. Open the cart — persisted across restart (`cart.v1`); open My Orders — the
   previous orders read from cache.
4. Dev tools → turn the offline switch off → pull-to-refresh → fresh data.

**Why:** the hidden GET cache was removed (QK-102) so freshness belongs to
explicit caches, each with a job and a key.

## 4. Store closed & force update, live (≈ 75 s)

1. Dev tools → **Close store** preset. On home: red ribbon with the
   **server's own message** ("We are closed for a short break. Back in 30
   minutes!"). Browsing still works — nothing is broken, nothing is hidden.
2. Open the cart: same banner above the lines, and the **Place order button is
   dead** (grey, unpressable). Point out the double barrier: the button and,
   deeper, `CheckoutController` that refuses *before building any request* —
   so no hidden path can order in a closed store.
3. Dev tools → **Open store** → reopen the cart: live again, no restart.
4. Dev tools → **Force update (min 2.0.0)**: the full-screen non-dismissible
   "Update required" gate — it covers every pushed route, and "Update now"
   opens `update_url` externally (url_launcher).
5. Back to the reset preset (min 1.0.0 / latest 1.4.0): the gate disappears
   live.
6. Dev tools → **Soft update (latest 1.5.0)**: an "Update available" banner
   with **Later** / **Update now**. Tap **Later**; re-apply the same soft
   preset → stays quiet (dismissals persist per `latest_version`, including
   across restart); a newer version would ask again.

## 5. Code walkthrough (≈ 110 s)

- `lib/features/cart/application/cart_reconciler.dart`:
  `CartReconciler.reconcile` is a pure function of (local cart, server state),
  batching product fetches (50 ids/request). It returns
  `ReconciliationResult(cart, changes)` where `cart` is exactly what could be
  ordered now, and `changes` carries one entry per product/coupon issue with
  `requiresUserReview` false only for price drops. Coupons: BUSINESS_RULES
  says a coupon under its minimum stays applied in the cart but is omitted
  from the order request — implemented exactly that way.
- `lib/features/checkout/application/checkout_controller.dart`: the order:
  reentrancy guard → store-open pre-check → reconcile → review gate → build
  payload once → POST with `Idempotency-Key` → one same-key retry on timeout →
  409/422 mean the world moved: re-reconcile and ask for review. The
  fingerprint (json of the exact request body) makes key reuse safe.
- Remote config (`lib/features/app_config/…`): `ConfigRepository.load` keeps
  the **raw last-good config** under `config.last_good_v1` and never throws,
  so an outage can't stop the app from booting; `AppConfigController` holds a
  single broadcast listener with `ref.onDispose` cleanup (the BUG-12 leak
  pattern is the reason). `UpdatePolicy` + `HomeLayout.parse` degrade every
  malformed value to "no update"/"default layout" — remote control must never
  be able to brick the app.
- Home screen: the section order comes from `home_sections`; everything from
  banner color to the deals row degrades gracefully. Reorder in Dev tools →
  the home reorders live, in one frame.

## 6. Outro (≈ 20 s) — camera shot

"117 tests green, analyzer clean, one failing test per bug before each fix —
`BUGS.md` maps every bug to its test and fix commit SHAs. My final commit SHA
and this video are on the submission form. `AI_LOG.md` documents where the AI
misled me and how I caught it. Thanks for watching!"

---

### Recording checklist

- [ ] Camera on, mic audible, English throughout
- [ ] Screen share legible (zoomed 120%+)
- [ ] Timer within 5–7 min (stop at 7)
- [ ] **Reset ALL server data** right before section 1
- [ ] Use the real labels: **Create conflicts for my cart**, **Lose next**,
      **Offline (no internet)**, **Close store / Open store**,
      **Soft update (latest 1.5.0)**, **Force update (min 2.0.0)**
- [ ] Link opens in an incognito window (no login) before submission
