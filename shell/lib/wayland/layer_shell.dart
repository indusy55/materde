// Runtime control of the wlr-layer-shell surface, forwarded to our patched
// flutter-client embedder (docs/06 Option A: C++ client + Dart FFI).
//
// Symbol: FlutterDesktopLayerShellSetInputRegion — declared in
// embedder/src/.../public/flutter_elinux.h, implemented in
// elinux_window_wayland.cc (see embedder/LAYER-SHELL-NOTES.md). flutter-client
// links the embedder statically and is built with `-rdynamic`, so the symbol
// is resolvable through DynamicLibrary.process().
//
// Lookup failures degrade to no-ops: widget tests (and any embedder without
// our patch) must not crash just because the surface cannot be reconfigured.

import 'dart:ffi';
import 'dart:ui';

/// Handle to the layer-shell surface of the current process.
class LayerShell {
  LayerShell._();

  static void Function(Rect rect)? _setInputRegion;

  static void Function(Rect rect) _fn() {
    return _setInputRegion ??= _lookup();
  }

  static void Function(Rect rect) _lookup() {
    try {
      final native = DynamicLibrary.process().lookupFunction<
          Void Function(Int32, Int32, Int32, Int32),
          void Function(int, int, int, int)>(
        'FlutterDesktopLayerShellSetInputRegion',
      );
      return (rect) => native(
            rect.left.round(),
            rect.top.round(),
            rect.width.round(),
            rect.height.round(),
          );
    } on ArgumentError {
      // Running outside a patched flutter-client (e.g. flutter test).
      return (rect) {};
    }
  }

  /// Restricts pointer/touch input to [rect] (surface-local logical px,
  /// origin at the surface's top-left).
  ///
  /// The state is double-buffered: the embedder commits the surface as part
  /// of the call, so the restriction applies right away.
  static void setInputRegion(Rect rect) => _fn()(rect);

  /// Lets the whole surface accept input again — used while a menu is open,
  /// so menu items inside the transparent zone get pointer events and an
  /// outside click reaches the barrier and dismisses the menu.
  static void setInputRegionFull() => _fn()(Rect.zero);
}
