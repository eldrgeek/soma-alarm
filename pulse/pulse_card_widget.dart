import 'package:flutter/material.dart';

// PulseCard — renders a single card from the Pulse card data model.
// Wire to CardService.fetchCard(id) after receiving FCM push.
// This is the v0 renderer scaffold; action dispatch is stubbed.

enum PulseCardType { reply, yes_no, multiple_choice, link, file, permission, pending_action, checklist }

class PulseCardData {
  final String id;
  final PulseCardType type;
  final String title;
  final String? body;
  final List<PulseCardAction> actions;
  final String priority;
  final String urgency;
  final Map<String, dynamic>? typeData;

  const PulseCardData({
    required this.id,
    required this.type,
    required this.title,
    this.body,
    required this.actions,
    required this.priority,
    required this.urgency,
    this.typeData,
  });

  factory PulseCardData.fromJson(Map<String, dynamic> json) {
    return PulseCardData(
      id: json['id'] as String,
      type: PulseCardType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => PulseCardType.reply,
      ),
      title: json['title'] as String,
      body: json['body'] as String?,
      actions: (json['actions'] as List<dynamic>? ?? [])
          .map((a) => PulseCardAction.fromJson(a as Map<String, dynamic>))
          .toList(),
      priority: json['priority'] as String? ?? 'normal',
      urgency: json['urgency'] as String? ?? 'async',
      typeData: json['type_data'] as Map<String, dynamic>?,
    );
  }
}

class PulseCardAction {
  final String id;
  final String label;
  final String actionType;
  final dynamic value;
  final String style;

  const PulseCardAction({
    required this.id,
    required this.label,
    required this.actionType,
    this.value,
    required this.style,
  });

  factory PulseCardAction.fromJson(Map<String, dynamic> json) {
    return PulseCardAction(
      id: json['id'] as String,
      label: json['label'] as String,
      actionType: json['action_type'] as String,
      value: json['value'],
      style: json['style'] as String? ?? 'secondary',
    );
  }
}

class PulseCardWidget extends StatelessWidget {
  final PulseCardData card;
  final void Function(PulseCardAction action) onAction;

  const PulseCardWidget({super.key, required this.card, required this.onAction});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context),
            if (card.body != null && card.body!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(card.body!, style: Theme.of(context).textTheme.bodyMedium),
            ],
            if (card.type == PulseCardType.checklist) ...[
              const SizedBox(height: 12),
              _buildChecklist(context),
            ],
            if (card.actions.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildActions(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        _typeIcon(),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            card.title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        if (card.urgency == 'blocking')
          const Icon(Icons.priority_high, color: Colors.orange, size: 18),
      ],
    );
  }

  Widget _typeIcon() {
    final iconData = switch (card.type) {
      PulseCardType.yes_no => Icons.help_outline,
      PulseCardType.multiple_choice => Icons.list,
      PulseCardType.link => Icons.link,
      PulseCardType.file => Icons.insert_drive_file_outlined,
      PulseCardType.permission => Icons.security,
      PulseCardType.pending_action => Icons.task_alt,
      PulseCardType.checklist => Icons.checklist,
      PulseCardType.reply => Icons.chat_bubble_outline,
    };
    return Icon(iconData, size: 20, color: Colors.white70);
  }

  Widget _buildChecklist(BuildContext context) {
    final items = (card.typeData?['items'] as List<dynamic>? ?? []);
    return Column(
      children: items.map((item) {
        final label = item['label'] as String? ?? '';
        final checked = item['checked'] as bool? ?? false;
        return CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          value: checked,
          onChanged: (_) {
            // TODO: update local state, call onAction with checklist item toggle
          },
        );
      }).toList(),
    );
  }

  Widget _buildActions(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: card.actions.map((action) {
        final isPrimary = action.style == 'primary';
        final isDestructive = action.style == 'destructive';
        if (isPrimary) {
          return FilledButton(
            onPressed: () => onAction(action),
            child: Text(action.label),
          );
        } else if (isDestructive) {
          return OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => onAction(action),
            child: Text(action.label),
          );
        } else {
          return OutlinedButton(
            onPressed: () => onAction(action),
            child: Text(action.label),
          );
        }
      }).toList(),
    );
  }
}

// PulseCardList — scrollable list of cards for the Pulse home screen.
class PulseCardList extends StatelessWidget {
  final List<PulseCardData> cards;
  final void Function(PulseCardData card, PulseCardAction action) onAction;

  const PulseCardList({super.key, required this.cards, required this.onAction});

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return const Center(
        child: Text('No cards right now.', style: TextStyle(color: Colors.white54)),
      );
    }
    return ListView.builder(
      itemCount: cards.length,
      itemBuilder: (context, index) {
        final card = cards[index];
        return PulseCardWidget(
          card: card,
          onAction: (action) => onAction(card, action),
        );
      },
    );
  }
}
