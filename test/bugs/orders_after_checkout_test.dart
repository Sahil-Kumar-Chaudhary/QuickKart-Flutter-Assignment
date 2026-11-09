// QK-102/checkout follow-up: My Orders must refresh after a successful
// checkout, not rely on a long-lived provider's first Future.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/cart/application/cart_controller.dart';
import 'package:quickkart/features/checkout/application/checkout_controller.dart';
import 'package:quickkart/features/orders/data/order_tracking_repository.dart';
import 'package:quickkart/features/catalog/domain/product.dart';

import '../helpers/test_harness.dart';

Product _banana(int serverPricePaise) => Product(
      id: 'fruits-01',
      name: 'Robusta Banana',
      categoryId: 'fruits',
      emoji: '🍌',
      unit: '6 pcs',
      pricePaise: serverPricePaise,
      mrpPaise: serverPricePaise + 1000,
      stock: 60,
      maxPerOrder: 6,
    );

void main() {
  late TestHarness h;

  setUp(() {
    h = TestHarness();
  });

  tearDown(() => h.dispose());

  test('ordersProvider refreshes after a successful checkout', () async {
    final before = await h.read(ordersProvider.future);
    expect(before, isEmpty, reason: 'the test starts without server orders');

    final serverPrice = h.server.product('fruits-01').pricePaise;
    await h.read(cartControllerProvider.notifier).add(_banana(serverPrice));

    final result =
        await h.read(checkoutControllerProvider.notifier).placeOrder();
    expect(result, isA<CheckoutSuccess>());

    final after = await h.read(ordersProvider.future);
    expect(
      after.length,
      before.length + 1,
      reason: 'successful checkout must invalidate the orders provider',
    );
  });
}
