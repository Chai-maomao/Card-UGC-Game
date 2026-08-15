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
			return "每回合恢复 %s" % value_text if is_zh else "restore %s HP each turn" % value_text
		SkillEngine.BUFF_MANA_REFUND:
			return "回合结束返还 %s 圣水" % value_text if is_zh else "refund %s elixir at turn end" % value_text
		SkillEngine.BUFF_THORNS:
			return "反伤 %s" % value_text if is_zh else "%s thorns damage" % value_text
		SkillEngine.BUFF_DAMAGE_REDUCTION:
			return "减伤 %s%%" % value_text if is_zh else "%s%% damage reduction" % value_text
		SkillEngine.BUFF_TAUNT:
			return "嘲讽" if is_zh else "taunt"
		SkillEngine.BUFF_SILENCE:
			return "沉默" if is_zh else "silence"
		SkillEngine.BUFF_MISFORTUNE:
			return "触发概率 -%s%%" % value_text if is_zh else "-%s%% trigger chance" % value_text
		SkillEngine.BUFF_IMMUNE_LETHAL:
			return "免疫致命伤害" if is_zh else "immune to lethal damage"
	return value_text


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
	var probability: int = int(normalized.get("probability", 100))
	var is_zh := Locale.language == "zh"
	var sentence := ""

	# Sentence templates are registered per effect in Locale (effect_sentence),
	# with {target}/{value}/{draw}/{keep}/{buff}/{buff_value}/{duration} placeholders.
	var template_key := _sentence_template_key(normalized)
	var template: String = Locale.term("effect_sentence", template_key)
	if template == template_key:
		# No template registered — fallback: "{target} {effect_name} {value}".
		sentence = "%s %s %s" % [target, Locale.term("effect", effect_id), vstr]
	else:
		var buff_name: String = ""
		var buff_value_text: String = ""
		if effect_id == SkillEngine.EFFECT_ADD_BUFF:
			buff_name = Locale.term("buff", normalized.get("buff_id", ""))
			buff_value_text = format_buff_value(normalized.get("buff_id", ""), vstr, is_zh)
		sentence = _render_sentence(template, normalized, target, vstr, buff_name, buff_value_text)

	var rcount: int = int(eff.get("random_count", 0))
	if rcount > 0:
		sentence += "，%s" % Locale.t("skill.max_targets", [rcount]) if is_zh else ", %s" % Locale.t("skill.max_targets", [rcount])
	var condition_text := format_condition_sentence(normalized)
	if condition_text != "":
		sentence += "，%s" % condition_text if is_zh else ", %s" % condition_text
	if probability < 100:
		sentence += " %s" % Locale.t("skill.chance", [probability])
	return sentence


# Recursive human-readable form for control blocks, used by the skill preview
# and card tooltips: "如果 [条件] 那么：a；b" / "重复 N 次：a" / "跳出当前条件".
static func format_control_sentence(eff: Dictionary) -> String:
	var effect_id: String = str(eff.get("effect", ""))
	match effect_id:
		SkillEngine.EFFECT_IF:
			return Locale.t("skill_editor.if_sentence") % [format_condition_sentence(eff), _format_sub_effects(eff.get("then_effects", []))]
		SkillEngine.EFFECT_IF_ELSE:
			return Locale.t("skill_editor.if_else_sentence") \
					% [format_condition_sentence(eff), _format_sub_effects(eff.get("then_effects", [])), _format_sub_effects(eff.get("else_effects", []))]
		SkillEngine.EFFECT_REPEAT:
			return Locale.t("skill_editor.repeat_sentence") \
					% [describe_repeat_count(eff), _format_sub_effects(eff.get("then_effects", []))]
		SkillEngine.EFFECT_STOP:
			return Locale.t("skill_editor.stop_word")
	return ""


static func _format_sub_effects(list: Array) -> String:
	var parts: Array = []
	for eff in list:
		parts.append(format_effect_sentence(eff))
	var sep: String = Locale.t("skill_editor.sub_sep")
	return sep.join(parts)


static func describe_repeat_count(eff: Dictionary) -> String:
	var var_id: String = eff.get("repeat_var", "")
	if var_id != "":
		return "(%s)" % Locale.term("value_var", var_id)
	return str(int(eff.get("repeat_count", 2)))


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


static func _render_sentence(template: String, eff: Dictionary, target: String, vstr: String, buff_name: String, buff_value_text: String) -> String:
	var s := template
	s = s.replace("{target}", target)
	s = s.replace("{value}", vstr)
	s = s.replace("{draw}", str(int(eff.get("random_count", 0))))
	s = s.replace("{keep}", vstr)
	s = s.replace("{buff}", buff_name)
	s = s.replace("{buff_value}", buff_value_text)
	s = s.replace("{duration}", str(int(eff.get("duration", 1))))
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
static func effect_sentence_tokens(eff: Dictionary) -> Array:
	var normalized := _TargetResolver.normalize_effect_target(eff)
	var effect_id: String = normalized.get("effect", "")
	# Control blocks render through their own C-shaped UI, not the sentence
	# row — expose a read-only text token as a defensive fallback.
	if effect_id in [SkillEngine.EFFECT_IF_ELSE, SkillEngine.EFFECT_IF,
			SkillEngine.EFFECT_REPEAT, SkillEngine.EFFECT_STOP]:
		return [{"type": "text", "text": format_control_sentence(normalized)}]
	var template_key := _sentence_template_key(normalized)
	var template: String = Locale.term("effect_sentence", template_key)
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
	_append_sentence_suffix(tokens, normalized)
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
	return null


# "value" renders as an editable control only for a plain numeric value;
# variable / math-expression values are rendered by the block's ValueSlot,
# while random-range values stay static text.
static func _value_token(eff: Dictionary) -> Dictionary:
	if eff.has("value_min") and eff.has("value_max"):
		return {"type": "text", "text": describe_value(eff)}
	return {"type": "value"}


static func _append_sentence_suffix(tokens: Array, eff: Dictionary) -> void:
	var is_zh := Locale.language == "zh"
	var rcount: int = int(eff.get("random_count", 0))
	if rcount > 0:
		tokens.append({"type": "text", "text": ("，%s" if is_zh else ", %s") % Locale.t("skill.max_targets", [rcount])})
	var condition_text := format_condition_sentence(eff)
	if condition_text != "":
		tokens.append({"type": "text", "text": ("，%s" if is_zh else ", %s") % condition_text})
	var probability: int = int(eff.get("probability", 100))
	if probability < 100:
		tokens.append({"type": "text", "text": " %s" % Locale.t("skill.chance", [probability])})


static func format_condition_sentence(eff: Dictionary) -> String:
	var cond := SkillEngine._condition_dict(eff)
	# Scratch-style boolean block: "[operand] op [operand]", "target has buff",
	# or a logic combination (and/or/not).
	if cond.has("lhs") or cond.has("logic"):
		return _format_boolean_sentence(cond)
	var condition_type: String = eff.get("condition_type", SkillEngine.CONDITION_NONE)
	if condition_type == "" or condition_type == SkillEngine.CONDITION_NONE:
		return ""
	var is_zh := Locale.language == "zh"
	if condition_type == SkillEngine.CONDITION_TARGET_HAS_BUFF:
		var buff_name := Locale.term("buff", eff.get("condition_buff_id", ""))
		return "若目标拥有%s" % buff_name if is_zh else "if the target has %s" % buff_name
	var cname := Locale.term("condition", condition_type)
	var opname := Locale.term("condition_op", eff.get("condition_op", SkillEngine.CONDITION_OP_GTE))
	var value_text := str(int(eff.get("condition_value", 0)))
	if condition_type in [SkillEngine.CONDITION_SOURCE_HP_PCT, SkillEngine.CONDITION_TARGET_HP_PCT]:
		value_text += "%"
	return "若%s %s %s" % [cname, opname, value_text] if is_zh else "if %s %s %s" % [cname, opname, value_text]


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
	var kind: String = str(opd.get("kind", "num"))
	match kind:
		"var":
			return "(%s)" % Locale.term("value_var", opd.get("var_id", ""))
		"expr":
			var op: String = str(opd.get("op", "+"))
			var a := _format_operand(opd.get("a", {}))
			var b := _format_operand(opd.get("b", {}))
			if op == "rand":
				return "%s(%s~%s)" % [Locale.t("skill_editor.op_random"), a, b]
			return "(%s %s %s)" % [a, _op_symbol(op), b]
	return str(int(opd.get("value", 0)))


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


static func format_skill_tooltip(skill: Dictionary) -> String:
	if skill.is_empty():
		return ""

	var sname: String = skill.get("skill_name", Locale.t("editor.unnamed"))
	var trig: String = Locale.term("trigger", skill.get("trigger", ""))
	var result: String = "[%s] %s\n" % [sname, trig]
	var skill_probability: int = int(skill.get("probability", 100))
	if skill_probability < 100:
		result += "  %s\n" % Locale.t("skill.chance", [skill_probability])

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
	if _TargetResolver.is_directed_target(target_id):
		return Locale.term("target", target_id)
	var target_name := Locale.term("target", target_id)
	var side_name := Locale.term("target_side", side_id)
	if side_id == SkillEngine.TARGET_SIDE_ALL:
		return target_name
	return "%s%s" % [side_name, target_name] if Locale.language == "zh" else "%s %s" % [side_name, target_name]


static func describe_value(eff: Dictionary) -> String:
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
		return "%d-%d" % [vmin, vmax]
	return str(int(eff.get("value", 0)))
