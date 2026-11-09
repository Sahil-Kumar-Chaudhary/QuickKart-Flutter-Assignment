// Feature 2, part 4: AppConfigController keeps itself up to date.
// * subscribes to ConfigRepository.remoteUpdates in build()
// * published changes apply within (fake) seconds, no restart
// * must not leak listeners (guaranteed checked via configListenerCount)
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/core/providers.dart';
import 'package:quickkart/features/app_config/data/config_repository.dart';
import 'package:quickkart/features/app_config/domain/app_config.dart';
import 'package:quickkart/features/app_config/presentation/app_config_controller.dart';

import '../helpers/test_harness.dart';

void main() {
  late TestHarness h;

  setUp(() {
    h = TestHarness();
  });

  tearDown(() => h.dispose());

  /// Lets the stream event + config GET settle.
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 120));

  test('a published config change applies without a restart', () async {
    final config = h.read(appConfigControllerProvider);
    expect(config.storeOpen, isTrue);

    h.server.publishConfig({'store_open': false});
    await settle();

    final updated = h.read(appConfigControllerProvider);
    expect(updated.storeOpen, isFalse);
    // Even the live update uses the resilient loader (it fetches fresh).
    expect(
      updated.storeClosedMessage,
      isNot(AppConfig.defaults().storeClosedMessage),
    );
  });

  test('consecutive publishes keep up (last one wins)', () async {
    h.server.publishConfig({'delivery_fee_paise': 1000});
    await settle();
    h.server.publishConfig({'delivery_fee_paise': 3000});
    await settle();

    expect(h.read(appConfigControllerProvider).deliveryFeePaise, 3000);
  });

  test('refresh() still works for manual pulls', () async {
    h.server.publishConfig({'free_delivery_threshold_paise': 9900});
    await h.read(appConfigControllerProvider.notifier).refresh();

    expect(h.read(appConfigControllerProvider).freeDeliveryThresholdPaise, 9900);
  });

  test('hydrated startup state survives until the next publish', () async {
    h.read(appConfigControllerProvider.notifier)
        .hydrate(AppConfig.fromValues({'store_open': false}));
    expect(h.read(appConfigControllerProvider).storeOpen, isFalse);

    // The controller must not revert to defaults while nothing is
    // published. (Nothing fires here: the controller only re-syncs on a
    // publish event, which does not happen before this assertion.)
    await settle();
    expect(h.read(appConfigControllerProvider).storeOpen, isFalse);
  });

  test('disposing the container does not leak config listeners', () async {
    final before = h.server.configListenerCount;

    final container = ProviderContainer(overrides: [
      keyValueStoreProvider.overrideWithValue(h.store),
      mockServerProvider.overrideWithValue(h.server),
    ]);
    container.read(appConfigControllerProvider); // build() -> subscribe
    await settle();
    expect(
      h.server.configListenerCount,
      before + 1,
      reason: 'the controller must be subscribed while alive',
    );
    container.dispose();
    await settle();

    expect(h.server.configListenerCount, before,
        reason: 'disposing the app must cancel the subscription');
  });

  test('rebuilding the controller does not stack subscriptions', () async {
    final before = h.server.configListenerCount;

    h.read(appConfigControllerProvider);
    await settle();
    // Simulate a rebuild (e.g. a watched dependency changed).
    h.container.invalidate(appConfigControllerProvider);
    h.read(appConfigControllerProvider);
    await settle();

    expect(h.server.configListenerCount, before + 1,
        reason: 'a rebuild must replace the subscription, not add another');
  });

  test('updates after dispose must not crash', () async {
    final container = ProviderContainer(overrides: [
      keyValueStoreProvider.overrideWithValue(h.store),
      mockServerProvider.overrideWithValue(h.server),
    ]);
    container.read(appConfigControllerProvider);
    container.dispose();

    // A publish right after app teardown must not throw anywhere.
    h.server.publishConfig({'store_open': false});
    await settle();
  });
}
