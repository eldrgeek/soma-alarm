import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'meta_glasses_service.dart';
import 'settings.dart';

class GlassesConversationScreen extends StatefulWidget {
  const GlassesConversationScreen({super.key});

  @override
  State<GlassesConversationScreen> createState() =>
      _GlassesConversationScreenState();
}

class _GlassesConversationScreenState extends State<GlassesConversationScreen> {
  final _speech = SpeechToText();
  final _tts = FlutterTts();
  final _simulation = TextEditingController();
  final _glasses = MetaGlassesService.instance;

  StreamSubscription<MetaGlassesStatus>? _statusSubscription;
  Timer? _replyPoll;
  MetaGlassesStatus _status = const MetaGlassesStatus();
  String _base = Settings.defaultYeshieHost;
  String _recipient = 'dee';
  String _mode = 'auto';
  String _transcript = '';
  String _reply = '';
  String? _pendingTimestamp;
  bool _speechReady = false;
  bool _listening = false;
  bool _waiting = false;
  bool _autoContinue = false;
  bool _submittedCurrentListen = false;

  // Persistent conversation log — survives auto-continue restarts so replies
  // don't vanish when the next listen begins.
  final List<({String role, String text})> _history = [];

  static const _recipients = {
    'dee': 'Dee',
    'codex': 'Codex',
    'opie': 'Opie',
    'skip': 'Skip',
    'team': 'Strategy Team',
  };

  static const _modes = {
    'auto': 'Voice decides',
    'conversation': 'Conversation',
    'dispatch': 'Dispatch work',
    'strategy': 'Strategy panel',
  };

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    _base = await Settings.yeshieHost();
    _speechReady = await _speech.initialize(
      onStatus: (status) {
        if (!mounted) return;
        if (status == 'done' || status == 'notListening') {
          setState(() => _listening = false);
          if (_transcript.trim().isNotEmpty && !_submittedCurrentListen) {
            _submit(_transcript);
          }
        }
      },
      onError: (error) => _showError(error.errorMsg),
    );
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.48);
    await _tts.awaitSpeakCompletion(true);
    _statusSubscription = _glasses.statuses.listen((status) {
      if (mounted) setState(() => _status = status);
    });
    if (_glasses.supported) {
      try {
        final status = await _glasses.initialize();
        if (mounted) setState(() => _status = status);
      } catch (e) {
        _showError('Meta DAT: $e');
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _connect() async {
    try {
      final status = await _glasses.initialize();
      if (mounted) setState(() => _status = status);
      if (!status.initialized) {
        _showMessage(
            'Permissions requested. Approve them, then tap Connect again.');
        return;
      }
      await _glasses.register();
      _showMessage('Continue registration in the Meta AI app.');
    } catch (e) {
      _showError('Connect failed: $e');
    }
  }

  Future<void> _enableMock() async {
    try {
      final status = await _glasses.enableMock();
      if (mounted) setState(() => _status = status);
      _showMessage(
          'Mock Ray-Ban Meta frames are ready. Use text simulation below.');
    } catch (e) {
      _showError('Mock setup failed: $e');
    }
  }

  Future<void> _startListening() async {
    if (!_speechReady) {
      _showError('Android speech recognition is unavailable.');
      return;
    }
    try {
      final route = await _glasses.routeAudio();
      if (_glasses.supported && route['routed'] != true) {
        _showMessage('${route['error'] ?? 'Using the phone microphone.'}');
      }
      _submittedCurrentListen = false;
      setState(() {
        _transcript = '';
        _reply = '';
        _listening = true;
      });
      await _speech.listen(
        onResult: _onSpeechResult,
        listenOptions: SpeechListenOptions(
          listenFor: const Duration(minutes: 2),
          pauseFor: const Duration(seconds: 3),
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
        ),
      );
    } catch (e) {
      _showError('Listen failed: $e');
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (!mounted) return;
    setState(() => _transcript = result.recognizedWords);
    if (result.finalResult &&
        _transcript.trim().isNotEmpty &&
        !_submittedCurrentListen) {
      _submit(_transcript);
    }
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    if (_transcript.trim().isNotEmpty && !_submittedCurrentListen) {
      await _submit(_transcript);
    }
  }

  Future<void> _submit(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty || _waiting || _submittedCurrentListen) return;
    _submittedCurrentListen = true;
    await _speech.stop();
    setState(() {
      _listening = false;
      _waiting = true;
      _reply = '';
      _transcript = text;
      _history.add((role: 'You', text: text));
    });

    try {
      final response = await http
          .post(
            Uri.parse('$_base/pulse/voice/turn'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'text': text,
              'mode': _mode,
              'recipient': _mode == 'strategy' ? 'team' : _recipient,
              'dispatch_target': 'auto',
              'client_id': 'glasses-${DateTime.now().microsecondsSinceEpoch}',
            }),
          )
          .timeout(const Duration(seconds: 12));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(data['error'] ?? 'HTTP ${response.statusCode}');
      }
      _pendingTimestamp = data['timestamp'] as String?;
      if (_pendingTimestamp == null) {
        throw Exception('Relay omitted turn timestamp');
      }
      _startReplyPolling();
    } catch (e) {
      if (mounted) setState(() => _waiting = false);
      await _glasses.clearAudioRoute();
      _showError('Send failed: $e');
    }
  }

  void _startReplyPolling() {
    _replyPoll?.cancel();
    var attempts = 0;
    _replyPoll = Timer.periodic(const Duration(seconds: 2), (timer) async {
      attempts++;
      if (attempts > 90) {
        timer.cancel();
        if (mounted) setState(() => _waiting = false);
        await _glasses.clearAudioRoute();
        _showError('The team did not answer within three minutes.');
        return;
      }
      await _pollForReply();
    });
    _pollForReply();
  }

  Future<void> _pollForReply() async {
    final pending = _pendingTimestamp;
    if (pending == null) return;
    try {
      final since = DateTime.parse(pending)
          .subtract(const Duration(milliseconds: 1))
          .toIso8601String();
      final response = await http
          .get(Uri.parse(
              '$_base/dispatch/conversation?since=${Uri.encodeQueryComponent(since)}&limit=30'))
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final messages = (data['messages'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
      final match = messages
          .where((message) => message['in_reply_to'] == pending)
          .firstOrNull;
      if (match == null) return;
      _replyPoll?.cancel();
      final speaker =
          match['speaker']?.toString() ?? match['from']?.toString() ?? 'Team';
      final body = match['body']?.toString() ?? '';
      if (!mounted) return;
      setState(() {
        _waiting = false;
        _reply = '$speaker: $body';
        _history.add((role: speaker, text: body));
      });
      await _tts.speak(body);
      await _glasses.clearAudioRoute();
      if (_autoContinue && mounted) await _startListening();
    } catch (_) {
      // Polling is intentionally tolerant of brief Mac/Tailscale interruptions.
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message),
          backgroundColor: Theme.of(context).colorScheme.error),
    );
  }

  @override
  void dispose() {
    _replyPoll?.cancel();
    _statusSubscription?.cancel();
    _simulation.dispose();
    _speech.cancel();
    _tts.stop();
    _glasses.clearAudioRoute();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = _status.deviceCount > 0 || _status.mock;
    return Scaffold(
      appBar: AppBar(title: const Text('Meta Glasses')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(connected ? Icons.check_circle : Icons.headset_mic,
                          color: connected
                              ? Colors.green
                              : theme.colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _status.mock
                              ? 'Mock Ray-Ban Meta connected'
                              : '${_status.registration} · ${_status.deviceCount} device(s)',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _glasses.supported ? _connect : null,
                        icon: const Icon(Icons.link),
                        label: const Text('Connect'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _glasses.supported ? _enableMock : null,
                        icon: const Icon(Icons.science_outlined),
                        label: const Text('Mock frames'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Connect opens Meta AI registration. Audio uses the glasses HFP microphone and speakers.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _mode,
            decoration: const InputDecoration(
                labelText: 'Turn type', border: OutlineInputBorder()),
            items: _modes.entries
                .map((entry) => DropdownMenuItem(
                    value: entry.key, child: Text(entry.value)))
                .toList(),
            onChanged: (value) =>
                setState(() => _mode = value ?? 'conversation'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _recipient,
            decoration: const InputDecoration(
                labelText: 'Teammate', border: OutlineInputBorder()),
            items: _recipients.entries
                .map((entry) => DropdownMenuItem(
                    value: entry.key, child: Text(entry.value)))
                .toList(),
            onChanged: _mode == 'strategy'
                ? null
                : (value) => setState(() => _recipient = value ?? 'dee'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Continue listening after each reply'),
            value: _autoContinue,
            onChanged: (value) => setState(() => _autoContinue = value),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 72,
            child: FilledButton.icon(
              onPressed: _waiting
                  ? null
                  : (_listening ? _stopListening : _startListening),
              icon: Icon(_listening ? Icons.stop_circle : Icons.mic, size: 32),
              label: Text(_listening
                  ? 'Stop and send'
                  : _waiting
                      ? 'Waiting for the team…'
                      : 'Talk'),
            ),
          ),
          if (_listening && _transcript.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('You (speaking)…', style: theme.textTheme.labelLarge),
            Text(_transcript, style: theme.textTheme.bodyLarge),
          ],
          if (_waiting) ...[
            const SizedBox(height: 16),
            Row(
              children: const [
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10),
                Text('Waiting for the team…'),
              ],
            ),
          ],
          if (_history.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Conversation', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            // Newest exchange first, so the latest reply is visible without
            // scrolling and never gets wiped by the next listen.
            ..._history.reversed.map(
              (m) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.role,
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: theme.colorScheme.primary),
                    ),
                    const SizedBox(height: 2),
                    Text(m.text, style: theme.textTheme.bodyLarge),
                  ],
                ),
              ),
            ),
          ],
          const Divider(height: 40),
          Text('Test without glasses', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _simulation,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: 'Type a turn, e.g. “Codex, what should we build next?”',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _waiting
                ? null
                : () {
                    final text = _simulation.text;
                    _simulation.clear();
                    _submittedCurrentListen = false;
                    _submit(text);
                  },
            child: const Text('Send simulated turn'),
          ),
          const SizedBox(height: 16),
          const Text(
            'Voice shortcuts: “Codex, …” · “Ask Opie …” · “Start a strategic discussion …” · “Dispatch to code: …”',
          ),
        ],
      ),
    );
  }
}
