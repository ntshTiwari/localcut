import '../core/pause_review.dart';
import '../core/context_preview.dart';
import 'inline_preview.dart';
import 'playback_media_engine.dart';
import '../widgets/time_range_playback.dart';
import 'package:flutter/material.dart';
import '../core/edit_plan.dart';
import '../core/silence_detection.dart';
import '../media/media_engine.dart';
import '../widgets/silence_review.dart';

class TimingScreen extends StatefulWidget {
  const TimingScreen({
    super.key,
    required this.source,
    required this.media,
    required this.edits,
    required this.onApply,
    required this.onActivity,
    this.analysis,
    this.pauseSession,
    required this.onAnalysis,
  });
  final PauseReviewSession? pauseSession;
  final SourceVideo source;
  final MediaEngine media;
  final List<EditRange> edits;
  final ValueChanged<List<EditRange>> onApply;
  final ValueChanged<bool> onActivity;
  final AudioAnalysis? analysis;
  final ValueChanged<AudioAnalysis> onAnalysis;
  @override
  State<TimingScreen> createState() => _TimingScreenState();
}

class _TimingScreenState extends State<TimingScreen> {
  final _preview = InlinePreviewController();
  final _pageScroll = ScrollController();
  late final _media = PlaybackMediaEngine(
    widget.media,
    () async {},
    onPreview: _preview.show,
  );

  late AudioAnalysis? _analysis = widget.analysis;
  final _start = TextEditingController(), _end = TextEditingController();
  EditKind _kind = EditKind.cut;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _pageScroll.dispose();
    _preview.dispose();
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

  EditRange? get _manualRange {
    final start = double.tryParse(_start.text),
        end = double.tryParse(_end.text);
    if (start == null || end == null || !start.isFinite || !end.isFinite) {
      return null;
    }
    final a = (start * 1000).round(), b = (end * 1000).round();
    if (a < 0 || b > widget.source.durationMs || a >= b) return null;
    return EditRange(a, b, _kind);
  }

  Future<void> _playManual(
    EditRange range, {
    bool withContext = false,
    bool edited = false,
  }) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    widget.onActivity(true);
    try {
      await _media.preview(
        widget.source.path,
        withContext
            ? contextPreview(
                widget.source.durationMs,
                range.startMs,
                range.endMs,
                remove: edited && range.kind == EditKind.cut,
                mute: edited && range.kind == EditKind.mute,
              )
            : [RenderSegment(range.startMs, range.endMs, false)],
        label: withContext
            ? contextLabel(
                remove: edited && range.kind == EditKind.cut,
                mute: edited && range.kind == EditKind.mute,
              )
            : 'Selected section',
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.onActivity(false);
      }
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
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Timing & pauses'),
        leading: IconButton(
          tooltip: 'Back to transcript',
          onPressed: _busy ? null : () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            key: const Key('proceed-from-timing'),
            onPressed: _busy || widget.edits.isEmpty
                ? null
                : () {
                    FocusScope.of(context).unfocus();
                    _preview.close();
                    Navigator.pop(context, true);
                  },
            icon: const Icon(Icons.arrow_forward),
            label: Text(
              widget.edits.isEmpty
                  ? 'Proceed to review'
                  : 'Proceed to review · ${widget.edits.length}',
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Work with original video time.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              InlinePreviewPane(controller: _preview, showPlaceholder: true),
              const SizedBox(height: 12),
              Expanded(
                child: Scrollbar(
                  controller: _pageScroll,
                  thumbVisibility: true,
                  child: ListView(
                    controller: _pageScroll,
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.viewInsetsOf(context).bottom,
                    ),
                    children: [
                      SilenceReview(
                        key: ValueKey(widget.source.path),
                        engine: _media,
                        collapseAdvanced: true,
                        pauseSession: widget.pauseSession,
                        onOpenPauseReview: _preview.close,
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
                          ButtonSegment(
                            value: EditKind.cut,
                            label: Text('Trim'),
                          ),
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
                              onChanged: (_) => setState(() {}),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
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
                              onChanged: (_) => setState(() {}),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
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
                      if (_manualRange case final range?)
                        TimeRangePlayback(
                          startMs: range.startMs,
                          endMs: range.endMs,
                          mute: range.kind == EditKind.mute,
                          showContext: true,
                          onContext: _busy
                              ? null
                              : () => _playManual(range, withContext: true),
                          onContextRemoved: _busy
                              ? null
                              : () => _playManual(
                                  range,
                                  withContext: true,
                                  edited: true,
                                ),
                          onPlay: _busy ? null : () => _playManual(range),
                        ),
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
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
