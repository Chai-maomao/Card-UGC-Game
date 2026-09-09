# Skill engine combination audit

Date: 2026-09-04
Engine used for acceptance: Godot 4.6.3 stable

## Automated coverage

`TestSkillCombinationMatrix.tscn` is the repeatable acceptance test for the
editor/formatter/runtime contract. The current run covers 27,576 cases,
including:

- every registered effect and its runtime handler;
- every trigger crossed with every effect/target/side configuration, plus a
  runtime probe for each registered trigger;
- all legal target shapes and side filters;
- Chinese and English text rendering;
- fixed, global-variable, target-variable and expression-driven values;
- every legacy condition type and comparison operator;
- every arithmetic operator, deterministic division and bounded random values;
- nested if/repeat targeting, legacy condition reporters and repeat expressions;
- target resolution for single, adjacent, self, self-adjacent, all and gender filters;
- random target limits, random X-cost reduction and first-turn spell scope;
- semantic rejection for target reporters without a live target, impossible
  trigger/target pairs, missing buffs and mixed ally/enemy directed targets;
- legacy `all_enemies` / `all_allies` normalization and every built-in starter
  card passing the semantic validator.

The existing targeted suites remain part of acceptance: `TestSkillRegistry`,
`TestSkillTargeting`, `TestSkillConditionEffects`, `TestSkillRichFields`,
`TestSkillTargetBlocks`, `TestSpellCast`, `TestUgcSafety`, editor undo/redo and
the complete root `Test*.tscn` suite.

## Corrected mismatches

1. Target-stat values are now evaluated once for each actual affected unit.
   Multi-target effects no longer reuse the source card's HP%, attack or cost.
2. Target-independent ranges and random expressions still roll once per effect,
   preserving existing card and replay behavior.
3. Nested legacy conditions now use their nested fields in both execution and
   preview. Repeat expressions are rendered instead of falling back to `2`.
4. Directed target previews now state enemy/ally explicitly. HP reporters state
   that they are percentages.
5. Target selection and first-turn enemy-spell detection recurse through control
   blocks. Hand/deck/resource effects never request a battlefield target and do
   not falsely make a spell enemy-targeting.
6. The first-turn restriction is scoped to enemy-targeting spells, as designed;
   ordinary unit skills are no longer silently skipped by the engine.
7. Non-negative effects clamp negative expression results to zero. Damage,
   healing and count effects cannot reverse meaning; max HP cannot fall below 1.
8. Random zero-cost selection displays and applies `random_count` consistently.
   Random-count controls/badges are hidden for effects that do not consume them.
9. The editor blocks configurations the runtime cannot interpret unambiguously:
   target-stat reporters without a per-unit target, directed targets on triggers
   with no target context, missing status selection, and mixed ally/enemy manual
   directed targets.
10. The default spell draft now starts with an explicit enemy side instead of
    generating the editor's invalid `single + all sides` combination.

## Deliberate compatibility contracts

- A positive heal action still fires `on_healed` even when the unit is already
  at full HP. The emitted HP delta now reflects actual healing.
- Legacy `all_enemies` and `all_allies` data remains accepted and normalizes to
  the two-dimensional target/side representation.
- Fixed, range, random and source/global values are shared across an AoE;
  only target-stat reporters are recalculated per target.

## Remaining design limits

- A skill has one manual target selection. Multiple directed effects may share
  that selected slot only when they use the same side; mixed enemy/ally directed
  effects are rejected.
- Control-block conditions and repeat counts have no per-unit iteration target.
  Therefore target-stat reporters are rejected there; put the condition on the
  concrete effect if it must be evaluated per target.
- Exhaustive testing is bounded by the UGC nesting, expression-depth, repeat and
  execution budgets. The matrix enumerates the complete registered surface and
  representative nested trees rather than every mathematically possible tree.

## Reproduction

```powershell
& 'D:\XunLeiXiaZai\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe' --headless --path . --scene res://TestSkillCombinationMatrix.tscn
& .\scripts\run_tests.ps1
```
