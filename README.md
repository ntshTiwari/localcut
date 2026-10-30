# LocalCut — offline iPhone prototype

Flutter UI and shared edit planning, with a Swift AVFoundation media adapter.
No app backend, network requests, account, or transcription service.

## First milestone implemented

- Import a local video using the iOS Files picker (copy into app storage).
- Watch the original and enter source-time cut or mute ranges in seconds.
- Remove proposed edits and preview the resulting native composition.
- Explicitly approve export to a new MP4; original media is unchanged.
- Cancel export and share/save the result through the iOS share sheet.
- Preserve orientation and use one composition builder for preview/export.

The prototype currently uses manual timestamps. Automatic silence detection,
waveform selection, project reopening, numeric export progress, Photos import,
and Android media processing are subsequent milestones.

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

## Architecture

- `lib/core/edit_plan.dart`: platform-independent source-time ranges and plan
  compiler. Cuts take precedence; adjacent equal-state segments are merged.
- `lib/media/media_engine.dart`: backend-neutral interface and one version-one
  platform channel adapter (`localcut/media`). Small, explicit message schema.
- `lib/main.dart`: import → mark → review → approve → export UI.
- `ios/Runner/AppDelegate.swift`: iOS import, source inspection, composition,
  native player, export, and share adapter. Kept in a registered Runner source
  file for the initial proof; extract into a plugin as the engine grows.
- `android/`: Flutter-generated scaffold only. Implement the same media
  interface in Kotlin/Media3 later. The shared edit compiler is already reusable.

The bridge transmits only file references and edit metadata, never video frames.
All range timestamps are integer milliseconds on the original video timeline.
Native composition converts them to CMTime and assembles retained segments.
No FFmpeg or AI model is needed for this milestone.

## Checks

Run `flutter analyze` and `flutter test`.
Tests cover overlapping cuts/mutes, range validation, merged segments, retained
length, and the initial screen. Native playback and encoding must additionally
be checked on an iPhone; Dart tests do not validate media output.

## Validation in this workspace

Flutter analysis passes and all four Dart/widget tests pass. Swift is checked
against the installed iOS SDK separately. Full app builds currently fail in
asset compilation because Xcode cannot access an available simulator runtime
in this execution session. The user has confirmed the expected edit workflow works in their test.
Broader device, format, and long-recording validation is still pending.

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
