import Flutter
import UIKit
import AVFoundation
import AVKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, UIDocumentPickerDelegate {
  private var pendingImport: FlutterResult?
  private var exportSession: AVAssetExportSession?
  private var mediaChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
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
    guard let args = call.arguments as? [String: Any], let path = args["path"] as? String else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing source path.", details: nil)); return
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
          reply(["path": destination.path, "durationMs": Int(duration.seconds * 1000)])
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
