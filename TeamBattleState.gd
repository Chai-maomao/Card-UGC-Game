extends "res://GameState.gd"

var fields: Dictionary = {}
var hands: Dictionary = {}
var teams: Dictionary = {}
var _seats: Array[int] = []
var _starting_seat := 1
var active_seat := 1
var winner := 0 # 1 and 2 are team ids, 3 is a draw.
var _paired: Array[int] = [1, 2]
var _choices: Array[Dictionary] = []
var _directed_action: Dictionary = {}
var _last_action: Dictionary = {}
var _selected_skill_seat := 0
var _selected_spell_field: BattleField


func start_match(decks: Dictionary, playing_order: Array[int], seed_value: int, rules: Dictionary = {}) -> void:
	var seat_count := playing_order.size()
	@warning_ignore("integer_division")
	var first_team_size: int = seat_count / 2
	_starting_seat = playing_order[0]
	active_seat = _starting_seat
	game_rng.seed = seed_value
	quiet = true
	battle_config = PlayerData.DEFAULT_BATTLE_CONFIG.duplicate(true) if rules.is_empty() else rules.duplicate(true)
	for index in seat_count:
		teams[playing_order[index]] = 1 if index < first_team_size else 2
	for seat in range(1, seat_count + 1):
		_seats.append(seat)
		var small_team: bool = seat_count % 2 == 1 and teams[seat] == 1
		var hp := int(battle_config.get("starting_hp", 30))
		if seat_count == 3:
			hp = maxi(1, roundi(hp * (1.5 if small_team else 25.0 / 30.0)))
		elif seat_count == 5:
			hp = maxi(1, roundi(hp * (37.0 / 30.0 if small_team else 26.0 / 30.0)))
		var field := BattleField.new("P%d" % seat, hp, 10)
		if small_team:
			field.current_mana = 6
		field.quiet = true
		fields[seat] = field
		hands[seat] = []
		for data: Dictionary in decks[seat]:
			shared_deck.append(PlayerData.deserialize_card(data))
	_shuffle_shared_deck()
	for seat: int in _seats:
		var rivals := opponents_of(seat)
		if fields[seat].player_hp <= 0 or rivals.is_empty():
			continue
		_pair(seat, rivals.front())
		var opening_count := opening_hand_size(battle_config) if seat_count == 2 else (4 if _is_small_team(seat) else 3)
		draw_cards_for_player(opening_count, 1)
		cleanup_deaths()
		reset_action_budget(1)
	_finish_resolution()
	if winner == 0:
		_pair(active_seat, opponents_of(active_seat).front())


func _pair(seat: int, rival: int) -> void:
	# The duel rules resolve each interaction between its participants. Keep
	# the third player's state separate, and keep status ownership by seat.
	_paired = [seat, rival]
	player_field = fields[seat]
	player2_field = fields[rival]
	player_hand = hands[seat]
	player2_hand = hands[rival]
	current_player = 1


func make_skill_context_for_player(player: int, source_slot: int = -1, target_slot: int = -1, target_player: int = 0) -> Dictionary:
	var context := super.make_skill_context_for_player(player, source_slot, target_slot, target_player)
	var seat := _paired[player - 1]
	context["status_owner"] = seat
	context["party_card_choice"] = _queue_choice.bind(seat)
	context["party_reaction"] = _dispatch_party_reaction
	context["party_fields"] = _party_fields.bind(seat)
	context["party_board_change"] = _notify_party_board_change
	context["party_spell_field"] = _selected_spell_field
	var paired_seat := _paired[2 - player]
	if teams[seat] == teams[paired_seat]:
		var rival := _reaction_rival(seat, 0)
		context["enemy_field"] = fields[rival]
		context["enemy_hand"] = hands[rival]
		if target_slot >= 0:
			context["selected_unit_field"] = fields[paired_seat]
	return context


func _party_fields(source: CardData, side: String, fallback: int) -> Array:
	var seat := _seat_of_unit(source)
	if seat == 0:
		seat = fallback
	var allies: Array[BattleField] = []
	var enemies: Array[BattleField] = []
	for candidate: int in _seats:
		var field: BattleField = fields[candidate]
		if field.player_hp <= 0:
			continue
		if teams[candidate] == teams[seat]:
			if candidate == seat:
				allies.push_front(field)
			else:
				allies.append(field)
		elif candidate in _paired:
			enemies.push_front(field)
		else:
			enemies.append(field)
	match side:
		SkillEngine.TARGET_SIDE_ALLY: return allies
		SkillEngine.TARGET_SIDE_ENEMY: return enemies
		_: return enemies + allies


func _notify_party_board_change(kind: String, card: CardData, field: BattleField) -> void:
	var seat: int = fields.find_key(field)
	if seat in _paired:
		notify_board_units_changed(_local_side(seat), kind, card)
		return
	var previous := _paired.duplicate()
	_pair(seat, _reaction_rival(seat, 0))
	notify_board_units_changed(1, kind, card)
	_pair(previous[0], previous[1])


func _seat_of_unit(card: CardData) -> int:
	if card != null:
		for seat: int in fields:
			if card in fields[seat].slots:
				return seat
	return 0


func _reaction_rival(seat: int, source_seat: int) -> int:
	var rivals := opponents_of(seat)
	if rivals.has(source_seat):
		return source_seat
	if not rivals.is_empty():
		return rivals.front()
	for candidate: int in teams:
		if teams[candidate] != teams[seat]:
			return candidate
	return seat


func _dispatch_party_reaction(trigger: String, target: CardData, context: Dictionary) -> bool:
	var reactor := _seat_of_unit(target)
	var source: CardData = context.get("source_card")
	var source_seat := _seat_of_unit(source)
	if reactor == 0 or (reactor in _paired and (source_seat == 0 or source_seat in _paired)):
		return false
	var previous := _paired.duplicate()
	_pair(reactor, _reaction_rival(reactor, source_seat))
	var reaction := context.duplicate()
	reaction.erase("selected_unit_field")
	var cause: BattleField = fields.get(source_seat)
	var target_slot := cause.slots.find(source) if cause != null else -1
	reaction.merge(make_skill_context_for_player(1, player_field.slots.find(target), target_slot), true)
	reaction["reaction_target_card"] = source
	if cause != null:
		reaction["selected_unit_field"] = cause
	SkillEngine.trigger_skills(trigger, target, reaction)
	if trigger == SkillEngine.TRIGGER_ON_DAMAGED:
		ParasiteRules.trigger_host_passives(trigger, target, reaction)
	_pair(previous[0], previous[1])
	return true


func opponents_of(seat: int) -> Array[int]:
	var result: Array[int] = []
	for candidate: int in _seats:
		if teams[seat] != teams[candidate] and fields[candidate].player_hp > 0:
			result.append(candidate)
	return result


func _is_small_team(seat: int) -> bool:
	return _seats.size() % 2 == 1 and teams[seat] == 1


func player_view(seat: int) -> Dictionary:
	var players: Array[Dictionary] = []
	for id: int in _seats:
		var field: BattleField = fields[id]
		var snapshot := _serialize_field(field)
		snapshot.merge({"seat": id, "team": teams[id], "hp": field.player_hp, "max_hp": field.max_player_hp,
			"mana": field.get_total_mana(), "actions": field.action_points, "hand_count": hands[id].size()})
		players.append(snapshot)
	var chooser := int(_choices.front().seat) if not _choices.is_empty() else 0
	var choice: Dictionary = {}
	if seat == chooser:
		choice = _choices.front().duplicate()
		if choice.kind != "enemy_swap":
			choice["cards"] = _serialize_card_array(_choice_cards(choice))
			choice["count"] = mini(int(choice.count), choice.cards.size())
	var visible_deck: Array = []
	if battle_config.get("draw_pile_visible", false):
		visible_deck = shared_deck.duplicate()
		if not battle_config.get("draw_pile_ordered", false):
			visible_deck.sort_custom(func(a: CardData, b: CardData): return a.instance_id < b.instance_id)
	return {"players": players, "hand": _serialize_card_array(hands[seat]), "active": active_seat,
		"round": turn_number, "winner": winner, "revision": state_revision,
		"deck_count": shared_deck.size(), "discard_count": shared_discard.size(),
		"visible_deck": _serialize_card_array(visible_deck), "discard": _serialize_card_array(shared_discard),
		"chooser": chooser, "choice": choice, "directed_action": _directed_action, "last_action": _last_action}


func apply_action(seat: int, expected_revision: int, command: String, source: int, target_seat: int, target_slot: int, skill: int) -> bool:
	if winner != 0 or seat != active_seat or state_revision != expected_revision or not _choices.is_empty() \
			or fields[seat].player_hp <= 0:
		return false
	var opponents := opponents_of(seat)
	if opponents.is_empty():
		return false
	var rival: int = target_seat if opponents.has(target_seat) else opponents.front()
	if command == "summon" and opponents.has(skill):
		rival = skill
	if command in ["attack", "parasite"]:
		if not fields.has(target_seat) or fields[target_seat].player_hp <= 0 or (command == "attack" and target_seat == seat):
			return false
		if target_seat != seat:
			rival = target_seat
	_pair(seat, rival)
	if command in ["cast", "skill"] and target_slot >= 0 and fields.has(target_seat):
		_selected_skill_seat = target_seat
	var applied := false
	var directed := command in ["attack", "parasite"]
	match command:
		"summon":
			if target_seat == seat and _hand_has(source) and target_slot in range(5):
				applied = summon_card(player_hand[source], target_slot)
				if applied:
					_resolve_summon_skills(target_slot)
		"discard":
			applied = _hand_has(source) and discard_card(player_hand[source])
		"discard_field":
			applied = source in range(5) and player_field.slots[source] != null and discard_card(player_field.slots[source])
		"move":
			if target_seat == seat and source in range(5) and target_slot in range(5) and source != target_slot \
					and player_field.slots[source] != null:
				var displaced: CardData = player_field.slots[target_slot]
				player_field.slots[target_slot] = player_field.slots[source]
				player_field.slots[source] = displaced
				applied = true
		"attack":
			applied = not execute_attack(source, target_slot, opponents.has(target_seat)).is_empty()
		"parasite":
			if target_seat in _paired and target_slot in range(5):
				applied = attach_parasite(source, _local_side(target_seat), target_slot)
		"cast":
			if _hand_has(source):
				var spell := SpellRules.spell_skill(player_hand[source])
				directed = SpellRules.needs_target(spell)
				if _valid_skill_target(spell, player_hand[source], target_seat, target_slot):
					if target_slot >= 0 and teams[target_seat] == teams[seat] and fields[target_seat].player_hp > 0:
						_selected_spell_field = fields[target_seat]
					applied = cast_spell(source, 0, target_slot, _local_side(target_seat))
					_selected_spell_field = null
		"skill":
			applied = _apply_skill(source, skill, target_seat, target_slot)
			if applied and source in range(player_field.slots.size()):
				var caster: CardData = player_field.slots[source]
				directed = caster != null and skill in range(caster.skills.size()) and SpellRules.needs_target(caster.skills[skill])
		"end":
			if opponents.has(target_seat):
				_end_seat_turn(skill != 0)
				applied = true
	_selected_skill_seat = 0
	if not applied:
		return false
	_finish_resolution()
	state_revision += 1
	_last_action = {"revision": state_revision, "command": command, "seat": seat, "source": source,
		"target_seat": target_seat, "target_slot": target_slot, "skill": skill}
	_directed_action = {}
	if directed and target_slot in range(5) and fields.has(target_seat):
		_directed_action = {"revision": state_revision, "seat": seat, "source_slot": source if command in ["attack", "skill"] else -1,
			"target_seat": target_seat, "target_slot": target_slot, "attack": command == "attack"}
	return true


func _resolve_summon_skills(slot: int) -> void:
	var original: CardData = player_field.slots[slot]
	if original == null:
		return
	for index in range(original.skills.size()):
		if player_field.slots[slot] != original or not original.is_alive():
			break
		if not _summon_skill_pending(original, index):
			continue
		var skill: Dictionary = original.skills[index]
		if SpellRules.needs_target(skill) and _has_summon_target(skill, original):
			continue
		original.skills_used.append(index)
		trigger_summon_skills(slot, -1, index)
		cleanup_deaths()


func _summon_skill_pending(card: CardData, index: int) -> bool:
	var skill: Dictionary = card.skills[index]
	return skill.get("trigger") == SkillEngine.TRIGGER_ON_SUMMON and card.summoned_this_turn \
		and not card.skills_disabled() and not card.skills_used.has(index) and SkillEngine.has_uses_remaining(card, skill, index) \
		and (turn_number > 1 or not SkillRegistry.skill_changes_enemy_hp_or_presence(skill))


func _queue_choice(choice: Dictionary, seat: int) -> void:
	if _choices.size() >= 128:
		return
	choice["seat"] = seat
	if choice.kind == "deck" and shared_deck.is_empty() and not shared_discard.is_empty():
		shared_deck = shared_discard.duplicate()
		shared_discard.clear()
		_shuffle_shared_deck()
	if not _choice_cards(choice).is_empty():
		_choices.append(choice)


func _choice_cards(choice: Dictionary) -> Array:
	if choice.kind == "cost":
		return hands[choice.seat].filter(func(card: CardData): return card.cost > 0)
	var pile := shared_deck if choice.kind == "deck" else shared_discard
	var look: int = choice.look
	if look <= 0:
		look = int(choice.count) * 2 if choice.kind == "deck" else pile.size()
	return pile.slice(0, mini(look, pile.size()))

func _request_enemy_slot_swap(player: int) -> void:
	var seat := _paired[player - 1]
	var rival := _reaction_rival(seat, _paired[2 - player])
	if _choices.size() < 128 and fields[rival].player_hp > 0 and fields[rival].can_swap_unit_positions():
		_choices.append({"kind": "enemy_swap", "seat": seat, "target_seat": rival, "count": 1})


func _prune_choices() -> void:
	if winner != 0:
		_choices.clear()
		return
	while not _choices.is_empty():
		var first: Dictionary = _choices.front()
		if fields[first.seat].player_hp > 0:
			if first.kind == "enemy_swap":
				var field: BattleField = fields[first.target_seat]
				if field.player_hp > 0 and field.can_swap_unit_positions():
					break
			elif not _choice_cards(first).is_empty():
				break
		_choices.pop_front()


func apply_card_choice(seat: int, expected_revision: int, indices: Array) -> bool:
	if expected_revision != state_revision or _choices.is_empty() or winner != 0:
		return false
	var choice: Dictionary = _choices.front()
	if choice.seat != seat or indices.size() > int(choice.count):
		return false
	if choice.kind == "enemy_swap":
		var field: BattleField = fields[choice.target_seat]
		if not indices.is_empty():
			if not indices[0] is int:
				return false
			var pair := decode_enemy_slot_pair(indices[0], field.slots.size())
			if not apply_enemy_slot_swap(field, pair.x, pair.y):
				return false
		_choices.pop_front()
		state_revision += 1
		return true
	var candidates := _choice_cards(choice)
	var selected: Array[CardData] = []
	for index in indices:
		if not index is int or index < 0 or index >= candidates.size() or selected.has(candidates[index]):
			return false
		selected.append(candidates[index])
	_choices.pop_front()
	_pair(seat, opponents_of(seat).front())
	if choice.kind == "cost" and not selected.is_empty():
		var index := player_hand.find(selected[0])
		var radius := int(choice.target in [SkillEngine.TARGET_SIDES, SkillEngine.TARGET_SELF_SIDES])
		for affected in range(maxi(0, index - radius), mini(player_hand.size(), index + radius + 1)):
			player_hand[affected].apply_cost_reduction(int(choice.value), choice.mode == SkillRegistry.COST_REDUCTION_PERMANENT)
	elif choice.kind != "cost":
		var pile := shared_deck if choice.kind == "deck" else shared_discard
		for chosen: CardData in selected:
			pile.erase(chosen)
			resolve_hand_entry_for_player(chosen, choice.kind, {}, 1)
	if not selected.is_empty():
		effective_actions_this_turn += 1
	_finish_resolution()
	state_revision += 1
	return true


func _hand_has(index: int) -> bool:
	return index >= 0 and index < player_hand.size()


func _local_side(seat: int) -> int:
	return 1 if seat == _paired[0] else 2


func _directed_skill_field(target_player: int) -> BattleField:
	if _selected_skill_seat != 0:
		return fields[_selected_skill_seat]
	return super._directed_skill_field(target_player)


func _directed_skill_is_hostile(target_player: int) -> bool:
	if _selected_skill_seat != 0:
		return teams[_selected_skill_seat] != teams[active_seat]
	return super._directed_skill_is_hostile(target_player)


func _has_summon_target(skill: Dictionary, source: CardData) -> bool:
	for seat: int in fields:
		var field: BattleField = fields[seat]
		if field.player_hp > 0 and SpellRules.has_selectable_unit(skill, source, field, teams[seat] != teams[active_seat], turn_number):
			return true
	return false


func _valid_skill_target(skill: Dictionary, source: CardData, seat: int, slot: int) -> bool:
	if skill.is_empty() or not fields.has(seat) or slot < -1 or slot >= 5:
		return false
	if slot >= 0 and fields[seat].player_hp <= 0:
		return false
	if not SpellRules.needs_target(skill):
		return true
	return SpellRules.can_select_unit(skill, source, fields[seat], slot, teams[seat] != teams[active_seat], turn_number)


func _apply_skill(source: int, index: int, seat: int, slot: int) -> bool:
	if source not in range(5):
		return false
	var card: CardData = player_field.slots[source]
	if card == null or index < 0 or index >= card.skills.size():
		return false
	var ability: Dictionary = card.skills[index]
	if not _valid_skill_target(ability, card, seat, slot):
		return false
	if ability.get("trigger") == SkillEngine.TRIGGER_ON_SUMMON:
		if not _summon_skill_pending(card, index):
			return false
		card.skills_used.append(index)
		trigger_summon_skills(source, slot, index, _local_side(seat))
		return true
	return trigger_activate_skills(source, slot, index, _local_side(seat))


func _end_seat_turn(allow_face_mana: bool) -> void:
	player_field.clear_temp_mana()
	for field: BattleField in fields.values():
		for card: CardData in field.slots:
			if card != null:
				player_field.add_mana(card.process_mana_refund(active_seat))
	_trigger_phase(SkillEngine.TRIGGER_ON_TURN_END)
	for card: CardData in player_hand:
		card.clear_turn_cost_reduction()
	for card: CardData in player_field.slots:
		if card != null:
			card.tick_poison()
	cleanup_deaths()
	if player_field.player_hp > 0 and player2_field.player_hp > 0:
		_process_empty_field_damage(allow_face_mana)
	for card: CardData in player_field.slots:
		if card != null:
			card.finish_stun_turn()
	cleanup_deaths()
	_update_winner()
	if winner == 0:
		_advance_turn()


func _finish_resolution() -> void:
	cleanup_deaths()
	_update_winner()
	# Hand-entry and start-of-turn effects can eliminate the active player.
	# Move past each defeated seat before publishing whose turn it is.
	while winner == 0 and fields[active_seat].player_hp <= 0:
		_advance_turn()
		cleanup_deaths()
		_update_winner()
	_prune_choices()


func cleanup_deaths() -> Dictionary:
	var previous := _paired.duplicate()
	var result := super.cleanup_deaths()
	while true:
		var next := 0
		for seat: int in _seats:
			if fields[seat].slots.any(func(card): return card != null and not card.is_alive()):
				next = seat
				break
		if next == 0:
			break
		_pair(next, _reaction_rival(next, previous[0]))
		super.cleanup_deaths()
	_pair(previous[0], previous[1])
	return result


func _advance_turn() -> void:
	var next := active_seat
	while true:
		next = next % _seats.size() + 1
		if next == _starting_seat:
			turn_number += 1
		if fields[next].player_hp > 0:
			break
	active_seat = next
	effective_actions_this_turn = 0
	for field: BattleField in fields.values():
		for card: CardData in field.slots:
			if card != null:
				card.tick_buffs(next)
	var rivals := opponents_of(next)
	_pair(next, rivals.front())
	for card: CardData in player_field.slots:
		if card != null:
			card.temp_hp = 0
			card.has_acted = card.has_stun()
			card.has_attacked = card.has_acted
			card.summoned_this_turn = false
			card.skills_used.clear()
			if card.has_acted:
				card.begin_stun_turn()
	var mana_per_turn := int(battle_config.get("mana_per_turn", PlayerData.DEFAULT_BATTLE_CONFIG["mana_per_turn"]))
	var draw_per_turn := int(battle_config.get("draw_per_turn", PlayerData.DEFAULT_BATTLE_CONFIG["draw_per_turn"]))
	if _seats.size() == 2 and turn_number == 1:
		var refill := first_response_resources(battle_config, mana_per_turn, draw_per_turn)
		player_field.add_mana(refill.x)
		draw_cards_for_player(refill.y, 1)
	elif turn_number > 1:
		var recovery := mana_per_turn + int(_is_small_team(next))
		recovery += int(battle_config.get("mana_increment", 0)) * maxi(0, turn_number - 2)
		player_field.add_mana(recovery)
		draw_cards_for_player(draw_per_turn, 1)
	_trigger_phase(SkillEngine.TRIGGER_ON_TURN_START)
	reset_action_budget(1)


func _trigger_phase(trigger: String) -> void:
	for slot in player_field.slots.size():
		var card: CardData = player_field.slots[slot]
		if card != null and card.is_alive():
			SkillEngine.trigger_skills(trigger, card, make_skill_context(slot))


func _update_winner() -> void:
	var living_teams: Array[int] = []
	for seat: int in _seats:
		if fields[seat].player_hp > 0 and not living_teams.has(teams[seat]):
			living_teams.append(teams[seat])
	if living_teams.size() <= 1:
		winner = 3 if living_teams.is_empty() else living_teams[0]
