import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'dee_said_models.dart';

class DeeSaidClient {
  final String baseUrl;
  final http.Client _http;

  DeeSaidClient(this.baseUrl, {http.Client? client})
      : _http = client ?? http.Client();

  /// PRIMARY MECHANISM: HTTP polling against /jobs/status.
  /// Socket.IO upgrade was deferred — relay exposes Socket.IO on the same
  /// port but the Flutter socket_io_client dep wasn't worth the bring-up
  /// cost for a 10s poll. Note marker for Phase 1b.
  Future<List<DeeSaidEntry>> fetchEntries({Duration? timeout}) async {
    final uri = Uri.parse('${_normalizeBase(baseUrl)}/jobs/status');
    final res = await _http
        .get(uri)
        .timeout(timeout ?? const Duration(seconds: 8));
    if (res.statusCode != 200) {
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

  void close() => _http.close();

  static String _normalizeBase(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    if (!u.startsWith('http')) {
      u = 'http://$u';
    }
    return u;
  }
}

class HttpException implements Exception {
  final String message;
  HttpException(this.message);
  @override
  String toString() => message;
}
