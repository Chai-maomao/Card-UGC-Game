extends Node

const Position = preload("res://BattlePosition.gd")
var battle: Node
var button: Button
var status: Label
var dialog: FileDialog
var pending: Dictionary = {}
var _message := ""


func setup(owner_battle: Node, parent: VBoxContainer) -> void:
	name = "PositionExporter"
	battle = owner_battle
	var row := HBoxContainer.new()
	row.name = "PositionExportRow"
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	button = Button.new()
	button.text = Locale.t("battle.save_position")
	UITheme.apply_button(button, "secondary")
	button.add_theme_font_size_override("font_size", 12)
	button.pressed.connect(_choose_path)
	row.add_child(button)
	status = Label.new()
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UITheme.apply_label(status, true)
	status.add_theme_font_size_override("font_size", 11)
	row.add_child(status)


func _process(_delta: float) -> void:
	if not is_instance_valid(button): return
	button.disabled = not can_export()
	if PlayerData.is_online_battle():
		status.text = ""
		button.tooltip_text = Locale.t("battle.position_local_only")
	elif button.disabled:
		status.text = ""
		button.tooltip_text = Locale.t("battle.position_wait")
	else:
		status.text = _message
		button.tooltip_text = ""


func can_export() -> bool:
	return is_instance_valid(battle) and not PlayerData.is_online_battle() and battle.game.is_player_turn and not battle.practice_ai_running and not battle._resolution_running and battle._resolution_pending_steps == 0 and battle.current_attacker_idx == -1 and not battle.summon_targeting and not battle.activate_targeting and not battle.cast_targeting and not battle.parasite_targeting


func _choose_path() -> void:
	if not can_export(): return
	pending = Position.capture(battle.game, {"origin": "local_player", "phase": "between_actions", "mode": PlayerData.battle_mode})
	if not is_instance_valid(dialog):
		dialog = FileDialog.new()
		dialog.title = Locale.t("battle.save_position")
		dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		dialog.access = FileDialog.ACCESS_FILESYSTEM
		dialog.filters = PackedStringArray(["*.json ; Cardex position"])
		dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
		dialog.file_selected.connect(_save_to_path)
		dialog.canceled.connect(func(): pending.clear())
		add_child(dialog)
		UITheme.apply_dialog(dialog)
		# An embedded battle must keep its save modal in the same viewport.
		if battle.get_viewport() is SubViewport:
			dialog.use_native_dialog = false
	dialog.current_file = "cardex-turn-%d.json" % battle.game.turn_number
	dialog.popup_centered(Vector2i(battle.get_viewport_rect().size * Vector2(0.72, 0.72)))


func _save_to_path(path: String) -> void:
	if pending.is_empty(): return
	var error := Position.save(pending, path)
	_message = Locale.t("battle.position_saved") if error == OK else Locale.t("battle.position_failed")
	pending.clear()
