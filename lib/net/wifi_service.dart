import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// Wi-Fi details. Fields are null when unavailable on the platform.
class WifiDetails {
  WifiDetails({
    this.ssid,
    this.bssid,
    this.signalPercent,
    this.signalDbm,
    this.frequencyMhz,
    this.ipAddress,
    this.radioType,
    this.source,
  });

  String? ssid;
  String? bssid;
  int? signalPercent; // 0..100
  int? signalDbm; // e.g. -55
  int? frequencyMhz;
  String? ipAddress;
  String? radioType; // e.g. 802.11ax
  String? source; // where the data came from, for transparency

  bool get connected => ssid != null && ssid!.isNotEmpty;
}

abstract class WifiInfoProvider {
  Future<WifiDetails> fetch();
}

/// Picks the right provider for the current OS.
WifiInfoProvider createWifiProvider() {
  if (Platform.isAndroid || Platform.isIOS) return _MobileWifiProvider();
  if (Platform.isWindows) return _WindowsWifiProvider();
  if (Platform.isLinux) return _LinuxWifiProvider();
  return _UnsupportedWifiProvider();
}

// ---------------------------------------------------------------------------
// Android / iOS — network_info_plus (+ /proc/net/wireless for signal on Android)
// ---------------------------------------------------------------------------

class _MobileWifiProvider implements WifiInfoProvider {
  final NetworkInfo _info = NetworkInfo();

  @override
  Future<WifiDetails> fetch() async {
    final d = WifiDetails(source: 'network_info_plus');
    await _ensureLocationPermission();
    try {
      d.ssid = _cleanSsid(await _info.getWifiName());
    } catch (_) {}
    try {
      d.bssid = await _info.getWifiBSSID();
    } catch (_) {}
    try {
      d.ipAddress = await _info.getWifiIP();
    } catch (_) {}
    // network_info_plus exposes no signal strength; on Android the kernel
    // exposes it via /proc/net/wireless (world-readable, no root needed).
    if (Platform.isAndroid) {
      d.signalDbm = await _signalDbmFromProcNetWireless();
      if (d.signalDbm != null) {
        d.signalPercent = ((d.signalDbm! + 100) * 2).clamp(0, 100);
        d.source = 'network_info_plus + /proc/net/wireless';
      }
    }
    return d;
  }

  Future<void> _ensureLocationPermission() async {
    try {
      final status = await Permission.location.status;
      if (!status.isGranted) {
        await Permission.location.request();
      }
    } catch (_) {}
  }

  String? _cleanSsid(String? raw) {
    if (raw == null) return null;
    var s = raw.trim();
    // Android wraps the SSID in double quotes.
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      s = s.substring(1, s.length - 1);
    }
    if (s.isEmpty || s == '<unknown ssid>' || s == '0x') return null;
    return s;
  }
}

/// Reads signal level (dBm) from /proc/net/wireless. Works on Android and
/// Linux; returns null when the file is absent or unparsable.
Future<int?> _signalDbmFromProcNetWireless() async {
  try {
    final f = File('/proc/net/wireless');
    if (!await f.exists()) return null;
    final lines = await f.readAsLines();
    for (final line in lines.skip(2)) {
      // e.g. "wlan0: 0000   70.  -40.  -256        0 ..."
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length >= 4) {
        final dbm = int.tryParse(parts[3].replaceAll('.', ''));
        if (dbm != null && dbm < 0) return dbm;
      }
    }
  } catch (_) {}
  return null;
}

// ---------------------------------------------------------------------------
// Windows — netsh wlan show interfaces
// ---------------------------------------------------------------------------

class _WindowsWifiProvider implements WifiInfoProvider {
  @override
  Future<WifiDetails> fetch() async {
    final d = WifiDetails(source: 'netsh wlan show interfaces');
    try {
      final res = await Process.run(
        'netsh',
        ['wlan', 'show', 'interfaces'],
      ).timeout(const Duration(seconds: 10));
      if (res.exitCode != 0) return d;
      final kv = <String, String>{};
      for (final line in res.stdout.toString().split('\n')) {
        final idx = line.indexOf(':');
        if (idx <= 0) continue;
        kv[line.substring(0, idx).trim().toLowerCase()] =
            line.substring(idx + 1).trim();
      }
      if ((kv['state'] ?? '').toLowerCase() != 'connected') return d;
      d.ssid = kv['ssid'];
      d.bssid = kv['bssid'];
      final sig = kv['signal']?.replaceAll('%', '');
      d.signalPercent = int.tryParse(sig ?? '');
      if (d.signalPercent != null) {
        d.signalDbm = (d.signalPercent! ~/ 2) - 100;
      }
      d.radioType = kv['radio type'];
      final ch = int.tryParse(kv['channel'] ?? '');
      if (ch != null) d.frequencyMhz = _channelToMhz(ch);
      d.ipAddress = await _localIpv4();
    } catch (_) {}
    return d;
  }

  int? _channelToMhz(int ch) {
    if (ch >= 1 && ch <= 14) return 2412 + 5 * (ch - 1); // 2.4 GHz
    const map5 = {
      36: 5180, 40: 5200, 44: 5220, 48: 5240, 52: 5260, 56: 5280,
      60: 5300, 64: 5320, 100: 5500, 104: 5500 + 20, 108: 5540, 112: 5560,
      116: 5580, 120: 5600, 124: 5620, 128: 5640, 132: 5660, 136: 5680,
      140: 5700, 149: 5745, 153: 5765, 157: 5785, 161: 5805, 165: 5825,
    };
    return map5[ch];
  }
}

// ---------------------------------------------------------------------------
// Linux — nmcli (fallback: iwgetid + /proc/net/wireless)
// ---------------------------------------------------------------------------

class _LinuxWifiProvider implements WifiInfoProvider {
  @override
  Future<WifiDetails> fetch() async {
    final d = WifiDetails(source: 'nmcli');
    try {
      final res = await Process.run(
        'nmcli',
        ['-t', '-f', 'IN-USE,SSID,SIGNAL,FREQ', 'device', 'wifi', 'list'],
      ).timeout(const Duration(seconds: 10));
      if (res.exitCode == 0) {
        for (final line in res.stdout.toString().split('\n')) {
          final t = line.trim();
          if (!t.startsWith('*')) continue; // '*' marks the active network
          // Fields are colon-separated; SSID itself may contain colons,
          // so anchor on the first and last two fields.
          final parts = t.split(':');
          if (parts.length < 4) continue;
          final signal = int.tryParse(parts[parts.length - 2]);
          final freq = int.tryParse(parts[parts.length - 1]);
          final middle = parts.sublist(1, parts.length - 2).join(':');
          final macMatch =
              RegExp(r'((?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2})$')
                  .firstMatch(middle);
          if (macMatch != null) {
            d.bssid = macMatch.group(1);
            d.ssid = middle
                .substring(0, middle.length - d.bssid!.length)
                .replaceAll(RegExp(r':+$'), '');
          } else {
            d.ssid = middle;
          }
          d.signalPercent = signal;
          if (signal != null) d.signalDbm = (signal ~/ 2) - 100;
          d.frequencyMhz = freq;
          break;
        }
      }
      if (!d.connected) {
        // Fallback: iwgetid for SSID + /proc/net/wireless for signal.
        d.source = 'iwgetid + /proc/net/wireless';
        try {
          final r = await Process.run('iwgetid', ['-r'])
              .timeout(const Duration(seconds: 5));
          if (r.exitCode == 0) {
            final s = r.stdout.toString().trim();
            if (s.isNotEmpty) d.ssid = s;
          }
        } catch (_) {}
        d.signalDbm = await _signalDbmFromProcNetWireless();
        if (d.signalDbm != null) {
          d.signalPercent = ((d.signalDbm! + 100) * 2).clamp(0, 100);
        }
      }
      d.ipAddress = await _localIpv4();
    } catch (_) {}
    return d;
  }
}

class _UnsupportedWifiProvider implements WifiInfoProvider {
  @override
  Future<WifiDetails> fetch() async =>
      WifiDetails(source: 'unsupported platform');
}

Future<String?> _localIpv4() async {
  try {
    final ifaces = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
      type: InternetAddressType.IPv4,
    );
    for (final iface in ifaces) {
      for (final addr in iface.addresses) {
        if (addr.type == InternetAddressType.IPv4 &&
            !addr.address.startsWith('169.254.')) {
          return addr.address;
        }
      }
    }
  } catch (_) {}
  return null;
}
