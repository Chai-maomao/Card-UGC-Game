extends Node

# ============================================
# Target-selector reporter tests: the effect sentence now renders two oval
# slots — [友方/敌方] [目标] — each accepting its matching palette reporter
# (side_block / target_block) via drag-drop, editable by clicking, and
# draggable back onto the palette to restore the default.
# ============================================

var failures: Array = []


func _ready() -> void:
	Locale.language = "zh"
	PlayerData.card_draft = {
		"name": "目标测试", "cost": 2, "hp": 4, "atk": 2, "gender": "male",
		"card_type": "minion", "art_path": "",
		"skill1": {}, "skill2": {}, "skill3": {},
	}
	PlayerData.editing_skill_index = 1
	var scene: PackedScene = load("res://SkillEditor.tscn")
	var sed: Node = scene.instantiate()
	add_child(sed)
	await get_tree().process_frame
	await get_tree().process_frame

	sed.call("_add_effect_block", SkillEngine.EFFECT_DAMAGE)
	await get_tree().process_frame
	var block: SkillBlock = _find_effect_block(sed, SkillEngine.EFFECT_DAMAGE)
	_assert(block != null, "damage block not rendered")
	if block == null:
		_finish()
		return

	var side_slot: TargetSlot = _find_target_slot(block, "side")
	var tgt_slot: TargetSlot = _find_target_slot(block, "target")
	_assert(side_slot != null, "side slot missing")
	_assert(tgt_slot != null, "target slot missing")

	# --- Sentence order: side slot comes before the target slot --------------
	var row: Control = block.get("_sentence_row")
	var first_slot := -1
	var second_slot := -1
	for i in range(row.get_child_count()):
		var c: Control = row.get_child(i)
		if c is TargetSlot:
			if first_slot < 0:
				first_slot = i
			elif second_slot < 0:
				second_slot = i
	_assert(first_slot >= 0 and second_slot > first_slot, "target slots order wrong (%d,%d)" % [first_slot, second_slot])
	_assert(row.get_child(first_slot).kind == "side", "first slot is not side")
	_assert(row.get_child(second_slot).kind == "target", "second slot is not target")

	# --- Drop a side reporter -> eff.target_side updates ---------------------
	var side_payload := {"type": "side_block", "value": SkillEngine.TARGET_SIDE_ENEMY}
	_assert(side_slot.call("_can_drop_var", Vector2.ZERO, side_payload), "side slot rejects side_block")
	side_slot.call("_drop_var", Vector2.ZERO, side_payload)
	var ed: Array = sed.get("effect_data")
	_assert(str(ed[0].get("target_side", "")) == SkillEngine.TARGET_SIDE_ENEMY,
			"side drop failed (side=%s)" % str(ed[0].get("target_side", "?")))

	# --- Drop a target reporter -> eff.target updates ------------------------
	var tgt_payload := {"type": "target_block", "value": SkillEngine.TARGET_ALL}
	_assert(tgt_slot.call("_can_drop_var", Vector2.ZERO, tgt_payload), "target slot rejects target_block")
	_assert(not tgt_slot.call("_can_drop_var", Vector2.ZERO, side_payload), "target slot accepted a side_block")
	tgt_slot.call("_drop_var", Vector2.ZERO, tgt_payload)
	ed = sed.get("effect_data")
	_assert(str(ed[0].get("target", "")) == SkillEngine.TARGET_ALL,
			"target drop failed (target=%s)" % str(ed[0].get("target", "?")))

	# --- Drag the chip out -> palette drop restores the default --------------
	var drag_data: Variant = tgt_slot.call("_slot_get_drag_data", Vector2.ZERO)
	_assert(drag_data is Dictionary and str((drag_data as Dictionary).get("type", "")) == "target_block",
			"target chip drag data wrong: %s" % str(drag_data))
	if drag_data is Dictionary:
		_assert((drag_data as Dictionary).get("from_slot") == tgt_slot, "chip did not carry from_slot")
		_assert(sed.call("_can_drop_on_palette", Vector2.ZERO, drag_data), "palette rejects target chip")
		sed.call("_drop_on_palette", Vector2.ZERO, drag_data)
	ed = sed.get("effect_data")
	_assert(str(ed[0].get("target", "")) == SkillEngine.TARGET_SINGLE,
			"palette drop did not restore target (target=%s)" % str(ed[0].get("target", "?")))

	# --- Click-to-pick path writes the same field (menu semantics) -----------
	# Emulate the menu's selection handler directly on the slot.
	tgt_slot.call("setup", ed[0], "target")
	tgt_slot.data["target"] = SkillEngine.TARGET_SELF_SIDES
	tgt_slot.call("_rebuild")
	ed = sed.get("effect_data")
	_assert(str(ed[0].get("target", "")) == SkillEngine.TARGET_SELF_SIDES, "target pick write failed")

	# --- Round-trip: saved skill keeps target + target_side ------------------
	var saved: Dictionary = sed.call("_build_skill")
	PlayerData.card_draft["skill2"] = saved
	var dict: Dictionary = PlayerData.serialize_card(CardData.new("T", 1, 1, 1, [saved]))
	var loaded: CardData = PlayerData.deserialize_card(JSON.parse_string(JSON.stringify(dict)))
	var s2: Dictionary = loaded.skills[0]
	var effs: Array = s2.get("effects", [])
	_assert(effs.size() == 1, "round-trip effects lost")
	if effs.size() == 1:
		_assert(str((effs[0] as Dictionary).get("target", "")) == SkillEngine.TARGET_SELF_SIDES, "round-trip target lost")
		_assert(str((effs[0] as Dictionary).get("target_side", "")) == SkillEngine.TARGET_SIDE_ENEMY, "round-trip target_side lost")

	_finish()


func _find_effect_block(sed: Node, effect_id: String) -> SkillBlock:
	var effects_list: VBoxContainer = sed.get_node("Panel/Margin/HBox/MainPanel/Margin/Scroll/VBox/EffectsList")
	if effects_list.get_child_count() == 0:
		return null
	var hat: SkillBlock = effects_list.get_child(0)
	for c in hat.body_container.get_children():
		if c is SkillBlock and str((c as SkillBlock)._effect.get("effect", "")) == effect_id:
			return c
	return null


func _find_target_slot(block: SkillBlock, kind: String) -> TargetSlot:
	var row: Control = block.get("_sentence_row")
	for i in range(row.get_child_count()):
		var c: Control = row.get_child(i)
		if c is TargetSlot and (c as TargetSlot).kind == kind:
			return c
	return null


func _finish() -> void:
	if failures.is_empty():
		print("TEST_SKILL_TARGET_BLOCKS_OK")
		get_tree().quit(0)
	else:
		for msg in failures:
			push_error(msg)
		get_tree().quit(1)


func _assert(cond: bool, message: String) -> void:
	if not cond:
		failures.append(message)
