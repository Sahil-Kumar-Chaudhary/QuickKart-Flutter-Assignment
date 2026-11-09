import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../../../core/storage/key_value_store.dart';
import '../domain/app_config.dart';

final configRepositoryProvider = Provider<ConfigRepository>(
  (ref) => ConfigRepository(
    ref.watch(apiClientProvider),
    ref.watch(keyValueStoreProvider),
    remoteUpdates: () => ref.read(mockServerProvider).configUpdates,
  ),
);

/// Local copy of the last successfully fetched config. A config is small;
/// storing the raw values keeps forward compatibility: unknown keys survive
/// an app restart and are re-served when the app learns to read them.
const String kLastGoodConfigKey = 'config.last_good_v1';

/// Loads remote config (think: Firebase Remote Config).
///
/// `load()` always completes and never throws:
/// * success -> values are returned **and** persisted;
/// * failure -> last known good config (from local storage);
/// * nothing cached -> [AppConfig.defaults].
class ConfigRepository {
  ConfigRepository(
    this._client,
    this._store, {
    required Stream<int> Function() remoteUpdates,
  }) : _remoteUpdates = remoteUpdates;

  final ApiClient _client;
  final KeyValueStore _store;
  final Stream<int> Function() _remoteUpdates;

  /// Fires (with the new config version) every time config is published
  /// from the console. Equivalent to Firebase's `onConfigUpdated`.
  Stream<int> get remoteUpdates => _remoteUpdates();

  /// Fetches the latest config, with offline resilience.
  Future<AppConfig> load() async {
    Map<String, Object?>? fetched;
    try {
      final json = await _client.get('/v1/config') as Map<String, dynamic>;
      fetched = (json['values'] as Map).cast<String, Object?>();
    } on Object {
      // Bad network / unexpected body: fall back below. Never throw - the
      // app must start normally offline.
    }
    if (fetched != null) {
      try {
        await _persist(fetched);
      } on Object {
        // A storage hiccup must not fail an otherwise good load.
      }
      return AppConfig.fromValues(fetched);
    }
    return await _cached() ?? AppConfig.defaults();
  }

  Future<void> _persist(Map<String, Object?> values) {
    return _store.setString(kLastGoodConfigKey, jsonEncode(values));
  }

  Future<AppConfig?> _cached() async {
    try {
      final raw = await _store.getString(kLastGoodConfigKey);
      if (raw == null || raw.isEmpty) return null;
      final values = jsonDecode(raw);
      if (values is! Map<String, dynamic>) return null;
      return AppConfig.fromValues(values);
    } catch (_) {
      // A corrupted cache is the same as no cache: defaults.
      return null;
    }
  }
}
