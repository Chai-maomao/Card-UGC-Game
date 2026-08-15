extends Node

const _TextFormatter = preload("res://SkillTextFormatter.gd")


func _ready() -> void:
	Locale.language = "zh"
	PlayerData.card_draft = {
		"name": "测试卡",
		"cost": 2,
		"hp": 4,
		"atk": 2,
		"gender": "male",
		"card_type": "minion",
		"art_path": "",
		"skill1": {},
		"skill2": {
			"skill_name": "第二技能",
			"trigger": SkillEngine.TRIGGER_ON_ACTIVATE,
			"probability": 100,
			"effects": [{
				"target": SkillEngine.TARGET_SINGLE,
				"target_side": SkillEngine.TARGET_SIDE_ENEMY,
				"effect": SkillEngine.EFFECT_DAMAGE,
				"value": 2,
			}],
		},
	}
	var scene: PackedScene = load("res://CardEditor.tscn")
	var editor: Node = scene.instantiate()
	add_child(editor)
	await get_tree().process_frame
	var summary: Label = editor.get_node("Panel/MarginContainer/ScrollContainer/VBoxContainer/Skill2Summary")
	if summary.text == Locale.t("editor.empty") or not summary.text.contains("第二技能") or not summary.text.contains("2"):
		push_error("Skill2 summary did not render saved second skill: %s" % summary.text)
		get_tree().quit(1)
		return

	# --- SkillEditor renders a nested if/else + stop block tree without errors ---
	PlayerData.card_draft["skill2"]["effects"] = [
		{
			"target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ENEMY,
			"effect": SkillEngine.EFFECT_DAMAGE, "value": 2,
		},
		{
			"effect": SkillEngine.EFFECT_IF_ELSE,
			"condition_type": SkillEngine.CONDITION_SOURCE_HP_PCT,
			"condition_op": SkillEngine.CONDITION_OP_GTE,
			"condition_value": 50,
			"then_effects": [
				{
					"target": SkillEngine.TARGET_SELF, "target_side": SkillEngine.TARGET_SIDE_ALL,
					"effect": SkillEngine.EFFECT_GAIN_ATTACK, "value": 2,
				},
				{"effect": SkillEngine.EFFECT_STOP},
			],
			"else_effects": [
				{
					"target": SkillEngine.TARGET_SELF, "target_side": SkillEngine.TARGET_SIDE_ALL,
					"effect": SkillEngine.EFFECT_ADD_BUFF, "value": 1,
					"buff_id": SkillEngine.BUFF_ATK_BOOST, "duration": 2,
				},
			],
		},
	]
	PlayerData.editing_skill_index = 1
	var sed_scene: PackedScene = load("res://SkillEditor.tscn")
	var sed: Node = sed_scene.instantiate()
	add_child(sed)
	await get_tree().process_frame
	await get_tree().process_frame
	var effects_list: VBoxContainer = sed.get_node("Panel/Margin/HBox/MainPanel/Margin/Scroll/VBox/EffectsList")
	if effects_list.get_child_count() != 1:
		push_error("SkillEditor did not wrap effects in one event block (children=%d)" % effects_list.get_child_count())
		get_tree().quit(1)
		return
	var event_block: SkillBlock = effects_list.get_child(0)
	var body: VBoxContainer = event_block.body_container
	var body_blocks := 0
	var if_block: SkillBlock = null
	for child in body.get_children():
		if child is SkillBlock:
			body_blocks += 1
			if str((child as SkillBlock)._effect.get("effect", "")) == SkillEngine.EFFECT_IF_ELSE:
				if_block = child
	if body_blocks != 2 or if_block == null:
		push_error("SkillEditor body blocks wrong (count=%d, if_else=%s)" % [body_blocks, if_block != null])
		get_tree().quit(1)
		return
	var then_blocks := 0
	var has_stop := false
	for child in if_block.then_container.get_children():
		if child is SkillBlock:
			then_blocks += 1
			if str((child as SkillBlock)._effect.get("effect", "")) == SkillEngine.EFFECT_STOP:
				has_stop = true
	if then_blocks != 2 or not has_stop:
		push_error("SkillEditor then-slot blocks wrong (count=%d, stop=%s)" % [then_blocks, has_stop])
		get_tree().quit(1)
		return

	# --- Layout integrity: render every effect (longest sentence templates) in
	#     one skill tree and assert no block / sentence row overflows its slot ---
	var stress_effects: Array = []
	for effect_id: String in SkillRegistry.EFFECT_IDS:
		var eff := {
			"target": SkillEngine.TARGET_SINGLE,
			"target_side": SkillEngine.TARGET_SIDE_ENEMY,
			"effect": effect_id,
			"value": 3,
			"buff_id": SkillEngine.BUFF_ATK_BOOST,
			"duration": 2,
			"random_count": 2,
			"probability": 80,
		}
		if SkillRegistry.force_self(effect_id):
			eff["target"] = SkillEngine.TARGET_SELF
			eff["target_side"] = SkillEngine.TARGET_SIDE_ALL
		stress_effects.append(eff)
	stress_effects.append({
		"effect": SkillEngine.EFFECT_IF_ELSE,
		"condition_type": SkillEngine.CONDITION_SOURCE_HP_PCT,
		"condition_op": SkillEngine.CONDITION_OP_GTE,
		"condition_value": 50,
		"then_effects": [
			{
				"target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ENEMY,
				"effect": SkillEngine.EFFECT_DAMAGE, "value": 2,
			},
			{"effect": SkillEngine.EFFECT_STOP},
		],
		"else_effects": [],
	})
	PlayerData.card_draft["skill2"]["effects"] = stress_effects
	sed.queue_free()
	await get_tree().process_frame
	var sed2: Node = sed_scene.instantiate()
	add_child(sed2)
	await get_tree().process_frame
	await get_tree().process_frame
	var issues: Array = _collect_layout_issues(sed2)
	if not issues.is_empty():
		push_error("Layout overflow: %s" % " | ".join(issues))
		get_tree().quit(1)
		return

	# --- Drag/move logic: insert, nest into slots, cycle protection ---
	var ed: Array = sed2.get("effect_data")
	ed.clear()
	for label: String in ["e_a", "e_b", "e_c"]:
		ed.append({"effect": label, "target": SkillEngine.TARGET_SELF, "target_side": SkillEngine.TARGET_SIDE_ALL})
	sed2.call("_refresh_script")
	await get_tree().process_frame
	# Move top-level [0] to index 2 (insert before the block now at index 2):
	# [e_a, e_b, e_c] -> [e_b, e_a, e_c]
	sed2.call("_move_effect", [0], [], 2)
	var moved: Array = sed2.get("effect_data")
	if _eff_ids(moved) != "e_b,e_a,e_c":
		push_error("top-level move before failed: %s" % _eff_ids(moved))
		get_tree().quit(1)
		return
	# Move [0] (e_b) to the end (index 3 of the original list): [e_a, e_c, e_b]
	sed2.call("_move_effect", [0], [], 3)
	var moved_end: Array = sed2.get("effect_data")
	if _eff_ids(moved_end) != "e_a,e_c,e_b":
		push_error("top-level move to end failed: %s" % _eff_ids(moved_end))
		get_tree().quit(1)
		return
	# Nest a top-level block into an if/else then-slot: [if, e_x] -> if.then=[e_x]
	moved.clear()
	moved.append({"effect": SkillEngine.EFFECT_IF_ELSE, "condition_type": SkillEngine.CONDITION_NONE, "then_effects": [], "else_effects": []})
	moved.append({"effect": "e_x", "target": SkillEngine.TARGET_SELF, "target_side": SkillEngine.TARGET_SIDE_ALL})
	sed2.call("_refresh_script")
	await get_tree().process_frame
	sed2.call("_move_effect", [1], [0, "then"], 0)
	var nested: Array = sed2.get("effect_data")
	var then_list: Array = nested[0].get("then_effects", [])
	if nested.size() != 1 or then_list.size() != 1 or str(then_list[0].get("effect", "")) != "e_x":
		push_error("nest into then slot failed: top=%d then=%s" % [nested.size(), _eff_ids(then_list)])
		get_tree().quit(1)
		return
	# Cycle protection: moving the if/else block into its own then slot is rejected.
	sed2.call("_move_effect", [0], [0, "then"], 0)
	var after_cycle: Array = sed2.get("effect_data")
	if after_cycle.size() != 1:
		push_error("cycle protection failed: top=%d" % after_cycle.size())
		get_tree().quit(1)
		return
	# Move out of a slot back to top level: if.then=[e_x] -> top=[e_x, if]
	sed2.call("_move_effect", [0, "then", 0], [], 0)
	var out: Array = sed2.get("effect_data")
	if out.size() != 2 or str(out[0].get("effect", "")) != "e_x" or str(out[1].get("effect", "")) != SkillEngine.EFFECT_IF_ELSE:
		push_error("move out of slot failed: %s" % _eff_ids(out))
		get_tree().quit(1)
		return

	# --- Save path: _build_skill mirrors the nested effect tree ---
	var built: Dictionary = sed2.call("_build_skill")
	var built_fx: Array = built.get("effects", [])
	if built_fx.size() != 2 or str(built_fx[1].get("effect", "")) != SkillEngine.EFFECT_IF_ELSE:
		push_error("build skill lost top-level effects: %s" % _eff_ids(built_fx))
		get_tree().quit(1)
		return
	# Nest e_x into the if/else then-slot again and rebuild.
	sed2.call("_move_effect", [0], [1, "then"], 0)
	var built2: Dictionary = sed2.call("_build_skill")
	var fx2: Array = built2.get("effects", [])
	var then2: Array = fx2[0].get("then_effects", [])
	if fx2.size() != 1 or then2.size() != 1 or str(then2[0].get("effect", "")) != "e_x":
		push_error("build skill lost nested effects: top=%d then=%s" % [fx2.size(), _eff_ids(then2)])
		get_tree().quit(1)
		return

	# --- Nested block dragging: reorder inside a slot, then drag out ---
	var nest_ed: Array = sed2.get("effect_data")
	var nest_then: Array = nest_ed[0].get("then_effects", [])
	nest_then.append({"effect": "e_y", "target": SkillEngine.TARGET_SELF, "target_side": SkillEngine.TARGET_SIDE_ALL})
	sed2.call("_refresh_script")
	await get_tree().process_frame
	# Move then[0] (e_x) to after then[1] (e_y): [e_x, e_y] -> [e_y, e_x]
	sed2.call("_move_effect", [0, "then", 0], [0, "then"], 2)
	var reordered: Array = sed2.get("effect_data")
	var re_then: Array = reordered[0].get("then_effects", [])
	if _eff_ids(re_then) != "e_y,e_x":
		push_error("slot reorder failed: %s" % _eff_ids(re_then))
		get_tree().quit(1)
		return
	# Drag a nested block out to the top level: then=[e_y,e_x] -> top=[e_y, if]
	sed2.call("_move_effect", [0, "then", 0], [], 0)
	var out2: Array = sed2.get("effect_data")
	if out2.size() != 2 or str(out2[0].get("effect", "")) != "e_y" or str(out2[1].get("effect", "")) != SkillEngine.EFFECT_IF_ELSE:
		push_error("nested drag out failed: %s" % _eff_ids(out2))
		get_tree().quit(1)
		return

	# --- Palette drag of control blocks (if/else, stop) into a slot ---
	var p_ed: Array = sed2.get("effect_data")
	p_ed.clear()
	p_ed.append({"effect": "e_z", "target": SkillEngine.TARGET_SELF, "target_side": SkillEngine.TARGET_SIDE_ALL})
	sed2.call("_refresh_script")
	await get_tree().process_frame
	sed2.call("_apply_drop", {"type": "effect_block", "effect_id": SkillEngine.EFFECT_IF_ELSE}, [], 1)
	var p_after: Array = sed2.get("effect_data")
	if p_after.size() != 2 or str(p_after[1].get("effect", "")) != SkillEngine.EFFECT_IF_ELSE:
		push_error("palette if/else drag failed: %s" % _eff_ids(p_after))
		get_tree().quit(1)
		return
	sed2.call("_apply_drop", {"type": "effect_block", "effect_id": SkillEngine.EFFECT_STOP}, [1, "then"], 0)
	var p_then: Array = p_after[1].get("then_effects", [])
	if p_then.size() != 1 or str(p_then[0].get("effect", "")) != SkillEngine.EFFECT_STOP:
		push_error("palette stop drag failed: %s" % _eff_ids(p_then))
		get_tree().quit(1)
		return

	# --- Palette drag-to-install: grab a palette block, drop it into the script ---
	var palette_vbox: VBoxContainer = sed2.get_node("Panel/Margin/HBox/PalettePanel/Margin/VBox/PaletteScroll/PaletteVBox")
	# Palette sections are collapsible; search inside every section container.
	var palette_block: SkillPaletteBlock = null
	for child in palette_vbox.find_children("*", "SkillPaletteBlock", true, false):
		if (child as SkillPaletteBlock).effect_id != "":
			palette_block = child as SkillPaletteBlock
			break
	if palette_block == null or palette_block.effect_id == "":
		push_error("no draggable palette block found")
		get_tree().quit(1)
		return
	var drag_data = palette_block._get_drag_data(Vector2.ZERO)
	if not (drag_data is Dictionary) or drag_data.get("type", "") != "effect_block" or str(drag_data.get("effect_id", "")) == "":
		push_error("palette drag data invalid: %s" % str(drag_data))
		get_tree().quit(1)
		return
	var d_ed: Array = sed2.get("effect_data")
	d_ed.clear()
	sed2.call("_refresh_script")
	await get_tree().process_frame
	var events_list: VBoxContainer = sed2.get_node("Panel/Margin/HBox/MainPanel/Margin/Scroll/VBox/EffectsList")
	var event_block2: SkillBlock = events_list.get_child(0)
	if not (sed2.call("_can_drop_on_slot", event_block2.body_container, Vector2.ZERO, drag_data) as bool):
		push_error("slot rejects palette drop")
		get_tree().quit(1)
		return
	sed2.call("_drop_on_slot", event_block2.body_container, Vector2(5.0, 5.0), drag_data)
	var d_after: Array = sed2.get("effect_data")
	if d_after.size() != 1 or str(d_after[0].get("effect", "")) != palette_block.effect_id:
		push_error("palette drag install failed: %s" % _eff_ids(d_after))
		get_tree().quit(1)
		return
	# NOTE: real mouse-event drag simulation is verified windowed (SkillPreview.tscn);
	# headless mode does not drive the GUI drag pipeline (set_drag_preview fails).

	# --- Boolean block drop: palette comparison block into an if gap ---
	var bool_block: SkillPaletteBlock = null
	for child in palette_vbox.find_children("*", "SkillPaletteBlock", true, false):
		if (child as SkillPaletteBlock).boolean_kind != "":
			bool_block = child as SkillPaletteBlock
			break
	if bool_block == null:
		push_error("no draggable boolean palette block found")
		get_tree().quit(1)
		return
	var bool_data = bool_block._get_drag_data(Vector2.ZERO)
	if not (bool_data is Dictionary) or bool_data.get("type", "") != "boolean_block":
		push_error("boolean drag data invalid: %s" % str(bool_data))
		get_tree().quit(1)
		return
	# Build an if block, then drop the boolean comparison into its gap.
	var c_ed: Array = sed2.get("effect_data")
	c_ed.clear()
	c_ed.append({"effect": SkillEngine.EFFECT_IF, "condition": {}, "then_effects": [], "else_effects": []})
	sed2.call("_refresh_script")
	await get_tree().process_frame
	var events_list_c: VBoxContainer = sed2.get_node("Panel/Margin/HBox/MainPanel/Margin/Scroll/VBox/EffectsList")
	var event_block_c: SkillBlock = events_list_c.get_child(0)
	var cond_if_block: SkillBlock = null
	for sub in event_block_c.body_container.get_children():
		if sub is SkillBlock and str((sub as SkillBlock)._effect.get("effect", "")) == SkillEngine.EFFECT_IF:
			cond_if_block = sub as SkillBlock
			break
	if cond_if_block == null or cond_if_block.cond_slot == null:
		push_error("if block condition slot not rendered")
		get_tree().quit(1)
		return
	if not (cond_if_block._can_drop_condition(Vector2.ZERO, bool_data) as bool):
		push_error("condition slot rejects boolean drop")
		get_tree().quit(1)
		return
	cond_if_block._drop_condition(Vector2.ZERO, bool_data)
	await get_tree().process_frame
	var c_after: Array = sed2.get("effect_data")
	var c_cond: Dictionary = c_after[0].get("condition", {})
	if not c_cond.has("lhs") or str(c_cond.get("op", "")) == "":
		push_error("boolean drop did not set if condition: %s" % str(c_cond))
		get_tree().quit(1)
		return

	# --- Drop-to-discard: dragging a script block back onto the palette deletes it ---
	var del_ed: Array = sed2.get("effect_data")
	del_ed.clear()
	del_ed.append({"effect": "e_del", "target": SkillEngine.TARGET_SELF, "target_side": SkillEngine.TARGET_SIDE_ALL})
	sed2.call("_refresh_script")
	await get_tree().process_frame
	sed2.call("_drop_on_palette", Vector2.ZERO, {"type": "effect_block", "from_path": [0], "effect": {}})
	await get_tree().process_frame
	var del_after: Array = sed2.get("effect_data")
	if del_after.size() != 0:
		push_error("drop-to-discard failed: %s" % _eff_ids(del_after))
		get_tree().quit(1)
		return

	# --- Block-level drop: palette block inserted before an existing block ---
	var ins_ed: Array = sed2.get("effect_data")
	ins_ed.clear()
	ins_ed.append({"effect": "e_a", "target": SkillEngine.TARGET_SELF, "target_side": SkillEngine.TARGET_SIDE_ALL})
	ins_ed.append({"effect": "e_b", "target": SkillEngine.TARGET_SELF, "target_side": SkillEngine.TARGET_SIDE_ALL})
	sed2.call("_refresh_script")
	await get_tree().process_frame
	sed2.call("_on_block_drop_path", [], [0], false, {"type": "effect_block", "effect_id": "e_new"})
	var ins_after: Array = sed2.get("effect_data")
	if _eff_ids(ins_after) != "e_new,e_a,e_b":
		push_error("block-level insert failed: %s" % _eff_ids(ins_after))
		get_tree().quit(1)
		return

	# --- Spell mode: effects render directly without an event block ---
	PlayerData.card_draft["card_type"] = "spell"
	var sed3: Node = sed_scene.instantiate()
	add_child(sed3)
	await get_tree().process_frame
	await get_tree().process_frame
	var spell_list: VBoxContainer = sed3.get_node("Panel/Margin/HBox/MainPanel/Margin/Scroll/VBox/EffectsList")
	var spell_has_event_block := false
	var spell_block_count := 0
	for child in spell_list.get_children():
		if child is SkillBlock:
			spell_block_count += 1
			if (child as SkillBlock).is_hat:
				spell_has_event_block = true
	if spell_has_event_block or spell_block_count == 0:
		push_error("spell mode should render bare blocks (hat=%s blocks=%d)" % [spell_has_event_block, spell_block_count])
		get_tree().quit(1)
		return

	# --- Compile-error detection: empty skill / missing condition / repeat 0 ---
	var err_ed: Array = sed3.get("effect_data")
	err_ed.clear()
	sed3.call("_refresh_script")
	await get_tree().process_frame
	var errs0: Array = sed3.call("_collect_errors")
	if errs0.is_empty():
		push_error("empty skill should report compile errors")
		get_tree().quit(1)
		return
	err_ed.append({"effect": SkillEngine.EFFECT_IF, "condition": {}, "then_effects": [], "else_effects": []})
	sed3.call("_refresh_script")
	await get_tree().process_frame
	var errs1: Array = sed3.call("_collect_errors")
	var missing_cond_reported := false
	for e in errs1:
		if str(e).contains(Locale.t("skill_editor.error_missing_condition")):
			missing_cond_reported = true
	if not missing_cond_reported:
		push_error("missing condition not reported: %s" % str(errs1))
		get_tree().quit(1)
		return
	err_ed[0]["condition"] = {
		"condition_type": SkillEngine.CONDITION_SOURCE_HP_PCT,
		"condition_op": SkillEngine.CONDITION_OP_GTE,
		"condition_value": 50,
	}
	err_ed.append({"effect": SkillEngine.EFFECT_REPEAT, "repeat_count": 0, "then_effects": []})
	sed3.call("_refresh_script")
	await get_tree().process_frame
	var errs2: Array = sed3.call("_collect_errors")
	var cond_err_gone := true
	var repeat_err_reported := false
	for e in errs2:
		if str(e).contains(Locale.t("skill_editor.error_missing_condition")):
			cond_err_gone = false
		if str(e).contains(Locale.t("skill_editor.error_repeat_count")):
			repeat_err_reported = true
	if not cond_err_gone or not repeat_err_reported:
		push_error("error detection wrong: %s" % str(errs2))
		get_tree().quit(1)
		return
	# A variable-driven repeat (repeat_var) must NOT report a missing count.
	err_ed.clear()
	err_ed.append({"effect": SkillEngine.EFFECT_REPEAT, "repeat_var": SkillEngine.VAR_HAND_COUNT, "then_effects": []})
	sed3.call("_refresh_script")
	await get_tree().process_frame
	var errs3: Array = sed3.call("_collect_errors")
	var repeat_var_false_positive := false
	for e in errs3:
		if str(e).contains(Locale.t("skill_editor.error_repeat_count")):
			repeat_var_false_positive = true
	if repeat_var_false_positive:
		push_error("repeat_var wrongly reported as missing count: %s" % str(errs3))
		get_tree().quit(1)
		return

	print("TEST_CARD_EDITOR_SKILL_SUMMARY_OK")
	OS.delay_msec(300)
	get_tree().quit(0)


# Joins effect ids for readable failure messages.
func _eff_ids(list: Array) -> String:
	var ids := ""
	for eff in list:
		if ids != "":
			ids += ","
		ids += str(eff.get("effect", "?"))
	return ids


# Walks every rendered block and reports any that exceed their slot width.
func _collect_layout_issues(sed: Node) -> Array:
	var issues: Array = []
	var blocks: Array = sed.find_children("*", "SkillBlock", true, false)
	var sized := 0
	for child in blocks:
		if (child as Control).size.x > 0.0:
			sized += 1
	if blocks.is_empty() or sized == 0:
		issues.append("layout not computed (blocks=%d sized=%d)" % [blocks.size(), sized])
		return issues
	for child in blocks:
		var block := child as SkillBlock
		var parent := block.get_parent()
		if parent is Control and block.size.x > parent.size.x + 1.0:
			issues.append("block[%s] %s w=%.0f > parent[%s] w=%.0f" % [str(block.effect_path), block.name, block.size.x, parent.name, parent.size.x])
		if block._sentence_row != null and block._sentence_row.get_parent() != null:
			# The sentence row is wrapped in a fixed-width clipping Control
			# (_wrap_row): deeply nested reporters may be wider than the block,
			# but the wrapper must stay inside the block so nothing spills into
			# the palette column.
			var wrap: Control = block._sentence_row.get_parent() as Control
			if wrap.size.x > block.size.x + 1.0:
				issues.append("sentence[%s] wrap w=%.0f > block w=%.0f" % [str(block.effect_path), wrap.size.x, block.size.x])
	return issues
