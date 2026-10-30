enum EditKind { cut, mute }

class EditRange {
  const EditRange(this.startMs, this.endMs, this.kind, {this.label});
  final int startMs;
  final int endMs;
  final EditKind kind;
  final String? label;
}

class RenderSegment {
  const RenderSegment(this.startMs, this.endMs, this.muted);
  final int startMs;
  final int endMs;
  final bool muted;
  Map<String, Object> toMap() => {
    'startMs': startMs,
    'endMs': endMs,
    'muted': muted,
  };
}

/// Splits original source time into retained segments. Cuts win over mutes.
List<RenderSegment> compilePlan(int durationMs, List<EditRange> edits) {
  if (durationMs <= 0) throw ArgumentError('Video duration must be positive.');
  final boundaries = <int>{0, durationMs};
  for (final edit in edits) {
    if (edit.startMs < 0 ||
        edit.endMs > durationMs ||
        edit.startMs >= edit.endMs) {
      throw ArgumentError(
        'Every edit must be inside the video with start < end.',
      );
    }
    boundaries.addAll([edit.startMs, edit.endMs]);
  }
  final sorted = boundaries.toList()..sort();
  final result = <RenderSegment>[];
  for (var i = 0; i < sorted.length - 1; i++) {
    final start = sorted[i];
    final end = sorted[i + 1];
    final active = edits.where((e) => e.startMs < end && e.endMs > start);
    if (active.any((e) => e.kind == EditKind.cut)) continue;
    final muted = active.any((e) => e.kind == EditKind.mute);
    if (result.isNotEmpty &&
        result.last.endMs == start &&
        result.last.muted == muted) {
      final previous = result.removeLast();
      result.add(RenderSegment(previous.startMs, end, muted));
    } else {
      result.add(RenderSegment(start, end, muted));
    }
  }
  if (result.isEmpty) throw ArgumentError('Keep at least part of the video.');
  return result;
}
