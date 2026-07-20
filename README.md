# Róbó-Fóbó (RSK Teleop)

Flutter joystick controller for Robot Soccer Kit robots over **Bluetooth Low Energy** (Android + iOS). No Wi‑Fi / no router.

## Download (Android)

Grab the latest **APK** from [Releases](../../releases/latest).

On your phone: allow install from that source, then open the APK.

## Run from source

```bash
flutter pub get
flutter run
```

### Connecting

1. Flash the shared BLE firmware to each robot.
2. Set the robot number once over USB serial (`115200`): `robotid 1` … `robotid 4`  
   (reboots; advertises as **1-Ronaldo**, **2-Haaland**, **3-Messi**, **4-EidurSmari**).
3. In the app **Settings**, tap **Scan & connect**, or pick the player name.

Grant Bluetooth permissions when prompted.

## Build a release APK

```bash
flutter pub get
flutter build apk --release
```

**Output:** `build/app/outputs/flutter-apk/app-release.apk`

## Protocol

- BLE Nordic UART–style service (see robot firmware `config.h` UUIDs).
- Binary frames **without** dest address octet (firmware address mode off).
- Joystick → **dx / dy** (m/s); rotation bar → **dturn** (rad/s).

## Permissions

- **Android:** `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` (and legacy BT + location on older APIs).
- **iOS:** `NSBluetoothAlwaysUsageDescription` in `Info.plist`.
