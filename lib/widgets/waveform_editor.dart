import 'time_range_playback.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/edit_plan.dart';
import '../core/silence_detection.dart';
import '../core/waveform_timeline.dart';

/// Source-time selection UI. Native playback/export still use the shared plan.
class WaveformEditor extends StatefulWidget {
  const WaveformEditor({
    super.key,
    required this.analysis,
    required this.durationMs,
    required this.edits,
    required this.suggestions,
    required this.enabled,
    required this.onHear,
    this.onContext,
    required this.onPreview,
    required this.onAdd,
  });
  final AudioAnalysis analysis;
  final int durationMs;
  final List<EditRange> edits;
  final List<EditRange> suggestions;
  final bool enabled;
  final Future<void> Function(int startMs, int endMs) onHear;
  final Future<void> Function(EditRange edit) onPreview;
  final Future<void> Function(EditRange edit, bool edited)? onContext;
  final ValueChanged<EditRange> onAdd;
  @override
  State<WaveformEditor> createState() => _WaveformEditorState();
}

enum _DragMode { newRange, start, end }

class _WaveformEditorState extends State<WaveformEditor> {
  late WaveformViewport _view = WaveformViewport.full(widget.durationMs);
  WaveformSelection? _selection;
  EditKind _kind = EditKind.cut;
  int _positionMs = 0;
  double _downX = 0;
  int _anchorMs = 0;
  _DragMode _dragMode = _DragMode.newRange;
  String? _error;
  List<double?>? _bins;
  List<AudioWindow>? _binnedWindows;
  int? _binnedStart;
  int? _binnedEnd;
  int? _binnedCount;

  int _time(double x, double width) => _view.timeAt(x / width);
  EditRange get _edit =>
      EditRange(_selection!.startMs, _selection!.endMs, _kind);
  int get _focus => _selection == null
      ? _positionMs
      : ((_selection!.startMs + _selection!.endMs) / 2).round();

  List<double?> _levels(int count) {
    if (!identical(_binnedWindows, widget.analysis.windows) ||
        _binnedStart != _view.startMs ||
        _binnedEnd != _view.endMs ||
        _binnedCount != count) {
      _bins = waveformBins(widget.analysis.windows, _view, count);
      _binnedWindows = widget.analysis.windows;
      _binnedStart = _view.startMs;
      _binnedEnd = _view.endMs;
      _binnedCount = count;
    }
    return _bins!;
  }

  Future<void> _safely(Future<void> Function() action) async {
    setState(() => _error = null);
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _startDrag(double width) {
    _anchorMs = _time(_downX, width);
    _dragMode = _DragMode.newRange;
    final selection = _selection;
    if (selection != null) {
      final left = _view.fractionAt(selection.startMs) * width;
      final right = _view.fractionAt(selection.endMs) * width;
      final leftDistance = (_downX - left).abs();
      final rightDistance = (_downX - right).abs();
      if (leftDistance <= 22 && leftDistance <= rightDistance) {
        _dragMode = _DragMode.start;
      } else if (rightDistance <= 22) {
        _dragMode = _DragMode.end;
      }
    }
    setState(() {
      _error = null;
      if (_dragMode == _DragMode.newRange) {
        _selection = WaveformSelection.between(
          _anchorMs,
          _anchorMs,
          widget.durationMs,
        );
      }
    });
  }

  void _drag(double x, double width) {
    final time = _time(x, width);
    setState(() {
      _selection = switch (_dragMode) {
        _DragMode.newRange => WaveformSelection.between(
          _anchorMs,
          time,
          widget.durationMs,
        ),
        _DragMode.start => _selection!.resizeStart(time, widget.durationMs),
        _DragMode.end => _selection!.resizeEnd(time, widget.durationMs),
      };
      _positionMs = time;
    });
  }

  void _nudge(bool start, int delta) => setState(() {
    _error = null;
    _selection = start
        ? _selection!.resizeStart(
            _selection!.startMs + delta,
            widget.durationMs,
          )
        : _selection!.resizeEnd(_selection!.endMs + delta, widget.durationMs);
  });

  Widget _edgeControl(bool start) {
    final label = start ? 'Start' : 'End';
    final time = start ? _selection!.startMs : _selection!.endMs;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label ${(time / 1000).toStringAsFixed(3)} s'),
        IconButton(
          key: Key('waveform-${start ? 'start' : 'end'}-earlier'),
          tooltip: '$label 20 milliseconds earlier',
          onPressed: widget.enabled ? () => _nudge(start, -20) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        IconButton(
          key: Key('waveform-${start ? 'start' : 'end'}-later'),
          tooltip: '$label 20 milliseconds later',
          onPressed: widget.enabled ? () => _nudge(start, 20) : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selection = _selection;
    final minimumSpan = math.min(250, widget.durationMs);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Select on the waveform',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        const Text(
          'Original video time. Drag horizontally to select a range; drag its edges to resize. Tap to hear original audio around that position.',
        ),
        Row(
          children: [
            IconButton(
              key: const Key('waveform-zoom-out'),
              tooltip: 'Zoom out',
              onPressed: widget.enabled && _view.spanMs < widget.durationMs
                  ? () => setState(() => _view = _view.zoomBy(.5, _focus))
                  : null,
              icon: const Icon(Icons.zoom_out),
            ),
            Text('${_view.zoom.toStringAsFixed(1)}×'),
            IconButton(
              key: const Key('waveform-zoom-in'),
              tooltip: 'Zoom in',
              onPressed: widget.enabled && _view.spanMs > minimumSpan
                  ? () => setState(() => _view = _view.zoomBy(2, _focus))
                  : null,
              icon: const Icon(Icons.zoom_in),
            ),
            const Spacer(),
            TextButton(
              onPressed: widget.enabled && _view.spanMs < widget.durationMs
                  ? () => setState(
                      () => _view = WaveformViewport.full(widget.durationMs),
                    )
                  : null,
              child: const Text('Fit all'),
            ),
          ],
        ),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            Text('Suggested pause', style: TextStyle(color: colors.tertiary)),
            Text('Cut', style: TextStyle(color: colors.error)),
            Text('Mute', style: TextStyle(color: colors.secondary)),
            Text('Selection', style: TextStyle(color: colors.primary)),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final count = math.max(1, (width / 3).ceil());
            return Semantics(
              label:
                  'Original audio waveform. Drag to select. Tap to hear context.',
              child: GestureDetector(
                key: const Key('waveform-surface'),
                behavior: HitTestBehavior.opaque,
                onHorizontalDragDown: widget.enabled
                    ? (d) => _downX = d.localPosition.dx
                    : null,
                onHorizontalDragStart: widget.enabled
                    ? (_) => _startDrag(width)
                    : null,
                onHorizontalDragUpdate: widget.enabled
                    ? (d) => _drag(d.localPosition.dx, width)
                    : null,
                onTapUp: widget.enabled
                    ? (d) {
                        final time = _time(d.localPosition.dx, width);
                        setState(() {
                          _positionMs = time;
                          _error = null;
                        });
                        _safely(
                          () => widget.onHear(
                            math.max(0, time - 700),
                            math.min(widget.durationMs, time + 1300),
                          ),
                        );
                      }
                    : null,
                child: CustomPaint(
                  size: Size(width, 160),
                  painter: _WaveformPainter(
                    view: _view,
                    bins: _levels(count),
                    edits: widget.edits,
                    suggestions: widget.suggestions,
                    selection: selection,
                    positionMs: _positionMs,
                    colors: colors,
                  ),
                ),
              ),
            );
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${(_view.startMs / 1000).toStringAsFixed(2)} s'),
            Text(
              '${((_view.startMs + _view.endMs) / 2000).toStringAsFixed(2)} s',
            ),
            Text('${(_view.endMs / 1000).toStringAsFixed(2)} s'),
          ],
        ),
        if (_view.spanMs < widget.durationMs) ...[
          const Text('Move along the original timeline'),
          Slider(
            key: const Key('waveform-pan'),
            value: _view.startMs.toDouble(),
            min: 0,
            max: (widget.durationMs - _view.spanMs).toDouble(),
            label: '${(_view.startMs / 1000).toStringAsFixed(2)} s',
            onChanged: widget.enabled
                ? (v) => setState(() => _view = _view.moveTo(v.round()))
                : null,
          ),
        ],
        const SizedBox(height: 8),
        if (selection == null)
          const Text(
            'No range selected. Drag across the waveform to choose audio.',
          )
        else ...[
          TimeRangePlayback(
            startMs: selection.startMs,
            endMs: selection.endMs,
            mute: _kind == EditKind.mute,
            onContext: widget.enabled && widget.onContext != null
                ? () => _safely(() => widget.onContext!(_edit, false))
                : null,
            onContextRemoved: widget.enabled && widget.onContext != null
                ? () => _safely(() => widget.onContext!(_edit, true))
                : null,
            onPlay: widget.enabled
                ? () => _safely(
                    () => widget.onHear(selection.startMs, selection.endMs),
                  )
                : null,
            label:
                'Selected ${(selection.startMs / 1000).toStringAsFixed(3)} – ${(selection.endMs / 1000).toStringAsFixed(3)} s (${((selection.endMs - selection.startMs) / 1000).toStringAsFixed(3)} s)',
            key: const Key('waveform-selection-label'),
          ),
          Wrap(
            spacing: 12,
            children: [_edgeControl(true), _edgeControl(false)],
          ),
          SegmentedButton<EditKind>(
            segments: const [
              ButtonSegment(value: EditKind.cut, label: Text('Cut selection')),
              ButtonSegment(
                value: EditKind.mute,
                label: Text('Mute selection'),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: widget.enabled
                ? (value) => setState(() {
                    _kind = value.first;
                    _error = null;
                  })
                : null,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: widget.enabled
                    ? () => _safely(() async {
                        compilePlan(widget.durationMs, [
                          ...widget.edits,
                          _edit,
                        ]);
                        await widget.onPreview(_edit);
                      })
                    : null,
                child: Text('Preview ${_kind.name}'),
              ),
              FilledButton(
                onPressed: widget.enabled
                    ? () {
                        try {
                          compilePlan(widget.durationMs, [
                            ...widget.edits,
                            _edit,
                          ]);
                          widget.onAdd(_edit);
                          setState(() {
                            _selection = null;
                            _error = null;
                          });
                        } catch (e) {
                          setState(() => _error = e.toString());
                        }
                      }
                    : null,
                child: Text('Add ${_kind.name}'),
              ),
              TextButton(
                onPressed: widget.enabled
                    ? () => setState(() {
                        _selection = null;
                        _error = null;
                      })
                    : null,
                child: const Text('Clear range'),
              ),
            ],
          ),
        ],
        if (_error != null)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!)),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.view,
    required this.bins,
    required this.edits,
    required this.suggestions,
    required this.selection,
    required this.positionMs,
    required this.colors,
  });
  final WaveformViewport view;
  final List<double?> bins;
  final List<EditRange> edits;
  final List<EditRange> suggestions;
  final WaveformSelection? selection;
  final int positionMs;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = colors.surfaceContainerHighest;
    canvas.drawRect(Offset.zero & size, paint);
    double x(int time) =>
        (view.fractionAt(time) * size.width).clamp(0, size.width);
    void band(int start, int end, double top, double height, Color color) {
      if (end <= view.startMs || start >= view.endMs) return;
      canvas.drawRect(
        Rect.fromLTRB(x(start), top, x(end), top + height),
        Paint()..color = color,
      );
    }

    for (final cut in suggestions) {
      band(cut.startMs, cut.endMs, 4, 10, colors.tertiary);
    }
    for (final edit in edits) {
      final cut = edit.kind == EditKind.cut;
      band(
        edit.startMs,
        edit.endMs,
        cut ? 18 : 32,
        10,
        cut ? colors.error : colors.secondary,
      );
    }
    final selected = selection;
    if (selected != null) {
      band(
        selected.startMs,
        selected.endMs,
        0,
        size.height,
        colors.primary.withValues(alpha: .14),
      );
    }
    const center = 102.0;
    canvas.drawLine(
      Offset(0, center),
      Offset(size.width, center),
      Paint()..color = colors.outlineVariant,
    );
    paint
      ..color = colors.onSurfaceVariant
      ..strokeWidth = 2;
    for (var i = 0; i < bins.length; i++) {
      final db = bins[i];
      if (db == null) continue; // Leave unmeasured gaps empty.
      final height = 1 + ((db + 60) / 60).clamp(0.0, 1.0) * 43;
      final column = (i + .5) / bins.length * size.width;
      canvas.drawLine(
        Offset(column, center - height),
        Offset(column, center + height),
        paint,
      );
    }
    if (positionMs >= view.startMs && positionMs <= view.endMs) {
      canvas.drawLine(
        Offset(x(positionMs), 48),
        Offset(x(positionMs), size.height),
        Paint()
          ..color = colors.primary
          ..strokeWidth = 1,
      );
    }
    if (selected != null) {
      for (final time in [selected.startMs, selected.endMs]) {
        if (time < view.startMs || time > view.endMs) continue;
        final handleX = x(time);
        canvas.drawLine(
          Offset(handleX, 0),
          Offset(handleX, size.height),
          Paint()
            ..color = colors.primary
            ..strokeWidth = 3,
        );
        canvas.drawCircle(
          Offset(handleX, center),
          7,
          Paint()..color = colors.primary,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) => true;
}
