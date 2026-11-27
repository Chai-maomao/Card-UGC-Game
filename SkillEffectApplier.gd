class_name SkillEffectApplier
extends RefCounted

const _GameplayRng = preload("res://GameplayRng.gd")
const _GameplayLog = preload("res://GameplayLog.gd")

const ParasiteRules = preload("res://ParasiteRules.gd")

# ============================================
# Skill effect application
# ============================================

static func apply_effect(effect_str: String, target: Variant, value: int, skill: Dictionary, context: Dictionary) -> void:
	if target is BattleField and not SkillRegistry.allows_player_target(effect_str):
		push_warning("[SkillEffectApplier] Effect '%s' cannot target a player body" % effect_str)
		return
	var handler_name: String = str(SkillRegistry.effect_meta(effect_str).get("handler", ""))
	if handler_name == "":
		push_error("[SkillEffectApplier] No handler registered for effect '%s'" % effect_str)
		return
	Callable(SkillEffectApplier, handler_name).call(target, value, skill, context)
	if effect_str not in [SkillEngine.EFFECT_DAMAGE, SkillEngine.EFFECT_HEAL, SkillEngine.EFFECT_SHIELD, SkillEngine.EFFECT_GAIN_MANA, SkillEngine.EFFECT_MANA_DRAIN, SkillEngine.EFFECT_LIFESTEAL_DAMAGE, SkillEngine.EFFECT_ADD_BUFF]:
		_metric(context, "unmeasured_effect", target, 1)


static func _apply_damage(target: Variant, value: int, _skill: Dictionary, context: Dictionary) -> void:
	if target == null or value <= 0:
		return
	if target is BattleField:
		var before: int = target.player_hp
		target.damage_player(value)
		var actual: int = maxi(0, before - target.player_hp)
		_metric(context, "damage", target, actual)
		_GameplayLog.write("  -> %s player takes %d dmg (HP: %d)" % [target.owner_name, actual, target.player_hp])
		return
	if not target is CardData:
		return
	var source: CardData = context.get("source_card")
	var declared := value
	var reduction_pct: int = target.get_damage_reduction()
	if reduction_pct > 0:
		value = maxi(0, int(floor(float(value) * (1.0 - float(reduction_pct) / 100.0))))
	if _should_parasite_absorb(target, context):
		var parasite_result := ParasiteRules.absorb_damage_detail(target, value, context.get("discard_pile", []))
		value = int(parasite_result.get("remaining", value))
		var parasite: CardData = parasite_result.get("parasite", null)
		if parasite != null:
			var sink: Callable = context.get("metrics_callable", Callable())
			if sink.is_valid(): sink.call({"kind":"damage_prevented","source_card":parasite,"target_card":target,"source_player":3-int(context.get("current_player",0)),"amount":parasite_result.get("prevented",0)})
			_metric(context, "parasite_damage", target, int(parasite_result.absorbed))
			EventBus.parasite_damage_resolved.emit(target, parasite, declared, int(parasite_result.get("absorbed", 0)), bool(parasite_result.get("destroyed", false)))
	var temp_hp_before: int = target.temp_hp
	var actual: int = int(target.take_damage_without_reduction(value))
	_metric(context, "shield_damage", target, temp_hp_before - target.temp_hp)
	_emit_damage(source, target, declared, actual, reduction_pct, temp_hp_before, "skill", context)
	EventBus.hp_changed.emit(target, -actual, target.hp)
	_trigger_damaged_safe(target, context)
	_GameplayLog.write("  -> %s takes %d dmg (HP: %d)" % [target.card_name, actual, target.hp])


static func _emit_damage(source: CardData, target: CardData, declared: int, actual: int, reduction_pct: int, temp_hp_before: int, reason: String, context: Dictionary) -> void:
	_metric(context, "damage", target, actual)
	var stats_callback: Callable = context.get("damage_stats_callable", Callable())
	if EventBus.is_blocking_signals() and stats_callback.is_valid():
		stats_callback.call(source, target, declared, actual, reduction_pct, temp_hp_before, reason)
	EventBus.damage_resolved.emit(source, target, declared, actual, reduction_pct, temp_hp_before, reason)


static func _metric(context: Dictionary, kind: String, target: Variant, amount: int, extra: Dictionary = {}) -> void:
	var sink: Callable = context.get("metrics_callable", Callable())
	if not sink.is_valid(): return
	var row := extra.duplicate()
	row.merge({"kind": kind, "source_card": context.get("metric_source_card", context.get("source_card")), "target_card": target, "source_player": int(context.get("current_player", 0)), "amount": amount})
	sink.call(row)


static func _trigger_damaged_safe(target: CardData, context: Dictionary) -> void:
	# On-damaged triggers only fire for non-lethal damage (target still alive).
	if target == null or not target.is_alive():
		return
	var party_reaction: Callable = context.get("party_reaction", Callable())
	if party_reaction.is_valid() and party_reaction.call(SkillEngine.TRIGGER_ON_DAMAGED, target, context):
		return
	var reaction := _reaction_context(target, context)
	SkillEngine.trigger_skills(SkillEngine.TRIGGER_ON_DAMAGED, target, reaction)
	ParasiteRules.trigger_host_passives(SkillEngine.TRIGGER_ON_DAMAGED, target, reaction)


static func _trigger_healed_safe(target: CardData, context: Dictionary) -> void:
	if target == null:
		return
	var party_reaction: Callable = context.get("party_reaction", Callable())
	if party_reaction.is_valid() and party_reaction.call(SkillEngine.TRIGGER_ON_HEALED, target, context):
		return
	SkillEngine.trigger_skills(SkillEngine.TRIGGER_ON_HEALED, target, _reaction_context(target, context))


static func _reaction_context(target: CardData, context: Dictionary) -> Dictionary:
	var factory: Callable = context.get("reaction_context_callable", Callable())
	return factory.call(target, context) if factory.is_valid() else context


static func _apply_heal(target: Variant, value: int, _skill: Dictionary, context: Dictionary) -> void:
	if target == null or value <= 0:
		return
	if target is BattleField:
		var before: int = target.player_hp
		target.heal_player(value)
		var actual: int = maxi(0, target.player_hp - before)
		_metric(context, "healing", target, actual)
		_GameplayLog.write("  -> %s player healed %d (HP: %d)" % [target.owner_name, actual, target.player_hp])
		return
	if not target is CardData:
		return
	var before: int = int(target.hp)
	target.heal(value)
	var actual: int = maxi(0, int(target.hp) - before)
	_metric(context, "healing", target, actual)
	EventBus.hp_changed.emit(target, actual, target.hp)
	_trigger_healed_safe(target, context)
	_GameplayLog.write("  -> %s healed %d (HP: %d)" % [target.card_name, actual, target.hp])


static func _apply_draw_cards(_target: CardData, value: int, _skill: Dictionary, context: Dictionary) -> void:
	if value <= 0:
		return
	var cb: Callable = context.get("draw_callable", Callable())
	if cb.is_valid():
		cb.call(value)
	_GameplayLog.write("  -> Draw %d cards" % value)


static func _apply_shield(target: CardData, value: int, _skill: Dictionary, context: Dictionary) -> void:
	if target == null or value <= 0:
		return
	target.temp_hp += value
	_metric(context, "shield", target, value)
	_GameplayLog.write("  -> %s gains %d shield (total: %d)" % [target.card_name, value, target.temp_hp])


static func _apply_buff(target: CardData, value: int, skill: Dictionary, context: Dictionary) -> void:
	var buff_id: String = skill.get("buff_id", "")
	if buff_id not in [SkillEngine.BUFF_ATK_BOOST, SkillEngine.BUFF_POISON, SkillEngine.BUFF_REGEN, SkillEngine.BUFF_MANA_REFUND]:
		_metric(context, "unmeasured_effect", target, 1)
	var duration: int = skill.get("duration", 1)
	if buff_id != "":
		target.apply_buff(buff_id, value, duration, context.get("status_owner", context.get("current_player", 0)))
		if buff_id in [SkillEngine.BUFF_POISON, SkillEngine.BUFF_REGEN, SkillEngine.BUFF_MANA_REFUND] and not target.status_effects.is_empty():
			_metric(context, "status_origin", target, 0, {"status": target.status_effects.back()})
		if buff_id == SkillEngine.BUFF_IMMUNE_LETHAL and value > 0:
			target.immune_lethal = true


static func _apply_lifesteal_damage(target: CardData, value: int, _skill: Dictionary, context: Dictionary) -> void:
	if target == null or value <= 0:
		return
	var source: CardData = context.get("source_card")
	var declared := value
	var reduction_pct: int = target.get_damage_reduction()
	if reduction_pct > 0:
		value = maxi(0, int(floor(float(value) * (1.0 - float(reduction_pct) / 100.0))))
	if _should_parasite_absorb(target, context):
		var parasite_result := ParasiteRules.absorb_damage_detail(target, value, context.get("discard_pile", []))
		value = int(parasite_result.get("remaining", value))
		var parasite: CardData = parasite_result.get("parasite", null)
		if parasite != null:
			var sink: Callable = context.get("metrics_callable", Callable())
			if sink.is_valid(): sink.call({"kind":"damage_prevented","source_card":parasite,"target_card":target,"source_player":3-int(context.get("current_player",0)),"amount":parasite_result.get("prevented",0)})
			_metric(context, "parasite_damage", target, int(parasite_result.absorbed))
			EventBus.parasite_damage_resolved.emit(target, parasite, declared, int(parasite_result.get("absorbed", 0)), bool(parasite_result.get("destroyed", false)))
	var temp_hp_before: int = target.temp_hp
	var actual := target.take_damage_without_reduction(value)
	_metric(context, "shield_damage", target, temp_hp_before - target.temp_hp)
	_emit_damage(source, target, declared, actual, reduction_pct, temp_hp_before, "lifesteal", context)
	EventBus.hp_changed.emit(target, -actual, target.hp)
	_trigger_damaged_safe(target, context)
	if source != null and actual > 0 and source.is_alive():
		var source_before := source.hp
		source.heal(actual)
		var healed := maxi(0, source.hp - source_before)
		_metric(context, "healing", source, healed)
		EventBus.hp_changed.emit(source, healed, source.hp)
		_trigger_healed_safe(source, context)
		_GameplayLog.write("  -> %s takes %d lifesteal dmg; %s heals %d (HP: %d)" % [target.card_name, actual, source.card_name, healed, source.hp])
	else:
		_GameplayLog.write("  -> %s takes %d lifesteal dmg" % [target.card_name, actual])


static func _apply_execute(target: CardData, value: int, _skill: Dictionary, context: Dictionary) -> void:
	if target == null or value <= 0:
		return
	if target.hp <= value:
		var before := target.hp
		if target.immune_lethal:
			target.take_damage_without_reduction(target.hp)
		else:
			target.hp = 0
		var actual := maxi(0, before - target.hp)
		_emit_damage(context.get("source_card"), target, before, actual, 0, 0, "execute", context)
		EventBus.hp_changed.emit(target, target.hp - before, target.hp)
		var message := "  -> %s executed" % target.card_name if target.hp <= 0 else "  -> %s resisted execute with lethal immunity" % target.card_name
		_GameplayLog.write(message)
	else:
		_GameplayLog.write("  -> %s resisted execute (HP: %d > %d)" % [target.card_name, target.hp, value])


static func _apply_remove_statuses(target: CardData, buff_ids: Array, label: String, context: Dictionary) -> void:
	var removed := 0
	for i in range(target.status_effects.size() - 1, -1, -1):
		var eff: Dictionary = target.status_effects[i]
		if eff.get("buff_id", "") in buff_ids:
			_metric(context, "status_expired", target, 0, {"status": eff})
			target.status_effects.remove_at(i)
			removed += 1
	_GameplayLog.write("  -> %s %s removed %d status(es)" % [target.card_name, label, removed])


static func _apply_cleanse(target: CardData, _value: int, _skill: Dictionary, context: Dictionary) -> void:
	_apply_remove_statuses(target, SkillRegistry.negative_buffs(), "cleanse", context)


static func _apply_dispel(target: CardData, _value: int, _skill: Dictionary, context: Dictionary) -> void:
	_apply_remove_statuses(target, SkillRegistry.positive_buffs(), "dispel", context)


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
	_metric(context, "mana_gained" if field.current_mana >= before else "mana_removed", field, absi(field.current_mana - before))
	_GameplayLog.write("  -> Gain %d mana (%d -> %d)" % [value, before, field.current_mana])


static func _apply_gain_attack(target: CardData, value: int, _skill: Dictionary, _context: Dictionary) -> void:
	target.field_atk_bonus += value
	_GameplayLog.write("  -> %s changes battlefield attack by %d (effective ATK: %d)" % [target.card_name, value, target.effective_atk()])


static func _apply_gain_max_hp(target: CardData, value: int, _skill: Dictionary, _context: Dictionary) -> void:
	if target == null or value == 0:
		return
	var old_max := target.max_hp
	var applied := maxi(1, old_max + value) - old_max
	target.max_hp = old_max + applied
	if applied >= 0:
		target.hp = mini(target.max_hp, target.hp + applied)
	else:
		# Negative max HP: also clamp current HP to new max
		target.hp = mini(target.max_hp, target.hp)
	EventBus.hp_changed.emit(target, applied, target.hp)
	_GameplayLog.write("  -> %s changes battlefield max HP by %d (HP: %d/%d)" % [target.card_name, applied, target.hp, target.max_hp])


static func _apply_match_max_hp(target: CardData, value: int, _skill: Dictionary, _context: Dictionary) -> void:
	if target == null or value <= 0:
		return
	target.base_max_hp += value
	target.max_hp += value
	target.hp += value
	EventBus.hp_changed.emit(target, value, target.hp)
	_GameplayLog.write("  -> %s gains %d max HP for this match (HP: %d/%d)" % [target.card_name, value, target.hp, target.max_hp])


static func _apply_damage_cap(_target: CardData, _value: int, _skill: Dictionary, _context: Dictionary) -> void:
	# Continuous talents are read directly by CardData at damage time.
	pass


static func _apply_change_cost(target: CardData, value: int, _skill: Dictionary, _context: Dictionary) -> void:
	if target == null or value == 0:
		return
	var before := target.cost
	target.apply_cost_change(value)
	_GameplayLog.write("  -> %s changes match cost by %d (%d -> %d)" % [target.card_name, value, before, target.cost])


static func _should_parasite_absorb(target: CardData, _context: Dictionary) -> bool:
	# Target selection does not change how a hit is blocked.
	return target != null and ParasiteRules.has_damage_absorber(target)


static func _apply_charm(target: CardData, _value: int, _skill: Dictionary, context: Dictionary) -> void:
	if target == context.get("source_card") and str(context.get("trigger", "")) == SkillEngine.TRIGGER_ON_DEATH:
		push_warning("[SkillEffect] A dead card cannot charm itself")
		return
	var player_field: BattleField = context.get("player_field")
	var hand: Array = context.get("active_hand", [])
	if hand == null:
		return

	var target_field := _field_containing_unit(target, context)
	if target_field == null:
		return
	var slot_idx := target_field.slots.find(target)

	var copy := target.duplicate_card()
	copy.apply_charm_cost(slot_idx)
	var current_player: int = int(context.get("current_player", 0))
	var source_player: int = current_player if target_field == player_field else (2 if current_player == 1 else 1)

	target_field.slots[slot_idx] = null
	var board_change_cb: Callable = context.get("board_change_callable", Callable())
	var party_change: Callable = context.get("party_board_change", Callable())
	if party_change.is_valid():
		party_change.call("leave", target, target_field)
	elif board_change_cb.is_valid():
		board_change_cb.call(source_player, "leave", target)
	_GameplayLog.write("  -> %s charmed! (slot %d) cost 0 for this turn" % [copy.card_name, slot_idx])
	_resolve_hand_entry(copy, "field", {
		"source_player": source_player,
		"source_slot": slot_idx,
		"source_instance_id": target.instance_id,
	}, context)


# ============================================
# New effect handlers
# ============================================

static func _apply_view_discard_select(_target: CardData, value: int, _skill: Dictionary, context: Dictionary) -> void:
	if value <= 0:
		return
	var picker: Callable = context.get("party_card_choice", Callable())
	if picker.is_valid():
		picker.call({"kind": "discard", "count": value, "look": int(context.get("random_count", 0))})
		return
	var discard_pile: Array = context.get("discard_pile", [])
	if discard_pile.is_empty():
		_GameplayLog.write("[SkillEffect] View discard: discard pile is empty")
		return
	var count := value
	var draw_count: int = int(context.get("random_count", 0))
	EventBus.view_discard_select.emit(count, draw_count, context.get("current_player", 0), context.get("active_hand", []))
	_GameplayLog.write("  -> View discard pile and select up to %d card(s) from %d drawn" % [count, draw_count])


static func _apply_view_deck_select(_target: CardData, value: int, _skill: Dictionary, context: Dictionary) -> void:
	if value <= 0:
		return
	var picker: Callable = context.get("party_card_choice", Callable())
	if picker.is_valid():
		picker.call({"kind": "deck", "count": value, "look": int(context.get("random_count", 0))})
		return
	var deck: Array = context.get("shared_deck", [])
	if deck.is_empty():
		var discard_pile: Array = context.get("discard_pile", [])
		if discard_pile.is_empty():
			_GameplayLog.write("[SkillEffect] View deck: deck is empty")
			return
		# Shuffle discard into deck when needed
		EventBus.shuffle_discard_into_deck.emit()
	var count := value
	var draw_count: int = int(context.get("random_count", 0))
	EventBus.view_deck_select.emit(count, draw_count, context.get("current_player", 0), context.get("active_hand", []))
	_GameplayLog.write("  -> View deck top cards and select up to %d card(s) from %d drawn" % [count, draw_count])


static func _apply_make_zero_cost(_target: CardData, value: int, skill: Dictionary, context: Dictionary) -> void:
	if value <= 0:
		return
	var hand: Array = context.get("active_hand", [])
	if hand.is_empty():
		_GameplayLog.write("[SkillEffect] Reduce cost: hand is empty")
		return
	# Legacy editor data may omit the hand selector. Treat it as the documented
	# default (choose one hand card) instead of emitting an empty selection mode.
	var target_str: String = str(skill.get("target", SkillEngine.TARGET_SINGLE))
	if target_str == "":
		target_str = SkillEngine.TARGET_SINGLE
	var random_count: int = int(skill.get("random_count", 0))
	var cost_mode: String = str(skill.get("cost_reduction_mode", SkillRegistry.COST_REDUCTION_TURN))
	var permanent: bool = cost_mode == SkillRegistry.COST_REDUCTION_PERMANENT

	# Reductions stack and clamp at zero. Zero-cost cards are omitted because
	# another reduction cannot change their current payable value.
	var candidates: Array = []
	for card in hand:
		if card is CardData and card.cost > 0:
			candidates.append(card)
	if candidates.is_empty():
		return

	# TARGET_ALL: apply to all hand cards directly
	if target_str == SkillEngine.TARGET_ALL:
		for card in candidates:
			card.apply_cost_reduction(value, permanent)
		_GameplayLog.write("  -> Reduce all %d hand card(s) by %d (%s)" % [candidates.size(), value, cost_mode])
		return

	# TARGET_SINGLE with random_count > 0: random mode. random_count is the
	# visible count in this variant; the ordinary value is used only by the
	# interactive selection variant.
	if target_str == SkillEngine.TARGET_SINGLE and random_count > 0:
		_GameplayRng.shuffle(candidates, _GameplayRng.from_context(context))
		var pick_count : int = min(random_count, candidates.size())
		for i in range(pick_count):
			candidates[i].apply_cost_reduction(value, permanent)
		_GameplayLog.write("  -> Reduce %d random card(s) by %d (%s)" % [pick_count, value, cost_mode])
		return

	# Otherwise the player selects one anchor; SIDES also affects its neighbors.
	var picker: Callable = context.get("party_card_choice", Callable())
	if picker.is_valid():
		picker.call({"kind": "cost", "count": 1, "value": value, "target": target_str, "mode": cost_mode})
		return
	EventBus.make_zero_cost_select.emit(value, cost_mode, context.get("current_player", 0), hand, target_str, random_count)
	_GameplayLog.write("  -> Choose a hand card to reduce by %d (%s, target=%s)" % [value, cost_mode, target_str])


static func _field_containing_unit(target: CardData, context: Dictionary) -> BattleField:
	for field: BattleField in [context.get("selected_unit_field"), context.get("player_field"), context.get("enemy_field")]:
		if field != null and target in field.slots:
			return field
	var party_fields: Callable = context.get("party_fields", Callable())
	if party_fields.is_valid():
		for field: BattleField in party_fields.call(context.get("source_card"), SkillEngine.TARGET_SIDE_ALL):
			if target in field.slots:
				return field
	return null


static func _apply_clone_enemy(target: CardData, _value: int, skill: Dictionary, context: Dictionary) -> void:
	if target == null:
		return
	var field: BattleField = context.get("enemy_field")
	var party_fields: Callable = context.get("party_fields", Callable())
	if party_fields.is_valid() or SkillTargetResolver.uses_selected_unit(str(skill.get("target", ""))):
		field = _field_containing_unit(target, context)
	var hand: Array = context.get("active_hand", [])
	if field == null or hand == null or target not in field.slots:
		return
	var copy := target.duplicate_card()
	var rng := _GameplayRng.from_context(context)
	_reidentify_clone_tree(copy, rng)
	# A clone carries the target's complete current card state; only its runtime
	# identity changes so synchronization and replay can distinguish the copy.
	var slot_idx: int = field.slots.find(target)
	var current_player: int = int(context.get("current_player", 0))
	_resolve_hand_entry(copy, "field", {
		"source_player": current_player if field == context.get("player_field") else 3 - current_player,
		"source_slot": slot_idx,
		"source_instance_id": target.instance_id,
	}, context)
	_GameplayLog.write("  -> Clone %s into hand" % target.card_name)


static func _reidentify_clone_tree(card: CardData, rng: RandomNumberGenerator) -> void:
	card.instance_id = "clone_%08x%08x" % [rng.randi(), rng.randi()]
	for parasite in card.parasite_cards:
		if parasite is CardData:
			_reidentify_clone_tree(parasite, rng)


# ============================================
# Extended effects (user-editable expansion)
# ============================================

static func _apply_mana_drain(_target: CardData, value: int, _skill: Dictionary, context: Dictionary) -> void:
	if value <= 0:
		return
	var pf: BattleField = context.get("player_field")
	var ef: BattleField = context.get("enemy_field")
	# Only siphon what the enemy actually has: draining 5 from an enemy with
	# 1 mana must give you 1, not 5 (previously the self side gained the full
	# requested amount regardless of how much was available).
	var drained: int = 0
	if ef != null:
		drained = min(value, ef.current_mana)
		ef.current_mana = max(0, ef.current_mana - drained)
		_GameplayLog.write("  -> Enemy loses %d mana (%d)" % [drained, ef.current_mana])
	if pf != null:
		var before := pf.current_mana
		pf.add_mana(drained)
		_metric(context, "mana_gained", pf, pf.current_mana - before)
		_GameplayLog.write("  -> Self gains %d mana (%d)" % [drained, pf.current_mana])
	_metric(context, "mana_drained", ef, drained)


static func _apply_swap_enemy_slots(_target: CardData, _value: int, _skill: Dictionary, context: Dictionary) -> void:
	var request: Callable = context.get("enemy_swap_callable", Callable())
	if request.is_valid():
		request.call()


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
	_GameplayLog.write("  -> %s and %s swap attack (%d <-> %d)" % [source.card_name, target.card_name, source.atk, target.atk])


static func _apply_discard_hand(_target: CardData, value: int, _skill: Dictionary, context: Dictionary) -> void:
	if value <= 0:
		return
	var enemy_hand: Array = context.get("enemy_hand", [])
	if enemy_hand == null or enemy_hand.is_empty():
		_GameplayLog.write("[SkillEffect] Discard hand: enemy hand is empty")
		return
	var rng := _GameplayRng.from_context(context)
	var discard_pile: Array = context.get("discard_pile", [])
	var discard_cb: Callable = context.get("discard_card_callable", Callable())
	var current_player := int(context.get("current_player", 1))
	var victim_player := 2 if current_player == 1 else 1
	var count: int = min(value, enemy_hand.size())
	var original_hand := enemy_hand.duplicate()
	var removed: Array = []
	for _i in range(count):
		var idx: int = rng.randi_range(0, enemy_hand.size() - 1)
		var card: CardData = enemy_hand[idx]
		enemy_hand.remove_at(idx)
		if card != null:
			removed.append({"card":card.duplicate_card(),"index":original_hand.find(card)})
			if discard_cb.is_valid():
				discard_cb.call(card, victim_player, "effect")
			else:
				card.reset_to_base()
				discard_pile.append(card)
	EventBus.enemy_hand_discarded.emit(current_player,original_hand.size(),removed)
	_GameplayLog.write("  -> Enemy discards %d card(s)" % count)


static func _apply_copy_hand(_target: CardData, value: int, _skill: Dictionary, context: Dictionary) -> void:
	if value <= 0:
		return
	var hand: Array = context.get("active_hand", [])
	if hand == null or hand.is_empty():
		_GameplayLog.write("[SkillEffect] Copy hand: hand is empty")
		return
	var rng := _GameplayRng.from_context(context)
	# Pick from the hand as it existed before this effect. Newly-created copies
	# must not become recursive candidates during the same multi-copy action.
	var source_cards: Array = hand.duplicate()
	for _i in range(value):
		var idx: int = rng.randi_range(0, source_cards.size() - 1)
		var source_card: CardData = source_cards[idx]
		var copy: CardData = source_card.duplicate_card()
		# Runtime identity is part of synchronized/replay state, so derive it
		# from the battle RNG instead of wall-clock time.
		copy.instance_id = "copy_%08x%08x" % [rng.randi(), rng.randi()]
		_resolve_hand_entry(copy, "hand", {
			"source_instance_id": source_card.instance_id,
		}, context)
	_GameplayLog.write("  -> Copy %d hand card(s)" % value)


static func _resolve_hand_entry(card: CardData, source: String, source_meta: Dictionary, context: Dictionary) -> String:
	var cb: Callable = context.get("hand_entry_callable", Callable())
	if cb.is_valid():
		return str(cb.call(card, source, source_meta))
	# Standalone engine tests and tools may build a lightweight context without
	# GameState. Keep the same rule in that fallback instead of silently growing
	# past six or deleting the generated card.
	var hand: Array = context.get("active_hand", [])
	var player: int = int(context.get("current_player", 0))
	var destination := "hand"
	if hand.size() < SkillEngine.MAX_HAND_SIZE:
		hand.append(card)
	else:
		destination = "discard"
		var discard_pile: Array = context.get("discard_pile", [])
		ParasiteRules.release_all_to_discard(card, discard_pile)
		card.reset_to_base()
		discard_pile.append(card)
	EventBus.hand_entry_resolved.emit(card, player, destination, source, source_meta.duplicate(true))
	return destination
