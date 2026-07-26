import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'settings.dart';
import 'about_page.dart';
import 'activity_screen.dart';
import 'asks_banner.dart';
import 'conversation_screen.dart';
import 'health_screen.dart';
import 'glasses_conversation_screen.dart';
import 'jobs_screen.dart';
import 'kanban_screen.dart';
import 'on_device_chat_screen.dart';
import 'reminders_screen.dart';
import 'today_screen.dart';
import 'version_chip.dart';

// Putoff items are re-homed to Reminders (category: self_deferred) via Track A.
// PutoffScreen and CampusScreen remain as files but are no longer in the main nav.

class WebShell extends StatefulWidget {
  const WebShell({super.key});

  // Programmatically navigate to a tab (e.g., from a notification tap).
  // Tab indices: 0=Today 1=Pulse 2=Jobs 3=Activity 4=Reminders 5=Health 6=Board
  static void Function(int)? _navCallback;
  static void requestTab(int tab) => _navCallback?.call(tab);

  @override
  State<WebShell> createState() => _WebShellState();
}

class _WebShellState extends State<WebShell> {
  int _selectedIndex =
      0; // 0=Today 1=Pulse 2=Jobs 3=Activity 4=Reminders 5=Health 6=Board
  final _searchTrigger = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    WebShell._navCallback = (tab) {
      if (mounted) setState(() => _selectedIndex = tab);
    };
  }

  @override
  void dispose() {
    WebShell._navCallback = null;
    _searchTrigger.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenStack = IndexedStack(
      index: _selectedIndex,
      children: [
        const TodayScreen(),
        ConversationScreen(
          isActive: _selectedIndex == 1,
          onRequestFocus: () => setState(() => _selectedIndex = 1),
          searchTrigger: _searchTrigger,
        ),
        const JobsScreen(),
        const ActivityScreen(),
        const RemindersScreen(),
        const HealthScreen(),
        const KanbanScreen(),
      ],
    );

    return Scaffold(
      body: Column(
        children: [
          // Pending cc hud-ask items — global, visible on every tab.
          const AsksBanner(),
          Expanded(
              child: Stack(
            children: [
              screenStack,
              Positioned(
                top: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  left: false,
                  right: false,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8, top: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_selectedIndex == 1)
                          SizedBox(
                            width: 44,
                            height: 44,
                            child: IconButton(
                              icon: const Icon(Icons.headset_mic, size: 19),
                              tooltip: 'Meta glasses conversation',
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const GlassesConversationScreen(),
                                ),
                              ),
                            ),
                          ),
                        if (_selectedIndex == 1)
                          SizedBox(
                            width: 44,
                            height: 44,
                            child: IconButton(
                              icon: const Icon(Icons.search, size: 18),
                              tooltip: 'Search conversation',
                              onPressed: () {
                                _searchTrigger.value = !_searchTrigger.value;
                              },
                            ),
                          ),
                        if (_selectedIndex == 1)
                          SizedBox(
                            width: 44,
                            height: 44,
                            child: IconButton(
                              icon: const Icon(
                                Icons.offline_bolt_outlined,
                                size: 19,
                              ),
                              tooltip: 'On-device AI (offline, no relay)',
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const OnDeviceChatScreen(),
                                ),
                              ),
                            ),
                          ),
                        const VersionChip(),
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 44,
                          height: 44,
                          child: IconButton(
                            icon: const Icon(Icons.info_outline, size: 18),
                            tooltip: 'About',
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const AboutPage()),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          )),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Pulse',
          ),
          NavigationDestination(
            icon: Icon(Icons.work_outline),
            selectedIcon: Icon(Icons.work),
            label: 'Jobs',
          ),
          NavigationDestination(
            icon: Icon(Icons.dynamic_feed_outlined),
            selectedIcon: Icon(Icons.dynamic_feed),
            label: 'Activity',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications),
            label: 'Reminders',
          ),
          NavigationDestination(
            icon: Icon(Icons.monitor_heart_outlined),
            selectedIcon: Icon(Icons.monitor_heart),
            label: 'Health',
          ),
          NavigationDestination(
            icon: Icon(Icons.view_kanban_outlined),
            selectedIcon: Icon(Icons.view_kanban),
            label: 'Board',
          ),
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

  String _base = Settings.defaultYeshieHost;

  @override
  void initState() {
    super.initState();
    _loadHost();
  }

  Future<void> _loadHost() async {
    final host = await Settings.yeshieHost();
    if (mounted) setState(() => _base = host);
  }

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
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red));
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
            top: BorderSide(color: Theme.of(context).dividerColor, width: 1)),
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
