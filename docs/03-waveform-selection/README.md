# Step 3: waveform selection

Implemented on `milestone/waveform-selection`, branched from the accepted
silence-detection work at `de5c2a7`. The source and this guide are committed
together. `main` is not merged or changed by this milestone.

Read [step 1](../01-cut-mute-export/README.md) for source-time edit planning and
[step 2](../02-silence-detection/README.md) for the cached audio measurements.

## Purpose

Choose a cut or mute visually instead of having to type timestamps. The same
local analysis now powers both the waveform and the automatic pause finder.
The existing manual timestamp fields remain available.

The graph is a mirrored RMS loudness envelope, drawn from 20 ms measurements.
It is not individual PCM sample peaks, a word transcript, or an edited timeline.
All positions and selections refer to the original video.

## User flow

1. Import a video and tap **Analyze audio**.
2. A waveform appears above the silence settings if readable audio exists.
3. Tap the graph to hear original context around that position, or drag
   horizontally across it to select a range. Drag left or right to create it.
4. Drag the visible edges to resize the range. Use the start/end minus and plus
   buttons to adjust in 20 ms steps without typing.
5. Zoom in around the selection or last touched position. Use the navigation
   slider to move through the original recording; **Fit all** restores the full
   clip. Selection timestamps survive zooming and panning.
6. Choose **Cut selection** or **Mute selection**.
7. **Hear selection** plays just its original audio/video range.
   **Preview cut/mute** plays the complete proposed edit plan including this
   range. Neither action adds an edit.
8. **Add cut/mute** appends the instruction to proposed edits and clears the
   temporary range. Review the full result and explicitly approve export as
   before. **Clear range** discards only the temporary selection.

## Code map

- [waveform_timeline.dart](../../lib/core/waveform_timeline.dart): source-time
  viewport mapping, zoom/navigation, ordered selection and resize constraints,
  and display-resolution audio bins. No Flutter or native dependencies.
- [waveform_editor.dart](../../lib/widgets/waveform_editor.dart): gestures,
  temporary selection, zoom controls, nudge controls, preview/add actions, and
  `_WaveformPainter`.
- [silence_review.dart](../../lib/widgets/silence_review.dart): embeds the
  waveform using its existing cached `AudioAnalysis`; supplies source context,
  combined-plan preview, and accepted edit callbacks.
- [main.dart](../../lib/main.dart): accepts waveform cuts/mutes through the
  existing edit-list callback and invalidates the previous export reference.
- [waveform_timeline_test.dart](../../test/waveform_timeline_test.dart): mapping,
  zoom bounds, reverse drags, resizing limits, and envelope aggregation.
- [waveform_editor_test.dart](../../test/waveform_editor_test.dart): gestures,
  preview vs addition, cut/mute choice, context, zoom/pan, invalid full removal,
  disabled interaction, and phone-width layout.
- [silence_review_test.dart](../../test/silence_review_test.dart): integration
  with cached analysis and existing source-time cuts.

No native Swift, channel protocol, backend, or package dependency changes are
required. Android can use these same Flutter controls when its media adapter
is implemented.

## 1. Reuse the audio measurements

`SilenceReview` already keeps the measured windows in memory. It passes that
same `AudioAnalysis` to `WaveformEditor`, along with existing edits and current
silence candidates. Zooming, selecting, or nudging never invokes audio decoding.

The waveform is absent when no audio track or no measured windows exist.
Unknown gaps between measurements stay empty rather than inventing audio.
The existing manual controls remain usable without waveform analysis.

## 2. Map screen positions into source timestamps

`WaveformViewport` stores total duration and a visible source interval. For a
horizontal position `x` inside a graph of width `W`:

```text
fraction    = clamp(x / W, 0, 1)
source time = visible start + fraction × visible duration
```

Integer milliseconds are used for the final selection. Zoom changes the visible
interval, not the underlying edit timestamps. It attempts to keep the focused
source position at the same screen fraction, clamping at recording boundaries.
Zoom stops at a 250 ms visible interval, or the whole clip for shorter clips.
Navigation clamps the viewport so it stays inside the source.

### Worked example

```text
Source duration:     10 seconds
Visible interval:     5–10 seconds
Graph width:        300 pixels
Drag from x=60 to x=120:
  start = 5 + (60 / 300) × 5  = 6 seconds
  end   = 5 + (120 / 300) × 5 = 7 seconds
```

The resulting mute is `[6000, 7000)`, even if an earlier accepted cut has removed
one second. Step 1's composition places it at the correct output position.
The timeline does not shrink when edits are added.

## 3. Distinguish taps, new drags, and edge drags

Flutter's horizontal drag recognizer lets vertical gestures keep scrolling the
page. The first pointer-down position is remembered so touch slop does not
shift the start timestamp when the drag is recognized.

At drag start, a touch within 22 logical pixels of a visible selection edge
resizes that edge; the nearest edge wins if both are close. A drag elsewhere
starts a new range. Moving outside the graph clamps the endpoint to the visible
interval. Edges cannot cross: the minimum range is 20 ms, or the full source
length for a shorter clip.

The nudge buttons can adjust endpoints across viewport boundaries; pan or
Fit all to reveal an offscreen endpoint. The range label always displays the
actual source timestamps with three decimal places.

A tap updates the last touched position and requests original context from
700 ms before it to 1300 ms after it, clamped to the source. That marker records
the last interaction; it is not a live playback cursor synchronized with the
native player.

## 4. Draw an envelope at screen resolution

`waveformBins()` creates roughly one column per three logical pixels. Each
column uses the loudest measured dBFS value overlapping its source-time span.
Null columns have no measured audio. A window touching only the outside of the
viewport is excluded.

The bins are cached by window-list identity, viewport start/end, and column
count. Moving an edge or changing its action can repaint without scanning all
measurements again. Zooming, panning, resized layout, or a new analysis updates
the bins.

The painter draws a mirrored dB-level envelope using a fixed display range of
-60 to 0 dBFS. This improves readability; it is not the linear amplitude of the
raw signal and does not change detection thresholds. Very quiet measured audio
is a thin line; unmeasured gaps have no bars.

Separate marked lanes show:

- Suggested pauses at the top, from the current silence settings.
- Accepted cuts below them.
- Accepted mutes below the cuts.
- The temporary selection as a tinted region with two boundary handles.

Labels explain the colors. The marker and all lanes use original source time.
Overlaps are visible but their final priority still comes from `compilePlan()`.

## 5. Keep preview and application separate

The waveform holds only a temporary `WaveformSelection` and Cut/Mute choice.
`Preview` combines the selected `EditRange` with existing edits and calls
`compilePlan()` before invoking the same native preview engine used elsewhere.
It does not modify `_edits`.

`Add` validates the plan again, then calls the parent callback. The parent adds
the instruction and clears any previous export-file reference. The shared
compiler still handles overlaps, cut precedence, and invalid ranges. Attempting
to cut the whole source shows an error and leaves the range available to fix.

During analysis, preview preparation, or export, conflicting controls are
disabled through the existing busy state. On native preview, the full-screen
player opens as before; this milestone does not embed a new player.

## Verification

```bash
flutter analyze
flutter test
```

The 26 Dart/widget tests pass, including the previous milestones' tests. New
checks cover source mapping after zoom and pan, selection in either direction,
edge resizing, bounded context, preview without addition, mute addition,
full-removal rejection, disabled gestures, unknown audio bins, and a 375-pixel
phone layout. An integration test confirms waveform preview incorporates an
existing cut and adding a mute reuses the one cached audio analysis.

This verifies the Dart logic and Flutter interactions with fake media callbacks.
It does not verify native playback/export or touch ergonomics on a physical
phone. This milestone makes no native changes; test the full flow on an iPhone
before accepting it.

### iPhone acceptance check

1. Run the new branch and import a local video with speech and pauses.
2. Analyze once. Check the graph and suggestions match the rough audio levels.
3. Tap near the beginning/end: context playback must stay within the source.
4. Drag a range, choose Mute, hear it, and preview it. Confirm the edit list is
   unchanged until Add. After adding, confirm its mute lane appears.
5. Zoom in, pan later, select a cut, and adjust both edges. Verify the source
   timestamps shown by the range label match the audio you intended.
6. Add the cut, preview all edits, export, and check sound/picture alignment.
7. Remove an accepted edit; its lane must disappear. Change silence settings;
   suggestions should change without losing the manual waveform selection.
8. Try a silent or no-audio video and a short clip. Confirm the screen stays
   usable and existing manual editing still works.

## Current limitations

This displays 20 ms RMS measurements, not sample-accurate speech boundaries.
Nudges use 20 ms steps. A tap opens the existing native context player; there
is no continuous scrub audio or synchronized in-app playback marker. The
navigation control is a slider, not pinch-to-zoom or two-finger scrolling.
Analysis remains required before the waveform appears. Selection, viewport,
and edits remain in memory only. Long recordings and physical-device
interaction still need validation. No word transcription or automatic filler
removal has been added.

## Subsequent milestone

[Step 4](../04-transcript-models/README.md) puts transcript editing first and moves
this interface into **Waveform & pause tools**. The waveform and pause analysis
still use the same cached measurements. Speech recognition uses a separate
model/decoder path and creates the same source-time mute instructions.
