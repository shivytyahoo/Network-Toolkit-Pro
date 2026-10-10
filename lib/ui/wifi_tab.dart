import 'package:flutter/material.dart';

import '../net/wifi_service.dart';
import 'common.dart';

/// Tab 5 — current Wi-Fi connection details.
class WifiTab extends StatefulWidget {
  const WifiTab({super.key});

  @override
  State<WifiTab> createState() => _WifiTabState();
}

class _WifiTabState extends State<WifiTab> {
  WifiDetails? _details;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final d = await createWifiProvider().fetch();
    if (!mounted) return;
    setState(() {
      _details = d;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = _details;
    return GradientBackground(
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _SignalBadge(details: d, loading: _loading),
                      const SizedBox(height: 12),
                      Text(
                        d?.connected == true
                            ? (d!.ssid ?? 'Connected')
                            : 'Not connected',
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      if (d?.connected == true)
                        const Pill(text: 'CONNECTED', color: TColors.green)
                      else if (!_loading)
                        const Pill(
                            text: 'DISCONNECTED', color: Colors.white38),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          onPressed: _loading ? null : _refresh,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (d?.connected == true) ...[
                const SectionTitle('DETAILS'),
                _row(Icons.tag, 'BSSID', d!.bssid ?? '--'),
                _row(Icons.network_cell, 'Signal',
                    _signalText(d)),
                _row(Icons.sensors, 'Frequency', _freqText(d)),
                _row(Icons.memory, 'IP address', d.ipAddress ?? '--'),
                if (d.radioType != null)
                  _row(Icons.wifi, 'Radio', d.radioType!),
                _row(Icons.source_outlined, 'Source', d.source ?? '--'),
                const SizedBox(height: 12),
                const Text(
                  'On Android, the SSID needs location permission \u2014 '
                  'grant it when asked, then refresh.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: TColors.cyan),
        title: Text(label, style: const TextStyle(color: Colors.white60)),
        trailing: Text(value,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 15)),
      ),
    );
  }

  String _signalText(WifiDetails d) {
    if (d.signalPercent == null) return '--';
    final dbm =
        d.signalDbm == null ? '' : ' (${d.signalDbm} dBm)';
    return '${d.signalPercent}%$dbm';
  }

  String _freqText(WifiDetails d) {
    if (d.frequencyMhz == null) return '--';
    final ghz = d.frequencyMhz! / 1000;
    final band = d.frequencyMhz! < 3000
        ? '2.4 GHz'
        : d.frequencyMhz! < 6000
            ? '5 GHz'
            : '6 GHz';
    return '${ghz.toStringAsFixed(3)} GHz ($band)';
  }
}

class _SignalBadge extends StatelessWidget {
  const _SignalBadge({required this.details, required this.loading});

  final WifiDetails? details;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final pct = details?.signalPercent;
    final color = pct == null
        ? Colors.white38
        : pct >= 70
            ? TColors.green
            : pct >= 40
                ? TColors.amber
                : TColors.red;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.1),
      ),
      child: loading
          ? const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(),
            )
          : Icon(Icons.signal_wifi_4_bar,
              size: 56, color: pct == null ? Colors.white38 : color),
    );
  }
}
