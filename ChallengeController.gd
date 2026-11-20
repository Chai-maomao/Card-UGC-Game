class_name ChallengeController
extends Node

var battle: Node
var challenge_id: String
var finished := false
var elapsed := 0.0
var popup_layer: CanvasLayer
var message_label: Label


func _t(zh: String, en: String) -> String:
	return zh if Locale.language == "zh" else en


func setup(owner_battle: Node, header: HBoxContainer, selected_challenge_id: String) -> void:
	battle = owner_battle
	challenge_id = selected_challenge_id
	battle.get_viewport().size_changed.connect(_resize_active_popup)
	var button := Button.new()
	button.name = "ChallengeObjectiveButton"
	button.text = _t("挑战目标", "Challenge objective")
	UITheme.apply_button(button, "secondary")
	header.add_child(button)
	button.pressed.connect(_show)
	_show.call_deferred()


func _reset() -> void:
	if battle._turn_ending or battle._resolution_running or battle._resolution_pending_steps > 0:
		return
	_close_popup()
	battle.cancel_attack()
	PracticeChallenges.configure(battle.game, challenge_id)
	battle._pending_hand_entry_ids.clear()
	battle._pending_feedback_events.clear()
	battle.reset_hand_ui_from_game_state()
	battle.battle_finished = false
	finished = false
	elapsed = 0.0
	battle.update_entire_screen()
	_show()


func _show(include_hint := false) -> void:
	_close_popup()
	var popup := UITheme.make_popup_layer(battle, 150)
	popup_layer = popup["layer"]
	popup_layer.name = "ChallengePopupLayer"
	var panel := PanelContainer.new()
	panel.name = "ChallengePopup"
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	popup_layer.add_child(panel)
	_fit_popup(panel)
	UITheme.apply_popup_frame(panel, "gold")
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 22)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)
	var number := PracticeChallenges.IDS.find(challenge_id) + 1
	var title := Label.new()
	title.name = "ChallengeTitle"
	title.text = "%d/%d  %s" % [number, PracticeChallenges.IDS.size(), PracticeChallenges.title(challenge_id)]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.apply_title(title, 23)
	box.add_child(title)
	message_label = Label.new()
	message_label.name = "ChallengeMessage"
	message_label.text = _message(include_hint)
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_label(message_label)
	message_label.add_theme_font_size_override("font_size", 16)
	var scroll := ScrollContainer.new()
	scroll.name = "ChallengeTextScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 160
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UITheme.apply_scrollbar(scroll.get_v_scroll_bar())
	box.add_child(scroll)
	scroll.add_child(message_label)
	var row := HBoxContainer.new()
	row.name = "ChallengeActions"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	_build_actions(row, include_hint)


func _fit_popup(panel: Control) -> void:
	if not is_instance_valid(panel): return
	var dimensions := Vector2(700, 450).min(panel.get_viewport_rect().size - Vector2(32, 32))
	panel.offset_left = -dimensions.x / 2
	panel.offset_right = dimensions.x / 2
	panel.offset_top = -dimensions.y / 2
	panel.offset_bottom = dimensions.y / 2


func _resize_active_popup() -> void:
	if is_instance_valid(popup_layer):
		_fit_popup(popup_layer.get_node("ChallengePopup"))


func _message(include_hint: bool) -> String:
	var text := PracticeChallenges.objective(challenge_id) + "\n\n" + PracticeChallenges.progress(battle.game, challenge_id)
	if include_hint:
		text += "\n\n" + PracticeChallenges.hint(challenge_id)
	if finished:
		if PracticeChallenges.succeeded(battle.game, challenge_id):
			text += "\n\n" + _t("挑战成功！", "Challenge complete!") + "\n" + PracticeChallenges.lesson(challenge_id)
		else:
			text += "\n\n" + PracticeChallenges.failure_reason(battle.game, challenge_id)
	return text


func _build_actions(row: HBoxContainer, include_hint: bool) -> void:
	if finished and PracticeChallenges.succeeded(battle.game, challenge_id):
		var current_index := PracticeChallenges.IDS.find(challenge_id)
		var next_id: String = PracticeChallenges.IDS[current_index + 1] if current_index >= 0 and current_index + 1 < PracticeChallenges.IDS.size() else ""
		if not next_id.is_empty():
			_add_action(row, "NextChallengeButton", _t("下一关", "Next challenge"), "primary", _start_challenge.bind(next_id))
		_add_action(row, "ChallengePickerButton", _t("返回关卡选择", "Choose challenge"), "secondary", _return_to_picker)
	else:
		if not include_hint and not finished:
			_add_action(row, "ChallengeHintButton", _t("查看提示", "Show hint"), "secondary", _show.bind(true))
		_add_action(row, "ChallengeRetryButton", _t("重新挑战", "Retry"), "secondary", _reset)
		if finished:
			_add_action(row, "ChallengePickerButton", _t("返回关卡选择", "Choose challenge"), "secondary", _return_to_picker)
	_add_action(row, "ChallengeCloseButton", _t("关闭", "Close"), "secondary", _close_popup)


func _add_action(row: HBoxContainer, node_name: String, text_value: String, variant: String, callback: Callable) -> void:
	var button := Button.new()
	button.name = node_name
	button.text = text_value
	button.custom_minimum_size = Vector2(120, 40)
	UITheme.apply_button(button, variant)
	button.pressed.connect(callback)
	row.add_child(button)


func _start_challenge(id: String) -> void:
	_close_popup()
	NetworkManager.close_connection()
	PlayerData.configure_hotseat_battle(CardDatabase.beginner_deck(), CardDatabase.beginner_deck())
	PlayerData.practice_challenge_id = id
	UIMotion.replace_scene("res://Main.tscn")


func _return_to_picker() -> void:
	_close_popup()
	NetworkManager.close_connection()
	PlayerData.practice_challenge_id = ""
	UIMotion.replace_scene("res://MainMenu.tscn", true, "challenge_picker:" + challenge_id)


func _close_popup() -> void:
	if is_instance_valid(popup_layer):
		popup_layer.queue_free()
	popup_layer = null
	message_label = null


func _process(delta: float) -> void:
	if battle == null or finished:
		return
	if battle._turn_ending or battle._resolution_running or battle._resolution_pending_steps > 0:
		return
	elapsed += delta
	if elapsed < 0.25:
		return
	elapsed = 0
	if PracticeChallenges.succeeded(battle.game, challenge_id) or PracticeChallenges.failed(battle.game, challenge_id):
		finished = true
		_show()


func _exit_tree() -> void:
	# A scene queued for deletion can exit after the player has already picked
	# another challenge. Only clear the selection this controller owns.
	if PlayerData.practice_challenge_id == challenge_id:
		PlayerData.practice_challenge_id = ""
