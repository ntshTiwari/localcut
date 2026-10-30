import 'package:flutter_test/flutter_test.dart';
import 'package:localcut/core/edit_plan.dart';
import 'package:localcut/transcript/transcript.dart';

void main() {
  test('offers exactly the three requested language modes', () {
    expect(TranscriptLanguage.values.map((l) => l.code), ['en', 'hi', 'mixed']);
  });
  test(
    'transcript words retain source timing and reverse selection yields one mute',
    () {
      final transcript = VideoTranscript.fromMap(TranscriptLanguage.english, {
        'words': [
          {'text': 'Hello', 'startMs': 1000, 'endMs': 1300},
          {'text': 'there', 'startMs': 1400, 'endMs': 1800},
          {'text': 'friend.', 'startMs': 1900, 'endMs': 2400},
        ],
      }, 5000);
      final mute = transcriptMute(transcript, 2, 0, 5000);
      expect(
        [mute.startMs, mute.endMs, mute.kind],
        [1000, 2400, EditKind.mute],
      );
      final plan = compilePlan(5000, [
        const EditRange(0, 500, EditKind.cut),
        mute,
      ]);
      expect(plan.map((s) => [s.startMs, s.endMs, s.muted]), [
        [500, 1000, false],
        [1000, 2400, true],
        [2400, 5000, false],
      ]);
    },
  );
  test(
    'invalid or missing word timing preserves text but cannot create edits',
    () {
      final transcript = VideoTranscript.fromMap(TranscriptLanguage.hindi, {
        'words': [
          {'text': 'नमस्ते', 'startMs': 1000, 'endMs': 1300},
          {'text': 'दोस्त', 'startMs': null, 'endMs': null},
          {'text': 'hello', 'startMs': 1200, 'endMs': 1500},
          {'text': 'again', 'startMs': 4900, 'endMs': 5500},
        ],
      }, 5000);
      expect(transcript.words.map((w) => w.text), [
        'नमस्ते',
        'दोस्त',
        'hello',
        'again',
      ]);
      expect(transcript.words.map((w) => w.aligned), [
        true,
        false,
        false,
        false,
      ]);
      expect(() => transcriptMute(transcript, 0, 1, 5000), throwsStateError);
      expect(
        () => transcriptMute(transcript, -1, 1, 5000),
        throwsArgumentError,
      );
    },
  );
}
