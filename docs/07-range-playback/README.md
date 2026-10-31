# Step 7 — Compare a section without leaving the editor

Implemented on `milestone/range-preview`, based on `73f14bf`.
The current screen layout is described in [step 8](../08-editor-navigation/README.md);
its selection screen replaces the earlier bottom action tray.
This guide describes the playback feature: exact-range playback, kept/removed
context comparison, and an embedded video player.

## What the user does

Actionable source-time ranges have a play-circle button directly beside their
timestamps. Press it to play only that original section with sound intact.
Under Hear context, compare:

- **With section:** the original section plus up to one second before and after.
- **Without section:** the same source window with the proposed cut applied.
  Confirmed transcript-pause previews retain the same 150 ms edge padding as
  Shorten pause. For a word censor or mute selection, the second option is
  **Censored**, keeping the frames and silencing the selected audio.

Playback appears above the selection controls in the editor, inside the timing
bottom sheet, or at the top of Review. It does not push a playback route or open
a modal player. Pause, scrub, or replay using the native player controls; switch
comparison buttons without closing anything. The preview can be closed separately
from the selection. Previewing never adds, restores, or exports an edit.

The waveform/manual range and review controls use the selected cut/mute type.
Word/phrase context comparison demonstrates censoring. An unverified transcript
gap can be temporarily compared with removal, but still cannot be quick-trimmed
without confirmed silence. A time interval is playable; single-point timeline
ticks and duration totals are not separate ranges.

## Code map and data flow

- [time_range_playback.dart](../../lib/widgets/time_range_playback.dart): shared
  timestamp row and context buttons. `rangeTimestamp` preserves milliseconds;
  180000 ms is `3:00.000`. Longer recordings continue counting minutes. A
  descriptive play tooltip and 48-point target support accessible interaction.
- [context_preview.dart](../../lib/core/context_preview.dart): creates bounded
  source-time plans. Both versions use the same one-second surrounding window,
  clamped to the source. Removal retains only the before/after segments; muting
  retains the selected video with muted audio. Optional effect bounds preserve
  the proposed breathing room inside a transcript pause. Removing the whole
  recording produces a clear error because no surrounding video remains.
- [silence_review.dart](../../lib/widgets/silence_review.dart): each suggestion
  has exact playback and context comparison independent of its checkbox.
- [waveform_editor.dart](../../lib/widgets/waveform_editor.dart): plays the
  selected interval and delegates cut/mute context comparison to SilenceReview.
- [transcript_actions.dart](../../lib/transcript/transcript_actions.dart) and
  [transcript_panel.dart](../../lib/transcript/transcript_panel.dart): provide
  playable bounds and comparison callbacks for aligned words/phrases and gaps.
  Unaligned words have no playable timestamp. Recognition timing is approximate.
- [timing_screen.dart](../../lib/editor/timing_screen.dart) (originally the timing sheet): provides a local
  preview host and exact/manual comparison once numeric fields form a finite,
  ordered range within the source. Invalid ranges have no active preview.
- [review_screen.dart](../../lib/editor/review_screen.dart): keeps its preview
  visible above the scrolling edit list. Each edit can be heard in isolation;
  Play edited video still compiles every pending change. Export/restoring an
  edit closes stale playback.
- [playback_media_engine.dart](../../lib/editor/playback_media_engine.dart):
  pauses the inline original, asks the media adapter to validate the composition,
  then publishes the plan to the current surface's inline controller. Sheets and
  Review get their own controller, so previews do not open underneath another
  surface. Fake adapters still receive the same plan arguments in tests.
- [inline_preview.dart](../../lib/editor/inline_preview.dart): owns an immutable
  preview request and revision. A keyed `UiKitView` replaces the native player
  when the request changes. The host pauses on application inactivity and has
  a separate close button. The original player is hidden and paused while a
  transcript preview is active, preventing competing playback controls.
- [AppDelegate.swift](../../ios/Runner/AppDelegate.swift): `preview` validates
  the plan without presenting a window. `LocalCutPreviewFactory` registers
  `localcut/inline-preview`; `LocalCutPreviewView` embeds an AVPlayerViewController
  as a child of the Flutter controller and renders the same AVFoundation
  composition used by export. It disables PiP, pauses the previous preview,
  cancels pending preparation when disposed, and removes the child controller
  on teardown. Preparation errors appear in the embedded region for retry.

Exact playback sends one `RenderSegment(start, end, false)`. Context comparison
sends a short segment list. The native view builds its own composition after
validation; both operations copy timeline instructions, without encoding a
preview file. The composition begins at zero and ends at the final retained
frame, so playback cannot continue into the rest of the recording. Existing
cut/mute/export algorithms, media files, and pending edits remain unchanged.

## Worked examples

For a suggestion `0:03.000–0:05.000` in a ten-second recording:

- Play section: `[3000–5000, audible]`.
- With section: `[2000–6000, audible]`.
- Without section: `[2000–3000, audible] + [5000–6000, audible]`.

For a confirmed transcript gap from 1000–2800 ms, Shorten pause removes
1150–2650 ms. Its context is 0–3800 ms; the cut preview plays 0–1150 followed by
2650–3800, preserving 300 ms of breathing room in total. Comparing this preview
does not shorten the actual video until the user adds and exports the edit.

A mute comparison for 1000–2000 ms instead plays 0–1000 audible, 1000–2000 muted,
and 2000–3000 audible, keeping the duration unchanged.

## Setup and verification

**Fully rebuild the iOS app after this step.** Hot reload cannot register the
new native platform-view factory. The existing video-player dependency remains;
no new model or package download is required for this feature. All preview
processing remains local. Android's native composition/player implementation is
still a future milestone.

Verification run: `flutter analyze` passed without issues; all 66 tests passed
with `flutter test`; iOS-targeted Swift type checking passed. A widget-rendered
phone preview was also inspected (with a placeholder for native video).
Run `flutter analyze` and `flutter test` to repeat the Dart checks. Tests inspect exact range arguments,
kept/cut/muted context plans, source-edge clamping, padded transcript pauses,
checkbox/edit independence, manual-field validation, preview replacement and
close behavior, in-place editor navigation, and phone/landscape layouts.

Widget tests use fake media engines and a placeholder for the iPhone platform
view. They prove the plans and Flutter layout/navigation, not native decoding,
AVKit gestures, or audio/video sync. iOS-targeted Swift type checking is a
separate source check; it is not an on-device playback test.

On iPhone, compare identifiable speech across a proposed cut, switch between all
three choices, pause/replay/scrub, rotate the phone, and background/resume. Check
that the preview stops at the end, never autoplays after backgrounding, leaves
selection/edits intact, and stops when replaced/closed or the screen is left.
Test both source edges, no-audio clips, manual ranges, and a censored word.
Native rendering/performance still require this device acceptance.
