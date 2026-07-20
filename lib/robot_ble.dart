import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// Nordic UART–style UUIDs matching firmware `config.h`.
const String kBleServiceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
const String kBleRxUuid = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
const String kBleTxUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

/// BLE display / advertise names for robot ids 1–4 (must match firmware).
const List<String> kRobotBleNames = [
  '1-Ronaldo',
  '2-Haaland',
  '3-Messi',
  '4-EidurSmari',
];

String robotBleName(int id) {
  if (id < 1 || id > 4) return 'Unknown';
  return kRobotBleNames[id - 1];
}

bool isRobotBleName(String? name) => robotIdFromBleName(name) != null;

int? robotIdFromBleName(String? name) {
  if (name == null) return null;
  final n = name.trim();
  for (var i = 0; i < kRobotBleNames.length; i++) {
    if (kRobotBleNames[i] == n) return i + 1;
  }
  return null;
}

Future<bool> ensureBlePermissions() async {
  if (kIsWeb) return false;
  if (defaultTargetPlatform == TargetPlatform.android) {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    final scanOk = statuses[Permission.bluetoothScan]?.isGranted ?? false;
    final connectOk = statuses[Permission.bluetoothConnect]?.isGranted ?? false;
    return scanOk && connectOk;
  }
  // iOS: CoreBluetooth prompts via NSBluetoothAlwaysUsageDescription.
  return true;
}

/// BLE link to one robot (write RX, notify TX).
class RobotBle {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _rx;
  BluetoothCharacteristic? _tx;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  final _rxBuffer = BytesBuilder(copy: false);
  final _inbound = StreamController<Uint8List>.broadcast();

  final List<Completer<Uint8List?>> _waiters = [];
  Completer<void>? _scanCancel;

  bool get isConnected =>
      _device != null &&
      _rx != null &&
      _tx != null &&
      (_device?.isConnected ?? false);

  String? get connectedName => _device?.platformName;
  int? get connectedRobotId => robotIdFromBleName(connectedName);

  Stream<Uint8List> get packets => _inbound.stream;

  Future<bool> get isBluetoothOn async {
    try {
      return await FlutterBluePlus.isSupported &&
          FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on;
    } catch (_) {
      return false;
    }
  }

  /// Scan for 1-Ronaldo…4-EidurSmari. Returns map id → device.
  ///
  /// If [preferId] is set, returns as soon as that robot is seen (still collects
  /// others seen so far). Call [cancelScan] to abort early.
  Future<Map<int, ScanResult>> scanRobots({
    Duration timeout = const Duration(seconds: 5),
    int? preferId,
  }) async {
    final found = <int, ScanResult>{};
    if (!await FlutterBluePlus.isSupported) return found;
    if (!await ensureBlePermissions()) {
      throw StateError('Bluetooth permission denied');
    }

    await FlutterBluePlus.stopScan();
    final done = Completer<void>();
    _scanCancel = done;

    await FlutterBluePlus.startScan(
      timeout: timeout,
      androidUsesFineLocation: false,
    );

    final sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final name = r.advertisementData.advName.isNotEmpty
            ? r.advertisementData.advName
            : r.device.platformName;
        final id = robotIdFromBleName(name);
        if (id == null) continue;
        final prev = found[id];
        if (prev == null || r.rssi > prev.rssi) {
          found[id] = r;
        }
        if (preferId != null &&
            found.containsKey(preferId) &&
            !done.isCompleted) {
          done.complete();
        }
      }
    });

    try {
      await Future.any([
        Future<void>.delayed(timeout),
        done.future,
      ]);
    } finally {
      await FlutterBluePlus.stopScan();
      await sub.cancel();
      if (identical(_scanCancel, done)) {
        _scanCancel = null;
      }
    }
    return found;
  }

  /// Abort an in-progress [scanRobots] (e.g. user switched robots).
  Future<void> cancelScan() async {
    final c = _scanCancel;
    if (c != null && !c.isCompleted) {
      c.complete();
    }
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  Future<void> connect(BluetoothDevice device) async {
    await disconnect();
    _device = device;

    _connSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _clearChars();
      }
    });

    await device.connect(license: License.nonprofit, autoConnect: false);
    try {
      await device.requestMtu(247);
    } catch (e, st) {
      debugPrint('BLE MTU request: $e\n$st');
    }

    final services = await device.discoverServices();
    BluetoothCharacteristic? rx;
    BluetoothCharacteristic? tx;
    for (final s in services) {
      if (s.uuid.str128.toLowerCase() != kBleServiceUuid) continue;
      for (final c in s.characteristics) {
        final u = c.uuid.str128.toLowerCase();
        if (u == kBleRxUuid) rx = c;
        if (u == kBleTxUuid) tx = c;
      }
    }
    if (rx == null || tx == null) {
      await disconnect();
      throw StateError('Robot BLE UART characteristics not found');
    }
    _rx = rx;
    _tx = tx;

    await tx.setNotifyValue(true);
    _notifySub = tx.onValueReceived.listen(_onNotify);
  }

  /// Connect to robot [id] (1–4), scanning if needed.
  Future<void> connectToRobotId(int id) async {
    final name = robotBleName(id);
    final found = await scanRobots(preferId: id);
    final hit = found[id];
    if (hit == null) {
      throw StateError('Robot $name not found (is it powered on?)');
    }
    await connect(hit.device);
  }

  void _onNotify(List<int> data) {
    if (data.isEmpty) return;
    _rxBuffer.add(Uint8List.fromList(data));
    _drainFrames();
  }

  void _drainFrames() {
    final buf = _rxBuffer.takeBytes();
    var i = 0;
    while (i + 5 <= buf.length) {
      if (buf[i] != 0xff || buf[i + 1] != 0xaa) {
        i++;
        continue;
      }
      final size = buf[i + 3];
      final frameLen = 2 + 1 + 1 + size + 1;
      if (i + frameLen > buf.length) {
        _rxBuffer.add(buf.sublist(i));
        return;
      }
      final frame = Uint8List.fromList(buf.sublist(i, i + frameLen));
      i += frameLen;
      _inbound.add(frame);
      if (_waiters.isNotEmpty) {
        final c = _waiters.removeAt(0);
        if (!c.isCompleted) c.complete(frame);
      }
    }
    if (i < buf.length) {
      _rxBuffer.add(buf.sublist(i));
    }
  }

  Future<void> send(Uint8List data) async {
    final rx = _rx;
    if (rx == null || !isConnected) return;
    // Control packets are small; never use allowLongWrite — on Android/iOS it
    // cannot be combined with withoutResponse and throws, which was killing
    // the link and causing reconnect loops.
    final noRsp = rx.properties.writeWithoutResponse;
    await rx.write(data, withoutResponse: noRsp);
  }

  Future<Uint8List?> receiveOnce(Duration timeout) async {
    final c = Completer<Uint8List?>();
    _waiters.add(c);
    try {
      return await c.future.timeout(timeout, onTimeout: () {
        _waiters.remove(c);
        return null;
      });
    } catch (_) {
      _waiters.remove(c);
      return null;
    }
  }

  void drain() {
    _rxBuffer.clear();
    for (final w in List<Completer<Uint8List?>>.from(_waiters)) {
      if (!w.isCompleted) w.complete(null);
    }
    _waiters.clear();
  }

  void _clearChars() {
    _rx = null;
    _tx = null;
  }

  Future<void> disconnect() async {
    drain();
    await _notifySub?.cancel();
    _notifySub = null;
    await _connSub?.cancel();
    _connSub = null;
    _clearChars();
    final d = _device;
    _device = null;
    if (d != null) {
      try {
        await d.disconnect();
      } catch (e, st) {
        debugPrint('BLE disconnect: $e\n$st');
      }
    }
  }

  Future<void> close() => disconnect();
}
