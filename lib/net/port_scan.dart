import 'dart:async';
import 'dart:io';

/// TCP-connect port scanner. Pure Dart, works on every platform.

class PortInfo {
  const PortInfo(this.port, this.service);

  final int port;
  final String service;
}

const List<PortInfo> kCommonPorts = [
  PortInfo(21, 'FTP'),
  PortInfo(22, 'SSH'),
  PortInfo(23, 'Telnet'),
  PortInfo(25, 'SMTP'),
  PortInfo(53, 'DNS'),
  PortInfo(80, 'HTTP'),
  PortInfo(110, 'POP3'),
  PortInfo(135, 'RPC'),
  PortInfo(139, 'NetBIOS'),
  PortInfo(143, 'IMAP'),
  PortInfo(443, 'HTTPS'),
  PortInfo(445, 'SMB'),
  PortInfo(993, 'IMAPS'),
  PortInfo(995, 'POP3S'),
  PortInfo(1433, 'MSSQL'),
  PortInfo(1521, 'Oracle DB'),
  PortInfo(1723, 'PPTP'),
  PortInfo(3306, 'MySQL'),
  PortInfo(3389, 'RDP'),
  PortInfo(5432, 'PostgreSQL'),
  PortInfo(5900, 'VNC'),
  PortInfo(6379, 'Redis'),
  PortInfo(8080, 'HTTP-alt'),
  PortInfo(8443, 'HTTPS-alt'),
  PortInfo(27017, 'MongoDB'),
];

class PortScanResult {
  const PortScanResult({
    required this.port,
    required this.service,
    required this.open,
    this.latencyMs,
  });

  final int port;
  final String service;
  final bool open;
  final int? latencyMs;
}

/// Scans [ports] on [host] with bounded concurrency.
Future<List<PortScanResult>> scanPorts(
  String host, {
  Iterable<PortInfo>? ports,
  Duration timeout = const Duration(milliseconds: 800),
  int concurrency = 32,
  void Function(int done, int total)? onProgress,
  bool Function()? isCancelled,
}) async {
  final list = (ports ?? kCommonPorts).toList();
  final results = <PortScanResult>[];
  var done = 0;
  for (var i = 0; i < list.length; i += concurrency) {
    if (isCancelled?.call() == true) break;
    final batch = list.skip(i).take(concurrency);
    final batchResults =
        await Future.wait(batch.map((p) => _probe(host, p, timeout)));
    results.addAll(batchResults);
    done += batchResults.length;
    onProgress?.call(done, list.length);
  }
  results.sort((a, b) => a.port.compareTo(b.port));
  return results;
}

Future<PortScanResult> _probe(String host, PortInfo p, Duration timeout) async {
  final sw = Stopwatch()..start();
  try {
    final s = await Socket.connect(host, p.port, timeout: timeout);
    final ms = sw.elapsedMilliseconds;
    s.destroy();
    return PortScanResult(
        port: p.port, service: p.service, open: true, latencyMs: ms);
  } catch (_) {
    return PortScanResult(port: p.port, service: p.service, open: false);
  }
}

/// Parses user input like "80,443,8000-8100" into a port list.
List<PortInfo> parsePortSpec(String spec) {
  final ports = <int>{};
  for (final part in spec.split(',')) {
    final t = part.trim();
    if (t.isEmpty) continue;
    if (t.contains('-')) {
      final ends = t.split('-');
      if (ends.length == 2) {
        final a = int.tryParse(ends[0].trim());
        final b = int.tryParse(ends[1].trim());
        if (a != null && b != null && a >= 1 && b <= 65535 && a <= b) {
          for (var p = a; p <= b; p++) {
            ports.add(p);
          }
          continue;
        }
      }
    } else {
      final p = int.tryParse(t);
      if (p != null && p >= 1 && p <= 65535) ports.add(p);
    }
  }
  final sorted = ports.toList()..sort();
  return [
    for (final p in sorted)
      PortInfo(p, _serviceName(p)),
  ];
}

String _serviceName(int port) {
  for (final k in kCommonPorts) {
    if (k.port == port) return k.service;
  }
  return 'custom';
}
