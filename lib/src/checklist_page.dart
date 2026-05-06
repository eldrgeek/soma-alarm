import 'package:flutter/material.dart';

import 'checklist.dart';

/// Surface contract used by [ChecklistPage]. Real app uses [ChecklistRepo];
/// widget tests inject an in-memory fake.
abstract class ChecklistApi {
  Future<void> resetIfNewDay();
  Future<List<ChecklistRoutine>> routines();
  Future<List<ChecklistItem>> items(int routineId);
  Future<int> createRoutine(String name);
  Future<void> deleteRoutine(int routineId);
  Future<int> addItem(int routineId, String label);
  Future<void> removeItem(int itemId);
  Future<void> setChecked(int itemId, bool checked);
}

class ChecklistPage extends StatefulWidget {
  final ChecklistApi? repo;
  const ChecklistPage({super.key, this.repo});

  @override
  State<ChecklistPage> createState() => _ChecklistPageState();
}

class _ChecklistPageState extends State<ChecklistPage> {
  late final ChecklistApi _repo = widget.repo ?? ChecklistRepo();
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

  Future<void> _showRoutineActions(ChecklistRoutine routine) async {
    final isOnly = _routines.length <= 1;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.label_outline),
              title: Text(routine.name),
              subtitle: routine.isMorning
                  ? const Text('Morning routine (default)')
                  : null,
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: isOnly
                    ? Theme.of(ctx).disabledColor
                    : Theme.of(ctx).colorScheme.error,
              ),
              title: Text(
                'Delete routine',
                style: TextStyle(
                  color: isOnly
                      ? Theme.of(ctx).disabledColor
                      : Theme.of(ctx).colorScheme.error,
                ),
              ),
              subtitle: isOnly
                  ? const Text("Can't delete the only routine")
                  : null,
              enabled: !isOnly,
              onTap: () async {
                Navigator.pop(ctx);
                await _confirmAndDeleteRoutine(routine);
              },
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndDeleteRoutine(ChecklistRoutine routine) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${routine.name}"?'),
        content: const Text(
          'This deletes the routine and all of its items. This cannot be undone.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _repo.deleteRoutine(routine.id);
    if (_selected?.id == routine.id) {
      _selected = null;
    }
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
      body: SelectionArea(
        child: Column(
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
                  return GestureDetector(
                    onLongPress: () => _showRoutineActions(r),
                    child: ChoiceChip(
                      label: Text(r.name),
                      selected: isSel,
                      onSelected: (_) async {
                        setState(() => _selected = r);
                        await _load();
                      },
                    ),
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
