// Visible build-version chip for the WebShell.
//
// Renders: vX.Y.Z+B · <shortSha>
// Tap → opens AboutPage as an inline drill-down (push on the same Navigator).
// SelectableText so Mike can copy values without leaving the chip.
//
// Drop this into lib/src/version_chip.dart and import from web_shell.dart.

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'build_info.dart';
import 'about_page.dart';

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
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: Theme.of(context).hintColor,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}
