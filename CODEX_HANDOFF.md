# Codex handoff

- Goal: continue improving the Godot card game's player-facing clarity while preserving its unified dark/gold UI.
- Phase/status: production polish; card draw and defeat-to-discard motion completed, with player-selectable pacing.
- Latest work: battle broadcasts now persist in the centre information bar instead of covering enemy cards; the selectable action log groups events by turn/type, tracks unread events, and opens below the enemy lane. Battle-parameter booleans now use visible sliding switches, and player inputs use a shared soft outline.
- Important files: `BattleFx.gd`, `BattleMainPresentation.gd`, `BattleMainFoundation.gd`, `GameState.gd`, `TestCardFlowAnimationVisual.gd`, `docs/HAND_FLOW_REFERENCE.md`.
- Verification: Godot 4.6.3; 44/44 logic scenes and 5/5 visual scenes pass. Responsive tests verify the feed and opened log never overlap the enemy lane; input tests verify sliding switches and persistent outlines. `artifacts/optimization-battle-feed.png` and `artifacts/optimization-battle-config.png` were inspected.
- Current risk: this project still sends ordinary draw overflow to discard, unlike Slay the Spire's stopped-draw behavior; changing that is a separate balance decision.
- Next safest task: playtest the persistent latest-action strip with long user-authored card names, then decide whether to adopt the separated draw-versus-generated overflow rules.
