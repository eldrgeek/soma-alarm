// Inline-drill-down About page for Pulse.
// Identical on web (kIsWeb) and mobile per feedback_web_mobile_parity.md.
// All identifier-style values are SelectableText so Mike can copy them.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'build_info.dart';
import 'ota_service.dart';
import 'pages.dart';
import 'round_info.dart';
import 'settings.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

enum _OtaState { checking, upToDate, available, downloading, error }

class _AboutPageState extends State<AboutPage> {
  PackageInfo? _pkg;
  String _host = '…';
  String _tailscale = 'checking…';
  String _roundNotes = '';

  /// Which pages are switched on. Null until loaded.
  List<String>? _enabledPages;

  // OTA
  _OtaState _otaState = _OtaState.checking;
  OtaManifest? _manifest;
  double _downloadProgress = 0;
  String _otaError = '';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final pkg = await PackageInfo.fromPlatform();
    final host = await Settings.yeshieHost();
    final ts = _classifyHost(host);
    final pages = await PulsePagePrefs.enabled();
    if (!mounted) return;
    setState(() {
      _pkg = pkg;
      _host = host;
      _tailscale = ts;
      _roundNotes = kRoundDescription.trim();
      _enabledPages = pages;
    });
    if (!kIsWeb) _checkOta(pkg);
  }

  Future<void> _togglePage(String id, bool on) async {
    final ok = await PulsePagePrefs.setPageEnabled(id, on);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keep at least one page turned on.')),
      );
      return;
    }
    final pages = await PulsePagePrefs.enabled();
    if (mounted) setState(() => _enabledPages = pages);
  }

  Future<void> _restoreDefaultPages() async {
    await PulsePagePrefs.restoreDefaults();
    final pages = await PulsePagePrefs.enabled();
    if (mounted) setState(() => _enabledPages = pages);
  }

  Future<void> _checkOta(PackageInfo pkg) async {
    setState(() => _otaState = _OtaState.checking);
    final manifest = await OtaService.instance.fetchLatest();
    if (!mounted) return;
    if (manifest == null) {
      setState(() {
        _otaState = _OtaState.error;
        _otaError = 'Could not reach OTA server';
      });
      return;
    }
    final currentBuild = int.tryParse(pkg.buildNumber) ?? 0;
    final available = OtaService.instance.isUpdateAvailable(manifest, currentBuild);
    // Update cache so VersionChip badge reflects this check.
    OtaUpdateCache.instance.set(manifest, available);
    setState(() {
      _manifest = manifest;
      _otaState = available ? _OtaState.available : _OtaState.upToDate;
    });
  }

  Future<void> _installUpdate() async {
    final m = _manifest;
    if (m == null) return;
    setState(() {
      _otaState = _OtaState.downloading;
      _downloadProgress = 0;
    });
    try {
      final path = await OtaService.instance.downloadApk(m, (p) {
        if (mounted) setState(() => _downloadProgress = p);
      });
      await OtaService.instance.launchInstaller(path);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _otaState = _OtaState.error;
        _otaError = e.toString();
      });
    }
  }

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
          _buildPagesSection(context),
          const SizedBox(height: 16),
          if (!kIsWeb) ...[
            _buildOtaSection(context),
            const SizedBox(height: 16),
          ],
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

  /// Page switches. Every screen Pulse has ever had is listed here — the
  /// simplification hid pages from the nav, it did not remove them.
  Widget _buildPagesSection(BuildContext context) {
    final enabled = _enabledPages;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Pages',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                TextButton(
                  onPressed: enabled == null ? null : _restoreDefaultPages,
                  child: const Text('Defaults'),
                ),
              ],
            ),
            Text(
              'Choose what appears in the bottom bar. Nothing is deleted — '
              'switch a page back on any time.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).hintColor),
            ),
            const SizedBox(height: 4),
            if (enabled == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              for (final page in PulsePages.all)
                SwitchListTile(
                  value: enabled.contains(page.id),
                  onChanged: (v) => _togglePage(page.id, v),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(page.icon, size: 20),
                  title: Text(page.label),
                  subtitle: Text(
                    page.blurb,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildOtaSection(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Software update',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            _buildOtaBody(context),
          ],
        ),
      ),
    );
  }

  Widget _buildOtaBody(BuildContext context) {
    switch (_otaState) {
      case _OtaState.checking:
        return const Row(children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 8),
          Text('Checking for updates…'),
        ]);

      case _OtaState.upToDate:
        final pkg = _pkg;
        return Row(children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 18),
          const SizedBox(width: 8),
          Text('Pulse is up to date (${pkg != null ? 'v${pkg.version}+${pkg.buildNumber}' : 'current version'})'),
        ]);

      case _OtaState.available:
        final m = _manifest!;
        final pkg = _pkg;
        final from = pkg != null ? 'v${pkg.version}+${pkg.buildNumber}' : 'current';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.system_update, color: Colors.orange, size: 18),
              const SizedBox(width: 8),
              Text('Update available: $from → v${m.versionName}+${m.buildNumber}'),
            ]),
            if (m.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(m.releaseNotes,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).hintColor)),
            ],
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _installUpdate,
              icon: const Icon(Icons.download),
              label: const Text('Install update'),
            ),
          ],
        );

      case _OtaState.downloading:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Downloading… ${(_downloadProgress * 100).toStringAsFixed(0)}%'),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: _downloadProgress),
            const SizedBox(height: 4),
            Text('SHA-256 will be verified before install.',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        );

      case _OtaState.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(_otaError)),
            ]),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _pkg != null ? _checkOta(_pkg!) : null,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        );
    }
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
