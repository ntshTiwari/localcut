import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localcut/core/edit_plan.dart';
import 'package:localcut/core/pause_review.dart';
import 'package:localcut/editor/pause_review_screen.dart';
import 'package:localcut/media/media_engine.dart';
import 'package:localcut/design/app_theme.dart';
import 'silence_review_test.dart' show FakeEngine;
import 'transcript_editor_flow_test.dart' show tap, editor, EditorMedia;

final pauses = [
  const EditRange(1000, 2000, EditKind.cut),
  const EditRange(4000, 7000, EditKind.cut),
  const EditRange(9000, 11000, EditKind.cut),
];
PauseReviewSession sessionWith(List<EditRange> p) =>
    PauseReviewSession()..sync(p);
Future<void> overview(
  WidgetTester tester,
  PauseReviewSession session, {
  FakeEngine? media,
  ValueChanged<List<EditRange>>? apply,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: PauseOverviewScreen(
        session: session,
        source: const SourceVideo('source.mp4', 1200000),
        media: media ?? FakeEngine(),
        onApply: apply ?? (_) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class PendingPausePreview extends FakeEngine {
  final result = Completer<void>();
  @override
  Future<void> preview(
    String path,
    List<RenderSegment> segments, {
    String? label,
  }) => result.future;
}

void main() {
  test(
    'decisions, filtering and sorting retain source identity and reversible history',
    () {
      final s = sessionWith(pauses);
      s.decide(pauses[0], PauseDecision.keep);
      s.decide(pauses[2], PauseDecision.trim);
      expect(s.reviewed, 2);
      expect(s.visible(PauseFilter.unreviewed, PauseOrder.timeline), [
        pauses[1],
      ]);
      expect(s.ordered(PauseOrder.longest), [pauses[1], pauses[2], pauses[0]]);
      s.markAllForTrim();
      expect(s.trims.length, 3);
      s.undo();
      expect(s.trims, [pauses[2]]);
      expect(s.decision(pauses[0]), PauseDecision.keep);
      s.undo();
      expect(s.decision(pauses[2]), isNull);
      s.sync(List.of(pauses));
      expect(s.canUndo, isTrue);
      s.undo();
      expect(s.reviewed, 0);
    },
  );
  test(
    'changed suggestions drop obsolete decisions and invalid undo history',
    () {
      final s = sessionWith(pauses);
      s.decide(pauses[0], PauseDecision.trim);
      s.decide(pauses[1], PauseDecision.keep);
      s.sync([pauses[1], pauses[2]]);
      expect(s.reviewed, 1);
      expect(s.trims, isEmpty);
      expect(s.canUndo, isFalse);
      s.reset();
      expect(s.reviewed, 0);
    },
  );
  testWidgets(
    '100 pauses use compact lazy rows, with no embedded player in overview',
    (tester) async {
      final large = List.generate(
        100,
        (i) => EditRange(i * 10000 + 1000, i * 10000 + 2500, EditKind.cut),
      );
      final s = sessionWith(large);
      await overview(tester, s);
      expect(find.textContaining('100 suggested pauses'), findsOneWidget);
      expect(
        tester.widgetList<ListTile>(find.byType(ListTile)).length,
        lessThan(20),
      );
      expect(
        find.byKey(ValueKey('pause-row-${pauseId(large.last)}')),
        findsNothing,
      );
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('pause-row-${pauseId(large.last)}')),
        600,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 30,
      );
      expect(
        find.byKey(ValueKey('pause-row-${pauseId(large.last)}')).hitTestable(),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'keep and trim auto advance with undo and do not add edits until Add',
    (tester) async {
      final s = sessionWith(pauses);
      final added = <EditRange>[];
      await overview(tester, s, apply: added.addAll);
      await tap(tester, find.text('Review next pause'));
      await tap(tester, find.text('Keep pause'));
      expect(find.text('Pause 2 of 3'), findsOneWidget);
      await tap(tester, find.text('Trim pause'));
      expect(find.text('Pause 3 of 3'), findsOneWidget);
      expect(added, isEmpty);
      await tap(tester, find.byTooltip('Undo review decision'));
      expect(find.text('Pause 2 of 3'), findsOneWidget);
      expect(s.decision(pauses[1]), isNull);
      await tap(tester, find.text('Trim pause'));
      await tap(tester, find.text('Keep pause'));
      expect(find.text('All pauses reviewed'), findsOneWidget);
      expect(added, isEmpty);
      await tap(tester, find.text('Back to overview'));
      await tap(tester, find.text('Add 1 cut to edits'));
      expect(added, [pauses[1]]);
    },
  );
  testWidgets(
    'three compact preview modes replay exact original and edited ranges',
    (tester) async {
      final s = sessionWith(pauses), media = FakeEngine();
      await overview(tester, s, media: media);
      await tap(tester, find.text('Review next pause'));
      await tap(tester, find.byKey(const ValueKey('preview-mode-Section')));
      expect(media.previewed!.map((p) => [p.startMs, p.endMs]), [
        [1000, 2000],
      ]);
      await tap(tester, find.byKey(const ValueKey('preview-mode-Original')));
      expect(media.previewed!.map((p) => [p.startMs, p.endMs]), [
        [0, 3000],
      ]);
      await tap(tester, find.byKey(const ValueKey('preview-mode-Trimmed')));
      expect(media.previewed!.map((p) => [p.startMs, p.endMs]), [
        [0, 1000],
        [2000, 3000],
      ]);
      await tap(tester, find.byKey(const ValueKey('preview-mode-Trimmed')));
      expect(s.reviewed, 0);
    },
  );
  testWidgets(
    'bulk mark and undo restore prior keep decisions, filters stay accurate',
    (tester) async {
      final s = sessionWith(pauses);
      s.decide(pauses.first, PauseDecision.keep);
      await overview(tester, s);
      await tap(tester, find.byTooltip('Review options'));
      await tap(tester, find.text('Mark all for removal'));
      expect(s.trims.length, 3);
      await tap(tester, find.byTooltip('Undo review decision'));
      expect(s.trims, isEmpty);
      expect(s.reviewed, 1);
      await tap(tester, find.byType(DropdownButtonFormField<PauseFilter>));
      await tap(tester, find.text('Kept').last);
      expect(
        find.byKey(ValueKey('pause-row-${pauseId(pauses.first)}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('pause-row-${pauseId(pauses.last)}')),
        findsNothing,
      );
      await tap(tester, find.byTooltip('Sort pauses'));
      await tap(tester, find.text('Longest first'));
      expect(find.text('Longest'), findsOneWidget);
    },
  );
  testWidgets(
    'review progress survives returning to the transcript and reopening timing',
    (tester) async {
      await editor(tester, EditorMedia());
      await tap(tester, find.text('Timing & pauses'));
      await tap(tester, find.text('Review suggested pauses'));
      await tap(tester, find.text('Review next pause'));
      await tap(tester, find.text('Keep pause'));
      await tap(tester, find.text('Back to overview'));
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tap(tester, find.byTooltip('Back to transcript'));
      await tap(tester, find.text('Timing & pauses'));
      await tap(tester, find.text('Review suggested pauses'));
      expect(
        find.text('1 of 1 reviewed · decisions are not applied yet'),
        findsOneWidget,
      );
      expect(find.text('Add 0 cuts to edits'), findsOneWidget);
    },
  );
  testWidgets(
    'preparation disables comparison and decisions until the request completes',
    (tester) async {
      final media = PendingPausePreview();
      await overview(tester, sessionWith(pauses), media: media);
      await tap(tester, find.text('Review next pause'));
      await tester.tap(find.byKey(const ValueKey('preview-mode-Section')));
      await tester.pump();
      expect(
        tester.widget<ToggleButtons>(find.byType(ToggleButtons)).onPressed,
        isNull,
      );
      expect(
        tester
            .widget<ButtonStyleButton>(
              find
                  .ancestor(
                    of: find.text('Keep pause'),
                    matching: find.byWidgetPredicate(
                      (w) => w is ButtonStyleButton,
                    ),
                  )
                  .first,
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Original'), findsOneWidget);
      expect(find.text('Trimmed'), findsOneWidget);
      media.result.complete();
      await tester.pumpAndSettle();
      expect(
        tester.widget<ToggleButtons>(find.byType(ToggleButtons)).onPressed,
        isNotNull,
      );
    },
  );
  test(
    'applied marks are consumed so restored cuts are unreviewed, not silently marked again',
    () {
      final s = sessionWith(pauses);
      s.decide(pauses.first, PauseDecision.trim);
      s.decide(pauses.last, PauseDecision.keep);
      final cuts = s.trims;
      s.applied(cuts);
      expect(s.trims, isEmpty);
      expect(s.canUndo, isFalse);
      s.sync(pauses.sublist(1));
      s.sync(pauses);
      expect(s.decision(pauses.first), isNull);
      expect(s.decision(pauses.last), PauseDecision.keep);
    },
  );

  testWidgets('timing Proceed opens review directly after adding guided cuts', (
    tester,
  ) async {
    await editor(tester, EditorMedia());
    await tap(tester, find.text('Timing & pauses'));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('proceed-from-timing')))
          .onPressed,
      isNull,
    );
    await tap(tester, find.text('Review suggested pauses'));
    await tap(tester, find.text('Review next pause'));
    await tap(tester, find.text('Trim pause'));
    await tap(tester, find.text('Back to overview'));
    await tap(tester, find.text('Add 1 cut to edits'));
    expect(find.text('Timing & pauses'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('proceed-from-timing')))
          .onPressed,
      isNotNull,
    );
    await tap(tester, find.byKey(const Key('proceed-from-timing')));
    expect(find.text('Review changes'), findsOneWidget);
    expect(find.text('Export video'), findsOneWidget);
    await tap(tester, find.byTooltip('Back to transcript'));
    expect(find.text('Review 1 change'), findsOneWidget);
  });

  for (final size in [const Size(320, 640), const Size(812, 375)]) {
    testWidgets('overview and reviewer fit $size with enlarged text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await overview(tester, sessionWith(pauses));
      await tap(tester, find.text('Review next pause'));
      await tap(tester, find.byKey(const ValueKey('preview-mode-Trimmed')));
      await tap(tester, find.text('Keep pause'));
      expect(find.text('Pause 2 of 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
