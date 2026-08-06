extends Node

# Diagnostic: render effects with long inline content (long variable chips,
# wide target slots, verbose sentences) and report any control whose rect
# overflows its effect block, so we can see what "drag in a long block breaks
# the UI" means concretely.

var _sed: Node


func _ready() -> void:
	Locale.language = "zh"
	PlayerData.card_draft = {
		"name": "诊断", "cost": 2, "hp": 4, "atk": 2, "gender": "male",
		"card_type": "minion", "art_path": "",
		"skill1": {}, "skill2": {}, "skill3": {},
	}
	PlayerData.editing_skill_index = 1
	var scene: PackedScene = load("res://SkillEditor.tscn")
	_sed = scene.instantiate()
	add_child(_sed)
	await get_tree().process_frame
	await get_tree().process_frame

	var cases: Array = [
		[SkillEngine.EFFECT_DAMAGE, {"value_var": SkillEngine.VAR_ENEMY_HAND_COUNT, "value_offset": -1}],
		[SkillEngine.EFFECT_DAMAGE, {"target": SkillEngine.TARGET_SELF_SIDES, "target_side": SkillEngine.TARGET_SIDE_ALLY, "value_expr": {"kind": "expr", "op": "+", "a": {"kind": "num", "value": 1}, "b": {"kind": "num", "value": 1}}}],
		[SkillEngine.EFFECT_VIEW_DISCARD, {"value": 3, "random_count": 5}],
		[SkillEngine.EFFECT_DRAW_CARDS, {"value": 0, "value_var": SkillEngine.VAR_DECK_COUNT, "random_count": 2}],
		[SkillEngine.EFFECT_ADD_BUFF, {"target": SkillEngine.TARGET_SELF, "buff_id": SkillEngine.BUFF_DAMAGE_REDUCTION, "duration": 5, "value": 3}],
		[SkillEngine.EFFECT_DAMAGE, {"target": SkillEngine.TARGET_SIDES, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "value": 999}],
		# Extreme: long var chip + offset + target "自身相邻" all at once.
		[SkillEngine.EFFECT_DAMAGE, {"target": SkillEngine.TARGET_SELF_SIDES, "target_side": SkillEngine.TARGET_SIDE_ALLY, "value_var": SkillEngine.VAR_ENEMY_HAND_COUNT, "value_offset": -1, "random_count": 3}],
	]
	var idx := 0
	for c in cases:
		idx += 1
		var eff: Dictionary = {"target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "effect": c[0], "value": 1, "probability": 100}
		for k in c[1]:
			eff[k] = c[1][k]
		var ed: Array = _sed.get("effect_data")
		ed.clear()
		ed.append(eff)
		_sed.call("_refresh_script")
		await get_tree().process_frame
		await get_tree().process_frame
		_check("case%d" % idx, eff.get("effect", "?"))

	# Nested inside an if block: inner width shrinks by the slot indent.
	var ed2: Array = _sed.get("effect_data")
	ed2.clear()
	var deep_eff: Dictionary = {"target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "effect": SkillEngine.EFFECT_DAMAGE, "value_var": SkillEngine.VAR_ENEMY_HAND_COUNT, "value_offset": -1, "random_count": 3, "probability": 100}
	var inner_list: Array = [deep_eff]
	for depth in range(3):
		inner_list = [{
			"effect": SkillEngine.EFFECT_IF,
			"condition": {"op": SkillEngine.CONDITION_OP_GTE, "lhs": {"kind": "num", "value": 1}, "rhs": {"kind": "num", "value": 1}},
			"then_effects": inner_list,
		}]
	ed2.append(inner_list[0])
	_sed.call("_refresh_script")
	await get_tree().process_frame
	await get_tree().process_frame
	var effects_list: VBoxContainer = _sed.get_node("Panel/Margin/HBox/MainPanel/Margin/Scroll/VBox/EffectsList")
	if effects_list.get_child_count() > 0:
		var hat: SkillBlock = effects_list.get_child(0)
		_walk_blocks(hat.body_container, 0)

	# Deeply nested comparison inside an if condition: the reporter grows wide;
	# blocks must stay inside the script area (no spill into the palette).
	var ed3: Array = _sed.get("effect_data")
	ed3.clear()
	var nested_op: Dictionary = {"kind": "num", "value": 1}
	for depth in range(4):
		nested_op = {"kind": "expr", "op": "+", "a": nested_op, "b": {"kind": "var", "var_id": SkillEngine.VAR_ENEMY_HAND_COUNT}}
	var deep_cond := {
		"op": SkillEngine.CONDITION_OP_GTE,
		"lhs": nested_op,
		"rhs": {"kind": "num", "value": 1},
	}
	ed3.append({
		"effect": SkillEngine.EFFECT_IF,
		"condition": deep_cond,
		"then_effects": [{"effect": SkillEngine.EFFECT_DAMAGE, "target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "value": 1, "probability": 100}],
	})
	_sed.call("_refresh_script")
	await get_tree().process_frame
	await get_tree().process_frame
	# A wide block must stay reachable through the script area's horizontal
	# scroll bar (bottom bar) — never clipped or spilling out of the editor.
	var script_scroll: ScrollContainer = _sed.get_node("Panel/Margin/HBox/MainPanel/Margin/Scroll")
	var h_auto: bool = script_scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO
	var h_max: float = script_scroll.get_h_scroll_bar().max_value
	var v_max: float = script_scroll.get_v_scroll_bar().max_value
	print("UI_OVERFLOW deep_cond h_auto=%s h_max=%.0f v_max=%.0f" % [h_auto, h_max, v_max])
	if not h_auto:
		push_error("UI_OVERFLOW_FAIL horizontal scrolling not enabled")
		get_tree().quit(1)
		return
	if h_max <= 0.0:
		push_error("UI_OVERFLOW_FAIL wide comparison has no horizontal scroll range")
		get_tree().quit(1)
		return
	# The block must still live inside the scroll content area (scrolling to
	# the far right reveals it fully).
	var scroll_rect: Rect2 = script_scroll.get_global_rect()
	var max_block_right: float = 0.0
	for blk in _sed.find_children("*", "SkillBlock", true, false):
		max_block_right = maxf(max_block_right, (blk as Control).get_global_rect().end.x)
	var content_right: float = script_scroll.get_global_rect().position.x + script_scroll.get_h_scroll_bar().max_value + script_scroll.size.x
	print("UI_OVERFLOW deep_cond max_right=%.0f content_right=%.0f" % [max_block_right, content_right])
	if max_block_right > content_right + 1.0:
		push_error("UI_OVERFLOW_FAIL block extends beyond scrollable content")
		get_tree().quit(1)
		return

	print("TEST_UI_OVERFLOW_OK")
	get_tree().quit(0)


func _walk_blocks(container: VBoxContainer, depth: int) -> void:
	for child in container.get_children():
		if child is SkillBlock:
			var blk: SkillBlock = child
			if blk.has_method("get") and blk.get("_sentence_row") != null:
				var irow: Control = blk.get("_sentence_row")
				var over: float = irow.size.x - blk.size.x
				print("UI_OVERFLOW depth=%d block=%.0f row=%.0f over=%.0f" % [depth, blk.size.x, irow.size.x, over])
			if blk.then_container != null:
				_walk_blocks(blk.then_container, depth + 1)
			if blk.else_container != null:
				_walk_blocks(blk.else_container, depth + 1)


func _check(tag: String, eff: String) -> void:
	var effects_list: VBoxContainer = _sed.get_node("Panel/Margin/HBox/MainPanel/Margin/Scroll/VBox/EffectsList")
	if effects_list.get_child_count() == 0:
		return
	var hat: SkillBlock = effects_list.get_child(0)
	for child in hat.body_container.get_children():
		if child is SkillBlock:
			var block: SkillBlock = child
			var row: Control = block.get("_sentence_row")
			var row_w: float = row.size.x
			var block_w: float = block.size.x
			var overflow: float = row_w - block_w
			var worst_child: float = 0.0
			var worst_name := ""
			for i in range(row.get_child_count()):
				var c: Control = row.get_child(i)
				if c.size.x > worst_child:
					worst_child = c.size.x
					worst_name = str(c.get_class())
			print("UI_OVERFLOW %s eff=%s block=%.0f row=%.0f over=%.0f worst=[%s %.0f]" % [tag, eff, block_w, row_w, overflow, worst_name, worst_child])
			break
