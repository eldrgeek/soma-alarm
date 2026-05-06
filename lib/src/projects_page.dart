import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'projects.dart';

class ProjectsPage extends StatefulWidget {
  const ProjectsPage({super.key, ProjectsRepo? repo})
      : _injectedRepo = repo;

  final ProjectsRepo? _injectedRepo;

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage>
    with SingleTickerProviderStateMixin {
  late final ProjectsRepo _repo;
  late final TabController _tabs;
  ProjectSort _sort = ProjectSort.mostRecent;
  List<Project> _recent = [];
  List<Project> _all = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _repo = widget._injectedRepo ?? ProjectsRepo();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final recent = await _repo.list(recentOnly: true, sort: _sort);
    final all = await _repo.list(recentOnly: false, sort: _sort);
    if (!mounted) return;
    setState(() {
      _recent = recent;
      _all = all;
      _loaded = true;
    });
  }

  void _toggleSort() {
    setState(() {
      _sort = _sort == ProjectSort.mostRecent
          ? ProjectSort.alphabetical
          : ProjectSort.mostRecent;
    });
    _load();
  }

  Future<void> _addProject() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New project'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Project name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await _repo.create(name);
    await _load();
  }

  Future<void> _showProjectActions(Project pr) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(pr.name,
                  style: Theme.of(ctx).textTheme.titleMedium),
              subtitle: Text(
                'Last opened ${DateFormat('MMM d, h:mm a').format(pr.lastAccessedAt.toLocal())}',
              ),
            ),
            const Divider(height: 1),
            if (pr.pinnedToRecent)
              ListTile(
                leading: const Icon(Icons.bookmark_remove_outlined),
                title: const Text('Remove from Recent'),
                onTap: () => Navigator.pop(ctx, 'remove'),
              )
            else
              ListTile(
                leading: const Icon(Icons.bookmark_add_outlined),
                title: const Text('Pin to Recent'),
                onTap: () => Navigator.pop(ctx, 'pin'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline,
                  color: Colors.redAccent),
              title: const Text('Delete project',
                  style: TextStyle(color: Colors.redAccent)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null) return;
    switch (action) {
      case 'pin':
        await _repo.pinToRecent(pr.id);
        break;
      case 'remove':
        await _repo.removeFromRecent(pr.id);
        break;
      case 'delete':
        if (!mounted) return;
        final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text('Delete "${pr.name}"?'),
                content: const Text('This cannot be undone.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.redAccent),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete')),
                ],
              ),
            ) ??
            false;
        if (ok) await _repo.delete(pr.id);
        break;
    }
    await _load();
  }

  Future<void> _openProject(Project pr) async {
    await _repo.touch(pr.id);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProjectDetailPage(project: pr)),
    );
    await _load();
  }

  Widget _buildList(List<Project> items, {required bool isRecentTab}) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            isRecentTab
                ? 'No recent projects.\nTap + to create one, or pin one from All.'
                : 'No projects yet.\nTap + to create your first.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.6),
                ),
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (_, i) {
        final pr = items[i];
        return ListTile(
          leading: Icon(
            pr.pinnedToRecent ? Icons.bookmark : Icons.folder_outlined,
            color: pr.pinnedToRecent
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
          title: Text(pr.name),
          subtitle: Text(
            DateFormat('MMM d, h:mm a').format(pr.lastAccessedAt.toLocal()),
          ),
          onTap: () => _openProject(pr),
          onLongPress: () => _showProjectActions(pr),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final sortIcon = _sort == ProjectSort.mostRecent
        ? Icons.schedule
        : Icons.sort_by_alpha;
    final sortLabel = _sort == ProjectSort.mostRecent
        ? 'Sort: most recent'
        : 'Sort: A–Z';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Projects'),
        actions: [
          IconButton(
            icon: Icon(sortIcon),
            tooltip: sortLabel,
            onPressed: _toggleSort,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Recent'),
            Tab(text: 'All'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildList(_recent, isRecentTab: true),
          _buildList(_all, isRecentTab: false),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addProject,
        tooltip: 'New project',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class ProjectDetailPage extends StatelessWidget {
  const ProjectDetailPage({super.key, required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('EEE MMM d, h:mm a');
    return Scaffold(
      appBar: AppBar(title: Text(project.name)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Last accessed', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(fmt.format(project.lastAccessedAt.toLocal()),
                style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 16),
            Text('Created', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(fmt.format(project.createdAt.toLocal()),
                style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 32),
            const Center(
              child: Text('Project detail — coming soon.',
                  style: TextStyle(fontStyle: FontStyle.italic)),
            ),
          ],
        ),
      ),
    );
  }
}
