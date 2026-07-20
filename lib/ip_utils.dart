/// Dotted-decimal IPv4 validation (each octet 0–255, exactly four parts).
bool isValidIpv4(String ip) {
  final parts = ip.trim().split('.');
  if (parts.length != 4) return false;
  for (final p in parts) {
    if (p.isEmpty) return false;
    final n = int.tryParse(p);
    if (n == null || n < 0 || n > 255) return false;
  }
  return true;
}

/// First three octets plus trailing dot, e.g. `192.168.0.` — or default if [ip] is invalid.
String subnetPrefixFromIpOrDefault(String ip, {String defaultPrefix = '192.168.0.'}) {
  final parts = ip.trim().split('.');
  if (parts.length != 4) return defaultPrefix;
  for (var i = 0; i < 3; i++) {
    final n = int.tryParse(parts[i]);
    if (n == null || n < 0 || n > 255) return defaultPrefix;
  }
  return '${parts[0]}.${parts[1]}.${parts[2]}.';
}
