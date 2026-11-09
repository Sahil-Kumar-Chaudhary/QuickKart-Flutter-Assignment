// Rapid load-more calls must never duplicate a page: after the first
// request takes the cursor, a second call is a no-op until it finishes.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/catalog/data/catalog_repository.dart';
import 'package:quickkart/features/catalog/presentation/catalog_controller.dart';

import '../helpers/test_harness.dart';

void main() {
  late TestHarness h;

  setUp(() {
    h = TestHarness();
  });

  tearDown(() => h.dispose());

  test('two simultaneous loadMore calls fetch the page once', () async {
    final notifier = h.read(catalogControllerProvider('dairy').notifier);

    // Wait for the first page microtask to finish.
    while (h.read(catalogControllerProvider('dairy')).isLoadingFirstPage) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    final stateBefore = h.read(catalogControllerProvider('dairy'));
    expect(stateBefore.hasMore, isTrue);
    expect(stateBefore.nextCursor, isNotNull);

    // The real second page, measured independently of the controller.
    final second = await h
        .read(catalogRepositoryProvider)
        .getPage(categoryId: 'dairy', cursor: stateBefore.nextCursor);
    final expected = stateBefore.items.length + second.items.length;

    final f1 = notifier.loadMore();
    final f2 = notifier.loadMore();
    await Future.wait([f1, f2]);

    final after = h.read(catalogControllerProvider('dairy'));
    expect(
      after.items.length,
      expected,
      reason: 'double-tapped load-more may not append a duplicate page',
    );
  });
}
