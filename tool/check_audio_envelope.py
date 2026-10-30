#!/usr/bin/env python3
"""Exercise the production Swift PCM accumulator on macOS (no iOS runtime).

Run: python3 tool/check_audio_envelope.py
Requires Xcode command-line tools. This verifies PCM windowing, not AV decoding.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'ios/Runner/AppDelegate.swift').read_text()
accumulator = source[source.index('struct AudioEnvelopeAccumulator {'):]
checks = r'''
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  precondition(condition(), message)
}
@main struct EnvelopeChecks {
  static func main() throws {
    let sampleRate = 48000.0
    var envelope = AudioEnvelopeAccumulator(durationSeconds: 5)
    // 5 seconds of opposite-phase stereo in uneven 137-frame chunks. Two
    // seconds of digital silence in the middle. Cancellation must not occur
    // when channel values would cancel in a mono mix.
    var frame = 0
    while frame < 240000 {
      let count = min(137, 240000 - frame)
      var pcm = [Float]()
      for offset in 0..<count {
        let time = Double(frame + offset) / sampleRate
        let value: Float = time >= 1 && time < 3 ? 0 : 0.2
        pcm.append(value); pcm.append(-value)
      }
      try envelope.append(samples: pcm, channels: 2,
        sampleRate: sampleRate, startSeconds: Double(frame) / sampleRate)
      frame += count
    }
    envelope.finish()
    check(envelope.windows.count == 250, "Expected 250 windows at 20 ms")
    for (index, window) in envelope.windows.enumerated() {
      check(Int(window[0]) == index * 20 && Int(window[1]) == (index + 1) * 20,
        "Chunking changed original timestamps")
      if index >= 50 && index < 150 {
        check(window[2] == -120, "Silence floor incorrect")
      } else {
        check(abs(window[2] - (-13.9794)) < 0.01, "Stereo energy was lost")
      }
    }
    // Partial windows must flush at discontinuities, without inventing audio
    // samples in gaps or extending beyond the recording duration.
    var gaps = AudioEnvelopeAccumulator(durationSeconds: 1)
    try gaps.append(samples: [Float](repeating: 0, count: 240), channels: 1,
      sampleRate: sampleRate, startSeconds: 0)
    try gaps.append(samples: [Float](repeating: 0.1, count: 240), channels: 1,
      sampleRate: sampleRate, startSeconds: 0.5)
    gaps.finish()
    check(gaps.windows.count == 2, "Missing partial windows")
    check(gaps.windows[0][1] == 5 && gaps.windows[1][0] == 500,
      "An unknown timestamp gap was treated as silence")
    var invalid = AudioEnvelopeAccumulator(durationSeconds: 1)
    do {
      try invalid.append(samples: [Float.nan], channels: 1,
        sampleRate: sampleRate, startSeconds: 0)
      preconditionFailure("Invalid samples must be rejected")
    } catch { /* Expected */ }
    print("Swift PCM checks passed: stereo, chunk boundaries, padding inputs, discontinuities, and invalid samples.")
  }
}
'''
with tempfile.TemporaryDirectory(prefix='localcut-audio-check-') as directory:
    folder = Path(directory)
    swift = folder / 'EnvelopeChecks.swift'
    binary = folder / 'envelope-checks'
    swift.write_text('import Foundation\n' + accumulator + checks)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(swift),
                    '-module-cache-path', str(folder / 'module-cache'),
                    '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
