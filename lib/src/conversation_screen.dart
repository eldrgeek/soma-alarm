import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:url_launcher/url_launcher.dart';

import 'alarms.dart';
import 'settings.dart';

class ConversationScreen extends StatefulWidget {
  /// True when this tab is the currently selected one in the shell.
  final bool isActive;

  /// Called when the user taps "View" on the in-app Dee reply toast,
  /// so the shell can switch back to this tab.
  final VoidCallback? onRequestFocus;

  /// Notifier from the shell's search icon; toggling opens/closes search.
  final ValueNotifier<bool>? searchTrigger;

  const ConversationScreen({
    super.key,
    this.isActive = true,
    this.onRequestFocus,
    this.searchTrigger,
  });

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

// Allow tests to fast-forward the idle timer.
@visibleForTesting
Duration kIdleNudgeDuration = const Duration(minutes: 2);

class _ConversationScreenState extends State<ConversationScreen>
    with WidgetsBindingObserver {
  String _base = Settings.defaultYeshieHost;

  final _scrollController = ScrollController();
  final _inputController = TextEditingController();

  List<_Message> _messages = [];
  bool _sending = false;
  bool _sendSuccess = false;
  bool _fetching = false;
  Timer? _pollTimer;
  String? _lastTs;
  bool _initialLoadDone = false;
  AppLifecycleState _appLifecycle = AppLifecycleState.resumed;

  // ── Smart scroll state ────────────────────────────────────────────────
  int _unreadCount = 0;
  bool _showScrollFab = false;

  // ── Send dedup: clientId → optimistic _Message (null = batch, swallow on echo) ──
  final Map<String, _Message?> _pendingClientIds = {};

  // ── Draft-batch state ────────────────────────────────────────────────
  List<String> _draftBatch = [];
  bool _showIdleBanner = false;
  Timer? _idleTimer;
  bool _flushing = false;

  // ── Scroll-on-send spacer ────────────────────────────────────────────
  // Set to ~65 % of viewport height on send so the user bubble scrolls to
  // the top of the viewport and the response streams in below it.
  // Cleared (→ 0) when the first response chunk arrives.
  double _bottomSpacer = 0.0;

  // ── Input draft persistence ───────────────────────────────────────────
  Timer? _draftSaveDebounce;

  // ── Image attachment state ────────────────────────────────────────────
  final _imagePicker = ImagePicker();
  XFile? _pendingImage;

  // ── Search state ──────────────────────────────────────────────────────
  bool _searchActive = false;
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _searchLoading = false;
  Timer? _searchDebounce;
  String? _highlightedTs;

  // ── Relay real-time: thinking indicator ──────────────────────────────
  IO.Socket? _pulseSocket;
  bool _showThinking = false;
  DateTime? _thinkingStart;

  // ── Pipeline state: track last send time for "waiting" indicator ──────
  DateTime? _lastSentAt;
  // One of: null, 'sent', 'working', 'replied'
  String? _pipelineState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadHost().then((_) {
      _startPolling(active: true);
      _fetchMessages();
      _connectPulseSocket();
    });
    _loadDraftBatch();
    _loadDispatchInputDraft();
    _inputController.addListener(_onInputChanged);
    _scrollController.addListener(_onScroll);
    widget.searchTrigger?.addListener(_onSearchTrigger);
  }

  void _onSearchTrigger() {
    setState(() {
      _searchActive = !_searchActive;
      if (!_searchActive) {
        _searchController.clear();
        _searchResults = [];
        _searchDebounce?.cancel();
      }
    });
  }

  void _connectPulseSocket() {
    _pulseSocket?.disconnect();
    final wsBase = _base.replaceFirst(RegExp(r'^http'), 'ws');
    _pulseSocket = IO.io(
      wsBase,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth({'role': 'pulse'})
          .build(),
    );
    _pulseSocket!.on('message', (data) {
      if (!mounted) return;
      if (data is Map && data['type'] == 'thinking') {
        setState(() {
          _showThinking = true;
          _thinkingStart = DateTime.now();
          _pipelineState = 'working';
        });
      } else if (data is Map && data['type'] == 'dee_reply') {
        final ts = data['ts'] as String?;
        final body = data['body'] as String?;
        final from = (data['from'] as String?) ?? 'dee';
        final speaker = (data['speaker'] as String?) ?? from;
        if (ts != null && body != null) {
          // Dedup: skip if already present (polling may have fetched it first).
          if (!_messages.any((m) => m.ts == ts && m.from == from)) {
            final msg = _Message(
              from: from,
              speaker: speaker,
              ts: ts,
              body: body,
              inReplyTo: data['in_reply_to'] as String?,
            );
            setState(() {
              _messages = [..._messages, msg];
              _showThinking = false;
              _thinkingStart = null;
              if (_lastTs == null || ts.compareTo(_lastTs!) > 0) _lastTs = ts;
              _bottomSpacer = 0;
            });
            _scrollToBottom();
          }
        }
      }
    });
    _pulseSocket!.connect();
  }

  Future<void> _loadHost() async {
    final host = await Settings.yeshieHost();
    if (mounted) setState(() => _base = host);
  }

  Future<void> _loadDraftBatch() async {
    final batch = await Settings.draftBatch();
    if (mounted) setState(() => _draftBatch = batch);
  }

  Future<void> _loadDispatchInputDraft() async {
    final draft = await Settings.dispatchInputDraft();
    if (draft.isNotEmpty && mounted) {
      _inputController.text = draft;
      _inputController.selection =
          TextSelection.fromPosition(TextPosition(offset: draft.length));
    }
  }

  bool get _isNearBottom {
    if (!_scrollController.hasClients) return true;
    final pos = _scrollController.position;
    return pos.pixels >= pos.maxScrollExtent - 300;
  }

  void _onScroll() {
    final atBottom = _isNearBottom;
    setState(() {
      _showScrollFab = !atBottom;
      if (atBottom) _unreadCount = 0;
    });
  }

  void _jumpToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
      setState(() => _unreadCount = 0);
    }
  }

  void _onInputChanged() {
    _resetIdleTimer();
    _draftSaveDebounce?.cancel();
    _draftSaveDebounce = Timer(const Duration(milliseconds: 500), () {
      Settings.saveDispatchInputDraft(_inputController.text);
    });
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    if (mounted) setState(() => _showIdleBanner = false);
    if (_draftBatch.isNotEmpty) {
      _idleTimer = Timer(kIdleNudgeDuration, () {
        if (mounted && _draftBatch.isNotEmpty) {
          setState(() => _showIdleBanner = true);
        }
      });
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _idleTimer?.cancel();
    _draftSaveDebounce?.cancel();
    _searchDebounce?.cancel();
    _scrollController.dispose();
    _inputController.dispose();
    _searchController.dispose();
    widget.searchTrigger?.removeListener(_onSearchTrigger);
    _pulseSocket?.disconnect();
    _pulseSocket?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() => _appLifecycle = state);
    final active = state == AppLifecycleState.resumed;
    _startPolling(active: active);
    if (!active && _draftBatch.isNotEmpty) {
      // Window backgrounded — show idle banner.
      if (mounted) setState(() => _showIdleBanner = true);
    }
  }

  void _startPolling({required bool active}) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      Duration(seconds: active ? 3 : 10),
      (_) => _fetchMessages(),
    );
  }

  Future<void> _fetchMessages() async {
    if (_fetching) return;
    _fetching = true;
    final uri = Uri.parse(
      _lastTs != null
          ? '$_base/dispatch/conversation?since=${Uri.encodeComponent(_lastTs!)}&limit=200'
          : '$_base/dispatch/conversation?limit=200',
    );
    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 5));
      if (!mounted) {
        _fetching = false;
        return;
      }
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final newMsgs = (data['messages'] as List<dynamic>)
            .map((e) => _Message.fromJson(e as Map<String, dynamic>))
            .toList();
        if (newMsgs.isNotEmpty) {
          // Notification guard — inactive covers brief focus loss (shade pull, tap).
          if (_initialLoadDone && newMsgs.any((m) => m.from != 'mike')) {
            final first = newMsgs.firstWhere((m) => m.from != 'mike');
            final foregrounded = _appLifecycle == AppLifecycleState.resumed ||
                _appLifecycle == AppLifecycleState.inactive;
            if (!foregrounded) {
              // App is backgrounded — fire OS notification.
              AlarmService.instance.notifyDeeReply(first.body);
            } else if (!widget.isActive) {
              // App is foregrounded but user is on a different tab — show toast.
              _showDeeReplyToast(first.body);
            }
            // Foregrounded + on this screen → new message renders inline; no notification.
          }

          // Dedup: match server echoes to optimistic messages by clientId.
          // Swallow exact-body echoes; replace optimistic copy when body differs.
          final Map<int, _Message> replacements = {};
          final dedupedMsgs = newMsgs.where((m) {
            if (m.from != 'mike' || m.clientId == null) return true;
            if (!_pendingClientIds.containsKey(m.clientId!)) return true;
            final optimistic = _pendingClientIds.remove(m.clientId!);
            if (optimistic == null) return false; // batch send → swallow
            if (m.body == optimistic.body)
              return false; // exact match → swallow
            // Body differs (e.g. compressed) → replace optimistic in list
            final idx = _messages.indexOf(optimistic);
            if (idx >= 0) replacements[idx] = m;
            return false;
          }).toList();

          final isInitial = _lastTs == null;
          final hadSpacer = _bottomSpacer > 0 && dedupedMsgs.isNotEmpty;
          final deeArrived = dedupedMsgs.any((m) => m.from != 'mike');
          setState(() {
            for (final e in replacements.entries) {
              _messages[e.key] = e.value;
            }
            if (dedupedMsgs.isNotEmpty) {
              _messages =
                  isInitial ? dedupedMsgs : [..._messages, ...dedupedMsgs];
            }
            // FIX: duplicate-on-send — only advance _lastTs forward, never rewind.
            // Rewinding can re-expose server echoes whose clientId was already removed
            // from _pendingClientIds, causing them to appear as duplicate bubbles.
            final newTs = newMsgs.last.ts;
            if (_lastTs == null || newTs.compareTo(_lastTs!) > 0)
              _lastTs = newTs;
            // Clear the send-spacer now that content is arriving.
            if (hadSpacer) _bottomSpacer = 0;
            // Dismiss thinking indicator when Dee's first chunk arrives.
            if (deeArrived) {
              _showThinking = false;
              _thinkingStart = null;
              _pipelineState = 'replied';
              _lastSentAt = null;
            }
          });

          if (dedupedMsgs.isNotEmpty) {
            // FIX: scroll jump — use _showScrollFab (persistent user-scrolled-away
            // state) rather than instantaneous _isNearBottom so a new Dee reply
            // never jumps the view while the user is actively scrolling upward.
            if (isInitial || !_showScrollFab || hadSpacer) {
              _scrollToBottom(force: hadSpacer);
            } else {
              setState(() => _unreadCount += dedupedMsgs.length);
            }
          }
        }
      }
    } catch (_) {}
    _fetching = false;
    if (!_initialLoadDone) _initialLoadDone = true;
  }

  void _scrollToBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (force || _isNearBottom) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Called immediately after the user submits a message. Sets a bottom spacer
  // equal to 65 % of the viewport so that scrolling to maxScrollExtent places
  // the user bubble near the top of the screen, leaving room for the response
  // to stream in below it.
  void _scrollOnSend() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final viewportH = _scrollController.position.viewportDimension;
      setState(() => _bottomSpacer = viewportH * 0.65);
      // Second callback: runs after the ListView rebuilds with the new spacer.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    });
  }

  // ── Local Send: appends to draft batch, no network ───────────────────
  Future<void> _localSend() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    final newBatch = [..._draftBatch, text];
    _inputController.clear();
    _draftSaveDebounce?.cancel();
    Settings.saveDispatchInputDraft('');
    setState(() {
      _draftBatch = newBatch;
      _showIdleBanner = false;
    });
    await Settings.saveDraftBatch(newBatch);
    _resetIdleTimer();
    _scrollOnSend();
  }

  // ── Remove a draft from the batch ───────────────────────────────────
  Future<void> _removeDraft(int index) async {
    final newBatch = List<String>.from(_draftBatch)..removeAt(index);
    setState(() {
      _draftBatch = newBatch;
      if (newBatch.isEmpty) _showIdleBanner = false;
    });
    await Settings.saveDraftBatch(newBatch);
    if (newBatch.isNotEmpty) _resetIdleTimer();
  }

  // ── Flush draft batch to /dispatch_input_compressed ─────────────────
  Future<void> _flushBatch() async {
    if (_draftBatch.isEmpty || _flushing) return;
    setState(() {
      _flushing = true;
      _showIdleBanner = false;
    });

    final combined = _draftBatch.join('\n\n\n');
    final secret = await _loadSecret();
    final batchClientId = _generateUuid();

    try {
      final resp = await http
          .post(
            Uri.parse('$_base/dispatch_input_compressed'),
            headers: {
              'Content-Type': 'application/json',
              if (secret.isNotEmpty) 'x-dispatch-token': secret,
            },
            body: jsonEncode({
              'message': combined,
              'source': 'pulse-draft-batch',
              'client_id': batchClientId
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;
      if (resp.statusCode == 200) {
        // Show each draft as a "sent" message in the thread (optimistic)
        final now = DateTime.now().toUtc().toIso8601String();
        final sentMessages = _draftBatch
            .map((text) => _Message(
                  from: 'mike',
                  ts: now,
                  body: text,
                  source: 'pulse-draft-batch',
                  sentLocally: true,
                ))
            .toList();
        // Register batch clientId (null = swallow echo without replacing optimistic bubbles)
        _pendingClientIds[batchClientId] = null;
        setState(() {
          _messages = [..._messages, ...sentMessages];
          _lastTs = now;
          _draftBatch = [];
        });
        await Settings.saveDraftBatch([]);
        _idleTimer?.cancel();
        _scrollOnSend();
      } else {
        _showError('Send failed: HTTP ${resp.statusCode}');
      }
    } catch (e) {
      if (mounted) _showError('$e');
    } finally {
      if (mounted) setState(() => _flushing = false);
    }
  }

  // ── Quick "Send now" — bypass batch, send directly ───────────────────
  Future<void> _sendNow() async {
    if (_sending) return;
    final text = _inputController.text.trim();
    final image = _pendingImage;
    if (text.isEmpty && image == null) return;
    setState(() => _sending = true);

    String? imageData;
    String? imageMediaType;
    if (image != null) {
      final bytes = await image.readAsBytes();
      imageData = base64Encode(bytes);
      imageMediaType = _mimeFromPath(image.path);
    }

    final optimisticTs = DateTime.now().toUtc().toIso8601String();
    final clientId = _generateUuid();
    final optimistic = _Message(
      from: 'mike',
      ts: optimisticTs,
      body: text,
      source: 'pulse-quickcapture',
      imageData: imageData,
      imageMediaType: imageMediaType,
      clientId: clientId,
      sentLocally: true,
    );
    _pendingClientIds[clientId] = optimistic;
    setState(() {
      _messages = [..._messages, optimistic];
      _lastTs = optimisticTs;
      _pendingImage = null;
    });
    _inputController.clear();
    _draftSaveDebounce?.cancel();
    Settings.saveDispatchInputDraft('');
    _scrollOnSend();

    final payload = <String, dynamic>{'client_id': clientId};
    if (text.isNotEmpty) payload['text'] = text;
    if (imageData != null)
      payload['image'] = {'data': imageData, 'mediaType': imageMediaType};

    try {
      final resp = await http
          .post(
            Uri.parse('$_base/pulse/capture'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        setState(() {
          _sendSuccess = true;
          _lastSentAt = DateTime.now();
          _pipelineState = 'sent';
        });
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) setState(() => _sendSuccess = false);
      } else {
        _showError('Send failed: HTTP ${resp.statusCode}');
      }
    } catch (e) {
      if (mounted) _showError('$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _generateUuid() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<String> _loadSecret() async {
    // Try to load relay secret from ~/.dispatch/relay.secret
    // On web, we can't read the filesystem; skip the token (localhost-only anyway)
    return '';
  }

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Photo library'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    final file = await _imagePicker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1920,
    );
    if (file != null && mounted) {
      setState(() => _pendingImage = file);
    }
  }

  String _mimeFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  void _showDeeReplyToast(String preview) {
    final trimmed =
        preview.length > 80 ? '${preview.substring(0, 80)}…' : preview;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Dee: $trimmed'),
        duration: const Duration(seconds: 4),
        action: widget.onRequestFocus != null
            ? SnackBarAction(label: 'View', onPressed: widget.onRequestFocus!)
            : null,
      ),
    );
  }

  void _onSearchQueryChanged(String q) {
    _searchDebounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    _searchDebounce =
        Timer(const Duration(milliseconds: 300), () => _runSearch(q.trim()));
  }

  Future<void> _runSearch(String q) async {
    setState(() => _searchLoading = true);
    try {
      final uri = Uri.parse(
          '$_base/conversation/search?q=${Uri.encodeQueryComponent(q)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final results =
            (data['results'] as List<dynamic>).cast<Map<String, dynamic>>();
        setState(() => _searchResults = results);
      }
    } catch (_) {
      if (mounted) setState(() => _searchResults = []);
    } finally {
      if (mounted) setState(() => _searchLoading = false);
    }
  }

  void _onSearchResultTap(Map<String, dynamic> result) {
    final ts = result['timestamp'] as String? ?? '';
    setState(() {
      _searchActive = false;
      _searchController.clear();
      _searchResults = [];
      _highlightedTs = ts;
    });

    // Scroll to approximate position.
    final idx = _messages.indexWhere((m) => m.ts == ts);
    if (idx >= 0 && _scrollController.hasClients) {
      final approx =
          (idx * 90.0).clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.animateTo(
        approx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    }

    // Clear highlight after 2s.
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _highlightedTs = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SelectionArea(
        child: Column(
      children: [
        // ── Pipeline state banner ─────────────────────────────────────
        if (_pipelineState != null &&
            _pipelineState != 'replied' &&
            !_showThinking)
          _PipelineBanner(state: _pipelineState!, sentAt: _lastSentAt),

        // ── Idle / blur nudge banner ──────────────────────────────────
        if (_showIdleBanner && _draftBatch.isNotEmpty)
          _IdleBanner(
            draftCount: _draftBatch.length,
            flushing: _flushing,
            onSend: _flushBatch,
            onDismiss: () => setState(() => _showIdleBanner = false),
          ),

        // ── Thread ────────────────────────────────────────────────────
        Expanded(
          child: Stack(
            children: [
              _messages.isEmpty && _draftBatch.isEmpty
                  ? _EmptyState()
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 16),
                      itemCount: _messages.length +
                          _draftBatch.length +
                          (_showThinking ? 1 : 0) +
                          1,
                      itemBuilder: (ctx, i) {
                        if (i < _messages.length) {
                          return _MessageBubble(
                            msg: _messages[i],
                            highlighted: _messages[i].ts == _highlightedTs,
                          );
                        }
                        final draftIndex = i - _messages.length;
                        if (draftIndex < _draftBatch.length) {
                          return _DraftBubble(
                            text: _draftBatch[draftIndex],
                            onRemove: () => _removeDraft(draftIndex),
                          );
                        }
                        final postDraft =
                            i - _messages.length - _draftBatch.length;
                        if (_showThinking && postDraft == 0) {
                          return _ThinkingBubble(
                              since: _thinkingStart ?? DateTime.now());
                        }
                        // Bottom spacer: non-zero only during scroll-on-send.
                        return SizedBox(height: _bottomSpacer);
                      },
                    ),
              // ── Search overlay ────────────────────────────────────────
              if (_searchActive)
                _SearchOverlay(
                  controller: _searchController,
                  results: _searchResults,
                  loading: _searchLoading,
                  onQueryChanged: _onSearchQueryChanged,
                  onResultTap: _onSearchResultTap,
                  onClose: () => setState(() {
                    _searchActive = false;
                    _searchController.clear();
                    _searchResults = [];
                    _searchDebounce?.cancel();
                  }),
                ),
              // ── ↓ N new pill — shown when scrolled up with arrivals ──
              if (_unreadCount > 0)
                Positioned(
                  bottom: 8,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: _jumpToBottom,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(
                                color: Colors.black26,
                                blurRadius: 6,
                                offset: Offset(0, 2)),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.arrow_downward,
                                color: Colors.white, size: 14),
                            const SizedBox(width: 5),
                            Text(
                              '$_unreadCount new',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              // ── Scroll-to-bottom FAB — shown whenever not at bottom ──
              if (_showScrollFab)
                Positioned(
                  bottom: 8,
                  right: 16,
                  child: FloatingActionButton.small(
                    onPressed: _jumpToBottom,
                    tooltip: 'Scroll to latest',
                    backgroundColor: theme.colorScheme.surface,
                    foregroundColor: theme.colorScheme.onSurface,
                    elevation: 3,
                    child: const Icon(Icons.keyboard_arrow_down, size: 22),
                  ),
                ),
            ],
          ),
        ),

        // ── Input bar ─────────────────────────────────────────────────
        _InputBar(
          controller: _inputController,
          sending: _sending,
          flushing: _flushing,
          success: _sendSuccess,
          hasDrafts: _draftBatch.isNotEmpty,
          pendingImage: _pendingImage,
          onLocalSend: _localSend,
          onSendToDee: _flushBatch,
          onSendNow: _sendNow,
          onAttachImage: _pickImage,
          onRemoveImage: () => setState(() => _pendingImage = null),
        ),
      ],
    ));
  }
}

// ── Data model ───────────────────────────────────────────────────────────────

class _Message {
  final String from;
  final String? speaker;
  final String ts;
  final String body;
  final String? source;
  final String? inReplyTo;
  final String? imageData;
  final String? imageMediaType;
  final String? clientId;
  // True for messages added optimistically by the client (not from server poll).
  final bool sentLocally;

  const _Message({
    required this.from,
    this.speaker,
    required this.ts,
    required this.body,
    this.source,
    this.inReplyTo,
    this.imageData,
    this.imageMediaType,
    this.clientId,
    this.sentLocally = false,
  });

  factory _Message.fromJson(Map<String, dynamic> j) {
    final img = j['image'] as Map<String, dynamic>?;
    return _Message(
      from: (j['from'] as String?) ?? 'mike',
      speaker: j['speaker'] as String?,
      ts: (j['ts'] as String?) ?? '',
      body: (j['body'] as String?) ?? '',
      source: j['source'] as String?,
      inReplyTo: j['in_reply_to'] as String?,
      imageData: img?['data'] as String?,
      imageMediaType: img?['mediaType'] as String?,
      clientId: j['client_id'] as String?,
    );
  }
}

// ── Draft bubble ─────────────────────────────────────────────────────────────

class _DraftBubble extends StatelessWidget {
  final String text;
  final VoidCallback onRemove;
  const _DraftBubble({required this.text, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 480),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.35),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(4),
                ),
                border: Border.all(
                  color: theme.colorScheme.primary.withOpacity(0.5),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SelectableText(text,
                      style: TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.onSurface.withOpacity(0.7))),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('draft',
                            style: TextStyle(
                                fontSize: 10,
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.errorContainer,
              ),
              child:
                  Icon(Icons.close, size: 12, color: theme.colorScheme.error),
            ),
          ),
          const SizedBox(width: 6),
          CircleAvatar(
            radius: 14,
            backgroundColor: theme.colorScheme.primary.withOpacity(0.4),
            child: const Text('M',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ── Idle / blur nudge banner ──────────────────────────────────────────────────

class _IdleBanner extends StatelessWidget {
  final int draftCount;
  final bool flushing;
  final VoidCallback onSend;
  final VoidCallback onDismiss;
  const _IdleBanner({
    required this.draftCount,
    required this.flushing,
    required this.onSend,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF9C4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.schedule_send, size: 18, color: Color(0xFF8B6914)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Ready to send $draftCount draft${draftCount == 1 ? '' : 's'} to Dee?',
              style: const TextStyle(fontSize: 13, color: Color(0xFF8B6914)),
            ),
          ),
          TextButton(
            onPressed: flushing ? null : onSend,
            child: flushing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Send',
                    style: TextStyle(
                        color: Color(0xFF8B6914), fontWeight: FontWeight.bold)),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 16, color: Color(0xFF8B6914)),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

// ── Pipeline state banner ─────────────────────────────────────────────────────

class _PipelineBanner extends StatefulWidget {
  final String state;
  final DateTime? sentAt;
  const _PipelineBanner({required this.state, this.sentAt});

  @override
  State<_PipelineBanner> createState() => _PipelineBannerState();
}

class _PipelineBannerState extends State<_PipelineBanner> {
  late Timer _ticker;
  int _elapsed = 0;

  @override
  void initState() {
    super.initState();
    _elapsed = widget.sentAt != null
        ? DateTime.now().difference(widget.sentAt!).inSeconds
        : 0;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _elapsed = widget.sentAt != null
              ? DateTime.now().difference(widget.sentAt!).inSeconds
              : _elapsed + 1;
        });
      }
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = switch (widget.state) {
      'sent' => 'Sent · waiting for Dee…',
      'working' => 'Dee is working…',
      _ => widget.state,
    };
    final elapsed = _elapsed > 0 ? ' (${_elapsed}s)' : '';
    return Container(
      width: double.infinity,
      color: const Color(0xFF1A2733),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.tealAccent)),
          const SizedBox(width: 10),
          Text(
            '$label$elapsed',
            style: const TextStyle(fontSize: 12, color: Colors.tealAccent),
          ),
        ],
      ),
    );
  }
}

// ── Message bubble ───────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final _Message msg;
  final bool highlighted;
  const _MessageBubble({required this.msg, this.highlighted = false});

  @override
  Widget build(BuildContext context) {
    final isMike = msg.from == 'mike';
    final speaker = msg.speaker ?? (isMike ? 'Mike' : msg.from);
    final theme = Theme.of(context);
    final ts = _formatTs(msg.ts);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isMike ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMike) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: theme.colorScheme.secondary,
              child: Text(speaker.isEmpty ? 'A' : speaker[0].toUpperCase(),
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              constraints: const BoxConstraints(maxWidth: 480),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: highlighted
                    ? const Color(0xFFFFF59D)
                    : isMike
                        ? theme.colorScheme.primary.withOpacity(0.85)
                        : theme.colorScheme.surfaceVariant,
                border: highlighted
                    ? Border.all(color: const Color(0xFFF9A825), width: 2)
                    : null,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMike ? 16 : 4),
                  bottomRight: Radius.circular(isMike ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment:
                    isMike ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isMike) ...[
                    Text(
                      speaker,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                    const SizedBox(height: 3),
                  ],
                  if (msg.imageData != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        base64Decode(msg.imageData!),
                        width: 220,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
                    ),
                    if (msg.body.isNotEmpty) const SizedBox(height: 6),
                  ],
                  if (msg.body.isNotEmpty)
                    isMike
                        ? SelectableText(msg.body,
                            style: TextStyle(
                                fontSize: 14,
                                color: highlighted
                                    ? const Color(0xFF333333)
                                    : theme.colorScheme.onPrimary))
                        // FIX: text selection — MarkdownBody selectable:true conflicts
                        // with the outer SelectionArea; let SelectionArea own it.
                        : MarkdownBody(
                            data: msg.body,
                            styleSheet: MarkdownStyleSheet(
                              p: TextStyle(
                                  fontSize: 14,
                                  color: theme.colorScheme.onSurfaceVariant),
                              code: TextStyle(
                                  fontSize: 12,
                                  backgroundColor: theme.colorScheme.surface,
                                  color: theme.colorScheme.onSurface),
                            ),
                            onTapLink: (text, href, title) {
                              if (href != null) {
                                launchUrl(
                                  Uri.parse(href),
                                  mode: LaunchMode.externalApplication,
                                );
                              }
                            },
                          ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        ts,
                        style: TextStyle(
                            fontSize: 11,
                            color: highlighted
                                ? const Color(0xFF555555)
                                : isMike
                                    ? theme.colorScheme.onPrimary
                                        .withOpacity(0.6)
                                    : theme.colorScheme.onSurfaceVariant
                                        .withOpacity(0.5)),
                      ),
                      if (isMike && msg.sentLocally) ...[
                        const SizedBox(width: 4),
                        Text(
                          '✓ Sent',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onPrimary.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isMike) ...[
            const SizedBox(width: 6),
            CircleAvatar(
              radius: 14,
              backgroundColor: theme.colorScheme.primary,
              child: const Text('M',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTs(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inSeconds < 60) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24 && dt.day == now.day) {
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      return '${dt.month}/${dt.day} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}

// ── Thinking bubble (animated relay-ACK indicator) ───────────────────────────

class _ThinkingBubble extends StatefulWidget {
  final DateTime since;
  const _ThinkingBubble({required this.since});

  @override
  State<_ThinkingBubble> createState() => _ThinkingBubbleState();
}

class _ThinkingBubbleState extends State<_ThinkingBubble> {
  late Timer _ticker;
  int _elapsed = 0;
  int _dot = 0;

  @override
  void initState() {
    super.initState();
    _elapsed = DateTime.now().difference(widget.since).inSeconds;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _elapsed = DateTime.now().difference(widget.since).inSeconds;
          _dot = (_dot + 1) % 4;
        });
      }
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dots = '.' * (_dot == 0 ? 1 : _dot);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: theme.colorScheme.secondary,
            child: const Text('D',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
          ),
          const SizedBox(width: 6),
          Container(
            constraints: const BoxConstraints(maxWidth: 480),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Text(
              'Dee · ${_elapsed}s$dots',
              style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                  fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline,
              size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            'Type a message.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Tap send to message Dee. Long-press to save locally.\nSend to Dee flushes drafts.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }
}

// ── Input bar ─────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final bool flushing;
  final bool success;
  final bool hasDrafts;
  final XFile? pendingImage;
  final VoidCallback onLocalSend;
  final VoidCallback onSendToDee;
  final VoidCallback onSendNow;
  final VoidCallback onAttachImage;
  final VoidCallback onRemoveImage;

  const _InputBar({
    required this.controller,
    required this.sending,
    required this.flushing,
    required this.success,
    required this.hasDrafts,
    required this.onLocalSend,
    required this.onSendToDee,
    required this.onSendNow,
    required this.onAttachImage,
    required this.onRemoveImage,
    this.pendingImage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Image preview strip
          if (pendingImage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(pendingImage!.path),
                      height: 80,
                      width: 80,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: -6,
                    right: -6,
                    child: GestureDetector(
                      onTap: onRemoveImage,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.errorContainer,
                        ),
                        child: Icon(Icons.close,
                            size: 12, color: theme.colorScheme.error),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Attach image button
              GestureDetector(
                onTap: onAttachImage,
                child: Padding(
                  padding: const EdgeInsets.only(right: 4, bottom: 10),
                  child: Icon(
                    Icons.attach_file,
                    size: 20,
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  // FIX: down-arrow nav to About — absorb vertical arrow keys that
                  // the TextField leaves unhandled (e.g. empty field on web/desktop)
                  // so they cannot propagate to the Scaffold's focus traversal and
                  // accidentally activate the About IconButton.
                  child: Focus(
                    onKeyEvent: (node, event) {
                      if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
                          event.logicalKey == LogicalKeyboardKey.arrowUp) {
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      controller: controller,
                      decoration: InputDecoration(
                        hintText: pendingImage != null
                            ? 'Add a caption…'
                            : 'Message Dee…',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      style: const TextStyle(fontSize: 14),
                      enabled: !sending && !flushing,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                    ),
                  ),
                ),
              ),
              // Dual-mode send: tap = send to Dee, long-press = local draft
              _DualSendButton(
                sending: sending,
                flushing: flushing,
                success: success,
                onSendNow: onSendNow,
                onLocalSend: pendingImage != null ? onSendNow : onLocalSend,
              ),
            ],
          ),
          // Send to Dee button (visible when drafts are queued)
          if (hasDrafts)
            Align(
              alignment: Alignment.centerLeft,
              child: _SmallButton(
                label: flushing ? 'Sending…' : 'Send to Dee',
                icon: Icons.send_to_mobile,
                tooltip: 'Flush drafts to Dee via compression layer',
                onPressed: flushing ? null : onSendToDee,
                enabled: !flushing,
                primary: true,
              ),
            ),
        ],
      ),
    );
  }
}

// Tap = send to Dee; long-press = save locally with haptic + toast.
class _DualSendButton extends StatefulWidget {
  final bool sending;
  final bool flushing;
  final bool success;
  final VoidCallback onSendNow;
  final VoidCallback onLocalSend;

  const _DualSendButton({
    required this.sending,
    required this.flushing,
    required this.success,
    required this.onSendNow,
    required this.onLocalSend,
  });

  @override
  State<_DualSendButton> createState() => _DualSendButtonState();
}

class _DualSendButtonState extends State<_DualSendButton> {
  bool _pressing = false;

  void _onLongPress() {
    setState(() => _pressing = false);
    HapticFeedback.mediumImpact();
    widget.onLocalSend();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sent locally'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: widget.success
          ? const Icon(Icons.check_circle,
              key: ValueKey('ok'), color: Colors.green, size: 22)
          : widget.sending
              ? const SizedBox(
                  key: ValueKey('spin'),
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              // FIX: send-arrow collision — enforce 44dp minimum tap target
              : ConstrainedBox(
                  constraints:
                      const BoxConstraints(minWidth: 44, minHeight: 44),
                  child: GestureDetector(
                    key: const ValueKey('send-now'),
                    onTap: widget.onSendNow,
                    onLongPress: _onLongPress,
                    onLongPressStart: (_) => setState(() => _pressing = true),
                    onLongPressEnd: (_) => setState(() => _pressing = false),
                    onLongPressCancel: () => setState(() => _pressing = false),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        decoration: BoxDecoration(
                          color: _pressing
                              ? theme.colorScheme.tertiary
                                  .withValues(alpha: 0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          Icons.send,
                          size: 20,
                          color: _pressing
                              ? theme.colorScheme.tertiary
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool enabled;
  final bool primary;

  const _SmallButton({
    required this.label,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.enabled = true,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: TextButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        style: TextButton.styleFrom(
          foregroundColor: primary
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

// ── Search overlay ────────────────────────────────────────────────────────────

class _SearchOverlay extends StatelessWidget {
  final TextEditingController controller;
  final List<Map<String, dynamic>> results;
  final bool loading;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<Map<String, dynamic>> onResultTap;
  final VoidCallback onClose;

  const _SearchOverlay({
    required this.controller,
    required this.results,
    required this.loading,
    required this.onQueryChanged,
    required this.onResultTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      elevation: 4,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Search input bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Search your Pulse conversation…',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                      style: const TextStyle(fontSize: 14),
                      onChanged: onQueryChanged,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Close search',
                    onPressed: onClose,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: theme.dividerColor),
            // Results
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : results.isEmpty && controller.text.isNotEmpty
                      ? Center(
                          child: Text(
                            'No results',
                            style: TextStyle(color: theme.colorScheme.outline),
                          ),
                        )
                      : results.isEmpty
                          ? Center(
                              child: Text(
                                'Search your Pulse conversation.',
                                style:
                                    TextStyle(color: theme.colorScheme.outline),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              itemCount: results.length,
                              separatorBuilder: (_, __) =>
                                  Divider(height: 1, color: theme.dividerColor),
                              itemBuilder: (ctx, i) {
                                final r = results[i];
                                return _SearchResultTile(
                                    result: r, onTap: onResultTap);
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final Map<String, dynamic> result;
  final ValueChanged<Map<String, dynamic>> onTap;

  const _SearchResultTile({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = result['source'] as String? ?? 'mike';
    final snippet = result['snippet'] as String? ?? '';
    final matchIndices = result['match_indices'] as List<dynamic>?;
    final ts = result['timestamp'] as String? ?? '';
    final isMike = source == 'mike';
    final label = isMike ? 'You' : 'Dee';
    final labelColor =
        isMike ? theme.colorScheme.primary : theme.colorScheme.secondary;

    // Format timestamp
    String formattedTs = '';
    try {
      final dt = DateTime.parse(ts).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inSeconds < 60) {
        formattedTs = 'just now';
      } else if (diff.inMinutes < 60) {
        formattedTs = '${diff.inMinutes}m ago';
      } else if (diff.inHours < 24 && dt.day == now.day) {
        formattedTs =
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } else {
        formattedTs =
            '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
    } catch (_) {}

    // Build snippet with highlighted match.
    TextSpan snippetSpan;
    if (matchIndices != null && matchIndices.length == 2) {
      final start = (matchIndices[0] as num).toInt().clamp(0, snippet.length);
      final end = (matchIndices[1] as num).toInt().clamp(start, snippet.length);
      snippetSpan = TextSpan(
        children: [
          if (start > 0) TextSpan(text: snippet.substring(0, start)),
          TextSpan(
            text: snippet.substring(start, end),
            style: const TextStyle(
              backgroundColor: Color(0xFFFFF59D),
              color: Color(0xFF333333),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (end < snippet.length) TextSpan(text: snippet.substring(end)),
        ],
        style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface),
      );
    } else {
      snippetSpan = TextSpan(
        text: snippet,
        style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface),
      );
    }

    return InkWell(
      onTap: () => onTap(result),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: labelColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      color: labelColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formattedTs,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            RichText(
              text: snippetSpan,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
