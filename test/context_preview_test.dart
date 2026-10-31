import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localcut/core/context_preview.dart';
import 'package:localcut/editor/inline_preview.dart';
import 'package:localcut/core/edit_plan.dart';
import 'transcript_editor_flow_test.dart' show editor, tap, EditorMedia;

void main() {
  test(
    'kept and cut contexts use identical source windows with no cut audio',
    () {
      expect(
        contextPreview(
          10000,
          3000,
          5000,
        ).map((s) => [s.startMs, s.endMs, s.muted]),
        [
          [2000, 6000, false],
        ],
      );
      expect(
        contextPreview(
          10000,
          3000,
          5000,
          remove: true,
        ).map((s) => [s.startMs, s.endMs, s.muted]),
        [
          [2000, 3000, false],
          [5000, 6000, false],
        ],
      );
      expect(
        contextPreview(
          5000,
          0,
          1000,
          remove: true,
        ).map((s) => [s.startMs, s.endMs]),
        [
          [1000, 2000],
        ],
      );
      expect(
        () => contextPreview(1000, 0, 1000, remove: true),
        throwsArgumentError,
      );
    },
  );
  test('censor comparison preserves the selected frames and length', () {
    final plan = contextPreview(5000, 1000, 2000, mute: true);
    expect(plan.map((s) => [s.startMs, s.endMs, s.muted]), [
      [0, 1000, false],
      [1000, 2000, true],
      [2000, 3000, false],
    ]);
  });
  testWidgets('compare context on one selection screen without adding edits', (
    tester,
  ) async {
    final media = EditorMedia();
    await editor(tester, media);
    await tap(tester, find.byKey(const ValueKey('transcript-gap-1')));
    await tap(tester, find.byKey(const ValueKey('preview-mode-Original')));
    expect(media.previewed!.map((s) => [s.startMs, s.endMs]), [
      [0, 3800],
    ]);
    expect(find.byType(InlinePreviewPane), findsOneWidget);
    expect(find.text('Context · with section'), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('preview-mode-Trimmed')));
    expect(media.previewed!.map((s) => [s.startMs, s.endMs]), [
      [0, 1150],
      [2650, 3800],
    ]);
    expect(find.text('Context · without section'), findsOneWidget);
    expect(find.text('Edit selection'), findsOneWidget);
    await tap(tester, find.byTooltip('Close selection preview'));
    expect(find.text('Context · without section'), findsNothing);
    expect(find.text('Shorten pause'), findsOneWidget);
    await tap(tester, find.byTooltip('Back to transcript'));
    expect(find.text('Review 0 changes'), findsOneWidget);
  });
  testWidgets('embedded preview and comparison fit a landscape phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(812, 375);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final media = EditorMedia();
    await editor(tester, media);
    await tap(tester, find.byKey(const ValueKey('transcript-gap-1')));
    await tap(tester, find.byKey(const ValueKey('preview-mode-Trimmed')));
    expect(find.text('Context · without section'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test('closing or replacing a preview never mutates a submitted plan', () {
    final c = InlinePreviewController();
    final plan = [const RenderSegment(100, 200, false)];
    c.show('source.mp4', plan);
    plan.clear();
    expect(c.segments.length, 1);
    c.close();
    expect(c.path, isNull);
    c.dispose();
    c.show('late.mp4', []);
  });
}
