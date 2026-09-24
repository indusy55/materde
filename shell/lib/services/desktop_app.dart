// XDG .desktop entry parsing and discovery (docs/07 Phase 1: launch apps
// from the shelf).
//
// No dependencies: a hand-rolled reader for the `[Desktop Entry]` group is
// plenty — we only need Type/Name/Exec/Icon/Categories plus the
// Hidden/NoDisplay filters.

import 'dart:io';

import 'app_launcher.dart';

class DesktopApp {
  const DesktopApp({
    required this.id,
    required this.name,
    required this.exec,
    required this.categories,
    required this.iconName,
    required this.filePath,
  });

  /// `.desktop` basename without the extension, e.g. `firefox`.
  final String id;

  /// Untranslated `Name=`.
  final String? name;

  /// Raw `Exec=` line; parsed by [AppLauncher.execToArgv] on launch.
  final String? exec;

  /// `Categories=` split on `;` (untranslated ids like `WebBrowser`).
  final List<String> categories;

  /// `Icon=` theme name or file basename; null when absent.
  final String? iconName;

  /// Full path of the entry file.
  final String filePath;

  String get displayName => (name?.isNotEmpty ?? false) ? name! : id;

  /// Launches this application (detached; the shell does not supervise it).
  Future<void> launch() => AppLauncher.launch(this);

  /// Parses one `.desktop` file; returns null for non-Applications,
  /// Hidden/NoDisplay entries, or files without a usable Name.
  static DesktopApp? parseFile(File file) {
    String? section;
    String? name;
    String? exec;
    String? icon;
    var type = 'Application';
    var hidden = false;
    var noDisplay = false;
    var categories = const <String>[];

    for (final rawLine in file.readAsLinesSync()) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.startsWith('[') && line.endsWith(']')) {
        section = line.substring(1, line.length - 1);
        continue;
      }
      if (section != 'Desktop Entry') continue;
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      final key = line.substring(0, eq);
      final value = line.substring(eq + 1);
      switch (key) {
        case 'Type':
          type = value;
        case 'Name':
          name = value;
        case 'Exec':
          exec = value;
        case 'Icon':
          icon = value;
        case 'Categories':
          categories =
              value.split(';').where((c) => c.isNotEmpty).toList(growable: false);
        case 'Hidden':
          hidden = value.trim().toLowerCase() == 'true';
        case 'NoDisplay':
          noDisplay = value.trim().toLowerCase() == 'true';
      }
    }

    if (type != 'Application' || hidden || noDisplay || name == null) {
      return null;
    }
    final fileName = file.path.split('/').last;
    final id = fileName.endsWith('.desktop')
        ? fileName.substring(0, fileName.length - '.desktop'.length)
        : fileName;
    return DesktopApp(
      id: id,
      name: name,
      exec: exec,
      categories: categories,
      iconName: (icon?.isNotEmpty ?? false) ? icon : null,
      filePath: file.path,
    );
  }

  /// Scans the standard XDG application dirs, user entries shadowing system
  /// ones by id, sorted by display name.
  ///
  /// [dirs] overrides the search path (used by tests).
  static List<DesktopApp> discover({List<String>? dirs}) {
    final home = Platform.environment['HOME'] ?? '';
    final searchDirs = dirs ??
        <String>[
          '$home/.local/share/applications',
          '$home/.local/share/flatpak/exports/share/applications',
          '/usr/share/applications',
          '/usr/share/flatpak/exports/share/applications',
        ];
    final seen = <String>{};
    final apps = <DesktopApp>[];
    for (final dirPath in searchDirs) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;
      final files = dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.desktop'));
      for (final file in files) {
        final app = parseFile(file);
        if (app == null || !seen.add(app.id)) continue;
        apps.add(app);
      }
    }
    apps.sort((a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return apps;
  }
}
