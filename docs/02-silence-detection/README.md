# Step 2: automatic silence suggestions

Implementation introduced in commit `f880c34` on
`milestone/silence-detection`. This guide was added in a later documentation
commit. Read [step 1](../01-cut-mute-export/README.md) first for edit planning,
platform messaging, preview, and export.

## Purpose

Find long quiet pauses locally and let the user decide which ones to remove.
This is volume-based detection, not transcription or an AI speech model. The
app does not know whether a sound is an “um,” music, or meaningful speech.

## User flow

Import → Analyze audio → adjust settings → hear original context → select
suggestions → preview selected cuts → Add selected cuts to edits → preview
and approve export through the existing workflow.

A suggestion is not an accepted edit. Even selecting its checkbox does not
add it to the main edit list; the user must explicitly press Add.

## Code map

- [AppDelegate.swift](../../ios/Runner/AppDelegate.swift): `analyzeAudio` and
  `cancelAnalysis` message handling, `OfflineAudioAnalyzer.analyze()`, and
  `AudioEnvelopeAccumulator`.
- [media_engine.dart](../../lib/media/media_engine.dart): `analyzeAudio()`
  converts the native response into `AudioAnalysis` and `AudioWindow` objects.
- [silence_detection.dart](../../lib/core/silence_detection.dart): settings,
  measured-window models, and the platform-independent `detectSilence()` logic.
- [silence_review.dart](../../lib/widgets/silence_review.dart): cached analysis,
  sliders, pending selection, context playback, and adding accepted cuts.
- [main.dart](../../lib/main.dart): inserts `SilenceReview` and appends accepted
  cuts to `_edits`, invalidating any previous exported-file reference.

## 1. Decode audio on the device

Flutter sends `analyzeAudio({path})` over `localcut/media`. Swift starts a
cancellable detached task so decoding does not block the UI thread.

`OfflineAudioAnalyzer` opens the first audio track with AVAssetReader and
requests interleaved, 32-bit floating-point PCM. PCM is a sequence of numbers
representing the signal amplitude. The reader provides one sample buffer at a
time; the code does not hold the whole decoded recording in memory or decode
the picture track for this analysis.

Each buffer has a source presentation timestamp and sample rate. For a frame
within the buffer:

```text
source time = buffer presentation time + frame index / sample rate
```

Using the source presentation timestamp preserves the relationship to video
time, including an audio track that starts later than the picture.

Cancellation is checked between buffers. Decode errors are reported to Flutter
rather than producing a partly trustworthy set of suggestions.

## 2. Reduce samples to 20 ms loudness measurements

`AudioEnvelopeAccumulator` groups PCM frames into about 20-millisecond windows.
At 48,000 frames per second, one complete window contains 960 frames.

For each channel, it accumulates squared amplitudes and divides by the number
of frames. It uses the largest channel power for the window:

```text
channel power = sum(sample × sample) / frame count
window power  = maximum channel power
window dBFS   = 10 × log10(window power)
```

This is the power form of an RMS level calculation. Digital silence is clamped
to a floor of -120 dBFS to avoid taking the logarithm of zero. Lower, more
negative values are quieter. For example, -60 dBFS is quieter than -30 dBFS.

The code keeps the loudest channel instead of downmixing stereo. Opposite-phase
channels could cancel in a mono mix and falsely appear silent; a silent channel
should also not dilute the active channel's level.

Partial windows are flushed at the end or a timestamp/format discontinuity.
Unknown gaps are not filled with invented silence. Native sample timing uses
seconds internally; the final window boundaries are integer milliseconds.

The compact response has this shape:

```text
{
  hasAudio: true,
  windows: [
    [startMs, endMs, measuredDbFS],
    ...
  ]
}
```

A source without an audio track returns `hasAudio: false` and no windows.

## 3. Detect continuous quiet runs in Dart

`detectSilence()` validates ordered, finite measurements within the video
bounds, then walks them in time order. It collects adjacent quiet windows into
runs. A louder window or unknown timeline gap ends a run.

Defaults in `SilenceSettings`:

- Threshold: -40 dBFS. A window at or below it counts as quiet.
- Minimum pause: 800 ms, measured before padding is removed.
- Retained padding: 150 ms at both ends of each quiet run.

A run is suggested only if it meets the minimum pause and still has positive
length after padding. Missing audio, no measurements, and an entirely quiet
source produce no suggestions. The latter requires at least one louder window
as an anchor; it is not proof that the louder window contains speech.

### Worked example

```text
Measured source:
  0.00–1.00 s: -18 dBFS
  1.00–3.00 s: -70 dBFS
  3.00–5.00 s: -20 dBFS

At the defaults:
  quiet run = 1.00–3.00 s, lasting 2 seconds
  cut start = 1.00 + 0.15 = 1.15 s
  cut end   = 3.00 - 0.15 = 2.85 s
  removed duration = 1.70 seconds

Compiled retained media:
  keep 0.00–1.15 s
  keep 2.85–5.00 s

Output duration = 3.30 seconds
```

A 500 ms quiet run stays untouched at the default minimum. A quiet run split
by audible sound is evaluated as separate pauses; we do not merge through that
sound. Raising the threshold from -40 to -30 includes more/louder windows and
may catch quiet speech, so review remains necessary.

## 4. Cache measurements and review suggestions

`SilenceReview` keeps one `AudioAnalysis` in memory for the current imported
source. Sliders rerun Dart detection using that cache; they do not decode audio
again. Analyze again explicitly replaces the measurements.

A new source creates a new widget state keyed by its path. Settings changes
clear pending checkbox selections but leave already-added edits alone. A
candidate already fully covered by an accepted cut is filtered out; partial
overlaps are handled by the existing edit-plan compiler.

The play icon previews original context extending about 700 ms before and
after a candidate, bounded by the source duration. Selected-cut preview
combines selected candidates with existing manual cuts and mutes. It leaves
`_edits` unchanged. Add validates the combined plan and then appends the selected
cuts. Export still requires the separate approval dialog from step 1.

If settings change after adding cuts, remove unwanted accepted cuts from the
proposed-edit list before adding their replacements. Cached analysis, settings,
and edits do not survive an app restart yet.

## Verification

```bash
flutter analyze
flutter test
python3 tool/check_audio_envelope.py
```

- [Detector tests](../../test/silence_detection_test.dart) check padding,
  short pauses, audible interruptions, missing timeline data, no audio,
  entirely quiet input, threshold changes, edge pauses, and invalid windows.
- [Review tests](../../test/silence_review_test.dart) check that selection and
  preview do not apply edits, explicit Add does, and no-audio input gives a
  clear result.
- [Native PCM checks](../../tool/check_audio_envelope.py) exercise the production
  accumulator with opposite-phase stereo, uneven buffer sizes, partial windows,
  timestamp gaps, and invalid samples. They do not invoke AVAssetReader.

At implementation time, Flutter analysis, all 14 Dart/widget tests, native PCM
checks, and Swift type checking passed. A separate AVAssetReader test failed
before reading samples in the execution environment with error -11800 on WAV
and MP4 fixtures. That environment test did not verify native decoding.

The user subsequently reported the sample-video workflow working. This is a
manual report; it does not establish broad device or format compatibility.

For a repeatable iPhone check, record speech, pause for two seconds, speak,
pause for three seconds, then speak again. At defaults, the two main gaps should
be proposed with padding retained. Compare context, selected preview, and final
export. Then try quiet speech, room noise, background music, and no-audio input.
Fully stop and relaunch the app after native Swift changes; Flutter hot reload
does not rebuild native code.

## Design choices and limits

Dart owns the detection rules and editing decisions; Swift only decodes and
measures audio. Android can implement the same window contract without
rewriting detection or review. No new app package or model is needed.

The detector cannot distinguish soft speech from quiet pauses. Music or room
noise can hide pauses. A 20 ms measurement and millisecond rounding provide
approximate boundaries, not word-level alignment. Padding reduces clipped
speech risk but does not guarantee natural cuts. Analysis progress is
indeterminate, cached windows grow with recording duration, and analysis runs
in the foreground without persistent caching or job recovery.

## Subsequent milestone

[Step 3](../03-waveform-selection/README.md) inserts the waveform above the pause
settings and shares this widget's cached analysis. The analysis, detector, and
native channel contract are unchanged. Changing silence settings clears pending
suggestion checkboxes but leaves the waveform's manual range alone.
