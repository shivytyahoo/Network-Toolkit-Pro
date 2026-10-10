import 'package:flutter/material.dart';

import 'common.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: GradientBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [TColors.cyan, TColors.blue],
                        ),
                      ),
                      child: const Icon(Icons.network_check,
                          size: 44, color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    const Text('Network Toolkit Pro',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold)),
                    const Text('v1.0.0',
                        style: TextStyle(color: Colors.white60)),
                    const SizedBox(height: 12),
                    const Text(
                      'Five network utilities in one app: live ping monitoring with down alerts, internet speed test, TCP port scanner, LAN device discovery and Wi-Fi details.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Card(
              child: ListTile(
                leading: Icon(Icons.radar, color: TColors.cyan),
                title: Text('Ping Monitor'),
                subtitle: Text(
                    'Watches your hosts every 5 seconds and notifies you after 10 seconds of no reply. Import hosts from Excel.'),
              ),
            ),
            const Card(
              child: ListTile(
                leading: Icon(Icons.speed, color: TColors.purple),
                title: Text('Speed Test'),
                subtitle: Text(
                    'Measures latency, download and upload speed using Cloudflare\u2019s public endpoints.'),
              ),
            ),
            const Card(
              child: ListTile(
                leading:
                    Icon(Icons.door_front_door_outlined, color: TColors.amber),
                title: Text('Port Scanner'),
                subtitle: Text(
                    'TCP-connect scan of common or custom ports on any host, with per-port response times.'),
              ),
            ),
            const Card(
              child: ListTile(
                leading: Icon(Icons.hub_outlined, color: TColors.green),
                title: Text('LAN Discovery'),
                subtitle: Text(
                    'Sweeps your local subnet for live devices and tries reverse-DNS hostnames.'),
              ),
            ),
            const Card(
              child: ListTile(
                leading: Icon(Icons.wifi, color: TColors.blue),
                title: Text('Wi-Fi Info'),
                subtitle: Text(
                    'SSID, BSSID, signal strength, frequency and IP \u2014 on Android, Windows and Linux.'),
              ),
            ),
            const Card(
              child: ListTile(
                leading: Icon(Icons.code, color: TColors.cyan),
                title: Text('Developer'),
                subtitle: Text('Shivam Bhalla',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
}
