class_name SkillTextFormatter
extends RefCounted

const _TargetResolver = preload("res://SkillTargetResolver.gd")

# ============================================
# Skill tooltip and editor text formatting
# ============================================

static func format_buff_value(buff_id: String, value_text: String, is_zh: bool = Locale.language == "zh") -> String:
	match buff_id:
		SkillEngine.BUFF_ATK_BOOST:
			return "攻击 +%s" % value_text if is_zh else "+%s attack" % value_text
		SkillEngine.BUFF_REGEN:
			return "在效果来源一方的回合开始时回复 %s 点生命" % value_text if is_zh else "Restore %s HP at the start of the turn of the player who granted Regeneration" % value_text
		SkillEngine.BUFF_MANA_REFUND:
			return "施加者回合结束时获得 %s 点圣水" % value_text if is_zh else "The caster gains %s elixir at the end of their turn" % value_text
		SkillEngine.BUFF_THORNS:
			return "受到普通攻击时反弹 %s 点伤害" % value_text if is_zh else "Reflect %s damage when hit by a basic attack" % value_text
		SkillEngine.BUFF_DAMAGE_REDUCTION:
			return "受到的伤害减少 %s%%" % value_text if is_zh else "Take %s%% less damage" % value_text
		SkillEngine.BUFF_DODGE:
			return "有 %s%% 概率使指向自己的行动失效" % value_text if is_zh else "%s%% chance to dodge an action targeting this unit" % value_text
		SkillEngine.BUFF_UNTARGETABLE:
			return "无法被指向性行动选中" if is_zh else "Cannot be chosen by targeted actions"
		SkillEngine.BUFF_TAUNT:
			return "嘲讽" if is_zh else "taunt"
		SkillEngine.BUFF_SILENCE:
			return "沉默" if is_zh else "silence"
		SkillEngine.BUFF_STUN:
			return "眩晕" if is_zh else "stun"
		SkillEngine.BUFF_MISFORTUNE:
			return "技能发动概率降低 %s 个百分点" % value_text if is_zh else "Skill activation chance drops by %s percentage points" % value_text
		SkillEngine.BUFF_LUCK:
			return "技能发动概率提高 %s 个百分点" % value_text if is_zh else "Skill activation chance rises by %s percentage points" % value_text
		SkillEngine.BUFF_POISON:
			return "己方回合结束时失去 %s 点生命" % value_text if is_zh else "Lose %s HP at the end of this unit's turn" % value_text
		SkillEngine.BUFF_IMMUNE_LETHAL:
			return "免疫致命伤害" if is_zh else "immune to lethal damage"
	return value_text


static func status_time_left(effect: Dictionary) -> String:
	var buff: String = effect.get("buff_id", "")
	if buff == SkillEngine.BUFF_IMMUNE_LETHAL:
		return Locale.t("card.status_lethal_once")
	var duration := int(effect.get("duration", 0))
	if buff == SkillEngine.BUFF_STUN:
		duration = maxi(1, duration)
	return Locale.t("card.status_turn_left" if duration == 1 else "card.status_turns_left", [duration])


static func format_effect_sentence(eff: Dictionary) -> String:
	var normalized := _TargetResolver.normalize_effect_target(eff)
	var effect_id: String = normalized.get("effect", "")
	# Control blocks (if / if-else / repeat / stop) have their own recursive
	# sentence form — the effect_sentence templates don't cover them.
	if effect_id in [SkillEngine.EFFECT_IF_ELSE, SkillEngine.EFFECT_IF,
			SkillEngine.EFFECT_REPEAT, SkillEngine.EFFECT_STOP]:
		return format_control_sentence(normalized)
	var target: String = _format_target_name(normalized)
	var vstr: String = describe_value(normalized)
	var sentence := ""

	if effect_id == SkillEngine.EFFECT_ADD_BUFF:
		sentence = _format_status_sentence(normalized, target, vstr)
	else:
		var template_key := _sentence_template_key(normalized)
		var prose_key := template_key
		if effect_id in [SkillEngine.EFFECT_GAIN_MANA, SkillEngine.EFFECT_GAIN_ATTACK,
				SkillEngine.EFFECT_GAIN_MAX_HP, SkillEngine.EFFECT_CHANGE_COST] and vstr.is_valid_int():
			prose_key += "_loss" if vstr.begins_with("-") else "_gain"
		var template := Locale.term("effect_prose", prose_key)
		if template != prose_key:
			sentence = _render_sentence(template, normalized, target, vstr.trim_prefix("-") if prose_key.ends_with("_loss") else vstr)
		else:
			template = Locale.term("effect_sentence", template_key)
			sentence = "%s %s %s" % [target, Locale.term("effect", effect_id), vstr] if template == template_key \
				else _render_sentence(template, normalized, target, vstr)
	return sentence + _sentence_suffix(normalized)


static func _format_status_sentence(effect: Dictionary, target: String, value: String) -> String:
	var buff_id: String = effect.get("buff_id", "")
	var name := Locale.term("buff", buff_id)
	var template := Locale.term("status_sentence", buff_id)
	if template == buff_id:
		template = _value_template(Locale.term("effect_sentence", "add_buff"), effect)
		return _render_sentence(template, effect, target, value, name, format_buff_value(buff_id, value))
	if Locale.language == "zh" and effect.get("target") == SkillEngine.TARGET_SELF:
		target = ""
	if value.is_empty() and SkillRegistry.buff_uses_value(buff_id):
		template = Locale.term("status_sentence", "name_only")
	var sentence := _render_sentence(template, effect, target, value, name)
	if buff_id != SkillEngine.BUFF_IMMUNE_LETHAL:
		var duration := int(effect.get("duration", 1))
		if buff_id == SkillEngine.BUFF_STUN:
			duration = maxi(1, duration)
		var timing := "duration_one" if duration == 1 else "duration"
		sentence += Locale.term("status_sentence", timing).replace("{duration}", str(duration))
	return sentence


# Recursive human-readable form for control blocks, used by the skill preview
# and card tooltips: "如果 [条件] 那么：a；b" / "重复 N 次：a" / "跳出当前条件".
static func format_control_sentence(eff: Dictionary) -> String:
	if SkillRegistry.is_chance_block(eff):
		return Locale.t("skill_editor.chance_sentence") % [int(eff.condition.rhs.value), _format_sub_effects(eff.get("then_effects", []))]
	var effect_id: String = str(eff.get("effect", ""))
	match effect_id:
		SkillEngine.EFFECT_IF:
			return Locale.t("skill_editor.if_sentence") % [format_condition_sentence(eff), _format_sub_effects(eff.get("then_effects", []))]
		SkillEngine.EFFECT_IF_ELSE:
			var otherwise := _format_sub_effects(eff.get("else_effects", []))
			if otherwise.is_empty():
				return Locale.t("skill_editor.if_sentence") % [format_condition_sentence(eff), _format_sub_effects(eff.get("then_effects", []))]
			return Locale.t("skill_editor.if_else_sentence") \
					% [format_condition_sentence(eff), _format_sub_effects(eff.get("then_effects", [])), otherwise]
		SkillEngine.EFFECT_REPEAT:
			return Locale.t("skill_editor.repeat_sentence") \
					% [describe_repeat_count(eff), _format_sub_effects(eff.get("then_effects", []))]
		SkillEngine.EFFECT_STOP:
			return Locale.t("skill_editor.stop_sentence")
	return ""


static func _format_sub_effects(list: Array) -> String:
	var parts: Array = []
	for eff in list:
		parts.append(format_effect_sentence(eff))
	var sep: String = Locale.t("skill_editor.sub_sep")
	return sep.join(parts)


static func describe_repeat_count(eff: Dictionary) -> String:
	if eff.has("repeat_expr"):
		return _format_operand(eff.get("repeat_expr", {}))
	var var_id: String = eff.get("repeat_var", "")
	if var_id != "":
		return "(%s)" % Locale.term("value_var", var_id)
	return str(int(eff.repeat_count)) if eff.has("repeat_count") else ""


# Picks the Locale effect_sentence template key for an effect, resolving the
# sub-type variants of pile-select and zero-cost effects.
static func _sentence_template_key(eff: Dictionary) -> String:
	var effect_id: String = eff.get("effect", "")
	match effect_id:
		SkillEngine.EFFECT_VIEW_DISCARD:
			return "view_discard_select_draw" if int(eff.get("random_count", 0)) > 0 else "view_discard_select"
		SkillEngine.EFFECT_VIEW_DECK:
			return "view_deck_select_draw" if int(eff.get("random_count", 0)) > 0 else "view_deck_select"
		SkillEngine.EFFECT_ZERO_COST:
			var target: String = eff.get("target", SkillEngine.TARGET_SELF)
			if target == SkillEngine.TARGET_ALL:
				return "make_zero_cost_all"
			if target in [SkillEngine.TARGET_SIDES, SkillEngine.TARGET_SELF_SIDES]:
				return "make_zero_cost_sides"
			if target == SkillEngine.TARGET_SINGLE and int(eff.get("random_count", 0)) > 0:
				return "make_zero_cost_random"
			return "make_zero_cost"
	return effect_id


static func _render_sentence(template: String, eff: Dictionary, target: String, vstr: String, buff_name: String = "", buff_value_text: String = "") -> String:
	var s := template
	var count := int(eff.get("random_count", 0))
	# These placeholders describe pile inspection, not battlefield targets.
	if s.contains("{look}"):
		var look := str(int(vstr) * 2) if vstr.is_valid_int() else "(%s) × 2" % vstr
		s = s.replace("{look}", look)
	if s.contains("card(s)"):
		var single := count == 1 if s.contains("{draw}") and not s.contains("{keep}") else vstr == "1"
		s = s.replace("card(s)", "card" if single else "cards")
	s = s.replace("{target}", target)
	s = s.replace("{value}", vstr)
	s = s.replace("{draw}", str(count))
	s = s.replace("{keep}", vstr)
	s = s.replace("{buff}", buff_name)
	s = s.replace("{buff_value}", buff_value_text)
	s = s.replace("{duration}", str(int(eff.get("duration", 1))))
	s = s.replace("{cost_mode}", Locale.term("cost_reduction_mode", str(eff.get("cost_reduction_mode", SkillRegistry.COST_REDUCTION_TURN))))
	return s


# ============================================
# Tokenized sentence (Scratch-style inline parameters)
# ============================================
# Splits an effect sentence template into tokens so the block editor can
# render inline parameter controls (target dropdown, value spinbox, buff
# dropdown, duration spinbox) between static text, instead of one flat label.
# Token dicts: {"type": "text", "text": ...} or {"type": "target" | "value" |
# "draw" | "buff" | "duration"} which the block UI turns into editable
# controls. "value"/"keep"/"buff_value" all edit the "value" field; "draw"
# edits "random_count".
static func _value_template(template: String, effect: Dictionary) -> String:
	if effect.get("effect") == SkillEngine.EFFECT_ADD_BUFF and not SkillRegistry.effect_uses_value(effect):
		return template.replace("（{buff_value}）", "").replace(" ({buff_value})", "").replace("({buff_value})", "")
	return template

static func effect_sentence_tokens(eff: Dictionary) -> Array:
	var normalized := _TargetResolver.normalize_effect_target(eff)
	var effect_id: String = normalized.get("effect", "")
	# Control blocks render through their own C-shaped UI, not the sentence
	# row — expose a read-only text token as a defensive fallback.
	if effect_id in [SkillEngine.EFFECT_IF_ELSE, SkillEngine.EFFECT_IF,
			SkillEngine.EFFECT_REPEAT, SkillEngine.EFFECT_STOP]:
		return [{"type": "text", "text": format_control_sentence(normalized)}]
	var template_key := _sentence_template_key(normalized)
	var template: String = _value_template(Locale.term("effect_sentence", template_key), normalized)
	if effect_id == SkillEngine.EFFECT_CHARM:
		template = Locale.term("effect_block_sentence", effect_id)
	var tokens: Array = []
	if template == template_key:
		# No template — fallback "{target} {effect_name} {value}".
		tokens.append({"type": "text", "text": _format_target_name(normalized)})
		tokens.append({"type": "text", "text": " %s " % Locale.term("effect", effect_id)})
		tokens.append(_value_token(normalized))
	else:
		var re := RegEx.new()
		re.compile("\\{([a-z_]+)\\}")
		var last_end := 0
		for m in re.search_all(template):
			var pre: String = template.substr(last_end, m.get_start() - last_end)
			if pre != "":
				tokens.append({"type": "text", "text": pre})
			var key := m.get_string(1)
			var tok: Variant = _placeholder_token(key, normalized, effect_id)
			if tok != null:
				tokens.append(tok)
			last_end = m.get_end()
		if last_end < template.length():
			tokens.append({"type": "text", "text": template.substr(last_end)})
	var suffix := _sentence_suffix(normalized)
	if not suffix.is_empty():
		tokens.append({"type": "text", "text": suffix})
	return tokens


static func _placeholder_token(key: String, eff: Dictionary, effect_id: String) -> Variant:
	match key:
		"target":
			# force_self effects have a fixed target — render it as static text.
			if SkillRegistry.force_self(effect_id):
				return {"type": "text", "text": _format_target_name(eff)}
			return {"type": "target"}
		"value", "keep", "buff_value":
			return _value_token(eff)
		"draw":
			return {"type": "draw"}
		"buff":
			return {"type": "buff"}
		"duration":
			return {"type": "duration"}
		"cost_mode":
			return {"type": "cost_mode"}
	return null


# "value" renders as an editable control only for a plain numeric value;
# variable / math-expression values are rendered by the block's ValueSlot,
# while random-range values stay static text.
static func _value_token(eff: Dictionary) -> Dictionary:
	if eff.has("value_min") and eff.has("value_max"):
		return {"type": "text", "text": describe_value(eff)}
	return {"type": "value"}


static func _sentence_suffix(eff: Dictionary) -> String:
	var suffix := ""
	var separator := "，" if Locale.language == "zh" else ", "
	if _has_random_battlefield_targets(eff):
		suffix += separator + Locale.t("skill.random_targets", [int(eff.random_count)])
	var condition_text := format_condition_sentence(eff)
	if condition_text != "":
		var condition_prefix := "若%s" if Locale.language == "zh" else "if %s"
		suffix += separator + condition_prefix % condition_text
	var probability: int = int(eff.get("probability", 100))
	if probability < 100:
		suffix += " " + Locale.t("skill.chance", [probability])
	return suffix


static func _has_random_battlefield_targets(effect: Dictionary) -> bool:
	return (int(effect.get("random_count", 0)) > 0 and SkillRegistry.requires_live_target(str(effect.get("effect", "")))
		and effect.get("target") in [SkillEngine.TARGET_ALL, SkillEngine.TARGET_SIDES, SkillEngine.TARGET_SELF_SIDES,
			SkillEngine.TARGET_MALE, SkillEngine.TARGET_FEMALE, SkillEngine.TARGET_NONHUMAN])


static func format_condition_sentence(eff: Dictionary) -> String:
	var cond := SkillEngine._condition_dict(eff)
	# Scratch-style boolean block: "[operand] op [operand]", "target has buff",
	# or a logic combination (and/or/not).
	if cond.has("lhs") or cond.has("logic"):
		return _format_boolean_sentence(cond)
	var condition_type: String = cond.get("condition_type", SkillEngine.CONDITION_NONE)
	if condition_type == "" or condition_type == SkillEngine.CONDITION_NONE:
		return ""
	if condition_type == SkillEngine.CONDITION_TARGET_HAS_BUFF:
		var buff_name := Locale.term("buff", cond.get("condition_buff_id", ""))
		return "目标拥有%s" % buff_name if Locale.language == "zh" else "the target has %s" % buff_name
	var cname := Locale.term("condition", condition_type)
	var opname := Locale.term("condition_op", cond.get("condition_op", SkillEngine.CONDITION_OP_GTE))
	var value_text := str(int(cond.get("condition_value", 0)))
	if condition_type in [SkillEngine.CONDITION_SOURCE_HP_PCT, SkillEngine.CONDITION_TARGET_HP_PCT]:
		value_text += "%"
	return "%s %s %s" % [cname, opname, value_text]


# Renders a Scratch-style boolean reporter: operands may be fixed numbers or
# variable ovals; the "has" form is "目标 拥有 [buff]"; logic nodes combine
# sub-reports with 与/或/非.
static func _format_boolean_sentence(cond: Dictionary) -> String:
	if cond.has("logic"):
		var logic: String = str(cond.get("logic", "and"))
		if logic == "not":
			return "(%s %s)" % [Locale.t("skill_editor.logic_not"), _format_boolean_sentence(cond.get("child", {}))]
		var a := _format_boolean_sentence(cond.get("lhs", {}))
		var b := _format_boolean_sentence(cond.get("rhs", {}))
		var word: String = Locale.t("skill_editor.logic_and") if logic == "and" else Locale.t("skill_editor.logic_or")
		return "(%s %s %s)" % [a, word, b]
	var is_zh := Locale.language == "zh"
	var op: String = str(cond.get("op", SkillEngine.CONDITION_OP_GTE))
	if op == "has":
		var rhs: Dictionary = cond.get("rhs", {})
		var buff_name := Locale.term("buff", rhs.get("buff_id", ""))
		return "目标拥有%s" % buff_name if is_zh else "target has %s" % buff_name
	var lhs := _format_operand(cond.get("lhs", {}))
	var rhs_text := _format_operand(cond.get("rhs", {}))
	var opname := Locale.term("condition_op", op)
	return "%s %s %s" % [lhs, opname, rhs_text]


static func _format_operand(opd: Dictionary) -> String:
	if opd.is_empty(): return ""
	var kind: String = str(opd.get("kind", "num"))
	match kind:
		"var":
			return "(%s)" % Locale.term("value_var", opd.get("var_id", ""))
		"expr":
			var op: String = str(opd.get("op", "+"))
			var a := _format_operand(opd.get("a", {}))
			var b := _format_operand(opd.get("b", {}))
			if op == "rand":
				return "%s~%s" % [a, b]
			var expression := "%s %s %s" % [a, _op_symbol(op), b]
			match str(opd.get("rounding", "round")):
				"ceil": return "⌈%s⌉" % expression
				"floor": return "⌊%s⌋" % expression
			return "(%s)" % expression
	return str(int(opd.value)) if opd.has("value") else ""


static func _op_symbol(op: String) -> String:
	match op:
		"-":
			return "-"
		"*":
			return "*"
		"/":
			return "/"
		_:
			return "+"


static func skill_display_name(skill: Dictionary, index: int = -1) -> String:
	var value := str(skill.get("skill_name", "")).strip_edges()
	return value if not value.is_empty() else (Locale.t("mycards.skill_fallback", [index+1]) if index >= 0 else Locale.t("editor.unnamed"))


static func remaining_skill_uses(card: CardData, skill: Dictionary, index: int) -> int:
	var limit := int(skill.get("max_uses", 0))
	return maxi(0, limit - int(card.skills_used_count.get(index, 0))) if limit > 0 else -1


static func format_remaining_skill_uses(remaining: int) -> String:
	if remaining < 0:
		return ""
	if remaining == 0:
		return Locale.t("card.skill_uses_spent")
	return Locale.t("card.skill_use_left" if remaining == 1 else "card.skill_uses_left", [remaining])


static func format_skill_tooltip(skill: Dictionary, index: int = -1, remaining_uses: int = -1) -> String:
	if skill.is_empty():
		return ""

	var sname := skill_display_name(skill, index)
	var trigger: String = skill.get("trigger", "")
	var trig := Locale.term("trigger", trigger)
	if trigger == SkillEngine.TRIGGER_ON_BOARD_CHANGED:
		trig = Locale.t("skill_editor.board_change_trigger", [Locale.term("board_side", str(skill.get("trigger_side", SkillEngine.TARGET_SIDE_ALL)))])
	var heading := "[%s] %s" % [sname, trig]
	if remaining_uses >= 0:
		heading += ("，" if Locale.language == "zh" else ", ") + format_remaining_skill_uses(remaining_uses)
	var result := heading + "\n"
	var skill_probability: int = int(skill.get("probability", 100))
	if skill_probability < 100:
		result += "  %s\n" % Locale.t("skill.chance", [skill_probability])
	var max_uses := int(skill.get("max_uses", 0))
	if max_uses > 0 and remaining_uses < 0:
		result += "  %s\n" % Locale.t("skill_editor.limited_uses", [max_uses])

	var effects: Array = SkillEngine.legacy_skill_effects(skill)

	if effects.is_empty():
		result += "  %s" % Locale.t("skill.no_effects")
	for i in range(effects.size()):
		var eff: Dictionary = effects[i]
		result += "  %d. %s" % [i + 1, format_effect_sentence(eff)]
		if i < effects.size() - 1:
			result += "\n"

	return result


static func _format_target_name(eff: Dictionary) -> String:
	var normalized := _TargetResolver.normalize_effect_target(eff)
	var target_id: String = normalized.get("target", "")
	if target_id == "":
		return Locale.t("skill_editor.target_unset")
	var side_id: String = normalized.get("target_side", _TargetResolver.default_target_side(target_id))
	var description_key := "random" if target_id == SkillEngine.TARGET_ALL and _has_random_battlefield_targets(normalized) else target_id
	var description := Locale.term("target_description", description_key)
	if description != description_key:
		return description.replace("{side}", Locale.term("target_description_side", side_id))
	var target_name := Locale.term("target", target_id)
	var side_name := Locale.term("target_side", side_id)
	if side_id == SkillEngine.TARGET_SIDE_ALL:
		return target_name
	return "%s%s" % [side_name, target_name] if Locale.language == "zh" else "%s %s" % [side_name, target_name]


static func describe_value(eff: Dictionary) -> String:
	if eff.has("effect") and not SkillRegistry.effect_uses_value(eff): return ""
	if eff.has("value_expr"):
		return _format_operand(eff.get("value_expr", {}))
	var var_id: String = eff.get("value_var", "")
	if var_id != "":
		var offset: int = int(eff.get("value_offset", 0))
		var vname: String = Locale.term("value_var", var_id)
		if offset > 0:
			return "(%s+%d)" % [vname, offset]
		elif offset < 0:
			return "(%s-%d)" % [vname, -offset]
		return "(%s)" % vname
	if eff.has("value_min") and eff.has("value_max"):
		var vmin: int = int(eff.get("value_min", 1))
		var vmax: int = int(eff.get("value_max", 1))
		if vmin == vmax:
			return str(vmin)
		return "%d~%d" % [vmin, vmax]
	return str(int(eff.value)) if eff.has("value") else ""
