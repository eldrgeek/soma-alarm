import 'dart:async';

import 'package:http/http.dart' as http;

/// Tries a list of candidate relay URLs in order, returns the first one that
/// answers /jobs/status with HTTP 200. Caches the winner for the lifetime of
/// the resolver so subsequent fetches don't re-probe.
///
/// Phase 1a chose hardcoded fallbacks over mDNS for two reasons:
/// 1. `multicast_dns` adds Android multicast-permission complexity for what
///    is currently a single-host network (Mike's Mac).
/// 2. The known-good IP is enough for daily use; once Tailscale is installed
///    the Tailscale name will work without any code change.
class RelayResolver {
  final String userUrl;
  final List<String> candidates;
  final http.Client _http;
  final Duration probeTimeout;

  String? _cached;
  Map<String, String> _lastErrors = const {};

  RelayResolver({
    required this.userUrl,
    required this.candidates,
    http.Client? client,
    this.probeTimeout = const Duration(seconds: 3),
  }) : _http = client ?? http.Client();

  String? get cached => _cached;
  Map<String, String> get lastErrors => Map.unmodifiable(_lastErrors);

  /// Returns the first reachable URL. Uses cached value if set; reset() to
  /// force a re-probe.
  Future<String> resolve() async {
    final cached = _cached;
    if (cached != null) return cached;
    final order = <String>[];
    void addUnique(String u) {
      final n = _normalize(u);
      if (n.isNotEmpty && !order.contains(n)) order.add(n);
    }

    addUnique(userUrl);
    for (final c in candidates) {
      addUnique(c);
    }

    final errors = <String, String>{};
    for (final url in order) {
      final result = await _probe(url);
      if (result == null) {
        _cached = url;
        _lastErrors = errors;
        return url;
      }
      errors[url] = result;
    }
    _lastErrors = errors;
    throw RelayResolverException(errors);
  }

  /// Probe a single URL. Returns null on success, error string on failure.
  /// Public so the "Test connection" UI can probe without affecting cache.
  Future<String?> probeOne(String url) async => _probe(_normalize(url));

  Future<String?> _probe(String url) async {
    try {
      final res = await _http
          .get(Uri.parse('$url/jobs/status'))
          .timeout(probeTimeout);
      if (res.statusCode == 200) return null;
      return 'HTTP ${res.statusCode}';
    } catch (e) {
      return _short(e);
    }
  }

  void reset() {
    _cached = null;
    _lastErrors = const {};
  }

  void close() => _http.close();

  static String _normalize(String url) {
    var u = url.trim();
    if (u.isEmpty) return '';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    if (!u.startsWith('http')) u = 'http://$u';
    return u;
  }

  static String _short(Object e) {
    final s = '$e';
    // Trim noisy stack-style suffixes; keep the SocketException reason etc.
    final lineEnd = s.indexOf('\n');
    return lineEnd > 0 ? s.substring(0, lineEnd) : s;
  }
}

class RelayResolverException implements Exception {
  final Map<String, String> attemptErrors;
  RelayResolverException(this.attemptErrors);
  @override
  String toString() {
    final lines = attemptErrors.entries
        .map((e) => '  • ${e.key} → ${e.value}')
        .join('\n');
    return 'No relay URL reachable. Tried:\n$lines';
  }
}

/// Default candidate list. Ordered most-likely-to-work first.
/// User-set URL from settings is tried before any of these.
const List<String> kDefaultRelayCandidates = [
  'http://192.168.4.36:3333',     // Mac LAN IP (Phase 1a known-good)
  'http://mikes-mac.local:3333',  // mDNS (works if avahi/bonjour resolves)
  'http://mikes-mac:3333',        // Tailscale name (works once installed)
];
