class_name BattleLogFormatter
extends RefCounted


static func format_event(event: Dictionary, view_player: int) -> String:
	var intro := _action_intro(event, view_player)
	if intro.is_empty():
		return ""
	var changes := _state_changes(event, view_player)
	if changes.is_empty():
		changes.append(Locale.t("battle.log.no_state_change"))
	var first := Locale.t("battle.log.action_result", [intro, changes.pop_front()])
	var parts: Array[String] = [first]
	parts.append_array(changes)
	return _join(parts)


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


static func _state_changes(event: Dictionary, view_player: int) -> Array[String]:
	var before: Dictionary = event.get("before_state", {})
	var after: Dictionary = event.get("after_state", {})
	if before.is_empty() or after.is_empty():
		return []
	var changes: Array[String] = []
	var before_cards: Dictionary = before.get("cards", {})
	var after_cards: Dictionary = after.get("cards", {})
	var card_keys: Array = before_cards.keys()
	for key in after_cards.keys():
		if not key in card_keys:
			card_keys.append(key)
	card_keys.sort()
	var primary_key := "%d:%d" % [int(event.get("target_player", -1)), int(event.get("target_slot", -1))]
	if not primary_key in card_keys and not str(event.get("target", "")).is_empty():
		for key in card_keys:
			var candidate: Dictionary = after_cards.get(key, before_cards.get(key, {}))
			if str(candidate.get("name", "")) == str(event.get("target", "")):
				primary_key = str(key)
				break
	if primary_key in card_keys:
		card_keys.erase(primary_key)
		card_keys.push_front(primary_key)
	for key in card_keys:
		_append_card_change(changes, before_cards.get(key, {}), after_cards.get(key, {}), view_player)
	for player in [int(event.get("player", 1)), 3 - int(event.get("player", 1))]:
		var hp_key := "p%d_hp" % player
		if not before.has(hp_key) or not after.has(hp_key):
			continue
		var old_hp := int(before[hp_key])
		var new_hp := int(after[hp_key])
		if old_hp != new_hp:
			changes.append(Locale.t("battle.log.change_leader_hp", [_side(player, view_player), old_hp, new_hp]))
	return changes


static func _append_card_change(parts: Array[String], before: Dictionary, after: Dictionary, view_player: int) -> void:
	if before.is_empty() and after.is_empty():
		return
	if before.is_empty():
		parts.append(Locale.t("battle.log.change_entered", [_entity(int(after.get("player", 0)), str(after.get("name", Locale.t("battle.log.unit"))), view_player)]))
		return
	if after.is_empty():
		parts.append(Locale.t("battle.log.change_left", [_entity(int(before.get("player", 0)), str(before.get("name", Locale.t("battle.log.unit"))), view_player)]))
		return
	if str(before.get("instance_id", "")) != str(after.get("instance_id", "")) or str(before.get("name", "")) != str(after.get("name", "")):
		parts.append(Locale.t("battle.log.change_left", [_entity(int(before.get("player", 0)), str(before.get("name", Locale.t("battle.log.unit"))), view_player)]))
		parts.append(Locale.t("battle.log.change_entered", [_entity(int(after.get("player", 0)), str(after.get("name", Locale.t("battle.log.unit"))), view_player)]))
		return
	var values: Array[String] = []
	var old_hp := int(before.get("hp", 0))
	var new_hp := int(after.get("hp", 0))
	var old_max_hp := int(before.get("max_hp", 0))
	var new_max_hp := int(after.get("max_hp", 0))
	if old_hp != new_hp or old_max_hp != new_max_hp:
		values.append(Locale.t("battle.log.change_hp", [old_hp, old_max_hp, new_hp, new_max_hp]))
	var old_shield := int(before.get("shield", 0))
	var new_shield := int(after.get("shield", 0))
	if old_shield != new_shield:
		values.append(Locale.t("battle.log.change_shield", [old_shield, new_shield]))
	var old_attack := int(before.get("attack", 0))
	var new_attack := int(after.get("attack", 0))
	if old_attack != new_attack:
		values.append(Locale.t("battle.log.change_attack", [old_attack, new_attack]))
	var old_statuses := _status_summary(before)
	var new_statuses := _status_summary(after)
	if old_statuses != new_statuses:
		values.append(Locale.t("battle.log.change_status", [old_statuses, new_statuses]))
	var old_parasites := _parasite_summary(before.get("parasites", []))
	var new_parasites := _parasite_summary(after.get("parasites", []))
	if old_parasites != new_parasites:
		values.append(Locale.t("battle.log.change_parasites", [old_parasites, new_parasites]))
	if not values.is_empty():
		parts.append(Locale.t("battle.log.change_card", [
			_entity(int(after.get("player", 0)), str(after.get("name", Locale.t("battle.log.unit"))), view_player),
			Locale.t("battle.log.change_join").join(values),
		]))


static func _status_summary(card: Dictionary) -> String:
	var labels: Array[String] = []
	for value in card.get("statuses", []):
		var status: Dictionary = value
		var buff_id := str(status.get("buff_id", ""))
		if buff_id.is_empty():
			continue
		var name := Locale.term("buff", buff_id)
		var duration := int(status.get("duration", 0))
		if SkillRegistry.buff_uses_value(buff_id):
			if int(status.get("value", 0)) <= 0:
				continue
			labels.append(Locale.t("battle.log.status_value", [name, int(status.get("value", 0)), duration]))
		else:
			labels.append(Locale.t("battle.log.status_presence", [name, duration]))
	if bool(card.get("immune_lethal", false)) and not _contains_status(card.get("statuses", []), SkillRegistry.BUFF_IMMUNE_LETHAL):
		labels.append(Locale.term("buff", SkillRegistry.BUFF_IMMUNE_LETHAL))
	labels.sort()
	return Locale.t("battle.log.state_none") if labels.is_empty() else Locale.t("battle.log.item_join").join(labels)


static func _contains_status(statuses: Array, buff_id: String) -> bool:
	for value in statuses:
		if value is Dictionary and str(value.get("buff_id", "")) == buff_id:
			return true
	return false


static func _parasite_summary(values: Array) -> String:
	var labels: Array[String] = []
	for value in values:
		var parasite: Dictionary = value
		labels.append(Locale.t("battle.log.parasite_state", [str(parasite.get("name", Locale.t("battle.log.parasite"))), int(parasite.get("hp", 0)), int(parasite.get("max_hp", 0))]))
	labels.sort()
	return Locale.t("battle.log.state_none") if labels.is_empty() else Locale.t("battle.log.item_join").join(labels)


static func _entity(player: int, name: String, view_player: int) -> String:
	return Locale.t("battle.log.entity", [_side(player, view_player), name])


static func _side(player: int, view_player: int) -> String:
	return Locale.t("battle.log.side_friendly") if player == view_player else Locale.t("battle.log.side_enemy")


static func _join(parts: Array[String]) -> String:
	var separator := "; " if Locale.language == "en" else "；"
	var ending := "." if Locale.language == "en" else "。"
	return separator.join(parts) + ending
