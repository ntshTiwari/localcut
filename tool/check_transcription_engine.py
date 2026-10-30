#!/usr/bin/env python3
"""Run the production Whisper decoder on macOS without Flutter/AVAssetReader.

No downloads are performed. Supply a verified model, the macOS framework folder
from the pinned XCFramework, and mono 16 kHz float32 little-endian PCM audio.
See docs/04-transcript-models/README.md for preparation and limitations.
"""
from pathlib import Path
import argparse
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--framework', type=Path, required=True)
parser.add_argument('--model', type=Path, required=True)
parser.add_argument('--audio', type=Path, required=True)
parser.add_argument('--language', choices=['en', 'hi', 'mixed'], default='en')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
source = (root / 'ios/Runner/LocalTranscription.swift').read_text()
models = source[source.index('struct LocalSpeechModel {'):source.index('@MainActor\nfinal class LocalTranscriptionService')]
decoder = source[source.index('enum LocalWhisperDecoder {'):]
runner = r'''
@main struct InferenceCheck {
  static func main() throws {
    let model = try LocalSpeechModel.forLanguage(CommandLine.arguments[3])
    let hindi = try LocalSpeechModel.forLanguage("hi")
    let mixed = try LocalSpeechModel.forLanguage("mixed")
    precondition(hindi.id == mixed.id && hindi.shared)
    let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: CommandLine.arguments[1]))
    var hash = SHA256(); var size: Int64 = 0
    while let data = try handle.read(upToCount: 1048576), !data.isEmpty { hash.update(data: data); size += Int64(data.count) }
    try handle.close()
    precondition(size == model.bytes, "Unexpected model file size")
    precondition(hash.finalize().map { String(format: "%02x", $0) }.joined() == model.sha256,
      "Model SHA256 mismatch")
    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
    precondition(!data.isEmpty && data.count % 4 == 0, "Invalid float32 audio file")
    let pcm = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    precondition(pcm.count <= 480000, "Use a fixture of at most 30 seconds")
    var params = whisper_context_default_params(); params.use_gpu = false
    guard let context = whisper_init_from_file_with_params(CommandLine.arguments[1], params) else { fatalError("Model failed to load") }
    defer { whisper_free(context) }
    let state = SpeechJobState()
    let duration = 2 + Double(pcm.count) / 16000
    let words = try LocalWhisperDecoder.recognize(context: context, audio: pcm, start: 2,
      duration: duration, language: CommandLine.arguments[3], state: state)
    precondition(!words.isEmpty, "No speech recognized in fixture")
    let timed = words.filter { $0["startMs"] is Int }
    for word in timed {
      let start = word["startMs"] as! Int, end = word["endMs"] as! Int
      precondition(start >= 2000 && end > start && end <= Int(duration * 1000), "Invalid source offset")
    }
    state.cancel()
    do {
      _ = try LocalWhisperDecoder.recognize(context: context, audio: pcm, start: 0,
        duration: duration, language: CommandLine.arguments[3], state: state)
      preconditionFailure("Canceled work must not run inference")
    } catch is CancellationError { }
    let result: [String: Any] = ["model":model.id,"language":CommandLine.arguments[3],"timedWordCount":timed.count,"words":words]
    print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
  }
}
'''
with tempfile.TemporaryDirectory(prefix='localcut-transcript-check-') as directory:
    folder = Path(directory)
    swift = folder / 'InferenceCheck.swift'
    binary = folder / 'inference-check'
    swift.write_text('import Foundation\nimport CryptoKit\nimport whisper\n' + models + decoder + runner)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(swift), '-F', str(args.framework.resolve()),
                    '-framework', 'whisper', '-framework', 'Accelerate', '-framework', 'Metal', '-lc++',
                    '-Xlinker', '-rpath', '-Xlinker', str(args.framework.resolve()),
                    '-module-cache-path', str(folder / 'module-cache'), '-o', str(binary)], check=True)
    subprocess.run([str(binary), str(args.model.resolve()), str(args.audio.resolve()), args.language], check=True)
