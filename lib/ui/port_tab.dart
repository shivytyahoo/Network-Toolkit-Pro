import 'package:flutter/material.dart';

import '../net/port_scan.dart';
import 'common.dart';

/// Tab 3 — TCP port scanner.
class PortTab extends StatefulWidget {
  const PortTab({super.key});

  @override
  State<PortTab> createState() => _PortTabState();
}

class _PortTabState extends State<PortTab> {
  final _hostCtrl = TextEditingController(text: '192.168.1.1');
  final _portsCtrl = TextEditingController();

  bool _scanning = false;
  bool _cancel = false;
  int _done = 0;
  int _total = 0;
  List<PortScanResult> _results = [];
  String? _error;

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portsCtrl.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final host = _hostCtrl.text.trim();
    if (host.isEmpty) {
      showMsg(context, 'Enter a target host or IP');
      return;
    }
    List<PortInfo> ports;
    if (_portsCtrl.text.trim().isEmpty) {
      ports = kCommonPorts;
    } else {
      ports = parsePortSpec(_portsCtrl.text);
      if (ports.isEmpty) {
        showMsg(context, 'No valid ports. Try e.g. 80,443,8000-8100');
        return;
      }
    }
    setState(() {
      _scanning = true;
      _cancel = false;
      _done = 0;
      _total = ports.length;
      _results = [];
      _error = null;
    });
    try {
      final results = await scanPorts(
        host,
        ports: ports,
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _done = done;
            _total = total;
          });
        },
        isCancelled: () => _cancel,
      );
      if (!mounted) return;
      setState(() {
        _results = results;
        _scanning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _error = 'Scan failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final open = _results.where((r) => r.open).toList();
    return GradientBackground(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _hostCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Target host',
                        hintText: '192.168.1.1 or example.com',
                        prefixIcon: Icon(Icons.computer_outlined),
                      ),
                      keyboardType: TextInputType.url,
                      enabled: !_scanning,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _portsCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Ports (optional)',
                        hintText: 'blank = common ports, or e.g. 80,443,8000-8100',
                        prefixIcon: Icon(Icons.numbers_outlined),
                      ),
                      keyboardType: TextInputType.text,
                      enabled: !_scanning,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: _scanning
                          ? FilledButton.tonalIcon(
                              onPressed: () =>
                                  setState(() => _cancel = true),
                              icon: const Icon(Icons.stop),
                              label: Text('Scanning $_done/$_total\u2026'),
                            )
                          : FilledButton.icon(
                              onPressed: _scan,
                              icon: const Icon(Icons.radar),
                              label: const Text('Scan ports'),
                            ),
                    ),
                    if (_scanning) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: _total == 0 ? null : _done / _total,
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
            if (!_scanning && _results.isNotEmpty) ...[
              const SectionTitle('RESULTS'),
              Row(
                children: [
                  BigStat(
                      label: 'OPEN',
                      value: '${open.length}',
                      color: TColors.green),
                  const SizedBox(width: 12),
                  BigStat(
                      label: 'CLOSED',
                      value: '${_results.length - open.length}',
                      color: Colors.white54),
                  const SizedBox(width: 12),
                  BigStat(
                      label: 'SCANNED',
                      value: '${_results.length}',
                      color: TColors.cyan),
                ],
              ),
              const SizedBox(height: 8),
              if (open.isEmpty)
                const Card(
                  child: ListTile(
                    leading:
                        Icon(Icons.check_circle_outline, color: TColors.green),
                    title: Text('No open ports found'),
                    subtitle: Text(
                        'The host is not accepting TCP connections on the scanned ports.'),
                  ),
                ),
              for (final r in _results)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      r.open
                          ? Icons.lock_open_outlined
                          : Icons.lock_outline,
                      color: r.open ? TColors.green : Colors.white38,
                    ),
                    title: Text(
                      'Port ${r.port} \u2022 ${r.service}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: r.open && r.latencyMs != null
                        ? Text('${r.latencyMs} ms response',
                            style:
                                const TextStyle(color: Colors.white60))
                        : const Text('no response',
                            style: TextStyle(color: Colors.white38)),
                    trailing: Pill(
                      text: r.open ? 'OPEN' : 'CLOSED',
                      color: r.open ? TColors.green : Colors.white38,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
