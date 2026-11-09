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

## BUG-2: <short title> (QK-102)

- **Symptom:**
- **Steps to reproduce:**
- **Root cause:**
- **Fix:**
- **Test:**
- **Commits:**

---

## BUG-3: …

<!-- Copy the block above for every bug you find. -->

---

## Suspicious but NOT a bug

<!-- Optional: things you investigated and concluded are correct, and why. -->
