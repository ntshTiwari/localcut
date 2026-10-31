# Step 8 — Clear destinations and one page scroll

Implemented on `milestone/editor-navigation`. This builds on the accepted creator
UI (`73f14bf`) and the range-preview working changes described in step 7. It
changes presentation/navigation; source-time edit planning and native composition
playback remain the same.

## Why this changed

A transcript viewport inside another scrolling page hid additional words. The
pause-suggestion list had its own viewport, and a player appeared above an action
tray when playback started. The Transcript badge and text-like timing button also
made it unclear what could be tapped.

## Current workflow

- The editor has a real **Transcript** heading and a **Timing & pauses** navigation
  card with a tool icon, description, material tap response, and chevron.
- Transcript paragraphs flow with the whole editor page. There is no independently
  draggable transcript viewport. The page has an explicit scroll indicator.
- Tap a word or pause to open **Edit selection**. Its video slot exists before
  playback begins; pressing an exact/context preview does not insert a player
  into the transcript or rearrange the action tray.
- The selection page keeps all comparison and editing controls together in one
  scrolling page. Add a change or restore it to return to the transcript. Back
  returns without editing and preserves the selection; the same word can reopen
  it, or use Edit selected section. Selecting a phrase returns to the transcript
  to choose its last word, then reopens the selection page.
- **Timing & pauses** opens a full screen with its own app bar and Back action.
  Waveform editor and Detection settings are collapsed, explicitly expandable
  sections so they do not obscure the suggestions. Pause rows are numbered
  “Pause 1 of N” and all flow with the page; there is no small internal list to
  discover. Manual numeric ranges remain further down the same page.
- Timing playback uses a stable video area. Review/export stays a separate step.
  Original media and pending edits survive navigation between these tools.

## Code map

- [editor_screen.dart](../../lib/editor/editor_screen.dart): owns the edit session,
  transcript selection, analysis cache, and page scroll position. `_timing`
  pushes a route. `_selected` updates selection state; only explicit selection
  requests open its page, so timing/review changes cannot unexpectedly navigate.
  `_openSelection` prevents duplicate pages and closes playback on return.
  The old scrollable bottom action tray is replaced by one compact selection
  button and the Review button.
- [selection_screen.dart](../../lib/editor/selection_screen.dart): observes action,
  busy, and error notifiers from the transcript. A cleared selection or a phrase
  endpoint request returns to the transcript. Route guards prevent double pops
  and leaving during preparation. The editing actions still call the existing
  transcript logic rather than maintaining a second edit list.
- [inline_preview.dart](../../lib/editor/inline_preview.dart): adds a placeholder
  mode with the same dimensions as active playback. A playback mode label replaces
  the placeholder label when ready. Native rendering is still embedded in the
  selection page, not a separate full-screen AVKit modal.
- [timing_screen.dart](../../lib/editor/timing_screen.dart): replaces the former
  `fine_tune_sheet.dart`. It provides a full Scaffold, Back action, stable preview
  slot, and one page controller/scrollbar. Analysis and pending edits are shared
  with the parent session.
- [transcript_document.dart](../../lib/transcript/transcript_document.dart):
  paragraph content expands into the parent page instead of a 380-pixel viewport.
- [silence_review.dart](../../lib/widgets/silence_review.dart): suggestion rows
  expand into the page, display their ordinal/total, and optionally collapse the
  advanced tools. Independent scrolling is disabled and `primary` is false on
  the inner content lists. Standalone embedding can retain expanded tools.
- [transcript_panel.dart](../../lib/transcript/transcript_panel.dart): exposes
  operation errors to the selection page and forces selection publication after
  an intentional tap, allowing the same selected word to reopen. Automatic
  widget updates retain signature-based loop protection.

## Example

Tap a 1.8-second pause. Edit selection opens with a stable video area, exact
source timestamps, With section, Without section, and Shorten pause. Compare
both versions without leaving that page. Shorten pause adds the same padded
source-time cut as before and returns to the transcript, where Review shows one
change. Opening Timing & pauses and returning does not regenerate the transcript
or clear that cut. No file changes until the existing export approval step.

## Verification

Verification run: `flutter analyze` passed without issues and all 72 tests passed
with `flutter test`. Rendered phone screens were visually checked using fixture
content. Run those commands to repeat the Dart checks. Navigation tests cover:

- The timing card's actual tap callback and full-page destination.
- One user-scrollable page on transcript, selection, and timing screens.
- A stable preview-slot size before/after playback.
- Back, reopening the same selected word, and applying a change.
- Phrase endpoint selection across two words.
- Playback errors shown on the active selection page.
- Multiple numbered suggestions reachable through the page scroll.
- Timing changes do not reopen an earlier transcript selection.

The existing cut/mute, silence, waveform, model, context comparison, phone,
landscape, review, and export tests remain in the suite. Widget screenshots use
fixture transcripts and a placeholder for the iPhone native view; they are design
checks, not evidence of on-device decoding or AVKit behavior.

Manual acceptance: import a recording, generate a transcript, scroll to its last
paragraph, open a word/pause and compare, return/reopen, select a phrase, open
Timing & pauses, expand a tool, inspect the last numbered suggestion, and export
an approved edit. Check larger text, both appearances, and rotation. Existing
native preview registration from step 7 still requires a full iOS rebuild if it
has not yet been installed. This step adds no further native dependency.

## Limits

Draft projects still live in memory for the session. Expanded content lists lay
out their paragraphs/rows to fit the parent page; very long transcripts need
performance profiling, and a future sliver-based document can preserve this
single-scroll interaction with more aggressive virtualization. This step does
not add transcript search, project persistence, or retake detection.
