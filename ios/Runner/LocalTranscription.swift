import Foundation
import Flutter
import AVFoundation
import CryptoKit
import whisper

struct LocalSpeechModel {
  let id: String
  let name: String
  let file: String
  let bytes: Int64
  let sha256: String
  let shared: Bool
  static let revision = "5359861c739e955e79d9a303bcbc70fb988958b1"
  var url: URL { URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/\(Self.revision)/\(file)?download=true")! }

  static func forLanguage(_ language: String) throws -> LocalSpeechModel {
    switch language {
    case "en":
      return LocalSpeechModel(id: "whisper-base-en-v1", name: "English speech model", file: "ggml-base.en.bin",
        bytes: 147964211, sha256: "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002", shared: false)
    case "hi", "mixed":
      return LocalSpeechModel(id: "whisper-small-multilingual-v1", name: "Multilingual speech model", file: "ggml-small.bin",
        bytes: 487601967, sha256: "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b", shared: true)
    default: throw speechError("Choose English, Hindi, or Hindi–English.")
    }
  }
}

func speechError(_ text: String) -> NSError {
  NSError(domain: "LocalCut.Transcription", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
}

/// C inference callbacks and URLSession delegates access this state across
/// threads. Keep it independent of Flutter and protect every read/write.
final class SpeechJobState: @unchecked Sendable {
  private let lock = NSLock()
  private var canceled = false
  private var phase = "idle"
  private var fraction: Double?
  private var bytes: Int64 = 0
  var isCanceled: Bool { lock.lock(); defer { lock.unlock() }; return canceled }
  func cancel() { lock.lock(); canceled = true; lock.unlock() }
  func reset() { lock.lock(); canceled = false; phase = "preparing"; fraction = nil; bytes = 0; lock.unlock() }
  func update(_ phase: String, fraction: Double? = nil, bytes: Int64? = nil) {
    lock.lock(); defer { lock.unlock() }
    self.phase = phase; self.fraction = fraction
    if let bytes = bytes { self.bytes = bytes }
  }
  func snapshot() -> [String: Any] {
    lock.lock(); defer { lock.unlock() }
    return ["phase": phase, "fraction": fraction.map { $0 as Any } ?? NSNull(), "downloadedBytes": bytes]
  }
  func check() throws { if isCanceled || Task.isCancelled { throw CancellationError() } }
}

final class SpeechDownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  let state: SpeechJobState
  let expected: Int64
  init(state: SpeechJobState, expected: Int64) { self.state = state; self.expected = expected }
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
      didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
    state.update("downloading", fraction: min(1, Double(totalBytesWritten) / Double(expected)), bytes: totalBytesWritten)
    if state.isCanceled { downloadTask.cancel() }
  }
}

/// Models are stored separately from footage, excluded from iCloud backup.
/// Only a size-checked, SHA256-verified download receives a readiness marker.
enum LocalSpeechModelStore {
  static func directory() throws -> URL {
    var folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
      appropriateFor: nil, create: true).appendingPathComponent("LocalCut/SpeechModels", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var values = URLResourceValues(); values.isExcludedFromBackup = true
    try folder.setResourceValues(values)
    return folder
  }
  static func path(_ model: LocalSpeechModel) throws -> URL {
    try directory().appendingPathComponent(model.id + ".bin")
  }
  static func marker(_ model: LocalSpeechModel) throws -> URL {
    try directory().appendingPathComponent(model.id + ".verified")
  }
  static func ready(_ model: LocalSpeechModel) throws -> Bool {
    let file = try path(model)
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
      (attributes[.size] as? NSNumber)?.int64Value == model.bytes,
      let stamp = try? String(contentsOf: marker(model), encoding: .utf8) else { return false }
    return stamp == model.sha256
  }
  static func remove(_ model: LocalSpeechModel) throws {
    for file in [try path(model), try marker(model)] where FileManager.default.fileExists(atPath: file.path) {
      try FileManager.default.removeItem(at: file)
    }
  }
  static func download(_ model: LocalSpeechModel, state: SpeechJobState) async throws {
    if try ready(model) { return }
    try state.check()
    let folder = try directory()
    let attributes = try FileManager.default.attributesOfFileSystem(forPath: folder.path)
    if let available = attributes[.systemFreeSize] as? NSNumber,
       available.int64Value < model.bytes * 2 + 64_000_000 {
      throw speechError("Not enough free storage for this model. Free up space and retry.")
    }
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 60
    config.timeoutIntervalForResource = 3600
    config.waitsForConnectivity = false
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    state.update("downloading", fraction: 0, bytes: 0)
    let progress = SpeechDownloadProgress(state: state, expected: model.bytes)
    let (temporary, response) = try await session.download(from: model.url, delegate: progress)
    defer { try? FileManager.default.removeItem(at: temporary) }
    try state.check()
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw speechError("The model download failed. Check your connection and retry.")
    }
    let size = try FileManager.default.attributesOfItem(atPath: temporary.path)[.size] as? NSNumber
    guard size?.int64Value == model.bytes else { throw speechError("Incomplete model download. Please retry.") }
    state.update("verifying")
    let handle = try FileHandle(forReadingFrom: temporary)
    defer { try? handle.close() }
    var digest = SHA256()
    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
      try state.check(); digest.update(data: data)
    }
    let sha = digest.finalize().map { String(format: "%02x", $0) }.joined()
    guard sha == model.sha256 else { throw speechError("Model verification failed. Please download it again.") }
    try state.check()
    try remove(model)
    try FileManager.default.moveItem(at: temporary, to: path(model))
    try model.sha256.write(to: marker(model), atomically: true, encoding: .utf8)
  }
}

@MainActor
final class LocalTranscriptionService {
  private let channel: FlutterMethodChannel
  private let state = SpeechJobState()
  private var job: Task<Void, Never>?
  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "localcut/transcription", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, reply in self?.handle(call, reply: reply) }
  }
  private func handle(_ call: FlutterMethodCall, reply: @escaping FlutterResult) {
    if call.method == "progress" { reply(state.snapshot()); return }
    if call.method == "cancel" { state.cancel(); job?.cancel(); reply(nil); return }
    let args = call.arguments as? [String: Any] ?? [:]
    guard let language = args["language"] as? String else {
      reply(FlutterError(code: "LANGUAGE", message: "Choose a transcript language.", details: nil)); return
    }
    do {
      let model = try LocalSpeechModel.forLanguage(language)
      if call.method == "model" {
        reply(["id": model.id, "name": model.name, "bytes": model.bytes,
          "ready": try LocalSpeechModelStore.ready(model), "shared": model.shared]); return
      }
      guard job == nil else { throw speechError("Another speech operation is still running.") }
      if call.method == "deleteModel" { try LocalSpeechModelStore.remove(model); reply(nil); return }
      guard call.method == "download" || call.method == "transcribe" else { reply(FlutterMethodNotImplemented); return }
      let path = args["path"] as? String
      if call.method == "transcribe" && path == nil { throw speechError("Missing video source.") }
      state.reset()
      let state = self.state
      let method = call.method
      job = Task.detached(priority: .userInitiated) { [self] in
        do {
          let output: [String: Any]?
          if method == "download" {
            try await LocalSpeechModelStore.download(model, state: state); output = nil
          } else {
            guard try LocalSpeechModelStore.ready(model) else { throw speechError("Download this language model first.") }
            output = try await LocalSpeechRecognizer.transcribe(path: path!, modelPath: LocalSpeechModelStore.path(model).path,
              language: language, state: state)
          }
          try state.check()
          await MainActor.run { self.job = nil; state.update("idle"); reply(output) }
        } catch {
          let canceled = state.isCanceled || error is CancellationError || (error as NSError).code == NSURLErrorCancelled
          await MainActor.run {
            self.job = nil; state.update("idle")
            reply(FlutterError(code: canceled ? "CANCELED" : "TRANSCRIPTION_ERROR",
              message: canceled ? "Transcription canceled." : error.localizedDescription, details: nil))
          }
        }
      }
    } catch { reply(FlutterError(code: "TRANSCRIPTION_ERROR", message: error.localizedDescription, details: nil)) }
  }
}

/// Chunked audio decoding bounds PCM memory to about 30 seconds. Everything
/// below operates on the source file and verified local weights; no networking.
enum LocalSpeechRecognizer {
  static func transcribe(path: String, modelPath: String, language: String, state: SpeechJobState) async throws -> [String: Any] {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
      throw speechError("This video has no audio track to transcribe.")
    }
    let duration = try await asset.load(.duration).seconds
    guard duration.isFinite, duration > 0 else { throw speechError("Invalid video duration.") }
    try state.check()
    state.update("loading")
    var contextParams = whisper_context_default_params()
    // CPU avoids a Metal resource dependency and also works in simulators.
    // Benchmark GPU acceleration in a later performance milestone.
    contextParams.use_gpu = false
    guard let context = whisper_init_from_file_with_params(modelPath, contextParams) else {
      throw speechError("Could not load the speech model. Free memory or download it again.")
    }
    defer { whisper_free(context) }
    try state.check()
    let reader = try AVAssetReader(asset: asset)
    defer { reader.cancelReading() }
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
      AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000,
      AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32,
      AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
    ])
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else { throw speechError("Unsupported audio format for transcription.") }
    reader.add(output)
    guard reader.startReading() else { throw reader.error ?? speechError("Could not decode audio.") }
    var samples: [Float] = []
    var chunkStart = 0.0
    var nextExpectedTime: Double?
    var words: [[String: Any]] = []
    let chunkFrames = 30 * 16000

    func recognize(_ audio: [Float], start: Double) throws {
      words.append(contentsOf: try LocalWhisperDecoder.recognize(context: context,
        audio: audio, start: start, duration: duration, language: language, state: state))
    }

    while reader.status == .reading {
      try state.check()
      let received: Bool = try autoreleasepool {
        guard let buffer = output.copyNextSampleBuffer() else { return false }
        guard let block = CMSampleBufferGetDataBuffer(buffer),
          let description = CMSampleBufferGetFormatDescription(buffer),
          let format = CMAudioFormatDescriptionGetStreamBasicDescription(description) else {
          throw speechError("Could not read decoded audio.")
        }
        let frames = CMSampleBufferGetNumSamples(buffer)
        guard format.pointee.mSampleRate == 16000, format.pointee.mChannelsPerFrame == 1,
          format.pointee.mBitsPerChannel == 32,
          format.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0,
          format.pointee.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0,
          frames > 0, CMBlockBufferGetDataLength(block) >= frames * 4 else {
          throw speechError("Unsupported decoded speech-audio format.")
        }
        let time = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
        guard time.isFinite else { throw speechError("Invalid audio timestamps.") }
        if let expected = nextExpectedTime, abs(time - expected) > 0.005 {
          try recognize(samples, start: chunkStart); samples.removeAll(keepingCapacity: true)
        }
        if samples.isEmpty { chunkStart = time }
        var pcm = [Float](repeating: 0, count: frames)
        let status = pcm.withUnsafeMutableBytes { bytes in
          CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: frames * 4, destination: bytes.baseAddress!)
        }
        guard status == kCMBlockBufferNoErr, pcm.allSatisfy({ $0.isFinite }) else {
          throw speechError("Invalid audio samples.")
        }
        samples.append(contentsOf: pcm)
        nextExpectedTime = time + Double(frames) / 16000
        while samples.count >= chunkFrames {
          try recognize(Array(samples.prefix(chunkFrames)), start: chunkStart)
          samples.removeFirst(chunkFrames); chunkStart += 30
        }
        return true
      }
      if !received { break }
    }
    try state.check()
    guard reader.status == .completed else { throw reader.error ?? speechError("Audio decoding did not finish.") }
    try recognize(samples, start: chunkStart)
    state.update("transcribing", fraction: 1)
    return ["words": words]
  }
}


/// Word-sized segment decoding is shared with the native inference check.
/// Timestamp generation is experimental; invalid timing remains uneditable.
enum LocalWhisperDecoder {
  static func recognize(context: OpaquePointer, audio: [Float], start: Double,
    duration: Double, language: String, state: SpeechJobState) throws -> [[String: Any]] {
    var words: [[String: Any]] = []
    try state.check()
    guard !audio.isEmpty else { return [] }
    // Digital silence must not be fed as speech (Whisper may hallucinate).
    let power = audio.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(audio.count)
    if power < 1e-10 { return [] }
    state.update("transcribing", fraction: min(0.99, start / duration))
    var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
    params.n_threads = Int32(max(1, min(4, ProcessInfo.processInfo.activeProcessorCount - 2)))
    params.translate = false
    params.no_context = true
    params.token_timestamps = true
    params.split_on_word = true
    params.max_len = 1
    params.print_realtime = false; params.print_progress = false
    params.print_timestamps = false; params.print_special = false
    params.suppress_nst = true
    params.abort_callback = { pointer in
      guard let pointer = pointer else { return true }
      return Unmanaged<SpeechJobState>.fromOpaque(pointer).takeUnretainedValue().isCanceled
    }
    params.abort_callback_user_data = Unmanaged.passUnretained(state).toOpaque()
    let lang = language == "mixed" ? "auto" : language
    let code = lang.withCString { languagePointer -> Int32 in
      params.language = languagePointer
      return audio.withUnsafeBufferPointer { buffer in
        whisper_full(context, params, buffer.baseAddress, Int32(buffer.count))
      }
    }
    try state.check()
    guard code == 0 else { throw speechError("On-device transcription failed. Try a shorter recording or free memory.") }
    for i in 0..<whisper_full_n_segments(context) {
      if whisper_full_get_segment_no_speech_prob(context, i) > 0.8 { continue }
      guard let cText = whisper_full_get_segment_text(context, i) else { continue }
      let text = String(cString: cText).trimmingCharacters(in: .whitespacesAndNewlines)
      if text.isEmpty || text.hasPrefix("[_") || text == "[BLANK_AUDIO]" { continue }
      let sourceStart = Int((start * 1000).rounded()) + Int(whisper_full_get_segment_t0(context, i)) * 10
      let sourceEnd = min(Int(duration * 1000), Int((start * 1000).rounded()) + Int(whisper_full_get_segment_t1(context, i)) * 10)
      // Never manufacture word timing: unaligned text remains visible but
      // cannot be applied as an edit until the user uses the waveform.
      if sourceStart >= 0 && sourceEnd > sourceStart {
        words.append(["text": text, "startMs": sourceStart, "endMs": sourceEnd])
      } else {
        words.append(["text": text, "startMs": NSNull(), "endMs": NSNull()])
      }
    }
    return words
  }
}
