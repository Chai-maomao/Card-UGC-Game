class_name BattlePosition
extends RefCounted

const MAX_FILE_BYTES := 16 * 1024 * 1024
const MAX_RECORDED_ACTIONS := 5000
const SOURCE_FILES := ["GameState.gd", "BattleField.gd", "BattleAiPlanner.gd", "BattleSearch.gd", "BattleRepro.gd", "SkillEngine.gd", "SkillEffectApplier.gd", "SkillTargetResolver.gd", "SkillRegistry.gd", "CardData.gd", "PlayerData.gd", "ParasiteRules.gd", "SpellRules.gd", "GameplayRng.gd", "DataSchema.gd"]


static func capture(game: RefCounted, metadata: Dictionary = {}) -> Dictionary:
	var copy: RefCounted = game.copy_for_simulation()
	ensure_ids(copy)
	var record := BattleRepro.begin(copy)
	record["kind"] = "cardex_position"
	record["position_version"] = 1
	record["metadata"] = metadata.duplicate(true)
	record["position"] = describe(copy)
	record["source_sha256"] = source_manifest()
	return record


static func ensure_ids(game: RefCounted) -> void:
	for property in ["player_hand", "player2_hand", "shared_deck", "shared_discard"]:
		var cards: Array = game.get(property)
		for index in range(cards.size()):
			if cards[index] != null: _ensure_card_ids(cards[index], "%s-%d" % [property, index])
	for player in [1, 2]:
		var field: BattleField = game.player_field if player == 1 else game.player2_field
		for index in range(field.slots.size()):
			if field.slots[index] != null: _ensure_card_ids(field.slots[index], "p%d-slot-%d" % [player, index])


static func _ensure_card_ids(card: CardData, location: String) -> void:
	if card.card_id.is_empty():
		var definition := [card.card_name, card.base_cost, card.base_max_hp, card.base_atk, card.skills, card.card_type, card.gender, card.parasite_damage_mode]
		card.card_id = "position-card-" + BattleRepro.canonical_text(definition).sha256_text().left(16)
	if card.instance_id.is_empty():
		card.instance_id = "position-" + location
	for index in range(card.parasite_cards.size()):
		_ensure_card_ids(card.parasite_cards[index], location + "-parasite-%d" % index)


static func describe(game: RefCounted) -> Dictionary:
	var result := {"turn": game.turn_number, "current_player": game.current_player, "players": {}}
	for player in [1, 2]:
		var field: BattleField = game.player_field if player == 1 else game.player2_field
		var hand: Array = game.player_hand if player == 1 else game.player2_hand
		var row := {"units": 0, "unit_hp": 0, "attack": 0, "hero_hp": field.player_hp, "hand": hand.size(), "mana": field.get_total_mana(), "action_points": field.action_points, "actions_taken": field.actions_taken}
		for card in field.slots:
			if card != null and card.is_alive():
				row.units += 1
				row.unit_hp += card.hp + card.temp_hp
				row.attack += card.effective_atk()
		result.players[str(player)] = row
	return result


static func source_manifest() -> Dictionary:
	var manifest := {}
	for file in SOURCE_FILES:
		manifest[file] = FileAccess.get_sha256("res://" + file)
	return manifest


static func read(source: String) -> Dictionary:
	if source.to_utf8_buffer().size() > MAX_FILE_BYTES:
		return {"ok": false, "reason": "file_too_large"}
	var imported := BattleRepro.import_json(source)
	if not imported.ok:
		return imported
	var record: Dictionary = imported.record
	if not record.get("actions", null) is Array or record.actions.size() > MAX_RECORDED_ACTIONS:
		return {"ok": false, "reason": "action_limit"}
	var verified := BattleRepro.verify(record)
	if not verified.ok:
		return verified
	return {"ok": true, "record": record, "game": verified.game}


static func save(record: Dictionary, path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(BattleRepro.export_json(record))
	return file.get_error()


static func continue_record(record: Dictionary, difficulty: String = "hard", max_player_turns: int = 100) -> Dictionary:
	var loaded := read(BattleRepro.export_json(record))
	if not loaded.ok:
		return loaded
	var game: RefCounted = loaded.game
	var continuation: Dictionary = loaded.record.duplicate(true)
	var turns := 0
	var stable := true
	var failure := {}
	var winner: String = game.check_game_over()
	var previously_blocked := EventBus.is_blocking_signals()
	EventBus.set_block_signals(true)
	while winner.is_empty() and turns < maxi(1, max_player_turns):
		var ended := false
		for index in range(BattleRepro.MAX_ACTIONS_PER_TURN):
			if continuation.actions.size() + 2 > MAX_RECORDED_ACTIONS:
				stable = false
				failure = {"reason": "record_limit"}
				break
			var action := BattleAiPlanner.choose_action(game, difficulty, game.game_rng)
			var applied := BattleRepro.execute_and_record(game, continuation, action)
			if not applied.ok:
				stable = false
				failure = applied
				break
			BattleRepro.execute_and_record(game, continuation, {"type": "settle"})
			winner = game.check_game_over()
			ended = action.type == "end_turn"
			if ended or not winner.is_empty(): break
		turns += 1
		if not stable or (not ended and winner.is_empty()):
			stable = false
			if failure.is_empty(): failure = {"reason": "action_cap"}
			break
	EventBus.set_block_signals(previously_blocked)
	return {"ok": true, "record": continuation, "stable": stable, "failure": failure, "winner": winner, "capped": winner.is_empty() and stable, "turns": turns, "final_hash": BattleRepro.state_hash(game)}
