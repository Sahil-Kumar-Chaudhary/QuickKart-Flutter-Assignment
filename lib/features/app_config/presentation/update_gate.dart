import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/providers.dart';
import '../domain/app_config.dart';
import '../domain/update_policy.dart';
import 'app_config_controller.dart';
import 'update_gate_state.dart';

/// Renders the app with an optional update gate on top.
///
/// * `required` -> a full-screen, non dismissible "Update required" page
///   (a config change can trigger it mid-session, because the gate reads
///   the live [appConfigControllerProvider]).
/// * `optional` -> a dismissible banner; a dismissal is remembered
///   per `latest_version`, so the user is not nagged again for the same
///   version (it also survives an app restart).
/// * nothing is rendered when the app is healthy or the config values are
///   malformed (UpdatePolicy returns `none` in that case).
class UpdateGate extends ConsumerWidget {
  const UpdateGate({super.key, required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigControllerProvider);
    final gate = ref.watch(updateGateStateProvider);
    final appVersion = ref.watch(appVersionProvider);

    final requirement = UpdatePolicy.evaluate(
      currentVersion: appVersion,
      minSupportedVersion: config.minSupportedVersion,
      latestVersion: config.latestVersion,
    );

    final Widget? overlay;
    overlay = switch (requirement) {
      UpdateRequirement.required => _RequiredUpdatePage(config: config),
      // "Later" remembers the version, so re-publishing the same
      // latest_version does not nag again (BUSINESS: respects the user).
      UpdateRequirement.optional =>
        gate.hydrationPending ||
                gate.dismissedLatestVersion == config.latestVersion
            ? null
            : _OptionalUpdateBanner(config: config),
      UpdateRequirement.none => null,
    };

    return Stack(
      children: [
        if (child != null) Positioned.fill(child: child!),
        // A modal barrier also swallows taps to whatever is behind the gate.
        if (overlay != null)
          const Positioned.fill(
            child: ModalBarrier(dismissible: false, color: Colors.black38),
          ),
        if (overlay != null) Positioned.fill(child: overlay),
      ],
    );
  }
}

class _RequiredUpdatePage extends StatelessWidget {
  const _RequiredUpdatePage({required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.system_update, size: 64),
                  const SizedBox(height: 16),
                  const Text(
                    'Update required',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This QuickKart version is no longer supported. Please '
                    'update the app to continue shopping.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => openUpdateUrl(context, config.updateUrl),
                    child: const Text('Update now'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionalUpdateBanner extends ConsumerWidget {
  const _OptionalUpdateBanner({required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        child: Material(
          elevation: 6,
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                const Icon(Icons.new_releases_outlined),
                const SizedBox(width: 8),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Update available',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 2),
                    Text('A fresh QuickKart is out. Grab it now!',
                        style: TextStyle(fontSize: 12)),
                  ],
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => ref
                      .read(updateGateStateProvider.notifier)
                      .dismiss(config.latestVersion),
                  child: const Text('Later'),
                ),
                TextButton(
                  onPressed: () => openUpdateUrl(context, config.updateUrl),
                  child: const Text('Update now'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the store page for [url]. Failures degrade to a snackbar with the
/// raw URL - a broken update_url must not crash the app.
Future<void> openUpdateUrl(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (url.isEmpty) {
    messenger?.showSnackBar(const SnackBar(
      content: Text('The update link is not configured yet.'),
    ));
    return;
  }
  try {
    final uri = Uri.tryParse(url);
    if (uri == null || !await canLaunchUrl(uri)) {
      throw Exception('cannot open $url');
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Exception {
    messenger?.showSnackBar(SnackBar(content: Text('Open this link: $url')));
  }
}
