import 'package:flutter/material.dart';
import '../core/edit_plan.dart';
import '../core/silence_detection.dart';
import '../media/media_engine.dart';
import '../widgets/silence_review.dart';

class FineTuneSheet extends StatefulWidget {
  const FineTuneSheet({
    super.key,
    required this.source,
    required this.media,
    required this.edits,
    required this.onApply,
    required this.onActivity,
    this.analysis,
    required this.onAnalysis,
  });
  final SourceVideo source;
  final MediaEngine media;
  final List<EditRange> edits;
  final ValueChanged<List<EditRange>> onApply;
  final ValueChanged<bool> onActivity;
  final AudioAnalysis? analysis;
  final ValueChanged<AudioAnalysis> onAnalysis;
  @override
  State<FineTuneSheet> createState() => _FineTuneSheetState();
}

class _FineTuneSheetState extends State<FineTuneSheet> {
  late AudioAnalysis? _analysis = widget.analysis;
  final _start = TextEditingController(), _end = TextEditingController();
  EditKind _kind = EditKind.cut;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  void _apply(List<EditRange> edits) {
    try {
      compilePlan(widget.source.durationMs, [...widget.edits, ...edits]);
      widget.onApply(edits);
      setState(() => _error = null);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  void _manual() {
    final start = double.tryParse(_start.text),
        end = double.tryParse(_end.text);
    if (start == null || end == null || !start.isFinite || !end.isFinite) {
      setState(() => _error = 'Enter a valid range in seconds.');
      return;
    }
    _apply([EditRange((start * 1000).round(), (end * 1000).round(), _kind)]);
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .82,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Fine-tune timing',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close timing tools',
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Text(
                'Work with original video time.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  children: [
                    SilenceReview(
                      key: ValueKey(widget.source.path),
                      engine: widget.media,
                      source: widget.source,
                      edits: widget.edits,
                      enabled: !_busy,
                      analysis: _analysis,
                      onAnalysis: (analysis) {
                        setState(() => _analysis = analysis);
                        widget.onAnalysis(analysis);
                      },
                      onBusyChanged: (busy) {
                        setState(() => _busy = busy);
                        widget.onActivity(busy);
                      },
                      onApply: _apply,
                    ),
                    const Divider(height: 32),
                    Text(
                      'Exact range',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<EditKind>(
                      segments: const [
                        ButtonSegment(value: EditKind.cut, label: Text('Trim')),
                        ButtonSegment(
                          value: EditKind.mute,
                          label: Text('Censor'),
                        ),
                      ],
                      selected: {_kind},
                      onSelectionChanged: _busy
                          ? null
                          : (value) => setState(() => _kind = value.first),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _start,
                            enabled: !_busy,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Start (seconds)',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _end,
                            enabled: !_busy,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'End (seconds)',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _busy ? null : _manual,
                      child: const Text('Add manual change'),
                    ),
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
