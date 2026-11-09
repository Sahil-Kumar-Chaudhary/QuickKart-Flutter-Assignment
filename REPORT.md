# QuickKart assignment — final report

**Repo:** https://github.com/Sahil-Kumar-Chaudhary/QuickKart-Flutter-Assignment
**Final state:** `flutter test` → **117 passing**, `flutter analyze` → **No
issues**, across 26 test files. Full history preserved (one failing test commit
before every fix; never force-pushed).

---

## Part A — the 13 seeded bugs (25%)

Every bug: failing test → smallest correct fix → full-suite regression →
`BUGS.md` entry with symptom/steps/root cause/fix/test/test+fix SHAs, in
separate commits. Highlights:

| Bug | Root cause | Fix shape |
|---|---|---|
| QK-101 cart lost on restart | mutations skipped `CartStorage.save()` | save-before-publish on every mutation |
| QK-102 stale everything | hidden 10-min `ApiClient` GET cache | cache deleted; freshness owned by repos |
| orders stale after checkout | never-invalidated `FutureProvider` | autoDispose + invalidate on success |
| ₹19.99 → 1998 | `.toInt()` truncation | round to nearest paisa |
| ₹199.50 → ₹199 | format dropped paise | include paise when non-zero |
| free delivery off-by-one | `>` instead of `>=` | inclusive threshold |
| legacy DTO crash | `mrp: null`, `stock: "…"` | fallbacks + `int.tryParse` |
| offline wrong-category rows | cache key + limit not scoped | per-category, per-limit keys |
| rapid taps lost | unserialized read-modify-write | serialized `_commit` chain |
| double load-more | no in-flight guard | in-flight guard + retryable footer |
| search race/stale tokens | late responses overwrote newer | token check + autoDispose + dispose clear |
| category listener leak | stream never cancelled | `ref.onDispose` cancel |
| coupon below minimum | hard error at request time | omit code; coupon stays applied contextually |

("Suspicious but NOT a bug" items are documented at the bottom of `BUGS.md`.)

## Part B — Feature 1: reconciliation & safe checkout (30%)

- **`CartReconciler.reconcile`** (pure, batched fetches). The result's `cart` is
  exactly orderable now; `changes` lists one entry per product/coupon issue;
  only price *drops* are silent — increases, quantity cuts, removals and coupon
  changes require review. Malformed legacy products don't break it; order of
  lines is preserved.
- **`CheckoutController.placeOrder`**: reentrancy guard → live store-open
  pre-check (no request when closed) → reconcile, block on
  `requiresUserReview` → build the payload once → `POST /v1/orders` with an
  **Idempotency-Key** pinned to the exact payload fingerprint → one same-key
  retry on timeout (server dedups) → keep the key after an uncertain outcome →
  409/422 re-reconcile and ask for review.
- **Cart UI**: on open, reconciles and shows the
  "Price & availability changed" review banner via `CartReviewController`
  (`describeChanges`), acknowledge with "Got it".
- Proof runs: chaos tests for two times-out scenarios, response-loss and
  conflicts — one order, always.

## Part C — Feature 2: remote control without a release (20%)

- **Config caching** — `ConfigRepository.load` stores the raw last-good
  response under `config.last_good_v1`, never throws, network → cache →
  defaults.
- **Live config** — `AppConfigController`: one app-lifetime broadcast
  subscription, cancelled in `ref.onDispose` (+ `_disposed` guard), hydrated
  before the first frame by `main.dart`.
- **Kill switch** — closed store: home ribbon + cart banner with the server's
  message; the place-order button is dead AND the controller refuses before
  any request; reopening re-enables live.
- **Update gate** — `UpdatePolicy` (segment-wise compare, malformed → "none")
  → required gate covers the whole Navigator (MaterialApp.builder) and is
  non-dismissible with an external `update_url` button (`url_launcher`, guarded
  — bad links degrade to a snackbar); optional prompt dismissible with the
  dismissal persisted per `latest_version` (`app_update.dismissed_version`),
  no re-nag, survives restarts.
- **Server-driven home** — `HomeLayout.parse` (unknown ids ignored,
  duplicates first-wins, malformed → default sections) renders
  banner/categories/deals/all_products in configured order; deals failures
  render empty; all-products hosts the paginated grid as slivers with shared
  pagination; layout publishes reorder the live screen.

## Documentation (15%)

- `BUGS.md` — 13 blocks + "suspicious but not a bug".
- `DECISIONS.md` — every heading answered (Feature 3 marked "Not attempted").
- `AI_LOG.md` — 8 recorded prompts, **5 honest "AI was wrong" cases** (finder
  mismatches, test ordering, missed broadcasts, over-suppression of nagging,
  viewport cache-extent assumptions), each with how it was noticed.
- `VIDEO_SCRIPT.md` — the demo script in the assignment's mandated section
  order, with why-explanations per section.

## What I would do with one more week

Persist idempotency keys across process restarts, hide add-actions on
non-orderable products, ETag-style catalog caching against real servers with
50-id batch pagination limits near the contract limits, and config-schema
versioning for `last_good` migrations.

## Final commit

See the submission form; the SHA snapshot in the bundle is final at this
point in history (subsequent doc/report commits will be pushed before the
bundle is cut).
