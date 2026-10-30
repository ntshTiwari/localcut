import 'package:flutter/material.dart';
import 'core/edit_plan.dart';
import 'widgets/silence_review.dart';
import 'media/media_engine.dart';

void main() => runApp(const LocalCutApp());

class LocalCutApp extends StatelessWidget {
  const LocalCutApp({super.key, this.engine});
  final MediaEngine? engine;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'LocalCut',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff236353)),
      useMaterial3: true,
    ),
    home: EditorScreen(engine: engine),
  );
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, this.engine});
  final MediaEngine? engine;
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final MediaEngine _engine = widget.engine ?? PlatformMediaEngine();
  final _start = TextEditingController();
  final _end = TextEditingController();
  final List<EditRange> _edits = [];
  SourceVideo? _source;
  EditKind _kind = EditKind.cut;
  bool _busy = false;
  bool _exporting = false;
  bool _silenceBusy = false;
  String? _exportPath;
  String? _message;

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

  void _add() {
    final start = double.tryParse(_start.text);
    final end = double.tryParse(_end.text);
    if (start == null || end == null || !start.isFinite || !end.isFinite) {
      setState(() => _message = 'Enter valid start and end times in seconds.');
      return;
    }
    final edit = EditRange((start * 1000).round(), (end * 1000).round(), _kind);
    try {
      compilePlan(_source!.durationMs, [..._edits, edit]);
      setState(() {
        _edits.add(edit);
        _exportPath = null;
        _message = null;
      });
    } catch (e) {
      setState(() => _message = e.toString());
    }
  }

  Future<void> _approveExport() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export these edits?'),
        content: Text(
          '${_edits.where((e) => e.kind == EditKind.cut).length} cuts and ${_edits.where((e) => e.kind == EditKind.mute).length} mute ranges. A new video will be created. Your original stays untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Review again'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Approve & export'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    await _run(() async {
      setState(() => _exporting = true);
      final path = await _engine.export(_source!.path, _plan);
      if (mounted) {
        setState(() {
          _exportPath = path;
          _message = 'Export ready. Save it using Share / Save.';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('LocalCut')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'A cleaner first cut.',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text('Offline editing · Waveform, cuts and muting · iPhone'),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _run(() async {
                    final source = await _engine.importVideo();
                    if (source != null && mounted) {
                      setState(() {
                        _source = source;
                        _edits.clear();
                        _exportPath = null;
                      });
                    }
                  }),
            icon: const Icon(Icons.video_library_outlined),
            label: Text(
              _source == null
                  ? 'Import video from Files'
                  : 'Choose another video',
            ),
          ),
          if (_source != null) ...[
            const SizedBox(height: 20),
            Text(
              'Source: ${(_source!.durationMs / 1000).toStringAsFixed(2)} seconds',
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                      () => _engine.preview(
                        _source!.path,
                        compilePlan(_source!.durationMs, []),
                      ),
                    ),
              child: const Text('Watch original'),
            ),
            const Divider(height: 36),
            SilenceReview(
              key: ValueKey(_source!.path),
              engine: _engine,
              source: _source!,
              enabled: !_busy,
              edits: _edits,
              onBusyChanged: (value) => setState(() {
                _busy = value;
                _silenceBusy = value;
              }),
              onApply: (cuts) {
                compilePlan(_source!.durationMs, [..._edits, ...cuts]);
                setState(() {
                  _edits.addAll(cuts);
                  _exportPath = null;
                  _message =
                      'Added to proposed edits. Preview before exporting.';
                });
              },
            ),
            const Divider(height: 36),
            Text('Mark an edit', style: Theme.of(context).textTheme.titleLarge),
            const Text(
              'Add a manual cut or mute using original video timestamps.',
            ),
            const SizedBox(height: 16),
            SegmentedButton<EditKind>(
              segments: const [
                ButtonSegment(value: EditKind.cut, label: Text('Cut section')),
                ButtonSegment(value: EditKind.mute, label: Text('Mute audio')),
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
                const SizedBox(width: 16),
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
            OutlinedButton.icon(
              onPressed: _busy ? null : _add,
              icon: const Icon(Icons.add),
              label: const Text('Add to proposed edits'),
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < _edits.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _edits[i].kind == EditKind.cut
                      ? Icons.content_cut
                      : Icons.volume_off_outlined,
                ),
                title: Text(
                  '${_edits[i].kind.name.toUpperCase()}  ${(_edits[i].startMs / 1000).toStringAsFixed(2)} – ${(_edits[i].endMs / 1000).toStringAsFixed(2)} s',
                ),
                trailing: IconButton(
                  tooltip: 'Remove edit',
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _edits.removeAt(i);
                          _exportPath = null;
                        }),
                  icon: const Icon(Icons.close),
                ),
              ),
            if (_edits.isNotEmpty) ...[
              Text(
                'Edited length: ${(_plan.fold<int>(0, (sum, s) => sum + s.endMs - s.startMs) / 1000).toStringAsFixed(2)} seconds',
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run(() => _engine.preview(_source!.path, _plan)),
                child: const Text('Preview proposed edits'),
              ),
              FilledButton(
                onPressed: _busy ? null : _approveExport,
                child: const Text('Review & export'),
              ),
            ],
          ],
          if (_busy && !_silenceBusy) ...[
            const SizedBox(height: 20),
            const LinearProgressIndicator(),
            Text(
              _exporting
                  ? 'Exporting on this device. Keep the app open.'
                  : 'Preparing video…',
            ),
          ],
          if (_exporting)
            TextButton(
              onPressed: () async {
                await _engine.cancelExport();
              },
              child: const Text('Cancel export'),
            ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: SelectableText(_message!),
            ),
          if (_exportPath != null)
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () => _run(() => _engine.share(_exportPath!)),
              icon: const Icon(Icons.ios_share),
              label: const Text('Share / Save exported video'),
            ),
        ],
      ),
    ),
  );
}
