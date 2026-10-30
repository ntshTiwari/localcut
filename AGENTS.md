# LocalCut project instructions

## Documentation with every step

- Keep `docs/` beside `lib/`. Its entry point is `docs/README.md`.
- Every code-changing commit must add or update the relevant step's README
  in the same commit. Small fixes update the existing step; a new feature or
  milestone gets a numbered folder such as `docs/03-waveform-selection/`.
- Explain what changed, why, how the code works, key files/functions, data flow,
  a worked example, verification, and known limitations. Use plain language.
- Update the docs index for new steps. Link source files using relative paths
  so links work both locally and on GitHub.
- Keep historical examples and behavior labeled with their implementation
  commit when known. Explain subsequent changes instead of silently making
  earlier behavior look current. Do not amend old commits just to add docs.
- Record tests actually run and distinguish user-reported checks from automated
  verification. Never describe an untested path as verified.

## Milestone branches

Start each new milestone on its own branch from the accepted base. Keep work
on the current milestone branch until review/merge; do not merge into `main`
without the user's instruction. Documentation for a milestone belongs on that
milestone's branch.
