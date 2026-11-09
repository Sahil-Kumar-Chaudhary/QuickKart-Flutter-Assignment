// Feature 1, part 2: reconciliation is surfaced to the user.
// Opening the cart after the world changed must show exactly what changed
// (BUSINESS_RULES.md 5: price drops silently ok; the rest for review).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/core/providers.dart';
import 'package:quickkart/core/storage/key_value_store.dart';
import 'package:quickkart/core/utils/money.dart';
import 'package:quickkart/features/cart/application/cart_controller.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/cart/domain/cart_pricing.dart';
import 'package:quickkart/features/cart/presentation/cart_screen.dart';
import 'package:quickkart/mock_server/mock_server.dart';

ProviderContainer makeContainer(MockServer server) => ProviderContainer(
      overrides: [
        keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        mockServerProvider.overrideWithValue(server),
      ],
    );

Future<void> pumpCartScreen(
  WidgetTester tester,
  ProviderContainer container,
) =>
    tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: CartScreen()),
    ));

Future<void> seedCart(ProviderContainer container, MockServer server) async {
  final product = server.product('dairy-03'); // Farm Eggs ₹54
  await container.read(cartControllerProvider.notifier).replace(
        Cart(
          lines: [
            CartLine(
              productId: product.id,
              name: product.name,
              emoji: '🥚',
              unit: '6 pcs',
              unitPricePaise: product.pricePaise,
              quantity: 2,
              maxPerOrder: product.maxPerOrder,
            ),
          ],
        ),
      );
}

void main() {
  testWidgets('opening the cart after a price hike shows the change',
      (tester) async {
    final server = MockServer.inMemory();
    server.setPrice('dairy-03', server.product('dairy-03').pricePaise + 500);

    final container = makeContainer(server);
    addTearDown(container.dispose);
    await seedCart(container, server);
    await pumpCartScreen(tester, container);
    await tester.pumpAndSettle();

    // The tile reflects the server price and the change is explicit.
    expect(
      find.text(formatPrice(server.product('dairy-03').pricePaise)),
      findsWidgets,
    );
    expect(
      find.text('Price & availability changed'),
      findsOneWidget,
      reason: 'a reviewable change must be surfaced, not applied silently',
    );
    expect(find.textContaining('old'), findsWidgets);
  });

  testWidgets('the review banner disappears when acknowledged',
      (tester) async {
    final server = MockServer.inMemory();
    server.setPrice('dairy-03', server.product('dairy-03').pricePaise + 500);

    final container = makeContainer(server);
    addTearDown(container.dispose);
    await seedCart(container, server);
    await pumpCartScreen(tester, container);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();

    expect(find.text('Price & availability changed'), findsNothing);
  });

  testWidgets('a price drop is applied silently without a banner',
      (tester) async {
    final server = MockServer.inMemory();
    server.setPrice('dairy-03', server.product('dairy-03').pricePaise - 500);

    final container = makeContainer(server);
    addTearDown(container.dispose);
    await seedCart(container, server);
    await pumpCartScreen(tester, container);
    await tester.pumpAndSettle();

    expect(find.text('Price & availability changed'), findsNothing);
    expect(
      find.text(formatPrice(server.product('dairy-03').pricePaise)),
      findsWidgets,
      reason: 'the lower price must be applied to the cart silently',
    );
  });
}

String formatPrice(int paise) => formatMoney(paise);
