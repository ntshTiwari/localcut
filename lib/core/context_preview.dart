import 'dart:math' as math;
import 'edit_plan.dart';

/// Compare one decision in isolation, using the same original context bounds.
List<RenderSegment> contextPreview(
  int durationMs,
  int startMs,
  int endMs, {
  bool remove = false,
  bool mute = false,
  int? effectStartMs,
  int? effectEndMs,
}) {
  final start = math.max(0, startMs - 1000),
      end = math.min(durationMs, endMs + 1000);
  if (startMs < 0 || endMs > durationMs || startMs >= endMs) {
    throw ArgumentError('Invalid preview range.');
  }
  if (!remove && !mute) return [RenderSegment(start, end, false)];
  final a = effectStartMs ?? startMs, b = effectEndMs ?? endMs;
  if (a < startMs || b > endMs || a >= b) {
    throw ArgumentError('Invalid effect range.');
  }
  final result = <RenderSegment>[
    if (start < a) RenderSegment(start, a, false),
    if (!remove) RenderSegment(a, b, mute),
    if (b < end) RenderSegment(b, end, false),
  ];
  if (result.isEmpty) {
    throw ArgumentError('No surrounding video remains to preview.');
  }
  return result;
}

String contextLabel({bool remove = false, bool mute = false}) => mute
    ? 'Context · censored'
    : remove
    ? 'Context · without section'
    : 'Context · with section';
