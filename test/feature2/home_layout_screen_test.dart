// Feature 2, part 7: the server-driven home screen.
// The home layout is driven by `home_sections` (order preserved, unknown
// ids ignored, bad values fall back) and `home_banner`. A config change
// re-orders the live screen without a restart, and bad config never
// breaks the home screen.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/core/providers.dart';
import 'package:quickkart/core/storage/key_value_store.dart';
import 'package:quickkart/features/app_config/domain/app_config.dart';
import 'package:quickkart/features/app_config/presentation/app_config_controller.dart';
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

Future<void> _pump(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: HomeScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the seeded layout renders banner, rail, deals and products',
      (tester) async {
    final server = MockServer.inMemory(); // seeds home_sections+banner
    final container = _container(server);
    addTearDown(container.dispose);

    await _pump(tester, container);

    expect(find.text('Diwali Dhamaka'), findsOneWidget,
        reason: 'the banner comes from home_banner config');
    expect(find.text('All products'), findsOneWidget);
    expect(find.text('Deals'), findsOneWidget);
    expect(tester.getRect(find.text('Deals')).top,
        greaterThan(tester.getRect(find.text('Diwali Dhamaka')).bottom),
        reason: 'banner is rendered above deals in the configured order');
  });

  testWidgets('config order is respected (deals above banner above products)',
      (tester) async {
    final server = MockServer.inMemory();
    server.publishConfig(
        {'home_sections': '["deals","banner","all_products"]'});
    final container = _container(server);
    addTearDown(container.dispose);

    await _pump(tester, container);

    final dealsTop = tester.getRect(find.text('Deals')).top;
    final bannerTop = tester.getRect(find.text('Diwali Dhamaka')).top;
    final productsTop = tester.getRect(find.text('All products')).top;
    expect(dealsTop, lessThan(bannerTop));
    expect(bannerTop, lessThan(productsTop));
  });

  testWidgets('unknown section ids are ignored', (tester) async {
    final server = MockServer.inMemory();
    server.publishConfig({'home_sections': '["mystery","categories"]'});
    final container = _container(server);
    addTearDown(container.dispose);

    await _pump(tester, container);

    expect(find.text('Diwali Dhamaka'), findsNothing);
    expect(find.text('All products'), findsNothing,
        reason: 'all_products was not configured');
    // Browsing still works: one configured section rendered.
    expect(find.byIcon(Icons.search), findsOneWidget);
  });

  testWidgets('a blank or broken layout falls back to the default', (tester)
      async {
    final server = MockServer.inMemory();
    server.publishConfig({'home_sections': 'not json'});
    final container = _container(server);
    addTearDown(container.dispose);

    await _pump(tester, container);

    // Default: categories + all products (no banner, no deals).
    expect(find.text('All products'), findsOneWidget);
    expect(find.text('Diwali Dhamaka'), findsNothing);
    expect(find.text('Deals'), findsNothing);
  });

  testWidgets('a broken banner never breaks the home screen', (tester) async {
    final server = MockServer.inMemory();
    server.publishConfig({'home_banner': '{oops'});
    final container = _container(server);
    addTearDown(container.dispose);

    await _pump(tester, container);

    expect(find.text('Diwali Dhamaka'), findsNothing,
        reason: 'malformed banner is skipped, not rendered broken');
    expect(find.text('All products'), findsOneWidget);
  });

  testWidgets('a layout publish reorders the live home screen',
      (tester) async {
    final server = MockServer.inMemory();
    final container = _container(server);
    addTearDown(container.dispose);

    await _pump(tester, container);
    expect(find.text('Diwali Dhamaka'), findsOneWidget);

    // Marketing turns the home into a pure banner push for a flash sale.
    server.publishConfig({'home_sections': '["banner"]'});
    await tester.pumpAndSettle();

    expect(find.text('Diwali Dhamaka'), findsOneWidget);
    expect(find.text('All products'), findsNothing,
        reason: 'sections re-order/order-out live without a restart');
  });
}
