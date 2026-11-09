// Feature 1, part 3: safe checkout.
// * never two orders (double taps, retries, lost responses, post-timeout)
// * every amount the user hasn't seen blocks the order for review
// * store closed => no request
// * honest messages for offline / timeout
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/core/network/api_client.dart';
import 'package:quickkart/core/providers.dart';
import 'package:quickkart/features/cart/application/cart_controller.dart';
import 'package:quickkart/features/cart/application/cart_reconciler.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/cart/domain/coupon.dart';
import 'package:quickkart/features/cart/domain/reconciliation.dart';
import 'package:quickkart/features/app_config/presentation/app_config_controller.dart';
import 'package:quickkart/features/catalog/data/catalog_repository.dart'
    show catalogApiProvider;
import 'package:quickkart/features/cart/data/coupon_api.dart';
import 'package:quickkart/features/checkout/application/checkout_controller.dart';
import 'package:quickkart/mock_server/mock_server.dart';

import '../helpers/test_harness.dart';

Cart _cartWithMilk(TestHarness h, {int quantity = 2, Coupon? coupon}) {
  final eggs = h.server.product('dairy-03'); // Farm Eggs ₹54, max 4
  return Cart(
    lines: [
      CartLine(
        productId: eggs.id,
        name: eggs.name,
        emoji: '🥚',
        unit: '6 pcs',
        unitPricePaise: eggs.pricePaise,
        quantity: quantity,
        maxPerOrder: eggs.maxPerOrder,
      ),
    ],
    coupon: coupon,
  );
}

void main() {
  late TestHarness h;

  setUp(() {
    h = TestHarness();
    h.read(cartControllerProvider.notifier).hydrate(_cartWithMilk(h));
  });

  tearDown(() => h.dispose());

  test('place order sends an Idempotency-Key header', () async {
    final result = await h.read(checkoutControllerProvider.notifier).placeOrder();

    expect(result, isA<CheckoutSuccess>());
    final orderRequests = h.server.requestLog
        .where((r) => r.method == 'POST' && r.path == '/v1/orders')
        .toList();
    expect(orderRequests, hasLength(1));
    expect(
      orderRequests.single.headers.keys
          .any((k) => k.toLowerCase() == 'idempotency-key'),
      isTrue,
    );
  });

  test('double tapping places exactly one order', () async {
    final controller = h.read(checkoutControllerProvider.notifier);
    final results = await Future.wait([
      controller.placeOrder(),
      controller.placeOrder(), // while the first is in flight
    ]);

    expect(h.server.orderCount, 1);
    expect(results.whereType<CheckoutSuccess>().length, 1,
        reason: 'one tap orders, the other must be a no-op');
  });

  test('a lost order response never creates a second order', () async {
    h.server.chaos.loseNextOrderResponses = 1;

    final result = await h.read(checkoutControllerProvider.notifier).placeOrder();

    expect(result, isA<CheckoutSuccess>(),
        reason: 'the retry with the same idempotency key must recover the '
            'lost response');
    expect(h.server.orderCount, 1);
    final orderRequests = h.server.requestLog
        .where((r) => r.method == 'POST' && r.path == '/v1/orders');
    expect(orderRequests.length, 2);
  });

  test('placing again after a timeout does not create a second order',
      () async {
    h.dispose();
    h = TestHarness(overrides: [
      apiClientProvider.overrideWith((ref) => ApiClient(
            ref.watch(mockServerProvider).transport,
            timeout: const Duration(milliseconds: 300),
          )),
    ]);
    h.read(cartControllerProvider.notifier).hydrate(_cartWithMilk(h));
    // Every order POST takes 900 ms: the client times out, but the server
    // still processes the request (the worst case for double orders).
    h.server.chaos.latencyOverride = (r) =>
        r.path == '/v1/orders' ? const Duration(milliseconds: 900) : null;

    final controller = h.read(checkoutControllerProvider.notifier);
    final result = await controller.placeOrder();

    expect(result, isA<CheckoutFailure>());
    expect((result as CheckoutFailure).message, contains('may have been'));
    expect(h.server.orderCount, 0, reason: 'processing may still be pending');

    // Let the server finish processing both timed-out attempts.
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(h.server.orderCount, 1, reason: 'exactly one order reaches the '
        'server even though both attempts timed out');

    // The user taps "Place order" again with the same cart: the same
    // idempotency key must return the original order.
    h.server.chaos.latencyOverride = null;
    final second = await controller.placeOrder();
    expect(second, isA<CheckoutSuccess>());
    expect(h.server.orderCount, 1);
    expect(
      (second as CheckoutSuccess).order.id,
      h.server.orders.single['id'] as String,
    );
  });

  test('store closed blocks checkout without sending a request', () async {
    h.server.publishConfig({'store_open': false});
    await h.read(appConfigControllerProvider.notifier).refresh();

    final result = await h.read(checkoutControllerProvider.notifier).placeOrder();

    expect(result, isA<CheckoutFailure>());
    expect((result as CheckoutFailure).message, contains('closed'));
    expect(
      h.server.requestLog.any((r) => r.path == '/v1/orders'),
      isFalse,
      reason: 'the order request must not be sent at all',
    );
    expect(h.read(cartControllerProvider).isEmpty, isFalse);
  });

  test('an offline checkout keeps the cart and is honest', () async {
    h.server.chaos.offline = true;

    final result = await h.read(checkoutControllerProvider.notifier).placeOrder();

    expect(result, isA<CheckoutFailure>());
    expect(h.server.orderCount, 0);
    expect(h.read(cartControllerProvider).isEmpty, isFalse,
        reason: 'the cart must survive a failed checkout');
  });

  test('a price increase is applied to the cart and blocks the order',
      () async {
    final eggs = h.server.product('dairy-03');
    h.server.setPrice('dairy-03', eggs.pricePaise + 500);

    final result = await h.read(checkoutControllerProvider.notifier).placeOrder();

    expect(result, isA<CheckoutNeedsReview>());
    expect(h.server.orderCount, 0);
    final cart = h.read(cartControllerProvider);
    expect(cart.lines.single.unitPricePaise, eggs.pricePaise + 500);
  });

  test('out of stock items are removed and block the order', () async {
    h.server.setStock('dairy-03', 0);

    final result = await h.read(checkoutControllerProvider.notifier).placeOrder();

    expect(result, isA<CheckoutNeedsReview>());
    expect(h.server.orderCount, 0);
    expect(h.read(cartControllerProvider).isEmpty, isTrue);
  });

  test('an expired coupon blocks the order for review', () async {
    h.server.expireCoupon('FLAT50');
    // 6 × ₹54 = ₹324 ≥ the ₹299 minimum, so the coupon was earning a
    // discount before it expired.
    h.read(cartControllerProvider.notifier).hydrate(_cartWithMilk(
      h,
      quantity: 6,
      coupon: Coupon(
        code: 'FLAT50',
        type: CouponType.flat,
        value: 5000,
        minOrderPaise: 29900,
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 30)),
      ),
    ));

    final result = await h.read(checkoutControllerProvider.notifier).placeOrder();

    expect(result, isA<CheckoutNeedsReview>());
    expect(h.server.orderCount, 0);
    expect(h.read(cartControllerProvider).coupon, isNull,
        reason: 'the expired coupon must be removed from the reconciled cart');
  });

  test('after reviewing, the user can place the order', () async {
    final eggs = h.server.product('dairy-03');
    h.server.setPrice('dairy-03', eggs.pricePaise + 500);

    final controller = h.read(checkoutControllerProvider.notifier);
    final first = await controller.placeOrder();
    expect(first, isA<CheckoutNeedsReview>());

    final second = await controller.placeOrder();
    expect(second, isA<CheckoutSuccess>());
    expect(h.server.orderCount, 1);
    expect((second as CheckoutSuccess).order.items.single.unitPricePaise,
        eggs.pricePaise + 500);
  });

  test('a price change racing after reconciliation still blocks the order',
      () async {
    // Reconciler that hikes the server price after its snapshot: emulates
    // the world changing between reconcile and POST.
    final eggs = h.server.product('dairy-03');
    final racingId = eggs.id;
    final oldPrice = eggs.pricePaise;
    h.dispose();
    h = TestHarness(overrides: [
      cartReconcilerProvider.overrideWith((ref) => _RacingReconciler(
            catalogApi: ref.watch(catalogApiProvider),
            couponApi: ref.watch(couponApiProvider),
            server: ref.watch(mockServerProvider),
            productId: racingId,
            oldPrice: oldPrice,
          )),
    ]);
    h.read(cartControllerProvider.notifier).hydrate(_cartWithMilk(h));
    final controller = h.read(checkoutControllerProvider.notifier);

    final result = await controller.placeOrder();

    expect(racingHiked, isTrue);
    expect(result, isA<CheckoutNeedsReview>());
    expect(h.server.orderCount, 0);
    expect(h.read(cartControllerProvider).lines.single.unitPricePaise,
        oldPrice + 500);
  });
}

bool racingHiked = false;

/// Wraps the real reconciler and, once, changes the server price after the
/// snapshot was taken (simulating a mid-flight change).
class _RacingReconciler extends CartReconciler {
  _RacingReconciler({
    required super.catalogApi,
    required super.couponApi,
    required this.server,
    required this.productId,
    required this.oldPrice,
  });

  final MockServer server;
  final String productId;
  final int oldPrice;

  @override
  Future<ReconciliationResult> reconcile(Cart cart) async {
    final result = await super.reconcile(cart);
    if (!racingHiked) {
      racingHiked = true;
      server.setPrice(productId, oldPrice + 500);
    }
    return result;
  }
}
