import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'settings.dart';

// ── Data models ───────────────────────────────────────────────────────────────

enum _NodeState { unknown, ok, degraded, offline }

class _Node {
  final String id;
  final String label;
  final String sublabel;
  final IconData icon;
  String? probeUrl; // null = static local node (not probeable)
  _NodeState state;
  String? detail;

  _Node({
    required this.id,
    required this.label,
    required this.sublabel,
    required this.icon,
    this.probeUrl,
    this.state = _NodeState.unknown,
    this.detail,
  });
}

class _Project {
  final String name;
  final String path;
  final String description;
  final IconData icon;

  const _Project({
    required this.name,
    required this.path,
    required this.description,
    required this.icon,
  });
}

// ── Screen ────────────────────────────────────────────────────────────────────

class CampusScreen extends StatefulWidget {
  const CampusScreen({super.key});

  @override
  State<CampusScreen> createState() => _CampusScreenState();
}

class _CampusScreenState extends State<CampusScreen> {
  String _relayBase = Settings.defaultYeshieHost;
  Timer? _timer;
  DateTime? _lastRefresh;
  bool _probing = false;

  late final List<_Node> _nodes;

  static const _kProbeIntervalSeconds = 30;

  static const _projects = [
    _Project(
      name: 'SOMA',
      path: '~/Projects/SOMA/',
      description: 'Cognitive architecture — docs & fleet state',
      icon: Icons.account_tree_outlined,
    ),
    _Project(
      name: 'Yeshie',
      path: '~/Projects/yeshie/',
      description: 'Browser RPA — relay :3333, 46+ recipes',
      icon: Icons.travel_explore,
    ),
    _Project(
      name: 'second-brain',
      path: '~/Projects/second-brain/',
      description: 'Obsidian vault — ~4,800 conversations',
      icon: Icons.storage_outlined,
    ),
    _Project(
      name: 'cc-bridge-mcp',
      path: '~/Projects/cc-bridge-mcp/',
      description: 'MCP bridge: CDC → Mac shell / CCc',
      icon: Icons.cable_outlined,
    ),
    _Project(
      name: 'mac-controller',
      path: '~/Projects/mac-controller/',
      description: 'cc.py — CDC AX control & HUD :3334',
      icon: Icons.computer,
    ),
    _Project(
      name: 'cie',
      path: '~/Projects/cie/',
      description: 'Collective Intelligence Engine',
      icon: Icons.hub_outlined,
    ),
    _Project(
      name: 'cc-dispatch',
      path: '~/Projects/cc-dispatch/',
      description: 'Fire-and-forget delegation CLI',
      icon: Icons.send_outlined,
    ),
    _Project(
      name: 'claude-email-daemon',
      path: '~/Projects/claude-email-daemon/',
      description: 'Email-as-transport dispatch handler',
      icon: Icons.mail_outlined,
    ),
    _Project(
      name: 'pulse',
      path: '~/Projects/Sidekick-android/',
      description: 'This app — Android SOMA companion',
      icon: Icons.phone_android,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _nodes = [
      _Node(
        id: 'relay',
        label: 'Relay :3333',
        sublabel: 'Yeshie relay — primary Mac bridge',
        icon: Icons.router_outlined,
        // probeUrl derived after _loadHost
      ),
      _Node(
        id: 'screenpipe',
        label: 'Screenpipe :3030',
        sublabel: 'Screen & audio capture daemon',
        icon: Icons.screen_search_desktop_outlined,
        // probeUrl derived after _loadHost
      ),
      _Node(
        id: 'vps',
        label: 'VPS',
        sublabel: 'vpsmikewolf.duckdns.org',
        icon: Icons.dns_outlined,
        probeUrl: 'https://vpsmikewolf.duckdns.org',
      ),
      _Node(
        id: 'hermes',
        label: 'HERMES',
        sublabel: 'Local gateway — Discord / fleet dispatch',
        icon: Icons.hub_outlined,
        probeUrl: null,
      ),
      _Node(
        id: 'cc_dispatch',
        label: 'cc-dispatch',
        sublabel: 'Local delegation CLI (pi RPC)',
        icon: Icons.send_outlined,
        probeUrl: null,
      ),
      _Node(
        id: 'vault',
        label: 'Mem (vault)',
        sublabel: '~/Projects/second-brain',
        icon: Icons.storage_outlined,
        probeUrl: null,
      ),
    ];

    _loadHost().then((_) {
      _probeAll();
      _timer = Timer.periodic(
        const Duration(seconds: _kProbeIntervalSeconds),
        (_) => _probeAll(),
      );
    });
  }

  Future<void> _loadHost() async {
    final host = await Settings.yeshieHost();
    if (!mounted) return;
    final relayUri = Uri.parse(host);
    final screenpipeUrl =
        relayUri.replace(port: 3030).toString() + '/health';
    setState(() {
      _relayBase = host;
      _nodes[0].probeUrl = '$host/health';
      _nodes[1].probeUrl = screenpipeUrl;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _probeAll() async {
    if (_probing) return;
    _probing = true;
    for (final node in _nodes) {
      await _probeNode(node);
    }
    _probing = false;
    if (mounted) setState(() => _lastRefresh = DateTime.now());
  }

  Future<void> _probeNode(_Node node) async {
    if (node.probeUrl == null) {
      // Local-only node: always shown as 'local'
      if (mounted) setState(() => node.state = _NodeState.ok);
      return;
    }
    try {
      final resp = await http
          .get(Uri.parse(node.probeUrl!))
          .timeout(const Duration(seconds: 4));
      if (!mounted) return;
      setState(() {
        node.state =
            resp.statusCode < 400 ? _NodeState.ok : _NodeState.degraded;
        node.detail = 'HTTP ${resp.statusCode}';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          node.state = _NodeState.offline;
          node.detail = e.toString().split('\n').first;
        });
      }
    }
  }

  static Color _stateColor(_NodeState s) => switch (s) {
        _NodeState.ok => Colors.green,
        _NodeState.degraded => Colors.amber,
        _NodeState.offline => Colors.red,
        _NodeState.unknown => Colors.grey,
      };

  static String _stateLabel(_NodeState s, bool isStatic) => switch (s) {
        _NodeState.ok => isStatic ? 'local' : 'ok',
        _NodeState.degraded => 'degraded',
        _NodeState.offline => 'offline',
        _NodeState.unknown => '…',
      };

  static String _fmtTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Campus'),
        actions: [
          if (_lastRefresh != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Text(
                  _fmtTime(_lastRefresh!),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Re-probe nodes',
            onPressed: _probeAll,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Nodes', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ..._nodes.map(
            (n) => _NodeTile(
              node: n,
              isStatic: n.probeUrl == null,
              stateColor: _stateColor(n.state),
              stateLabel: _stateLabel(n.state, n.probeUrl == null),
            ),
          ),
          const SizedBox(height: 20),
          Text('Projects', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ..._projects.map((p) => _ProjectTile(project: p)),
          const SizedBox(height: 72), // FAB clearance
        ],
      ),
      floatingActionButton: FloatingActionButton.small(
        tooltip: 'Quick capture',
        onPressed: () => _showCaptureDialog(context),
        child: const Icon(Icons.bolt),
      ),
    );
  }

  void _showCaptureDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quick Capture'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Capture a thought or dispatch task…',
          ),
          maxLines: 4,
          onSubmitted: (_) {},
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final text = ctrl.text.trim();
              Navigator.pop(ctx);
              if (text.isEmpty) return;
              try {
                await http
                    .post(
                      Uri.parse('$_relayBase/pulse/capture'),
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode({'text': text}),
                    )
                    .timeout(const Duration(seconds: 5));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Captured ✓')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Capture failed: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }
}

// ── Node tile ─────────────────────────────────────────────────────────────────

class _NodeTile extends StatelessWidget {
  final _Node node;
  final bool isStatic;
  final Color stateColor;
  final String stateLabel;

  const _NodeTile({
    required this.node,
    required this.isStatic,
    required this.stateColor,
    required this.stateLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: stateColor.withOpacity(0.4)),
          borderRadius: BorderRadius.circular(8),
          color: stateColor.withOpacity(0.07),
        ),
        child: ListTile(
          dense: true,
          leading:
              Icon(node.icon, color: stateColor.withOpacity(0.85), size: 20),
          title: Text(
            node.label,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
          subtitle: SelectableText(
            node.sublabel,
            style: TextStyle(
              fontSize: 11,
              color: theme.textTheme.bodySmall?.color,
            ),
          ),
          trailing: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: stateColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              stateLabel,
              style: TextStyle(
                fontSize: 11,
                color: stateColor,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Project tile ──────────────────────────────────────────────────────────────

class _ProjectTile extends StatelessWidget {
  final _Project project;

  const _ProjectTile({required this.project});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(8),
          color: cs.surfaceContainerHighest.withOpacity(0.3),
        ),
        child: ListTile(
          dense: true,
          leading: Icon(project.icon, color: cs.primary, size: 20),
          title: Text(
            project.name,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
          subtitle: SelectableText(
            project.description,
            style: TextStyle(
              fontSize: 11,
              color: theme.textTheme.bodySmall?.color,
            ),
          ),
          trailing: SelectableText(
            project.path,
            style: TextStyle(
              fontSize: 10,
              color: cs.onSurface.withOpacity(0.35),
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}
