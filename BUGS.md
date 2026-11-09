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

<!-- Copy the block above for every bug you find. -->

---

## Suspicious but NOT a bug

<!-- Optional: things you investigated and concluded are correct, and why. -->
