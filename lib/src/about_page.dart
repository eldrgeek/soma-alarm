import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'dee_stream/dee_said_client.dart';
import 'dee_stream/dee_stream_page.dart';
import 'dee_stream/relay_resolver.dart';
import 'settings.dart';

const String _kVersion = '0.2.1+6';
const String _kBuildSha =
    String.fromEnvironment('BUILD_SHA', defaultValue: 'dev');
const String _kBuildTime =
    String.fromEnvironment('BUILD_TIME', defaultValue: '');
const String _kBuildChangelog =
    String.fromEnvironment('BUILD_CHANGELOG', defaultValue: '');

/// About / Status — version, configured host, live connection status,
/// stream health, and a Reload button. Built so that "what host is Pulse
/// pointing at, and is it actually reachable" is a one-glance answer.
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _userUrl = '';
  String _activeUrl = '(not yet probed)';
  String? _probeError;
  bool _probing = true;
  Map<String, String> _attemptErrors = const {};
  Timer? _ticker;

  // Pull live stream health from whatever DeeSaidClient the Dee Stream page
  // last had. We look it up via the static registry on DeeStreamPage.
  DeeSaidClient? get _liveClient => DeeStreamPage.lastClient;

  @override
  void initState() {
    super.initState();
    _probe();
    // Re-render every second so "last poll N seconds ago" stays fresh.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _probe() async {
    setState(() {
      _probing = true;
      _probeError = null;
    });
    final user = await Settings.relayUrl();
    final resolver = RelayResolver(
      userUrl: user,
      candidates: kDefaultRelayCandidates,
    );
    String active = '';
    String? err;
    try {
      active = await resolver.resolve();
    } catch (e) {
      err = '$e';
    }
    final attempts = Map<String, String>.from(resolver.lastErrors);
    resolver.close();
    if (!mounted) return;
    setState(() {
      _userUrl = user;
      _activeUrl = active.isNotEmpty ? active : '(none reachable)';
      _probeError = err;
      _attemptErrors = attempts;
      _probing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reachable = _probeError == null && !_probing;
    return Scaffold(
      appBar: AppBar(
        title: const Text('About / Status'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Re-probe',
            onPressed: _probing ? null : _probe,
          ),
        ],
      ),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _section(theme, 'Version'),
            _kvCard([
              _kv('Version', _kVersion),
              _kv('Build', _kBuildSha),
              if (_kBuildTime.isNotEmpty) _kv('Built', _kBuildTime),
            ]),
            const SizedBox(height: 16),
            _section(theme, 'Relay'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _probing
                              ? Icons.help_outline
                              : (reachable
                                  ? Icons.check_circle
                                  : Icons.error),
                          size: 18,
                          color: _probing
                              ? theme.colorScheme.onSurfaceVariant
                              : (reachable ? Colors.green : Colors.red),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _probing
                              ? 'Probing...'
                              : (reachable
                                  ? 'Reachable'
                                  : 'Not reachable'),
                          style: theme.textTheme.titleSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _kv('Configured host',
                        _userUrl.isEmpty ? '(empty — using fallbacks)' : _userUrl),
                    _kv('Active host', _activeUrl),
                    if (_probeError != null) ...[
                      const SizedBox(height: 8),
                      SelectableText(
                        _probeError!,
                        style: TextStyle(
                            color: Colors.red.shade300, fontSize: 12),
                      ),
                    ],
                    if (_attemptErrors.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('Tried, in order:',
                          style: theme.textTheme.labelSmall),
                      for (final e in _attemptErrors.entries)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: SelectableText(
                            '• ${e.key} → ${e.value}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('Copy active'),
                          onPressed: () => _copy(_activeUrl),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _section(theme, 'Stream health'),
            _streamHealthCard(theme),
            const SizedBox(height: 16),
            _section(theme, 'What\'s new'),
            _changelogCard(theme),
          ],
        ),
      ),
    );
  }

  Widget _streamHealthCard(ThemeData theme) {
    final c = _liveClient;
    if (c == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'Open Dee Stream once to start polling.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }
    final lastPoll = c.lastPollAt;
    final lastOk = c.lastSuccessAt;
    return _kvCard([
      _kv('Last poll', _ago(lastPoll)),
      _kv('Last success', _ago(lastOk)),
      _kv('Cards in last fetch', '${c.lastEntryCount}'),
      if (c.lastError != null) _kv('Last error', c.lastError!),
    ]);
  }

  Widget _changelogCard(ThemeData theme) {
    final lines = _kBuildChangelog.isNotEmpty
        ? _kBuildChangelog.split('|').map((s) => s.trim()).where((s) => s.isNotEmpty).toList()
        : _fallbackChangelog;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: SelectableText(
                  line,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _section(ThemeData theme, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
              color: theme.colorScheme.onSurfaceVariant,
            )),
      );

  Widget _kvCard(List<Widget> rows) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: rows,
          ),
        ),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(k, style: const TextStyle(fontSize: 12)),
            ),
            Expanded(
              child: SelectableText(
                v,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        ),
      );

  String _ago(DateTime? t) {
    if (t == null) return 'never';
    final secs = DateTime.now().difference(t).inSeconds;
    if (secs < 5) return 'just now';
    if (secs < 60) return '${secs}s ago';
    final mins = secs ~/ 60;
    if (mins < 60) return '${mins}m ago';
    return DateFormat('MMM d • h:mm:ss a').format(t.toLocal());
  }

  Future<void> _copy(String s) async {
    await Clipboard.setData(ClipboardData(text: s));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Copied')));
  }
}

// Fallback changelog used when the build wasn't run with --dart-define
// BUILD_CHANGELOG. Keep in sync with CHANGELOG-PULSE.md (top entries).
const List<String> _fallbackChangelog = [
  'v0.2.1+6 (2026-05-07)',
  '  • Add About / Status screen — version, host, connection state',
  '  • Add Tailscale IP fallback (100.72.65.118) so stream survives off-LAN',
  '  • Track stream health: last poll, last success, last error, count',
  '',
  'v0.2.0+5',
  '  • Per-segment response bars on Dee Stream cards (Mira-principle UX)',
  '  • Phase 1b — Reply-to-Dee composer + dispatch_input client',
  '  • Bug-fix bundle: alarm dismiss, Dee Stream scroll, routine deletion',
];
