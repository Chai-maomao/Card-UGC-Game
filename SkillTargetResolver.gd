class_name SkillTargetResolver
extends RefCounted

const TARGET_SINGLE := "target_single"
const TARGET_SIDES := "target_sides"
const TARGET_SELF := "self"
const TARGET_SELF_SIDES := "self_sides"
const TARGET_ALL := "all"
const TARGET_MALE := "target_male"
const TARGET_FEMALE := "target_female"
const TARGET_NONHUMAN := "target_nonhuman"

const TARGET_SIDE_ENEMY := "enemy"
const TARGET_SIDE_ALLY := "ally"
const TARGET_SIDE_ALL := "all"

# ============================================
# Skill target normalization and resolution
# ============================================

static func is_directed_target(target_str: String) -> bool:
	return target_str in [TARGET_SELF, TARGET_SELF_SIDES, TARGET_SINGLE, TARGET_SIDES]


static func default_target_side(target_str: String) -> String:
	# Legacy save compat: old cards may store the pre-combined "all_enemies" /
	# "all_allies" targets; map them to their implicit side.
	if target_str == "all_enemies":
		return TARGET_SIDE_ENEMY
	if target_str == "all_allies":
		return TARGET_SIDE_ALLY
	return TARGET_SIDE_ALL


static func normalize_effect_target(eff: Dictionary) -> Dictionary:
	var normalized := eff.duplicate(true)
	var target_str: String = normalized.get("target", TARGET_SINGLE)
	# Legacy save compat: split the old pre-combined "all_enemies"/"all_allies"
	# targets into the two-dimensional side + target form.
	if target_str == "all_enemies":
		normalized["target"] = TARGET_ALL
		normalized["target_side"] = TARGET_SIDE_ENEMY
	elif target_str == "all_allies":
		normalized["target"] = TARGET_ALL
		normalized["target_side"] = TARGET_SIDE_ALLY
	elif not normalized.has("target_side"):
		normalized["target_side"] = TARGET_SIDE_ALL
	return normalized


static func resolve_targets(target_str: String, source_card: CardData, context: Dictionary, target_side: String = TARGET_SIDE_ALL) -> Array:
	match target_str:
		TARGET_SELF:
			return [source_card]
		TARGET_SINGLE:
			return _resolve_directed_target(source_card, context, false, target_side)
		TARGET_SIDES:
			return _resolve_directed_target(source_card, context, true, target_side)
		TARGET_SELF_SIDES:
			return _resolve_self_adjacent(source_card, context)
		# Legacy save compat: un-normalized old cards may still carry the
		# pre-combined "all_enemies"/"all_allies" targets.
		"all_enemies":
			return _resolve_cards_by_side(source_card, context, TARGET_SIDE_ENEMY)
		"all_allies":
			return _resolve_cards_by_side(source_card, context, TARGET_SIDE_ALLY)
		TARGET_ALL:
			return _resolve_cards_by_side(source_card, context, target_side)
		TARGET_MALE:
			return _resolve_by_gender(source_card, context, "male", target_side)
		TARGET_FEMALE:
			return _resolve_by_gender(source_card, context, "female", target_side)
		TARGET_NONHUMAN:
			return _resolve_by_gender(source_card, context, "nonhuman", target_side)
	return []


static func enemy_field_of_source(source_card: CardData, context: Dictionary) -> BattleField:
	var pf: BattleField = context.get("player_field")
	var ef: BattleField = context.get("enemy_field")
	if pf != null and source_card in pf.slots:
		return ef
	if ef != null and source_card in ef.slots:
		return pf
	return ef


static func targets_include_enemy(targets: Array, source_card: CardData, context: Dictionary) -> bool:
	var enemy_field: BattleField = enemy_field_of_source(source_card, context)
	if enemy_field == null:
		return false
	for t in targets:
		if t != null and t in enemy_field.slots:
			return true
	return false


static func _source_field_of(source_card: CardData, context: Dictionary) -> BattleField:
	var pf: BattleField = context.get("player_field")
	var ef: BattleField = context.get("enemy_field")
	if pf != null and source_card in pf.slots:
		return pf
	if ef != null and source_card in ef.slots:
		return ef
	return pf


static func _resolve_directed_target(source_card: CardData, context: Dictionary, include_sides: bool, target_side: String = TARGET_SIDE_ENEMY) -> Array:
	var target_slot: int = context.get("target_slot", -1)
	if target_slot < 0:
		return []
	var field: BattleField = _directed_target_field(source_card, context, target_side)
	if field == null:
		return []
	return _cards_around_slot(field, target_slot, include_sides)


static func _directed_target_field(source_card: CardData, context: Dictionary, target_side: String) -> BattleField:
	match target_side:
		TARGET_SIDE_ALLY:
			return _source_field_of(source_card, context)
		TARGET_SIDE_ENEMY:
			return enemy_field_of_source(source_card, context)
	return enemy_field_of_source(source_card, context)


static func _resolve_self_adjacent(source_card: CardData, context: Dictionary) -> Array:
	var field: BattleField = _source_field_of(source_card, context)
	if field == null:
		return []
	var source_slot: int = field.slots.find(source_card)
	if source_slot < 0:
		source_slot = int(context.get("source_slot", -1))
	return _cards_around_slot(field, source_slot, true)


static func _cards_around_slot(field: BattleField, center: int, include_sides: bool) -> Array:
	var result: Array = []
	if center < 0 or center >= field.slots.size():
		return result
	if field.slots[center] != null:
		result.append(field.slots[center])
	if include_sides:
		for offset in [-1, 1]:
			var adj: int = center + offset
			if adj >= 0 and adj < field.slots.size() and field.slots[adj] != null:
				result.append(field.slots[adj])
	return result


static func _resolve_cards_by_side(source_card: CardData, context: Dictionary, target_side: String) -> Array:
	var result: Array = []
	var source_field := _source_field_of(source_card, context)
	var enemy_field := enemy_field_of_source(source_card, context)
	var fields: Array = []
	match target_side:
		TARGET_SIDE_ENEMY:
			fields = [enemy_field]
		TARGET_SIDE_ALLY:
			fields = [source_field]
		_:
			fields = [enemy_field, source_field]
	for field in fields:
		if field == null:
			continue
		for slot in field.slots:
			if slot != null and slot.is_alive():
				result.append(slot)
	return result


static func _resolve_by_gender(source_card: CardData, context: Dictionary, gender: String, target_side: String = TARGET_SIDE_ALL) -> Array:
	var result: Array = []
	for slot in _resolve_cards_by_side(source_card, context, target_side):
		if slot != null and slot.is_alive() and slot.gender == gender:
			result.append(slot)
	return result
