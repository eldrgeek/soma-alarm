import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'activity_screen.dart';
import 'health_screen.dart';
import 'jobs_screen.dart';
import 'putoff_screen.dart';

class WebShell extends StatefulWidget {
  const WebShell({super.key});

  @override
  State<WebShell> createState() => _WebShellState();
}

class _WebShellState extends State<WebShell> {
  int _selectedIndex = 0; // 0=Jobs 1=Activity 2=Putoff 3=Health

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (i) =>
                      setState(() => _selectedIndex = i),
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.work_outline),
                      selectedIcon: Icon(Icons.work),
                      label: Text('Jobs'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.dynamic_feed_outlined),
                      selectedIcon: Icon(Icons.dynamic_feed),
                      label: Text('Activity'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.pause_circle_outline),
                      selectedIcon: Icon(Icons.pause_circle),
                      label: Text('Putoff'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.monitor_heart_outlined),
                      selectedIcon: Icon(Icons.monitor_heart),
                      label: Text('Health'),
                    ),
                  ],
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: const [
                      JobsScreen(),
                      ActivityScreen(),
                      PutoffScreen(),
                      HealthScreen(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const _QuickCaptureBar(),
        ],
      ),
    );
  }
}

// ── Quick-capture bar ────────────────────────────────────────────────────────

class _QuickCaptureBar extends StatefulWidget {
  const _QuickCaptureBar();

  @override
  State<_QuickCaptureBar> createState() => _QuickCaptureBarState();
}

class _QuickCaptureBarState extends State<_QuickCaptureBar> {
  final _controller = TextEditingController();
  bool _sending = false;
  bool _success = false;

  static const _base = 'http://localhost:3333';

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final resp = await http
          .post(
            Uri.parse('$_base/pulse/capture'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'text': text}),
          )
          .timeout(const Duration(seconds: 5));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        _controller.clear();
        setState(() => _success = true);
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) setState(() => _success = false);
      } else {
        _showError('Send failed: HTTP ${resp.statusCode}');
      }
    } catch (e) {
      if (mounted) _showError('$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
            top: BorderSide(
                color: Theme.of(context).dividerColor, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.bolt, size: 18, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: const InputDecoration(
                hintText: 'Quick capture…',
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
              style: const TextStyle(fontSize: 14),
              onSubmitted: (_) => _send(),
              enabled: !_sending,
            ),
          ),
          const SizedBox(width: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _success
                ? const Icon(Icons.check_circle,
                    key: ValueKey('ok'), color: Colors.green, size: 22)
                : _sending
                    ? const SizedBox(
                        key: ValueKey('spin'),
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : IconButton(
                        key: const ValueKey('send'),
                        icon: const Icon(Icons.send, size: 20),
                        tooltip: 'Capture',
                        onPressed: _send,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
          ),
        ],
      ),
    );
  }
}
