// Feature 2, part 6: the store kill switch.
// store_open = false must:
// * show the store_closed_message prominently (home AND cart)
// * still let users browse everything
// * make checkout impossible - the place-order button is dead on the cart
//   screen, closing works live while the cart screen is open.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/core/providers.dart';
import 'package:quickkart/core/storage/key_value_store.dart';
import 'package:quickkart/features/app_config/domain/app_config.dart';
import 'package:quickkart/features/app_config/presentation/app_config_controller.dart';
import 'package:quickkart/features/cart/application/cart_controller.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/cart/presentation/cart_screen.dart';
import 'package:quickkart/features/catalog/presentation/home_screen.dart';
import 'package:quickkart/mock_server/mock_server.dart';

ProviderContainer _container(MockServer server, {KeyValueStore? store}) {
  final container = ProviderContainer(overrides: [
    keyValueStoreProvider.overrideWithValue(store ?? InMemoryKeyValueStore()),
    mockServerProvider.overrideWithValue(server),
  ]);
  // main.dart hydrates before the first frame; mirror that here.
  container
      .read(appConfigControllerProvider.notifier)
      .hydrate(AppConfig.fromValues(server.configValues));
  return container;
}

Future<void> _seedCartEggs(ProviderContainer container, MockServer server)
    async {
  final eggs = server.product('dairy-03');
  await container.read(cartControllerProvider.notifier).replace(
        Cart(
          lines: [
            CartLine(
              productId: eggs.id,
              name: eggs.name,
              emoji: '🥚',
              unit: '6 pcs',
              unitPricePaise: eggs.pricePaise,
              quantity: 1,
              maxPerOrder: eggs.maxPerOrder,
            ),
          ],
        ),
      );
}

void main() {
  testWidgets('home shows the closed message but stays browsable',
      (tester) async {
    final server = MockServer.inMemory();
    server.publishConfig({'store_open': false});
    final container = _container(server);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: HomeScreen()),
    ));
    await tester.pumpAndSettle();

    expect(
      find.text('We are closed for a short break. Back in 30 minutes!'),
      findsOneWidget,
      reason: 'the configured message is shown, not a generic error',
    );
    // Browsing still works: the category rail and products render.
    expect(find.text('All products'), findsOneWidget);
    expect(find.byIcon(Icons.bug_report_outlined), findsOneWidget);
  });

  testWidgets('home shows nothing special while the store is open',
      (tester) async {
    final server = MockServer.inMemory();
    final container = _container(server);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: HomeScreen()),
    ));
    await tester.pumpAndSettle();

    expect(
      find.byIcon(Icons.storefront),
      findsNothing,
      reason: 'no closed-store chrome on a healthy home screen',
    );
  });

  testWidgets('opening the cart while closed disables checkout',
      (tester) async {
    final server = MockServer.inMemory();
    server.publishConfig({'store_open': false});
    final container = _container(server);
    addTearDown(container.dispose);
    await _seedCartEggs(container, server);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: CartScreen()),
    ));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(find.ancestor(
      of: find.textContaining('Place order'),
      matching: find.byType(FilledButton),
    ));
    expect(button.onPressed, isNull,
        reason: 'checkout must be impossible while closed');
    expect(
      find.text('We are closed for a short break. Back in 30 minutes!'),
      findsOneWidget,
    );
  });

  testWidgets('the store can close while the cart screen is open',
      (tester) async {
    final server = MockServer.inMemory();
    final container = _container(server);
    addTearDown(container.dispose);
    await _seedCartEggs(container, server);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: CartScreen()),
    ));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(find.ancestor(
      of: find.textContaining('Place order'),
      matching: find.byType(FilledButton),
    ));
    expect(button.onPressed, isNotNull, reason: 'precondition: open store');

    // Surprise rain spike: ops closes the store live.
    server.publishConfig({'store_open': false,
        'store_closed_message': 'Closed due to heavy rain'});
    await tester.pumpAndSettle();

    final closedButton = tester.widget<FilledButton>(find.ancestor(
      of: find.textContaining('Place order'),
      matching: find.byType(FilledButton),
    ));
    expect(closedButton.onPressed, isNull,
        reason: 'a mid-session close must be respected immediately');
    expect(find.text('Closed due to heavy rain'), findsOneWidget);
  });

  testWidgets('reopening the store re-enables checkout live', (tester) async {
    final server = MockServer.inMemory();
    server.publishConfig({'store_open': false});
    final container = _container(server);
    addTearDown(container.dispose);
    await _seedCartEggs(container, server);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: CartScreen()),
    ));
    await tester.pumpAndSettle();

    server.publishConfig({'store_open': true});
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(find.ancestor(
      of: find.textContaining('Place order'),
      matching: find.byType(FilledButton),
    ));
    expect(button.onPressed, isNotNull);
    expect(
      find.text('We are closed for a short break. Back in 30 minutes!'),
      findsNothing,
    );
  });
}
