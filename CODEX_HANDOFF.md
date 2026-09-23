# Codex handoff

- Goal: continue improving the Godot card game's player-facing clarity while preserving its unified dark/gold UI.
- Phase/status: production polish; card flow motion, selectable pacing, and state-difference battle reporting completed.
- Latest work: card action reports compare the battlefield immediately before and after each action and omit causal explanations. Multi-stage HP feedback now follows real effect boundaries: a direct attack result plays first, later triggered effects wait 0.2 seconds, and every target of the same area effect plays together. Single-stage actions remain immediate and accelerated mode skips the gaps.
- Important files: `BattleLogFormatter.gd`, `BattleMainPresentation.gd`, `BattleMainFoundation.gd`, `SkillEngine.gd`, `EventBus.gd`, `Locale.gd`, `TestBattleLayout.gd`.
- Verification: Godot 4.6.3; 44/44 logic scenes and 5/5 visual scenes pass. A real attack-plus-target-and-neighbors skill test verifies direct `-2` feedback appears immediately, three `-1` results stay hidden through 0.1 seconds, and the area stage appears after the 0.2-second gap. Tutorial, replay, skill, Parasite and network safety regressions pass.
- Current risk: this project still sends ordinary draw overflow to discard, unlike Slay the Spire's stopped-draw behavior; changing that is a separate balance decision.
- Next safest task: playtest custom skills whose names and translated effect lists are unusually long, then decide whether the full log needs expandable detail rows; separately decide whether to adopt separated draw-versus-generated overflow rules.
