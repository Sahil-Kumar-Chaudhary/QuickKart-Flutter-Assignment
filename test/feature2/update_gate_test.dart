// Feature 2, part 5: the version gate.
// * required -> full-screen, non dismissible "Update required" page, also
//   mid-session when the config changes while the app is open
// * optional -> dismissible prompt, dismissals are remembered (no nagging
//   for the same latest_version, and they survive a restart)
// * gate evaluates from live config; a broken value never locks the app.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/core/providers.dart';
import 'package:quickkart/core/storage/key_value_store.dart';
import 'package:quickkart/features/app_config/presentation/app_config_controller.dart';
import 'package:quickkart/features/app_config/presentation/update_gate.dart';
import 'package:quickkart/mock_server/mock_server.dart';

Widget _app(
  ProviderContainer container,
  MockServer server, {
  String appVersion = '1.4.0',
}) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        builder: (context, child) => UpdateGate(child: child ?? const SizedBox()),
        home: const Scaffold(
          key: Key('home-content'),
          body: Center(child: Text('HOME CONTENT')),
        ),
      ),
    );

ProviderContainer _container(MockServer server, {KeyValueStore? store}) =>
    ProviderContainer(overrides: [
      keyValueStoreProvider.overrideWithValue(store ?? InMemoryKeyValueStore()),
      mockServerProvider.overrideWithValue(server),
      appVersionProvider.overrideWithValue('1.4.0'),
    ]);

void main() {
  testWidgets('required gate blocks the app full screen', (tester) async {
    final server = MockServer.inMemory();
    server.publishConfig({
      'min_supported_version': '2.0.0',
      'latest_version': '2.0.0',
      'update_url': 'https://example.com/update',
    });
    final container = _container(server);
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container, server));
    await tester.pumpAndSettle();

    expect(find.text('Update required'), findsOneWidget);
    expect(find.byKey(const Key('home-content')), findsOneWidget,
        reason: 'the gate overlays the app instead of replacing it');
    expect(find.text('Update now'), findsOneWidget,
        reason: 'the gate points the user at the update');
  });

  testWidgets('the required gate cannot be dismissed by tapping around',
      (tester) async {
    final server = MockServer.inMemory();
    server.publishConfig({'min_supported_version': '2.0.0'});
    final container = _container(server);
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container, server));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('home-content')),
        warnIfMissed: false); // behind the barrier
    await tester.pumpAndSettle();

    expect(find.text('Update required'), findsOneWidget);
  });

  testWidgets('a config change mid-session triggers the gate within seconds',
      (tester) async {
    final server = MockServer.inMemory();
    final container = _container(server);
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container, server));
    await tester.pumpAndSettle();
    expect(find.text('Update required'), findsNothing);

    // Ops force-blocks this buggy build while the app is open.
    server.publishConfig({'min_supported_version': '9.9.9'});
    await tester.pumpAndSettle();

    expect(find.text('Update required'), findsOneWidget);
  });

  testWidgets('optional updates show a dismissible prompt', (tester) async {
    final server = MockServer.inMemory();
    server.publishConfig({'latest_version': '2.0.0'});
    final container = _container(server);
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container, server));
    await tester.pumpAndSettle();
    expect(find.text('Update required'), findsNothing);
    expect(find.text('Update available'), findsOneWidget);

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsNothing);
  });

  testWidgets('a dismissed optional update does not nag again for the same '
      'version, but a newer one does', (tester) async {
    final server = MockServer.inMemory();
    final store = InMemoryKeyValueStore();
    final container = _container(server, store: store);
    addTearDown(container.dispose);

    server.publishConfig({'latest_version': '2.0.0'});
    await tester.pumpWidget(_app(container, server));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsNothing);

    // Same version re-published: stay quiet.
    server.publishConfig({'update_url': 'https://example.com/update-2'});
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsNothing);

    // A new version lands: ask again.
    server.publishConfig({'latest_version': '2.1.0'});
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsOneWidget);
  });

  testWidgets('a dismissal survives an app restart', (tester) async {
    final server = MockServer.inMemory();
    server.publishConfig({'latest_version': '2.0.0'});

    final store = InMemoryKeyValueStore();
    final first = _container(server, store: store);
    await tester.pumpWidget(_app(first, server));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    first.dispose();

    // "Restart": same store, fresh container.
    final restarted = _container(server, store: store);
    addTearDown(restarted.dispose);
    await tester.pumpWidget(_app(restarted, server));
    await tester.pumpAndSettle();

    expect(find.text('Update available'), findsNothing,
        reason: 'dismissals persist across restarts');
  });

  testWidgets('a healthy app never shows the gate', (tester) async {
    final server = MockServer.inMemory();
    final container = _container(server);
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container, server));
    await tester.pumpAndSettle();

    expect(find.text('Update required'), findsNothing);
    expect(find.text('Update available'), findsNothing);
  });

  testWidgets('malformed version values in the console never lock the app',
      (tester) async {
    final server = MockServer.inMemory();
    server.publishConfig({'min_supported_version': ''});
    final container = _container(server);
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container, server));
    await tester.pumpAndSettle();

    expect(find.text('Update required'), findsNothing);
  });
}
