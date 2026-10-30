# Step 4: downloadable language models and transcript muting

Implemented on `milestone/transcript-language-models`, based on waveform commit
`b490f03`. This guide is committed with the implementation. `main` is unchanged.

## Purpose and user flow

Select English, Hindi, or Hindi–English for a local video. On first use, the
button shows the required model size and downloads it only when the user asks
to transcribe. It stays on the device for subsequent offline transcription.
Video/audio are not uploaded. There is no transcription backend or API key.

1. Import a video and choose its language in the transcript section.
2. Tap **Download … MB & transcribe**, or **Generate transcript** if ready.
3. Watch download/verification/transcription status; cancel if needed.
4. Tap a word to hear original context. Long-press the first word, then tap the
   last word to select a consecutive phrase; long-press alone selects one word.
5. Preview the proposed mute, then explicitly Add. Export approval is still
   separate. Changing selection or previewing never modifies the edit list.
6. Use **Waveform & pause tools** for range adjustment or existing pause cleanup.

Transcript editing currently creates mutes. Cuts remain available through the
waveform or timestamp controls. The app does not automatically remove fillers.

## The three language modes and two downloads

- English (`en`) uses Whisper `base.en`: 147,964,211 bytes, displayed as 148 MB.
- Hindi (`hi`) uses multilingual Whisper `small`: 487,601,967 bytes, 488 MB.
- Hindi–English (`mixed`) uses that same multilingual model, with language
  auto-detection and transcription, not translation. It does not download a
  second copy when the Hindi model is already available.

Selecting a language checks local readiness without contacting the model host.
It does not start a download. Switching languages preserves each generated
transcript for the current video in memory. Models persist across app restarts;
transcripts and edits do not yet persist.

Hindi–English is mixed-speech recognition, not a promise of a particular script
or perfect switching. The model may use Devanagari, Latin text, or transliterate
parts. Hindi and mixed accuracy need real-speaker evaluation. The small model
is a first baseline; increasing model size later trades storage and memory for
potential accuracy improvements.

## Code map

- [transcript.dart](../../lib/transcript/transcript.dart): the three languages,
  model metadata, timed text, validation, and `transcriptMute()`.
- [transcription_engine.dart](../../lib/transcript/transcription_engine.dart):
  platform-independent interface and the `localcut/transcription` channel.
- [transcript_panel.dart](../../lib/transcript/transcript_panel.dart): language
  selection, on-demand download, progress polling/cancel, transcript display,
  selection, model removal, preview, and explicit mute addition.
- [LocalTranscription.swift](../../ios/Runner/LocalTranscription.swift): model
  catalog/store, verified downloads, job state, chunked audio decoding, and
  the Whisper recognizer.
- [AppDelegate.swift](../../ios/Runner/AppDelegate.swift): registers the native
  service and adds `hasAudio` to imported source metadata.
- [main.dart](../../lib/main.dart): displays transcript editing first and keeps
  existing waveform/pause controls in a collapsible section.
- [Package.swift](../../ios/Packages/LocalWhisper/Package.swift): the pinned
  native engine XCFramework dependency. The Xcode Runner target links it via
  a local Swift package.
- [ThirdPartyNotices.txt](../../ios/Runner/ThirdPartyNotices.txt): MIT notices
  included in the app bundle for whisper.cpp and Whisper weights.

## 1. Separate recognition from media editing

A new `TranscriptionEngine` handles model status, download, removal, progress,
and transcript generation. The existing `MediaEngine` still handles preview
and export. Recognition returns original source-time words; it does not edit
media. Android can implement the same transcript contract later, potentially
using the same ggml weights and whisper.cpp engine.

The channel exposes:

```text
model({language}) -> {id, name, bytes, ready, shared}
download({language}) -> completion
deleteModel({language}) -> completion
transcribe({language, path}) -> {words: [{text, startMs, endMs}, ...]}
progress() -> {phase, fraction, downloadedBytes}
cancel() -> request cancellation
```

Times may be null when the model cannot provide usable alignment. The UI
preserves that text, but refuses to create edits across unaligned words.

## 2. Download and validate only when needed

`LocalSpeechModel.forLanguage()` maps the three modes to two fixed catalog
entries. Each entry pins a Hugging Face repository revision, file size, and
SHA256 digest. No user-provided URL is downloaded.

`LocalSpeechModelStore` uses Application Support/LocalCut/SpeechModels, excluded
from iCloud backup. A readiness check requires both the expected file size and
a matching verification marker. The marker is created only after verification.

Download steps:

1. Check whether verified weights already exist and check available disk space.
2. Download to a temporary file with an ephemeral URLSession. Track bytes.
3. Require HTTP 200 and the exact expected file size.
4. Stream the file through SHA256 in 1 MB blocks. Reject a mismatched digest.
5. Check cancellation, install the model, and atomically write its marker.
6. Remove temporary output on completion or failure.

A failed or canceled download is not marked ready. Retry starts a new download;
partial-download resume is not implemented. A video explicitly marked as having
no audio is rejected before requesting any model download.

Removing a model requires an explicit user action and confirmation in the app.
For a shared model, the dialog explains that both Hindi modes will need to
download again. Removal does not delete footage or cached transcript text.

## 3. Read audio in bounded chunks

`LocalSpeechRecognizer` opens the first audio track and requests mono 16 kHz,
32-bit float PCM. The imported file is read locally with AVAssetReader. A
single native job runs off the main thread, guarded against concurrent speech
operations.

PCM is collected into 30-second chunks (480,000 floats, about 1.92 MB per full
chunk), plus the current reader buffer/copy. Each chunk is recognized before
moving to the next. The model and inference workspace consume additional
memory, much more than the PCM itself. The model is unloaded afterward.

The source presentation timestamp sets the chunk's offset. A discontinuity
flushes the pending chunk instead of inventing samples in an unknown gap.
This preserves video-relative timing when audio does not start at zero.

Chunk boundaries can split a spoken word. There is no overlapping-chunk
stitching in this baseline; long continuous recordings need device evaluation.
Digital-silence chunks are skipped to reduce hallucinations. Noise and music
can still cause false recognition.

## 4. Decode local words and timestamps

The engine is whisper.cpp v1.7.6, using verified local weights. It currently
uses CPU inference for a consistent baseline without external Core ML encoder
assets. GPU/Core ML acceleration is a future performance task. The upstream binary may
log a missing optional Core ML encoder file before using CPU inference; that
message alone does not mean transcription failed.

`LocalWhisperDecoder` requests token timestamps, word-boundary splitting, and
small text segments. Its result is generally word-sized text units; a unit may
contain more than one written word. It does not invent evenly spaced word
times. Whisper's timestamp generation is experimental and approximate.

Engine timestamps are in 10 ms units relative to a chunk:

```text
source startMs = chunk startMs + engine start × 10
source endMs   = chunk startMs + engine end × 10
```

Results are bounded by the source duration. Invalid/zero-length times become
null while the recognized text remains visible. Dart additionally rejects
overlapping, reversed, out-of-order, or out-of-source timing for editing.
Recognized text accuracy is separate from whether its timestamps pass bounds
checks; users must listen and review.

Cancellation sets a lock-protected state flag, cancels the Swift task, and is
also checked by the C inference abort callback. Download delegates and UI
progress reads share the same thread-safe state. Progress is approximate and
transcription advances at chunk boundaries rather than per-word completion.

## 5. Convert selected words to a mute

`transcriptMute()` sorts the selected endpoint indices, requires usable timing
for every word between them, and returns one source-time mute instruction.

```text
Hello    1.00–1.30 s
friend   1.40–1.80 s

Select both:
  EditRange(1000, 1800, EditKind.mute)

With an existing source cut at 0.00–0.50 s:
  keep source 0.50–1.00, normal audio
  keep source 1.00–1.80, muted audio
  keep source 1.80–end, normal audio

The mute appears at output 0.50–1.30 s.
```

The existing plan compiler handles this mapping. The transcript never rewrites
its word times after cuts. Highlighting indicates overlap with accepted mutes;
strikethrough indicates overlap with a cut. Partial word overlap is a visual
hint, not a claim that the whole word is muted.

## Build and first run

Stop the running app and do a full iOS rebuild (`flutter run`, or VS Code F5).
Xcode must resolve `ios/Packages/LocalWhisper`, which downloads the pinned native
engine binary from the official whisper.cpp release. This is a build dependency,
separate from the runtime language-model download. Flutter hot reload cannot
install this native library into an older app binary.

The package has no API key or separate server dependency. Its archive checksum
is pinned in Package.swift. On-device weights are not checked into Git.

## Verification

```bash
flutter analyze
flutter test
```

The 36 Dart/widget tests cover prior milestones and the new language modes,
word-to-mute timing, invalid alignment, lazy downloading, shared Hindi/mixed
reuse, offline-ready reuse, download errors/retry/cancel, no-audio input, and
model removal while preserving the transcript.

Swift code and the package manifest type-check against the installed SDK and
actual pinned engine. The Xcode project plist parses and the engine archive
SHA256 matches its manifest. Full SwiftPM resolution in this execution session
is blocked by nested `sandbox-exec` permissions; a complete iPhone build,
native downloader lifecycle, and device playback/export need acceptance tests.

Native CPU inference was separately exercised on generated English, Hindi, and
mixed-language PCM using production decoder code. The English demo produced all
34 scripted words, with 32 usable times; the remaining two stayed unaligned.
Hindi/mixed smoke tests confirm execution, not production accuracy. They showed
recognition errors and missed phrases in a mixed sample; both modes are labeled
experimental in the interface. Synthetic
speech is not a substitute for real accents, background noise, or phone tests.

To reproduce a native smoke check on macOS, provide the macOS folder from the
pinned engine archive, a catalog model, and a short PCM fixture:

```bash
ffmpeg -i sample.mp4 -ar 16000 -ac 1 -f f32le sample.f32
python3 tool/check_transcription_engine.py \
  --framework /path/to/whisper.xcframework/macos-arm64_x86_64 \
  --model /path/to/ggml-base.en.bin \
  --audio sample.f32 --language en
```

The fixture must be at most 30 seconds. The script verifies the model's size
and SHA256, tests shared Hindi catalog identity and a two-second source offset,
and checks cancellation before inference. It performs no downloads and does
not exercise AVAssetReader or the app's URLSession downloader.

## iPhone acceptance checklist

1. First use English on Wi-Fi. Verify size before download, progress, completed
   transcript, tap-to-hear, phrase selection, preview, Add, and saved export.
2. Restart the app, enable airplane mode, and transcribe another local English
   recording. No model download should be requested.
3. Choose Hindi without pressing Generate; confirm no download starts. Generate
   on Wi-Fi, then switch to Hindi–English and confirm it reuses that download.
4. Test real Hindi and mixed recordings; check language/script, omissions,
   repeated words, and mute timing. Do not assume filler words are preserved.
5. Cancel a download, interrupt networking, and retry. Unverified files must not
   appear ready. Cancel inference and confirm existing edits remain intact.
6. Remove the shared download and verify both Hindi modes ask to download again.
7. Test no-audio, silent, long, noisy, and low-storage cases.

## Limits and follow-up work

CPU recognition can be slow and use substantial memory/battery, especially the
multilingual model. Work runs in the foreground; there is no background resume.
Word timings, recognition, code-switching, and filler preservation are not
perfect. Unaligned words require waveform/timestamp editing. Transcript text
correction, transcript cuts, persistent transcripts, speaker labels, model
quality selection, and Android's native adapter are not implemented.

## Sources and notices

- [whisper.cpp v1.7.6](https://github.com/ggml-org/whisper.cpp/tree/v1.7.6)
- [Engine release](https://github.com/ggml-org/whisper.cpp/releases/tag/v1.7.6)
- [Pinned model repository](https://huggingface.co/ggerganov/whisper.cpp/tree/5359861c739e955e79d9a303bcbc70fb988958b1)
- [Bundled notices](../../ios/Runner/ThirdPartyNotices.txt)

## Subsequent milestone

[Step 5](../05-transcript-pause-editor/README.md) replaces the long-press and
individual preview/add controls with tap selection, explicit Censor, verified
pause chips, and a fixed Review flow. Download/recognition logic remains the
same, with a shared local audio-analysis pass to verify pauses. Language and
model controls collapse once a transcript exists.
