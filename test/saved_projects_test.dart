import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localcut/main.dart';
import 'package:localcut/core/pause_review.dart';
import 'package:localcut/editor/source_video_player.dart';
import 'package:localcut/media/media_engine.dart';
import 'package:localcut/transcript/transcript.dart';
import 'project_fakes.dart';
import 'transcript_panel_test.dart' show FakeSpeech, language;
import 'transcript_editor_flow_test.dart' show tap, EditorMedia;

Future<void> mount(
  WidgetTester tester,
  MemoryProjects repo,
  EditorMedia media,
  FakeSpeech speech,
) async {
  await tester.pumpWidget(
    LocalCutApp(engine: media, transcriptionEngine: speech, projects: repo),
  );
  await tester.pumpAndSettle();
}

Future<void> createTranscript(WidgetTester tester) async {
  await tap(tester, find.text('Import video from Files'));
  await tap(tester, find.text('Create transcript'));
  await tap(tester, find.text('Generate transcript'));
}

void main() {
  testWidgets(
    'a fresh app restores multilingual transcripts, edits and pause decisions without inference',
    (tester) async {
      final repo = MemoryProjects(),
          media = EditorMedia(),
          speech = FakeSpeech()..downloaded.addAll(['english', 'multilingual']);
      await mount(tester, repo, media, speech);
      await createTranscript(tester);
      await tap(tester, find.byKey(const ValueKey('transcript-word-0')));
      await tap(tester, find.text('Censor'));
      await tap(tester, find.text('Language & downloads'));
      await language(tester, 'Hindi–English');
      await tap(tester, find.text('Generate transcript'));
      await tap(tester, find.text('Timing & pauses'));
      await tap(tester, find.text('Review suggested pauses'));
      await tap(tester, find.text('Review next pause'));
      await tap(tester, find.text('Keep pause'));
      await tap(tester, find.text('Back to overview'));
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tap(tester, find.byTooltip('Back to transcript'));
      await tap(tester, find.byTooltip('Back to home'));
      final saved = repo.records.values.single;
      expect(saved.edits.length, 1);
      expect(saved.transcripts.length, 2);
      expect(saved.language, TranscriptLanguage.hindiEnglish);
      final review = PauseReviewSession.fromMap(saved.pauseReview, 5000);
      expect(review.reviewed, 1);
      expect(review.decision(review.pauses.first), PauseDecision.keep);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      final newSpeech = FakeSpeech(), newMedia = EditorMedia();
      await mount(tester, repo, newMedia, newSpeech);
      expect(find.text('Recent projects'), findsOneWidget);
      await tap(tester, find.text('Recent projects'));
      await tap(tester, find.byKey(ValueKey('project-${saved.id}')));
      expect(find.byKey(const ValueKey('transcript-word-0')), findsOneWidget);
      expect(find.text('Review 1 change'), findsOneWidget);
      expect(find.text('Create transcript'), findsNothing);
      expect(newSpeech.transcriptions, isEmpty);
      expect(newSpeech.downloads, isEmpty);
      expect(newMedia.analyses, 0);
      await tap(tester, find.text('Timing & pauses'));
      await tap(tester, find.text('Review suggested pauses'));
      expect(
        find.text('1 of 1 reviewed · decisions are not applied yet'),
        findsOneWidget,
      );
    },
  );
  testWidgets('rename and confirmed delete update Recent projects', (
    tester,
  ) async {
    final repo = MemoryProjects();
    final project = await repo.create(const SourceVideo('source.mp4', 5000));
    await mount(tester, repo, EditorMedia(), FakeSpeech());
    await tap(tester, find.text('Recent projects'));
    await tap(tester, find.byTooltip('Project options for Recording'));
    await tap(tester, find.text('Rename project'));
    await tester.enterText(
      find.byKey(const Key('project-name')),
      'Episode one',
    );
    await tap(tester, find.text('Save name'));
    expect(repo.records[project.id]!.title, 'Episode one');
    expect(find.text('Episode one'), findsOneWidget);
    await tap(tester, find.byTooltip('Project options for Episode one'));
    await tap(tester, find.text('Delete project'));
    await tap(tester, find.text('Cancel'));
    expect(repo.records.length, 1);
    await tap(tester, find.byTooltip('Project options for Episode one'));
    await tap(tester, find.text('Delete project'));
    await tap(tester, find.text('Delete project'));
    expect(repo.records, isEmpty);
    expect(find.text('No saved projects yet'), findsOneWidget);
    await tap(tester, find.text('Back to Home'));
    expect(find.text('Import video from Files'), findsOneWidget);
  });
  testWidgets(
    'missing media leaves the saved record intact and explains the problem',
    (tester) async {
      final repo = MemoryProjects()..missingSource = true;
      await repo.create(const SourceVideo('source.mp4', 5000));
      await mount(tester, repo, EditorMedia(), FakeSpeech());
      await tap(tester, find.text('Recent projects'));
      await tap(tester, find.text('Recording'));
      expect(find.textContaining('imported video is missing'), findsOneWidget);
      expect(repo.records.length, 1);
    },
  );
  testWidgets(
    'failed autosave keeps editing open and retries the latest work',
    (tester) async {
      final repo = MemoryProjects();
      await mount(
        tester,
        repo,
        EditorMedia(),
        FakeSpeech()..downloaded.add('english'),
      );
      await createTranscript(tester);
      repo.failSave = true;
      await tap(tester, find.byKey(const ValueKey('transcript-word-0')));
      await tap(tester, find.text('Censor'));
      expect(find.text('Could not autosave'), findsOneWidget);
      expect(repo.records.values.single.edits, isEmpty);
      await tap(tester, find.byTooltip('Back to home'));
      expect(find.text('Review 1 change'), findsOneWidget);
      expect(find.text('Recent projects'), findsNothing);
      repo.failSave = false;
      await tap(tester, find.text('Retry save'));
      expect(find.text('Saved on this device'), findsOneWidget);
      expect(repo.records.values.single.edits.length, 1);
      await tap(tester, find.byTooltip('Back to home'));
      expect(find.text('Recent projects'), findsOneWidget);
    },
  );
  testWidgets('reopened source uses its saved playback position', (
    tester,
  ) async {
    final repo = MemoryProjects();
    final p = await repo.create(const SourceVideo('source.mp4', 5000));
    await repo.save(p.copyWith(playbackMs: 2300));
    await mount(tester, repo, EditorMedia(), FakeSpeech());
    await tap(tester, find.text('Recent projects'));
    await tap(tester, find.text('Recording'));
    expect(
      tester
          .widget<SourceVideoPlayer>(find.byType(SourceVideoPlayer))
          .initialPositionMs,
      2300,
    );
  });
  testWidgets(
    'autosave errors are visible while reviewing pauses, not only in the editor',
    (tester) async {
      final repo = MemoryProjects();
      await mount(
        tester,
        repo,
        EditorMedia(),
        FakeSpeech()..downloaded.add('english'),
      );
      await createTranscript(tester);
      await tap(tester, find.text('Timing & pauses'));
      await tap(tester, find.text('Review suggested pauses'));
      await tap(tester, find.text('Review next pause'));
      repo.failSave = true;
      await tap(tester, find.text('Keep pause'));
      expect(find.text('All pauses reviewed'), findsOneWidget);
      expect(
        find.text('Autosave failed. Retry before closing the project.'),
        findsOneWidget,
      );
      repo.failSave = false;
      await tap(tester, find.text('Retry autosave'));
      final restored = PauseReviewSession.fromMap(
        repo.records.values.single.pauseReview,
        5000,
      );
      expect(restored.reviewed, 1);
    },
  );
}
