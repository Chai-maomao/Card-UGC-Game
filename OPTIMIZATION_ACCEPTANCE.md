# Project improvement acceptance

Scope: current working tree, preserving changes already present on 2026-09-09.

## Required acceptance

- Test infrastructure: separate logic/visual suites; timeout, errors and success markers enforced; renderer probes fail cleanly in headless mode.
- Balance: nested repeat/if/stop, expressions, card type and use limits affect estimates; uncertainty labelled; semantic equivalence tests pass.
- AI: bounded action sequences on isolated state; no live state/RNG mutation or gameplay events; resource-then-play and buff-then-attack tests; diverse paired-side calibration.
- Playtest: bounded trace explains triggers, conditions, targets, values and skips; restore opening and export diagnostics; isolated from simulation.
- Draft simulation: the editor runs cancellable, seeded games across unit, spell and support shared pools; reports candidate use/contribution and match pacing without mutating the draft, library or live game.
- Card revisions: the editor records distinct before/after save states by card identity, retains the newest 10, summarizes changes, and restores an old state to the draft without mutating the saved deck.
- Architecture: extract cohesive reusable responsibilities behind compatibility entry points and regression coverage.
- Content/share: accessible practice challenges with success criteria; author/revision/source metadata and import preview; legacy import preserved; online readiness shows rules/deck agreement.
- Challenge startup: every lesson replaces the shuffled opening state before the first UI refresh; the visible hand matches the lesson after deferred startup work, and an exiting challenge cannot clear a newly selected lesson.
- Challenge flow: objective and selection popups use the same in-game overlay frame as other battle actions, display only the active language, and offer next-lesson and challenge-selection actions after success.
- UI consistency: menus, editors, battle overlays, confirmation dialogs, file pickers, lists and scrollbars share one palette and preserve primary/secondary/danger action hierarchy.
- Final: applicable full regression, rendered probes and reconnect integration pass; visual outputs inspected; diff whitespace checked. Public competitive security and universal statistical balance are outside this scope.

## Evidence

2026-09-21, final working tree (Godot 4.6.3 stable):

- `scripts/run_tests.ps1 -Suite logic` — **44/44 PASS**. This includes deterministic challenge startup, nested-balance equivalence, cancellable seeded draft simulation, bounded revision retention and draft-only restore, bounded two-action AI puzzles, trace isolation, legacy/new share packages, rule validation, 30,542 skill combinations, and 1,000-game default calibration.
- `scripts/run_tests.ps1 -Suite visual` — **4/4 PASS**. The inspected `optimization-*.png` outputs cover the complete playtest toolbar, challenge picker, scenario balance range, batch simulation, card version history, share metadata, and localized match agreement; existing overflow, summon and talent visuals also pass.
- The challenge route now contains seven two-step lessons: resource sequencing, buff timing, Taunt/attacker allocation, Cleanse, Dispel, execute thresholds and Parasite hosting. Every optimal path and a legal unrecoverable mistake per lesson are regression-tested; the picker and an in-battle challenge state have rendered screenshot coverage. Duplicate summon-slot candidates no longer crowd other actions out of bounded AI search.
- Challenge startup now installs the lesson hand and board synchronously before the first visible refresh, skips ordinary opening-draw feedback, and preserves a newly selected lesson when the previous battle exits late. The startup regression checks all seven game-state and visible-UI hands after deferred work has settled.
- Dynamic dialogs now use the same dark navy surfaces, gold titles, blue secondary actions and gold primary actions as the rest of the game. Shared theme assertions cover dialog surfaces, action hierarchy and embedded lists.
- Card Editor batch simulation inserts one isolated draft copy into each of three standard shared pools, yields between games to preserve UI responsiveness, supports cancellation, and labels small-sample results as diagnostic. The rendered report uses the shared popup, scrolling and button styles.
- Card Editor version history uses the same dark/gold popup, panel, scrolling and button styles as the simulation report. Restoring a version refreshes every editor summary and preview while leaving the saved deck unchanged until Update Card is pressed.
- `scripts/run_reconnect_integration.sh` — **PASS** command receipt/ack, room reconnect, snapshot recovery and survivor notification; `scripts/run_lan_reconnect_integration.ps1` — **PASS** LAN discovery, reconnect and process-restart snapshot resume.
- `artifacts/balance-calibration.json` was regenerated from three seeded 40-game pools. It reports zero stability failures and emits `high_draw_rate` / `first_player_skew` warnings when the sample supports them; the unit/support fixtures correctly expose draw-heavy calibration pools, so the report explicitly labels these samples diagnostic rather than universal balance evidence.
- Runner fixes in this wave: `run_tests.ps1` falls back to a quoted `Arguments` string when `ProcessStartInfo.ArgumentList` is absent (Windows PowerShell 5.1 / .NET Framework); visual probes quit(1) with a clear message when the renderer is missing.
- `TestHandOverflowVisual` locates the pile-selection dialog by its `CardCollectionPanel` node instead of assuming it is the last battle child.
- Godot editor import/parse completed without errors; `git diff --check` is clean.
- Online ready flow now uses protocol v6: both players review the same validated rules and submitted deck names, then confirm the canonical offer hash before the authority starts the match.
- CI determinism: `.github/workflows/tests.yml` installs `fonts-noto-cjk` before the test run — card-layout scenes render Chinese skill names, and a runner without any CJK font measures degenerate fallback line metrics (chip rows inflate to a constant ~16px and the column overflows its fixed bounds). With a real CJK font the chips scale like the Windows reference build.
