/// Same presets as `teleop_keyboard.py` (number keys 0–8).
typedef LedPreset = ({String label, int r, int g, int b});

const List<LedPreset> kLedPresets = <LedPreset>[
  (label: 'Off', r: 0, g: 0, b: 0),
  (label: 'W', r: 255, g: 255, b: 255),
  (label: 'R', r: 255, g: 0, b: 0),
  (label: 'G', r: 0, g: 255, b: 0),
  (label: 'B', r: 0, g: 0, b: 255),
  (label: 'Y', r: 255, g: 255, b: 0),
  (label: 'C', r: 0, g: 255, b: 255),
  (label: 'M', r: 255, g: 0, b: 255),
  (label: 'A', r: 255, g: 80, b: 0),
];

/// Maps a sampled RGB (e.g. telemetry collar pixel) to the nearest preset.
/// Very dim colors snap to Off so noise does not pick a random hue.
LedPreset closestLedPreset(int r, int g, int b) {
  int byte(int v) {
    if (v < 0) return 0;
    if (v > 255) return 255;
    return v;
  }

  r = byte(r);
  g = byte(g);
  b = byte(b);
  const dim = 8;
  if (r <= dim && g <= dim && b <= dim) {
    return kLedPresets.first;
  }
  LedPreset best = kLedPresets.first;
  var bestD = double.infinity;
  for (final p in kLedPresets) {
    final dr = r - p.r;
    final dg = g - p.g;
    final db = b - p.b;
    final d = (dr * dr + dg * dg + db * db).toDouble();
    if (d < bestD) {
      bestD = d;
      best = p;
    }
  }
  return best;
}
