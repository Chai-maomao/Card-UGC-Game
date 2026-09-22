class_name BattleLogFormatter
extends RefCounted


static func format_event(event: Dictionary, view_player: int) -> String:
	var kind := str(event.get("kind", ""))
	var player := int(event.get("player", 0))
	var source := str(event.get("source", Locale.t("battle.log.unit")))
	var target := str(event.get("target", Locale.t("battle.log.unit")))
	var intro := ""
	match kind:
		"attack":
			intro = Locale.t("battle.log.action_attack", [_entity(player, source, view_player), _entity(int(event.get("target_player", 3 - player)), target, view_player)])
		"summon_skill":
			intro = Locale.t("battle.log.action_summon_skill", [_entity(player, source, view_player), str(event.get("skill", Locale.t("battle.log.skill_word")))])
		"skill":
			intro = Locale.t("battle.log.action_skill", [_entity(player, source, view_player), str(event.get("skill", Locale.t("battle.log.skill_word")))])
		"cast":
			intro = Locale.t("battle.log.action_cast", [_side(player, view_player), source])
		_:
			return ""

	var outcomes: Array[String] = []
	var details: Array[String] = []
	var damage_groups := _damage_groups(event.get("damage_events", []))
	var primary_key := "%d:%d" % [int(event.get("target_player", -1)), int(event.get("target_slot", -1))]
	if kind == "attack" and damage_groups.has(primary_key):
		var primary: Dictionary = damage_groups[primary_key]
		outcomes.append(_damage_outcome(primary, view_player))
		_append_damage_detail(details, primary, event.get("parasite_events", []))
		damage_groups.erase(primary_key)
		var base_damage := int(event.get("base_damage", 0))
		var effective_damage := int(event.get("effective_damage", base_damage))
		if base_damage != effective_damage:
			details.append(Locale.t("battle.log.attack_modified", [base_damage, effective_damage]))

	for group: Dictionary in damage_groups.values():
		outcomes.append(_damage_outcome(group, view_player))
		_append_damage_detail(details, group, event.get("parasite_events", []))
	for heal: Dictionary in _heal_groups(event.get("hp_events", [])).values():
		outcomes.append(Locale.t("battle.log.outcome_heal", [
			_entity(int(heal["player"]), str(heal["card"]), view_player),
			int(heal["amount"]), int(heal["hp_after"]), int(heal["max_hp"]),
		]))
	for parasite: Dictionary in event.get("parasite_events", []):
		var absorbed := int(parasite.get("actual", 0))
		if absorbed <= 0:
			continue
		var clause := Locale.t("battle.log.parasite_absorb", [str(parasite.get("parasite", Locale.t("battle.log.parasite"))), absorbed])
		if bool(parasite.get("destroyed", false)):
			clause += Locale.t("battle.log.parasite_destroyed")
		details.append(clause)
	_append_state_changes(outcomes, event, view_player)
	var effect_parts: Array[String] = []
	_append_effect_names(effect_parts, event.get("effect_ids", []))
	if outcomes.is_empty():
		outcomes.append_array(effect_parts)
	else:
		details.append_array(effect_parts)
	_append_failed_roll(details if not outcomes.is_empty() else outcomes, event.get("failed_events", []))

	if outcomes.is_empty():
		outcomes.append(Locale.t("battle.log.effect_resolved"))
	var first := Locale.t("battle.log.action_result", [intro, outcomes.pop_front()])
	var parts: Array[String] = [first]
	parts.append_array(outcomes)
	parts.append_array(details)
	return _join(parts)


static func summary(full_text: String) -> String:
	var separator := "; " if Locale.language == "en" else "；"
	return full_text.get_slice(separator, 0).strip_edges()


static func _damage_groups(events: Array) -> Dictionary:
	var groups := {}
	for value in events:
		var event: Dictionary = value
		var key := "%d:%d" % [int(event.get("player", 0)), int(event.get("slot", -1))]
		if not groups.has(key):
			groups[key] = {
				"player": int(event.get("player", 0)), "slot": int(event.get("slot", -1)),
				"target": str(event.get("target", Locale.t("battle.log.unit"))),
				"declared": 0, "actual": 0, "reduction_pct": 0, "shield_absorbed": 0,
				"hp_after": int(event.get("hp_after", -1)), "max_hp": int(event.get("max_hp", -1)),
				"reasons": [],
			}
		var group: Dictionary = groups[key]
		group["declared"] = int(group["declared"]) + int(event.get("declared", 0))
		group["actual"] = int(group["actual"]) + int(event.get("actual", 0))
		group["reduction_pct"] = maxi(int(group["reduction_pct"]), int(event.get("reduction_pct", 0)))
		group["shield_absorbed"] = int(group["shield_absorbed"]) + maxi(0, int(event.get("temp_hp_before", 0)) - int(event.get("temp_hp_after", 0)))
		group["hp_after"] = int(event.get("hp_after", group["hp_after"]))
		group["max_hp"] = int(event.get("max_hp", group["max_hp"]))
		var reason := str(event.get("reason", ""))
		if not reason.is_empty() and not reason in group["reasons"]:
			group["reasons"].append(reason)
	return groups


static func _heal_groups(events: Array) -> Dictionary:
	var groups := {}
	for value in events:
		var event: Dictionary = value
		var delta := int(event.get("delta", 0))
		if delta <= 0:
			continue
		var key := "%d:%d:%s" % [int(event.get("player", 0)), int(event.get("slot", -1)), str(event.get("card", ""))]
		if not groups.has(key):
			groups[key] = {"player": int(event.get("player", 0)), "card": str(event.get("card", Locale.t("battle.log.unit"))), "amount": 0, "hp_after": -1, "max_hp": -1}
		groups[key]["amount"] = int(groups[key]["amount"]) + delta
		groups[key]["hp_after"] = int(event.get("new_hp", groups[key]["hp_after"]))
		groups[key]["max_hp"] = int(event.get("max_hp", groups[key]["max_hp"]))
	return groups


static func _damage_outcome(group: Dictionary, view_player: int) -> String:
	var target := _entity(int(group["player"]), str(group["target"]), view_player)
	var hp_after := int(group.get("hp_after", -1))
	var max_hp := int(group.get("max_hp", -1))
	var hp_state := Locale.t("battle.log.hp_defeated") if hp_after == 0 else Locale.t("battle.log.hp_remaining", [hp_after, max_hp])
	var actual := int(group["actual"])
	if actual > 0:
		return Locale.t("battle.log.outcome_damage", [target, actual, hp_state])
	return Locale.t("battle.log.outcome_no_damage", [target, hp_state])


static func _append_damage_detail(parts: Array[String], group: Dictionary, parasite_events: Array) -> void:
	var declared := int(group["declared"])
	var actual := int(group["actual"])
	var reasons: Array[String] = []
	var reduction := int(group["reduction_pct"])
	var shield := int(group["shield_absorbed"])
	if reduction > 0:
		reasons.append(Locale.t("battle.log.reason_reduction", [reduction]))
	if shield > 0:
		reasons.append(Locale.t("battle.log.reason_shield", [shield]))
	var target_name := str(group["target"])
	for parasite: Dictionary in parasite_events:
		if str(parasite.get("host", "")) == target_name and int(parasite.get("actual", 0)) > 0:
			reasons.append(Locale.t("battle.log.reason_parasite"))
			break
	if declared != actual and reasons.is_empty():
		reasons.append(Locale.t("battle.log.reason_other_protection"))
	if declared != actual or not reasons.is_empty():
		parts.append(Locale.t("battle.log.damage_resolution", [declared, actual, Locale.t("battle.log.reason_join").join(reasons)]))


static func _append_state_changes(parts: Array[String], event: Dictionary, view_player: int) -> void:
	var before: Dictionary = event.get("before_state", {})
	var after: Dictionary = event.get("after_state", {})
	if before.is_empty() or after.is_empty():
		if bool(event.get("kill_mana", false)):
			parts.append(Locale.t("battle.log.kill_mana"))
		return
	for player in [int(event.get("player", 1)), 3 - int(event.get("player", 1))]:
		var prefix := "p%d_" % player
		var hp_delta := int(after.get(prefix + "hp", 0)) - int(before.get(prefix + "hp", 0))
		if hp_delta < 0:
			parts.append(Locale.t("battle.log.body_damage", [_side(player, view_player), -hp_delta, int(after.get(prefix + "hp", 0))]))
		elif hp_delta > 0:
			parts.append(Locale.t("battle.log.body_heal", [_side(player, view_player), hp_delta, int(after.get(prefix + "hp", 0))]))
		var mana_delta := int(after.get(prefix + "mana", 0)) - int(before.get(prefix + "mana", 0))
		if mana_delta != 0:
			parts.append(Locale.t("battle.log.mana_change", [_side(player, view_player), "%+d" % mana_delta, int(after.get(prefix + "mana", 0))]))


static func _append_effect_names(parts: Array[String], effect_ids: Array) -> void:
	var names: Array[String] = []
	for value in effect_ids:
		var effect_id := str(value)
		if effect_id in ["damage", "heal", "lifesteal_damage", "execute"]:
			continue
		var name := Locale.term("effect", effect_id)
		if name == effect_id:
			continue
		if not name in names:
			names.append(name)
	if not names.is_empty():
		parts.append(Locale.t("battle.log.other_effects", [Locale.t("battle.log.item_join").join(names)]))


static func _append_failed_roll(parts: Array[String], failed_events: Array) -> void:
	if failed_events.is_empty():
		return
	var first: Dictionary = failed_events[0]
	var probability := int(first.get("final_probability", 0))
	var misfortune := int(first.get("misfortune", 0))
	var key := "battle.log.probability_failed" if parts.is_empty() else "battle.log.probability_partial"
	if misfortune > 0:
		parts.append(Locale.t(key, [probability, misfortune]))
	else:
		parts.append(Locale.t(key + "_plain", [probability]))


static func _entity(player: int, name: String, view_player: int) -> String:
	return Locale.t("battle.log.entity", [_side(player, view_player), name])


static func _side(player: int, view_player: int) -> String:
	return Locale.t("battle.log.side_friendly") if player == view_player else Locale.t("battle.log.side_enemy")


static func _join(parts: Array[String]) -> String:
	var separator := "; " if Locale.language == "en" else "；"
	var ending := "." if Locale.language == "en" else "。"
	return separator.join(parts) + ending
