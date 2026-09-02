class_name SkillEffectApplier
extends RefCounted

const _GameplayRng = preload("res://GameplayRng.gd")

const ParasiteRules = preload("res://ParasiteRules.gd")

# ============================================
# Skill effect application
# ============================================

static func apply_effect(effect_str: String, target: CardData, value: int, skill: Dictionary, context: Dictionary) -> void:
	var handler_name: String = str(SkillRegistry.effect_meta(effect_str).get("handler", ""))
	if handler_name == "":
		push_error("[SkillEffectApplier] No handler registered for effect '%s'" % effect_str)
		return
	Callable(SkillEffectApplier, handler_name).call(target, value, skill, context)


static func _apply_damage(target: CardData, value: int, _skill: Dictionary, context: Dictionary) -> void:
	var source: CardData = context.get("source_card")
	var declared := value
	var reduction_pct: int = target.get_damage_reduction()
	if reduction_pct > 0:
		value = int(floor(float(value) * (1.0 - float(reduction_pct) / 100.0)))
	if _should_parasite_absorb(target, context):
		var parasite_result := ParasiteRules.absorb_damage_detail(target, value, context.get("discard_pile", []))
		value = int(parasite_result.get("remaining", value))
		var parasite: CardData = parasite_result.get("parasite", null)
		if parasite != null:
			EventBus.parasite_damage_resolved.emit(target, parasite, declared, int(parasite_result.get("absorbed", 0)), bool(parasite_result.get("destroyed", false)))
	var temp_hp_before: int = target.temp_hp
	var actual := target.take_damage_without_reduction(value)
	EventBus.damage_resolved.emit(source, target, declared, actual, reduction_pct, temp_hp_before, "skill")
	EventBus.hp_changed.emit(target, -actual, target.hp)
	_trigger_damaged_safe(target, context)
	print("  -> %s takes %d dmg (HP: %d)" % [target.card_name, actual, target.hp])


static func _trigger_damaged_safe(target: CardData, context: Dictionary) -> void:
	# On-damaged triggers only fire for non-lethal damage (target still alive).
	if target == null or not target.is_alive():
		return
	SkillEngine.trigger_skills(SkillEngine.TRIGGER_ON_DAMAGED, target, context)
	ParasiteRules.trigger_host_passives(SkillEngine.TRIGGER_ON_DAMAGED, target, context)


static func _trigger_healed_safe(target: CardData, context: Dictionary) -> void:
	if target == null:
		return
	SkillEngine.trigger_skills(SkillEngine.TRIGGER_ON_HEALED, target, context)


static func _apply_heal(target: CardData, value: int, _skill: Dictionary, context: Dictionary) -> void:
	target.heal(value)
	EventBus.hp_changed.emit(target, value, target.hp)
	_trigger_healed_safe(target, context)
	print("  -> %s healed %d (HP: %d)" % [target.card_name, value, target.hp])


static func _apply_draw_cards(_target: CardData, value: int, _skill: Dictionary, context: Dictionary) -> void:
	var cb: Callable = context.get("draw_callable", Callable())
	if cb.is_valid():
		cb.call(value)
	print("  -> Draw %d cards" % value)


static func _apply_shield(target: CardData, value: int, _skill: Dictionary, _context: Dictionary) -> void:
	target.temp_hp += value
	print("  -> %s gains %d temp HP (total: %d)" % [target.card_name, value, target.temp_hp])


static func _apply_buff(target: CardData, value: int, skill: Dictionary, context: Dictionary) -> void:
	var buff_id: String = skill.get("buff_id", "")
	var duration: int = skill.get("duration", 1)
	if buff_id != "":
		target.apply_buff(buff_id, value, duration, context.get("current_player", 0))
		if buff_id == SkillEngine.BUFF_IMMUNE_LETHAL and value > 0:
			target.immune_lethal = true


static func _apply_lifesteal_damage(target: CardData, value: int, _skill: Dictionary, context: Dictionary) -> void:
	var source: CardData = context.get("source_card")
	var declared := value
	var reduction_pct: int = target.get_damage_reduction()
	if reduction_pct > 0:
		value = int(floor(float(value) * (1.0 - float(reduction_pct) / 100.0)))
	if _should_parasite_absorb(target, context):
		var parasite_result := ParasiteRules.absorb_damage_detail(target, value, context.get("discard_pile", []))
		value = int(parasite_result.get("remaining", value))
		var parasite: CardData = parasite_result.get("parasite", null)
		if parasite != null:
			EventBus.parasite_damage_resolved.emit(target, parasite, declared, int(parasite_result.get("absorbed", 0)), bool(parasite_result.get("destroyed", false)))
	var temp_hp_before: int = target.temp_hp
	var actual := target.take_damage_without_reduction(value)
	EventBus.damage_resolved.emit(source, target, declared, actual, reduction_pct, temp_hp_before, "lifesteal")
	EventBus.hp_changed.emit(target, -actual, target.hp)
	_trigger_damaged_safe(target, context)
	if source != null and actual > 0 and source.is_alive():
		source.heal(actual)
		EventBus.hp_changed.emit(source, actual, source.hp)
		_trigger_healed_safe(source, context)
		print("  -> %s takes %d lifesteal dmg; %s heals %d (HP: %d)" % [target.card_name, actual, source.card_name, actual, source.hp])
	else:
		print("  -> %s takes %d lifesteal dmg" % [target.card_name, actual])


static func _apply_execute(target: CardData, value: int, _skill: Dictionary, _context: Dictionary) -> void:
	if target.hp <= value:
		var actual := target.hp
		if target.immune_lethal:
			target.take_damage_without_reduction(target.hp)
		else:
			target.hp = 0
		EventBus.damage_resolved.emit(null, target, actual, actual, 0, 0, "execute")
		EventBus.hp_changed.emit(target, target.hp - actual, target.hp)
		var message := "  -> %s executed" % target.card_name if target.hp <= 0 else "  -> %s resisted execute with lethal immunity" % target.card_name
		print(message)
	else:
		print("  -> %s resisted execute (HP: %d > %d)" % [target.card_name, target.hp, value])


static func _apply_remove_statuses(target: CardData, buff_ids: Array, label: String) -> void:
	var removed := 0
	for i in range(target.status_effects.size() - 1, -1, -1):
		var eff: Dictionary = target.status_effects[i]
		if eff.get("buff_id", "") in buff_ids:
			target.status_effects.remove_at(i)
			removed += 1
	print("  -> %s %s removed %d status(es)" % [target.card_name, label, removed])


static func _apply_cleanse(target: CardData, _value: int, _skill: Dictionary, _context: Dictionary) -> void:
	_apply_remove_statuses(target, SkillRegistry.negative_buffs(), "cleanse")


static func _apply_dispel(target: CardData, _value: int, _skill: Dictionary, _context: Dictionary) -> void:
	_apply_remove_statuses(target, SkillRegistry.positive_buffs(), "dispel")


static func _apply_gain_mana(_target: CardData, value: int, _skill: Dictionary, context: Dictionary) -> void:
	var field: BattleField = context.get("player_field")
	if field == null:
		return
	var before := field.current_mana
	if value >= 0:
		field.add_mana(value)
	else:
		# Negative mana: deduct from current mana (capped at 0)
		field.current_mana = max(0, field.current_mana + value)
	print("  -> Gain %d mana (%d -> %d)" % [value, before, field.current_mana])


static func _apply_gain_attack(target: CardData, value: int, _skill: Dictionary, _context: Dictionary) -> void:
	target.field_atk_bonus += value
	print("  -> %s gains %d permanent attack (effective ATK: %d)" % [target.card_name, value, target.effective_atk()])


static func _apply_gain_max_hp(target: CardData, value: int, _skill: Dictionary, _context: Dictionary) -> void:
	target.max_hp += value
	target.base_max_hp += value
	if value >= 0:
		target.hp = min(target.max_hp, target.hp + value)
	else:
		# Negative max HP: also clamp current HP to new max
		target.hp = min(target.max_hp, target.hp)
	EventBus.hp_changed.emit(target, value, target.hp)
	print("  -> %s gains %d max HP (HP: %d/%d)" % [target.card_name, value, target.hp, target.max_hp])


static func _should_parasite_absorb(target: CardData, context: Dictionary) -> bool:
	if target == null or target.parasite_cards.is_empty():
		return false
	var skill_target: String = context.get("effect_target", "")
	return skill_target in [SkillEngine.TARGET_SINGLE, SkillEngine.TARGET_SIDES]


static func _apply_charm(target: CardData, _value: int, _skill: Dictionary, context: Dictionary) -> void:
	var enemy_field: BattleField = context.get("enemy_field")
	var player_field: BattleField = context.get("player_field")
	var hand: Array = context.get("active_hand", [])
	if hand == null:
		return

	var slot_idx := -1
	var target_field: BattleField = null
	if enemy_field != null:
		for i in range(enemy_field.slots.size()):
			if enemy_field.slots[i] == target:
				slot_idx = i
				target_field = enemy_field
				break
	if target_field == null and player_field != null:
		for i in range(player_field.slots.size()):
			if player_field.slots[i] == target:
				slot_idx = i
				target_field = player_field
				break
	if slot_idx < 0:
		return

	var copy := target.duplicate_card()
	copy.original_cost = target.original_cost if target.original_cost >= 0 else target.cost
	copy.cost = 0
	copy.charmed_slot = slot_idx

	target_field.slots[slot_idx] = null
	print("  -> %s charmed! (slot %d) cost 0 this turn" % [copy.card_name, slot_idx])

	hand.append(copy)


# ============================================
# New effect handlers
# ============================================

static func _apply_view_discard_select(_target: CardData, value: int, _skill: Dictionary, context: Dictionary) -> void:
	var discard_pile: Array = context.get("discard_pile", [])
	if discard_pile.is_empty():
		print("[SkillEffect] View discard: discard pile is empty")
		return
	var count := value if value > 0 else 1
	var draw_count: int = int(context.get("random_count", 0))
	EventBus.view_discard_select.emit(count, draw_count, context.get("current_player", 0), context.get("active_hand", []))
	print("  -> View discard pile and select up to %d card(s) from %d drawn" % [count, draw_count])


static func _apply_view_deck_select(_target: CardData, value: int, _skill: Dictionary, context: Dictionary) -> void:
	var deck: Array = context.get("shared_deck", [])
	if deck.is_empty():
		var discard_pile: Array = context.get("discard_pile", [])
		if discard_pile.is_empty():
			print("[SkillEffect] View deck: deck is empty")
			return
		# Shuffle discard into deck when needed
		EventBus.shuffle_discard_into_deck.emit()
	var count := value if value > 0 else 1
	var draw_count: int = int(context.get("random_count", 0))
	EventBus.view_deck_select.emit(count, draw_count, context.get("current_player", 0), context.get("active_hand", []))
	print("  -> View deck top cards and select up to %d card(s) from %d drawn" % [count, draw_count])


static func _apply_make_zero_cost(_target: CardData, value: int, skill: Dictionary, context: Dictionary) -> void:
	var hand: Array = context.get("active_hand", [])
	if hand.is_empty():
		print("[SkillEffect] Make zero cost: hand is empty")
		return
	var target_str: String = skill.get("target", SkillEngine.TARGET_SELF)
	var random_count: int = int(skill.get("random_count", 0))

	# Gather eligible candidates (cost > 0, not already zero-cost)
	var candidates: Array = []
	for card in hand:
		if card is CardData and card.cost > 0 and not card.zero_cost_until_deploy:
			candidates.append(card)
	if candidates.is_empty():
		return

	# TARGET_ALL: apply to all hand cards directly
	if target_str == SkillEngine.TARGET_ALL:
		for card in candidates:
			card.cost = 0
			card.zero_cost_until_deploy = true
		print("  -> Make all %d hand card(s) cost 0 until deployed" % candidates.size())
		return

	# TARGET_SINGLE with random_count > 0: randomly select
	if target_str == SkillEngine.TARGET_SINGLE and random_count > 0:
		_GameplayRng.shuffle(candidates, _GameplayRng.from_context(context))
		var pick_count : int = min(random_count, candidates.size())
		for i in range(pick_count):
			candidates[i].cost = 0
			candidates[i].zero_cost_until_deploy = true
		print("  -> Make %d random card(s) cost 0 until deployed" % pick_count)
		return

	# Otherwise: let player select (SELF, SINGLE, SIDES, SELF_SIDES)
	var count: int = value if value > 0 else 1
	EventBus.make_zero_cost_select.emit(count, context.get("current_player", 0), hand, target_str, random_count)
	print("  -> Make up to %d card(s) cost 0 until deployed (target=%s)" % [count, target_str])


# ============================================
# Extended effects (user-editable expansion)
# ============================================

static func _apply_mana_drain(_target: CardData, value: int, _skill: Dictionary, context: Dictionary) -> void:
	var pf: BattleField = context.get("player_field")
	var ef: BattleField = context.get("enemy_field")
	# Only siphon what the enemy actually has: draining 5 from an enemy with
	# 1 mana must give you 1, not 5 (previously the self side gained the full
	# requested amount regardless of how much was available).
	var drained: int = 0
	if ef != null:
		drained = min(value, ef.current_mana)
		ef.current_mana = max(0, ef.current_mana - drained)
		print("  -> Enemy loses %d mana (%d)" % [drained, ef.current_mana])
	if pf != null:
		pf.add_mana(drained)
		print("  -> Self gains %d mana (%d)" % [drained, pf.current_mana])


static func _apply_swap_attack(target: CardData, _value: int, _skill: Dictionary, context: Dictionary) -> void:
	var source: CardData = context.get("source_card")
	if target == null or source == null or target == source:
		return
	var tmp_atk: int = target.atk
	var tmp_base: int = target.base_atk
	target.atk = source.atk
	target.base_atk = source.base_atk
	source.atk = tmp_atk
	source.base_atk = tmp_base
	print("  -> %s and %s swap attack (%d <-> %d)" % [source.card_name, target.card_name, source.atk, target.atk])


static func _apply_discard_hand(_target: CardData, value: int, _skill: Dictionary, context: Dictionary) -> void:
	var enemy_hand: Array = context.get("enemy_hand", [])
	if enemy_hand == null or enemy_hand.is_empty():
		print("[SkillEffect] Discard hand: enemy hand is empty")
		return
	var rng := _GameplayRng.from_context(context)
	var discard_pile: Array = context.get("discard_pile", [])
	var count: int = min(value, enemy_hand.size())
	for _i in range(count):
		var idx: int = rng.randi_range(0, enemy_hand.size() - 1)
		var card: CardData = enemy_hand[idx]
		enemy_hand.remove_at(idx)
		if card != null:
			card.reset_to_base()
			discard_pile.append(card)
	print("  -> Enemy discards %d card(s)" % count)


static func _apply_copy_hand(_target: CardData, value: int, _skill: Dictionary, context: Dictionary) -> void:
	var hand: Array = context.get("active_hand", [])
	if hand == null or hand.is_empty():
		print("[SkillEffect] Copy hand: hand is empty")
		return
	var rng := _GameplayRng.from_context(context)
	var space: int = max(0, SkillEngine.MAX_HAND_SIZE - hand.size())
	var count: int = min(value, space)
	for _i in range(count):
		var idx: int = rng.randi_range(0, hand.size() - 1)
		var copy: CardData = hand[idx].duplicate_card()
		# Runtime identity is part of synchronized/replay state, so derive it
		# from the battle RNG instead of wall-clock time.
		copy.instance_id = "copy_%08x%08x" % [rng.randi(), rng.randi()]
		hand.append(copy)
	print("  -> Copy %d hand card(s)" % count)
