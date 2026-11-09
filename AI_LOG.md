# AI usage log

Tools used: OpenCode (GLM agent session) for repo exploration, test writing,
implementation, `flutter test` / `flutter analyze` runs, git commits & pushes.

## Significant prompts (5–10)

| # | What I asked (summary is fine) | What I did with the answer |
|---|---|---|
| 1 | "Fix QK-101..QK-104 test-first, one commit per bug, following ASSIGNMENT.md" | Walked every Part A bug: wrote a failing test, minimal fix, regression run, BUGS.md entry, separate commit for each of BUG-1..13. |
| 2 | "Design the cart reconciler against API_CONTRACT/BUSINESS_RULES before coding" | Produced the `ReconciliationResult` contract first (with contract tests), then the implementation — caught the "one product may emit two changes" question early. |
| 3 | "How do I prevent duplicate orders on slow networks?" | Designed the fingerprint→idempotency-key reuse scheme with the same-key retry, and wrote the 300ms-timeout chaos tests to prove exactly one order exists. |
| 4 | "The config broadcast may publish before any listener exists — will updates be missed?" | Confirmed the lazy-notifier gap; mirrored `main.dart` hydration in test helpers instead of inventing a replaying stream the server doesn't support. |
| 5 | "Add the forced-update gate without letting back-button escape" | Wrapped the gate in `MaterialApp.builder` (covers pushed routes) instead of only `home`. |
| 6 | "Write the widget tests for the optional-update nag rule" | Produced the dismiss-persists-per-latest_version tests, which found the gate suppressing on *any* dismissal (fixed by comparing versions). |
| 7 | "Prove the server-driven home survives `home_sections: 'not json'`" | Added robustness tests that drove the `HomeLayout.parse` contract (unknown ids, duplicates, malformed). |
| 8 | "Run the full suite + analyze and fill the docs" | Final regressions (117 passing, 0 analyzer issues), then DECISIONS.md/AI_LOG.md/report writing. |

## When the AI was wrong or misleading (at least 3)

### 1. `find.text` matched strings that are concatenated on screen
- **What it suggested:** Assert `find.text('6 pcs ₹54')` on a cart tile.
- **Why it was wrong:** The cart tile renders `"6 pcs", "₹54"` as **separate Text
  widgets inside one Row**, so the concatenated string never exists as a widget.
- **How I noticed:** A test failed with `Found 0 widgets with text…` even though
  the string was visible on the (imagined) screen; dumping the widget tree showed
  the split texts.
- **What I did instead:** Used `find.textContaining('₹54')`/precise per-fragment
  assertions and recorded the rule in the test-suite gotchas.

### 2. Cart mutation ordering in tests ("seed after price change")
- **What it suggested:** In a reconciliation test, first `server.setPrice(...)`,
  then seed the cart, then reconcile.
- **Why it was wrong:** Seeding the cart from a *changed* product snapshot put
  the new price into the cart already, so the reconciler had nothing to detect —
  the test passed trivially or found nothing to change depending on order.
- **How I noticed:** newPassword the test output showed an empty `changes` list
  when one was expected.
- **What I did instead:** Now every conflict test seeds the cart **first**, then
  mutates the server product; documented as a mandatory ordering rule in the
  cart test helpers.

### 3. Lazy Riverpod notifiers miss broadcasts published before the first read
- **What it suggested:** Put `publishConfig(...)` in `setUp`, then just pump the
  widget — the controller "obviously" starts with the latest config.
- **Why it was wrong:** `AppConfigController` builds lazily and its stream
  subscription only exists after the first `read()`; events published before
  that are dropped by the non-replaying broadcast. The gate silently evaluated
  against defaults and the tests found no gate.
- **How I noticed:** The update-gate tests failed with "Found 0 widgets with
  text 'Update required'" although the app logic was correct.
- **What I did instead:** Each test helper hydrates the controller from
  `server.configValues` exactly like `main.dart` does before the first frame;
  publishes that must be observed mid-session happen after the first pump.

### 4. (Bonus) The update gate suppressed re-nagging for *any* dismissed version
- **What it suggested:** Hide the optional banner whenever a dismissal record
  exists.
- **Why it was wrong:** The rule is per `latest_version`: a *newer* version must
  ask again. The naive suppression silenced the prompt forever.
- **How I noticed:** The "newer version re-asks" contract test failed.
- **What I did instead:** The gate compares the dismissed value to
  `config.latestVersion` and only suppresses on an exact match.

### 5. (Bonus) Test viewport has (practically) no sliver cache extent
- **What it suggested:** `expect(find.text('All products'), findsOneWidget)` on
  the closed-store home; when that failed, drag −1200 px and retry.
- **Why it was wrong:** Content above it (ribbon + banner + rail + 200 px deals
  carousel) pushed the header just past the 600 px test viewport, and the −1200
  drag overshot so the header was *above* the window. Widget trees beyond the
  viewport (+0 cache extent in tests) are simply not built, so `find.text`
  legitimately finds nothing.
- **How I noticed:** A probe dumping `RenderViewport` slivers showed the
  all-products slivers attached with `paintExtent 0`.
- **What I did instead:** Assert on in-viewport chrome (search field, category
  rail) for the "browsable" criterion; the products grid itself is covered by
  dedicated paginated-catalog tests.

## What I would NOT trust an AI with in this codebase, and why

- **Widget-test finders against visual intuition.** Whether a text is actually
  built in the element tree depends on viewport size, cache extent and scroll
  position; only a probe dump of `RenderViewport` children settles it.
- **Async streaming semantics (broadcast vs replay, lazy notifier timing).**
  Plausible-sounding "the controller will catch it on the next rebuild" claims
  are wrong here; every timing assumption needs a test that *proves* the event
  arrives when it must.
- **HTTP failure-path UX.** "Retry a few times" style advice without an explicit
  idempotency policy would create duplicate orders; the retry policy is a
  business decision that has to be encoded in code + tests, not improvised.
