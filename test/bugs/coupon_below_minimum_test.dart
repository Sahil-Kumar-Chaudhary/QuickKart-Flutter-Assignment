// A coupon whose minimum is not met stays in the cart locally (zero
// discount) but the order must be sent *without* the coupon code.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/app_config/domain/app_config.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/cart/domain/cart_pricing.dart';
import 'package:quickkart/features/cart/domain/coupon.dart';
import 'package:quickkart/features/checkout/data/order_api.dart';

import '../helpers/test_harness.dart';

void main() {
  late TestHarness h;

  setUp(() {
    h = TestHarness();
  });

  tearDown(() => h.dispose());

  test('a coupon below the minimum is omitted from the request', () async {
    final chicken = h.server.product('fruits-01');
    final cart = Cart(
      lines: [
        CartLine(
          productId: chicken.id,
          name: chicken.name,
          emoji: '🍌',
          unit: '6 pcs',
          unitPricePaise: chicken.pricePaise,
          quantity: 1,
          maxPerOrder: chicken.maxPerOrder,
        ),
      ],
      coupon: Coupon(
        code: 'FLAT50',
        type: CouponType.flat,
        value: 5000,
        minOrderPaise: 19900,
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 30)),
      ),
    );
    final pricing = CartPricing.compute(cart, AppConfig.defaults());

    final order = await h.read(orderApiProvider).placeOrder(cart, pricing);
    expect(order.totalPaise, pricing.totalPaise);
    expect(order.couponCode, isNull);

    // The same cart above the minimum still sends the coupon.
    final aboveMin = Cart(
      lines: cart.lines,
      coupon: Coupon(
        code: 'FLAT50',
        type: CouponType.flat,
        value: 5000,
        minOrderPaise: 19900,
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 30)),
      ),
    );
    final pricingAbove = CartPricing.compute(aboveMin, AppConfig.defaults());
    final orderAbove =
        await h.read(orderApiProvider).placeOrder(aboveMin, pricingAbove);
    expect(orderAbove.couponCode, isNotNull);
  });
}
