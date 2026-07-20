/// Rough charge % for **2S Li‑ion** (e.g. 2×18650): [vEmpty] → 0 %, [vFull] → 100 %.
///
/// Returns `null` for USB power (&lt; 5 V) or invalid readings. Linear in voltage
/// only — sags under motor load, so treat as a hint, not a fuel gauge.
int? approximateBatteryPercent2S(
  double voltageVolts, {
  double vEmpty = 6.4,
  double vFull = 8.4,
}) {
  if (voltageVolts <= 0 || voltageVolts < 5.0) {
    return null;
  }
  final span = vFull - vEmpty;
  if (span <= 0) return null;
  final t = (voltageVolts - vEmpty) / span;
  return (t.clamp(0.0, 1.0) * 100.0).round();
}
