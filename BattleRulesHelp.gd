class_name BattleRulesHelp
extends RefCounted


static func description(game: RefCounted) -> String:
	var config: Dictionary = game.battle_config
	var mana := int(config.get("mana_per_turn", PlayerData.DEFAULT_BATTLE_CONFIG["mana_per_turn"]))
	var draw := int(config.get("draw_per_turn", 2))
	var lines: Array[String] = [
		Locale.t("help.resources", [mana, draw, maxi(1, mana / 2) + int(config.get("second_extra_mana", 0)), maxi(1, draw / 2) + int(config.get("second_extra_cards", 0)), SkillEngine.MAX_HAND_SIZE]),
	]
	if config.has("mana_increment"):
		lines[0] = Locale.t("help.resources_growing", [mana, int(config.mana_increment), draw,
			maxi(1, mana / 2) + int(config.get("second_extra_mana", 0)),
			maxi(1, draw / 2) + int(config.get("second_extra_cards", 0)), SkillEngine.MAX_HAND_SIZE])
	if config.has("action_base"):
		lines.append(Locale.t("help.actions", [str(config.get("action_base", 3)), str(config.get("action_empty_slot_factor", 1.0)), str(config.get("action_empty_hand_factor", 0.5)), str(config.get("action_mana_factor", 1.0))]))
	else:
		lines.append(Locale.t("help.actions_legacy"))
	lines.append(Locale.t("help.skills"))
	lines.append(Locale.t("help.combat", [Locale.t("help.first_turn_attacks_allowed" if game.allow_first_turn_attacks else "help.first_turn")]))
	if config.get("face_damage_compensation", false):
		var compensation_mana := int(config.get("face_damage_compensation_mana", PlayerData.DEFAULT_FACE_DAMAGE_COMPENSATION_MANA))
		lines.append(Locale.t("battle_config.face_damage_compensation") + "\n"
			+ Locale.t("battle_config.face_damage_compensation_help") + "\n"
			+ Locale.t("help.face_damage_compensation_rate", [compensation_mana]))
	return "\n\n".join(lines)


static func room_summary(config: Dictionary) -> String:
	var hp := int(config.get("starting_hp", 30))
	var mana := int(config.get("mana_per_turn", PlayerData.DEFAULT_BATTLE_CONFIG["mana_per_turn"]))
	var draw := int(config.get("draw_per_turn", 2))
	if config.has("mana_increment"):
		return Locale.t("battle_config.summary_growing", [hp, mana, int(config.mana_increment), draw])
	return Locale.t("battle_config.summary_fixed", [hp, mana, draw])
