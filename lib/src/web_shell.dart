import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'settings.dart';
import 'about_page.dart';
import 'asks_banner.dart';
import 'glasses_conversation_screen.dart';
import 'on_device_chat_screen.dart';
import 'pages.dart';
import 'version_chip.dart';

// Putoff items are re-homed to Reminders (category: self_deferred) via Track A.
// PutoffScreen and CampusScreen remain as files but are no longer in the main nav.

class WebShell extends StatefulWidget {
  const WebShell({super.key});

  // Programmatically navigate to a page (e.g., from a notification tap).
  //
  // Takes a PulsePages id, NOT an index. Indices used to be hardcoded at call
  // sites ("tab 5 = Health"); once the nav became user-configurable those
  // constants pointed at whatever page happened to land in that slot.
  static void Function(String)? _navCallback;
  static void requestPage(String pageId) => _navCallback?.call(pageId);

  /// Sentinel meaning "whatever page leads the nav". Used by callers that just
  /// want the app foregrounded on its home surface and don't care which one.
  static const String homePage = '__home__';
  static void requestHome() => _navCallback?.call(homePage);

  @override
  State<WebShell> createState() => _WebShellState();
}

class _WebShellState extends State<WebShell> {
  final _searchTrigger = ValueNotifier<bool>(false);

  List<PulsePage> _pages = const [];
  String? _selectedId;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadPages();
    PulsePagePrefs.revision.addListener(_loadPages);
    WebShell._navCallback = (pageId) {
      if (!mounted) return;
      if (pageId == WebShell.homePage) {
        if (_pages.isNotEmpty) setState(() => _selectedId = _pages.first.id);
        return;
      }
      final page = PulsePages.byId(pageId);
      if (page == null) return;
      if (_pages.any((p) => p.id == pageId)) {
        setState(() => _selectedId = pageId);
      } else {
        // The page is switched off in About. Honour the request anyway by
        // pushing it as a route — a disabled page should still be reachable
        // when something (a notification, a deep link) asks for it by name.
        _openAsRoute(page);
      }
    };
  }

  Future<void> _loadPages() async {
    final ids = await PulsePagePrefs.enabled();
    if (!mounted) return;
    final pages = PulsePages.resolve(ids);
    setState(() {
      _pages = pages;
      _loaded = true;
      // Keep the current page selected across a config change when possible.
      if (_selectedId == null || !pages.any((p) => p.id == _selectedId)) {
        _selectedId = pages.isEmpty ? null : pages.first.id;
      }
    });
  }

  void _openAsRoute(PulsePage page) {
    final host = PulsePageHost(
      isActive: true,
      onRequestFocus: () {},
      searchTrigger: _searchTrigger,
    );
    Navigator.of(context).push(
      MaterialPageRoute(builder: (ctx) => page.builder(ctx, host)),
    );
  }

  @override
  void dispose() {
    PulsePagePrefs.revision.removeListener(_loadPages);
    WebShell._navCallback = null;
    _searchTrigger.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final selectedIndex =
        _pages.indexWhere((p) => p.id == _selectedId).clamp(0, _pages.length);
    final onDee = _selectedId == PulsePages.dee;

    final screenStack = IndexedStack(
      index: selectedIndex,
      children: [
        for (final page in _pages)
          page.builder(
            context,
            PulsePageHost(
              isActive: page.id == _selectedId,
              onRequestFocus: () => setState(() => _selectedId = page.id),
              searchTrigger: _searchTrigger,
            ),
          ),
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
                        if (onDee)
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
                        if (onDee)
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
                        if (onDee)
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
      // A single enabled page needs no chooser — drop the bar entirely.
      bottomNavigationBar: _pages.length < 2
          ? null
          : NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: (i) =>
                  setState(() => _selectedId = _pages[i].id),
              labelBehavior:
                  NavigationDestinationLabelBehavior.onlyShowSelected,
              destinations: [
                for (final page in _pages)
                  NavigationDestination(
                    icon: Icon(page.icon),
                    selectedIcon: Icon(page.selectedIcon),
                    label: page.label,
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
