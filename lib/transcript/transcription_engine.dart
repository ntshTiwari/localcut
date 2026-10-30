import 'package:flutter/services.dart';
import 'transcript.dart';

abstract interface class TranscriptionEngine {
  Future<SpeechModel> model(TranscriptLanguage language);
  Future<void> download(TranscriptLanguage language);
  Future<VideoTranscript> transcribe(
    String path,
    int durationMs,
    TranscriptLanguage language,
  );
  Future<SpeechProgress> progress();
  Future<void> cancel();
  Future<void> deleteModel(TranscriptLanguage language);
}

class PlatformTranscriptionEngine implements TranscriptionEngine {
  static const _channel = MethodChannel('localcut/transcription');
  @override
  Future<SpeechModel> model(TranscriptLanguage language) async =>
      SpeechModel.fromMap(
        (await _channel.invokeMapMethod<String, dynamic>('model', {
          'language': language.code,
        }))!,
      );
  @override
  Future<void> download(TranscriptLanguage language) =>
      _channel.invokeMethod('download', {'language': language.code});
  @override
  Future<void> deleteModel(TranscriptLanguage language) =>
      _channel.invokeMethod('deleteModel', {'language': language.code});
  @override
  Future<VideoTranscript> transcribe(
    String path,
    int durationMs,
    TranscriptLanguage language,
  ) async => VideoTranscript.fromMap(
    language,
    (await _channel.invokeMapMethod<String, dynamic>('transcribe', {
      'path': path,
      'language': language.code,
    }))!,
    durationMs,
  );
  @override
  Future<SpeechProgress> progress() async {
    final data = (await _channel.invokeMapMethod<String, dynamic>('progress'))!;
    final fraction = (data['fraction'] as num?)?.toDouble();
    return SpeechProgress(
      data['phase'] as String,
      fraction != null && fraction.isFinite ? fraction.clamp(0.0, 1.0) : null,
      (data['downloadedBytes'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<void> cancel() => _channel.invokeMethod('cancel');
}
