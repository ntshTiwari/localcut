import 'package:flutter/material.dart';
import 'core/edit_plan.dart';
import 'core/silence_detection.dart';
import 'media/media_engine.dart';
import 'transcript/transcript_actions.dart';
import 'transcript/transcript_gaps.dart';
import 'transcript/transcript_panel.dart';
import 'transcript/transcription_engine.dart';
import 'widgets/silence_review.dart';

void main() => runApp(const LocalCutApp());

class LocalCutApp extends StatelessWidget {
  const LocalCutApp({super.key, this.engine, this.transcriptionEngine});
  final MediaEngine? engine;
  final TranscriptionEngine? transcriptionEngine;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'LocalCut',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff236353)),
      useMaterial3: true,
    ),
    home: EditorScreen(
      engine: engine,
      transcriptionEngine: transcriptionEngine,
    ),
  );
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, this.engine, this.transcriptionEngine});
  final MediaEngine? engine;
  final TranscriptionEngine? transcriptionEngine;
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final MediaEngine _engine = widget.engine ?? PlatformMediaEngine();
  late final TranscriptionEngine _speech =
      widget.transcriptionEngine ?? PlatformTranscriptionEngine();
  final _start = TextEditingController(), _end = TextEditingController();
  final List<EditRange> _edits = [];
  SourceVideo? _source;
  AudioAnalysis? _analysis;
  TranscriptActions? _actions;
  EditKind _kind = EditKind.cut;
  bool _busy = false, _exporting = false, _panelBusy = false;
  String? _exportPath, _message;

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _message = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _exporting = false;
        });
      }
    }
  }

  List<RenderSegment> get _plan => compilePlan(_source!.durationMs, _edits);
  void _panelActivity(bool value) => setState(() {
    _busy = value;
    _panelBusy = value;
  });
  void _acceptEdit(EditRange edit) {
    compilePlan(_source!.durationMs, [..._edits, edit]);
    setState(() {
      _edits.add(edit);
      _exportPath = null;
      _message = null;
    });
  }

  void _restore(int start, int end, EditKind? kind) {
    final restored = restoreEdits(_edits, start, end, kind: kind);
    setState(() {
      _edits
        ..clear()
        ..addAll(restored);
      _exportPath = null;
      _message = null;
    });
  }

  void _addManual() {
    final start = double.tryParse(_start.text),
        end = double.tryParse(_end.text);
    if (start == null || end == null || !start.isFinite || !end.isFinite) {
      setState(() => _message = 'Enter valid start and end times in seconds.');
      return;
    }
    try {
      _acceptEdit(
        EditRange((start * 1000).round(), (end * 1000).round(), _kind),
      );
      FocusScope.of(context).unfocus();
    } catch (e) {
      setState(() => _message = e.toString());
    }
  }

  Future<void> _import() => _run(() async {
    final source = await _engine.importVideo();
    if (source != null && mounted) {
      setState(() {
        _source = source;
        _analysis = null;
        _actions = null;
        _edits.clear();
        _exportPath = null;
        _start.clear();
        _end.clear();
      });
    }
  });

  Future<void> _review() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      builder: (sheetContext) {
        bool working = false;
        return StatefulBuilder(
          builder: (context, refresh) {
            Future<void> perform(Future<void> Function() action) async {
              refresh(() => working = true);
              await _run(action);
              if (context.mounted) refresh(() => working = false);
            }

            final duration = _edits.isEmpty
                ? _source!.durationMs
                : _plan.fold<int>(0, (sum, s) => sum + s.endMs - s.startMs);
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * .82,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Review changes',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Back to transcript',
                            onPressed: working
                                ? null
                                : () => Navigator.pop(sheetContext),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      Text(
                        '${(_source!.durationMs / 1000).toStringAsFixed(1)}s original → ${(duration / 1000).toStringAsFixed(1)}s edited',
                      ),
                      const Text(
                        'Export creates a new video. Your original stays unchanged.',
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: _edits.isEmpty
                            ? const Center(
                                child: Text(
                                  'No changes left. Return to the transcript to keep editing.',
                                ),
                              )
                            : ListView.builder(
                                itemCount: _edits.length,
                                itemBuilder: (context, index) {
                                  final edit = _edits[index];
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(
                                      edit.kind == EditKind.mute
                                          ? Icons.volume_off_outlined
                                          : Icons.content_cut,
                                    ),
                                    title: Text(
                                      edit.label ??
                                          (edit.kind == EditKind.mute
                                              ? 'Censor section'
                                              : 'Trim section'),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      '${(edit.startMs / 1000).toStringAsFixed(2)}–${(edit.endMs / 1000).toStringAsFixed(2)}s in original',
                                    ),
                                    trailing: IconButton(
                                      tooltip: 'Restore this change',
                                      onPressed: working
                                          ? null
                                          : () {
                                              setState(() {
                                                _edits.removeAt(index);
                                                _exportPath = null;
                                                _message = null;
                                              });
                                              refresh(() {});
                                            },
                                      icon: const Icon(Icons.undo),
                                    ),
                                  );
                                },
                              ),
                      ),
                      if (working) ...[
                        const LinearProgressIndicator(),
                        Text(
                          _exporting
                              ? 'Exporting on this device. Keep the app open.'
                              : 'Preparing video…',
                        ),
                      ],
                      if (working && _exporting)
                        TextButton(
                          onPressed: () async {
                            await _engine.cancelExport();
                          },
                          child: const Text('Cancel export'),
                        ),
                      if (_message != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(_message!),
                        ),
                      OutlinedButton.icon(
                        onPressed: working || _edits.isEmpty
                            ? null
                            : () => perform(
                                () => _engine.preview(_source!.path, _plan),
                              ),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Play edited video'),
                      ),
                      FilledButton.icon(
                        onPressed: working || _edits.isEmpty
                            ? null
                            : () => perform(() async {
                                if (_exportPath != null) {
                                  await _engine.share(_exportPath!);
                                  return;
                                }
                                setState(() => _exporting = true);
                                refresh(() {});
                                final path = await _engine.export(
                                  _source!.path,
                                  _plan,
                                );
                                if (mounted) {
                                  setState(() {
                                    _exportPath = path;
                                    _message =
                                        'Video ready. Tap Save or share.';
                                  });
                                }
                              }),
                        icon: Icon(
                          _exportPath == null
                              ? Icons.file_download_outlined
                              : Icons.ios_share,
                        ),
                        label: Text(
                          _exportPath == null
                              ? 'Export video'
                              : 'Save or share',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _fineTune() => ExpansionTile(
    title: const Text('Fine-tune timing'),
    subtitle: const Text('Waveform, pause settings, and manual ranges'),
    maintainState: true,
    children: [
      SilenceReview(
        key: ValueKey(_source!.path),
        engine: _engine,
        source: _source!,
        enabled: !_busy,
        edits: _edits,
        analysis: _analysis,
        onAnalysis: (a) => setState(() => _analysis = a),
        onBusyChanged: _panelActivity,
        onApply: (edits) {
          compilePlan(_source!.durationMs, [..._edits, ...edits]);
          setState(() {
            _edits.addAll(edits);
            _exportPath = null;
            _message = null;
          });
        },
      ),
      const Divider(height: 24),
      const Align(
        alignment: Alignment.centerLeft,
        child: Text('Enter an exact range in the original video'),
      ),
      SegmentedButton<EditKind>(
        segments: const [
          ButtonSegment(value: EditKind.cut, label: Text('Trim')),
          ButtonSegment(value: EditKind.mute, label: Text('Censor')),
        ],
        selected: {_kind},
        onSelectionChanged: _busy
            ? null
            : (value) => setState(() => _kind = value.first),
      ),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _start,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Start (seconds)'),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: TextField(
              controller: _end,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'End (seconds)'),
            ),
          ),
        ],
      ),
      OutlinedButton(
        onPressed: _busy ? null : _addManual,
        child: const Text('Add manual change'),
      ),
      const SizedBox(height: 12),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('LocalCut')),
    bottomNavigationBar: _source == null
        ? null
        : SafeArea(
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_actions != null) ...[
                    TranscriptActionBar(actions: _actions!, enabled: !_busy),
                    const Divider(height: 14),
                  ],
                  FilledButton.icon(
                    key: const Key('review-changes'),
                    onPressed: _busy || _edits.isEmpty ? null : _review,
                    icon: const Icon(Icons.checklist),
                    label: Text(
                      'Review ${_edits.length} ${_edits.length == 1 ? 'change' : 'changes'}',
                    ),
                  ),
                ],
              ),
            ),
          ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_source == null) ...[
            Text(
              'A cleaner first cut.',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text('Read your video. Censor words. Shorten pauses.'),
            const SizedBox(height: 24),
          ],
          if (_source == null)
            FilledButton.tonalIcon(
              onPressed: _busy ? null : _import,
              icon: const Icon(Icons.video_library_outlined),
              label: const Text('Import video from Files'),
            ),
          if (_source != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${(_source!.durationMs / 1000).toStringAsFixed(1)}s original',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : _import,
                  child: const Text('Change video'),
                ),
                IconButton(
                  tooltip: 'Watch original',
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => _engine.preview(
                            _source!.path,
                            compilePlan(_source!.durationMs, []),
                          ),
                        ),
                  icon: const Icon(Icons.play_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TranscriptPanel(
              key: ValueKey('transcript-${_source!.path}'),
              engine: _speech,
              media: _engine,
              source: _source!,
              edits: _edits,
              enabled: !_busy,
              analysis: _analysis,
              onAnalysis: (analysis) => setState(() => _analysis = analysis),
              onBusyChanged: _panelActivity,
              onAdd: _acceptEdit,
              onSelectionChanged: (actions) =>
                  setState(() => _actions = actions),
              onRestoreRange: _restore,
            ),
            const Divider(height: 28),
            _fineTune(),
          ],
          if (_busy && !_panelBusy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: LinearProgressIndicator(),
            ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_message!),
            ),
        ],
      ),
    ),
  );
}
