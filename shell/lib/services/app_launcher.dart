// Launches .desktop applications (docs/07 Phase 1: shelf → process).

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'desktop_app.dart';

class AppLauncher {
  AppLauncher._();

  /// Launches [app] detached; failures are logged, not thrown — the shell
  /// must keep running even if an entry is stale.
  static Future<void> launch(DesktopApp app) async {
    final exec = app.exec;
    if (exec == null || exec.isEmpty) {
      debugPrint('shelf: ${app.id} has no Exec= line');
      return;
    }
    final argv = execToArgv(exec);
    if (argv.isEmpty) {
      debugPrint('shelf: ${app.id} Exec= produced no argv: $exec');
      return;
    }
    try {
      await Process.start(
        argv.first,
        argv.sublist(1),
        mode: ProcessStartMode.detached,
        workingDirectory: Platform.environment['HOME'],
      );
    } on ProcessException catch (e) {
      debugPrint('shelf: failed to launch ${app.id}: ${e.message}');
    }
  }

  /// Turns an `Exec=` line into an argv.
  ///
  /// Handles single/double quotes and backslash escapes, and strips XDG
  /// field codes (`%f`, `%u`, `%%`, …). Deliberately not a shell: no
  /// globbing or expansion — an entry needing `sh -c` writes that itself.
  static List<String> execToArgv(String exec) {
    final argv = <String>[];
    final buffer = StringBuffer();
    var tokenOpen = false;
    var inSingle = false;
    var inDouble = false;

    void flush() {
      if (tokenOpen) {
        argv.add(buffer.toString());
        buffer.clear();
        tokenOpen = false;
      }
    }

    for (var i = 0; i < exec.length; i++) {
      final c = exec[i];
      if (inSingle) {
        if (c == "'") {
          inSingle = false;
        } else {
          buffer.write(c);
        }
        continue;
      }
      if (inDouble) {
        if (c == '"') {
          inDouble = false;
        } else if (c == '\\' && i + 1 < exec.length) {
          buffer.write(exec[++i]);
        } else {
          buffer.write(c);
        }
        continue;
      }
      if (c == "'") {
        inSingle = true;
        tokenOpen = true;
      } else if (c == '"') {
        inDouble = true;
        tokenOpen = true;
      } else if (c == '\\' && i + 1 < exec.length) {
        tokenOpen = true;
        buffer.write(exec[++i]);
      } else if (c == ' ') {
        flush();
      } else {
        tokenOpen = true;
        buffer.write(c);
      }
    }
    flush();

    return argv
        .map(_stripFieldCode)
        .where((t) => t != null)
        .cast<String>()
        .toList(growable: false);
  }

  /// Removes standalone XDG field-code tokens (null = drop) and expands
  /// `%%` escapes wherever they appear.
  static String? _stripFieldCode(String token) {
    if (!token.contains('%')) return token;
    if (token.startsWith('%') && token.length == 2) {
      if ('fFuUdDnNickvm'.contains(token[1])) return null; // %f %u %i …
      if (token[1] == '%') return '%'; // %%
    }
    return token.replaceAll('%%', '%');
  }
}
