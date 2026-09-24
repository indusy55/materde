// Tests for XDG .desktop parsing/discovery, Exec= tokenization and the
// first-run default pin heuristic.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:materde_shell/services/app_launcher.dart';
import 'package:materde_shell/services/desktop_app.dart';
import 'package:materde_shell/shelf/pinned_apps.dart';

void main() {
  late Directory tmp;

  File write(Directory dir, String name, String content) {
    final file = File('${dir.path}/$name');
    file.writeAsStringSync(content);
    return file;
  }

  const plainEntry = '''
[Desktop Entry]
Type=Application
Name=Fake Browser
Exec=fake-browser --new-window %U
Icon=fakebrowser
Categories=Network;WebBrowser;
''';

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('materde-desktop-app');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  group('DesktopApp.parseFile', () {
    test('parses a plain Application entry', () {
      final app = DesktopApp.parseFile(write(tmp, 'fake.desktop', plainEntry));
      expect(app, isNotNull);
      expect(app!.id, 'fake');
      expect(app.name, 'Fake Browser');
      expect(app.exec, 'fake-browser --new-window %U');
      expect(app.iconName, 'fakebrowser');
      expect(app.categories, containsAll(<String>['Network', 'WebBrowser']));
    });

    test('skips Hidden, NoDisplay, non-Application and nameless entries', () {
      expect(
        DesktopApp.parseFile(write(tmp, 'hidden.desktop',
            plainEntry.replaceFirst('Type=', 'Hidden=true\nType='))),
        isNull,
      );
      expect(
        DesktopApp.parseFile(write(tmp, 'nodisp.desktop',
            plainEntry.replaceFirst('Type=', 'NoDisplay=true\nType='))),
        isNull,
      );
      expect(
        DesktopApp.parseFile(write(
            tmp, 'link.desktop', plainEntry.replaceFirst('Type=Application', 'Type=Link'))),
        isNull,
      );
      expect(
        DesktopApp.parseFile(write(
            tmp, 'nameless.desktop', '[Desktop Entry]\nType=Application\nExec=x\n')),
        isNull,
      );
    });
  });

  group('DesktopApp.discover', () {
    test('user entries shadow system ones by id, sorted by display name', () {
      final system = Directory('${tmp.path}/system')..createSync();
      final user = Directory('${tmp.path}/user')..createSync();
      write(system, 'zeta.desktop',
          plainEntry.replaceFirst('Fake Browser', 'Zeta'));
      write(system, 'alpha.desktop',
          plainEntry.replaceFirst('Fake Browser', 'Alpha'));
      write(user, 'zeta.desktop',
          plainEntry.replaceFirst('Fake Browser', 'Zeta User'));

      final apps = DesktopApp.discover(dirs: [user.path, system.path]);
      expect(apps.map((a) => a.id).toList(), <String>['alpha', 'zeta']);
      expect(apps.last.name, 'Zeta User', reason: 'user dir wins by id');
    });
  });

  group('AppLauncher.execToArgv', () {
    test('handles quotes and strips field codes', () {
      expect(
        AppLauncher.execToArgv('prog --name "hello world" %u'),
        <String>['prog', '--name', 'hello world'],
      );
      expect(
        AppLauncher.execToArgv("prog 'single quoted' %f"),
        <String>['prog', 'single quoted'],
      );
      expect(
        AppLauncher.execToArgv('env FOO=bar app -x %i %c'),
        <String>['env', 'FOO=bar', 'app', '-x'],
      );
    });

    test('expands %% and keeps ordinary % tokens', () {
      expect(
        AppLauncher.execToArgv('prog 100%% done'),
        <String>['prog', '100%', 'done'],
      );
      expect(
        AppLauncher.execToArgv('prog %'),
        <String>['prog', '%'],
      );
      expect(
        AppLauncher.execToArgv('prog 50%off'),
        <String>['prog', '50%off'],
      );
    });
  });

  group('suggestDefaultPins', () {
    test('picks a browser and a terminal, at most one per category', () {
      DesktopApp app(String id, List<String> cats) => DesktopApp(
            id: id,
            name: id,
            exec: id,
            categories: cats,
            iconName: null,
            filePath: '/x',
          );
      final picks = suggestDefaultPins([
        app('browser1', const ['WebBrowser']),
        app('browser2', const ['WebBrowser']),
        app('editor', const ['Utility', 'TextEditor']),
        app('term', const ['TerminalEmulator']),
      ]);
      expect(picks.map((p) => p.id).toList(), <String>['browser1', 'term']);
    });
  });
}
