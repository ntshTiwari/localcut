import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:localcut/core/edit_plan.dart';
import 'package:localcut/core/pause_review.dart';
import 'package:localcut/core/silence_detection.dart';
import 'package:localcut/media/media_engine.dart';
import 'package:localcut/projects/project.dart';
import 'package:localcut/projects/project_repository.dart';
import 'package:localcut/transcript/transcript.dart';

void main() {
  late Directory home, root;
  late File video;
  late FileProjectRepository repo;
  setUp(() async {
    home = await Directory.systemTemp.createTemp('localcut-project-tests-');
    root = await Directory('${home.path}/container-a').create();
    video = await File(
      '${root.path}/imported.mp4',
    ).writeAsString('immutable-source-fixture');
    repo = FileProjectRepository(root: () async => root);
  });
  tearDown(() async {
    if (await home.exists()) await home.delete(recursive: true);
  });
  Future<LocalProject> create() => repo.create(
    SourceVideo(video.path, 5000, name: 'Episode.mp4', hasAudio: true),
  );
  File snapshot(LocalProject p) =>
      File('${root.path}/projects/${p.id}/project.json');
  test(
    'round trip restores edits, languages, audio, decisions, positions and export reference',
    () async {
      final initial = await create();
      final session = PauseReviewSession()
        ..sync([const EditRange(1000, 2000, EditKind.cut)]);
      session.settings = const SilenceSettings(
        thresholdDb: -45,
        minimumPauseMs: 1000,
        paddingMs: 100,
      );
      session.decide(session.pauses.first, PauseDecision.keep);
      session.lastVisitedId = pauseId(session.pauses.first);
      final output = await File(
        '${root.path}/LocalCut-output.mp4',
      ).writeAsString('export-fixture');
      final project = initial.copyWith(
        edits: [
          const EditRange(1000, 2000, EditKind.cut),
          const EditRange(3000, 3500, EditKind.mute, label: 'Censor test'),
        ],
        language: TranscriptLanguage.hindiEnglish,
        transcripts: {
          TranscriptLanguage.english: const VideoTranscript(
            TranscriptLanguage.english,
            [TranscriptWord('Hello', 0, 500)],
          ),
          TranscriptLanguage.hindiEnglish: const VideoTranscript(
            TranscriptLanguage.hindiEnglish,
            [
              TranscriptWord('Namaste', 0, 500),
              TranscriptWord('friend', null, null),
            ],
          ),
        },
        analysis: const AudioAnalysis([
          AudioWindow(0, 5000, -20),
        ], hasAudio: true),
        pauseReview: session.toMap(),
        scrollOffset: 123.5,
        playbackMs: 1700,
        exportPath: output.path,
      );
      await repo.save(project);
      final reopened = await FileProjectRepository(
        root: () async => root,
      ).load(project.id);
      expect(reopened.edits.map((e) => [e.startMs, e.endMs, e.kind]), [
        [1000, 2000, EditKind.cut],
        [3000, 3500, EditKind.mute],
      ]);
      expect(reopened.transcripts.length, 2);
      expect(reopened.language, TranscriptLanguage.hindiEnglish);
      expect(
        reopened
            .transcripts[TranscriptLanguage.hindiEnglish]!
            .words
            .last
            .aligned,
        isFalse,
      );
      expect(reopened.analysis!.windows.single.db, -20);
      expect(reopened.scrollOffset, 123.5);
      expect(reopened.playbackMs, 1700);
      final restored = PauseReviewSession.fromMap(reopened.pauseReview, 5000);
      expect(restored.decision(restored.pauses.first), PauseDecision.keep);
      expect(restored.settings.thresholdDb, -45);
      expect(restored.lastVisitedId, '1000:2000');
      expect(reopened.exportPath, output.path);
      expect(await video.readAsString(), 'immutable-source-fixture');
      expect(
        (await snapshot(project).readAsString()).contains(root.path),
        isFalse,
      );
    },
  );
  test('unchanged audio cache is not rewritten on every edit save', () async {
    final p = (await create()).copyWith(
      analysis: const AudioAnalysis([
        AudioWindow(0, 5000, -20),
      ], hasAudio: true),
    );
    await repo.save(p);
    final cache = File('${root.path}/projects/${p.id}/analysis.json');
    final stamp = DateTime.utc(2000);
    await cache.setLastModified(stamp);
    await repo.save(
      p.copyWith(edits: [const EditRange(1000, 2000, EditKind.cut)]),
    );
    expect((await cache.lastModified()).toUtc(), stamp);
  });
  test(
    'corrupt primary recovers backup and later saves do not overwrite it with corrupt data',
    () async {
      final p = await create();
      await repo.save(
        p.copyWith(edits: [const EditRange(1000, 2000, EditKind.cut)]),
      );
      await snapshot(p).writeAsString('{broken');
      final recovered = await repo.load(p.id);
      expect(recovered.recovered, isTrue);
      expect(recovered.edits, isEmpty);
      await repo.save(recovered.copyWith(title: 'Recovered title'));
      expect((await repo.load(p.id)).title, 'Recovered title');
      final backup =
          jsonDecode(await File('${snapshot(p).path}.bak').readAsString())
              as Map;
      expect(backup['title'], 'Episode.mp4');
    },
  );
  test(
    'optional cache loss preserves transcript and edits; missing exports are invalidated',
    () async {
      final p = (await create()).copyWith(
        analysis: const AudioAnalysis([
          AudioWindow(0, 5000, -20),
        ], hasAudio: true),
        transcripts: {
          TranscriptLanguage.english: const VideoTranscript(
            TranscriptLanguage.english,
            [TranscriptWord('Hello', 0, 500)],
          ),
        },
        edits: [const EditRange(1000, 2000, EditKind.cut)],
        exportPath: '${root.path}/missing-export.mp4',
      );
      await repo.save(p);
      await File(
        '${root.path}/projects/${p.id}/analysis.json',
      ).writeAsString('corrupt cache');
      final reopened = await repo.load(p.id);
      expect(reopened.analysis, isNull);
      expect(reopened.edits.length, 1);
      expect(reopened.transcripts.length, 1);
      expect(reopened.exportPath, isNull);
    },
  );
  test(
    'summary listing does not decode every large snapshot and surfaces unreadable folders',
    () async {
      final p = await create();
      await snapshot(p).writeAsString('broken');
      final listing = await repo.list();
      expect(listing.projects.single.id, p.id);
      await File('${root.path}/projects/${p.id}/summary.json').delete();
      final other = await create();
      final partial = await repo.list();
      expect(partial.projects.single.id, other.id);
      expect(partial.warnings, isNotEmpty);
    },
  );
  test(
    'newer schemas are refused without falling back or overwriting their files',
    () async {
      final p = await create();
      await repo.save(p);
      final map =
          jsonDecode(await snapshot(p).readAsString()) as Map<String, dynamic>;
      map['version'] = 99;
      await snapshot(p).writeAsString(jsonEncode(map));
      await expectLater(
        repo.load(p.id),
        throwsA(isA<UnsupportedProjectVersion>()),
      );
      await expectLater(
        repo.save(p),
        throwsA(isA<UnsupportedProjectVersion>()),
      );
      expect(
        (jsonDecode(await snapshot(p).readAsString()) as Map)['version'],
        99,
      );
    },
  );
  test('relative source references survive app-container relocation', () async {
    final p = await create();
    final moved = await root.rename('${home.path}/container-b');
    final restored = await FileProjectRepository(
      root: () async => moved,
    ).load(p.id);
    expect(restored.source.path, '${moved.path}/imported.mp4');
    expect(await File(restored.source.path).exists(), isTrue);
  });
  test(
    'deleting projects respects shared imports and keeps originals and exports',
    () async {
      final original = await File(
        '${home.path}/original.mp4',
      ).writeAsString('original');
      final output = await File(
        '${root.path}/export.mp4',
      ).writeAsString('export');
      final a = await create(), b = await create();
      await repo.delete(a.id);
      expect(await video.exists(), isTrue);
      await repo.delete(b.id);
      expect(await video.exists(), isFalse);
      expect(await original.exists(), isTrue);
      expect(await output.exists(), isTrue);
    },
  );
  test('invalid filenames and IDs cannot escape app storage', () async {
    final p = await create();
    final map = p.toMap()..['sourceFile'] = '../original.mp4';
    expect(() => LocalProject.fromMap(map, root.path), throwsFormatException);
    await expectLater(repo.load('../outside'), throwsFormatException);
    final external = await File(
      '${home.path}/external.mp4',
    ).writeAsString('outside');
    await expectLater(
      repo.create(SourceVideo(external.path, 5000)),
      throwsStateError,
    );
  });
  test(
    'a failed serialization leaves the previous snapshot intact and the queue recovers',
    () async {
      final p = await create();
      final before = await snapshot(p).readAsString();
      await expectLater(
        repo.save(p.copyWith(pauseReview: {'bad': double.nan})),
        throwsA(anything),
      );
      expect(await snapshot(p).readAsString(), before);
      await repo.save(p.copyWith(title: 'Next successful save'));
      expect((await repo.load(p.id)).title, 'Next successful save');
    },
  );
  test('a temporary storage-root failure can be retried', () async {
    var attempts = 0;
    final retrying = FileProjectRepository(
      root: () async {
        if (attempts++ == 0) throw StateError('temporarily unavailable');
        return root;
      },
    );
    await expectLater(retrying.list(), throwsStateError);
    expect((await retrying.list()).projects, isEmpty);
  });
  test(
    'large transcript and audio-cache metadata round-trip without copying media',
    () async {
      final p = await repo.create(
        SourceVideo(video.path, 1800000, name: 'Long recording'),
      );
      final long = p.copyWith(
        transcripts: {
          TranscriptLanguage.english: VideoTranscript(
            TranscriptLanguage.english,
            List.generate(
              5000,
              (i) => TranscriptWord('word$i', i * 300, i * 300 + 250),
            ),
          ),
        },
        analysis: AudioAnalysis(
          List.generate(90000, (i) => AudioWindow(i * 20, (i + 1) * 20, -20)),
          hasAudio: true,
        ),
      );
      await repo.save(long);
      final loaded = await FileProjectRepository(
        root: () async => root,
      ).load(p.id);
      expect(
        loaded.transcripts[TranscriptLanguage.english]!.words.length,
        5000,
      );
      expect(loaded.analysis!.windows.length, 90000);
      expect(await video.readAsString(), 'immutable-source-fixture');
    },
  );
}
