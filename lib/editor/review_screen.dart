import '../core/context_preview.dart';
import 'inline_preview.dart';
import 'playback_media_engine.dart';
import '../widgets/time_range_playback.dart';
import 'package:flutter/material.dart';
import '../core/edit_plan.dart';
import '../media/media_engine.dart';

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({
    super.key,
    required this.source,
    required this.media,
    required this.edits,
    required this.onRemove,
    required this.onExported,
    this.initialExportPath,
  });
  final SourceVideo source;
  final MediaEngine media;
  final List<EditRange> edits;
  final ValueChanged<int> onRemove;
  final ValueChanged<String> onExported;
  final String? initialExportPath;
  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final _preview = InlinePreviewController();
  late final _media = PlaybackMediaEngine(
    widget.media,
    () async {},
    onPreview: _preview.show,
  );

  late String? _output = widget.initialExportPath;
  bool _working = false,
      _exporting = false,
      _finished = false,
      _cancelled = false;
  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
  }

  String? _error;
  List<RenderSegment> get _plan =>
      compilePlan(widget.source.durationMs, widget.edits);
  int get _duration => widget.edits.isEmpty
      ? widget.source.durationMs
      : _plan.fold<int>(0, (sum, item) => sum + item.endMs - item.startMs);
  Future<void> _perform(Future<void> Function() action) async {
    setState(() {
      _working = true;
      _error = null;
      _cancelled = false;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = _cancelled
              ? 'Export canceled. Your changes are still here.'
              : e.toString(),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _exporting = false;
        });
      }
    }
  }

  Future<void> _export() => _perform(() async {
    if (_output != null) {
      await widget.media.share(_output!);
      return;
    }
    _preview.close();
    setState(() => _exporting = true);
    final path = await widget.media.export(widget.source.path, _plan);
    if (_cancelled) throw StateError('Canceled');
    if (mounted) {
      widget.onExported(path);
      setState(() {
        _output = path;
        _finished = true;
      });
    }
  });
  Future<void> _context(EditRange edit, bool edited) => _perform(
    () => _media.preview(
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
  );
  String _time(int ms) => '${(ms / 1000).toStringAsFixed(1)}s';
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_working,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back to transcript',
            onPressed: _working ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(_finished ? 'Your video is ready' : 'Review changes'),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                if (!_exporting && !_finished)
                  InlinePreviewPane(controller: _preview),
                Expanded(
                  child: _exporting
                      ? SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 64,
                                height: 64,
                                child: CircularProgressIndicator(
                                  strokeWidth: 4,
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                'Making the final cut.',
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Keep LocalCut open while your video exports.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 24),
                              TextButton(
                                onPressed: _cancelled
                                    ? null
                                    : () async {
                                        setState(() => _cancelled = true);
                                        try {
                                          await widget.media.cancelExport();
                                        } catch (e) {
                                          if (mounted) {
                                            setState(() {
                                              _cancelled = false;
                                              _error = e.toString();
                                            });
                                          }
                                        }
                                      },
                                child: Text(
                                  _cancelled
                                      ? 'Canceling export…'
                                      : 'Cancel export',
                                ),
                              ),
                            ],
                          ),
                        )
                      : _finished
                      ? ListView(
                          children: [
                            const SizedBox(height: 28),
                            Icon(
                              Icons.check_circle_outline_rounded,
                              size: 70,
                              color: colors.onSurface,
                            ),
                            const SizedBox(height: 22),
                            Text(
                              'Ready for your\nnext upload.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineLarge,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Your edited video is ready to save or share.\nThe original is right where you left it.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colors.onSurfaceVariant),
                            ),
                            const SizedBox(height: 24),
                            Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.surfaceContainer,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${_time(_duration)} · MP4',
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                              ),
                            ),
                            const SizedBox(height: 32),
                            if (_error != null)
                              Text(
                                _error!,
                                style: TextStyle(color: colors.error),
                              ),
                            FilledButton.icon(
                              onPressed: _working
                                  ? null
                                  : () => _perform(
                                      () => widget.media.share(_output!),
                                    ),
                              icon: const Icon(Icons.ios_share),
                              label: const Text('Save or share'),
                            ),
                            TextButton(
                              onPressed: _working
                                  ? null
                                  : () => setState(() => _finished = false),
                              child: const Text('Back to review'),
                            ),
                          ],
                        )
                      : ListView(
                          children: [
                            Text(
                              'One last look.',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Times refer to your original. Play any range to check it before exporting.',
                              style: TextStyle(color: colors.onSurfaceVariant),
                            ),
                            const SizedBox(height: 22),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: colors.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _Metric(
                                      label: 'ORIGINAL',
                                      value: _time(widget.source.durationMs),
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_forward,
                                    color: colors.onSurfaceVariant,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 24),
                                  Expanded(
                                    child: _Metric(
                                      label: 'EDITED',
                                      value: _time(_duration),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              '${widget.edits.length} PROPOSED ${widget.edits.length == 1 ? 'CHANGE' : 'CHANGES'}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.1,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              child: widget.edits.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'No changes left. Return to your transcript to keep editing.',
                                      ),
                                    )
                                  : ListView.separated(
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      itemCount: widget.edits.length,
                                      separatorBuilder: (_, _) =>
                                          const Divider(height: 1),
                                      itemBuilder: (context, index) {
                                        final edit = widget.edits[index];
                                        return ListTile(
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                vertical: 8,
                                              ),
                                          leading: Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: colors.surfaceContainer,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Icon(
                                              edit.kind == EditKind.mute
                                                  ? Icons.volume_off_outlined
                                                  : Icons.content_cut,
                                              size: 20,
                                            ),
                                          ),
                                          title: Text(
                                            edit.label ??
                                                (edit.kind == EditKind.mute
                                                    ? 'Censor section'
                                                    : 'Trim section'),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleSmall,
                                          ),
                                          subtitle: TimeRangePlayback(
                                            startMs: edit.startMs,
                                            endMs: edit.endMs,
                                            mute: edit.kind == EditKind.mute,
                                            onContext: _working
                                                ? null
                                                : () => _context(edit, false),
                                            onContextRemoved: _working
                                                ? null
                                                : () => _context(edit, true),
                                            onPlay: _working
                                                ? null
                                                : () => _perform(
                                                    () => _media.preview(
                                                      widget.source.path,
                                                      [
                                                        RenderSegment(
                                                          edit.startMs,
                                                          edit.endMs,
                                                          false,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                          ),
                                          trailing: IconButton(
                                            tooltip: 'Restore this change',
                                            onPressed: _working
                                                ? null
                                                : () {
                                                    _preview.close();
                                                    widget.onRemove(index);
                                                    setState(() {
                                                      _output = null;
                                                      _error = null;
                                                    });
                                                  },
                                            icon: const Icon(
                                              Icons.undo,
                                              size: 20,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                            if (_working) const LinearProgressIndicator(),
                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Text(
                                  _error!,
                                  style: TextStyle(color: colors.error),
                                ),
                              ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _working || widget.edits.isEmpty
                                  ? null
                                  : () => _perform(
                                      () => _media.preview(
                                        widget.source.path,
                                        _plan,
                                      ),
                                    ),
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Play edited video'),
                            ),
                            const SizedBox(height: 10),
                            FilledButton.icon(
                              onPressed: _working || widget.edits.isEmpty
                                  ? null
                                  : _export,
                              icon: Icon(
                                _output == null
                                    ? Icons.file_download_outlined
                                    : Icons.ios_share,
                              ),
                              label: Text(
                                _output == null
                                    ? 'Export video'
                                    : 'Save or share',
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Your original video stays unchanged.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                color: colors.onSurfaceVariant,
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
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 9,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 4),
      Text(value, style: Theme.of(context).textTheme.titleLarge),
    ],
  );
}
