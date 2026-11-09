// Feature 1, part 1: CartReconciler.reconcile contract (ASSIGNMENT.md).
// The reconciled cart must be exactly what the server would accept right
// now, with every difference reported.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/core/network/api_exceptions.dart';
import 'package:quickkart/features/cart/application/cart_reconciler.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/cart/domain/coupon.dart';
import 'package:quickkart/features/cart/domain/reconciliation.dart';

import '../helpers/test_harness.dart';

CartLine _lineFor(
  TestHarness h,
  String id, {
  int quantity = 2,
  int? pricePaise,
  int? maxPerOrder,
}) {
  final product = h.server.product(id);
  return CartLine(
    productId: product.id,
    name: product.name,
    emoji: '🛒',
    unit: '1 pc',
    unitPricePaise: pricePaise ?? product.pricePaise,
    quantity: quantity,
    maxPerOrder: maxPerOrder ?? product.maxPerOrder,
  );
}

void main() {
  late TestHarness h;

  setUp(() {
    h = TestHarness();
  });

  tearDown(() => h.dispose());

  test('an unchanged cart is returned as-is with no changes', () async {
    final cart = Cart(lines: [_lineFor(h, 'fruits-01')]);

    final result = await h.read(cartReconcilerProvider).reconcile(cart);

    expect(result.cart, cart);
    expect(result.changes, isEmpty);
    expect(result.requiresUserReview, isFalse);
  });

  test('prices are updated to the server price and reported', () async {
    final original = _lineFor(h, 'fruits-01');
    h.server.setPrice('fruits-01', original.unitPricePaise + 2000);

    final result = await h
        .read(cartReconcilerProvider)
        .reconcile(Cart(lines: [original]));

    expect(result.cart.lines.single.unitPricePaise, original.unitPricePaise + 2000);
    expect(result.cart.lines.single.quantity, original.quantity);
    final change = result.changes.single as PriceChanged;
    expect(change.productId, 'fruits-01');
    expect(change.oldPricePaise, original.unitPricePaise);
    expect(change.newPricePaise, original.unitPricePaise + 2000);
    // Price *increases* must be shown to the user (BUSINESS_RULES.md 5).
    expect(change.requiresUserReview, isTrue);
    expect(result.requiresUserReview, isTrue);
  });

  test('price drops are applied silently', () async {
    final original = _lineFor(h, 'fruits-01');
    h.server.setPrice('fruits-01', original.unitPricePaise - 1000);

    final result = await h
        .read(cartReconcilerProvider)
        .reconcile(Cart(lines: [original]));

    expect(result.cart.lines.single.unitPricePaise, original.unitPricePaise - 1000);
    expect(result.changes.single, isA<PriceChanged>());
    expect(result.changes.single.requiresUserReview, isFalse);
    expect(result.requiresUserReview, isFalse);
  });

  test('quantities above stock are reduced and reported', () async {
    final original = _lineFor(h, 'fruits-01', quantity: 5);
    h.server.setStock('fruits-01', 3);

    final result = await h
        .read(cartReconcilerProvider)
        .reconcile(Cart(lines: [original]));

    expect(result.cart.lines.single.quantity, 3);
    final change = result.changes.single as QuantityReduced;
    expect(change.productId, 'fruits-01');
    expect(change.requestedQuantity, 5);
    expect(change.availableQuantity, 3);
    expect(change.requiresUserReview, isTrue);
  });

  test('a per-order limit drop caps the quantity', () async {
    final original = _lineFor(h, 'fruits-01', quantity: 5);
    h.server.setMaxPerOrder('fruits-01', 2);

    final result = await h
        .read(cartReconcilerProvider)
        .reconcile(Cart(lines: [original]));

    expect(result.cart.lines.single.quantity, 2);
    expect(
      result.changes.single,
      isA<QuantityReduced>()
          .having((c) => c.availableQuantity, 'availableQuantity', 2),
    );
  });

  test('a fitting quantity keeps its size but refreshes maxPerOrder',
      () async {
    final original = _lineFor(h, 'fruits-01', quantity: 2);
    h.server.setMaxPerOrder('fruits-01', 4);

    final result = await h
        .read(cartReconcilerProvider)
        .reconcile(Cart(lines: [original]));

    expect(result.cart.lines.single.quantity, 2);
    expect(result.cart.lines.single.maxPerOrder, 4);
    expect(result.changes, isEmpty);
  });

  test('an out-of-stock product is removed and reported', () async {
    final original = _lineFor(h, 'fruits-01');
    h.server.setStock('fruits-01', 0);

    final result = await h
        .read(cartReconcilerProvider)
        .reconcile(Cart(lines: [original]));

    expect(result.cart.isEmpty, isTrue);
    final change = result.changes.single as OutOfStock;
    expect(change.productId, 'fruits-01');
    expect(result.requiresUserReview, isTrue);
  });

  test('a discontinued product is removed and reported', () async {
    final original = _lineFor(h, 'fruits-01');
    h.server.setActive('fruits-01', false);

    final result = await h
        .read(cartReconcilerProvider)
        .reconcile(Cart(lines: [original]));

    expect(result.cart.isEmpty, isTrue);
    final change = result.changes.single as ProductUnavailable;
    expect(change.productId, 'fruits-01');
  });

  test('line order is preserved', () async {
    final lines = [
      _lineFor(h, 'fruits-00', quantity: 1),
      _lineFor(h, 'fruits-02', quantity: 1),
    ];
    h.server.setPrice('fruits-02', h.server.product('fruits-02').pricePaise + 100);

    final result =
        await h.read(cartReconcilerProvider).reconcile(Cart(lines: lines));

    expect(
      result.cart.lines.map((l) => l.productId).toList(),
      const ['fruits-00', 'fruits-02'],
    );
    expect(result.changes, hasLength(1));
  });

  test('a coupon whose rules changed is refreshed from the server', () async {
    final cart = Cart(
      lines: [_lineFor(h, 'fruits-01')],
      coupon: Coupon(
        code: 'SAVE10',
        type: CouponType.percent,
        value: 99, // stale local copy
        minOrderPaise: 1,
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 30)),
      ),
    );

    final result = await h.read(cartReconcilerProvider).reconcile(cart);

    final coupon = result.cart.coupon!;
    expect(coupon.value, 10);
    expect(coupon.maxDiscountPaise, 7500);
    expect(coupon.minOrderPaise, 19900);
    expect(result.changes, isEmpty);
  });

  test('an expired coupon is removed with reason EXPIRED', () async {
    final cart = Cart(
      lines: [_lineFor(h, 'fruits-01')],
      coupon: Coupon(
        code: 'FLAT50',
        type: CouponType.flat,
        value: 5000,
        minOrderPaise: 29900,
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 30)),
      ),
    );
    h.server.expireCoupon('FLAT50');

    final result = await h.read(cartReconcilerProvider).reconcile(cart);

    expect(result.cart.coupon, isNull);
    expect(result.cart.lines, hasLength(1));
    final change = result.changes.single as CouponRemoved;
    expect(change.code, 'FLAT50');
    expect(change.reason, 'EXPIRED');
    expect(change.requiresUserReview, isTrue);
  });

  test('an unknown coupon is removed with reason NOT_FOUND', () async {
    final cart = Cart(
      lines: [_lineFor(h, 'fruits-01')],
      coupon: Coupon(
        code: 'NOPE123',
        type: CouponType.flat,
        value: 1000,
        minOrderPaise: 100,
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 30)),
      ),
    );

    final result = await h.read(cartReconcilerProvider).reconcile(cart);

    expect(result.cart.coupon, isNull);
    final change = result.changes.single as CouponRemoved;
    expect(change.code, 'NOPE123');
    expect(change.reason, 'NOT_FOUND');
  });

  test('a coupon below its minimum stays in the cart', () async {
    // ₹49 < the ₹199 minimum of SAVE10.
    final cart = Cart(
      lines: [_lineFor(h, 'fruits-01', quantity: 1)],
      coupon: Coupon(
        code: 'SAVE10',
        type: CouponType.percent,
        value: 10,
        maxDiscountPaise: 7500,
        minOrderPaise: 19900,
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 30)),
      ),
    );

    final result = await h.read(cartReconcilerProvider).reconcile(cart);

    expect(result.cart.coupon?.code, 'SAVE10');
    expect(result.changes.whereType<CouponRemoved>(), isEmpty);
  });

  test('reconcile throws when the server cannot be reached', () async {
    h.server.chaos.offline = true;

    await expectLater(
      h
          .read(cartReconcilerProvider)
          .reconcile(Cart(lines: [_lineFor(h, 'fruits-01')])),
      throwsA(isA<ApiException>()),
    );
  });

  test('a cart with several issues reconciles every one of them', () async {
    final banana = _lineFor(h, 'fruits-01', quantity: 5);
    h.server.setStock('fruits-01', 3);
    h.server.setPrice('fruits-01', banana.unitPricePaise + 100);
    h.server.setActive('fruits-00', false);

    final result = await h
        .read(cartReconcilerProvider)
        .reconcile(Cart(lines: [_lineFor(h, 'fruits-00'), banana]));

    expect(result.cart.lines, hasLength(1));
    expect(result.cart.lines.single.productId, 'fruits-01');
    expect(result.cart.lines.single.quantity, 3);
    expect(result.cart.lines.single.unitPricePaise, banana.unitPricePaise + 100);
    expect(result.changes, hasLength(3)); // unavailable, price, quantity
  });
}

