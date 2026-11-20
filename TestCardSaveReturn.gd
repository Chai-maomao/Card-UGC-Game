extends Node

var failures := 0

func _enter_tree() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH, true)

func _ready() -> void:
	Locale.language = "zh"
	get_window().size = Vector2i(1280, 720)
	PlayerData.deck_library = [{"id":"save-return-test", "name":"测试牌组", "cards":[]}]
	PlayerData.current_deck_id = "save-return-test"
	PlayerData.rebuild_card_library_cache()
	PlayerData.editing_index = -1
	PlayerData.editing_deck_id = ""
	PlayerData.editing_instance_id = ""
	PlayerData.card_draft = PlayerData.card_to_draft(CardData.new("继续编辑测试", 2, 4, 3, []))
	var editor := preload("res://CardEditor.tscn").instantiate()
	add_child(editor)
	await get_tree().process_frame
	if not await _save_with_keyboard_navigation(editor):
		get_tree().quit(1)
		return
	await get_tree().create_timer(.4).timeout
	var buttons := _popup_buttons(editor)
	_check(buttons.size() == 2, "save dialog must have exactly two actions")
	_check(buttons.any(func(b): return b.text == "热座测试"), "hotseat action missing")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://artifacts/hand-overlap-20261115/save-return-popup.png")
	var saved_id := PlayerData.editing_instance_id
	_send_key(KEY_ESCAPE)
	await get_tree().create_timer(0.1).timeout
	_check(is_instance_valid(editor) and editor.is_inside_tree(), "return left current editor")
	_check(_popup_buttons(editor).is_empty(), "return did not close popup")
	_check(editor.name_input.text == "继续编辑测试", "return lost current form")
	_check(editor.name_input.has_focus(), "closing the saved result did not restore focus to the form")
	_check(not editor._has_unsaved_card_edits(), "saved card still appears unsaved")
	editor.name_input.text = "再次保存测试"
	editor._save_form_to_draft()
	editor._save_card_without_conflict(PlayerData.build_card_from_draft())
	_check(PlayerData.get_cards_for_deck("save-return-test").size() == 1, "second save duplicated card")
	_check(PlayerData.find_deck_card("save-return-test", saved_id).card_name == "再次保存测试", "second save did not update same card")
	editor.queue_free()
	await get_tree().process_frame
	await _check_save_name_conflicts()
	await _check_import_name_conflict()
	await _check_repeated_import_conflict()
	await _check_cancelled_import()
	await _check_new_deck_import_result()
	await _check_failed_card_save()
	if failures == 0: print("TEST_CARD_SAVE_RETURN_OK")
	get_tree().quit(0 if failures == 0 else 1)

func _send_key(key: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.pressed = pressed
		get_viewport().push_input(event, true)

func _save_with_keyboard_navigation(editor: Node) -> bool:
	editor.name_input.grab_focus()
	editor.save_button.pressed.emit()
	await get_tree().create_timer(0.1).timeout
	var targets := UIMotion.top_popup()
	_check(targets != null and targets.get_parent() == editor, "the save target dialog did not take over keyboard navigation")
	if targets == null:
		return false
	var focus := get_viewport().gui_get_focus_owner()
	_check(focus != null and targets.is_ancestor_of(focus), "opening save targets left focus on the form")
	_send_key(KEY_ESCAPE)
	await get_tree().create_timer(0.1).timeout
	_check(UIMotion.top_popup() == null and editor.name_input.has_focus(), "Escape did not close save targets and refocus the form")
	_check(editor.name_input.text == "继续编辑测试" and PlayerData.get_cards_for_deck("save-return-test").is_empty(), "Escape changed the draft or saved a card")
	editor.save_button.pressed.emit()
	await get_tree().create_timer(0.1).timeout
	targets = UIMotion.top_popup()
	if targets == null:
		return false
	_send_key(KEY_TAB)
	var save := get_viewport().gui_get_focus_owner() as Button
	_check(save != null and targets.is_ancestor_of(save) and save.text == Locale.t("editor.save_card"), "Tab could not reach Save in the target dialog")
	if save == null or not targets.is_ancestor_of(save):
		return false
	_send_key(KEY_ENTER)
	await get_tree().create_timer(0.1).timeout
	var result := UIMotion.top_popup()
	focus = get_viewport().gui_get_focus_owner()
	var result_has_focus := result != null and focus != null and result.is_ancestor_of(focus)
	_check(result_has_focus, "saving restored focus behind the result dialog")
	return result_has_focus

func _popup_buttons(editor: Node) -> Array[Button]:
	var result: Array[Button] = []
	for child in editor.get_children():
		if child is CanvasLayer and child.layer == 100:
			for button in child.find_children("*", "Button", true, false):
				result.append(button)
	return result

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _check_save_name_conflicts() -> void:
	for action in ["share.rename_incoming","share.rename_local"]:
		PlayerData.deck_library = [{"id":"save-return-test","name":"测试牌组","cards":[]}]
		PlayerData.current_deck_id = "save-return-test"
		PlayerData.rebuild_card_library_cache()
		PlayerData.editing_index = -1
		PlayerData.editing_deck_id = ""
		PlayerData.editing_instance_id = ""
		for card_name in ["未命名","未命名 2","未命名 4"]:
			PlayerData.add_card_copy_to_deck("save-return-test",CardData.new(card_name,1,4,1,[]))
		var incoming := CardData.new("未命名",1,4,3,[])
		PlayerData.card_draft = PlayerData.card_to_draft(incoming)
		var editor := preload("res://CardEditor.tscn").instantiate()
		add_child(editor)
		await get_tree().create_timer(0.3).timeout
		editor._start_multi_deck_save(incoming,["save-return-test"])
		await get_tree().create_timer(0.3).timeout
		var conflict: CanvasLayer
		for child in editor.get_children():
			if child is CanvasLayer and child.layer == 110: conflict = child
		_check(conflict != null,"name conflict must open a resolution dialog")
		if conflict == null:
			editor.queue_free()
			await get_tree().process_frame
			continue
		var input: LineEdit = conflict.find_children("*","LineEdit",true,false)[0]
		var suggested := input.text
		var names_before: Array = PlayerData.get_cards_for_deck("save-return-test").map(func(c): return c.card_name)
		_check(suggested not in names_before,"suggested rename is already taken: %s" % suggested)
		var rename: Button
		for button in conflict.find_children("*","Button",true,false):
			if button.text == Locale.t(action): rename = button
		input.text = "未命名 2"
		await _click(rename)
		_check(is_instance_valid(conflict) and not conflict.is_queued_for_deletion(),"duplicate rename must keep the dialog open")
		_check(PlayerData.get_cards_for_deck("save-return-test").map(func(c): return c.card_name) == names_before,"rejected rename changed the existing cards")
		_check(incoming.card_name == "未命名","rejected rename changed the unsaved card")
		_check(editor.pending_save_index == 0,"rejected rename advanced the save or reported success")
		_check(editor.pending_save_card != null and _popup_buttons(editor).is_empty(),"rejected rename reported save success")
		if is_instance_valid(conflict) and not conflict.is_queued_for_deletion():
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("res://artifacts/hand-overlap-20261115/save-name-conflict.png")
			input.text = suggested
			await _click(rename)
			var cards := PlayerData.get_cards_for_deck("save-return-test")
			_check(cards.size() == 4,"successful rename lost or overwrote a card")
			_check(cards.map(func(c): return c.card_name).count(suggested) == 1,"successful rename did not keep a unique name")
			_check(cards.any(func(c): return c.card_name == (suggested if action == "share.rename_incoming" else "未命名") and c.base_atk == 3),"the actual incoming card was not saved")
		editor.queue_free()
		await get_tree().process_frame

func _click(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion,true)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		get_viewport().push_input(event,true)
		await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout


func _check_import_name_conflict() -> void:
	var deck_id := "import-name-test"
	PlayerData.deck_library = [{"id": deck_id, "name": "导入测试牌组", "cards": []}]
	PlayerData.current_deck_id = deck_id
	PlayerData.rebuild_card_library_cache()
	for card_name in ["未命名", "未命名 2"]:
		PlayerData.add_card_copy_to_deck(deck_id, CardData.new(card_name, 1, 4, 1, []))
	var incoming := CardData.new("未命名", 1, 4, 3, [])
	incoming.card_id = "incoming-original"
	var reserved := CardData.new("未命名 3", 1, 4, 5, [])
	reserved.card_id = "incoming-numbered"
	var path := "user://import-name-test.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(PlayerData.serialize_cards_for_share([incoming, reserved]))
	file.close()
	var screen := preload("res://MyCards.tscn").instantiate()
	add_child(screen)
	screen._show_deck_cards(deck_id)
	screen.pending_import_mode = "deck_append"
	screen._import_from_file(path)
	var dialogs := screen.find_children("*", "ConfirmationDialog", true, false)
	_check(dialogs.size() == 1, "importing a real share file must open its preview")
	if dialogs.size() != 1:
		screen.queue_free()
		return
	dialogs[0].get_ok_button().pressed.emit()
	await get_tree().create_timer(0.4).timeout
	var dialog: CanvasLayer
	for child in screen.get_children():
		if child is CanvasLayer and child.layer == 120:
			dialog = child
	_check(dialog != null, "the import must show the conflicting cards")
	if dialog == null:
		screen.queue_free()
		return
	var input := dialog.find_children("*", "LineEdit", true, false)[0] as LineEdit
	var suggested := input.text
	_check(suggested == "未命名 4", "the import suggestion must avoid existing names and other incoming cards")
	var rename_new: Button
	var rename_local: Button
	for button in dialog.find_children("*", "Button", true, false):
		if button.text == Locale.t("share.rename_incoming"): rename_new = button
		if button.text == Locale.t("share.rename_local"): rename_local = button
	input.text = "未命名 2"
	await _click(rename_local)
	_check(is_instance_valid(dialog) and not dialog.is_queued_for_deletion(), "renaming the local card to an occupied name must leave the import dialog open")
	if is_instance_valid(dialog) and not dialog.is_queued_for_deletion():
		input.text = "未命名 3"
		await _click(rename_new)
		_check(is_instance_valid(dialog) and not dialog.is_queued_for_deletion(), "a name reserved by the same import must be rejected")
	if is_instance_valid(dialog) and not dialog.is_queued_for_deletion():
		_check(PlayerData.get_cards_for_deck(deck_id).size() == 2, "invalid names must not add any card")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://artifacts/import-name-conflict.png")
		input.text = suggested
		await _click(rename_new)
	var cards := PlayerData.get_cards_for_deck(deck_id)
	_check(cards.map(func(card): return card.card_name) == ["未命名", "未命名 2", "未命名 3", "未命名 4"], "import must preserve both existing cards and add both incoming cards under distinct names")
	_check(cards.any(func(card): return card.card_name == "未命名 4" and card.base_atk == 3), "the renamed import must retain the incoming card's data")
	screen.queue_free()


func _check_repeated_import_conflict() -> void:
	var deck_id := "repeated-import-name-test"
	PlayerData.deck_library = [{"id": deck_id, "name": "批量导入测试牌组", "cards": []}]
	PlayerData.current_deck_id = deck_id
	PlayerData.rebuild_card_library_cache()
	var original: CardData = PlayerData.add_card_copy_to_deck(deck_id, CardData.new("同名卡", 1, 4, 1, []))["card"]
	var first := CardData.new("同名卡", 1, 4, 3, [])
	first.card_id = "incoming-first"
	var second := CardData.new("同名卡", 1, 4, 5, [])
	second.card_id = "incoming-second"
	var path := "user://repeated-import-name-test.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(PlayerData.serialize_cards_for_share([first, second]))
	file.close()
	var screen := preload("res://MyCards.tscn").instantiate()
	add_child(screen)
	screen._show_deck_cards(deck_id)
	screen.pending_import_mode = "deck_append"
	screen._import_from_file(path)
	var dialogs := screen.find_children("*", "ConfirmationDialog", true, false)
	_check(dialogs.size() == 1, "the repeated-name package must open its preview")
	if dialogs.size() != 1:
		screen.queue_free()
		return
	dialogs[0].get_ok_button().pressed.emit()
	await get_tree().create_timer(0.4).timeout
	var first_conflict := _find_import_action(screen, "share.rename_local")
	_check(first_conflict != null, "the first incoming card must ask about the existing card")
	if first_conflict == null:
		screen.queue_free()
		return
	await _click(first_conflict)
	var replace := _find_import_action(screen, "share.replace_pending")
	_check(replace != null, "the second incoming card must ask about the first imported card")
	if replace != null:
		var preview_cards := replace.get_parent().get_parent().find_children("*", "Control", true, false).filter(func(node): return node.get("current_card_data") is CardData)
		_check(preview_cards.size() == 2 and preview_cards[0].current_card_data.base_atk == 3, "the second conflict preview must show the first incoming card as its replacement target")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://artifacts/import-repeated-name.png")
		await _click(replace)
	var cards := PlayerData.get_cards_for_deck(deck_id)
	var kept_original := PlayerData.find_deck_card(deck_id, original.instance_id)
	_check(kept_original != null and kept_original.card_name == "同名卡 2" and kept_original.base_atk == 1, "the second replacement must preserve the renamed original")
	_check(cards.size() == 2 and cards.any(func(card): return card.card_name == "同名卡" and card.base_atk == 5), "the second incoming card must replace the first incoming card")
	screen.queue_free()


func _find_import_action(screen: Node, label_key: String) -> Button:
	for child in screen.get_children():
		if child is CanvasLayer and child.layer == 120 and not child.is_queued_for_deletion():
			for button in child.find_children("*", "Button", true, false):
				if button.text == Locale.t(label_key):
					return button
	return null


func _check_cancelled_import() -> void:
	var deck_id := "cancel-import-test"
	PlayerData.deck_library = [{"id": deck_id, "name": "取消导入测试牌组", "cards": []}]
	PlayerData.current_deck_id = deck_id
	PlayerData.rebuild_card_library_cache()
	for name in ["取消测试甲", "取消测试乙"]:
		PlayerData.add_card_copy_to_deck(deck_id, CardData.new(name, 1, 4, 1, []))
	var originals := PlayerData.get_cards_for_deck(deck_id).duplicate()
	_check(PlayerData.save_library(), "the cancellation fixture must have a save on disk")
	var saved := FileAccess.get_file_as_bytes(PlayerData.save_path)
	var before := PlayerData.serialize_deck(PlayerData.get_deck(deck_id))
	var incoming := [
		CardData.new("取消测试甲", 1, 4, 3, []),
		CardData.new("取消测试乙", 1, 4, 5, []),
	]
	var path := "user://cancel-import-test.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(PlayerData.serialize_cards_for_share(incoming))
	file.close()
	var screen := preload("res://MyCards.tscn").instantiate()
	add_child(screen)
	screen._show_deck_cards(deck_id)
	screen.pending_import_mode = "deck_append"
	screen._import_from_file(path)
	var previews := screen.find_children("*", "ConfirmationDialog", true, false)
	_check(previews.size() == 1, "the cancellation test must enter through the import preview")
	if previews.size() != 1:
		screen.queue_free()
		return
	previews[0].get_ok_button().pressed.emit()
	await get_tree().create_timer(0.4).timeout
	var replace := _find_import_action(screen, "share.replace_local")
	_check(replace != null, "the first local conflict must offer replacement")
	if replace == null:
		screen.queue_free()
		return
	await _click(replace)
	_check(_find_import_action(screen, "share.replace_local") != null, "there must still be a second conflict after the first selection")
	_check(PlayerData.serialize_deck(PlayerData.get_deck(deck_id)) == before, "choosing the first replacement must not modify the live deck")
	_check(FileAccess.get_file_as_bytes(PlayerData.save_path) == saved, "choosing the first replacement must not modify the saved deck")
	var cancel := _find_import_action(screen, "share.cancel_import")
	_check(cancel != null, "the remaining conflict must offer Cancel Import")
	if cancel != null:
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://artifacts/import-cancel.png")
			await _click(cancel)
		else:
			var escape := InputEventKey.new()
			escape.keycode = KEY_ESCAPE
			escape.pressed = true
			get_viewport().push_input(escape, true)
			escape.pressed = false
			get_viewport().push_input(escape, true)
			await get_tree().process_frame
		_check(_find_import_action(screen, "share.replace_local") == null, "cancel must dismiss the conflict")
		_check(screen.pending_import_prepared.is_empty(), "cancel must clear the pending batch")
	_check(PlayerData.serialize_deck(PlayerData.get_deck(deck_id)) == before and FileAccess.get_file_as_bytes(PlayerData.save_path) == saved, "cancel must preserve both original cards and the saved file")
	screen.queue_free()
	await get_tree().process_frame
	var parsed := PlayerData.parse_share_package(PlayerData.serialize_cards_for_share(incoming))
	var prepared := PlayerData.prepare_import_cards(parsed["package"], deck_id)
	var replacement: CardData = incoming[0].duplicate_card()
	replacement.instance_id = originals[0].instance_id
	prepared["updates"][replacement.instance_id] = replacement
	prepared["incoming"].append({"card": CardData.new("本应新增", 1, 4, 2, []), "share_id": "failed-import"})
	var original_save_path := PlayerData.save_path
	PlayerData.save_path = "user://missing-import-test-directory/card_library.json"
	var result := PlayerData.apply_prepared_import(prepared, parsed["package"], false, true)
	PlayerData.save_path = original_save_path
	_check(not result.get("ok", false) and PlayerData.serialize_deck(PlayerData.get_deck(deck_id)) == before, "a failed write must roll back additions and updates")
	_check(FileAccess.get_file_as_bytes(PlayerData.save_path) == saved and PlayerData.current_deck_id == deck_id, "a failed write must preserve the saved deck and selected deck")


func _check_new_deck_import_result() -> void:
	var deck_id := PlayerData.current_deck_id
	var deck_count := PlayerData.deck_library.size()
	var save_path := PlayerData.save_path
	var saved := FileAccess.get_file_as_bytes(save_path)
	var card := CardData.new("导入测试卡", 1, 4, 3, [])
	card.card_id = "new-deck-test-card"
	var package: Dictionary = JSON.parse_string(PlayerData.serialize_cards_for_share([card]))
	var provenance := {"author": "测试作者", "revision": "3", "source": "本机导入测试"}
	package["provenance"] = provenance
	var path := "user://new-deck-import-test.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(package))
	file.close()
	var screen := preload("res://MyCards.tscn").instantiate()
	add_child(screen)
	screen.pending_import_mode = "deck_manager"
	screen._import_from_file(path)
	var previews := screen.find_children("*", "ConfirmationDialog", true, false)
	_check(previews.size() == 1, "a new-deck import must show the package preview")
	if previews.size() != 1:
		screen.queue_free()
		return
	PlayerData.save_path = "user://missing-new-deck-test-directory/card_library.json"
	previews[0].get_ok_button().pressed.emit()
	PlayerData.save_path = save_path
	await get_tree().create_timer(0.35).timeout
	_check(PlayerData.deck_library.size() == deck_count and PlayerData.current_deck_id == deck_id, "a failed new-deck import must restore the deck list and selection")
	_check(FileAccess.get_file_as_bytes(save_path) == saved, "a failed new-deck import must preserve the library file")
	var message := screen.find_child("CollectionConfirmPanel", true, false)
	_check(message != null and message.find_children("*", "Label", true, false).any(func(label): return label.text == Locale.t("share.import_save_failed")), "the new-deck import must report the failed write")
	if message != null and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://artifacts/new-deck-import-save-failed.png")
	if message != null:
		var ok := message.find_children("*", "Button", true, false)[0] as Button
		await _click(ok)
	screen._import_from_file(path)
	previews = screen.find_children("*", "ConfirmationDialog", true, false)
	if previews.size() == 1:
		previews[0].get_ok_button().pressed.emit()
	await get_tree().process_frame
	_check(PlayerData.deck_library.size() == deck_count + 1 and PlayerData.get_current_deck().cards.size() == 1, "retry must import exactly one deck with its card")
	PlayerData.load_library()
	var imported := PlayerData.get_current_deck()
	_check(imported.get("provenance", {}) == provenance, "the imported deck must retain its share metadata after reopening the library")
	screen.queue_free()


func _check_failed_card_save() -> void:
	var first_id := "failed-card-save-first"
	var second_id := "failed-card-save-second"
	PlayerData.deck_library = [{"id": first_id, "name": "保存测试甲", "cards": []}, {"id": second_id, "name": "保存测试乙", "cards": []}]
	PlayerData.current_deck_id = first_id
	PlayerData.rebuild_card_library_cache()
	PlayerData.editing_index = -1
	PlayerData.editing_deck_id = ""
	PlayerData.editing_instance_id = ""
	_check(PlayerData.save_library(), "the save failure fixture must have a saved file")
	var original_path := PlayerData.save_path
	var saved := FileAccess.get_file_as_bytes(original_path)
	PlayerData.card_draft = PlayerData.card_to_draft(CardData.new("失败后重试", 1, 4, 3, []))
	var editor := preload("res://CardEditor.tscn").instantiate()
	add_child(editor)
	await get_tree().process_frame
	editor._on_save_button_pressed()
	await get_tree().create_timer(0.35).timeout
	var targets := _editor_popup(editor, 105)
	_check(targets != null, "normal save must ask for target decks")
	if targets == null:
		editor.queue_free()
		return
	for checkbox in targets.find_children("*", "CheckBox", true, false):
		checkbox.button_pressed = true
	var save := _save_button(targets)
	PlayerData.save_path = "user://missing-editor-save-directory/card_library.json"
	await _click(save)
	PlayerData.save_path = original_path
	_check(_popup_buttons(editor).is_empty() and PlayerData.editing_instance_id.is_empty(), "a failed save must not offer a saved-card playtest or bind the unsaved card")
	_check(PlayerData.get_cards_for_deck(first_id).is_empty() and PlayerData.get_cards_for_deck(second_id).is_empty(), "a failed save must not leave a card in either target deck")
	_check(FileAccess.get_file_as_bytes(original_path) == saved and editor.name_input.text == "失败后重试", "a failed save must keep the saved bytes and editable draft")
	var notice := _editor_popup(editor, 120)
	_check(notice != null and notice.find_children("*", "Label", true, false).any(func(label): return label.text == Locale.t("editor.card_save_failed")), "the editor must explain the failed save")
	if notice != null:
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://artifacts/editor-card-save-failed.png")
		await _click(notice.find_children("*", "Button", true, false)[0] as Button)
	editor._on_save_button_pressed()
	await get_tree().create_timer(0.35).timeout
	targets = _editor_popup(editor, 105)
	if targets != null:
		_check(targets.find_children("*", "CheckBox", true, false).all(func(checkbox): return checkbox.button_pressed), "retry must keep the selected deck targets")
		await _click(_save_button(targets))
	_check(PlayerData.get_cards_for_deck(first_id).size() == 1 and PlayerData.get_cards_for_deck(second_id).size() == 1, "retry must save exactly one card in each selected deck")
	var success := _popup_buttons(editor)
	for button in success:
		if button.text == Locale.t("editor.after_save_return"):
			await _click(button)
			break
	var after_create := FileAccess.get_file_as_bytes(original_path)
	var first_deck := PlayerData.get_cards_for_deck(first_id)
	var second_deck := PlayerData.get_cards_for_deck(second_id)
	var first_card: CardData = first_deck.front() if not first_deck.is_empty() else null
	var second_card: CardData = second_deck.front() if not second_deck.is_empty() else null
	if first_card != null and second_card != null:
		editor.name_input.text = "同步改名"
		editor._on_save_button_pressed()
		await get_tree().create_timer(0.35).timeout
		targets = _editor_popup(editor, 105)
		if targets != null:
			PlayerData.save_path = "user://missing-editor-save-directory/card_library.json"
			await _click(_save_button(targets))
			PlayerData.save_path = original_path
			_check(_popup_buttons(editor).is_empty() and _editor_popup(editor, 120) != null and editor.name_input.text == "同步改名", "a failed synced edit must keep the draft and show only the error")
			_check(PlayerData.find_deck_card(first_id, first_card.instance_id).card_name == "失败后重试" and PlayerData.find_deck_card(second_id, second_card.instance_id).card_name == "失败后重试" and FileAccess.get_file_as_bytes(original_path) == after_create, "a failed synced edit must leave both saved instances unchanged")
			notice = _editor_popup(editor, 120)
			if notice != null:
				await _click(notice.find_children("*", "Button", true, false)[0] as Button)
			editor._on_save_button_pressed()
			await get_tree().create_timer(0.35).timeout
			targets = _editor_popup(editor, 105)
			if targets != null:
				await _click(_save_button(targets))
			_check(PlayerData.find_deck_card(first_id, first_card.instance_id).card_name == "同步改名" and PlayerData.find_deck_card(second_id, second_card.instance_id).card_name == "同步改名", "retrying the synced edit must update both original instances")
			PlayerData.load_library()
			for target in [[first_id, first_card.instance_id], [second_id, second_card.instance_id]]:
				var reloaded := PlayerData.find_deck_card(target[0], target[1])
				_check(reloaded != null and reloaded.card_name == "同步改名" and int(reloaded.get_meta(&"modified_at", 0)) > 0,
					"the synced edit and modification date must survive reloading both copies")
	editor.queue_free()


func _editor_popup(editor: Node, index: int) -> CanvasLayer:
	for child in editor.get_children():
		if child is CanvasLayer and child.layer == index and not child.is_queued_for_deletion():
			return child
	return null


func _save_button(targets: CanvasLayer) -> Button:
	for button in targets.find_children("*", "Button", true, false):
		if button.text == Locale.t("editor.save_card"):
			return button
	return null
