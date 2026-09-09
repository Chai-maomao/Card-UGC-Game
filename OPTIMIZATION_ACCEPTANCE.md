# Project improvement acceptance

Scope: current working tree, preserving changes already present on 2026-09-09.

## Required acceptance

- Test infrastructure: separate logic/visual suites; timeout, errors and success markers enforced; renderer probes fail cleanly in headless mode.
- Balance: nested repeat/if/stop, expressions, card type and use limits affect estimates; uncertainty labelled; semantic equivalence tests pass.
- AI: bounded action sequences on isolated state; no live state/RNG mutation or gameplay events; resource-then-play and buff-then-attack tests; diverse paired-side calibration.
- Playtest: bounded trace explains triggers, conditions, targets, values and skips; restore opening and export diagnostics; isolated from simulation.
- Architecture: extract cohesive reusable responsibilities behind compatibility entry points and regression coverage.
- Content/share: accessible practice challenges with success criteria; author/revision/source metadata and import preview; legacy import preserved; online readiness shows rules/deck agreement.
- Final: applicable full regression, rendered probes and reconnect integration pass; visual outputs inspected; diff whitespace checked. Public competitive security and universal statistical balance are outside this scope.

## Evidence

2026-09-09, current working tree:

- `scripts/run_tests.ps1 -Suite logic` — **41/41 PASS** (per-scene logs under `.godot/test-logs/logic/`), twice in a row; one earlier suite run reported 3 failures (MainArchitecture line budget, playtest trigger routes, tutorial flow) that did not reproduce standalone or in either later full run — presumed stale `.godot` compile cache from mid-edit sources.
- `scripts/run_tests.ps1 -Suite visual` — **4/4 PASS**; screenshots written to `res://artifacts/optimization-*.png` and `user://hand_*_visual.png`, luminance/variance sampling confirms non-blank rendered content; `artifacts/balance-calibration.json` produced (3 pools × 40 seeded games).
- `scripts/run_reconnect_integration.sh` (Godot 4.6.3 linux, WSL Ubuntu 26.04, same invocation as CI) — **PASS** command receipt/ack, reconnect transport, snapshot recovery, survivor notification.
- Runner fixes in this wave: `run_tests.ps1` falls back to a quoted `Arguments` string when `ProcessStartInfo.ArgumentList` is absent (Windows PowerShell 5.1 / .NET Framework); visual probes quit(1) with a clear message when the renderer is missing.
- `TestHandOverflowVisual` locates the pile-selection dialog by its `CardCollectionPanel` node instead of assuming it is the last battle child.
- Whitespace: `git diff --check` clean; line endings normalized via `core.autocrlf`.
- CI determinism: `.github/workflows/tests.yml` installs `fonts-noto-cjk` before the test run — card-layout scenes render Chinese skill names, and a runner without any CJK font measures degenerate fallback line metrics (chip rows inflate to a constant ~16px and the column overflows its fixed bounds). With a real CJK font the chips scale like the Windows reference build.
