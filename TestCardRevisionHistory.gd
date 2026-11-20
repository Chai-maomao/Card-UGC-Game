extends Node

const Revisions = preload("res://CardRevisionRepository.gd")
const Schema = preload("res://DataSchema.gd")

var failures := 0


func _ready() -> void:
	Locale.language = "zh"
	_test_repository()
	await _test_editor_restore()
	if failures > 0:
		push_error("TEST_CARD_REVISION_HISTORY_FAILED: %d" % failures)
		get_tree().quit(1)
		return
	print("TEST_CARD_REVISION_HISTORY_OK")
	get_tree().quit(0)


func _test_repository() -> void:
	var entries: Array = []
	var snapshot := _snapshot("card_history", "初版", 1, 3, 1)
	var first := Revisions.add(entries, snapshot, 100)
	entries = first.entries
	_assert(first.changed and entries.size() == 1, "first revision was not recorded")
	var duplicate := Revisions.add(entries, snapshot, 101)
	_assert(not duplicate.changed and duplicate.entries.size() == 1, "identical revision was not deduplicated")
	for index in range(2, 14):
		var changed := _snapshot("card_history", "版本%d" % index, index, 3, 1)
		entries = Revisions.add(entries, changed, 100 + index).entries
	var history := Revisions.history(entries, "card_history")
	_assert(history.size() == Revisions.MAX_REVISIONS_PER_CARD, "per-card revision limit was not enforced")
	_assert(int(history[0].revision) == 13 and int(history[-1].revision) == 4, "revision trimming did not retain the newest entries")
	var payload := Revisions.payload(entries)
	_assert(Schema.validate(Schema.KIND_CARD_REVISIONS, payload).is_empty(), "revision payload failed schema validation")


func _test_editor_restore() -> void:
	var backup := {
		"decks": PlayerData.deck_library,
		"cards": PlayerData.card_library,
		"draft": PlayerData.card_draft.duplicate(true),
		"deck_id": PlayerData.editing_deck_id,
		"instance_id": PlayerData.editing_instance_id,
		"index": PlayerData.editing_index,
		"revisions": PlayerData.card_revisions,
		"tutorial": PlayerData.skill_tutorial_active,
	}
	var current := CardData.new("当前版本", 4, 7, 3, [])
	current.card_id = "card_ui_history"
	current.instance_id = "instance_ui_history"
	var old_snapshot := _snapshot(current.card_id, "旧版本", 2, 5, 2)
	var current_snapshot := PlayerData._card_revision_snapshot(current)
	PlayerData.deck_library = [{"id": "deck_ui_history", "name": "测试牌组", "cards": [current]}]
	PlayerData.rebuild_card_library_cache()
	PlayerData.editing_deck_id = "deck_ui_history"
	PlayerData.editing_instance_id = current.instance_id
	PlayerData.editing_index = 0
	PlayerData.card_draft = PlayerData.card_to_draft(current)
	PlayerData.card_revisions = [
		{"card_id": current.card_id, "revision": 2, "saved_at": 200, "card": current_snapshot},
		{"card_id": current.card_id, "revision": 1, "saved_at": 100, "card": old_snapshot},
	]
	PlayerData.skill_tutorial_active = false
	var editor := preload("res://CardEditor.tscn").instantiate()
	add_child(editor)
	await get_tree().process_frame
	await get_tree().process_frame
	var button: Button = editor.get("version_history_button")
	_assert(not button.disabled and button.text == Locale.t("revision.button_count", [2]), "history entry did not show its revision count")
	_assert(button.get_meta("ui_button_variant", "") == "secondary", "history entry does not use the shared secondary style")
	var popup: CanvasLayer = editor._open_version_history()
	await get_tree().process_frame
	var panel: Panel = popup.get_node("CardRevisionPanel")
	var hint: Label = panel.find_child("RevisionHint", true, false)
	_assert(panel.get_theme_stylebox("panel") is StyleBoxFlat, "history popup does not use the shared panel style")
	_assert(hint.text.contains("恢复只会替换当前草稿") and not hint.text.contains("Restore"), "history popup mixed languages")
	var restore_buttons := panel.find_children("RestoreRevisionButton", "Button", true, false)
	_assert(restore_buttons.size() == 2, "history popup did not render all versions")
	# Restore the older row. The saved deck must stay untouched until a later save.
	(restore_buttons[1] as Button).pressed.emit()
	await get_tree().process_frame
	_assert(str(PlayerData.card_draft.get("name", "")) == "旧版本", "old revision was not restored to the draft")
	_assert(int(PlayerData.card_draft.get("cost", 0)) == 2 and int(PlayerData.card_draft.get("hp", 0)) == 5 and int(PlayerData.card_draft.get("atk", 0)) == 2, "programmatic restore was overwritten by stale form signals")
	_assert(current.card_name == "当前版本" and current.cost == 4, "restoring a revision changed the saved deck immediately")
	# Authoring layout must still trigger the discard warning and survive the
	# actual card save path, while leaving gameplay identity unchanged.
	current.skills = [{"skill_name":"守护","trigger":SkillEngine.TRIGGER_ON_ATTACK,"effects":[{"effect":SkillEngine.EFFECT_HEAL,"target":SkillEngine.TARGET_SELF,"target_side":SkillEngine.TARGET_SIDE_ALL,"value":1}]}]
	PlayerData.card_draft = PlayerData.card_to_draft(current)
	editor._restore_form_from_draft()
	_assert(not editor._has_unsaved_card_edits(), "unchanged card must not become dirty")
	PlayerData.card_draft.skill1["_workspace"] = {"version":1,"position":[1200,3400],"groups":{}}
	_assert(editor._has_unsaved_card_edits(), "layout-only edits must retain the discard warning")
	var layout_card := PlayerData.build_card_from_draft()
	_assert(SharePackage.gameplay_signature(PlayerData.serialize_card(current)) == SharePackage.gameplay_signature(PlayerData.serialize_card(layout_card)), "layout must not create different game rules")
	_assert(PlayerData.update_deck_card("deck_ui_history", current.instance_id, layout_card), "card save must accept editor layout")
	var stored := PlayerData.find_deck_card("deck_ui_history", current.instance_id)
	_assert(stored.skills[0].get("_workspace", {}).get("position", []) == [1200,3400], "actual deck save lost the layout")
	editor.queue_free()
	await get_tree().process_frame
	PlayerData.deck_library = backup.decks
	PlayerData.card_library = backup.cards
	PlayerData.card_draft = backup.draft
	PlayerData.editing_deck_id = backup.deck_id
	PlayerData.editing_instance_id = backup.instance_id
	PlayerData.editing_index = backup.index
	PlayerData.card_revisions = backup.revisions
	PlayerData.skill_tutorial_active = backup.tutorial


func _snapshot(card_id: String, name: String, cost: int, hp: int, atk: int) -> Dictionary:
	return {
		"card_id": card_id,
		"instance_id": "instance_" + card_id,
		"name": name,
		"cost": cost,
		"max_hp": hp,
		"hp": hp,
		"atk": atk,
		"base_cost": cost,
		"base_max_hp": hp,
		"base_atk": atk,
		"gender": "nonhuman",
		"art_path": "",
		"card_type": "minion",
		"parasite_damage_mode": CardData.PARASITE_DAMAGE_ABSORB,
		"skills": [],
		"parasite_cards": [],
	}


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
