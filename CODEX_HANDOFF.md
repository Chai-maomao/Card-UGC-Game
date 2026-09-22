# Codex handoff

- Goal: continue improving the Godot card game's player-facing clarity while preserving its unified dark/gold UI.
- Phase/status: production polish; card flow motion, selectable pacing, and structured battle reporting completed.
- Latest work: battle reports now use a stable actor/action/target/result sentence followed by exact resolution details. They expose remaining health, mitigation and shield absorption, Parasite interception, healing, leader health, mana, attack changes, resolved utility effects, and final failure probability when relevant. The centre strip shows the concise primary clause, while its tooltip and the grouped log retain the full report.
- Important files: `BattleLogFormatter.gd`, `BattleMainPresentation.gd`, `BattleMainFoundation.gd`, `Locale.gd`, `BattleFx.gd`, `GameState.gd`, `TestProjectImprovements.gd`.
- Verification: Godot 4.6.3; 44/44 logic scenes and 5/5 visual scenes pass. Copy tests cover Chinese and English ordering, numeric resolution details, concise summaries, and utility-only skills. Responsive tests verify the feed and opened log never overlap the enemy lane. `artifacts/optimization-battle-feed.png` was inspected with the new structured report.
- Current risk: this project still sends ordinary draw overflow to discard, unlike Slay the Spire's stopped-draw behavior; changing that is a separate balance decision.
- Next safest task: playtest custom skills whose names and translated effect lists are unusually long, then decide whether the full log needs expandable detail rows; separately decide whether to adopt separated draw-versus-generated overflow rules.
