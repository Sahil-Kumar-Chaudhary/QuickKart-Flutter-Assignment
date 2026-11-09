// Search must skip late responses and reset when the screen reopens.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/core/providers.dart';
import 'package:quickkart/features/catalog/data/catalog_repository.dart';
import 'package:quickkart/features/search/search_screen.dart';
import 'package:quickkart/features/search/search_controller.dart';
import 'package:quickkart/mock_server/mock_server.dart';

import '../helpers/slow_key_value_store.dart';
import '../helpers/test_harness.dart';

void main() {
  late TestHarness h;

  setUp(() {
    h = TestHarness(store: SlowKeyValueStore());
  });

  tearDown(() => h.dispose());

  test('a slow earlier search never overwrites a newer one', () async {
    h.server.chaos.latencyOverride = (request) {
      final query = request.query['q'] ?? '';
      return query == 'milk' ? const Duration(milliseconds: 400) : null;
    };

    final notifier = h.read(searchControllerProvider.notifier);
    // Simulate a screen listening to the search state, just like the real UI.
    h.container.listen(searchControllerProvider, (_, __) {});
    final expected = await h
        .read(catalogRepositoryProvider)
        .search('chi'); // fast fetch, not delayed by the override.

    final f1 = notifier.search('milk'); // slow
    final f2 = notifier.search('chi'); // fast
    await Future.wait([f1, f2]);

    final state = h.read(searchControllerProvider);
    expect(state.query, 'chi');
    expect(
      state.results.map((p) => p.id).toList(),
      expected.map((p) => p.id).skip(0).toList(),
      reason: 'a stale milk response must not clobber the chi results',
    );
  });

  testWidgets('search state is fresh after reopening the screen', (tester) async {
    final container = ProviderContainer(
      overrides: [
        keyValueStoreProvider.overrideWithValue(SlowKeyValueStore()),
        mockServerProvider.overrideWithValue(MockServer.inMemory()),
      ],
    );
    addTearDown(container.dispose);

    Future<void> open() => tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: SearchScreen()),
          ),
        );

    await open();
    await tester.enterText(find.byType(TextField), 'milk');
    await tester.pumpAndSettle();
    expect(container.read(searchControllerProvider).query, 'milk');

    // Close the screen then reopen it on the same provider container.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await open();

    expect(
      container.read(searchControllerProvider).query,
      isEmpty,
      reason: 'reopened search must not show the previous query',
    );
  });
}
