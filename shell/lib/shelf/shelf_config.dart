// Shelf configuration: pinned-app persistence (docs/04 §1 "Shelf").
//
// Stored as hand-rolled JSON via dart:convert — Phase 1 adds zero Dart
// dependencies (docs/07 constraint). Layout:
//
//   ~/.config/materde/shelf.json
//   { "pinned": ["firefox.desktop", "org.kde.konsole.desktop"] }

import 'dart:convert';
import 'dart:io';

/// Corner radius of individual shelf items (docs/05 "Shelf items: 8px";
/// docs/04's 16px conflicts with docs/05 and lost — see docs/04 §1 note).
const double kShelfItemRadius = 8;

class ShelfConfig {
  ShelfConfig._(this.pinned, this.path, this.existed);

  /// Ordered ids of pinned applications (`.desktop` basenames).
  final List<String> pinned;

  /// Where this config was loaded from (and where [save] writes).
  final String path;

  /// Whether the config file existed when loaded. `false` marks a first run,
  /// which is when the shelf seeds default pins.
  final bool existed;

  static String defaultPath() {
    final home = Platform.environment['HOME'] ?? '';
    return '$home/.config/materde/shelf.json';
  }

  /// Loads the config; missing or corrupt files yield an empty pin list.
  ///
  /// A missing file keeps `existed == false` (first run), a corrupt one does
  /// not — we never silently overwrite a file we failed to read.
  factory ShelfConfig.load({String? path}) {
    final p = path ?? defaultPath();
    final file = File(p);
    if (!file.existsSync()) {
      return ShelfConfig._(<String>[], p, false);
    }
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map<String, dynamic>) {
        final ids = decoded['pinned'];
        if (ids is List) {
          return ShelfConfig._(
              ids.whereType<String>().toList(growable: false), p, true);
        }
      }
    } catch (_) {
      // FormatException (bad JSON) or FileSystemException (unreadable):
      // fall through to an empty list, still "existed".
    }
    return ShelfConfig._(<String>[], p, true);
  }

  /// A fresh config holding [pinned] — used both for first-run defaults and
  /// for persisting pin changes (`initial` = "config to write").
  factory ShelfConfig.initial(List<String> pinned, {String? path}) {
    return ShelfConfig._(
        List<String>.unmodifiable(pinned), path ?? defaultPath(), false);
  }

  /// Persists the pin list, creating its parent directory on demand.
  Future<void> save() async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(<String, dynamic>{
        'pinned': pinned,
      }),
    );
  }
}
