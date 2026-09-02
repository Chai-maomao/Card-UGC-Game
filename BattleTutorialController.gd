class_name BattleTutorialController
extends Node

const ProgressStore = preload("res://TutorialProgress.gd")

enum Phase {
	INTRO,
	HUD,
	SUMMON,
	SKILL,
	ATTACK_SOURCE,
	ATTACK_TARGET,
	END_TURN,
	COMPLETE,
}

var battle: Node
var phase: int = Phase.INTRO
var overlay_layer: CanvasLayer
var overlay_root: Control
var instruction_panel: PanelContainer
var step_label: Label
var title_label: Label
var body_label: Label
var next_button: Button
var skip_button: Button
var exit_button: Button
var focus_frames: Array[Panel] = []
var _panel_tween: Tween
var progress_path: String = ProgressStore.DEFAULT_PATH


static func configure_game(game) -> void:
	var rally_skill := {
		"skill_name": Locale.t("tutorial.card_skill"),
		"trigger": SkillEngine.TRIGGER_ON_SUMMON,
		"probability": 100,
		"effects": [{
			"target": SkillEngine.TARGET_SELF,
			"target_side": SkillEngine.TARGET_SIDE_ALLY,
			"effect": SkillEngine.EFFECT_SHIELD,
			"value": 2,
			"buff_id": "",
			"duration": 0,
			"random_count": 0,
			"probability": 100,
		}],
	}
	var trainee: CardData = PlayerData.tutorial_created_card.duplicate_card() if PlayerData.tutorial_created_card != null \
			else CardData.new(Locale.t("tutorial.card_name"), 1, 5, 2, [rally_skill])
	var target := CardData.new(Locale.t("tutorial.target_name"), 0, 6, 1, [])
	game.player_hand = [trainee]
	game.player2_hand = []
	game.player_field.slots = [null, null, null, null, null]
	game.player2_field.slots = [null, null, target, null, null]
	game.player_field.current_mana = 5
	game.player_field.max_mana = 10
	game.player2_field.current_mana = 5
	game.player2_field.max_mana = 10
	game.shared_deck = []
	for index in range(PlayerData.battle_deck.size()):
		# The tutorial card is already guaranteed in hand and must not appear a
		# second time in the shared draw pile.
		if PlayerData.tutorial_created_card != null and index == PlayerData.battle_deck.size() - 1:
			continue
		game.shared_deck.append((PlayerData.battle_deck[index] as CardData).duplicate_card())
	for opponent_card in PlayerData.opponent_battle_deck:
		game.shared_deck.append((opponent_card as CardData).duplicate_card())
	if game.shared_deck.is_empty():
		game.shared_deck = [CardData.new(Locale.t("tutorial.reserve_name"), 1, 3, 1, [])]
	game.shared_discard = []
	game.current_player = 1
	game.turn_number = 1
	game.is_player_turn = true
	game.first_switch = false
	game.allow_first_turn_attacks = true
	game.state_revision = 0


func start(owner_battle: Node) -> void:
	battle = owner_battle
	_build_ui()
	set_phase(Phase.INTRO)


func allows(action: String, context: Dictionary = {}) -> bool:
	var allowed := false
	match phase:
		Phase.SUMMON:
			allowed = action == "summon" and int(context.get("slot", -1)) == 2
		Phase.SKILL:
			allowed = action == "skill" and int(context.get("slot", -1)) == 2 and int(context.get("skill", -1)) == 0
		Phase.ATTACK_SOURCE:
			allowed = action == "attack_source" and int(context.get("slot", -1)) == 2
		Phase.ATTACK_TARGET:
			allowed = action == "attack_target" and int(context.get("slot", -1)) == 2
		Phase.END_TURN:
			allowed = action == "end_turn"
		_:
			allowed = false
	if not allowed:
		_remind()
	return allowed


func notify_action(action: String, _context: Dictionary = {}) -> void:
	match phase:
		Phase.SUMMON when action == "summon":
			set_phase(Phase.SKILL)
		Phase.SKILL when action == "skill":
			set_phase(Phase.ATTACK_SOURCE)
		Phase.ATTACK_SOURCE when action == "attack_source":
			set_phase(Phase.ATTACK_TARGET)
		Phase.ATTACK_TARGET when action == "attack_target":
			set_phase(Phase.END_TURN)
		Phase.END_TURN when action == "end_turn":
			ProgressStore.new(progress_path).mark_completed()
			set_phase(Phase.COMPLETE)


func set_phase(next_phase: int) -> void:
	phase = next_phase
	_clear_focus()
	var total := 7
	match phase:
		Phase.INTRO:
			_set_copy(1, "tutorial.intro_title", "tutorial.intro_body", true)
		Phase.HUD:
			_set_copy(2, "tutorial.hud_title", "tutorial.hud_body", true)
			_focus_controls([battle.player_status_hud, battle.enemy_status_hud])
		Phase.SUMMON:
			_set_copy(3, "tutorial.summon_title", "tutorial.summon_body")
			_focus_controls(_summon_focus_controls())
		Phase.SKILL:
			_set_copy(4, "tutorial.skill_title", "tutorial.skill_body")
			_focus_controls([battle._my_slots_ui()[2]])
		Phase.ATTACK_SOURCE:
			_set_copy(5, "tutorial.attack_title", "tutorial.attack_body")
			_focus_controls([battle._my_slots_ui()[2]])
		Phase.ATTACK_TARGET:
			_set_copy(5, "tutorial.target_title", "tutorial.target_body")
			_focus_controls([battle._their_slots_ui()[2]])
		Phase.END_TURN:
			_set_copy(6, "tutorial.end_title", "tutorial.end_body")
			_focus_controls([battle.end_turn_button])
		Phase.COMPLETE:
			_set_copy(total, "tutorial.complete_title", "tutorial.complete_body", true)
			next_button.text = Locale.t("tutorial.continue_battle")
			next_button.custom_minimum_size.x = 164
			skip_button.disabled = true
			skip_button.visible = false
			exit_button.text = Locale.t("tutorial.exit_tutorial")
			exit_button.custom_minimum_size.x = 96
	step_label.text = Locale.t("tutorial.step", [mini(phase + 1, total), total])
	_refresh_focus_deferred.call_deferred()


func _set_copy(_step: int, title_key: String, body_key: String, show_next: bool = false) -> void:
	title_label.text = Locale.t(title_key)
	body_label.text = Locale.t(body_key)
	next_button.visible = true
	next_button.disabled = not show_next
	next_button.text = Locale.t("tutorial.next") if show_next else Locale.t("tutorial.complete_action")
	next_button.custom_minimum_size.x = 104
	skip_button.visible = true
	skip_button.disabled = false
	skip_button.modulate.a = 1.0
	exit_button.visible = true
	exit_button.disabled = false
	exit_button.modulate.a = 1.0
	exit_button.text = Locale.t("tutorial.exit")
	exit_button.custom_minimum_size.x = 72


func _build_ui() -> void:
	overlay_layer = CanvasLayer.new()
	overlay_layer.layer = 90
	battle.add_child(overlay_layer)
	overlay_root = Control.new()
	overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_layer.add_child(overlay_root)

	instruction_panel = PanelContainer.new()
	instruction_panel.position = Vector2(18, 92)
	instruction_panel.custom_minimum_size = Vector2(300, 224)
	instruction_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	instruction_panel.z_index = 10
	UITheme.apply_panel(instruction_panel, "gold")
	overlay_root.add_child(instruction_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	instruction_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	margin.add_child(box)
	step_label = Label.new()
	step_label.add_theme_font_size_override("font_size", 12)
	UITheme.apply_label(step_label, true)
	box.add_child(step_label)
	title_label = Label.new()
	UITheme.apply_title(title_label, 21)
	box.add_child(title_label)
	body_label = Label.new()
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.custom_minimum_size = Vector2(268, 72)
	body_label.add_theme_font_size_override("font_size", 14)
	UITheme.apply_label(body_label)
	box.add_child(body_label)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	next_button = Button.new()
	next_button.text = Locale.t("tutorial.next")
	next_button.custom_minimum_size = Vector2(104, 38)
	next_button.clip_text = true
	UITheme.apply_button(next_button, "primary")
	next_button.pressed.connect(_on_next)
	buttons.add_child(next_button)
	skip_button = Button.new()
	skip_button.text = Locale.t("tutorial.skip")
	skip_button.custom_minimum_size = Vector2(104, 38)
	skip_button.clip_text = true
	UITheme.apply_button(skip_button, "secondary")
	skip_button.pressed.connect(_on_skip)
	buttons.add_child(skip_button)
	exit_button = Button.new()
	exit_button.text = Locale.t("tutorial.exit")
	exit_button.custom_minimum_size = Vector2(72, 38)
	exit_button.clip_text = true
	UITheme.apply_button(exit_button, "secondary")
	exit_button.pressed.connect(_on_exit)
	buttons.add_child(exit_button)
	UITheme.animate_popup_enter(instruction_panel)


func _on_next() -> void:
	if phase == Phase.INTRO:
		set_phase(Phase.HUD)
	elif phase == Phase.HUD:
		set_phase(Phase.SUMMON)
	elif phase == Phase.COMPLETE:
		_continue_battle()


func _on_skip() -> void:
	ProgressStore.new(progress_path).mark_skipped()
	_return_to_menu()


func _on_exit() -> void:
	_return_to_menu()


func _return_to_menu() -> void:
	PlayerData.clear_battle_preparation()
	UIMotion.replace_scene("res://MainMenu.tscn", true, "battle_hub")


func _continue_battle() -> void:
	PlayerData.battle_mode = "practice"
	PlayerData.battle_select_mode = "practice"
	if battle != null:
		battle.tutorial_controller = null
	if overlay_layer != null and is_instance_valid(overlay_layer):
		overlay_layer.queue_free()
	if battle != null and battle.game.current_player == 2:
		battle._start_practice_ai_turn.call_deferred()
	queue_free()


func _summon_focus_controls() -> Array:
	var controls: Array = [battle._my_slots_ui()[2]]
	if battle.hand_container.get_child_count() > 0:
		controls.append(battle.hand_container.get_child(0))
	return controls


func _focus_controls(controls: Array) -> void:
	for control in controls:
		if control is Control and is_instance_valid(control):
			var frame := Panel.new()
			frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0, 0, 0, 0)
			style.border_color = UITheme.COLOR_GOLD
			style.set_border_width_all(4)
			style.set_corner_radius_all(10)
			style.shadow_color = Color(UITheme.COLOR_GOLD.r, UITheme.COLOR_GOLD.g, UITheme.COLOR_GOLD.b, 0.38)
			style.shadow_size = 8
			frame.add_theme_stylebox_override("panel", style)
			overlay_root.add_child(frame)
			focus_frames.append(frame)
	_refresh_focus(controls)
	for frame in focus_frames:
		var pulse := frame.create_tween().set_loops()
		pulse.tween_property(frame, "modulate:a", 0.48, 0.55).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(frame, "modulate:a", 1.0, 0.55).set_trans(Tween.TRANS_SINE)


func _refresh_focus(controls: Array) -> void:
	for i in range(mini(controls.size(), focus_frames.size())):
		var control := controls[i] as Control
		var frame := focus_frames[i]
		frame.position = control.global_position - Vector2(6, 6)
		frame.size = control.size + Vector2(12, 12)


func _refresh_focus_deferred() -> void:
	await get_tree().process_frame
	match phase:
		Phase.HUD:
			_refresh_focus([battle.player_status_hud, battle.enemy_status_hud])
		Phase.SUMMON:
			_refresh_focus(_summon_focus_controls())
		Phase.SKILL, Phase.ATTACK_SOURCE:
			_refresh_focus([battle._my_slots_ui()[2]])
		Phase.ATTACK_TARGET:
			_refresh_focus([battle._their_slots_ui()[2]])
		Phase.END_TURN:
			_refresh_focus([battle.end_turn_button])


func _clear_focus() -> void:
	for frame in focus_frames:
		if is_instance_valid(frame):
			frame.queue_free()
	focus_frames.clear()


func _remind() -> void:
	if instruction_panel == null:
		return
	if _panel_tween and _panel_tween.is_valid():
		_panel_tween.kill()
	instruction_panel.pivot_offset = instruction_panel.size / 2
	_panel_tween = create_tween()
	_panel_tween.tween_property(instruction_panel, "scale", Vector2(1.035, 1.035), 0.08)
	_panel_tween.tween_property(instruction_panel, "scale", Vector2.ONE, 0.12)
