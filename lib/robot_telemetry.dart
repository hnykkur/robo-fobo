import 'dart:typed_data';

/// Parsed `BIN_STREAM_USER` (0x05) payload from the robot.
///
/// Firmware v3 layout: version, uptime ms (BE), voltage decivolts, R, G, B,
/// RSSI encoding (255 = N/A on BLE), free heap (BE).
class RobotTelemetry {
  const RobotTelemetry({
    required this.formatVersion,
    required this.uptimeMs,
    required this.voltageVolts,
    this.ledR,
    this.ledG,
    this.ledB,
    this.wifiRssiDbm,
    this.freeHeapBytes,
  });

  final int formatVersion;
  final int uptimeMs;
  final double voltageVolts;

  /// Collar sample (first pixel); null if format has no RGB.
  final int? ledR;
  final int? ledG;
  final int? ledB;

  /// dBm, or null if unknown (firmware sends 0xFF on BLE).
  final int? wifiRssiDbm;

  /// ESP32 free heap bytes; null if not in payload.
  final int? freeHeapBytes;
}

const int _binStreamUser = 0x05;

/// Verifies framing and checksum; returns null if invalid or not a user packet.
///
/// [hasAddress] must match firmware `bin_stream_enable_address` (false for BLE).
RobotTelemetry? parseTelemetryDatagram(
  Uint8List raw, {
  bool hasAddress = false,
}) {
  if (raw.length < 6) return null;
  if (raw[0] != 0xff || raw[1] != 0xaa) return null;
  var i = 2;
  if (hasAddress) {
    if (raw.length < 7) return null;
    i++; // dest
  }
  final type = raw[i++];
  final size = raw[i++];
  if (raw.length < i + size + 1) return null;
  final payload = raw.sublist(i, i + size);
  i += size;
  final checksum = raw[i];
  var sum = 0;
  for (final b in payload) {
    sum = (sum + b) & 0xff;
  }
  if (checksum != sum) return null;
  if (type != _binStreamUser) return null;
  return parseTelemetryPayload(payload);
}

/// Inner payload only (after type/size in the bin stream).
RobotTelemetry? parseTelemetryPayload(Uint8List p) {
  if (p.length < 6) return null;
  final ver = p[0];
  final uptimeMs = (p[1] << 24) | (p[2] << 16) | (p[3] << 8) | p[4];
  final voltageVolts = p[5] / 10.0;

  if (ver < 3 || p.length < 14) {
    return RobotTelemetry(
      formatVersion: ver,
      uptimeMs: uptimeMs,
      voltageVolts: voltageVolts,
    );
  }

  final r = p[6];
  final g = p[7];
  final b = p[8];
  final rssiEnc = p[9];
  final heap = (p[10] << 24) | (p[11] << 16) | (p[12] << 8) | p[13];

  int? rssi;
  if (rssiEnc != 255) {
    rssi = rssiEnc - 128;
  }

  return RobotTelemetry(
    formatVersion: ver,
    uptimeMs: uptimeMs,
    voltageVolts: voltageVolts,
    ledR: r,
    ledG: g,
    ledB: b,
    wifiRssiDbm: rssi,
    freeHeapBytes: heap,
  );
}
