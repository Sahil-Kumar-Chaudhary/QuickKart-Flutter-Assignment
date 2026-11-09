import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/config_repository.dart';
import '../domain/app_config.dart';

/// The config the app is currently using. Hydrated in `main.dart` before the
/// first frame.
final appConfigControllerProvider =
    NotifierProvider<AppConfigController, AppConfig>(AppConfigController.new);

class AppConfigController extends Notifier<AppConfig> {
  /// Guard against pushing state after this notifier was disposed (the
  /// subscription could deliver one in flight load).
  bool _disposed = false;

  StreamSubscription<int>? _subscription;

  @override
  AppConfig build() {
    // Cancel on dispose before anything else so an in-flight sync can never
    // touch state afterwards. Also note: this runs again whenever this
    // provider is rebuilt (dependencies changed), which replaces the
    // subscription exactly once - no stacking, no leaks.
    _subscription = ref.watch(configRepositoryProvider).remoteUpdates.listen(
          (_) => unawaited(_sync()),
        );
    ref.onDispose(() {
      _disposed = true;
      unawaited(_subscription?.cancel());
      _subscription = null;
    });

    // Hydrated by main.dart before the first frame; until then config
    // defaults apply (safe offline boot).
    return AppConfig.defaults();
  }

  /// Applied at startup and, within seconds, on every remote publish.
  Future<void> _sync() async {
    try {
      final config = await ref.read(configRepositoryProvider).load();
      if (!_disposed) state = config;
    } on Exception {
      // load() never throws for network problems; this is belt-and-braces.
    }
  }

  /// Used at startup with the config loaded during bootstrap.
  void hydrate(AppConfig config) => state = config;

  Future<void> refresh() async {
    final config = await ref.read(configRepositoryProvider).load();
    if (!_disposed) state = config;
  }
}
