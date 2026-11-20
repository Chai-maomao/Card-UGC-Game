extends PanelContainer

var _editor: WeakRef
var _key: String

static func valid_number(raw: Variant, depth := 1) -> bool:
	if not raw is Dictionary or depth > UgcSafety.MAX_EXPRESSION_NESTING_DEPTH: return false
	if raw.is_empty(): return true # An unfilled socket is a valid editor draft.
	var kind := str(raw.get("kind", "expr" if raw.has("op") else "num"))
	match kind:
		"num": return not raw.has("value") or (raw.get("value") is int or raw.get("value") is float) and is_finite(float(raw.value))
		"var":
			var offset: Variant = raw.get("offset", 0)
			return raw.get("var_id") in SkillRegistry.VALUE_VAR_IDS and (offset is int or offset is float) and is_finite(float(offset))
		"expr": return raw.get("op") in ValueSlot.EXPR_OPS and valid_number(raw.get("a"),depth+1) and valid_number(raw.get("b"),depth+1)
	return false

static func valid_condition(raw: Variant, depth := 1) -> bool:
	if not raw is Dictionary or depth > UgcSafety.MAX_EXPRESSION_NESTING_DEPTH: return false
	if raw.is_empty(): return true # Empty inner hexagons are editable drafts.
	if raw.has("logic"):
		if raw.logic == "not": return valid_condition(raw.get("child"),depth+1)
		return raw.logic in ["and","or"] and valid_condition(raw.get("lhs"),depth+1) and valid_condition(raw.get("rhs"),depth+1)
	if raw.get("op") == "has":
		return raw.get("lhs") is Dictionary and raw.get("rhs") is Dictionary and raw.rhs.get("buff_id") in SkillRegistry.BUFF_IDS
	if raw.has("lhs"):
		return raw.get("op") in SkillRegistry.CONDITION_OP_IDS and valid_number(raw.get("lhs"),depth+1) and valid_number(raw.get("rhs"),depth+1)
	return raw.get("condition_type") in SkillRegistry.CONDITION_IDS and raw.get("condition_op") in SkillRegistry.CONDITION_OP_IDS and (raw.get("condition_value") is int or raw.get("condition_value") is float)

func setup(editor: Control, key: String, record: Dictionary) -> void:
	_editor = weakref(editor)
	_key = key
	name = "Reporter_%s" % key
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	# The reporter owns the press; bubbling it to the canvas starts camera
	# panning at the same time as the reporter drag and moves the target away.
	mouse_filter = Control.MOUSE_FILTER_STOP
	if record.kind == "number":
		var slot := ValueSlot.new()
		slot.set_meta("loose_reporter_key", key)
		slot.set_meta("loose_reporter_editor", weakref(editor))
		slot.setup(record.value, "value", "var_id", "kind", true, 999.0, "", "offset")
		slot.changed.connect(editor._on_loose_reporter_changed)
		add_child(slot)
	elif record.kind in ["target", "side"]:
		var slot := TargetSlot.new()
		slot.set_meta("loose_reporter_key", key)
		slot.set_meta("loose_reporter_editor", weakref(editor))
		slot.setup(record.value, record.kind)
		slot.changed.connect(editor._on_loose_reporter_changed)
		add_child(slot)
	else:
		var holder := SkillBlock.new()
		holder._effect = record.value
		holder.effect_path = ["reporter", key]
		holder.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		holder.cond_slot = holder._make_cond_slot()
		holder.add_child(holder.cond_slot)
		holder.cond_slot.get_child(0).gui_input.connect(_gui_input)
		holder.changed.connect(func(_path): editor._on_loose_reporter_changed())
		holder.condition_inserted.connect(editor._on_block_condition_inserted)
		holder.condition_dropped.connect(editor._on_block_condition_dropped)
		holder.context_requested.connect(func(_path, at): editor._on_loose_reporter_context(key, at))
		add_child(holder)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var editor = _editor.get_ref()
		if editor != null:
			editor._on_loose_reporter_context(_key, event.global_position)
			get_viewport().set_input_as_handled()
