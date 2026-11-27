class_name BattleTutorialController
extends Node

const ProgressStore = preload("res://TutorialProgress.gd")

enum Phase {
	INTRO,
	HUD,
	BOARD,
	HAND,
	RESOURCES,
	ACTIONS,
	SUMMON,
	SKILL,
	CARD_STATS,
	ATTACK_SOURCE,
	ATTACK_TARGET,
	COMBAT_RESULT,
	FACE_DAMAGE,
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
var progress_path: String = PlayerData.tutorial_progress_path
var _attack_target_hp := 0
var _attack_payment: Dictionary = {}


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
	# This sandbox replaces the opening hand/board after init_game. Quote its
	# actual opening layout, rather than retaining the starter-deck budget.
	game.reset_action_budget(1)
	game.reset_action_budget(2)


func start(owner_battle: Node) -> void:
	battle = owner_battle
	_build_ui()
	set_phase(Phase.INTRO)


func allows(action: String, context: Dictionary = {}) -> bool:
	var allowed := false
	match phase:
		Phase.SUMMON:
			allowed = action == "summon" and int(context.get("slot", -1)) == 2
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
	elif phase == Phase.ATTACK_TARGET:
		var target: CardData = battle.game.player2_field.slots[2]
		_attack_target_hp = target.hp if target != null else 0
		_attack_payment = battle.game.next_action_payment().duplicate()
	return allowed


func notify_action(action: String, _context: Dictionary = {}) -> void:
	match phase:
		Phase.SUMMON when action == "summon":
			set_phase(Phase.SKILL)
		Phase.ATTACK_SOURCE when action == "attack_source":
			set_phase(Phase.ATTACK_TARGET)
		Phase.ATTACK_TARGET when action == "attack_target":
			set_phase(Phase.COMBAT_RESULT)
		Phase.END_TURN when action == "end_turn":
			ProgressStore.new(progress_path).mark_completed()
			set_phase(Phase.COMPLETE)


func set_phase(next_phase: int) -> void:
	phase = next_phase
	_clear_focus()
	var total := Phase.size()
	match phase:
		Phase.INTRO:
			_set_copy(1, "tutorial.intro_title", "tutorial.intro_body", true)
		Phase.HUD:
			_set_copy(2, "tutorial.hud_title", "tutorial.hud_body", true)
		Phase.BOARD:
			_set_copy(3, "tutorial.board_title", "tutorial.board_body", true)
		Phase.HAND:
			_set_copy(4, "tutorial.hand_title", "tutorial.hand_body", true, [SkillEngine.MAX_HAND_SIZE])
		Phase.RESOURCES:
			_set_copy(5, "tutorial.resources_title", "tutorial.resources_body", true)
		Phase.ACTIONS:
			var config: Dictionary = battle.game.battle_config
			if config.has("action_base"):
				_set_copy(6, "tutorial.actions_title", "tutorial.actions_body", true, [str(config.get("action_base", 3)), str(config.get("action_empty_slot_factor", 1)), str(config.get("action_empty_hand_factor", 0.5)), str(config.get("action_mana_factor", 1))])
			else:
				_set_copy(6, "tutorial.actions_title", "tutorial.actions_legacy_body", true)
		Phase.SUMMON:
			var card: CardData = battle.game.player_hand[0]
			_set_copy(7, "tutorial.summon_title", "tutorial.summon_body", false, [card.cost, battle.game.player_field.get_total_mana()])
		Phase.SKILL:
			_set_copy(8, "tutorial.skill_title", "tutorial.skill_body", true)
		Phase.CARD_STATS:
			var card: CardData = battle.game.player_field.slots[2]
			_set_copy(9, "tutorial.stats_title", "tutorial.stats_body", true, [card.cost, card.hp, card.effective_atk()])
		Phase.ATTACK_SOURCE:
			_set_copy(10, "tutorial.attack_title", "tutorial.attack_body")
		Phase.ATTACK_TARGET:
			_set_copy(11, "tutorial.target_title", "tutorial.target_body")
		Phase.COMBAT_RESULT:
			var target: CardData = battle.game.player2_field.slots[2]
			_set_copy(12, "tutorial.result_title", "tutorial.result_body", true, [_attack_target_hp, target.hp if target != null else 0, int(_attack_payment.get("points", 0)), int(_attack_payment.get("mana", 0)), int(battle.game.next_action_payment().cost)])
		Phase.FACE_DAMAGE:
			_set_copy(13, "tutorial.face_title", "tutorial.face_body", true)
		Phase.END_TURN:
			_set_copy(14, "tutorial.end_title", "tutorial.end_body", false, [int(battle.game.battle_config.get("mana_per_turn", PlayerData.DEFAULT_BATTLE_CONFIG["mana_per_turn"])), int(battle.game.battle_config.get("draw_per_turn", 2))])
		Phase.COMPLETE:
			_set_copy(total, "tutorial.complete_title", "tutorial.complete_body", true)
			next_button.text = Locale.t("tutorial.continue_battle")
			next_button.custom_minimum_size.x = 164
			skip_button.disabled = true
			skip_button.visible = false
			exit_button.text = Locale.t("tutorial.exit_tutorial")
			exit_button.custom_minimum_size.x = 96
	_focus_controls(_phase_focus_controls())
	step_label.text = Locale.t("tutorial.step", [phase + 1, total])
	_refresh_focus_deferred.call_deferred()


func _set_copy(_step: int, title_key: String, body_key: String, show_next: bool = false, args: Array = []) -> void:
	title_label.text = Locale.t(title_key)
	body_label.text = Locale.t(body_key, args)
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
	overlay_layer.set_meta("popup_close", _on_exit)
	overlay_layer.tree_entered.connect(_resume_focus_updates)
	overlay_layer.tree_exiting.connect(_stop_focus_updates)
	battle.add_child(overlay_layer)
	overlay_root = Control.new()
	overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_layer.add_child(overlay_root)

	instruction_panel = PanelContainer.new()
	instruction_panel.custom_minimum_size = Vector2(740, 0)
	instruction_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	instruction_panel.z_index = 10
	UITheme.apply_popup_frame(instruction_panel, "gold", false, true)
	overlay_root.add_child(instruction_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		# The shared panel style already supplies padding.
		margin.add_theme_constant_override("margin_%s" % side, 6)
	instruction_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	margin.add_child(box)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 14)
	box.add_child(heading)
	step_label = Label.new()
	step_label.add_theme_font_size_override("font_size", 12)
	UITheme.apply_label(step_label, true)
	heading.add_child(step_label)
	title_label = Label.new()
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.apply_title(title_label, 20)
	heading.add_child(title_label)
	body_label = Label.new()
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.custom_minimum_size.y = 48
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
	_position_panel()
	UITheme.animate_popup_enter(instruction_panel)


func _on_next() -> void:
	if phase in [Phase.INTRO, Phase.HUD, Phase.BOARD, Phase.HAND, Phase.RESOURCES, Phase.ACTIONS, Phase.SKILL, Phase.CARD_STATS, Phase.COMBAT_RESULT, Phase.FACE_DAMAGE]:
		set_phase(phase + 1)
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


func _phase_focus_controls() -> Array:
	var content: Node = battle.player_status_hud.get_node("Margin/Content")
	match phase:
		Phase.HUD:
			return [content.get_node("HpBar"), battle.enemy_status_hud.get_node("Margin/Content/HpBar")]
		Phase.BOARD:
			return battle._my_slots_ui() + battle._their_slots_ui()
		Phase.HAND:
			return [battle.hand_area, battle.draw_pile_btn, battle.discard_zone]
		Phase.RESOURCES:
			return [content.get_node("ManaBar"), content.get_node("ActionBar")] if battle.game.battle_config.has("action_base") else [content.get_node("ManaBar")]
		Phase.ACTIONS:
			return [content.get_node("HandLabel"), content.get_node("ActionBar")] if battle.game.battle_config.has("action_base") else [battle.player_status_hud]
		Phase.SUMMON:
			return _summon_focus_controls()
		Phase.SKILL:
			return [battle._my_slots_ui()[2], battle.hand_area]
		Phase.CARD_STATS:
			if battle.get("tabletop") != null:
				return [battle._my_slots_ui()[2]]
			var card_ui = battle._my_slots_ui()[2].current_card_ui
			return [card_ui.cost_label, card_ui.hp_label, card_ui.atk_label] if card_ui != null else []
		Phase.ATTACK_SOURCE:
			return [battle._my_slots_ui()[2]]
		Phase.ATTACK_TARGET:
			return [battle._their_slots_ui()[2]]
		Phase.COMBAT_RESULT:
			return [battle._their_slots_ui()[2]]
		Phase.FACE_DAMAGE:
			return battle._their_slots_ui() + [battle.enemy_status_hud.get_node("Margin/Content/HpBar")]
		Phase.END_TURN:
			return [battle.end_turn_button]
	return []


func _position_panel() -> void:
	var viewport_size: Vector2 = battle.get_viewport_rect().size
	var compact := viewport_size.y <= 540.0 and phase in [Phase.SUMMON, Phase.SKILL]
	var body_min_height := 30.0 if compact else 48.0
	if body_label.custom_minimum_size.y != body_min_height:
		body_label.custom_minimum_size.y = body_min_height
		var box := body_label.get_parent() as VBoxContainer
		box.add_theme_constant_override("separation", 6 if compact else 9)
		var margin := box.get_parent() as MarginContainer
		margin.add_theme_constant_override("margin_top", 4 if compact else 6)
		margin.add_theme_constant_override("margin_bottom", 4 if compact else 6)
	var width := minf(900, viewport_size.x - 32)
	instruction_panel.custom_minimum_size.x = width
	instruction_panel.size.x = width
	instruction_panel.size.y = instruction_panel.get_combined_minimum_size().y
	var y: float = viewport_size.y - instruction_panel.size.y - 14
	if phase in [Phase.HUD, Phase.HAND, Phase.RESOURCES, Phase.ACTIONS, Phase.SUMMON, Phase.SKILL]:
		y = minf(44, y)
	instruction_panel.position = Vector2((viewport_size.x - width) / 2, maxf(14, y))


func _process(_delta: float) -> void:
	if is_instance_valid(battle) and is_instance_valid(instruction_panel):
		_position_panel()
		_refresh_focus(_phase_focus_controls())


func _stop_focus_updates() -> void:
	set_process(false)
	_clear_focus()


func _resume_focus_updates() -> void:
	set_process(true)
	if is_instance_valid(instruction_panel):
		_focus_controls(_phase_focus_controls())


func _focus_controls(controls: Array) -> void:
	for control in controls:
		if control is Control and is_instance_valid(control):
			var frame := preload("res://presentation/TutorialFocusFrame.gd").new()
			frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var style := StyleBoxFlat.new()
			style.bg_color = Color.TRANSPARENT
			style.border_color = UITheme.COLOR_GOLD
			# Compact stat rows need a fine outline outside their text bounds.
			style.set_border_width_all(1 if phase == Phase.CARD_STATS else 4)
			style.set_corner_radius_all(2 if phase == Phase.CARD_STATS else 10)
			# A StyleBox shadow also fills the transparent interior, obscuring the
			# board. Keep the outline clear so players can read the real card face.
			style.shadow_size = 0
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
		var table: Node = battle.get("tabletop")
		var slot_key: int = battle._my_slots_ui().find(control)
		if slot_key < 0:
			var far: int = battle._their_slots_ui().find(control)
			if far >= 0: slot_key = far + 5
		if slot_key < 0 and table != null:
			var hand_index: int = battle.hand_container.get_children().find(control)
			if hand_index >= 0: slot_key = 10+hand_index
		if table != null and slot_key >= 0:
			var points: PackedVector2Array = table.projected_slot_corners(slot_key)
			if points.is_empty(): frame.hide(); continue
			var bounds := Rect2(points[0],Vector2.ZERO)
			for point in points: bounds = bounds.expand(point)
			frame.position = bounds.position
			frame.size = bounds.size
			for j in range(points.size()): points[j] -= bounds.position
			frame.set("polygon",points)
			(frame.get_theme_stylebox("panel") as StyleBoxFlat).set_border_width_all(0)
			frame.visible = control.is_visible_in_tree()
			frame.queue_redraw()
			continue
		var bounds := control.get_global_rect().grow(1.0 if phase == Phase.CARD_STATS else 6.0)
		if phase == Phase.CARD_STATS:
			# Font minimum heights leave less than one pixel between these rows.
			# Keep the vertical bounds intact while outlining the horizontal rim.
			bounds.position.y = control.global_position.y
			bounds.size.y = control.get_global_rect().size.y
		# The hand area can extend below the viewport to make room for the card fan.
		bounds = bounds.intersection(battle.get_viewport().get_visible_rect().grow(-2.0))
		frame.position = bounds.position
		frame.size = bounds.size
		frame.visible = control.is_visible_in_tree() and control.size.x > 1 and control.size.y > 1 and bounds.has_area()


func _refresh_focus_deferred() -> void:
	await get_tree().process_frame
	_refresh_focus(_phase_focus_controls())


func _clear_focus() -> void:
	for frame in focus_frames:
		if is_instance_valid(frame):
			frame.queue_free()
	focus_frames.clear()


func _remind() -> void:
	if not is_instance_valid(instruction_panel):
		return
	if _panel_tween and _panel_tween.is_valid():
		_panel_tween.kill()
	instruction_panel.pivot_offset = instruction_panel.size / 2
	_panel_tween = create_tween()
	_panel_tween.tween_property(instruction_panel, "scale", Vector2(1.035, 1.035), 0.08)
	_panel_tween.tween_property(instruction_panel, "scale", Vector2.ONE, 0.12)
