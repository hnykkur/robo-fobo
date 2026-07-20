import 'package:shared_preferences/shared_preferences.dart';

/// Persists teleop session bits so the same robot can be resumed after app or
/// robot restarts.
class RobotPrefs {
  RobotPrefs._();

  static const _keyRobotId = 'robot_id';
  static const _keyLedR = 'led_r';
  static const _keyLedG = 'led_g';
  static const _keyLedB = 'led_b';

  /// Preferred robot number 1–4 (BLE: 1-Ronaldo … 4-EidurSmari).
  static Future<int?> loadRobotId() async {
    final p = await SharedPreferences.getInstance();
    final id = p.getInt(_keyRobotId);
    if (id == null || id < 1 || id > 4) return null;
    return id;
  }

  static Future<void> saveRobotId(int id) async {
    if (id < 1 || id > 4) return;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_keyRobotId, id);
  }

  static Future<(int, int, int)?> loadLedRgb() async {
    final p = await SharedPreferences.getInstance();
    if (!p.containsKey(_keyLedR)) return null;
    return (
      p.getInt(_keyLedR) ?? 0,
      p.getInt(_keyLedG) ?? 0,
      p.getInt(_keyLedB) ?? 0,
    );
  }

  static Future<void> saveLedRgb(int r, int g, int b) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_keyLedR, r.clamp(0, 255));
    await p.setInt(_keyLedG, g.clamp(0, 255));
    await p.setInt(_keyLedB, b.clamp(0, 255));
  }
}
