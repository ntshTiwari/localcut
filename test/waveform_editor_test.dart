import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localcut/core/edit_plan.dart';
import 'package:localcut/core/silence_detection.dart';
import 'package:localcut/widgets/waveform_editor.dart';

const analysis = AudioAnalysis([
  AudioWindow(0, 2000, -15),
  AudioWindow(2000, 4000, -70),
  AudioWindow(4000, 10000, -20),
], hasAudio: true);

Future<void> dragRange(WidgetTester tester, double from, double to) async {
  final finder = find.byKey(const Key('waveform-surface'));
  await tester.ensureVisible(finder);
  final rect = tester.getRect(finder);
  final gesture = await tester.startGesture(
    Offset(rect.left + rect.width * from, rect.center.dy),
  );
  // Cross touch slop before moving to the final endpoint.
  await gesture.moveBy(Offset(to > from ? 24 : -24, 0));
  await tester.pump();
  await gesture.moveTo(Offset(rect.left + rect.width * to, rect.center.dy));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'drag selects original time; preview and add are separate actions',
    (tester) async {
      final accepted = <EditRange>[];
      final previews = <EditRange>[];
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
                onHear: (_, _) async {},
                onPreview: (edit) async => previews.add(edit),
                onAdd: accepted.add,
              ),
            ),
          ),
        ),
      );
      await dragRange(tester, .2, .4);
      expect(find.textContaining('Selected 2.000 – 4.000 s'), findsOneWidget);
      expect(accepted, isEmpty);
      await tester.ensureVisible(find.text('Mute selection'));
      await tester.tap(find.text('Mute selection'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Preview mute'));
      await tester.tap(find.text('Preview mute'));
      await tester.pumpAndSettle();
      expect(previews.single.kind, EditKind.mute);
      expect([previews.single.startMs, previews.single.endMs], [2000, 4000]);
      expect(accepted, isEmpty);
      await tester.ensureVisible(find.text('Add mute'));
      await tester.tap(find.text('Add mute'));
      await tester.pumpAndSettle();
      expect(accepted.single.kind, EditKind.mute);
      expect(find.byKey(const Key('waveform-selection-label')), findsNothing);
    },
  );
  testWidgets(
    'tap hears bounded original context; zoom and pan retain source coordinates',
    (tester) async {
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
                onHear: (start, end) async {
                  heard = [start, end];
                },
                onPreview: (_) async {},
                onAdd: (_) {},
              ),
            ),
          ),
        ),
      );
      final surface = find.byKey(const Key('waveform-surface'));
      final rect = tester.getRect(surface);
      await tester.tapAt(Offset(rect.left, rect.center.dy));
      await tester.pumpAndSettle();
      expect(heard, [0, 1300]);
      await tester.tap(find.byKey(const Key('waveform-zoom-in')));
      await tester.pumpAndSettle();
      final slider = tester.widget<Slider>(
        find.byKey(const Key('waveform-pan')),
      );
      slider.onChanged!(5000);
      await tester.pumpAndSettle();
      await dragRange(tester, .2, .4);
      expect(find.textContaining('Selected 6.000 – 7.000 s'), findsOneWidget);
    },
  );
  testWidgets('edge gestures and nudges resize without moving the other edge', (
    tester,
  ) async {
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
              onHear: (_, _) async {},
              onPreview: (_) async {},
              onAdd: (_) {},
            ),
          ),
        ),
      ),
    );
    await dragRange(tester, .2, .6);
    await dragRange(tester, .2, .3);
    expect(find.textContaining('Selected 3.000 – 6.000 s'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('waveform-end-earlier')));
    await tester.tap(find.byKey(const Key('waveform-end-earlier')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Selected 3.000 – 5.980 s'), findsOneWidget);
  });
  testWidgets(
    'cannot remove the full clip and disabled waveform ignores input',
    (tester) async {
      final accepted = <EditRange>[];
      Widget app(bool enabled) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WaveformEditor(
              analysis: analysis,
              durationMs: 10000,
              edits: const [],
              suggestions: const [],
              enabled: enabled,
              onHear: (_, _) async {},
              onPreview: (_) async {},
              onAdd: accepted.add,
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(true));
      await dragRange(tester, 0, 1);
      await tester.ensureVisible(find.text('Preview cut'));
      await tester.tap(find.text('Preview cut'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Keep at least part of the video.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Add cut'));
      await tester.tap(find.text('Add cut'));
      await tester.pumpAndSettle();
      expect(accepted, isEmpty);
      expect(
        find.textContaining('Keep at least part of the video.'),
        findsOneWidget,
      );
      await tester.pumpWidget(app(false));
      await tester.ensureVisible(find.byKey(const Key('waveform-surface')));
      await dragRange(tester, .1, .5);
      expect(find.textContaining('Selected 0.000 – 10.000 s'), findsOneWidget);
    },
  );
  testWidgets('controls fit a narrow phone screen without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
              onHear: (_, _) async {},
              onPreview: (_) async {},
              onAdd: (_) {},
            ),
          ),
        ),
      ),
    );
    await dragRange(tester, .2, .6);
    expect(tester.takeException(), isNull);
    expect(find.text('Add cut'), findsOneWidget);
  });
}
