# LocalCut — offline iPhone prototype

Flutter UI and shared edit planning, with a Swift AVFoundation media adapter.
No app backend, account, or media uploads. Network access is used only for
on-demand speech-model downloads; recognition runs locally afterward.

## Code walkthroughs

Start with [docs/README.md](docs/README.md) for step-by-step explanations of
cuts, muting, export, and silence detection. Each code-changing commit must
include its corresponding documentation update; new milestones get a numbered
guide under `docs/` beside `lib/`.

## Transcript editing

Choose **English**, **Hindi**, or **Hindi–English** after importing a video.
Download the required model on first transcription: English is about 148 MB;
Hindi and Hindi–English share one 488 MB multilingual download. Selection alone
does not download anything. Subsequent recognition works offline.

Tap a word, then **Censor**, or **Select phrase** and tap its last word.
Tap a confirmed **Pause 1.8s** marker and **Shorten pause** to keep 0.3s of
breathing room. Unverified **Gap** markers offer listening, not automatic cuts.
Edited words and pauses show the proposed change; tap them to Restore.

The bottom action bar stays visible while reading. **Review N changes** opens
one screen for undo, playback, and explicit export. Language/model controls
collapse under **Language & downloads** after generation, and waveform/manual
controls live under **Fine-tune timing**. Pause analysis is reused across both.

See [step 5](docs/05-transcript-pause-editor/README.md) for the current UI and logic.

**Installing the native transcription milestone for the first time requires a full iOS rebuild.** Xcode resolves the pinned
whisper.cpp native library through a local Swift package. Hot reload is not enough.
See [step 4](docs/04-transcript-models/README.md) for setup, model storage, download
verification, the code walkthrough, tests, and limitations.

## Implemented

- Import a local video using the iOS Files picker (copy into app storage).
- Watch the original and enter source-time cut or mute ranges in seconds.
- Remove proposed edits and preview the resulting native composition.
- Explicitly approve export to a new MP4; original media is unchanged.
- Cancel export and share/save the result through the iOS share sheet.
- Preserve orientation and use one composition builder for preview/export.

- Analyze local audio for long quiet pauses without a backend or AI model.
- Display the source waveform with marked suggestions, cuts, and mutes.
- Drag/resize a range, zoom and navigate, and adjust its edges in 20 ms steps.
- Hear original context and preview a waveform cut/mute before adding it.
- Tune threshold (default -40 dBFS), minimum pause (800 ms), and retained edge
  padding (150 ms on each side), reusing cached measurements for the session.
- Hear original context, select suggestions, preview them, and explicitly add
  them to proposed edits before the existing export approval step.
- Cancel analysis. Missing audio and entirely quiet videos produce no cuts.

Project reopening, persistent transcripts, numeric export progress, Photos
import, and Android media processing are subsequent milestones.

## Run on your iPhone

Prerequisites: Flutter, Xcode with iOS platform support, and an iPhone with
Developer Mode enabled, running iOS 16 or later. Initial tooling setup may require internet; editing
runs offline once installed. Use a short SDR video for the first test.

1. Open `ios/Runner.xcworkspace` in Xcode.
2. Under Runner → Signing & Capabilities, select your development team and
   choose a unique bundle identifier if required.
3. Connect and trust your iPhone; select it as the run destination.
4. From this directory run `flutter pub get`, then `flutter run`.
5. If the video is only in Photos, save it to Files first. iCloud-only files
   need to be downloaded before an airplane-mode test.

## Acceptance exercise

Use a recording longer than 12 seconds with visible talking or hand claps.

1. Import the video and watch the original.
2. Add cuts at 2–3 seconds and 7–8 seconds (source timestamps).
3. Add a mute at 4–5 seconds.
4. Preview: output should be two seconds shorter, with muted sound at output
   time 3–4 seconds. Video must continue normally during muting.
5. Approve export, save through the share sheet, then watch the saved MP4.
6. Check orientation, lip sync, cut boundaries, and mute timing.
7. Repeat in airplane mode with a locally available file.

## Silence-detection acceptance exercise

1. Record yourself speaking, pause for about two seconds, then speak again.
2. Import the recording, tap **Analyze audio**, and inspect the suggestions.
3. Use the play icon beside a suggestion to hear its original context.
4. Select a suggestion and tap **Preview selected silence cuts**. Your manual
   cuts and mutes are included in that preview too.
5. Tap **Add selected cuts to edits**, then preview and approve export.
6. Confirm speech starts/ends naturally and the exported result matches preview.
7. Adjust settings: candidates recalculate without decoding again and the
   pending selection clears. Already-added edits remain in the proposed list;
   remove them there if you want a different version of the same pause.
8. Test no-audio, noisy-room, quiet-speaker, and all-silent recordings too.

This is volume-based quiet detection, not speech recognition. Background music
can prevent pause detection and soft speech can look quiet. Every cut requires
selection and review. Unknown gaps in decoded audio are not treated as silence.

## Waveform selection

After **Analyze audio**, drag across the waveform to select original source
media. Drag its edges or use the start/end buttons to adjust it. Zoom and use
the navigation slider for smaller sections. Choose Cut or Mute, preview, then
Add. Tapping the graph opens original context playback. Analysis is shared
with the pause finder; waveform controls do not decode again.

See [the step-3 walkthrough](docs/03-waveform-selection/README.md) for the
mapping, drawing logic, and an iPhone acceptance checklist.

## Architecture

- `lib/core/edit_plan.dart`: platform-independent source-time ranges and plan
  compiler. Cuts take precedence; adjacent equal-state segments are merged.
- `lib/media/media_engine.dart`: backend-neutral interface and one version-one
  platform channel adapter (`localcut/media`). Small, explicit message schema.
- `lib/main.dart`: import → mark → review → approve → export UI.
- `lib/transcript/`: language packs, timed transcript models, recognition bridge,
  readable words/confirmed pause markers, shared selection actions, scoped restore,
  and model-download controls.
- `ios/Runner/LocalTranscription.swift`: verified weight storage/downloads,
  cancellable local recognition, and bounded PCM input chunks.
- `ios/Packages/LocalWhisper/Package.swift`: checksum-pinned native speech engine.
- `lib/core/silence_detection.dart`: shared pause detection over measured audio
  windows, independent of Apple APIs and ready for an Android decoder adapter.
- `lib/core/waveform_timeline.dart`: source-time viewport, range constraints,
  and display-resolution loudness aggregation.
- `lib/widgets/waveform_editor.dart`: source waveform, zoom/navigation, gesture
  selection, preview, and explicit cut/mute addition.
- `lib/widgets/silence_review.dart`: analysis settings, selection, context
  playback, candidate preview, and explicit addition to the edit list.
- `ios/Runner/AppDelegate.swift`: iOS import, source inspection, composition,
  native player, export, and share adapter. Kept in a registered Runner source
  file for the initial proof; extract into a plugin as the engine grows.
- `android/`: Flutter-generated scaffold only. Implement the same media
  interface in Kotlin/Media3 later. The shared edit compiler is already reusable.

The bridge transmits only file references and edit metadata, never video frames.
All range timestamps are integer milliseconds on the original video timeline.
Native composition converts them to CMTime and assembles retained segments.
The audio bridge adds `analyzeAudio({path})`, returning
`{hasAudio, windows: [[startMs, endMs, dbFS], ...]}`, and `cancelAnalysis()`.
iOS decodes 32-bit float PCM using AVAssetReader on a detached task, computes
20 ms RMS windows using the loudest channel, and sends only that compact
envelope to Dart. Stereo is not downmixed, avoiding phase cancellation. Raw
PCM is released per buffer. Cancellation is checked between buffers. The
measurements remain in memory for the current imported source; settings reuse
them. Android will provide the same window contract through MediaCodec later.
Silence detection needs no AI model. Transcript generation uses optional
downloaded Whisper models. FFmpeg is not an app dependency.

## Checks

Run `flutter analyze` and `flutter test`. On macOS, also run
`python3 tool/check_audio_envelope.py` for native PCM checks.
Tests cover overlapping cuts/mutes, range validation, pause padding, threshold
changes, missing/quiet audio, unknown timeline gaps, and explicit suggestion
selection/preview/addition. Native PCM checks cover opposite-phase stereo,
uneven buffer boundaries, partial windows, gaps, and invalid sample rejection. Native playback and encoding must additionally
be checked on an iPhone; Dart tests do not validate media output.

## Validation in this workspace

Flutter analysis and Dart/widget tests pass. Swift is checked
against the installed iOS SDK separately. Full app builds currently fail in
asset compilation because Xcode cannot access an available simulator runtime
in this execution session. The user has confirmed the expected edit workflow works in their test.
The user subsequently reported the sample-video workflow working. This is a
manual report, not comprehensive native decoder/device verification.
An attempted AVAssetReader fixture test in this execution session fails at
reader startup with AVFoundation error -11800 on both WAV and MP4; PCM
accumulation is separately tested without the media reader. Broader device,
format, and long-recording validation is still pending.

## Current limitations

- Foreground exports only, with indeterminate progress. Keep the app open.
- Imported copies and exports remain in app storage; project history and
  storage management are not implemented. Removing the app clears its data.
- Reopening the app does not restore edit state yet.
- Intended for one video and its first audio track. Multi-track audio,
  HDR/color handling, very long recordings, and arbitrary codec support need
  device validation before claiming support.
- Export uses Apple's 1080p preset and MP4; exact output dimensions depend on
  the source and native preset. It does not guarantee lossless export.
- Mute edges currently use hard volume changes. Short audio fades can be added
  after the initial export path is verified.

## Milestone branches

Each milestone starts on its own branch from the accepted base. The silence
detection work lives on `milestone/silence-detection`. Waveform selection lives
on `milestone/waveform-selection`, based on the pushed silence milestone.
Transcript models live on `milestone/transcript-language-models`, based on
waveform commit `b490f03`. The unified transcript/pause editor lives on
`milestone/transcript-pause-editor`, based on `6c21745`. `main` retains the first
working prototype until the user requests a merge.
