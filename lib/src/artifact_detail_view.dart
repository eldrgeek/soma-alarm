import 'package:flutter/material.dart';

class ArtifactDetailView extends StatelessWidget {
  final Map<String, dynamic> item;

  const ArtifactDetailView({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final name = item['name']?.toString() ?? item['path']?.toString() ?? 'Artifact';
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          name,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (item['kind'] != null) _field(context, 'Kind', _KindBadge(kind: item['kind'] as String)),
          _selectableField(context, 'Name', name),
          if (item['path'] != null) _selectableField(context, 'Path', item['path'] as String),
          if (item['mtime'] != null) _selectableField(context, 'Modified', _formatMtime(item['mtime'] as String)),
          if (item['size_bytes'] != null)
            _selectableField(context, 'Size', _formatSize(item['size_bytes'] as int)),
          ..._extraFields(context, item),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Tap an artifact row in Activity to view file content inline.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(BuildContext context, String label, Widget value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.grey,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: value),
        ],
      ),
    );
  }

  Widget _selectableField(BuildContext context, String label, String value) {
    return _field(
      context,
      label,
      SelectableText(
        value,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      ),
    );
  }

  List<Widget> _extraFields(BuildContext context, Map<String, dynamic> item) {
    const knownKeys = {'name', 'path', 'kind', 'mtime', 'size_bytes'};
    final extras = <Widget>[];
    for (final entry in item.entries) {
      if (knownKeys.contains(entry.key)) continue;
      final v = entry.value;
      if (v == null) continue;
      extras.add(_selectableField(context, entry.key, v.toString()));
    }
    return extras;
  }

  String _formatMtime(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} '
        '${_pad(dt.hour)}:${_pad(dt.minute)}:${_pad(dt.second)}';
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}

class _KindBadge extends StatelessWidget {
  final String kind;
  const _KindBadge({required this.kind});

  Color _color() => switch (kind) {
        'audit' => Colors.blue,
        'log' => Colors.grey,
        'report' => Colors.green,
        'spec' => Colors.orange,
        'wall' => Colors.purple,
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    final color = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        border: Border.all(color: color.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        kind,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
