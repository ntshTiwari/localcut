import '../projects/project.dart';
import '../projects/project_repository.dart';
import '../projects/project_autosave.dart';
import '../transcript/transcript.dart';
import 'package:flutter/scheduler.dart';
import '../core/pause_review.dart';
import 'selection_screen.dart';
import 'inline_preview.dart';
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
import 'timing_screen.dart';
import 'playback_media_engine.dart';
import 'review_screen.dart';
import 'source_video_player.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({
    super.key,
    required this.initialSource,
    required this.engine,
    required this.transcriptionEngine,
    this.initialProject,
    this.projects,
  });
  final LocalProject? initialProject;
  final ProjectRepository? projects;
  final SourceVideo initialSource;
  final MediaEngine engine;
  final TranscriptionEngine transcriptionEngine;
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen>
    with WidgetsBindingObserver {
  LocalProject? _project;
  ProjectAutosave? _autosave;
  final Map<TranscriptLanguage, VideoTranscript> _transcripts = {};
  TranscriptLanguage _language = TranscriptLanguage.english;
  int _playbackMs = 0, _lastPlaybackSave = 0;
  bool _savePosted = false, _recoveryNotice = false, _saveFailureShown = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _project = widget.initialProject;
    if (_project case final project?) {
      _edits.addAll(project.edits);
      _analysis = project.analysis;
      _transcripts.addAll(project.transcripts);
      _language = project.language;
      _playbackMs = project.playbackMs;
      _lastPlaybackSave = _playbackMs;
      _exportPath = project.exportPath;
      _recoveryNotice = project.recovered;
      _pauseReview.dispose();
      _pauseReview = PauseReviewSession.fromMap(
        project.pauseReview,
        project.source.durationMs,
      );
    }
    _pauseReview.addListener(_scheduleSave);
    _pageScroll.addListener(_scheduleSave);
    _setupAutosave();
  }

  void _setupAutosave() {
    if (widget.projects == null || _project == null) return;
    _autosave = ProjectAutosave(
      repository: widget.projects!,
      capture: _capture,
      onSaved: (snapshot) {
        _project = snapshot;
      },
    )..addListener(_saveStateChanged);
  }

  void _saveStateChanged() {
    if (_autosave?.state == SaveState.saved) _saveFailureShown = false;
    if (_autosave?.state != SaveState.failed || _saveFailureShown) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _autosave?.state != SaveState.failed ||
          _saveFailureShown) {
        return;
      }
      _saveFailureShown = true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Autosave failed. Retry before closing the project.',
          ),
          action: SnackBarAction(
            label: 'Retry autosave',
            onPressed: () {
              final saver = _autosave;
              if (saver != null) {
                unawaited(saver.flush().catchError((Object _) {}));
              }
            },
          ),
        ),
      );
    });
  }

  LocalProject _capture() => _project!.copyWith(
    updatedAt: DateTime.now(),
    edits: _edits,
    transcripts: _transcripts,
    language: _language,
    analysis: _analysis,
    pauseReview: _pauseReview.toMap(),
    scrollOffset: _pageScroll.hasClients
        ? _pageScroll.offset.clamp(0, double.infinity)
        : _project!.scrollOffset,
    playbackMs: _playbackMs.clamp(0, _source.durationMs),
    exportPath: _exportPath,
    clearExport: _exportPath == null,
    recovered: false,
  );
  void _scheduleSave() {
    if (!mounted || _autosave == null) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_savePosted) return;
      _savePosted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _savePosted = false;
        if (mounted) _autosave?.schedule();
      });
    } else {
      _autosave!.schedule();
    }
  }

  Future<void> _flushSave() async {
    if (_autosave == null) return;
    _scheduleSave();
    await _autosave!.flush();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_flushSave().catchError((Object _) {}));
    }
  }

  void _receivedAnalysis(AudioAnalysis analysis) {
    setState(() => _analysis = analysis);
    _scheduleSave();
  }

  Widget _saveStatus() {
    final autosave = _autosave;
    if (autosave == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: autosave,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  autosave.state == SaveState.failed
                      ? Icons.error_outline
                      : Icons.save_outlined,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(switch (autosave.state) {
                    SaveState.saved => 'Saved on this device',
                    SaveState.pending => 'Changes waiting to save…',
                    SaveState.saving => 'Saving project…',
                    SaveState.failed => 'Could not autosave',
                  }, style: Theme.of(context).textTheme.bodySmall),
                ),
                if (autosave.state == SaveState.failed)
                  TextButton(
                    onPressed: () =>
                        unawaited(autosave.flush().catchError((Object _) {})),
                    child: const Text('Retry save'),
                  ),
              ],
            ),
            if (autosave.state == SaveState.failed)
              Text(
                autosave.error ?? 'Free storage and retry before leaving.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_recoveryNotice)
              const Text(
                'Recovered a previous autosave. Check your latest changes.',
                style: TextStyle(fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }

  late SourceVideo _source = widget.initialSource;
  late final MediaEngine _media = PlaybackMediaEngine(
    widget.engine,
    _pause,
    onPreview: _preview.show,
  );
  final _preview = InlinePreviewController();
  var _pauseReview = PauseReviewSession();
  late final _pageScroll = ScrollController(
    initialScrollOffset: widget.initialProject?.scrollOffset ?? 0,
  );
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autosave?.dispose();
    _pauseReview.removeListener(_scheduleSave);
    _pageScroll.removeListener(_scheduleSave);
    _pauseReview.dispose();
    _pageScroll.dispose();
    _selection.dispose();
    _selectionBusy.dispose();
    _selectionError.dispose();
    _preview.dispose();
    super.dispose();
  }

  final _player = GlobalKey<SourceVideoPlayerState>();
  var _transcript = GlobalKey<TranscriptPanelState>();
  final List<EditRange> _edits = [];
  AudioAnalysis? _analysis;
  TranscriptActions? _actions;
  final _selection = ValueNotifier<TranscriptActions?>(null);
  final _selectionBusy = ValueNotifier(false);
  final _selectionError = ValueNotifier<String?>(null);
  bool _selectionOpen = false;

  void _selected(TranscriptActions? actions) {
    setState(() => _actions = actions);
    _selection.value = actions;
  }

  Future<void> _openSelection() async {
    if (_selectionOpen || _actions == null || !mounted) return;
    _selectionOpen = true;
    _selectionError.value = null;
    await _pause();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SelectionScreen(
          actions: _selection,
          busy: _selectionBusy,
          error: _selectionError,
          preview: _preview,
        ),
      ),
    );
    _preview.close();
    _selectionOpen = false;
  }

  bool _busy = false, _allowLeave = false;
  String? _exportPath, _error;
  Future<void> _pause() async {
    await _player.currentState?.pause();
  }

  void _activity(bool busy) {
    if (!mounted) return;
    if (busy) unawaited(_pause());
    setState(() => _busy = busy);
    _selectionBusy.value = busy;
  }

  void _accept(List<EditRange> edits) {
    compilePlan(_source.durationMs, [..._edits, ...edits]);
    setState(() {
      _edits.addAll(edits);
      _exportPath = null;
      _error = null;
    });
    _scheduleSave();
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
    _scheduleSave();
  }

  Future<bool> _confirmLeave({bool replace = false}) async {
    if (_project != null || _edits.isEmpty) return true;
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
    try {
      await _flushSave();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not save the latest changes. Retry autosave before leaving.',
            ),
          ),
        );
      }
      return;
    }
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
      await _flushSave();
      final source = await widget.engine.importVideo();
      if (source != null && mounted) {
        final nextProject = widget.projects == null
            ? null
            : await widget.projects!.create(source);
        if (!mounted) return;
        _autosave?.dispose();
        _autosave = null;
        setState(() {
          _preview.close();
          _pauseReview.removeListener(_scheduleSave);
          _pauseReview.dispose();
          _pauseReview = PauseReviewSession()..addListener(_scheduleSave);
          _project = nextProject;
          _transcripts.clear();
          _language = TranscriptLanguage.english;
          _playbackMs = 0;
          _lastPlaybackSave = 0;
          _recoveryNotice = false;
          _saveFailureShown = false;
          _source = source;
          _transcript = GlobalKey<TranscriptPanelState>();
          _edits.clear();
          _analysis = null;
          _actions = null;
          _selection.value = null;
          _selectionError.value = null;
          _exportPath = null;
        });
        if (_pageScroll.hasClients) _pageScroll.jumpTo(0);
        _setupAutosave();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _watchOriginal() async {
    if (_busy) return;
    _activity(true);
    try {
      await _media.preview(
        _source.path,
        compilePlan(_source.durationMs, []),
        label: 'Original video',
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Original video')),
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: InlinePreviewPane(
                controller: _preview,
                showPlaceholder: true,
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      _preview.close();
      if (mounted) _activity(false);
    }
  }

  Future<void> _timing() async {
    await _pause();
    _preview.close();
    if (!mounted) return;
    final proceed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => TimingScreen(
          source: _source,
          media: widget.engine,
          edits: _edits,
          analysis: _analysis,
          pauseSession: _pauseReview,
          onAnalysis: _receivedAnalysis,
          onActivity: _activity,
          onApply: _accept,
        ),
      ),
    );
    if (!mounted) return;
    setState(() {});
    if (proceed == true && _edits.isNotEmpty) await _review();
  }

  Future<void> _settings() async {
    await _pause();
    _preview.close();
    await _transcript.currentState?.openSettings();
  }

  Future<void> _review() async {
    await _pause();
    if (!mounted) return;
    _preview.close();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReviewScreen(
          source: _source,
          media: widget.engine,
          edits: _edits,
          initialExportPath: _exportPath,
          onRemove: (index) {
            setState(() {
              _edits.removeAt(index);
              _exportPath = null;
            });
            _scheduleSave();
          },
          onExported: (path) {
            setState(() => _exportPath = path);
            _scheduleSave();
          },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: _allowLeave || (_project == null && _edits.isEmpty && !_busy),
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
                _project?.title ?? _source.name ?? 'Your video',
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
                PopupMenuItem(
                  value: 'replace',
                  child: Text('Import another video'),
                ),
                PopupMenuItem(
                  value: 'language',
                  child: Text('Language & downloads'),
                ),
                PopupMenuItem(value: 'timing', child: Text('Timing & pauses')),
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
                _saveStatus(),
                if (_actions != null) ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : _actions!.choosingPhrase
                          ? _actions!.onPhrase
                          : _openSelection,
                      icon: Icon(
                        _actions!.choosingPhrase
                            ? Icons.close
                            : Icons.edit_outlined,
                      ),
                      label: Text(
                        _actions!.choosingPhrase
                            ? 'Cancel phrase selection'
                            : 'Edit selected section',
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
          child: Scrollbar(
            controller: _pageScroll,
            thumbVisibility: true,
            child: ListView(
              controller: _pageScroll,
              children: [
                AnimatedBuilder(
                  animation: _preview,
                  builder: (_, _) => Visibility(
                    visible: _preview.path == null,
                    maintainState: true,
                    child: ConstrainedBox(
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
                        initialPositionMs: _playbackMs,
                        onPositionChanged: (position) {
                          _playbackMs = position.clamp(0, _source.durationMs);
                          if ((_playbackMs - _lastPlaybackSave).abs() >= 5000) {
                            _lastPlaybackSave = _playbackMs;
                            _scheduleSave();
                          }
                        },
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      enabled: !_busy,
                      onTap: _busy ? null : _timing,
                      leading: const Icon(Icons.tune),
                      trailing: const Icon(Icons.chevron_right),
                      title: const Text('Timing & pauses'),
                      subtitle: const Text(
                        'Open waveform, silence suggestions and exact ranges',
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    'Transcript',
                    style: Theme.of(context).textTheme.titleLarge,
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
                        onAnalysis: _receivedAnalysis,
                        initialLanguage: _language,
                        initialTranscripts: _transcripts,
                        onStateChanged: (language, transcripts) {
                          _language = language;
                          _transcripts
                            ..clear()
                            ..addAll(transcripts);
                          _scheduleSave();
                        },
                        onBusyChanged: _activity,
                        onAdd: (edit) => _accept([edit]),
                        onSelectionChanged: _selected,
                        onSelectionRequested: _openSelection,
                        onError: (error) => _selectionError.value = error,
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
      ),
    );
  }
}
