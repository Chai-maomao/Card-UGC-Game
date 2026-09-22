# Codex handoff

- Goal: continue improving the Godot card game's player-facing clarity while preserving its unified dark/gold UI.
- Phase/status: production polish; card draw and defeat-to-discard motion completed.
- Latest work: ordered draw batches now fly from deck to exact hand slots and reveal on arrival; defeated cards visibly travel to the discard pile; Slay the Spire hand-overflow behavior is documented without changing this project's existing overflow rule.
- Important files: `BattleFx.gd`, `BattleMainPresentation.gd`, `BattleMainFoundation.gd`, `GameState.gd`, `TestCardFlowAnimationVisual.gd`, `docs/HAND_FLOW_REFERENCE.md`.
- Verification: Godot 4.6.3; 44/44 logic scenes and 5/5 visual scenes pass; `artifacts/card-draw-flow.png` and `artifacts/card-death-discard-flow.png` inspected.
- Current risk: this project still sends ordinary draw overflow to discard, unlike Slay the Spire's stopped-draw behavior; changing that is a separate balance decision.
- Next safest task: playtest animation speed at normal battle pace, then decide whether to adopt the separated draw-versus-generated overflow rules.
