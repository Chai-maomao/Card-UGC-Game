extends "res://BattleMainFoundation.gd"

# Records resolved effects for local presentation and network replay.

func _on_skill_effect_started(_source: CardData, effect_id: String, _chain_depth: int) -> void:
	if _action_broadcast.is_empty():
		return
	_action_feedback_next_group += 1
	_action_feedback_group_stack.append(_action_feedback_next_group)
	_action_presentation_events.append({
		"kind": "stage",
		"effect_id": effect_id,
		"feedback_group": _action_feedback_next_group,
	})


func _on_skill_effect_resolved(source: CardData, effect_id: String, targets: Variant, _chain_depth: int) -> void:
	if _action_broadcast.is_empty():
		if not _random_unbatched_events.is_empty():
			_random_unbatched_events.append({"kind":"effect","effect_id":effect_id,"targets":_presentation_target_locations(targets),"feedback_group":0})
			_random_unbatched_events.append({"kind":"random_board","board":_capture_random_board(),"feedback_group":0})
		return
	var group := int(_action_feedback_group_stack.back()) if not _action_feedback_group_stack.is_empty() else 0
	# HP changes and hand movement already provide their own readable feedback.
	# Effects with no such event still get a target pulse in their exact slot in
	# the causal timeline (buffs, shields, attack changes, cleanse, and so on).
	if not _presentation_group_has_visible_event(group):
		var locations := _presentation_target_locations(targets)
		if locations.is_empty() and source != null:
			var source_loc := _locate_card_player_slot(source)
			if int(source_loc.get("slot", -1)) >= 0:
				locations.append(source_loc)
		_action_presentation_events.append({
			"kind": "effect",
			"effect_id": effect_id,
			"targets": locations,
			"feedback_group": group,
		})
	if _action_feedback_group_stack.size() > 1:
		_action_feedback_group_stack.pop_back()
	if _action_presentation_events.any(func(event): return str(event.get("kind",""))=="random"):
		_action_presentation_events.append({"kind":"random_board","board":_capture_random_board(),"feedback_group":group})


func _capture_random_board() -> Dictionary:
	var snapshot := {"resources":{}}
	for player in [1,2]:
		var field = game.player_field if player==1 else game.player2_field
		var cards: Array = []
		for card in field.slots:
			cards.append(PlayerData.serialize_card(card) if card != null else {})
		snapshot[str(player)] = cards
		snapshot.resources[str(player)] = {"hp":field.player_hp,"mana":field.get_total_mana(),"points":field.action_points}
	return snapshot


func _on_skill_random_resolved(source: CardData,outcome: Dictionary) -> void:
	if game==null or int(outcome.get("player",0)) not in [1,2]: return
	var event := outcome.duplicate(true)
	event["kind"] = "random"
	event["source"] = source.card_name if source != null else ""
	event["source_slot"] = int(_locate_card_player_slot(source).get("slot",-1))
	event["board"] = _capture_random_board()
	event["feedback_group"] = int(_action_feedback_group_stack.back()) if not _action_feedback_group_stack.is_empty() else 0
	if not _action_broadcast.is_empty():
		_action_presentation_events.append(event)
	else:
		var first := _random_unbatched_events.is_empty()
		if first:
			_random_unbatched_before = _random_last_shown_board.duplicate(true) if not _random_last_shown_board.is_empty() else event.board.duplicate(true)
			for hp_event in _unbatched_hp_feedback: _pending_hp_events.erase(hp_event)
			_random_unbatched_events.append_array(_unbatched_hp_feedback)
			_unbatched_hp_feedback.clear()
		_random_unbatched_events.append(event)
		if first:
			if PlayerData.is_online_battle() and NetworkManager.is_authority():
				_pending_feedback_events.append({"kind":"presentation","events":_random_unbatched_events})
			_flush_random_unbatched.call_deferred()


func _flush_random_unbatched() -> void:
	var events := _order_random_feedback(_random_unbatched_events,_random_unbatched_before)
	# The outbound packet shares this Array until a commit copies it.
	_random_unbatched_events.assign(events)
	_random_unbatched_events = []
	_random_unbatched_before.clear()
	_queue_presentation_feedback(events)


func _on_random_attack_declared(attacker: CardData,_victim: CardData,source_slot: int,target_slot: int) -> void:
	if game==null or source_slot not in range(5) or game.active_field().slots[source_slot]!=attacker: return
	_random_attack_motion = {"kind":"attack_motion","player":game.current_player,"source_slot":source_slot,"target_slot":target_slot,"feedback_group":0}
	if _action_broadcast.is_empty(): _clear_plain_attack_motion.call_deferred()

func _clear_plain_attack_motion() -> void:
	if _random_unbatched_events.is_empty(): _random_attack_motion.clear()


func _order_random_feedback(events: Array,before: Dictionary) -> Array:
	var ordered := events.duplicate(true)
	var roll_index := ordered.find_custom(func(event): return event.get("kind") == "random")
	if roll_index >= 0:
		if not before.is_empty(): ordered[roll_index]["board_before"] = before.duplicate(true)
		if not _random_attack_motion.is_empty() and not ordered.any(func(event): return event.get("kind") == "attack_motion"):
			ordered.push_front(_random_attack_motion.duplicate(true))
	_random_attack_motion.clear()
	return ordered


func _presentation_group_has_visible_event(group: int) -> bool:
	for index in range(_action_presentation_events.size() - 1, -1, -1):
		var event: Dictionary = _action_presentation_events[index]
		if int(event.get("feedback_group", -1)) != group:
			continue
		if str(event.get("kind", "")) == "stage":
			return false
		return true
	return false


func _presentation_target_locations(targets: Variant) -> Array:
	var values: Array = targets if targets is Array else [targets]
	var locations: Array = []
	for value in values:
		if not value is CardData:
			continue
		var loc := _locate_card_player_slot(value)
		if int(loc.get("slot", -1)) >= 0 and not loc in locations:
			locations.append(loc)
	return locations


func _on_hp_changed(target: CardData, delta: int, new_hp: int):
	var target_key := target.get_instance_id() if target != null else 0
	var zero_damage := delta == 0 and _pending_zero_damage_targets.has(target_key)
	_pending_zero_damage_targets.erase(target_key)
	if delta == 0 and not zero_damage:
		return
	# Authority records the change (as player+slot) so it can be replayed as
	# floating text on the non-authority client, which never runs combat logic
	# and therefore never emits hp_changed itself.
	var loc := _locate_card_player_slot(target)
	var feedback_group: int = int(_action_feedback_group_stack.back()) if not _action_feedback_group_stack.is_empty() else 0
	var feedback_origin_group := 0 if str(_action_broadcast.get("kind", "")) == "attack" else 1
	var feedback_event := {
		"player": loc.player, "slot": loc.slot, "delta": delta, "card": target.card_name,
		"before_hp": new_hp - delta, "new_hp": new_hp, "max_hp": target.max_hp,
		"zero_damage": zero_damage,
		"kind": "hp",
		"feedback_group": feedback_group, "feedback_origin_group": feedback_origin_group,
	}
	if loc.slot >= 0 and not _action_broadcast.is_empty():
		_action_hp_events.append(feedback_event)
		_action_presentation_events.append(feedback_event.duplicate(true))
	if PlayerData.is_online_battle() and NetworkManager.is_authority() and loc.slot>=0 and _action_broadcast.is_empty() and _random_unbatched_events.is_empty():
		_pending_hp_events.append(feedback_event.duplicate(true))
	if loc.slot < 0:
		return
	if _action_broadcast.is_empty():
		if not _random_unbatched_events.is_empty():
			_random_unbatched_events.append(feedback_event)
		else:
			var first := _unbatched_hp_feedback.is_empty()
			_unbatched_hp_feedback.append(feedback_event)
			if first: _flush_plain_hp_feedback.call_deferred()


func _flush_plain_hp_feedback() -> void:
	var events := _unbatched_hp_feedback.duplicate(true)
	_unbatched_hp_feedback.clear()
	for event in events:
		_show_combat_feedback_for(int(event.player),int(event.slot),int(event.delta),bool(event.get("zero_damage",false)))


