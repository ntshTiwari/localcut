import 'package:flutter/services.dart';
import '../core/edit_plan.dart';
import '../core/silence_detection.dart';

class SourceVideo {
  const SourceVideo(this.path, this.durationMs, {this.hasAudio, this.name});
  final String path;
  final int durationMs;
  final bool? hasAudio;
  final String? name;
}

abstract interface class MediaEngine {
  Future<SourceVideo?> importVideo();
  Future<void> preview(
    String path,
    List<RenderSegment> segments, {
    String? label,
  });
  Future<String> export(String path, List<RenderSegment> segments);
  Future<void> share(String path);
  Future<void> cancelExport();
  Future<AudioAnalysis> analyzeAudio(String path);
  Future<void> cancelAnalysis();
}

/// Only this adapter knows about platform messaging. Android implements the
/// same protocol; edit planning and UI stay in Dart.
class PlatformMediaEngine implements MediaEngine {
  static const _channel = MethodChannel('localcut/media');
  @override
  Future<SourceVideo?> importVideo() async {
    final data = await _channel.invokeMapMethod<String, dynamic>('import');
    return data == null
        ? null
        : SourceVideo(
            data['path'] as String,
            (data['durationMs'] as num).toInt(),
            hasAudio: data['hasAudio'] as bool?,
            name: data['name'] as String?,
          );
  }

  Map<String, Object> _args(String path, List<RenderSegment> segments) => {
    'path': path,
    'segments': segments.map((e) => e.toMap()).toList(),
  };
  @override
  Future<void> preview(
    String path,
    List<RenderSegment> segments, {
    String? label,
  }) => _channel.invokeMethod('preview', _args(path, segments));
  @override
  Future<String> export(String path, List<RenderSegment> segments) async =>
      (await _channel.invokeMethod<String>('export', _args(path, segments)))!;
  @override
  Future<void> share(String path) =>
      _channel.invokeMethod('share', {'path': path});
  @override
  Future<AudioAnalysis> analyzeAudio(String path) async {
    final data = await _channel.invokeMapMethod<String, dynamic>(
      'analyzeAudio',
      {'path': path},
    );
    if (data == null) throw StateError('Audio analysis returned no result.');
    final windows = (data['windows'] as List)
        .map((raw) {
          final values = raw as List;
          return AudioWindow(
            (values[0] as num).toInt(),
            (values[1] as num).toInt(),
            (values[2] as num).toDouble(),
          );
        })
        .toList(growable: false);
    return AudioAnalysis(windows, hasAudio: data['hasAudio'] as bool);
  }

  @override
  Future<void> cancelAnalysis() => _channel.invokeMethod('cancelAnalysis');
  @override
  Future<void> cancelExport() => _channel.invokeMethod('cancelExport');
}
