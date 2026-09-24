// Widget test for the shelf: bar contents, pinned apps from a pre-written
// config, launcher panel open/close, right-click unpin flow — and the
// input-region state machine they drive (no-op under flutter_test, but the
// code path must not throw).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:materde_shell/services/desktop_app.dart';
import 'package:materde_shell/shelf/shelf.dart';

DesktopApp _app(String id, String name, List<String> categories) => DesktopApp(
      id: id,
      name: name,
      exec: id,
      categories: categories,
      iconName: null,
      filePath: '/fake/$id.desktop',
    );

void main() {
  late Directory tmp;
  late String configPath;
  final launched = <String>[];

  final apps = <DesktopApp>[
    _app('fakeweb', 'Fake Browser', const ['Network', 'WebBrowser']),
    _app('faketerm', 'Fake Term', const ['System', 'TerminalEmulator']),
    _app('fakeutil', 'Fake Util', const ['Utility']),
  ];

  setUp(() async {
    launched.clear();
    tmp = await Directory.systemTemp.createTemp('materde-shelf-widget');
    configPath = '${tmp.path}/shelf.json';
    // Pre-seed the config so the test never takes the first-run save path
    // (async real IO does not play well with the fake-async test clock).
    File(configPath)
        .writeAsStringSync(jsonEncode({'pinned': ['fakeweb', 'faketerm']}));
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Future<void> pumpShelf(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MaterdeShelf(
        configPath: configPath,
        appsOverride: apps,
        trayPoll: false,
        appLauncher: (app) async => launched.add(app.id),
      ),
    ));
    await tester.pump(); // post-frame input-region sync + config load
  }

  testWidgets('shows bar, pins and clock', (tester) async {
    await pumpShelf(tester);

    expect(find.byIcon(Icons.apps), findsOneWidget, reason: 'launcher');
    expect(find.byTooltip('Fake Browser'), findsOneWidget, reason: 'pinned');
    expect(find.byTooltip('Fake Term'), findsOneWidget, reason: 'pinned');
    expect(
      tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .any((text) => RegExp(r'^\d{2}:\d{2}$').hasMatch(text)),
      isTrue,
      reason: 'clock',
    );

    // No menu yet → the launcher panel must not be built.
    expect(find.text('Fake Util'), findsNothing);

    await tester.pumpWidget(const SizedBox()); // unmount: cancel timers
  });

  testWidgets('launcher panel lists all apps and closes after a row tap',
      (tester) async {
    await pumpShelf(tester);

    await tester.tap(find.byIcon(Icons.apps));
    await tester.pump();
    expect(find.text('Fake Util'), findsOneWidget, reason: 'all apps listed');
    expect(find.text('Fake Browser'), findsWidgets,
        reason: 'pinned app also listed');

    // Row tap launches through the seam and closes the panel.
    await tester.tap(find.text('Fake Util'));
    await tester.pump();
    expect(find.text('Fake Util'), findsNothing, reason: 'panel closed');
    expect(launched, <String>['fakeutil'], reason: 'launch requested');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('launcher panel dismisses when clicking outside it',
      (tester) async {
    await pumpShelf(tester);

    await tester.tap(find.byIcon(Icons.apps));
    await tester.pump();
    expect(find.text('Fake Util'), findsOneWidget);

    // The dismiss layer covers the bar too: clicking the launcher button
    // again hits it (not the button) and closes the panel — warnIfMissed
    // off because hitting the button instead would be the bug.
    await tester.tap(find.byIcon(Icons.apps), warnIfMissed: false);
    await tester.pump();
    expect(find.text('Fake Util'), findsNothing, reason: 'dismissed');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('right-click opens the pin menu and unpinning hides the item',
      (tester) async {
    await pumpShelf(tester);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byTooltip('Fake Browser')),
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pump();
    expect(find.text('Unpin from shelf'), findsOneWidget);

    await tester.tap(find.text('Unpin from shelf'));
    await tester.pump();
    expect(find.byTooltip('Fake Browser'), findsNothing,
        reason: 'unpinned from the bar');
    expect(find.text('Unpin from shelf'), findsNothing,
        reason: 'menu closed after action');

    await tester.pumpWidget(const SizedBox());
  });
}
