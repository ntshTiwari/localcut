import 'project_fakes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localcut/core/edit_plan.dart';
import 'package:localcut/core/silence_detection.dart';
import 'package:localcut/main.dart';
import 'package:localcut/transcript/transcript.dart';
import 'silence_review_test.dart' show FakeEngine;
import 'transcript_panel_test.dart' show FakeSpeech;

class EditorMedia extends FakeEngine {
  List<RenderSegment>? exported;
  bool failAnalysis = false;
  @override
  Future<AudioAnalysis> analyzeAudio(String path) async {
    if (failAnalysis) throw StateError('Analysis unavailable');
    return super.analyzeAudio(path);
  }

  @override
  Future<String> export(String path, List<RenderSegment> segments) async {
    exported = segments;
    return 'export.mp4';
  }
}

Future<void> editor(WidgetTester tester, EditorMedia media) async {
  final speech = FakeSpeech()
    ..downloaded.add('english')
    ..result = const VideoTranscript(TranscriptLanguage.english, [
      TranscriptWord('Hello', 0, 1000),
      TranscriptWord('friend', 2800, 3300),
    ]);
  await tester.pumpWidget(
    LocalCutApp(
      engine: media,
      transcriptionEngine: speech,
      projects: MemoryProjects(),
    ),
  );
  await tap(tester, find.text('Import video from Files'));
  await tap(tester, find.text('Create transcript'));
  await tap(tester, find.text('Generate transcript'));
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      150,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
  // Wait for debounced project autosave after meaningful user actions.
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'confirmed pause and word actions feed one review and approved export',
    (tester) async {
      final media = EditorMedia();
      await editor(tester, media);
      expect(media.analyses, 1);
      expect(media.previewed, isNull);
      await tap(tester, find.text('Timing & pauses'));
      await tap(tester, find.text('Waveform editor'));
      expect(find.byKey(const Key('waveform-surface')), findsOneWidget);
      expect(media.analyses, 1);
      await tap(tester, find.byTooltip('Back to transcript'));
      await tap(tester, find.byKey(const ValueKey('transcript-gap-1')));
      expect(find.text('Shorten pause'), findsOneWidget);
      expect(find.textContaining('Remove 1.5s'), findsOneWidget);
      await tap(tester, find.text('Shorten pause'));
      expect(find.text('Pause 1.8s → 0.3s'), findsOneWidget);
      expect(find.text('Review 1 change'), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('transcript-word-0')));
      await tap(tester, find.text('Censor'));
      expect(find.text('Review 2 changes'), findsOneWidget);
      expect(media.exported, isNull);
      await tap(tester, find.byKey(const Key('review-changes')));
      expect(find.text('Review changes'), findsOneWidget);
      expect(find.textContaining('Shorten pause (1.8s'), findsOneWidget);
      expect(find.textContaining('Censor “Hello”'), findsOneWidget);
      await tap(tester, find.text('Play edited video'));
      expect(
        media.previewed!.map((s) => [s.startMs, s.endMs, s.muted]).toList(),
        [
          [0, 1000, true],
          [1000, 1150, false],
          [2650, 5000, false],
        ],
      );
      expect(media.exported, isNull);
      await tap(tester, find.text('Export video'));
      expect(media.exported, isNotNull);
      expect(find.text('Save or share'), findsOneWidget);
      await tap(tester, find.text('Back to review'));
      await tap(tester, find.byTooltip('Restore this change').first);
      expect(find.text('Save or share'), findsNothing);
      expect(find.textContaining('Video ready.'), findsNothing);
    },
  );
  testWidgets('edited items can be restored directly in the transcript', (
    tester,
  ) async {
    await editor(tester, EditorMedia());
    await tap(tester, find.byKey(const ValueKey('transcript-gap-1')));
    await tap(tester, find.text('Shorten pause'));
    await tap(tester, find.byKey(const ValueKey('transcript-gap-1')));
    expect(find.text('Shorten pause'), findsNothing);
    await tap(tester, find.text('Restore'));
    expect(find.text('Pause 1.8s'), findsOneWidget);
    expect(find.text('Review 0 changes'), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('transcript-word-0')));
    await tap(tester, find.text('Censor'));
    await tap(tester, find.byKey(const ValueKey('transcript-word-0')));
    expect(find.text('Restore'), findsOneWidget);
    await tap(tester, find.text('Restore'));
    expect(find.text('Review 0 changes'), findsOneWidget);
  });
  testWidgets(
    'unrecognized audio between words is a gap, not a trimmable pause',
    (tester) async {
      final media = EditorMedia()
        ..response = const AudioAnalysis([
          AudioWindow(0, 5000, -10),
        ], hasAudio: true);
      await editor(tester, media);
      await tap(tester, find.byKey(const ValueKey('transcript-gap-1')));
      expect(find.text('Gap · 1.8s'), findsOneWidget);
      expect(find.text('Shorten pause'), findsNothing);
      expect(find.textContaining('Silence is not confirmed'), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('preview-mode-Original')));
      expect(media.previewed, isNotNull);
      await tap(tester, find.byTooltip('Back to transcript'));
      expect(find.text('Review 0 changes'), findsOneWidget);
    },
  );
  testWidgets('pause verification failure keeps transcript censorship usable', (
    tester,
  ) async {
    final media = EditorMedia()..failAnalysis = true;
    await editor(tester, media);
    expect(
      find.textContaining('Pause checking is unavailable'),
      findsOneWidget,
    );
    await tap(tester, find.byKey(const ValueKey('transcript-word-0')));
    await tap(tester, find.text('Censor'));
    expect(find.text('Review 1 change'), findsOneWidget);
  });
  testWidgets('selection actions remain visible on a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await editor(tester, EditorMedia());
    await tap(tester, find.byKey(const ValueKey('transcript-gap-1')));
    final action = tester.getRect(find.text('Shorten pause'));
    expect(action.bottom, lessThan(812));
    expect(find.text('Edit selection'), findsOneWidget);
    await tap(tester, find.byTooltip('Back to transcript'));
    expect(find.byKey(const Key('review-changes')), findsOneWidget);
  });
}
