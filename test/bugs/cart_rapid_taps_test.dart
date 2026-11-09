// Rapid taps on the cart must all land: an in-flight tap must read the cart
// after the previous tap's state change, not the pre-tap snapshot.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/cart/application/cart_controller.dart';
import 'package:quickkart/features/catalog/domain/product.dart';

import '../helpers/slow_key_value_store.dart';
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

void main() {
  late TestHarness h;

  setUp(() {
    h = TestHarness(store: SlowKeyValueStore());
  });

  tearDown(() => h.dispose());

  test('five rapid taps add four products the app remembers', () async {
    final notifier = h.read(cartControllerProvider.notifier);
    final taps = [for (var i = 0; i < 5; i++) notifier.add(_milk())];
    await Future.wait(taps);

    expect(
      h.read(cartControllerProvider).quantityOf('dairy-00'),
      5,
      reason: 'no rapid tap may be dropped by an in-flight save',
    );
  });

  test('two rapid decrements remove the quantity down to zero', () async {
    final notifier = h.read(cartControllerProvider.notifier);
    await notifier.add(_milk());
    await notifier.add(_milk());

    final taps = [
      notifier.decrement('dairy-00'),
      notifier.decrement('dairy-00'),
    ];
    await Future.wait(taps);

    final cart = h.read(cartControllerProvider);
    expect(
      cart.lineFor('dairy-00'),
      isNull,
      reason: 'the second decrement must see the first decrement result',
    );
  });
}
