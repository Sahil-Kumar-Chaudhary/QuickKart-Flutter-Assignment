// QK-102: stale GET responses must never be returned after server data
// changes. This applies to catalog, orders and remote config alike.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/app_config/data/config_repository.dart';
import 'package:quickkart/features/app_config/domain/app_config.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/cart/domain/cart_pricing.dart';
import 'package:quickkart/features/catalog/data/catalog_repository.dart';
import 'package:quickkart/features/orders/data/order_tracking_repository.dart';

import '../helpers/test_harness.dart';

void main() {
  late TestHarness h;

  setUp(() {
    h = TestHarness();
  });

  tearDown(() => h.dispose());

  test('a changed price is returned by a fresh catalog GET (QK-102)', () async {
    final repository = h.read(catalogRepositoryProvider);
    final product = h.server.product('fruits-03');

    final first = await repository.getPage(categoryId: 'fruits');
    final stalePrice =
        first.items.singleWhere((p) => p.id == product.id).pricePaise;
    h.server.setPrice(product.id, stalePrice + 500);

    final second = await repository.getPage(categoryId: 'fruits');
    final shownPrice =
        second.items.singleWhere((p) => p.id == product.id).pricePaise;

    expect(
      shownPrice,
      h.server.product(product.id).pricePaise,
      reason: 'pull-to-refresh must not return the cached price',
    );
  });

  test('orders fetched after placing are not stale (QK-102)', () async {
    final repository = h.read(orderTrackingRepositoryProvider);
    await repository.getOrders();

    final banana = h.server.product('fruits-01');
    final cart = Cart(lines: [
      CartLine(
        productId: banana.id,
        name: banana.name,
        emoji: '🍌',
        unit: '6 pcs',
        unitPricePaise: banana.pricePaise,
        quantity: 1,
        maxPerOrder: banana.maxPerOrder,
      ),
    ]);

    await repository.orderApi.placeOrder(
      cart,
      CartPricing.compute(cart, AppConfig.defaults()),
    );

    final orders = await repository.getOrders();
    expect(
      orders,
      anyElement(
        (o) => o.items.any(
          (item) =>
              item.productId == banana.id && item.unitPricePaise ==
              banana.pricePaise,
        ),
      ),
      reason: 'the order placed a moment ago must be visible immediately',
    );
  });

  test('published config is returned by a fresh config GET (QK-102)', () async {
    final repository = h.read(configRepositoryProvider);
    await repository.load();

    h.server.publishConfig({'store_open': false});
    final config = await repository.load();

    expect(config.storeOpen, isFalse);
  });
}
