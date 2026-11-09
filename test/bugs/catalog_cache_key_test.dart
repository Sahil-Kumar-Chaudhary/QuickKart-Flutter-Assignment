// The offline catalog cache must be scoped per category: a cached fruit page
// must never masquerade as a cached snacks page after the network drops.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/catalog/data/catalog_repository.dart';
import 'package:quickkart/core/network/api_exceptions.dart';

import '../helpers/test_harness.dart';

void main() {
  late TestHarness h;

  setUp(() {
    h = TestHarness();
  });

  tearDown(() => h.dispose());

  test('offline pages are keyed by category, not cursor alone (A8)', () async {
    final repository = h.read(catalogRepositoryProvider);

    // Bring the fruit category online once.
    final fruitsOnline = await repository.getPage(categoryId: 'fruits');
    expect(fruitsOnline.fromCache, isFalse);

    h.server.chaos.offline = true;

    // Same category: cache hit with fromCache=true.
    final fruitsCached = await repository.getPage(categoryId: 'fruits');
    expect(fruitsCached.fromCache, isTrue);
    expect(
      fruitsCached.items.every((p) => p.categoryId == 'fruits'),
      isTrue,
    );

    // Different category: there is no cached page for snacks yet, so the
    // repository must surface the network error instead of serving fruits.
    await expectLater(
      repository.getPage(categoryId: 'snacks'),
      throwsA(isA<NetworkException>()),
    );
  });
}
