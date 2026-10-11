# 📡 Beamo

<p align="center">
  <img src="assets/icon/app_icon.png" width="160" alt="Beamo logo">
</p>

<p align="center"><i>Beam files from your phone to your TV — no internet, no cloud.</i></p>

Local-network file sharing — **phone → TV**, phone → phone. Same Wi-Fi or hotspot, no internet, no cloud, no account. Built with Flutter (Android, iOS, Android TV).

## How it works

```
  ┌──────────┐   mDNS: _beamo._tcp    ┌──────────┐
  │  SENDER  │ ─── discover ───────────▶ │ RECEIVER │
  │ (phone)  │                           │ (TV)     │
  └──────────┘                           └──────────┘
       │  POST /offer {filename, size}         │
       │  GET  /offer/<id>/status  (poll)     │  shelf HTTP
       │  POST /upload/<id>  (raw bytes)      │  server :8080
       ▼                                      ▼
   progress bar                        accept dialog → save
```

1. **Receiver** (TV): opens *Receive files* → starts an HTTP server on port 8080 and advertises `_beamo._tcp` via mDNS/Bonjour.
2. **Sender** (phone): opens *Send files* → browses mDNS, picks the TV, picks files.
3. Each file: `POST /offer` → TV shows **Accept/Decline** → sender polls status → on accept, raw bytes stream via `POST /upload/<id>` with progress on both sides.
4. If mDNS is blocked (some hotspots), enter the receiver's IP manually — the HTTP protocol doesn't care how you learned the address.

## Project structure

```
lib/
  main.dart
  models/
    peer_device.dart      # discovered device (name, host, port)
    transfer.dart         # transfer state (progress, status)
  services/
    network_service.dart  # Wi-Fi IP lookup
    discovery_service.dart# mDNS advertise + browse (nsd)
    share_server.dart     # shelf HTTP server (receiver)
    share_client.dart     # HTTP client: offer → poll → upload (sender)
    storage_service.dart  # where received files are saved
  screens/
    home_screen.dart      # Send / Receive role picker
    send_screen.dart      # pick files, find devices, send
    receive_screen.dart   # advertise, accept dialog, progress
  widgets/
    transfer_tile.dart    # progress row
```

## Setup

```bash
# 1. scaffold the native projects, then drop these files in
flutter create --org com.example --project-name beamo beamo-app
# copy pubspec.yaml + lib/ from this folder into beamo-app/

cd beamo-app
flutter pub get
flutter run
```

### App icon

The logo lives at `assets/icon/app_icon.png`. Generate all platform icons with:

```bash
dart run flutter_launcher_icons
```

> `flutter create` generates `android/` and `ios/` for you — this repo ships the Dart side (`lib/`, `pubspec.yaml`) which is where all the logic lives.

### Android — `android/app/src/main/AndroidManifest.xml`

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
<!-- needed for getWifiIP() on Android 10+ -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

### iOS — `ios/Runner/Info.plist`

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Beamo needs local network access to find nearby devices.</string>
<key>NSBonjourServices</key>
<array>
  <string>_beamo._tcp</string>
</array>
```

## 📺 Android TV notes

- Build an APK (`flutter build apk`) and sideload it on the TV.
- Open **Receive files** on the TV — the Accept button is autofocused for D-pad remotes.
- For a proper TV launcher entry, add to the manifest:
  ```xml
  <uses-feature android:name="android.software.leanback" android:required="false" />
  ```
  and an `android:banner` on the launcher activity (optional).
- Received files land in the app-specific external dir
  (`Android/data/<package>/files/Beamo`) — visible in the TV's file manager.

## 📶 Hotspot tips

- Phone hotspot ON → TV joins the hotspot → same LAN, works.
- Some hotspots block mDNS multicast: if the TV doesn't appear, use **Manual IP** on the sender (the TV shows its IP on the Receive screen).
- iOS Personal Hotspot + Android TV: same deal — manual IP is the reliable fallback.

## Limitations / roadmap

- [ ] One file at a time per peer (queue works, parallel doesn't yet)
- [ ] No resume after disconnect — large files restart
- [ ] Receiver can't browse the sender's files (push-only for now)
- [ ] No transfer encryption — LAN-only, don't use on untrusted networks
- [ ] iOS background uploads will pause if the app is backgrounded
- [ ] TV D-pad: basic focus works; full leanback polish is future work

## Dependencies

`nsd` (mDNS) · `shelf` + `shelf_router` (embedded server) · `http` · `file_picker` · `path_provider` · `permission_handler` · `network_info_plus` · `uuid`
