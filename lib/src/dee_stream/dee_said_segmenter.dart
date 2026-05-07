class MessageSegment {
  final String text;
  final String? heading;
  final int index;
  const MessageSegment(this.text, {this.heading, this.index = 0});

  /// Stable per-segment id derived from the parent entry id + segment index +
  /// a short content hash. Survives rebuild of the same content; if the text
  /// of segment N changes, the id changes too so an old reaction doesn't carry
  /// forward to a different paragraph.
  String idFor(String entryId) => '$entryId#$index-${_hash6(text)}';
}

class OpenItem {
  final String prompt;
  final List<String> choices;
  const OpenItem(this.prompt, {this.choices = const []});
}

class SegmentedMessage {
  final List<MessageSegment> segments;
  final List<OpenItem> openItems;
  final bool wasSegmented;
  const SegmentedMessage({
    required this.segments,
    required this.openItems,
    required this.wasSegmented,
  });
}

const _minSegmentChars = 20;

/// Phase-1a-extension: per-segment response bars need granular segments for
/// every Dee message, not only long ones. Always segment by paragraph; merge
/// trivially-short fragments into the next segment to avoid orphaned bars.
SegmentedMessage segmentMessage(String body) {
  final trimmed = body.trim();
  final openItems = _extractOpenItems(trimmed);

  if (trimmed.isEmpty) {
    return const SegmentedMessage(
      segments: [MessageSegment('', index: 0)],
      openItems: [],
      wasSegmented: false,
    );
  }

  final raw = _splitPreservingCodeBlocks(trimmed);
  final headingRe = RegExp(r'^#{1,6}\s+(.+)$');

  final merged = <String>[];
  for (final p in raw) {
    final t = p.trim();
    if (t.isEmpty) continue;
    final isCode = t.startsWith('```');
    if (!isCode && t.length < _minSegmentChars && merged.isNotEmpty) {
      // Tiny fragment: glue onto previous segment so the user doesn't get a
      // lonely emoji bar under a one-word line.
      merged[merged.length - 1] = '${merged.last}\n\n$t';
    } else {
      merged.add(t);
    }
  }
  // Edge case: if the very first fragment was tiny, it would have escaped the
  // merge above (no previous to glue to). Pull it forward into the next.
  if (merged.length >= 2 &&
      !merged.first.startsWith('```') &&
      merged.first.length < _minSegmentChars) {
    merged[1] = '${merged.first}\n\n${merged[1]}';
    merged.removeAt(0);
  }

  final segments = <MessageSegment>[];
  for (var i = 0; i < merged.length; i++) {
    final para = merged[i];
    final firstLine = para.split('\n').first.trim();
    final m = headingRe.firstMatch(firstLine);
    segments.add(MessageSegment(para, heading: m?.group(1), index: i));
  }

  if (segments.isEmpty) {
    segments.add(MessageSegment(trimmed, index: 0));
  }

  return SegmentedMessage(
    segments: segments,
    openItems: openItems,
    wasSegmented: segments.length > 1,
  );
}

/// Split by `\n\n` and `---` rules, but treat fenced code blocks as opaque so
/// internal blank lines inside code don't fragment them.
List<String> _splitPreservingCodeBlocks(String body) {
  final out = <String>[];
  final lines = body.split('\n');
  final buf = <String>[];
  bool inCode = false;
  void flush() {
    if (buf.isEmpty) return;
    out.add(buf.join('\n'));
    buf.clear();
  }

  for (final line in lines) {
    final t = line.trim();
    if (t.startsWith('```')) {
      if (!inCode) {
        flush();
        buf.add(line);
        inCode = true;
      } else {
        buf.add(line);
        inCode = false;
        flush();
      }
      continue;
    }
    if (inCode) {
      buf.add(line);
      continue;
    }
    // Horizontal rule: --- on its own line splits.
    if (RegExp(r'^-{3,}$').hasMatch(t)) {
      flush();
      continue;
    }
    if (t.isEmpty) {
      flush();
      continue;
    }
    buf.add(line);
  }
  flush();
  return out;
}

/// Heuristic for the existing four-button protocol:
/// Reply: yes / hell yes / no / waya  (or "why are you asking?")
final RegExp _fourButtonRe = RegExp(
  r'Reply:\s*(yes\s*/\s*hell\s*yes\s*/\s*no\s*/\s*waya|why\s+are\s+you\s+asking\?)',
  caseSensitive: false,
);

bool isFourButtonSegment(String segmentText) =>
    _fourButtonRe.hasMatch(segmentText);

String _hash6(String s) {
  // Tiny non-cryptographic hash, 6 hex chars. Stable across runs.
  var h = 5381;
  for (final c in s.codeUnits) {
    h = ((h << 5) + h + c) & 0x7fffffff;
  }
  return h.toRadixString(16).padLeft(8, '0').substring(0, 6);
}

List<OpenItem> _extractOpenItems(String body) {
  final items = <OpenItem>[];

  final openSectionRe = RegExp(
      r'(?:^|\n)\s*#{0,6}\s*Open\s+on\s+your\s+court[:\s]*\n(.+?)(?=\n\s*\n#{1,6}|\n\s*\n[A-Z]|\Z)',
      caseSensitive: false, dotAll: true);
  for (final m in openSectionRe.allMatches(body)) {
    final block = m.group(1) ?? '';
    final lines = block.split('\n');
    for (final line in lines) {
      final cleaned = line.replaceFirst(RegExp(r'^\s*[-*\d+\.\)]+\s*'), '').trim();
      if (cleaned.isEmpty) continue;
      items.add(OpenItem(cleaned));
    }
  }

  final replyRe = RegExp(
      r'Reply:\s*([a-zA-Z][a-zA-Z\s/]*?)(?=\n|$)',
      caseSensitive: false);
  for (final m in replyRe.allMatches(body)) {
    final raw = (m.group(1) ?? '').trim();
    if (raw.isEmpty) continue;
    final choices = raw
        .split(RegExp(r'\s*/\s*'))
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList();
    final ctxStart = (m.start - 120).clamp(0, body.length).toInt();
    final preceding = body
        .substring(ctxStart, m.start)
        .trim()
        .split(RegExp(r'\n\s*\n'))
        .last
        .trim();
    items.add(OpenItem(
      preceding.isEmpty ? 'Reply' : preceding,
      choices: choices,
    ));
  }

  return items;
}
