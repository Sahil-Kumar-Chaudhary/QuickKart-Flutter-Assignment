import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quickkart/core/providers.dart';
import 'package:quickkart/core/storage/key_value_store.dart';
import 'package:quickkart/mock_server/mock_server.dart';

/// Wires the app's providers to an in-memory store and an in-memory mock
/// server (perfect network by default). Use `server.chaos` to make the
/// network misbehave and the server admin API (`setPrice`, `setStock`,
/// `publishConfig`, ...) to change backend data.
class TestHarness {
  TestHarness._(this.store, this.server, this.container);

  factory TestHarness({KeyValueStore? store, MockServer? server}) {
    final s = store ?? InMemoryKeyValueStore();
    final srv = server ?? MockServer.inMemory();
    final container = ProviderContainer(overrides: [
      keyValueStoreProvider.overrideWithValue(s),
      mockServerProvider.overrideWithValue(srv),
    ]);
    return TestHarness._(s, srv, container);
  }

  final KeyValueStore store;
  final MockServer server;
  final ProviderContainer container;

  T read<T>(ProviderListenable<T> provider) => container.read(provider);

  /// Simulates an app restart: same device storage, same server, fresh
  /// in-memory app state.
  TestHarness restart() => TestHarness(store: store, server: server);

  void dispose() => container.dispose();
}
