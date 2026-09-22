# Codex handoff

- Goal: continue improving the Godot card game's player-facing clarity while preserving its unified dark/gold UI.
- Phase/status: production polish; card flow motion, selectable pacing, and state-difference battle reporting completed.
- Latest work: card action reports now compare the battlefield immediately before and after each action. They list only health, maximum health, shield, attack, named status, Parasite attachment and field-presence changes; causal explanations, damage math, probability, draw and resource details are omitted. The centre strip keeps the action plus first change, while its tooltip and the grouped log retain additional changed entities.
- Important files: `BattleLogFormatter.gd`, `BattleMainPresentation.gd`, `BattleMainFoundation.gd`, `Locale.gd`, `BattleFx.gd`, `GameState.gd`, `TestProjectImprovements.gd`.
- Verification: Godot 4.6.3; 44/44 logic scenes and 5/5 visual scenes pass, followed by focused final checks for the copy and rendered feed. Copy tests cover Chinese and English before/after values, no-change actions, status changes, Parasite attachment changes, concise summaries, and the absence of causal wording. `artifacts/optimization-battle-feed.png` was inspected with the state-difference report.
- Current risk: this project still sends ordinary draw overflow to discard, unlike Slay the Spire's stopped-draw behavior; changing that is a separate balance decision.
- Next safest task: playtest custom skills whose names and translated effect lists are unusually long, then decide whether the full log needs expandable detail rows; separately decide whether to adopt separated draw-versus-generated overflow rules.
