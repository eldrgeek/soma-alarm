// Inline-drill-down About page for Pulse.
// Identical on web (kIsWeb) and mobile per feedback_web_mobile_parity.md.
// All identifier-style values are SelectableText so Mike can copy them.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'build_info.dart';
import 'round_info.dart';
import 'settings.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  PackageInfo? _pkg;
  String _host = '…';
  String _tailscale = 'checking…';
  String _roundNotes = '';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final pkg = await PackageInfo.fromPlatform();
    final host = await Settings.yeshieHost();
    final ts = _classifyHost(host);
    if (!mounted) return;
    setState(() {
      _pkg = pkg;
      _host = host;
      _tailscale = ts;
      _roundNotes = kRoundDescription.trim();
    });
  }

  // Classify the configured Yeshie host without any platform-specific imports.
  String _classifyHost(String host) {
    if (host.isEmpty) return 'host not configured';
    final uri = Uri.tryParse(host);
    if (uri == null) return 'unparsable host';
    final h = uri.host;
    if (h.isEmpty) return 'no host in URI';
    if (h == 'localhost' || h == '127.0.0.1') {
      return kIsWeb ? 'localhost (web)' : 'localhost (mobile)';
    }
    if (h.startsWith('100.')) return '$h (tailnet)';
    return h;
  }

  @override
  Widget build(BuildContext context) {
    final pkg = _pkg;
    final version =
        pkg == null ? '…' : 'v${pkg.version} (build ${pkg.buildNumber})';

    return Scaffold(
      appBar: AppBar(title: const Text('About Pulse')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _row('Pulse version', version),
          _row('Round', 'r$kRoundNumber  ($kRoundTitle)'),
          _row('Git commit (short)', kBuildGitShaShort),
          _row('Git commit (full)', kBuildGitShaFull),
          _row('Commit message', kBuildCommitSubject),
          _row('Build time', kBuildTime),
          _row('Yeshie host', _host.isEmpty ? '(not configured)' : _host),
          _row('Tailscale', _tailscale),
          _row('Platform', kIsWeb ? 'web' : 'mobile'),
          const SizedBox(height: 16),
          Text("What's new in this round",
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          SelectableText(
            _roundNotes.isEmpty ? 'no round notes' : _roundNotes,
            style: const TextStyle(height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
