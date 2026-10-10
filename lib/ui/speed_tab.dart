import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../net/speed_test.dart';
import 'common.dart';

/// Display units for speed values. Bits vs bytes: byte units are 8x smaller.
enum SpeedUnit {
  kbps('Kbps', 1e3),
  mbps('Mbps', 1e6),
  gbps('Gbps', 1e9),
  kBps('KBps', 8e3),
  mBps('MBps', 8e6),
  gBps('GBps', 8e9);

  const SpeedUnit(this.label, this.bitsPerUnit);

  final String label;
  final double bitsPerUnit;

  double fromMbps(double mbps) => mbps * 1e6 / bitsPerUnit;

  String format(double mbps) {
    final v = fromMbps(mbps);
    return v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  }
}

/// Tab 2 — internet speed test (latency / download / upload)
/// against a user-selectable test server, including Ookla's
/// public server list (the same one speedtest.net uses).
class SpeedTab extends StatefulWidget {
  const SpeedTab({super.key});

  @override
  State<SpeedTab> createState() => _SpeedTabState();
}

enum _Phase { idle, latency, download, upload, done, error }

class _SpeedTabState extends State<SpeedTab> {
  final _service = SpeedTestService();
  SpeedTestController? _controller;

  SpeedTestServer _server = SpeedTestServer.cloudflare;
  final Map<String, double?> _pings = {};
  NetworkInfo? _netInfo;
  SpeedUnit _unit = SpeedUnit.mbps;
  String? _cfColo;

  _Phase _phase = _Phase.idle;
  double? _latencyMs;
  double? _downloadMbps;
  double? _uploadMbps;
  double? _liveMbps;
  double? _fraction;
  String? _error;
  String? _note;
  final List<SpeedTestResult> _history = [];

  bool get _running =>
      _phase == _Phase.latency ||
      _phase == _Phase.download ||
      _phase == _Phase.upload;

  @override
  void initState() {
    super.initState();
    NetworkInfo.fetch().then((n) {
      if (mounted) setState(() => _netInfo = n);
    });
    SpeedTestService.fetchCloudflareColo().then((c) {
      if (mounted) setState(() => _cfColo = c);
    });
    SharedPreferences.getInstance().then((p) {
      final name = p.getString('speed_unit');
      if (name != null && mounted) {
        final match = SpeedUnit.values.where((u) => u.name == name);
        if (match.isNotEmpty) setState(() => _unit = match.first);
      }
    });
  }

  Future<void> _setUnit(SpeedUnit u) async {
    setState(() => _unit = u);
    final p = await SharedPreferences.getInstance();
    await p.setString('speed_unit', u.name);
  }

  /// Location line for the server card. For Cloudflare (anycast), also show
  /// the actual PoP city the client is routed to.
  String _serverLocationText() {
    if (_server.id == 'cloudflare' && _cfColo != null) {
      return '${_server.location} • ${SpeedTestService.coloName(_cfColo!)} PoP';
    }
    return _server.location;
  }

  @override
  void dispose() {
    _controller?.cancel();
    super.dispose();
  }

  String _pingText(String id) {
    final p = _pings[id];
    if (p == null) return _pings.containsKey(id) ? 'unreachable' : '—';
    return '${p.toStringAsFixed(0)} ms';
  }

  Future<void> _pingCurrent() async {
    setState(() => _pingingOne = true);
    try {
      final ms = await _service.measureLatency(server: _server);
      if (!mounted) return;
      setState(() {
        _pings[_server.id] = ms;
        _pingingOne = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pings[_server.id] = null;
        _pingingOne = false;
      });
    }
  }

  bool _pingingOne = false;

  /// Runs [fn], returning null when it fails (except cancellation).
  /// Used for best-effort Ookla endpoints.
  Future<double?> _guarded(Future<double> Function() fn) async {
    try {
      return await fn();
    } on SpeedTestCancelled {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  Future<void> _run() async {
    final c = SpeedTestController();
    final server = _server;
    final bestEffort = server.isOokla;
    setState(() {
      _controller = c;
      _phase = _Phase.latency;
      _error = null;
      _note = null;
      _liveMbps = null;
      _fraction = null;
      _latencyMs = null;
      _downloadMbps = null;
      _uploadMbps = null;
    });
    try {
      final latency = await _service.measureLatency(server: server);
      if (!mounted) return;
      setState(() {
        _latencyMs = latency;
        _pings[server.id] = latency;
      });

      void progress(SpeedTestProgress p) {
        if (!mounted) return;
        setState(() {
          _liveMbps = p.mbps;
          _fraction = p.fraction;
        });
      }

      if (server.supportsDownload) {
        setState(() => _phase = _Phase.download);
        final dl = bestEffort
            ? await _guarded(() => _service.testDownload(
                server: server, controller: c, onProgress: progress))
            : await _service.testDownload(
                server: server, controller: c, onProgress: progress);
        if (!mounted) return;
        if (dl != null) {
          setState(() {
            _downloadMbps = dl;
            _liveMbps = null;
            _fraction = null;
          });
        } else {
          setState(() {
            _note =
                '${server.name} did not answer the download test — ping recorded only.';
            _liveMbps = null;
            _fraction = null;
          });
        }
      } else {
        setState(() => _note =
            '${server.name} supports ping only — pick Cloudflare, Hetzner, OVHcloud or an Ookla server for a full speed test.');
      }

      if (server.supportsUpload) {
        setState(() => _phase = _Phase.upload);
        final ul = bestEffort
            ? await _guarded(() => _service.testUpload(
                server: server, controller: c, onProgress: progress))
            : await _service.testUpload(
                server: server, controller: c, onProgress: progress);
        if (!mounted) return;
        if (ul != null) {
          setState(() => _uploadMbps = ul);
        } else if (_note == null) {
          setState(() => _note =
              '${server.name} did not answer the upload test — showing ping + download only.');
        }
      } else if (server.supportsDownload && _note == null) {
        setState(() => _note =
            '${server.name} has no upload endpoint — showing ping + download only.');
      }

      if (!mounted) return;
      setState(() {
        _phase = _Phase.done;
        _history.insert(
          0,
          SpeedTestResult(
            latencyMs: _latencyMs ?? 0,
            downloadMbps: _downloadMbps,
            uploadMbps: _uploadMbps,
            serverName: server.name,
            at: DateTime.now(),
          ),
        );
        if (_history.length > 10) _history.removeLast();
      });
    } on SpeedTestCancelled {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.idle;
        _liveMbps = null;
        _fraction = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = _friendlyError(e);
        _liveMbps = null;
        _fraction = null;
      });
    }
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('SocketException') || s.contains('Failed host lookup')) {
      return 'No internet connection. Check your network and try again.';
    }
    if (s.contains('403')) {
      return 'This server refused the test (rate-limited). Try another server or wait a minute.';
    }
    if (s.contains('TimeoutException')) {
      return 'The test timed out. Your connection may be very slow.';
    }
    return 'Speed test failed: $s';
  }

  void _showServerPicker() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.85,
        child: _ServerPickerSheet(
          selectedId: _server.id,
          pings: _pings,
          onSelect: (s) {
            setState(() => _server = s);
            Navigator.of(ctx).pop();
          },
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final ping = _pings[_server.id];
    return GradientBackground(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            // ---- server selector ----
            Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _running ? null : _showServerPicker,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.dns, color: TColors.cyan),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_server.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15)),
                            Text(_serverLocationText(),
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 12)),
                          ],
                        ),
                      ),
                      if (_pingingOne)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        InkWell(
                          onTap: _running ? null : _pingCurrent,
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.speed,
                                    size: 16, color: TColors.amber),
                                const SizedBox(width: 4),
                                Text(
                                  ping == null
                                      ? 'ping'
                                      : _pingText(_server.id),
                                  style: const TextStyle(
                                      color: TColors.amber,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(width: 4),
                      const Icon(Icons.unfold_more,
                          color: Colors.white54),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                BigStat(
                  label: 'DOWNLOAD',
                  value: _downloadMbps == null
                      ? '--'
                      : _unit.format(_downloadMbps!),
                  unit: _unit.label,
                  color: TColors.cyan,
                ),
                const SizedBox(width: 12),
                BigStat(
                  label: 'UPLOAD',
                  value: _uploadMbps == null
                      ? '--'
                      : _unit.format(_uploadMbps!),
                  unit: _unit.label,
                  color: TColors.purple,
                ),
                const SizedBox(width: 12),
                BigStat(
                  label: 'LATENCY',
                  value: _latencyMs == null
                      ? '--'
                      : _latencyMs!.toStringAsFixed(0),
                  unit: 'ms',
                  color: TColors.amber,
                ),
              ],
            ),
            const SizedBox(height: 10),
            // ---- unit selector ----
            Row(
              children: [
                const Text(
                  'UNITS',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 34,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: SpeedUnit.values.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(width: 8),
                      itemBuilder: (ctx, i) {
                        final u = SpeedUnit.values[i];
                        return ChoiceChip(
                          label: Text(u.label,
                              style: const TextStyle(fontSize: 12)),
                          selected: u == _unit,
                          onSelected: (_) => _setUnit(u),
                          visualDensity: VisualDensity.compact,
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // ---- your connection (ISP) ----
            if (_netInfo != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.wifi, color: TColors.green),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'YOUR CONNECTION',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _netInfo!.isp,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              '${_netInfo!.ip} • ${_netInfo!.city}, ${_netInfo!.country}',
                              style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _PhaseLabel(
                        phase: _phase,
                        liveMbps: _liveMbps,
                        unit: _unit),
                    const SizedBox(height: 12),
                    if (_running)
                      LinearProgressIndicator(
                        value: _fraction,
                        borderRadius: BorderRadius.circular(8),
                        minHeight: 8,
                      )
                    else
                      const SizedBox(height: 8),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: _running
                          ? FilledButton.tonalIcon(
                              onPressed: () => _controller?.cancel(),
                              icon: const Icon(Icons.stop),
                              label: const Text('Cancel test'),
                            )
                          : FilledButton.icon(
                              onPressed: _run,
                              icon: const Icon(Icons.speed),
                              label: Text(_server.supportsDownload
                                  ? 'Run speed test'
                                  : 'Ping ${_server.name}'),
                            ),
                    ),
                    if (_phase == _Phase.error && _error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: const TextStyle(color: TColors.red),
                          textAlign: TextAlign.center),
                    ],
                    if (_note != null) ...[
                      const SizedBox(height: 12),
                      Text(_note!,
                          style: const TextStyle(
                              color: TColors.amber, fontSize: 12),
                          textAlign: TextAlign.center),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      _server.isOokla
                          ? 'Ookla server (speedtest.net network). Ping + download work here; upload is not supported by Ookla\u2019s current server software — switch to Cloudflare or a LibreSpeed server for the upload test.'
                          : _server.isLibreSpeed
                              ? 'LibreSpeed server: open-source network, ping + download + upload all supported (upload goes in 4 MB posts).'
                              : _server.supportsUpload
                              ? 'Full test on ${_server.name}: ping + \u2248 25 MB download + \u2248 10 MB upload.'
                              : _server.supportsDownload
                                  ? 'Download test on ${_server.name} is capped at \u2248 25 MB / 20 s. Upload is only available on Cloudflare.'
                                  : '${_server.name} supports ping only.',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            if (_history.isNotEmpty) ...[
              const SectionTitle('HISTORY'),
              for (final r in _history)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading:
                        const Icon(Icons.history, color: TColors.cyan),
                    title: Text(
                      r.downloadMbps == null
                          ? 'Ping ${r.latencyMs.toStringAsFixed(0)} ms'
                          : '\u2193 ${_unit.format(r.downloadMbps!)} ${_unit.label}'
                              '${r.uploadMbps == null ? '' : '  \u2191 ${_unit.format(r.uploadMbps!)} ${_unit.label}'}',
                      style:
                          const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                        '${r.latencyMs.toStringAsFixed(0)} ms latency \u2022 ${r.serverName} \u2022 ${ago(r.at)}'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Bottom-sheet content: curated full-test servers + Ookla's public
/// server list (same as speedtest.net), with ping-all and use-fastest.
class _ServerPickerSheet extends StatefulWidget {
  const _ServerPickerSheet({
    required this.selectedId,
    required this.pings,
    required this.onSelect,
  });

  final String selectedId;
  final Map<String, double?> pings;
  final ValueChanged<SpeedTestServer> onSelect;

  @override
  State<_ServerPickerSheet> createState() => _ServerPickerSheetState();
}

class _ServerPickerSheetState extends State<_ServerPickerSheet> {
  final _service = SpeedTestService();
  List<SpeedTestServer> _ookla = [];
  bool _loadingOokla = false;
  List<SpeedTestServer> _libre = [];
  bool _loadingLibre = false;
  bool _pingingAll = false;
  String? _ooklaError;
  String? _libreError;

  String _pingText(String id) {
    final p = widget.pings[id];
    if (p == null) return widget.pings.containsKey(id) ? 'unreachable' : '—';
    return '${p.toStringAsFixed(0)} ms';
  }

  Future<void> _loadOokla() async {
    setState(() {
      _loadingOokla = true;
      _ooklaError = null;
    });
    try {
      final servers = await SpeedTestService.fetchOoklaServers();
      if (!mounted) return;
      setState(() {
        _ookla = servers;
        _loadingOokla = false;
      });
      final pings = await _service.pingOoklaServers(servers);
      if (!mounted) return;
      setState(() => widget.pings.addAll(pings));
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingOokla = false;
          _ooklaError = 'Could not load Ookla servers. Check internet.';
        });
      }
    }
  }

  Future<void> _loadLibre() async {
    setState(() {
      _loadingLibre = true;
      _libreError = null;
    });
    try {
      final servers = await SpeedTestService.fetchLibreSpeedServers();
      if (!mounted) return;
      setState(() => _libre = servers);
      final pings =
          await _service.pingAllServers(servers: servers);
      if (!mounted) return;
      setState(() => widget.pings.addAll(pings));
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingLibre = false;
          _libreError =
              'Could not load LibreSpeed servers. Check internet.';
        });
      }
    } finally {
      if (mounted) setState(() => _loadingLibre = false);
    }
  }

  Future<void> _pingAll({bool autoSelect = false}) async {
    setState(() => _pingingAll = true);
    try {
      final results = await _service.pingAllServers();
      widget.pings.addAll(results);
      if (_ookla.isNotEmpty) {
        final op = await _service.pingOoklaServers(_ookla);
        widget.pings.addAll(op);
      }
      if (_libre.isNotEmpty) {
        final lp = await _service.pingAllServers(servers: _libre);
        widget.pings.addAll(lp);
      }
      if (!mounted) return;
      setState(() => _pingingAll = false);
      if (autoSelect) {
        final all = [...SpeedTestServer.all, ..._ookla, ..._libre]
            .where((s) => s.supportsDownload);
        SpeedTestServer? best;
        double? bestPing;
        for (final s in all) {
          final p = widget.pings[s.id];
          if (p == null) continue;
          if (bestPing == null || p < bestPing) {
            bestPing = p;
            best = s;
          }
        }
        if (best != null) widget.onSelect(best);
      }
    } catch (_) {
      if (mounted) setState(() => _pingingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Test server',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
              'Pick a server, or load speedtest.net\u2019s nearby servers and LibreSpeed\u2019s open servers, then ping them all.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed:
                        _pingingAll ? null : () => _pingAll(),
                    icon: _pingingAll
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2),
                          )
                        : const Icon(Icons.radar),
                    label: const Text('Ping all servers'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pingingAll
                        ? null
                        : () => _pingAll(autoSelect: true),
                    icon: const Icon(Icons.bolt),
                    label: const Text('Use fastest'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  const _SectionLabel('Full-test servers'),
                  for (final s in SpeedTestServer.all)
                    _ServerRow(
                      server: s,
                      selected: s.id == widget.selectedId,
                      pingText: _pingText(s.id),
                      onTap: () => widget.onSelect(s),
                    ),
                  const Divider(height: 24),
                  const _SectionLabel('Nearby servers \u00b7 speedtest.net'),
                  if (_loadingOokla) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    const Text('Loading nearby servers\u2026',
                        style: TextStyle(
                            color: Colors.white54, fontSize: 12)),
                  ] else if (_ooklaError != null) ...[
                    Text(_ooklaError!,
                        style: const TextStyle(color: TColors.red)),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _loadOokla,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ] else if (_ookla.isEmpty) ...[
                    OutlinedButton.icon(
                      onPressed: _loadOokla,
                      icon: const Icon(Icons.cloud_download),
                      label: const Text('Load nearby servers'),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Same public list speedtest.net uses, sorted by distance from you.',
                      style: TextStyle(
                          color: Colors.white54, fontSize: 12),
                    ),
                  ] else ...[
                    for (final s in _ookla)
                      _ServerRow(
                        server: s,
                        selected: s.id == widget.selectedId,
                        pingText: _pingText(s.id),
                        onTap: () => widget.onSelect(s),
                      ),
                  ],
                  const Divider(height: 24),
                  const _SectionLabel('LibreSpeed servers \u00b7 full test'),
                  if (_loadingLibre) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    const Text('Loading LibreSpeed servers\u2026',
                        style: TextStyle(
                            color: Colors.white54, fontSize: 12)),
                  ] else if (_libreError != null) ...[
                    Text(_libreError!,
                        style: const TextStyle(color: TColors.red)),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _loadLibre,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ] else if (_libre.isEmpty) ...[
                    OutlinedButton.icon(
                      onPressed: _loadLibre,
                      icon: const Icon(Icons.cloud_download),
                      label: const Text('Load LibreSpeed servers'),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Open-source speedtest network — these support ping + download + upload.',
                      style: TextStyle(
                          color: Colors.white54, fontSize: 12),
                    ),
                  ] else ...[
                    for (final s in _libre)
                      _ServerRow(
                        server: s,
                        selected: s.id == widget.selectedId,
                        pingText: _pingText(s.id),
                        onTap: () => widget.onSelect(s),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _ServerRow extends StatelessWidget {
  const _ServerRow({
    required this.server,
    required this.selected,
    required this.pingText,
    required this.onTap,
  });

  final SpeedTestServer server;
  final bool selected;
  final String pingText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: selected ? TColors.cardBorder : null,
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? TColors.cyan : Colors.white54,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(server.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600)),
                    Text(server.location,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _CapChip(label: 'PING', on: true),
                        _CapChip(
                            label: 'DL',
                            on: server.supportsDownload),
                        _CapChip(
                            label: 'UL',
                            on: server.supportsUpload),
                      ],
                    ),
                  ],
                ),
              ),
              Text(
                pingText,
                style: TextStyle(
                  color: pingText == 'unreachable'
                      ? TColors.red
                      : TColors.amber,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CapChip extends StatelessWidget {
  const _CapChip({required this.label, required this.on});

  final String label;
  final bool on;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: on ? TColors.cyan.withValues(alpha: 0.15) : Colors.white10,
        border: Border.all(
            color: on ? TColors.cyan.withValues(alpha: 0.5) : Colors.white24),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: on ? TColors.cyan : Colors.white38,
        ),
      ),
    );
  }
}

class _PhaseLabel extends StatelessWidget {
  const _PhaseLabel(
      {required this.phase, this.liveMbps, required this.unit});

  final _Phase phase;
  final double? liveMbps;
  final SpeedUnit unit;

  @override
  Widget build(BuildContext context) {
    final live = liveMbps == null ? '--' : unit.format(liveMbps!);
    final text = switch (phase) {
      _Phase.idle => 'Ready when you are',
      _Phase.latency => 'Pinging server\u2026',
      _Phase.download => 'Downloading\u2026 $live ${unit.label}',
      _Phase.upload => 'Uploading\u2026 $live ${unit.label}',
      _Phase.done => 'Test complete',
      _Phase.error => 'Something went wrong',
    };
    final color = switch (phase) {
      _Phase.error => TColors.red,
      _Phase.done => TColors.green,
      _Phase.idle => Colors.white70,
      _ => TColors.cyan,
    };
    return Text(
      text,
      style: TextStyle(
          fontSize: 18, fontWeight: FontWeight.bold, color: color),
    );
  }
}
