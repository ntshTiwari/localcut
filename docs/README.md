# LocalCut code walkthroughs

These guides explain the implementation step by step. Start here when returning
to the project, then follow the source links in the relevant guide. `docs/` sits
beside `lib/`; explanations are versioned with the code in Git.

## Reading order

1. [Cut, mute, preview, and export](01-cut-mute-export/README.md) — the original
   offline workflow, edit instructions, timeline compilation, and iOS rendering.
   Introduced in commit `118be0c`.
2. [Automatic silence suggestions](02-silence-detection/README.md) — local audio
   decoding, RMS measurements, pause detection, settings, and review controls.
   Introduced in commit `f880c34` on `milestone/silence-detection`.
3. [Waveform selection](03-waveform-selection/README.md) — source-time audio
   display, drag/resize selection, zoom/navigation, and cut/mute preview/addition.
   Added on `milestone/waveform-selection`, based on `de5c2a7`.

4. [Downloadable transcript models](04-transcript-models/README.md) — English,
   Hindi, and mixed-speech selection, verified downloads, offline recognition,
   word timings, and explicit transcript muting.
   Added on `milestone/transcript-language-models`, based on `b490f03`.

5. [Words and pauses in one editor](05-transcript-pause-editor/README.md) —
   confirmed pause markers, tap selection, sticky actions, scoped restore,
   and one review/export screen. Added on `milestone/transcript-pause-editor`,
   based on `6c21745`.

6. [Creator workspace and theme](06-creator-design/README.md) — Home, inline local
   playback, transcript/timing sheets, review/export screens, and system themes.
   Added on `milestone/creator-design`, based on `3b270d6`.

The first two guides were added in a documentation follow-up after their
implementation commits. Later guides are included with their implementations.
Existing commits have not been rewritten. Later changes should update
the guide for the affected behavior in the same commit as the code.

## Documentation convention

- Each new feature or milestone gets a numbered directory with a `README.md`.
- Small fixes update the existing feature guide, including any changed examples
  and limitations. They do not need a duplicate document.
- Every code-changing commit includes the relevant documentation change.
- Explain the purpose, user flow, key files/functions, logic, inputs/outputs,
  an example, tests, and current limitations.
- State verification accurately: passing a unit test does not prove on-device
  decoding or export works. Label user-reported device checks separately.
- Update this reading list when adding a new step.

To revisit an exact implementation, run these from the project folder:

```bash
git log --oneline -- docs lib ios/Runner/AppDelegate.swift
git show 118be0c:lib/core/edit_plan.dart
git show f880c34:lib/core/silence_detection.dart
```

For a future code-and-docs commit, `git show <commit>:docs/<step>/README.md`
opens the explanation saved at that revision. The two initial commits predate
the docs folders; use these follow-up guides to read about them.

## Template for the next step

Use these sections in the next `docs/NN-feature/README.md`:

1. Purpose and implementation reference.
2. What the user does.
3. Code map with links to the relevant functions.
4. Data flow and the algorithm in plain language.
5. A worked example with concrete input and output.
6. Why the design was chosen and platform boundaries.
7. How to verify it, including commands and manual checks.
8. Limitations and changes made after the initial implementation.

Project-wide instructions are in [AGENTS.md](../AGENTS.md).
