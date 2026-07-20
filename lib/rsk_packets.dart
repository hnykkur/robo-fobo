import 'dart:math' as math;
import 'dart:typed_data';

/// Binary packets matching firmware `bin_stream` / `rsk/packets.py`.
/// BLE uses [includeAddress]: false (firmware `bin_stream_enable_address(0)`).

const int _cmdControl = 2;
const int _cmdBeep = 3;
const int _cmdLedsCustom = 7;
const int _cmdKick = 12;
const int _cmdStatus = 13;
const int _cmdLedsTemp = 14;
const int _cmdLedsRestore = 15;
const int _typeRobot = 80;

Uint8List _buildRobotPacket(
  Uint8List payload, {
  bool includeAddress = false,
  int destLastOctet = 0,
}) {
  var sum = 0;
  for (var i = 0; i < payload.length; i++) {
    sum = (sum + payload[i]) % 256;
  }
  final checksum = sum & 0xff;
  final out = Uint8List(
    2 + (includeAddress ? 1 : 0) + 1 + 1 + payload.length + 1,
  );
  var o = 0;
  out[o++] = 0xff;
  out[o++] = 0xaa;
  if (includeAddress) {
    out[o++] = destLastOctet & 0xff;
  }
  out[o++] = _typeRobot;
  out[o++] = payload.length;
  out.setRange(o, o + payload.length, payload);
  o += payload.length;
  out[o] = checksum;
  return out;
}

/// Movement (inverse kinematics velocities).
Uint8List buildControlPacket({
  required double dxMps,
  required double dyMps,
  required double dturnRadPerSec,
  bool includeAddress = false,
  int destLastOctet = 0,
}) {
  final dxMm = _clampInt16((1000 * dxMps).round());
  final dyMm = _clampInt16((1000 * dyMps).round());
  final dDeg = _clampInt16(
    (dturnRadPerSec * 180.0 / math.pi).round(),
  );

  final payload = Uint8List(7);
  payload[0] = _cmdControl;
  _putBe16(payload, 1, dxMm);
  _putBe16(payload, 3, dyMm);
  _putBe16(payload, 5, dDeg);
  return _buildRobotPacket(
    payload,
    includeAddress: includeAddress,
    destLastOctet: destLastOctet,
  );
}

/// RGB LEDs (0–255 each). Persists to robot NVS (team color).
Uint8List buildLedPacket({
  required int r,
  required int g,
  required int b,
  bool includeAddress = false,
  int destLastOctet = 0,
}) {
  final payload = Uint8List(4);
  payload[0] = _cmdLedsCustom;
  payload[1] = r.clamp(0, 255);
  payload[2] = g.clamp(0, 255);
  payload[3] = b.clamp(0, 255);
  return _buildRobotPacket(
    payload,
    includeAddress: includeAddress,
    destLastOctet: destLastOctet,
  );
}

/// Temporary RGB (disco / effects) — does **not** update robot NVS.
Uint8List buildLedTempPacket({
  required int r,
  required int g,
  required int b,
  bool includeAddress = false,
  int destLastOctet = 0,
}) {
  final payload = Uint8List(4);
  payload[0] = _cmdLedsTemp;
  payload[1] = r.clamp(0, 255);
  payload[2] = g.clamp(0, 255);
  payload[3] = b.clamp(0, 255);
  return _buildRobotPacket(
    payload,
    includeAddress: includeAddress,
    destLastOctet: destLastOctet,
  );
}

/// Restore display from robot NVS team color.
Uint8List buildLedRestorePacket({
  bool includeAddress = false,
  int destLastOctet = 0,
}) {
  final payload = Uint8List(1);
  payload[0] = _cmdLedsRestore;
  return _buildRobotPacket(
    payload,
    includeAddress: includeAddress,
    destLastOctet: destLastOctet,
  );
}

/// Kicker pulse. [power] is 0–1.
Uint8List buildKickPacket({
  double power = 1.0,
  bool includeAddress = false,
  int destLastOctet = 0,
}) {
  final payload = Uint8List(2);
  payload[0] = _cmdKick;
  payload[1] = (power * 100).round().clamp(0, 100);
  return _buildRobotPacket(
    payload,
    includeAddress: includeAddress,
    destLastOctet: destLastOctet,
  );
}

/// Request a single telemetry frame.
Uint8List buildStatusQueryPacket({
  bool includeAddress = false,
  int destLastOctet = 0,
}) {
  final payload = Uint8List(1);
  payload[0] = _cmdStatus;
  return _buildRobotPacket(
    payload,
    includeAddress: includeAddress,
    destLastOctet: destLastOctet,
  );
}

/// Buzzer: frequency (Hz), duration (ms).
Uint8List buildBeepPacket({
  required int frequencyHz,
  required int durationMs,
  bool includeAddress = false,
  int destLastOctet = 0,
}) {
  final payload = Uint8List(5);
  payload[0] = _cmdBeep;
  _putBe16(payload, 1, frequencyHz.clamp(0, 65535));
  _putBe16(payload, 3, durationMs.clamp(0, 65535));
  return _buildRobotPacket(
    payload,
    includeAddress: includeAddress,
    destLastOctet: destLastOctet,
  );
}

int _clampInt16(int v) => v.clamp(-32768, 32767);

void _putBe16(Uint8List buf, int offset, int v) {
  buf[offset] = (v >> 8) & 0xff;
  buf[offset + 1] = v & 0xff;
}
