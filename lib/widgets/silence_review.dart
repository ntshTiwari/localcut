import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/edit_plan.dart';
import '../core/silence_detection.dart';
import '../media/media_engine.dart';

class SilenceReview extends StatefulWidget {
  const SilenceReview({
    super.key,
    required this.engine,
    required this.source,
    required this.enabled,
    required this.edits,
    required this.onApply,
    required this.onBusyChanged,
  });
  final MediaEngine engine;
  final SourceVideo source;
  final bool enabled;
  final List<EditRange> edits;
  final ValueChanged<List<EditRange>> onApply;
  final ValueChanged<bool> onBusyChanged;
  @override
  State<SilenceReview> createState() => _SilenceReviewState();
}

class _SilenceReviewState extends State<SilenceReview> {
  AudioAnalysis? _analysis;
  double _threshold = -40;
  double _minimumPause = .8;
  double _padding = .15;
  final Set<String> _selected = {};
  String? _message;
  bool _working = false;
  bool _analyzing = false;
  bool _cancelRequested = false;

  String _id(EditRange e) => '${e.startMs}:${e.endMs}';
  List<EditRange> get _suggestions => _analysis == null
      ? []
      : detectSilence(
              _analysis!,
              widget.source.durationMs,
              SilenceSettings(
                thresholdDb: _threshold,
                minimumPauseMs: (_minimumPause * 1000).round(),
                paddingMs: (_padding * 1000).round(),
              ),
            )
            .where(
              (candidate) => !widget.edits.any(
                (edit) =>
                    edit.kind == EditKind.cut &&
                    edit.startMs <= candidate.startMs &&
                    edit.endMs >= candidate.endMs,
              ),
            )
            .toList();
  List<EditRange> get _chosen =>
      _suggestions.where((e) => _selected.contains(_id(e))).toList();
  bool get _enabled => widget.enabled && !_working;

  Future<void> _perform(
    Future<void> Function() action, {
    bool analyze = false,
  }) async {
    setState(() {
      _working = true;
      _analyzing = analyze;
      _cancelRequested = false;
      _message = null;
    });
    widget.onBusyChanged(true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = _cancelRequested
              ? 'Analysis canceled. Your edits are unchanged.'
              : error.toString(),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _analyzing = false;
        });
        widget.onBusyChanged(false);
      }
    }
  }

  Future<void> _analyze() => _perform(() async {
    final result = await widget.engine.analyzeAudio(widget.source.path);
    if (mounted && !_cancelRequested) {
      setState(() {
        _analysis = result;
        _selected.clear();
      });
    }
  }, analyze: true);

  void _change(VoidCallback update) => setState(() {
    update();
    _selected.clear();
    _message = null;
  });

  Future<void> _previewSelected() => _perform(() async {
    final plan = compilePlan(widget.source.durationMs, [
      ...widget.edits,
      ..._chosen,
    ]);
    await widget.engine.preview(widget.source.path, plan);
  });

  Future<void> _hear(EditRange cut) => _perform(
    () => widget.engine.preview(widget.source.path, [
      RenderSegment(
        math.max(0, cut.startMs - 700),
        math.min(widget.source.durationMs, cut.endMs + 700),
        false,
      ),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final suggestions = _suggestions;
    final chosen = _chosen;
    final selectedMs = chosen.fold<int>(
      0,
      (sum, e) => sum + e.endMs - e.startMs,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Find long pauses', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        const Text(
          'Find quiet sections on this device. Listen and select the cuts you want; nothing is added automatically.',
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: _enabled ? _analyze : null,
          icon: const Icon(Icons.graphic_eq),
          label: Text(_analysis == null ? 'Analyze audio' : 'Analyze again'),
        ),
        if (_analyzing) ...[
          const LinearProgressIndicator(),
          const Text('Analyzing audio locally…'),
          TextButton(
            onPressed: _cancelRequested
                ? null
                : () async {
                    setState(() => _cancelRequested = true);
                    try {
                      await widget.engine.cancelAnalysis();
                    } catch (error) {
                      if (mounted) {
                        setState(() {
                          _cancelRequested = false;
                          _message = error.toString();
                        });
                      }
                    }
                  },
            child: const Text('Cancel analysis'),
          ),
        ],
        if (_analysis != null) ...[
          const SizedBox(height: 12),
          Text('Quietness threshold: ${_threshold.round()} dBFS'),
          Slider(
            key: const Key('threshold'),
            value: _threshold,
            min: -60,
            max: -20,
            divisions: 40,
            label: '${_threshold.round()} dBFS',
            onChanged: _enabled ? (v) => _change(() => _threshold = v) : null,
          ),
          const Text(
            'A higher threshold includes louder pauses. Quiet speech can also be selected.',
          ),
          const SizedBox(height: 8),
          Text('Minimum pause: ${_minimumPause.toStringAsFixed(1)} s'),
          Slider(
            key: const Key('minimum-pause'),
            value: _minimumPause,
            min: .4,
            max: 2,
            divisions: 16,
            label: '${_minimumPause.toStringAsFixed(1)} s',
            onChanged: _enabled
                ? (v) => _change(() => _minimumPause = v)
                : null,
          ),
          Text('Keep around each edge: ${(_padding * 1000).round()} ms'),
          Slider(
            key: const Key('pause-padding'),
            value: _padding,
            min: .05,
            max: .3,
            divisions: 5,
            label: '${(_padding * 1000).round()} ms',
            onChanged: _enabled ? (v) => _change(() => _padding = v) : null,
          ),
          const Text(
            'Settings reuse the analysis. Changing them clears your selection; edits already added stay in place.',
          ),
          const SizedBox(height: 12),
          if (!_analysis!.hasAudio)
            const Text(
              'This video has no audio track. No silence cuts were suggested.',
            )
          else if (suggestions.isEmpty)
            const Text(
              'No new pauses found at these settings. Lower the minimum pause or raise the threshold. Entirely quiet recordings are left unchanged.',
            )
          else ...[
            Text(
              '${suggestions.length} suggested cuts · ${(selectedMs / 1000).toStringAsFixed(2)} s selected',
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _enabled
                      ? () => setState(
                          () => _selected.addAll(suggestions.map(_id)),
                        )
                      : null,
                  child: const Text('Select all'),
                ),
                TextButton(
                  onPressed: _enabled && chosen.isNotEmpty
                      ? () => setState(_selected.clear)
                      : null,
                  child: const Text('Clear selection'),
                ),
              ],
            ),
            // Bounded, lazy list keeps long recordings from building every row.
            SizedBox(
              height: math.min(280, suggestions.length * 80).toDouble(),
              child: ListView.builder(
                key: const Key('silence-suggestions'),
                itemCount: suggestions.length,
                itemBuilder: (context, index) {
                  final cut = suggestions[index];
                  return Row(
                    children: [
                      Expanded(
                        child: CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: _selected.contains(_id(cut)),
                          title: Text(
                            '${(cut.startMs / 1000).toStringAsFixed(2)} – ${(cut.endMs / 1000).toStringAsFixed(2)} s',
                          ),
                          subtitle: Text(
                            'Cut ${((cut.endMs - cut.startMs) / 1000).toStringAsFixed(2)} s',
                          ),
                          onChanged: _enabled
                              ? (value) => setState(() {
                                  value == true
                                      ? _selected.add(_id(cut))
                                      : _selected.remove(_id(cut));
                                })
                              : null,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Hear original context',
                        onPressed: _enabled ? () => _hear(cut) : null,
                        icon: const Icon(Icons.play_circle_outline),
                      ),
                    ],
                  );
                },
              ),
            ),
            OutlinedButton(
              onPressed: _enabled && chosen.isNotEmpty
                  ? _previewSelected
                  : null,
              child: const Text('Preview selected silence cuts'),
            ),
            FilledButton(
              onPressed: _enabled && chosen.isNotEmpty
                  ? () {
                      try {
                        compilePlan(widget.source.durationMs, [
                          ...widget.edits,
                          ...chosen,
                        ]);
                        widget.onApply(chosen);
                        setState(() {
                          _selected.clear();
                          _message = null;
                        });
                      } catch (error) {
                        setState(() => _message = error.toString());
                      }
                    }
                  : null,
              child: const Text('Add selected cuts to edits'),
            ),
          ],
        ],
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_message!),
          ),
      ],
    );
  }
}
