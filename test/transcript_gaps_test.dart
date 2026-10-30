import 'package:flutter_test/flutter_test.dart';
import 'package:localcut/core/edit_plan.dart';
import 'package:localcut/core/silence_detection.dart';
import 'package:localcut/transcript/transcript.dart';
import 'package:localcut/transcript/transcript_gaps.dart';

const transcript = VideoTranscript(TranscriptLanguage.english, [
  TranscriptWord('Hello', 0, 1000),
  TranscriptWord('friend', 3000, 3300),
]);
void main() {
  test('timestamp gaps alone never authorize a trim', () {
    final gap = transcriptGaps(transcript, 5000, null).single;
    expect([gap.startMs, gap.endMs], [1000, 3000]);
    expect(gap.confirmed, isFalse);
    expect(() => gap.shorten(), throwsStateError);
    final noisy = transcriptGaps(
      transcript,
      5000,
      const AudioAnalysis([AudioWindow(0, 5000, -10)], hasAudio: true),
    ).single;
    expect(noisy.confirmed, isFalse);
  });
  test('cut is restricted to confirmed quiet audio, with breathing room', () {
    final gap = transcriptGaps(
      transcript,
      5000,
      const AudioAnalysis([
        AudioWindow(0, 1200, -15),
        AudioWindow(1200, 2800, -80),
        AudioWindow(2800, 5000, -15),
      ], hasAudio: true),
    ).single;
    expect([gap.scopeStart, gap.scopeEnd], [1200, 2800]);
    final cut = gap.shorten();
    expect([cut.startMs, cut.endMs], [1350, 2650]);
    expect(cut.label, contains('1.6s → 0.3s'));
  });
  test('separated quiet runs do not trim through noise or unknown samples', () {
    final gap = transcriptGaps(
      transcript,
      5000,
      const AudioAnalysis([
        AudioWindow(0, 1000, -10),
        AudioWindow(1000, 1700, -80),
        AudioWindow(1700, 1900, -10),
        AudioWindow(2100, 3000, -80),
        AudioWindow(3000, 5000, -10),
      ], hasAudio: true),
    ).single;
    expect([gap.scopeStart, gap.scopeEnd], [2100, 3000]);
  });
  test('gaps next to unaligned words and short gaps are not invented', () {
    const words = VideoTranscript(TranscriptLanguage.english, [
      TranscriptWord('one', 0, 300),
      TranscriptWord('two', 500, 1000),
      TranscriptWord('unknown', null, null),
      TranscriptWord('four', 3000, 4000),
    ]);
    expect(transcriptGaps(words, 5000, null), isEmpty);
  });
  test('overlapping cuts count once in remaining pause duration', () {
    expect(
      coveredMilliseconds(
        const [
          EditRange(1000, 2000, EditKind.cut),
          EditRange(1500, 2500, EditKind.cut),
          EditRange(2500, 3000, EditKind.mute),
        ],
        1000,
        3000,
        EditKind.cut,
      ),
      1500,
    );
  });
  test(
    'restoring one word preserves the other portions of a phrase censor',
    () {
      final restored = restoreEdits(
        const [
          EditRange(0, 3000, EditKind.mute, label: 'Censor phrase'),
          EditRange(3500, 4000, EditKind.cut),
        ],
        1000,
        2000,
      );
      expect(restored.map((e) => [e.startMs, e.endMs, e.kind]).toList(), [
        [0, 1000, EditKind.mute],
        [2000, 3000, EditKind.mute],
        [3500, 4000, EditKind.cut],
      ]);
      expect(restored.first.label, isNull);
    },
  );
  test('restoring a pause affects cuts only, leaving manual mutes intact', () {
    final restored = restoreEdits(
      const [
        EditRange(1000, 3000, EditKind.cut),
        EditRange(1000, 3000, EditKind.mute),
      ],
      1000,
      3000,
      kind: EditKind.cut,
    );
    expect(restored.single.kind, EditKind.mute);
  });
}
