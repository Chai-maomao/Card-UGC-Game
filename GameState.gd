extends RefCounted

const SpellRules = preload("res://SpellRules.gd")
const ParasiteRules = preload("res://ParasiteRules.gd")
const GameplayRandom = preload("res://GameplayRng.gd")
const Schema = preload("res://DataSchema.gd")

var player_field: BattleField
var player2_field: BattleField
var player_hand: Array = []
var player2_hand: Array = []
var is_player_turn: bool = true
var turn_number: int = 1
var current_player: int = 1  # 1 or 2
var draw_callable: Callable
var first_switch: bool = true
var battle_config: Dictionary = {}
var shared_deck: Array = []
var shared_discard: Array = []
var game_rng := RandomNumberGenerator.new()
var state_revision: int = 0
var quiet: bool = false
var allow_first_turn_attacks: bool = false
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
		print(message)


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


func init_game(draw_cb: Callable, requested_seed: Variant = null) -> void:
	draw_callable = draw_cb
	if requested_seed != null:
		game_rng.seed = int(requested_seed)
	elif NetworkManager.is_online:
		game_rng.seed = 4567
	else:
		game_rng.randomize()
	battle_config = PlayerData.battle_config.duplicate(true)
	var cfg: Dictionary = battle_config
	var start_hp: int = cfg.get("starting_hp", 30)
	player_field = BattleField.new("P1", start_hp, 10)
	player2_field = BattleField.new("P2", start_hp, 10)
	player_field.quiet = quiet
	player2_field.quiet = quiet
	_build_shared_deck()
	draw_cards(cfg.get("draw_per_turn", 2) + 1, player_hand)  # +1 for initial hand
	draw_cards(cfg.get("draw_per_turn", 2) + 1, player2_hand)
	current_player = 1
	EventBus.game_started.emit()


func export_initial_state() -> Dictionary:
	return {
		"player_field": _serialize_field(player_field),
		"player2_field": _serialize_field(player2_field),
		"player_hand": _serialize_card_array(player_hand),
		"player2_hand": _serialize_card_array(player2_hand),
		"shared_deck": _serialize_card_array(shared_deck),
		"shared_discard": _serialize_card_array(shared_discard),
		"current_player": current_player,
		"turn_number": turn_number,
		"is_player_turn": is_player_turn,
		"first_switch": first_switch,
		"state_revision": state_revision,
		"rng_seed": game_rng.seed,
		"rng_state": game_rng.state,
		"stats": {1: get_stats(1).duplicate(true), 2: get_stats(2).duplicate(true)},
		"battle_config": battle_config.duplicate(true),
		"allow_first_turn_attacks": allow_first_turn_attacks,
	}


func apply_initial_state(state: Dictionary) -> void:
	var envelope := {"schema": 1, "room_code": "STATE", "player": 1, "state": state}
	var state_errors := Schema.validate(Schema.KIND_MATCH_SNAPSHOT, envelope)
	if not state_errors.is_empty():
		push_warning("Rejected invalid battle state: %s" % [state_errors])
		return
	# Sync battle_config from authority so both players use the same rules.
	var config: Dictionary = state.get("battle_config", {})
	if not config.is_empty():
		battle_config = config.duplicate(true)
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
	turn_number = int(state.get("turn_number", 1))
	is_player_turn = bool(state.get("is_player_turn", true))
	first_switch = bool(state.get("first_switch", true))
	state_revision = int(state.get("state_revision", state_revision))
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
	if NetworkManager.is_online and not NetworkManager.is_authority():
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
		"current_player": player,
		"active_hand": active_hand_for_context,
		"enemy_hand": enemy_hand_for_context,
		"discard_pile": shared_discard,
		"shared_deck": shared_deck,
		"rng": game_rng,
		"turn_number": turn_number,
		"quiet": quiet,
	}


# ============================================
# Drawing / discard
# ============================================

func draw_cards_for_player(amount: int, player: int) -> Array:
	var hand = player_hand if player == 1 else player2_hand
	return draw_cards(amount, hand)


func draw_cards(amount: int, hand: Array = active_hand()) -> Array:
	var drawn: Array = []
	for _k in range(amount):
		if hand.size() >= SkillEngine.MAX_HAND_SIZE:
			_log("Hand full!")
			break
		if shared_deck.is_empty() and not shared_discard.is_empty():
			_log("Deck empty! Shuffling discard pile into deck...")
			shared_deck = shared_discard.duplicate()
			shared_discard.clear()
			_shuffle_shared_deck()
		if shared_deck.is_empty():
			break
		var card_data = shared_deck.pop_front()
		hand.append(card_data)
		drawn.append(card_data)
		_log("Drew: %s" % card_data.card_name)
	if not drawn.is_empty():
		_stats_add(1 if hand == player_hand else 2, "cards_drawn", drawn.size())
	return drawn


func discard_card(card_data: CardData) -> bool:
	# Check hand first, then battlefield
	var hand = active_hand()
	var idx: int = hand.find(card_data)
	if idx >= 0:
		hand.remove_at(idx)
		card_data.reset_to_base()
		shared_discard.append(card_data)
		active_field().add_mana(1)
		_log("Discarded from hand: %s" % card_data.card_name)
		return true
	# Check battlefield
	var field = active_field()
	for i in range(5):
		if field.slots[i] == card_data:
			ParasiteRules.release_all_to_discard(card_data, shared_discard)
			card_data.reset_to_base()
			shared_discard.append(card_data)
			field.slots[i] = null
			active_field().add_mana(1)
			_log("Discarded from field: %s" % card_data.card_name)
			return true
	return false


# ============================================
# Summon / skill activation / spell cast
# ============================================

func summon_card(card_data: CardData, slot_index: int) -> bool:
	if card_data != null and (card_data.is_spell() or card_data.is_parasite()):
		return false
	var summoner := current_player
	if not active_field().summon_card(card_data, slot_index):
		return false
	_stats_add(summoner, "summons", 1)
	_stats_add(summoner, "mana_spent", card_data.cost)
	if card_data.zero_cost_until_deploy:
		card_data.cost = card_data.base_cost
		card_data.zero_cost_until_deploy = false
	active_hand().erase(card_data)
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
	var attacher := current_player
	active_field().spend_mana(card.cost)
	hand.remove_at(hand_index)
	ParasiteRules.attach(card, target)
	_stats_add(attacher, "parasites", 1)
	_stats_add(attacher, "mana_spent", card.cost)
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

	var caster := current_player
	var field := active_field()
	field.spend_mana(card.cost)
	hand.remove_at(hand_index)

	var ctx := make_skill_context(-1, target_slot, target_player)
	var normalized_skill: Dictionary = cast_check.get("skill", {})
	if skill_index >= 0 and skill_index < card.skills.size():
		card.skills[skill_index] = normalized_skill
	_stats_listen(caster)
	SkillEngine.trigger_single_skill(card, skill_index, ctx)
	_stats_unlisten()

	_stats_add(caster, "spells", 1)
	_stats_add(caster, "mana_spent", card.cost)
	card.reset_to_base()
	shared_discard.append(card)
	return true


func trigger_summon_skills(source_slot: int, target_slot: int, skill_index: int, target_player: int = 0) -> void:
	# Fires a single on_summon skill by index WITHOUT marking has_acted.
	# on_summon skills are now manually activated (only on the summon turn);
	# Main._on_skill_activated routes them here so they don't consume the
	# card's attack/action for the turn, unlike trigger_activate_skills.
	var card: CardData = active_field().slots[source_slot]
	if card != null:
		var actor := current_player
		_stats_listen(actor)
		SkillEngine.trigger_single_skill(card, skill_index, make_skill_context(source_slot, target_slot, target_player))
		_stats_unlisten()


func trigger_activate_skills(source_slot: int, target_slot: int, skill_index: int, target_player: int = 0) -> void:
	var card: CardData = active_field().slots[source_slot]
	if card != null:
		var actor := current_player
		_stats_listen(actor)
		SkillEngine.trigger_single_skill(card, skill_index, make_skill_context(source_slot, target_slot, target_player))
		_stats_unlisten()
		card.has_acted = true


func activate_skill(slot_index: int, skill_index: int) -> String:
	var card: CardData = active_field().slots[slot_index]
	if card == null or card.has_acted:
		return ""
	if card.is_silenced():
		return ""
	if skill_index >= card.skills.size():
		return ""
	var skill: Dictionary = card.skills[skill_index]
	var trigger: String = skill.get("trigger", "")
	if trigger == SkillEngine.TRIGGER_ON_ACTIVATE:
		var actor := current_player
		_stats_listen(actor)
		SkillEngine.trigger_skills(SkillEngine.TRIGGER_ON_ACTIVATE, card, make_skill_context(slot_index, -1))
		_stats_unlisten()
		card.has_acted = true
		return skill.get("skill_name", "")
	return ""


# ============================================
# Attack
# ============================================

func execute_attack(atk_slot: int, def_slot: int) -> Dictionary:
	if turn_number <= 1 and not allow_first_turn_attacks:
		_log("Turn 1: attacks are not allowed!")
		return {}
	var attacker: CardData = active_field().slots[atk_slot]
	var victim: CardData = opponent_field().slots[def_slot]
	if attacker == null or victim == null:
		return {}
	if attacker.has_acted:
		_log("%s already acted this turn!" % attacker.card_name)
		return {}
	if attacker.is_silenced() and not attacker.attack_ignores_silence:
		_log("%s is silenced and cannot attack!" % attacker.card_name)
		return {}
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
		EventBus.parasite_damage_resolved.emit(victim, parasite, declared_dmg, int(parasite_result.get("absorbed", 0)), bool(parasite_result.get("destroyed", false)))
	var temp_hp_before: int = victim.temp_hp
	var actual_dmg: int = victim.take_damage_without_reduction(atk_dmg)
	EventBus.damage_resolved.emit(attacker, victim, declared_dmg, actual_dmg, reduction_pct, temp_hp_before, "attack")
	EventBus.hp_changed.emit(victim, -actual_dmg, victim.hp)
	if victim.is_alive():
		var victim_ctx := make_skill_context_for_player(3 - current_player, def_slot, atk_slot)
		SkillEngine.trigger_skills(SkillEngine.TRIGGER_ON_DAMAGED, victim, victim_ctx)
		SkillEngine.trigger_skills(SkillEngine.TRIGGER_ON_ATTACKED, victim, victim_ctx)
		ParasiteRules.trigger_host_passives(SkillEngine.TRIGGER_ON_DAMAGED, victim, victim_ctx)
	attacker.has_acted = true
	attacker.has_attacked = true
	if not victim.is_alive():
		active_field().add_mana(1)
		_log("  Kill! Mana +1")
	EventBus.attack_declared.emit(attacker, victim, atk_slot, def_slot)
	var thorns: int = thorns_before_damage
	if thorns > 0:
		_log("  [Thorns] %s reflects %d dmg" % [victim.card_name, thorns])
		var attacker_reduction: int = attacker.get_damage_reduction()
		var attacker_temp_before: int = attacker.temp_hp
		var thorns_actual: int = attacker.take_damage(thorns)
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
			p2_dead.append(i)
			if death_comp:
				draw_cards_for_player(1, 2)
				_log("[DeathComp] P2 draws 1 card (compensation for %s)" % dead_card.card_name)
	return { "p1": p1_dead, "p2": p2_dead }


# ============================================
# Turn system
# ============================================

func end_player_turn() -> Dictionary:
	is_player_turn = false
	# Clear current player's temp mana (vanishes at turn end)
	active_field().clear_temp_mana()
	# Reset charmed card costs
	for card in player_hand:
		if card != null: card.reset_charm_cost()
	for card in player2_hand:
		if card != null: card.reset_charm_cost()

	var refund_owner: int = current_player
	var refund_total: int = 0
	for slot in player_field.slots:
		if slot != null:
			refund_total += slot.process_mana_refund(refund_owner)
	for slot in player2_field.slots:
		if slot != null:
			refund_total += slot.process_mana_refund(refund_owner)
	if refund_total > 0:
		active_field().add_mana(refund_total)
		_log("[Mana+] P%d gains %d mana at turn end (%d/%d)" % [current_player, refund_total, active_field().current_mana, active_field().max_mana])

	# On-turn-end passives for the current player's field.
	var ending_board: BattleField = player_field if current_player == 1 else player2_field
	_stats_listen(current_player)
	for i in range(ending_board.slots.size()):
		var card: CardData = ending_board.slots[i]
		if card != null and card.is_alive():
			SkillEngine.trigger_skills(SkillEngine.TRIGGER_ON_TURN_END, card, make_skill_context_for_player(current_player, i, -1))
	_stats_unlisten()

	# Tick buffs owned by the next player, then clear that player's old shields.
	# Shields gained this turn stay through the opponent's turn and expire when
	# their owner is about to act again.
	var tick_owner: int = 2 if current_player == 1 else 1
	for slot in player_field.slots:
		if slot != null:
			var hp_before: int = slot.hp
			slot.tick_buffs(tick_owner)
			if tick_owner == 1:
				slot.temp_hp = 0
			if slot.hp != hp_before:
				EventBus.hp_changed.emit(slot, slot.hp - hp_before, slot.hp)
	for slot in player2_field.slots:
		if slot != null:
			var hp_before: int = slot.hp
			slot.tick_buffs(tick_owner)
			if tick_owner == 2:
				slot.temp_hp = 0
			if slot.hp != hp_before:
				EventBus.hp_changed.emit(slot, slot.hp - hp_before, slot.hp)

	# Empty-field direct damage (turn 2+)
	var result := _process_empty_field_damage()
	return result


func _field_is_empty(field: BattleField) -> bool:
	for i in range(5):
		if field.slots[i] != null and field.slots[i].is_alive():
			return false
	return true


func _process_empty_field_damage() -> Dictionary:
	if turn_number < 2:
		return {}

	var af := active_field()
	var of := opponent_field()
	var opp_empty := _field_is_empty(of)

	if not opp_empty:
		return {}

	var damaged_player: int = 3 - current_player
	var attacking_field: BattleField = af
	var attacking_player: int = current_player

	var total_dmg := 0
	var cards_hit: Array = []
	for i in range(5):
		var card = attacking_field.slots[i]
		if card != null and card.is_alive() and not card.has_acted:
			var dmg :int= card.effective_atk()
			total_dmg += dmg
			cards_hit.append({"card_name": card.card_name, "dmg": dmg, "slot": i, "player": attacking_player})

	if total_dmg > 0:
		if damaged_player == 1:
			player_field.damage_player(total_dmg)
		else:
			player2_field.damage_player(total_dmg)
		_stats_add(attacking_player, "hero_damage", total_dmg)
		_log("[EmptyField] P%d board empty — P%d deals %d direct damage to P%d" % [damaged_player, attacking_player, total_dmg, damaged_player])
		# Face damage compensation: 1 temp mana per attacking card
		if battle_config.get("face_damage_compensation", false):
			var attacker_count: int = cards_hit.size()
			if attacker_count > 0:
				if damaged_player == 1:
					player_field.add_temp_mana(attacker_count)
				else:
					player2_field.add_temp_mana(attacker_count)
				_log("[FaceComp] P%d gains %d temp mana (compensation for %d attacking cards)" % [damaged_player, attacker_count, attacker_count])

	return {
		"triggered": true,
		"damaged_player": damaged_player,
		"total_damage": total_dmg,
		"attacking_player": attacking_player,
		"cards_hit": cards_hit,
	}


func start_new_turn() -> void:
	is_player_turn = true
	current_player = 2 if current_player == 1 else 1

	var cfg: Dictionary = battle_config
	var mana_per_turn: int = cfg.get("mana_per_turn", 2)
	var draw_amount: int = cfg.get("draw_per_turn", 2)
	if first_switch:
		# First P1→P2 switch: half benefits as catch-up + extra compensation
		var extra_mana: int = cfg.get("second_extra_mana", 0)
		var extra_cards: int = cfg.get("second_extra_cards", 0)
		active_field().add_mana(max(1, mana_per_turn / 2) + extra_mana)
		draw_amount = max(1, draw_amount / 2) + extra_cards
		first_switch = false
	else:
		# Standard mana restoration per turn
		active_field().current_mana = min(active_field().max_mana, active_field().current_mana + mana_per_turn)

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

	if current_player == 1:
		turn_number += 1

	# Stun: stunned cards skip their actions this turn (buff consumed once).
	var active_board: BattleField = player_field if current_player == 1 else player2_field
	for slot in active_board.slots:
		if slot != null and slot.has_stun():
			slot.has_acted = true
			slot.consume_stun()

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
