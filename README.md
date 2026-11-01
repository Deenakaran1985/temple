# Temple Alarm – mobile app

Flutter app (Android and macOS) for the ESP32 Temple Alarm. It talks to the device through an MQTT broker (e.g. HiveMQ Cloud, free tier) and shows alarm notifications.

## Features
- Arm, disarm, panic, stop alarm, mute
- Live status: armed/disarmed, alarm zone, device online
- Pair / unpair sensor zones, pair the HC-12 remote
- Volume, stop music, test siren, say date & time (Tamil)
- Recent events and device network details
- Alarm notifications; on Android a foreground service keeps them working with the app closed

## Build
Needs Flutter 3.41+ and the Android SDK (Android Studio).

```
flutter pub get
flutter build apk --release        # build/app/outputs/flutter-apk/app-release.apk
flutter build macos --release      # on a Mac with Xcode
```

## Set up
1. On the device web page: Settings → Mobile App (MQTT Cloud) → enter the broker host, port 8883, user and password.
2. In the app: enter the Device ID (TALM-XXXXXX, shown on the device), the same broker details → Save & connect → allow notifications.
3. Android: Settings → Apps → Temple Alarm → Battery → Unrestricted.

## MQTT topics
`templealarm/<Device ID>/`
- `status` – retained JSON status (device → app)
- `event` – retained last event (device → app)
- `online` – `1` / `0`
- `cmd` – JSON command from the app, e.g. `{"cmd":"arm"}`
- `ack` – command replies
