class DeeSaidEntry {
  final String id;
  final String title;
  final String body;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DeeSaidEntry({
    required this.id,
    required this.title,
    required this.body,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DeeSaidEntry.fromJson(Map<String, dynamic> j) {
    int ms(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
    return DeeSaidEntry(
      id: '${j['id']}',
      title: '${j['title'] ?? 'Dee said:'}',
      body: '${j['step'] ?? j['result'] ?? ''}',
      status: '${j['status'] ?? ''}',
      createdAt: DateTime.fromMillisecondsSinceEpoch(ms(j['createdAt'])),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(ms(j['updatedAt'])),
    );
  }

  String get firstLine {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return '(empty)';
    final newline = trimmed.indexOf('\n');
    final firstSentenceEnd = trimmed.indexOf(RegExp(r'[.!?](?=\s|$)'));
    int cut = trimmed.length;
    if (newline > 0 && newline < cut) cut = newline;
    if (firstSentenceEnd > 0 && firstSentenceEnd + 1 < cut) {
      cut = firstSentenceEnd + 1;
    }
    if (cut > 80) cut = 80;
    return trimmed.substring(0, cut).trim();
  }
}
