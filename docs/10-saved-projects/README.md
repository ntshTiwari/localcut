# Step 10 — Saved projects and local autosave

Implemented on `milestone/saved-projects`, based on accepted commit `8ae3ab1`.
This step makes the editing session durable without adding a backend, account,
cloud service, database dependency, or another copy of the video per save.

## What the user does

Import a video to create a saved project before editing begins. Home always keeps
its original hero/import layout. A **Recent projects** button opens a separate
library with search by project name, All/With changes/No changes filters, and
sorting by recently saved, newest created, name A–Z, or longest video. The cards
show duration and edit count. Tap a card to resume; its menu offers Rename project
and Delete project. Empty libraries and no-match searches have distinct messages
and a way back to importing or clearing filters.

The editor shows Saved on this device, Changes waiting to save, Saving project,
or Could not autosave. Errors offer Retry save. A failure is also announced while
reviewing pauses or using another tool, so it is not hidden on the parent editor.
Leaving for Home flushes pending changes; if saving fails, editing stays open so
the user can retry. There is no discard-edits confirmation for a saved project.
Import another video saves the current project and creates another one instead
of overwriting the old project.

A project restores:

- Its imported video reference, title, creation/save dates, and duration.
- Pending source-time cut/mute edits and their labels.
- Cached transcripts for all generated languages and the selected language.
- Cached audio measurements when available, without automatically analyzing
  or recognizing speech again.
- Pause suggestions, Keep/Trim decisions, detection settings, and last visited
  pause. Review next pause can resume that part of the guided review.
- Transcript-page scroll position and original-video playback position.
- A cached export reference if that output file still exists.

Reopening starts in the transcript editor with the restored data. Native preview
playback does not autoplay. Temporary word selection, an unfinished phrase,
currently open tool routes, and in-memory Undo history are not restored.

## Code map

- [project.dart](../../lib/projects/project.dart): version-1 metadata models,
  compact summaries, serialization, and validation. Edit bounds are validated
  with `compilePlan`; transcript text/timing uses the existing parser. Stored
  positions must be finite and in bounds. IDs and media basenames cannot contain
  path traversal. Unsupported future versions are refused rather than silently
  downgraded.
- [project_repository.dart](../../lib/projects/project_repository.dart):
  `ProjectRepository` separates UI from storage. `FileProjectRepository` uses
  asynchronous file I/O, a serialized write queue, and top-level isolate helpers
  for JSON encoding/decoding/validation. Isolate closures capture data only,
  avoiding the repository's unsendable Future queue. Recent projects read small
  summaries rather than every transcript and audio cache.
- [project_autosave.dart](../../lib/projects/project_autosave.dart): coalesces
  rapid changes for 700 ms, captures an immutable snapshot, serializes writes,
  reports progress/failure, and retries the newest state. A later revision cannot
  be overwritten by an earlier in-flight save.
- [editor_screen.dart](../../lib/editor/editor_screen.dart): restores the session,
  owns autosave, and captures successful edit/transcript/analysis/review changes.
  It flushes on Home navigation and requests a best-effort flush on backgrounding.
  Save status rebuilds independently of the whole transcript. Source replacement
  creates a new project and resets its state after the previous save completes.
- [home_screen.dart](../../lib/editor/home_screen.dart): retains the original
  import/hero screen, creates projects, and opens the library through Recent projects.
- [project_library_screen.dart](../../lib/editor/project_library_screen.dart):
  lazy project cards, summary-only search/filter/sort, project resume, rename,
  confirmed deletion, missing-media handling, and visible load warnings. Search
  and filter combine; view preferences stay while opening/returning from a project.
  Rename does not rename the imported media file.
- [transcript_panel.dart](../../lib/transcript/transcript_panel.dart): accepts
  restored language/transcripts and reports completed generations or language
  changes. Canceled/partial inference is not published as a completed transcript.
- [pause_review.dart](../../lib/core/pause_review.dart): saves/restores decisions,
  detector settings, and pause identity. Last-visited changes now notify autosave;
  reviewer initialization publishes them after the frame to avoid notifying an
  underlying overview during widget construction.
- [source_video_player.dart](../../lib/editor/source_video_player.dart): seeks to
  the saved original-source position after initialization and reports progress
  by second. The parent schedules periodic position saves approximately every
  five seconds rather than saving every rendered frame.
- [AppDelegate.swift](../../ios/Runner/AppDelegate.swift): adds `storageRoot` to
  the existing local media channel, returning the app's Application Support
  LocalCut directory. Rendering/import/transcription algorithms are unchanged.

## Storage and recovery

Each project has a private folder under `Application Support/LocalCut/projects`:

```text
<project-id>/
  project.json       # complete editing metadata, schema version 1
  project.json.bak   # previous valid metadata snapshot
  summary.json       # lightweight Recent projects entry
  analysis.json      # optional audio-measurement cache
```

The already imported video stays once in the LocalCut media directory. Project
metadata stores its basename rather than an absolute app-container path. On
load, the current storage root is supplied again, so an iOS container relocation
does not invalidate the source reference. Export references follow the same
rule. No video bytes or speech-model files are serialized into the JSON.

Each metadata write uses a flushed temporary file followed by a rename. The
previous valid snapshot is backed up before replacement; a corrupt primary is
never copied over a valid backup. Load can recover that previous snapshot and
shows a recovery notice. Newer unsupported schemas are not replaced with older
backups. These are local-file safeguards, not a cloud backup or a guarantee
against every device/power failure.

The audio cache is separate and rewritten only when the analysis changes or the
cache is missing. Weak identity references avoid retaining every previously
opened project's audio measurements in the repository. An unreadable/missing
cache is ignored while edits and transcript text remain available for rebuilding
the measurements. A missing export invalidates only the share-ready output,
allowing a new export. A missing source prevents opening and explains the issue;
its saved editing data is retained.

Deleting a project removes its metadata/cache folder and its app-imported video
copy if no other readable project references that copy. If some records cannot
be inspected, media cleanup is conservative. Externally stored originals and
exported videos are not deleted. Existing exports in app storage are also left
alone by project deletion. Unreadable metadata is kept for recovery instead of
being silently discarded.

## Worked example

Import `Episode.mp4`, generate English text, censor 1.0–1.3 seconds, and mark a
pause Keep without adding a cut. Autosave writes that transcript, one mute edit,
and the review decision as lightweight metadata. Return Home and rename the
project to `Episode — first pass`. Close and reopen the app, then tap the card.
The text, mute, selected language, pause decision, and reading/playback positions
are restored; no model download or inference is started just to read the text.
The original imported source is referenced by the same basename throughout.

If storage fails after another edit, the previous saved snapshot is kept. The
editor reports the failure and remains open when Home is requested. Free storage
and Retry save to write the current state. A failed write does not deliberately
replace good saved work with an empty project.

## Verification

`flutter analyze` passed without issues. All **111 tests** passed with
`flutter test`. The iOS Swift sources passed iOS-targeted type checking. Fixture
phone renders of Recent projects and a resumed editor were visually inspected.

Tests cover real temporary-file round trips, two-language transcript caches,
unaligned words, cuts/mutes/labels, decisions/settings/visited pause, positions,
exports, no repeated audio-cache writes, corrupt-primary recovery, corrupt-cache
fallback, lightweight summary listing, unknown schemas, relative paths after
container relocation, shared imports, deletion safety, traversal rejection,
queue recovery, and retrying storage-root failures. A storage test also round-
trips 5,000 words and 90,000 audio windows without copying the source media.
That is a metadata test, not a thirty-minute video decoding benchmark.

Autosave tests exercise coalescing, in-flight revision ordering, failure, and
retry. Widget tests recreate the app with a saved repository and verify no new
transcription/download/analysis, rename/delete confirmation, missing sources,
save failures both in the editor and reviewer, retry, and playback restore input.
Library checks cover the original Home layout, explicit navigation, combined
search/filter behavior, every sort mode, empty states, and enlarged-text layouts.
Earlier media/editing/navigation tests remain in the suite. Widget tests inject
an in-memory repository; native playback and iPhone lifecycle behavior still
need device acceptance.

## Run and manual acceptance

**Fully stop and rebuild the iOS app after this step.** Hot reload cannot install
the new native `storageRoot` hook. No additional package or CocoaPods dependency
was added. The repository itself is Dart; a future Android media adapter needs
its corresponding app-storage-root method alongside existing native media APIs.

On iPhone:

1. Import a disposable short recording and generate its transcript.
2. Add a cut/mute, make guided-review decisions, and adjust detector settings.
3. Watch the original, pause, and wait for Saved on this device.
4. Return Home, rename, close/relaunch the app, and reopen the project.
5. Check restored words, edits, settings, review decisions, and source playhead.
6. Export, reopen again, and check saving/sharing the existing export.
7. Delete a disposable project and confirm its external original/export remain.

This milestone has not been run on an iPhone here. Source type checking and
widget/file tests do not substitute for that acceptance exercise.

## Limits and next steps

Autosave is debounced: very recent pending changes can be lost if the process is
terminated before the write completes. Background flushing is best effort; iOS
may terminate/suspend the app. Normal Home navigation waits for the latest save.
Project files are on this device; uninstalling/resetting app data removes them.

Scroll restore uses pixels and can shift with different fonts/orientations.
Short selection previews do not restore mid-preview playback or open tool routes.
No persistent global Undo/Redo, cloud sync, project relinking, or migration of
pre-project in-memory drafts is added. Older unreferenced import/export files are
not automatically purged. Transcript rendering is still the existing expanded
layout; long-video UI virtualization and actual on-device profiling remain a
separate performance task before claiming reliable 20–30 minute support.
