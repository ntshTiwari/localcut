import 'package:flutter/material.dart';

/// Icon + short label avoids ambiguous icon-only comparison controls.
/// Pressing the active choice again replays it.
class CompactPreviewSwitch extends StatefulWidget {
  const CompactPreviewSwitch({
    super.key,
    this.onSection,
    required this.onOriginal,
    required this.onEdited,
    this.mute = false,
    this.enabled = true,
  });
  final VoidCallback? onSection, onOriginal, onEdited;
  final bool mute, enabled;
  @override
  State<CompactPreviewSwitch> createState() => _CompactPreviewSwitchState();
}

class _CompactPreviewSwitchState extends State<CompactPreviewSwitch> {
  int? _selected;
  @override
  void didUpdateWidget(covariant CompactPreviewSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mute != widget.mute) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final options =
        <({String label, String hint, IconData icon, VoidCallback? action})>[
          if (widget.onSection != null)
            (
              label: 'Section',
              hint: 'Play only this original section',
              icon: Icons.play_arrow,
              action: widget.onSection,
            ),
          (
            label: 'Original',
            hint: 'Play context with the section kept',
            icon: Icons.compare_arrows,
            action: widget.onOriginal,
          ),
          (
            label: widget.mute ? 'Censored' : 'Trimmed',
            hint: widget.mute
                ? 'Play context with the section muted'
                : 'Play context with the section removed',
            icon: widget.mute ? Icons.volume_off_outlined : Icons.content_cut,
            action: widget.onEdited,
          ),
        ];
    return LayoutBuilder(
      builder: (context, constraints) => ToggleButtons(
        borderRadius: BorderRadius.circular(12),
        constraints: BoxConstraints(
          minWidth:
              (constraints.maxWidth - options.length - 1) / options.length,
          maxWidth:
              (constraints.maxWidth - options.length - 1) / options.length,
          minHeight: 52,
        ),
        isSelected: List.generate(options.length, (i) => i == _selected),
        onPressed: !widget.enabled || options.every((o) => o.action == null)
            ? null
            : (i) {
                if (options[i].action == null) return;
                setState(() => _selected = i);
                options[i].action!();
              },
        children: [
          for (final o in options)
            Tooltip(
              message: o.hint,
              child: Padding(
                key: ValueKey('preview-mode-${o.label}'),
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(o.icon, size: 18),
                    Text(o.label, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
