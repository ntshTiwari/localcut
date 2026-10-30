import Flutter
import UIKit
import AVFoundation
import AVKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, UIDocumentPickerDelegate {
  private var transcriptionService: LocalTranscriptionService?
  private var pendingImport: FlutterResult?
  private var exportSession: AVAssetExportSession?
  private var analysisTask: Task<Void, Never>?
  private var mediaChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    transcriptionService = LocalTranscriptionService(messenger: controller.binaryMessenger)
    mediaChannel = FlutterMethodChannel(name: "localcut/media", binaryMessenger: controller.binaryMessenger)
    mediaChannel?.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func fail(_ error: Error, _ result: @escaping FlutterResult) {
    result(FlutterError(code: "MEDIA_ERROR", message: error.localizedDescription, details: nil))
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "import" {
      guard pendingImport == nil else {
        result(FlutterError(code: "BUSY", message: "An import is already open.", details: nil)); return
      }
      pendingImport = result
      let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.movie], asCopy: true)
      picker.delegate = self
      window?.rootViewController?.present(picker, animated: true)
      return
    }
    if call.method == "cancelExport" {
      exportSession?.cancelExport(); result(nil); return
    }
    if call.method == "cancelAnalysis" {
      analysisTask?.cancel(); result(nil); return
    }
    guard let args = call.arguments as? [String: Any], let path = args["path"] as? String else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing source path.", details: nil)); return
    }
    if call.method == "analyzeAudio" {
      guard analysisTask == nil else {
        result(FlutterError(code: "BUSY", message: "Audio analysis is already running.", details: nil)); return
      }
      analysisTask = Task.detached(priority: .userInitiated) { [weak self] in
        guard let self = self else { return }
        do {
          let data = try await OfflineAudioAnalyzer.analyze(path: path)
          try Task.checkCancellation()
          await MainActor.run {
            self.analysisTask = nil
            result(data)
          }
        } catch {
          await MainActor.run {
            self.analysisTask = nil
            result(FlutterError(code: error is CancellationError ? "CANCELED" : "ANALYSIS_ERROR",
              message: error is CancellationError ? "Audio analysis canceled." : error.localizedDescription,
              details: nil))
          }
        }
      }
      return
    }
    if call.method == "share" {
      let sheet = UIActivityViewController(activityItems: [URL(fileURLWithPath: path)], applicationActivities: nil)
      if let popover = sheet.popoverPresentationController, let view = window?.rootViewController?.view {
        popover.sourceView = view
        popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
      }
      window?.rootViewController?.present(sheet, animated: true)
      result(nil); return
    }
    guard call.method == "preview" || call.method == "export" else {
      result(FlutterMethodNotImplemented); return
    }
    guard let segments = args["segments"] as? [[String: Any]], !segments.isEmpty else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing edit segments.", details: nil)); return
    }
    Task { @MainActor in
      do {
        let (composition, mix) = try await self.compose(path: path, segments: segments)
        if call.method == "preview" {
          try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
          try AVAudioSession.sharedInstance().setActive(true)
          let item = AVPlayerItem(asset: composition)
          item.audioMix = mix
          let player = AVPlayerViewController()
          player.player = AVPlayer(playerItem: item)
          self.window?.rootViewController?.present(player, animated: true) { player.player?.play() }
          result(nil)
        } else {
          try await self.export(composition: composition, mix: mix, result: result)
        }
      } catch { self.fail(error, result) }
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pendingImport?(nil); pendingImport = nil
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let reply = pendingImport else { return }
    pendingImport = nil
    guard let url = urls.first else { reply(nil); return }
    Task { @MainActor in
      let access = url.startAccessingSecurityScopedResource()
      defer { if access { url.stopAccessingSecurityScopedResource() } }
      do {
        let directory = try self.projectDirectory()
        let destination = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(url.pathExtension)
        try FileManager.default.copyItem(at: url, to: destination)
        do {
          let asset = AVURLAsset(url: destination)
          let duration = try await asset.load(.duration)
          let tracks = try await asset.loadTracks(withMediaType: .video)
          guard !tracks.isEmpty, duration.seconds.isFinite, duration.seconds > 0 else {
            throw self.error("Choose a playable video with a positive duration.")
          }
          let audioTracks = try await asset.loadTracks(withMediaType: .audio)
          reply(["path": destination.path, "durationMs": Int(duration.seconds * 1000), "hasAudio": !audioTracks.isEmpty])
        } catch {
          try? FileManager.default.removeItem(at: destination)
          throw error
        }
      } catch { self.fail(error, reply) }
    }
  }

  private func projectDirectory() throws -> URL {
    let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("LocalCut", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private func error(_ message: String) -> NSError {
    NSError(domain: "LocalCut", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }

  /// Both preview and export consume the same composition. All incoming times
  /// reference the original source; destination time advances only for kept media.
  private func compose(path: String, segments: [[String: Any]]) async throws -> (AVMutableComposition, AVMutableAudioMix?) {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let duration = try await asset.load(.duration)
    guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else {
      throw error("This file has no video track.")
    }
    let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first
    let composition = AVMutableComposition()
    guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
      throw error("Could not create a video track.")
    }
    video.preferredTransform = try await sourceVideo.load(.preferredTransform)
    let audio = sourceAudio == nil ? nil : composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
    let parameters = audio.map { AVMutableAudioMixInputParameters(track: $0) }
    var cursor = CMTime.zero
    var previousEnd = 0.0
    for segment in segments {
      guard let start = segment["startMs"] as? NSNumber,
            let end = segment["endMs"] as? NSNumber,
            let muted = segment["muted"] as? Bool else { throw error("Invalid edit segment.") }
      let startMs = start.doubleValue, endMs = end.doubleValue
      guard startMs.isFinite, endMs.isFinite, startMs >= previousEnd,
            endMs > startMs, endMs <= duration.seconds * 1000 + 1 else {
        throw error("Edit ranges must be ordered and inside the source video.")
      }
      previousEnd = endMs
      let range = CMTimeRange(start: CMTime(seconds: startMs / 1000, preferredTimescale: 60000), duration: CMTime(seconds: (endMs - startMs) / 1000, preferredTimescale: 60000))
      try video.insertTimeRange(range, of: sourceVideo, at: cursor)
      if let sourceAudio = sourceAudio, let audio = audio {
        // Intersect with audio coverage: some camera clips have shorter audio.
        let coverage = try await sourceAudio.load(.timeRange)
        let available = CMTimeRangeGetIntersection(range, otherRange: coverage)
        if available.isValid && !available.isEmpty {
          let offset = CMTimeSubtract(available.start, range.start)
          try audio.insertTimeRange(available, of: sourceAudio, at: CMTimeAdd(cursor, offset))
        }
        parameters?.setVolume(muted ? 0 : 1, at: cursor)
      }
      cursor = CMTimeAdd(cursor, range.duration)
    }
    let mix = AVMutableAudioMix()
    mix.inputParameters = parameters.map { [$0] } ?? []
    return (composition, sourceAudio == nil ? nil : mix)
  }

  @MainActor
  private func export(composition: AVMutableComposition, mix: AVMutableAudioMix?, result: @escaping FlutterResult) async throws {
    guard exportSession == nil else { throw error("An export is already running.") }
    guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPreset1920x1080) else {
      throw error("Could not initialize export for this video.")
    }
    guard session.supportedFileTypes.contains(.mp4) else { throw error("MP4 export is unavailable for this video.") }
    let output = try projectDirectory().appendingPathComponent("LocalCut-\(UUID().uuidString).mp4")
    session.outputURL = output
    session.outputFileType = .mp4
    session.audioMix = mix
    session.shouldOptimizeForNetworkUse = false
    exportSession = session
    // Prevent idle screen locking during foreground export; restore afterward.
    let wasIdleDisabled = UIApplication.shared.isIdleTimerDisabled
    UIApplication.shared.isIdleTimerDisabled = true
    session.exportAsynchronously {
      DispatchQueue.main.async {
        guard let completedSession = self.exportSession else { return }
        self.exportSession = nil
        UIApplication.shared.isIdleTimerDisabled = wasIdleDisabled
        if completedSession.status == .completed {
          result(output.path)
        } else {
          try? FileManager.default.removeItem(at: output)
          self.fail(completedSession.error ?? self.error(completedSession.status == .cancelled ? "Export canceled." : "Export failed."), result)
        }
      }
    }
  }
}


/// Reads only decoded audio, one sample buffer at a time. No video decoding,
/// model download, or whole-recording PCM allocation. Output is measured in
/// source time, retaining gaps rather than guessing they contain silence.
enum OfflineAudioAnalyzer {
  private static func failure(_ message: String) -> NSError {
    NSError(domain: "LocalCut.AudioAnalysis", code: 1,
      userInfo: [NSLocalizedDescriptionKey: message])
  }

  static func analyze(path: String) async throws -> [String: Any] {
    try Task.checkCancellation()
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
      return ["hasAudio": false, "windows": [[Double]]()]
    }
    let duration = try await asset.load(.duration).seconds
    guard duration.isFinite, duration > 0 else { throw failure("Invalid audio duration.") }
    let reader = try AVAssetReader(asset: asset)
    defer { reader.cancelReading() }
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVLinearPCMBitDepthKey: 32,
      AVLinearPCMIsFloatKey: true,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
    ])
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else { throw failure("This audio format cannot be analyzed.") }
    reader.add(output)
    guard reader.startReading() else { throw reader.error ?? failure("Could not read audio.") }
    var envelope = AudioEnvelopeAccumulator(durationSeconds: duration)
    while reader.status == .reading {
      try Task.checkCancellation()
      let received: Bool = try autoreleasepool {
        guard let buffer = output.copyNextSampleBuffer() else { return false }
        guard CMSampleBufferDataIsReady(buffer),
          let description = CMSampleBufferGetFormatDescription(buffer),
          let format = CMAudioFormatDescriptionGetStreamBasicDescription(description),
          let block = CMSampleBufferGetDataBuffer(buffer) else {
          throw failure("Could not decode audio samples.")
        }
        let stream = format.pointee
        let channels = Int(stream.mChannelsPerFrame)
        let frames = CMSampleBufferGetNumSamples(buffer)
        guard stream.mFormatID == kAudioFormatLinearPCM,
          stream.mBitsPerChannel == 32,
          stream.mFormatFlags & kAudioFormatFlagIsFloat != 0,
          stream.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0,
          stream.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
          channels > 0, channels <= 32, stream.mSampleRate > 0,
          frames > 0 else { throw failure("Unsupported decoded audio layout.") }
        let byteCount = frames * channels * MemoryLayout<Float>.size
        guard byteCount <= CMBlockBufferGetDataLength(block) else {
          throw failure("Incomplete decoded audio buffer.")
        }
        var samples = [Float](repeating: 0, count: frames * channels)
        let status = samples.withUnsafeMutableBytes { bytes in
          CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: byteCount, destination: bytes.baseAddress!)
        }
        guard status == kCMBlockBufferNoErr else { throw failure("Could not access audio samples.") }
        let start = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
        guard start.isFinite else { throw failure("Audio has invalid sample timestamps.") }
        try envelope.append(samples: samples, channels: channels,
          sampleRate: stream.mSampleRate, startSeconds: start)
        return true
      }
      if !received { break }
    }
    try Task.checkCancellation()
    guard reader.status == .completed else {
      throw reader.error ?? failure("Audio analysis did not finish. Try another video.")
    }
    envelope.finish()
    guard !envelope.windows.isEmpty else { throw failure("No readable audio samples found.") }
    return ["hasAudio": true, "windows": envelope.windows]
  }
}

/// 20 ms RMS windows, using the loudest channel rather than a mono downmix.
/// This avoids phase cancellation or a silent channel hiding quiet speech.
struct AudioEnvelopeAccumulator {
  private let durationSeconds: Double
  private var energy: [Double] = []
  private var frameCount = 0
  private var windowStart = 0.0
  private var nextTime: Double?
  private var rate = 0.0
  private(set) var windows: [[Double]] = []

  init(durationSeconds: Double) { self.durationSeconds = durationSeconds }

  mutating func append(samples: [Float], channels: Int, sampleRate: Double, startSeconds: Double) throws {
    guard channels > 0, sampleRate.isFinite, sampleRate > 0,
      samples.count % channels == 0 else {
      throw NSError(domain: "LocalCut.AudioAnalysis", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Invalid PCM data."])
    }
    // Discontinuous timestamps and format changes end a run. Unknown gaps are
    // not synthesized as quiet windows. Audio PTS remains source-relative.
    if energy.count != channels || rate != sampleRate ||
      (nextTime != nil && abs(startSeconds - nextTime!) > 0.001) {
      finish()
      energy = [Double](repeating: 0, count: channels)
      rate = sampleRate
    }
    let framesPerWindow = max(1, Int((sampleRate * 0.02).rounded()))
    for frame in 0..<(samples.count / channels) {
      let time = startSeconds + Double(frame) / sampleRate
      if time < 0 || time >= durationSeconds { continue }
      if frameCount == 0 { windowStart = time }
      for channel in 0..<channels {
        let value = Double(samples[frame * channels + channel])
        guard value.isFinite else {
          throw NSError(domain: "LocalCut.AudioAnalysis", code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Audio contains invalid samples."])
        }
        energy[channel] += value * value
      }
      frameCount += 1
      nextTime = min(durationSeconds, time + 1 / sampleRate)
      if frameCount >= framesPerWindow { finish() }
    }
  }

  mutating func finish() {
    guard frameCount > 0, let end = nextTime else { return }
    let startMs = max(0, Int((windowStart * 1000).rounded()))
    let endMs = min(Int(durationSeconds * 1000), Int((end * 1000).rounded()))
    let power = (energy.max() ?? 0) / Double(frameCount)
    let db = max(-120, 10 * log10(max(power, 1e-12)))
    if endMs > startMs { windows.append([Double(startMs), Double(endMs), db]) }
    frameCount = 0
    energy = [Double](repeating: 0, count: energy.count)
  }
}
