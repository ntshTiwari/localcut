import '../media/media_engine.dart';
import '../core/edit_plan.dart';
import '../core/silence_detection.dart';

/// Pause the inline original before a native context/edited player or export
/// uses the same audio session. Editing algorithms remain in the backend.
class PlaybackMediaEngine implements MediaEngine {
  PlaybackMediaEngine(this.backend, this.pauseSource, {this.onPreview});
  final void Function(
    String path,
    List<RenderSegment> segments, {
    String? label,
  })?
  onPreview;
  final MediaEngine backend;
  final Future<void> Function() pauseSource;
  @override
  Future<void> preview(
    String path,
    List<RenderSegment> segments, {
    String? label,
  }) async {
    await pauseSource();
    await backend.preview(path, segments, label: label);
    onPreview?.call(path, segments, label: label);
  }

  @override
  Future<String> export(String path, List<RenderSegment> segments) async {
    await pauseSource();
    return backend.export(path, segments);
  }

  @override
  Future<SourceVideo?> importVideo() => backend.importVideo();
  @override
  Future<void> share(String path) => backend.share(path);
  @override
  Future<void> cancelExport() => backend.cancelExport();
  @override
  Future<AudioAnalysis> analyzeAudio(String path) => backend.analyzeAudio(path);
  @override
  Future<void> cancelAnalysis() => backend.cancelAnalysis();
}
