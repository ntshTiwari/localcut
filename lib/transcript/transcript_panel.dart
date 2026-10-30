import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/edit_plan.dart';
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
  });
  final TranscriptionEngine engine;
  final MediaEngine media;
  final SourceVideo source;
  final List<EditRange> edits;
  final bool enabled;
  final ValueChanged<bool> onBusyChanged;
  final ValueChanged<EditRange> onAdd;
  @override
  State<TranscriptPanel> createState() => _TranscriptPanelState();
}

class _TranscriptPanelState extends State<TranscriptPanel> {
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
  VideoTranscript? get _transcript => _transcripts[_language];
  bool get _enabled => widget.enabled && !_working;

  @override
  void initState() {
    super.initState();
    _refreshModel();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refreshModel() async {
    final language = _language;
    try {
      final model = await widget.engine.model(language);
      if (mounted && language == _language) {
        setState(() {
          _model = model;
          _checking = false;
        });
      }
    } catch (e) {
      if (mounted && language == _language) {
        setState(() {
          _checking = false;
          _error = (e is PlatformException
              ? e.message ?? 'Speech operation failed.'
              : e.toString());
        });
      }
    }
  }

  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    try {
      final progress = await widget.engine.progress();
      if (mounted && _working) setState(() => _progress = progress);
    } catch (_) {
      /* The main operation reports actionable errors. */
    } finally {
      _polling = false;
    }
  }

  Future<void> _perform(
    Future<void> Function() action, {
    bool cancellable = false,
  }) async {
    setState(() {
      _working = true;
      _canCancel = cancellable;
      _cancelled = false;
      _error = null;
      _progress = null;
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
    } catch (e) {
      if (mounted) {
        setState(
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
        setState(() {
          _working = false;
          _canCancel = false;
          _progress = null;
        });
        widget.onBusyChanged(false);
        await _refreshModel();
      }
    }
  }

  Future<void> _generate() => _perform(() async {
    if (widget.source.hasAudio == false) {
      throw StateError(
        'This video has no audio track. No model download is needed.',
      );
    }
    final model = await widget.engine.model(_language);
    if (_cancelled) return;
    if (!model.ready) {
      if (mounted) {
        setState(
          () => _progress = const SpeechProgress('downloading', null, 0),
        );
      }
      await widget.engine.download(_language);
    }
    if (_cancelled) return;
    if (mounted) {
      setState(() => _progress = const SpeechProgress('loading', null, 0));
    }
    final transcript = await widget.engine.transcribe(
      widget.source.path,
      widget.source.durationMs,
      _language,
    );
    if (mounted && !_cancelled) {
      setState(() {
        _transcripts[_language] = transcript;
        _anchor = null;
        _end = null;
      });
    }
  }, cancellable: true);

  EditRange get _mute =>
      transcriptMute(_transcript!, _anchor!, _end!, widget.source.durationMs);

  Future<void> _hear(int index) async {
    final word = _transcript!.words[index];
    if (!word.aligned) {
      setState(
        () => _error =
            'Timing unavailable for this word. Use the waveform to find it.',
      );
      return;
    }
    await _perform(
      () => widget.media.preview(widget.source.path, [
        RenderSegment(
          math.max(0, word.startMs! - 500),
          math.min(widget.source.durationMs, word.endMs! + 700),
          false,
        ),
      ]),
    );
  }

  Future<void> _previewMute() => _perform(
    () => widget.media.preview(
      widget.source.path,
      compilePlan(widget.source.durationMs, [...widget.edits, _mute]),
    ),
  );

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

  Widget _word(int index) {
    final word = _transcript!.words[index];
    final colors = Theme.of(context).colorScheme;
    final first = _anchor == null ? -1 : math.min(_anchor!, _end!);
    final last = _anchor == null ? -1 : math.max(_anchor!, _end!);
    final selected = index >= first && index <= last;
    final overlapping = widget.edits.where(
      (e) => word.aligned && e.startMs < word.endMs! && e.endMs > word.startMs!,
    );
    final cut = overlapping.any((e) => e.kind == EditKind.cut);
    final muted = overlapping.any((e) => e.kind == EditKind.mute);
    return Semantics(
      label:
          '${word.text}${!word.aligned ? ', timing unavailable' : ''}${selected ? ', selected' : ''}${cut
              ? ', cut'
              : muted
              ? ', muted'
              : ''}',
      child: InkWell(
        key: ValueKey('transcript-word-$index'),
        onTap: !_enabled
            ? null
            : () {
                if (_anchor != null) {
                  setState(() {
                    _end = index;
                    _error = null;
                  });
                } else {
                  _hear(index);
                }
              },
        onLongPress: !_enabled
            ? null
            : () => setState(() {
                _anchor = index;
                _end = index;
                _error = null;
              }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? colors.primaryContainer
                : muted
                ? colors.secondaryContainer
                : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            word.text,
            style: TextStyle(
              fontSize: 17,
              height: 1.4,
              color: !word.aligned ? colors.outline : colors.onSurface,
              decoration: cut ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final transcript = _transcript;
    final model = _model;
    final progress = _progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Edit from the transcript',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
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
                  setState(() {
                    _language = language;
                    _model = null;
                    _checking = true;
                    _anchor = null;
                    _end = null;
                    _error = null;
                  });
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
          onPressed: _enabled && !_checking && model != null ? _generate : null,
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
        if (_working) ...[
          LinearProgressIndicator(value: progress?.fraction),
          Text(switch (progress?.phase) {
            'downloading' =>
              'Downloading model… ${((progress?.downloadedBytes ?? 0) / 1000000).toStringAsFixed(1)} MB',
            'verifying' => 'Verifying model download…',
            'transcribing' => 'Transcribing on this device…',
            'loading' => 'Loading speech model…',
            _ => 'Preparing transcript…',
          }),
          if (_canCancel)
            TextButton(
              onPressed: _cancelled
                  ? null
                  : () async {
                      setState(() => _cancelled = true);
                      try {
                        await widget.engine.cancel();
                      } catch (e) {
                        if (mounted) {
                          setState(() {
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
        if (transcript != null) ...[
          const SizedBox(height: 12),
          if (transcript.words.isEmpty)
            const Text(
              'No speech was recognized. Try another language or a clearer recording.',
            )
          else ...[
            const Text(
              'Tap a word to hear it. Long-press the first word, then tap the last word to select a phrase.',
            ),
            const Text(
              'Muted words are shaded; cuts are struck through. Selected words use a separate highlight. Word times are approximate—preview every change.',
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: math.min(
                320.0,
                math.max(96.0, transcript.words.length * 8.0),
              ),
              child: ListView.builder(
                key: const Key('transcript-text'),
                itemCount: (transcript.words.length / 25).ceil(),
                itemBuilder: (context, paragraph) {
                  final start = paragraph * 25;
                  final end = math.min(start + 25, transcript.words.length);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Wrap(
                      spacing: 2,
                      children: [for (var i = start; i < end; i++) _word(i)],
                    ),
                  );
                },
              ),
            ),
            if (_anchor != null) ...[
              Text(
                'Selected words ${math.min(_anchor!, _end!) + 1}–${math.max(_anchor!, _end!) + 1}',
              ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _enabled ? _previewMute : null,
                    child: const Text('Preview selected mute'),
                  ),
                  FilledButton(
                    onPressed: !_enabled
                        ? null
                        : () {
                            try {
                              final mute = _mute;
                              compilePlan(widget.source.durationMs, [
                                ...widget.edits,
                                mute,
                              ]);
                              widget.onAdd(mute);
                              setState(() {
                                _anchor = null;
                                _end = null;
                                _error = null;
                              });
                            } catch (e) {
                              setState(
                                () => _error = (e is PlatformException
                                    ? e.message ?? 'Speech operation failed.'
                                    : e.toString()),
                              );
                            }
                          },
                    child: const Text('Add selected mute'),
                  ),
                  TextButton(
                    onPressed: _enabled
                        ? () => setState(() {
                            _anchor = null;
                            _end = null;
                            _error = null;
                          })
                        : null,
                    child: const Text('Clear word selection'),
                  ),
                ],
              ),
            ],
          ],
        ],
        if (_error != null) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SelectableText(_error!),
          ),
          if (!_working && model == null)
            TextButton(
              onPressed: _enabled
                  ? () {
                      setState(() => _checking = true);
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
