import 'package:flutter/services.dart';
import '../core/edit_plan.dart';

class SourceVideo {
  const SourceVideo(this.path, this.durationMs);
  final String path;
  final int durationMs;
}

abstract interface class MediaEngine {
  Future<SourceVideo?> importVideo();
  Future<void> preview(String path, List<RenderSegment> segments);
  Future<String> export(String path, List<RenderSegment> segments);
  Future<void> share(String path);
  Future<void> cancelExport();
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
          );
  }

  Map<String, Object> _args(String path, List<RenderSegment> segments) => {
    'path': path,
    'segments': segments.map((e) => e.toMap()).toList(),
  };
  @override
  Future<void> preview(String path, List<RenderSegment> segments) =>
      _channel.invokeMethod('preview', _args(path, segments));
  @override
  Future<String> export(String path, List<RenderSegment> segments) async =>
      (await _channel.invokeMethod<String>('export', _args(path, segments)))!;
  @override
  Future<void> share(String path) =>
      _channel.invokeMethod('share', {'path': path});
  @override
  Future<void> cancelExport() => _channel.invokeMethod('cancelExport');
}
