import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localcut/core/edit_plan.dart';
import 'package:localcut/core/silence_detection.dart';
import 'package:localcut/media/media_engine.dart';
import 'package:localcut/transcript/transcript.dart';
import 'package:localcut/transcript/transcript_panel.dart';
import 'package:localcut/transcript/transcription_engine.dart';
import 'silence_review_test.dart' show FakeEngine;

class FakeSpeech implements TranscriptionEngine {
  final downloaded = <String>{};
  final downloads = <TranscriptLanguage>[];
  final transcriptions = <TranscriptLanguage>[];
  Completer<void>? pendingDownload;
  bool failDownload = false;
  VideoTranscript? result;
  String id(TranscriptLanguage language) =>
      language == TranscriptLanguage.english ? 'english' : 'multilingual';
  @override
  Future<SpeechModel> model(TranscriptLanguage language) async => SpeechModel(
    id: id(language),
    name: id(language),
    bytes: language == TranscriptLanguage.english ? 147964211 : 487601967,
    ready: downloaded.contains(id(language)),
    shared: language != TranscriptLanguage.english,
  );
  @override
  Future<void> download(TranscriptLanguage language) async {
    downloads.add(language);
    if (failDownload) throw StateError('Download failed');
    if (pendingDownload != null) await pendingDownload!.future;
    downloaded.add(id(language));
  }

  @override
  Future<VideoTranscript> transcribe(
    String path,
    int durationMs,
    TranscriptLanguage language,
  ) async {
    transcriptions.add(language);
    return result ??
        VideoTranscript(language, const [
          TranscriptWord('Hello', 1000, 1300),
          TranscriptWord('friend', 1400, 1800),
        ]);
  }

  @override
  Future<SpeechProgress> progress() async =>
      const SpeechProgress('downloading', .4, 60000000);
  @override
  Future<void> cancel() async {
    pendingDownload?.completeError(StateError('Canceled'));
  }

  @override
  Future<void> deleteModel(TranscriptLanguage language) async {
    downloaded.remove(id(language));
  }
}

class WaitingAnalysis extends FakeEngine {
  final pending = Completer<AudioAnalysis>();
  bool canceled = false;
  @override
  Future<AudioAnalysis> analyzeAudio(String path) => pending.future;
  @override
  Future<void> cancelAnalysis() async {
    canceled = true;
    pending.completeError(StateError('Canceled'));
  }
}

Future<void> mount(
  WidgetTester tester,
  FakeSpeech speech, {
  FakeEngine? media,
  List<EditRange>? edits,
  SourceVideo? source,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TranscriptPanel(
            engine: speech,
            media: media ?? FakeEngine(),
            source: source ?? const SourceVideo('source.mp4', 5000),
            edits: edits ?? [],
            enabled: true,
            onBusyChanged: (_) {},
            onAdd: (edits ?? []).add,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Create transcript'));
  await tester.pumpAndSettle();
}

Future<void> language(WidgetTester tester, String label) async {
  if (find.byKey(const Key('transcript-language')).evaluate().isEmpty) {
    final entry = find.text('Language & downloads').evaluate().isNotEmpty
        ? find.text('Language & downloads')
        : find.text('Create transcript');
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(find.byKey(const Key('transcript-language')));
  await tester.tap(find.byKey(const Key('transcript-language')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'no eager download; download on request and mute only after explicit addition',
    (tester) async {
      final speech = FakeSpeech();
      final media = FakeEngine();
      final edits = <EditRange>[];
      await mount(tester, speech, media: media, edits: edits);
      expect(speech.downloads, isEmpty);
      await tester.tap(find.text('Download 148 MB & transcribe'));
      await tester.pumpAndSettle();
      expect(speech.downloads, [TranscriptLanguage.english]);
      await tester.ensureVisible(
        find.byKey(const ValueKey('transcript-word-0')),
      );
      await tester.tap(find.byKey(const ValueKey('transcript-word-0')));
      await tester.pumpAndSettle();
      expect(media.previewed, isNull);
      await tester.ensureVisible(find.text('Original'));
      await tester.tap(find.byKey(const ValueKey('preview-mode-Original')));
      await tester.pumpAndSettle();
      expect(media.previewed!.single.startMs, 0);
      await tester.ensureVisible(find.text('Select phrase'));
      await tester.tap(find.text('Select phrase'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('transcript-word-1')),
      );
      await tester.tap(find.byKey(const ValueKey('transcript-word-1')));
      await tester.pumpAndSettle();
      expect(edits, isEmpty);
      await tester.ensureVisible(find.text('Censor'));
      await tester.tap(find.text('Censor'));
      await tester.pumpAndSettle();
      expect([edits.single.startMs, edits.single.endMs], [1000, 1800]);
    },
  );
  testWidgets(
    'Hindi and mixed speech reuse one download; English remains separate',
    (tester) async {
      final speech = FakeSpeech();
      await mount(tester, speech);
      await language(tester, 'Hindi');
      expect(speech.downloads, isEmpty);
      await tester.tap(find.text('Download 488 MB & transcribe'));
      await tester.pumpAndSettle();
      await language(tester, 'Hindi–English');
      expect(find.textContaining('Downloaded — ready offline'), findsOneWidget);
      await tester.ensureVisible(find.text('Generate transcript'));
      await tester.tap(find.text('Generate transcript'));
      await tester.pumpAndSettle();
      expect(speech.downloads, [TranscriptLanguage.hindi]);
      expect(speech.transcriptions, [
        TranscriptLanguage.hindi,
        TranscriptLanguage.hindiEnglish,
      ]);
      await language(tester, 'English');
      expect(find.text('Download 148 MB & transcribe'), findsOneWidget);
    },
  );
  testWidgets('ready models work without another download', (tester) async {
    final speech = FakeSpeech()..downloaded.add('english');
    await mount(tester, speech);
    await tester.tap(find.text('Generate transcript'));
    await tester.pumpAndSettle();
    expect(speech.downloads, isEmpty);
    expect(speech.transcriptions, [TranscriptLanguage.english]);
  });
  testWidgets('download errors permit retry without creating a transcript', (
    tester,
  ) async {
    final speech = FakeSpeech()..failDownload = true;
    await mount(tester, speech);
    await tester.tap(find.text('Download 148 MB & transcribe'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Download failed'), findsOneWidget);
    expect(speech.transcriptions, isEmpty);
    speech.failDownload = false;
    await tester.ensureVisible(find.text('Download 148 MB & transcribe'));
    await tester.tap(find.text('Download 148 MB & transcribe'));
    await tester.pumpAndSettle();
    expect(speech.transcriptions, [TranscriptLanguage.english]);
  });
  testWidgets('canceling a model download does not start transcription', (
    tester,
  ) async {
    final speech = FakeSpeech()..pendingDownload = Completer<void>();
    await mount(tester, speech);
    await tester.tap(find.text('Download 148 MB & transcribe'));
    await tester.pump();
    await tester.ensureVisible(find.text('Cancel transcription'));
    await tester.tap(find.text('Cancel transcription'));
    await tester.pumpAndSettle();
    expect(speech.transcriptions, isEmpty);
    expect(find.textContaining('Canceled.'), findsOneWidget);
  });
  testWidgets('video without audio does not trigger a model download', (
    tester,
  ) async {
    final speech = FakeSpeech();
    await mount(
      tester,
      speech,
      source: const SourceVideo('silent.mp4', 5000, hasAudio: false),
    );
    await tester.tap(find.text('Download 148 MB & transcribe'));
    await tester.pumpAndSettle();
    expect(speech.downloads, isEmpty);
    expect(speech.transcriptions, isEmpty);
    expect(find.textContaining('no audio track'), findsOneWidget);
  });
  testWidgets('removing shared model preserves the cached transcript', (
    tester,
  ) async {
    final speech = FakeSpeech()..downloaded.add('multilingual');
    await mount(tester, speech);
    await language(tester, 'Hindi');
    await tester.tap(find.text('Generate transcript'));
    await tester.pumpAndSettle();
    final entry = find.text('Language & downloads').evaluate().isNotEmpty
        ? find.text('Language & downloads')
        : find.text('Create transcript');
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Remove model download'));
    await tester.tap(find.text('Remove model download'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Hindi and Hindi–English share this model'),
      findsOneWidget,
    );
    await tester.tap(find.text('Remove download'));
    await tester.pumpAndSettle();
    expect(speech.downloaded, isEmpty);
    expect(find.byKey(const Key('transcript-text')), findsOneWidget);
    expect(find.text('Download 488 MB & transcribe'), findsOneWidget);
  });
  testWidgets(
    'cancel during pause checking cancels audio analysis without publishing a partial transcript',
    (tester) async {
      final speech = FakeSpeech()..downloaded.add('english');
      final media = WaitingAnalysis();
      await mount(tester, speech, media: media);
      await tester.tap(find.text('Generate transcript'));
      await tester.pump();
      expect(find.text('Checking pauses on this device…'), findsOneWidget);
      await tester.ensureVisible(find.text('Cancel transcription'));
      await tester.tap(find.text('Cancel transcription'));
      await tester.pumpAndSettle();
      expect(media.canceled, isTrue);
      expect(find.byKey(const Key('transcript-text')), findsNothing);
      expect(find.textContaining('Canceled.'), findsOneWidget);
    },
  );
}
