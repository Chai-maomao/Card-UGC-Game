class_name BattleRepro
extends RefCounted

const SCHEMA_VERSION := 1
const GameStateScript = preload("res://GameState.gd")


static func state_hash(game: RefCounted) -> String:
	return hash_state(game.export_initial_state())


static func hash_state(state: Dictionary) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(_canonical(state).to_utf8_buffer())
	return context.finish().hex_encode()


static func canonical_text(value: Variant) -> String:
	return _canonical(value)


static func begin(game: RefCounted) -> Dictionary:
	var initial: Dictionary = game.export_initial_state()
	return {
		"version": SCHEMA_VERSION,
		"schema": SCHEMA_VERSION,
		"godot_version": str(Engine.get_version_info().get("string", "unknown")),
		"seed": int(initial.get("rng_seed", 0)),
		"initial_state": initial,
		"actions": [],
		"state_hashes": [hash_state(initial)],
	}


static func export_json(record: Dictionary) -> String:
	return JSON.stringify(_encode_for_json(record), "\t")


static func import_json(source: String) -> Dictionary:
	var parsed = JSON.parse_string(source)
	if not (parsed is Dictionary):
		return {"ok": false, "reason": "invalid_json"}
	var decoded = _decode_from_json(parsed)
	if not (decoded is Dictionary):
		return {"ok": false, "reason": "invalid_record"}
	var record: Dictionary = decoded
	var initial = record.get("initial_state", null)
	if not (initial is Dictionary):
		return {"ok": false, "reason": "invalid_record"}
	return {"ok": true, "record": record}


static func _encode_for_json(value: Variant) -> Variant:
	if value is int and (value > 9007199254740991 or value < -9007199254740991):
		return "i64:" + str(value)
	if value is Dictionary:
		var result := {}
		for key in value.keys():
			result[key] = _encode_for_json(value[key])
		return result
	if value is Array:
		var result: Array = []
		for child in value:
			result.append(_encode_for_json(child))
		return result
	return value


static func _decode_from_json(value: Variant) -> Variant:
	if value is String and value.begins_with("i64:"):
		return int(value.trim_prefix("i64:"))
	if value is Dictionary:
		var result := {}
		for key in value.keys():
			result[key] = _decode_from_json(value[key])
		return result
	if value is Array:
		var result: Array = []
		for child in value:
			result.append(_decode_from_json(child))
		return result
	return value


static func _clone_variant(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key in value.keys():
			result[key] = _clone_variant(value[key])
		return result
	if value is Array:
		var result: Array = []
		for child in value:
			result.append(_clone_variant(child))
		return result
	return value


static func execute_and_record(game: RefCounted, record: Dictionary, action: Dictionary) -> Dictionary:
	var result := apply_action(game, action)
	if not bool(result.get("ok", false)):
		return result
	record["actions"].append(action.duplicate(true))
	record["state_hashes"].append(state_hash(game))
	return result


static func verify(record: Dictionary) -> Dictionary:
	if int(record.get("schema", 0)) != SCHEMA_VERSION:
		return {"ok": false, "reason": "unsupported_schema"}
	var initial = record.get("initial_state", null)
	var actions = record.get("actions", null)
	var expected_hashes = record.get("state_hashes", null)
	if not (initial is Dictionary) or not (actions is Array) or not (expected_hashes is Array):
		return {"ok": false, "reason": "invalid_record"}
	if expected_hashes.size() != actions.size() + 1:
		return {"ok": false, "reason": "hash_count"}
	var game := GameStateScript.new()
	game.apply_initial_state(_clone_variant(initial))
	var restored_state: Dictionary = game.export_initial_state()
	var actual := hash_state(restored_state)
	if actual != str(expected_hashes[0]):
		var changed_keys: Array[String] = []
		for key in initial.keys():
			if _canonical(initial[key]) != _canonical(restored_state.get(key)):
				changed_keys.append(str(key))
		return {"ok": false, "reason": "initial_hash", "step": 0, "expected": expected_hashes[0], "actual": actual, "changed_keys": changed_keys, "input_keys": initial.keys(), "restored_keys": restored_state.keys()}
	for index in range(actions.size()):
		var result := apply_action(game, actions[index])
		if not bool(result.get("ok", false)):
			return {"ok": false, "reason": "action_failed", "step": index + 1, "detail": result}
		actual = state_hash(game)
		if actual != str(expected_hashes[index + 1]):
			return {"ok": false, "reason": "hash_mismatch", "step": index + 1, "expected": expected_hashes[index + 1], "actual": actual}
	return {"ok": true, "steps": actions.size(), "final_hash": actual, "game": game}


static func apply_action(game: RefCounted, action: Dictionary) -> Dictionary:
	var action_type := str(action.get("type", ""))
	var ok := false
	match action_type:
		"summon":
			var hand_index := int(action.get("hand_index", -1))
			var hand: Array = game.active_hand()
			ok = hand_index >= 0 and hand_index < hand.size() and game.summon_card(hand[hand_index], int(action.get("slot", -1)))
		"discard":
			var hand_index := int(action.get("hand_index", -1))
			var hand: Array = game.active_hand()
			ok = hand_index >= 0 and hand_index < hand.size() and game.discard_card(hand[hand_index])
		"cast":
			ok = game.cast_spell(int(action.get("hand_index", -1)), int(action.get("skill_index", 0)), int(action.get("target_slot", -1)), int(action.get("target_player", 0)))
		"attach":
			ok = game.attach_parasite(int(action.get("hand_index", -1)), int(action.get("target_player", 0)), int(action.get("target_slot", -1)))
		"attack":
			ok = not game.execute_attack(int(action.get("source_slot", -1)), int(action.get("target_slot", -1))).is_empty()
		"activate":
			var source_slot := int(action.get("slot", -1))
			var skill_index := int(action.get("skill_index", 0))
			var source: CardData = game.active_field().slots[source_slot] if source_slot >= 0 and source_slot < game.active_field().slots.size() else null
			if source != null and not source.has_acted and skill_index >= 0 and skill_index < source.skills.size():
				var trigger := str(source.skills[skill_index].get("trigger", ""))
				if trigger == SkillEngine.TRIGGER_ON_ACTIVATE:
					game.trigger_activate_skills(source_slot, int(action.get("target_slot", -1)), skill_index, int(action.get("target_player", 0)))
					ok = true
		"end_turn":
			game.end_player_turn()
			game.start_new_turn()
			ok = true
		"cleanup":
			game.cleanup_deaths()
			ok = true
		"draw":
			game.draw_cards_for_player(int(action.get("amount", 1)), int(action.get("player", game.current_player)))
			ok = true
		_:
			return {"ok": false, "reason": "unknown_action", "type": action_type}
	if not ok:
		return {"ok": false, "reason": "illegal_action", "type": action_type}
	game.state_revision += 1
	return {"ok": true, "type": action_type, "revision": game.state_revision}


static func _canonical(value: Variant) -> String:
	if value == null:
		return "null"
	if value is bool:
		return "true" if value else "false"
	if value is int:
		return str(value)
	if value is float:
		# Godot's JSON parser represents numeric literals as floats. Treat exact
		# integral floats as integers so an export/import round trip cannot alter
		# a gameplay hash solely because 2 became 2.0.
		if value == floor(value) and value >= -9223372036854775808.0 and value <= 9223372036854775807.0:
			return str(int(value))
		return JSON.stringify(value)
	if value is String or value is StringName:
		return JSON.stringify(str(value))
	if value is Array:
		var entries: Array[String] = []
		for child in value:
			entries.append(_canonical(child))
		return "[" + ",".join(entries) + "]"
	if value is Dictionary:
		var entries: Array[String] = []
		var pairs: Array = []
		for key in value.keys():
			pairs.append({"text": str(key), "value": value[key]})
		pairs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["text"] < b["text"])
		for pair in pairs:
			entries.append(JSON.stringify(pair["text"]) + ":" + _canonical(pair["value"]))
		return "{" + ",".join(entries) + "}"
	return JSON.stringify(str(value))
