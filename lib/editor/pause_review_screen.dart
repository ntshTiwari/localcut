import 'package:flutter/material.dart';
import '../core/edit_plan.dart';
import '../core/context_preview.dart';
import '../core/pause_review.dart';
import '../media/media_engine.dart';
import '../widgets/time_range_playback.dart';
import '../widgets/compact_preview_switch.dart';
import 'inline_preview.dart';
import 'playback_media_engine.dart';

String pauseDuration(int ms) => ms >= 60000
    ? '${ms ~/ 60000}m ${ms % 60000 ~/ 1000}s'
    : '${(ms / 1000).toStringAsFixed(1)}s';
MediaEngine _rawMedia(MediaEngine media) =>
    media is PlaybackMediaEngine ? _rawMedia(media.backend) : media;

class PauseOverviewScreen extends StatefulWidget {
  const PauseOverviewScreen({
    super.key,
    required this.session,
    required this.source,
    required this.media,
    required this.onApply,
  });
  final PauseReviewSession session;
  final SourceVideo source;
  final MediaEngine media;
  final ValueChanged<List<EditRange>> onApply;
  @override
  State<PauseOverviewScreen> createState() => _PauseOverviewScreenState();
}

class _PauseOverviewScreenState extends State<PauseOverviewScreen> {
  PauseFilter _filter = PauseFilter.all;
  PauseOrder _order = PauseOrder.timeline;
  final _scroll = ScrollController();
  String? _error;
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _review(EditRange? start) async {
    final ordered = widget.session.ordered(_order);
    if (ordered.isEmpty) return;
    start ??=
        ordered
            .where(
              (p) =>
                  pauseId(p) == widget.session.lastVisitedId &&
                  widget.session.decision(p) == null,
            )
            .firstOrNull ??
        ordered.where((p) => widget.session.decision(p) == null).firstOrNull ??
        ordered
            .where((p) => pauseId(p) == widget.session.lastVisitedId)
            .firstOrNull ??
        ordered.first;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => PauseReviewerScreen(
          session: widget.session,
          source: widget.source,
          media: _rawMedia(widget.media),
          queue: ordered,
          start: start!,
        ),
      ),
    );
  }

  void _add() {
    try {
      final cuts = widget.session.trims;
      widget.onApply(cuts);
      widget.session.applied(cuts);
      Navigator.pop(context);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.session,
    builder: (context, _) {
      final session = widget.session, rows = session.visible(_filter, _order);
      final total = session.pauses.fold<int>(
        0,
        (n, p) => n + p.endMs - p.startMs,
      );
      return Scaffold(
        appBar: AppBar(
          title: const Text('Pause review'),
          actions: [
            IconButton(
              tooltip: 'Undo review decision',
              onPressed: session.canUndo ? session.undo : null,
              icon: const Icon(Icons.undo),
            ),
            PopupMenuButton<String>(
              tooltip: 'Review options',
              onSelected: (value) {
                if (value == 'all') session.markAllForTrim();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'all',
                  child: Text('Mark all for removal'),
                ),
              ],
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: session.trims.isEmpty ? null : _add,
              child: Text(
                'Add ${session.trims.length} ${session.trims.length == 1 ? 'cut' : 'cuts'} to edits',
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: Scrollbar(
            controller: _scroll,
            thumbVisibility: true,
            child: CustomScrollView(
              controller: _scroll,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${session.pauses.length} suggested pauses · ${pauseDuration(total)} removable',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${session.reviewed} of ${session.pauses.length} reviewed · decisions are not applied yet',
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: session.pauses.isEmpty
                              ? 0
                              : session.reviewed / session.pauses.length,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => _review(null),
                          icon: const Icon(Icons.playlist_play),
                          label: Text(
                            session.reviewed == session.pauses.length
                                ? 'Review decisions'
                                : 'Review next pause',
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<PauseFilter>(
                                initialValue: _filter,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Show',
                                ),
                                items: [
                                  for (final f in PauseFilter.values)
                                    DropdownMenuItem(
                                      value: f,
                                      child: Text(switch (f) {
                                        PauseFilter.all => 'All pauses',
                                        PauseFilter.unreviewed => 'Unreviewed',
                                        PauseFilter.trim =>
                                          'Marked for removal',
                                        PauseFilter.keep => 'Kept',
                                      }),
                                    ),
                                ],
                                onChanged: (v) => setState(() => _filter = v!),
                              ),
                            ),
                            const SizedBox(width: 8),
                            PopupMenuButton<PauseOrder>(
                              tooltip: 'Sort pauses',
                              initialValue: _order,
                              onSelected: (v) => setState(() => _order = v),
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: PauseOrder.timeline,
                                  child: Text('Timeline order'),
                                ),
                                const PopupMenuItem(
                                  value: PauseOrder.longest,
                                  child: Text('Longest first'),
                                ),
                              ],
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  children: [
                                    const Icon(Icons.sort),
                                    Text(
                                      _order == PauseOrder.timeline
                                          ? 'Timeline'
                                          : 'Longest',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
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
                if (rows.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: Text('No pauses in this filter.')),
                  )
                else
                  SliverFixedExtentList(
                    key: const Key('pause-overview-list'),
                    itemExtent:
                        80 + MediaQuery.textScalerOf(context).scale(32) - 32,
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final p = rows[index], decision = session.decision(p);
                      return ListTile(
                        key: ValueKey('pause-row-${pauseId(p)}'),
                        leading: Checkbox(
                          value: decision == PauseDecision.trim,
                          onChanged: (checked) => session.decide(
                            p,
                            checked == true ? PauseDecision.trim : null,
                          ),
                        ),
                        title: Text(
                          '${rangeTimestamp(p.startMs)} – ${rangeTimestamp(p.endMs)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${pauseDuration(p.endMs - p.startMs)} · ${switch (decision) {
                            PauseDecision.keep => 'Kept',
                            PauseDecision.trim => 'Marked for removal',
                            null => 'Unreviewed',
                          }}',
                        ),
                        onTap: () => _review(p),
                        trailing: IconButton(
                          tooltip:
                              'Review pause at ${rangeTimestamp(p.startMs)}',
                          onPressed: () => _review(p),
                          icon: const Icon(Icons.play_circle_outline),
                        ),
                      );
                    }, childCount: rows.length),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class PauseReviewerScreen extends StatefulWidget {
  const PauseReviewerScreen({
    super.key,
    required this.session,
    required this.source,
    required this.media,
    required this.queue,
    required this.start,
  });
  final PauseReviewSession session;
  final SourceVideo source;
  final MediaEngine media;
  final List<EditRange> queue;
  final EditRange start;
  @override
  State<PauseReviewerScreen> createState() => _PauseReviewerScreenState();
}

class _PauseReviewerScreenState extends State<PauseReviewerScreen> {
  late int _index = widget.queue.indexWhere(
    (p) => pauseId(p) == pauseId(widget.start),
  );
  final _preview = InlinePreviewController();
  late final _media = PlaybackMediaEngine(
    widget.media,
    () async {},
    onPreview: _preview.show,
  );
  final List<int> _undo = [];
  bool _busy = false, _finished = false;
  String? _error;
  EditRange get _pause => widget.queue[_index];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.session.lastVisitedId = pauseId(_pause);
    });
  }

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
  }

  Future<void> _play(int mode) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final p = _pause;
    try {
      await _media.preview(
        widget.source.path,
        mode == 0
            ? [RenderSegment(p.startMs, p.endMs, false)]
            : contextPreview(
                widget.source.durationMs,
                p.startMs,
                p.endMs,
                remove: mode == 2,
              ),
        label: mode == 0 ? 'Selected section' : contextLabel(remove: mode == 2),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _move(int index) {
    _preview.close();
    setState(() {
      _index = index;
      _finished = false;
      _error = null;
    });
    widget.session.lastVisitedId = pauseId(_pause);
  }

  void _decide(PauseDecision decision) {
    _undo.add(_index);
    widget.session.decide(_pause, decision);
    _preview.close();
    int? next;
    for (var offset = 1; offset < widget.queue.length; offset++) {
      final candidate = (_index + offset) % widget.queue.length;
      if (widget.session.decision(widget.queue[candidate]) == null) {
        next = candidate;
        break;
      }
    }
    if (next != null) {
      _move(next);
    } else {
      setState(() => _finished = true);
    }
  }

  void _undoDecision() {
    if (_undo.isEmpty) return;
    widget.session.undo();
    _move(_undo.removeLast());
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.session,
    builder: (context, _) {
      final session = widget.session, p = _pause;
      return PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar: AppBar(
            title: Text('Pause ${_index + 1} of ${widget.queue.length}'),
            leading: IconButton(
              tooltip: 'Back to pause overview',
              onPressed: _busy ? null : () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
            ),
            actions: [
              IconButton(
                tooltip: 'Undo review decision',
                onPressed: _busy || _undo.isEmpty ? null : _undoDecision,
                icon: const Icon(Icons.undo),
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  '${session.reviewed} of ${session.pauses.length} reviewed',
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: session.reviewed / session.pauses.length,
                ),
                const SizedBox(height: 12),
                if (_finished) ...[
                  const Icon(Icons.task_alt, size: 56),
                  const SizedBox(height: 12),
                  Text(
                    session.reviewed == session.pauses.length
                        ? 'All pauses reviewed'
                        : 'No more unreviewed pauses in this queue',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Text(
                    'Your decisions are saved for this session. Add marked cuts from the overview when you are ready.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Back to overview'),
                  ),
                  TextButton(
                    onPressed: _undo.isEmpty ? null : _undoDecision,
                    child: const Text('Undo last decision'),
                  ),
                ] else ...[
                  InlinePreviewPane(
                    controller: _preview,
                    showPlaceholder: true,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${rangeTimestamp(p.startMs)} – ${rangeTimestamp(p.endMs)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '${pauseDuration(p.endMs - p.startMs)} would be removed · ${switch (session.decision(p)) {
                      PauseDecision.keep => 'Kept',
                      PauseDecision.trim => 'Marked for removal',
                      null => 'Unreviewed',
                    }}',
                  ),
                  const SizedBox(height: 12),
                  CompactPreviewSwitch(
                    key: ValueKey(pauseId(p)),
                    enabled: !_busy,
                    onSection: () => _play(0),
                    onOriginal: () => _play(1),
                    onEdited: () => _play(2),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Section only · original context · context after trimming',
                    style: TextStyle(fontSize: 12),
                  ),
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _decide(PauseDecision.keep),
                          icon: const Icon(Icons.check),
                          label: const Text('Keep pause'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _decide(PauseDecision.trim),
                          icon: const Icon(Icons.content_cut),
                          label: const Text('Trim pause'),
                        ),
                      ),
                    ],
                  ),
                  const Text(
                    'Advances to the next unreviewed pause. Undo is always available.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      TextButton.icon(
                        onPressed: _busy || _index == 0
                            ? null
                            : () => _move(_index - 1),
                        icon: const Icon(Icons.chevron_left),
                        label: const Text('Previous'),
                      ),
                      TextButton.icon(
                        onPressed: _busy || _index == widget.queue.length - 1
                            ? null
                            : () => _move(_index + 1),
                        icon: const Icon(Icons.chevron_right),
                        label: const Text('Next / skip'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}
