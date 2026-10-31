import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/edit_plan.dart';
import '../core/silence_detection.dart';
import '../media/media_engine.dart';
import '../transcript/transcript_actions.dart';
import '../transcript/transcript_gaps.dart';
import '../transcript/transcript_panel.dart';
import '../transcript/transcription_engine.dart';
import 'fine_tune_sheet.dart';
import 'playback_media_engine.dart';
import 'review_screen.dart';
import 'source_video_player.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({
    super.key,
    required this.initialSource,
    required this.engine,
    required this.transcriptionEngine,
  });
  final SourceVideo initialSource;
  final MediaEngine engine;
  final TranscriptionEngine transcriptionEngine;
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late SourceVideo _source = widget.initialSource;
  late final MediaEngine _media = PlaybackMediaEngine(widget.engine, _pause);
  final _player = GlobalKey<SourceVideoPlayerState>();
  var _transcript = GlobalKey<TranscriptPanelState>();
  final List<EditRange> _edits = [];
  AudioAnalysis? _analysis;
  TranscriptActions? _actions;
  bool _busy = false, _allowLeave = false;
  String? _exportPath, _error;
  Future<void> _pause() async {
    await _player.currentState?.pause();
  }

  void _activity(bool busy) {
    if (busy) unawaited(_pause());
    setState(() => _busy = busy);
  }

  void _accept(List<EditRange> edits) {
    compilePlan(_source.durationMs, [..._edits, ...edits]);
    setState(() {
      _edits.addAll(edits);
      _exportPath = null;
      _error = null;
    });
  }

  void _restore(int start, int end, EditKind? kind) {
    final restored = restoreEdits(_edits, start, end, kind: kind);
    setState(() {
      _edits
        ..clear()
        ..addAll(restored);
      _exportPath = null;
      _error = null;
    });
  }

  Future<bool> _confirmLeave({bool replace = false}) async {
    if (_edits.isEmpty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(replace ? 'Replace this video?' : 'Leave this edit?'),
            content: const Text(
              'These changes are not saved as a project. Your original video stays untouched.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(replace ? 'Replace video' : 'Leave edit'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _leave() async {
    if (_busy || !await _confirmLeave() || !mounted) return;
    await _pause();
    if (!mounted) return;
    setState(() => _allowLeave = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context);
  }

  Future<void> _replace() async {
    if (!await _confirmLeave(replace: true) || !mounted) return;
    await _pause();
    setState(() => _busy = true);
    try {
      final source = await widget.engine.importVideo();
      if (source != null && mounted) {
        setState(() {
          _source = source;
          _transcript = GlobalKey<TranscriptPanelState>();
          _edits.clear();
          _analysis = null;
          _actions = null;
          _exportPath = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _watchOriginal() async {
    try {
      await _media.preview(_source.path, compilePlan(_source.durationMs, []));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _timing() async {
    await _pause();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      builder: (_) => FineTuneSheet(
        source: _source,
        media: _media,
        edits: _edits,
        analysis: _analysis,
        onAnalysis: (analysis) => setState(() => _analysis = analysis),
        onActivity: _activity,
        onApply: _accept,
      ),
    );
  }

  Future<void> _settings() async {
    await _pause();
    await _transcript.currentState?.openSettings();
  }

  Future<void> _review() async {
    await _pause();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReviewScreen(
          source: _source,
          media: _media,
          edits: _edits,
          initialExportPath: _exportPath,
          onRemove: (index) => setState(() {
            _edits.removeAt(index);
            _exportPath = null;
          }),
          onExported: (path) => setState(() => _exportPath = path),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: _allowLeave || (_edits.isEmpty && !_busy),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back to home',
            onPressed: _busy ? null : _leave,
            icon: const Icon(Icons.arrow_back),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _source.name ?? 'Your video',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                'ORIGINAL · ${videoClock(Duration(milliseconds: _source.durationMs))}',
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 1,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            PopupMenuButton<String>(
              enabled: !_busy,
              tooltip: 'Video options',
              onSelected: (value) {
                if (value == 'replace') _replace();
                if (value == 'language') _settings();
                if (value == 'timing') _timing();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'replace', child: Text('Replace video')),
                PopupMenuItem(
                  value: 'language',
                  child: Text('Language & downloads'),
                ),
                PopupMenuItem(value: 'timing', child: Text('Fine-tune timing')),
              ],
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(top: BorderSide(color: colors.outlineVariant)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_actions != null) ...[
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: math.max(
                        110,
                        MediaQuery.sizeOf(context).height * .26,
                      ),
                    ),
                    child: SingleChildScrollView(
                      child: TranscriptActionBar(
                        actions: _actions!,
                        enabled: !_busy,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('review-changes'),
                    onPressed: _busy || _edits.isEmpty ? null : _review,
                    icon: const Icon(Icons.checklist_rounded, size: 19),
                    label: Text(
                      'Review ${_edits.length} ${_edits.length == 1 ? 'change' : 'changes'}',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        body: SafeArea(
          bottom: false,
          child: ListView(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: math.min(
                    270,
                    MediaQuery.sizeOf(context).height * .29,
                  ),
                ),
                child: SourceVideoPlayer(
                  key: _player,
                  source: _source,
                  enabled: !_busy,
                  onOpenOriginal: _watchOriginal,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: colors.onSurface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Transcript',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.surface,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _busy ? null : _timing,
                      icon: const Icon(Icons.tune, size: 17),
                      label: const Text('Fine-tune timing'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Column(
                  children: [
                    TranscriptPanel(
                      key: _transcript,
                      engine: widget.transcriptionEngine,
                      media: _media,
                      source: _source,
                      edits: _edits,
                      enabled: !_busy,
                      analysis: _analysis,
                      onAnalysis: (a) => setState(() => _analysis = a),
                      onBusyChanged: _activity,
                      onAdd: (edit) => _accept([edit]),
                      onSelectionChanged: (actions) =>
                          setState(() => _actions = actions),
                      onRestoreRange: _restore,
                    ),
                    if (_error != null)
                      Text(_error!, style: TextStyle(color: colors.error)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
