import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:localcut/media/media_engine.dart';
import 'package:localcut/projects/project.dart';
import 'package:localcut/projects/project_autosave.dart';
import 'project_fakes.dart';

class HeldSave extends MemoryProjects {
  Completer<void>? gate;
  @override
  Future<void> save(LocalProject project) async {
    if (gate != null) await gate!.future;
    await super.save(project);
  }
}

void main() {
  test(
    'debounce captures the latest change once rather than saving every action',
    () async {
      final repo = MemoryProjects();
      var p = await repo.create(const SourceVideo('source.mp4', 5000));
      final baseline = repo.writes;
      final saver = ProjectAutosave(
        repository: repo,
        capture: () => p,
        delay: const Duration(milliseconds: 10),
      );
      saver.schedule();
      p = p.copyWith(title: 'Newest');
      saver.schedule();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await saver.flush();
      expect(repo.writes, baseline + 1);
      expect(repo.records[p.id]!.title, 'Newest');
      expect(saver.state, SaveState.saved);
      saver.dispose();
    },
  );
  test(
    'writes are serialized and a newer snapshot wins over an in-flight save',
    () async {
      final repo = HeldSave();
      var p = await repo.create(const SourceVideo('source.mp4', 5000));
      final saver = ProjectAutosave(repository: repo, capture: () => p);
      repo.gate = Completer<void>();
      p = p.copyWith(title: 'First');
      saver.schedule();
      final first = saver.flush();
      p = p.copyWith(title: 'Second');
      saver.schedule();
      final second = saver.flush();
      repo.gate!.complete();
      await Future.wait([first, second]);
      expect(repo.records[p.id]!.title, 'Second');
      expect(saver.state, SaveState.saved);
      saver.dispose();
    },
  );
  test(
    'failure preserves the last save and retry writes the latest state',
    () async {
      final repo = MemoryProjects();
      var p = await repo.create(const SourceVideo('source.mp4', 5000));
      final saver = ProjectAutosave(repository: repo, capture: () => p);
      repo.failSave = true;
      p = p.copyWith(title: 'Unsaved work');
      saver.schedule();
      await expectLater(saver.flush(), throwsStateError);
      expect(saver.state, SaveState.failed);
      expect(repo.records[p.id]!.title, 'Recording');
      repo.failSave = false;
      await saver.flush();
      expect(repo.records[p.id]!.title, 'Unsaved work');
      expect(saver.state, SaveState.saved);
      saver.dispose();
    },
  );
}
