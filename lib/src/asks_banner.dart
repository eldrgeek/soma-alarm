import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'alarms.dart';
import 'settings.dart';

/// Pending human-in-the-loop asks from the Yeshie relay (`cc hud-ask`).
/// Replaces the retired Mac HUD overlay: polls GET /hud/asks, answers via
/// POST /hud/response/:id. Renders nothing when there are no pending asks.
class AsksBanner extends StatefulWidget {
  const AsksBanner({super.key});

  @override
  State<AsksBanner> createState() => _AsksBannerState();
}

class _AsksBannerState extends State<AsksBanner> {
  List<Map<String, dynamic>> _asks = [];
  Timer? _timer;
  bool _fetching = false;
  String _relayBase = Settings.defaultYeshieHost;

  // Asks we've already fired an Android notification for.
  final Set<String> _notified = {};
  // Asks being answered right now (button pressed, POST in flight).
  final Set<String> _answering = {};

  @override
  void initState() {
    super.initState();
    Settings.yeshieHost().then((host) {
      if (mounted) setState(() => _relayBase = host);
      _fetch();
      _timer = Timer.periodic(const Duration(seconds: 5), (_) => _fetch());
    });
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
          .get(Uri.parse('$_relayBase/hud/asks'))
          .timeout(const Duration(seconds: 4));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        final list = (decoded is Map<String, dynamic> ? decoded['asks'] : null);
        final asks = (list is List)
            ? list.whereType<Map<String, dynamic>>().toList()
            : <Map<String, dynamic>>[];
        setState(() => _asks = asks);
        if (!kIsWeb) {
          for (final a in asks) {
            final id = a['id'] as String? ?? '';
            if (id.isNotEmpty && !_notified.contains(id)) {
              _notified.add(id);
              AlarmService.instance
                  .notifyAsk(id, a['message'] as String? ?? '');
            }
          }
        }
      }
    } catch (_) {
      // Relay unreachable — keep showing last known asks; poll again in 5s.
    } finally {
      _fetching = false;
    }
  }

  Future<void> _answer(String id, String response) async {
    setState(() => _answering.add(id));
    try {
      final resp = await http
          .post(
            Uri.parse('$_relayBase/hud/response/$id'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'response': response}),
          )
          .timeout(const Duration(seconds: 5));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        setState(() => _asks.removeWhere((a) => a['id'] == id));
      } else {
        _showError('Answer failed: HTTP ${resp.statusCode}');
      }
    } catch (e) {
      if (mounted) _showError('$e');
    } finally {
      if (mounted) setState(() => _answering.remove(id));
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    if (_asks.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Material(
      color: Colors.deepPurple.withOpacity(0.12),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _asks.map((a) {
            final id = a['id'] as String? ?? '';
            final message = a['message'] as String? ?? '';
            final age = a['ageSeconds'] as int? ?? 0;
            final busy = _answering.contains(id);
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.help_outline,
                          size: 16, color: Colors.deepPurpleAccent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: SelectableText(
                          message,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      Text(
                        age < 60 ? '${age}s' : '${age ~/ 60}m',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: busy
                        ? const [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ]
                        : [
                            TextButton(
                              onPressed: () => _answer(id, 'failed'),
                              style: TextButton.styleFrom(
                                  foregroundColor: Colors.red.shade300),
                              child: const Text('Failed'),
                            ),
                            TextButton(
                              onPressed: () => _answer(id, 'partial'),
                              style: TextButton.styleFrom(
                                  foregroundColor: Colors.amber.shade700),
                              child: const Text('Partial'),
                            ),
                            FilledButton(
                              onPressed: () => _answer(id, 'confirm'),
                              child: const Text('Confirm'),
                            ),
                          ],
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
