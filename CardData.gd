class_name CardData
extends RefCounted

const PARASITE_DAMAGE_ABSORB := "absorb"
const PARASITE_DAMAGE_LINKED := "linked"

# ============================================
# Card data model
# ============================================

# Base stats
var card_id: String = ""
var instance_id: String = ""
var card_name: String = ""
var cost: int = 0
var max_hp: int = 0
var hp: int = 0
var atk: int = 0
var base_cost: int = 0
var base_max_hp: int = 0
var base_atk: int = 0
var gender: String = "female"
var has_acted: bool = false
var has_attacked: bool = false
var summoned_this_turn: bool = false
var skills_used: Array = []
var skills_used_count: Dictionary = {}  # skill_index -> count (for 限定技 max_uses tracking)
var charmed_slot: int = -1
var original_cost: int = -1

# Battle-only cost modifiers. Permanent reductions survive discard/reset and
# reshuffling for the rest of the match; turn reductions and Charm expire at
# the end of their owner's current turn. base_cost remains the printed cost,
# so the UI can distinguish a real discount from mere affordability.
var permanent_cost_reduction: int = 0
var turn_cost_reduction: int = 0
# Signed, match-long cost adjustment. Positive values raise cost and negative
# values lower it; unlike a turn reduction this survives discard and reshuffle.
var match_cost_delta: int = 0

# When true, this card's basic attack bypasses silence (天赋特性)
var attack_ignores_silence: bool = false

# Field-only permanent ATK bonus (from gain_attack effects). This bonus only
# applies while the card is on the battlefield; it is cleared on reset_to_base().
var field_atk_bonus: int = 0

# Immunity to lethal damage (1-time effect, consumed when triggered)
var immune_lethal: bool = false

# Legacy snapshot compatibility. New battles use the explicit reduction fields
# above; old snapshots with this flag are migrated on deserialization.
var zero_cost_until_deploy: bool = false

# Card type: "minion" (default, occupies a battlefield slot), "spell"
# (casts directly from hand to discard pile), or "parasite" (attaches to a
# unit and follows that host's battlefield lifecycle).
var card_type: String = "minion"

# Parasites may either intercept directed damage for their host or remain
# linked without taking damage. Missing legacy data defaults to interception.
var parasite_damage_mode: String = PARASITE_DAMAGE_ABSORB

# Parasite cards attached to this unit. Only attachments configured for damage
# interception take directed attack/skill damage before this unit loses HP.
var parasite_cards: Array = []

# Temporary HP (shield replacement, expires when its owner is about to act again)
var temp_hp: int = 0

# Skill definitions (Array[Dictionary])
var skills: Array = []

# Splash art texture path (empty = no art)
var art_path: String = ""

# Runtime status effects / buffs
# Each buff: { "buff_id": String, "value": int, "duration": int }
var status_effects: Array = []


func _init(_name: String, _cost: int, _hp: int, _atk: int, _skills: Array = []):
	card_name = _name
	cost = _cost
	max_hp = _hp
	hp = _hp
	atk = _atk
	base_cost = _cost
	base_max_hp = _hp
	base_atk = _atk
	skills = _skills


func is_alive() -> bool:
	return hp > 0


func is_spell() -> bool:
	return card_type == "spell"


func is_parasite() -> bool:
	return card_type == "parasite"


static func normalize_parasite_damage_mode(mode: String) -> String:
	return mode if mode in [PARASITE_DAMAGE_ABSORB, PARASITE_DAMAGE_LINKED] else PARASITE_DAMAGE_ABSORB


func parasite_absorbs_host_damage() -> bool:
	return is_parasite() and normalize_parasite_damage_mode(parasite_damage_mode) == PARASITE_DAMAGE_ABSORB


func is_silenced() -> bool:
	for eff in status_effects:
		if eff.get("buff_id", "") == SkillEngine.BUFF_SILENCE and eff.get("value", 0) > 0:
			return true
	return false


# ============================================
# Charm state
# ============================================

func is_charmed() -> bool:
	return original_cost != -1


func is_cost_reduced() -> bool:
	return is_charmed() or cost < base_cost


func apply_cost_reduction(amount: int, permanent: bool) -> void:
	if amount <= 0:
		return
	if permanent:
		permanent_cost_reduction = mini(base_cost, permanent_cost_reduction + amount)
	else:
		turn_cost_reduction = mini(base_cost, turn_cost_reduction + amount)
	_recalculate_cost()


func apply_cost_change(amount: int) -> void:
	if amount == 0:
		return
	match_cost_delta += amount
	_recalculate_cost()


func apply_charm_cost(slot: int) -> void:
	if not is_charmed():
		original_cost = cost
	charmed_slot = slot
	cost = 0


func reset_charm_cost() -> void:
	if original_cost >= 0:
		original_cost = -1
		charmed_slot = -1
		_recalculate_cost()


func clear_turn_cost_reduction() -> void:
	turn_cost_reduction = 0
	zero_cost_until_deploy = false
	reset_charm_cost()
	_recalculate_cost()


func clear_cost_modifiers_after_play() -> void:
	clear_turn_cost_reduction()


func _recalculate_cost() -> void:
	if is_charmed():
		cost = 0
		return
	cost = maxi(0, base_cost + match_cost_delta - permanent_cost_reduction - turn_cost_reduction)


# ============================================
# Damage & healing
# ============================================

# Temp HP consumed first, then real HP. Damage reduction applied first.
# Returns actual HP lost, excluding shield/temp HP absorption.
func take_damage(amount: int) -> int:
	if amount <= 0:
		return 0

	# Damage reduction (floor)
	var reduction_pct := get_damage_reduction()
	if reduction_pct > 0:
		var reduced := int(floor(float(amount) * (1.0 - float(reduction_pct) / 100.0)))
		print("  [DmgCut] %s reduces %d -> %d (%d%%)" % [card_name, amount, reduced, reduction_pct])
		amount = reduced

	return take_damage_without_reduction(amount)


func take_damage_without_reduction(amount: int) -> int:
	if amount <= 0:
		return 0
	var talent_cap := single_damage_cap()
	if talent_cap > 0 and amount > talent_cap:
		print("  [Talent] %s caps single damage %d -> %d" % [card_name, amount, talent_cap])
		amount = talent_cap

	var hp_before := hp
	var remaining: int = amount

	if temp_hp > 0:
		var blocked: int = min(remaining, temp_hp)
		temp_hp -= blocked
		remaining -= blocked
		print("  [TempHP] %s absorbs %d, temp left: %d" % [card_name, blocked, temp_hp])

	if remaining > 0:
		hp = max(0, hp - remaining)

	# Check immune_lethal: if damage was fatal and card has immunity, survive at 1 HP
	if hp <= 0 and immune_lethal:
		hp = 1
		immune_lethal = false
		print("  [Immune] %s survived lethal damage with 1 HP!" % card_name)
		# Check immunity from buff too
		for eff in status_effects:
			if eff.get("buff_id", "") == SkillEngine.BUFF_IMMUNE_LETHAL and eff.get("value", 0) > 0:
				eff["value"] = 0  # consume the buff
				break

	return hp_before - hp


func single_damage_cap() -> int:
	var result := 0
	for skill_value in skills:
		if not skill_value is Dictionary:
			continue
		var skill: Dictionary = skill_value
		if str(skill.get("skill_type", SkillEngine.SKILL_TYPE_NORMAL)) != SkillEngine.SKILL_TYPE_TALENT:
			continue
		if str(skill.get("trigger", "")) != SkillEngine.TRIGGER_ALWAYS:
			continue
		result = _scan_damage_cap(skill.get("effects", []), result)
	return result


func _scan_damage_cap(effects: Variant, current: int) -> int:
	if not effects is Array:
		return current
	var result := current
	for value in effects:
		if not value is Dictionary:
			continue
		var effect: Dictionary = value
		if str(effect.get("effect", "")) == SkillEngine.EFFECT_DAMAGE_CAP:
			# Continuous talents are evaluated at damage time so restored math and
			# self/target reporter blocks remain live instead of degrading to the
			# old fixed `value` field.
			var cap := maxi(1, SkillEngine._resolve_value(effect, self, self, {"source_card": self}))
			result = cap if result <= 0 else mini(result, cap)
		for branch in ["then_effects", "else_effects"]:
			result = _scan_damage_cap(effect.get(branch, []), result)
	return result


func heal(amount: int) -> int:
	if amount <= 0:
		return hp
	hp = min(max_hp, hp + amount)
	return hp


# ============================================
# Effective ATK
# ============================================

func effective_atk() -> int:
	var bonus: int = field_atk_bonus
	for eff in status_effects:
		if eff.get("buff_id", "") == SkillEngine.BUFF_ATK_BOOST:
			bonus += eff.get("value", 0)
	for parasite in parasite_cards:
		if parasite is CardData:
			bonus += parasite.atk
	return atk + bonus


func get_thorns_damage() -> int:
	var total: int = 0
	for eff in status_effects:
		if eff.get("buff_id", "") == SkillEngine.BUFF_THORNS:
			total += eff.get("value", 0)
	return total


func get_damage_reduction() -> int:
	var total: int = 0
	for eff in status_effects:
		if eff.get("buff_id", "") == SkillEngine.BUFF_DAMAGE_REDUCTION:
			total += eff.get("value", 0)
	return total


func get_misfortune() -> int:
	var total: int = 0
	for eff in status_effects:
		if eff.get("buff_id", "") == SkillEngine.BUFF_MISFORTUNE:
			total += eff.get("value", 0)
	return total


func get_mana_refund() -> int:
	var total: int = 0
	for eff in status_effects:
		if eff.get("buff_id", "") == SkillEngine.BUFF_MANA_REFUND:
			total += eff.get("value", 0)
	return total


func has_taunt() -> bool:
	for eff in status_effects:
		# Taunt is a presence-based status; its editor intentionally hides the
		# numeric value. Older/value-less cards must therefore still taunt.
		if eff.get("buff_id", "") == SkillEngine.BUFF_TAUNT:
			return true
	return false


# Stun: the card skips its next turn. Buffs are consumed by consume_stun()
# when the owner's turn starts; they are exempt from the normal duration tick.
func has_stun() -> bool:
	for eff in status_effects:
		if eff.get("buff_id", "") == SkillEngine.BUFF_STUN and eff.get("value", 0) > 0:
			return true
	return false


func consume_stun() -> bool:
	for i in range(status_effects.size()):
		if status_effects[i].get("buff_id", "") == SkillEngine.BUFF_STUN and status_effects[i].get("value", 0) > 0:
			status_effects.remove_at(i)
			print("  [Stun] %s is stunned and skips its turn" % card_name)
			return true
	return false


# ============================================
# Buff management (no merging — each buff is independent)
# ============================================

func apply_buff(buff_id: String, value: int, duration: int, owner: int = 0) -> void:
	# Temp HP is not a buff — just add to scalar

	status_effects.append({"buff_id": buff_id, "value": value, "duration": duration, "owner": owner})
	print("  [Buff] %s gained %s: v=%d d=%d (owner P%d)" % [card_name, buff_id, value, duration, owner])


func process_mana_refund(owner_player: int) -> int:
	var total: int = 0
	var to_remove: Array = []
	for i in range(status_effects.size()):
		var eff: Dictionary = status_effects[i]
		if eff.get("owner", 0) != owner_player:
			continue
		if eff.get("buff_id", "") != SkillEngine.BUFF_MANA_REFUND:
			continue
		var refund_val: int = eff.get("value", 0)
		if refund_val > 0:
			total += refund_val
			print("  [Mana+] %s refunds %d mana" % [card_name, refund_val])
		eff["duration"] = eff.get("duration", 0) - 1
		if eff["duration"] <= 0 or refund_val <= 0:
			to_remove.append(i)

	for j in range(to_remove.size() - 1, -1, -1):
		var idx: int = to_remove[j]
		var expired: Dictionary = status_effects[idx]
		print("  [Buff] %s's %s expired" % [card_name, expired.get("buff_id", "")])
		status_effects.remove_at(idx)

	return total


# Tick buffs belonging to a specific player
func tick_buffs(owner_player: int) -> void:
	var to_remove: Array = []
	for i in range(status_effects.size()):
		var eff: Dictionary = status_effects[i]
		if eff.get("owner", 0) != owner_player:
			continue
		var buff_id: String = eff.get("buff_id", "")
		if buff_id == SkillEngine.BUFF_MANA_REFUND or buff_id == SkillEngine.BUFF_STUN:
			continue

		if buff_id == SkillEngine.BUFF_REGEN:
			var regen_val: int = eff.get("value", 0)
			if regen_val > 0 and hp > 0:
				heal(regen_val)
				print("  [Regen] %s heals %d (HP: %d)" % [card_name, regen_val, hp])
		elif buff_id == SkillEngine.BUFF_POISON:
			var poison_val: int = eff.get("value", 0)
			if poison_val > 0 and hp > 0:
				hp = max(0, hp - poison_val)
				print("  [Poison] %s takes %d poison (HP: %d)" % [card_name, poison_val, hp])

		eff["duration"] = eff.get("duration", 0) - 1
		if eff["duration"] <= 0:
			to_remove.append(i)

	for j in range(to_remove.size() - 1, -1, -1):
		var idx: int = to_remove[j]
		var expired: Dictionary = status_effects[idx]
		print("  [Buff] %s's %s expired" % [card_name, expired.get("buff_id", "")])
		status_effects.remove_at(idx)


# ============================================
# Reset
# ============================================

func reset_to_base() -> void:
	turn_cost_reduction = 0
	original_cost = -1
	charmed_slot = -1
	zero_cost_until_deploy = false
	_recalculate_cost()
	max_hp = base_max_hp
	atk = base_atk
	hp = max_hp
	temp_hp = 0
	has_acted = false
	has_attacked = false
	summoned_this_turn = false
	skills_used.clear()
	skills_used_count.clear()
	status_effects.clear()
	parasite_cards.clear()
	field_atk_bonus = 0
	immune_lethal = false


# ============================================
# Copy
# ============================================

func duplicate_card() -> CardData:
	var copy := CardData.new(card_name, base_cost, base_max_hp, base_atk, skills.duplicate(true))
	copy.card_id = card_id
	copy.instance_id = instance_id
	copy.cost = cost
	copy.max_hp = max_hp
	copy.hp = hp
	copy.atk = atk
	copy.temp_hp = temp_hp
	copy.has_acted = has_acted
	copy.has_attacked = has_attacked
	copy.summoned_this_turn = summoned_this_turn
	copy.gender = gender
	copy.card_type = card_type
	copy.parasite_damage_mode = parasite_damage_mode
	copy.parasite_cards.clear()
	for parasite in parasite_cards:
		if parasite is CardData:
			copy.parasite_cards.append(parasite.duplicate_card())
	copy.charmed_slot = charmed_slot
	copy.original_cost = original_cost
	copy.permanent_cost_reduction = permanent_cost_reduction
	copy.turn_cost_reduction = turn_cost_reduction
	copy.match_cost_delta = match_cost_delta
	copy.skills_used = skills_used.duplicate()
	copy.skills_used_count = skills_used_count.duplicate()
	copy.attack_ignores_silence = attack_ignores_silence
	copy.field_atk_bonus = field_atk_bonus
	copy.immune_lethal = immune_lethal
	copy.zero_cost_until_deploy = zero_cost_until_deploy
	copy.art_path = art_path
	copy.status_effects = status_effects.duplicate(true)
	return copy


func get_status() -> String:
	var s: String = "%s | C:%d A:%d H:%d/%d" % [card_name, cost, effective_atk(), hp, max_hp]
	if temp_hp > 0:
		s += " +%dt" % temp_hp
	return s
