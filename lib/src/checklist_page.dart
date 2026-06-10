import 'package:flutter/material.dart';

import 'checklist.dart';
import 'voice_capture.dart';

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
    final id = await _repo.createRoutine(name);
    await _load();
    // Select the newly created routine
    if (mounted) {
      final r = _routines.firstWhere((x) => x.id == id, orElse: () => _routines.first);
      setState(() => _selected = r);
    }
  }

  Future<void> _editRoutine(ChecklistRoutine routine) async {
    final nameCtrl = TextEditingController(text: routine.name);
    final timeCtrl = TextEditingController(text: routine.triggerTime ?? '');
    String recurrence = routine.recurrence;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Edit routine'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: timeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Time (HH:MM, optional)',
                  hintText: 'e.g. 07:00',
                ),
                keyboardType: TextInputType.datetime,
              ),
              const SizedBox(height: 12),
              const Text('Recurrence', style: TextStyle(fontSize: 12, color: Colors.grey)),
              Wrap(
                spacing: 6,
                children: ['daily', 'weekdays', 'weekends', 'manual'].map((r) {
                  return ChoiceChip(
                    label: Text(r),
                    selected: recurrence == r,
                    onSelected: (_) => setS(() => recurrence = r),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx, false);
                await _repo.deleteRoutine(routine.id);
                await _load();
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (result != true) return;
    final newName = nameCtrl.text.trim();
    final newTime = timeCtrl.text.trim().isEmpty ? null : timeCtrl.text.trim();
    await _repo.updateRoutine(routine.id,
        name: newName.isNotEmpty ? newName : null,
        triggerTime: newTime,
        recurrence: recurrence);
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

  Future<void> _toggleItem(ChecklistItem it, bool newValue) async {
    // Optimistic update so the checkbox feels instant.
    setState(() {
      _items = _items
          .map((x) => x.id == it.id
              ? x.copyWith(checked: newValue, checkedAt: newValue ? DateTime.now() : null)
              : x)
          .toList();
    });
    try {
      await _repo.setChecked(it.id, newValue);
    } catch (e) {
      // Revert on DB failure
      if (mounted) {
        setState(() {
          _items = _items
              .map((x) => x.id == it.id ? it : x)
              .toList();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    // Sync authoritative state from DB (handles reset-if-new-day edge cases)
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Routines'),
            if (_selected != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _editRoutine(_selected!),
                child: const Icon(Icons.edit_outlined, size: 16, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
      body: Column(
        children: [
          if (_routines.isNotEmpty || true)
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: _routines.length + 1, // +1 for the "+" chip
                itemBuilder: (_, i) {
                  // Last item = "Add new routine" button
                  if (i == _routines.length) {
                    return ActionChip(
                      avatar: const Icon(Icons.add, size: 16),
                      label: const Text('New'),
                      onPressed: _newRoutine,
                    );
                  }
                  final r = _routines[i];
                  final isSel = _selected?.id == r.id;
                  return GestureDetector(
                    onLongPress: () => _editRoutine(r),
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
              ),
            ),
          if (_selected != null && (_selected!.triggerTime != null || _selected!.recurrence != 'daily'))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: [
                  const Icon(Icons.schedule, size: 12, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    [
                      if (_selected!.triggerTime != null) _selected!.triggerTime!,
                      _selected!.recurrence,
                    ].join(' · '),
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: _items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('No items.', style: TextStyle(color: Colors.grey)),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: _addItem,
                          icon: const Icon(Icons.add),
                          label: const Text('Add first item'),
                        ),
                      ],
                    ),
                  )
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
                        onChanged: (v) => _toggleItem(it, v ?? false),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _selected == null
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (kVoiceCaptureEnabled)
                  VoiceCaptureButton(
                    onLine: (line) async {
                      await _repo.addItem(_selected!.id, line);
                      await _load();
                    },
                  ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'add_item',
                  onPressed: _addItem,
                  child: const Icon(Icons.add),
                ),
              ],
            ),
    );
  }
}
