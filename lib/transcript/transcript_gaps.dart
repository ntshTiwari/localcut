import 'dart:math' as math;
import '../core/edit_plan.dart';
import '../core/silence_detection.dart';
import 'transcript.dart';

/// A gap between two adjacent aligned words. Only measured quiet audio can
/// become a pause cut; a timestamp gap alone is never evidence of silence.
class TranscriptGap {
  const TranscriptGap({
    required this.beforeWord,
    required this.startMs,
    required this.endMs,
    this.quietStartMs,
    this.quietEndMs,
  });
  final int beforeWord;
  final int startMs;
  final int endMs;
  final int? quietStartMs;
  final int? quietEndMs;
  bool get confirmed => quietStartMs != null && quietEndMs != null;
  int get scopeStart => quietStartMs ?? startMs;
  int get scopeEnd => quietEndMs ?? endMs;
  int get durationMs => scopeEnd - scopeStart;

  EditRange shorten({int keepMs = 300}) {
    if (!confirmed) {
      throw StateError(
        'Listen to this gap or use Fine-tune timing. Silence has not been confirmed.',
      );
    }
    if (keepMs < 0 || keepMs >= durationMs) {
      throw ArgumentError('Keep less than the pause duration.');
    }
    final before = keepMs ~/ 2;
    return EditRange(
      scopeStart + before,
      scopeEnd - (keepMs - before),
      EditKind.cut,
      label: 'Shorten pause (${seconds(durationMs)} → ${seconds(keepMs)})',
    );
  }
}

String seconds(int ms) => '${(ms / 1000).toStringAsFixed(1)}s';

List<TranscriptGap> transcriptGaps(
  VideoTranscript transcript,
  int durationMs,
  AudioAnalysis? analysis, {
  int minimumMs = 500,
}) {
  final quiet = analysis == null
      ? <EditRange>[]
      : detectSilence(
          analysis,
          durationMs,
          SilenceSettings(minimumPauseMs: minimumMs, paddingMs: 0),
        );
  final gaps = <TranscriptGap>[];
  var quietIndex = 0;
  for (var i = 1; i < transcript.words.length; i++) {
    final previous = transcript.words[i - 1], next = transcript.words[i];
    if (!previous.aligned || !next.aligned) continue;
    final start = previous.endMs!, end = next.startMs!;
    if (start < 0 || end > durationMs || end - start < minimumMs) continue;
    while (quietIndex < quiet.length && quiet[quietIndex].endMs <= start) {
      quietIndex++;
    }
    int? quietStart, quietEnd;
    for (var j = quietIndex; j < quiet.length && quiet[j].startMs < end; j++) {
      final left = math.max(start, quiet[j].startMs),
          right = math.min(end, quiet[j].endMs);
      if (right - left >= minimumMs &&
          (quietStart == null || right - left > quietEnd! - quietStart)) {
        quietStart = left;
        quietEnd = right;
      }
    }
    gaps.add(
      TranscriptGap(
        beforeWord: i,
        startMs: start,
        endMs: end,
        quietStartMs: quietStart,
        quietEndMs: quietEnd,
      ),
    );
  }
  return gaps;
}

/// Measures the union, so overlapping edits are never counted twice.
int coveredMilliseconds(
  List<EditRange> edits,
  int start,
  int end,
  EditKind kind,
) {
  final intervals =
      edits
          .where((e) => e.kind == kind && e.startMs < end && e.endMs > start)
          .map((e) => (math.max(start, e.startMs), math.min(end, e.endMs)))
          .toList()
        ..sort((a, b) => a.$1.compareTo(b.$1));
  var covered = 0, cursor = start;
  for (final interval in intervals) {
    if (interval.$2 <= cursor) continue;
    covered += interval.$2 - math.max(cursor, interval.$1);
    cursor = interval.$2;
  }
  return covered;
}

/// Restore just the selected source interval, retaining other parts of a
/// larger edit. A split loses its old phrase label to avoid describing words
/// that were restored. A null kind restores both cuts and mutes.
List<EditRange> restoreEdits(
  List<EditRange> edits,
  int start,
  int end, {
  EditKind? kind,
}) {
  if (start < 0 || end <= start) {
    throw ArgumentError('Invalid restore interval.');
  }
  final result = <EditRange>[];
  for (final edit in edits) {
    if ((kind != null && edit.kind != kind) ||
        edit.endMs <= start ||
        edit.startMs >= end) {
      result.add(edit);
      continue;
    }
    if (edit.startMs < start) {
      result.add(EditRange(edit.startMs, start, edit.kind));
    }
    if (edit.endMs > end) result.add(EditRange(end, edit.endMs, edit.kind));
  }
  return result;
}
