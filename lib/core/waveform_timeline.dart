import 'dart:math' as math;
import 'silence_detection.dart';

/// A visible interval on the original source timeline, never edited time.
class WaveformViewport {
  WaveformViewport(this.totalMs, this.startMs, this.endMs) {
    if (totalMs <= 0 || startMs < 0 || endMs > totalMs || startMs >= endMs) {
      throw ArgumentError('Invalid waveform viewport.');
    }
  }
  factory WaveformViewport.full(int durationMs) =>
      WaveformViewport(durationMs, 0, durationMs);
  final int totalMs;
  final int startMs;
  final int endMs;
  int get spanMs => endMs - startMs;
  double get zoom => totalMs / spanMs;
  int timeAt(double fraction) =>
      (startMs + fraction.clamp(0.0, 1.0) * spanMs).round();
  double fractionAt(int timeMs) => (timeMs - startMs) / spanMs;

  WaveformViewport zoomBy(double factor, int focusMs) {
    if (!factor.isFinite || factor <= 0) {
      throw ArgumentError('Invalid zoom factor.');
    }
    final minimum = math.min(250, totalMs);
    final span = (spanMs / factor).round().clamp(minimum, totalMs);
    // Keep the focused source position at the same screen fraction while zooming.
    final focus = focusMs.clamp(startMs, endMs);
    final fraction = fractionAt(focus);
    final start = (focus - fraction * span).round().clamp(0, totalMs - span);
    return WaveformViewport(totalMs, start, start + span);
  }

  WaveformViewport moveTo(int start) {
    final clamped = start.clamp(0, totalMs - spanMs);
    return WaveformViewport(totalMs, clamped, clamped + spanMs);
  }
}

class WaveformSelection {
  const WaveformSelection(this.startMs, this.endMs);
  final int startMs;
  final int endMs;
  static int minimumLength(int durationMs) => math.min(20, durationMs);

  factory WaveformSelection.between(int a, int b, int durationMs) {
    if (durationMs <= 0) throw ArgumentError('Invalid source duration.');
    final minimum = minimumLength(durationMs);
    final start = math.min(a, b).clamp(0, durationMs - minimum);
    final end = math.max(a, b).clamp(start + minimum, durationMs);
    return WaveformSelection(start, end);
  }

  WaveformSelection resizeStart(int value, int durationMs) => WaveformSelection(
    value.clamp(0, endMs - minimumLength(durationMs)),
    endMs,
  );
  WaveformSelection resizeEnd(int value, int durationMs) => WaveformSelection(
    startMs,
    value.clamp(startMs + minimumLength(durationMs), durationMs),
  );
}

/// One loudest measurement per display column. Null columns have no measured
/// audio. Aggregating to screen resolution bounds drawing work for long clips.
List<double?> waveformBins(
  List<AudioWindow> windows,
  WaveformViewport viewport,
  int count,
) {
  if (count <= 0) throw ArgumentError('Waveform bin count must be positive.');
  final bins = List<double?>.filled(count, null);
  for (final window in windows) {
    if (window.endMs <= viewport.startMs) continue;
    if (window.startMs >= viewport.endMs) break;
    final first = (viewport.fractionAt(window.startMs) * count).floor().clamp(
      0,
      count - 1,
    );
    final last = (viewport.fractionAt(window.endMs) * count).ceil().clamp(
      1,
      count,
    );
    for (var i = first; i < last; i++) {
      bins[i] = bins[i] == null ? window.db : math.max(bins[i]!, window.db);
    }
  }
  return bins;
}
