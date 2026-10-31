import '../widgets/time_range_playback.dart';
import 'package:flutter/material.dart';

/// Actions describe a temporary selection. The main screen hosts this bar
/// above its persistent Review button, outside the scrolling transcript.
class TranscriptActions {
  const TranscriptActions({
    required this.title,
    required this.detail,
    required this.onClear,
    this.onHear,
    this.onHearRemoved,
    this.contextMute = false,
    this.startMs,
    this.endMs,
    this.onPlayRange,
    this.onCensor,
    this.onShorten,
    this.onRestore,
    this.onPhrase,
    this.choosingPhrase = false,
  });
  final bool contextMute;
  final int? startMs, endMs;
  final VoidCallback? onPlayRange;
  final String title;
  final String detail;
  final VoidCallback onClear;
  final VoidCallback? onHear;
  final VoidCallback? onHearRemoved;
  final VoidCallback? onCensor;
  final VoidCallback? onShorten;
  final VoidCallback? onRestore;
  final VoidCallback? onPhrase;
  final bool choosingPhrase;
}

class TranscriptActionBar extends StatelessWidget {
  const TranscriptActionBar({
    super.key,
    required this.actions,
    required this.enabled,
  });
  final TranscriptActions actions;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              actions.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          IconButton(
            tooltip: 'Clear selection',
            onPressed: enabled ? actions.onClear : null,
            icon: const Icon(Icons.close),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
      if (actions.startMs != null && actions.endMs != null)
        TimeRangePlayback(
          startMs: actions.startMs!,
          endMs: actions.endMs!,
          onPlay: enabled ? actions.onPlayRange : null,
        ),
      Text(
        actions.detail,
        style: Theme.of(context).textTheme.bodySmall,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          if (actions.onHear != null)
            ContextPlaybackButtons(
              mute: actions.contextMute,
              onKeep: enabled ? actions.onHear : null,
              onRemove: enabled ? actions.onHearRemoved : null,
            ),
          if (actions.onCensor != null)
            FilledButton.icon(
              onPressed: enabled ? actions.onCensor : null,
              icon: const Icon(Icons.volume_off_outlined, size: 18),
              label: const Text('Censor'),
            ),
          if (actions.onShorten != null)
            FilledButton.icon(
              onPressed: enabled ? actions.onShorten : null,
              icon: const Icon(Icons.content_cut, size: 18),
              label: const Text('Shorten pause'),
            ),
          if (actions.onPhrase != null)
            TextButton(
              onPressed: enabled ? actions.onPhrase : null,
              child: Text(
                actions.choosingPhrase
                    ? 'Cancel phrase selection'
                    : 'Select phrase',
              ),
            ),
          if (actions.onRestore != null)
            TextButton.icon(
              onPressed: enabled ? actions.onRestore : null,
              icon: const Icon(Icons.undo, size: 18),
              label: const Text('Restore'),
            ),
        ],
      ),
    ],
  );
}
