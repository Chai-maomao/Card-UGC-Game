extends RefCounted

const SpellRules = preload("res://SpellRules.gd")
const ParasiteRules = preload("res://ParasiteRules.gd")
const GameplayRandom = preload("res://GameplayRng.gd")
const Schema = preload("res://DataSchema.gd")
const _GameplayLog = preload("res://GameplayLog.gd")

var player_field: BattleField
var player2_field: BattleField
var player_hand: Array = []
var player2_hand: Array = []
var is_player_turn: bool = true
var turn_number: int = 1
var current_player: int = 1  # 1 or 2
var starting_player: int = 1
var draw_callable: Callable
var first_switch: bool = true
var battle_config: Dictionary = {}
var effective_actions_this_turn := 0
var shared_deck: Array = []
var shared_discard: Array = []
var game_rng := RandomNumberGenerator.new()
var state_revision: int = 0
var pending_cost_choices: Array = []
var manual_enemy_swaps := false
var auto_enemy_swap_player := 0
var quiet: bool = false
var trace_callable: Callable
var metrics_callable: Callable
var allow_first_turn_attacks: bool = false
var _lifecycle_trigger_depth: int = 0
var _board_change_trigger_depth: int = 0
# 每位玩家的战斗统计（召唤/施法/寄生/抽牌/卡牌伤害/本体伤害/击杀/消耗圣水），
# 按玩家编号 1/2 记录，用于历史战绩详情
var stats: Dictionary = {1: _new_stats(), 2: _new_stats()}


func _new_stats() -> Dictionary:
	return {
		"summons": 0,
		"spells": 0,
		"parasites": 0,
		"cards_drawn": 0,
		"card_damage": 0,
		"hero_damage": 0,
		"kills": 0,
		"mana_spent": 0,
	}


func _log(message: Variant) -> void:
	if not quiet:
		_GameplayLog.write(message)


func get_stats(player: int) -> Dictionary:
	return stats.get(player, _new_stats())


# ---- 战斗统计：在动作窗口内监听 damage_resolved，按伤害来源归属玩家 ----
# 说明：连接只在同步触发窗口内存在（connect/disconnect 成对出现），
# 避免向 autoload 信号长期挂接导致 GameState 实例无法回收、跨局重复计数。
var _stats_listening := false
var _stats_actor := 0


func _stats_listen(actor: int = 0) -> void:
	_stats_actor = actor
	if _stats_listening:
		return
	EventBus.damage_resolved.connect(_on_stats_damage)
	_stats_listening = true


func _stats_unlisten() -> void:
	_stats_actor = 0
	if not _stats_listening:
		return
	EventBus.damage_resolved.disconnect(_on_stats_damage)
	_stats_listening = false


func _on_stats_damage(source: CardData, target: CardData, _declared: int, actual: int, _reduction_pct: int, _temp_hp_before: int, _reason: String) -> void:
	if actual <= 0 or target == null:
		return
	var owner := _stats_owner_of(source)
	if owner == 0:
		owner = _stats_actor
	if owner == 0:
		return
	stats[owner]["card_damage"] = int(stats[owner].get("card_damage", 0)) + actual
	if not target.is_alive():
		stats[owner]["kills"] = int(stats[owner].get("kills", 0)) + 1


func _record_suppressed_damage(source: CardData, target: CardData, declared: int, actual: int, reduction_pct: int, temp_hp_before: int, reason: String) -> void:
	# UI suppression must not suppress authoritative statistics during replay.
	if EventBus.is_blocking_signals() and _stats_listening:
		_on_stats_damage(source, target, declared, actual, reduction_pct, temp_hp_before, reason)


func _stats_owner_of(card: CardData) -> int:
	if card == null:
		return 0
	for i in range(5):
		if player_field.slots[i] == card:
			return 1
		if player2_field.slots[i] == card:
			return 2
	return 0


func _stats_add(player: int, key: String, amount: int) -> void:
	if player != 1 and player != 2:
		return
	stats[player][key] = int(stats[player].get(key, 0)) + amount


func record_metric(event: Dictionary) -> void:
	if not metrics_callable.is_valid(): return
	var row := event.duplicate()
	var source: CardData = row.get("source_card")
	var target: Variant = row.get("target_card")
	var owner := _metric_owner_of(source)
	row["source_player"] = owner if owner != 0 else int(row.get("source_player", current_player))
	var target_owner := _metric_owner_of(target)
	row["target_player"] = target_owner if target_owner != 0 else int(row.get("target_player", 0))
	row["source"] = {"name": source.card_name, "card_id": source.card_id, "instance_id": source.instance_id, "identity": BattleMetrics.identity_of(source)} if source != null else {}
	row["hero"] = target is BattleField
	if str(row.get("kind", "")) == "status_origin" and target is CardData:
		row["status_target"] = weakref(target)
	row.erase("source_card")
	row.erase("target_card")
	metrics_callable.call(row)


func _metric_owner_of(target: Variant) -> int:
	if target == null: return 0
	for player in [1, 2]:
		var field: BattleField = player_field if player == 1 else player2_field
		if target == field: return player
		for card in field.slots:
			if card == target: return player
			if card is CardData and card.parasite_cards.has(target): return player
	return 0


func _record_attack_metric(source: CardData, target: Variant, amount: int, kind: String = "damage") -> void:
	if not metrics_callable.is_valid() or amount <= 0: return
	var total := maxi(1,source.effective_atk())
	var remaining := amount
	for parasite in source.parasite_cards:
		var share := mini(remaining, int(floor(float(amount) * maxi(0,parasite.atk) / total)))
		if share > 0:
			record_metric({"kind":kind,"source_card":parasite,"target_card":target,"amount":share})
			remaining -= share
	for status in source.status_effects:
		if status.get("buff_id","") != SkillEngine.BUFF_ATK_BOOST or int(status.get("value",0)) <= 0: continue
		var share := mini(remaining, int(floor(float(amount) * int(status.value) / total)))
		if share > 0:
			record_metric({"kind":kind,"status":status,"source_card":source,"target_card":target,"amount":share})
			remaining -= share
	record_metric({"kind":kind,"source_card":source,"target_card":target,"amount":remaining})


func _metric_payment(source: CardData, action: String, mana: int, points: int, temp_before: int) -> void:
	record_metric({"kind": "payment", "source_card": source, "action": action, "mana": mana, "points": points, "temporary_mana": mini(temp_before, mana), "source_player": current_player})


func init_game(draw_cb: Callable, requested_seed: Variant = null, opening_player: int = 1) -> void:
	draw_callable = draw_cb
	if requested_seed != null:
		game_rng.seed = int(requested_seed)
	elif PlayerData.is_online_battle():
		game_rng.seed = 4567
	else:
		game_rng.randomize()
	initialize_fields(PlayerData.battle_config)
	_build_shared_deck()
	deal_opening_hands(PlayerData.card_playtest_opening_card(), opening_player)
	EventBus.game_started.emit()


# Shared setup for fresh real and simulated matches. Deck selection, RNG seed,
# editor instruments and presentation events remain the caller's responsibility.
func initialize_fields(config: Dictionary) -> void:
	battle_config = config.duplicate(true)
	var start_hp: int = battle_config.get("starting_hp", 30)
	player_field = BattleField.new("P1", start_hp, 10)
	player2_field = BattleField.new("P2", start_hp, 10)
	player_field.quiet = quiet
	player2_field.quiet = quiet


func deal_opening_hands(test_card: CardData = null, opening_player: int = 1) -> void:
	var opening_count := opening_hand_size(battle_config)
	if test_card != null:
		# The dedicated test specimen is not shuffled into the shared deck: reserve
		# one opening-hand slot for it, even when the normal opening already fills six.
		player_hand.append(test_card)
		_stats_add(1, "cards_drawn", 1)
		_reserve_playtest_helpers(player_hand, 1)
		_reserve_playtest_helpers(player2_hand, 2)
		# Even custom zero-draw settings must leave room for the test instruments.
		opening_count = maxi(opening_count, 3)
	draw_cards_for_player(opening_count - player_hand.size(), 1)
	draw_cards_for_player(opening_count - player2_hand.size(), 2)
	starting_player = 2 if opening_player == 2 else 1
	current_player = starting_player
	reset_action_budget(1)
	reset_action_budget(2)


static func opening_hand_size(config: Dictionary) -> int:
	return clampi(int(config.get("draw_per_turn", PlayerData.DEFAULT_BATTLE_CONFIG["draw_per_turn"])) + 1, 1, SkillEngine.MAX_HAND_SIZE)


static func first_response_resources(config: Dictionary, mana: int, draws: int) -> Vector2i:
	return Vector2i(maxi(1, mana / 2) + int(config.get("second_extra_mana", 0)),
		maxi(1, draws / 2) + int(config.get("second_extra_cards", 0)))


func _reserve_playtest_helpers(hand: Array, player: int) -> void:
	for support_id: String in CardDatabase.PLAYTEST_SUPPORT_IDS:
		for index in range(shared_deck.size()):
			var card: CardData = shared_deck[index]
			if card.card_id == support_id:
				shared_deck.remove_at(index)
				hand.append(card)
				_stats_add(player, "cards_drawn", 1)
				break


func export_initial_state() -> Dictionary:
	var state := {
		"player_field": _serialize_field(player_field),
		"player2_field": _serialize_field(player2_field),
		"player_hand": _serialize_card_array(player_hand),
		"player2_hand": _serialize_card_array(player2_hand),
		"shared_deck": _serialize_card_array(shared_deck),
		"shared_discard": _serialize_card_array(shared_discard),
		"current_player": current_player,
		"starting_player": starting_player,
		"turn_number": turn_number,
		"is_player_turn": is_player_turn,
		"first_switch": first_switch,
		"state_revision": state_revision,
		"effective_actions_this_turn": effective_actions_this_turn,
		"rng_seed": game_rng.seed,
		"rng_state": game_rng.state,
		"stats": {1: get_stats(1).duplicate(true), 2: get_stats(2).duplicate(true)},
		"battle_config": battle_config.duplicate(true),
		"allow_first_turn_attacks": allow_first_turn_attacks,
	}
	if not pending_cost_choices.is_empty():
		state["pending_cost_choices"] = pending_cost_choices.duplicate(true)
	return state


func copy_for_simulation() -> RefCounted:
	# Trusted in-memory copies avoid revalidating the network/save schema at
	# every search node. No cards, arrays, callbacks or RNG are shared with play.
	var copy: RefCounted = get_script().new()
	copy.quiet = true
	for pair in [["player_field", player_field], ["player2_field", player2_field]]:
		var source: BattleField = pair[1]
		var field := BattleField.new(source.owner_name, source.max_player_hp, source.max_mana)
		field.quiet = true
		field.player_hp = source.player_hp
		field.current_mana = source.current_mana
		field.temp_mana = source.temp_mana
		field.action_budget = source.action_budget
		field.action_points = source.action_points
		field.actions_taken = source.actions_taken
		field.slots = _copy_cards(source.slots)
		copy.set(pair[0], field)
	for property in ["player_hand", "player2_hand", "shared_deck", "shared_discard"]:
		copy.set(property, _copy_cards(get(property)))
	for property in ["is_player_turn", "turn_number", "current_player", "starting_player", "first_switch", "state_revision", "allow_first_turn_attacks"]:
		copy.set(property, get(property))
	copy.battle_config = battle_config.duplicate(true)
	copy.effective_actions_this_turn = effective_actions_this_turn
	copy.stats = stats.duplicate(true)
	copy.pending_cost_choices = pending_cost_choices.duplicate(true)
	copy.manual_enemy_swaps = manual_enemy_swaps
	copy.auto_enemy_swap_player = auto_enemy_swap_player
	copy.game_rng.seed = game_rng.seed
	copy.game_rng.state = game_rng.state
	copy.draw_callable = copy.draw_cards
	return copy


func _copy_cards(cards: Array) -> Array:
	var copies: Array = []
	for card in cards:
		copies.append(card.duplicate_card() if card != null else null)
	return copies


func apply_initial_state(state: Dictionary, sync_preferences: bool = true) -> void:
	var envelope := {"schema": 1, "room_code": "STATE", "player": 1, "state": state}
	var state_errors := Schema.validate(Schema.KIND_MATCH_SNAPSHOT, envelope)
	if not state_errors.is_empty():
		push_warning("Rejected invalid battle state: %s" % [state_errors])
		return
	# Sync battle_config from authority so both players use the same rules.
	var config: Dictionary = state.get("battle_config", {})
	record_metric({"kind": "reset"})
	if not config.is_empty():
		battle_config = config.duplicate(true)
		if sync_preferences:
			PlayerData.battle_config = battle_config.duplicate(true)
	if player_field == null:
		player_field = BattleField.new("P1", 1, 1)
	if player2_field == null:
		player2_field = BattleField.new("P2", 1, 1)
	player_field.quiet = quiet
	player2_field.quiet = quiet
	_apply_field_state(player_field, state.get("player_field", {}))
	_apply_field_state(player2_field, state.get("player2_field", {}))
	player_hand = _deserialize_card_array(state.get("player_hand", []))
	player2_hand = _deserialize_card_array(state.get("player2_hand", []))
	shared_deck = _deserialize_card_array(state.get("shared_deck", []))
	shared_discard = _deserialize_card_array(state.get("shared_discard", []))
	current_player = int(state.get("current_player", 1))
	starting_player = 2 if state.get("starting_player", 1) == 2 else 1
	turn_number = int(state.get("turn_number", 1))
	is_player_turn = bool(state.get("is_player_turn", true))
	first_switch = bool(state.get("first_switch", true))
	state_revision = int(state.get("state_revision", state_revision))
	effective_actions_this_turn = maxi(0, int(state.get("effective_actions_this_turn", 0)))
	pending_cost_choices = state.get("pending_cost_choices", []).duplicate(true)
	allow_first_turn_attacks = bool(state.get("allow_first_turn_attacks", false))
	game_rng.seed = int(state.get("rng_seed", game_rng.seed))
	game_rng.state = int(state.get("rng_state", game_rng.state))
	var synced_stats = state.get("stats", {})
	if synced_stats is Dictionary and not synced_stats.is_empty():
		for player in [1, 2]:
			var entry = synced_stats.get(player, synced_stats.get(str(player), {}))
			if entry is Dictionary:
				stats[player] = entry.duplicate(true)


func _serialize_field(field: BattleField) -> Dictionary:
	return {
		"player_hp": field.player_hp,
		"max_player_hp": field.max_player_hp,
		"current_mana": field.current_mana,
		"max_mana": field.max_mana,
		"temp_mana": field.temp_mana,
		"action_points": field.action_points,
		"action_budget": field.action_budget,
		"actions_taken": field.actions_taken,
		"slots": _serialize_slots(field.slots),
	}


func _apply_field_state(field: BattleField, state: Dictionary) -> void:
	if state.is_empty():
		return
	field.player_hp = int(state.get("player_hp", field.player_hp))
	field.max_player_hp = int(state.get("max_player_hp", field.max_player_hp))
	field.current_mana = int(state.get("current_mana", field.current_mana))
	field.max_mana = int(state.get("max_mana", field.max_mana))
	field.temp_mana = int(state.get("temp_mana", 0))
	field.action_points = int(state.get("action_points", 0))
	field.action_budget = int(state.get("action_budget", field.action_points))
	field.actions_taken = int(state.get("actions_taken", 0))
	field.slots = _deserialize_slots(state.get("slots", []))


func _serialize_slots(slots: Array) -> Array:
	var result: Array = []
	for card in slots:
		result.append({} if card == null else PlayerData.serialize_card(card))
	return result


func _deserialize_slots(slots_data: Array) -> Array:
	var result: Array = []
	for i in range(5):
		if i >= slots_data.size() or slots_data[i].is_empty():
			result.append(null)
		else:
			result.append(PlayerData.deserialize_card(slots_data[i]))
	return result


func _serialize_card_array(cards: Array) -> Array:
	var result: Array = []
	for card in cards:
		result.append(PlayerData.serialize_card(card))
	return result


func _deserialize_card_array(cards_data: Array) -> Array:
	var result: Array = []
	for card_data in cards_data:
		result.append(PlayerData.deserialize_card(card_data))
	return result


func _build_shared_deck() -> void:
	shared_deck.clear()
	shared_discard.clear()
	var p1 = PlayerData.battle_deck if PlayerData.battle_deck.size() > 0 else PlayerData.card_library
	var p2 = PlayerData.opponent_battle_deck if PlayerData.opponent_battle_deck.size() > 0 else PlayerData.card_library
	if PlayerData.is_online_battle() and not NetworkManager.is_authority():
		p1 = PlayerData.opponent_battle_deck if PlayerData.opponent_battle_deck.size() > 0 else PlayerData.card_library
		p2 = PlayerData.battle_deck if PlayerData.battle_deck.size() > 0 else PlayerData.card_library
	for c in p1:
		shared_deck.append(c.duplicate_card())
	for c in p2:
		shared_deck.append(c.duplicate_card())
	if shared_deck.is_empty():
		for c in CardDatabase.player_starters():
			shared_deck.append(c.duplicate_card())
			# double starters for both players in hotseat
			shared_deck.append(c.duplicate_card())
	_shuffle_shared_deck()


func _shuffle_shared_deck() -> void:
	GameplayRandom.shuffle(shared_deck, game_rng)


func active_field() -> BattleField:
	return player_field if current_player == 1 else player2_field


func opponent_field() -> BattleField:
	return player2_field if current_player == 1 else player_field


func active_hand() -> Array:
	return player_hand if current_player == 1 else player2_hand


func make_skill_context(source_slot: int = -1, target_slot: int = -1, target_player: int = 0) -> Dictionary:
	return make_skill_context_for_player(current_player, source_slot, target_slot, target_player)


func make_skill_context_for_player(player: int, source_slot: int = -1, target_slot: int = -1, target_player: int = 0) -> Dictionary:
	var player_field_for_context = player_field if player == 1 else player2_field
	var enemy_field_for_context = player2_field if player == 1 else player_field
	var active_hand_for_context = player_hand if player == 1 else player2_hand
	var enemy_hand_for_context = player2_hand if player == 1 else player_hand
	return {
		"player_field": player_field_for_context,
		"enemy_field": enemy_field_for_context,
		"source_slot": source_slot,
		"target_slot": target_slot,
		"target_player": target_player,
		"draw_callable": Callable(self, "draw_cards_for_player").bind(player),
		"hand_entry_callable": Callable(self, "resolve_hand_entry_for_player").bind(player),
		"board_change_callable": Callable(self, "notify_board_units_changed"),
		"enemy_swap_callable": Callable(self, "_request_enemy_slot_swap").bind(player),
		"discard_card_callable": Callable(self, "finalize_card_discard"),
		"current_player": player,
		"active_hand": active_hand_for_context,
		"enemy_hand": enemy_hand_for_context,
		"discard_pile": shared_discard,
		"shared_deck": shared_deck,
		"rng": game_rng,
		"turn_number": turn_number,
		"quiet": quiet,
		"trace_callable": trace_callable,
		"metrics_callable": Callable(self, "record_metric") if metrics_callable.is_valid() else Callable(),
		"damage_stats_callable": Callable(self, "_record_suppressed_damage"),
		"reaction_context_callable": Callable(self, "make_reaction_context"),
	}


func make_reaction_context(reactor: CardData, context: Dictionary) -> Dictionary:
	var owner := _metric_owner_of(reactor)
	if owner not in [1, 2]: return context
	var cause: CardData = context.get("source_card")
	var cause_owner := _metric_owner_of(cause)
	if cause_owner == 0: cause_owner = int(context.get("current_player", 0))
	var source_field: BattleField = player_field if owner == 1 else player2_field
	var cause_field: BattleField = player_field if cause_owner == 1 else player2_field
	var cause_slot := cause_field.slots.find(cause) if cause != null else -1
	# Keep the shared recursion budget/RNG and per-effect options. Rebind only
	# battle-owned fields, hands and callbacks to the reacting unit's owner.
	var reaction := context.duplicate()
	reaction.erase("selected_unit_field")
	reaction.merge(make_skill_context_for_player(owner, source_field.slots.find(reactor), cause_slot, cause_owner), true)
	reaction["reaction_target_card"] = cause
	return reaction


# ============================================
# Drawing / discard
# ============================================

func draw_cards_for_player(amount: int, player: int) -> Array:
	var hand = player_hand if player == 1 else player2_hand
	return draw_cards(amount, hand, player)


func draw_cards(amount: int, hand: Array = active_hand(), player: int = 0) -> Array:
	if player not in [1, 2]:
		player = 1 if is_same(hand, player_hand) else (2 if is_same(hand, player2_hand) else current_player)
	# Collect the whole draw batch before resolving hand capacity. Otherwise a
	# card that overflows into an empty discard pile could immediately be
	# shuffled back and drawn again by the same multi-card draw.
	var candidates: Array = []
	var reshuffle_count := 0
	for _k in range(maxi(0, amount)):
		if shared_deck.is_empty() and not shared_discard.is_empty():
			reshuffle_count = shared_discard.size()
			_log("Deck empty! Shuffling discard pile into deck...")
			shared_deck = shared_discard.duplicate()
			shared_discard.clear()
			_shuffle_shared_deck()
		if shared_deck.is_empty():
			break
		candidates.append(shared_deck.pop_front())

	var drawn: Array = []
	for candidate_index in range(candidates.size()):
		var card_data: CardData = candidates[candidate_index]
		# Presentation uses the batch position to stagger cards without delaying
		# authoritative draw resolution. Keep this metadata cosmetic: rules and
		# networking still resolve the whole batch immediately.
		var destination := resolve_hand_entry_for_player(card_data, "deck", {
			"batch_index": candidate_index,
			"batch_size": candidates.size(),
			"reshuffle_count": reshuffle_count,
			"reshuffle_deck_remaining": shared_deck.size(),
		}, player)
		if destination == "hand":
			drawn.append(card_data)
			_log("Drew: %s" % card_data.card_name)
	if not candidates.is_empty():
		_stats_add(player, "cards_drawn", candidates.size())
	return drawn


func resolve_hand_entry_for_player(card_data: CardData, source: String = "generated", source_meta: Dictionary = {}, player: int = 0) -> String:
	if card_data == null or player not in [1, 2]:
		return ""
	_trigger_lifecycle(SkillEngine.TRIGGER_ON_ADDED, card_data, player)
	var hand: Array = player_hand if player == 1 else player2_hand
	var destination := "hand"
	if hand.size() < SkillEngine.MAX_HAND_SIZE:
		hand.append(card_data)
	else:
		destination = "discard"
		move_card_to_shared_discard(card_data, player, "overflow")
		_log("Hand overflow: %s moved to discard" % card_data.card_name)
	EventBus.hand_entry_resolved.emit(card_data, player, destination, source, source_meta.duplicate(true))
	return destination


func move_card_to_shared_discard(card_data: CardData, player: int = 0, reason: String = "discard") -> void:
	if card_data == null:
		return
	if player in [1, 2] and reason in ["discard", "manual", "overflow", "effect"]:
		_trigger_lifecycle(SkillEngine.TRIGGER_ON_DISCARDED, card_data, player)
	# Overflow is a real trip to the discard pile, not deletion. Apply the same
	# lifecycle cleanup as defeat/manual discard before the card becomes visible
	# there: release attachments and restore battle-only HP/ATK/cost state.
	ParasiteRules.release_all_to_discard(card_data, shared_discard)
	card_data.reset_to_base()
	shared_discard.append(card_data)


func finalize_card_discard(card_data: CardData, player: int, reason: String = "effect") -> void:
	move_card_to_shared_discard(card_data, player, reason)


func _trigger_lifecycle(trigger: String, card_data: CardData, player: int) -> void:
	if _lifecycle_trigger_depth >= 16:
		push_warning("[GameState] Card lifecycle trigger chain limit reached")
		return
	_lifecycle_trigger_depth += 1
	SkillEngine.trigger_skills(trigger, card_data, make_skill_context_for_player(player))
	_lifecycle_trigger_depth -= 1


# Emits the board-composition trigger after a unit has entered or left a
# battlefield. Slot swaps deliberately do not call this method: composition
# is unchanged. Nested charm/death chains are bounded like lifecycle chains.
func notify_board_units_changed(changed_player: int, change_kind: String = "change", changed_card: CardData = null) -> void:
	if changed_player not in [1, 2]:
		return
	if _board_change_trigger_depth >= 16:
		push_warning("[GameState] Board-change trigger chain limit reached")
		return
	_board_change_trigger_depth += 1
	var sources: Array = []
	for owner in [1, 2]:
		var field: BattleField = player_field if owner == 1 else player2_field
		for slot in range(field.slots.size()):
			var card: CardData = field.slots[slot]
			if card == null or not card.is_alive():
				continue
			for skill_index in range(card.skills.size()):
				var skill: Dictionary = card.skills[skill_index]
				if str(skill.get("trigger", "")) != SkillEngine.TRIGGER_ON_BOARD_CHANGED:
					continue
				var side := str(skill.get("trigger_side", SkillEngine.TARGET_SIDE_ALL))
				if side == SkillEngine.TARGET_SIDE_ALL or (side == SkillEngine.TARGET_SIDE_ALLY and owner == changed_player) or (side == SkillEngine.TARGET_SIDE_ENEMY and owner != changed_player):
					sources.append({"owner": owner, "slot": slot, "card": card, "skill_index": skill_index})
	for entry in sources:
		var owner := int(entry.owner)
		var source: CardData = entry.card
		var field: BattleField = player_field if owner == 1 else player2_field
		var live_slot := field.slots.find(source)
		if live_slot < 0 or not source.is_alive():
			continue
		var context := make_skill_context_for_player(owner, live_slot)
		context["board_changed_player"] = changed_player
		context["board_change_kind"] = change_kind
		context["board_changed_card"] = changed_card
		SkillEngine.trigger_single_skill(source, int(entry.skill_index), context)
	_board_change_trigger_depth -= 1


func discard_card(card_data: CardData) -> bool:
	return discard_card_with_refund(card_data) >= 0


# A negative result means no card was removed. Zero is a successful discard at the mana cap.
func discard_card_with_refund(card_data: CardData) -> int:
	# Check hand first, then battlefield
	var hand = active_hand()
	var idx: int = hand.find(card_data)
	if idx >= 0:
		hand.remove_at(idx)
		move_card_to_shared_discard(card_data, current_player, "manual")
		var refund := _refund_discard_mana(card_data)
		_log("Discarded from hand: %s" % card_data.card_name)
		return refund
	# Check battlefield
	var field = active_field()
	for i in range(5):
		if field.slots[i] == card_data:
			field.slots[i] = null
			move_card_to_shared_discard(card_data, current_player, "manual")
			notify_board_units_changed(current_player, "leave", card_data)
			var refund := _refund_discard_mana(card_data)
			_log("Discarded from field: %s" % card_data.card_name)
			return refund
	return -1


func _refund_discard_mana(card_data: CardData) -> int:
	effective_actions_this_turn += 1
	var field := active_field()
	var before := field.current_mana
	field.add_mana(1)
	var refund := field.current_mana - before
	record_metric({"kind": "mana_refunded", "source_card": card_data, "target_card": field, "amount": refund})
	return maxi(0, refund)


# ============================================
# Summon / skill activation / spell cast
# ============================================

func summon_card(card_data: CardData, slot_index: int) -> bool:
	if card_data != null and (card_data.is_spell() or card_data.is_parasite()):
		return false
	var summoner := current_player
	var temp_before := active_field().temp_mana
	if not active_field().summon_card(card_data, slot_index):
		return false
	effective_actions_this_turn += 1
	_stats_add(summoner, "summons", 1)
	_stats_add(summoner, "mana_spent", card_data.cost)
	_metric_payment(card_data, "summon", card_data.cost, 0, temp_before)
	card_data.clear_cost_modifiers_after_play()
	active_hand().erase(card_data)
	notify_board_units_changed(summoner, "enter", card_data)
	return true


func attach_parasite(hand_index: int, target_player: int, target_slot: int) -> bool:
	var hand := active_hand()
	if hand_index < 0 or hand_index >= hand.size():
		return false
	var card: CardData = hand[hand_index]
	var target_field := player_field if target_player == 1 else player2_field
	var target: CardData = target_field.slots[target_slot] if target_slot >= 0 and target_slot < target_field.slots.size() else null
	var attach_check: Dictionary = ParasiteRules.can_attach(card, target, active_field().get_total_mana())
	if not attach_check.get("ok", false):
		return false
	effective_actions_this_turn += 1
	var attacher := current_player
	var temp_before := active_field().temp_mana
	active_field().spend_mana(card.cost)
	_metric_payment(card, "attach", card.cost, 0, temp_before)
	hand.remove_at(hand_index)
	if _target_dodged(target):
		card.reset_to_base()
		shared_discard.append(card)
	else:
		ParasiteRules.attach(card, target)
		_stats_add(attacher, "parasites", 1)
	_stats_add(attacher, "mana_spent", card.cost)
	card.clear_cost_modifiers_after_play()
	return true


# Cast a spell from hand: consume mana, remove from hand, trigger on_cast
# skill, then move the card directly to the discard pile (no slot occupation,
# no +1 discard-mana refund).
func cast_spell(hand_index: int, skill_index: int = SpellRules.CAST_SKILL_INDEX, target_slot: int = -1, target_player: int = 0) -> bool:
	var hand := active_hand()
	if hand_index < 0 or hand_index >= hand.size():
		return false
	var card: CardData = hand[hand_index]
	var cast_check: Dictionary = SpellRules.can_cast(card, active_field().get_total_mana(), skill_index, turn_number)
	if not cast_check.get("ok", false):
		return false
	var normalized_skill: Dictionary = cast_check.get("skill", {})
	if SpellRules.needs_target(normalized_skill) and not _can_select_directed_unit(normalized_skill, card, target_slot, target_player):
		return false
	effective_actions_this_turn += 1

	var caster := current_player
	var field := active_field()
	var paid_cost := card.cost
	var temp_before := field.temp_mana
	field.spend_mana(card.cost)
	_metric_payment(card, "cast", paid_cost, 0, temp_before)
	hand.remove_at(hand_index)

	if skill_index >= 0 and skill_index < card.skills.size():
		card.skills[skill_index] = normalized_skill
	_resolve_directed_skill(card, -1, target_slot, skill_index, target_player)

	_stats_add(caster, "spells", 1)
	_stats_add(caster, "mana_spent", paid_cost)
	card.reset_to_base()
	shared_discard.append(card)
	return true


func trigger_summon_skills(source_slot: int, target_slot: int, skill_index: int, target_player: int = 0) -> void:
	# Fires a single on_summon skill by index WITHOUT marking has_acted.
	# on_summon skills are now manually activated (only on the summon turn);
	# Main._on_skill_activated routes them here so they don't consume the
	# card's attack/action for the turn, unlike trigger_activate_skills.
	var card: CardData = active_field().slots[source_slot]
	if card != null and skill_index >= 0 and skill_index < card.skills.size():
		if turn_number <= 1 and SkillRegistry.skill_changes_enemy_hp_or_presence(card.skills[skill_index]):
			return
		if target_slot >= 0 and SpellRules.needs_target(card.skills[skill_index]) \
				and not _can_select_directed_unit(card.skills[skill_index], card, target_slot, target_player):
			return
		effective_actions_this_turn += 1
		_resolve_directed_skill(card, source_slot, target_slot, skill_index, target_player)


func _resolve_directed_skill(source: CardData, source_slot: int, target_slot: int, skill_index: int, target_player: int) -> void:
	var skill: Dictionary = source.skills[skill_index]
	var context := make_skill_context(source_slot, target_slot, target_player)
	if target_slot >= 0 and SpellRules.needs_target(skill):
		var field := _directed_skill_field(target_player)
		context["selected_unit_field"] = field
		if _target_dodged(field.slots[target_slot]):
			return
	_stats_listen(current_player)
	SkillEngine.trigger_single_skill(source, skill_index, context)
	_stats_unlisten()


func _can_select_directed_unit(skill: Dictionary, source: CardData, slot: int, target_player: int) -> bool:
	return SpellRules.can_select_unit(skill, source, _directed_skill_field(target_player), slot, _directed_skill_is_hostile(target_player), turn_number)


func _directed_skill_field(target_player: int) -> BattleField:
	return active_field() if target_player == current_player else (player2_field if current_player == 1 else player_field)


func _directed_skill_is_hostile(target_player: int) -> bool:
	return target_player != current_player


func _target_dodged(target: CardData) -> bool:
	if target == null or not target.is_alive():
		return false
	var chance := target.get_dodge_chance()
	if chance <= 0 or game_rng.randi_range(1, 100) > chance:
		return false
	if not quiet:
		EventBus.action_dodged.emit(target)
	return true


func _request_enemy_slot_swap(player: int) -> void:
	var field := player2_field if player == 1 else player_field
	if not field.can_swap_unit_positions():
		return
	if manual_enemy_swaps and is_player_turn and player == current_player and player != auto_enemy_swap_player:
		if pending_cost_choices.size() < UgcSafety.MAX_EXECUTED_EFFECT_NODES:
			pending_cost_choices.append({"kind": "enemy_swap", "player": player})
		return
	for source in range(field.slots.size()):
		for offset in range(1, field.slots.size()):
			if apply_enemy_slot_swap(field, source, (source + offset) % field.slots.size()):
				return


func decode_enemy_slot_pair(index: int, slot_count: int) -> Vector2i:
	if index < 0 or index >= slot_count * slot_count:
		return Vector2i(-1, -1)
	@warning_ignore("integer_division")
	return Vector2i(index / slot_count, index % slot_count)


func apply_enemy_slot_swap(field: BattleField, source: int, destination: int) -> bool:
	if source == destination or source not in range(field.slots.size()) or destination not in range(field.slots.size()):
		return false
	var card: CardData = field.slots[source]
	if card == null or not card.is_selectable():
		return false
	var displaced: CardData = field.slots[destination]
	if displaced != null and not displaced.is_selectable():
		return false
	if not _target_dodged(card):
		field.slots[source] = field.slots[destination]
		field.slots[destination] = card
	return true


func reset_action_budget(player: int) -> void:
	var field: BattleField = player_field if player == 1 else player2_field
	var hand: Array = player_hand if player == 1 else player2_hand
	var empty_slots := field.slots.size() - field.get_alive_count()
	var empty_hand := maxi(0, SkillEngine.MAX_HAND_SIZE - hand.size())
	field.action_budget = maxi(0, int(floor(float(battle_config.get("action_base", 3)) + empty_slots * float(battle_config.get("action_empty_slot_factor", 1.0)) + empty_hand * float(battle_config.get("action_empty_hand_factor", 0.5)))))
	field.action_points = field.action_budget
	if not battle_config.has("action_base"):
		field.action_budget = 0
		field.action_points = 0
	field.actions_taken = 0


func next_action_payment() -> Dictionary:
	# Missing coefficients mean a legacy saved match keeps its original rules.
	return _action_payment(active_field().actions_taken, active_field().action_points, active_field().get_total_mana())


func _action_payment(actions: int, available_points: int, available_mana: int) -> Dictionary:
	var cost := actions if battle_config.has("action_base") else 0
	var points := mini(cost, available_points)
	var mana := int(ceil((cost - points) * float(battle_config.get("action_mana_factor", 1.0))))
	return {"cost": cost, "points": points, "mana": mana, "ok": available_mana >= mana}


func can_pay_action() -> bool:
	return bool(next_action_payment()["ok"])


func preview_action_payments(count: int = 2) -> Array:
	var points := active_field().action_points
	var mana := active_field().get_total_mana()
	var actions := active_field().actions_taken
	var result: Array = []
	for index in range(clampi(count, 0, active_field().slots.size())):
		var payment := _action_payment(actions, points, mana)
		result.append(payment)
		if not payment.ok:
			break
		points -= int(payment.points)
		mana -= int(payment.mana)
		actions += 1
	return result


func _pay_action(source: CardData = null, action: String = "activate") -> bool:
	var payment := next_action_payment()
	if not payment["ok"]:
		return false
	var temp_before := active_field().temp_mana
	active_field().spend_mana(int(payment["mana"]))
	active_field().action_points -= int(payment["points"])
	active_field().actions_taken += 1
	if action != "automatic":
		effective_actions_this_turn += 1
	_stats_add(current_player, "mana_spent", int(payment["mana"]))
	_metric_payment(source, action, int(payment.mana), int(payment.points), temp_before)
	return true


func can_activate_skill(source_slot: int, skill_index: int) -> bool:
	if source_slot < 0 or source_slot >= active_field().slots.size():
		return false
	var card: CardData = active_field().slots[source_slot]
	if card == null or not card.is_alive() or card.has_attacked or card.skills_disabled():
		return false
	if skill_index < 0 or skill_index >= card.skills.size() or card.skills_used.has(skill_index):
		return false
	var skill: Dictionary = card.skills[skill_index]
	if str(skill.get("trigger", "")) != SkillEngine.TRIGGER_ON_ACTIVATE or not SkillEngine.has_uses_remaining(card, skill, skill_index):
		return false
	if turn_number <= 1 and SkillRegistry.skill_changes_enemy_hp_or_presence(skill):
		return false
	return can_pay_action()


# Target-independent readiness only: no UGC execution or target prediction.
# Zero-ATK attacks remain valid (e.g. to trigger on-attack growth).
func unit_action_readiness(source_slot: int) -> Dictionary:
	var ready := {"attack": false, "skills": []}
	if source_slot < 0 or source_slot >= active_field().slots.size():
		return ready
	var card: CardData = active_field().slots[source_slot]
	if card == null or not card.is_alive() or not can_pay_action():
		return ready
	ready.attack = not card.has_acted and (turn_number > 1 or allow_first_turn_attacks) and not card.has_stun()
	for skill_index in range(card.skills.size()):
		if can_activate_skill(source_slot, skill_index):
			ready.skills.append(skill_index)
	return ready


func trigger_activate_skills(source_slot: int, target_slot: int, skill_index: int, target_player: int = 0) -> bool:
	if not can_activate_skill(source_slot, skill_index):
		return false
	var card: CardData = active_field().slots[source_slot]
	if SpellRules.needs_target(card.skills[skill_index]) and not _can_select_directed_unit(card.skills[skill_index], card, target_slot, target_player):
		return false
	if not _pay_action(card, "activate"):
		return false
	card.skills_used.append(skill_index)
	_resolve_directed_skill(card, source_slot, target_slot, skill_index, target_player)
	card.has_acted = true
	return true


func activate_skill(slot_index: int, skill_index: int) -> String:
	var card: CardData = active_field().slots[slot_index]
	if card == null or card.has_attacked:
		return ""
	if card.skills_disabled():
		return ""
	if skill_index >= card.skills.size():
		return ""
	var skill: Dictionary = card.skills[skill_index]
	if turn_number <= 1 and SkillRegistry.skill_changes_enemy_hp_or_presence(skill):
		return ""
	var trigger: String = skill.get("trigger", "")
	if trigger == SkillEngine.TRIGGER_ON_ACTIVATE:
		if trigger_activate_skills(slot_index, -1, skill_index):
			return skill.get("skill_name", "")
	return ""


# ============================================
# Attack
# ============================================

func execute_attack(atk_slot: int, def_slot: int, hostile: bool = true) -> Dictionary:
	if atk_slot < 0 or atk_slot >= active_field().slots.size() or def_slot < 0 or def_slot >= opponent_field().slots.size():
		return {}
	if turn_number <= 1 and not allow_first_turn_attacks:
		_log("Turn 1: attacks are not allowed!")
		return {}
	var attacker: CardData = active_field().slots[atk_slot]
	var victim: CardData = opponent_field().slots[def_slot]
	if attacker == null or victim == null or not victim.is_selectable():
		return {}
	# Keep taunt as a game-state invariant. UI, network clients and AI may all
	# propose targets, but none may bypass the rule at execution time.
	if hostile and opponent_field().has_any_taunt() and not victim.has_taunt():
		_log("A taunt minion must be attacked first!")
		return {}
	if attacker.has_acted:
		_log("%s already acted this turn!" % attacker.card_name)
		return {}
	if attacker.has_stun():
		_log("%s is stunned and cannot attack!" % attacker.card_name)
		return {}
	if not attacker.is_alive() or not victim.is_alive() or not _pay_action(attacker, "attack"):
		return {}
	if _target_dodged(victim):
		attacker.has_acted = true
		attacker.has_attacked = true
		return {"attacker_died": false, "victim_died": false, "dodged": true}
	var actor := current_player
	_stats_listen(actor)
	var atk_dmg: int = attacker.effective_atk()
	var thorns_before_damage: int = victim.get_thorns_damage()
	_log("%s attacks %s! (%d dmg)" % [attacker.card_name, victim.card_name, atk_dmg])
	var declared_dmg := atk_dmg
	var reduction_pct: int = victim.get_damage_reduction()
	if reduction_pct > 0:
		atk_dmg = int(floor(float(atk_dmg) * (1.0 - float(reduction_pct) / 100.0)))
	var parasite_result := ParasiteRules.absorb_damage_detail(victim, atk_dmg, shared_discard)
	atk_dmg = int(parasite_result.get("remaining", atk_dmg))
	var parasite: CardData = parasite_result.get("parasite", null)
	if parasite != null:
		record_metric({"kind":"damage_prevented","source_card":parasite,"target_card":victim,"amount":parasite_result.get("prevented",0),"source_player":3-current_player})
		record_metric({"kind": "parasite_damage", "source_card": attacker, "target_card": victim, "amount": parasite_result.absorbed})
		EventBus.parasite_damage_resolved.emit(victim, parasite, declared_dmg, int(parasite_result.get("absorbed", 0)), bool(parasite_result.get("destroyed", false)))
	var temp_hp_before: int = victim.temp_hp
	var actual_dmg: int = victim.take_damage_without_reduction(atk_dmg)
	_record_attack_metric(attacker,victim,actual_dmg)
	_record_attack_metric(attacker,victim,temp_hp_before-victim.temp_hp,"shield_damage")
	_record_suppressed_damage(attacker, victim, declared_dmg, actual_dmg, reduction_pct, temp_hp_before, "attack")
	EventBus.damage_resolved.emit(attacker, victim, declared_dmg, actual_dmg, reduction_pct, temp_hp_before, "attack")
	EventBus.hp_changed.emit(victim, -actual_dmg, victim.hp)
	if victim.is_alive():
		var victim_ctx := make_skill_context_for_player(3 - current_player, def_slot, atk_slot, current_player)
		victim_ctx["reaction_target_card"] = attacker
		SkillEngine.trigger_skills(SkillEngine.TRIGGER_ON_DAMAGED, victim, victim_ctx)
		SkillEngine.trigger_skills(SkillEngine.TRIGGER_ON_ATTACKED, victim, victim_ctx)
		ParasiteRules.trigger_host_passives(SkillEngine.TRIGGER_ON_DAMAGED, victim, victim_ctx)
	attacker.has_acted = true
	attacker.has_attacked = true
	if not victim.is_alive():
		var mana_before := active_field().current_mana
		active_field().add_mana(1)
		record_metric({"kind": "mana_refunded", "source_card": attacker, "target_card": active_field(), "amount": active_field().current_mana - mana_before})
		_log("  Kill! Mana +1")
	EventBus.attack_declared.emit(attacker, victim, atk_slot, def_slot)
	var thorns: int = thorns_before_damage
	if thorns > 0:
		_log("  [Thorns] %s reflects %d dmg" % [victim.card_name, thorns])
		var attacker_reduction: int = attacker.get_damage_reduction()
		var attacker_temp_before: int = attacker.temp_hp
		var thorns_actual: int = attacker.take_damage(thorns)
		record_metric({"kind": "damage", "source_card": victim, "target_card": attacker, "amount": thorns_actual})
		record_metric({"kind": "shield_damage", "source_card": victim, "target_card": attacker, "amount": attacker_temp_before - attacker.temp_hp})
		_record_suppressed_damage(victim, attacker, thorns, thorns_actual, attacker_reduction, attacker_temp_before, "thorns")
		EventBus.damage_resolved.emit(victim, attacker, thorns, thorns_actual, attacker_reduction, attacker_temp_before, "thorns")
		EventBus.hp_changed.emit(attacker, -thorns_actual, attacker.hp)
	SkillEngine.trigger_skills(SkillEngine.TRIGGER_ON_ATTACK, attacker, make_skill_context(atk_slot, def_slot))
	ParasiteRules.trigger_host_passives(SkillEngine.TRIGGER_ON_ATTACK, attacker, make_skill_context(atk_slot, def_slot))
	_stats_unlisten()
	return { "attacker_died": not attacker.is_alive(), "victim_died": not victim.is_alive() }


# ============================================
# Death cleanup
# ============================================

func cleanup_deaths() -> Dictionary:
	var p1_dead: Array = []
	var p2_dead: Array = []
	var death_comp: bool = battle_config.get("death_compensation", false)
	for i in range(5):
		if player_field.slots[i] != null and not player_field.slots[i].is_alive():
			var dead_card: CardData = player_field.slots[i]
			_log("%s died!" % dead_card.card_name)
			_stats_listen(1)
			SkillEngine.trigger_skills(SkillEngine.TRIGGER_ON_DEATH, dead_card, make_skill_context_for_player(1, i, -1))
			ParasiteRules.trigger_host_passives(SkillEngine.TRIGGER_ON_DEATH, dead_card, make_skill_context_for_player(1, i, -1))
			_stats_unlisten()
			if player_field.slots[i] == dead_card:
				ParasiteRules.release_all_to_discard(dead_card, shared_discard)
				dead_card.reset_to_base()
				shared_discard.append(dead_card)
				player_field.slots[i] = null
				notify_board_units_changed(1, "leave", dead_card)
			p1_dead.append(i)
			if death_comp:
				draw_cards_for_player(1, 1)
				_log("[DeathComp] P1 draws 1 card (compensation for %s)" % dead_card.card_name)
		if player2_field.slots[i] != null and not player2_field.slots[i].is_alive():
			var dead_card: CardData = player2_field.slots[i]
			_log("%s died!" % dead_card.card_name)
			_stats_listen(2)
			SkillEngine.trigger_skills(SkillEngine.TRIGGER_ON_DEATH, dead_card, make_skill_context_for_player(2, i, -1))
			ParasiteRules.trigger_host_passives(SkillEngine.TRIGGER_ON_DEATH, dead_card, make_skill_context_for_player(2, i, -1))
			_stats_unlisten()
			if player2_field.slots[i] == dead_card:
				ParasiteRules.release_all_to_discard(dead_card, shared_discard)
				dead_card.reset_to_base()
				shared_discard.append(dead_card)
				player2_field.slots[i] = null
				notify_board_units_changed(2, "leave", dead_card)
			p2_dead.append(i)
			if death_comp:
				draw_cards_for_player(1, 2)
				_log("[DeathComp] P2 draws 1 card (compensation for %s)" % dead_card.card_name)
	return { "p1": p1_dead, "p2": p2_dead }


# ============================================
# Turn system
# ============================================

func end_player_turn(allow_face_mana: bool = true) -> Dictionary:
	is_player_turn = false
	# Clear current player's temp mana (vanishes at turn end)
	active_field().clear_temp_mana()
	var refund_owner: int = current_player
	var refund_total: int = 0
	var observed_refunds: Array = []
	if metrics_callable.is_valid():
		for field in [player_field, player2_field]:
			for card in field.slots:
				if card == null: continue
				for effect in card.status_effects:
					if int(effect.get("owner", 0)) == refund_owner and str(effect.get("buff_id", "")) == SkillEngine.BUFF_MANA_REFUND:
						observed_refunds.append({"status": effect, "amount": maxi(0, int(effect.get("value", 0)))})
	for slot in player_field.slots:
		if slot != null:
			refund_total += slot.process_mana_refund(refund_owner)
	for slot in player2_field.slots:
		if slot != null:
			refund_total += slot.process_mana_refund(refund_owner)
	if refund_total > 0:
		var mana_before := active_field().current_mana
		active_field().add_mana(refund_total)
		var remaining := active_field().current_mana - mana_before
		for refund in observed_refunds:
			var actual := mini(remaining, int(refund.amount))
			remaining -= actual
			record_metric({"kind": "mana_refunded", "status": refund.status, "amount": actual, "target_card": active_field(), "source_player": current_player})
		_log("[Mana+] P%d gains %d mana at turn end (%d/%d)" % [current_player, refund_total, active_field().current_mana, active_field().max_mana])
	for refund in observed_refunds:
		if int(refund.status.get("duration", 0)) <= 0 or int(refund.status.get("value", 0)) <= 0:
			record_metric({"kind": "status_expired", "status": refund.status})

	# On-turn-end passives for the current player's field.
	var ending_board: BattleField = player_field if current_player == 1 else player2_field
	_stats_listen(current_player)
	for i in range(ending_board.slots.size()):
		var card: CardData = ending_board.slots[i]
		if card != null and card.is_alive():
			SkillEngine.trigger_skills(SkillEngine.TRIGGER_ON_TURN_END, card, make_skill_context_for_player(current_player, i, -1))
	_stats_unlisten()

	# Current-turn reductions—including Charm's zero-cost override—expire only
	# after turn-end passives have resolved. Permanent reductions remain.
	for card: CardData in active_hand():
		card.clear_turn_cost_reduction()
	var face_exposed := not opponent_field().has_selectable_units()

	# Tick buffs owned by the next player, then clear that player's old shields.
	# Shields gained this turn stay through the opponent's turn and expire when
	# their owner is about to act again.
	var tick_owner: int = 2 if current_player == 1 else 1
	for slot in player_field.slots:
		if slot != null:
			var hp_before: int = slot.hp
			if current_player == 1: slot.tick_poison(Callable(self,"record_metric") if metrics_callable.is_valid() else Callable())
			slot.tick_buffs(tick_owner, Callable(self, "record_metric") if metrics_callable.is_valid() else Callable())
			if tick_owner == 1:
				slot.temp_hp = 0
			if slot.hp != hp_before:
				EventBus.hp_changed.emit(slot, slot.hp - hp_before, slot.hp)
	for slot in player2_field.slots:
		if slot != null:
			var hp_before: int = slot.hp
			if current_player == 2: slot.tick_poison(Callable(self,"record_metric") if metrics_callable.is_valid() else Callable())
			slot.tick_buffs(tick_owner, Callable(self, "record_metric") if metrics_callable.is_valid() else Callable())
			if tick_owner == 2:
				slot.temp_hp = 0
			if slot.hp != hp_before:
				EventBus.hp_changed.emit(slot, slot.hp - hp_before, slot.hp)

	# Empty-field direct damage (turn 2+)
	var result := _process_empty_field_damage(allow_face_mana, face_exposed)
	for card in active_field().slots:
		if card != null: card.finish_stun_turn()
	return result


func _process_empty_field_damage(allow_face_mana: bool = true, face_exposed: Variant = null) -> Dictionary:
	if turn_number < 2:
		return {}

	var af := active_field()
	var can_hit_player: bool = not opponent_field().has_selectable_units() if face_exposed == null else face_exposed
	if not can_hit_player:
		return {}

	var damaged_player: int = 3 - current_player
	var attacking_field: BattleField = af
	var attacking_player: int = current_player

	var total_dmg := 0
	var cards_hit: Array = []
	var resources_before := {"points":af.action_points,"mana":af.get_total_mana()}
	var plan := _automatic_attack_plan(af.get_total_mana(), allow_face_mana, can_hit_player)
	for hit in plan.cards_hit:
		var i := int(hit.slot)
		var card = attacking_field.slots[i]
		if card != null and card.is_alive() and not card.has_acted:
			if card.has_stun():
				continue
			if not _pay_action(card, "automatic"):
				continue
			card.has_acted = true
			card.has_attacked = true
			var dmg :int= card.effective_atk()
			total_dmg += dmg
			cards_hit.append({"card_name": card.card_name, "dmg": dmg, "slot": i, "player": attacking_player,"resources_after":{"points":af.action_points,"mana":af.get_total_mana()}})

	if total_dmg > 0:
		var remaining_hp := opponent_field().player_hp
		var damaging_attacks := 0
		for hit in cards_hit:
			var damage := mini(maxi(0, int(hit.dmg)), remaining_hp)
			remaining_hp -= damage
			if damage > 0:
				damaging_attacks += 1
			_record_attack_metric(attacking_field.slots[int(hit.slot)],opponent_field(),damage)
		if damaged_player == 1:
			player_field.damage_player(total_dmg)
		else:
			player2_field.damage_player(total_dmg)
		_stats_add(attacking_player, "hero_damage", total_dmg)
		_log("[EmptyField] P%d board empty — P%d deals %d direct damage to P%d" % [damaged_player, attacking_player, total_dmg, damaged_player])
		if damaging_attacks > 0 and battle_config.get("face_damage_compensation", false):
			var mana := damaging_attacks * int(battle_config.get("face_damage_compensation_mana", PlayerData.DEFAULT_FACE_DAMAGE_COMPENSATION_MANA))
			opponent_field().add_temp_mana(mana)
			_log("[FaceComp] P%d gains %d temp mana (compensation for %d damaging attacks)" % [damaged_player, mana, damaging_attacks])

	return {
		"triggered": true,
		"damaged_player": damaged_player,
		"total_damage": total_dmg,
		"attacking_player": attacking_player,
		"cards_hit": cards_hit,
		"resources_before": resources_before,
	}


func preview_end_turn_attacks(allow_face_mana: bool = true) -> Dictionary:
	# Read-only quote: temporary Elixir expires before automatic attacks.
	# Refunds are deterministic; authored turn-end skills and ticking buffs may
	# change the quoted board, so expose that uncertainty instead of running UGC.
	var refund := 0
	var conditional := false
	for field in [player_field, player2_field]:
		for card in field.slots:
			if card == null:
				continue
			for status in card.status_effects:
				var buff := str(status.get("buff_id", ""))
				if int(status.get("owner", 0)) == current_player and buff == SkillEngine.BUFF_MANA_REFUND:
					refund += maxi(0, int(status.get("value", 0)))
				elif (buff == SkillEngine.BUFF_POISON and field == active_field()) or (int(status.get("owner", 0)) == 3-current_player and buff not in [SkillEngine.BUFF_MANA_REFUND, SkillEngine.BUFF_STUN, SkillEngine.BUFF_POISON]):
					conditional = true
			if field == active_field() and card.is_alive():
				for skill in card.skills:
					if str(skill.get("trigger", "")) == SkillEngine.TRIGGER_ON_TURN_END:
						conditional = true
	var plan := _automatic_attack_plan(mini(active_field().max_mana, active_field().current_mana + refund), allow_face_mana)
	plan["conditional"] = conditional
	return plan


func _automatic_attack_plan(available_mana: int, allow_face_mana: bool = true, face_exposed: Variant = null) -> Dictionary:
	var field := active_field()
	var points := field.action_points
	var actions := field.actions_taken
	var plan := {"cards_hit": [], "blocked": [], "total_damage": 0, "points": 0, "mana": 0, "reason": "ready"}
	if turn_number < 2:
		plan.reason = "first_turn"
		return plan
	var can_hit_player: bool = not opponent_field().has_selectable_units() if face_exposed == null else face_exposed
	if not can_hit_player:
		plan.reason = "defended"
		return plan
	for slot in range(field.slots.size()):
		var card: CardData = field.slots[slot]
		if card == null or not card.is_alive() or card.has_acted or (card.has_stun()):
			continue
		var payment := _action_payment(actions, points, available_mana)
		if not allow_face_mana and int(payment.mana) > 0:
			plan.blocked.append(slot)
			continue
		var hit := {"slot": slot, "card_name": card.card_name, "dmg": card.effective_atk(), "points": payment.points, "mana": payment.mana}
		if not payment.ok:
			plan.blocked.append(hit)
			continue
		plan.cards_hit.append(hit)
		plan.total_damage += hit.dmg
		plan.points += payment.points
		plan.mana += payment.mana
		points -= int(payment.points)
		available_mana -= int(payment.mana)
		actions += 1
	return plan


func start_new_turn() -> void:
	is_player_turn = true
	effective_actions_this_turn = 0
	current_player = 2 if current_player == 1 else 1

	var cfg: Dictionary = battle_config
	var mana_per_turn: int = cfg.get("mana_per_turn", PlayerData.DEFAULT_BATTLE_CONFIG["mana_per_turn"])
	var draw_amount: int = cfg.get("draw_per_turn", 2)
	if first_switch:
		# The second player gets catch-up benefits on their first turn.
		var refill := first_response_resources(cfg, mana_per_turn, draw_amount)
		active_field().add_mana(refill.x)
		draw_amount = refill.y
		first_switch = false
	else:
		# Both players receive the base amount in round two, their first regular refill.
		var upcoming_round := turn_number + int(current_player == starting_player)
		var mana_increment := int(cfg.get("mana_increment", 0))
		active_field().add_mana(mana_per_turn + mana_increment * maxi(0, upcoming_round - 2))

	for slot in player_field.slots:
		if slot != null:
			slot.has_acted = false
			slot.has_attacked = false
			slot.summoned_this_turn = false
			slot.skills_used.clear()
	for slot in player2_field.slots:
		if slot != null:
			slot.has_acted = false
			slot.has_attacked = false
			slot.summoned_this_turn = false
			slot.skills_used.clear()

	if current_player == starting_player:
		turn_number += 1

	# Only a turn that starts with Stun counts toward its duration.
	var active_board: BattleField = player_field if current_player == 1 else player2_field
	for slot in active_board.slots:
		if slot != null and slot.has_stun():
			slot.has_acted = true
			slot.has_attacked = true
			slot.begin_stun_turn()

	# On-turn-start passives for the current player's field.
	_stats_listen(current_player)
	for i in range(active_board.slots.size()):
		var card: CardData = active_board.slots[i]
		if card != null and card.is_alive():
			SkillEngine.trigger_skills(SkillEngine.TRIGGER_ON_TURN_START, card, make_skill_context_for_player(current_player, i, -1))
	_stats_unlisten()

	if draw_callable.is_valid():
		draw_callable.call(draw_amount)
	else:
		draw_cards(draw_amount)
	reset_action_budget(current_player)

	_log("Turn %d start! Player %d (Mana: %d/%d)" % [turn_number, current_player, active_field().current_mana, active_field().max_mana])
	EventBus.turn_started.emit(turn_number)


# ============================================
# Win/lose
# ============================================

func check_game_over() -> String:
	if player_field.player_hp <= 0:
		return "p2_wins"
	if player2_field.player_hp <= 0:
		return "p1_wins"
	return ""
