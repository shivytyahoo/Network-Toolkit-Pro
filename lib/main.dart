import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ping/monitor.dart';
import 'ui/about_page.dart';
import 'ui/common.dart';
import 'ui/lan_tab.dart';
import 'ui/ping_tab.dart';
import 'ui/port_tab.dart';
import 'ui/speed_tab.dart';
import 'ui/wifi_tab.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final monitor = MonitorService(prefs);
  await monitor.init();
  runApp(NetworkToolkitApp(monitor: monitor));
}

class NetworkToolkitApp extends StatelessWidget {
  const NetworkToolkitApp({super.key, required this.monitor});

  final MonitorService monitor;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Network Toolkit Pro',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: HomeShell(monitor: monitor),
    );
  }
}

class _TabDef {
  const _TabDef(this.label, this.icon, this.activeIcon);

  final String label;
  final IconData icon;
  final IconData activeIcon;
}

const _tabs = [
  _TabDef('Ping', Icons.radar_outlined, Icons.radar),
  _TabDef('Speed', Icons.speed_outlined, Icons.speed),
  _TabDef('Ports', Icons.door_front_door_outlined, Icons.door_front_door),
  _TabDef('LAN', Icons.hub_outlined, Icons.hub),
  _TabDef('Wi-Fi', Icons.wifi_outlined, Icons.wifi),
];

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.monitor});

  final MonitorService monitor;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      PingTab(monitor: widget.monitor),
      const SpeedTab(),
      const PortTab(),
      const LanTab(),
      const WifiTab(),
    ];
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [TColors.bgGlow, TColors.bgDeep],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [TColors.cyan, TColors.blue],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child:
                  const Icon(Icons.network_check, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Network Toolkit Pro',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  Text(_tabs[_index].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white60)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_index == 0) PingTabActions(monitor: widget.monitor),
          IconButton(
            tooltip: 'About',
            icon: const Icon(Icons.info_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AboutPage()),
            ),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: pages),
      floatingActionButton: _index == 0
          ? ListenableBuilder(
              listenable: widget.monitor,
              builder: (context, _) => widget.monitor.hosts.isEmpty
                  ? const SizedBox.shrink()
                  : PingTabFab(monitor: widget.monitor),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final t in _tabs)
            NavigationDestination(
              icon: Icon(t.icon),
              selectedIcon: Icon(t.activeIcon),
              label: t.label,
            ),
        ],
      ),
    );
  }
}
