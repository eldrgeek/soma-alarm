class MessageSegment {
  final String text;
  final String? heading;
  const MessageSegment(this.text, {this.heading});
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

const _segmentThreshold = 800;

/// Split a long Dee message into selectable segments and pull out open-items.
/// Segmentation rule: only kicks in for bodies > 800 chars; splits on blank
/// lines, falling back to markdown headings if there are no blank lines.
SegmentedMessage segmentMessage(String body) {
  final trimmed = body.trim();
  final openItems = _extractOpenItems(trimmed);

  if (trimmed.length <= _segmentThreshold) {
    return SegmentedMessage(
      segments: [MessageSegment(trimmed)],
      openItems: openItems,
      wasSegmented: false,
    );
  }

  final segments = <MessageSegment>[];
  String? currentHeading;
  final headingRe = RegExp(r'^#{1,6}\s+(.+)$');

  final paragraphs = trimmed
      .split(RegExp(r'\n\s*\n'))
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();

  if (paragraphs.length <= 1) {
    final lines = trimmed.split('\n');
    final buf = <String>[];
    for (final line in lines) {
      final m = headingRe.firstMatch(line.trim());
      if (m != null) {
        if (buf.isNotEmpty) {
          segments.add(MessageSegment(buf.join('\n').trim(),
              heading: currentHeading));
          buf.clear();
        }
        currentHeading = m.group(1);
        buf.add(line);
      } else {
        buf.add(line);
      }
    }
    if (buf.isNotEmpty) {
      segments.add(MessageSegment(buf.join('\n').trim(),
          heading: currentHeading));
    }
  } else {
    for (final para in paragraphs) {
      final firstLine = para.split('\n').first.trim();
      final m = headingRe.firstMatch(firstLine);
      final heading = m?.group(1);
      segments.add(MessageSegment(para, heading: heading));
    }
  }

  if (segments.isEmpty) {
    segments.add(MessageSegment(trimmed));
  }

  return SegmentedMessage(
    segments: segments,
    openItems: openItems,
    wasSegmented: segments.length > 1,
  );
}

List<OpenItem> _extractOpenItems(String body) {
  final items = <OpenItem>[];

  // "Open on your court" section: collect bullet/numbered lines that follow.
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

  // "Reply: yes / hell yes / no / waya" inline patterns.
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
