import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How often every host is pinged.
const pingInterval = Duration(seconds: 5);

/// A host is reported down only after this long without a successful ping.
const downThreshold = Duration(seconds: 10);

const _notifChannelId = 'net_toolkit_pro_v1';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

class HostEntry {
  HostEntry({
    required this.name,
    required this.ip,
    required this.addedAt,
    this.isUp,
    this.latencyMs,
    this.lastSuccess,
    this.downNotified = false,
  });

  String name;
  String ip;
  bool? isUp; // null = not checked yet
  int? latencyMs;
  DateTime? lastSuccess;
  DateTime addedAt;
  bool downNotified;

  Map<String, dynamic> toJson() => {
        'name': name,
        'ip': ip,
        'addedAt': addedAt.millisecondsSinceEpoch,
      };

  factory HostEntry.fromJson(Map<String, dynamic> j) => HostEntry(
        name: (j['name'] ?? '').toString(),
        ip: (j['ip'] ?? '').toString(),
        addedAt: DateTime.fromMillisecondsSinceEpoch(
            (j['addedAt'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch),
      );
}

// ---------------------------------------------------------------------------
// Ping
// ---------------------------------------------------------------------------

/// Returns latency in ms, or null when the host did not answer.
Future<int?> pingHost(String ip) async {
  // 1) Try the OS ping binary (ICMP, no root needed on Android).
  try {
    final args = Platform.isWindows
        ? ['-n', '1', '-w', '2000', ip]
        : ['-c', '1', '-W', '2', ip];
    final res =
        await Process.run('ping', args).timeout(const Duration(seconds: 5));
    if (res.exitCode == 0) {
      final m = RegExp(r'time[=<]([\d.]+)\s?ms')
          .firstMatch(res.stdout.toString());
      if (m != null) return double.parse(m.group(1)!).round();
      return 0;
    }
  } catch (_) {
    // fall through to TCP fallback
  }

  // 2) Fallback: TCP connect to common ports (works when the ping binary
  //    is missing but the network stack is reachable).
  for (final port in [80, 443]) {
    try {
      final sw = Stopwatch()..start();
      final socket = await Socket.connect(ip, port,
          timeout: const Duration(seconds: 2));
      socket.destroy();
      return sw.elapsedMilliseconds;
    } catch (_) {}
  }
  return null;
}

// ---------------------------------------------------------------------------
// Monitor service
// ---------------------------------------------------------------------------

class MonitorService extends ChangeNotifier {
  MonitorService(this._prefs);

  final SharedPreferences _prefs;
  final FlutterLocalNotificationsPlugin _notif =
      FlutterLocalNotificationsPlugin();

  final List<HostEntry> hosts = [];
  Timer? _timer;
  bool _checking = false;

  int get upCount => hosts.where((h) => h.isUp == true).length;
  int get downCount => hosts.where((h) => h.isUp == false).length;

  Future<void> init() async {
    _load();
    await _initNotifications();
    await _requestPermission();
    _timer = Timer.periodic(pingInterval, (_) => _checkAll());
    unawaited(_checkAll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Public entry used by pull-to-refresh.
  Future<void> checkNow() => _checkAll();

  // -- persistence ----------------------------------------------------------

  void _load() {
    try {
      final raw = _prefs.getString('hosts_v1');
      if (raw == null) return;
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      hosts
        ..clear()
        ..addAll(list.map(HostEntry.fromJson).where((h) => h.ip.isNotEmpty));
    } catch (_) {}
  }

  void _save() {
    try {
      _prefs.setString(
          'hosts_v1', jsonEncode(hosts.map((h) => h.toJson()).toList()));
    } catch (_) {}
  }

  // -- notifications --------------------------------------------------------

  Future<void> _initNotifications() async {
    // Desktop platforms (Linux/Windows/macOS) have no notification setup
    // here; skip quietly instead of crashing startup.
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _notif.initialize(settings: settings);
      const channel = AndroidNotificationChannel(
        _notifChannelId,
        'Network Toolkit Pro',
        description: 'Link up/down alerts',
        importance: Importance.high,
      );
      await _notif
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    } catch (_) {}
  }

  Future<void> _requestPermission() async {
    await _notif
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  int _idFor(String ip, int salt) => (ip.hashCode ^ salt) & 0x7fffffff;

  Future<void> _notifyDown(HostEntry h) => _notif.show(
        id: _idFor(h.ip, 0xD09A),
        title: '${h.name} link is down',
        body: 'No ping reply for 10 seconds \u2022 ${h.ip}',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _notifChannelId,
            'Network Toolkit Pro',
            channelDescription: 'Link up/down alerts',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );

  Future<void> _notifyUp(HostEntry h) => _notif.show(
        id: _idFor(h.ip, 0x9E11),
        title: '${h.name} link is back up',
        body: 'Ping reply received \u2022 ${h.ip}',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _notifChannelId,
            'Network Toolkit Pro',
            channelDescription: 'Link up/down alerts',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );

  // -- monitoring loop ------------------------------------------------------

  Future<void> _checkAll() async {
    if (_checking || hosts.isEmpty) return;
    _checking = true;
    try {
      await Future.wait(hosts.map(_pingAndUpdate));
    } finally {
      _checking = false;
      _save();
      notifyListeners();
    }
  }

  Future<void> _pingAndUpdate(HostEntry h) async {
    final ms = await pingHost(h.ip);
    final now = DateTime.now();
    if (ms != null) {
      final wasDown = h.isUp == false;
      h.isUp = true;
      h.latencyMs = ms;
      h.lastSuccess = now;
      h.downNotified = false;
      if (wasDown) {
        try {
          await _notifyUp(h);
        } catch (_) {}
      }
    } else {
      h.isUp = false;
      h.latencyMs = null;
      final ref = h.lastSuccess ?? h.addedAt;
      if (!h.downNotified && now.difference(ref) >= downThreshold) {
        h.downNotified = true;
        try {
          await _notifyDown(h);
        } catch (_) {}
      }
    }
  }

  // -- mutations ------------------------------------------------------------

  bool addHost(String name, String ip) {
    final cleanIp = ip.trim();
    if (cleanIp.isEmpty) return false;
    if (hosts.any((h) => h.ip == cleanIp)) return false;
    hosts.add(HostEntry(
      name: name.trim().isEmpty ? cleanIp : name.trim(),
      ip: cleanIp,
      addedAt: DateTime.now(),
    ));
    _save();
    notifyListeners();
    unawaited(_checkAll());
    return true;
  }

  /// Imports Name/IP rows from an .xlsx/.xls file. Returns a status message.
  Future<String> importExcel() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );
      if (files.isEmpty) {
        return 'No file selected';
      }
      final bytes = await files.first.readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      if (excel.tables.isEmpty) return 'No sheets found in file';
      final rows = excel.tables[excel.tables.keys.first]!.rows;
      if (rows.isEmpty) return 'Sheet is empty';

      int start = 0;
      final head = rows.first
          .map((c) => (c?.value?.toString() ?? '').toLowerCase())
          .join(' ');
      if (head.contains('name') ||
          head.contains('ip') ||
          head.contains('host')) {
        start = 1;
      }

      int added = 0;
      for (var i = start; i < rows.length; i++) {
        final row = rows[i];
        final name =
            row.isNotEmpty ? (row[0]?.value?.toString().trim() ?? '') : '';
        final ip =
            row.length > 1 ? (row[1]?.value?.toString().trim() ?? '') : '';
        if (ip.isEmpty) continue;
        if (hosts.any((h) => h.ip == ip)) continue;
        hosts.add(HostEntry(
          name: name.isEmpty ? ip : name,
          ip: ip,
          addedAt: DateTime.now(),
        ));
        added++;
      }
      _save();
      notifyListeners();
      unawaited(_checkAll());
      return added == 0
          ? 'No new hosts found (duplicates skipped)'
          : 'Added $added host${added == 1 ? '' : 's'}';
    } catch (e) {
      return 'Could not read file: $e';
    }
  }

  void loadDemo() {
    for (final d in [
      ('Google DNS', '8.8.8.8'),
      ('Cloudflare DNS', '1.1.1.1'),
      ('Demo Down Host', '192.0.2.1'),
    ]) {
      if (hosts.any((h) => h.ip == d.$2)) continue;
      hosts.add(HostEntry(name: d.$1, ip: d.$2, addedAt: DateTime.now()));
    }
    _save();
    notifyListeners();
    unawaited(_checkAll());
  }

  void removeHost(HostEntry h) {
    hosts.remove(h);
    _save();
    notifyListeners();
  }

  void clearAll() {
    hosts.clear();
    _save();
    notifyListeners();
  }
}
