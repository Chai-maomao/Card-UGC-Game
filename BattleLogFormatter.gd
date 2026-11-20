class_name BattleLogFormatter
extends RefCounted


static func format_event(event: Dictionary, view_player: int) -> String:
	var intro := _action_intro(event, view_player)
	if intro.is_empty():
		return ""
	return intro + ("." if Locale.language == "en" else "。")


static func summary(full_text: String) -> String:
	var separator := "; " if Locale.language == "en" else "；"
	return full_text.get_slice(separator, 0).strip_edges()


static func _action_intro(event: Dictionary, view_player: int) -> String:
	var kind := str(event.get("kind", ""))
	var player := int(event.get("player", 0))
	var source := str(event.get("source", Locale.t("battle.log.unit")))
	var target := str(event.get("target", Locale.t("battle.log.unit")))
	match kind:
		"attack":
			return Locale.t("battle.log.action_attack", [_entity(player, source, view_player), _entity(int(event.get("target_player", 3 - player)), target, view_player)])
		"summon_skill":
			return Locale.t("battle.log.action_summon_skill", [_entity(player, source, view_player), str(event.get("skill", Locale.t("battle.log.skill_word")))])
		"skill":
			return Locale.t("battle.log.action_skill", [_entity(player, source, view_player), str(event.get("skill", Locale.t("battle.log.skill_word")))])
		"cast":
			return Locale.t("battle.log.action_cast", [_side(player, view_player), source])
		"parasite":
			return Locale.t("battle.log.action_parasite", [_side(player, view_player), source, target])
	return ""


static func _entity(player: int, name: String, view_player: int) -> String:
	return Locale.t("battle.log.entity", [_side(player, view_player), name])


static func _side(player: int, view_player: int) -> String:
	return Locale.t("battle.log.side_friendly") if player == view_player else Locale.t("battle.log.side_enemy")
