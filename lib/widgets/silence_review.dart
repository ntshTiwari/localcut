import '../core/context_preview.dart';
import '../core/pause_review.dart';
import '../editor/pause_review_screen.dart';
import 'package:flutter/material.dart';
import '../core/edit_plan.dart';
import '../core/silence_detection.dart';
import '../media/media_engine.dart';
import 'waveform_editor.dart';

class SilenceReview extends StatefulWidget {
  const SilenceReview({
    super.key,
    required this.engine,
    required this.source,
    required this.enabled,
    required this.edits,
    required this.onApply,
    required this.onBusyChanged,
    this.analysis,
    this.onAnalysis,
    this.collapseAdvanced = false,
    this.pauseSession,
    this.onOpenPauseReview,
  });
  final PauseReviewSession? pauseSession;
  final VoidCallback? onOpenPauseReview;
  final bool collapseAdvanced;
  final MediaEngine engine;
  final SourceVideo source;
  final bool enabled;
  final List<EditRange> edits;
  final ValueChanged<List<EditRange>> onApply;
  final ValueChanged<bool> onBusyChanged;
  final AudioAnalysis? analysis;
  final ValueChanged<AudioAnalysis>? onAnalysis;
  @override
  State<SilenceReview> createState() => _SilenceReviewState();
}

class _SilenceReviewState extends State<SilenceReview> {
  AudioAnalysis? _analysis;
  late final _review = widget.pauseSession ?? PauseReviewSession();
  @override
  void dispose() {
    if (widget.pauseSession == null) _review.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _analysis = widget.analysis;
    _threshold = _review.settings.thresholdDb;
    _minimumPause = _review.settings.minimumPauseMs / 1000;
    _padding = _review.settings.paddingMs / 1000;
  }

  @override
  void didUpdateWidget(covariant SilenceReview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.analysis != null &&
        !identical(widget.analysis, oldWidget.analysis)) {
      _analysis = widget.analysis;
    }
  }

  double _threshold = -40;
  double _minimumPause = .8;
  double _padding = .15;
  String? _message;
  bool _working = false;
  bool _analyzing = false;
  bool _cancelRequested = false;

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
        _review.reset();
      });
      widget.onAnalysis?.call(result);
    }
  }, analyze: true);

  void _change(VoidCallback update) => setState(() {
    update();
    _review.reset();
    _review.settings = SilenceSettings(
      thresholdDb: _threshold,
      minimumPauseMs: (_minimumPause * 1000).round(),
      paddingMs: (_padding * 1000).round(),
    );
    _message = null;
  });

  Future<void> _openReview(List<EditRange> suggestions) async {
    widget.onOpenPauseReview?.call();
    _review.sync(suggestions);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PauseOverviewScreen(
          session: _review,
          source: widget.source,
          media: widget.engine,
          onApply: (cuts) {
            compilePlan(widget.source.durationMs, [...widget.edits, ...cuts]);
            widget.onApply(cuts);
          },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _advanced(String title, String detail, Widget child) =>
      widget.collapseAdvanced
      ? ExpansionTile(
          title: Text(title),
          subtitle: Text(detail),
          childrenPadding: const EdgeInsets.symmetric(vertical: 12),
          children: [child],
        )
      : child;

  @override
  Widget build(BuildContext context) {
    final suggestions = _suggestions;
    final removableMs = suggestions.fold<int>(
      0,
      (sum, e) => sum + e.endMs - e.startMs,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Audio analysis', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        const Text(
          'Analyze once to display the waveform and find quiet sections. All processing stays on this device.',
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
          if (_analysis!.hasAudio && _analysis!.windows.isNotEmpty)
            _advanced(
              'Waveform editor',
              'Open precise drag and edge controls',
              WaveformEditor(
                key: ValueKey('waveform-${widget.source.path}'),
                analysis: _analysis!,
                durationMs: widget.source.durationMs,
                edits: widget.edits,
                suggestions: suggestions,
                enabled: _enabled,
                onHear: (start, end) => _perform(
                  () => widget.engine.preview(widget.source.path, [
                    RenderSegment(start, end, false),
                  ]),
                ),
                onContext: (edit, edited) => _perform(
                  () => widget.engine.preview(
                    widget.source.path,
                    contextPreview(
                      widget.source.durationMs,
                      edit.startMs,
                      edit.endMs,
                      remove: edited && edit.kind == EditKind.cut,
                      mute: edited && edit.kind == EditKind.mute,
                    ),
                    label: contextLabel(
                      remove: edited && edit.kind == EditKind.cut,
                      mute: edited && edit.kind == EditKind.mute,
                    ),
                  ),
                ),
                onPreview: (edit) => _perform(
                  () => widget.engine.preview(
                    widget.source.path,
                    compilePlan(widget.source.durationMs, [
                      ...widget.edits,
                      edit,
                    ]),
                  ),
                ),
                onAdd: (edit) {
                  widget.onApply([edit]);
                  setState(() => _message = null);
                },
              ),
            ),
          _advanced(
            'Detection settings',
            'Adjust quietness and pause length',
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Find long pauses',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text('Quietness threshold: ${_threshold.round()} dBFS'),
                Slider(
                  key: const Key('threshold'),
                  value: _threshold,
                  min: -60,
                  max: -20,
                  divisions: 40,
                  label: '${_threshold.round()} dBFS',
                  onChanged: _enabled
                      ? (v) => _change(() => _threshold = v)
                      : null,
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
                  onChanged: _enabled
                      ? (v) => _change(() => _padding = v)
                      : null,
                ),
                const Text(
                  'Settings reuse the analysis. Changing them clears pause-review decisions; edits already added stay in place.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Suggested pauses',
            style: Theme.of(context).textTheme.titleLarge,
          ),
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
              '${suggestions.length} suggested pauses · ${pauseDuration(removableMs)} removable',
            ),
            const SizedBox(height: 8),
            const Text(
              'Review one pause at a time, or mark several in a compact overview.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _enabled ? () => _openReview(suggestions) : null,
              icon: const Icon(Icons.playlist_play),
              label: const Text('Review suggested pauses'),
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
