import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../projects/project.dart';
import '../projects/project_repository.dart';
import '../media/media_engine.dart';
import '../transcript/transcription_engine.dart';
import 'editor_screen.dart';
import 'source_video_player.dart' show videoClock;

enum ProjectSort { saved, created, name, duration }

enum ProjectFilter { all, changed, untouched }

class ProjectLibraryScreen extends StatefulWidget {
  const ProjectLibraryScreen({
    super.key,
    required this.projects,
    required this.media,
    required this.speech,
  });
  final ProjectRepository projects;
  final MediaEngine media;
  final TranscriptionEngine speech;
  @override
  State<ProjectLibraryScreen> createState() => _ProjectLibraryScreenState();
}

class _ProjectLibraryScreenState extends State<ProjectLibraryScreen> {
  bool _importing = false, _loading = true;
  String? _error;
  ProjectListing _listing = const ProjectListing([]);
  final _search = TextEditingController();
  final _scroll = ScrollController();
  ProjectSort _sort = ProjectSort.saved;
  ProjectFilter _filter = ProjectFilter.all;
  @override
  void initState() {
    super.initState();
    _search.addListener(_searchChanged);
    _reload();
  }

  void _searchChanged() {
    setState(() {});
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<ProjectSummary> get _visible {
    final query = _search.text.trim().toLowerCase();
    final result = _listing.projects
        .where(
          (p) =>
              p.title.toLowerCase().contains(query) &&
              switch (_filter) {
                ProjectFilter.all => true,
                ProjectFilter.changed => p.editCount > 0,
                ProjectFilter.untouched => p.editCount == 0,
              },
        )
        .toList();
    result.sort((a, b) {
      final comparison = switch (_sort) {
        ProjectSort.saved => b.updatedAt.compareTo(a.updatedAt),
        ProjectSort.created => b.createdAt.compareTo(a.createdAt),
        ProjectSort.name => a.title.toLowerCase().compareTo(
          b.title.toLowerCase(),
        ),
        ProjectSort.duration => b.durationMs.compareTo(a.durationMs),
      };
      return comparison != 0 ? comparison : a.id.compareTo(b.id);
    });
    return result;
  }

  String _message(Object error) => error is FileSystemException
      ? 'Could not read or save this project. Check available storage and try again.'
      : error is StateError
      ? error.message.toString()
      : error is FormatException
      ? error.message
      : error is ArgumentError
      ? error.message.toString()
      : error is MissingPluginException
      ? 'Local storage is unavailable. Fully restart or rebuild the iPhone app.'
      : error is PlatformException
      ? error.message ?? 'Project operation failed.'
      : error.toString();
  Future<void> _reload() async {
    try {
      final listing = await widget.projects.list();
      if (mounted) {
        setState(() {
          _listing = listing;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _message(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _show(LocalProject project) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditorScreen(
          initialSource: project.source,
          initialProject: project,
          projects: widget.projects,
          engine: widget.media,
          transcriptionEngine: widget.speech,
        ),
      ),
    );
    await _reload();
  }

  Future<void> _open(ProjectSummary summary) async {
    if (_importing) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final project = await widget.projects.load(summary.id);
      if (!await widget.projects.sourceExists(project)) {
        throw StateError(
          'The imported video is missing. Your saved edits are kept. Reimport the recording as a new project to continue.',
        );
      }
      await _show(project);
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _rename(ProjectSummary summary) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => _RenameProjectDialog(title: summary.title),
    );
    if (title == null || !mounted) return;
    setState(() => _importing = true);
    try {
      await widget.projects.rename(summary.id, title);
      await _reload();
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _delete(ProjectSummary summary) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete “${summary.title}”?'),
        content: const Text(
          'This removes the project and its imported copy from LocalCut. Your original recording and exported videos stay untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete project'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() => _importing = true);
    try {
      await widget.projects.delete(summary.id);
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      await _reload();
      if (mounted) setState(() => _importing = false);
    }
  }

  Widget _notices(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_loading) const LinearProgressIndicator(),
      if (_error != null) ...[
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        TextButton(
          onPressed: () {
            setState(() => _error = null);
            _reload();
          },
          child: const Text('Retry loading projects'),
        ),
      ],
      if (_listing.warnings.isNotEmpty)
        Text(
          'Some saved projects could not be read. Their files have been kept.',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ],
  );
  String _savedAt(DateTime date) {
    final local = date.toLocal();
    return '${local.day}/${local.month}/${local.year} · ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible;
    return Scaffold(
      appBar: AppBar(title: const Text('Recent projects')),
      body: SafeArea(
        child: Scrollbar(
          controller: _scroll,
          thumbVisibility: true,
          child: CustomScrollView(
            controller: _scroll,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Pick up where you left off. Everything is saved on this device.',
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        key: const Key('project-search'),
                        controller: _search,
                        enabled: !_importing,
                        decoration: InputDecoration(
                          labelText: 'Search project names',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _search.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear project search',
                                  onPressed: _search.clear,
                                  icon: const Icon(Icons.close),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<ProjectSort>(
                              key: const Key('project-sort'),
                              initialValue: _sort,
                              selectedItemBuilder: (context) => [
                                for (final sort in ProjectSort.values)
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      switch (sort) {
                                        ProjectSort.saved => 'Last saved',
                                        ProjectSort.created => 'Newest',
                                        ProjectSort.name => 'Name A–Z',
                                        ProjectSort.duration => 'Longest',
                                      },
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Sort by',
                              ),
                              items: [
                                for (final sort in ProjectSort.values)
                                  DropdownMenuItem(
                                    value: sort,
                                    child: Text(
                                      switch (sort) {
                                        ProjectSort.saved => 'Recently saved',
                                        ProjectSort.created => 'Newest created',
                                        ProjectSort.name => 'Name A–Z',
                                        ProjectSort.duration => 'Longest video',
                                      },
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: _importing
                                  ? null
                                  : (v) => setState(() {
                                      _sort = v!;
                                      if (_scroll.hasClients) _scroll.jumpTo(0);
                                    }),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<ProjectFilter>(
                              key: const Key('project-filter'),
                              initialValue: _filter,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Show',
                              ),
                              items: [
                                for (final filter in ProjectFilter.values)
                                  DropdownMenuItem(
                                    value: filter,
                                    child: Text(
                                      switch (filter) {
                                        ProjectFilter.all => 'All projects',
                                        ProjectFilter.changed => 'With changes',
                                        ProjectFilter.untouched => 'No changes',
                                      },
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: _importing
                                  ? null
                                  : (v) => setState(() {
                                      _filter = v!;
                                      if (_scroll.hasClients) _scroll.jumpTo(0);
                                    }),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${rows.length} of ${_listing.projects.length} projects',
                      ),
                      if (_importing) const LinearProgressIndicator(),
                      _notices(context),
                    ],
                  ),
                ),
              ),
              if (rows.isEmpty && !_loading)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.video_library_outlined, size: 42),
                        const SizedBox(height: 12),
                        Text(
                          _listing.projects.isEmpty
                              ? 'No saved projects yet'
                              : 'No matching projects',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _listing.projects.isEmpty
                              ? 'Import a video from Home to create your first project.'
                              : 'Try another name or change the filter.',
                          textAlign: TextAlign.center,
                        ),
                        TextButton(
                          onPressed: _listing.projects.isEmpty
                              ? () => Navigator.pop(context)
                              : () {
                                  _search.clear();
                                  setState(() => _filter = ProjectFilter.all);
                                },
                          child: Text(
                            _listing.projects.isEmpty
                                ? 'Back to Home'
                                : 'Clear search and filters',
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final project = rows[index];
                      return Card(
                        child: ListTile(
                          key: ValueKey('project-${project.id}'),
                          enabled: !_importing,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          leading: const Icon(Icons.movie_outlined),
                          title: Text(
                            project.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${videoClock(Duration(milliseconds: project.durationMs))} · ${project.editCount} changes\nSaved ${_savedAt(project.updatedAt)}',
                          ),
                          onTap: () => _open(project),
                          trailing: PopupMenuButton<String>(
                            enabled: !_importing,
                            tooltip: 'Project options for ${project.title}',
                            onSelected: (value) => value == 'rename'
                                ? _rename(project)
                                : _delete(project),
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'rename',
                                child: Text('Rename project'),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete project'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }, childCount: rows.length),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RenameProjectDialog extends StatefulWidget {
  const _RenameProjectDialog({required this.title});
  final String title;
  @override
  State<_RenameProjectDialog> createState() => _RenameProjectDialogState();
}

class _RenameProjectDialogState extends State<_RenameProjectDialog> {
  late final _controller = TextEditingController(text: widget.title);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename project'),
    content: TextField(
      key: const Key('project-name'),
      controller: _controller,
      autofocus: true,
      maxLength: 120,
      decoration: const InputDecoration(labelText: 'Project name'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      ValueListenableBuilder(
        valueListenable: _controller,
        builder: (context, value, _) => FilledButton(
          onPressed: value.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, value.text.trim()),
          child: const Text('Save name'),
        ),
      ),
    ],
  );
}
