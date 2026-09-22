# Codex handoff

- Goal: continue improving the Godot card game's player-facing clarity while preserving its unified dark/gold UI.
- Phase/status: production polish; card draw and defeat-to-discard motion completed, with player-selectable pacing.
- Latest work: standard card-flow timing is 1.55x longer for readability; the settings-page accelerated mode preserves the previous timing and still skips chained-effect pauses. Overlapping discard-pile pulses restart from a stable rest style so red/orange tint cannot remain stuck.
- Important files: `BattleFx.gd`, `BattleMainPresentation.gd`, `BattleMainFoundation.gd`, `GameState.gd`, `TestCardFlowAnimationVisual.gd`, `docs/HAND_FLOW_REFERENCE.md`.
- Verification: Godot 4.6.3; 44/44 logic scenes and 5/5 visual scenes pass. The visual suite checks overlapping pile-pulse restoration and exact normal/accelerated draw timing; `artifacts/card-draw-flow.png` and `artifacts/card-death-discard-flow.png` were inspected.
- Current risk: this project still sends ordinary draw overflow to discard, unlike Slay the Spire's stopped-draw behavior; changing that is a separate balance decision.
- Next safest task: playtest both speed modes at normal battle pace, then decide whether to adopt the separated draw-versus-generated overflow rules.
