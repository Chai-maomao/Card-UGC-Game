extends Node2D

# ============================================
# Main --- 2P hotseat UI
# ============================================

var game
var current_attacker_idx: int = -1
var summon_targeting: bool = false
var summon_source_slot: int = -1
var activate_targeting: bool = false
var activate_source_slot: int = -1
var cast_targeting: bool = false
var cast_hand_index: int = -1
var cast_skill_index: int = -1
var parasite_targeting: bool = false
var parasite_hand_index: int = -1
var summon_skill_idx: int = -1
var activate_skill_idx: int = -1
var card_ui_scene = preload("res://CardUI.tscn")
const UITheme = preload("res://UITheme.gd")
const SpellRules = preload("res://SpellRules.gd")
const ParasiteRules = preload("res://ParasiteRules.gd")
const _TargetResolver = preload("res://SkillTargetResolver.gd")
const TutorialController = preload("res://BattleTutorialController.gd")

@onready var enemy_side_ui = $CanvasLayer/MainBackground/MainLayout/EnemySide
@onready var player_side_ui = $CanvasLayer/MainBackground/MainLayout/PlayerSide
@onready var turn_label = $CanvasLayer/MainBackground/MainLayout/MiddleInfoBar/InfoHBox/TurnLabel
@onready var end_turn_button = $CanvasLayer/MainBackground/MainLayout/MiddleInfoBar/InfoHBox/EndTurnButton
@onready var attack_arrow = $CanvasLayer/AttackArrow
@onready var bottom_dock = $CanvasLayer/MainBackground/MainLayout/BottomDockMargin/BottomDock
@onready var pile_column = $CanvasLayer/MainBackground/MainLayout/BottomDockMargin/BottomDock/PileColumn
@onready var hand_area = $CanvasLayer/MainBackground/MainLayout/BottomDockMargin/BottomDock/HandArea
@onready var hand_content = $CanvasLayer/MainBackground/MainLayout/BottomDockMargin/BottomDock/HandArea/HandContent
@onready var hand_container = $CanvasLayer/MainBackground/MainLayout/BottomDockMargin/BottomDock/HandArea/HandContent/HandScroll/HandContainer
@onready var splash_panel = $CanvasLayer/SplashPanel
@onready var splash_art = $CanvasLayer/SplashPanel/SplashArt
@onready var splash_name = $CanvasLayer/SplashPanel/SplashName
@onready var splash_text = $CanvasLayer/SplashPanel/SplashText
@onready var discard_column = $CanvasLayer/MainBackground/MainLayout/BottomDockMargin/BottomDock/DiscardColumn
@onready var discard_zone = $CanvasLayer/MainBackground/MainLayout/BottomDockMargin/BottomDock/DiscardColumn/DiscardZone
@onready var enemy_status_hud = $CanvasLayer/MainBackground/MainLayout/EnemyStatusRow/EnemyStatusHUD
@onready var player_status_hud = $CanvasLayer/MainBackground/MainLayout/PlayerStatusRow/PlayerStatusHUD

var splash_tween: Tween
var turn_cover: ColorRect
var turn_wait_hint: Panel
var draw_pile_btn: Button
var discard_pile_btn: Button
var debug_state_btn: Button
var help_btn: Button
var toast_stack: VBoxContainer
var action_log_button: Button
var abandon_battle_button: Button
var action_log_panel: PanelContainer
var action_log_text: RichTextLabel
var _action_log_entries: Array = []
var _battle_started_at: float = 0.0
var reconnect_leave_button: Button
var _reconnect_elapsed_seconds: int = 0
var _reconnect_attempt: int = 0
var _history_recorded: bool = false
var practice_ai_running: bool = false
var battle_finished: bool = false
var _turn_ending: bool = false  # 防止短时间内重复点击结束按钮
var _pending_feedback_events: Array = []
var _action_broadcast: Dictionary = {}
var _action_hp_events: Array = []
var _action_damage_events: Array = []
var _action_parasite_events: Array = []
var _action_failed_events: Array = []
var _end_turn_pulse: Tween = null
var _turn_pop_tween: Tween = null
var _turn_last_text: String = ""
var my_player: int = 0
var remote_arrow_source: int = -1
var remote_arrow_target: int = -1
var last_hovered_target: int = -1
var _charm_popup_active: bool = false
var _pending_hp_events: Array = []
var match_paused: bool = false
var _resume_waiting_for_player: int = 0
var _resume_expected_revision: int = -1
var _local_slot_rejoined: bool = false
var _resume_nonce: String = ""
var _resume_waiting_nonce: String = ""
var _resume_deadline: float = 0.0
var _resume_next_request_at: float = 0.0
var _resume_request_count: int = 0
var _screen_refresh_queued: bool = false
var _network_command_phase: String = ""
var tutorial_controller: BattleTutorialController
var _last_pile_counts := Vector2i(-1, -1)
const BASE_VIEWPORT_SIZE := Vector2(1152, 648)
const BASE_CARD_SIZE := Vector2(120, 160)
const BASE_SLOT_SIZE := BASE_CARD_SIZE
const BASE_PILE_BUTTON_SIZE := Vector2(112, 44)
const BASE_DEBUG_BUTTON_SIZE := Vector2(130, 50)
const BASE_HELP_BUTTON_SIZE := Vector2(90, 38)
const RESUME_SYNC_TIMEOUT := 15.0
const RESUME_REQUEST_INTERVAL := 1.5
const RESUME_MAX_REQUESTS := 8


func _ui_scale() -> float:
	var size := get_viewport_rect().size
	if size.x <= 0 or size.y <= 0:
		return 1.0
	return min(size.x / BASE_VIEWPORT_SIZE.x, size.y / BASE_VIEWPORT_SIZE.y)


func _scale_control(control: Control, base_size: Vector2) -> void:
	if control == null:
		return
	var s := _ui_scale()
	if control.has_method("apply_ui_scale"):
		control.call("apply_ui_scale", s)
		return
	var scaled := base_size * s
	control.custom_minimum_size = scaled
	control.size = scaled


func _apply_theme() -> void:
	UITheme.apply_panel($CanvasLayer/MainBackground, "battle")
	UITheme.apply_panel($CanvasLayer/MainBackground/MainLayout/MiddleInfoBar, "gold")
	UITheme.apply_panel(hand_area.get_node("HandBackdrop"), "hand")
	UITheme.apply_panel(discard_zone, "dark")
	UITheme.apply_panel(splash_panel, "gold")
	UITheme.apply_label(turn_label)
	_apply_status_hud_theme(enemy_status_hud, true, false)
	_apply_status_hud_theme(player_status_hud, false, false)
	# End-turn gets its own attention pulse, so skip the generic hover hook.
	UITheme.apply_button(end_turn_button, "primary", false)
	for btn in [draw_pile_btn, discard_pile_btn, debug_state_btn, help_btn]:
		UITheme.apply_button(btn, "secondary")
	var discard_label := discard_zone.get_node("DiscardLabel")
	UITheme.apply_label(discard_label)
	UITheme.apply_title(splash_name, 18)
	UITheme.apply_label(splash_text)


func _apply_status_hud_theme(hud: Panel, enemy: bool, active: bool) -> void:
	if hud == null:
		return
	var faction_color: Color = UITheme.COLOR_ENEMY if enemy else UITheme.COLOR_PLAYER
	var border_color: Color = UITheme.COLOR_GOLD if active else faction_color
	var fill_color := Color(0.105, 0.045, 0.08, 0.94) if enemy else Color(0.025, 0.095, 0.14, 0.94)
	var glow := Color(border_color.r, border_color.g, border_color.b, 0.30 if active else 0.12)
	hud.add_theme_stylebox_override("panel", UITheme.panel_style(
		fill_color, border_color, 2 if active else 1, 9, glow, 4 if active else 2
	))

	var content := hud.get_node("Margin/Content") as HBoxContainer
	var side_label := content.get_node("SideLabel") as Label
	var hp_label := content.get_node("HpLabel") as Label
	var mana_value_label := content.get_node("ManaLabel") as Label
	var hand_label := content.get_node("HandLabel") as Label
	for label in [side_label, hp_label, mana_value_label, hand_label]:
		UITheme.apply_label(label)
	side_label.add_theme_color_override("font_color", border_color.lightened(0.22))
	hp_label.add_theme_color_override("font_color", Color(1.0, 0.50, 0.48))
	mana_value_label.add_theme_color_override("font_color", Color(0.40, 0.86, 1.0))
	hand_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)

	var hp_bar := content.get_node("HpBar") as ProgressBar
	var mana_bar := content.get_node("ManaBar") as ProgressBar
	_style_status_bar(hp_bar, Color(0.88, 0.24, 0.24))
	_style_status_bar(mana_bar, Color(0.20, 0.72, 0.88))


func _style_status_bar(bar: ProgressBar, fill_color: Color) -> void:
	if bar == null:
		return
	bar.add_theme_stylebox_override("background", UITheme.panel_style(
		Color(0.025, 0.03, 0.045, 0.90), Color(0.20, 0.24, 0.31, 0.85), 1, 7
	))
	bar.add_theme_stylebox_override("fill", UITheme.panel_style(
		fill_color, fill_color.lightened(0.20), 1, 7
	))


func _scale_status_hud(hud: Panel, scale_value: float) -> void:
	if hud == null:
		return
	hud.custom_minimum_size = Vector2(720, 38) * scale_value
	var margin := hud.get_node("Margin") as MarginContainer
	margin.add_theme_constant_override("margin_left", max(7, int(14 * scale_value)))
	margin.add_theme_constant_override("margin_right", max(7, int(14 * scale_value)))
	var content := hud.get_node("Margin/Content") as HBoxContainer
	content.add_theme_constant_override("separation", max(4, int(10 * scale_value)))
	var label_size: int = max(9, int(13 * scale_value))
	for label in [content.get_node("SideLabel"), content.get_node("HpLabel"), content.get_node("ManaLabel"), content.get_node("HandLabel")]:
		(label as Label).add_theme_font_size_override("font_size", label_size)
	content.get_node("SideLabel").custom_minimum_size = Vector2(72 * scale_value, 0)
	content.get_node("HpLabel").custom_minimum_size = Vector2(108 * scale_value, 0)
	content.get_node("HpBar").custom_minimum_size = Vector2(128, 14) * scale_value
	content.get_node("ManaLabel").custom_minimum_size = Vector2(108 * scale_value, 0)
	content.get_node("ManaBar").custom_minimum_size = Vector2(104, 14) * scale_value
	content.get_node("HandLabel").custom_minimum_size = Vector2(104 * scale_value, 0)


func _apply_responsive_layout() -> void:
	var s := _ui_scale()
	var viewport_size := get_viewport_rect().size

	# Slots
	for slot in _my_slots_ui() + _their_slots_ui():
		_scale_control(slot, BASE_SLOT_SIZE)
	if enemy_side_ui:
		enemy_side_ui.add_theme_constant_override("separation", int(20 * s))
	if player_side_ui:
		player_side_ui.add_theme_constant_override("separation", int(20 * s))

	# Hand area
	if hand_container:
		hand_container.add_theme_constant_override("separation", int(8 * s))
		for card_ui in hand_container.get_children():
			_scale_control(card_ui, BASE_CARD_SIZE)

	# Fixed player/opponent HUDs and middle turn controls.
	_scale_status_hud(enemy_status_hud, s)
	_scale_status_hud(player_status_hud, s)
	if turn_label:
		turn_label.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	if end_turn_button:
		end_turn_button.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	var info_hbox := $CanvasLayer/MainBackground/MainLayout/MiddleInfoBar/InfoHBox
	info_hbox.add_theme_constant_override("separation", int(20 * s))

	# Spacers
	$CanvasLayer/MainBackground/MainLayout/TopSpacer.custom_minimum_size = Vector2(0, 4 * s)
	$CanvasLayer/MainBackground/MainLayout/EnemyStatusRow.custom_minimum_size = Vector2(0, 40 * s)
	$CanvasLayer/MainBackground/MainLayout/MidSpacer.custom_minimum_size = Vector2(0, 6 * s)
	$CanvasLayer/MainBackground/MainLayout/MiddleInfoBar.custom_minimum_size = Vector2(720, 48) * s
	$CanvasLayer/MainBackground/MainLayout/BottomSpacer.custom_minimum_size = Vector2(0, 4 * s)
	$CanvasLayer/MainBackground/MainLayout/PlayerStatusRow.custom_minimum_size = Vector2(0, 40 * s)
	$CanvasLayer/MainBackground/MainLayout/HandSpacer.custom_minimum_size = Vector2(0, 4 * s)
	$CanvasLayer/MainBackground/MainLayout/BottomDockMargin.custom_minimum_size = Vector2(0, 154 * s)
	$CanvasLayer/MainBackground/MainLayout/BottomDockMargin.add_theme_constant_override("margin_left", int(18 * s))
	$CanvasLayer/MainBackground/MainLayout/BottomDockMargin.add_theme_constant_override("margin_right", int(18 * s))
	$CanvasLayer/MainBackground/MainLayout/BottomDockMargin.add_theme_constant_override("margin_bottom", int(8 * s))
	bottom_dock.add_theme_constant_override("separation", int(12 * s))
	pile_column.custom_minimum_size = Vector2(112 * s, 0)
	pile_column.add_theme_constant_override("separation", int(8 * s))
	hand_area.custom_minimum_size = Vector2(0, 154 * s)
	hand_content.add_theme_constant_override("margin_left", int(8 * s))
	hand_content.add_theme_constant_override("margin_top", int(8 * s))
	hand_content.add_theme_constant_override("margin_right", int(8 * s))
	hand_content.add_theme_constant_override("margin_bottom", int(8 * s))
	discard_column.custom_minimum_size = Vector2(150 * s, 0)
	call_deferred("_align_player_aura")

	# Pile buttons live in the left dock column, so they never cover the hand.
	if draw_pile_btn:
		UITheme.apply_button(draw_pile_btn, "secondary")
		_scale_control(draw_pile_btn, BASE_PILE_BUTTON_SIZE)
		draw_pile_btn.add_theme_font_size_override("font_size", max(9, int(12 * s)))
	if discard_pile_btn:
		UITheme.apply_button(discard_pile_btn, "secondary")
		_scale_control(discard_pile_btn, BASE_PILE_BUTTON_SIZE)
		discard_pile_btn.add_theme_font_size_override("font_size", max(9, int(12 * s)))
	if debug_state_btn:
		UITheme.apply_button(debug_state_btn, "secondary")
		_scale_control(debug_state_btn, BASE_DEBUG_BUTTON_SIZE)
		debug_state_btn.add_theme_font_size_override("font_size", max(9, int(12 * s)))
	if help_btn:
		UITheme.apply_button(help_btn, "secondary")
		_scale_control(help_btn, BASE_HELP_BUTTON_SIZE)
		help_btn.position = Vector2(viewport_size.x - (BASE_HELP_BUTTON_SIZE.x + 16.0) * s, 10.0 * s)
		help_btn.add_theme_font_size_override("font_size", max(9, int(12 * s)))
	if action_log_button:
		UITheme.apply_button(action_log_button, "secondary")
		action_log_button.custom_minimum_size = Vector2(90, 38) * s
		action_log_button.size = action_log_button.custom_minimum_size
		# Utility controls flank the centred enemy HUD instead of covering it.
		action_log_button.position = Vector2(124.0 * s, 10.0 * s)
		action_log_button.add_theme_font_size_override("font_size", max(9, int(12 * s)))
	if abandon_battle_button:
		UITheme.apply_button(abandon_battle_button, "danger")
		abandon_battle_button.custom_minimum_size = Vector2(104, 38) * s
		abandon_battle_button.size = abandon_battle_button.custom_minimum_size
		abandon_battle_button.position = Vector2(12.0 * s, 10.0 * s)
		abandon_battle_button.add_theme_font_size_override("font_size", max(9, int(12 * s)))
	if action_log_panel:
		action_log_panel.position = Vector2(viewport_size.x - 404.0 * s, 56.0 * s)
		action_log_panel.size = Vector2(388, 268) * s
	_update_wait_hint_layout()

	# Discard drop target lives in the right dock column.
	if discard_zone:
		discard_zone.custom_minimum_size = Vector2(150, 72) * s
		var discard_label := discard_zone.get_node("DiscardLabel")
		discard_label.text = Locale.t("battle.discard_zone")
		discard_label.add_theme_font_size_override("font_size", max(10, int(18 * s)))


func _align_player_aura() -> void:
	var background := $CanvasLayer/MainBackground as Control
	var player_aura := $CanvasLayer/MainBackground/PlayerAura as Control
	var enemy_aura := $CanvasLayer/MainBackground/EnemyAura as Control
	if background == null or player_aura == null or enemy_aura == null or player_side_ui == null or enemy_side_ui == null:
		return
	# Local gradients identify the two lanes without dividing the battlefield
	# into hard cyan/black bands. Their transparent edges always sit outside the
	# cards, so no colour boundary can cut through a card body.
	var pad := 26.0 * _ui_scale()
	for pair in [[enemy_aura, enemy_side_ui], [player_aura, player_side_ui]]:
		var aura: Control = pair[0]
		var row: Control = pair[1]
		var row_top: float = row.global_position.y - background.global_position.y
		aura.anchor_top = 0.0
		aura.anchor_bottom = 0.0
		aura.offset_top = row_top - pad
		aura.offset_bottom = row_top + row.size.y + pad


func _on_viewport_size_changed() -> void:
	_apply_responsive_layout()
	update_entire_screen()


# ============================================
# Helpers
# ============================================

func _view_player() -> int:
	if NetworkManager.is_online or my_player in [1, 2]:
		return my_player
	if PlayerData.battle_mode in ["practice", "tutorial"]:
		return 1
	return game.current_player


func _opponent_player() -> int:
	return 2 if _view_player() == 1 else 1


func _my_field() -> BattleField:
	return _field_for_player(_view_player())

func _their_field() -> BattleField:
	return _field_for_player(_opponent_player())

func _my_slots_ui() -> Array:
	return player_side_ui.get_children()

func _their_slots_ui() -> Array:
	return enemy_side_ui.get_children()

func _my_hand() -> Array:
	return _hand_for_player(_view_player())

func _active_hand_container():
	return hand_container


func _hand_for_player(player: int) -> Array:
	return game.player_hand if player == 1 else game.player2_hand


func _field_for_player(player: int) -> BattleField:
	return game.player_field if player == 1 else game.player2_field


func _tutorial_allows(action: String, context: Dictionary = {}) -> bool:
	if PlayerData.battle_mode != "tutorial" or tutorial_controller == null:
		return true
	return tutorial_controller.allows(action, context)


func _tutorial_notify(action: String, context: Dictionary = {}) -> void:
	if PlayerData.battle_mode == "tutorial" and tutorial_controller != null:
		tutorial_controller.notify_action(action, context)


func _find_card_location(card_data: CardData) -> Dictionary:
	var hand = _my_hand()
	var hand_index := hand.find(card_data)
	if hand_index >= 0:
		return {"location": "hand", "index": hand_index}
	var field = _my_field()
	for i in range(5):
		if field.slots[i] == card_data:
			return {"location": "field", "index": i}
	return {"location": "", "index": -1}


func _card_names(cards: Array) -> Array:
	var names: Array = []
	for card in cards:
		names.append("null" if card == null else card.card_name)
	return names


func _slot_names(field: BattleField) -> Array:
	var names: Array = []
	for card in field.slots:
		names.append("[]" if card == null else "%s(%d/%d A%d)" % [card.card_name, card.hp, card.max_hp, card.effective_atk()])
	return names


func _print_authority_state(label: String) -> void:
	print("=== STATE SNAPSHOT: %s ===" % label)
	print("online=%s host=%s my_player=%d current_player=%d turn=%d is_player_turn=%s" % [NetworkManager.is_online, NetworkManager.is_authority(), my_player, game.current_player, game.turn_number, game.is_player_turn])
	print("P1 hp=%d mana=%d/%d hand=%s slots=%s" % [game.player_field.player_hp, game.player_field.current_mana, game.player_field.max_mana, _card_names(game.player_hand), _slot_names(game.player_field)])
	print("P2 hp=%d mana=%d/%d hand=%s slots=%s" % [game.player2_field.player_hp, game.player2_field.current_mana, game.player2_field.max_mana, _card_names(game.player2_hand), _slot_names(game.player2_field)])
	print("deck=%d discard=%d" % [game.shared_deck.size(), game.shared_discard.size()])


func _broadcast_authority_state(label: String) -> void:
	_print_authority_state(label)
	if NetworkManager.is_online and NetworkManager.is_authority():
		var state: Dictionary = game.export_initial_state()
		NetworkManager.save_match_snapshot(state)
		# Ship combat feedback from this action so the non-authority can replay
		# presentation without running combat logic itself.
		state["_hp_events"] = _pending_hp_events.duplicate()
		state["_feedback_events"] = _pending_feedback_events.duplicate()
		_pending_hp_events.clear()
		_pending_feedback_events.clear()
		NetworkManager.broadcast_authority_state(state)


func _commit_authority_state(label: String) -> void:
	if NetworkManager.is_online and NetworkManager.is_authority():
		game.state_revision += 1
	_broadcast_authority_state(label)


func _apply_authority_state(state: Dictionary, label: String = "authority") -> void:
	game.apply_initial_state(state)
	NetworkManager.save_match_snapshot(game.export_initial_state())
	_restore_local_art_paths()
	remote_arrow_source = -1
	remote_arrow_target = -1
	_refresh_hand_ui()
	_check_charm_overflow()
	update_entire_screen()
	# Re-enable turn button for non-authority (may have been locked by end-turn intent)
	if not NetworkManager.is_authority():
		_turn_ending = false
		if end_turn_button:
			end_turn_button.disabled = false
	var feedback_events: Array = state.get("_feedback_events", [])
	for ev in feedback_events:
		_replay_feedback_event(ev)
	# Replay floating text for damage/heal that happened on the authority.
	var hp_events: Array = state.get("_hp_events", [])
	for ev in hp_events:
		_show_floating_for(int(ev.get("player", 0)), int(ev.get("slot", -1)), int(ev.get("delta", 0)))
	_check_and_show_game_over()
	_print_authority_state(label)


func _restore_local_art_paths() -> void:
	if not NetworkManager.is_online:
		return
	var local_art_by_key := {}
	# Opponent arts were downloaded during the lobby and saved to local net_arts
	# paths in opponent_battle_deck. The authority state carries the authority's
	# own (remote) art paths for these cards, so we must remap them to our local
	# copies — otherwise the non-authority can't display the opponent's art.
	for card in PlayerData.opponent_battle_deck:
		if card is CardData and card.art_path != "":
			local_art_by_key[_card_identity_key(card)] = card.art_path
	# Our own cards take precedence on identity collisions.
	for card in PlayerData.battle_deck:
		if card is CardData and card.art_path != "":
			local_art_by_key[_card_identity_key(card)] = card.art_path
	for card in PlayerData.card_library:
		if card is CardData and card.art_path != "":
			local_art_by_key[_card_identity_key(card)] = card.art_path
	_restore_art_paths_in_cards(game.player_hand, local_art_by_key)
	_restore_art_paths_in_cards(game.player2_hand, local_art_by_key)
	_restore_art_paths_in_cards(game.shared_deck, local_art_by_key)
	_restore_art_paths_in_cards(game.shared_discard, local_art_by_key)
	_restore_art_paths_in_slots(game.player_field.slots, local_art_by_key)
	_restore_art_paths_in_slots(game.player2_field.slots, local_art_by_key)


func _restore_art_paths_in_cards(cards: Array, local_art_by_key: Dictionary) -> void:
	for card in cards:
		_restore_art_path(card, local_art_by_key)


func _restore_art_paths_in_slots(slots: Array, local_art_by_key: Dictionary) -> void:
	for card in slots:
		_restore_art_path(card, local_art_by_key)


func _restore_art_path(card, local_art_by_key: Dictionary) -> void:
	if not (card is CardData):
		return
	var key := _card_identity_key(card)
	if not local_art_by_key.has(key):
		return
	card.art_path = local_art_by_key[key]


func _card_identity_key(card: CardData) -> String:
	return "%s|%d|%d|%d|%s" % [card.card_name, card.cost, card.max_hp, card.atk, card.gender]


# ============================================
# Init
# ============================================

var _disconnect_overlay: Control
var _disconnect_back_btn: Button


func _ready():
	game = load("res://GameState.gd").new()
	_battle_started_at = Time.get_unix_time_from_system()
	_init_network()
	game.init_game(Callable(self, "_on_game_draw_cards"))
	if PlayerData.battle_mode == "tutorial":
		TutorialController.configure_game(game)
	if NetworkManager.just_reconnected:
		var saved_state := NetworkManager.load_match_snapshot()
		if not saved_state.is_empty():
			game.apply_initial_state(saved_state)
	elif NetworkManager.is_online and NetworkManager.is_authority():
		NetworkManager.save_match_snapshot(game.export_initial_state())
	_build_turn_cover()
	_build_pile_buttons()
	_build_action_log()
	_apply_theme()
	if $CanvasLayer/MainBackground:
		$CanvasLayer/MainBackground.mouse_filter = Control.MOUSE_FILTER_PASS
		$CanvasLayer/MainBackground.gui_input.connect(_on_battle_background_gui_input)

	var p_slots = player_side_ui.get_children()
	var e_slots = enemy_side_ui.get_children()

	for i in range(p_slots.size()):
		p_slots[i].set_visual_variant("player")
		e_slots[i].set_visual_variant("enemy")
		p_slots[i].pressed.connect(_on_player_slot_clicked.bind(i))
		if p_slots[i].has_signal("slot_attack_requested"):
			p_slots[i].slot_attack_requested.connect(_on_attack_requested.bind(i))
		if p_slots[i].has_signal("slot_skill1_requested"):
			p_slots[i].slot_skill1_requested.connect(_on_skill_activated.bind(i, 0))
		if p_slots[i].has_signal("slot_skill2_requested"):
			p_slots[i].slot_skill2_requested.connect(_on_skill_activated.bind(i, 1))
		if p_slots[i].has_signal("slot_skill3_requested"):
			p_slots[i].slot_skill3_requested.connect(_on_skill_activated.bind(i, 2))
		if p_slots[i].has_signal("card_dropped_here"):
			p_slots[i].card_dropped_here.connect(_on_card_drag_summoned.bind(i))

		e_slots[i].pressed.connect(_on_enemy_slot_clicked.bind(i))
		if e_slots[i].has_signal("slot_attack_requested"):
			e_slots[i].slot_attack_requested.connect(_on_attack_requested.bind(i))
		if e_slots[i].has_signal("slot_skill1_requested"):
			e_slots[i].slot_skill1_requested.connect(_on_skill_activated.bind(i, 0))
		if e_slots[i].has_signal("slot_skill2_requested"):
			e_slots[i].slot_skill2_requested.connect(_on_skill_activated.bind(i, 1))
		if e_slots[i].has_signal("slot_skill3_requested"):
			e_slots[i].slot_skill3_requested.connect(_on_skill_activated.bind(i, 2))
		if e_slots[i].has_signal("card_dropped_here"):
			e_slots[i].card_dropped_here.connect(_on_card_drag_cast_on_enemy.bind(i))

	if end_turn_button:
		end_turn_button.text = Locale.t("battle.end_turn")
		end_turn_button.pressed.connect(_on_end_turn_pressed)

	if discard_zone and discard_zone.has_signal("card_discarded"):
		discard_zone.card_discarded.connect(_on_card_discarded)
	if EventBus.has_signal("hp_changed"):
		EventBus.hp_changed.connect(_on_hp_changed)
	if EventBus.has_signal("damage_resolved"):
		EventBus.damage_resolved.connect(_on_damage_resolved)
	if EventBus.has_signal("parasite_damage_resolved"):
		EventBus.parasite_damage_resolved.connect(_on_parasite_damage_resolved)
	if EventBus.has_signal("skill_roll_failed"):
		EventBus.skill_roll_failed.connect(_on_skill_roll_failed)
	if EventBus.has_signal("skill_safety_limit_hit"):
		EventBus.skill_safety_limit_hit.connect(_on_skill_safety_limit_hit)
	if EventBus.has_signal("shuffle_discard_into_deck"):
		EventBus.shuffle_discard_into_deck.connect(_on_shuffle_discard_into_deck)
	if EventBus.has_signal("view_discard_select"):
		EventBus.view_discard_select.connect(_on_view_discard_select)
	if EventBus.has_signal("view_deck_select"):
		EventBus.view_deck_select.connect(_on_view_deck_select)
	if EventBus.has_signal("make_zero_cost_select"):
		EventBus.make_zero_cost_select.connect(_on_make_zero_cost_select)

	_refresh_hand_ui()
	_apply_responsive_layout()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	update_entire_screen()
	if PlayerData.battle_mode == "tutorial":
		tutorial_controller = TutorialController.new()
		add_child(tutorial_controller)
		tutorial_controller.start(self)
	_play_opening_draw_feedback.call_deferred()
	if NetworkManager.is_online:
		var server_state := NetworkManager.take_pending_server_match_state()
		if not server_state.is_empty() and int(server_state.get("state_revision", -1)) >= game.state_revision:
			_apply_authority_state(server_state, "room server recovery")
		if NetworkManager.just_reconnected:
			_local_slot_rejoined = true
			match_paused = true
			update_entire_screen()
			call_deferred("_request_resume_state")
		elif not NetworkManager.is_authority():
			NetworkManager.rpc_request_initial_state.rpc()


func _on_game_draw_cards(amount: int):
	var drawing_player: int = game.current_player
	var drawn = game.draw_cards(amount)
	if drawn.size() > 0:
		_play_draw_fly_feedback(drawing_player, drawn.size())
	for card_data in drawn:
		var card_ui = card_ui_scene.instantiate()
		_active_hand_container().add_child(card_ui)
		card_ui.set_card(card_data)
		_scale_control(card_ui, BASE_CARD_SIZE)
		card_ui.is_hand_card = true
		_apply_hand_castability(card_ui, card_data)
		_play_hand_card_enter_feedback(card_ui)
		_connect_hand_card_signals(card_ui)


# ============================================
# Contextual tip toasts (stacked, typed)
# ============================================

const TOAST_MAX := 3
const TOAST_KIND_STYLE := {
	"warn": {"border": Color(0.95, 0.58, 0.25), "text": Color(1.0, 0.86, 0.66)},
	"attack": {"border": Color(0.85, 0.32, 0.30), "text": Color(1.0, 0.82, 0.78)},
	"skill": {"border": Color(0.20, 0.72, 0.84), "text": Color(0.82, 0.95, 1.0)},
	"system": {"border": Color(0.62, 0.50, 0.28), "text": Color(0.96, 0.94, 0.88)},
}


func _build_toast_stack() -> void:
	toast_stack = VBoxContainer.new()
	toast_stack.name = "ToastStack"
	toast_stack.anchor_left = 0.5
	toast_stack.anchor_right = 0.5
	toast_stack.anchor_top = 0.14
	toast_stack.anchor_bottom = 0.14
	toast_stack.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_stack.grow_vertical = Control.GROW_DIRECTION_BOTH
	toast_stack.add_theme_constant_override("separation", 8)
	toast_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$CanvasLayer.add_child(toast_stack)


func _spawn_toast(text: String, kind: String = "system", hold: float = 1.8) -> void:
	if text.strip_edges() == "":
		return
	if toast_stack == null or not is_instance_valid(toast_stack):
		_build_toast_stack()
	while toast_stack.get_child_count() >= TOAST_MAX:
		var oldest := toast_stack.get_child(0)
		toast_stack.remove_child(oldest)
		oldest.queue_free()
	var s := _ui_scale()
	var style_cfg: Dictionary = TOAST_KIND_STYLE.get(kind, TOAST_KIND_STYLE["system"])
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UITheme.panel_style(
		Color(0.045, 0.055, 0.08, 0.88),
		style_cfg["border"], 1, 8,
		Color(style_cfg["border"].r, style_cfg["border"].g, style_cfg["border"].b, 0.28), 5
	))
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", max(11, int(17 * s)))
	label.add_theme_color_override("font_color", style_cfg["text"])
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.custom_minimum_size = Vector2(min(560, 380 * s), 0)
	panel.add_child(label)
	toast_stack.add_child(panel)
	panel.modulate.a = 0.0
	var tween := panel.create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(hold)
	tween.tween_property(panel, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(panel.queue_free)


# Show a short fading tip. Pass a Locale key; args fill % placeholders.
func _show_toast(key: String, args := []) -> void:
	_spawn_toast(Locale.t(key, args), "warn", 1.8)
	if key == "tip.insufficient_mana" and toast_stack != null:
		var count := toast_stack.get_child_count()
		if count > 0:
			UITheme.reject_shake(toast_stack.get_child(count - 1))


func _show_combat_broadcast(text: String, kind: String = "system") -> void:
	if text.strip_edges() == "":
		return
	_append_action_log(text, kind)
	_spawn_toast(text, kind if TOAST_KIND_STYLE.has(kind) else "system", 3.1)


func _build_action_log() -> void:
	abandon_battle_button = Button.new()
	abandon_battle_button.text = Locale.t("battle.abandon_battle")
	UITheme.apply_button(abandon_battle_button, "danger")
	abandon_battle_button.pressed.connect(_show_abandon_confirmation)
	$CanvasLayer.add_child(abandon_battle_button)
	action_log_button = Button.new()
	action_log_button.text = Locale.t("battle.action_log")
	UITheme.apply_button(action_log_button, "secondary")
	$CanvasLayer.add_child(action_log_button)
	action_log_panel = PanelContainer.new()
	action_log_panel.visible = false
	action_log_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	UITheme.apply_panel(action_log_panel, "dark")
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 10)
	action_log_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	box.add_child(header)
	var title := Label.new()
	title.text = Locale.t("battle.action_log")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_title(title, 16)
	header.add_child(title)
	var clear_btn := Button.new()
	clear_btn.text = Locale.t("battle.clear_log")
	clear_btn.custom_minimum_size = Vector2(64, 26)
	UITheme.apply_button(clear_btn, "secondary")
	clear_btn.pressed.connect(func():
		_action_log_entries.clear()
		_refresh_action_log_text()
	)
	header.add_child(clear_btn)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(30, 26)
	UITheme.apply_button(close_btn, "danger")
	close_btn.pressed.connect(func(): action_log_panel.visible = false)
	header.add_child(close_btn)
	action_log_text = RichTextLabel.new()
	action_log_text.bbcode_enabled = true
	action_log_text.fit_content = false
	action_log_text.scroll_active = true
	action_log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	action_log_text.add_theme_font_size_override("normal_font_size", 13)
	box.add_child(action_log_text)
	$CanvasLayer.add_child(action_log_panel)
	action_log_button.pressed.connect(func(): action_log_panel.visible = not action_log_panel.visible)


func _show_abandon_confirmation() -> void:
	var popup := UITheme.make_popup_layer(self, 140)
	var layer: CanvasLayer = popup["layer"]
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -230
	panel.offset_top = -105
	panel.offset_right = 230
	panel.offset_bottom = 105
	UITheme.apply_panel(panel, "gold")
	layer.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 22)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	margin.add_child(box)
	var title := Label.new()
	title.text = Locale.t("battle.abandon_confirm_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, 24)
	box.add_child(title)
	var body := Label.new()
	body.text = Locale.t("battle.abandon_confirm_online" if NetworkManager.is_online else "battle.abandon_confirm_solo")
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.apply_label(body, true)
	box.add_child(body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	var cancel_btn := Button.new()
	cancel_btn.text = Locale.t("common.cancel")
	UITheme.apply_button(cancel_btn, "secondary")
	cancel_btn.pressed.connect(layer.queue_free)
	row.add_child(cancel_btn)
	var confirm_btn := Button.new()
	confirm_btn.text = Locale.t("battle.abandon_confirm")
	UITheme.apply_button(confirm_btn, "danger")
	confirm_btn.pressed.connect(func():
		layer.queue_free()
		_abandon_battle_now()
	)
	row.add_child(confirm_btn)
	UITheme.animate_popup_enter(panel)


func _abandon_battle_now() -> void:
	_record_match_history("forfeit", "")
	battle_finished = true
	practice_ai_running = false
	cancel_attack()
	if PlayerData.is_card_playtest_active():
		NetworkManager.close_connection()
		PlayerData.restore_after_card_playtest()
		UIMotion.change_scene("res://CardEditor.tscn")
		return
	if NetworkManager.is_online or NetworkManager.has_saved_match_session():
		NetworkManager.close_connection()
		NetworkManager.clear_room_session()
		UIMotion.change_scene("res://MultiplayerMenu.tscn")
		return
	NetworkManager.close_connection()
	UIMotion.change_scene("res://MainMenu.tscn")


const ACTION_LOG_MAX := 60
const LOG_KIND_COLOR := {
	"attack": Color(1.0, 0.52, 0.45),
	"skill": Color(0.42, 0.80, 0.96),
	"cast": Color(0.42, 0.80, 0.96),
	"summon_skill": Color(0.42, 0.80, 0.96),
	"system": Color(0.95, 0.88, 0.62),
}


func _append_action_log(text: String, kind: String = "system") -> void:
	if action_log_text == null:
		return
	var turn := 1
	if game != null:
		turn = game.turn_number
	_action_log_entries.push_front({"turn": turn, "kind": kind, "text": text.strip_edges()})
	if _action_log_entries.size() > ACTION_LOG_MAX:
		_action_log_entries.resize(ACTION_LOG_MAX)
	_refresh_action_log_text()


func _refresh_action_log_text() -> void:
	if action_log_text == null:
		return
	var parts: Array[String] = []
	for entry in _action_log_entries:
		var kind: String = entry.get("kind", "system")
		var color: Color = LOG_KIND_COLOR.get(kind, LOG_KIND_COLOR["system"])
		var turn_tag := "T%d" % int(entry.get("turn", 1))
		var body := str(entry.get("text", ""))
		# BBCode escape: card names may contain brackets
		body = body.replace("[", "[lb]").replace("]", "[rb]")
		parts.append("[color=#7d8590]%s[/color]  [color=#%s]%s[/color]" % [
			turn_tag, color.to_html(false), body,
		])
	action_log_text.clear()
	action_log_text.append_text("\n".join(parts))
	action_log_text.scroll_to_line(0)
	action_log_button.text = "%s · %d" % [Locale.t("battle.action_log"), _action_log_entries.size()]


# ============================================
# Combat feedback
# ============================================

func _on_hp_changed(target: CardData, delta: int, _new_hp: int):
	if delta == 0:
		return
	# Authority records the change (as player+slot) so it can be replayed as
	# floating text on the non-authority client, which never runs combat logic
	# and therefore never emits hp_changed itself.
	var loc := _locate_card_player_slot(target)
	if loc.slot >= 0 and not _action_broadcast.is_empty():
		_action_hp_events.append({"player": loc.player, "slot": loc.slot, "delta": delta, "card": target.card_name})
	if NetworkManager.is_online and NetworkManager.is_authority():
		if loc.slot >= 0:
			_pending_hp_events.append({"player": loc.player, "slot": loc.slot, "delta": delta})
	if loc.slot < 0:
		return
	_show_combat_feedback_for(loc.player, loc.slot, delta)


func _on_damage_resolved(source: CardData, target: CardData, declared: int, actual: int, reduction_pct: int, temp_hp_before: int, reason: String) -> void:
	if _action_broadcast.is_empty() or target == null:
		return
	var loc := _locate_card_player_slot(target)
	_action_damage_events.append({
		"source": source.card_name if source != null else "",
		"target": target.card_name,
		"player": loc.player,
		"slot": loc.slot,
		"declared": declared,
		"actual": actual,
		"reduction_pct": reduction_pct,
		"temp_hp_before": temp_hp_before,
		"reason": reason,
	})


func _on_parasite_damage_resolved(host: CardData, parasite: CardData, declared: int, actual: int, destroyed: bool) -> void:
	if _action_broadcast.is_empty() or host == null or parasite == null:
		return
	var loc := _locate_card_player_slot(host)
	_action_parasite_events.append({
		"host": host.card_name,
		"parasite": parasite.card_name,
		"player": loc.player,
		"slot": loc.slot,
		"declared": declared,
		"actual": actual,
		"destroyed": destroyed,
	})


func _on_skill_roll_failed(source: CardData, skill_name: String, misfortune: int, final_probability: int) -> void:
	if _action_broadcast.is_empty():
		return
	_action_failed_events.append({
		"source": source.card_name if source != null else "",
		"skill": skill_name,
		"misfortune": misfortune,
		"final_probability": final_probability,
	})


func _on_skill_safety_limit_hit(source_name: String, _reason: String) -> void:
	_show_toast("tip.skill_safety_limit", [source_name])


func _spawn_combat_text(pos: Vector2, delta: int, strong: bool = false) -> void:
	BattleFx.combat_text($CanvasLayer, pos, delta, strong, _ui_scale())
	if strong:
		BattleFx.shake_layer($CanvasLayer, 2.8)


func _spawn_impact_ring(center: Vector2, damage: bool = true, tint: Color = Color()) -> void:
	BattleFx.impact_ring($CanvasLayer, center, damage, tint, _ui_scale())


func _spawn_heal_particles(center: Vector2, amount: int) -> void:
	BattleFx.heal_particles($CanvasLayer, center, amount, _ui_scale())


func _show_combat_feedback_for(player: int, slot: int, delta: int) -> void:
	if slot < 0 or slot > 4:
		return
	var slots_ui: Array = _my_slots_ui() if player == _view_player() else _their_slots_ui()
	if slot >= slots_ui.size():
		return
	var slot_ui: Control = slots_ui[slot]
	var center: Vector2 = slot_ui.global_position + slot_ui.size / 2
	_spawn_combat_text(center, delta, abs(delta) >= 4)
	if delta < 0:
		_spawn_impact_ring(center, true)
	else:
		_spawn_heal_particles(center, delta)
	_play_card_feedback(slot_ui, delta)


func _record_feedback_event(kind: String, player: int, slot: int, extra: Dictionary = {}) -> void:
	if NetworkManager.is_online and NetworkManager.is_authority():
		var event := {"kind": kind, "player": player, "slot": slot}
		for key in extra.keys():
			event[key] = extra[key]
		_pending_feedback_events.append(event)


func _replay_feedback_event(event: Dictionary) -> void:
	var kind: String = event.get("kind", "")
	var player: int = int(event.get("player", 0))
	var slot: int = int(event.get("slot", -1))
	if kind == "broadcast":
		_show_combat_broadcast(_format_action_broadcast(event.get("event", {})), str(event.get("event", {}).get("kind", "system")))
	elif kind == "broadcast_text":
		_show_combat_broadcast(Locale.t(event.get("text_key", "")))
	elif kind == "attack":
		_play_attack_feedback(player, slot, int(event.get("target_slot", -1)))
	elif kind == "skill":
		_play_skill_cast_feedback(player, slot)
	elif kind == "summon":
		_play_summon_feedback(_slot_ui_for_player(player, slot))
	elif kind == "cast":
		_play_skill_cast_feedback(player, slot)
	elif kind == "move":
		_play_move_feedback(player, slot, int(event.get("target_slot", -1)), true)
	elif kind == "turn":
		_show_turn_banner()
	elif kind == "discard":
		_play_discard_feedback()


func _slot_ui_for_player(player: int, slot: int) -> Control:
	if slot < 0 or slot > 4:
		return null
	var slots_ui: Array = _my_slots_ui() if player == _view_player() else _their_slots_ui()
	if slot >= slots_ui.size():
		return null
	return slots_ui[slot]


func _card_feedback_target(slot_ui: Control) -> CanvasItem:
	if slot_ui == null:
		return null
	var card_ui = slot_ui.get("current_card_ui")
	if card_ui != null and is_instance_valid(card_ui):
		return card_ui
	return slot_ui


# Brief screen shake for impactful moments (attack hits).
func _shake_screen(strength: float = 2.5) -> void:
	BattleFx.shake_layer($CanvasLayer, strength)


# Three-beat attack animation: attacker lunge toward the target -> impact
# (ring + light screen shake) -> recoil return and fade. Main resolves where
# the attacker and target are; BattleFx owns the animation itself.
func _play_attack_feedback(player: int, source_slot: int, target_slot: int = -1) -> void:
	var slot_ui := _slot_ui_for_player(player, source_slot)
	if slot_ui == null:
		return
	var card_ui = slot_ui.get("current_card_ui")
	if card_ui == null or not is_instance_valid(card_ui):
		return
	var from_center: Vector2 = slot_ui.global_position + slot_ui.size / 2
	var to_center: Vector2 = from_center + Vector2(0, -14) * _ui_scale()
	if target_slot >= 0:
		var target_ui := _slot_ui_for_player(_opponent_of_player(player), target_slot)
		if target_ui != null:
			to_center = from_center.lerp(target_ui.global_position + target_ui.size / 2, 0.68)
	BattleFx.attack_lunge($CanvasLayer, card_ui, to_center, _ui_scale())


# Pop-in landing effect for a freshly summoned card in a slot.
func _play_summon_feedback(slot_ui: Control) -> void:
	if slot_ui == null or not is_instance_valid(slot_ui):
		return
	var card_ui = slot_ui.get("current_card_ui")
	if card_ui == null or not is_instance_valid(card_ui):
		return
	var center: Vector2 = slot_ui.global_position + slot_ui.size / 2
	BattleFx.summon_landing($CanvasLayer, card_ui, center, _ui_scale())


# Swap transition for a move: both involved cards fly along a small arc to each
# other's slot, then fade. Call before update_entire_screen so the ghost still
# shows the pre-swap arrangement. When `reverse` is set (non-authority client
# replaying after the state already swapped), each ghost starts from the slot
# the card originally occupied so the animation direction stays consistent.
func _play_move_feedback(player: int, source_slot: int, target_slot: int, reverse: bool = false) -> void:
	if source_slot < 0 or target_slot < 0 or source_slot == target_slot:
		return
	var slots_ui: Array = _my_slots_ui() if player == _view_player() else _their_slots_ui()
	if source_slot >= slots_ui.size() or target_slot >= slots_ui.size():
		return
	var src_ui: Control = slots_ui[source_slot]
	var dst_ui: Control = slots_ui[target_slot]
	var src_center: Vector2 = src_ui.global_position + src_ui.size / 2
	var dst_center: Vector2 = dst_ui.global_position + dst_ui.size / 2
	var to_dst: Vector2 = dst_center - src_center
	var to_src: Vector2 = src_center - dst_center
	var entries: Array = []
	if reverse:
		# Post-swap: the moved card now sits in target_slot, the displaced card
		# in source_slot — start each ghost from the slot it left.
		_append_move_entry(entries, dst_ui, to_dst, src_center)
		_append_move_entry(entries, src_ui, to_src, dst_center)
	else:
		# Pre-swap: the moved card sits in source_slot, the displaced card in target_slot.
		_append_move_entry(entries, src_ui, to_dst)
		_append_move_entry(entries, dst_ui, to_src)
	BattleFx.move_swap($CanvasLayer, entries, _ui_scale())


func _append_move_entry(entries: Array, slot_ui: Control, delta: Vector2, start_pos: Vector2 = Vector2.INF) -> void:
	var card_ui = slot_ui.get("current_card_ui")
	if card_ui == null or not is_instance_valid(card_ui):
		return
	entries.append([card_ui, delta, start_pos])


# Lightweight turn-start banner (fade in -> hold -> fade out), replaces the
# heavy full-screen splash for turn transitions.
func _show_turn_banner() -> void:
	if battle_finished:
		return
	var text := Locale.t("battle.your_turn") if game.current_player == _view_player() else Locale.t("battle.opponent_turn")
	BattleFx.turn_banner($CanvasLayer, text, _ui_scale(), get_viewport_rect().size)


func _play_skill_cast_feedback(player: int, slot: int) -> void:
	# Hand-cast spells have no field slot; render an arcane burst + projectile
	# flying from the hand toward the battlefield center instead.
	if slot < 0:
		_play_spell_cast_from_hand_feedback()
		return
	var slot_ui := _slot_ui_for_player(player, slot)
	var target := _card_feedback_target(slot_ui)
	if target == null or not is_instance_valid(target):
		return
	var center: Vector2 = slot_ui.global_position + slot_ui.size / 2
	BattleFx.skill_cast_pulse($CanvasLayer, target, center, _ui_scale())


# Arcane burst at the hand + a projectile flying to the battlefield center for
# spells cast directly from hand (slot == -1).
func _play_spell_cast_from_hand_feedback() -> void:
	if hand_container == null:
		return
	var start: Vector2 = hand_container.global_position + Vector2(hand_container.size.x * 0.5, hand_container.size.y * 0.35)
	_spawn_impact_ring(start, false, Color(0.45, 0.7, 1.0, 0.5))
	var field_center: Vector2 = (player_side_ui.global_position + enemy_side_ui.global_position) / 2
	field_center.y = (player_side_ui.global_position.y + enemy_side_ui.global_position.y) / 2 + player_side_ui.size.y / 2
	BattleFx.spell_cast_projectile($CanvasLayer, start, field_center, _ui_scale())


func _opponent_of_player(player: int) -> int:
	return 2 if player == 1 else 1


func _play_card_feedback(slot_ui: Control, delta: int) -> void:
	if slot_ui == null or delta == 0:
		return
	var target: CanvasItem = slot_ui
	var card_ui = slot_ui.get("current_card_ui")
	if card_ui != null and is_instance_valid(card_ui):
		target = card_ui
	if not is_instance_valid(target):
		return
	BattleFx.card_hit_flash(target, delta)


# Locates a card's absolute player (1/2) and slot index, or slot -1 if not found.
func _locate_card_player_slot(card: CardData) -> Dictionary:
	for i in range(5):
		if game.player_field.slots[i] == card:
			return {"player": 1, "slot": i}
		if game.player2_field.slots[i] == card:
			return {"player": 2, "slot": i}
	return {"player": 0, "slot": -1}


# Replays floating text on the non-authority client using absolute player+slot,
# mapping to the correct UI side for this client's viewing perspective.
func _show_floating_for(player: int, slot: int, delta: int) -> void:
	_show_combat_feedback_for(player, slot, delta)


func _find_card_slot_pos(card: CardData) -> Vector2:
	var p_slots = player_side_ui.get_children()
	var e_slots = enemy_side_ui.get_children()
	for i in range(5):
		if _my_field().slots[i] == card:
			return p_slots[i].global_position
		if _their_field().slots[i] == card:
			return e_slots[i].global_position
	return Vector2.ZERO


func _begin_action_broadcast(kind: String, player: int, source_name: String, target_name: String = "", extra: Dictionary = {}) -> void:
	_action_broadcast = {"kind": kind, "player": player, "source": source_name, "target": target_name}
	for key in extra.keys():
		_action_broadcast[key] = extra[key]
	_action_hp_events.clear()
	_action_damage_events.clear()
	_action_parasite_events.clear()
	_action_failed_events.clear()


func _finish_action_broadcast() -> void:
	if _action_broadcast.is_empty():
		_action_hp_events.clear()
		_action_damage_events.clear()
		_action_parasite_events.clear()
		_action_failed_events.clear()
		return
	var event := _action_broadcast.duplicate(true)
	event["hp_events"] = _action_hp_events.duplicate(true)
	event["damage_events"] = _action_damage_events.duplicate(true)
	event["parasite_events"] = _action_parasite_events.duplicate(true)
	event["failed_events"] = _action_failed_events.duplicate(true)
	var text := _format_action_broadcast(event)
	_show_combat_broadcast(text, str(event.get("kind", "system")))
	if NetworkManager.is_online and NetworkManager.is_authority():
		_pending_feedback_events.append({"kind": "broadcast", "event": event})
	_action_broadcast.clear()
	_action_hp_events.clear()
	_action_damage_events.clear()
	_action_parasite_events.clear()
	_action_failed_events.clear()


func _format_action_broadcast(event: Dictionary) -> String:
	var kind: String = event.get("kind", "")
	var player: int = int(event.get("player", 0))
	var source: String = event.get("source", "")
	var target: String = event.get("target", "")
	var subject := "%s%s" % [_side_text(player), source]
	var hp_events: Array = event.get("hp_events", [])
	var damage_events: Array = event.get("damage_events", [])
	var parasite_events: Array = event.get("parasite_events", [])
	var failed_events: Array = event.get("failed_events", [])
	match kind:
		"attack":
			return _format_attack_broadcast(subject, target, hp_events, damage_events, parasite_events, int(event.get("base_damage", 0)), int(event.get("effective_damage", event.get("base_damage", 0))), int(event.get("target_player", _opponent_of_player(player))), int(event.get("target_slot", -1)), bool(event.get("kill_mana", false)))
		"skill", "summon_skill":
			var skill_name: String = event.get("skill", Locale.t("battle.log.skill_word"))
			return _format_skill_broadcast(subject, skill_name, hp_events, damage_events, parasite_events, failed_events)
		"cast":
			return _format_skill_broadcast(subject, Locale.t("battle.log.cast_word"), hp_events, damage_events, parasite_events, failed_events)
	return ""


# Joins battle-broadcast segments with the punctuation of the active language
# (CJK uses ，。; English uses ", ."). Avoids hardcoded Chinese separators
# leaking into English builds.
func _join_broadcast(parts: Array, with_period: bool = true) -> String:
	var sep: String = ", " if Locale.language == "en" else "，"
	var text := sep.join(parts)
	if with_period:
		text += "." if Locale.language == "en" else "。"
	return text


func _format_attack_broadcast(subject: String, target: String, hp_events: Array, damage_events: Array, parasite_events: Array, base_damage: int, effective_damage: int, target_player: int, target_slot: int, kill_mana: bool = false) -> String:
	var target_damage := 0
	var extra_target_damage := 0
	var adjacent_damage := 0
	var adjacent_count := 0
	var other_damage := 0
	var other_count := 0
	var heals := []
	for ev in hp_events:
		var delta: int = int(ev.get("delta", 0))
		if delta < 0:
			var damage := -delta
			var ev_player: int = int(ev.get("player", 0))
			var ev_slot: int = int(ev.get("slot", -1))
			if ev_player == target_player and ev_slot == target_slot:
				target_damage += damage
			elif ev_player == target_player and abs(ev_slot - target_slot) == 1:
				adjacent_damage += damage
				adjacent_count += 1
			else:
				other_damage += damage
				other_count += 1
		elif delta > 0:
			heals.append(Locale.t("battle.log.heal", [ev.get("card", Locale.t("battle.log.unit")), delta]))
	var target_detail := _damage_detail_for(damage_events, target_player, target_slot)
	if target_damage == 0 and not target_detail.is_empty():
		target_damage = int(target_detail.get("actual", 0))
	var target_declared: int = base_damage if effective_damage != base_damage else int(target_detail.get("declared", effective_damage))
	var parts := []
	var intro := Locale.t("battle.log.attack_intro", [subject, _side_text(target_player), target])
	if target_declared > 0 and (target_damage > 0 or target_declared != target_damage):
		if target_declared != target_damage:
			parts.append(Locale.t("battle.log.damage_reduced", [intro, target_declared, target_damage]))
		else:
			parts.append(Locale.t("battle.log.damage_plain", [intro, target_damage]))
	else:
		parts.append(intro)
	if adjacent_damage > 0:
		parts.append(Locale.t("battle.log.splash", [target, adjacent_count, adjacent_damage]))
	if other_damage > 0:
		parts.append(Locale.t("battle.log.other_damage", [other_count, other_damage]))
	if kill_mana:
		parts.append(Locale.t("battle.log.kill_mana"))
	parts.append_array(_format_parasite_broadcast_parts(parasite_events))
	parts.append_array(heals)
	return _join_broadcast(parts)


func _format_skill_broadcast(subject: String, action_name: String, hp_events: Array, damage_events: Array, parasite_events: Array, failed_events: Array) -> String:
	var parts := [Locale.t("battle.log.skill_use", [subject, action_name])]
	var has_result := not damage_events.is_empty()
	for ev in hp_events:
		if int(ev.get("delta", 0)) > 0:
			has_result = true
	for fail in failed_events:
		var misfortune: int = int(fail.get("misfortune", 0))
		if misfortune > 0 and not has_result:
			parts.append(Locale.t("battle.log.skill_misfortune", [misfortune]))
		elif has_result:
			parts.append(Locale.t("battle.log.skill_partial"))
		else:
			parts.append(Locale.t("battle.log.skill_failed"))
	for dmg in damage_events:
		var actual: int = int(dmg.get("actual", 0))
		var declared: int = int(dmg.get("declared", actual))
		if declared <= 0:
			continue
		var target_name: String = dmg.get("target", Locale.t("battle.log.unit"))
		var player: int = int(dmg.get("player", 0))
		if declared != actual:
			parts.append(Locale.t("battle.log.damage_target_reduced", [_side_text(player), target_name, declared, actual]))
		else:
			parts.append(Locale.t("battle.log.damage_target_plain", [_side_text(player), target_name, actual]))
	var heal_by_card := {}
	for ev in hp_events:
		var card_name: String = ev.get("card", Locale.t("battle.log.unit"))
		var delta: int = int(ev.get("delta", 0))
		if delta > 0:
			heal_by_card[card_name] = int(heal_by_card.get(card_name, 0)) + delta
	for card_name in heal_by_card.keys():
		parts.append(Locale.t("battle.log.heal_target", [_side_text(_player_for_event_card(hp_events, card_name)), card_name, int(heal_by_card[card_name])]))
	parts.append_array(_format_parasite_broadcast_parts(parasite_events))
	return _join_broadcast(parts)


func _format_parasite_broadcast_parts(parasite_events: Array) -> Array:
	var parts := []
	for ev in parasite_events:
		var declared: int = int(ev.get("declared", 0))
		var actual: int = int(ev.get("actual", 0))
		if declared <= 0:
			continue
		var parasite_name: String = ev.get("parasite", Locale.t("battle.log.parasite"))
		if declared != actual:
			parts.append(Locale.t("battle.log.parasite_reduced", [parasite_name, declared, actual]))
		else:
			parts.append(Locale.t("battle.log.parasite_plain", [parasite_name, actual]))
		if bool(ev.get("destroyed", false)):
			parts.append(Locale.t("battle.log.parasite_gone", [parasite_name]))
	return parts


func _damage_detail_for(damage_events: Array, player: int, slot: int) -> Dictionary:
	for ev in damage_events:
		if int(ev.get("player", 0)) == player and int(ev.get("slot", -1)) == slot:
			return ev
	return {}


func _player_for_event_card(events: Array, card_name: String) -> int:
	for ev in events:
		if ev.get("card", "") == card_name:
			return int(ev.get("player", 0))
	return 0


func _side_text(player: int) -> String:
	if player == _view_player():
		return Locale.t("battle.log.friendly")
	if player == _opponent_player():
		return Locale.t("battle.log.enemy")
	return ""


# Cross-layer interface implemented by the action, presentation, and network components.

func _apply_hand_castability(card_ui, card_data: CardData) -> void:
	pass

func _build_pile_buttons():
	pass

func _build_turn_cover():
	pass

func _check_and_show_game_over() -> bool:
	return false

func _check_charm_overflow():
	pass

func _connect_hand_card_signals(card_ui) -> void:
	pass

func _init_network():
	pass

func _on_attack_requested(slot_index: int):
	pass

func _on_battle_background_gui_input(event: InputEvent) -> void:
	pass

func _on_card_discarded(card_data: CardData):
	pass

func _on_card_drag_cast_on_enemy(card_data: CardData, origin_ui, enemy_slot_index: int) -> void:
	pass

func _on_card_drag_summoned(card_data, origin_ui, slot_index: int):
	pass

func _on_end_turn_pressed():
	pass

func _on_enemy_slot_clicked(enemy_index: int):
	pass

func _on_make_zero_cost_select(count: int, _current_player: int, hand: Array, target: String, _random_count: int) -> void:
	pass

func _on_player_slot_clicked(index: int):
	pass

func _on_shuffle_discard_into_deck() -> void:
	pass

func _on_skill_activated(slot_index: int, skill_index: int):
	pass

func _on_view_deck_select(count: int, draw_count: int, current_player: int, hand: Array) -> void:
	pass

func _on_view_discard_select(count: int, draw_count: int, current_player: int, hand: Array) -> void:
	pass

func _play_discard_feedback() -> void:
	pass

func _play_draw_fly_feedback(player: int, count: int) -> void:
	pass

func _play_hand_card_enter_feedback(card_ui: Control) -> void:
	pass

func _play_opening_draw_feedback() -> void:
	pass

func _record_match_history(outcome: String, result: String) -> void:
	pass

func _refresh_hand_ui():
	pass

func _update_wait_hint_layout() -> void:
	pass

func cancel_attack():
	pass

func update_entire_screen():
	pass

func _apply_deaths():
	pass

func _hand_index_of(card_ui) -> int:
	return 0

func _host_apply_attack(source_slot: int, target_slot: int, player: int) -> void:
	pass

func _host_apply_cast(hand_index: int, skill_index: int, target_slot: int, player: int) -> void:
	pass

func _host_apply_discard(location: String, index: int, player: int) -> void:
	pass

func _host_apply_end_turn(player: int) -> void:
	pass

func _host_apply_move(source_slot: int, target_slot: int, player: int) -> void:
	pass

func _host_apply_parasite(hand_index: int, target_player: int, target_slot: int, player: int) -> void:
	pass

func _host_apply_skill(slot_index: int, skill_index: int, target_slot: int, player: int) -> void:
	pass

func _host_apply_summon(hand_index: int, slot_index: int, player: int) -> void:
	pass

func _host_apply_summon_skill(slot_index: int, skill_index: int, target_slot: int, player: int) -> void:
	pass

func _parasite_intent_source(hand_index: int, target_player: int) -> int:
	return 0

func _show_direct_damage(result: Dictionary):
	pass

func _spell_intent_source(hand_index: int) -> int:
	return 0

func _sync_targeting_state():
	pass

func is_my_turn() -> bool:
	return false

func _process_resume_sync() -> void:
	pass

func _on_resume_retry_pressed() -> void:
	pass

func _toggle_turn_cover():
	pass

func _update_pile_labels():
	pass
