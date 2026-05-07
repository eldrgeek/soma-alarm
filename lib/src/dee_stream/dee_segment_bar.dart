import 'package:flutter/material.dart';

import 'dee_reactions.dart';

typedef OnReactionTap = Future<void> Function(String token);
typedef OnThreadSubmit = Future<void> Function(String note);

/// Compact response bar shown beneath each Dee message segment.
/// Five buttons: ✓ read · 💬 thread · ❓ confused · 🔥 landed · 🤔 pushback.
/// `read` is an independent toggle; the other four are mutually exclusive
/// per-segment.
class SegmentResponseBar extends StatefulWidget {
  final SegmentReaction current;
  final OnReactionTap onTap;
  final OnThreadSubmit onSubmitThread;

  const SegmentResponseBar({
    super.key,
    required this.current,
    required this.onTap,
    required this.onSubmitThread,
  });

  @override
  State<SegmentResponseBar> createState() => _SegmentResponseBarState();
}

class _SegmentResponseBarState extends State<SegmentResponseBar> {
  bool _composerOpen = false;
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.current.note ?? '');
  bool _submitting = false;

  @override
  void didUpdateWidget(covariant SegmentResponseBar old) {
    super.didUpdateWidget(old);
    // If the persisted note changes from elsewhere, sync the field unless the
    // user is actively composing.
    if (!_composerOpen &&
        (widget.current.note ?? '') != (old.current.note ?? '')) {
      _ctrl.text = widget.current.note ?? '';
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _tap(String token) async {
    if (token == Reaction.thread) {
      setState(() => _composerOpen = !_composerOpen);
    }
    await widget.onTap(token);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      setState(() => _composerOpen = false);
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.onSubmitThread(text);
      if (!mounted) return;
      setState(() {
        _composerOpen = false;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.current;
    final showComposer =
        _composerOpen || (r.note != null && r.note!.isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              _ReactionChip(
                key: const Key('reaction-read'),
                glyph: '✓',
                tooltip: 'I read this',
                active: r.tokens.contains(Reaction.read),
                onTap: () => _tap(Reaction.read),
              ),
              _ReactionChip(
                key: const Key('reaction-thread'),
                glyph: '💬',
                tooltip: 'Open a thread on this point',
                active: r.tokens.contains(Reaction.thread) ||
                    (r.note != null && r.note!.isNotEmpty),
                onTap: () => _tap(Reaction.thread),
              ),
              _ReactionChip(
                key: const Key('reaction-confused'),
                glyph: '❓',
                tooltip: 'I want clarification',
                active: r.tokens.contains(Reaction.confused),
                onTap: () => _tap(Reaction.confused),
              ),
              _ReactionChip(
                key: const Key('reaction-landed'),
                glyph: '🔥',
                tooltip: 'This landed — push it further',
                active: r.tokens.contains(Reaction.landed),
                onTap: () => _tap(Reaction.landed),
              ),
              _ReactionChip(
                key: const Key('reaction-pushback'),
                glyph: '🤔',
                tooltip: 'I want to push back',
                active: r.tokens.contains(Reaction.pushback),
                onTap: () => _tap(Reaction.pushback),
              ),
            ],
          ),
        ),
        if (showComposer)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('segment-thread-composer'),
                    controller: _ctrl,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Thread on this segment…',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  key: const Key('segment-thread-send'),
                  onPressed: _submitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ReactionChip extends StatelessWidget {
  final String glyph;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;
  const _ReactionChip({
    super.key,
    required this.glyph,
    required this.tooltip,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: tooltip,
        child: InkResponse(
          onTap: onTap,
          radius: 22,
          child: Container(
            width: 36,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active
                  ? theme.colorScheme.primaryContainer
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: active
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
                width: active ? 1.4 : 1.0,
              ),
            ),
            child: Text(glyph, style: const TextStyle(fontSize: 16)),
          ),
        ),
      ),
    );
  }
}

/// Existing four-button protocol: yes / hell yes / no / waya.
/// Used in place of [SegmentResponseBar] when the segment ends with that
/// `Reply: …` line (see [isFourButtonSegment]).
class FourButtonReplyBar extends StatelessWidget {
  final String? selected;
  final Future<void> Function(String choice) onChoose;
  final List<String> choices;
  const FourButtonReplyBar({
    super.key,
    required this.selected,
    required this.onChoose,
    this.choices = const ['yes', 'hell yes', 'no', 'waya'],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final c in choices)
            ChoiceChip(
              key: Key('four-button-$c'),
              label: Text(c),
              selected: selected == c,
              onSelected: (_) => onChoose(c),
              labelStyle: TextStyle(
                color: selected == c
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
              selectedColor: theme.colorScheme.primary,
            ),
        ],
      ),
    );
  }
}
