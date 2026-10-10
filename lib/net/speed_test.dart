import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// A speed-test / ping server the user can switch between.
class SpeedTestServer {
  const SpeedTestServer({
    required this.id,
    required this.name,
    required this.location,
    required this.latencyUrl,
    this.downloadUrl,
    this.uploadUrl,
    this.rangePing = false,
    this.isOokla = false,
    this.isLibreSpeed = false,
    this.tcpHost,
    this.tcpPort,
  });

  final String id;
  final String name;
  final String location;

  /// Tiny request used for the latency ("ping") probe.
  final String latencyUrl;

  /// Download URL. May contain a `{bytes}` placeholder (Cloudflare-style)
  /// for variable-size downloads; otherwise it is treated as a fixed file
  /// and the transfer is capped by size / time.
  final String? downloadUrl;

  /// Upload endpoint (plain POST of raw bytes). Null when unsupported.
  final String? uploadUrl;

  /// Send `Range: bytes=0-1023` on the latency probe (for fixed files).
  final bool rangePing;

  /// True for servers discovered from Ookla's public list (speedtest.net).
  /// Ping is a TCP connect to [tcpHost]:[tcpPort]; download uses the
  /// classic `/speedtest/` HTTP endpoints on a best-effort basis; upload is
  /// not supported by their current server software (see fromOokla).
  final bool isOokla;

  /// True for servers from LibreSpeed's public list (librespeed.org).
  /// Fully documented open protocol: ping/download/upload all work.
  /// Upload goes as sequential 4 MB POSTs (their PHP sink refuses bigger).
  final bool isLibreSpeed;

  /// TCP host/port used for the Ookla ping.
  final String? tcpHost;
  final int? tcpPort;

  bool get supportsDownload => downloadUrl != null;
  bool get supportsUpload => uploadUrl != null;

  String downloadUrlFor(int bytes) =>
      (downloadUrl ?? '').replaceAll('{bytes}', '$bytes');

  static const cloudflare = SpeedTestServer(
    id: 'cloudflare',
    name: 'Cloudflare',
    location: 'Global (auto)',
    latencyUrl: 'https://speed.cloudflare.com/__down?bytes=0',
    downloadUrl: 'https://speed.cloudflare.com/__down?bytes={bytes}',
    uploadUrl: 'https://speed.cloudflare.com/__up',
  );

  static const hetznerAsh = SpeedTestServer(
    id: 'hetzner-ash',
    name: 'Hetzner',
    location: 'Ashburn, USA',
    latencyUrl: 'https://ash-speed.hetzner.com/100MB.bin',
    downloadUrl: 'https://ash-speed.hetzner.com/100MB.bin',
    rangePing: true,
  );

  static const ovh = SpeedTestServer(
    id: 'ovh',
    name: 'OVHcloud',
    location: 'France',
    latencyUrl: 'https://proof.ovh.net/files/1Gb.dat',
    downloadUrl: 'https://proof.ovh.net/files/1Gb.dat',
    rangePing: true,
  );

  static const google = SpeedTestServer(
    id: 'google',
    name: 'Google',
    location: 'Global (ping only)',
    latencyUrl: 'https://www.google.com/generate_204',
  );

  static const List<SpeedTestServer> all = [
    cloudflare,
    hetznerAsh,
    ovh,
    google,
  ];

  /// Build a server entry from one item of LibreSpeed's public list
  /// (https://librespeed.org/backend-servers/servers.php).
  factory SpeedTestServer.fromLibreSpeed(Map<String, dynamic> json) {
    String join(String base, String path) {
      final b = base.replaceAll(RegExp(r'/+$'), '');
      final p = path.replaceAll(RegExp(r'^/+'), '');
      return '$b/$p';
    }

    final server = (json['server'] ?? '').toString();
    final fullName = (json['name'] ?? 'LibreSpeed server').toString();
    final sponsor = (json['sponsorName'] ?? '').toString();
    final place = fullName.replaceAll(RegExp(r'\s*\(.*\)\s*'), '').trim();
    return SpeedTestServer(
      id: 'libre-${json['id']}',
      name: sponsor.isEmpty ? fullName : sponsor,
      location: place.isEmpty ? fullName : '$place • LibreSpeed',
      latencyUrl: join(server, (json['pingURL'] ?? 'empty.php').toString()),
      downloadUrl:
          '${join(server, (json['dlURL'] ?? 'garbage.php').toString())}?ckSize={mb}',
      uploadUrl: join(server, (json['ulURL'] ?? 'empty.php').toString()),
      isLibreSpeed: true,
    );
  }

  /// Build a server entry from one item of Ookla's public server list.
  ///
  /// NOTE (diagnosed 2026-10-02): these servers RST any POST to the legacy
  /// `/speedtest/upload.php` endpoint (verified on 4 providers, both raw and
  /// form-encoded bodies, plain HTTP and TLS) — the current Ookla server
  /// software only does upload over its new undocumented protocol. So upload
  /// is deliberately disabled here; ping + download work fine.
  factory SpeedTestServer.fromOokla(Map<String, dynamic> json) {
    final host = (json['host'] ?? '').toString();
    final parts = host.split(':');
    final port = parts.length > 1 ? int.tryParse(parts[1]) ?? 8080 : 8080;
    return SpeedTestServer(
      id: 'ookla-${json['id']}',
      name: (json['sponsor'] ?? 'Unknown sponsor').toString(),
      location: '${json['name']}, ${json['country']}',
      latencyUrl: '',
      downloadUrl: 'http://$host/speedtest/download',
      uploadUrl: null, // not supported by current Ookla server software
      isOokla: true,
      tcpHost: parts[0],
      tcpPort: port,
    );
  }
}

/// Internet speed test against a selectable public server.
/// No API keys needed; works anywhere with plain HTTPS.
class SpeedTestService {
  /// Rough round-trip latency via a tiny HTTPS request ("ping").
  /// For Ookla servers this is a TCP connect to host:port instead.
  Future<double> measureLatency({
    SpeedTestServer server = SpeedTestServer.cloudflare,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (server.isOokla) {
      final host = server.tcpHost;
      final port = server.tcpPort ?? 8080;
      if (host == null || host.isEmpty) {
        throw const HttpException('No host for Ookla server');
      }
      final sw = Stopwatch()..start();
      final socket = await Socket.connect(host, port, timeout: timeout);
      sw.stop();
      socket.destroy();
      return sw.elapsedMicroseconds / 1000.0;
    }
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final sw = Stopwatch()..start();
      final req = await client.getUrl(Uri.parse(server.latencyUrl));
      if (server.rangePing) req.headers.set('range', 'bytes=0-1023');
      final resp = await req.close();
      await resp.drain();
      sw.stop();
      if (resp.statusCode >= 400) {
        throw HttpException('Latency probe failed: ${resp.statusCode}');
      }
      return sw.elapsedMicroseconds / 1000.0;
    } finally {
      client.close(force: true);
    }
  }

  /// Ping every known server concurrently. A null value means unreachable.
  Future<Map<String, double?>> pingAllServers({
    List<SpeedTestServer>? servers,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final targets = servers ?? SpeedTestServer.all;
    final results = <String, double?>{};
    await Future.wait(targets.map((s) async {
      try {
        results[s.id] = await measureLatency(server: s, timeout: timeout);
      } catch (_) {
        results[s.id] = null;
      }
    }));
    return results;
  }

  /// Fetch Ookla's public server list (the same one speedtest.net uses),
  /// sorted by distance from the requester's IP.
  static Future<List<SpeedTestServer>> fetchOoklaServers() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(
          'https://www.speedtest.net/api/js/servers?engine=js&https_functional=true'));
      // Ookla's bot protection rejects non-browser user agents.
      req.headers.set('user-agent',
          'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36');
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw HttpException('Ookla list failed: HTTP ${resp.statusCode}');
      }
      final body = await resp.transform(utf8.decoder).join();
      final list = jsonDecode(body) as List;
      final servers = <SpeedTestServer>[];
      for (final e in list) {
        try {
          final s = SpeedTestServer.fromOokla(e as Map<String, dynamic>);
          if (s.tcpHost != null && s.tcpHost!.isNotEmpty) servers.add(s);
        } catch (_) {
          // Skip malformed entries.
        }
      }
      return servers;
    } finally {
      client.close(force: true);
    }
  }

  /// Fetch LibreSpeed's public server list (the same default list their
  /// official CLI uses).
  static Future<List<SpeedTestServer>> fetchLibreSpeedServers() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(
          'https://librespeed.org/backend-servers/servers.php'));
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw HttpException(
            'LibreSpeed list failed: HTTP ${resp.statusCode}');
      }
      final body = await resp.transform(utf8.decoder).join();
      final list = jsonDecode(body) as List;
      final servers = <SpeedTestServer>[];
      for (final e in list) {
        try {
          servers.add(SpeedTestServer.fromLibreSpeed(
              e as Map<String, dynamic>));
        } catch (_) {
          // Skip malformed entries.
        }
      }
      return servers;
    } finally {
      client.close(force: true);
    }
  }
  Future<Map<String, double?>> pingOoklaServers(
    List<SpeedTestServer> servers, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final results = <String, double?>{};
    const chunk = 8;
    for (var i = 0; i < servers.length; i += chunk) {
      final batch = servers.sublist(i, min(i + chunk, servers.length));
      await Future.wait(batch.map((s) async {
        try {
          results[s.id] = await measureLatency(server: s, timeout: timeout);
        } catch (_) {
          results[s.id] = null;
        }
      }));
    }
    return results;
  }

  /// Classic Ookla `/speedtest/random*.jpg` endpoints, looped until the
  /// byte cap or time cap. Best-effort: some servers refuse these paths.
  static const _ooklaSizes = ['4000x4000', '2000x2000', '1500x1500'];

  Future<double> _ooklaDownload(
    SpeedTestServer server,
    int bytes,
    SpeedTestController c,
    void Function(SpeedTestProgress)? onProgress,
    Duration timeout,
    Duration maxDuration,
  ) async {
    final host = server.tcpHost;
    final port = server.tcpPort ?? 8080;
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final sw = Stopwatch()..start();
      var received = 0;
      var lastReport = DateTime.now();
      var sizeIdx = 0;
      outer:
      while (received < bytes && sw.elapsed < maxDuration) {
        final size = _ooklaSizes[sizeIdx % _ooklaSizes.length];
        sizeIdx++;
        final req = await client.getUrl(Uri.parse(
            'http://$host:$port/speedtest/random$size.jpg'));
        final resp = await req.close();
        if (resp.statusCode != 200) {
          if (received == 0) {
            throw HttpException('Download failed: HTTP ${resp.statusCode}');
          }
          break;
        }
        await for (final chunk in resp) {
          c.throwIfCancelled();
          received += chunk.length;
          final elapsed = sw.elapsed;
          final now = DateTime.now();
          if (now.difference(lastReport).inMilliseconds >= 250) {
            lastReport = now;
            onProgress?.call(SpeedTestProgress(
              mbps: _mbps(received, elapsed),
              bytesTransferred: received,
              totalBytes: bytes,
              elapsed: elapsed,
            ));
          }
          if (received >= bytes || elapsed >= maxDuration) break outer;
        }
      }
      sw.stop();
      if (received == 0) throw const HttpException('No data received');
      return _mbps(received, sw.elapsed);
    } finally {
      client.close(force: true);
    }
  }

  /// LibreSpeed upload: sequential 4 MB POSTs to empty.php (their PHP sink
  /// refuses bigger request bodies), until 12 MB total or the time cap.
  Future<double> _libreSpeedUpload(
    SpeedTestServer server,
    SpeedTestController c,
    void Function(SpeedTestProgress)? onProgress,
    Duration timeout, {
    Duration maxDuration = const Duration(seconds: 20),
  }) async {
    const postBytes = 4 * 1024 * 1024;
    const totalBytes = 12 * 1024 * 1024;
    final rnd = Random();
    final chunk = List<int>.generate(postBytes, (_) => rnd.nextInt(256));
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final sw = Stopwatch()..start();
      var sent = 0;
      var lastReport = DateTime.now();
      while (sent < totalBytes && sw.elapsed < maxDuration) {
        c.throwIfCancelled();
        final req = await client.postUrl(Uri.parse(server.uploadUrl!));
        req.contentLength = postBytes;
        req.headers.contentType = ContentType.binary;
        req.add(chunk);
        final resp = await req.close();
        await resp.drain();
        if (resp.statusCode != 200) {
          if (sent == 0) {
            throw HttpException('Upload failed: HTTP ${resp.statusCode}');
          }
          break;
        }
        sent += postBytes;
        final now = DateTime.now();
        if (now.difference(lastReport).inMilliseconds >= 250) {
          lastReport = now;
          onProgress?.call(SpeedTestProgress(
            mbps: _mbps(sent, sw.elapsed),
            bytesTransferred: sent,
            totalBytes: totalBytes,
            elapsed: sw.elapsed,
          ));
        }
      }
      sw.stop();
      if (sent == 0) throw const HttpException('No data uploaded');
      return _mbps(sent, sw.elapsed);
    } finally {
      client.close(force: true);
    }
  }

  /// Download test against [server]. For fixed-file servers the transfer is
  /// capped at [bytes] or [maxDuration], whichever comes first.
  Future<double> testDownload({
    SpeedTestServer server = SpeedTestServer.cloudflare,
    int bytes = 25000000,
    SpeedTestController? controller,
    void Function(SpeedTestProgress)? onProgress,
    Duration timeout = const Duration(seconds: 60),
    Duration maxDuration = const Duration(seconds: 20),
  }) async {
    if (!server.supportsDownload) {
      throw UnsupportedError('${server.name} does not support download tests');
    }
    final c = controller ?? SpeedTestController();
    if (server.isOokla) {
      return _ooklaDownload(server, bytes, c, onProgress, timeout, maxDuration);
    }
    // LibreSpeed's garbage.php takes ckSize in megabytes.
    final url = server.isLibreSpeed
        ? server.downloadUrl!
            .replaceAll('{mb}', '${(bytes / 1048576).ceil()}')
        : server.downloadUrlFor(bytes);
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close();
      if (resp.statusCode != 200 && resp.statusCode != 206) {
        throw HttpException('Download failed: HTTP ${resp.statusCode}');
      }
      final sw = Stopwatch()..start();
      var received = 0;
      var lastReport = DateTime.now();
      await for (final chunk in resp) {
        c.throwIfCancelled();
        received += chunk.length;
        final elapsed = sw.elapsed;
        final now = DateTime.now();
        if (now.difference(lastReport).inMilliseconds >= 250) {
          lastReport = now;
          onProgress?.call(SpeedTestProgress(
            mbps: _mbps(received, elapsed),
            bytesTransferred: received,
            totalBytes: bytes,
            elapsed: elapsed,
          ));
        }
        if (received >= bytes || elapsed >= maxDuration) break;
      }
      sw.stop();
      if (received == 0) throw const HttpException('No data received');
      return _mbps(received, sw.elapsed);
    } finally {
      client.close(force: true);
    }
  }

  /// Upload test. Cloudflare + LibreSpeed servers have upload endpoints;
  /// Ookla's current server software does not (legacy endpoint is dead).
  Future<double> testUpload({
    SpeedTestServer server = SpeedTestServer.cloudflare,
    int bytes = 10000000,
    SpeedTestController? controller,
    void Function(SpeedTestProgress)? onProgress,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final upUrl = server.uploadUrl;
    if (upUrl == null) {
      throw UnsupportedError('${server.name} does not support upload tests');
    }
    final c = controller ?? SpeedTestController();
    if (server.isLibreSpeed) {
      return _libreSpeedUpload(server, c, onProgress, timeout);
    }
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.postUrl(Uri.parse(upUrl));
      req.contentLength = bytes;
      req.headers.contentType = ContentType.binary;
      final rnd = Random();
      const chunkSize = 64 * 1024;
      final chunk = List<int>.generate(chunkSize, (_) => rnd.nextInt(256));
      final sw = Stopwatch()..start();
      var sent = 0;
      var lastReport = DateTime.now();
      while (sent < bytes) {
        c.throwIfCancelled();
        final n = min(chunkSize, bytes - sent);
        req.add(chunk.sublist(0, n));
        sent += n;
        if (sent % (chunkSize * 4) == 0) {
          await req.flush();
          final now = DateTime.now();
          if (now.difference(lastReport).inMilliseconds >= 250) {
            lastReport = now;
            onProgress?.call(SpeedTestProgress(
              mbps: _mbps(sent, sw.elapsed),
              bytesTransferred: sent,
              totalBytes: bytes,
              elapsed: sw.elapsed,
            ));
          }
        }
      }
      await req.flush();
      final resp = await req.close();
      await resp.drain();
      sw.stop();
      if (resp.statusCode != 200) {
        throw HttpException('Upload failed: HTTP ${resp.statusCode}');
      }
      return _mbps(sent, sw.elapsed);
    } finally {
      client.close(force: true);
    }
  }

  double _mbps(int bytes, Duration elapsed) {
    final us = elapsed.inMicroseconds;
    if (us <= 0) return 0;
    return bytes * 8 / us; // bits per microsecond == Mbps
  }

  /// Cloudflare's PoP (datacenter IATA code) serving this client, e.g. "BOM".
  /// speed.cloudflare.com is anycast, so this tells the user which city
  /// they're actually testing against.
  static Future<String?> fetchCloudflareColo() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client
          .getUrl(Uri.parse('https://speed.cloudflare.com/cdn-cgi/trace'));
      final resp = await req.close();
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join();
      for (final line in body.split('\n')) {
        if (line.startsWith('colo=')) return line.substring(5).trim();
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Human-readable city for a Cloudflare colo code (Indian PoPs first).
  static String coloName(String colo) {
    const names = {
      'BOM': 'Mumbai',
      'DEL': 'New Delhi',
      'CCU': 'Kolkata',
      'MAA': 'Chennai',
      'HYD': 'Hyderabad',
      'BLR': 'Bengaluru',
      'AMD': 'Ahmedabad',
      'PNQ': 'Pune',
    };
    return names[colo.toUpperCase()] ?? colo.toUpperCase();
  }
}

/// Current network identity (ISP, public IP, city) via a free lookup.
class NetworkInfo {
  const NetworkInfo({
    required this.isp,
    required this.ip,
    required this.city,
    required this.country,
  });

  final String isp;
  final String ip;
  final String city;
  final String country;

  static Future<NetworkInfo?> fetch() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(
          'http://ip-api.com/json/?fields=status,isp,query,city,country'));
      final resp = await req.close();
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join();
      final m = jsonDecode(body) as Map<String, dynamic>;
      if (m['status'] != 'success') return null;
      return NetworkInfo(
        isp: (m['isp'] ?? 'Unknown').toString(),
        ip: (m['query'] ?? '').toString(),
        city: (m['city'] ?? '').toString(),
        country: (m['country'] ?? '').toString(),
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

class SpeedTestProgress {
  const SpeedTestProgress({
    required this.mbps,
    required this.bytesTransferred,
    required this.totalBytes,
    required this.elapsed,
  });

  final double mbps;
  final int bytesTransferred;
  final int totalBytes; // -1 when unknown
  final Duration elapsed;

  double? get fraction =>
      totalBytes > 0 ? bytesTransferred / totalBytes : null;
}

class SpeedTestResult {
  const SpeedTestResult({
    required this.latencyMs,
    required this.downloadMbps,
    required this.uploadMbps,
    required this.serverName,
    required this.at,
  });

  final double latencyMs;
  final double? downloadMbps; // null when the server can't do downloads
  final double? uploadMbps; // null when the server can't do uploads
  final String serverName;
  final DateTime at;
}

/// Cooperative cancellation token for a running speed test.
class SpeedTestController {
  bool _cancelled = false;

  void cancel() => _cancelled = true;
  bool get isCancelled => _cancelled;

  void throwIfCancelled() {
    if (_cancelled) throw const SpeedTestCancelled();
  }
}

class SpeedTestCancelled implements Exception {
  const SpeedTestCancelled();

  @override
  String toString() => 'Speed test cancelled';
}
