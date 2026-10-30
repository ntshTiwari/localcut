# Step 1: cut, mute, preview, and export

Implementation introduced in commit `118be0c` on `main`. This guide was added
later, without rewriting that commit. The current interface also includes the
[step 2 silence panel](../02-silence-detection/README.md).

## Purpose

Let someone clean up one local video on an iPhone, preview the edits, and
approve a new MP4 export. The original stays untouched. There is no backend,
account, speech model, or upload in the app.

## User flow

Import from Files → watch the original → enter original start/end timestamps →
choose Cut or Mute → add proposed edits → preview → approve export → share/save.

The first version uses timestamps entered in seconds. It does not transcribe
spoken words or provide waveform selection yet.

## Code map

- [main.dart](../../lib/main.dart): `EditorScreen` holds the source and proposed
  edits. `_add()` validates manual ranges. `_approveExport()` asks the user
  to approve the current plan before calling the media engine.
- [edit_plan.dart](../../lib/core/edit_plan.dart): `EditRange` describes an edit;
  `RenderSegment` describes retained media; `compilePlan()` converts one into
  the other.
- [media_engine.dart](../../lib/media/media_engine.dart): `MediaEngine` defines
  operations and `PlatformMediaEngine` sends messages to native code.
- [AppDelegate.swift](../../ios/Runner/AppDelegate.swift): `handle()` routes
  messages; the document-picker delegate imports footage; `compose()` builds
  edited media; `export()` writes an MP4.
- [edit_plan_test.dart](../../test/edit_plan_test.dart): overlapping ranges,
  retained duration, and invalid edit checks.

## 1. Import a local working copy

Flutter asks `MediaEngine.importVideo()`. The iOS implementation opens the
Files picker, copies the selected file into Application Support/LocalCut, and
uses AVFoundation to check its duration and video track. It returns:

```text
SourceVideo(path: local-file-path, durationMs: original-duration)
```

The app stores this in memory. The picker does not edit the selected original.
A cloud-only file must first be available locally to work in airplane mode.

## 2. Store editing instructions, not changed media

An `EditRange` has `startMs`, `endMs`, and `kind` (`cut` or `mute`). UI seconds
are converted to integer milliseconds. All edits refer to the original source.

For example, `EditRange(4000, 5000, EditKind.mute)` always means the original
fourth-to-fifth second, even if an earlier second is removed later.

`_add()` runs `compilePlan()` before accepting a new edit. It rejects negative,
reversed, zero-length, or out-of-bounds ranges, and rejects removing the entire
video. Removing a proposed edit simply removes its instruction from the list.
The current UI has removal, not a general undo/redo history.

## 3. Compile edits into sections to keep

`compilePlan(durationMs, edits)`:

1. Collects source start/end and all edit start/end times as boundaries.
2. Sorts and deduplicates those boundaries.
3. Examines each interval between neighboring boundaries.
4. Skips an interval if a cut covers it.
5. Otherwise marks the interval muted if a mute covers it.
6. Merges adjacent retained intervals with the same mute state.

A cut wins when cut and mute overlap: there is no retained audio to mute in a
removed section. The result is an ordered list of `RenderSegment` objects.

### Worked example

For a ten-second source, remove seconds 2–3 and mute original seconds 4–5:

```text
Inputs:
  Cut:  [2000, 3000)
  Mute: [4000, 5000)

Compiled retained source sections:
  [0, 2000)      normal audio
  [3000, 4000)   normal audio
  [4000, 5000)   muted audio
  [5000, 10000)  normal audio

Output duration: 9 seconds
Mute location in output: 3–4 seconds
```

The notation `[start, end)` includes the start and excludes the end; adjacent
sections can share a boundary without duplicating it.

## 4. Send the plan through the platform boundary

The `localcut/media` method channel transmits the local source path and a list
of `{startMs, endMs, muted}` maps. It does not move video frames through Dart.
Methods include `import`, `preview`, `export`, `share`, and `cancelExport`.

Dart controls the editing decisions. Swift controls Apple's media APIs. A
future Android adapter can implement this same contract without replacing
`compilePlan()` or the Flutter interface.

## 5. Build matching video and audio timelines

`compose()` creates an `AVMutableComposition` and a destination cursor at zero.
For each retained segment, it inserts that source video range at the cursor,
inserts its available source audio at the corresponding position, sets audio
volume to zero or one, and advances the cursor by the retained duration.

Removing the same source ranges from picture and sound keeps them aligned.
Muting changes audio volume but removes no time. Audio coverage is intersected
with the requested section to accommodate a shorter audio track. The source
video's preferred transform preserves its orientation.

## 6. Preview and export use the same assembly logic

For preview, `compose()` supplies an `AVPlayerItem` and audio mix to AVPlayer.
No full preview movie needs to be rendered first.

After user approval, `export()` builds a composition using the same function
and uses `AVAssetExportSession` with Apple's 1080p preset to write a new MP4.
Export re-encodes as needed; it is not guaranteed lossless. Its file goes into
app storage and the share sheet lets the user save or send it elsewhere.

Cancellation stops the export and attempts to remove partial output. Export
keeps the display awake while running and restores its previous idle setting
afterward. There is no resumable background export in this version.

## Verification

```bash
flutter analyze
flutter test test/edit_plan_test.dart test/widget_test.dart
```

The automated checks exercise edit-plan behavior and the initial screen.
They do not verify the native encoder or player.

On an iPhone, use a video longer than 12 seconds. Add cuts at 2–3 and 7–8 seconds,
then mute original seconds 4–5. The output should be two seconds shorter, with
the mute at output seconds 3–4. Compare preview and saved export, checking
orientation and lip sync. Repeat with a local file in airplane mode.

The user reported the expected first-milestone workflow working. This is a
manual report, not a comprehensive codec/device compatibility test.

## Current limitations

One source and its first audio track are used. Project reopening, waveform
selection, storage cleanup, numeric export progress, and Android media support
are not implemented. Edits live in memory and disappear on restart. Copies and
exports stay in app storage. Mute edges use hard volume changes, which may need
short fades to avoid clicks. HDR, unusual codecs, and long videos need broader
device testing.
