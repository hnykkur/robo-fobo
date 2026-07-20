import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'app_branding.dart';
import 'disco_songs.dart';
import 'splash_screen.dart';
import 'led_presets.dart';
import 'robot_ble.dart';
import 'robot_prefs.dart';
import 'robot_telemetry.dart';
import 'rsk_packets.dart';
import 'teleop_settings_page.dart';
import 'widgets/analog_joystick.dart';
import 'widgets/rotation_bar.dart';

enum _LinkState { unknown, online, lost }

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // FBP defaults to LogLevel.debug and floods the console with GATT chatter.
  FlutterBluePlus.setLogLevel(LogLevel.warning);
  runApp(const RskTeleopApp());
}

class RskTeleopApp extends StatefulWidget {
  const RskTeleopApp({super.key});

  @override
  State<RskTeleopApp> createState() => _RskTeleopAppState();
}

class _RskTeleopAppState extends State<RskTeleopApp> {
  var _showSplash = true;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showSplash = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppDisplayName,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
      ),
      home: _showSplash ? const SplashScreen() : const TeleopPage(),
    );
  }
}

class TeleopPage extends StatefulWidget {
  const TeleopPage({super.key});

  @override
  State<TeleopPage> createState() => _TeleopPageState();
}

class _TeleopPageState extends State<TeleopPage> with WidgetsBindingObserver {
  static const _sendMs = 20;
  static const _connectBanner =
      'Open Settings and pick a robot to connect.';

  static const _discoBpm = 128.0;

  static const _discoDanceSteps = <(double, double, double, int)>[
    (0.0, 0.20, -0.70, 4),
    (0.0, -0.20, -0.70, 4),
    (0.0, 0.20, 0.70, 4),
    (0.0, -0.20, 0.70, 4),
    (0.0, 0.0, -0.85, 2),
    (0.0, 0.0, 0.85, 2),
    (0.0, 0.0, -0.85, 2),
    (0.0, 0.0, 0.85, 2),
    (0.0, 0.35, 0.0, 2),
    (0.0, -0.35, 0.0, 2),
    (0.0, 0.35, 0.45, 2),
    (0.0, -0.35, -0.45, 2),
    (0.0, 0.0, -0.90, 8),
    (0.0, 0.0, 0.90, 8),
    (0.30, 0.0, 0.40, 2),
    (-0.30, 0.0, -0.40, 2),
    (0.30, 0.0, 0.40, 2),
    (-0.30, 0.0, -0.40, 2),
    (0.0, 0.0, 0.0, 4),
  ];

  final _ble = RobotBle();
  final _rnd = math.Random();

  /// Preferred robot 1–4 (BLE: 1-Ronaldo / 2-Haaland / 3-Messi / 4-EidurSmari).
  int _robotId = 1;
  bool _connecting = false;
  /// Bumped to cancel an in-flight connect when the user picks another robot.
  int _connectGen = 0;
  /// When false, do not scan/connect unless the user picks a robot.
  bool _autoReconnect = false;

  double _maxLinear = 0.6;
  double _maxAngular = 4.0;
  double _maxTransAccel = 1.0;
  double _maxRotAccel = 10.0;

  double _vx = 0;
  double _vy = 0;
  double _omega = 0;

  double _nx = 0;
  double _ny = 0;
  double _nTurn = 0;

  String? _error;
  String? _statusBanner;

  Timer? _timer;
  Timer? _discoTimer;
  Timer? _discoMelodyTimer;
  Timer? _ledSyncDebounce;
  Timer? _kickCooldownTimer;
  Timer? _healthTimer;
  bool _discoActive = false;
  bool _discoSound = false;
  bool _discoDanceEnabled = true;
  DiscoSong _discoSong = DiscoSong.funkyTown;
  int _discoMelodyIndex = 0;
  DateTime? _discoStartedAt;

  static const _kickCooldownSecs = 3;
  int _kickCooldownLeft = 0;

  _LinkState _linkState = _LinkState.unknown;
  int? _lastUptimeMs;
  int _missedProbes = 0;
  bool _healthProbeBusy = false;
  bool _reconnectBusy = false;
  static const _healthInterval = Duration(seconds: 2);
  static const _missesBeforeLost = 2;

  Color _joystickAccent = const Color(0xFF1565C0);
  final ValueNotifier<LedPreset?> _ledPresetSelection =
      ValueNotifier<LedPreset?>(null);
  final ValueNotifier<Map<int, Color>> _robotAccentById =
      ValueNotifier<Map<int, Color>>(<int, Color>{});

  static Color _accentFromPreset(LedPreset p) {
    if (p.r == 0 && p.g == 0 && p.b == 0) {
      return const Color(0xFF78909C);
    }
    return Color.fromARGB(255, p.r, p.g, p.b);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_restoreSessionAndStart());
  }

  Future<void> _restoreSessionAndStart() async {
    final savedId = await RobotPrefs.loadRobotId();
    if (!mounted) return;
    // Remember last pick for Settings highlight only — do not auto-connect.
    if (savedId != null) {
      _robotId = savedId;
    }

    final savedLed = await RobotPrefs.loadLedRgb();
    if (!mounted) return;
    if (savedLed != null) {
      final (r, g, b) = savedLed;
      _ledPresetSelection.value = closestLedPreset(r, g, b);
      setState(() => _joystickAccent = _accentFromPresetRgb(r, g, b));
    }

    await _ensureBluetoothReady();
    await _openAndStart();
    _startHealthMonitor();
    if (mounted) {
      setState(() => _error = _connectBanner);
    }
  }

  Color _accentFromPresetRgb(int r, int g, int b) {
    const dim = 8;
    if (r <= dim && g <= dim && b <= dim) {
      return const Color(0xFF78909C);
    }
    return Color.fromARGB(255, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255));
  }

  Future<void> _ensureBluetoothReady() async {
    try {
      if (!await FlutterBluePlus.isSupported) {
        if (mounted) {
          setState(() => _error = 'Bluetooth LE is not supported on this device.');
        }
        return;
      }
      await FlutterBluePlus.adapterState
          .where((s) => s == BluetoothAdapterState.on)
          .first
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Turn on Bluetooth to connect to robots.');
      }
    }
  }

  Future<void> _connectToSelectedRobot({bool force = false}) async {
    if (!force &&
        _ble.isConnected &&
        _ble.connectedRobotId == _robotId) {
      return;
    }

    final gen = ++_connectGen;
    final targetId = _robotId;

    setState(() {
      _connecting = true;
      _statusBanner = 'Connecting to ${robotBleName(targetId)}…';
      _error = null;
    });

    try {
      // Drop any prior scan/connect so a robot switch is not blocked.
      await _ble.cancelScan();
      if (gen != _connectGen) return;

      if (_ble.isConnected) {
        await _sendControlZeros();
        if (gen != _connectGen) return;
        await _ble.disconnect();
        if (gen != _connectGen) return;
      }

      await _ble.connectToRobotId(targetId);
      if (!mounted || gen != _connectGen) return;

      setState(() {
        _connecting = false;
        _statusBanner = null;
        _linkState = _LinkState.online;
        _missedProbes = 0;
        _error = null;
        _autoReconnect = true;
      });
      unawaited(_trySyncLedFromRobot());
      unawaited(_healthProbe());
    } catch (e) {
      if (!mounted || gen != _connectGen) return;
      setState(() {
        _connecting = false;
        _statusBanner = null;
        _error =
            'Could not connect to ${robotBleName(targetId)}. Pick another robot in Settings, or tap Scan & connect.';
        _linkState = _LinkState.lost;
        // Stop hammering a missing robot; user must pick / scan again.
        _autoReconnect = false;
      });
    }
  }

  Future<void> _selectRobot(int id) async {
    if (id < 1 || id > 4) return;
    if (id == _robotId && _ble.isConnected) return;

    // Invalidate any in-flight connect/scan for the previous robot.
    _connectGen++;
    _autoReconnect = true;
    _stopDisco();
    unawaited(_ble.cancelScan());

    _robotId = id;
    unawaited(RobotPrefs.saveRobotId(id));
    _lastUptimeMs = null;
    _missedProbes = 0;
    _linkState = _LinkState.unknown;
    _connecting = false;
    if (mounted) {
      setState(() {
        _statusBanner = 'Switching to ${robotBleName(id)}…';
        _error = null;
      });
    }

    // Fire-and-forget so Settings buttons stay responsive.
    unawaited(_connectToSelectedRobot(force: true));
  }

  void _startHealthMonitor() {
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(_healthInterval, (_) {
      unawaited(_healthProbe());
    });
    unawaited(_healthProbe());
  }

  Future<void> _healthProbe() async {
    if (_healthProbeBusy || !mounted || _connecting) return;
    // Idle until the user has selected a robot this session.
    if (!_autoReconnect && !_ble.isConnected) return;
    if (!_ble.isConnected) {
      _missedProbes++;
      if (_missedProbes >= _missesBeforeLost) {
        await _onLinkLost();
      }
      return;
    }

    _healthProbeBusy = true;
    try {
      final t = await _fetchRobotTelemetry();
      if (!mounted) return;

      if (t == null) {
        _missedProbes++;
        if (_missedProbes >= _missesBeforeLost) {
          await _onLinkLost();
        }
        return;
      }

      final wasLost = _linkState == _LinkState.lost ||
          (_linkState == _LinkState.unknown && _missedProbes > 0);
      final prevUptime = _lastUptimeMs;
      final rebooted = prevUptime != null && t.uptimeMs + 1500 < prevUptime;
      final justBooted = (_linkState == _LinkState.lost) && t.uptimeMs < 20000;

      _lastUptimeMs = t.uptimeMs;
      _missedProbes = 0;

      if (_linkState != _LinkState.online || _statusBanner != null) {
        setState(() {
          _linkState = _LinkState.online;
          _statusBanner = null;
        });
      } else {
        _linkState = _LinkState.online;
      }

      if (wasLost || rebooted || justBooted) {
        await _onLinkRecovered(t, rebooted: rebooted || justBooted);
      }
    } finally {
      _healthProbeBusy = false;
    }
  }

  Future<void> _onLinkLost() async {
    if (_linkState != _LinkState.lost) {
      if (mounted) {
        setState(() {
          _linkState = _LinkState.lost;
          _statusBanner = _autoReconnect
              ? 'Robot unreachable — holding stop, reconnecting to ${robotBleName(_robotId)}…'
              : 'Not connected to ${robotBleName(_robotId)}. Pick a robot in Settings.';
        });
      } else {
        _linkState = _LinkState.lost;
      }
      _resetSlew();
      await _sendControlZeros();
    }
    if (_autoReconnect) {
      await _tryReconnect();
    }
  }

  Future<void> _onLinkRecovered(
    RobotTelemetry t, {
    required bool rebooted,
  }) async {
    if (!mounted) return;
    _autoReconnect = true;
    // Robot NVS is source of truth — mirror into UI only.
    if (t.ledR != null && t.ledG != null && t.ledB != null && !_discoActive) {
      _syncLedFromRobotRgb(t.ledR!, t.ledG!, t.ledB!);
    } else if (!_discoActive) {
      unawaited(_trySyncLedFromRobot());
    }
  }

  Future<void> _tryReconnect() async {
    if (!_autoReconnect || _reconnectBusy || _connecting) return;
    _reconnectBusy = true;
    try {
      await _connectToSelectedRobot(force: true);
    } finally {
      _reconnectBusy = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_healthProbe());
      if (_autoReconnect && !_ble.isConnected) {
        unawaited(_tryReconnect());
      }
    }
  }

  Future<void> _sendControlZeros() async {
    if (!_ble.isConnected) {
      _resetSlew();
      return;
    }
    try {
      await _ble.send(
        buildControlPacket(dxMps: 0, dyMps: 0, dturnRadPerSec: 0),
      );
    } catch (e, st) {
      debugPrint('zero cmd: $e\n$st');
    }
    _resetSlew();
  }

  void _resetSlew() {
    _vx = 0;
    _vy = 0;
    _omega = 0;
  }

  Future<RobotTelemetry?> _fetchRobotTelemetry() async {
    if (!_ble.isConnected) return null;
    try {
      return await _fetchRobotTelemetryImpl().timeout(
        const Duration(seconds: 2),
        onTimeout: () => null,
      );
    } catch (_) {
      return null;
    }
  }

  Future<RobotTelemetry?> _fetchRobotTelemetryImpl() async {
    _ble.drain();
    await _ble.send(buildStatusQueryPacket());
    final raw = await _ble.receiveOnce(const Duration(milliseconds: 900));
    if (raw == null) return null;
    return parseTelemetryDatagram(raw, hasAddress: false);
  }

  Future<void> _trySyncLedFromRobot() async {
    if (!_ble.isConnected || _discoActive) return;
    for (var attempt = 0; attempt < 6; attempt++) {
      final t = await _fetchRobotTelemetryImpl();
      if (!mounted || t == null) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        continue;
      }
      final r = t.ledR;
      final g = t.ledG;
      final b = t.ledB;
      if (r == null || g == null || b == null) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        continue;
      }
      _syncLedFromRobotRgb(r, g, b);
      unawaited(RobotPrefs.saveLedRgb(r, g, b));
      return;
    }
  }

  void _syncLedFromRobotRgb(int r, int g, int b) {
    if (!mounted || _discoActive) return;
    const dim = 8;
    final off = r <= dim && g <= dim && b <= dim;
    final accent = off
        ? const Color(0xFF78909C)
        : Color.fromARGB(
            255,
            r.clamp(0, 255),
            g.clamp(0, 255),
            b.clamp(0, 255),
          );
    _ledPresetSelection.value = closestLedPreset(r, g, b);
    final next = Map<int, Color>.from(_robotAccentById.value);
    next[_robotId] = accent;
    _robotAccentById.value = next;
    setState(() => _joystickAccent = accent);
  }

  void _openSettings() {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => TeleopSettingsPage(
          robotId: _robotId,
          connecting: _connecting,
          connected: _ble.isConnected,
          connectedName: _ble.connectedName,
          maxLinear: _maxLinear,
          maxAngular: _maxAngular,
          maxTransAccel: _maxTransAccel,
          maxRotAccel: _maxRotAccel,
          discoActive: _discoActive,
          discoSound: _discoSound,
          discoDance: _discoDanceEnabled,
          discoSong: _discoSong,
          onMaxLinearChanged: (v) => setState(() => _maxLinear = v),
          onMaxAngularChanged: (v) => setState(() => _maxAngular = v),
          onMaxTransAccelChanged: (v) => setState(() => _maxTransAccel = v),
          onMaxRotAccelChanged: (v) => setState(() => _maxRotAccel = v),
          onDiscoSoundChanged: _setDiscoSound,
          onDiscoDanceChanged: _setDiscoDanceEnabled,
          onDiscoSongChanged: _setDiscoSong,
          onDiscoChanged: _setDisco,
          onLedPreset: _applyLedPreset,
          onSelectRobot: (id) => unawaited(_selectRobot(id)),
          onDisconnect: () async {
            _connectGen++;
            _autoReconnect = false;
            await _sendControlZeros();
            await _ble.cancelScan();
            await _ble.disconnect();
            if (mounted) {
              setState(() {
                _connecting = false;
                _statusBanner = null;
                _linkState = _LinkState.lost;
                _error =
                    'Disconnected. Pick a robot in Settings to connect.';
              });
            }
          },
          onScanAndConnect: () async {
            _autoReconnect = true;
            await _connectToSelectedRobot(force: true);
          },
          scanRobots: _ble.scanRobots,
          fetchRobotTelemetry: _fetchRobotTelemetry,
          ledPresetListenable: _ledPresetSelection,
          robotAccentByIdListenable: _robotAccentById,
          onRobotLedRgb: _syncLedFromRobotRgb,
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _openAndStart() async {
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(milliseconds: _sendMs),
      (_) => unawaited(_tick()),
    );
  }

  Future<void> _tick() async {
    if (!_ble.isConnected) {
      _resetSlew();
      if (_error == null &&
          !_connecting &&
          _linkState != _LinkState.lost &&
          mounted) {
        setState(() => _error = _connectBanner);
      }
      return;
    }

    if (_linkState == _LinkState.lost) {
      _resetSlew();
      try {
        await _ble.send(
          buildControlPacket(dxMps: 0, dyMps: 0, dturnRadPerSec: 0),
        );
      } catch (_) {}
      return;
    }

    const dt = _sendMs / 1000.0;
    var nx = _nx;
    var ny = _ny;
    var nTurn = _nTurn;
    if (_discoActive && _discoDanceEnabled && _discoStartedAt != null) {
      final pose = _discoDancePoseAt(
        DateTime.now().difference(_discoStartedAt!),
      );
      nx = pose.$1;
      ny = pose.$2;
      nTurn = pose.$3;
    }
    final dxDes = -ny * _maxLinear;
    final dyDes = -nx * _maxLinear;
    final dturnDes = -nTurn * _maxAngular;

    final ddx = dxDes - _vx;
    final ddy = dyDes - _vy;
    final transErr = math.sqrt(ddx * ddx + ddy * ddy);
    final maxTransStep = _maxTransAccel * dt;
    if (transErr > maxTransStep && transErr > 0) {
      final s = maxTransStep / transErr;
      _vx += ddx * s;
      _vy += ddy * s;
    } else {
      _vx = dxDes;
      _vy = dyDes;
    }

    final dw = dturnDes - _omega;
    final maxRotStep = _maxRotAccel * dt;
    if (dw.abs() > maxRotStep) {
      _omega += maxRotStep * dw.sign;
    } else {
      _omega = dturnDes;
    }

    final pkt = buildControlPacket(
      dxMps: _vx,
      dyMps: _vy,
      dturnRadPerSec: _omega,
    );

    try {
      await _ble.send(pkt);
      if (_error != null && mounted) {
        setState(() => _error = null);
      }
    } catch (e) {
      final msg = '$e';
      if (_error != msg && mounted) {
        setState(() => _error = msg);
      }
    }
  }

  (double, double, double) _discoDancePoseAt(Duration elapsed) {
    final eighthMs = 60000.0 / _discoBpm / 2.0;
    var totalEighths = 0;
    for (final step in _discoDanceSteps) {
      totalEighths += step.$4;
    }
    if (totalEighths <= 0) return (0.0, 0.0, 0.0);
    final eighthIndex =
        ((elapsed.inMilliseconds / eighthMs).floor()) % totalEighths;
    var cursor = 0;
    for (final step in _discoDanceSteps) {
      final next = cursor + step.$4;
      if (eighthIndex < next) {
        return (step.$1, step.$2, step.$3);
      }
      cursor = next;
    }
    return (0.0, 0.0, 0.0);
  }

  void _stopDiscoMelody() {
    _discoMelodyTimer?.cancel();
    _discoMelodyTimer = null;
    _discoMelodyIndex = 0;
  }

  void _scheduleDiscoMelodyNote() {
    _discoMelodyTimer?.cancel();
    if (!_discoActive || !_discoSound) return;
    if (!_ble.isConnected) return;

    final melody = _discoSong.melody;
    final (hz, units) = melody[_discoMelodyIndex % melody.length];
    _discoMelodyIndex++;
    final unitMs = 60000.0 / _discoBpm / _discoSong.durationDivisor;
    final stepMs = (unitMs * units).round().clamp(30, 4000);
    if (hz > 0) {
      final toneMs = math.max(30, (stepMs * 0.85).round());
      unawaited(() async {
        try {
          await _ble.send(
            buildBeepPacket(frequencyHz: hz, durationMs: toneMs),
          );
        } catch (e, st) {
          debugPrint('disco melody: $e\n$st');
        }
      }());
    }
    _discoMelodyTimer = Timer(Duration(milliseconds: stepMs), () {
      _scheduleDiscoMelodyNote();
    });
  }

  void _startDiscoMelody() {
    _stopDiscoMelody();
    if (!_discoActive || !_discoSound) return;
    _scheduleDiscoMelodyNote();
  }

  void _setDiscoSound(bool on) {
    setState(() => _discoSound = on);
    if (!_discoActive) return;
    if (on) {
      _startDiscoMelody();
    } else {
      _stopDiscoMelody();
    }
  }

  void _setDiscoSong(DiscoSong song) {
    if (song == _discoSong) return;
    setState(() => _discoSong = song);
    if (_discoActive && _discoSound) {
      _startDiscoMelody();
    }
  }

  void _setDiscoDanceEnabled(bool on) {
    setState(() => _discoDanceEnabled = on);
    if (!_discoActive || on) return;
    _nx = 0;
    _ny = 0;
    _nTurn = 0;
    unawaited(_sendControlZeros());
  }

  void _stopDisco() {
    final wasActive = _discoActive;
    _discoTimer?.cancel();
    _discoTimer = null;
    _stopDiscoMelody();
    _discoStartedAt = null;
    _nx = 0;
    _ny = 0;
    _nTurn = 0;
    if (_discoActive && mounted) {
      setState(() => _discoActive = false);
    } else {
      _discoActive = false;
    }
    if (wasActive && mounted) {
      unawaited(_sendControlZeros());
      unawaited(() async {
        try {
          if (_ble.isConnected) {
            await _ble.send(buildLedRestorePacket());
          }
        } catch (e, st) {
          debugPrint('disco restore LED: $e\n$st');
        }
        await _trySyncLedFromRobot();
      }());
    }
  }

  void _setDisco(bool on) {
    if (on) {
      if (!_ble.isConnected) {
        setState(() => _error = 'Connect to a robot in Settings before Disco.');
        return;
      }
      _discoTimer?.cancel();
      _stopDiscoMelody();
      _nx = 0;
      _ny = 0;
      _nTurn = 0;
      _discoStartedAt = DateTime.now();
      setState(() {
        _discoActive = true;
        _error = null;
      });
      final palette =
          kLedPresets.where((p) => p.r != 0 || p.g != 0 || p.b != 0).toList();
      final intervalMs = (60000.0 / _discoBpm).round().clamp(50, 2000);
      _discoTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
        if (!_ble.isConnected) return;
        final pick = palette[_rnd.nextInt(palette.length)];
        unawaited(() async {
          try {
            await _ble.send(
              buildLedTempPacket(r: pick.r, g: pick.g, b: pick.b),
            );
          } catch (e, st) {
            debugPrint('disco: $e\n$st');
          }
        }());
      });
      if (_discoSound) {
        _startDiscoMelody();
      }
    } else {
      _stopDisco();
    }
  }

  void _applyLedPreset(LedPreset preset) {
    _stopDisco();
    if (!_ble.isConnected) {
      setState(() => _error = 'Connect to a robot in Settings first.');
      return;
    }
    unawaited(() async {
      try {
        await _ble.send(
          buildLedPacket(r: preset.r, g: preset.g, b: preset.b),
        );
        _ledPresetSelection.value = preset;
        final accent = _accentFromPreset(preset);
        final next = Map<int, Color>.from(_robotAccentById.value);
        next[_robotId] = accent;
        _robotAccentById.value = next;
        unawaited(RobotPrefs.saveLedRgb(preset.r, preset.g, preset.b));
        if (mounted) {
          setState(() {
            _error = null;
            _joystickAccent = accent;
          });
        }
      } catch (e) {
        if (mounted) setState(() => _error = '$e');
      }
    }());
  }

  void _kick({double power = 1.0}) {
    if (_kickCooldownLeft > 0) return;
    if (!_ble.isConnected) {
      setState(() => _error = 'Connect to a robot in Settings first.');
      return;
    }
    unawaited(() async {
      try {
        await _ble.send(buildKickPacket(power: power));
        _startKickCooldown();
        if (_error != null && mounted) {
          setState(() => _error = null);
        }
      } catch (e) {
        if (mounted) setState(() => _error = '$e');
      }
    }());
  }

  void _startKickCooldown() {
    _kickCooldownTimer?.cancel();
    setState(() => _kickCooldownLeft = _kickCooldownSecs);
    _kickCooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _kickCooldownLeft -= 1;
        if (_kickCooldownLeft <= 0) {
          _kickCooldownLeft = 0;
          t.cancel();
          _kickCooldownTimer = null;
        }
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _discoTimer?.cancel();
    _discoMelodyTimer?.cancel();
    _ledSyncDebounce?.cancel();
    _kickCooldownTimer?.cancel();
    _healthTimer?.cancel();
    _ledPresetSelection.dispose();
    _robotAccentById.dispose();
    unawaited(_ble.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final linkLabel = _ble.isConnected
        ? (_ble.connectedName ?? robotBleName(_robotId))
        : _connecting
            ? robotBleName(_robotId)
            : 'Not connected';

    return Scaffold(
      appBar: AppBar(
        title: Text('$kAppDisplayName · $linkLabel'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Material(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            color:
                                Theme.of(context).colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_statusBanner != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Material(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSecondaryContainer,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _statusBanner!,
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSecondaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              FilledButton.icon(
                onPressed: _kickCooldownLeft > 0 ? null : _kick,
                icon: Icon(
                  Icons.sports_soccer,
                  size: 32,
                  color: _kickCooldownLeft > 0
                      ? Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.38)
                      : null,
                ),
                label: Text(
                  _kickCooldownLeft > 0 ? '$_kickCooldownLeft' : 'Kick',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(64),
                  padding:
                      const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
                  backgroundColor: _joystickAccent,
                  disabledBackgroundColor: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.12),
                  disabledForegroundColor: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.38),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final side = math.min(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        ) -
                        8;
                    final joySize = side.clamp(220.0, 560.0);
                    return Center(
                      child: AnalogJoystick(
                        size: joySize,
                        accentColor: _joystickAccent,
                        onChanged: (nx, ny) {
                          _nx = nx;
                          _ny = ny;
                        },
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Rotation — CCW ←    → CW',
                style: Theme.of(context).textTheme.labelMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              RotationBar(
                accentColor: _joystickAccent,
                onChanged: (t) {
                  _nTurn = t;
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
