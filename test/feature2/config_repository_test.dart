// Feature 2, part 3: ConfigRepository.load must survive bad networks.
// * success: persist the values (last known good)
// * failure: last known good, else defaults
// * it must NEVER throw - offline cold start boots normally.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/app_config/data/config_repository.dart';
import 'package:quickkart/features/app_config/domain/app_config.dart';

import '../helpers/test_harness.dart';

void main() {
  late TestHarness h;

  setUp(() {
    h = TestHarness();
  });

  tearDown(() => h.dispose());

  test('a successful load returns the server values', () async {
    h.server.publishConfig({'store_open': false,
        'store_closed_message': 'Test closed message',
        'delivery_fee_paise': 4200});

    final config = await h.read(configRepositoryProvider).load();

    expect(config.storeOpen, isFalse);
    expect(config.storeClosedMessage, 'Test closed message');
    expect(config.deliveryFeePaise, 4200);
  });

  test('after a successful load, an offline load returns the last known good',
      () async {
    h.server.publishConfig({
      'store_open': false,
      'store_closed_message': 'Closed during the rain spike',
      'latest_version': '1.6.0',
      'home_banner': '{"title":"Diwali!","subtitle":"30% off"}',
      'home_sections': '["banner","categories","deals"]',
    });
    final good = await h.read(configRepositoryProvider).load();
    expect(good.storeOpen, isFalse, reason: 'precondition: server values read');

    // The network is gone.
    h.server.chaos.offline = true;

    final offline = await h.read(configRepositoryProvider).load();

    expect(offline.storeOpen, isFalse);
    expect(offline.storeClosedMessage, 'Closed during the rain spike');
    expect(offline.latestVersion, '1.6.0');
    expect(offline.homeBanner?.title, 'Diwali!');
    expect(offline.homeSectionsJson, '["banner","categories","deals"]');
  });

  test('an offline cold start (nothing cached) uses defaults and never throws',
      () async {
    h.server.chaos.offline = true;

    final AppConfig config;
    config = await h.read(configRepositoryProvider).load();

    expect(config.storeOpen, isTrue);
    expect(config.deliveryFeePaise, 2500);
    expect(config, AppConfig.defaults());
  });

  test('load never throws and survives a 5xx', () async {
    // Seed the cache with good values first.
    await h.read(configRepositoryProvider).load();

    // Simulate a server error without going fully offline.
    h.server.chaos.failureRate = 1.0;

    final config = await h.read(configRepositoryProvider).load();

    expect(config.storeOpen, isTrue, reason: 'last known good is served');
  });

  test('new values overwrite the cached copy', () async {
    final repo = h.read(configRepositoryProvider);
    await repo.load(); // cache the defaults
    h.server.publishConfig({'free_delivery_threshold_paise': 9900});
    final fresh = await repo.load();
    expect(fresh.freeDeliveryThresholdPaise, 9900);

    h.server.chaos.offline = true;
    final offline = await repo.load();
    expect(offline.freeDeliveryThresholdPaise, 9900);
  });
}


