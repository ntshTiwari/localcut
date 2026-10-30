# Step 5: edit words and pauses in one transcript

Implemented on `milestone/transcript-pause-editor`, based on working transcript
commit `6c21745`. This guide accompanies the code. `main` is unchanged.

## Purpose

Replace separate selection, preview, and manual editing panels with one primary
flow: read → tap a word or pause → choose an action → review → export.

This is a Flutter UI and shared-logic milestone. The speech models, native
transcription engine, and native media/export APIs from earlier steps are
unchanged. Restart the Flutter app to test it; no new model download is needed
if the corresponding weights are already installed.

## What the user sees

- A readable transcript with small duration markers between words.
- **Pause 1.8s** means at least that much quiet audio was confirmed between
  adjacent aligned words. Longer pauses have slightly wider markers, capped
  so they still wrap on a phone.
- **Gap 1.8s** means recognition timestamps leave a gap, but silence was not
  confirmed. It can be heard, but does not offer automatic shortening.
- Tap a word to select it. Nothing plays or changes automatically.
- The action bar stays at the bottom, above **Review N changes**, even when
  the transcript scrolls.
- **Hear** plays original context. **Censor** adds a proposed mute.
- **Select phrase** asks for the last word; tapping it selects a consecutive
  phrase. The same Censor action applies to that range. Long-press is no longer
  required.
- Tap a verified pause and choose **Shorten pause**. The bar states how much
  will be removed and how much breathing room remains.
- A shortened marker reads **Pause 1.8s → 0.3s**. Censored words have a mute icon
  and shading; a temporary selection has a separate highlight and underline.
- Tap an edited item and choose **Restore** to put back only that interval.
- **Review** lists the proposed changes, offers whole-change undo, previews the
  edited video, and exports only when the user taps **Export video**.
- Language/model controls collapse into **Language & downloads** once the
  transcript is ready. Waveform, automatic pause settings, and exact timestamp
  fields live under **Fine-tune timing**.

Export itself is the explicit approval action on the review screen. There is
no second confirmation dialog after reviewing the concrete change list. The
original video stays untouched; export creates a new file as before.

## Code map

- [transcript_gaps.dart](../../lib/transcript/transcript_gaps.dart): gaps,
  quiet-audio confirmation, safe pause cuts, union coverage, and partial restore.
- [transcript_document.dart](../../lib/transcript/transcript_document.dart):
  readable words, duration chips, selection styling, and pending-edit marks.
- [transcript_actions.dart](../../lib/transcript/transcript_actions.dart):
  selection action data and the reusable bottom action bar.
- [transcript_panel.dart](../../lib/transcript/transcript_panel.dart): source
  transcript and language state, shared audio analysis, explicit selection,
  action publishing, and adding/restoring edits.
- [main.dart](../../lib/main.dart): fixed bottom navigation, one review sheet,
  shared analysis cache, pending-edit ownership, and export approval.
- [silence_review.dart](../../lib/widgets/silence_review.dart): accepts the
  shared analysis and publishes re-analysis back to the main screen.
- [edit_plan.dart](../../lib/core/edit_plan.dart): optional human-readable edit
  labels. Compilation and source-time behavior remain unchanged.
- [transcript.dart](../../lib/transcript/transcript.dart): selected phrases now
  give their mute an explanatory label such as `Censor “Hello friend”`.

## 1. Build markers from original word timings

`transcriptGaps()` examines adjacent recognized words. If either lacks valid
alignment, no gap is invented across it. For two aligned words:

```text
gap start = previous word end
gap end   = next word start
```

Only gaps of at least 500 ms get a marker. Smaller gaps remain normal text
spacing, reducing visual clutter. Gap IDs use the index of the following word,
so selection stays stable when an analysis result arrives.

All markers and edits refer to the original recording. Trimming an earlier
pause never shifts the source timestamps attached to later words.

## 2. Confirm quiet audio before offering a cut

After a transcript is generated, the panel obtains the local audio measurements
from step 2 unless a shared analysis already exists. It does not treat the
absence of recognized words as evidence that audio is silent.

The shared detector finds continuous measured runs at or below -40 dBFS for at
least 500 ms, with zero padding during detection. Gaps in measured data and
louder samples break quiet runs. An entirely quiet recording still has no
speech anchor, so the detector proposes no cuts.

For each word gap, intersect the quiet runs with that gap. Choose the longest
single quiet intersection that lasts at least 500 ms. Do not combine separate
runs through noise, missing measurements, or unrecognized speech.

If only part of a word gap is quiet, the **Pause** chip describes that confirmed
quiet part. The rest of the gap is left untouched. Unknown or noisy gaps use
**Gap** and only offer listening/fine adjustment.

Quietness is volume-based, not a guarantee of no meaningful speech. Soft speech
can still be classified as quiet. The user can Hear, Restore, and preview every
proposed edit before exporting.

### Worked example

```text
Previous word ends:          1.00 s
Next word starts:            3.00 s
Measured quiet audio:        1.20–2.80 s

Marker:                     Pause 1.6s
Keep:                       0.15 s on each edge
Proposed cut:                1.35–2.65 s
Removed:                    1.30 s
Marker after adding cut:     Pause 1.6s → 0.3s
```

Audio at 1.00–1.20 and 2.80–3.00 remains untouched. If the gap contains no
confirmed quiet interval, it cannot create a one-tap cut.

## 3. Reuse analysis instead of decoding twice

The main screen owns an `AudioAnalysis?` for the current imported source.
Transcript and waveform/pause tools accept it and publish new analysis through
callbacks. Opening Fine-tune after transcript generation immediately uses the
same measurements; it does not start another decode.

Gap detection is cached by transcript and analysis identity. Selecting words
or adding a mute does not scan PCM again. Duration labels for edited markers
are computed from pending cuts, using the union of overlaps so time is never
counted twice.

If checking audio fails, the transcript still appears and censorship stays
available. Unverified gaps cannot be shortened. **Check pauses** allows a retry.
Canceling during the analysis phase requests `MediaEngine.cancelAnalysis()`;
it does not publish a partly generated new transcript. A completed language
transcript and all existing edits are retained until a new generation succeeds.

## 4. Keep selection distinct from editing

A selected word, phrase, or gap is temporary UI state. It has no effect on the
edit plan until Censor or Shorten is pressed. Hear plays original context with
500 ms before and 700 ms after the selected source interval, bounded by the
video duration.

A word click selects one word. Select phrase retains its anchor and waits for
an endpoint click; endpoints work in either order. Timing validation from
step 4 still rejects phrases containing unaligned words.

`TranscriptActions` describes the selected item and the callbacks currently
available for it. The main screen renders those actions outside its scrolling
body. Busy state disables conflicting actions. The panel publishes a new
descriptor only when the selection, confirmed interval, or effective edit
ranges change; this prevents callback-driven rebuild loops.

Standalone panel tests render the same action bar inline when no main-screen
selection callback is supplied. In the actual app it is always in the fixed
bottom region with the Review button.

## 5. Restore only what was selected

Removing an entire phrase mute when restoring a single word would unexpectedly
uncensor other words. `restoreEdits()` subtracts only the selected interval:

```text
Existing mute:        0.00–3.00 s
Restore selected:     1.00–2.00 s

Remaining mutes:      0.00–1.00 s and 2.00–3.00 s
```

Word restore can remove overlapping cuts and mutes within that word/phrase.
Pause restore affects cuts only, preserving unrelated manual mutes. Split edits
lose their old phrase label so the review does not describe restored words as
still censored. The review sheet also offers whole-change undo through its
Restore icon.

The original media and word times never change. These operations only alter
proposed editing instructions consumed by the existing compiler.

## 6. Use one review and export screen

The bottom Review button counts proposed edit ranges. A restored portion may
split an edit into two ranges, so the count is not a history of button presses.
The sheet shows original and edited duration and a readable label per range.
Each label also shows exact original source times.

**Play edited video** compiles the current plan and invokes native preview.
It does not export. **Export video** is the approval action and invokes the
same native exporter. After success the action becomes **Save or share**.
Changing/restoring an edit invalidates that export reference. While working,
conflicting sheet actions and closing are disabled; export cancellation remains
available. Removing all changes disables export until new edits are added.

## Verification

```bash
flutter analyze
flutter test
```

The 49 project tests cover prior milestones and this redesign. New checks
exercise unknown/noisy gaps, clipped quiet intervals, separate quiet runs,
unaligned neighbors, union duration, partial restoration, pause-only restore,
and the complete import/generate/select/censor/shorten/review/export flow with
fake media callbacks. Integration checks ensure audio is reused in Fine-tune,
no preview/export occurs merely on selection, and only explicit Export calls
the encoder API. Tests also cover failed/canceled pause checking and visible
bottom actions on a 375×812 phone layout.

Phone-sized rendered examples were inspected with fixture data for both editor
and review. These are layout checks, not device encoding tests. There are no
native changes in this milestone. Real on-device interaction and output still
need the following acceptance check.

## iPhone acceptance check

1. Generate an English transcript from a local video with speech and long
   pauses. Verify quiet gaps appear as Pause markers without extra setup.
2. Tap a word: it should select without playing. Hear should play original
   context. Censor should mark it and increment Review.
3. Select phrase, tap the last word, censor, and verify the intended range.
4. Tap a confirmed pause, inspect remove/keep time, then shorten it. Check its
   duration arrow, Hear, Restore, and repeat.
5. Use a clip with unrecognized noise between words. Gap may appear, but it
   must not offer automatic shortening without confirmed quiet audio.
6. Open Review, undo a change, play the edited result, and export. Verify
   censor timing, natural pause edges, sync, and the saved file.
7. Open Fine-tune and confirm waveform/settings remain available without an
   extra automatic analysis. Change videos and confirm old selections vanish.
8. Try longer transcripts, landscape orientation, and larger system text.

## Limits

Markers currently cover gaps between adjacent aligned words, not leading or
trailing silence. Only the longest confirmed quiet portion of a gap is offered
as its quick cut. Quietness thresholds remain adjustable in Fine-tune. Padding
is fixed at 300 ms total for the quick action. There is no general undo history
or persisted project state. Recognition/timing limitations from step 4 still
apply. Duration chips wrap with text; they are not a proportional timeline or
a substitute for waveform-level alignment.
