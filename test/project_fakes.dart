import 'package:localcut/media/media_engine.dart';
import 'package:localcut/projects/project.dart';
import 'package:localcut/projects/project_repository.dart';

class MemoryProjects implements ProjectRepository {
  final records = <String, LocalProject>{};
  bool failSave = false, missingSource = false;
  int writes = 0, _next = 0;
  @override
  Future<ProjectListing> list() async {
    final summaries = records.values.map((p) => p.summary).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return ProjectListing(summaries);
  }

  @override
  Future<LocalProject> create(SourceVideo source) async {
    final now = DateTime.now();
    final p = LocalProject(
      id: 'project-${_next++}',
      title: source.name ?? 'Recording',
      source: source,
      createdAt: now,
      updatedAt: now,
    );
    await save(p);
    return p;
  }

  @override
  Future<LocalProject> load(String id) async => records[id]!;
  @override
  Future<void> save(LocalProject project) async {
    if (failSave) throw StateError('Storage is full');
    records[project.id] = project;
    writes++;
  }

  @override
  Future<void> rename(String id, String title) async =>
      save(records[id]!.copyWith(title: title, updatedAt: DateTime.now()));
  @override
  Future<void> delete(String id) async {
    records.remove(id);
  }

  @override
  Future<bool> sourceExists(LocalProject project) async => !missingSource;
}
