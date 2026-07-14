extends RefCounted

var player_field: BattleField
var player2_field: BattleField
var player_hand: Array = []
var player2_hand: Array = []
var is_player_turn: bool = true
var turn_number: int = 1
var current_player: int = 1  # 1 or 2
var draw_callable: Callable
var first_switch: bool = true
var shared_deck: Array = []
var shared_discard: Array = []
var game_rng := RandomNumberGenerator.new()
var state_revision: int = 0


func init_game(draw_cb: Callable) -> void:
	draw_callable = draw_cb
	if NetworkManager.is_online:
		game_rng.seed = 4567
	else:
		game_rng.randomize()
	player_field = BattleField.new("P1", 30, 10)
	player2_field = BattleField.new("P2", 30, 10)
	_build_shared_deck()
	draw_cards(3, player_hand)
	draw_cards(3, player2_hand)
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
	}


func apply_initial_state(state: Dictionary) -> void:
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
	game_rng.seed = int(state.get("rng_seed", game_rng.seed))
	game_rng.state = int(state.get("rng_state", game_rng.state))


func _serialize_field(field: BattleField) -> Dictionary:
	return {
		"player_hp": field.player_hp,
		"max_player_hp": field.max_player_hp,
		"current_mana": field.current_mana,
		"max_mana": field.max_mana,
		"slots": _serialize_slots(field.slots),
	}


func _apply_field_state(field: BattleField, state: Dictionary) -> void:
	if state.is_empty():
		return
	field.player_hp = int(state.get("player_hp", field.player_hp))
	field.max_player_hp = int(state.get("max_player_hp", field.max_player_hp))
	field.current_mana = int(state.get("current_mana", field.current_mana))
	field.max_mana = int(state.get("max_mana", field.max_mana))
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
	if NetworkManager.is_online:
		_shuffle_shared_deck()
	else:
		shared_deck.shuffle()


func _shuffle_shared_deck() -> void:
	for i in range(shared_deck.size() - 1, 0, -1):
		var j := game_rng.randi_range(0, i)
		var temp = shared_deck[i]
		shared_deck[i] = shared_deck[j]
		shared_deck[j] = temp


func active_field() -> BattleField:
	return player_field if current_player == 1 else player2_field


func opponent_field() -> BattleField:
	return player2_field if current_player == 1 else player_field


func active_hand() -> Array:
	return player_hand if current_player == 1 else player2_hand


func make_skill_context(source_slot: int = -1, target_slot: int = -1) -> Dictionary:
	return make_skill_context_for_player(current_player, source_slot, target_slot)


func make_skill_context_for_player(player: int, source_slot: int = -1, target_slot: int = -1) -> Dictionary:
	var player_field_for_context = player_field if player == 1 else player2_field
	var enemy_field_for_context = player2_field if player == 1 else player_field
	var active_hand_for_context = player_hand if player == 1 else player2_hand
	return {
		"player_field": player_field_for_context,
		"enemy_field": enemy_field_for_context,
		"source_slot": source_slot,
		"target_slot": target_slot,
		"draw_callable": Callable(self, "draw_cards_for_player").bind(player),
		"current_player": player,
		"active_hand": active_hand_for_context,
		"rng": game_rng,
		"turn_number": turn_number,
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
			print("Hand full!")
			break
		if shared_deck.is_empty() and not shared_discard.is_empty():
			print("Deck empty! Shuffling discard pile into deck...")
			shared_deck = shared_discard.duplicate()
			shared_discard.clear()
			if NetworkManager.is_online:
				_shuffle_shared_deck()
			else:
				shared_deck.shuffle()
		if shared_deck.is_empty():
			break
		var card_data = shared_deck.pop_front()
		hand.append(card_data)
		drawn.append(card_data)
		print("Drew: %s" % card_data.card_name)
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
		print("Discarded from hand: %s" % card_data.card_name)
		return true
	# Check battlefield
	var field = active_field()
	for i in range(5):
		if field.slots[i] == card_data:
			card_data.reset_to_base()
			shared_discard.append(card_data)
			field.slots[i] = null
			active_field().add_mana(1)
			print("Discarded from field: %s" % card_data.card_name)
			return true
	return false


# ============================================
# Summon / skill activation
# ============================================

func summon_card(card_data: CardData, slot_index: int) -> bool:
	if not active_field().summon_card(card_data, slot_index):
		return false
	active_hand().erase(card_data)
	return true


func trigger_summon_skills(source_slot: int, target_slot: int, skill_index: int) -> void:
	# Fires a single on_summon skill by index WITHOUT marking has_acted.
	# on_summon skills are now manually activated (only on the summon turn);
	# Main._on_skill_activated routes them here so they don't consume the
	# card's attack/action for the turn, unlike trigger_activate_skills.
	var card: CardData = active_field().slots[source_slot]
	if card != null:
		SkillEngine.trigger_single_skill(card, skill_index, make_skill_context(source_slot, target_slot))


func trigger_activate_skills(source_slot: int, target_slot: int, skill_index: int) -> void:
	var card: CardData = active_field().slots[source_slot]
	if card != null:
		SkillEngine.trigger_single_skill(card, skill_index, make_skill_context(source_slot, target_slot))
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
		SkillEngine.trigger_skills(SkillEngine.TRIGGER_ON_ACTIVATE, card, make_skill_context(slot_index, -1))
		card.has_acted = true
		return skill.get("skill_name", "")
	return ""


# ============================================
# Attack
# ============================================

func execute_attack(atk_slot: int, def_slot: int) -> Dictionary:
	if turn_number <= 1:
		print("Turn 1: attacks are not allowed!")
		return {}
	var attacker: CardData = active_field().slots[atk_slot]
	var victim: CardData = opponent_field().slots[def_slot]
	if attacker == null or victim == null:
		return {}
	if attacker.is_silenced():
		print("%s is silenced and cannot attack!" % attacker.card_name)
		return {}
	var atk_dmg: int = attacker.effective_atk()
	print("%s attacks %s! (%d dmg)" % [attacker.card_name, victim.card_name, atk_dmg])
	victim.take_damage(atk_dmg)
	EventBus.hp_changed.emit(victim, -atk_dmg, victim.hp)
	SkillEngine.trigger_skills(SkillEngine.TRIGGER_ON_DAMAGED, victim, make_skill_context(def_slot, atk_slot))
	attacker.has_acted = true
	attacker.has_attacked = true
	if not victim.is_alive():
		active_field().add_mana(1)
		print("  Kill! Mana +1")
	EventBus.attack_declared.emit(attacker, victim, atk_slot, def_slot)
	var thorns: int = victim.get_thorns_damage()
	if thorns > 0:
		print("  [Thorns] %s reflects %d dmg" % [victim.card_name, thorns])
		attacker.take_damage(thorns)
		EventBus.hp_changed.emit(attacker, -thorns, attacker.hp)
	SkillEngine.trigger_skills(SkillEngine.TRIGGER_ON_ATTACK, attacker, make_skill_context(atk_slot, def_slot))
	return { "attacker_died": not attacker.is_alive(), "victim_died": not victim.is_alive() }


# ============================================
# Death cleanup
# ============================================

func cleanup_deaths() -> Dictionary:
	var p1_dead: Array = []
	var p2_dead: Array = []
	for i in range(5):
		if player_field.slots[i] != null and not player_field.slots[i].is_alive():
			print("%s died!" % player_field.slots[i].card_name)
			SkillEngine.trigger_skills(SkillEngine.TRIGGER_ON_DEATH, player_field.slots[i], make_skill_context_for_player(1, i, -1))
			player_field.slots[i].reset_to_base()
			shared_discard.append(player_field.slots[i])
			player_field.slots[i] = null
			p1_dead.append(i)
		if player2_field.slots[i] != null and not player2_field.slots[i].is_alive():
			print("%s died!" % player2_field.slots[i].card_name)
			SkillEngine.trigger_skills(SkillEngine.TRIGGER_ON_DEATH, player2_field.slots[i], make_skill_context_for_player(2, i, -1))
			player2_field.slots[i].reset_to_base()
			shared_discard.append(player2_field.slots[i])
			player2_field.slots[i] = null
			p2_dead.append(i)
	return { "p1": p1_dead, "p2": p2_dead }


# ============================================
# Turn system
# ============================================

func end_player_turn() -> Dictionary:
	is_player_turn = false
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
		print("[Mana+] P%d gains %d mana at turn end (%d/%d)" % [current_player, refund_total, active_field().current_mana, active_field().max_mana])

	# Tick all buffs and reset temp HP
	var tick_owner: int = 2 if current_player == 1 else 1
	for slot in player_field.slots:
		if slot != null:
			var hp_before: int = slot.hp
			slot.tick_buffs(tick_owner)
			slot.temp_hp = 0
			if slot.hp != hp_before:
				EventBus.hp_changed.emit(slot, slot.hp - hp_before, slot.hp)
	for slot in player2_field.slots:
		if slot != null:
			var hp_before: int = slot.hp
			slot.tick_buffs(tick_owner)
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
		print("[EmptyField] P%d board empty — P%d deals %d direct damage to P%d" % [damaged_player, attacking_player, total_dmg, damaged_player])

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

	var draw_amount: int = 2
	if first_switch:
		# First P1→P2 switch: half benefits as catch-up
		active_field().add_mana(1)
		draw_amount = 1
		first_switch = false
	else:
		active_field().reset_mana_for_new_turn()

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

	draw_cards(draw_amount)

	print("Turn %d start! Player %d (Mana: %d/%d)" % [turn_number, current_player, active_field().current_mana, active_field().max_mana])
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
