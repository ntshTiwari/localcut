import '../core/pause_review.dart';
import '../core/edit_plan.dart';
import '../core/silence_detection.dart';
import '../media/media_engine.dart';
import '../transcript/transcript.dart';

class UnsupportedProjectVersion extends FormatException {
  const UnsupportedProjectVersion()
    : super('This project needs a newer version of LocalCut.');
}

String fileName(String path) => path.replaceAll('\\', '/').split('/').last;
String safeName(dynamic value) {
  if (value is! String ||
      value.isEmpty ||
      value == '.' ||
      value == '..' ||
      value.contains('/') ||
      value.contains('\\')) {
    throw const FormatException('Invalid project filename.');
  }
  return value;
}

String safeId(dynamic value) {
  if (value is! String || !RegExp(r'^[a-z0-9-]+$').hasMatch(value)) {
    throw const FormatException('Invalid project ID.');
  }
  return value;
}

class ProjectSummary {
  const ProjectSummary({
    required this.id,
    required this.title,
    required this.sourceFile,
    required this.durationMs,
    required this.createdAt,
    required this.updatedAt,
    required this.editCount,
  });
  final String id, title, sourceFile;
  final int durationMs, editCount;
  final DateTime createdAt, updatedAt;
  Map<String, dynamic> toMap() => {
    'version': 1,
    'id': id,
    'title': title,
    'sourceFile': sourceFile,
    'durationMs': durationMs,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'editCount': editCount,
  };
  factory ProjectSummary.fromMap(Map<String, dynamic> m) {
    if (m['version'] != 1) throw const UnsupportedProjectVersion();
    final title = m['title'] as String,
        duration = (m['durationMs'] as num).toInt(),
        count = (m['editCount'] as num).toInt();
    if (title.trim().isEmpty || duration <= 0 || count < 0) {
      throw const FormatException('Invalid project summary.');
    }
    return ProjectSummary(
      id: safeId(m['id']),
      title: title,
      sourceFile: safeName(m['sourceFile']),
      durationMs: duration,
      editCount: count,
      createdAt: DateTime.parse(m['createdAt']),
      updatedAt: DateTime.parse(m['updatedAt']),
    );
  }
}

class LocalProject {
  LocalProject({
    required this.id,
    required this.title,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    List<EditRange> edits = const [],
    Map<TranscriptLanguage, VideoTranscript> transcripts = const {},
    this.language = TranscriptLanguage.english,
    this.analysis,
    this.pauseReview = const {},
    this.scrollOffset = 0,
    this.playbackMs = 0,
    this.exportPath,
    this.recovered = false,
  }) : edits = List.unmodifiable(edits),
       transcripts = Map.unmodifiable(transcripts);
  final String id, title;
  final SourceVideo source;
  final DateTime createdAt, updatedAt;
  final List<EditRange> edits;
  final Map<TranscriptLanguage, VideoTranscript> transcripts;
  final TranscriptLanguage language;
  final AudioAnalysis? analysis;
  final Map<String, dynamic> pauseReview;
  final double scrollOffset;
  final int playbackMs;
  final String? exportPath;
  final bool recovered;
  ProjectSummary get summary => ProjectSummary(
    id: id,
    title: title,
    sourceFile: fileName(source.path),
    durationMs: source.durationMs,
    createdAt: createdAt,
    updatedAt: updatedAt,
    editCount: edits.length,
  );
  LocalProject copyWith({
    String? title,
    DateTime? updatedAt,
    List<EditRange>? edits,
    Map<TranscriptLanguage, VideoTranscript>? transcripts,
    TranscriptLanguage? language,
    AudioAnalysis? analysis,
    Map<String, dynamic>? pauseReview,
    double? scrollOffset,
    int? playbackMs,
    String? exportPath,
    bool clearExport = false,
    bool? recovered,
  }) => LocalProject(
    id: id,
    title: title ?? this.title,
    source: source,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    edits: edits ?? this.edits,
    transcripts: transcripts ?? this.transcripts,
    language: language ?? this.language,
    analysis: analysis ?? this.analysis,
    pauseReview: pauseReview ?? this.pauseReview,
    scrollOffset: scrollOffset ?? this.scrollOffset,
    playbackMs: playbackMs ?? this.playbackMs,
    exportPath: clearExport ? null : exportPath ?? this.exportPath,
    recovered: recovered ?? this.recovered,
  );
  Map<String, dynamic> toMap() => {
    ...summary.toMap(),
    'hasAudio': source.hasAudio,
    'sourceName': source.name,
    'edits': [
      for (final e in edits)
        {
          'startMs': e.startMs,
          'endMs': e.endMs,
          'kind': e.kind.name,
          'label': e.label,
        },
    ],
    'transcripts': {
      for (final entry in transcripts.entries)
        entry.key.code: {
          'words': [
            for (final w in entry.value.words)
              {'text': w.text, 'startMs': w.startMs, 'endMs': w.endMs},
          ],
        },
    },
    'language': language.code,
    'hasAnalysis': analysis != null,
    'pauseReview': pauseReview,
    'scrollOffset': scrollOffset,
    'playbackMs': playbackMs,
    'exportFile': exportPath == null ? null : fileName(exportPath!),
  };
  factory LocalProject.fromMap(
    Map<String, dynamic> m,
    String root, {
    AudioAnalysis? analysis,
    bool recovered = false,
  }) {
    final summary = ProjectSummary.fromMap(m);
    final edits = [
      for (final raw in m['edits'] as List)
        EditRange(
          (raw['startMs'] as num).toInt(),
          (raw['endMs'] as num).toInt(),
          EditKind.values.byName(raw['kind']),
          label: raw['label'] as String?,
        ),
    ];
    compilePlan(summary.durationMs, edits);
    final language = TranscriptLanguage.values.firstWhere(
      (l) => l.code == m['language'],
    );
    final transcripts = <TranscriptLanguage, VideoTranscript>{};
    for (final entry in (m['transcripts'] as Map).entries) {
      final lang = TranscriptLanguage.values.firstWhere(
        (l) => l.code == entry.key,
      );
      transcripts[lang] = VideoTranscript.fromMap(
        lang,
        entry.value as Map,
        summary.durationMs,
      );
    }
    final offset = (m['scrollOffset'] as num).toDouble(),
        position = (m['playbackMs'] as num).toInt();
    if (!offset.isFinite ||
        offset < 0 ||
        position < 0 ||
        position > summary.durationMs) {
      throw const FormatException('Invalid saved position.');
    }
    final exportFile = m['exportFile'] == null
        ? null
        : safeName(m['exportFile']);
    final review = PauseReviewSession.fromMap(
      Map<String, dynamic>.from(m['pauseReview'] as Map),
      summary.durationMs,
    );
    final reviewMap = review.toMap();
    review.dispose();
    return LocalProject(
      id: summary.id,
      title: summary.title,
      source: SourceVideo(
        '$root/${summary.sourceFile}',
        summary.durationMs,
        hasAudio: m['hasAudio'] as bool?,
        name: m['sourceName'] as String?,
      ),
      createdAt: summary.createdAt,
      updatedAt: summary.updatedAt,
      edits: edits,
      transcripts: transcripts,
      language: language,
      analysis: analysis,
      pauseReview: reviewMap,
      scrollOffset: offset,
      playbackMs: position,
      exportPath: exportFile == null ? null : '$root/$exportFile',
      recovered: recovered,
    );
  }
}
