# Step 9 — Guided review for long recordings

Implemented on `milestone/guided-pause-review`, based on accepted commit `b14888d`.
The detector, source timestamps, native composition builder, and explicit export
approval are unchanged. This step replaces the tall repeated suggestion cards
with a compact overview and a focused reviewer.

## User flow

Open Timing & pauses, then Review suggested pauses. The timing page no longer
builds a long list of individual pause controls.

The overview shows the total suggested pauses, potentially removable duration,
review progress, and compact rows with a checkbox, original time range, duration,
status, and preview icon. It has one scroll viewport. Filtering offers All,
Unreviewed, Marked for removal, and Kept; sorting offers timeline order or longest
first. The list is lazily built, including when there are 100 suggestions.
Review next pause resumes a pending visited pause or starts with an unreviewed
one. Review options also offers Mark all for removal for an exceptions-first pass;
Undo restores the decisions that existed before that bulk operation.

A row opens the one-pause reviewer with:

- Pause position and reviewed count.
- The existing stable embedded video area.
- **Section:** only the original suggested removal range.
- **Original:** that range plus one second of original context on each side.
- **Trimmed:** the same surrounding window with the range removed.
- Keep pause and Trim pause decisions, followed by Previous and Next / skip.

Each decision advances to the next unreviewed pause in the current ordered queue,
wrapping around if necessary. Playback stops when moving between pauses. Skip
changes position without recording a decision. Undo returns to the affected
pause and restores its previous decision. When there are no unreviewed pauses,
the reviewer shows a completion state with Back to overview and Undo.

Decisions are separate from edits. Only **Add N cuts to edits** submits marked
cuts to the parent editor; Keep merely declines a suggestion and does not restore
an existing edit. Timing & pauses has a pinned **Proceed to review** button with the current edit
count. After adding cuts, it opens Review directly without requiring Back and
a second Review tap. It is disabled while processing or when no edits exist.
Export remains a further explicit approval step. Individual
checkboxes mark for removal; clearing one returns that pause to unreviewed.
“Reviewed” means a Keep/Trim decision exists, including bulk decisions; it does
not claim the user played every pause.

## Code map

- [pause_review.dart](../../lib/core/pause_review.dart): `PauseReviewSession`
  owns suggestions, decisions keyed by exact source bounds, detection settings,
  last visited pause, and undo snapshots. Filtering and sorting do not change
  identity. `sync` preserves matching decisions when candidates change, drops
  obsolete ones, and invalidates incompatible history. Identical candidates
  retain history. `applied` consumes submitted marks so restoring a cut later
  does not silently mark it for removal again.
- [pause_review_screen.dart](../../lib/editor/pause_review_screen.dart):
  `PauseOverviewScreen` uses one `CustomScrollView` with a header and lazy sliver
  rows. The header scrolls on small/landscape screens rather than crowding out
  the list. `PauseReviewerScreen` owns its preview controller and current queue
  index; it does not own or mutate the editor's edit list. The queue stays
  stable even as decisions make rows disappear from an overview filter.
- [compact_preview_switch.dart](../../lib/widgets/compact_preview_switch.dart):
  small segmented choices with icons and short labels, selected styling,
  explanatory tooltips, and full-size touch targets. Pressing the active choice
  replays it. Preparation disables comparison and decisions. Labels wrap at
  enlarged text sizes instead of pushing the control beyond the viewport.
- [time_range_playback.dart](../../lib/widgets/time_range_playback.dart):
  transcript, manual-range, waveform, and review context comparisons also use
  compact Original/Trimmed switches, or Original/Censored for mute decisions.
  Disabled context controls keep their space during preview preparation.
- [silence_review.dart](../../lib/widgets/silence_review.dart): keeps analysis,
  waveform, and detector settings; exposes a summary and entry into guided
  review. It validates combined edits through `compilePlan` before accepting
  marked cuts. Changing detection settings or successfully analyzing again
  clears review decisions, while already added edits remain unchanged.
- [editor_screen.dart](../../lib/editor/editor_screen.dart) and
  [timing_screen.dart](../../lib/editor/timing_screen.dart): keep the session at
  the source-video editor level, so decisions and detection settings survive
  leaving Timing and returning. Replacing the source creates a fresh session.
  Opening the overview closes any stale timing preview.

## Playback and data flow

The detector supplies original-source `EditRange` cuts. Review records Keep/Trim
values against `startMs:endMs`; it does not render a new file. Exact and context
previews use the segment lists from step 7. The reviewer's media decorator
publishes playback to its own embedded host instead of the underlying timing
page. No new native player, model, package, or backend is introduced.

Example: a suggestion from 3000–5000 ms has a two-second removable duration.
Section plays 3000–5000. Original plays 2000–6000. Trimmed plays 2000–3000 followed
by 5000–6000. Trim pause records the decision and moves forward, but creates no
edit. Undo clears/restores that decision and returns to its pause. Add 1 cut to
edits finally sends the original 3000–5000 range through existing validation.

If 100 suggestions total 150 seconds, the overview displays “100 suggested
pauses · 2m 30s removable.” Reviewing 29 of them changes progress to 29 of 100.
Marking ten for removal enables Add 10 cuts to edits. Potentially removable time
is the total of suggestions; it is not a prediction of net time saved once cuts
are combined with other existing edits. Context previews isolate one decision;
Review → Play edited video remains the check for all edits together.

## Verification

`flutter analyze` passed without issues. All **84 tests** passed with
`flutter test`. Widget-rendered phone screenshots with 100 fixture suggestions
were inspected for the overview and reviewer.

New checks cover decision identity, sorting, filters, bulk marking/undo,
compatible/incompatible candidate updates, lazy construction and reachability
of the hundredth row, automatic advance, Undo returning to the right pause,
completion, explicit addition, exact/context segment arguments, repeated replay,
preparation locks, session progress after reopening Timing, and consumption of
applied marks. Layout checks cover 320-pixel phones and landscape with enlarged
text. Existing transcript, waveform, silence, model, export, and navigation
regressions remain in the suite.

These widget checks use fake media engines and the native-view placeholder.
They do not establish actual decoding performance on a twenty-minute iPhone
recording. Test that on device: review several pauses, switch modes, undo,
leave/reopen Timing, filter/sort, mark a batch, add cuts, and inspect the full
edited composition before exporting. No additional native rebuild is needed
for this Dart-only step if step 7's embedded player is already installed.

## Limits

Review decisions and detector settings live only for the current in-memory
source-video session; restarting the app or replacing the source clears them.
This is not persistent project storage. Filters and sort are overview-view
preferences; returning from the reviewer retains the overview and its scroll
position, while reopening the overview from Timing starts its view afresh and
retains decisions/last visited pause.

Silence detection is still volume-based. A suggested range may contain quiet
speech, so marking everything is an optional shortcut rather than an automatic
export. This step adds neither speech-based retake detection nor a background
processing backend.
