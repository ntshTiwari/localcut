import '../core/edit_plan.dart';

enum TranscriptLanguage {
  english('en', 'English'),
  hindi('hi', 'Hindi'),
  hindiEnglish('mixed', 'Hindi–English');

  const TranscriptLanguage(this.code, this.label);
  final String code;
  final String label;
}

class SpeechModel {
  const SpeechModel({
    required this.id,
    required this.name,
    required this.bytes,
    required this.ready,
    required this.shared,
  });
  final String id;
  final String name;
  final int bytes;
  final bool ready;
  final bool shared;
  String get sizeLabel => '${(bytes / 1000000).round()} MB';
  factory SpeechModel.fromMap(Map<dynamic, dynamic> map) => SpeechModel(
    id: map['id'] as String,
    name: map['name'] as String,
    bytes: (map['bytes'] as num).toInt(),
    ready: map['ready'] as bool,
    shared: map['shared'] as bool,
  );
}

class TranscriptWord {
  const TranscriptWord(this.text, this.startMs, this.endMs);
  final String text;
  final int? startMs;
  final int? endMs;
  bool get aligned => startMs != null && endMs != null && endMs! > startMs!;
}

class VideoTranscript {
  const VideoTranscript(this.language, this.words);
  final TranscriptLanguage language;
  final List<TranscriptWord> words;

  factory VideoTranscript.fromMap(
    TranscriptLanguage language,
    Map<dynamic, dynamic> data,
    int durationMs,
  ) {
    var lastEnd = 0;
    final words = (data['words'] as List)
        .map((raw) {
          final map = raw as Map;
          final text = (map['text'] as String).trim();
          final start = (map['startMs'] as num?)?.toInt();
          final end = (map['endMs'] as num?)?.toInt();
          if (text.isEmpty) {
            throw const FormatException('Transcript contains empty text.');
          }
          final valid =
              start != null &&
              end != null &&
              start >= lastEnd &&
              end > start &&
              end <= durationMs;
          if (valid) {
            lastEnd = end;
            return TranscriptWord(text, start, end);
          }
          // Keep all recognized text, but never fabricate editable word timings.
          return TranscriptWord(text, null, null);
        })
        .toList(growable: false);
    return VideoTranscript(language, words);
  }
}

EditRange transcriptMute(
  VideoTranscript transcript,
  int a,
  int b,
  int durationMs,
) {
  final first = a < b ? a : b;
  final last = a > b ? a : b;
  if (first < 0 || last >= transcript.words.length) {
    throw ArgumentError('Invalid word selection.');
  }
  final selected = transcript.words.sublist(first, last + 1);
  if (selected.any((word) => !word.aligned)) {
    throw StateError(
      'Some words have no reliable timing. Select another phrase or adjust the range on the waveform.',
    );
  }
  final start = selected.first.startMs!;
  final end = selected.last.endMs!;
  if (start < 0 || end > durationMs || end <= start) {
    throw StateError('Selection falls outside the video.');
  }
  return EditRange(start, end, EditKind.mute);
}

class SpeechProgress {
  const SpeechProgress(this.phase, this.fraction, this.downloadedBytes);
  final String phase;
  final double? fraction;
  final int downloadedBytes;
}
