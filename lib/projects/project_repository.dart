import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:flutter/services.dart';
import '../core/silence_detection.dart';
import '../media/media_engine.dart';
import 'project.dart';

// Keep isolate closures outside the repository: capturing a repository method's
// context also captures its unsendable Future write queue.
Future<Map<String, dynamic>> _decodeJson(String text) =>
    Isolate.run(() => Map<String, dynamic>.from(jsonDecode(text) as Map));
Future<String> _encodeAnalysis(AudioAnalysis data) => Isolate.run(
  () => jsonEncode({
    'hasAudio': data.hasAudio,
    'windows': [
      for (final w in data.windows) [w.startMs, w.endMs, w.db],
    ],
  }),
);
Future<String> _encodeSnapshot(Map<String, dynamic> map, String rootPath) =>
    Isolate.run(() {
      LocalProject.fromMap(map, rootPath);
      return jsonEncode(map);
    });
Future<void> _validateSnapshot(Map<String, dynamic> map, String rootPath) =>
    Isolate.run(() {
      LocalProject.fromMap(map, rootPath);
    });

class ProjectListing {
  const ProjectListing(this.projects, {this.warnings = const []});
  final List<ProjectSummary> projects;
  final List<String> warnings;
}

abstract interface class ProjectRepository {
  Future<ProjectListing> list();
  Future<LocalProject> create(SourceVideo source);
  Future<LocalProject> load(String id);
  Future<void> save(LocalProject project);
  Future<void> rename(String id, String title);
  Future<void> delete(String id);
  Future<bool> sourceExists(LocalProject project);
}

/// App-support storage; source media is referenced by basename so container
/// relocation after an iOS update does not invalidate a saved project.
class FileProjectRepository implements ProjectRepository {
  FileProjectRepository({Future<Directory> Function()? root})
    : _rootProvider = root ?? _platformRoot;
  final Future<Directory> Function() _rootProvider;
  Future<Directory>? _rootFuture;
  Future<void> _tail = Future.value();
  final _analysisIdentity = <String, WeakReference<AudioAnalysis>>{};
  static Future<Directory> _platformRoot() async => Directory(
    (await const MethodChannel(
      'localcut/media',
    ).invokeMethod<String>('storageRoot'))!,
  );
  Future<Directory> get _root => _rootFuture ??= _rootProvider()
      .then((d) async {
        await d.create(recursive: true);
        return d;
      })
      .catchError((Object error, StackTrace stack) {
        _rootFuture = null;
        Error.throwWithStackTrace(error, stack);
      });
  Future<Directory> _folder(String id) async =>
      Directory('${(await _root).path}/projects/${safeId(id)}');
  Future<void> _write(Future<void> Function() action) {
    final work = _tail.then((_) => action());
    _tail = work.catchError((Object _) {});
    return work;
  }

  Future<Map<String, dynamic>> _json(File file) async {
    final text = await file.readAsString();
    return _decodeJson(text);
  }

  Future<void> _atomic(File file, String text) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<LocalProject> create(SourceVideo source) async {
    final root = await _root;
    if (File(source.path).parent.path != root.path ||
        !await File(source.path).exists()) {
      throw StateError('The imported video is unavailable. Import it again.');
    }
    final now = DateTime.now();
    final id =
        '${now.microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32).toRadixString(16)}';
    final name = source.name?.trim();
    final project = LocalProject(
      id: id,
      title: name == null || name.isEmpty ? fileName(source.path) : name,
      source: source,
      createdAt: now,
      updatedAt: now,
    );
    await save(project);
    return project;
  }

  @override
  Future<void> save(LocalProject project) => _write(() async {
    final root = await _root, folder = await _folder(project.id);
    await folder.create(recursive: true);
    if (File(project.source.path).parent.path != root.path) {
      throw StateError('Project media is outside app storage.');
    }
    final cache = File('${folder.path}/analysis.json');
    if (project.analysis case final analysis?) {
      if (!identical(_analysisIdentity[project.id]?.target, analysis) ||
          !await cache.exists()) {
        final text = await _encodeAnalysis(analysis);
        await _atomic(cache, text);
        _analysisIdentity[project.id] = WeakReference(analysis);
      }
    }
    final snapshot = project.toMap();
    final text = await _encodeSnapshot(snapshot, root.path);
    final current = File('${folder.path}/project.json');
    if (await current.exists()) {
      // Never replace a recoverable backup with a corrupt primary snapshot.
      try {
        final old = await _json(current);
        await _validateSnapshot(old, root.path);
        await _atomic(
          File('${current.path}.bak'),
          await current.readAsString(),
        );
      } on UnsupportedProjectVersion {
        rethrow;
      } on FormatException {
        /* Retain the earlier valid backup. */
      } on TypeError {
        /* Retain the earlier valid backup. */
      } on StateError {
        /* Retain the earlier valid backup. */
      } on ArgumentError {
        /* Retain the earlier valid backup. */
      }
    }
    await _atomic(current, text);
    await _atomic(
      File('${folder.path}/summary.json'),
      jsonEncode(project.summary.toMap()),
    );
  });
  @override
  Future<LocalProject> load(String id) async {
    await _tail;
    final root = await _root, folder = await _folder(id);
    Map<String, dynamic> map;
    bool recovered = false;
    try {
      map = await _json(File('${folder.path}/project.json'));
      LocalProject.fromMap(map, root.path);
      if (map['id'] != id) {
        throw const FormatException('Project identity mismatch.');
      }
    } on UnsupportedProjectVersion {
      rethrow;
    } catch (_) {
      map = await _json(File('${folder.path}/project.json.bak'));
      LocalProject.fromMap(map, root.path);
      recovered = true;
    }
    if (map['id'] != id) {
      throw const FormatException('Project identity mismatch.');
    }
    AudioAnalysis? analysis;
    if (map['hasAnalysis'] == true) {
      try {
        final data = await _json(File('${folder.path}/analysis.json'));
        final windows = [
          for (final w in data['windows'] as List)
            AudioWindow(
              (w[0] as num).toInt(),
              (w[1] as num).toInt(),
              (w[2] as num).toDouble(),
            ),
        ];
        var end = 0;
        for (final w in windows) {
          if (w.startMs < end ||
              w.endMs <= w.startMs ||
              w.endMs > (map['durationMs'] as num) ||
              !w.db.isFinite) {
            throw const FormatException('Invalid audio cache.');
          }
          end = w.endMs;
        }
        analysis = AudioAnalysis(windows, hasAudio: data['hasAudio'] as bool);
        _analysisIdentity[id] = WeakReference(analysis);
      } catch (_) {
        /* Optional cache can be rebuilt without losing edits/text. */
      }
    }
    final result = LocalProject.fromMap(
      map,
      root.path,
      analysis: analysis,
      recovered: recovered,
    );
    if (result.exportPath != null && !await File(result.exportPath!).exists()) {
      return result.copyWith(clearExport: true);
    }
    return result;
  }

  @override
  Future<ProjectListing> list() async {
    await _tail;
    final dir = Directory('${(await _root).path}/projects');
    if (!await dir.exists()) return const ProjectListing([]);
    final result = <ProjectSummary>[], warnings = <String>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! Directory ||
          !RegExp(r'^[a-z0-9-]+$').hasMatch(fileName(entity.path))) {
        continue;
      }
      final id = fileName(entity.path);
      try {
        ProjectSummary summary;
        try {
          summary = ProjectSummary.fromMap(
            await _json(File('${entity.path}/summary.json')),
          );
        } catch (_) {
          summary = (await load(id)).summary;
        }
        if (summary.id != id) {
          throw const FormatException('Project identity mismatch.');
        }
        result.add(summary);
      } catch (_) {
        warnings.add(
          'A saved project could not be read ($id). Its files have been kept.',
        );
      }
    }
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return ProjectListing(result, warnings: warnings);
  }

  @override
  Future<bool> sourceExists(LocalProject project) =>
      File(project.source.path).exists();
  @override
  Future<void> rename(String id, String title) async {
    title = title.trim();
    if (title.isEmpty || title.length > 120) {
      throw ArgumentError('Use a project name between 1 and 120 characters.');
    }
    final project = await load(id);
    await save(project.copyWith(title: title, updatedAt: DateTime.now()));
  }

  @override
  Future<void> delete(String id) async {
    await _tail;
    final project = await load(id);
    final root = await _root, folder = await _folder(id);
    await _write(() async {
      final trash = await folder.rename('${folder.parent.path}/.deleted-$id');
      await trash.delete(recursive: true);
      _analysisIdentity.remove(id);
    });
    final others = await list();
    // If another record is unreadable, conservatively retain shared media.
    if (others.warnings.isEmpty &&
        !others.projects.any(
          (p) => p.sourceFile == fileName(project.source.path),
        )) {
      final file = File(
        '${root.path}/${safeName(fileName(project.source.path))}',
      );
      if (await FileSystemEntity.type(file.path, followLinks: false) ==
          FileSystemEntityType.file) {
        await file.delete();
      }
    }
  }
}
