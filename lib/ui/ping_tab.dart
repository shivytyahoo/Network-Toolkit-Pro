import 'package:flutter/material.dart';

import '../ping/monitor.dart';
import 'common.dart';

/// Tab 1 — continuous ping monitor (reused from the Link Monitor app).
class PingTab extends StatelessWidget {
  const PingTab({super.key, required this.monitor});

  final MonitorService monitor;

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: SafeArea(
        child: ListenableBuilder(
          listenable: monitor,
          builder: (context, _) => Column(
            children: [
              _StatsRow(monitor: monitor),
              Expanded(
                child: monitor.hosts.isEmpty
                    ? _EmptyState(monitor: monitor)
                    : RefreshIndicator(
                        onRefresh: () => monitor.checkNow(),
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                          itemCount: monitor.hosts.length,
                          itemBuilder: (context, i) {
                            final h = monitor.hosts[i];
                            return Dismissible(
                              key: ValueKey(h.ip),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 24),
                                decoration: BoxDecoration(
                                  color: TColors.red.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Icon(Icons.delete_outline,
                                    color: TColors.red),
                              ),
                              onDismissed: (_) => monitor.removeHost(h),
                              child: _HostCard(host: h),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.monitor});

  final MonitorService monitor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          BigStat(
              label: 'UP', value: '${monitor.upCount}', color: TColors.green),
          const SizedBox(width: 12),
          BigStat(
              label: 'DOWN',
              value: '${monitor.downCount}',
              color: TColors.red),
          const SizedBox(width: 12),
          BigStat(
              label: 'TOTAL',
              value: '${monitor.hosts.length}',
              color: TColors.cyan),
        ],
      ),
    );
  }
}

class _HostCard extends StatelessWidget {
  const _HostCard({required this.host});

  final HostEntry host;

  @override
  Widget build(BuildContext context) {
    final up = host.isUp;
    final dotColor = up == null
        ? Colors.grey
        : up
            ? TColors.green
            : TColors.red;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dotColor,
            boxShadow: [
              BoxShadow(
                  color: dotColor.withValues(alpha: 0.8),
                  blurRadius: 10,
                  spreadRadius: 2),
            ],
          ),
        ),
        title: Text(host.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(_subtitle(),
            style: const TextStyle(color: Colors.white60, fontSize: 13)),
        trailing: Pill(
          text: up == null ? 'WAIT' : up ? 'UP' : 'DOWN',
          color: dotColor,
        ),
      ),
    );
  }

  String _subtitle() {
    if (host.isUp == true) {
      return '${host.ip} \u2022 ${host.latencyMs ?? 0} ms \u2022 seen ${ago(host.lastSuccess)}';
    }
    if (host.isUp == false) {
      return '${host.ip} \u2022 no reply \u2022 last seen ${ago(host.lastSuccess)}';
    }
    return '${host.ip} \u2022 checking\u2026';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.monitor});

  final MonitorService monitor;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: TColors.cyan.withValues(alpha: 0.1),
              ),
              child: const Icon(Icons.radar, size: 56, color: TColors.cyan),
            ),
            const SizedBox(height: 20),
            const Text('No hosts yet',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'Add a host manually, or import an Excel sheet with Name in column A and IP in column B.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _showAddDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Add host'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () async {
                final msg = await monitor.importExcel();
                if (context.mounted) showMsg(context, msg);
              },
              icon: const Icon(Icons.upload_file),
              label: const Text('Import Excel'),
            ),
            TextButton(
              onPressed: monitor.loadDemo,
              child: const Text('or load demo data'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final ipCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add host'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Name'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ipCtrl,
              decoration: const InputDecoration(
                  labelText: 'IP or hostname', hintText: '192.168.1.1'),
              keyboardType: TextInputType.url,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final ok = monitor.addHost(nameCtrl.text, ipCtrl.text);
              Navigator.pop(ctx);
              showMsg(context,
                  ok ? 'Host added' : 'Enter an IP (duplicates are skipped)');
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

/// FAB + overflow actions for the Ping tab, shown by the shell.
class PingTabActions extends StatelessWidget {
  const PingTabActions({super.key, required this.monitor});

  final MonitorService monitor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Import Excel',
          icon: const Icon(Icons.upload_file_outlined),
          onPressed: () async {
            final msg = await monitor.importExcel();
            if (context.mounted) showMsg(context, msg);
          },
        ),
        IconButton(
          tooltip: 'Clear all',
          icon: const Icon(Icons.delete_sweep_outlined),
          onPressed: () => _confirmClear(context),
        ),
      ],
    );
  }

  void _confirmClear(BuildContext context) {
    if (monitor.hosts.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all hosts?'),
        content:
            const Text('This removes every monitored IP from the list.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              monitor.clearAll();
              Navigator.pop(ctx);
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

/// Floating action button for the Ping tab.
class PingTabFab extends StatelessWidget {
  const PingTabFab({super.key, required this.monitor});

  final MonitorService monitor;

  @override
  Widget build(BuildContext context) {
    final nameCtrl = TextEditingController();
    final ipCtrl = TextEditingController();
    return FloatingActionButton.extended(
      onPressed: () {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Add host'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name'),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ipCtrl,
                  decoration: const InputDecoration(
                      labelText: 'IP or hostname',
                      hintText: '192.168.1.1'),
                  keyboardType: TextInputType.url,
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  final ok = monitor.addHost(nameCtrl.text, ipCtrl.text);
                  Navigator.pop(ctx);
                  showMsg(context,
                      ok ? 'Host added' : 'Enter an IP (duplicates skipped)');
                },
                child: const Text('Add'),
              ),
            ],
          ),
        );
      },
      icon: const Icon(Icons.add),
      label: const Text('Add host'),
    );
  }
}
