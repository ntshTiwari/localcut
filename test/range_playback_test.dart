import 'package:localcut/editor/timing_screen.dart';
import 'package:localcut/widgets/waveform_editor.dart';
import 'waveform_editor_test.dart' show dragRange, analysis;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localcut/core/edit_plan.dart';
import 'package:localcut/design/app_theme.dart';
import 'package:localcut/editor/review_screen.dart';
import 'package:localcut/media/media_engine.dart';
import 'package:localcut/widgets/silence_review.dart';
import 'package:localcut/widgets/time_range_playback.dart';
import 'silence_review_test.dart' show FakeEngine;
import 'transcript_editor_flow_test.dart' show editor, tap, EditorMedia;

void main() {
  test(
    'timestamps preserve milliseconds and support recordings over an hour',
    () {
      expect(rangeTimestamp(180000), '3:00.000');
      expect(rangeTimestamp(3600123), '60:00.123');
    },
  );

  testWidgets('suggestion play is exact and never selects or adds the cut', (
    tester,
  ) async {
    final media = FakeEngine();
    final edits = <EditRange>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SilenceReview(
              engine: media,
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
    await tap(tester, find.text('Analyze audio'));
    await tap(tester, find.byTooltip('Play original 0:01.150 – 0:02.850'));
    expect(
      media.previewed!.map((s) => [s.startMs, s.endMs, s.muted]).toList(),
      [
        [1150, 2850, false],
      ],
    );
    expect(edits, isEmpty);
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
    await tap(tester, find.text('With section'));
    expect(media.previewed!.single.startMs, 150);
    expect(media.previewed!.single.endMs, 3850);
  });

  testWidgets('review plays original sound for both cuts and censored ranges', (
    tester,
  ) async {
    final media = FakeEngine();
    final edits = [
      const EditRange(0, 1000, EditKind.mute),
      const EditRange(2000, 3000, EditKind.cut),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: ReviewScreen(
          source: const SourceVideo('source.mp4', 5000),
          media: media,
          edits: edits,
          onRemove: (_) => fail('Playback must not restore an edit'),
          onExported: (_) => fail('Playback must not export'),
        ),
      ),
    );
    for (final range in edits) {
      await tap(
        tester,
        find.byTooltip(
          'Play original ${rangeTimestamp(range.startMs)} – ${rangeTimestamp(range.endMs)}',
        ),
      );
      expect(
        media.previewed!.map((s) => [s.startMs, s.endMs, s.muted]).toList(),
        [
          [range.startMs, range.endMs, false],
        ],
      );
    }
    expect(edits.length, 2);
  });

  testWidgets('transcript word and pause play their exact source bounds', (
    tester,
  ) async {
    final media = EditorMedia();
    await editor(tester, media);
    await tap(tester, find.byKey(const ValueKey('transcript-word-0')));
    await tap(tester, find.byTooltip('Play original 0:00.000 – 0:01.000'));
    expect(media.previewed!.single.startMs, 0);
    expect(media.previewed!.single.endMs, 1000);
    expect(media.previewed!.single.muted, isFalse);
    await tap(tester, find.byTooltip('Back to transcript'));
    await tap(tester, find.byKey(const ValueKey('transcript-gap-1')));
    await tap(tester, find.byTooltip('Play original 0:01.000 – 0:02.800'));
    expect(media.previewed!.single.startMs, 1000);
    expect(media.previewed!.single.endMs, 2800);
    await tap(tester, find.byTooltip('Back to transcript'));
    expect(find.text('Review 0 changes'), findsOneWidget);
  });

  testWidgets(
    'manual time fields expose exact playback without adding an edit',
    (tester) async {
      final media = FakeEngine();
      final edits = <EditRange>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimingScreen(
              source: const SourceVideo('source.mp4', 5000),
              media: media,
              edits: edits,
              onApply: edits.addAll,
              onActivity: (_) {},
              onAnalysis: (_) {},
            ),
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.byType(TextField).first,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.byType(TextField).first, '1.234');
      await tester.enterText(find.byType(TextField).last, '2.345');
      await tester.pumpAndSettle();
      await tap(tester, find.byTooltip('Play original 0:01.234 – 0:02.345'));
      expect(media.previewed!.single.startMs, 1234);
      expect(media.previewed!.single.endMs, 2345);
      expect(edits, isEmpty);
      await tester.scrollUntilVisible(
        find.byType(TextField).last,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.widgetWithText(TextField, '2.345'), '0.2');
      await tester.pumpAndSettle();
      expect(find.byType(TimeRangePlayback), findsNothing);
    },
  );

  testWidgets('waveform timestamp plays only selected original time', (
    tester,
  ) async {
    List<int>? heard;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WaveformEditor(
              analysis: analysis,
              durationMs: 10000,
              edits: const [],
              suggestions: const [],
              enabled: true,
              onHear: (a, b) async => heard = [a, b],
              onPreview: (_) async {},
              onAdd: (_) => fail('Play must not add an edit'),
            ),
          ),
        ),
      ),
    );
    await dragRange(tester, .2, .4);
    await tap(tester, find.byTooltip('Play original 0:02.000 – 0:04.000'));
    expect(heard, [2000, 4000]);
  });

  testWidgets(
    'range control wraps on a narrow phone with larger text and disables cleanly',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: const SizedBox(
                width: 200,
                child: TimeRangePlayback(
                  startMs: 180000,
                  endMs: 300000,
                  onPlay: null,
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
