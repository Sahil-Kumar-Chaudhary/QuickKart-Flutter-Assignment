import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';

/// Storage key of the optional-update version the user dismissed.
const String kDismissedUpdateVersionKey = 'app_update.dismissed_version';

/// State of the version gate: which optional update the user has already
/// dismissed (persisted across restarts) and whether that persisted value
/// has been read yet.
class UpdateGateState {
  const UpdateGateState({
    this.hydrationPending = true,
    this.dismissedLatestVersion,
  });

  /// True until the persisted dismissal has been read once. The gate stays
  /// out of the way until then, so a slow storage never causes a wrong
  /// prompt flash on startup.
  final bool hydrationPending;

  /// `latest_version` the user chose "Later" for. Suppresses the optional
  /// prompt while the server still offers exactly this version.
  final String? dismissedLatestVersion;
}

final updateGateStateProvider =
    NotifierProvider<UpdateGateController, UpdateGateState>(
        UpdateGateController.new);

class UpdateGateController extends Notifier<UpdateGateState> {
  bool _disposed = false;

  @override
  UpdateGateState build() {
    // Hydrate the persisted dismissal before the gate may nag again.
    ref.watch(keyValueStoreProvider).getString(kDismissedUpdateVersionKey).then(
      (raw) {
        if (_disposed) return;
        state = UpdateGateState(
          hydrationPending: false,
          dismissedLatestVersion: (raw == null || raw.isEmpty) ? null : raw,
        );
      },
      onError: (Object _) {
        // A storage hiccup must not show a wrong gate: treat as no dismissal.
        if (!_disposed) state = const UpdateGateState(hydrationPending: false);
      },
    );
    ref.onDispose(() => _disposed = true);
    return const UpdateGateState();
  }

  Future<void> dismiss(String latestVersion) async {
    if (_disposed || latestVersion.isEmpty) return;
    state = UpdateGateState(
      hydrationPending: false,
      dismissedLatestVersion: latestVersion,
    );
    try {
      await ref
          .read(keyValueStoreProvider)
          .setString(kDismissedUpdateVersionKey, latestVersion);
    } on Exception {
      // Remembering is best-effort; the prompt stays suppressed for this
      // session regardless.
    }
  }
}
