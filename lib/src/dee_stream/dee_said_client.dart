import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'dee_said_models.dart';
import 'relay_resolver.dart';

class DeeSaidClient {
  final RelayResolver resolver;
  final http.Client _http;

  DeeSaidClient({required this.resolver, http.Client? client})
      : _http = client ?? http.Client();

  /// PRIMARY MECHANISM: HTTP polling against /jobs/status.
  /// Socket.IO upgrade was deferred — relay exposes Socket.IO on the same
  /// port but the Flutter socket_io_client dep wasn't worth the bring-up
  /// cost for a 10s poll. Note marker for Phase 1b.
  Future<List<DeeSaidEntry>> fetchEntries({Duration? timeout}) async {
    final base = await resolver.resolve();
    final uri = Uri.parse('$base/jobs/status');
    final res = await _http
        .get(uri)
        .timeout(timeout ?? const Duration(seconds: 8));
    if (res.statusCode != 200) {
      // If the cached URL went bad, drop it and let next fetch re-probe.
      resolver.reset();
      throw HttpException(
          'relay /jobs/status returned ${res.statusCode}: ${res.body}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final jobs = (body['jobs'] as List?) ?? const [];
    final entries = <DeeSaidEntry>[];
    for (final raw in jobs) {
      if (raw is! Map) continue;
      final id = '${raw['id'] ?? ''}';
      if (!id.startsWith('dee-said-')) continue;
      if (id == 'svc-dee-said-bridge') continue;
      entries.add(
        DeeSaidEntry.fromJson(Map<String, dynamic>.from(raw)),
      );
    }
    entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return entries;
  }

  /// Best-effort POST of a per-segment reaction to the relay's
  /// /dispatch_input endpoint. Local persistence is the source of truth;
  /// failure here is logged via thrown exception but the caller should
  /// swallow it — Mike's tag must always succeed locally.
  Future<void> postReaction({
    required String segmentId,
    required String deeMessageId,
    required String reaction,
    String? note,
    String? segmentText,
    Duration? timeout,
  }) async {
    final base = await resolver.resolve();
    final uri = Uri.parse('$base/dispatch_input');
    final res = await _http
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'segment_id': segmentId,
            'dee_message_id': deeMessageId,
            'reaction': reaction,
            'source': 'pulse-segment-bar',
            if (note != null && note.isNotEmpty) 'note': note,
            if (segmentText != null && segmentText.isNotEmpty)
              'segment_text': segmentText,
          }),
        )
        .timeout(timeout ?? const Duration(seconds: 6));
    if (res.statusCode >= 400) {
      throw HttpException(
          'relay /dispatch_input returned ${res.statusCode}: ${res.body}');
    }
  }

  void close() => _http.close();
}

class HttpException implements Exception {
  final String message;
  HttpException(this.message);
  @override
  String toString() => message;
}
