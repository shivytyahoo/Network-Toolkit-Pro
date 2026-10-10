import 'package:flutter/material.dart';

import '../net/lan_discovery.dart';
import 'common.dart';

/// Tab 4 — LAN discovery: sweep the local subnet for live hosts.
class LanTab extends StatefulWidget {
  const LanTab({super.key});

  @override
  State<LanTab> createState() => _LanTabState();
}

class _LanTabState extends State<LanTab> {
  bool _scanning = false;
  bool _cancel = false;
  int _scanned = 0;
  String? _subnet;
  String? _ownIp;
  List<LanHostInfo> _hosts = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _detectSubnet();
  }

  Future<void> _detectSubnet() async {
    final base = await localSubnetBase();
    final ip = await localIpAddress();
    if (!mounted) return;
    setState(() {
      _subnet = base == null ? null : '$base.0/24';
      _ownIp = ip;
    });
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _cancel = false;
      _scanned = 0;
      _hosts = [];
      _error = null;
    });
    try {
      final hosts = await discoverHosts(
        onProgress: (scanned, total) {
          if (!mounted) return;
          setState(() => _scanned = scanned);
        },
        isCancelled: () => _cancel,
      );
      if (!mounted) return;
      setState(() {
        _hosts = hosts;
        _scanning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _error = e is StateError ? e.message : 'Scan failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: TColors.purple.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.hub_outlined,
                              color: TColors.purple),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _subnet ?? 'Detecting network\u2026',
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold),
                              ),
                              Text(
                                _ownIp == null
                                    ? ''
                                    : 'This device: $_ownIp',
                                style: const TextStyle(
                                    color: Colors.white60, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: _scanning
                          ? FilledButton.tonalIcon(
                              onPressed: () =>
                                  setState(() => _cancel = true),
                              icon: const Icon(Icons.stop),
                              label: Text('Scanning $_scanned/254\u2026'),
                            )
                          : FilledButton.icon(
                              onPressed: _scan,
                              icon: const Icon(Icons.search),
                              label: const Text('Discover devices'),
                            ),
                    ),
                    if (_scanning) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: _scanned / 254,
                        borderRadius: BorderRadius.circular(8),
                        minHeight: 8,
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: const TextStyle(color: TColors.red)),
                    ],
                  ],
                ),
              ),
            ),
            if (!_scanning && _hosts.isNotEmpty) ...[
              const SectionTitle('LIVE HOSTS'),
              BigStat(
                label: 'DEVICES FOUND',
                value: '${_hosts.length}',
                color: TColors.green,
              ),
              const SizedBox(height: 8),
              for (final h in _hosts)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: TColors.green,
                        boxShadow: [
                          BoxShadow(
                            color: TColors.green.withValues(alpha: 0.8),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                    title: Text(
                      h.hostname ?? h.ip,
                      style:
                          const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      h.hostname == null
                          ? '${h.latencyMs} ms response'
                          : '${h.ip} \u2022 ${h.latencyMs} ms',
                      style: const TextStyle(color: Colors.white60),
                    ),
                    trailing: h.ip == _ownIp
                        ? const Pill(text: 'THIS DEVICE', color: TColors.cyan)
                        : null,
                  ),
                ),
            ],
            if (!_scanning && _hosts.isEmpty && _error == null) ...[
              const SizedBox(height: 24),
              const Center(
                child: Text(
                  'Tap "Discover devices" to sweep your local network\nfor phones, PCs, printers, cameras and more.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
