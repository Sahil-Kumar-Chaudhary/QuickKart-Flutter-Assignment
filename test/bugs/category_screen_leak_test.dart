// CategoryScreen subscribes to config updates for the free-delivery banner.
// It must release that listener when the screen is popped.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/core/providers.dart';
import 'package:quickkart/features/app_config/presentation/app_config_controller.dart';
import 'package:quickkart/features/catalog/domain/product.dart';
import 'package:quickkart/features/catalog/presentation/category_screen.dart';
import 'package:quickkart/mock_server/mock_server.dart';

import '../helpers/slow_key_value_store.dart';

void main() {
  testWidgets('category screen detaches config listener on dispose',
      (tester) async {
    final server = MockServer.inMemory();
    final container = ProviderContainer(
      overrides: [
        keyValueStoreProvider.overrideWithValue(SlowKeyValueStore()),
        mockServerProvider.overrideWithValue(server),
      ],
    );
    addTearDown(container.dispose);

    final before = server.configListenerCount;

    // Warm the app-level config listener (AppConfigController keeps a
    // permanent subscription by design since Feature 2) so this test only
    // measures the screen's own listener.
    container.read(appConfigControllerProvider);
    await tester.pumpAndSettle();
    final baseline = server.configListenerCount;
    expect(baseline, before + 1,
        reason: 'the app-level listener must be active');

    Widget buildApp() => UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: CategoryScreen(
              category: Category(
                id: 'dairy',
                name: 'Dairy',
                emoji: '🥛',
              ),
            ),
          ),
        );

    await tester.pumpWidget(buildApp());
    expect(
      server.configListenerCount,
      baseline + 1,
      reason: 'the screen should subscribe while it is visible',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(
      server.configListenerCount,
      baseline,
      reason: 'leaving the screen must cancel the config subscription '
          '(the app-level listener stays)',
    );
  });
}
