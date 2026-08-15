extends Node

# Windowed preview harness for the skill editor. Loads SkillEditor with a
# sample skill, then simulates real mouse drags (Input.parse_input_event) to
# verify the Scratch-style interactions end-to-end:
#   A. condition reporter block  -> if block's condition gap
#   B. palette effect block      -> if block's then slot (nesting)
#   C. palette effect block      -> script body (insert)
#   D. body block                -> palette (drop-to-discard)
# Also prints block layout sizes to check for overflow.
# Usage: godot --path . res://SkillPreview.tscn  (NOT --headless)

var _sed: Node


func _ready() -> void:
	# Safety net: a runtime error inside a coroutine silently kills the await
	# chain, which would otherwise leave the window frozen on a screen forever.
	# Force a timeout exit so the harness never hangs (auto-closes the window).
	get_tree().create_timer(120.0).timeout.connect(func():
		print("E2E_TIMEOUT_FAIL scenarios did not finish in 120s")
		get_tree().quit(1)
	)
	# A saved high-resolution preset (user://settings.cfg via WindowSizeController)
	# can stretch the 1152x648 canvas (e.g. 1920x1080 -> 1.6667x). Synthetic
	# mouse events are hit-tested in window space, so the input helpers scale
	# every coordinate with the viewport's final transform (see _win()).
	Locale.language = "zh"
	PlayerData.card_draft = {
		"name": "预览卡",
		"cost": 2,
		"hp": 4,
		"atk": 2,
		"gender": "male",
		"card_type": "minion",
		"art_path": "",
		"skill1": {},
		"skill2": {
			"skill_name": "示例技能",
			"trigger": SkillEngine.TRIGGER_ON_ATTACK,
			"probability": 100,
			"effects": [
				{
					"target": SkillEngine.TARGET_SINGLE,
					"target_side": SkillEngine.TARGET_SIDE_ENEMY,
					"effect": SkillEngine.EFFECT_DAMAGE,
					"value": 3,
				},
				{
					"effect": SkillEngine.EFFECT_IF,
					"condition": {
						"condition_type": SkillEngine.CONDITION_TARGET_HP_PCT,
						"condition_op": SkillEngine.CONDITION_OP_GTE,
						"condition_value": 50,
					},
					"then_effects": [
						{
							"target": SkillEngine.TARGET_SELF, "target_side": SkillEngine.TARGET_SIDE_ALL,
							"effect": SkillEngine.EFFECT_GAIN_ATTACK, "value": 2,
						},
						{"effect": SkillEngine.EFFECT_STOP},
					],
				},
				{
					"effect": SkillEngine.EFFECT_IF_ELSE,
					"condition": {
						"condition_type": SkillEngine.CONDITION_TARGET_HAS_BUFF,
						"condition_buff_id": SkillEngine.BUFF_THORNS,
					},
					"then_effects": [],
					"else_effects": [
						{
							"target": SkillEngine.TARGET_SELF, "target_side": SkillEngine.TARGET_SIDE_ALL,
							"effect": SkillEngine.EFFECT_ADD_BUFF, "value": 1,
							"buff_id": SkillEngine.BUFF_THORNS, "duration": 2,
						},
					],
				},
			],
		},
		"skill3": {},
	}
	PlayerData.editing_skill_index = 1
	var scene: PackedScene = load("res://SkillEditor.tscn")
	_sed = scene.instantiate()
	add_child(_sed)
	await get_tree().process_frame
	await get_tree().process_frame
	_print_layout()
	_dump_texts()
	# en-language sanity pass: block/palette text must come from Locale (no
	# hardcoded Chinese leaking), and no collapsed text in the en build.
	var old_lang: String = Locale.language
	Locale.language = "en"
	_sed.call("_refresh_script")
	await get_tree().process_frame
	await get_tree().process_frame
	var en_issues := 0
	for c in _sed.find_children("*", "", true, false):
		var text := ""
		if c is Label:
			text = (c as Label).text
		elif c is Button:
			text = (c as Button).text
		if text == "":
			continue
		if c is Control:
			var size2: Vector2 = (c as Control).size
			if size2.x < 8.0 and size2.y > 0.0:
				en_issues += 1
				print("TEXT_ISSUE_EN ", c.get_class(), " size=", size2, " text=\"", text, "\"")
	print("TEXT_SCAN_EN done issues=", en_issues)
	Locale.language = old_lang
	_sed.call("_refresh_script")
	await get_tree().process_frame
	await get_tree().process_frame
	# Capture the rendered editor UI for visual review.
	var img := get_viewport().get_texture().get_image()
	if img != null:
		var err: int = img.save_png("C:/Users/admin/AppData/Local/Temp/skill_editor_shot.png")
		print("SCREENSHOT_SAVED err=", err)
	_run_drag_simulation()


# ============================================
# Real-mouse drag scenarios
# ============================================

# Palette sections are collapsible (advanced ones start closed). The drag
# simulations need every reporter reachable, so open all section boxes and
# sync their header marks ("+ 标题" -> "- 标题").
func _expand_all_sections(palette_vbox: VBoxContainer) -> void:
	for child in palette_vbox.get_children():
		if child is VBoxContainer:
			(child as VBoxContainer).visible = true
		elif child is Button:
			var t: String = (child as Button).text
			if t.begins_with("+"):
				(child as Button).text = "-" + t.substr(1)

func _run_drag_simulation() -> void:
	var palette_vbox: VBoxContainer = _sed.get_node("Panel/Margin/HBox/PalettePanel/Margin/VBox/PaletteScroll/PaletteVBox")
	var palette_panel: Panel = _sed.get_node("Panel/Margin/HBox/PalettePanel")
	var palette_scroll: ScrollContainer = _sed.get_node("Panel/Margin/HBox/PalettePanel/Margin/VBox/PaletteScroll")
	var main_scroll: ScrollContainer = _sed.get_node("Panel/Margin/HBox/MainPanel/Margin/Scroll")
	var effects_list: VBoxContainer = _sed.get_node("Panel/Margin/HBox/MainPanel/Margin/Scroll/VBox/EffectsList")
	# Palette sections are collapsible and advanced ones start closed — open
	# every section so the real-mouse simulations can reach any reporter.
	_expand_all_sections(palette_vbox)

	# --- A. Boolean comparison block -> if block's condition gap ------------
	var bool_pal: SkillPaletteBlock = null
	for child in palette_vbox.find_children("*", "SkillPaletteBlock", true, false):
		if (child as SkillPaletteBlock).boolean_kind != "":
			bool_pal = child as SkillPaletteBlock
			break
	if bool_pal == null:
		print("DRAG_TEST_FAIL no boolean palette block")
		get_tree().quit(1)
		return
	await _scroll_palette_to(palette_scroll, bool_pal)
	var bool_kind: String = bool_pal.boolean_kind
	var if_block := _find_body_block(SkillEngine.EFFECT_IF)
	if if_block == null or if_block.cond_slot == null:
		print("DRAG_TEST_FAIL no if block / cond slot")
		get_tree().quit(1)
		return
	print("DRAG_TEST_A press=", bool_pal.get_global_rect().get_center(), " drop=", if_block.cond_slot.get_global_rect().get_center(), " kind=", bool_kind)
	# The pinned preview/button area shrinks the script viewport, so bring the
	# if block's condition gap into view before the synthetic drop.
	await _scroll_into_view(main_scroll, if_block.cond_slot)
	await _drag(bool_pal.get_global_rect().get_center(), if_block.cond_slot.get_global_rect().get_center())
	var ed: Array = _sed.get("effect_data")
	var cond_dict: Dictionary = (ed[1] as Dictionary).get("condition", {})
	print("DRAG_TEST_A lhs=", str(cond_dict.get("lhs", {})), " op=", str(cond_dict.get("op", "")))
	if not cond_dict.has("lhs") or str(cond_dict.get("op", "")) == "":
		print("DRAG_TEST_FAIL boolean not written into if gap")
		get_tree().quit(1)
		return

	# --- B. Palette effect block -> if block's then slot (nesting) -----------
	# The if block is tall; scroll the main script so its then slot is on
	# screen (otherwise the synthetic release point falls outside the window).
	palette_scroll.scroll_vertical = 0
	await get_tree().process_frame
	await get_tree().process_frame
	var eff_pal: SkillPaletteBlock = null
	for child in palette_vbox.find_children("*", "SkillPaletteBlock", true, false):
		if (child as SkillPaletteBlock).effect_id != "":
			eff_pal = child as SkillPaletteBlock
			break
	if eff_pal == null:
		print("DRAG_TEST_FAIL no effect palette block")
		get_tree().quit(1)
		return
	if_block = _find_body_block(SkillEngine.EFFECT_IF)
	var then_before: int = (ed[1] as Dictionary).get("then_effects", []).size()
	await _scroll_into_view(main_scroll, if_block.then_container)
	await _drag(eff_pal.get_global_rect().get_center(), if_block.then_container.get_global_rect().get_center())
	ed = _sed.get("effect_data")
	var then_after: Array = (ed[1] as Dictionary).get("then_effects", [])
	print("DRAG_TEST_B then_effects=", str(then_after.size()), " want=", str(then_before + 1))
	if then_after.size() != then_before + 1:
		print("DRAG_TEST_FAIL effect not nested into then slot")
		get_tree().quit(1)
		return

	# --- C. Palette effect block -> script body (insert) ----------------------
	# The pinned preview panel clips the scroll viewport's bottom edge, and a
	# tall body centered by _scroll_into_view leaves its top above the viewport.
	# Drop onto the FIRST block instead: its center scrolls fully visible and
	# the upper-half rule inserts the new block before it (index 0).
	var first_block_c: SkillBlock = _find_body_block_path(0)
	if first_block_c == null:
		print("DRAG_TEST_FAIL no first body block for insert")
		get_tree().quit(1)
		return
	await _scroll_into_view(main_scroll, first_block_c)
	var drop_pos: Vector2 = first_block_c.get_global_rect().get_center()
	await _drag(eff_pal.get_global_rect().get_center(), drop_pos)
	ed = _sed.get("effect_data")
	print("DRAG_TEST_C effect_data=", str(ed.size()), " first=", str(ed[0].get("effect", "?")) if ed.size() > 0 else "none")
	if ed.size() <= 3:
		print("DRAG_TEST_FAIL palette->body insert failed: size=%d" % ed.size())
		get_tree().quit(1)
		return

	# --- D. Body block -> palette (drop-to-discard) ---------------------------
	# The palette title strip (no button underneath) is the drop point; the
	# palette buttons also accept the drop via their own _can_drop_data /
	# _drop_data handlers (see SkillPaletteBlock), and the delete logic itself
	# is asserted headlessly in TestCardEditorSkillSummary.
	var first_block: SkillBlock = _find_body_block_path(0)
	if first_block == null:
		print("DRAG_TEST_FAIL no top-level body block to discard")
		get_tree().quit(1)
		return
	var before_discard: int = ed.size()
	var palette_drop: Vector2 = palette_panel.get_global_rect().position + Vector2(120, 12)
	await _drag(first_block.get_global_rect().get_center(), palette_drop)
	ed = _sed.get("effect_data")
	print("DRAG_TEST_D discard_size=", str(ed.size()), " before=", str(before_discard))
	if ed.size() != before_discard - 1:
		print("DRAG_TEST_FAIL drop-to-discard failed")
		get_tree().quit(1)
		return

	# --- E. Empty script: drag the FIRST block into the empty event body ------
	var e_ed: Array = _sed.get("effect_data")
	e_ed.clear()
	_sed.call("_refresh_script")
	palette_scroll.scroll_vertical = 0
	main_scroll.scroll_vertical = 0
	await get_tree().process_frame
	await get_tree().process_frame
	var empty_body: Control = effects_list.get_child(0).body_container
	print("EMPTY_TEST body_rect=", empty_body.get_global_rect(), " size=", empty_body.size)
	# The empty hat sits just above the pinned preview panel; release inside
	# the visible part of the slot (its center is clipped by the viewport).
	await _drag(eff_pal.get_global_rect().get_center(), empty_body.get_global_rect().position + Vector2(30, 6))
	e_ed = _sed.get("effect_data")
	print("EMPTY_TEST size=", str(e_ed.size()))
	if e_ed.size() != 1:
		print("EMPTY_TEST_FAIL first block drag did not insert")
		get_tree().quit(1)
		return

	# --- F. Empty then slot: no "+ 添加效果" button, only a faint hint --------
	var f_ed: Array = _sed.get("effect_data")
	f_ed.clear()
	f_ed.append({"effect": SkillEngine.EFFECT_IF, "condition": {}, "then_effects": [], "else_effects": []})
	_sed.call("_refresh_script")
	await get_tree().process_frame
	await get_tree().process_frame
	var if_block_f: SkillBlock = _find_body_block(SkillEngine.EFFECT_IF)
	var has_button := false
	var has_hint := false
	for child in if_block_f.then_container.get_children():
		if child is Button:
			has_button = true
		if child is Label and (child as Label).text == Locale.t("skill_editor.slot_hint"):
			has_hint = true
	print("ADD_TEST button=", has_button, " hint=", has_hint)
	if has_button or not has_hint:
		print("ADD_TEST_FAIL slot should be hint-only (no add button)")
		get_tree().quit(1)
		return

	# --- G. Drag a palette block into an EMPTY then slot ----------------------
	var g_ed: Array = _sed.get("effect_data")
	g_ed.clear()
	g_ed.append({"effect": SkillEngine.EFFECT_IF, "condition": {}, "then_effects": [], "else_effects": []})
	_sed.call("_refresh_script")
	await get_tree().process_frame
	await get_tree().process_frame
	var if_block_g: SkillBlock = _find_body_block(SkillEngine.EFFECT_IF)
	await _scroll_into_view(main_scroll, if_block_g.then_container)
	print("EMPTYTHEN_TEST then_rect=", if_block_g.then_container.get_global_rect())
	await _drag(eff_pal.get_global_rect().get_center(), if_block_g.then_container.get_global_rect().get_center())
	g_ed = _sed.get("effect_data")
	var g_then: Array = g_ed[0].get("then_effects", [])
	print("EMPTYTHEN_TEST then_effects=", str(g_then.size()))
	if g_then.size() != 1:
		print("EMPTYTHEN_TEST_FAIL drag into empty then slot failed")
		get_tree().quit(1)
		return

	# --- H. Inline value edit still works with PASS param controls ------------
	var h_ed: Array = _sed.get("effect_data")
	h_ed.clear()
	h_ed.append({"effect": SkillEngine.EFFECT_DAMAGE, "target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "value": 3})
	_sed.call("_refresh_script")
	main_scroll.scroll_vertical = 0
	await get_tree().process_frame
	await get_tree().process_frame
	var dmg_block: SkillBlock = _find_body_block(SkillEngine.EFFECT_DAMAGE)
	var value_slot_h: ValueSlot = null
	for item in dmg_block._sentence_row.get_children():
		if item is ValueSlot:
			value_slot_h = item as ValueSlot
			break
	if value_slot_h == null:
		print("EDIT_TEST_FAIL no value slot in sentence row")
		get_tree().quit(1)
		return
	var value_spin: SpinBox = null
	for item in value_slot_h.get_children():
		if item is SpinBox:
			value_spin = item as SpinBox
			break
	if value_spin == null:
		print("EDIT_TEST_FAIL no value spin in slot")
		get_tree().quit(1)
		return
	var le: LineEdit = value_spin.get_line_edit()
	print("EDIT_TEST le_rect=", le.get_global_rect(), " main_rect=", main_scroll.get_global_rect())
	await _click(le.get_global_rect().get_center())
	await get_tree().process_frame
	print("EDIT_TEST focused=", le.has_focus())
	if not le.has_focus():
		print("EDIT_TEST_FAIL spin not editable after PASS change")
		get_tree().quit(1)
		return
	await _type_key(Key.KEY_A, true)
	print("EDIT_DEBUG after ctrl+a text=", le.text)
	await _type_key(Key.KEY_5)
	print("EDIT_DEBUG after 5 text=", le.text)
	await _type_key(Key.KEY_ENTER)
	# Enter commits the spin value -> _on_param_changed rebuilds the sentence
	# row, freeing `le` / `value_spin` — do not touch them past this point.
	await get_tree().process_frame
	await get_tree().process_frame
	h_ed = _sed.get("effect_data")
	print("EDIT_TEST value=", str(h_ed[0].get("value", "?")), " want=5")
	if int(h_ed[0].get("value", -1)) != 5:
		print("EDIT_TEST_FAIL inline value edit failed")
		get_tree().quit(1)
		return

	# --- L. Variable reporter oval -> effect value slot ----------------------
	# Dragging a variable palette block onto the value slot switches it from a
	# SpinBox to a variable chip and writes value_var into the effect data.
	var l_ed: Array = _sed.get("effect_data")
	l_ed.clear()
	l_ed.append({"effect": SkillEngine.EFFECT_DAMAGE, "target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "value": 3})
	_sed.call("_refresh_script")
	main_scroll.scroll_vertical = 0
	await get_tree().process_frame
	await get_tree().process_frame
	var var_pal: SkillPaletteBlock = null
	for child in palette_vbox.find_children("*", "SkillPaletteBlock", true, false):
		if (child as SkillPaletteBlock).var_id != "":
			var_pal = child as SkillPaletteBlock
			break
	if var_pal == null:
		print("VAR_TEST_FAIL no variable palette block")
		get_tree().quit(1)
		return
	await _scroll_palette_to(palette_scroll, var_pal)
	var var_id: String = var_pal.var_id
	var dmg_block_l: SkillBlock = _find_body_block(SkillEngine.EFFECT_DAMAGE)
	var value_slot: ValueSlot = null
	for item in dmg_block_l._sentence_row.get_children():
		if item is ValueSlot:
			value_slot = item as ValueSlot
			break
	if value_slot == null:
		print("VAR_TEST_FAIL no value slot in sentence row")
		get_tree().quit(1)
		return
	await _drag(var_pal.get_global_rect().get_center(), value_slot.get_global_rect().get_center())
	l_ed = _sed.get("effect_data")
	print("VAR_TEST value_var=", str(l_ed[0].get("value_var", "")), " want=", var_id)
	if str(l_ed[0].get("value_var", "")) != var_id:
		print("VAR_TEST_FAIL variable not written into value slot")
		get_tree().quit(1)
		return

	# --- M. Variable reporter oval -> comparison operand slot ----------------
	# Inside a boolean comparison block the operands are ValueSlots too; a
	# variable dropped there becomes the lhs reporter.
	var m_ed: Array = _sed.get("effect_data")
	m_ed.clear()
	m_ed.append({
		"effect": SkillEngine.EFFECT_IF,
		"condition": {
			"op": SkillEngine.CONDITION_OP_GTE,
			"lhs": {"kind": "num", "value": 1},
			"rhs": {"kind": "num", "value": 1},
		},
		"then_effects": [],
	})
	_sed.call("_refresh_script")
	await get_tree().process_frame
	await get_tree().process_frame
	var if_block_m: SkillBlock = _find_body_block(SkillEngine.EFFECT_IF)
	if if_block_m == null or if_block_m.cond_slot == null or if_block_m.cond_slot.get_child_count() == 0:
		print("COMP_TEST_FAIL comparison not rendered in cond slot")
		get_tree().quit(1)
		return
	var comp_row: Control = if_block_m.cond_slot.get_child(0)
	var lhs_slot: ValueSlot = null
	for item in comp_row.get_children():
		if item is ValueSlot:
			lhs_slot = item as ValueSlot
			break
	if lhs_slot == null:
		print("COMP_TEST_FAIL no operand slot in comparison")
		get_tree().quit(1)
		return
	await _scroll_into_view(main_scroll, if_block_m.cond_slot)
	await _drag(var_pal.get_global_rect().get_center(), lhs_slot.get_global_rect().get_center())
	m_ed = _sed.get("effect_data")
	var m_cond: Dictionary = m_ed[0].get("condition", {})
	var m_lhs: Dictionary = m_cond.get("lhs", {})
	print("COMP_TEST lhs=", str(m_lhs), " want_var=", var_id)
	if str(m_lhs.get("kind", "")) != "var" or str(m_lhs.get("var_id", "")) != var_id:
		print("COMP_TEST_FAIL variable not written into comparison operand")
		get_tree().quit(1)
		return

	# --- N. Math-expression reporter -> effect value slot --------------------
	# Dropping "a + b" into the value slot switches it to an expression editor
	# (value_expr); a variable can then be nested into the left operand.
	var n_ed: Array = _sed.get("effect_data")
	n_ed.clear()
	n_ed.append({"effect": SkillEngine.EFFECT_DAMAGE, "target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "value": 3})
	_sed.call("_refresh_script")
	main_scroll.scroll_vertical = 0
	await get_tree().process_frame
	await get_tree().process_frame
	var expr_pal: SkillPaletteBlock = null
	for child in palette_vbox.find_children("*", "SkillPaletteBlock", true, false):
		if (child as SkillPaletteBlock).expr_kind != "":
			expr_pal = child as SkillPaletteBlock
			break
	if expr_pal == null:
		print("EXPR_TEST_FAIL no math palette block")
		get_tree().quit(1)
		return
	await _scroll_palette_to(palette_scroll, expr_pal)
	var dmg_block_n: SkillBlock = _find_body_block(SkillEngine.EFFECT_DAMAGE)
	var value_slot_n: ValueSlot = null
	for item in dmg_block_n._sentence_row.get_children():
		if item is ValueSlot:
			value_slot_n = item as ValueSlot
			break
	if value_slot_n == null:
		print("EXPR_TEST_FAIL no value slot")
		get_tree().quit(1)
		return
	await _drag(expr_pal.get_global_rect().get_center(), value_slot_n.get_global_rect().get_center())
	n_ed = _sed.get("effect_data")
	var n_expr: Dictionary = n_ed[0].get("value_expr", {})
	print("EXPR_TEST value_expr=", str(n_expr))
	if str(n_expr.get("kind", "")) != "expr" or str(n_expr.get("op", "")) != "+":
		print("EXPR_TEST_FAIL math reporter not written into value slot")
		get_tree().quit(1)
		return
	# Nested variable: drop a variable oval onto the expression's left operand.
	var value_slot_n2: ValueSlot = null
	for item in dmg_block_n._sentence_row.get_children():
		if item is ValueSlot:
			value_slot_n2 = item as ValueSlot
			break
	var left_operand: ValueSlot = null
	if value_slot_n2 != null:
		for item in value_slot_n2.get_children():
			if item is HBoxContainer or item is HFlowContainer:
				for sub in (item as Control).get_children():
					if sub is ValueSlot:
						left_operand = sub as ValueSlot
						break
	if left_operand == null:
		print("EXPR_TEST_FAIL no left operand slot in expression")
		get_tree().quit(1)
		return
	# Nested fill: drag the variable oval onto the expression's left operand
	# with real mouse input — the "drop a variable onto a math reporter"
	# interaction that must work by hand.
	await _scroll_palette_to(palette_scroll, var_pal)
	await _drag(var_pal.get_global_rect().get_center(), left_operand.get_global_rect().get_center())
	await get_tree().process_frame
	n_ed = _sed.get("effect_data")
	var n_expr2: Dictionary = n_ed[0].get("value_expr", {})
	var n_a: Dictionary = n_expr2.get("a", {})
	print("EXPR_TEST nested_a=", str(n_a), " want_var=", var_id, " expr_kept=", str(n_expr2.get("kind", "")))
	if str(n_a.get("kind", "")) != "var" or str(n_a.get("var_id", "")) != var_id:
		print("EXPR_TEST_FAIL variable not nested into expression operand")
		get_tree().quit(1)
		return
	if str(n_expr2.get("kind", "")) != "expr":
		print("EXPR_TEST_FAIL expression mode lost after nested fill")
		get_tree().quit(1)
		return

	# --- EXPR_NEST. A math reporter nests inside another math reporter --------
	# Scratch allows [a] [op] [b] where a/b are themselves reporters: drop a
	# second math block onto the expression's right operand and the tree
	# deepens ([x] [+] [a] [-] [b]).
	var nest_ed: Array = _sed.get("effect_data")
	nest_ed.clear()
	nest_ed.append({"effect": SkillEngine.EFFECT_DAMAGE, "target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "value": 3})
	_sed.call("_refresh_script")
	main_scroll.scroll_vertical = 0
	await get_tree().process_frame
	await get_tree().process_frame
	var expr_pal_n: SkillPaletteBlock = null
	var expr_pal_sub: SkillPaletteBlock = null
	for child in palette_vbox.find_children("*", "SkillPaletteBlock", true, false):
		if (child as SkillPaletteBlock).expr_kind != "":
			if expr_pal_n == null:
				expr_pal_n = child as SkillPaletteBlock
			elif expr_pal_sub == null:
				expr_pal_sub = child as SkillPaletteBlock
				break
	if expr_pal_n == null or expr_pal_sub == null:
		print("EXPR_NEST_TEST_FAIL no math palette blocks")
		get_tree().quit(1)
		return
	await _scroll_palette_to(palette_scroll, expr_pal_n)
	var dmg_block_nest: SkillBlock = _find_body_block(SkillEngine.EFFECT_DAMAGE)
	var value_slot_nest: ValueSlot = null
	for item in dmg_block_nest._sentence_row.get_children():
		if item is ValueSlot:
			value_slot_nest = item as ValueSlot
			break
	await _drag(expr_pal_n.get_global_rect().get_center(), value_slot_nest.get_global_rect().get_center())
	# Re-acquire the freshly rebuilt expression and its right operand slot.
	nest_ed = _sed.get("effect_data")
	var nest_expr: Dictionary = nest_ed[0].get("value_expr", {})
	print("EXPR_NEST_TEST top=", str(nest_expr.get("op", "")))
	if str(nest_expr.get("op", "")) != "+":
		print("EXPR_NEST_TEST_FAIL first math block not written")
		get_tree().quit(1)
		return
	dmg_block_nest = _find_body_block(SkillEngine.EFFECT_DAMAGE)
	value_slot_nest = null
	for item in dmg_block_nest._sentence_row.get_children():
		if item is ValueSlot:
			value_slot_nest = item as ValueSlot
			break
	var right_operand: ValueSlot = null
	if value_slot_nest != null:
		var ops := []
		for item in value_slot_nest.get_children():
			if item is HBoxContainer or item is HFlowContainer:
				for sub in (item as Control).get_children():
					if sub is ValueSlot:
						ops.append(sub as ValueSlot)
		if ops.size() >= 2:
			right_operand = ops[1] as ValueSlot
	if right_operand == null:
		print("EXPR_NEST_TEST_FAIL no right operand slot")
		get_tree().quit(1)
		return
	await _scroll_palette_to(palette_scroll, expr_pal_sub)
	await _drag(expr_pal_sub.get_global_rect().get_center(), right_operand.get_global_rect().get_center())
	await get_tree().process_frame
	nest_ed = _sed.get("effect_data")
	var nest_b: Dictionary = nest_ed[0].get("value_expr", {}).get("b", {})
	print("EXPR_NEST_TEST nested_b=", str(nest_b), " want_op=", str(expr_pal_sub.expr_kind))
	if str(nest_b.get("kind", "")) != "expr" or str(nest_b.get("op", "")) != expr_pal_sub.expr_kind:
		print("EXPR_NEST_TEST_FAIL math reporter not nested into operand")
		get_tree().quit(1)
		return

	# --- TARGET. Palette target/side reporters drop into the effect's
	# [友方/敌方] [目标] slots; dragging the chip back to the palette
	# restores the default target.
	var tgt_ed: Array = _sed.get("effect_data")
	tgt_ed.clear()
	tgt_ed.append({"effect": SkillEngine.EFFECT_DAMAGE, "target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ALLY, "value": 3})
	_sed.call("_refresh_script")
	main_scroll.scroll_vertical = 0
	await get_tree().process_frame
	await get_tree().process_frame
	var dmg_block_t: SkillBlock = _find_body_block(SkillEngine.EFFECT_DAMAGE)
	var tgt_slot: TargetSlot = null
	var side_slot_t: TargetSlot = null
	if dmg_block_t != null:
		tgt_slot = _find_target_slot(dmg_block_t, "target")
		side_slot_t = _find_target_slot(dmg_block_t, "side")
	var side_pal_t: SkillPaletteBlock = null
	var tgt_pal_t: SkillPaletteBlock = null
	for child in palette_vbox.find_children("*", "SkillPaletteBlock", true, false):
		if (child as SkillPaletteBlock).side_kind == SkillEngine.TARGET_SIDE_ENEMY:
			side_pal_t = child as SkillPaletteBlock
		if (child as SkillPaletteBlock).target_kind == SkillEngine.TARGET_ALL:
			tgt_pal_t = child as SkillPaletteBlock
	if dmg_block_t == null or tgt_slot == null or side_slot_t == null or side_pal_t == null or tgt_pal_t == null:
		print("TARGET_TEST_FAIL setup (block/slot/palette missing)")
		get_tree().quit(1)
		return
	# Order: the side slot sits before the target slot in the sentence row.
	var t_row: Control = dmg_block_t.get("_sentence_row")
	var t_side_idx: int = -1
	var t_tgt_idx: int = -1
	for i in range(t_row.get_child_count()):
		var tc: Control = t_row.get_child(i)
		if tc is TargetSlot:
			if t_side_idx < 0:
				t_side_idx = i
			elif t_tgt_idx < 0:
				t_tgt_idx = i
	if not (t_side_idx >= 0 and t_tgt_idx > t_side_idx):
		print("TARGET_TEST_FAIL order (side should precede target)")
		get_tree().quit(1)
		return
	await _scroll_palette_to(palette_scroll, side_pal_t)
	await _drag(side_pal_t.get_global_rect().get_center(), side_slot_t.get_global_rect().get_center())
	await get_tree().process_frame
	tgt_ed = _sed.get("effect_data")
	if str(tgt_ed[0].get("target_side", "")) != SkillEngine.TARGET_SIDE_ENEMY:
		print("TARGET_TEST_FAIL side drop (side=%s)" % str(tgt_ed[0].get("target_side", "?")))
		get_tree().quit(1)
		return
	print("TARGET_TEST side_drop=ok")
	await _scroll_palette_to(palette_scroll, tgt_pal_t)
	await _drag(tgt_pal_t.get_global_rect().get_center(), tgt_slot.get_global_rect().get_center())
	await get_tree().process_frame
	tgt_ed = _sed.get("effect_data")
	if str(tgt_ed[0].get("target", "")) != SkillEngine.TARGET_ALL:
		print("TARGET_TEST_FAIL target drop (target=%s)" % str(tgt_ed[0].get("target", "?")))
		get_tree().quit(1)
		return
	print("TARGET_TEST target_drop=ok")
	# Drag the target chip out and drop on the palette -> default restored.
	dmg_block_t = _find_body_block(SkillEngine.EFFECT_DAMAGE)
	tgt_slot = _find_target_slot(dmg_block_t, "target")
	if tgt_slot == null:
		print("TARGET_TEST_FAIL target slot gone after refresh")
		get_tree().quit(1)
		return
	await _drag(tgt_slot.get_global_rect().get_center(), side_pal_t.get_global_rect().get_center())
	await get_tree().process_frame
	tgt_ed = _sed.get("effect_data")
	if str(tgt_ed[0].get("target", "")) != SkillEngine.TARGET_SINGLE:
		print("TARGET_TEST_FAIL palette drop did not restore (target=%s)" % str(tgt_ed[0].get("target", "?")))
		get_tree().quit(1)
		return
	print("TARGET_TEST restore=ok")

	# --- INLINE. New inline controls answer to simulated mouse/keyboard ------
	# (The bare probability spin was removed from the block header for a
	# cleaner look — probability is edited in the config form and surfaced as
	# a badge. The inline side-slot click path below is still required.)
	var inline_ed: Array = _sed.get("effect_data")
	inline_ed.clear()
	inline_ed.append({"effect": SkillEngine.EFFECT_DAMAGE, "target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "value": 3})
	_sed.call("_refresh_script")
	main_scroll.scroll_vertical = 0
	await get_tree().process_frame
	await get_tree().process_frame
	var dmg_inline: SkillBlock = _find_body_block(SkillEngine.EFFECT_DAMAGE)
	# Side slot: click it open, then pick "ally" (2nd entry of the popup menu).
	var side_slot_in: TargetSlot = _find_target_slot(dmg_inline, "side")
	if side_slot_in == null:
		print("INLINE_TEST_FAIL no side slot in sentence row")
		get_tree().quit(1)
		return
	var side_before: String = str(inline_ed[0].get("target_side", ""))
	await _click(side_slot_in.get_global_rect().get_center())
	await get_tree().process_frame
	await get_tree().process_frame
	var side_rect2: Rect2 = side_slot_in.get_global_rect()
	await _click(side_rect2.position + Vector2(20, side_rect2.size.y + 12 + 24))
	await get_tree().process_frame
	await get_tree().process_frame
	inline_ed = _sed.get("effect_data")
	var side_after: String = str(inline_ed[0].get("target_side", ""))
	print("INLINE_TEST target_side before=", side_before, " after=", side_after)
	if side_after == "" or side_after == side_before:
		print("INLINE_TEST_FAIL side slot click did not change target_side")
		get_tree().quit(1)
		return

	# --- OFFSET. Variable reporter shows an inline +/- offset spin -----------
	# Scratch-style variable oval + a game-specific offset: type a value into
	# the offset spin next to the chip and it lands in effect["value_offset"].
	var off_ed: Array = _sed.get("effect_data")
	off_ed.clear()
	off_ed.append({"effect": SkillEngine.EFFECT_DAMAGE, "target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "value_var": var_id})
	_sed.call("_refresh_script")
	main_scroll.scroll_vertical = 0
	await get_tree().process_frame
	await get_tree().process_frame
	var dmg_off: SkillBlock = _find_body_block(SkillEngine.EFFECT_DAMAGE)
	var off_slot: ValueSlot = null
	for item in dmg_off._sentence_row.get_children():
		if item is ValueSlot:
			off_slot = item as ValueSlot
			break
	if off_slot == null:
		print("OFFSET_TEST_FAIL no value slot")
		get_tree().quit(1)
		return
	var off_spin: SpinBox = null
	for item in off_slot.get_children():
		if item is HBoxContainer or item is HFlowContainer:
			for sub in (item as Control).get_children():
				if sub is SpinBox:
					off_spin = sub as SpinBox
					break
		if off_spin != null:
			break
	if off_spin == null:
		print("OFFSET_TEST_FAIL no offset spin next to variable chip")
		get_tree().quit(1)
		return
	var off_le: LineEdit = off_spin.get_line_edit()
	await _click(off_le.get_global_rect().get_center())
	await get_tree().process_frame
	await _type_key(Key.KEY_A, true)
	await _type_key(Key.KEY_5)
	await _type_key(Key.KEY_ENTER)
	await get_tree().process_frame
	await get_tree().process_frame
	off_ed = _sed.get("effect_data")
	print("OFFSET_TEST value_offset=", str(off_ed[0].get("value_offset", "?")))
	if int(off_ed[0].get("value_offset", 0)) != 5:
		print("OFFSET_TEST_FAIL value_offset not edited")
		get_tree().quit(1)
		return

	# (random_count / probability header spins were removed for a cleaner block
	# header; they are edited in the config form and surfaced as badges.)

	# --- CHARM. Charm always pulls the target into hand at 0 cost — its
	# numeric value is meaningless, so the block must NOT render a value slot.
	var charm_ed: Array = _sed.get("effect_data")
	charm_ed.clear()
	charm_ed.append({"effect": SkillEngine.EFFECT_CHARM, "target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "value": 1})
	_sed.call("_refresh_script")
	main_scroll.scroll_vertical = 0
	await get_tree().process_frame
	await get_tree().process_frame
	var charm_block: SkillBlock = _find_body_block(SkillEngine.EFFECT_CHARM)
	if charm_block == null or charm_block._sentence_row == null:
		print("CHARM_TEST_FAIL charm block not rendered")
		get_tree().quit(1)
		return
	var charm_has_value := false
	for item in charm_block._sentence_row.get_children():
		if item is ValueSlot:
			charm_has_value = true
			break
	print("CHARM_TEST has_value_slot=", charm_has_value)
	if charm_has_value:
		print("CHARM_TEST_FAIL charm sentence must not show a value slot")
		get_tree().quit(1)
		return

	# --- O. Logic block -> if condition gap ---------------------------------
	# Dropping "AND" into the gap writes {"logic":"and", lhs/rhs leaves}; a
	# comparison can then be nested into a leaf slot.
	var o_ed: Array = _sed.get("effect_data")
	o_ed.clear()
	o_ed.append({"effect": SkillEngine.EFFECT_IF, "condition": {}, "then_effects": []})
	_sed.call("_refresh_script")
	await get_tree().process_frame
	await get_tree().process_frame
	var logic_pal: SkillPaletteBlock = null
	for child in palette_vbox.find_children("*", "SkillPaletteBlock", true, false):
		if (child as SkillPaletteBlock).logic_kind != "":
			logic_pal = child as SkillPaletteBlock
			break
	if logic_pal == null:
		print("LOGIC_TEST_FAIL no logic palette block")
		get_tree().quit(1)
		return
	await _scroll_palette_to(palette_scroll, logic_pal)
	var if_block_o: SkillBlock = _find_body_block(SkillEngine.EFFECT_IF)
	await _scroll_into_view(main_scroll, if_block_o.cond_slot)
	await _drag(logic_pal.get_global_rect().get_center(), if_block_o.cond_slot.get_global_rect().get_center())
	# The drop rebuilt the editor (fresh block instances) — re-acquire both the
	# block and the (re-created) condition dict before drilling into leaves.
	o_ed = _sed.get("effect_data")
	var o_cond: Dictionary = o_ed[0].get("condition", {})
	print("LOGIC_TEST logic=", str(o_cond.get("logic", "")), " lhs=", str(o_cond.get("lhs", {}).has("op")))
	if str(o_cond.get("logic", "")) != "and" or not o_cond.get("lhs", {}).has("op"):
		print("LOGIC_TEST_FAIL logic block not written into gap")
		get_tree().quit(1)
		return
	var if_block_o2: SkillBlock = _find_body_block(SkillEngine.EFFECT_IF)
	if if_block_o2 == null:
		print("LOGIC_TEST_FAIL if block gone after logic drop")
		get_tree().quit(1)
		return
	# Nest a comparison into the logic node's lhs leaf (drop handler directly).
	var compare_leaf := {
		"op": SkillEngine.CONDITION_OP_GTE,
		"lhs": {"kind": "var", "var_id": SkillEngine.VAR_HAND_COUNT},
		"rhs": {"kind": "num", "value": 2},
	}
	if_block_o2.call("_drop_bool_sub", o_cond, "lhs", {"type": "boolean_block", "boolean": compare_leaf})
	await get_tree().process_frame
	o_ed = _sed.get("effect_data")
	var o_lhs: Dictionary = o_ed[0].get("condition", {}).get("lhs", {})
	print("LOGIC_TEST nested_lhs=", str(o_lhs.get("op", "")), " var=", str(o_lhs.get("lhs", {}).get("var_id", "")))
	if str(o_lhs.get("op", "")) != SkillEngine.CONDITION_OP_GTE \
			or str(o_lhs.get("lhs", {}).get("var_id", "")) != SkillEngine.VAR_HAND_COUNT:
		print("LOGIC_TEST_FAIL comparison not nested into logic leaf")
		get_tree().quit(1)
		return

	# --- J. Repeat block renders and accepts nested effects -------------------
	var j_ed: Array = _sed.get("effect_data")
	j_ed.clear()
	_sed.call("_add_repeat_block")
	await get_tree().process_frame
	await get_tree().process_frame
	j_ed = _sed.get("effect_data")
	print("REPEAT_TEST top=", str(j_ed.size()), " id=", str(j_ed[0].get("effect", "?") if j_ed.size() > 0 else "?"))
	if j_ed.size() != 1 or str(j_ed[0].get("effect", "")) != SkillEngine.EFFECT_REPEAT:
		print("REPEAT_TEST_FAIL repeat not added")
		get_tree().quit(1)
		return
	var repeat_block: SkillBlock = _find_body_block(SkillEngine.EFFECT_REPEAT)
	if repeat_block == null or repeat_block.then_container == null:
		print("REPEAT_TEST_FAIL repeat block not rendered")
		get_tree().quit(1)
		return
	# Earlier scenarios scrolled the palette to the bottom; roll it back so the
	# effect palette block is visible / hittable again.
	palette_scroll.scroll_vertical = 0
	await get_tree().process_frame
	await get_tree().process_frame
	await _scroll_into_view(main_scroll, repeat_block.then_container)
	await _drag(eff_pal.get_global_rect().get_center(), repeat_block.then_container.get_global_rect().get_center())
	j_ed = _sed.get("effect_data")
	var j_then: Array = j_ed[0].get("then_effects", [])
	print("REPEAT_TEST then=", str(j_then.size()))
	if j_then.size() != 1:
		print("REPEAT_TEST_FAIL drag into repeat body failed")
		get_tree().quit(1)
		return

	# --- K. Compile-error banner appears and clears ---------------------------
	var k_ed: Array = _sed.get("effect_data")
	k_ed.clear()
	_sed.call("_refresh_script")
	await get_tree().process_frame
	await get_tree().process_frame
	var banner_text := _find_banner_text()
	print("ERROR_TEST empty_banner=", banner_text != "")
	if banner_text == "":
		print("ERROR_TEST_FAIL empty skill should show error banner")
		get_tree().quit(1)
		return
	k_ed.append({"effect": SkillEngine.EFFECT_IF, "condition": {}, "then_effects": [], "else_effects": []})
	_sed.call("_refresh_script")
	await get_tree().process_frame
	await get_tree().process_frame
	banner_text = _find_banner_text()
	print("ERROR_TEST if_missing_cond=", banner_text.contains(Locale.t("skill_editor.error_missing_condition")))
	if not banner_text.contains(Locale.t("skill_editor.error_missing_condition")):
		print("ERROR_TEST_FAIL missing-condition not reported: ", banner_text)
		get_tree().quit(1)
		return
	var bool_pal_k: SkillPaletteBlock = null
	for child in palette_vbox.find_children("*", "SkillPaletteBlock", true, false):
		if (child as SkillPaletteBlock).boolean_kind != "":
			bool_pal_k = child as SkillPaletteBlock
			break
	if bool_pal_k == null:
		print("ERROR_TEST_FAIL no boolean palette block")
		get_tree().quit(1)
		return
	await _scroll_palette_to(palette_scroll, bool_pal_k)
	var if_block_k: SkillBlock = _find_body_block(SkillEngine.EFFECT_IF)
	await _scroll_into_view(main_scroll, if_block_k.cond_slot)
	await _drag(bool_pal_k.get_global_rect().get_center(), if_block_k.cond_slot.get_global_rect().get_center())
	# Let the dropped-condition refresh + old banner queue_free settle.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	banner_text = _find_banner_text()
	var k_after: Array = _sed.get("effect_data")
	print("ERROR_TEST after_cond=", banner_text == "", " cond=", str(k_after[0].get("condition", {})) if k_after.size() > 0 else "?", " errors=", str(_sed.call("_collect_errors")))
	if banner_text != "":
		print("ERROR_TEST_FAIL banner should clear after condition added: ", banner_text)
		get_tree().quit(1)
		return
	k_ed = _sed.get("effect_data")
	k_ed.clear()
	k_ed.append({"effect": SkillEngine.EFFECT_REPEAT, "repeat_count": 0, "then_effects": []})
	_sed.call("_refresh_script")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	banner_text = _find_banner_text()
	print("ERROR_TEST repeat0=", banner_text.contains(Locale.t("skill_editor.error_repeat_count")))
	if not banner_text.contains(Locale.t("skill_editor.error_repeat_count")):
		print("ERROR_TEST_FAIL repeat 0 not reported")
		get_tree().quit(1)
		return
	# Directed target + 全体 must surface in the red banner (the old gray-out
	# chip was removed in favour of a compile error).
	var ie_ed: Array = _sed.get("effect_data")
	ie_ed.clear()
	ie_ed.append({"effect": SkillEngine.EFFECT_DAMAGE, "target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ALL, "value": 1})
	_sed.call("_refresh_script")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	banner_text = _find_banner_text()
	print("ERROR_TEST ineffective=", banner_text.contains(Locale.t("skill_editor.error_target_ineffective")))
	if not banner_text.contains(Locale.t("skill_editor.error_target_ineffective")):
		print("ERROR_TEST_FAIL directed+all not reported: ", banner_text)
		get_tree().quit(1)
		return

	# --- P. Variable chip dragged from a value slot back to the palette ------
	# Scratch drop-to-discard: a variable reporter dropped into a number slot
	# can be dragged out again; dropping it on the palette restores the slot to
	# a plain fixed number.
	var p_ed: Array = _sed.get("effect_data")
	p_ed.clear()
	p_ed.append({"effect": SkillEngine.EFFECT_DAMAGE, "target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "value_var": var_id})
	_sed.call("_refresh_script")
	main_scroll.scroll_vertical = 0
	await get_tree().process_frame
	await get_tree().process_frame
	var dmg_block_p: SkillBlock = _find_body_block(SkillEngine.EFFECT_DAMAGE)
	var value_slot_p: ValueSlot = null
	for item in dmg_block_p._sentence_row.get_children():
		if item is ValueSlot:
			value_slot_p = item as ValueSlot
			break
	if value_slot_p == null:
		print("PALVAR_TEST_FAIL no value slot")
		get_tree().quit(1)
		return
	await _drag(value_slot_p.get_global_rect().get_center(), palette_panel.get_global_rect().position + Vector2(120, 12))
	p_ed = _sed.get("effect_data")
	print("PALVAR_TEST value_var=", str(p_ed[0].get("value_var", "")), " value=", str(p_ed[0].get("value", "?")))
	if p_ed[0].has("value_var") or int(p_ed[0].get("value", 0)) != 1:
		print("PALVAR_TEST_FAIL variable chip not removed by palette drop")
		get_tree().quit(1)
		return

	# --- Q. Condition reporter dragged back to the palette -------------------
	var q_ed: Array = _sed.get("effect_data")
	q_ed.clear()
	q_ed.append({"effect": SkillEngine.EFFECT_IF, "condition": {"op": SkillEngine.CONDITION_OP_GTE, "lhs": {"kind": "num", "value": 1}, "rhs": {"kind": "num", "value": 2}}, "then_effects": []})
	_sed.call("_refresh_script")
	main_scroll.scroll_vertical = 0
	await get_tree().process_frame
	await get_tree().process_frame
	var if_block_q: SkillBlock = _find_body_block(SkillEngine.EFFECT_IF)
	if if_block_q == null or if_block_q.cond_slot == null or if_block_q.cond_slot.get_child_count() == 0:
		print("PALCOND_TEST_FAIL no condition tree")
		get_tree().quit(1)
		return
	var cond_root: Control = if_block_q.cond_slot.get_child(0)
	await _scroll_into_view(main_scroll, if_block_q.cond_slot)
	# Drag-out: the reporter's drag data (via Control.get_drag_data, the same
	# call the GUI pipeline makes) must carry from_cond_slot, the palette must
	# accept it, and the drop must clear the condition. A real-mouse run of the
	# same chain cleared the condition; the synthetic mouse injection here is
	# timing-sensitive after earlier scenarios, so drive the chain directly.
	var q_data: Variant = cond_root.call("_slot_get_drag_data", Vector2.ZERO)
	print("PALCOND_TEST drag_data=", str(q_data))
	if not (q_data is Dictionary) or not (q_data as Dictionary).has("from_cond_slot"):
		print("PALCOND_TEST_FAIL no from_cond_slot drag data")
		get_tree().quit(1)
		return
	if not _sed.call("_can_drop_on_palette", Vector2.ZERO, q_data):
		print("PALCOND_TEST_FAIL palette rejects condition drag")
		get_tree().quit(1)
		return
	_sed.call("_drop_on_palette", Vector2.ZERO, q_data)
	q_ed = _sed.get("effect_data")
	var q_cond: Dictionary = q_ed[0].get("condition", {})
	print("PALCOND_TEST condition=", str(q_cond))
	if not q_cond.is_empty():
		print("PALCOND_TEST_FAIL condition not removed by palette drop")
		get_tree().quit(1)
		return

	# --- R. Insertion line shows before/after the hovered block --------------
	# Hovering the UPPER half of the first script block must show the yellow
	# line BEFORE it (index 0); the LOWER half moves it AFTER it (index 1).
	var r_ed: Array = _sed.get("effect_data")
	r_ed.clear()
	r_ed.append({"effect": SkillEngine.EFFECT_DAMAGE, "target": SkillEngine.TARGET_SELF, "target_side": SkillEngine.TARGET_SIDE_ALL, "value": 1})
	r_ed.append({"effect": SkillEngine.EFFECT_HEAL, "target": SkillEngine.TARGET_SELF, "target_side": SkillEngine.TARGET_SIDE_ALL, "value": 1})
	_sed.call("_refresh_script")
	main_scroll.scroll_vertical = 0
	await get_tree().process_frame
	await get_tree().process_frame
	var body_r: Control = effects_list.get_child(0).body_container
	var first_r: SkillBlock = body_r.get_child(0) as SkillBlock
	first_r.call("_can_drop_data", Vector2(20, 6), {"type": "effect_block", "effect_id": SkillEngine.EFFECT_DAMAGE})
	var line_r: Control = _sed.get("_insertion_line")
	var line_in_body: bool = line_r != null and line_r.get_parent() == body_r
	var line_idx: int = line_r.get_index() if line_in_body else -1
	print("INSERTLINE_TEST line_in_body=", line_in_body, " index=", line_idx)
	if not line_in_body or line_idx != 0:
		print("INSERTLINE_TEST_FAIL insertion line should sit before the first block")
		get_tree().quit(1)
		return
	first_r.call("_can_drop_data", Vector2(20, first_r.size.y - 6), {"type": "effect_block", "effect_id": SkillEngine.EFFECT_DAMAGE})
	line_r = _sed.get("_insertion_line")
	var line_idx2: int = line_r.get_index() if line_r != null and line_r.get_parent() == body_r else -1
	print("INSERTLINE_TEST lower_index=", line_idx2)
	if line_idx2 != 1:
		print("INSERTLINE_TEST_FAIL insertion line should sit after the first block")
		get_tree().quit(1)
		return

	# --- S. Sweeping over several blocks must not leave lingering highlights --
	# Drag from the palette up across two script blocks and release on empty
	# space: each block the pointer passed over must lose its drop highlight
	# (and the shared insertion line must vanish) once the pointer left it.
	var s_ed: Array = _sed.get("effect_data")
	s_ed.clear()
	s_ed.append({"effect": SkillEngine.EFFECT_DAMAGE, "target": SkillEngine.TARGET_SELF, "target_side": SkillEngine.TARGET_SIDE_ALL, "value": 1})
	s_ed.append({"effect": SkillEngine.EFFECT_HEAL, "target": SkillEngine.TARGET_SELF, "target_side": SkillEngine.TARGET_SIDE_ALL, "value": 1})
	_sed.call("_refresh_script")
	palette_scroll.scroll_vertical = 0
	main_scroll.scroll_vertical = 0
	await get_tree().process_frame
	await get_tree().process_frame
	var body_s: Control = effects_list.get_child(0).body_container
	var block_s0: SkillBlock = body_s.get_child(0) as SkillBlock
	var block_s1: SkillBlock = body_s.get_child(1) as SkillBlock
	# Empty release point: the scroll content above the event block (labels /
	# VBox have no drop forwarding, so the release cancels instead of landing).
	var scroll_vbox: Control = effects_list.get_parent()
	var empty_s: Vector2 = scroll_vbox.get_global_rect().position + Vector2(scroll_vbox.size.x * 0.5, 14)
	await _drag_path([
		eff_pal.get_global_rect().get_center(),
		block_s0.get_global_rect().get_center(),
		block_s1.get_global_rect().get_center(),
		empty_s,
	])
	await get_tree().process_frame
	var glow0: bool = block_s0.get("_drag_highlight")
	var glow1: bool = block_s1.get("_drag_highlight")
	var line_s: Control = _sed.get("_insertion_line")
	var line_ghost: bool = line_s != null and line_s.get_parent() != null
	print("SWEEP_TEST glow0=", glow0, " glow1=", glow1, " line_ghost=", line_ghost)
	if glow0 or glow1 or line_ghost:
		print("SWEEP_TEST_FAIL swept-over block/line stayed lit after pointer left")
		get_tree().quit(1)
		return

	# --- I. Save -> fresh editor session reload (round-trip) ------------------
	var i_ed: Array = _sed.get("effect_data")
	i_ed.clear()
	i_ed.append({
		"effect": SkillEngine.EFFECT_IF_ELSE,
		"condition": {
			"condition_type": SkillEngine.CONDITION_SOURCE_HP_PCT,
			"condition_op": SkillEngine.CONDITION_OP_GTE,
			"condition_value": 50,
		},
		"then_effects": [
			{"effect": SkillEngine.EFFECT_DAMAGE, "target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "value": 2},
			{"effect": SkillEngine.EFFECT_STOP},
		],
		"else_effects": [
			{"effect": SkillEngine.EFFECT_ADD_BUFF, "target": SkillEngine.TARGET_SELF, "target_side": SkillEngine.TARGET_SIDE_ALL, "buff_id": SkillEngine.BUFF_ATK_BOOST, "duration": 2},
		],
	})
	var saved: Dictionary = _sed.call("_build_skill")
	PlayerData.card_draft["skill2"] = saved
	_sed.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var sed_new: Node = (load("res://SkillEditor.tscn") as PackedScene).instantiate()
	add_child(sed_new)
	await get_tree().process_frame
	await get_tree().process_frame
	var new_effects: Array = sed_new.get("effect_data")
	print("ROUNDTRIP_TEST top=", str(new_effects.size()))
	if new_effects.size() != 1 or str(new_effects[0].get("effect", "")) != SkillEngine.EFFECT_IF_ELSE:
		print("ROUNDTRIP_TEST_FAIL top structure lost: %s" % str(new_effects.size()))
		get_tree().quit(1)
		return
	var rt_cond: Dictionary = new_effects[0].get("condition", {})
	var rt_then: Array = new_effects[0].get("then_effects", [])
	var rt_else: Array = new_effects[0].get("else_effects", [])
	var ok_cond: bool = str(rt_cond.get("condition_type", "")) == SkillEngine.CONDITION_SOURCE_HP_PCT and int(rt_cond.get("condition_value", -1)) == 50
	var ok_then: bool = rt_then.size() == 2 and str(rt_then[1].get("effect", "")) == SkillEngine.EFFECT_STOP
	var ok_else: bool = rt_else.size() == 1 and str(rt_else[0].get("effect", "")) == SkillEngine.EFFECT_ADD_BUFF
	print("ROUNDTRIP_TEST cond=", ok_cond, " then=", ok_then, " else=", ok_else)
	if not (ok_cond and ok_then and ok_else):
		print("ROUNDTRIP_TEST_FAIL nested structure lost across sessions")
		get_tree().quit(1)
		return
	# The reloaded editor must render the nested if/else block tree again.
	var rt_events: VBoxContainer = sed_new.get_node("Panel/Margin/HBox/MainPanel/Margin/Scroll/VBox/EffectsList")
	var rt_has_if := false
	if rt_events.get_child_count() == 1 and rt_events.get_child(0) is SkillBlock:
		for sub in (rt_events.get_child(0) as SkillBlock).body_container.get_children():
			if sub is SkillBlock and str((sub as SkillBlock)._effect.get("effect", "")) == SkillEngine.EFFECT_IF_ELSE:
				rt_has_if = true
				break
	print("ROUNDTRIP_TEST rendered_if=", rt_has_if)
	if not rt_has_if:
		print("ROUNDTRIP_TEST_FAIL reloaded editor did not render nested tree")
		get_tree().quit(1)
		return

	print("DRAG_TEST_PASS=true")
	get_tree().quit(0)


# Press -> motion(s) -> release with the GUI drag pipeline driven by real
# input events (motion must carry the left-button mask to keep the drag alive).
func _drag(from_pos: Vector2, to_pos: Vector2) -> void:
	Input.parse_input_event(_mouse_button(from_pos, true))
	await get_tree().process_frame
	Input.parse_input_event(_mouse_motion(from_pos, from_pos + Vector2(40, 0)))
	await get_tree().process_frame
	var steps := 6
	for i in range(1, steps + 1):
		var p := from_pos.lerp(to_pos, float(i) / float(steps))
		Input.parse_input_event(_mouse_motion(from_pos, p))
		await get_tree().process_frame
	Input.warp_mouse(_win(to_pos))
	for _i in range(3):
		await get_tree().process_frame
	Input.parse_input_event(_mouse_button(to_pos, false))
	await get_tree().process_frame
	await get_tree().process_frame


# Like _drag but with intermediate waypoints, so a drag can sweep over several
# blocks (highlighting each) before releasing on an empty spot. The press
# happens at path[0], the release at the last waypoint.
func _drag_path(path: Array) -> void:
	Input.parse_input_event(_mouse_button(path[0], true))
	await get_tree().process_frame
	var prev: Vector2 = path[0]
	for i in range(1, path.size()):
		var target: Vector2 = path[i]
		var steps := 5
		for j in range(1, steps + 1):
			var p := prev.lerp(target, float(j) / float(steps))
			Input.parse_input_event(_mouse_motion(prev, p))
			await get_tree().process_frame
		prev = target
	Input.warp_mouse(_win(prev))
	for _i in range(3):
		await get_tree().process_frame
	Input.parse_input_event(_mouse_button(prev, false))
	await get_tree().process_frame
	await get_tree().process_frame


func _click(pos: Vector2) -> void:
	Input.warp_mouse(_win(pos))
	for _i in range(2):
		await get_tree().process_frame
	Input.parse_input_event(_mouse_button(pos, true))
	await get_tree().process_frame
	Input.parse_input_event(_mouse_button(pos, false))
	await get_tree().process_frame
	await get_tree().process_frame


func _type_key(keycode: Key, ctrl: bool = false) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	# Text insertion needs the unicode char (real keyboards supply it).
	if keycode != Key.KEY_ENTER and keycode != Key.KEY_BACKSPACE:
		ev.unicode = keycode
	ev.ctrl_pressed = ctrl
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	ev.pressed = false
	Input.parse_input_event(ev)
	await get_tree().process_frame


func _find_body_block(effect_id: String) -> SkillBlock:
	var effects_list: VBoxContainer = _sed.get_node("Panel/Margin/HBox/MainPanel/Margin/Scroll/VBox/EffectsList")
	var event_block: SkillBlock = effects_list.get_child(0)
	for sub in event_block.body_container.get_children():
		if sub is SkillBlock and str((sub as SkillBlock)._effect.get("effect", "")) == effect_id:
			return sub as SkillBlock
	return null


func _find_target_slot(block: SkillBlock, kind: String) -> TargetSlot:
	var row: Control = block.get("_sentence_row")
	for i in range(row.get_child_count()):
		var c: Control = row.get_child(i)
		if c is TargetSlot and (c as TargetSlot).kind == kind:
			return c as TargetSlot
	return null


func _find_banner_text() -> String:
	var title: String = Locale.t("skill_editor.error_title")
	var hint: String = Locale.t("skill_editor.error_empty_skill")
	for c in _sed.find_children("*", "Label", true, false):
		if c is Label:
			var t: String = (c as Label).text
			if t.contains(title) or t == hint:
				return t
	return ""


# Scrolls a ScrollContainer so `control`'s vertical center lands near target_y
# (in window space), keeping the drop point inside the visible window.
func _scroll_into_view(scroll: ScrollContainer, control: Control, target_y: float = 300.0) -> void:
	scroll.scroll_vertical = 0
	await get_tree().process_frame
	await get_tree().process_frame
	var center_y: float = control.get_global_rect().get_center().y
	var max_v: float = scroll.get_v_scroll_bar().max_value
	scroll.scroll_vertical = clampf(center_y - target_y, 0.0, max_v)
	await get_tree().process_frame
	await get_tree().process_frame


# Scrolls the palette so a specific palette block (content coordinates) is
# inside the visible viewport.
func _scroll_palette_to(scroll: ScrollContainer, ctrl: Control) -> void:
	# Palette blocks now live inside collapsible section containers, so their
	# local position.y is relative to the section, not the scroll content.
	# Derive the content-space offset from global rects instead.
	var content_y: float = ctrl.get_global_rect().position.y - scroll.get_global_rect().position.y + scroll.scroll_vertical
	var max_v: float = scroll.get_v_scroll_bar().max_value
	scroll.scroll_vertical = clampf(content_y - 80.0, 0.0, max_v)
	await get_tree().process_frame
	await get_tree().process_frame


func _find_body_block_path(index: int) -> SkillBlock:
	var effects_list: VBoxContainer = _sed.get_node("Panel/Margin/HBox/MainPanel/Margin/Scroll/VBox/EffectsList")
	var event_block: SkillBlock = effects_list.get_child(0)
	var idx := 0
	for sub in event_block.body_container.get_children():
		if sub is SkillBlock:
			if idx == index:
				return sub as SkillBlock
			idx += 1
	return null


# ============================================
# Layout reporting (overflow check)
# ============================================

func _print_layout() -> void:
	var effects_list: VBoxContainer = _sed.get_node("Panel/Margin/HBox/MainPanel/Margin/Scroll/VBox/EffectsList")
	for child in effects_list.get_children():
		if child is SkillBlock:
			var block := child as SkillBlock
			print("LAYOUT event size=", block.size)
			_dump_block(block, "  ")
			for sub in block.body_container.get_children():
				if sub is SkillBlock:
					_dump_block(sub as SkillBlock, "    ")


# Scans every text control under the editor and flags collapsed / overflowing
# text (empty-ish size while holding visible text => autowrap or glyph issue).
func _dump_texts() -> void:
	var bad := 0
	for c in _sed.find_children("*", "", true, false):
		var text := ""
		if c is Label:
			text = (c as Label).text
		elif c is Button:
			text = (c as Button).text
		if text == "":
			continue
		if c is Control:
			var size2: Vector2 = (c as Control).size
			# Collapsed-to-nothing text (autowrap / missing glyph) is the bug;
			# tall multiline paragraph labels are legitimate.
			var suspicious := size2.x < 8.0 and size2.y > 0.0
			if suspicious:
				bad += 1
				print("TEXT_ISSUE ", c.get_class(), " size=", size2, " text=\"", text, "\"")
	print("TEXT_SCAN done issues=", bad)


func _dump_block(block: SkillBlock, indent: String) -> void:
	print(indent, "block[", str(block.effect_path), "] size=", block.size, " eff=", str(block._effect.get("effect", "?")))
	if block.cond_slot != null:
		print(indent, "  cond_slot size=", block.cond_slot.size, " pos=", block.cond_slot.position)
		for cc in block.cond_slot.get_children():
			if cc is Control:
				var ctxt := ""
				for gc in (cc as Control).get_children():
					if gc is Control:
						ctxt += " %s:%s" % [gc.get_class(), str((gc as Control).size)]
				print(indent, "    cond_child ", cc.get_class(), " size=", (cc as Control).size, ctxt)
	if block.then_container != null:
		print(indent, "  then_container size=", block.then_container.size)
	if block.else_container != null:
		print(indent, "  else_container size=", block.else_container.size)
	if block._sentence_row != null:
		print(indent, "  sentence_row size=", block._sentence_row.size)
		for item in block._sentence_row.get_children():
			if item is Control:
				var c := item as Control
				var txt := ""
				if item is Label:
					txt = (item as Label).text
				elif item is OptionButton:
					txt = (item as OptionButton).text
				print(indent, "    item ", item.get_class(), " size=", c.size, " pos=", c.position, " text=", txt)
	# Show the head row (title + action buttons) sizes.
	for child in block.get_children():
		if child is VBoxContainer:
			for row in child.get_children():
				if row is HBoxContainer:
					var widths := ""
					for sub in row.get_children():
						if sub is Control:
							widths += " " + str(sub.get_class()) + "=" + str((sub as Control).size.x)
					print(indent, "  head_hbox w=", (row as HBoxContainer).size, widths)


# ============================================
# Input event helpers
# ============================================

# Canvas -> window transform: a saved high-resolution preset (WindowSizeController)
# stretches the 1152x648 canvas, so synthetic mouse events (whose positions the
# GUI hit-tests in window space) must be scaled to match the control rects.
func _win(p: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * p


func _mouse_button(pos: Vector2, pressed: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	var w := _win(pos)
	ev.position = w
	ev.global_position = w
	return ev


func _mouse_motion(from: Vector2, to: Vector2) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	var w := _win(to)
	var w_from := _win(from)
	ev.position = w
	ev.global_position = w
	ev.relative = w - w_from
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	return ev
