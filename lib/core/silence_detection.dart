import 'edit_plan.dart';

/// A measured window on the original source timeline, in dBFS. The native
/// adapter reports the loudest channel's RMS so stereo speech is preserved.
class AudioWindow {
  const AudioWindow(this.startMs, this.endMs, this.db);
  final int startMs;
  final int endMs;
  final double db;
}

class AudioAnalysis {
  const AudioAnalysis(this.windows, {required this.hasAudio});
  final List<AudioWindow> windows;
  final bool hasAudio;
}

class SilenceSettings {
  const SilenceSettings({
    this.thresholdDb = -40,
    this.minimumPauseMs = 800,
    this.paddingMs = 150,
  });
  final double thresholdDb;
  final int minimumPauseMs;

  /// Retained on each side of a quiet run to protect speech boundaries.
  final int paddingMs;
}

/// Conservative volume-based suggestions, not speech recognition. Unknown
/// gaps never count as silence. A completely quiet source has no speech anchor
/// and produces no automatic cuts. Nothing is applied by this function.
List<EditRange> detectSilence(
  AudioAnalysis analysis,
  int durationMs,
  SilenceSettings settings,
) {
  if (durationMs <= 0 ||
      !settings.thresholdDb.isFinite ||
      settings.minimumPauseMs <= 0 ||
      settings.paddingMs < 0) {
    throw ArgumentError('Invalid silence detection settings.');
  }
  final windows = analysis.windows;
  if (!analysis.hasAudio || windows.isEmpty) return [];
  var previousEnd = 0;
  for (final w in windows) {
    if (!w.db.isFinite ||
        w.startMs < previousEnd ||
        w.endMs <= w.startMs ||
        w.endMs > durationMs) {
      throw ArgumentError('Invalid or unordered audio analysis windows.');
    }
    previousEnd = w.endMs;
  }
  if (!windows.any((w) => w.db > settings.thresholdDb)) return [];
  final result = <EditRange>[];
  int? quietStart;
  var quietEnd = 0;
  void finishRun() {
    if (quietStart != null &&
        quietEnd - quietStart! >= settings.minimumPauseMs) {
      final start = quietStart! + settings.paddingMs;
      final end = quietEnd - settings.paddingMs;
      if (end > start) result.add(EditRange(start, end, EditKind.cut));
    }
    quietStart = null;
  }

  for (final w in windows) {
    if (w.db > settings.thresholdDb) {
      finishRun();
    } else {
      if (quietStart != null && w.startMs > quietEnd) finishRun();
      quietStart ??= w.startMs;
      quietEnd = w.endMs;
    }
  }
  finishRun();
  return result;
}
