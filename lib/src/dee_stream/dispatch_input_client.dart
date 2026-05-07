import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'relay_resolver.dart';

/// Result returned by [DispatchInputClient.send].
/// `ok` is true on HTTP 200 with a `queued: true` body. `timestamp` is the
/// server-recorded ISO-8601 timestamp of the queue entry, used to render the
/// "you said" card.
class DispatchInputResult {
  final bool ok;
  final String? timestamp;
  final String? error;
  final int? statusCode;

  const DispatchInputResult({
    required this.ok,
    this.timestamp,
    this.error,
    this.statusCode,
  });
}

/// Client for the relay's /dispatch_input endpoint.
///
/// Resolves the active relay URL via [RelayResolver] (same fallback chain
/// the Dee Stream poller uses) and POSTs `{message, source}` with the
/// X-Dispatch-Token header. Phase 1b only emits "sent"; the daemon's
/// pickup → "confirmed" round-trip is v2.
class DispatchInputClient {
  final RelayResolver resolver;
  final http.Client _http;
  final String Function() _tokenGetter;

  DispatchInputClient({
    required this.resolver,
    required String Function() tokenGetter,
    http.Client? client,
  })  : _http = client ?? http.Client(),
        _tokenGetter = tokenGetter;

  Future<DispatchInputResult> send(
    String message, {
    String source = 'pulse',
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final token = _tokenGetter();
    if (token.isEmpty) {
      return const DispatchInputResult(
        ok: false,
        error: 'Dispatch token not set. Settings → Dispatch Token.',
      );
    }
    final trimmed = message.trim();
    if (trimmed.isEmpty) {
      return const DispatchInputResult(ok: false, error: 'Empty message.');
    }
    if (trimmed.length > 8000) {
      return const DispatchInputResult(
        ok: false,
        error: 'Message exceeds 8000 chars.',
      );
    }

    String base;
    try {
      base = await resolver.resolve();
    } catch (e) {
      return DispatchInputResult(ok: false, error: 'Relay unreachable: $e');
    }

    final uri = Uri.parse('$base/dispatch_input');
    try {
      final res = await _http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'X-Dispatch-Token': token,
            },
            body: jsonEncode({'message': trimmed, 'source': source}),
          )
          .timeout(timeout);

      if (res.statusCode == 200) {
        try {
          final body = jsonDecode(res.body) as Map<String, dynamic>;
          if (body['queued'] == true) {
            return DispatchInputResult(
              ok: true,
              timestamp: body['timestamp']?.toString(),
              statusCode: 200,
            );
          }
          return DispatchInputResult(
            ok: false,
            error: 'Unexpected body: ${res.body}',
            statusCode: 200,
          );
        } catch (_) {
          return DispatchInputResult(
            ok: false,
            error: 'Bad JSON from relay',
            statusCode: 200,
          );
        }
      }

      String why;
      switch (res.statusCode) {
        case 401:
          why = 'Bad token. Check Settings → Dispatch Token.';
          break;
        case 403:
          why = 'Forbidden — not on LAN/Tailscale.';
          break;
        case 413:
          why = 'Message too large.';
          break;
        case 503:
          why = 'Relay secret not configured on host.';
          break;
        default:
          why = 'HTTP ${res.statusCode}';
      }
      return DispatchInputResult(
        ok: false,
        error: why,
        statusCode: res.statusCode,
      );
    } on TimeoutException {
      return const DispatchInputResult(ok: false, error: 'Timed out.');
    } catch (e) {
      return DispatchInputResult(ok: false, error: '$e');
    }
  }

  void close() => _http.close();
}

/// A "you said" entry that mirrors a successful dispatch_input POST. Lives
/// alongside DeeSaidEntry in the unified Dee Stream feed.
class YouSaidEntry {
  final String body;
  final DateTime sentAt;
  final String? serverTimestamp;
  final String status; // 'sending' | 'sent' | 'failed'
  final String? error;

  const YouSaidEntry({
    required this.body,
    required this.sentAt,
    this.serverTimestamp,
    this.status = 'sent',
    this.error,
  });

  YouSaidEntry copyWith({String? status, String? error, String? serverTimestamp}) {
    return YouSaidEntry(
      body: body,
      sentAt: sentAt,
      serverTimestamp: serverTimestamp ?? this.serverTimestamp,
      status: status ?? this.status,
      error: error ?? this.error,
    );
  }
}
