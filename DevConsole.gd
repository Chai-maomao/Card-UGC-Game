extends CanvasLayer

const COMMANDS := {
	"help": "help [command]  Show command usage.",
	"clear": "clear  Clear console output.",
	"fps": "fps  Show current frame rate and frame time.",
	"scene": "scene  Show the active scene and window size.",
	"battle": "battle  Show the current turn, pile counts and resources.",
	"give": "give <card name>  Add a copy of a card to your hand during local play.",
	"init": "init  Replay the first-launch tutorial.",
	"logging": "logging [on|off]  Show or change verbose gameplay logging for this session.",
	"system": "system  Show the local diagnostic summary.",
}
const OUTPUT_LIMIT := 180
const HISTORY_LIMIT := 60
const TEXT_COLOR := Color("#e5e9ed")
const MUTED_COLOR := Color("#a4b2bc")
const ACCENT_COLOR := Color("#f2c883")
const ERROR_COLOR := Color("#ff9e91")

var _surface: ColorRect
var _panel: PanelContainer
var _output: RichTextLabel
var _line: LineEdit
var _previous_focus: WeakRef
var _expanded := false
var _messages: Array[Dictionary] = []
var _history: Array[String] = []
var _history_index := 0
var _draft := ""
var _tutorial_preview_path := ""


func _ready() -> void:
	if not OS.is_debug_build() or DisplayServer.get_name() == "headless":
		set_process_input(false)
		set_process_shortcut_input(false)
		return
	var args := OS.get_cmdline_user_args()
	if args.has("--server") or args.has("--room-server"):
		set_process_input(false)
		set_process_shortcut_input(false)
		return

	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 1280
	_build_console()
	hide()
	get_tree().scene_changed.connect(_on_scene_changed)


func is_open() -> bool:
	return _surface != null and visible


func _exit_tree() -> void:
	if not _tutorial_preview_path.is_empty():
		TutorialProgress.new(_tutorial_preview_path).clear()


func _build_console() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Cascadia Mono", "Consolas", "Menlo", "DejaVu Sans Mono", "monospace"])
	var terminal_theme := Theme.new()
	terminal_theme.default_font = font
	terminal_theme.default_font_size = 15

	# Catch clicks on the rest of the game while the terminal has focus.
	_surface = ColorRect.new()
	_surface.color = Color(0.03, 0.04, 0.05, 0.25)
	_surface.mouse_force_pass_scroll_events = false
	add_child(_surface)
	_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_panel = PanelContainer.new()
	_panel.theme = terminal_theme
	_panel.add_theme_stylebox_override("panel", _terminal_style(Color(0.06, 0.075, 0.09, 0.96), Color("#59636b"), 0))
	_surface.add_child(_panel)
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 0.47

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 0)
	_panel.add_child(rows)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "DEVELOPER CONSOLE"
	title.set_meta("keyword_literal", true)
	title.add_theme_color_override("font_color", ACCENT_COLOR)
	header.add_child(title)
	var shortcuts := Label.new()
	shortcuts.text = "TAB Complete   ↑↓ History   F11 Expand   ESC Close"
	shortcuts.set_meta("keyword_literal", true)
	shortcuts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shortcuts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	shortcuts.add_theme_font_size_override("font_size", 13)
	shortcuts.add_theme_color_override("font_color", MUTED_COLOR)
	shortcuts.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(shortcuts)
	_add_row(rows, header, Color("#1b252d"), 7)

	_output = RichTextLabel.new()
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.scroll_following = true
	_output.selection_enabled = true
	_output.mouse_force_pass_scroll_events = false
	_output.add_theme_color_override("default_color", TEXT_COLOR)
	_output.add_theme_stylebox_override("normal", _terminal_style(Color.TRANSPARENT, Color.TRANSPARENT, 9))
	rows.add_child(_output)

	var prompt_row := HBoxContainer.new()
	prompt_row.add_theme_constant_override("separation", 8)
	var prompt := Label.new()
	prompt.text = ">"
	prompt.add_theme_color_override("font_color", ACCENT_COLOR)
	prompt_row.add_child(prompt)
	_line = LineEdit.new()
	_line.name = "CommandLine"
	_line.placeholder_text = "Type help"
	_line.context_menu_enabled = false
	_line.keep_editing_on_text_submit = true
	_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line.max_length = 256
	_line.caret_blink = true
	_line.add_theme_color_override("font_color", TEXT_COLOR)
	_line.add_theme_color_override("font_placeholder_color", MUTED_COLOR)
	_line.add_theme_color_override("caret_color", ACCENT_COLOR)
	for state in ["normal", "focus"]:
		_line.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_line.text_submitted.connect(_submit)
	prompt_row.add_child(_line)
	_add_row(rows, prompt_row, Color("#151e25"), 9)


func _add_row(parent: VBoxContainer, content: Control, color: Color, padding: int) -> void:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _terminal_style(color, Color.TRANSPARENT, padding))
	parent.add_child(row)
	row.add_child(content)


func _terminal_style(color: Color, divider: Color, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = divider
	style.border_width_bottom = 1
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style


func _on_scene_changed() -> void:
	# Godot visits the last root branch first when dispatching input.
	get_parent().move_child(self, -1)
	if is_open():
		_line.grab_focus.call_deferred()


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null:
		return
	var toggle := not (key.ctrl_pressed or key.alt_pressed or key.meta_pressed) and (
		key.physical_keycode == KEY_QUOTELEFT or key.keycode == KEY_QUOTELEFT
		or key.keycode == KEY_ASCIITILDE or key.unicode in [0x60, 0x7e, 0xb7, 0xff5e]
	)
	if toggle and (is_open() or not UIMotion.key_capture.is_valid()):
		get_viewport().set_input_as_handled()
		if key.pressed and not key.echo:
			_toggle_console()
		return
	if not is_open():
		return
	match key.keycode:
		KEY_ESCAPE, KEY_F11, KEY_TAB, KEY_UP, KEY_DOWN:
			get_viewport().set_input_as_handled()
		_:
			return
	if not key.pressed:
		return
	match key.keycode:
		KEY_ESCAPE:
			if not key.echo:
				_toggle_console()
		KEY_F11:
			if not key.echo:
				_expanded = not _expanded
				_panel.anchor_bottom = 1.0 if _expanded else 0.47
		KEY_TAB:
			if not key.echo:
				_complete()
		KEY_UP:
			_recall(-1)
		KEY_DOWN:
			_recall(1)


func _shortcut_input(event: InputEvent) -> void:
	if is_open() and event is InputEventKey:
		get_viewport().set_input_as_handled()


func _toggle_console() -> void:
	if is_open():
		hide()
		var focus: Control = _previous_focus.get_ref() if _previous_focus != null else null
		if is_instance_valid(focus) and focus.is_visible_in_tree():
			focus.grab_focus()
		_previous_focus = null
		return
	var focus := get_viewport().gui_get_focus_owner()
	_previous_focus = weakref(focus) if focus != null else null
	if get_viewport().gui_is_dragging():
		get_viewport().gui_cancel_drag()
	show()
	_line.grab_focus()


func _recall(direction: int) -> void:
	if _history_index == _history.size():
		_draft = _line.text
	_history_index = clampi(_history_index + direction, 0, _history.size())
	_set_input_text(_draft if _history_index == _history.size() else _history[_history_index])


func _set_input_text(value: String) -> void:
	_line.text = value
	_line.caret_column = value.length()


func _complete() -> void:
	var prefix := _line.text.strip_edges().to_lower()
	if " " in prefix:
		return
	var matches := PackedStringArray()
	for command in COMMANDS:
		if command.begins_with(prefix):
			matches.append(command)
	if matches.size() == 1:
		_set_input_text(matches[0])
	elif matches.size() > 1:
		_print_line("  ".join(matches), MUTED_COLOR)


func _submit(value: String) -> void:
	var command_line := value.strip_edges()
	_line.clear()
	if command_line.is_empty():
		return
	if _history.is_empty() or _history.back() != command_line:
		_history.append(command_line)
		if _history.size() > HISTORY_LIMIT:
			_history.pop_front()
	_history_index = _history.size()
	_draft = ""
	_print_line("> " + command_line, ACCENT_COLOR)
	var args := command_line.replace("\t", " ").split(" ", false)
	var command := args[0].to_lower()
	if not COMMANDS.has(command):
		_print_line("Unknown command. Type help.", ERROR_COLOR)
		return
	var accepts_argument := command in ["help", "logging"]
	if command != "give" and args.size() > (2 if accepts_argument else 1):
		_print_line(COMMANDS[command], ERROR_COLOR)
		return
	var argument := args[1].to_lower() if args.size() == 2 else ""
	match command:
		"help":
			if argument.is_empty():
				_print_line("\n".join(PackedStringArray(COMMANDS.values())))
			elif COMMANDS.has(argument):
				_print_line(COMMANDS[argument])
			else:
				_print_line("Unknown command: " + argument, ERROR_COLOR)
		"clear":
			_messages.clear()
			_output.clear()
		"fps":
			var fps := Engine.get_frames_per_second()
			var milliseconds := 1000.0 / fps if fps > 0 else 0.0
			_print_line("%d FPS (%.1f ms per frame)" % [fps, milliseconds])
		"scene":
			var scene := get_tree().current_scene
			var path := scene.scene_file_path if scene != null else "(transitioning)"
			_print_line("Scene %s, window %s" % [path, get_window().size])
		"battle":
			_print_battle()
		"give":
			_give_card(command_line.substr(args[0].length()).strip_edges())
		"init":
			_start_tutorial_preview()
		"logging":
			_set_gameplay_logging(argument)
		"system":
			_print_line(AppDiagnostics.summary())


func _set_gameplay_logging(argument: String) -> void:
	if argument in ["on", "off"]:
		ProjectSettings.set_setting(GameplayLog.SETTING, argument == "on")
	elif not argument.is_empty():
		_print_line(COMMANDS["logging"], ERROR_COLOR)
		return
	_print_line("Verbose gameplay logging: " + ("on" if GameplayLog.is_enabled() else "off"))


func _print_battle() -> void:
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path != "res://Main.tscn":
		_print_line("Start a battle to use this command.", ERROR_COLOR)
		return
	var game: RefCounted = scene.get("game")
	if game == null or game.player_field == null or game.player2_field == null:
		_print_line("Battle is initializing.", ERROR_COLOR)
		return
	_print_line("Turn %d, P%d to act. Deck: %d cards. Discard: %d cards." % [
		game.turn_number, game.current_player, game.shared_deck.size(), game.shared_discard.size(),
	])
	var fields: Array[BattleField] = [game.player_field, game.player2_field]
	for index in fields.size():
		var field := fields[index]
		_print_line("P%d    HP %d/%d    Elixir %d/%d (+%d temporary)    AP %d/%d" % [
			index + 1, field.player_hp, field.max_player_hp, field.current_mana,
			field.max_mana, field.temp_mana, field.action_points, field.action_budget,
		])


func _give_card(card_name: String) -> void:
	if card_name.is_empty():
		_print_line(COMMANDS["give"], ERROR_COLOR)
		return
	var battle := get_tree().current_scene
	if battle == null or battle.scene_file_path != "res://Main.tscn" or PlayerData.is_online_battle():
		_print_line("Start a local battle to use give.", ERROR_COLOR)
		return
	var game: RefCounted = battle.get("game")
	if game == null or not battle.is_my_turn() or UIMotion.is_transitioning():
		_print_line("Use give during your turn when the battle is ready.", ERROR_COLOR)
		return
	if battle._my_hand().size() >= SkillEngine.MAX_HAND_SIZE:
		_print_line(Locale.t("tip.hand_full", [SkillEngine.MAX_HAND_SIZE]), ERROR_COLOR)
		return
	var template := _find_card_template(card_name)
	if template == null:
		_print_line(Locale.t("battle.debug_card_not_found", [card_name]), ERROR_COLOR)
		return
	var card := PlayerData.prepare_deck_card(template)
	card.reset_to_base()
	var destination: String = game.resolve_hand_entry_for_player(card, "generated", {}, battle._view_player())
	battle._refresh_hand_ui()
	battle.update_entire_screen()
	if destination == "hand":
		var message := Locale.t("battle.debug_card_acquired", [card.card_name])
		battle._show_combat_broadcast(message)
		_print_line(message)
	else:
		_print_line(Locale.t("tip.hand_overflow", [card.card_name]), ERROR_COLOR)


func _find_card_template(card_name: String) -> CardData:
	for pool in [PlayerData.card_library, PlayerData.battle_deck, PlayerData.opponent_battle_deck]:
		for card: CardData in pool:
			if card.card_name.nocasecmp_to(card_name) == 0:
				return card
	for card: CardData in CardDatabase.beginner_deck():
		if card.card_name.nocasecmp_to(card_name) == 0:
			return card
	return null


func _start_tutorial_preview() -> void:
	if NetworkManager.is_online or UIMotion.is_transitioning():
		_print_line("Use init offline when the current screen is ready.", ERROR_COLOR)
		return
	var path := "user://debug_first_launch_%d.cfg" % OS.get_process_id()
	var progress := TutorialProgress.new(path)
	var error := progress.clear()
	if error == OK:
		error = progress.initialize_startup(false)
	if error != OK:
		_print_line("Could not start the tutorial preview (error %d)." % error, ERROR_COLOR)
		return
	_tutorial_preview_path = path
	PlayerData.tutorial_progress_path = path
	PlayerData.cancel_skill_tutorial()
	PlayerData.restore_after_card_playtest()
	PlayerData.startup_tutorial_pending = true
	_print_line("Starting the first-launch tutorial.")
	_toggle_console()
	UIMotion.replace_scene("res://MainMenu.tscn", true)


func _print_line(message: String, color := TEXT_COLOR) -> void:
	var entry := {"text": message, "color": color}
	_messages.append(entry)
	if _messages.size() > OUTPUT_LIMIT:
		_messages.pop_front()
		_output.clear()
		for item in _messages:
			_append_output(item)
	else:
		_append_output(entry)


func _append_output(entry: Dictionary) -> void:
	_output.push_color(entry.color)
	_output.add_text(entry.text + "\n")
	_output.pop()
