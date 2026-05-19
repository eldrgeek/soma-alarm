// OTA update badge for the WebShell.
//
// Hidden until an update is detected; shows only the ⬆ icon so the header
// stays clean during normal use. Tap → opens AboutPage for the full update UI.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'about_page.dart';
import 'ota_service.dart';

class VersionChip extends StatefulWidget {
  const VersionChip({super.key});

  @override
  State<VersionChip> createState() => _VersionChipState();
}

class _VersionChipState extends State<VersionChip> {
  bool _updateAvailable = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
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
    if (!_updateAvailable) return const SizedBox.shrink();

    return Semantics(
      label: 'Update available. Tap for details.',
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AboutPage()),
          ),
          borderRadius: BorderRadius.circular(22),
          child: const SizedBox(
            width: 44,
            height: 44,
            child: Icon(Icons.arrow_circle_up, size: 20, color: Colors.orange),
          ),
        ),
      ),
    );
  }
}
