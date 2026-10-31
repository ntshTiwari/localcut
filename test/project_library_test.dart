import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localcut/main.dart';
import 'package:localcut/core/edit_plan.dart';
import 'package:localcut/editor/project_library_screen.dart';
import 'package:localcut/media/media_engine.dart';
import 'package:localcut/projects/project.dart';
import 'package:localcut/design/app_theme.dart';
import 'project_fakes.dart';
import 'transcript_panel_test.dart' show FakeSpeech;
import 'transcript_editor_flow_test.dart' show EditorMedia, tap;

Future<MemoryProjects> fixtures() async {
  final repo = MemoryProjects();
  for (final row in [
    (
      id: 'alpha',
      title: 'Alpha tutorial',
      duration: 60000,
      created: 1,
      saved: 2,
      changed: true,
    ),
    (
      id: 'beta',
      title: 'Beta update',
      duration: 600000,
      created: 2,
      saved: 3,
      changed: false,
    ),
    (
      id: 'gamma',
      title: 'Gamma episode',
      duration: 1800000,
      created: 4,
      saved: 1,
      changed: true,
    ),
  ]) {
    await repo.save(
      LocalProject(
        id: row.id,
        title: row.title,
        source: SourceVideo('${row.id}.mp4', row.duration),
        createdAt: DateTime.utc(2026, 1, row.created),
        updatedAt: DateTime.utc(2026, 1, row.saved),
        edits: row.changed
            ? [const EditRange(1000, 2000, EditKind.cut)]
            : const [],
      ),
    );
  }
  return repo;
}

Future<void> library(WidgetTester tester, MemoryProjects repo) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: ProjectLibraryScreen(
        projects: repo,
        media: EditorMedia(),
        speech: FakeSpeech(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<String> visibleTitles(WidgetTester tester) => tester
    .widgetList<ListTile>(find.byType(ListTile))
    .map((tile) => (tile.title! as Text).data!)
    .toList();
Future<void> select(WidgetTester tester, String key, String value) async {
  await tap(tester, find.byKey(Key(key)));
  await tap(tester, find.text(value).last);
}

void main() {
  testWidgets(
    'home retains its hero with saved projects and opens the library through a button',
    (tester) async {
      final repo = await fixtures();
      await tester.pumpWidget(
        LocalCutApp(
          projects: repo,
          engine: EditorMedia(),
          transcriptionEngine: FakeSpeech(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Less cleanup.\nMore creating.'), findsOneWidget);
      expect(find.text('Import video from Files'), findsOneWidget);
      expect(find.byKey(const ValueKey('project-alpha')), findsNothing);
      await tap(tester, find.byKey(const Key('recent-projects')));
      expect(find.byType(ProjectLibraryScreen), findsOneWidget);
      expect(find.text('Beta update'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 700));
      await tester.pumpAndSettle();
      expect(find.text('Less cleanup.\nMore creating.'), findsOneWidget);
    },
  );
  testWidgets(
    'name search combines with change filters without loading project snapshots',
    (tester) async {
      final repo = await fixtures();
      await library(tester, repo);
      await tester.enterText(find.byKey(const Key('project-search')), 'ALPHA');
      await tester.pumpAndSettle();
      expect(visibleTitles(tester), ['Alpha tutorial']);
      await select(tester, 'project-filter', 'No changes');
      expect(visibleTitles(tester), isEmpty);
      expect(find.text('No matching projects'), findsOneWidget);
      await tap(tester, find.text('Clear search and filters'));
      expect(visibleTitles(tester).length, 3);
      expect(find.text('All projects'), findsOneWidget);
      await select(tester, 'project-filter', 'With changes');
      expect(visibleTitles(tester).toSet(), {
        'Alpha tutorial',
        'Gamma episode',
      });
      expect(repo.records.length, 3);
    },
  );
  testWidgets('all sort choices use saved metadata in the expected order', (
    tester,
  ) async {
    await library(tester, await fixtures());
    expect(visibleTitles(tester), [
      'Beta update',
      'Alpha tutorial',
      'Gamma episode',
    ]);
    await select(tester, 'project-sort', 'Name A–Z');
    expect(visibleTitles(tester), [
      'Alpha tutorial',
      'Beta update',
      'Gamma episode',
    ]);
    await select(tester, 'project-sort', 'Longest video');
    expect(visibleTitles(tester), [
      'Gamma episode',
      'Beta update',
      'Alpha tutorial',
    ]);
    await select(tester, 'project-sort', 'Newest created');
    expect(visibleTitles(tester), [
      'Gamma episode',
      'Beta update',
      'Alpha tutorial',
    ]);
    await select(tester, 'project-sort', 'Recently saved');
    expect(visibleTitles(tester), [
      'Beta update',
      'Alpha tutorial',
      'Gamma episode',
    ]);
  });
  testWidgets('empty library gives a clear way back to importing', (
    tester,
  ) async {
    await library(tester, MemoryProjects());
    expect(find.text('No saved projects yet'), findsOneWidget);
    expect(find.text('Back to Home'), findsOneWidget);
  });
  for (final size in [const Size(320, 640), const Size(812, 375)]) {
    testWidgets('library controls fit $size with enlarged text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await library(tester, await fixtures());
      await select(tester, 'project-sort', 'Longest video');
      await select(tester, 'project-filter', 'With changes');
      expect(tester.takeException(), isNull);
    });
  }
}
