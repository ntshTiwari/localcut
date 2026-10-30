import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localcut/core/edit_plan.dart';
import 'package:localcut/core/silence_detection.dart';
import 'package:localcut/media/media_engine.dart';
import 'package:localcut/widgets/silence_review.dart';

class FakeEngine implements MediaEngine {
  int analyses = 0;
  List<RenderSegment>? previewed;
  AudioAnalysis response = const AudioAnalysis([
    AudioWindow(0, 1000, -15),
    AudioWindow(1000, 3000, -70),
    AudioWindow(3000, 5000, -15),
  ], hasAudio: true);
  @override
  Future<AudioAnalysis> analyzeAudio(String path) async {
    analyses++;
    return response;
  }

  @override
  Future<void> preview(String path, List<RenderSegment> segments) async {
    previewed = segments;
  }

  @override
  Future<void> cancelAnalysis() async {}
  @override
  Future<void> cancelExport() async {}
  @override
  Future<String> export(String path, List<RenderSegment> segments) async =>
      'export.mp4';
  @override
  Future<SourceVideo?> importVideo() async =>
      const SourceVideo('source.mp4', 5000);
  @override
  Future<void> share(String path) async {}
}

void main() {
  testWidgets(
    'suggestions require selection and explicit addition; preview uses the chosen plan',
    (tester) async {
      final engine = FakeEngine();
      final edits = <EditRange>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SilenceReview(
                engine: engine,
                source: const SourceVideo('source.mp4', 5000),
                enabled: true,
                edits: edits,
                onApply: edits.addAll,
                onBusyChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Analyze audio'));
      await tester.pumpAndSettle();
      expect(engine.analyses, 1);
      expect(edits, isEmpty);
      expect(find.text('1.15 – 2.85 s'), findsOneWidget);
      await tester.ensureVisible(find.text('Select all'));
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Preview selected silence cuts'));
      await tester.tap(find.text('Preview selected silence cuts'));
      await tester.pumpAndSettle();
      expect(engine.previewed!.map((s) => [s.startMs, s.endMs]).toList(), [
        [0, 1150],
        [2850, 5000],
      ]);
      expect(edits, isEmpty);
      await tester.ensureVisible(find.text('Add selected cuts to edits'));
      await tester.tap(find.text('Add selected cuts to edits'));
      await tester.pumpAndSettle();
      expect(edits.single.startMs, 1150);
      expect(find.textContaining('No new pauses found'), findsOneWidget);
      expect(engine.analyses, 1);
    },
  );
  testWidgets('no-audio videos give a clear message and cannot add cuts', (
    tester,
  ) async {
    final engine = FakeEngine()
      ..response = const AudioAnalysis([], hasAudio: false);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SilenceReview(
              engine: engine,
              source: const SourceVideo('source.mp4', 5000),
              enabled: true,
              edits: const [],
              onApply: (_) => fail('No edits should be applied'),
              onBusyChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Analyze audio'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('This video has no audio track'),
      findsOneWidget,
    );
    expect(find.text('Add selected cuts to edits'), findsNothing);
  });
  testWidgets(
    'waveform reuses silence analysis and previews a mute with existing cuts',
    (tester) async {
      final engine = FakeEngine();
      final edits = <EditRange>[const EditRange(0, 500, EditKind.cut)];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SilenceReview(
                engine: engine,
                source: const SourceVideo('source.mp4', 5000),
                enabled: true,
                edits: edits,
                onApply: edits.addAll,
                onBusyChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Analyze audio'));
      await tester.pumpAndSettle();
      final graph = find.byKey(const Key('waveform-surface'));
      await tester.ensureVisible(graph);
      final rect = tester.getRect(graph);
      final gesture = await tester.startGesture(
        Offset(rect.left + rect.width * .2, rect.center.dy),
      );
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();
      await gesture.moveTo(Offset(rect.left + rect.width * .4, rect.center.dy));
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Mute selection'));
      await tester.tap(find.text('Mute selection'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Preview mute'));
      await tester.tap(find.text('Preview mute'));
      await tester.pumpAndSettle();
      expect(
        engine.previewed!.map((s) => [s.startMs, s.endMs, s.muted]).toList(),
        [
          [500, 1000, false],
          [1000, 2000, true],
          [2000, 5000, false],
        ],
      );
      expect(edits.length, 1);
      await tester.ensureVisible(find.text('Add mute'));
      await tester.tap(find.text('Add mute'));
      await tester.pumpAndSettle();
      expect(edits.last.kind, EditKind.mute);
      expect(engine.analyses, 1);
    },
  );
}
