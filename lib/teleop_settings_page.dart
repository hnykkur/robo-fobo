import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'app_assets.dart';
import 'battery_estimate.dart';
import 'disco_songs.dart';
import 'led_presets.dart';
import 'robot_ble.dart';
import 'robot_telemetry.dart';

/// BLE connect, speed limits, quick robot select, and LED / disco controls.
class TeleopSettingsPage extends StatefulWidget {
  const TeleopSettingsPage({
    super.key,
    required this.robotId,
    required this.connecting,
    required this.connected,
    this.connectedName,
    required this.maxLinear,
    required this.maxAngular,
    required this.maxTransAccel,
    required this.maxRotAccel,
    required this.discoActive,
    required this.discoSound,
    required this.discoDance,
    required this.discoSong,
    required this.onMaxLinearChanged,
    required this.onMaxAngularChanged,
    required this.onMaxTransAccelChanged,
    required this.onMaxRotAccelChanged,
    required this.onDiscoSoundChanged,
    required this.onDiscoDanceChanged,
    required this.onDiscoSongChanged,
    required this.onDiscoChanged,
    required this.onLedPreset,
    required this.onSelectRobot,
    required this.onScanAndConnect,
    required this.onDisconnect,
    required this.scanRobots,
    this.fetchRobotTelemetry,
    required this.ledPresetListenable,
    required this.robotAccentByIdListenable,
    this.onRobotLedRgb,
  });

  final int robotId;
  final bool connecting;
  final bool connected;
  final String? connectedName;
  final double maxLinear;
  final double maxAngular;
  final double maxTransAccel;
  final double maxRotAccel;
  final bool discoActive;
  final bool discoSound;
  final bool discoDance;
  final DiscoSong discoSong;
  final ValueChanged<double> onMaxLinearChanged;
  final ValueChanged<double> onMaxAngularChanged;
  final ValueChanged<double> onMaxTransAccelChanged;
  final ValueChanged<double> onMaxRotAccelChanged;
  final ValueChanged<bool> onDiscoSoundChanged;
  final ValueChanged<bool> onDiscoDanceChanged;
  final ValueChanged<DiscoSong> onDiscoSongChanged;
  final ValueChanged<bool> onDiscoChanged;
  final ValueChanged<LedPreset> onLedPreset;
  final ValueChanged<int> onSelectRobot;
  final Future<void> Function() onScanAndConnect;
  final Future<void> Function() onDisconnect;
  final Future<Map<int, ScanResult>> Function({Duration timeout}) scanRobots;

  final Future<RobotTelemetry?> Function()? fetchRobotTelemetry;
  final ValueListenable<LedPreset?> ledPresetListenable;
  final ValueListenable<Map<int, Color>> robotAccentByIdListenable;
  final void Function(int r, int g, int b)? onRobotLedRgb;

  @override
  State<TeleopSettingsPage> createState() => _TeleopSettingsPageState();
}

class _TeleopSettingsPageState extends State<TeleopSettingsPage> {
  late double _maxLinear;
  late double _maxAngular;
  late double _maxTransAccel;
  late double _maxRotAccel;

  RobotTelemetry? _telemetry;
  bool _telemetryLoading = false;
  String? _telemetryWarning;
  bool _busy = false;
  bool _scanning = false;
  Map<int, ScanResult> _scanHits = {};
  late int _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.robotId;
    _maxLinear = widget.maxLinear;
    _maxAngular = widget.maxAngular;
    _maxTransAccel = widget.maxTransAccel;
    _maxRotAccel = widget.maxRotAccel;
    if (widget.fetchRobotTelemetry != null) {
      _telemetryLoading = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshTelemetry();
      unawaited(_runScan());
    });
  }

  @override
  void didUpdateWidget(TeleopSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.robotId != oldWidget.robotId) {
      _selectedId = widget.robotId;
    }
    if (widget.maxLinear != oldWidget.maxLinear) {
      _maxLinear = widget.maxLinear;
    }
    if (widget.maxAngular != oldWidget.maxAngular) {
      _maxAngular = widget.maxAngular;
    }
    if (widget.maxTransAccel != oldWidget.maxTransAccel) {
      _maxTransAccel = widget.maxTransAccel;
    }
    if (widget.maxRotAccel != oldWidget.maxRotAccel) {
      _maxRotAccel = widget.maxRotAccel;
    }
    if (widget.robotId != oldWidget.robotId ||
        widget.connected != oldWidget.connected) {
      unawaited(_refreshTelemetry());
    }
  }

  Future<void> _runScan() async {
    setState(() => _scanning = true);
    try {
      final hits = await widget.scanRobots();
      if (!mounted) return;
      setState(() => _scanHits = hits);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _refreshTelemetry() async {
    final fetch = widget.fetchRobotTelemetry;
    if (fetch == null) return;
    if (!widget.connected) {
      setState(() {
        _telemetryLoading = false;
        _telemetryWarning = 'Not connected.';
      });
      return;
    }
    setState(() {
      _telemetryLoading = true;
      _telemetryWarning = null;
    });
    try {
      final t = await fetch();
      if (!mounted) return;
      setState(() {
        _telemetryLoading = false;
        if (t != null) {
          _telemetry = t;
          _telemetryWarning = null;
        } else {
          _telemetryWarning = 'Status refresh failed.';
        }
      });
      if (t != null) {
        final r = t.ledR;
        final g = t.ledG;
        final b = t.ledB;
        if (r != null && g != null && b != null) {
          widget.onRobotLedRgb?.call(r, g, b);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _telemetryLoading = false;
        _telemetryWarning = 'Refresh error: $e';
      });
    }
  }

  Widget _sliderTrailingValue(String value) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 52,
      child: Text(
        value,
        textAlign: TextAlign.right,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusText = widget.connecting
        ? 'Connecting to ${robotBleName(_selectedId)}…'
        : widget.connected
            ? 'Connected to ${widget.connectedName ?? robotBleName(_selectedId)}'
            : 'Not connected';

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text('Settings'),
            Image.asset(
              kAppLogoAsset,
              height: 34,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
          ],
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [
          Text('Robot (BLE)', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(
            statusText,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          ListenableBuilder(
            listenable: widget.robotAccentByIdListenable,
            builder: (context, _) {
              final accents = widget.robotAccentByIdListenable.value;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final id in [1, 2, 3, 4])
                    Builder(
                      builder: (context) {
                        final accent = accents[id];
                        final seen = _scanHits.containsKey(id);
                        final selected = _selectedId == id;
                        final style = OutlinedButton.styleFrom(
                          foregroundColor: accent,
                          backgroundColor: selected
                              ? (accent ?? Theme.of(context).colorScheme.primary)
                                  .withValues(alpha: 0.18)
                              : accent?.withValues(alpha: 0.12),
                          side: BorderSide(
                            color: selected
                                ? (accent ??
                                    Theme.of(context).colorScheme.primary)
                                : (accent?.withValues(alpha: 0.65) ??
                                    Theme.of(context).colorScheme.outline),
                            width: selected ? 2 : 1,
                          ),
                        );
                        return OutlinedButton(
                          style: style,
                          onPressed: () {
                            setState(() => _selectedId = id);
                            widget.onSelectRobot(id);
                          },
                          child: Text(
                            seen
                                ? '${robotBleName(id)} ·'
                                : robotBleName(id),
                          ),
                        );
                      },
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: (_busy || _scanning)
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          try {
                            await _runScan();
                            await widget.onScanAndConnect();
                            if (mounted) await _refreshTelemetry();
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                  icon: _scanning || widget.connecting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bluetooth_searching, size: 20),
                  label: Text(
                    widget.connecting
                        ? 'Connecting…'
                        : _scanning
                            ? 'Scanning…'
                            : 'Scan & connect',
                  ),
                ),
              ),
              if (widget.connected) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          try {
                            await widget.onDisconnect();
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                  child: const Text('Disconnect'),
                ),
              ],
            ],
          ),
          if (widget.fetchRobotTelemetry != null) ...[
            const SizedBox(height: 20),
            Text('Robot status', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            _buildTelemetryCard(context),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              const SizedBox(width: 130, child: Text('Max move (m/s)')),
              Expanded(
                child: Slider(
                  value: _maxLinear,
                  min: 0.1,
                  max: 0.6,
                  divisions: 10,
                  label: _maxLinear.toStringAsFixed(2),
                  onChanged: (v) {
                    setState(() => _maxLinear = v);
                    widget.onMaxLinearChanged(v);
                  },
                ),
              ),
              _sliderTrailingValue(_maxLinear.toStringAsFixed(2)),
            ],
          ),
          Row(
            children: [
              const SizedBox(width: 130, child: Text('Max turn (rad/s)')),
              Expanded(
                child: Slider(
                  value: _maxAngular,
                  min: 0.2,
                  max: 9.0,
                  divisions: 88,
                  label: _maxAngular.toStringAsFixed(2),
                  onChanged: (v) {
                    setState(() => _maxAngular = v);
                    widget.onMaxAngularChanged(v);
                  },
                ),
              ),
              _sliderTrailingValue(_maxAngular.toStringAsFixed(2)),
            ],
          ),
          Row(
            children: [
              const SizedBox(
                width: 130,
                child: Text('Move accel (m/s²)'),
              ),
              Expanded(
                child: Slider(
                  value: _maxTransAccel,
                  min: 0.5,
                  max: 25.0,
                  divisions: 49,
                  label: _maxTransAccel.toStringAsFixed(1),
                  onChanged: (v) {
                    setState(() => _maxTransAccel = v);
                    widget.onMaxTransAccelChanged(v);
                  },
                ),
              ),
              _sliderTrailingValue(_maxTransAccel.toStringAsFixed(1)),
            ],
          ),
          Row(
            children: [
              const SizedBox(
                width: 130,
                child: Text('Turn accel (rad/s²)'),
              ),
              Expanded(
                child: Slider(
                  value: _maxRotAccel,
                  min: 1.0,
                  max: 120.0,
                  divisions: 119,
                  label: _maxRotAccel.round().toString(),
                  onChanged: (v) {
                    setState(() => _maxRotAccel = v);
                    widget.onMaxRotAccelChanged(v);
                  },
                ),
              ),
              _sliderTrailingValue(_maxRotAccel.round().toString()),
            ],
          ),
          const SizedBox(height: 16),
          Text('LEDs', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: widget.ledPresetListenable,
            builder: (context, _) {
              final selected = widget.ledPresetListenable.value;
              return Wrap(
                spacing: 6,
                runSpacing: 8,
                children: [
                  for (final p in kLedPresets)
                    ChoiceChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (p.r == 0 && p.g == 0 && p.b == 0)
                            const Icon(Icons.block, size: 18)
                          else
                            CircleAvatar(
                              backgroundColor:
                                  Color.fromARGB(255, p.r, p.g, p.b),
                              radius: 8,
                            ),
                          const SizedBox(width: 6),
                          Text(p.label),
                        ],
                      ),
                      selected: selected == p,
                      onSelected: (_) => widget.onLedPreset(p),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          FilterChip(
            label: const Text('Disco (128 BPM)'),
            selected: widget.discoActive,
            onSelected: widget.onDiscoChanged,
          ),
          SwitchListTile(
            title: const Text('Disco sound'),
            value: widget.discoSound,
            onChanged: widget.onDiscoSoundChanged,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButtonFormField<DiscoSong>(
              initialValue: widget.discoSong,
              decoration: const InputDecoration(
                labelText: 'Disco song',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final song in DiscoSong.values)
                  DropdownMenuItem(
                    value: song,
                    child: Text(song.label),
                  ),
              ],
              onChanged: (song) {
                if (song != null) widget.onDiscoSongChanged(song);
              },
            ),
          ),
          SwitchListTile(
            title: const Text('Disco dance'),
            value: widget.discoDance,
            onChanged: widget.onDiscoDanceChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryCard(BuildContext context) {
    final theme = Theme.of(context);

    if (_telemetryLoading && _telemetry == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 16),
              Text('Fetching status…'),
            ],
          ),
        ),
      );
    }

    final tel = _telemetry;
    final placeholder = tel == null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_telemetryLoading && tel != null) ...[
              const LinearProgressIndicator(minHeight: 3),
              const SizedBox(height: 10),
            ],
            _telemetryLinkBlock(theme, placeholder),
            const SizedBox(height: 14),
            _telemetryBatteryRow(theme, tel, placeholder),
            const SizedBox(height: 12),
            _telemetryLedRow(theme, tel, placeholder),
            if (placeholder) ...[
              const SizedBox(height: 8),
              Text(
                'Free heap —',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                tel.freeHeapBytes != null
                    ? 'Free heap ${tel.freeHeapBytes} bytes'
                    : 'Free heap —',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tel.freeHeapBytes == null
                      ? theme.colorScheme.onSurfaceVariant
                      : null,
                ),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              placeholder
                  ? 'Uptime —'
                  : 'Uptime ${Duration(milliseconds: tel.uptimeMs).inMinutes} min (${tel.uptimeMs} ms)',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _telemetryLoading ? null : _refreshTelemetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
              ),
            ),
            if (_telemetryWarning != null) ...[
              const SizedBox(height: 4),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _telemetryWarning!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _telemetryLinkBlock(ThemeData theme, bool placeholder) {
    final cs = theme.colorScheme;
    final connected = widget.connected;
    return Row(
      children: [
        Icon(
          connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
          size: 32,
          color: connected ? cs.primary : cs.outline,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bluetooth',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              Text(
                connected
                    ? (widget.connectedName ?? robotBleName(widget.robotId))
                    : 'Disconnected',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: connected ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
              Text(
                placeholder ? 'No telemetry yet' : 'Link OK',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _telemetryBatteryRow(
    ThemeData theme,
    RobotTelemetry? tel,
    bool placeholder,
  ) {
    if (placeholder) {
      return Row(
        children: [
          Icon(Icons.battery_unknown, color: theme.colorScheme.outline),
          const SizedBox(width: 8),
          Text(
            'Battery — V',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }
    final t = tel!;
    final lowBatt =
        t.voltageVolts > 0 && t.voltageVolts < 6.4 && t.voltageVolts >= 5.0;
    final battPct = approximateBatteryPercent2S(t.voltageVolts);
    return Row(
      children: [
        Icon(
          lowBatt ? Icons.battery_alert : Icons.battery_std,
          color: lowBatt ? theme.colorScheme.error : null,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            battPct != null
                ? 'Battery ${t.voltageVolts.toStringAsFixed(1)} V (~$battPct%)'
                : 'Battery ${t.voltageVolts.toStringAsFixed(1)} V',
            style: theme.textTheme.titleMedium?.copyWith(
              color: lowBatt ? theme.colorScheme.error : null,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (t.voltageVolts > 0 && t.voltageVolts < 5.0)
          Text('USB', style: theme.textTheme.labelSmall),
      ],
    );
  }

  Widget _telemetryLedRow(
    ThemeData theme,
    RobotTelemetry? tel,
    bool placeholder,
  ) {
    if (placeholder || tel == null || tel.ledR == null) {
      return Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Icon(Icons.help_outline, color: theme.colorScheme.outline),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'LED collar —',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    }
    final t = tel;
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Color.fromARGB(255, t.ledR!, t.ledG!, t.ledB!),
            shape: BoxShape.circle,
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'LED collar (sample)  ${t.ledR}, ${t.ledG}, ${t.ledB}',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
