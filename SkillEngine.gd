class_name SkillEngine
extends SkillRegistry

const _TargetResolver = preload("res://SkillTargetResolver.gd")
const _EffectApplier = preload("res://SkillEffectApplier.gd")
const _TextFormatter = preload("res://SkillTextFormatter.gd")
const _UgcSafety = preload("res://UgcSafety.gd")
const _GameplayRng = preload("res://GameplayRng.gd")

const MAX_HAND_SIZE = 6

# ============================================
# Skill execution engine
# ============================================
# SkillEngine inherits from SkillRegistry, so every identifier constant
# (TRIGGER_*, TARGET_*, EFFECT_*, BUFF_*, VAR_*, CONDITION_*) is available as
# SkillEngine.* directly — adding a new effect only touches SkillRegistry.
# Metadata (editor lists, handlers, templates, balance weights) lives there
# too; the engine below only handles execution flow.


# ============================================
# Main entry
# ============================================

static func _is_talent_skill(skill: Dictionary) -> bool:
	return skill.get("skill_type", SKILL_TYPE_NORMAL) == SKILL_TYPE_TALENT


static func _check_max_uses(card: CardData, skill: Dictionary, skill_index: int) -> bool:
	var max_uses: int = skill.get("max_uses", 0)
	if max_uses <= 0:
		return true  # unlimited
	var count: int = card.skills_used_count.get(skill_index, 0)
	if count >= max_uses:
		print("[SkillEngine] %s: max_uses (%d) reached for '%s'" % [card.card_name, max_uses, skill.get("skill_name", "???")])
		return false
	return true


static func _mark_skill_used(card: CardData, skill_index: int) -> void:
	card.skills_used_count[skill_index] = card.skills_used_count.get(skill_index, 0) + 1


static func trigger_skills(trigger: String, source_card: CardData, context: Dictionary) -> void:
	if source_card == null or source_card.skills.is_empty():
		return
	var budget := _ensure_budget(context)
	if not _enter_trigger_budget(budget, source_card):
		return
	var silenced := source_card.is_silenced()
	var trigger_context := context.duplicate()
	trigger_context["trigger"] = trigger

	for skill_index in range(source_card.skills.size()):
		var skill_dict: Dictionary = source_card.skills[skill_index]
		if skill_dict.get("trigger", "") != trigger:
			continue
		# Talent skills bypass silence; normal skills are blocked
		if silenced and not _is_talent_skill(skill_dict):
			continue
		if not _check_max_uses(source_card, skill_dict, skill_index):
			continue
		if _passes_skill_roll(skill_dict, source_card, trigger_context):
			_execute_skill(skill_dict, source_card, trigger_context)
			_mark_skill_used(source_card, skill_index)
	_leave_trigger_budget(budget)


static func trigger_single_skill(card: CardData, skill_index: int, context: Dictionary) -> void:
	if card == null or skill_index < 0 or skill_index >= card.skills.size():
		return
	var budget := _ensure_budget(context)
	if not _enter_trigger_budget(budget, card):
		return
	var skill_dict: Dictionary = card.skills[skill_index]
	if card.is_silenced() and not _is_talent_skill(skill_dict):
		_leave_trigger_budget(budget)
		return
	if not _check_max_uses(card, skill_dict, skill_index):
		_leave_trigger_budget(budget)
		return
	var single_context := context.duplicate()
	single_context["trigger"] = skill_dict.get("trigger", "")
	if _passes_skill_roll(skill_dict, card, single_context):
		_execute_skill(skill_dict, card, single_context)
		_mark_skill_used(card, skill_index)
	_leave_trigger_budget(budget)


static func trigger_external_skill(skill: Dictionary, source_card: CardData, context: Dictionary) -> void:
	if source_card == null or skill.is_empty():
		return
	var budget := _ensure_budget(context)
	if not _enter_trigger_budget(budget, source_card):
		return
	if source_card.is_silenced() and not _is_talent_skill(skill):
		_leave_trigger_budget(budget)
		return
	var external_context := context.duplicate()
	external_context["trigger"] = skill.get("trigger", "")
	if _passes_skill_roll(skill, source_card, external_context):
		_execute_skill(skill, source_card, external_context)
	_leave_trigger_budget(budget)


static func _execute_skill(skill: Dictionary, source_card: CardData, context: Dictionary) -> void:
	var skill_name: String = skill.get("skill_name", "???")
	_execute_effects(legacy_skill_effects(skill), source_card, context, skill_name, 1)


static func _execute_effects(effects: Array, source_card: CardData, context: Dictionary, skill_name: String, depth: int = 1) -> void:
	if depth > _UgcSafety.MAX_EFFECT_NESTING_DEPTH:
		_abort_budget(_ensure_budget(context), source_card, "effect_depth")
		return
	for eff in effects:
		if not _consume_effect_budget(_ensure_budget(context), source_card):
			return
		var eff_dict: Dictionary = eff
		if str(eff_dict.get("effect", "")) in [EFFECT_IF_ELSE, EFFECT_IF]:
			_execute_if_else(eff_dict, source_card, context, skill_name, depth)
			continue
		if str(eff_dict.get("effect", "")) == EFFECT_REPEAT:
			_execute_repeat(eff_dict, source_card, context, skill_name, depth)
			continue
		if str(eff_dict.get("effect", "")) == EFFECT_STOP:
			# Stop block: halts the remaining effects of the current block
			# (top-level skill, or the current then/else branch).
			print("[SkillEngine] %s: stop — halting current block" % skill_name)
			return
		if not _passes_effect_roll(eff_dict, source_card, context):
			continue

		var target_str: String = eff_dict.get("target", TARGET_SINGLE)
		var target_side: String = eff_dict.get("target_side", _TargetResolver.default_target_side(target_str))
		var effect_str: String = eff_dict.get("effect", EFFECT_DAMAGE)
		var value: int = _resolve_value(eff_dict, source_card, context)
		if bool(_ensure_budget(context).get("aborted", false)):
			return
		var targets: Array = _TargetResolver.resolve_targets(target_str, source_card, context, target_side)
		targets = _limit_random_targets(targets, int(eff_dict.get("random_count", 0)), context)

		# Effects that don't need a live battlefield target (draw, mana, zero_cost, etc.)
		# operate on the hand/deck — skip the turn-1 enemy filter for them.
		var needs_live_target: bool = not SkillRegistry.is_hand_effect(effect_str)
		if needs_live_target and _is_enemy_effect_blocked_on_turn_one(targets, source_card, context):
			print("[SkillEngine] Turn 1: '%s' enemy-targeting effect skipped" % skill_name)
			continue

		print("[SkillEngine] %s: %s -> %s x%d on %d target(s)" % [skill_name, effect_str, target_str, value, targets.size()])
		var effect_context := context.duplicate()
		effect_context["source_card"] = source_card
		effect_context["effect_target"] = target_str
		effect_context["random_count"] = int(eff_dict.get("random_count", 0))
		if not needs_live_target:
			# Hand/deck effects still honor conditions, evaluated against the source
			# card as the pseudo-target (e.g. "if hand count >= N").
			if not _passes_effect_condition(eff_dict, source_card, source_card, context):
				continue
			_EffectApplier.apply_effect(effect_str, source_card, value, eff_dict, effect_context)
			continue
		for target_card in targets:
			var allow_dead_source: bool = target_card == source_card and context.get("trigger", "") == TRIGGER_ON_DEATH
			if target_card == null or (not target_card.is_alive() and not allow_dead_source):
				continue
			if not _passes_effect_condition(eff_dict, source_card, target_card, context):
				continue
			_EffectApplier.apply_effect(effect_str, target_card, value, eff_dict, effect_context)


# Control block: evaluates its condition against the source card and runs the
# matching then/else sub-effects recursively. Supports both "if () then" and
# "if () then else" control blocks (else_effects stays empty for the former).
static func _execute_if_else(eff: Dictionary, source_card: CardData, context: Dictionary, skill_name: String, depth: int) -> void:
	var cond := _condition_dict(eff)
	var take_then: bool = _passes_effect_condition(cond, source_card, source_card, context)
	print("[SkillEngine] %s: if -> %s" % [skill_name, "then" if take_then else "else"])
	if take_then:
		_execute_effects(eff.get("then_effects", []), source_card, context, skill_name, depth + 1)
	else:
		_execute_effects(eff.get("else_effects", []), source_card, context, skill_name, depth + 1)


# Control block: repeats its then-effects N times (Scratch-style "repeat N"
# C-shaped block). N may be a plain number or a variable reporter oval.
# A stop block inside the body halts the current iteration only; subsequent
# iterations still run.
static func _execute_repeat(eff: Dictionary, source_card: CardData, context: Dictionary, skill_name: String, depth: int) -> void:
	var times: int = mini(_repeat_count(eff, source_card, context), _UgcSafety.MAX_REPEAT_COUNT)
	print("[SkillEngine] %s: repeat x%d" % [skill_name, times])
	for _i in range(times):
		_execute_effects(eff.get("then_effects", []), source_card, context, skill_name, depth + 1)
		if bool(_ensure_budget(context).get("aborted", false)):
			return


static func _ensure_budget(context: Dictionary) -> Dictionary:
	var budget = context.get("_ugc_budget", null)
	if budget is Dictionary:
		return budget
	budget = {"effect_nodes": 0, "trigger_depth": 0, "aborted": false, "notified": false}
	context["_ugc_budget"] = budget
	return budget


static func _enter_trigger_budget(budget: Dictionary, source_card: CardData) -> bool:
	if bool(budget.get("aborted", false)):
		return false
	budget["trigger_depth"] = int(budget.get("trigger_depth", 0)) + 1
	if int(budget["trigger_depth"]) > _UgcSafety.MAX_TRIGGER_CHAIN_DEPTH:
		_abort_budget(budget, source_card, "trigger_depth")
		budget["trigger_depth"] = int(budget["trigger_depth"]) - 1
		return false
	return true


static func _leave_trigger_budget(budget: Dictionary) -> void:
	budget["trigger_depth"] = maxi(0, int(budget.get("trigger_depth", 0)) - 1)


static func _consume_effect_budget(budget: Dictionary, source_card: CardData) -> bool:
	if bool(budget.get("aborted", false)):
		return false
	budget["effect_nodes"] = int(budget.get("effect_nodes", 0)) + 1
	if int(budget["effect_nodes"]) > _UgcSafety.MAX_EXECUTED_EFFECT_NODES:
		_abort_budget(budget, source_card, "effect_nodes")
		return false
	return true


static func _abort_budget(budget: Dictionary, source_card: CardData, reason: String) -> void:
	budget["aborted"] = true
	if bool(budget.get("notified", false)):
		return
	budget["notified"] = true
	var source_name := source_card.card_name if source_card != null else "?"
	push_warning("[SkillEngine] UGC safety limit hit: %s (%s)" % [source_name, reason])
	EventBus.skill_safety_limit_hit.emit(source_name, reason)


static func _repeat_count(eff: Dictionary, source_card: CardData, context: Dictionary) -> int:
	if eff.has("repeat_expr"):
		return maxi(0, _eval_operand(eff.get("repeat_expr", {}), source_card, null, context))
	var var_id: String = eff.get("repeat_var", "")
	if var_id != "":
		return maxi(0, _var_value(var_id, source_card, null, context))
	return maxi(0, int(eff.get("repeat_count", 2)))


# The if-block condition may live in a nested "condition" reporter dictionary
# (block editor) or directly on the effect (legacy format). Returns whichever
# holds the condition fields.
static func _condition_dict(eff: Dictionary) -> Dictionary:
	var c: Variant = eff.get("condition", {})
	if c is Dictionary and not c.is_empty():
		return c
	return eff


# Legacy single-effect skill format ("effect"/"value"/"buff_id"/"duration" at
# the skill root) normalized to the standard effects array. Single shared
# implementation used by the engine, tooltips and both editors.
static func legacy_skill_effects(skill: Dictionary) -> Array:
	var effects: Array = skill.get("effects", [])
	if not effects.is_empty():
		return effects
	if skill.get("effect", "").is_empty():
		return []
	return [{
		"target": skill.get("target", TARGET_SINGLE),
		"target_side": skill.get("target_side", TARGET_SIDE_ALL),
		"effect": skill.get("effect", EFFECT_DAMAGE),
		"value": skill.get("value", 1),
		"buff_id": skill.get("buff_id", ""),
		"duration": skill.get("duration", 0),
	}]


# ============================================
# Chance and targeting rules
# ============================================

static func _passes_skill_roll(skill: Dictionary, source_card: CardData, context: Dictionary) -> bool:
	var prob: int = skill.get("probability", 100)
	var misfortune: int = source_card.get_misfortune()
	if misfortune > 0:
		prob = max(0, prob - misfortune)
		print("[SkillEngine] %s: misfortune -%d%% (eff: %d%%)" % [skill.get("skill_name", "???"), misfortune, prob])
	if prob < 100 and _roll_percent(context) > float(prob):
		print("[SkillEngine] %s: %d%% roll failed — skipped" % [skill.get("skill_name", "???"), prob])
		EventBus.skill_roll_failed.emit(source_card, skill.get("skill_name", "技能"), misfortune, prob)
		return false
	return true


static func _passes_effect_roll(eff: Dictionary, source_card: CardData, context: Dictionary) -> bool:
	var prob: int = eff.get("probability", 100)
	var misfortune: int = source_card.get_misfortune()
	if misfortune > 0:
		prob = max(0, prob - misfortune)
	if prob < 100 and _roll_percent(context) > float(prob):
		print("[SkillEngine] Effect skipped: %d%% roll failed" % prob)
		EventBus.skill_roll_failed.emit(source_card, source_card.card_name if source_card != null else "效果", misfortune, prob)
		return false
	return true


static func _passes_effect_condition(eff: Dictionary, source_card: CardData, target_card: CardData, context: Dictionary) -> bool:
	# Scratch-style boolean block, stored either in a nested "condition" dict
	# (same shape as if blocks, e.g. {op, lhs, rhs} or {logic, lhs, rhs}) or
	# directly on the effect dict for legacy data.
	var cond: Dictionary = eff
	var nested: Variant = eff.get("condition", null)
	if nested is Dictionary and not (nested as Dictionary).is_empty():
		cond = nested
	if cond.has("lhs") or cond.has("logic"):
		return _eval_boolean(cond, source_card, target_card, context)
	var condition_type: String = eff.get("condition_type", CONDITION_NONE)
	if condition_type == "" or condition_type == CONDITION_NONE:
		return true
	var op: String = eff.get("condition_op", CONDITION_OP_GTE)
	if condition_type == CONDITION_TARGET_HAS_BUFF:
		var buff_id: String = eff.get("condition_buff_id", "")
		return buff_id != "" and _card_has_buff(target_card, buff_id)
	var actual: int = _condition_value(condition_type, source_card, target_card, context)
	var expected: int = int(eff.get("condition_value", 0))
	return _compare_condition(actual, expected, op)


# Evaluates a Scratch-style boolean reporter block. The comparison form is
# "[operand] [op] [operand]" where each operand is a number, a variable oval
# or a math expression; the special "has" form is "[target] has [buff]";
# and "and"/"or"/"not" combine sub-reports (each a full boolean block).
static func _eval_boolean(cond: Dictionary, source_card: CardData, target_card: CardData, context: Dictionary, depth: int = 1) -> bool:
	if depth > _UgcSafety.MAX_EXPRESSION_NESTING_DEPTH:
		_abort_budget(_ensure_budget(context), source_card, "expression_depth")
		return false
	if cond.has("logic"):
		var logic: String = str(cond.get("logic", "and"))
		if logic == "not":
			return not _eval_boolean(cond.get("child", {}), source_card, target_card, context, depth + 1)
		var a := _eval_boolean(cond.get("lhs", {}), source_card, target_card, context, depth + 1)
		var b := _eval_boolean(cond.get("rhs", {}), source_card, target_card, context, depth + 1)
		if logic == "or":
			return a or b
		return a and b
	var op: String = str(cond.get("op", CONDITION_OP_GTE))
	if op == "has":
		var rhs: Dictionary = cond.get("rhs", {})
		var buff_id: String = str(rhs.get("buff_id", ""))
		return buff_id != "" and _card_has_buff(target_card, buff_id)
	var actual: int = _eval_operand(cond.get("lhs", {}), source_card, target_card, context, depth + 1)
	var expected: int = _eval_operand(cond.get("rhs", {}), source_card, target_card, context, depth + 1)
	return _compare_condition(actual, expected, op)


# Resolves one side of a comparison (or a value expression): a fixed number,
# a variable reporter, or a nested math expression like "(hand+2)*3".
static func _eval_operand(opd: Dictionary, source_card: CardData, target_card: CardData, context: Dictionary, depth: int = 1) -> int:
	if depth > _UgcSafety.MAX_EXPRESSION_NESTING_DEPTH:
		_abort_budget(_ensure_budget(context), source_card, "expression_depth")
		return 0
	var kind: String = str(opd.get("kind", "num"))
	match kind:
		"var":
			return _var_value(str(opd.get("var_id", "")), source_card, target_card, context)
		"expr":
			var op: String = str(opd.get("op", "+"))
			var a := _eval_operand(opd.get("a", {}), source_card, target_card, context, depth + 1)
			var b := _eval_operand(opd.get("b", {}), source_card, target_card, context, depth + 1)
			match op:
				"-":
					return a - b
				"*":
					return a * b
				"/":
					return int(floor(float(a) / float(b))) if b != 0 else 0
				"rand":
					if b < a:
						var t: int = a
						a = b
						b = t
					return _GameplayRng.from_context(context).randi_range(a, b)
				_:
					return a + b
	return int(opd.get("value", 0))


static func _condition_value(condition_type: String, source_card: CardData, target_card: CardData, context: Dictionary) -> int:
	match condition_type:
		CONDITION_SOURCE_HP_PCT:
			return _hp_percent(source_card)
		CONDITION_TARGET_HP_PCT:
			return _hp_percent(target_card)
		CONDITION_FIELD_ALLY:
			return _count_cards(context.get("player_field"))
		CONDITION_FIELD_ENEMY:
			return _count_cards(context.get("enemy_field"))
		CONDITION_HAND_COUNT:
			var hand: Array = context.get("active_hand", [])
			return hand.size() if hand != null else 0
		CONDITION_MANA_CURRENT:
			var pf: BattleField = context.get("player_field")
			return pf.current_mana if pf != null else 0
		CONDITION_TARGET_ATK:
			return target_card.effective_atk() if target_card != null else 0
		CONDITION_TARGET_COST:
			return target_card.cost if target_card != null else 0
		CONDITION_ENEMY_HAND_COUNT:
			var enemy_hand: Array = context.get("enemy_hand", [])
			return enemy_hand.size() if enemy_hand != null else 0
		CONDITION_TURN_NUMBER:
			return int(context.get("turn_number", 0))
		CONDITION_DECK_COUNT:
			var deck: Array = context.get("shared_deck", [])
			return deck.size() if deck != null else 0
	return 0


static func _hp_percent(card: CardData) -> int:
	if card == null or card.max_hp <= 0:
		return 0
	return int(round(float(card.hp) * 100.0 / float(card.max_hp)))


static func _card_has_buff(card: CardData, buff_id: String) -> bool:
	if card == null:
		return false
	for eff in card.status_effects:
		if eff.get("buff_id", "") == buff_id and eff.get("value", 0) > 0:
			return true
	return false


static func _compare_condition(actual: int, expected: int, op: String) -> bool:
	match op:
		CONDITION_OP_LTE:
			return actual <= expected
		CONDITION_OP_EQ:
			return actual == expected
	return actual >= expected


static func _limit_random_targets(targets: Array, random_count: int, context: Dictionary) -> Array:
	if random_count <= 0 or targets.size() <= random_count:
		return targets
	_shuffle_targets(targets, context)
	return targets.slice(0, random_count)


static func _is_enemy_effect_blocked_on_turn_one(targets: Array, source_card: CardData, context: Dictionary) -> bool:
	var turn_no: int = int(context.get("turn_number", 99))
	return turn_no <= 1 and _TargetResolver.targets_include_enemy(targets, source_card, context)


static func _roll_percent(context: Dictionary) -> float:
	return _GameplayRng.from_context(context).randf() * 100.0


static func _shuffle_targets(targets: Array, context: Dictionary) -> void:
	_GameplayRng.shuffle(targets, _GameplayRng.from_context(context))


# ============================================
# Dynamic values
# ============================================

static func _resolve_value(eff: Dictionary, source_card: CardData, context: Dictionary) -> int:
	# A dropped math-expression reporter (e.g. (hand+2)*3) drives the value.
	if eff.has("value_expr"):
		return _eval_operand(eff.get("value_expr", {}), source_card, source_card, context)
	var var_id: String = eff.get("value_var", "")
	if var_id != "":
		var offset: int = int(eff.get("value_offset", 0))
		# Value reporters never depend on a single target (battlefield / hand /
		# mana stats); target-relative reporters fall back to the source card.
		return _var_value(var_id, source_card, source_card, context) + offset
	if eff.has("value_min") and eff.has("value_max"):
		var vmin: int = int(eff.get("value_min", 1))
		var vmax: int = int(eff.get("value_max", 1))
		if vmax < vmin:
			var t: int = vmin
			vmin = vmax
			vmax = t
		return _GameplayRng.from_context(context).randi_range(vmin, vmax)
	return int(eff.get("value", 1))


static func _var_value(var_id: String, source_card: CardData, target_card: CardData, context: Dictionary) -> int:
	var pf: BattleField = context.get("player_field")
	var ef: BattleField = context.get("enemy_field")
	var hand: Array = context.get("active_hand", [])
	var enemy_hand: Array = context.get("enemy_hand", [])
	match var_id:
		VAR_FIELD_TOTAL:
			return _count_cards(pf) + _count_cards(ef)
		VAR_FIELD_ALLY:
			return _count_cards(pf)
		VAR_FIELD_ENEMY:
			return _count_cards(ef)
		VAR_EMPTY_ALLY:
			return (pf.slots.size() - _count_cards(pf)) if pf != null else 0
		VAR_EMPTY_ENEMY:
			return (ef.slots.size() - _count_cards(ef)) if ef != null else 0
		VAR_HAND_COUNT:
			return hand.size() if hand != null else 0
		VAR_MANA_CURRENT:
			return pf.current_mana if pf != null else 0
		VAR_ENEMY_HAND_COUNT:
			return enemy_hand.size() if enemy_hand != null else 0
		VAR_TURN_NUMBER:
			return int(context.get("turn_number", 0))
		VAR_DECK_COUNT:
			var deck: Array = context.get("shared_deck", [])
			return deck.size() if deck != null else 0
		VAR_ENEMY_MANA:
			return ef.current_mana if ef != null else 0
		VAR_SOURCE_HP_PCT:
			return _hp_percent(source_card)
		VAR_TARGET_HP_PCT:
			return _hp_percent(target_card)
		VAR_TARGET_ATK:
			return target_card.effective_atk() if target_card != null else 0
		VAR_TARGET_COST:
			return target_card.cost if target_card != null else 0
	return 0


static func _count_cards(field: BattleField) -> int:
	if field == null:
		return 0
	var n := 0
	for slot in field.slots:
		if slot != null:
			n += 1
	return n


# ============================================
# Compatibility wrappers
# ============================================

static func _is_directed_target(target_str: String) -> bool:
	return _TargetResolver.is_directed_target(target_str)


static func _default_target_side(target_str: String) -> String:
	return _TargetResolver.default_target_side(target_str)


static func normalize_effect_target(eff: Dictionary) -> Dictionary:
	return _TargetResolver.normalize_effect_target(eff)


static func _resolve_targets(target_str: String, source_card: CardData, context: Dictionary, target_side: String = TARGET_SIDE_ALL) -> Array:
	return _TargetResolver.resolve_targets(target_str, source_card, context, target_side)


static func _targets_include_enemy(targets: Array, source_card: CardData, context: Dictionary) -> bool:
	return _TargetResolver.targets_include_enemy(targets, source_card, context)


static func _enemy_field_of_source(source_card: CardData, context: Dictionary) -> BattleField:
	return _TargetResolver.enemy_field_of_source(source_card, context)


static func _apply_effect(effect_str: String, target: CardData, value: int, skill: Dictionary, context: Dictionary) -> void:
	_EffectApplier.apply_effect(effect_str, target, value, skill, context)


static func format_buff_value(buff_id: String, value_text: String, is_zh: bool = Locale.language == "zh") -> String:
	return _TextFormatter.format_buff_value(buff_id, value_text, is_zh)


static func _format_effect_sentence(eff: Dictionary) -> String:
	return _TextFormatter.format_effect_sentence(eff)


static func _describe_value(eff: Dictionary) -> String:
	return _TextFormatter.describe_value(eff)


static func format_skill_tooltip(skill: Dictionary) -> String:
	return _TextFormatter.format_skill_tooltip(skill)
