import '../core/context_preview.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/edit_plan.dart';
import '../core/silence_detection.dart';
import 'transcript_gaps.dart';
import 'transcript_actions.dart';
import 'transcript_document.dart';
import '../media/media_engine.dart';
import 'transcript.dart';
import 'transcription_engine.dart';

class TranscriptPanel extends StatefulWidget {
  const TranscriptPanel({
    super.key,
    required this.engine,
    required this.media,
    required this.source,
    required this.edits,
    required this.enabled,
    required this.onBusyChanged,
    required this.onAdd,
    this.onSelectionChanged,
    this.onSelectionRequested,
    this.onRestoreRange,
    this.analysis,
    this.onAnalysis,
    this.onError,
    this.initialLanguage = TranscriptLanguage.english,
    this.initialTranscripts = const {},
    this.onStateChanged,
  });
  final TranscriptionEngine engine;
  final MediaEngine media;
  final SourceVideo source;
  final List<EditRange> edits;
  final bool enabled;
  final ValueChanged<bool> onBusyChanged;
  final ValueChanged<EditRange> onAdd;
  final ValueChanged<TranscriptActions?>? onSelectionChanged;
  final VoidCallback? onSelectionRequested;
  final void Function(int startMs, int endMs, EditKind? kind)? onRestoreRange;
  final AudioAnalysis? analysis;
  final ValueChanged<AudioAnalysis>? onAnalysis;
  final ValueChanged<String?>? onError;
  final TranscriptLanguage initialLanguage;
  final Map<TranscriptLanguage, VideoTranscript> initialTranscripts;
  final void Function(
    TranscriptLanguage,
    Map<TranscriptLanguage, VideoTranscript>,
  )?
  onStateChanged;

  @override
  State<TranscriptPanel> createState() => TranscriptPanelState();
}

class TranscriptPanelState extends State<TranscriptPanel> {
  final ValueNotifier<int> _sheetUpdates = ValueNotifier(0);
  void _update(VoidCallback action) {
    if (!mounted) return;
    super.setState(action);
    _sheetUpdates.value++;
  }

  bool _settingsOpen = false;
  Future<void> openSettings() async {
    if (_settingsOpen) return;
    _update(() => _settingsOpen = true);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetContext) => AnimatedBuilder(
        animation: _sheetUpdates,
        builder: (_, _) => PopScope(
          canPop: !_working,
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .8,
            child: Column(
              children: [
                ListTile(
                  title: const Text('Transcript settings'),
                  trailing: IconButton(
                    tooltip: 'Close transcript settings',
                    icon: const Icon(Icons.close),
                    onPressed: _working
                        ? null
                        : () => Navigator.pop(sheetContext),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: _content(sheetContext, settingsOnly: true),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted) _update(() => _settingsOpen = false);
  }

  TranscriptLanguage _language = TranscriptLanguage.english;
  final Map<TranscriptLanguage, VideoTranscript> _transcripts = {};
  SpeechModel? _model;
  String? _error;
  bool _checking = true;
  bool _working = false;
  bool _canCancel = false;
  bool _cancelled = false;
  SpeechProgress? _progress;
  Timer? _timer;
  bool _polling = false;
  int? _anchor;
  int? _end;
  int? _selectedGap;
  bool _choosingPhrase = false;
  bool _findingPauses = false;
  AudioAnalysis? _analysis;
  String? _pauseNotice;
  VideoTranscript? _gapsForTranscript;
  AudioAnalysis? _gapsForAnalysis;
  List<TranscriptGap> _cachedGaps = [];
  String _lastSelectionSignature = 'none';
  AudioAnalysis? get _availableAnalysis => widget.analysis ?? _analysis;
  List<TranscriptGap> get _gaps {
    final transcript = _transcript;
    if (transcript == null) return [];
    if (!identical(transcript, _gapsForTranscript) ||
        !identical(_availableAnalysis, _gapsForAnalysis)) {
      _cachedGaps = transcriptGaps(
        transcript,
        widget.source.durationMs,
        _availableAnalysis,
      );
      _gapsForTranscript = transcript;
      _gapsForAnalysis = _availableAnalysis;
    }
    return _cachedGaps;
  }

  VideoTranscript? get _transcript => _transcripts[_language];
  bool get _enabled => widget.enabled && !_working;

  @override
  void initState() {
    super.initState();
    _language = widget.initialLanguage;
    _transcripts.addAll(widget.initialTranscripts);
    _refreshModel();
  }

  @override
  void didUpdateWidget(covariant TranscriptPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_anchor != null || _selectedGap != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _publishSelection();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sheetUpdates.dispose();
    super.dispose();
  }

  Future<void> _refreshModel() async {
    final language = _language;
    try {
      final model = await widget.engine.model(language);
      if (mounted && language == _language) {
        _update(() {
          _model = model;
          _checking = false;
        });
      }
    } catch (e) {
      if (mounted && language == _language) {
        _update(() {
          _checking = false;
          _error = (e is PlatformException
              ? e.message ?? 'Speech operation failed.'
              : e.toString());
        });
      }
    }
  }

  Future<void> _poll() async {
    if (_polling || _findingPauses) return;
    _polling = true;
    try {
      final progress = await widget.engine.progress();
      if (mounted && _working) _update(() => _progress = progress);
    } catch (_) {
      /* The main operation reports actionable errors. */
    } finally {
      _polling = false;
    }
  }

  Future<void> _perform(
    Future<void> Function() action, {
    bool cancellable = false,
    bool preview = false,
  }) async {
    _update(() {
      _working = true;
      _canCancel = cancellable;
      _cancelled = false;
      _error = null;
      _progress = preview ? const SpeechProgress('previewing', null, 0) : null;
    });
    widget.onBusyChanged(true);
    if (cancellable) {
      _timer = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => _poll(),
      );
    }
    try {
      await action();
      if (_cancelled) throw StateError('Canceled');
    } catch (e) {
      if (mounted) {
        _update(
          () => _error = _cancelled
              ? 'Canceled. Existing transcript and edits are unchanged.'
              : (e is PlatformException
                    ? e.message ?? 'Speech operation failed.'
                    : e.toString()),
        );
      }
    } finally {
      _timer?.cancel();
      _timer = null;
      if (mounted) {
        _update(() {
          _working = false;
          _canCancel = false;
          _progress = null;
        });
        widget.onBusyChanged(false);
        widget.onError?.call(_error);
        await _refreshModel();
      }
    }
  }

  Future<void> _generate() => _perform(() async {
    _clearSelection();
    if (widget.source.hasAudio == false) {
      throw StateError(
        'This video has no audio track. No model download is needed.',
      );
    }
    final model = await widget.engine.model(_language);
    if (_cancelled) return;
    if (!model.ready) {
      if (mounted) {
        _update(() => _progress = const SpeechProgress('downloading', null, 0));
      }
      await widget.engine.download(_language);
    }
    if (_cancelled) return;
    if (mounted) {
      _update(() => _progress = const SpeechProgress('loading', null, 0));
    }
    final transcript = await widget.engine.transcribe(
      widget.source.path,
      widget.source.durationMs,
      _language,
    );
    AudioAnalysis? analysis = _availableAnalysis;
    if (analysis == null && !_cancelled) {
      _findingPauses = true;
      if (mounted) {
        _update(
          () => _progress = const SpeechProgress('checkingPauses', null, 0),
        );
      }
      try {
        analysis = await widget.media.analyzeAudio(widget.source.path);
      } catch (_) {
        if (mounted && !_cancelled) {
          _update(
            () => _pauseNotice =
                'Transcript ready. Pause checking is unavailable; you can still censor words.',
          );
        }
      } finally {
        _findingPauses = false;
      }
    }
    if (mounted && !_cancelled) {
      _update(() {
        _analysis = analysis;
        if (analysis != null) _pauseNotice = null;
        _transcripts[_language] = transcript;
        _anchor = null;
        _end = null;
      });
      if (analysis != null) widget.onAnalysis?.call(analysis);
      widget.onStateChanged?.call(_language, Map.of(_transcripts));
    }
  }, cancellable: true);

  EditRange get _mute =>
      transcriptMute(_transcript!, _anchor!, _end!, widget.source.durationMs);

  void _clearSelection() {
    _update(() {
      _anchor = null;
      _end = null;
      _selectedGap = null;
      _choosingPhrase = false;
    });
    _publishSelection();
  }

  void _selectWord(int index) {
    _update(() {
      _selectedGap = null;
      _error = null;
      if (_choosingPhrase && _anchor != null) {
        _end = index;
        _choosingPhrase = false;
      } else {
        _anchor = index;
        _end = index;
      }
    });
    _publishSelection(force: true);
    widget.onSelectionRequested?.call();
  }

  void _selectGap(TranscriptGap gap) {
    _update(() {
      _selectedGap = gap.beforeWord;
      _anchor = null;
      _end = null;
      _choosingPhrase = false;
      _error = null;
    });
    _publishSelection(force: true);
    widget.onSelectionRequested?.call();
  }

  Future<void> _playRange(int start, int end) => _perform(
    () => widget.media.preview(widget.source.path, [
      RenderSegment(start, end, false),
    ]),
    preview: true,
  );

  Future<void> _hearRange(
    int start,
    int end, {
    bool remove = false,
    bool mute = false,
    int? effectStart,
    int? effectEnd,
  }) => _perform(
    () => widget.media.preview(
      widget.source.path,
      contextPreview(
        widget.source.durationMs,
        start,
        end,
        remove: remove,
        mute: mute,
        effectStartMs: effectStart,
        effectEndMs: effectEnd,
      ),
      label: contextLabel(remove: remove, mute: mute),
    ),
    preview: true,
  );

  void _apply(EditRange edit) {
    try {
      compilePlan(widget.source.durationMs, [...widget.edits, edit]);
      widget.onAdd(edit);
      _clearSelection();
    } catch (e) {
      _update(() => _error = e.toString());
      widget.onError?.call(_error);
    }
  }

  Future<void> _checkPauses() => _perform(() async {
    _findingPauses = true;
    _update(() => _progress = const SpeechProgress('checkingPauses', null, 0));
    try {
      final analysis = await widget.media.analyzeAudio(widget.source.path);
      if (mounted && !_cancelled) {
        _update(() {
          _analysis = analysis;
          _pauseNotice = null;
        });
        widget.onAnalysis?.call(analysis);
        _publishSelection();
      }
    } finally {
      _findingPauses = false;
    }
  }, cancellable: true);

  TranscriptActions? get _actions {
    if (_selectedGap != null) {
      final found = _gaps.where((gap) => gap.beforeWord == _selectedGap);
      if (found.isEmpty) return null;
      final gap = found.first;
      final removed = coveredMilliseconds(
        widget.edits,
        gap.scopeStart,
        gap.scopeEnd,
        EditKind.cut,
      );
      final shortened = removed > 0;
      return TranscriptActions(
        title:
            '${gap.confirmed ? 'Pause' : 'Gap'} · ${seconds(gap.durationMs)}',
        detail: shortened
            ? '${seconds(gap.durationMs - removed)} remains. Restore puts the trimmed time back.'
            : gap.confirmed
            ? 'Remove ${seconds(gap.durationMs - 300)} · keep 0.3s of breathing room.'
            : 'Silence is not confirmed. Listen, or use Timing & pauses.',
        onClear: _clearSelection,
        startMs: gap.startMs,
        endMs: gap.endMs,
        onPlayRange: () => _playRange(gap.startMs, gap.endMs),
        onHear: () => _hearRange(gap.startMs, gap.endMs),
        onHearRemoved: () => _hearRange(
          gap.startMs,
          gap.endMs,
          remove: true,
          effectStart: gap.confirmed ? gap.shorten().startMs : null,
          effectEnd: gap.confirmed ? gap.shorten().endMs : null,
        ),
        onShorten: gap.confirmed && !shortened
            ? () => _apply(gap.shorten())
            : null,
        onRestore: shortened && widget.onRestoreRange != null
            ? () {
                widget.onRestoreRange!(
                  gap.scopeStart,
                  gap.scopeEnd,
                  EditKind.cut,
                );
                _clearSelection();
              }
            : null,
      );
    }
    if (_anchor == null || _transcript == null) return null;
    final first = math.min(_anchor!, _end!), last = math.max(_anchor!, _end!);
    final text = _transcript!.words
        .sublist(first, last + 1)
        .map((word) => word.text)
        .join(' ');
    EditRange? mute;
    try {
      mute = _mute;
    } catch (_) {
      /* Text remains selectable; timing is unavailable. */
    }
    final range = mute;
    final hasEdits =
        range != null &&
        widget.edits.any(
          (edit) => edit.startMs < range.endMs && edit.endMs > range.startMs,
        );
    final censored =
        range != null &&
        coveredMilliseconds(
              widget.edits,
              range.startMs,
              range.endMs,
              EditKind.mute,
            ) ==
            range.endMs - range.startMs;
    final trimmed =
        range != null &&
        coveredMilliseconds(
              widget.edits,
              range.startMs,
              range.endMs,
              EditKind.cut,
            ) ==
            range.endMs - range.startMs;
    return TranscriptActions(
      title: _choosingPhrase ? 'Now tap the last word' : text,
      detail: range == null
          ? 'Timing unavailable. Use Timing & pauses to locate this text.'
          : _choosingPhrase
          ? 'Select the end of the phrase in the transcript.'
          : censored
          ? 'Already censored. Restore brings the sound back.'
          : trimmed
          ? 'This selection is trimmed. Restore puts it back.'
          : '${first == last ? 'Word' : 'Phrase'} · ${seconds(range.endMs - range.startMs)} · censoring keeps video length unchanged.',
      onClear: _clearSelection,
      startMs: range?.startMs,
      endMs: range?.endMs,
      onPlayRange: range == null
          ? null
          : () => _playRange(range.startMs, range.endMs),
      contextMute: true,
      onHearRemoved: range == null
          ? null
          : () => _hearRange(range.startMs, range.endMs, mute: true),
      onHear: range == null
          ? null
          : () => _hearRange(range.startMs, range.endMs),
      onCensor: range == null || censored || trimmed || _choosingPhrase
          ? null
          : () => _apply(range),
      onRestore: hasEdits && widget.onRestoreRange != null
          ? () {
              widget.onRestoreRange!(range.startMs, range.endMs, null);
              _clearSelection();
            }
          : null,
      choosingPhrase: _choosingPhrase,
      onPhrase: () {
        _update(() => _choosingPhrase = !_choosingPhrase);
        _publishSelection();
      },
    );
  }

  void _publishSelection({bool force = false}) {
    final signature = _anchor == null && _selectedGap == null
        ? 'none'
        : '${_language.code}|$_anchor|$_end|$_selectedGap|$_choosingPhrase|${_gaps.where((g) => g.beforeWord == _selectedGap).map((g) => '${g.quietStartMs}:${g.quietEndMs}').join()}|${widget.edits.map((e) => '${e.kind}:${e.startMs}:${e.endMs}').join(',')}';
    if (!force && signature == _lastSelectionSignature) return;
    _lastSelectionSignature = signature;
    widget.onSelectionChanged?.call(_actions);
  }

  Future<void> _removeModel() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove model download?'),
        content: Text(
          _model!.shared
              ? 'Hindi and Hindi–English share this model. Both will need a download again. Existing transcripts and videos stay on the phone.'
              : 'English transcription will need a download again. Existing transcripts and videos stay on the phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep download'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove download'),
          ),
        ],
      ),
    );
    if (approved == true && mounted) {
      await _perform(() => widget.engine.deleteModel(_language));
    }
  }

  @override
  Widget build(BuildContext context) => _content(context);

  Widget _content(BuildContext context, {bool settingsOnly = false}) {
    final transcript = _transcript, model = _model;
    final progress = _progress;
    final settings = <Widget>[
      DropdownButtonFormField<TranscriptLanguage>(
        key: const Key('transcript-language'),
        initialValue: _language,
        decoration: const InputDecoration(
          labelText: 'Video language',
          border: OutlineInputBorder(),
        ),
        items: TranscriptLanguage.values
            .map(
              (language) => DropdownMenuItem(
                value: language,
                child: Text(language.label),
              ),
            )
            .toList(),
        onChanged: !_enabled
            ? null
            : (language) {
                if (language == null) return;
                _update(() {
                  _language = language;
                  _model = null;
                  _checking = true;
                  _anchor = null;
                  _end = null;
                  _selectedGap = null;
                  _choosingPhrase = false;
                  _error = null;
                });
                _publishSelection();
                widget.onStateChanged?.call(_language, Map.of(_transcripts));
                _refreshModel();
              },
      ),
      const SizedBox(height: 8),
      const Text(
        'Audio and video stay on your phone. Internet is used only to download the selected model; transcription then works offline.',
      ),
      if (_language != TranscriptLanguage.english)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Hindi and mixed speech are experimental. Recognition may miss phrases; listen to the original before muting.',
          ),
        ),
      if (_checking)
        const Padding(
          padding: EdgeInsets.all(8),
          child: LinearProgressIndicator(),
        ),
      if (model != null) ...[
        const SizedBox(height: 8),
        Text(
          '${model.name} · ${model.sizeLabel} · ${model.ready ? 'Downloaded — ready offline' : 'Not downloaded'}',
        ),
        if (model.shared)
          const Text('One shared download for Hindi and Hindi–English.'),
      ],
      FilledButton.icon(
        onPressed: _enabled && !_checking && model != null
            ? () async {
                await _generate();
                if (mounted &&
                    _error == null &&
                    _transcript != null &&
                    settingsOnly &&
                    context.mounted) {
                  Navigator.of(context).pop();
                }
              }
            : null,
        icon: const Icon(Icons.subtitles_outlined),
        label: Text(
          model == null || model.ready
              ? (transcript == null
                    ? 'Generate transcript'
                    : 'Regenerate transcript')
              : 'Download ${model.sizeLabel} & transcribe',
        ),
      ),
      if (model?.ready == true)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _enabled ? _removeModel : null,
            child: const Text('Remove model download'),
          ),
        ),
    ];
    final actions = _actions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (settingsOnly)
          ...settings
        else if (transcript == null) ...[
          const SizedBox(height: 16),
          Text(
            'Start with your words',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Turn speech into a transcript. Tap words to censor them and pauses to shorten them.',
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _enabled ? openSettings : null,
            icon: const Icon(Icons.subtitles_outlined),
            label: const Text('Create transcript'),
          ),
          const SizedBox(height: 12),
          const Text(
            'On-device editing. Your video stays with you.',
            textAlign: TextAlign.center,
          ),
        ] else ...[
          const Text('Tap a word to censor it. Tap a pause to shorten it.'),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _enabled ? openSettings : null,
              child: const Text('Language & downloads'),
            ),
          ),
        ],
        if (_working && (settingsOnly || !_settingsOpen)) ...[
          LinearProgressIndicator(value: progress?.fraction),
          Text(switch (progress?.phase) {
            'downloading' =>
              'Downloading model… ${((progress?.downloadedBytes ?? 0) / 1000000).toStringAsFixed(1)} MB',
            'verifying' => 'Verifying model download…',
            'transcribing' => 'Transcribing on this device…',
            'loading' => 'Loading speech model…',
            'previewing' => 'Opening original range…',
            'checkingPauses' => 'Checking pauses on this device…',
            _ => 'Preparing transcript…',
          }),
          if (_canCancel)
            TextButton(
              onPressed: _cancelled
                  ? null
                  : () async {
                      _update(() => _cancelled = true);
                      try {
                        await widget.engine.cancel();
                        if (_findingPauses) await widget.media.cancelAnalysis();
                      } catch (e) {
                        if (mounted) {
                          _update(() {
                            _cancelled = false;
                            _error = (e is PlatformException
                                ? e.message ?? 'Speech operation failed.'
                                : e.toString());
                          });
                        }
                      }
                    },
              child: const Text('Cancel transcription'),
            ),
        ],

        if (!settingsOnly && transcript != null) ...[
          if (transcript.words.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'No speech was recognized. Try another language or a clearer recording.',
              ),
            )
          else
            TranscriptDocument(
              transcript: transcript,
              gaps: _gaps,
              edits: widget.edits,
              enabled: _enabled,
              firstWord: _anchor == null ? null : math.min(_anchor!, _end!),
              lastWord: _anchor == null ? null : math.max(_anchor!, _end!),
              selectedGap: _selectedGap,
              onWord: _selectWord,
              onGap: _selectGap,
            ),
          const Text(
            'Pauses are checked against the audio. Word timing is approximate; review before exporting.',
            style: TextStyle(fontSize: 12),
          ),
          if (_availableAnalysis == null && transcript.words.isNotEmpty)
            TextButton.icon(
              onPressed: _enabled ? _checkPauses : null,
              icon: const Icon(Icons.refresh),
              label: const Text('Check pauses'),
            ),
          if (_pauseNotice != null) Text(_pauseNotice!),
        ],
        if (!settingsOnly &&
            widget.onSelectionChanged == null &&
            actions != null)
          TranscriptActionBar(actions: actions, enabled: _enabled),
        if (_error != null && (settingsOnly || !_settingsOpen)) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SelectableText(_error!),
          ),
          if (!_working && model == null)
            TextButton(
              onPressed: _enabled
                  ? () {
                      _update(() => _checking = true);
                      _refreshModel();
                    }
                  : null,
              child: const Text('Retry model check'),
            ),
        ],
      ],
    );
  }
}
