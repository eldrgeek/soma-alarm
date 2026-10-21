// Pulse Zero — the live decision board, embedded.
//
// Deliberately a WebView over the deployed board rather than a native
// re-implementation: the board's card types change often, and a second
// renderer in Dart would silently fall behind the web one. What Mike sees here
// is byte-for-byte what he sees in a browser.
//
// Note this is NOT the 'Board' tab (kanban_screen.dart) — that one is a native
// Kanban fed by the relay's /pulse/projects. Different surface, different data.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

const String kPulseZeroUrl = 'https://pulse-zero.netlify.app/';

class PulseZeroScreen extends StatefulWidget {
  const PulseZeroScreen({super.key, this.url = kPulseZeroUrl});

  final String url;

  @override
  State<PulseZeroScreen> createState() => _PulseZeroScreenState();
}

class _PulseZeroScreenState extends State<PulseZeroScreen>
    with AutomaticKeepAliveClientMixin {
  WebViewController? _controller;
  bool _loading = true;
  String? _error;

  // The shell keeps every page alive in an IndexedStack; without this the
  // WebView would reload (and lose scroll position) on every tab switch.
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) _initWebView();
  }

  void _initWebView() {
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _loading = true;
                _error = null;
              });
            }
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (err) {
            // Subframe/asset errors are noise; only the main document failing
            // means the board genuinely did not load.
            if (!err.isForMainFrame.orFalse) return;
            if (mounted) {
              setState(() {
                _loading = false;
                _error = err.description.isEmpty
                    ? 'Could not load the board'
                    : err.description;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
    setState(() => _controller = c);
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await _controller?.reload();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Back must walk the board's own history first. Without this, one Back tap
    // from a card or the sign-in flow quits Pulse outright.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Resolve the navigator before the await so we aren't reaching through
        // a BuildContext across an async gap.
        final nav = Navigator.of(context);
        final c = _controller;
        if (c != null && await c.canGoBack()) {
          await c.goBack();
          return;
        }
        // Nothing left in web history — let the system handle it (background
        // the app), matching what the other tabs do.
        if (mounted) nav.maybePop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pulse Zero'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reload board',
              onPressed: _reload,
            ),
          ],
        ),
        body: kIsWeb ? _unsupported(context) : _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final c = _controller;
    if (c == null) return const Center(child: CircularProgressIndicator());

    return Stack(
      children: [
        WebViewWidget(controller: c),
        if (_error != null) _errorPane(context, _error!),
        if (_loading && _error == null)
          const Align(
            alignment: Alignment.topCenter,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }

  Widget _errorPane(BuildContext context, String message) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 40, color: Colors.orange),
          const SizedBox(height: 12),
          Text(
            "Couldn't reach the board",
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }

  Widget _unsupported(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Pulse Zero is embedded on mobile only.\nOpen $kPulseZeroUrl directly.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
}

extension _NullableBool on bool? {
  bool get orFalse => this ?? false;
}
