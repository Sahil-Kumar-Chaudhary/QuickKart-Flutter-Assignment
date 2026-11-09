// Free delivery threshold is inclusive on the server: subtotal >= threshold
// is free. At exactly ₹199 the app must match that.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/app_config/domain/app_config.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/cart/domain/cart_pricing.dart';

void main() {
  test('a cart of exactly ₹199 gets free delivery', () {
    final cart = Cart(lines: [
      const CartLine(
        productId: 'p1',
        name: 'Item',
        emoji: '🛒',
        unit: '1 pc',
        unitPricePaise: 9900,
        quantity: 1,
        maxPerOrder: 10,
      ),
      const CartLine(
        productId: 'p2',
        name: 'Pricy',
        emoji: '💎',
        unit: '1 pc',
        unitPricePaise: 10000,
        quantity: 1,
        maxPerOrder: 10,
      ),
    ]);

    final pricing = CartPricing.compute(cart, AppConfig.defaults());

    expect(pricing.subtotalPaise, 19900);
    expect(pricing.deliveryFeePaise, 0, reason: 'server uses >= threshold');
    expect(pricing.amountForFreeDeliveryPaise, 0);
    expect(pricing.totalPaise, 19900);
  });
}
