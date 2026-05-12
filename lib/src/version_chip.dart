// Visible build-version chip for the WebShell.
//
// Renders: vX.Y.Z+B · <shortSha>  [⬆ if update available]
// Tap → opens AboutPage as an inline drill-down (push on the same Navigator).
// SelectableText so Mike can copy values without leaving the chip.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'about_page.dart';
import 'build_info.dart';
import 'ota_service.dart';

class VersionChip extends StatefulWidget {
  /// If [compact] is true, only shows "vX.Y.Z+B".
  /// Otherwise shows "vX.Y.Z+B · shortSha".
  final bool compact;
  const VersionChip({super.key, this.compact = false});

  @override
  State<VersionChip> createState() => _VersionChipState();
}

class _VersionChipState extends State<VersionChip> {
  String? _version;
  String? _build;
  bool _updateAvailable = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _version = info.version;
      _build = info.buildNumber;
    });
    if (!kIsWeb) _checkUpdateBadge(info);
  }

  Future<void> _checkUpdateBadge(PackageInfo info) async {
    // Use cached result if fresh; otherwise do a background check.
    final cache = OtaUpdateCache.instance;
    if (!cache.isStale && cache.updateAvailable != null) {
      if (mounted) setState(() => _updateAvailable = cache.updateAvailable!);
      return;
    }
    final available = await OtaService.instance.checkForUpdate();
    if (mounted) setState(() => _updateAvailable = available);
  }

  @override
  Widget build(BuildContext context) {
    final v = _version ?? '?';
    final b = _build ?? '?';
    final sha = kBuildGitShaShort;
    final label = widget.compact ? 'v$v+$b' : 'v$v+$b  ·  $sha';

    return Semantics(
      label: 'App version $v build $b commit $sha. Tap for details.',
      button: true,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AboutPage()),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Theme.of(context).hintColor,
                  letterSpacing: 0.2,
                ),
              ),
              if (_updateAvailable) ...[
                const SizedBox(width: 4),
                const Icon(Icons.arrow_circle_up, size: 13, color: Colors.orange),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
