# Step 6 — A familiar creator workspace

Implemented on `milestone/creator-design`, based on accepted commit `3b270d6`.
This step replaces the single crowded editor page with focused screens and
YouTube-inspired red actions, neutral surfaces, and system light/dark themes.
LocalCut retains its own name and editing workflow.

## What the user does

1. Import a recording from Home.
2. Watch the original above the transcript, using play/pause, scrubbing, volume,
   and full-screen playback. This player shows the original; proposed changes
   are heard through Review → Play edited video.
3. Open Create transcript. Choose English, Hindi, or Hindi–English in a bottom
   sheet. Download only the required model, or use the existing offline model.
   Generation progress and cancellation stay inside this sheet. It closes when
   the transcript succeeds; errors remain available for retry.
4. Tap a word or confirmed pause. The selection actions remain in a bottom tray.
   Fine-tune timing opens a separate sheet for the waveform, silence settings,
   and exact numeric ranges. The source video and transcript scroll together.
5. Review changes on a separate screen, restore individual changes if needed,
   play the edited composition, then explicitly export. The completion screen
   offers Save or share and Back to review.
6. Leaving/replacing a video with pending edits requires a discard confirmation.
   Projects are not persisted yet; export your result before leaving.

## Code map

- [main.dart](../../lib/main.dart): small composition root; injects media/speech
  engines and applies the shared themes.
- [app_theme.dart](../../lib/design/app_theme.dart): color, typography, button,
  sheet, and input styles; shared LocalCut wordmark.
- [home_screen.dart](../../lib/editor/home_screen.dart): local import, busy/error
  states, and navigation into a new editing session.
- [editor_screen.dart](../../lib/editor/editor_screen.dart): owns source-time
  edits, cached audio analysis, selection actions, and invalidated export path.
  The editor coordinates all child tools; replacing a video resets transcript
  state as well as edits and analysis.
- [source_video_player.dart](../../lib/editor/source_video_player.dart): official
  Flutter `video_player` file controller. No autoplay. Pauses on application
  inactivity, disposes on replacement/exit, and shares one controller with its
  full-screen view. An unavailable inline player offers native original playback.
- [playback_media_engine.dart](../../lib/editor/playback_media_engine.dart):
  pauses the inline player before native context/edited playback or export,
  preventing two audio sources from playing together.
- [transcript_panel.dart](../../lib/transcript/transcript_panel.dart): retains
  the model/transcript algorithms from step 5, moves setup into a modal sheet,
  and refreshes the separate modal route through a notifier. A busy sheet cannot
  close mid-operation; cancellation remains explicit.
- [timing_screen.dart](../../lib/editor/timing_screen.dart) (originally `fine_tune_sheet.dart`): reuses
  `SilenceReview` and the editor's audio cache; validates all manual changes
  through `compilePlan` before accepting them.
- [review_screen.dart](../../lib/editor/review_screen.dart): source/edited
  duration, edit list, native preview, export busy/cancel states, and sharing.
  A canceled export cannot publish a late successful response. Restoring an edit
  invalidates the cached exported path.
- [media_engine.dart](../../lib/media/media_engine.dart) and
  [AppDelegate.swift](../../ios/Runner/AppDelegate.swift): add optional original
  filename metadata to the import response for the editor title.

## Data flow and example

Import returns a copied file path, duration, audio presence, and filename. Home
pushes an Editor which owns one edit list. Transcript and timing tools add
`EditRange` values against the original recording. No source media is modified.
Review receives that list and compiles the same plan used by native preview and
export. The screens change how editing is presented, not the cut/mute algorithm.

For a 5-second video, censoring 0–1 seconds and removing 1.15–2.65 seconds
produces retained segments 0–1 (muted), 1–1.15 (audible), and 2.65–5 (audible).
Review displays an edited duration of 3.5 seconds. Export creates a new MP4 only
after the user presses Export video. Restoring the cut returns the full length
while preserving the word censor, and a new export is required.

The speech download/model checks, confirmed silence boundaries, approximate word
timestamps, and per-range restore rules remain documented in
[step 4](../04-transcript-models/README.md) and
[step 5](../05-transcript-pause-editor/README.md).

## Native dependency setup

`video_player` is pinned through `pubspec.lock`; its iOS implementation uses
AVFoundation and supports local file playback. CocoaPods integration and lockfile
are included, targeting iOS 16 consistently with the app. Run `flutter pub get`
and perform a full iOS rebuild after this step; hot reload cannot register the
new native plugin. Use `ios/Runner.xcworkspace` when opening Xcode.

The Flutter UI/player dependency supports Android, but LocalCut's import,
analysis, rendering, and transcription channel implementations still require
an Android milestone. Adding a player does not complete Android support.

References: [official video_player package](https://pub.dev/packages/video_player)
and [Flutter video playback guide](https://docs.flutter.dev/cookbook/plugins/play-video).

## Verification and limits

Checks run for this step: `flutter analyze` passed without issues; all 54 tests
passed with `flutter test`. `pod install --no-repo-update` succeeded and the
native Swift sources passed iOS-targeted type checking. CocoaPods prints its
custom-configuration warning for Profile; the checked-in Flutter Release config
includes the Pods release configuration, which currently matches Profile.
Run `flutter analyze` and `flutter test` to repeat the Dart checks. The regression suite covers the prior
edit plans, silence/waveform behavior, language downloads, transcript selections,
and the new screen flow. New tests exercise pending-edit discard confirmation,
pausing before native playback/export, cancellation with late export completion,
and landscape navigation in both themes at enlarged text size. Narrow phone
selection controls remain covered by the existing flow tests.

Widget tests use fake media/speech engines. They verify navigation and edit
instructions, not actual codec playback or on-device performance. Widget-rendered
screenshots are design checks with fixture transcripts, not iPhone captures.
The iOS configuration build was attempted here but Xcode package discovery was
blocked by the execution sandbox's SwiftPM diagnostic/cache permissions. A full
iPhone build, inline plugin playback, and real video export need device testing.

Manual acceptance:

- Launch in light and dark system appearance; import a short real MP4.
- Play, scrub, mute, full-screen, background/resume; check that context playback
  and edited playback do not overlap the inline original audio.
- Generate a transcript; cancel/retry a download or analysis if applicable.
- Shorten a confirmed pause, censor a word, open/close timing tools, then review.
- Export, save/share, return to review and restore a change; confirm a fresh
  export is required. Leave/replace and verify discard confirmation.
- Check portrait, landscape, and larger accessibility text.

No project library, persistent drafts, thumbnails, numeric export percentage,
Photos import, or retake detection is introduced by this milestone.

Later UI changes: [step 8](../08-editor-navigation/README.md) replaces the timing sheet
with a page and moves transcript decisions to a dedicated selection screen.
