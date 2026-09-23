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

## Card flow polish evidence

2026-09-22, Godot 4.6.3 stable:

- Defeated field cards remain face-up for a short break beat, follow a curved shrinking path into the discard pile, and pulse the pile on arrival. Gameplay state still resolves synchronously.
- Draw batches carry presentation-only order metadata, leave the deck as staggered card backs, target the actual post-layout hand slots, and reveal each card face on arrival.
- Local and replayed online feedback use the same timing metadata; animation lifetimes are owned by the battle UI so closing a battle cannot retain card resources.
- Standard card-flow timing is 1.55x the previous duration; Settings > 加速模式 restores the previous timing and skips chained-effect pauses.
- Overlapping discard-pile arrival pulses restart cleanly and restore the pile's stable color and scale.
- Battle feedback: the latest action persists in the centre information bar, while the selectable full log groups entries by turn and type and opens below the enemy lane.
- Player input clarity: battle-parameter booleans use the same sliding switch as accelerated mode; text and numeric inputs retain a soft outline before focus.
- Battle copy now reports only observable before/after changes: leader and card health, maximum health, shield, attack, named statuses, Parasite attachments and field presence. It does not narrate damage calculations, mitigation causes, probability rolls, effect names, draw activity or resource changes.
- The centre information bar keeps the action and first state change in one concise clause. The grouped battle log and strip tooltip retain any additional changed entities; an action with no health or status change says so directly.
- Multi-stage action feedback follows the emitted causal order across HP changes, draw travel and status/stat pulses. An attack for 2 against a 4/4 unit whose damaged trigger heals 3, followed by a 1-damage attack skill, presents `-2 -> +2 -> -1 -> +1`; each transition waits 0.2 seconds. Consecutive targets of one area effect share a stage unless a nested reaction interrupts the effect. Single-stage actions gain no input delay, accelerated mode removes waits without reordering, and online peers replay the same timeline.
- The “三口一个巧乐兹” acceptance fixture presents self-damage, one-card draw travel and enemy Misfortune application as three distinct groups in that order. Drawn hand cards stay hidden until their queued travel stage begins; non-HP effects use the existing unified blue skill pulse.
- After discarding the first, middle or last card, the remaining hand keeps its relative order and reuses the same card controls. If a discard lifecycle or authority update supplies a different legal order, the UI mirrors that array exactly rather than appending moved controls out of sequence.
- Repeated skill pulses, and a damage/heal flash interrupting a skill pulse, always restore the card's original tint, position and scale. No pale-blue overlay remains after the feedback tween finishes.
- `scripts/run_tests.ps1 -Suite logic` — **44/44 PASS**.
- `scripts/run_tests.ps1 -Suite visual` — **5/5 PASS**, including `TestCardFlowAnimationVisual` screenshots for defeat-to-discard and ordered drawing.
