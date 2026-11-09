// QK-101: every cart mutation must survive an app restart.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/cart/application/cart_controller.dart';
import 'package:quickkart/features/cart/data/cart_storage.dart';
import 'package:quickkart/features/cart/domain/coupon.dart';
import 'package:quickkart/features/catalog/domain/product.dart';

import '../helpers/test_harness.dart';

Product _milk() => const Product(
      id: 'dairy-00',
      name: 'Toned Milk',
      categoryId: 'dairy',
      emoji: '🥛',
      unit: '500 ml',
      pricePaise: 2900,
      mrpPaise: 2900,
      stock: 120,
      maxPerOrder: 6,
    );

Product _chips() => const Product(
      id: 'snacks-00',
      name: 'Classic Salted Chips',
      categoryId: 'snacks',
      emoji: '🥔',
      unit: '52 g',
      pricePaise: 2000,
      mrpPaise: 2000,
      stock: 100,
      maxPerOrder: 10,
    );

Coupon _coupon() => Coupon(
      code: 'FLAT50',
      type: CouponType.flat,
      value: 5000,
      minOrderPaise: 29900,
      expiresAt: DateTime.now().add(const Duration(days: 1)),
    );

Future<TestHarness> seededHarness() async {
  final h = TestHarness();
  addTearDown(h.dispose);
  final notifier = h.read(cartControllerProvider.notifier);
  await notifier.add(_milk());
  await notifier.add(_milk());
  await notifier.add(_chips());
  await notifier.applyCoupon(_coupon());
  return h;
}

Future<TestHarness> mutateAndRestart(
  Future<void> Function(CartController notifier) mutation,
) async {
  final beforeStop = await seededHarness();
  await mutation(beforeStop.read(cartControllerProvider.notifier));

  // Same storage + server, completely fresh in-memory app state.
  final afterRestart = beforeStop.restart();
  beforeStop.dispose();

  final cart = await afterRestart.read(cartStorageProvider).load();
  afterRestart.read(cartControllerProvider.notifier).hydrate(cart);
  return afterRestart;
}

void main() {
  test('decrement survives an app restart (QK-101)', () async {
    final h = await mutateAndRestart((notifier) async {
      await notifier.decrement('dairy-00');
    });

    final cart = h.read(cartControllerProvider);
    expect(cart.quantityOf('dairy-00'), 1);
    expect(cart.lineFor('snacks-00'), isNotNull);
  });

  test('line removal survives an app restart (QK-101)', () async {
    final h = await mutateAndRestart((notifier) async {
      await notifier.remove('snacks-00');
    });

    final cart = h.read(cartControllerProvider);
    expect(cart.lineFor('snacks-00'), isNull);
    expect(cart.quantityOf('dairy-00'), 2);
  });

  test('coupon removal survives an app restart (QK-101)', () async {
    final h = await mutateAndRestart((notifier) async {
      await notifier.removeCoupon();
    });

    expect(h.read(cartControllerProvider).coupon, isNull);
  });
}
