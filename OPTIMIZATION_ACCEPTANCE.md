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

2026-09-13, final working tree (Godot 4.6.3 stable):

- `scripts/run_tests.ps1 -Suite logic` — **41/41 PASS**. This includes nested-balance equivalence, bounded two-action AI puzzles, trace isolation, legacy/new share packages, rule validation, 30,542 skill combinations, and 1,000-game default calibration.
- `scripts/run_tests.ps1 -Suite visual` — **4/4 PASS**. The inspected `optimization-*.png` outputs cover the complete playtest toolbar, challenge picker, scenario balance range, share metadata, and localized match agreement; existing overflow, summon and talent visuals also pass.
- The challenge route now contains seven two-step lessons: resource sequencing, buff timing, Taunt/attacker allocation, Cleanse, Dispel, execute thresholds and Parasite hosting. Every optimal path and a legal unrecoverable mistake per lesson are regression-tested; the picker and an in-battle challenge state have rendered screenshot coverage. Duplicate summon-slot candidates no longer crowd other actions out of bounded AI search.
- `scripts/run_reconnect_integration.sh` — **PASS** command receipt/ack, room reconnect, snapshot recovery and survivor notification; `scripts/run_lan_reconnect_integration.ps1` — **PASS** LAN discovery, reconnect and process-restart snapshot resume.
- `artifacts/balance-calibration.json` was regenerated from three seeded 40-game pools. It reports zero stability failures and emits `high_draw_rate` / `first_player_skew` warnings when the sample supports them; the unit/support fixtures correctly expose draw-heavy calibration pools, so the report explicitly labels these samples diagnostic rather than universal balance evidence.
- Runner fixes in this wave: `run_tests.ps1` falls back to a quoted `Arguments` string when `ProcessStartInfo.ArgumentList` is absent (Windows PowerShell 5.1 / .NET Framework); visual probes quit(1) with a clear message when the renderer is missing.
- `TestHandOverflowVisual` locates the pile-selection dialog by its `CardCollectionPanel` node instead of assuming it is the last battle child.
- Godot editor import/parse completed without errors; `git diff --check` is clean.
- Online ready flow now uses protocol v6: both players review the same validated rules and submitted deck names, then confirm the canonical offer hash before the authority starts the match.
- CI determinism: `.github/workflows/tests.yml` installs `fonts-noto-cjk` before the test run — card-layout scenes render Chinese skill names, and a runner without any CJK font measures degenerate fallback line metrics (chip rows inflate to a constant ~16px and the column overflows its fixed bounds). With a real CJK font the chips scale like the Windows reference build.
