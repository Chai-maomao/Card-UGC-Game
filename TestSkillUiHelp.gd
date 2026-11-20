extends Node

const Hints = preload("res://UIHoverHints.gd")
var failures: Array[String] = []


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--visual"):
		await _show_visual_editor()
		return
	_test_rounding()
	await _test_rounding_menu()
	await _test_editor_rounding_history()
	await _test_hint_coverage()
	await _test_boundaries()
	_test_menu_theme()
	await _test_live_menu_hover()
	if failures.is_empty():
		print("TEST_SKILL_UI_HELP_OK: rounding, menu change/serialization, palette coverage, bounded tooltips, native menu themes")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("TEST_SKILL_UI_HELP_FAILED: " + failure)
		get_tree().quit(1)


func _show_visual_editor() -> void:
	Locale.language = "zh"
	PlayerData.skill_tutorial_active = false
	PlayerData.card_draft = {"card_type": "minion", "name": "取整验收", "cost": 3, "hp": 5, "atk": 2, "skill1": {}, "skill2": {}}
	PlayerData.editing_skill_index = 1
	var editor = preload("res://SkillEditor.tscn").instantiate()
	add_child(editor)
	await _settle()
	editor._load_skill({"skill_name": "取整与魅惑说明", "trigger": "on_activate", "probability": 100, "effects": [
		{"effect": "damage", "target": "target_single", "target_side": "enemy", "value_expr": _expression(5, 2)},
		{"effect": "charm", "target": "target_single", "target_side": "enemy", "value": 1},
	]})
	editor._update_summary()
	editor._update_trigger_preview()
	DisplayServer.window_set_title("CARDEX · 运算与悬停说明验收")
	if OS.get_cmdline_user_args().has("--trace-hints"):
		var timer := Timer.new()
		timer.wait_time = 3
		timer.timeout.connect(func():
			var hints = UIMotion.get_node("HoverHints")
			if is_instance_valid(hints.active_menu):
				print("HINT_TRACE ", hints.active_menu.visible, " item=", hints.active_menu.get_focused_item(), " text=", hints.current_text, " panel=", hints.panel.visible, " rect=", hints.panel.get_global_rect())
		)
		add_child(timer)
		timer.start()


func _expression(a: int, b: int, mode: String = "round") -> Dictionary:
	return {"kind": "expr", "op": "/", "a": {"kind": "num", "value": a}, "b": {"kind": "num", "value": b}, "rounding": mode}


func _test_rounding() -> void:
	for row in [[5, 2, 3, 3, 2], [-5, 2, -3, -2, -3], [5, -2, -3, -2, -3], [1, 3, 0, 1, 0], [5, 0, 0, 0, 0]]:
		for i in range(3):
			var expr := _expression(row[0], row[1], ["round", "ceil", "floor"][i])
			_assert(SkillEngine._eval_operand(expr, null, null, {}) == row[i + 2], "signed rounding and zero divisor")
	var old_expr := _expression(5, 2)
	old_expr.erase("rounding")
	_assert(SkillEngine._eval_operand(old_expr, null, null, {}) == 3, "old expressions default to nearest")
	var nested := {"kind": "expr", "op": "/", "rounding": "ceil", "a": _expression(5, 2, "floor"), "b": {"kind": "num", "value": 3}}
	_assert(SkillEngine._eval_operand(nested, null, null, {}) == 1, "each nested expression owns independent rounding")
	_assert(SkillTextFormatter._format_operand(nested).contains("⌈") and SkillTextFormatter._format_operand(nested).contains("⌊"), "preview must preserve both rounding choices")
	var card := CardData.new("取整保存", 1, 2, 1, [{"trigger": "on_activate", "effects": [{"effect": "damage", "value_expr": nested}]}])
	var restored := PlayerData.deserialize_card(PlayerData.serialize_card(card))
	_assert(restored.skills[0].effects[0].value_expr == nested, "rounding must survive card serialization")


func _test_rounding_menu() -> void:
	var expr := _expression(5, 2)
	var slot := ValueSlot.new()
	slot.setup(expr, "value", "var_id", "kind")
	add_child(slot)
	await _settle()
	var changes := [0]
	slot.changed.connect(func(): changes[0] += 1)
	var menu := slot._open_rounding_menu(slot)
	_assert(menu.item_count == 3 and menu.is_item_checked(0), "right-click menu exposes three radio choices, nearest default")
	menu.id_pressed.emit(2)
	await _settle()
	_assert(expr.rounding == "floor" and changes[0] == 1, "menu must change the actual bound expression and notify undo pipeline")
	_assert(SkillEngine._eval_operand(expr, null, null, {}) == 2, "menu choice must affect execution")
	var target := ValueSlot.new()
	var target_data := {"kind": "num", "value": 8}
	target.setup(target_data, "value", "var_id", "kind")
	add_child(target)
	await _settle()
	var moved := expr.duplicate(true)
	target._drop_var(Vector2.ZERO, {"type": "expr_block", "expr_kind": "/", "expression": moved, "from_slot": slot})
	_assert(target_data == moved and expr.kind == "num", "moving an expression must retain operands and rounding")
	target.queue_free()
	slot.queue_free()
	await _settle()


func _test_editor_rounding_history() -> void:
	PlayerData.skill_tutorial_active = false
	PlayerData.card_draft = {"card_type": "minion", "name": "取整历史", "cost": 3, "hp": 5, "atk": 2, "skill1": {}, "skill2": {}}
	PlayerData.editing_skill_index = 1
	var editor = preload("res://SkillEditor.tscn").instantiate()
	add_child(editor)
	await _settle()
	editor._load_skill({"skill_name": "取整历史", "trigger": "on_activate", "probability": 100, "effects": [
		{"effect": "damage", "target": "target_single", "target_side": "enemy", "value_expr": _expression(5, 2)},
	]})
	editor._reset_undo_history()
	await _settle()
	var expression_slot: ValueSlot
	for node in editor.find_children("*", "ValueSlot", true, false):
		if node._slot_mode() == "expr":
			expression_slot = node
			break
	_assert(expression_slot != null, "real editor must expose an expression slot")
	if expression_slot != null:
		var menu := expression_slot._open_rounding_menu(expression_slot)
		menu.id_pressed.emit(2)
		await _settle()
		_assert(editor._build_skill().effects[0].value_expr.rounding == "floor", "editor save payload must include menu rounding")
		editor._undo()
		await _settle()
		_assert(editor._build_skill().effects[0].value_expr.rounding == "round", "undo must restore expression rounding")
		editor._redo()
		await _settle()
		var saved: Dictionary = editor._build_skill().duplicate(true)
		_assert(saved.effects[0].value_expr.rounding == "floor", "redo must restore expression rounding")
		editor._load_skill(saved)
		await _settle()
		_assert(editor._build_skill().effects[0].value_expr.rounding == "floor", "editor reload must retain rounding")
	editor.queue_free()
	await _settle()


func _test_hint_coverage() -> void:
	for language in ["zh", "en"]:
		Locale.language = language
		for id: String in SkillRegistry.EFFECT_META:
			_assert(not SkillHelp.description("effect", id).is_empty(), "missing effect hint: " + language + ":" + id)
		for id: String in SkillRegistry.VALUE_VAR_IDS:
			_assert(not SkillHelp.description("value_var", id).is_empty(), "missing variable hint: " + id)
		for id: String in SkillRegistry.TRIGGER_META:
			_assert(not SkillHelp.description("trigger", id).is_empty(), "missing trigger hint: " + id)
		for id in ["minion", "spell", "parasite"]:
			_assert(not SkillHelp.description("card_type", id).is_empty(), "missing creation hint")
	Locale.language = "zh"
	PlayerData.card_draft = {"card_type": "minion", "name": "说明测试", "cost": 1, "hp": 3, "atk": 1, "skill1": {}, "skill2": {}}
	PlayerData.editing_skill_index = 0
	var editor = preload("res://SkillEditor.tscn").instantiate()
	add_child(editor)
	await _settle()
	var count := 0
	for block in editor.palette_vbox.find_children("*", "SkillPaletteBlock", true, false):
		count += 1
		_assert(not block.tooltip_text.is_empty(), "actual palette block missing explanation: " + block.text)
	_assert(count > 30, "test must cover the actual built palette, not just a few samples")
	editor._select_trigger(SkillEngine.TRIGGER_ON_BOARD_CHANGED)
	_assert(editor.trigger_side_row.visible, "board-change trigger must expose its side selector")
	editor.trigger_side_select.select(0)
	editor.trigger_side_select.item_selected.emit(0)
	editor.effect_data = [{"effect": SkillEngine.EFFECT_GAIN_ATTACK, "target": SkillEngine.TARGET_SELF, "value": 1}]
	var board_skill: Dictionary = editor._build_skill()
	_assert(str(board_skill.get("trigger_side", "")) == SkillEngine.TARGET_SIDE_ENEMY, "board-change side must be serialized into the skill")
	editor.queue_free()
	await _settle()
	PlayerData.editing_skill_index = 3
	PlayerData.card_draft["talent"] = {"skill_name": "变量天赋", "skill_type": SkillEngine.SKILL_TYPE_TALENT, "trigger": SkillEngine.TRIGGER_ON_ADDED, "effects": [{"effect": SkillEngine.EFFECT_MATCH_MAX_HP, "target": SkillEngine.TARGET_SELF, "value": 1}]}
	var talent_editor = preload("res://SkillEditor.tscn").instantiate()
	add_child(talent_editor)
	await _settle()
	var has_variable := false
	var has_math := false
	var leaked_target_variable := false
	for block in talent_editor.palette_vbox.find_children("*", "SkillPaletteBlock", true, false):
		has_variable = has_variable or str(block.var_id) != ""
		has_math = has_math or str(block.expr_kind) != ""
		leaked_target_variable = leaked_target_variable or SkillRegistry.is_target_relative_var(str(block.var_id))
	_assert(has_variable and has_math, "talent palette must restore variable and math reporter blocks")
	_assert(not leaked_target_variable, "talent palette must not imply a manually selected target through target-relative variables")
	_assert(SkillEngine.TRIGGER_ON_BOARD_CHANGED in talent_editor._trigger_keys(), "board-change trigger must be available to talents")
	talent_editor._select_trigger(SkillEngine.TRIGGER_ON_BOARD_CHANGED)
	var has_talent_cost_change := false
	for block in talent_editor.palette_vbox.find_children("*", "SkillPaletteBlock", true, false):
		has_talent_cost_change = has_talent_cost_change or str(block.effect_id) == SkillEngine.EFFECT_CHANGE_COST
	_assert(has_talent_cost_change, "board-change talent palette must expose cost change")
	var talent_cost_effect: Dictionary = talent_editor._default_effect(SkillEngine.EFFECT_CHANGE_COST)
	_assert(str(talent_cost_effect.get("target", "")) == SkillEngine.TARGET_SELF, "passive talent effects must use a deterministic self target")
	talent_editor.queue_free()
	await _settle()


func _test_boundaries() -> void:
	for viewport_size in [Vector2i(320, 240), Vector2i(640, 360), Vector2i(1280, 720)]:
		var viewport := SubViewport.new()
		viewport.size = viewport_size
		add_child(viewport)
		var hints := Hints.new()
		viewport.add_child(hints)
		_assert(hints.layer > 1024, "hints must render above embedded popup menus")
		hints.set_process(false)
		for at in [Vector2.ZERO, Vector2(viewport_size.x, 0), Vector2(0, viewport_size.y), Vector2(viewport_size), Vector2(viewport_size) / 2]:
			for text in [SkillHelp.description("effect", "charm"), "long_unbroken_text_".repeat(100), "多行说明\n".repeat(100)]:
				hints.show_hint(text, at)
				await _settle()
				_assert(Rect2(Vector2.ZERO, Vector2(viewport_size)).encloses(hints.panel.get_global_rect()), "tooltip overflow at " + str(at) + " / " + str(viewport_size))
		viewport.queue_free()
		await _settle()
	var control := Control.new()
	control.tooltip_text = "old"
	_assert(Hints.hint_for(control).text == "old", "hint must read current text")
	control.tooltip_text = ""
	_assert(Hints.hint_for(control).is_empty(), "reused control must not retain a removed tooltip")
	control.free()


func _test_menu_theme() -> void:
	for control in [OptionButton.new(), LineEdit.new(), TextEdit.new()]:
		add_child(control)
		var menu: PopupMenu = control.get_popup() if control is OptionButton else control.get_menu()
		_assert(menu.get_theme_stylebox("panel") is StyleBoxFlat, "native dropdown/context menu must receive game style")
		_assert(menu.get_theme_stylebox("panel").bg_color == UITheme.COLOR_PANEL_DARK, "all native menus must share fill colour")
		control.queue_free()
	var popup := PopupMenu.new()
	add_child(popup)
	_assert(popup.get_theme_stylebox("panel").bg_color == UITheme.COLOR_PANEL_DARK, "left/right-click dynamic popups must use same theme")
	popup.add_item("Charm")
	popup.set_item_tooltip(0, SkillHelp.description("effect", "charm"))
	popup.set_focused_item(0)
	_assert(Hints.menu_hint(popup).text == SkillHelp.description("effect", "charm"), "popup item hints must survive native tooltip suppression")
	popup.set_item_tooltip(0, "")
	_assert(Hints.menu_hint(popup).is_empty(), "popup item hints must clear when removed")
	popup.queue_free()
	var dialog := ConfirmationDialog.new()
	var content := VBoxContainer.new()
	var label := Label.new()
	var list := ItemList.new()
	content.add_child(label)
	content.add_child(list)
	dialog.add_child(content)
	add_child(dialog)
	UITheme.apply_dialog(dialog, true)
	_assert(dialog.get_theme_stylebox("panel").bg_color == UITheme.COLOR_PANEL_DARK, "dialogs must use the shared dark panel")
	_assert(dialog.get_theme_stylebox("embedded_border").border_color == UITheme.COLOR_GOLD, "dialog window frame must use the shared gold border")
	_assert(dialog.get_ok_button().get_meta("ui_button_variant", "") == "primary", "dialog confirmation must use primary action style")
	_assert(dialog.get_cancel_button().get_meta("ui_button_variant", "") == "secondary", "dialog cancellation must use secondary action style")
	_assert(list.get_theme_stylebox("panel").bg_color == UITheme.COLOR_PANEL_DARK, "dialog lists must use the shared dark surface")
	dialog.queue_free()


func _test_live_menu_hover() -> void:
	var popup := PopupMenu.new()
	popup.add_item("Charm")
	popup.set_item_tooltip(0, SkillHelp.description("effect", "charm"))
	add_child(popup)
	popup.position = Vector2i(100, 100)
	popup.popup()
	await _settle()
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(popup.position) + Vector2(35, 20)
	motion.relative = Vector2(5, 5)
	motion.velocity = Vector2(100, 100)
	get_viewport().push_input(motion, true)
	await _settle()
	_assert(popup.get_focused_item() == 0, "real mouse motion must focus the popup item")
	var hints = UIMotion.get_node("HoverHints")
	hints._process(1.0)
	await _settle()
	var text: String = hints.label.get_parsed_text().replace(" \u2009", "")
	_assert(hints.panel.visible and text == SkillHelp.description("effect", "charm"), "hovered popup item must display the full shared hint")
	_assert(hints.label.text.contains("res://res/ui/keywords/charm.svg[/img]"), "hovered charm hint must display its keyword icon")
	_assert(Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).encloses(hints.panel.get_global_rect()), "live menu hint must remain inside viewport")
	popup.hide()
	popup.queue_free()
	await _settle()


func _settle() -> void:
	for frame in range(4):
		await get_tree().process_frame


func _assert(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)
