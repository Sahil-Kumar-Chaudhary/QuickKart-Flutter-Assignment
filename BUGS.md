# Bugs found & fixed

> One section per bug. Order doesn't matter. Keep each one short and precise.
> Commit the reproducing test **before** the fix.

---

## BUG-1: Cart changes disappear after restarting (QK-101)

- **Symptom:** A decrement, line removal or coupon removal comes back after the app is killed and reopened. The badge on the home screen shows the old cart total.
- **Steps to reproduce:**
  1. Put milk and chips in the cart and apply a coupon.
  2. Reduce milk, delete chips and remove the coupon.
  3. Fully restart the app (not hot reload).
- **Root cause:** `CartController.decrement()`, `remove()` and `removeCoupon()` changed only the in-memory `state`. They never called `CartStorage.save()`, so `cart.v1` still held the pre-mutation cart when the app restarted.
- **Fix:** Compute the new immutable cart, call `_storage.save(updated)`, and only then publish it to Riverpod state. This keeps the existing public methods and architecture unchanged.
- **Test:** `test/bugs/cart_persistence_test.dart` → `decrement survives an app restart (QK-101)`, `line removal survives an app restart (QK-101)`, `coupon removal survives an app restart (QK-101)`
- **Commits:** test `9d1c0b8` → fix `ad9897f`

---

## BUG-2: Prices, orders and config stay stale until restart (QK-102)

- **Symptom:** Pull-to-refresh keeps an old price until the app is killed and reopened. Orders placed a moment ago are not visible. Published config can also remain stale.
- **Steps to reproduce:**
  1. Load a catalog page / order list / config.
  2. Change the server price, place an order or publish config.
  3. Repeat the GET.
- **Root cause:** `ApiClient` stored every successful `GET` response in an in-process cache and served it for 10 minutes before reaching the transport. Catalog, order and config reads all shared this stale cache.
- **Fix:** Remove `ApiClient`'s response cache. Freshness is now owned by each repository. The catalog still has its explicit offline cache; no hidden network cache can override fresh reads.
- **Test:** `test/bugs/stale_get_cache_test.dart` → `a changed price is returned by a fresh catalog GET (QK-102)`, `orders fetched after placing are not stale (QK-102)`, `published config is returned by a fresh config GET (QK-102)`
- **Commits:** test `9ab53e7` → fix `4783ee3`

---

## BUG-3: My Orders does not show a just-placed order

- **Symptom:** After checkout, the order list can still show the previous orders. It only catches up later.
- **Steps to reproduce:**
  1. Open My Orders.
  2. Place an order.
  3. Read `ordersProvider` again.
- **Root cause:** `ordersProvider` was a long-lived `FutureProvider` and was not invalidated by checkout, so its first Future could remain in memory.
- **Fix:** Make `ordersProvider` autoDispose and invalidate it after a successful checkout.
- **Test:** `test/bugs/orders_after_checkout_test.dart` → `ordersProvider refreshes after a successful checkout`
- **Commits:** test `93bff2b` → fix `7fc1906`

---

## BUG-4: ₹19.99 is stored as 1998 paise

- **Symptom:** Products with paise can charge/display a different amount than the server expects, often as `PRICE_CHANGED` at checkout.
- **Steps to reproduce:**
  1. Load the tomato product (`19.99`).
  2. Convert it to paise.
  3. Compare with the server price.
- **Root cause:** `rupeesToPaise()` used `.toInt()`, truncating `19.99 * 100 = 1998.999...` to `1998`.
- **Fix:** Round the converted value to the nearest whole paisa.
- **Test:** `test/bugs/money_precision_test.dart` → `19.99 becomes 1999 paise`, `79.99 becomes 7999 paise`
- **Commits:** test `4128187` → fix `050bf3e`

---

## BUG-5: Displayed price drops the paise

- **Symptom:** A cart line priced at ₹19.99 renders as ₹19 while totals are charged in paise.
- **Steps to reproduce:**
  1. Add any product priced at 1999 paise.
  2. Read its formatted price.
- **Root cause:** `formatMoney()` did `paise ~/ 100` and never rendered the remainder.
- **Fix:** Render the paise remainder when it is non-zero, zero-padded to two digits, and omit `.00` for whole rupees.
- **Test:** `test/bugs/money_display_test.dart` → `1999 paise is shown as ₹19.99`, `1950 paise is shown as ₹19.50`, `whole rupees do not show .00`
- **Commits:** test `bffe23f` → fix `6099d42`

---

## BUG-6: Cart at exactly ₹199 still pays the delivery fee

- **Symptom:** A subtotal of exactly ₹199 shows a delivery fee locally; the same order is free on the server. `amountForFreeDelivery` also shows ₹0 instead of the true gap.
- **Steps to reproduce:**
  1. Build a cart whose subtotal is 19900 paise.
  2. Run `CartPricing.compute` with default config.
- **Root cause:** `CartPricing.compute` used `payable > threshold` while BUSINESS_RULES and the server use `payable >= threshold`.
- **Fix:** Make the free-delivery comparison inclusive (payable >= threshold ⇒ fee 0). Then the existing "large cart" test still passes.
- **Test:** `test/bugs/free_delivery_threshold_test.dart` → `a cart of exactly ₹199 gets free delivery`
- **Commits:** test `21f06e2` → fix `c33d6d9`

---

## BUG-7: Legacy products crash the catalog while loading

- **Symptom:** `dairy-00`, `dairy-02` and `snacks-09` (`mrp: null`, string `stock`) throw a `TypeError` before any product screen renders, and the screen is stuck loading.
- **Steps to reproduce:**
  1. Open the app with the legacy products enabled (Dev tools → product flags do not matter, they are always in the deal mix).
  2. Receive a legacy product from the API.
- **Root cause:** `ProductDto.fromJson` cast `mrp` to a non-nullable `num` and `stock` directly to `int`; legacy responses violate both, throwing `Null is not a subtype of num` / `String is not a subtype of int` under the catalog controller's catch-all.
- **Fix:** Fall back to the price when `mrp` is null (no fake discount) and parse `stock` via `int.tryParse` with a 0 fallback.
- **Test:** `test/bugs/product_dto_legacy_test.dart` → `a legacy product with mrp null and a string stock is parsed`, `a legacy product with no MRP shows no fake discount`, `current-style products still parse`
- **Commits:** test `7e5c65b` → fix `24e1ccd`

---

## BUG-8: A cached fruit page is served as the snacks page offline

- **Symptom:** After the network drops on one category, opening a different category returns the previously cached page as if it were that category's products.
- **Steps to reproduce:**
  1. Open the fruits category while online.
  2. Turn off the network.
  3. Open the snacks category while offline.
- **Root cause:** `CatalogRepository.getPage()` built the cache key as `page.${cursor ?? 'first'}`, ignoring `categoryId` and `limit`, so every first page shared one key.
- **Fix:** Compose the cache key from `categoryId`, cursor and `limit`.
- **Test:** `test/bugs/catalog_cache_key_test.dart` → `offline pages are keyed by category, not cursor alone (A8)`
- **Commits:** test `260ad79` → fix `58e5640`

---

## BUG-9: Rapid cart taps lose updates

- **Symptom:** Tapping `+` five times in a row sometimes results in a cart of 1–2 items instead of 5. Tapping `-` twice on one item can leave qty 1 in the cart.
- **Steps to reproduce:**
  1. Add a product to the cart.
  2. Tap `+` quickly several times.
  3. Reopen the cart or restart the app.
- **Root cause:** `add()`/`increment()` computed a new cart from `state`, then awaited `_storage.save()` before assigning `state`. A second tap could run concurrently on the stale in-memory state and later overwrite the first result.
- **Fix:** All cart mutations are dispatched through a single serialized write chain (`_commit`). Each operation sees the committed result of the previous one.
- **Test:** `test/bugs/cart_rapid_taps_test.dart` → `five rapid taps add four products the app remembers`, `two rapid decrements remove the quantity down to zero`
- **Commits:** test `93c5352` → fix `c41c407`

---

## BUG-10: Double-tapping load-more duplicates a page

- **Symptom:** Scrolling near the end can trigger two concurrent `loadMore()` calls that append the same page twice, showing duplicated rows.
- **Steps to reproduce:**
  1. Open a category with a next page.
  2. Fire load-more twice (or tap fast).
- **Root cause:** `loadMore()` only checked `hasMore` and never observe `isLoadingMore` nor `nextCursor` stability. It also did not remember the last requested cursor.
- **Fix:** Skip load-more while first page/refresh/loadMore is in flight, track the last requested cursor, and drop a second call with the same cursor; reset that cursor on error so retry is possible.
- **Test:** `test/bugs/load_more_guard_test.dart` → `two simultaneous loadMore calls fetch the page once`
- **Commits:** test `82db5d9` → fix `fce842e`

---

## BUG-11: Search results and query go stale

- **Symptom:** Two quick search keystrokes end with the older request overwriting the newer one. After leaving Search and returning, the previous query/results are still displayed.
- **Steps to reproduce:**
  1. Open Search, type `milk`, then quickly change the text to `chi`.
  2. Read the controller state and reopen the screen.
- **Root cause:** `searchControllerProvider` was a long-lived `Notifier` and each `search()` wrote the newest response regardless of the current query.
- **Fix:** Track request tokens in the controller, make the provider autoDispose, and have the screen reset the state when it unmounts.
- **Test:** `test/bugs/search_reset_race_test.dart` → `a slow earlier search never overwrites a newer one`, `search state is fresh after reopening the screen`
- **Commits:** test `28d1347` → fix `dc86d8f`

---

## BUG-12: Category screen leaks a config listener

- **Symptom:** Leaving CategoryScreen leaves a live subscription on the config stream; repeated open/close keeps accumulating a listener and can cause `setState` after dispose.
- **Steps to reproduce:**
  1. Open CategoryScreen.
  2. Leave it.
  3. Run an in-app Dev Tools "config listener count" (or refresh config).
- **Root cause:** `_CategoryScreenState.initState().listen()` call was never cancelled in `dispose()`. Since `_freeDeliveryThresholdPaise` uses `setState`, a late update may also throw.
- **Fix:** Cancel every `_subscriptions` stream after the widget is disposed and guard `setState` with `mounted`.
- **Test:** `test/bugs/category_screen_leak_test.dart` → `category screen detaches config listener on dispose`
- **Commits:** test `4d8837c` → fix `2421533`

<!-- Copy the block above for every bug you find. -->

---

## Suspicious but NOT a bug

<!-- Optional: things you investigated and concluded are correct, and why. -->
