import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'alarms.dart';
import 'settings.dart';

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  Map<String, dynamic>? _health;
  String? _error;
  Timer? _timer;
  bool _fetching = false;

  String _relayBase = Settings.defaultYeshieHost;

  // Health-trigger state: streak counts, last-notified timestamps, previous statuses
  final Map<String, int> _nonGreenStreak = {};
  final Map<String, DateTime> _lastNotified = {};
  final Map<String, int> _prevStatus = {};

  @override
  void initState() {
    super.initState();
    _loadHost().then((_) {
      _fetch();
      _timer = Timer.periodic(const Duration(seconds: 5), (_) => _fetch());
    });
  }

  Future<void> _loadHost() async {
    final host = await Settings.yeshieHost();
    if (mounted) setState(() => _relayBase = host);
  }

  // Fire Android notifications on green→non-green / non-green→green transitions.
  // Debounce: component must be non-green for 2 consecutive polls before alerting.
  // Rate-limit: max one degradation alert per component per hour.
  void _checkHealthTransitions(Map<String, dynamic> components) {
    if (kIsWeb) return;
    final now = DateTime.now();
    for (final entry in components.entries) {
      final name = entry.key;
      final status = (entry.value['status'] as int?) ?? 0;
      final msg = (entry.value['msg'] as String?) ?? '';

      if (status > 0) {
        _nonGreenStreak[name] = (_nonGreenStreak[name] ?? 0) + 1;
        if (_nonGreenStreak[name]! >= 2) {
          final last = _lastNotified[name];
          if (last == null || now.difference(last) >= const Duration(hours: 1)) {
            AlarmService.instance.notifyHealthAlert(name, msg, false);
            _lastNotified[name] = now;
          }
        }
      } else {
        // Back to green — send recovery only if we previously sent a degradation alert
        if (_lastNotified.containsKey(name)) {
          AlarmService.instance.notifyHealthAlert(name, 'Back to normal', true);
          _lastNotified.remove(name);
        }
        _nonGreenStreak[name] = 0;
      }
      _prevStatus[name] = status;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    if (_fetching) return;
    _fetching = true;
    try {
      final resp = await http
          .get(Uri.parse('$_relayBase/health'))
          .timeout(const Duration(seconds: 4));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() {
          _health = data;
          _error = null;
        });
        final components = (data['components'] as Map<String, dynamic>?) ?? {};
        _checkHealthTransitions(components);
      } else {
        setState(() => _error = 'HTTP ${resp.statusCode}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      _fetching = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SelectionArea(child: Scaffold(
      appBar: AppBar(
        title: const Text('Pulse — Health'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _fetch,
          ),
        ],
      ),
      body: _error != null && _health == null
          ? Center(
              child: Text(
                'Error: $_error',
                style: const TextStyle(color: Colors.red),
              ),
            )
          : _health == null
              ? const Center(child: CircularProgressIndicator())
              : _buildBody(theme),
    ));
  }

  Widget _buildBody(ThemeData theme) {
    final overall = (_health!['overall'] as String?) ?? '?';
    final failStreak = (_health!['fail_streak'] as int?) ?? 0;
    final tsLocal = (_health!['ts_local'] as String?) ?? '';
    final components =
        (_health!['components'] as Map<String, dynamic>?) ?? {};

    final overallColor = _statusColor(
      overall == 'ok'
          ? 0
          : overall == 'degraded'
              ? 1
              : 2,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Header card
        Card(
          color: overallColor.withOpacity(0.15),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.circle, color: overallColor, size: 12),
                    const SizedBox(width: 8),
                    Text(
                      'Overall: $overall',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: overallColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                SelectableText(
                  'Fail streak: $failStreak',
                  style: theme.textTheme.bodySmall,
                ),
                SelectableText(tsLocal, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Services', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        ...components.entries.map(
          (e) => _ServicePill(
            name: e.key,
            status: (e.value['status'] as int?) ?? 0,
            msg: (e.value['msg'] as String?) ?? '',
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Poll error: $_error',
              style: TextStyle(
                color: Colors.orange.shade300,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
      ],
    );
  }

  static Color _statusColor(int status) => switch (status) {
        0 => Colors.green,
        1 => Colors.amber,
        _ => Colors.red,
      };
}

class _ServicePill extends StatelessWidget {
  final String name;
  final int status;
  final String msg;

  const _ServicePill({
    required this.name,
    required this.status,
    required this.msg,
  });

  static Color _color(int s) => switch (s) {
        0 => Colors.green,
        1 => Colors.amber,
        _ => Colors.red,
      };

  @override
  Widget build(BuildContext context) {
    final color = _color(status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: color.withOpacity(0.4)),
          borderRadius: BorderRadius.circular(8),
          color: color.withOpacity(0.07),
        ),
        child: ListTile(
          dense: true,
          leading: Icon(Icons.circle, color: color, size: 10),
          title: Text(
            name,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
            ),
          ),
          subtitle: SelectableText(
            msg,
            style: TextStyle(
              color: color.withOpacity(0.85),
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}
