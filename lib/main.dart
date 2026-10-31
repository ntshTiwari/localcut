import 'projects/project_repository.dart';
import 'package:flutter/material.dart';
import 'design/app_theme.dart';
import 'editor/home_screen.dart';
import 'media/media_engine.dart';
import 'transcript/transcription_engine.dart';
export 'editor/editor_screen.dart';

void main() => runApp(const LocalCutApp());

class LocalCutApp extends StatelessWidget {
  const LocalCutApp({
    super.key,
    this.engine,
    this.transcriptionEngine,
    this.themeMode = ThemeMode.system,
    this.projects,
  });
  final ProjectRepository? projects;
  final MediaEngine? engine;
  final TranscriptionEngine? transcriptionEngine;
  final ThemeMode themeMode;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'LocalCut',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: themeMode,
    home: HomeScreen(
      media: engine ?? PlatformMediaEngine(),
      speech: transcriptionEngine ?? PlatformTranscriptionEngine(),
      projects: projects ?? FileProjectRepository(),
    ),
  );
}
