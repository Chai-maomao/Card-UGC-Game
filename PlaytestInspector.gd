class_name PlaytestInspector
extends Node

const SCENARIO_PATH := "user://playtest_scenario.json"
var battle: Node
var trace := SkillTrace.new()
var opening: Dictionary
var dialog: AcceptDialog
var rows: ItemList
var detail: Label
var edit: Button


func setup(owner_battle: Node, header: HBoxContainer) -> void:
	battle = owner_battle
	battle.game.trace_callable = trace.record
	var button := Button.new()
	button.text = _t("试打诊断", "Inspect playtest")
	UITheme.apply_button(button, "secondary")
	header.add_child(button)
	button.pressed.connect(show_trace)
	_capture_opening.call_deferred()


func _capture_opening() -> void:
	opening = battle.game.export_initial_state().duplicate(true)


func _t(zh: String, en: String) -> String:
	return zh if Locale.language == "zh" else en


func show_trace() -> void:
	if is_instance_valid(dialog):
		dialog.queue_free()
	dialog = AcceptDialog.new()
	dialog.title = _t("试打诊断 · 最近 300 条", "Playtest · latest 300 events")
	dialog.get_ok_button().text = _t("关闭", "Close")
	dialog.min_size = Vector2i(700, 500)
	add_child(dialog)
	var box := VBoxContainer.new()
	dialog.add_child(box)
	rows = ItemList.new()
	rows.custom_minimum_size = Vector2(670, 220)
	rows.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	box.add_child(rows)
	for row in trace.entries:
		rows.add_item(SkillTrace.describe(row))
	detail = Label.new()
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.text = _t("选择一条记录查看积木位置。没有记录时，请先触发一个技能。", "Select an event to see its block path. Trigger a skill to record events.")
	box.add_child(detail)
	var actions := HFlowContainer.new()
	box.add_child(actions)
	edit = _button(actions, _t("编辑对应积木", "Edit block"), _edit_selected)
	edit.disabled = true
	_button(actions, _t("重置试打", "Reset opening"), func(): _restore(opening))
	_button(actions, _t("保存当前局面", "Save scenario"), _save_scenario)
	_button(actions, _t("载入局面复测", "Load scenario"), _load_scenario)
	_button(actions, _t("导出诊断", "Export trace"), _export_trace)
	rows.item_selected.connect(func(index: int):
		var entry: Dictionary = trace.entries[index]
		detail.text = _t("技能 %d · 积木位置 %s", "Skill %d · block path %s") % [int(entry.get("skill_index", -1)) + 1, str(entry.get("path", []))]
		var specimen: Dictionary = PlayerData.card_playtest_context.get("test_card", {})
		edit.disabled = str(entry.get("card_id", "")) != str(specimen.get("card_id", "")) or int(entry.get("skill_index", -1)) < 0 or (entry.get("path", []) as Array).is_empty()
	)
	dialog.popup_centered(Vector2i(720, 540))


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	UITheme.apply_button(button, "secondary")
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _restore(state: Dictionary) -> void:
	if state.is_empty() or battle.is_resolution_locked():
		return
	battle.cancel_attack()
	battle.game.apply_initial_state(state.duplicate(true), false)
	battle.battle_finished = false
	trace.clear()
	battle.update_entire_screen()
	dialog.hide()


func _save_scenario() -> void:
	var file := FileAccess.open(SCENARIO_PATH, FileAccess.WRITE)
	if file == null:
		detail.text = _t("保存失败", "Save failed")
		return
	file.store_string(BattleRepro.export_json({"initial_state": battle.game.export_initial_state(), "specimen": PlayerData.card_playtest_context.get("test_card", {})}))
	detail.text = _t("已保存；编辑卡牌后可再次进入试打，载入此局面。", "Saved. After editing the card, re-enter playtest and load this scenario.")


func _load_scenario() -> void:
	var result := BattleRepro.import_json(FileAccess.get_file_as_string(SCENARIO_PATH)) if FileAccess.file_exists(SCENARIO_PATH) else {}
	if not result.get("ok", false):
		detail.text = _t("没有可用的局面", "No saved scenario")
		return
	var record: Dictionary = result.record
	var state: Dictionary = record.initial_state
	var previous: Dictionary = record.get("specimen", {})
	var current: Dictionary = PlayerData.card_playtest_context.get("test_card", {})
	_replace_specimen(state, str(previous.get("card_id", "")), current)
	_restore(state)


static func _replace_specimen(data: Variant, card_id: String, replacement: Dictionary) -> void:
	if card_id.is_empty() or replacement.is_empty(): return
	if data is Dictionary:
		if str(data.get("card_id", "")) == card_id:
			var instance = data.get("instance_id", "")
			data.clear()
			data.merge(replacement.duplicate(true))
			data["instance_id"] = instance
			return
		for child in data.values(): _replace_specimen(child, card_id, replacement)
	elif data is Array:
		for child in data: _replace_specimen(child, card_id, replacement)


func _export_trace() -> void:
	var picker := FileDialog.new()
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	picker.filters = PackedStringArray(["*.json ; Playtest diagnostics"])
	picker.current_file = "playtest-trace.json"
	add_child(picker)
	picker.file_selected.connect(func(path: String):
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_string(BattleRepro.export_json({"initial_state": opening, "current_state": battle.game.export_initial_state(), "events": trace.entries, "dropped_events": trace.dropped}))
			detail.text = _t("已导出诊断", "Diagnostics exported")
		else:
			detail.text = _t("导出失败", "Export failed")
		picker.queue_free()
	)
	picker.canceled.connect(picker.queue_free)
	picker.popup_centered_ratio(0.7)


func _edit_selected() -> void:
	if rows.get_selected_items().is_empty(): return
	var entry: Dictionary = trace.entries[rows.get_selected_items()[0]]
	var specimen: Dictionary = PlayerData.card_playtest_context.get("test_card", {}).duplicate(true)
	PlayerData.restore_after_card_playtest()
	PlayerData.card_draft = PlayerData.card_to_draft(PlayerData.deserialize_card(specimen))
	var index := int(entry.skill_index)
	var skills: Array = specimen.get("skills", [])
	PlayerData.editing_skill_index = 3 if str(skills[index].get("skill_type", "normal")) == "talent" else index
	PlayerData.skill_focus_path = (entry.path as Array).duplicate()
	get_tree().change_scene_to_file("res://SkillEditor.tscn")
