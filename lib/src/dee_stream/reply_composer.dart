import 'package:flutter/material.dart';

import 'dispatch_input_client.dart';

/// Bottom-sheet composer for replying to Dee. Returns the composed
/// [YouSaidEntry] to the caller (DeeStreamPage), which optimistically appends
/// it to the feed before the POST returns.
///
/// Status states:
///   • idle      — text field, Send button enabled when non-empty
///   • sending   — spinner overlay, Send disabled
///   • failed    — inline error banner; Send re-enabled
///
/// Bottom-sheet (not FAB-only) was chosen over a full screen so Mike can see
/// the most recent Dee card scroll up behind the sheet — context preserved.
Future<YouSaidEntry?> showReplyComposer(
  BuildContext context, {
  required DispatchInputClient client,
}) {
  return showModalBottomSheet<YouSaidEntry>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(ctx).viewInsets.bottom,
      ),
      child: _ReplyComposer(client: client),
    ),
  );
}

class _ReplyComposer extends StatefulWidget {
  final DispatchInputClient client;
  const _ReplyComposer({required this.client});

  @override
  State<_ReplyComposer> createState() => _ReplyComposerState();
}

class _ReplyComposerState extends State<_ReplyComposer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });

    final result = await widget.client.send(text);
    if (!mounted) return;

    if (result.ok) {
      final entry = YouSaidEntry(
        body: text,
        sentAt: DateTime.now(),
        serverTimestamp: result.timestamp,
        status: 'sent',
      );
      Navigator.of(context).pop(entry);
      return;
    }

    setState(() {
      _sending = false;
      _error = result.error ?? 'Send failed.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Reply to Dee', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            key: const Key('reply_composer_field'),
            controller: _controller,
            focusNode: _focus,
            maxLines: 6,
            minLines: 3,
            enabled: !_sending,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              hintText: 'Type your reply…',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline,
                      color: theme.colorScheme.onErrorContainer, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      _error!,
                      style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                          fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _sending ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const Key('reply_composer_send'),
                onPressed: (_sending || _controller.text.trim().isEmpty)
                    ? null
                    : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send, size: 18),
                label: Text(_sending ? 'Sending…' : 'Send'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
