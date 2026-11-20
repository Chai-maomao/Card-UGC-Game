class_name AiDecisionTrace
extends RefCounted

const VERSION := 1
const BOOKKEEPING := ["has_acted", "has_attacked", "skills_used", "skills_used_count", "summoned_this_turn"]


# Replay recorded commands, never choose new ones. All speculative events and
# preference synchronization remain disabled, including on rejected records.
static func build(record: Dictionary) -> Dictionary:
	var blocked := EventBus.is_blocking_signals()
	EventBus.set_block_signals(true)
	var result := _build(record)
	EventBus.set_block_signals(blocked)
	return result


static func _build(record: Dictionary) -> Dictionary:
	var verified := BattlePosition.read(BattleRepro.export_json(record))
	if not verified.ok:
		return verified
	var game := preload("res://GameState.gd").new()
	game.quiet = true
	game.apply_initial_state(record.initial_state.duplicate(true), false)
	game.draw_callable = game.draw_cards
	var metrics := BattleMetrics.new()
	var events: Array = []
	game.metrics_callable = func(event: Dictionary):
		metrics.record(event)
		var safe := {}
		for key in ["kind", "source", "source_player", "target_player", "hero", "amount", "action", "points", "mana", "temporary_mana"]:
			if event.has(key): safe[key] = event[key]
		events.append(safe)
	var current_manifest := BattlePosition.source_manifest()
	var report := {"version": VERSION, "kind": "cardex_ai_decisions", "metadata": record.get("metadata", {}).duplicate(true), "recorded_source_sha256": record.get("source_sha256", {}).duplicate(true), "current_source_sha256": current_manifest, "diagnostic_sha256": FileAccess.get_sha256("res://AiDecisionTrace.gd"), "rows": [], "summary": {"recorded_steps": record.actions.size(), "decisions": 0, "player_turns": 0, "activations_without_observed_payload": 0, "metrics_version": BattleMetrics.VERSION}, "initial_hash": record.state_hashes[0], "final_hash": record.state_hashes[-1]}
	var step := 0
	var previous_turn := ""
	while step < record.actions.size():
		var action: Dictionary = record.actions[step]
		if str(action.type) in ["settle", "cleanup"]:
			var result := _apply_step(game, record, step)
			if not result.ok: return result
			step += 1
			continue
		var first_step := step
		var before := _view(game)
		var actor := int(game.current_player)
		var source := _source(game, action)
		var event_start := events.size()
		var metric_before := metrics.snapshot()
		var planning_hash := BattleRepro.state_hash(game)
		var candidates: Array = []
		for legal in BattleAiPlanner.generate_legal_actions(game):
			var assessment := BattleAiPlanner.score_action(game, legal)
			candidates.append({"action": legal, "score": assessment.score, "factors": assessment.factors})
		candidates.sort_custom(func(a, b): return float(a.score) > float(b.score))
		var reassessment := BattleAiPlanner.score_action(game, action) if str(action.type) in ["attack", "activate", "cast", "attach", "summon", "end_turn"] else {}
		if BattleRepro.state_hash(game) != planning_hash or events.size() != event_start:
			return {"ok": false, "reason": "assessment_mutated_state", "step": step + 1}
		var result := _apply_step(game, record, step)
		if not result.ok: return result
		step += 1
		# Death resolution belongs to its preceding command, not another decision.
		while step < record.actions.size() and str(record.actions[step].type) in ["settle", "cleanup"]:
			result = _apply_step(game, record, step)
			if not result.ok: return result
			step += 1
		var after := _view(game)
		var row_events := events.slice(event_start)
		var metric_delta := _metric_delta(metric_before, metrics.snapshot())
		var payload_changed: bool = before.payload_hash != after.payload_hash
		var observed_resource := false
		for event in row_events:
			if str(event.get("kind", "")) in ["mana_gained", "mana_refunded", "mana_removed", "mana_drained"] and int(event.get("amount", 0)) > 0:
				observed_resource = true
		for player in ["1", "2"]:
			var paid := 0
			for event in row_events:
				if event.get("kind") == "payment" and str(event.get("source_player", 0)) == player: paid += int(event.get("mana", 0))
			if int(after.resources[player].mana) + int(after.resources[player].temporary_mana) + paid != int(before.resources[player].mana) + int(before.resources[player].temporary_mana):
				observed_resource = true
		var no_payload := str(action.type) == "activate" and not payload_changed and not observed_resource
		var row := {"index": report.rows.size() + 1, "step_start": first_step + 1, "step_end": step, "turn": before.turn, "player": actor, "source": source, "action": action.duplicate(true), "recorded_score": action.get("score"), "recorded_factors": action.get("explanation", []), "current_assessment": reassessment, "alternatives": candidates.slice(0, 5), "before": before, "after": after, "events": row_events, "metrics_delta": metric_delta, "payload_changed": payload_changed, "activation_without_observed_payload": no_payload, "hash": BattleRepro.state_hash(game)}
		report.rows.append(row)
		if no_payload: report.summary.activations_without_observed_payload += 1
		var turn_key := "%d:%d" % [before.turn, actor]
		if turn_key != previous_turn:
			report.summary.player_turns += 1
			previous_turn = turn_key
	report.summary.decisions = report.rows.size()
	report["metrics"] = metrics.snapshot()
	report["winner"] = game.check_game_over()
	if BattleRepro.state_hash(game) != report.final_hash:
		return {"ok": false, "reason": "trace_final_hash"}
	return {"ok": true, "report": report}


static func _apply_step(game: RefCounted, record: Dictionary, step: int) -> Dictionary:
	var action: Dictionary = record.actions[step]
	if action.has("rng_state_before_action"):
		game.game_rng.state = action.rng_state_before_action
	var result := BattleRepro.apply_action(game, action)
	if not result.ok: return {"ok": false, "reason": "trace_action", "step": step + 1}
	if BattleRepro.state_hash(game) != record.state_hashes[step + 1]:
		return {"ok": false, "reason": "trace_hash", "step": step + 1}
	return {"ok": true}


static func _source(game: RefCounted, action: Dictionary) -> Dictionary:
	var source: CardData
	if action.has("hand_index"):
		var hand: Array = game.active_hand()
		var index := int(action.hand_index)
		if index >= 0 and index < hand.size(): source = hand[index]
	else:
		var slot := int(action.get("source_slot", action.get("slot", -1)))
		if slot >= 0 and slot < game.active_field().slots.size(): source = game.active_field().slots[slot]
	return {"name": source.card_name, "card_id": source.card_id, "instance_id": source.instance_id} if source != null else {}


static func _view(game: RefCounted) -> Dictionary:
	var state: Dictionary = game.export_initial_state()
	var payload := {}
	var resources := {}
	for player in [1, 2]:
		var field: BattleField = game.player_field if player == 1 else game.player2_field
		resources[str(player)] = {"mana": field.current_mana, "temporary_mana": field.temp_mana, "ap": field.action_points, "actions_taken": field.actions_taken}
		var field_key := "player_field" if player == 1 else "player2_field"
		payload[str(player)] = {"hero_hp": field.player_hp, "slots": _payload_cards(state[field_key].slots), "hand": _payload_cards(state["player_hand" if player == 1 else "player2_hand"])}
	payload["deck"] = _payload_cards(state.shared_deck)
	payload["discard"] = _payload_cards(state.shared_discard)
	return {"turn": game.turn_number, "current_player": game.current_player, "resources": resources, "position": BattlePosition.describe(game), "payload_hash": BattleRepro.hash_state(payload), "board": {"1": payload["1"].slots, "2": payload["2"].slots}}


static func _payload_cards(cards: Array) -> Array:
	var result: Array = []
	for value in cards:
		if not value is Dictionary or value.is_empty():
			result.append({})
			continue
		var card: Dictionary = value.duplicate(true)
		for key in BOOKKEEPING: card.erase(key)
		if card.get("parasite_cards") is Array:
			card.parasite_cards = _payload_cards(card.parasite_cards)
		result.append(card)
	return result


static func _metric_delta(before: Dictionary, after: Dictionary) -> Dictionary:
	var result := {}
	for identity in after.by_identity:
		var row := {}
		var old: Dictionary = before.by_identity.get(identity, {})
		for key in BattleMetrics.KEYS:
			var amount := int(after.by_identity[identity][key]) - int(old.get(key, 0))
			if amount != 0: row[key] = amount
		if not row.is_empty(): result[identity] = row
	return result
