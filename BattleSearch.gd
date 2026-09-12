class_name BattleSearch
extends RefCounted

const Game = preload("res://GameState.gd")
const WIDTH := 4
const MAX_NODES := 24


static func choose(game: RefCounted, ranked: Array) -> Dictionary:
	var initial: Dictionary = game.export_initial_state()
	var player: int = game.current_player
	var base := _value(game, player)
	var nodes := 0
	var best: Dictionary = ranked[0].duplicate(true)
	var best_score := -INF
	# Synchronous scope: speculative events must never reach UI, statistics,
	# playtest traces or network listeners. No await is allowed in this scope.
	var previously_blocked := EventBus.is_blocking_signals()
	EventBus.set_block_signals(true)
	for candidate in _diverse_actions(ranked, WIDTH):
		if str(candidate.get("type", "")) == "end_turn":
			continue
		if not _supported(game, candidate): continue
		var simulated := _clone(initial)
		nodes += 1
		if not BattleRepro.apply_action(simulated, candidate).get("ok", false):
			continue
		simulated.cleanup_deaths()
		var outcome := _value(simulated, player) - base
		var followups: Array = []
		for action in BattleAiPlanner.generate_legal_actions(simulated):
			if str(action.get("type", "")) == "end_turn":
				continue
			var row: Dictionary = action.duplicate(true)
			row["score"] = BattleAiPlanner.score_action(simulated, action)["score"]
			followups.append(row)
		followups.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.score) > float(b.score))
		var next_state: Dictionary = simulated.export_initial_state()
		for action in _diverse_actions(followups, WIDTH):
			if not _supported(simulated, action): continue
			if nodes >= MAX_NODES:
				break
			var next := _clone(next_state)
			nodes += 1
			if BattleRepro.apply_action(next, action).get("ok", false):
				next.cleanup_deaths()
				outcome = maxf(outcome, _value(next, player) - base)
		var score := outcome + float(candidate.get("score", 0)) * 0.02
		if score > best_score:
			best_score = score
			best = candidate.duplicate(true)
	EventBus.set_block_signals(previously_blocked)
	if best_score == -INF: return best
	best["search_nodes"] = nodes
	best["search_depth"] = 2
	best["explanation"].append("two_action_outcome:%.1f" % best_score)
	return best


static func _diverse_actions(ranked: Array, limit: int) -> Array:
	var result: Array = []
	var seen := {}
	for action in ranked:
		var key := _action_key(action)
		if seen.has(key):
			continue
		seen[key] = true
		result.append(action)
		if result.size() >= limit:
			break
	return result


static func _action_key(action: Dictionary) -> String:
	var action_type := str(action.get("type", ""))
	if action_type == "summon":
		# Empty-slot choices are strategically equivalent in the current rules.
		# Keeping one leaves the bounded search room for other cards and actions.
		return "summon:%d" % int(action.get("hand_index", -1))
	return "%s:%d:%d:%d:%d:%d" % [
		action_type,
		int(action.get("hand_index", -1)),
		int(action.get("source_slot", action.get("slot", -1))),
		int(action.get("target_slot", -1)),
		int(action.get("target_player", -1)),
		int(action.get("skill_index", -1)),
	]


static func _clone(state: Dictionary) -> RefCounted:
	var game := Game.new()
	game.quiet = true
	game.apply_initial_state(state, false)
	game.draw_callable = game.draw_cards
	return game


static func _value(game: RefCounted, player: int) -> float:
	var ally: BattleField = game.player_field if player == 1 else game.player2_field
	var enemy: BattleField = game.player2_field if player == 1 else game.player_field
	if enemy.player_hp <= 0:
		return 100000.0
	if ally.player_hp <= 0:
		return -100000.0
	var score := float(ally.player_hp - enemy.player_hp) * 3.0
	for pair in [[ally, 1.0], [enemy, -1.0]]:
		for card in pair[0].slots:
			if card != null and card.is_alive():
				score += float(pair[1]) * (card.effective_atk() * 3.0 + card.hp * 1.5 + card.temp_hp + card.cost + 4.0)
	var hand: Array = game.player_hand if player == 1 else game.player2_hand
	score += hand.size() * 1.0 + ally.get_total_mana() * 0.4
	return score


static func needs_search(game: RefCounted) -> bool:
	# Setup effects benefit from look-ahead. Plain trades keep the cheap planner.
	for card in game.active_hand() + game.active_field().slots:
		if card == null:
			continue
		if _has_setup(card.skills):
			return true
	return false


static func _has_setup(value: Variant) -> bool:
	if value is Dictionary:
		if str(value.get("effect", "")) in ["gain_mana", "gain_attack", "make_zero_cost", "change_cost"]:
			return true
		for child in value.values():
			if _has_setup(child): return true
	elif value is Array:
		for child in value:
			if _has_setup(child): return true
	return false


static func _supported(game: RefCounted, action: Dictionary) -> bool:
	var cards: Array = []
	# A passive on any unit may request a UI choice; avoid partial simulations.
	cards.append_array(game.player_field.slots)
	cards.append_array(game.player2_field.slots)
	if str(action.get("type", "")) in ["cast", "summon", "attach"]:
		cards.append(game.active_hand()[int(action.get("hand_index", 0))])
	for card in cards:
		if card != null and _has_manual_choice(card.skills): return false
	return true


static func _has_manual_choice(value: Variant) -> bool:
	if value is Dictionary:
		if str(value.get("effect", "")) in ["view_discard_select", "view_deck_select", "make_zero_cost"]: return true
		for child in value.values():
			if _has_manual_choice(child): return true
	elif value is Array:
		for child in value:
			if _has_manual_choice(child): return true
	return false
