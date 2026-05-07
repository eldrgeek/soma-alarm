import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Tokens for the per-segment response bar.
/// Kept as plain strings so they're stable in JSON storage and on the relay.
class Reaction {
  static const read = 'read';        // ✓
  static const thread = 'thread';    // 💬
  static const confused = 'confused';// ❓
  static const landed = 'landed';    // 🔥
  static const pushback = 'pushback';// 🤔

  /// All reactions other than `read` are mutually exclusive (a segment can be
  /// "read" AND "landed", but it can't be both "landed" and "pushback").
  static const exclusive = {confused, landed, pushback, thread};
}

class SegmentReaction {
  final Set<String> tokens;
  final String? note;
  const SegmentReaction({this.tokens = const {}, this.note});

  bool get isEmpty => tokens.isEmpty && (note == null || note!.isEmpty);

  Map<String, dynamic> toJson() => {
        if (tokens.isNotEmpty) 't': tokens.toList(),
        if (note != null && note!.isNotEmpty) 'n': note,
      };

  factory SegmentReaction.fromJson(Map<String, dynamic> j) => SegmentReaction(
        tokens: ((j['t'] as List?) ?? const []).map((e) => '$e').toSet(),
        note: j['n'] as String?,
      );

  SegmentReaction toggle(String token) {
    final next = Set<String>.from(tokens);
    if (next.contains(token)) {
      next.remove(token);
    } else {
      if (Reaction.exclusive.contains(token)) {
        next.removeWhere(Reaction.exclusive.contains);
      }
      next.add(token);
    }
    return SegmentReaction(tokens: next, note: note);
  }

  SegmentReaction withNote(String? n) =>
      SegmentReaction(tokens: tokens, note: n);
}

/// Local-first persistence for per-segment reactions. Single SharedPreferences
/// key holds the whole map (small payloads, infrequent writes).
class ReactionsRepo {
  static const _prefsKey = 'dee.segmentReactions.v1';

  /// Allows tests to inject an in-memory store.
  final Future<SharedPreferences> Function() _getPrefs;
  ReactionsRepo({Future<SharedPreferences> Function()? getPrefs})
      : _getPrefs = getPrefs ?? SharedPreferences.getInstance;

  final _controller = StreamController<void>.broadcast();
  Stream<void> get changes => _controller.stream;

  Map<String, SegmentReaction>? _cache;

  Future<Map<String, SegmentReaction>> _load() async {
    if (_cache != null) return _cache!;
    final p = await _getPrefs();
    final raw = p.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      _cache = {};
      return _cache!;
    }
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _cache = map.map(
        (k, v) => MapEntry(k, SegmentReaction.fromJson(
            Map<String, dynamic>.from(v as Map))),
      );
    } catch (_) {
      _cache = {};
    }
    return _cache!;
  }

  Future<SegmentReaction> get(String segmentId) async {
    final map = await _load();
    return map[segmentId] ?? const SegmentReaction();
  }

  Future<void> set(String segmentId, SegmentReaction r) async {
    final map = await _load();
    if (r.isEmpty) {
      map.remove(segmentId);
    } else {
      map[segmentId] = r;
    }
    final p = await _getPrefs();
    await p.setString(
      _prefsKey,
      jsonEncode(map.map((k, v) => MapEntry(k, v.toJson()))),
    );
    _controller.add(null);
  }

  Future<SegmentReaction> toggle(String segmentId, String token) async {
    final cur = await get(segmentId);
    final next = cur.toggle(token);
    await set(segmentId, next);
    return next;
  }

  Future<SegmentReaction> setNote(String segmentId, String? note) async {
    final cur = await get(segmentId);
    await set(segmentId, cur.withNote(note));
    return cur.withNote(note);
  }

  void dispose() => _controller.close();
}
