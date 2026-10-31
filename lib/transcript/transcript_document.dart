import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/edit_plan.dart';
import 'transcript.dart';
import 'transcript_gaps.dart';

class TranscriptDocument extends StatelessWidget {
  const TranscriptDocument({
    super.key,
    required this.transcript,
    required this.gaps,
    required this.edits,
    required this.enabled,
    required this.onWord,
    required this.onGap,
    this.firstWord,
    this.lastWord,
    this.selectedGap,
  });
  final VideoTranscript transcript;
  final List<TranscriptGap> gaps;
  final List<EditRange> edits;
  final bool enabled;
  final ValueChanged<int> onWord;
  final ValueChanged<TranscriptGap> onGap;
  final int? firstWord;
  final int? lastWord;
  final int? selectedGap;

  Widget _word(BuildContext context, int index) {
    final word = transcript.words[index];
    final colors = Theme.of(context).colorScheme;
    final selected =
        firstWord != null && index >= firstWord! && index <= lastWord!;
    final cut =
        word.aligned &&
        coveredMilliseconds(edits, word.startMs!, word.endMs!, EditKind.cut) >
            0;
    final censored =
        word.aligned &&
        coveredMilliseconds(edits, word.startMs!, word.endMs!, EditKind.mute) >
            0;
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${word.text}${censored ? ', censored' : ''}${cut ? ', trimmed' : ''}${!word.aligned ? ', timing unavailable' : ''}',
      child: InkWell(
        key: ValueKey('transcript-word-$index'),
        onTap: enabled ? () => onWord(index) : null,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? colors.primaryContainer
                : censored
                ? colors.secondaryContainer
                : null,
            border: Border(
              bottom: BorderSide(
                color: selected ? colors.primary : Colors.transparent,
                width: 2,
              ),
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text.rich(
            TextSpan(
              children: [
                if (censored)
                  const WidgetSpan(
                    child: Padding(
                      padding: EdgeInsets.only(right: 3),
                      child: Icon(Icons.volume_off_outlined, size: 13),
                    ),
                  ),
                TextSpan(text: word.text),
              ],
            ),
            style: TextStyle(
              fontSize: 17,
              height: 1.35,
              color: word.aligned ? colors.onSurface : colors.outline,
              decoration: cut ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _gap(BuildContext context, TranscriptGap gap) {
    final colors = Theme.of(context).colorScheme;
    final removed = coveredMilliseconds(
      edits,
      gap.scopeStart,
      gap.scopeEnd,
      EditKind.cut,
    );
    final label =
        '${gap.confirmed ? 'Pause' : 'Gap'} ${seconds(gap.durationMs)}${removed > 0 ? ' → ${seconds(gap.durationMs - removed)}' : ''}';
    final selected = selectedGap == gap.beforeWord;
    // Duration adds a little width, capped so long pauses never break layout.
    final extra = (gap.durationMs / 1000 * 3).clamp(0.0, 12.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: Semantics(
        button: true,
        selected: selected,
        label:
            '$label${gap.confirmed ? ', verified quiet audio' : ', silence not confirmed'}',
        child: ActionChip(
          key: ValueKey('transcript-gap-${gap.beforeWord}'),
          avatar: Icon(
            removed > 0
                ? Icons.content_cut
                : gap.confirmed
                ? Icons.pause
                : Icons.more_horiz,
            size: 16,
            color: selected ? colors.primary : colors.onSurfaceVariant,
          ),
          label: Text(
            label,
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
          labelPadding: EdgeInsets.symmetric(horizontal: 2 + extra),
          backgroundColor: selected
              ? colors.primaryContainer
              : colors.surfaceContainerHighest,
          side: BorderSide(
            color: selected ? colors.primary : colors.outlineVariant,
          ),
          onPressed: enabled ? () => onGap(gap) : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final byWord = {for (final gap in gaps) gap.beforeWord: gap};
    return ListView.builder(
      shrinkWrap: true,
      primary: false,
      physics: const NeverScrollableScrollPhysics(),
      key: const Key('transcript-text'),
      itemCount: (transcript.words.length / 25).ceil(),
      itemBuilder: (context, paragraph) {
        final start = paragraph * 25,
            end = math.min(start + 25, transcript.words.length);
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Wrap(
            spacing: 1,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = start; i < end; i++) ...[
                if (byWord[i] != null) _gap(context, byWord[i]!),
                _word(context, i),
              ],
            ],
          ),
        );
      },
    );
  }
}
