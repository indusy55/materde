// System tray + clock, right end of the shelf (docs/04 §1 layout:
// "🔊 🌐 🔋 12:34").
//
// Phase 1 constraint: **zero new Dart dependencies** — the indicators poll
// the system directly (docs/07):
//   volume  → wpctl get-volume @DEFAULT_AUDIO_SINK@   (PipeWire)
//   network → nmcli -t -f TYPE,STATE dev             (NetworkManager)
//   battery → /sys/class/power_supply/BAT*/{capacity,status}
// A missing tool hides its indicator instead of failing.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

class SystemTray extends StatefulWidget {
  const SystemTray({super.key, this.poll = true});

  /// Whether to poll volume/network/battery. Widget tests pass false to
  /// avoid spawning processes; the clock keeps running either way.
  final bool poll;

  @override
  State<SystemTray> createState() => _SystemTrayState();
}

class _SystemTrayState extends State<SystemTray> {
  Timer? _clockTimer;
  Timer? _volumeTimer;
  Timer? _networkTimer;
  Timer? _batteryTimer;

  String _clock = _formatClock(DateTime.now());
  double? _volume; // 0..1, null = unknown / wpctl missing
  bool _muted = false;
  IconData? _networkIcon;
  String _networkTooltip = '';
  int? _batteryPercent;
  bool _batteryCharging = false;

  static String _formatClock(DateTime now) {
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  void initState() {
    super.initState();
    // Re-render only when the displayed minute actually changes.
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final next = _formatClock(DateTime.now());
      if (next != _clock && mounted) {
        setState(() => _clock = next);
      }
    });
    if (widget.poll) {
      _readVolume();
      _readNetwork();
      _readBattery();
      _volumeTimer =
          Timer.periodic(const Duration(seconds: 3), (_) => _readVolume());
      _networkTimer =
          Timer.periodic(const Duration(seconds: 10), (_) => _readNetwork());
      _batteryTimer =
          Timer.periodic(const Duration(seconds: 30), (_) => _readBattery());
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _volumeTimer?.cancel();
    _networkTimer?.cancel();
    _batteryTimer?.cancel();
    super.dispose();
  }

  Future<void> _readVolume() async {
    try {
      final result =
          await Process.run('wpctl', ['get-volume', '@DEFAULT_AUDIO_SINK@']);
      if (result.exitCode != 0) return;
      final line = (result.stdout as String).trim();
      final match = RegExp(r'Volume:\s*([0-9.]+)').firstMatch(line);
      if (match == null) return;
      final volume = double.tryParse(match.group(1)!);
      if (volume == null) return;
      if (mounted) {
        setState(() {
          _volume = volume.clamp(0.0, 1.0);
          _muted = line.contains('MUTED');
        });
      }
    } on ProcessException {
      // wpctl not installed: hide the indicator and stop polling it.
      _volumeTimer?.cancel();
      if (mounted && _volume != null) {
        setState(() => _volume = null);
      }
    }
  }

  Future<void> _readNetwork() async {
    try {
      final result =
          await Process.run('nmcli', ['-t', '-f', 'TYPE,STATE', 'dev']);
      if (result.exitCode != 0) return;
      final lines = (result.stdout as String)
          .split('\n')
          .where((l) => l.isNotEmpty)
          .toList();
      IconData? icon;
      var tooltip = '';
      if (lines.any((l) => l.startsWith('wifi:') && l.endsWith('connected'))) {
        icon = Icons.wifi;
        tooltip = 'Wi-Fi connected';
      } else if (lines.any((l) => l.startsWith('wifi:'))) {
        icon = Icons.wifi_off;
        tooltip = 'Wi-Fi disconnected';
      } else if (lines
          .any((l) => l.startsWith('ethernet:') && l.endsWith('connected'))) {
        icon = Icons.lan;
        tooltip = 'Ethernet connected';
      }
      if (mounted && (icon != _networkIcon || tooltip != _networkTooltip)) {
        setState(() {
          _networkIcon = icon;
          _networkTooltip = tooltip;
        });
      }
    } on ProcessException {
      // nmcli not installed: hide the indicator and stop polling it.
      _networkTimer?.cancel();
      if (mounted && _networkIcon != null) {
        setState(() => _networkIcon = null);
      }
    }
  }

  Future<void> _readBattery() async {
    final supply = Directory('/sys/class/power_supply');
    if (!supply.existsSync()) return;
    for (final entry in supply.listSync().whereType<Directory>()) {
      final name = entry.path.split('/').last;
      if (!name.startsWith('BAT')) continue;
      try {
        final capacity =
            int.parse(File('${entry.path}/capacity').readAsStringSync().trim());
        final status = File('${entry.path}/status').readAsStringSync().trim();
        if (mounted) {
          setState(() {
            _batteryPercent = capacity;
            _batteryCharging = status == 'Charging';
          });
        }
        return;
      } on FileSystemException {
        continue;
      } on FormatException {
        continue;
      }
    }
  }

  IconData _volumeIcon() {
    if (_muted || _volume == null || _volume! <= 0.0) return Icons.volume_off;
    if (_volume! < 0.5) return Icons.volume_down;
    return Icons.volume_up;
  }

  IconData _batteryIcon() {
    if (_batteryCharging) return Icons.battery_charging_full;
    if (_batteryPercent != null && _batteryPercent! < 15) {
      return Icons.battery_alert;
    }
    return Icons.battery_full;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final percent = _volume == null ? null : (_volume! * 100).round();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (percent != null)
          Tooltip(
            message: 'Volume $percent%${_muted ? ' (muted)' : ''}',
            child: Icon(
              _volumeIcon(),
              size: 20,
              color: scheme.onSurfaceVariant,
              semanticLabel: 'Volume',
            ),
          ),
        if (_networkIcon != null)
          Tooltip(
            message: _networkTooltip,
            child: Icon(
              _networkIcon,
              size: 20,
              color: scheme.onSurfaceVariant,
              semanticLabel: 'Network',
            ),
          ),
        if (_batteryPercent != null)
          Tooltip(
            message:
                'Battery $_batteryPercent%${_batteryCharging ? ' (charging)' : ''}',
            child: Icon(
              _batteryIcon(),
              size: 20,
              color: scheme.onSurfaceVariant,
              semanticLabel: 'Battery',
            ),
          ),
        Container(
          width: 1,
          height: 22,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          color: scheme.outlineVariant,
        ),
        Text(
          _clock,
          style: theme.textTheme.titleLarge?.copyWith(
            color: scheme.onSurface,
          ),
        ),
      ],
    );
  }
}
