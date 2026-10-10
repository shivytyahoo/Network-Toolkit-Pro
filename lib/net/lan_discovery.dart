import 'dart:async';
import 'dart:io';

/// LAN discovery: finds the local /24 subnet, sweeps it for live hosts
/// with a fast TCP-connect probe, then attempts reverse DNS.

class LanHostInfo {
  LanHostInfo({required this.ip, required this.latencyMs, this.hostname});

  final String ip;
  final int latencyMs;
  String? hostname;
}

/// Returns e.g. "192.168.1" for the first usable local IPv4 interface,
/// or null when no LAN interface is available.
Future<String?> localSubnetBase() async {
  try {
    final ifaces = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
      type: InternetAddressType.IPv4,
    );
    for (final iface in ifaces) {
      for (final addr in iface.addresses) {
        if (addr.type != InternetAddressType.IPv4) continue;
        final ip = addr.address;
        if (ip.startsWith('169.254.')) continue; // link-local, not routable
        final parts = ip.split('.');
        if (parts.length == 4) {
          return '${parts[0]}.${parts[1]}.${parts[2]}';
        }
      }
    }
  } catch (_) {}
  return null;
}

/// Returns the device's own LAN IPv4 address, if any.
Future<String?> localIpAddress() async {
  try {
    final ifaces = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
      type: InternetAddressType.IPv4,
    );
    for (final iface in ifaces) {
      for (final addr in iface.addresses) {
        if (addr.type != InternetAddressType.IPv4) continue;
        if (addr.address.startsWith('169.254.')) continue;
        return addr.address;
      }
    }
  } catch (_) {}
  return null;
}

const _probePorts = [445, 139, 80, 443, 22, 8080];

Future<LanHostInfo?> _probeHost(String ip, Duration timeout) async {
  for (final port in _probePorts) {
    final sw = Stopwatch()..start();
    try {
      final s = await Socket.connect(ip, port, timeout: timeout);
      final ms = sw.elapsedMilliseconds;
      s.destroy();
      return LanHostInfo(ip: ip, latencyMs: ms);
    } catch (_) {
      // try next port
    }
  }
  return null;
}

/// Sweeps 1..254 of [subnetBase] (e.g. "192.168.1"). Throws [StateError]
/// when no local subnet can be determined.
Future<List<LanHostInfo>> discoverHosts({
  String? subnetBase,
  Duration timeout = const Duration(milliseconds: 400),
  int concurrency = 48,
  void Function(int scanned, int total)? onProgress,
  bool Function()? isCancelled,
}) async {
  final base = subnetBase ?? await localSubnetBase();
  if (base == null) {
    throw StateError('No local IPv4 network found. Are you on Wi-Fi/LAN?');
  }
  const total = 254;
  final found = <LanHostInfo>[];
  var scanned = 0;
  for (var i = 1; i <= 254; i += concurrency) {
    if (isCancelled?.call() == true) break;
    final batch = [
      for (var n = i; n < i + concurrency && n <= 254; n++) n,
    ];
    final results =
        await Future.wait(batch.map((n) => _probeHost('$base.$n', timeout)));
    for (final r in results) {
      if (r != null) found.add(r);
    }
    scanned += batch.length;
    onProgress?.call(scanned, total);
  }

  // Reverse-DNS lookup for every live host (best effort).
  await Future.wait(found.map((h) async {
    try {
      final rev = await InternetAddress(h.ip)
          .reverse()
          .timeout(const Duration(seconds: 2));
      if (rev.host != h.ip) h.hostname = rev.host;
    } catch (_) {}
  }));

  found.sort((a, b) => _ipValue(a.ip).compareTo(_ipValue(b.ip)));
  return found;
}

int _ipValue(String ip) {
  var v = 0;
  for (final p in ip.split('.')) {
    v = v * 256 + (int.tryParse(p) ?? 0);
  }
  return v;
}
