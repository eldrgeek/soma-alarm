import 'package:flutter/material.dart';

import 'checklist.dart';

class ChecklistPage extends StatefulWidget {
  const ChecklistPage({super.key});

  @override
  State<ChecklistPage> createState() => _ChecklistPageState();
}

class _ChecklistPageState extends State<ChecklistPage> {
  final _repo = ChecklistRepo();
  List<ChecklistRoutine> _routines = [];
  ChecklistRoutine? _selected;
  List<ChecklistItem> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _repo.resetIfNewDay();
    final r = await _repo.routines();
    final selected = _selected != null
        ? r.firstWhere((x) => x.id == _selected!.id, orElse: () => r.first)
        : (r.isNotEmpty ? r.first : null);
    final items =
        selected != null ? await _repo.items(selected.id) : <ChecklistItem>[];
    if (!mounted) return;
    setState(() {
      _routines = r;
      _selected = selected;
      _items = items;
    });
  }

  Future<void> _newRoutine() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New routine'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await _repo.createRoutine(name);
    await _load();
  }

  Future<void> _addItem() async {
    if (_selected == null) return;
    final controller = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New item'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Label'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Add')),
        ],
      ),
    );
    if (label == null || label.isEmpty) return;
    await _repo.addItem(_selected!.id, label);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Routines'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_box_outlined),
            tooltip: 'New routine',
            onPressed: _newRoutine,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_routines.isNotEmpty)
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemBuilder: (_, i) {
                  final r = _routines[i];
                  final isSel = _selected?.id == r.id;
                  return ChoiceChip(
                    label: Text(r.name),
                    selected: isSel,
                    onSelected: (_) async {
                      setState(() => _selected = r);
                      await _load();
                    },
                  );
                },
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemCount: _routines.length,
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: _items.isEmpty
                ? const Center(child: Text('No items.'))
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (_, i) {
                      final it = _items[i];
                      return CheckboxListTile(
                        value: it.checked,
                        title: Text(it.label),
                        secondary: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await _repo.removeItem(it.id);
                            await _load();
                          },
                        ),
                        onChanged: (v) async {
                          await _repo.setChecked(it.id, v ?? false);
                          await _load();
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _selected == null
          ? null
          : FloatingActionButton(
              onPressed: _addItem,
              child: const Icon(Icons.add),
            ),
    );
  }
}
