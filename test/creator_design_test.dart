import 'project_fakes.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localcut/core/edit_plan.dart';
import 'package:localcut/design/app_theme.dart';
import 'package:localcut/editor/playback_media_engine.dart';
import 'package:localcut/editor/review_screen.dart';
import 'package:localcut/main.dart';
import 'package:localcut/media/media_engine.dart';
import 'silence_review_test.dart' show FakeEngine;
import 'transcript_panel_test.dart' show FakeSpeech;
import 'transcript_editor_flow_test.dart' show editor, tap, EditorMedia;

class PendingExport extends FakeEngine {
  final result = Completer<String>();
  bool canceled = false;
  @override
  Future<String> export(String path, List<RenderSegment> segments) =>
      result.future;
  @override
  Future<void> cancelExport() async {
    canceled = true;
  }
}

void main() {
  test(
    'native playback and export wait for inline playback to pause',
    () async {
      final backend = EditorMedia();
      final paused = Completer<void>();
      final engine = PlaybackMediaEngine(backend, () => paused.future);
      final preview = engine.preview('source.mp4', [
        const RenderSegment(0, 1000, false),
      ]);
      final export = engine.export('source.mp4', [
        const RenderSegment(0, 1000, false),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(backend.previewed, isNull);
      expect(backend.exported, isNull);
      paused.complete();
      await preview;
      await export;
      expect(backend.previewed, isNotNull);
      expect(backend.exported, isNotNull);
    },
  );

  testWidgets('leaving proposed edits autosaves without a discard dialog', (
    tester,
  ) async {
    await editor(tester, EditorMedia());
    await tap(tester, find.byKey(const ValueKey('transcript-word-0')));
    await tap(tester, find.text('Censor'));
    expect(find.text('Saved on this device'), findsOneWidget);
    await tap(tester, find.byTooltip('Back to home'));
    expect(find.text('Leave this edit?'), findsNothing);
    expect(find.text('Recent projects'), findsOneWidget);
  });
  testWidgets('late completion after export cancel never publishes output', (
    tester,
  ) async {
    final media = PendingExport();
    String? output;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ReviewScreen(
          source: const SourceVideo('source.mp4', 5000),
          media: media,
          edits: [const EditRange(1000, 2000, EditKind.cut)],
          onRemove: (_) {},
          onExported: (path) => output = path,
        ),
      ),
    );
    await tester.ensureVisible(find.text('Export video'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export video'));
    await tester.pump();
    expect(find.text('Making the final cut.'), findsOneWidget);
    await tester.tap(find.text('Cancel export'));
    await tester.pump();
    expect(media.canceled, isTrue);
    media.result.complete('late.mp4');
    await tester.pumpAndSettle();
    expect(output, isNull);
    expect(
      find.text('Export canceled. Your changes are still here.'),
      findsOneWidget,
    );
    expect(find.text('Save or share'), findsNothing);
  });

  Future<void> scrollTap(WidgetTester tester, Finder finder) async {
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
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  for (final dark in [false, true]) {
    testWidgets('creator flow fits landscape at larger text size, dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(812, 375);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final speech = FakeSpeech()..downloaded.add('english');
      await tester.pumpWidget(
        LocalCutApp(
          engine: EditorMedia(),
          projects: MemoryProjects(),
          transcriptionEngine: speech,
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        ),
      );
      await tester.pumpAndSettle();
      // Exercise text enlargement across all routes.
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Import video from Files'),
        150,
      );
      final context = tester.element(find.text('Import video from Files'));
      expect(
        Theme.of(context).brightness,
        dark ? Brightness.dark : Brightness.light,
      );
      await scrollTap(tester, find.text('Import video from Files'));
      await scrollTap(tester, find.text('Create transcript'));
      await scrollTap(tester, find.text('Generate transcript'));
      await scrollTap(tester, find.byKey(const ValueKey('transcript-word-0')));
      await scrollTap(tester, find.text('Censor'));
      await scrollTap(tester, find.byKey(const Key('review-changes')));
      await scrollTap(tester, find.text('Export video'));
      await scrollTap(tester, find.text('Back to review'));
      expect(tester.takeException(), isNull);
    });
  }
}
