class_name SkillEffectForm
extends Control

# ============================================
# Effect editor popup — overlay + centered form.
# SkillEditor creates an instance and add_child()s it; OK emits
# confirmed(effect), cancel emits cancelled. All dropdown options and
# validation are driven by SkillRegistry (no magic indices).
# ============================================

const UITheme = preload("res://UITheme.gd")
const _TargetResolver = preload("res://SkillTargetResolver.gd")
const _TextFormatter = preload("res://SkillTextFormatter.gd")

signal confirmed(effect: Dictionary)
signal cancelled

var _scale: float = 1.0
var _trigger_key: String = SkillEngine.TRIGGER_ON_ATTACK

# Control refs
var _target_sel: OptionButton
var _side_sel: OptionButton
var _effect_sel: OptionButton
var _val_spin: SpinBox
var _mode_sel: OptionButton
var _min_spin: SpinBox
var _max_spin: SpinBox
var _var_sel: OptionButton
var _off_spin: SpinBox
var _eff_prob_spin: SpinBox
var _rcount_spin: SpinBox
var _condition_sel: OptionButton
var _condition_op_sel: OptionButton
var _condition_value_spin: SpinBox
var _condition_buff_sel: OptionButton
var _buff_sel: OptionButton
var _dur_spin: SpinBox

# Labels / rows
var _warning_label: Label
var _effect_preview_label: Label
var _val_label: Label
var _rcount_label: Label
var _pct_label: Label
var _rand_row: HBoxContainer
var _var_row: HBoxContainer
var _mode_row: HBoxContainer
var _buff_row: HBoxContainer
var _condition_detail_row: HBoxContainer
var _condition_buff_row: HBoxContainer


func setup(scale_factor: float, existing: Dictionary, trigger_key: String) -> void:
	_scale = scale_factor
	_trigger_key = trigger_key
	_build_ui(existing)


# ============================================
# UI construction
# ============================================

func _build_ui(existing: Dictionary) -> void:
	var s := _scale
	var popup := UITheme.make_popup_layer(self, 100)
	var layer: CanvasLayer = popup.get("layer")

	var popup_size := Vector2(390, 380) * s
	var panel := Panel.new()
	UITheme.apply_panel(panel, "gold")
	panel.custom_minimum_size = popup_size
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -popup_size.x / 2.0
	panel.offset_top = -popup_size.y / 2.0
	panel.offset_right = popup_size.x / 2.0
	panel.offset_bottom = popup_size.y / 2.0
	layer.add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", int(6 * s))
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.offset_left = 10 * s
	outer.offset_top = 10 * s
	outer.offset_right = -10 * s
	outer.offset_bottom = -10 * s
	panel.add_child(outer)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", int(6 * s))
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)

	# Target dropdown
	vb.add_child(_make_label(Locale.t("skill_editor.target"), s))
	_target_sel = _make_option(SkillRegistry.TARGET_IDS, "target", s)
	vb.add_child(_target_sel)

	# Target side row
	var side_row := _make_row(s)
	side_row.add_child(_make_label(Locale.t("skill_editor.target_side"), s))
	_side_sel = _make_option(SkillRegistry.TARGET_SIDE_IDS, "target_side", s)
	_side_sel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_row.add_child(_side_sel)
	vb.add_child(side_row)

	_warning_label = _make_soft_label(s)
	vb.add_child(_warning_label)
	_effect_preview_label = _make_soft_label(s)
	vb.add_child(_effect_preview_label)

	# Effect + value row
	var r1 := _make_row(s)
	r1.add_child(_make_label(Locale.t("skill_editor.effect"), s))
	_effect_sel = _make_option(SkillRegistry.EFFECT_IDS, "effect", s)
	_effect_sel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_effect_sel.custom_minimum_size = Vector2(100 * s, 0)
	r1.add_child(_effect_sel)
	_val_label = _make_label(Locale.t("skill_editor.value"), s)
	r1.add_child(_val_label)
	_val_spin = _make_spin(1.0, 500.0, 1.0, s)
	r1.add_child(_val_spin)
	_pct_label = _make_label("%", s)
	_pct_label.visible = false
	r1.add_child(_pct_label)
	vb.add_child(r1)

	# Value mode: fixed / random range / variable
	_mode_row = _make_row(s)
	_mode_row.add_child(_make_label(Locale.t("skill_editor.value_mode"), s))
	_mode_sel = OptionButton.new()
	_mode_sel.add_item(Locale.t("skill_editor.value_mode_fixed"), 0)
	_mode_sel.add_item(Locale.t("skill_editor.value_mode_random"), 1)
	_mode_sel.add_item(Locale.t("skill_editor.value_mode_var"), 2)
	_mode_sel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_button(_mode_sel, "secondary")
	_mode_row.add_child(_mode_sel)
	vb.add_child(_mode_row)

	# Random range row (min / max)
	_rand_row = _make_row(s)
	_rand_row.add_child(_make_label(Locale.t("skill_editor.value_min"), s))
	_min_spin = _make_spin(1.0, 500.0, 1.0, s)
	_rand_row.add_child(_min_spin)
	_rand_row.add_child(_make_label(Locale.t("skill_editor.value_max"), s))
	_max_spin = _make_spin(1.0, 500.0, 3.0, s)
	_rand_row.add_child(_max_spin)
	_rand_row.visible = false
	vb.add_child(_rand_row)

	# Variable row (variable dropdown + offset)
	_var_row = _make_row(s)
	_var_row.add_child(_make_label(Locale.t("skill_editor.value_var"), s))
	_var_sel = _make_option(SkillRegistry.VALUE_VAR_IDS, "value_var", s)
	_var_sel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_var_row.add_child(_var_sel)
	_var_row.add_child(_make_label(Locale.t("skill_editor.value_offset"), s))
	_off_spin = _make_spin(-100.0, 100.0, 0.0, s)
	_var_row.add_child(_off_spin)
	_var_row.visible = false
	vb.add_child(_var_row)

	# Effect probability row
	var prob_row := _make_row(s)
	prob_row.add_child(_make_label(Locale.t("skill_editor.effect_prob"), s))
	_eff_prob_spin = _make_spin(1.0, 100.0, 100.0, s, 55.0)
	prob_row.add_child(_eff_prob_spin)
	prob_row.add_child(_make_label("%", s))
	vb.add_child(prob_row)

	# Random target count
	var rcount_row := _make_row(s)
	_rcount_label = _make_label(Locale.t("skill_editor.max_targets"), s)
	rcount_row.add_child(_rcount_label)
	_rcount_spin = _make_spin(0.0, 15.0, 0.0, s)
	rcount_row.add_child(_rcount_spin)
	vb.add_child(rcount_row)

	# Effect condition row
	var condition_row := _make_row(s)
	condition_row.add_child(_make_label(Locale.t("skill_editor.condition"), s))
	_condition_sel = OptionButton.new()
	_condition_sel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_setup_condition_dropdown(_condition_sel)
	UITheme.apply_button(_condition_sel, "secondary")
	condition_row.add_child(_condition_sel)
	vb.add_child(condition_row)

	# Condition detail row (op + value)
	_condition_detail_row = _make_row(s)
	_condition_detail_row.add_child(_make_label(Locale.t("skill_editor.condition_op"), s))
	_condition_op_sel = OptionButton.new()
	_setup_condition_op_dropdown(_condition_op_sel)
	UITheme.apply_button(_condition_op_sel, "secondary")
	_condition_detail_row.add_child(_condition_op_sel)
	_condition_detail_row.add_child(_make_label(Locale.t("skill_editor.condition_value"), s))
	_condition_value_spin = _make_spin(0.0, 100.0, 1.0, s, 55.0)
	_condition_detail_row.add_child(_condition_value_spin)
	_condition_detail_row.visible = false
	vb.add_child(_condition_detail_row)

	# Condition buff row (target_has_buff)
	_condition_buff_row = _make_row(s)
	_condition_buff_row.add_child(_make_label(Locale.t("skill_editor.condition_buff"), s))
	_condition_buff_sel = _make_option(SkillRegistry.BUFF_IDS, "buff", s)
	_condition_buff_sel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_condition_buff_row.add_child(_condition_buff_sel)
	_condition_buff_row.visible = false
	vb.add_child(_condition_buff_row)

	# Buff row (conditional)
	_buff_row = _make_row(s)
	_buff_sel = _make_option(SkillRegistry.BUFF_IDS, "buff", s)
	_buff_sel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_buff_sel.custom_minimum_size = Vector2(120 * s, 0)
	_buff_row.add_child(_buff_sel)
	_buff_row.add_child(_make_label(Locale.t("skill_editor.duration"), s))
	_dur_spin = _make_spin(1.0, 20.0, 2.0, s)
	_buff_row.add_child(_dur_spin)
	_buff_row.visible = false
	vb.add_child(_buff_row)

	# Buttons
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", int(16 * s))
	var ok_btn := Button.new()
	ok_btn.text = Locale.t("skill_editor.ok")
	ok_btn.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	UITheme.apply_button(ok_btn, "primary")
	ok_btn.pressed.connect(_on_ok)
	btns.add_child(ok_btn)
	var cls_btn := Button.new()
	cls_btn.text = Locale.t("skill_editor.cancel")
	cls_btn.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	UITheme.apply_button(cls_btn, "secondary")
	cls_btn.pressed.connect(_on_cancel)
	btns.add_child(cls_btn)
	outer.add_child(btns)

	_connect_signals()
	_update_tooltips()

	if not existing.is_empty():
		_backfill(existing)
	else:
		_update_effect_labels()
		_update_value_mode(0)
		_update_condition_mode()
		_update_target_side()
		_update_preview()


# ============================================
# Widget helpers
# ============================================

func _make_label(text: String, s: float) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	UITheme.apply_label(lbl)
	return lbl


func _make_soft_label(s: float) -> Label:
	var lbl := Label.new()
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", max(9, int(12 * s)))
	UITheme.apply_label(lbl, true)
	return lbl


func _make_option(keys: Array, category: String, s: float) -> OptionButton:
	var dd := OptionButton.new()
	dd.custom_minimum_size = Vector2(200 * s, 0)
	_setup_editor_dropdown(dd, category, keys)
	UITheme.apply_button(dd, "secondary")
	return dd


func _make_spin(min_v: float, max_v: float, value: float, s: float, w: float = 50.0) -> SpinBox:
	var spin := SpinBox.new()
	spin.custom_minimum_size = Vector2(w * s, 0)
	spin.min_value = min_v
	spin.max_value = max_v
	spin.value = value
	UITheme.apply_input(spin)
	return spin


func _make_row(s: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(4 * s))
	return row


# ============================================
# Dropdown helpers (tooltips from Locale editor_* terms)
# ============================================

func _setup_editor_dropdown(dd: OptionButton, category: String, keys: Array) -> void:
	dd.clear()
	for i in range(keys.size()):
		var key: String = keys[i]
		dd.add_item(Locale.term(category, key), i)
		dd.get_popup().set_item_tooltip(i, _editor_term(category, key))
	_update_editor_dropdown_tooltip(dd, category, keys)
	dd.item_selected.connect(func(_i: int): _update_editor_dropdown_tooltip(dd, category, keys))


func _update_editor_dropdown_tooltip(dd: OptionButton, category: String, keys: Array) -> void:
	if dd.selected < 0 or dd.selected >= keys.size():
		dd.tooltip_text = ""
		return
	dd.tooltip_text = _editor_term(category, keys[dd.selected])


func _setup_condition_dropdown(dd: OptionButton) -> void:
	dd.clear()
	for i in range(SkillRegistry.CONDITION_IDS.size()):
		var key: String = SkillRegistry.CONDITION_IDS[i]
		var label := Locale.t("skill_editor.condition_none") if key == SkillEngine.CONDITION_NONE else Locale.term("condition", key)
		dd.add_item(label, i)
		if key != SkillEngine.CONDITION_NONE:
			dd.get_popup().set_item_tooltip(i, _editor_term("condition", key))
	_update_condition_dropdown_tooltip(dd)
	dd.item_selected.connect(func(_i: int): _update_condition_dropdown_tooltip(dd))


func _update_condition_dropdown_tooltip(dd: OptionButton) -> void:
	if dd.selected < 0 or dd.selected >= SkillRegistry.CONDITION_IDS.size():
		dd.tooltip_text = ""
		return
	var key: String = SkillRegistry.CONDITION_IDS[dd.selected]
	dd.tooltip_text = "" if key == SkillEngine.CONDITION_NONE else _editor_term("condition", key)


func _setup_condition_op_dropdown(dd: OptionButton) -> void:
	dd.clear()
	for i in range(SkillRegistry.CONDITION_OP_IDS.size()):
		dd.add_item(Locale.term("condition_op", SkillRegistry.CONDITION_OP_IDS[i]), i)


func _update_tooltips() -> void:
	_update_editor_dropdown_tooltip(_target_sel, "target", SkillRegistry.TARGET_IDS)
	_update_editor_dropdown_tooltip(_side_sel, "target_side", SkillRegistry.TARGET_SIDE_IDS)
	_update_editor_dropdown_tooltip(_effect_sel, "effect", SkillRegistry.EFFECT_IDS)
	_update_editor_dropdown_tooltip(_buff_sel, "buff", SkillRegistry.BUFF_IDS)
	_update_editor_dropdown_tooltip(_var_sel, "value_var", SkillRegistry.VALUE_VAR_IDS)
	_update_editor_dropdown_tooltip(_condition_buff_sel, "buff", SkillRegistry.BUFF_IDS)
	_update_condition_dropdown_tooltip(_condition_sel)


func _editor_term(category: String, value: String) -> String:
	var label := Locale.term("editor_%s" % category, value)
	if label == value:
		return Locale.term(category, value)
	return label


func _idx_of(key: String, keys: Array) -> int:
	var i := keys.find(key)
	return i if i >= 0 else 0


# ============================================
# State sync
# ============================================

func _connect_signals() -> void:
	_target_sel.item_selected.connect(func(_i: int): _update_target_side())
	_side_sel.item_selected.connect(func(_i: int): _update_target_side())
	_effect_sel.item_selected.connect(_on_effect_changed)
	_buff_sel.item_selected.connect(_on_buff_changed)
	_mode_sel.item_selected.connect(func(m: int): _update_value_mode(m))
	_condition_sel.item_selected.connect(func(_i: int): _update_condition_mode())

	for control in [_target_sel, _side_sel, _effect_sel, _buff_sel, _mode_sel, _var_sel, _condition_sel, _condition_op_sel, _condition_buff_sel]:
		control.item_selected.connect(func(_i: int): _update_preview())
	for control in [_val_spin, _min_spin, _max_spin, _off_spin, _eff_prob_spin, _rcount_spin, _dur_spin, _condition_value_spin]:
		control.value_changed.connect(func(_value: float): _update_preview())


func _on_effect_changed(_i: int) -> void:
	var effect_key: String = SkillRegistry.EFFECT_IDS[_effect_sel.selected]
	_buff_row.visible = (effect_key == SkillEngine.EFFECT_ADD_BUFF)
	_target_sel.disabled = SkillRegistry.force_self(effect_key)
	_update_target_side()
	_mode_sel.disabled = not SkillRegistry.uses_value(effect_key)
	if effect_key != SkillEngine.EFFECT_ADD_BUFF:
		_val_spin.editable = true
	else:
		_val_spin.editable = SkillRegistry.buff_uses_value(SkillRegistry.BUFF_IDS[_buff_sel.selected])
	_update_effect_labels()
	_update_value_mode(_mode_sel.selected)
	_update_pct()


func _on_buff_changed(_i: int) -> void:
	var buff_key: String = SkillRegistry.BUFF_IDS[_buff_sel.selected]
	if not SkillRegistry.buff_uses_value(buff_key):
		_val_spin.value = 1.0
		_val_spin.editable = false
	else:
		_val_spin.editable = true
	_update_pct()


func _update_target_side() -> void:
	var target_key: String = SkillRegistry.TARGET_IDS[_target_sel.selected]
	var effect_key: String = SkillRegistry.EFFECT_IDS[_effect_sel.selected]
	# Zero-cost effect always targets own hand — target_side is irrelevant.
	var is_hand_effect_ui: bool = effect_key == SkillEngine.EFFECT_ZERO_COST
	var disabled: bool = _target_sel.disabled or target_key in [SkillEngine.TARGET_SELF, SkillEngine.TARGET_SELF_SIDES] or is_hand_effect_ui
	_side_sel.disabled = disabled
	if disabled:
		_side_sel.selected = _idx_of(SkillEngine.TARGET_SIDE_ALL, SkillRegistry.TARGET_SIDE_IDS)
	elif target_key in [SkillEngine.TARGET_SINGLE, SkillEngine.TARGET_SIDES] and SkillRegistry.TARGET_SIDE_IDS[_side_sel.selected] == SkillEngine.TARGET_SIDE_ALL:
		_side_sel.selected = _idx_of(SkillEngine.TARGET_SIDE_ENEMY, SkillRegistry.TARGET_SIDE_IDS)
	_update_target_warning()


func _update_target_warning() -> void:
	var target_key: String = SkillRegistry.TARGET_IDS[_target_sel.selected]
	var effect_key: String = SkillRegistry.EFFECT_IDS[_effect_sel.selected]
	# Zero-cost effect targets the hand — battlefield target warnings don't apply.
	if effect_key == SkillEngine.EFFECT_ZERO_COST:
		_warning_label.text = ""
		_warning_label.visible = false
		return
	var msg := _target_warning_for(_trigger_key, target_key, _target_sel.disabled)
	_warning_label.text = msg
	_warning_label.visible = msg != ""


func _target_warning_for(trigger_key: String, target_key: String, target_disabled: bool = false) -> String:
	if target_disabled:
		return Locale.t("skill_editor.warning_forced_self")
	if target_key in [SkillEngine.TARGET_SINGLE, SkillEngine.TARGET_SIDES]:
		if trigger_key == SkillEngine.TRIGGER_ON_DEATH:
			return Locale.t("skill_editor.warning_death_directed")
		if trigger_key == SkillEngine.TRIGGER_ON_ATTACK:
			return Locale.t("skill_editor.warning_attack_target")
		if trigger_key == SkillEngine.TRIGGER_ON_DAMAGED:
			return Locale.t("skill_editor.warning_damaged_source")
		if trigger_key in [SkillEngine.TRIGGER_ON_ACTIVATE, SkillEngine.TRIGGER_ON_SUMMON]:
			return Locale.t("skill_editor.warning_manual_target")
		return Locale.t("skill_editor.warning_directed_side")
	if trigger_key == SkillEngine.TRIGGER_ON_DEATH:
		return Locale.t("skill_editor.warning_death_filter")
	return Locale.t("skill_editor.warning_side_filter")


func _update_pct() -> void:
	var effect_key: String = SkillRegistry.EFFECT_IDS[_effect_sel.selected]
	var buff_key: String = SkillRegistry.BUFF_IDS[_buff_sel.selected]
	_pct_label.visible = (effect_key == SkillEngine.EFFECT_ADD_BUFF and buff_key in [SkillEngine.BUFF_DAMAGE_REDUCTION, SkillEngine.BUFF_MISFORTUNE])


func _update_effect_labels() -> void:
	var effect_key: String = SkillRegistry.EFFECT_IDS[_effect_sel.selected]
	var is_pile_select: bool = effect_key in [SkillEngine.EFFECT_VIEW_DISCARD, SkillEngine.EFFECT_VIEW_DECK]
	# Effects that logically support negative values
	var allows_negative: bool = SkillRegistry.allows_negative(effect_key)
	if is_pile_select:
		_val_label.text = Locale.t("skill_editor.keep_count")
		_rcount_label.text = Locale.t("skill_editor.draw_count")
		_rcount_spin.max_value = 30.0
	else:
		_val_label.text = Locale.t("skill_editor.value")
		_rcount_label.text = Locale.t("skill_editor.max_targets")
		_rcount_spin.max_value = 15.0
	_val_spin.min_value = -500.0 if allows_negative else 0.0
	_val_spin.suffix = "%" if (effect_key == SkillEngine.EFFECT_ADD_BUFF and SkillRegistry.BUFF_IDS[_buff_sel.selected] in [SkillEngine.BUFF_DAMAGE_REDUCTION, SkillEngine.BUFF_MISFORTUNE]) else ""
	_min_spin.min_value = -500.0 if allows_negative else 0.0
	if _val_spin.value < _val_spin.min_value:
		_val_spin.value = _val_spin.min_value
	if _min_spin.value < _min_spin.min_value:
		_min_spin.value = _min_spin.min_value


func _update_value_mode(m: int) -> void:
	var effect_key: String = SkillRegistry.EFFECT_IDS[_effect_sel.selected]
	var uses_value: bool = SkillRegistry.uses_value(effect_key)
	_val_label.visible = uses_value and (m == 0)
	_val_spin.visible = uses_value and (m == 0)
	_rand_row.visible = uses_value and (m == 1)
	_var_row.visible = uses_value and (m == 2)
	_mode_row.visible = uses_value


func _update_condition_mode() -> void:
	var condition_type: String = SkillRegistry.CONDITION_IDS[_condition_sel.selected]
	var has_condition: bool = condition_type != SkillEngine.CONDITION_NONE
	var uses_buff: bool = condition_type == SkillEngine.CONDITION_TARGET_HAS_BUFF
	_condition_detail_row.visible = has_condition and not uses_buff
	_condition_buff_row.visible = uses_buff


# ============================================
# Preview / result
# ============================================

func _preview_dict() -> Dictionary:
	var preview := {
		"target": SkillRegistry.TARGET_IDS[_target_sel.selected],
		"target_side": SkillRegistry.TARGET_SIDE_IDS[_side_sel.selected],
		"effect": SkillRegistry.EFFECT_IDS[_effect_sel.selected],
		"value": float(_val_spin.value),
		"buff_id": "",
		"duration": 0,
		"random_count": int(_rcount_spin.value),
		"probability": int(_eff_prob_spin.value),
	}
	var vmode: int = _mode_sel.selected
	if vmode == 1:
		preview.value_min = int(_min_spin.value)
		preview.value_max = int(_max_spin.value)
	elif vmode == 2:
		preview.value_var = SkillRegistry.VALUE_VAR_IDS[_var_sel.selected]
		preview.value_offset = int(_off_spin.value)
	if SkillRegistry.EFFECT_IDS[_effect_sel.selected] == SkillEngine.EFFECT_ADD_BUFF:
		preview.buff_id = SkillRegistry.BUFF_IDS[_buff_sel.selected]
		preview.duration = int(_dur_spin.value)
	var condition_type: String = SkillRegistry.CONDITION_IDS[_condition_sel.selected]
	if condition_type != SkillEngine.CONDITION_NONE:
		preview.condition_type = condition_type
		if condition_type == SkillEngine.CONDITION_TARGET_HAS_BUFF:
			preview.condition_buff_id = SkillRegistry.BUFF_IDS[_condition_buff_sel.selected]
		else:
			preview.condition_op = SkillRegistry.CONDITION_OP_IDS[_condition_op_sel.selected]
			preview.condition_value = int(_condition_value_spin.value)
	if SkillRegistry.force_self(str(preview.effect)):
		preview.target = SkillEngine.TARGET_SELF
		preview.target_side = SkillEngine.TARGET_SIDE_ALL
	return _TargetResolver.normalize_effect_target(preview)


func _update_preview() -> void:
	var sentence := _TextFormatter.format_effect_sentence(_preview_dict())
	_effect_preview_label.text = Locale.t("skill_editor.effect_preview", [sentence])


func _backfill(existing: Dictionary) -> void:
	var eff: Dictionary = _TargetResolver.normalize_effect_target(existing)
	_target_sel.selected = _idx_of(eff.get("target", SkillEngine.TARGET_SINGLE), SkillRegistry.TARGET_IDS)
	_side_sel.selected = _idx_of(eff.get("target_side", SkillEngine.TARGET_SIDE_ALL), SkillRegistry.TARGET_SIDE_IDS)
	_update_target_side()
	_effect_sel.selected = _idx_of(eff.get("effect", SkillEngine.EFFECT_DAMAGE), SkillRegistry.EFFECT_IDS)
	_val_spin.value = float(eff.get("value", 1))
	_buff_sel.selected = _idx_of(eff.get("buff_id", SkillEngine.BUFF_ATK_BOOST), SkillRegistry.BUFF_IDS)
	_val_spin.editable = SkillRegistry.buff_uses_value(SkillRegistry.BUFF_IDS[_buff_sel.selected])
	_target_sel.disabled = SkillRegistry.force_self(SkillRegistry.EFFECT_IDS[_effect_sel.selected])
	_update_target_side()
	_dur_spin.value = int(eff.get("duration", 2))
	_rcount_spin.value = float(eff.get("random_count", 0))
	_eff_prob_spin.value = float(eff.get("probability", 100))
	_buff_row.visible = (SkillRegistry.EFFECT_IDS[_effect_sel.selected] == SkillEngine.EFFECT_ADD_BUFF)
	# Detect value mode from which optional fields are present.
	var var_id: String = eff.get("value_var", "")
	if var_id != "":
		_mode_sel.selected = 2
		_var_sel.selected = _idx_of(var_id, SkillRegistry.VALUE_VAR_IDS)
		_off_spin.value = float(eff.get("value_offset", 0))
	elif eff.has("value_min") and eff.has("value_max"):
		_mode_sel.selected = 1
		_min_spin.value = float(eff.get("value_min", 1))
		_max_spin.value = float(eff.get("value_max", 1))
	else:
		_mode_sel.selected = 0
	_condition_sel.selected = _idx_of(eff.get("condition_type", SkillEngine.CONDITION_NONE), SkillRegistry.CONDITION_IDS)
	_condition_op_sel.selected = _idx_of(eff.get("condition_op", SkillEngine.CONDITION_OP_GTE), SkillRegistry.CONDITION_OP_IDS)
	_condition_value_spin.value = float(eff.get("condition_value", 1))
	_condition_buff_sel.selected = _idx_of(eff.get("condition_buff_id", SkillEngine.BUFF_TAUNT), SkillRegistry.BUFF_IDS)
	_update_condition_mode()
	_update_effect_labels()
	_update_value_mode(_mode_sel.selected)
	_update_pct()
	_update_preview()


# ============================================
# OK / Cancel
# ============================================

func _on_ok() -> void:
	var selected_target: String = SkillRegistry.TARGET_IDS[_target_sel.selected]
	var selected_side: String = SkillRegistry.TARGET_SIDE_IDS[_side_sel.selected]
	if selected_target in [SkillEngine.TARGET_SINGLE, SkillEngine.TARGET_SIDES] and selected_side == SkillEngine.TARGET_SIDE_ALL:
		selected_side = SkillEngine.TARGET_SIDE_ENEMY
	var eff := {
		"target": selected_target,
		"target_side": selected_side,
		"effect": SkillRegistry.EFFECT_IDS[_effect_sel.selected],
		"value": float(_val_spin.value),
		"buff_id": "",
		"duration": 0,
		"random_count": int(_rcount_spin.value),
		"probability": int(_eff_prob_spin.value),
	}
	# Value mode: 0=fixed, 1=random range, 2=variable. Only the active mode's
	# fields are written so _resolve_value / _describe_value pick the right one.
	var vmode: int = _mode_sel.selected
	if vmode == 1:
		eff.value_min = int(_min_spin.value)
		eff.value_max = int(_max_spin.value)
	elif vmode == 2:
		eff.value_var = SkillRegistry.VALUE_VAR_IDS[_var_sel.selected]
		eff.value_offset = int(_off_spin.value)
	if SkillRegistry.EFFECT_IDS[_effect_sel.selected] == SkillEngine.EFFECT_ADD_BUFF:
		eff.buff_id = SkillRegistry.BUFF_IDS[_buff_sel.selected]
		eff.duration = int(_dur_spin.value)
	var condition_type: String = SkillRegistry.CONDITION_IDS[_condition_sel.selected]
	if condition_type != SkillEngine.CONDITION_NONE:
		eff.condition_type = condition_type
		if condition_type == SkillEngine.CONDITION_TARGET_HAS_BUFF:
			eff.condition_buff_id = SkillRegistry.BUFF_IDS[_condition_buff_sel.selected]
		else:
			eff.condition_op = SkillRegistry.CONDITION_OP_IDS[_condition_op_sel.selected]
			eff.condition_value = int(_condition_value_spin.value)
	if SkillRegistry.force_self(str(eff.effect)):
		eff.target = SkillEngine.TARGET_SELF
		eff.target_side = SkillEngine.TARGET_SIDE_ALL
	eff = _TargetResolver.normalize_effect_target(eff)
	confirmed.emit(eff)
	queue_free()


func _on_cancel() -> void:
	cancelled.emit()
	queue_free()
