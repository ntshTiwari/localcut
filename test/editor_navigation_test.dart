import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localcut/core/edit_plan.dart';
import 'package:localcut/core/silence_detection.dart';
import 'package:localcut/editor/inline_preview.dart';
import 'package:localcut/editor/timing_screen.dart';
import 'package:localcut/media/media_engine.dart';
import 'transcript_editor_flow_test.dart' show editor, tap, EditorMedia;
import 'silence_review_test.dart' show FakeEngine;

class FailedPreview extends EditorMedia {
  @override
  Future<void> preview(
    String path,
    List<RenderSegment> segments, {
    String? label,
  }) async {
    throw StateError('Preview unavailable for this recording');
  }
}

void expectOnePageScroll(WidgetTester tester) {
  final lists = tester.widgetList<ListView>(find.byType(ListView));
  expect(
    lists.where((list) => list.physics is! NeverScrollableScrollPhysics).length,
    1,
  );
}

void main() {
  testWidgets(
    'timing card opens a full page and keeps the transcript on return',
    (tester) async {
      final media = EditorMedia();
      await editor(tester, media);
      expectOnePageScroll(tester);
      final tile = find.ancestor(
        of: find.text('Timing & pauses'),
        matching: find.byType(ListTile),
      );
      expect(tester.widget<ListTile>(tile).onTap, isNotNull);
      await tap(tester, find.text('Timing & pauses'));
      expect(find.byType(TimingScreen), findsOneWidget);
      expect(find.text('Choose a preview below'), findsOneWidget);
      expectOnePageScroll(tester);
      await tap(tester, find.byTooltip('Back to transcript'));
      expect(find.byKey(const ValueKey('transcript-word-0')), findsOneWidget);
      expect(media.analyses, 1);
    },
  );

  testWidgets(
    'selection page has a stable player slot and the same word reopens',
    (tester) async {
      await editor(tester, EditorMedia());
      final word = find.byKey(const ValueKey('transcript-word-0'));
      await tap(tester, word);
      expect(find.text('Edit selection'), findsOneWidget);
      expectOnePageScroll(tester);
      final before = tester.getRect(find.byType(InlinePreviewPane));
      await tap(tester, find.byTooltip('Play original 0:00.000 – 0:01.000'));
      expect(tester.getSize(find.byType(InlinePreviewPane)), before.size);
      await tap(tester, find.byTooltip('Back to transcript'));
      expect(find.text('Edit selected section'), findsOneWidget);
      await tap(tester, word);
      expect(find.text('Edit selection'), findsOneWidget);
      await tap(tester, find.text('Censor'));
      expect(find.text('Edit selection'), findsNothing);
      expect(find.text('Review 1 change'), findsOneWidget);
    },
  );

  testWidgets('phrase selection returns to transcript to choose its endpoint', (
    tester,
  ) async {
    await editor(tester, EditorMedia());
    await tap(tester, find.byKey(const ValueKey('transcript-word-0')));
    await tap(tester, find.text('Select phrase'));
    expect(find.text('Cancel phrase selection'), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('transcript-word-1')));
    expect(find.text('Edit selection'), findsOneWidget);
    await tap(tester, find.text('Censor'));
    expect(find.text('Review 1 change'), findsOneWidget);
  });

  testWidgets('playback failure stays visible on the selection page', (
    tester,
  ) async {
    await editor(tester, FailedPreview());
    await tap(tester, find.byKey(const ValueKey('transcript-word-0')));
    await tap(tester, find.byTooltip('Play original 0:00.000 – 0:01.000'));
    expect(
      find.textContaining('Preview unavailable for this recording'),
      findsOneWidget,
    );
    await tap(tester, find.byTooltip('Back to transcript'));
    expect(find.text('Review 0 changes'), findsOneWidget);
  });

  testWidgets('timing changes do not reopen an earlier transcript selection', (
    tester,
  ) async {
    await editor(tester, EditorMedia());
    await tap(tester, find.byKey(const ValueKey('transcript-word-0')));
    await tap(tester, find.byTooltip('Back to transcript'));
    await tap(tester, find.text('Timing & pauses'));
    await tester.scrollUntilVisible(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Start (seconds)',
      ),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '0.2');
    await tester.enterText(find.byType(TextField).last, '0.8');
    await tester.pumpAndSettle();
    await tap(tester, find.text('Add manual change'));
    expect(find.byType(TimingScreen), findsOneWidget);
    expect(find.text('Edit selection'), findsNothing);
    await tap(tester, find.byTooltip('Back to transcript'));
    expect(find.text('Review 1 change'), findsOneWidget);
  });

  testWidgets(
    'all suggestions are in the page scroll with explicit positions',
    (tester) async {
      final analysis = const AudioAnalysis([
        AudioWindow(0, 1000, -10),
        AudioWindow(1000, 3000, -80),
        AudioWindow(3000, 4000, -10),
        AudioWindow(4000, 6000, -80),
        AudioWindow(6000, 7000, -10),
        AudioWindow(7000, 9000, -80),
        AudioWindow(9000, 10000, -10),
      ], hasAudio: true);
      await tester.pumpWidget(
        MaterialApp(
          home: TimingScreen(
            source: const SourceVideo('source.mp4', 10000),
            media: FakeEngine(),
            edits: const [],
            onApply: (_) {},
            onActivity: (_) {},
            analysis: analysis,
            onAnalysis: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expectOnePageScroll(tester);
      await tap(tester, find.text('Review suggested pauses'));
      expect(find.textContaining('3 suggested pauses'), findsOneWidget);
      await tap(tester, find.byTooltip('Review pause at 0:07.150'));
      expect(find.text('Pause 3 of 3'), findsOneWidget);
    },
  );
}
