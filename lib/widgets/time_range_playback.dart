import 'compact_preview_switch.dart';
import 'package:flutter/material.dart';

/// Source timestamps always describe the unedited recording.
String rangeTimestamp(int ms) {
  final minutes = ms ~/ 60000;
  final seconds = (ms % 60000) ~/ 1000;
  final fraction = (ms % 1000).toString().padLeft(3, '0');
  return '$minutes:${seconds.toString().padLeft(2, '0')}.$fraction';
}

/// A full-size accessible play target immediately beside a wrapping time range.
class TimeRangePlayback extends StatelessWidget {
  const TimeRangePlayback({
    super.key,
    required this.startMs,
    required this.endMs,
    required this.onPlay,
    this.label,
    this.onContext,
    this.onContextRemoved,
    this.mute = false,
    this.showContext = false,
  });
  final int startMs, endMs;
  final VoidCallback? onPlay;
  final String? label;
  final VoidCallback? onContext, onContextRemoved;
  final bool mute, showContext;
  @override
  Widget build(BuildContext context) {
    final range = '${rangeTimestamp(startMs)} – ${rangeTimestamp(endMs)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                label ?? range,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            IconButton(
              tooltip: 'Play original $range',
              onPressed: onPlay,
              icon: const Icon(Icons.play_circle_outline),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
          ],
        ),
        if (showContext || onContext != null || onContextRemoved != null)
          ContextPlaybackButtons(
            onKeep: onContext,
            onRemove: onContextRemoved,
            mute: mute,
          ),
      ],
    );
  }
}

class ContextPlaybackButtons extends StatelessWidget {
  const ContextPlaybackButtons({
    super.key,
    this.onKeep,
    this.onRemove,
    this.mute = false,
  });
  final VoidCallback? onKeep, onRemove;
  final bool mute;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Hear context', style: TextStyle(fontSize: 12)),
      CompactPreviewSwitch(onOriginal: onKeep, onEdited: onRemove, mute: mute),
    ],
  );
}
