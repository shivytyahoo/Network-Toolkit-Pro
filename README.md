# Network Toolkit Pro

**The successor to IP Link Monitor.** What started as a single-purpose ping
monitor is now a complete network toolkit: five utilities in one
cross-platform Flutter app for **Android, Windows and Linux**, built from a
single codebase.

## Download

Grab the ready-to-install Android APK from the
[**Releases**](https://github.com/shivytyahoo/Network-Toolkit-Pro/releases) page,
copy it to your phone and install. No build needed.

> The older `V1.0.0` release on that page is the original IP Link Monitor
> app. The Network Toolkit Pro release is the current one — its Ping
> Monitor tab includes everything IP Link Monitor did, plus four more
> tools.

## The five tools

| Tab | What it does |
|-----|--------------|
| **Ping Monitor** | Watches multiple hosts every 5 s, shows UP/DOWN + latency, keeps history, and fires a local notification when a host stays down for 10 s (and when it recovers). Hosts persist across restarts; import from Excel (Name in column A, IP in column B) or add manually. |
| **Speed Test** | Latency, download and upload against a selectable server: Cloudflare, Hetzner, OVHcloud, Google (ping only), any **LibreSpeed** server, or any **Ookla** (speedtest.net) server — the public server lists are fetched live. Live throughput graph, selectable display units (Kbps / Mbps / Gbps / KBps / MBps / GBps), and the actual Cloudflare PoP city you are routed to (e.g. BOM → Mumbai). |
| **Port Scanner** | TCP-connect scan of 25 common ports (or a custom list like `80,443,8000-8100`) on any host, with per-port response times and OPEN/CLOSED pills. |
| **LAN Discovery** | Detects your local /24 subnet, sweeps all 254 addresses with a fast TCP probe, and lists live devices with latency and reverse-DNS hostnames. |
| **Wi-Fi Info** | SSID, BSSID, signal strength (dBm + %), frequency/band, radio type and local IP. Sources: `network_info_plus` on Android, `netsh wlan show interfaces` on Windows, `nmcli` on Linux. |

## Excel format (Ping Monitor import)

| A (Name)     | B (IP)        |
|--------------|---------------|
| Core Router  | 192.168.1.1   |
| Branch Link  | 10.10.10.2    |

A header row is detected automatically.

## Permissions (Android)

- `INTERNET` / `ACCESS_NETWORK_STATE` — pinging hosts and running tests.
- `ACCESS_WIFI_STATE` + location (`ACCESS_COARSE_LOCATION` /
  `ACCESS_FINE_LOCATION`) — Android requires location permission to read
  the Wi-Fi SSID; it is requested in-app and used for nothing else.
- `POST_NOTIFICATIONS` — down/recovery alerts (asked at runtime on
  Android 13+).

## Build from source

Prerequisites: Flutter 3.47+ (Dart 3.13+), JDK 17 for Android.

```bash
flutter pub get
flutter analyze          # must be clean
flutter build apk --release
# APK: build/app/outputs/flutter-apk/app-release.apk
```

Windows and Linux desktop builds:

```bash
flutter build windows    # -> build/windows/x64/runner/Release/
flutter build linux      # -> build/linux/x64/release/bundle/
```

Every push to `main` is built automatically by GitHub Actions, and every
`v*` tag publishes a Release with the Android APK attached.

## Tech notes

- Pure Dart first (`dart:io` sockets/HTTP/processes). Platform specifics:
  - **Ping**: OS `ping` binary, with a TCP-connect fallback on ports
    80/443 when ICMP is missing or blocked.
  - **Wi-Fi signal on Android/Linux**: parsed from `/proc/net/wireless`
    (world-readable, no root).
  - **Notifications**: `flutter_local_notifications` on Android; desktop
    builds skip initialisation gracefully.
- Hosts, speed-test server choice and display unit persist on-device
  (SharedPreferences).

## Planned for v2

- **Background monitoring service** — today the ping loop runs while the
  app is open; v2 adds an Android foreground service so down-alerts
  arrive with the app closed.
- **Windows installer packaging** (MSIX / Inno Setup).
- **Play Store release** with release signing.
- **More tools**: DNS lookup, traceroute, Wake-on-LAN, subnet calculator.

## Project layout

```
lib/
  main.dart            # app shell, Material 3 dark theme, bottom nav
  ping/monitor.dart    # HostEntry, pingHost(), MonitorService (from Link Monitor)
  net/
    speed_test.dart    # multi-server latency/download/upload (Cloudflare, LibreSpeed, Ookla)
    port_scan.dart     # TCP-connect scanner + port-spec parser
    lan_discovery.dart # subnet detection + /24 sweep + reverse DNS
    wifi_service.dart  # per-OS Wi-Fi providers (Android, Windows, Linux)
  ui/
    common.dart        # theme, palette, shared widgets
    ping_tab.dart      # ping monitor UI
    speed_tab.dart     # speed test UI (server picker, unit selector, PoP)
    port_tab.dart      # port scanner UI
    lan_tab.dart       # LAN discovery UI
    wifi_tab.dart      # Wi-Fi info UI
    about_page.dart
android/  linux/  windows/   # platform runners
```

## Developer

**Shivam Bhalla** — NOC engineer by day, Flutter dev by night.
