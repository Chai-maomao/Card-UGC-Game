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
const BattleLogFormatter = preload("res://BattleLogFormatter.gd")
const ToastFeed = preload("res://BattleToastFeed.gd")

@onready var enemy_side_ui = $CanvasLayer/MainBackground/MainLayout/EnemySide
@onready var player_side_ui = $CanvasLayer/MainBackground/MainLayout/PlayerSide
@onready var turn_label = $CanvasLayer/MainBackground/MainLayout/MiddleInfoBar/InfoHBox/TurnLabel
var _face_mana_turn_key := ""
@onready var face_mana_button: Button = $CanvasLayer/MainBackground/MainLayout/MiddleInfoBar/InfoHBox/FaceManaButton
@onready var end_turn_button = $CanvasLayer/MainBackground/MainLayout/MiddleInfoBar/InfoHBox/EndTurnButton
@onready var attack_arrow = $CanvasLayer/AttackArrow
@onready var bottom_dock = $CanvasLayer/MainBackground/MainLayout/BottomDockMargin/BottomDock
@onready var pile_column = $CanvasLayer/MainBackground/MainLayout/BottomDockMargin/BottomDock/PileColumn
@onready var hand_area = $CanvasLayer/MainBackground/MainLayout/BottomDockMargin/BottomDock/HandArea
@onready var hand_content = $CanvasLayer/MainBackground/MainLayout/BottomDockMargin/BottomDock/HandArea/HandContent
@onready var hand_container = $CanvasLayer/MainBackground/MainLayout/BottomDockMargin/BottomDock/HandArea/HandContent/HandScroll/HandContainer
@onready var splash_panel = $CanvasLayer/SplashPanel
@onready var middle_info_bar: Control = $CanvasLayer/MainBackground/MainLayout/MiddleInfoBar
@onready var discard_column = $CanvasLayer/MainBackground/MainLayout/BottomDockMargin/BottomDock/DiscardColumn
var discard_zone: Control # Compatibility alias for tutorial/feedback targets; this is the right pile button.
@onready var enemy_status_hud = $CanvasLayer/MainBackground/MainLayout/EnemyStatusRow/EnemyStatusHUD
@onready var player_status_hud = $CanvasLayer/MainBackground/MainLayout/PlayerStatusRow/PlayerStatusHUD

var splash_tween: Tween
var splash_slide_progress: float = 0.0:
	set(value):
		splash_slide_progress = value
		_position_splash_panel()
		if is_instance_valid(splash_panel): splash_panel.travel = value
var turn_cover: ColorRect
var turn_wait_hint: Panel
var draw_pile_btn: Button
var discard_pile_btn: Button
var debug_state_btn: Button
var help_btn: Button
var field_rules_btn: Button
var battle_settings_btn: Button
var battle_chat_button: Button
var _toast_feed: ToastFeed
var _command_result_prompt: WeakRef
var _command_send_failure_prompt: WeakRef
var action_log_button: Button
var abandon_battle_button: Button
var action_log_panel: PanelContainer
var action_log_text: RichTextLabel
var _battle_started_at: float = 0.0
var reconnect_leave_button: Button
var _reconnect_elapsed_seconds: int = 0
var _reconnect_attempt: int = 0
var _history_recorded: bool = false
var practice_ai_running: bool = false
var battle_finished: bool = false
var _simulating_web_command := false
var _turn_ending: bool = false  # 防止短时间内重复点击结束按钮
var _timed_out_action := ""
var _rejected_action_pending := false
var _pending_feedback_events: Array = []
var _action_broadcast: Dictionary = {}
var _action_hp_events: Array = []
var _action_presentation_events: Array = []
var _action_damage_events: Array = []
var _pending_zero_damage_targets: Dictionary = {}
var _action_parasite_events: Array = []
var _action_failed_events: Array = []
var _end_turn_pulse: Tween = null
var _turn_pop_tween: Tween = null
var _turn_last_text: String = ""
var _status_hud_state: Dictionary = {}
var _status_value_tweens: Dictionary = {}
var _suppress_status_feedback_once: bool = false
var _pending_hand_entry_ids: Dictionary = {}
var _deferred_hand_arrival_refs: Dictionary = {}
var my_player: int = 0
var remote_arrow_source: int = -1
var remote_arrow_target: int = -1
var _remote_arrow_expires_at := 0
var _next_targeting_refresh := 0
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
var _resolution_pending_steps: int = 0
var _resolution_running: bool = false
var _resolution_blocker: Control
var _action_feedback_group_stack: Array[int] = []
var _action_feedback_next_group: int = 0
var _hp_feedback_batches: Array = []
var _hp_feedback_running: bool = false
var _result_waiting_for_feedback := false
var _random_feedback_pending := 0
var _random_unbatched_events: Array = []
var _random_last_shown_board: Dictionary = {}
var _random_unbatched_before: Dictionary = {}
var _random_action_before: Dictionary = {}
var _random_attack_motion: Dictionary = {}
var _playing_random_action := false
var _playing_deferred_feedback := false
var _unbatched_hp_feedback: Array = []
var _deployment_feedback_until_msec := 0
var _hp_presentation_overrides: Dictionary = {}
var _network_command_phase: String = ""
var tutorial_controller: BattleTutorialController
var _active_challenge_id: String = ""
var _last_pile_counts := Vector2i(-1, -1)
var _pile_arrivals: Dictionary = {}
var _pile_arrival_serial := 0


func _hold_pile_addition(pile: int, amount: int = 1) -> int:
	_pile_arrival_serial += 1
	_pile_arrivals[_pile_arrival_serial] = Vector2i(amount if pile == 0 else 0, amount if pile == 1 else 0)
	return _pile_arrival_serial


func _finish_pile_addition(token: int, amount: int = -1) -> void:
	if not _pile_arrivals.has(token): return
	var remaining: Vector2i = _pile_arrivals[token]
	if amount < 0:
		remaining = Vector2i.ZERO
	else:
		remaining = Vector2i(maxi(0,remaining.x-amount),maxi(0,remaining.y-amount))
	if remaining == Vector2i.ZERO: _pile_arrivals.erase(token)
	else: _pile_arrivals[token] = remaining
	_update_pile_labels()


func _visible_pile_counts() -> Vector2i:
	var counts := Vector2i(game.shared_deck.size(),game.shared_discard.size())
	for pending in _pile_arrivals.values(): counts -= pending
	return counts.max(Vector2i.ZERO)


func _reserve_hand_pile_arrivals(meta: Dictionary, destination: String, source: String) -> void:
	meta.erase("discard_arrival_token")
	meta.erase("reshuffle_arrival_token")
	if destination == "discard": meta["discard_arrival_token"] = _hold_pile_addition(1)
	if source == "deck" and int(meta.get("reshuffle_count",0)) > 0 and int(meta.get("batch_index",0)) == 0:
		var count := int(meta.get("reshuffle_deck_remaining",maxi(0,int(meta.reshuffle_count)-int(meta.get("batch_size",1)))))
		meta["reshuffle_arrival_token"] = _hold_pile_addition(0,count)
const BASE_VIEWPORT_SIZE := Vector2(1152, 648)
const BASE_CARD_SIZE := Vector2(120, 160)
const BASE_SLOT_SIZE := BASE_CARD_SIZE
const BASE_PILE_BUTTON_SIZE := Vector2(112, 44)
const BASE_DEBUG_BUTTON_SIZE := Vector2(130, 50)
const BASE_HELP_BUTTON_SIZE := Vector2(90, 38)
const RESUME_SYNC_TIMEOUT := 15.0
const RESUME_REQUEST_INTERVAL := 1.5
const RESUME_MAX_REQUESTS := 8
const EFFECT_PRESENTATION_GAP := 0.2


func _ui_scale() -> float:
	var size := get_viewport_rect().size
	if size.x <= 0 or size.y <= 0:
		return 1.0
	return min(size.x / BASE_VIEWPORT_SIZE.x, size.y / BASE_VIEWPORT_SIZE.y)


func _screen_pixels_in_ui(pixels: float) -> float:
	var canvas_size := get_viewport_rect().size
	var window_size := Vector2(get_window().size)
	if canvas_size.x <= 0 or canvas_size.y <= 0 or window_size.x <= 0 or window_size.y <= 0:
		return pixels
	return pixels / minf(window_size.x / canvas_size.x, window_size.y / canvas_size.y)


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
	UITheme.apply_panel($CanvasLayer/MainBackground/MainLayout/MiddleInfoBar, "dark")
	UITheme.apply_panel(hand_area.get_node("HandBackdrop"), "hand")
	UITheme.apply_label(turn_label)
	_apply_status_hud_theme(enemy_status_hud, true, false)
	_apply_status_hud_theme(player_status_hud, false, false)
	# End-turn gets its own attention pulse, so skip the generic hover hook.
	UITheme.apply_button(end_turn_button, "primary", false)
	UITheme.apply_button(face_mana_button, "secondary", false)
	for btn in [debug_state_btn, help_btn]:
		UITheme.apply_button(btn, "secondary")


func _apply_status_hud_theme(hud: Panel, enemy: bool, active: bool) -> void:
	BattleStatusHud._apply_status_hud_theme(hud, enemy, active)


func _style_status_bar(bar: ProgressBar, fill_color: Color) -> void:
	BattleStatusHud._style_status_bar(bar, fill_color)


func _sync_hand_area_minimum() -> void:
	if not is_instance_valid(hand_area) or not is_instance_valid(hand_container): return
	var padding: int = hand_content.get_theme_constant("margin_top")+hand_content.get_theme_constant("margin_bottom")
	hand_area.custom_minimum_size.y = maxf(154*_ui_scale(),hand_container.get_combined_minimum_size().y+padding)


func _scale_status_hud(hud: Panel, scale_value: float) -> void:
	BattleStatusHud._scale_status_hud(hud, scale_value)


func _apply_responsive_layout() -> void:
	var s := _ui_scale()
	var viewport_size := get_viewport_rect().size
	_layout_splash_panel()

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
		turn_label.add_theme_font_size_override("font_size", max(11, int(13 * s)))
		# Status and resource text can change while the adjacent actions stay put.
		turn_label.custom_minimum_size.x = maxf(148, 176 * s)
		turn_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if end_turn_button:
		end_turn_button.add_theme_font_size_override("font_size", maxi(13, int(15 * s)))
		end_turn_button.custom_minimum_size.x = maxf(100, 124 * s)
	if face_mana_button:
		face_mana_button.add_theme_font_size_override("font_size", max(11, int(13 * s)))
	var info_hbox := $CanvasLayer/MainBackground/MainLayout/MiddleInfoBar/InfoHBox
	var info_gap := int(12 * s)
	info_hbox.offset_left = info_gap
	info_hbox.offset_right = -info_gap
	info_hbox.add_theme_constant_override("separation", info_gap)
	var broadcast_strip := info_hbox.get_node_or_null("CombatBroadcastStrip") as Control
	if broadcast_strip:
		broadcast_strip.custom_minimum_size = Vector2(
			maxf(330 * s, _screen_pixels_in_ui(224)),
			maxf(44 * s, maxf(40, _screen_pixels_in_ui(34))))
		broadcast_strip.add_theme_font_size_override("font_size", max(12, int(14 * s)))
	var info_width := float(info_gap * (info_hbox.get_child_count() + 1))
	for control: Control in [turn_label, end_turn_button, face_mana_button, broadcast_strip]:
		if control != null:
			info_width += control.get_combined_minimum_size().x
	var strip_height := broadcast_strip.custom_minimum_size.y if broadcast_strip else 0.0
	middle_info_bar.custom_minimum_size = Vector2(maxf(720 * s, info_width), maxf(48 * s, strip_height))
	_align_turn_label.call_deferred()

	# Spacers
	$CanvasLayer/MainBackground/MainLayout/TopSpacer.custom_minimum_size = Vector2(0, 4 * s)
	$CanvasLayer/MainBackground/MainLayout/EnemyStatusRow.custom_minimum_size = Vector2(0, 40 * s)
	$CanvasLayer/MainBackground/MainLayout/MidSpacer.custom_minimum_size = Vector2(0, 6 * s)
	$CanvasLayer/MainBackground/MainLayout/BottomSpacer.custom_minimum_size = Vector2(0, 4 * s)
	$CanvasLayer/MainBackground/MainLayout/PlayerStatusRow.custom_minimum_size = Vector2(0, 40 * s)
	$CanvasLayer/MainBackground/MainLayout/HandSpacer.custom_minimum_size = Vector2(0, 4 * s)
	$CanvasLayer/MainBackground/MainLayout/BottomDockMargin.custom_minimum_size = Vector2(0, 154 * s)
	$CanvasLayer/MainBackground/MainLayout/BottomDockMargin.add_theme_constant_override("margin_left", int(18 * s))
	$CanvasLayer/MainBackground/MainLayout/BottomDockMargin.add_theme_constant_override("margin_right", int(18 * s))
	$CanvasLayer/MainBackground/MainLayout/BottomDockMargin.add_theme_constant_override("margin_bottom", int(8 * s))
	bottom_dock.add_theme_constant_override("separation", int(12 * s))
	pile_column.custom_minimum_size = Vector2(140 * s, 0)
	pile_column.add_theme_constant_override("separation", int(8 * s))
	_sync_hand_area_minimum()
	hand_content.add_theme_constant_override("margin_left", int(8 * s))
	hand_content.add_theme_constant_override("margin_top", int(8 * s))
	hand_content.add_theme_constant_override("margin_right", int(8 * s))
	hand_content.add_theme_constant_override("margin_bottom", int(8 * s))
	_sync_hand_area_minimum()
	discard_column.custom_minimum_size = Vector2(140 * s, 0)
	call_deferred("_align_player_aura")

	# Pile buttons live in the left dock column, so they never cover the hand.
	if draw_pile_btn:
		_scale_control(draw_pile_btn, BASE_PILE_BUTTON_SIZE)
		draw_pile_btn.add_theme_font_size_override("font_size", max(9, int(12 * s)))
	if discard_pile_btn:
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
	if field_rules_btn:
		_scale_control(field_rules_btn, BASE_HELP_BUTTON_SIZE)
		field_rules_btn.position = help_btn.position + Vector2(0, (BASE_HELP_BUTTON_SIZE.y + 8) * s)
		field_rules_btn.add_theme_font_size_override("font_size", max(9, int(12 * s)))
	if battle_settings_btn:
		_scale_control(battle_settings_btn, BASE_HELP_BUTTON_SIZE)
		battle_settings_btn.position = field_rules_btn.position + Vector2(0, (BASE_HELP_BUTTON_SIZE.y + 8) * s)
		battle_settings_btn.add_theme_font_size_override("font_size", max(9, int(12 * s)))
	if battle_chat_button:
		_scale_control(battle_chat_button, BASE_HELP_BUTTON_SIZE)
		battle_chat_button.position = battle_settings_btn.position + Vector2(0, (BASE_HELP_BUTTON_SIZE.y + 8) * s)
		battle_chat_button.add_theme_font_size_override("font_size", max(11, int(12 * s)))
	if action_log_button:
		UITheme.apply_button(action_log_button, "secondary")
		action_log_button.add_theme_font_size_override("font_size", max(9, int(12 * s)))
		action_log_button.clip_text = true
		action_log_button.custom_minimum_size = Vector2(90, 38) * s
		action_log_button.size = action_log_button.custom_minimum_size
		# Utility controls flank the centred enemy HUD instead of covering it.
		action_log_button.position = Vector2(124.0 * s, 10.0 * s)
	if abandon_battle_button:
		UITheme.apply_button(abandon_battle_button, "secondary")
		abandon_battle_button.add_theme_font_size_override("font_size", max(9, int(12 * s)))
		abandon_battle_button.custom_minimum_size = Vector2(104, 38) * s
		abandon_battle_button.size = abandon_battle_button.custom_minimum_size
		abandon_battle_button.position = Vector2(12.0 * s, 10.0 * s)
	_layout_action_log_panel.call_deferred()
	_update_wait_hint_layout()



func _align_turn_label() -> void:
	var side_label := player_status_hud.get_node("Margin/Content/SideLabel") as Control
	var row := turn_label.get_parent() as HBoxContainer
	var inset := maxf(0, side_label.get_global_rect().position.x - middle_info_bar.get_global_rect().position.x)
	var broadcast := row.get_node_or_null("CombatBroadcastStrip") as Control
	if broadcast != null:
		var available := middle_info_bar.size.x - inset + row.offset_right
		var separation := row.get_theme_constant("separation")
		for child in row.get_children():
			if child is Control and child != broadcast:
				available -= child.get_combined_minimum_size().x + separation
		broadcast.custom_minimum_size.x = maxf(1, minf(available, maxf(330 * _ui_scale(), _screen_pixels_in_ui(224))))
	row.grow_horizontal = Control.GROW_DIRECTION_END
	row.offset_left = inset


func _layout_action_log_panel() -> void:
	if not is_instance_valid(action_log_panel): return
	var s := _ui_scale()
	var viewport_size := get_viewport_rect().size
	var log_top: float = enemy_side_ui.get_global_rect().end.y + 16.0*s
	var log_bottom := viewport_size.y - 168.0*s
	action_log_panel.size = Vector2(minf(460*s,viewport_size.x-24*s),minf(360*s,maxf(180*s,log_bottom-log_top)))
	action_log_panel.position = Vector2(viewport_size.x-action_log_panel.size.x-16*s,maxf(log_top,log_bottom-action_log_panel.size.y))


func _layout_splash_panel() -> void:
	if splash_panel == null:
		return
	var s := _ui_scale()
	# The turn bar can extend farther left than the lanes at compact sizes.
	var gutter := middle_info_bar.get_global_rect().position.x - 16.0 * s - maxf(8.0, _screen_pixels_in_ui(6))
	var reveal_scale := clampf(gutter / 200.0, 0.0, s)
	splash_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	splash_panel.size = Vector2(200, 280) * reveal_scale
	splash_panel.position.y = 100.0 * s
	splash_panel.scale = Vector2.ONE
	_position_splash_panel()
	splash_panel.z_index = 40


func _position_splash_panel() -> void:
	if not is_instance_valid(splash_panel):
		return
	var inset := 16.0 * _ui_scale()
	splash_panel.position.x = lerpf(-splash_panel.size.x - inset, inset, splash_slide_progress)


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
	if PlayerData.is_online_battle() or my_player in [1, 2]:
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
	if not bool(ProjectSettings.get_setting("debug/gameplay_verbose_logging",false)): return
	print("=== STATE SNAPSHOT: %s ===" % label)
	print("online=%s host=%s my_player=%d current_player=%d turn=%d is_player_turn=%s" % [PlayerData.is_online_battle(), NetworkManager.is_authority(), my_player, game.current_player, game.turn_number, game.is_player_turn])
	print("P1 hp=%d mana=%d/%d hand=%s slots=%s" % [game.player_field.player_hp, game.player_field.current_mana, game.player_field.max_mana, _card_names(game.player_hand), _slot_names(game.player_field)])
	print("P2 hp=%d mana=%d/%d hand=%s slots=%s" % [game.player2_field.player_hp, game.player2_field.current_mana, game.player2_field.max_mana, _card_names(game.player2_hand), _slot_names(game.player2_field)])
	print("deck=%d discard=%d" % [game.shared_deck.size(), game.shared_discard.size()])


func _broadcast_authority_state(label: String) -> void:
	_print_authority_state(label)
	if PlayerData.is_online_battle() and NetworkManager.is_authority():
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
	if _simulating_web_command:
		game.state_revision += 1
		return
	if PlayerData.is_online_battle() and NetworkManager.is_authority():
		game.state_revision += 1
	_broadcast_authority_state(label)


func _apply_authority_state(state: Dictionary, label: String = "authority") -> void:
	var show_checkpoint_finish: bool = label == "room checkpoint" and game.check_game_over().is_empty()
	if label in ["initial", "reconnect recovery", "room server recovery", "room checkpoint"]:
		_pile_arrivals.clear()
		_suppress_status_feedback_once = true
	var feedback_events: Array = state.get("_feedback_events", [])
	for event in feedback_events:
		if str(event.get("kind", "")) == "broadcast":
			for presentation_event in (event.get("event", {}) as Dictionary).get("presentation_events", []):
				_prime_remote_hand_entry(presentation_event, true)
		elif str(event.get("kind",""))=="presentation":
			for presentation_event in event.get("events",[]): _prime_remote_hand_entry(presentation_event,true)
		else:
			_prime_remote_hand_entry(event, false)
	game.apply_initial_state(state)
	NetworkManager.save_match_snapshot(game.export_initial_state())
	_restore_local_art_paths()
	remote_arrow_source = -1
	remote_arrow_target = -1
	_refresh_hand_ui()
	_check_charm_overflow()
	if not NetworkManager.is_authority():
		_turn_ending = false
		if not _timed_out_action.is_empty():
			NetworkManager.finish_timed_out_command_sync()
		_timed_out_action = ""
		_finish_rejected_action_sync()
	update_entire_screen()
	for ev in feedback_events:
		_replay_feedback_event(ev)
	# Replay floating text for damage/heal that happened on the authority.
	var hp_events: Array = state.get("_hp_events", [])
	_queue_hp_feedback(hp_events)
	if show_checkpoint_finish and not game.check_game_over().is_empty():
		# Recovered summaries omit scene playback. Still show the last HP change.
		_suppress_status_feedback_once = false
		_update_battle_status_huds()
	_check_and_show_game_over()
	# An authoritative summon may have left a choice-requiring battlecry
	# pending for this client. Resume its target picker after the new card UI
	# has been rebuilt; non-targeted summon skills were already resolved by
	# the authority before this state was sent.
	if has_method("_resume_auto_summon_targeting"):
		call_deferred("_resume_auto_summon_targeting")
	_print_authority_state(label)


func _waiting_for_action_state() -> bool:
	return _rejected_action_pending or not _timed_out_action.is_empty()


func _finish_rejected_action_sync() -> void:
	if not _rejected_action_pending:
		return
	_rejected_action_pending = false
	_dismiss_command_prompt(_command_result_prompt)
	if not game.check_game_over().is_empty():
		_command_result_prompt = null
		return
	var can_retry := (bool(game.is_player_turn) and int(game.current_player) == my_player
		and not match_paused and not _waiting_for_room_link() and not _waiting_for_action_state()
		and NetworkManager.pending_game_command_count() == 0)
	_command_result_prompt = weakref(_spawn_toast(Locale.t("tip.command_resynced" if can_retry else "tip.command_not_applied"), "warn"))


func _dismiss_command_prompt(prompt_ref: WeakRef) -> void:
	var prompt := prompt_ref.get_ref() as PanelContainer if prompt_ref != null else null
	if prompt == null:
		return
	var parent := prompt.get_parent()
	if parent != null:
		parent.remove_child(prompt)
	prompt.queue_free()


func _prime_remote_hand_entry(event: Dictionary, deferred: bool) -> void:
	if str(event.get("kind", "")) == "discard":
		event["pile_arrival_token"] = _hold_pile_addition(1)
	if str(event.get("kind", "")) == "hand_entry":
		var meta: Dictionary = event.get("source_meta",{}).duplicate(true)
		_reserve_hand_pile_arrivals(meta,str(event.get("destination","")),str(event.get("source","")))
		event["source_meta"] = meta
	if str(event.get("kind", "")) != "hand_entry" \
			or str(event.get("destination", "")) != "hand" \
			or int(event.get("player", 0)) != _view_player():
		return
	var source_meta: Dictionary = event.get("source_meta", {})
	var source := str(event.get("source", "generated"))
	var key := str(event.get("instance_id", ""))
	if key.is_empty():
		key = str(event.get("entry_key", ""))
	if deferred:
		_pending_hand_entry_ids[key] = {"deferred": true}
		return
	var batch_index := maxi(0, int(source_meta.get("batch_index", 0)))
	var reveal_delay := (BattleFx.draw_card_arrival_delay(batch_index) + BattleFx.reshuffle_arrival_delay(int(source_meta.get("reshuffle_count", 0)))) if source == "deck" else BattleFx.travel_card_arrival_delay(batch_index)
	_pending_hand_entry_ids[key] = {
		"reveal_delay": reveal_delay,
		"feedback": {
			"player": int(event.get("player", 0)),
			"source": source,
			"source_meta": source_meta.duplicate(true),
		},
	}


func _restore_local_art_paths() -> void:
	BattleArtResolver.restore(game)


func _card_identity_key(card: CardData) -> String:
	return BattleArtResolver._card_identity_key(card)


# ============================================
# Init
# ============================================

var _disconnect_overlay: Control
var _online_result_back_btn: Button


var _opening_coin_active := false


func _ready():
	add_to_group("battle_screen")
	enemy_status_hud.get_parent().mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
	hand_container.minimum_size_changed.connect(_sync_hand_area_minimum)
	game = load("res://GameState.gd").new()
	_battle_started_at = Time.get_unix_time_from_system()
	_init_network()
	var opening_player := NetworkManager.match_opening_player if PlayerData.is_online_battle() else PlayerData.hotseat_opening_player
	game.init_game(Callable(self, "_on_game_draw_cards"), null, opening_player)
	_opening_coin_active = opening_player in [1, 2] and not NetworkManager.just_reconnected and DisplayServer.get_name() != "headless"
	_active_challenge_id = PlayerData.practice_challenge_id
	if not _active_challenge_id.is_empty():
		if _active_challenge_id in PracticeChallenges.IDS:
			# Challenge hands and boards must exist before the first UI refresh.
			# Deferring this replacement let the normal shuffled opening hand flash
			# or remain visible when another deferred startup callback won the race.
			PracticeChallenges.configure(game, _active_challenge_id)
			_pending_hand_entry_ids.clear()
			_pending_feedback_events.clear()
		else:
			_active_challenge_id = ""
			PlayerData.practice_challenge_id = ""
	if PlayerData.battle_mode == "tutorial":
		TutorialController.configure_game(game)
	if PlayerData.is_online_battle() and NetworkManager.just_reconnected:
		var saved_state := NetworkManager.load_match_snapshot()
		if not saved_state.is_empty():
			game.apply_initial_state(saved_state)
	elif PlayerData.is_online_battle() and NetworkManager.is_authority():
		NetworkManager.save_match_snapshot(game.export_initial_state())
	_build_turn_cover()
	_build_pile_buttons()
	if PlayerData.is_online_battle():
		var chat := preload("res://presentation/BattleQuickChat.gd").new()
		chat.can_chat = func(): return not battle_finished and not match_paused and not _waiting_for_room_link()
		battle_chat_button = chat
		$CanvasLayer.add_child(chat)
		var cursor := preload("res://presentation/BattleOpponentCursor.gd").new()
		cursor.opposing_lane = enemy_side_ui
		cursor.own_lane = player_side_ui
		cursor.can_share = chat.can_chat
		$CanvasLayer.add_child(cursor)
	_build_action_log()
	_apply_theme()
	_bind_battle_inputs()

	_refresh_hand_ui()
	_apply_responsive_layout()
	middle_info_bar.item_rect_changed.connect(_layout_splash_panel)
	middle_info_bar.item_rect_changed.connect(_align_turn_label)
	player_status_hud.get_node("Margin/Content/SideLabel").item_rect_changed.connect(_align_turn_label)
	player_status_hud.item_rect_changed.connect(_align_turn_label)
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	update_entire_screen()
	if PlayerData.battle_mode == "tutorial":
		tutorial_controller = TutorialController.new()
		add_child(tutorial_controller)
		tutorial_controller.start(self)
	if _active_challenge_id.is_empty():
		if _opening_coin_active:
			_play_opening_coin.call_deferred()
		else:
			_play_opening_draw_feedback.call_deferred()
	if PlayerData.is_online_battle():
		var server_state := NetworkManager.take_pending_server_match_state()
		if not server_state.is_empty() and int(server_state.get("state_revision", -1)) >= game.state_revision:
			_apply_authority_state(server_state, "room server recovery")
		if NetworkManager.just_reconnected:
			_local_slot_rejoined = true
			match_paused = true
			update_entire_screen()
			call_deferred("_request_resume_state")
		elif not NetworkManager.is_authority():
			NetworkManager.request_initial_state()


func _play_opening_coin() -> void:
	if battle_finished:
		_opening_coin_active = false
		return
	var toss := preload("res://presentation/PvpCoinToss.gd").new()
	toss.name = "PvpOpeningCoin"
	toss.setup(game.starting_player, my_player)
	turn_label.hide()
	toss.finished.connect(func():
		_opening_coin_active = false
		turn_label.show()
		if not battle_finished:
			update_entire_screen()
			if game.state_revision == 0:
				_play_opening_draw_feedback())
	add_child(toss)


func is_resolution_locked() -> bool:
	if _random_feedback_pending>0 or not _random_unbatched_events.is_empty(): return true
	if _web_playback_allows_input():
		return _resolution_running or _resolution_pending_steps > 1
	var queued_multistage := false
	for batch in _hp_feedback_batches:
		if _feedback_stage_span(batch) > 1:
			queued_multistage = true
			break
	return _resolution_running or _resolution_pending_steps > 1 or _hp_feedback_running or queued_multistage


func _web_playback_allows_input() -> bool:
	return game != null and PlayerData.is_online_battle() and not match_paused \
		and game.is_player_turn and game.current_player == _view_player()


func _waiting_for_room_link() -> bool:
	return PlayerData.is_online_battle() and NetworkManager.room_link_waiting()


func _on_skill_effect_started(_source: CardData,_effect_id: String,_depth: int) -> void:
	pass

func _on_skill_effect_resolved(_source: CardData,_effect_id: String,_targets: Variant,_depth: int) -> void:
	pass

func _capture_random_board() -> Dictionary:
	return {}

func _on_skill_random_resolved(_source: CardData,_outcome: Dictionary) -> void:
	pass

func _on_random_attack_declared(_attacker: CardData,_victim: CardData,_source_slot: int,_target_slot: int) -> void:
	pass

func _order_random_feedback(events: Array,_before: Dictionary) -> Array:
	return events.duplicate(true)

func _on_first_turn_effect_blocked(_source: CardData, _effect_id: String) -> void:
	_spawn_toast(Locale.t("tip.no_enemy_hp_effect_turn1"), "warn", 1.8)


func _ensure_resolution_blocker() -> void:
	if _resolution_blocker != null and is_instance_valid(_resolution_blocker):
		_resolution_blocker.visible = true
		return
	_resolution_blocker = Control.new()
	_resolution_blocker.name = "ResolutionInputBlocker"
	_resolution_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_resolution_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_resolution_blocker.z_index = 900
	$CanvasLayer.add_child(_resolution_blocker)
	_resolution_blocker.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed and not end_turn_button.disabled:
			if end_turn_button.get_global_rect().has_point(_resolution_blocker.get_global_transform()*event.position):
				_on_end_turn_pressed()
				_resolution_blocker.accept_event())


func _drain_resolution_steps() -> void:
	if _resolution_running:
		return
	_resolution_running = true
	# A lone effect needs no artificial delay. With N effects there are N-1
	# readable gaps, which is what the player experiences as ordered resolution.
	if _resolution_pending_steps > 0:
		_resolution_pending_steps -= 1
	while _resolution_pending_steps > 0 and is_inside_tree():
		_resolution_pending_steps -= 1
		await get_tree().create_timer(EFFECT_PRESENTATION_GAP).timeout
	_resolution_running = false
	if not _hp_feedback_running and _hp_feedback_batches.is_empty() and _resolution_blocker != null and is_instance_valid(_resolution_blocker):
		_resolution_blocker.visible = false
	if is_inside_tree():
		update_entire_screen()


func _on_game_draw_cards(amount: int):
	var drawn = game.draw_cards(amount)
	for card_data in drawn:
		var card_ui = card_ui_scene.instantiate()
		_active_hand_container().add_child(card_ui)
		card_ui.set_card(card_data)
		_scale_control(card_ui, BASE_CARD_SIZE)
		card_ui.is_hand_card = true
		_apply_hand_castability(card_ui, card_data)
		_prepare_hand_entry_ui(card_ui, card_data)
		_connect_hand_card_signals(card_ui)


# ============================================
# Contextual tip toasts (stacked, typed)
# ============================================

func _spawn_toast(text: String, kind: String = "system", hold: float = 1.8) -> PanelContainer:
	if text.strip_edges().is_empty():
		return null
	if not is_instance_valid(_toast_feed):
		_toast_feed = ToastFeed.new()
		$CanvasLayer.add_child(_toast_feed)
	return _toast_feed.show_message(text, kind, hold, _ui_scale())


# Show a short fading tip. Pass a Locale key; args fill % placeholders.
func _show_toast(key: String, args := []) -> void:
	_spawn_toast(Locale.t(key, args), "warn", 1.8)
	if key == "tip.insufficient_mana" and is_instance_valid(_toast_feed):
		_toast_feed.reject_latest()


func _show_abandon_confirmation(layer_index: int = 140, before_confirm: Callable = Callable(), recovery_only: bool = false) -> void:
	if battle_finished or _result_waiting_for_feedback or has_node("AbandonBattleConfirmation"):
		return
	var popup := UITheme.make_popup_layer(self, layer_index)
	var layer: CanvasLayer = popup["layer"]
	layer.name = "AbandonBattleConfirmation"
	layer.set_meta("recovery_only", recovery_only)
	layer.add_to_group("battle_modal")
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -230
	panel.offset_top = -105
	panel.offset_right = 230
	panel.offset_bottom = 105
	UITheme.apply_popup_frame(panel, "gold", false)
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
	var online_match := PlayerData.is_online_battle() or NetworkManager.has_saved_match_session()
	body.text = Locale.t("battle.abandon_confirm_online" if online_match else "battle.abandon_confirm_solo")
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
		if recovery_only and not match_paused and not _waiting_for_room_link():
			return
		if before_confirm.is_valid(): before_confirm.call()
		_abandon_battle_now()
	)
	row.add_child(confirm_btn)
	UITheme.animate_popup_enter(panel)
	cancel_btn.grab_focus()


func _abandon_battle_now() -> void:
	if _result_waiting_for_feedback:
		return
	_record_match_history("forfeit", "")
	battle_finished = true
	practice_ai_running = false
	cancel_attack()
	if PlayerData.is_card_playtest_active():
		var destination := str(PlayerData.card_playtest_context.get("exit_scene", "res://CardEditor.tscn"))
		PlayerData.restore_after_card_playtest()
		UIMotion.replace_scene(destination,true)
		return
	if PlayerData.is_online_battle() or NetworkManager.has_saved_match_session():
		if not await NetworkManager.leave_online_room() or not is_inside_tree():
			return
		UIMotion.replace_scene("res://MainMenu.tscn",true,"online")
		return
	NetworkManager.close_connection()
	UIMotion.replace_scene("res://MainMenu.tscn",true)


# ============================================
# Combat feedback
# ============================================

func _on_hp_changed(_target: CardData,_delta: int,_new_hp: int):
	pass

func _on_damage_resolved(source: CardData, target: CardData, declared: int, actual: int, reduction_pct: int, temp_hp_before: int, reason: String) -> void:
	if target != null and actual == 0 and declared > 0:
		_pending_zero_damage_targets[target.get_instance_id()] = true
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


func _spawn_combat_text(pos: Vector2, delta: int, strong: bool = false, zero_damage: bool = false) -> void:
	BattleFx.combat_text($CanvasLayer, pos, delta, strong, _ui_scale(), zero_damage)
	if strong:
		BattleFx.shake_layer($CanvasLayer, 2.8)


func _spawn_impact_ring(center: Vector2, damage: bool = true, tint: Color = Color()) -> void:
	BattleFx.impact_ring($CanvasLayer, center, damage, tint, _ui_scale())


func _spawn_heal_particles(center: Vector2, amount: int) -> void:
	BattleFx.heal_particles($CanvasLayer, center, amount, _ui_scale())


func _show_combat_feedback_for(player: int, slot: int, delta: int, zero_damage: bool = false) -> void:
	if slot < 0 or slot > 4:
		return
	var slots_ui: Array = _my_slots_ui() if player == _view_player() else _their_slots_ui()
	if slot >= slots_ui.size():
		return
	var slot_ui: Control = slots_ui[slot]
	var center: Vector2 = slot_ui.global_position + slot_ui.size / 2
	_spawn_combat_text(center, delta, abs(delta) >= 4, zero_damage)
	if delta < 0 or zero_damage:
		_spawn_impact_ring(center, true)
	elif delta > 0:
		_spawn_heal_particles(center, delta)
	if delta != 0:
		_play_card_feedback(slot_ui, delta)
	if delta < 0:
		AppAudio.play("heavy" if delta <= -4 else "hurt")
	elif delta == 0 and zero_damage:
		AppAudio.play("blocked")


func _record_feedback_event(kind: String, player: int, slot: int, extra: Dictionary = {}) -> void:
	if PlayerData.is_online_battle() and NetworkManager.is_authority():
		var event := {"kind": kind, "player": player, "slot": slot}
		for key in extra.keys():
			event[key] = extra[key]
		_pending_feedback_events.append(event)


func _replay_feedback_event(event: Dictionary) -> void:
	var kind: String = event.get("kind", "")
	var player: int = int(event.get("player", 0))
	var slot: int = int(event.get("slot", -1))
	var recovered_turn := int(event.get("checkpoint_turn", -1))
	if kind == "broadcast":
		var broadcast_event: Dictionary = event.get("event", {})
		_show_combat_broadcast(_format_action_broadcast(broadcast_event), str(broadcast_event.get("kind", "system")), recovered_turn)
		_queue_presentation_feedback(broadcast_event.get("presentation_events", broadcast_event.get("hp_events", [])))
	elif kind=="presentation":
		_queue_presentation_feedback(event.get("events",[]))
	elif kind == "broadcast_text":
		_show_combat_broadcast(Locale.t(event.get("text_key", "")), "system", recovered_turn)
	elif kind == "hero_damage":
		_show_direct_damage(event.get("result",{}))
	elif kind == "attack":
		_play_attack_feedback(player, slot, int(event.get("target_slot", -1)))
	elif kind == "skill":
		_play_skill_cast_feedback(player, slot, int(event.get("skill_index",-1)))
	elif kind == "summon":
		_play_summon_feedback(_slot_ui_for_player(player, slot))
	elif kind == "cast":
		_play_skill_cast_feedback(player, slot, int(event.get("skill_index",-1)))
	elif kind == "move":
		_play_move_feedback(player, slot, int(event.get("target_slot", -1)), true)
	elif kind == "turn":
		AppAudio.play("turn")
	elif kind == "discard":
		_play_discard_feedback(_discard_source_position(player, str(event.get("location", "hand")), int(event.get("index", -1))), int(event.get("pile_arrival_token", -1)))
	elif kind == "hand_entry":
		var meta: Dictionary = event.get("source_meta", {}).duplicate(true)
		var destination := str(event.get("destination", ""))
		# The local hand card starts its flight from the container's post-sort
		# callback, which provides an exact landing slot and owns the connection's
		# lifetime. Other destinations can replay immediately.
		if destination != "hand" or player != _view_player():
			_play_hand_resolution_feedback(
				_find_feedback_card(str(event.get("instance_id", ""))),
				player,
				destination,
				str(event.get("source", "generated")),
				meta
			)
		if destination == "discard":
			_spawn_toast(Locale.t("tip.hand_overflow", [str(event.get("card_name", Locale.t("battle.card")))]), "warn", 2.0)


func _find_feedback_card(instance_id: String) -> CardData:
	if instance_id == "":
		return null
	var collections: Array = [game.player_hand, game.player2_hand, game.shared_deck, game.shared_discard]
	for cards: Array in collections:
		for card in cards:
			if card is CardData and card.instance_id == instance_id:
				return card
	for field: BattleField in [game.player_field, game.player2_field]:
		for card in field.slots:
			if card is CardData and card.instance_id == instance_id:
				return card
	return null


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
func _play_hero_attack_feedback(player: int, source_slot: int) -> void:
	_play_attack_feedback(player,source_slot)


func _play_attack_feedback(player: int, source_slot: int, target_slot: int = -1) -> void:
	if not _playing_random_action and _defer_action_feedback(_play_attack_feedback.bind(player,source_slot,target_slot)):
		_random_attack_motion = {"kind":"attack_motion","player":player,"source_slot":source_slot,"target_slot":target_slot,"feedback_group":0}
		return
	if not _playing_random_action and (_random_feedback_pending>0 or not _random_unbatched_events.is_empty()): return
	AppAudio.play("swoosh")
	_show_unit_action_splash(player, source_slot)
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


# Keep deployment readable before skill visuals, card travel and their sounds.
func _deployment_feedback_delay() -> float:
	return maxf(0.0, float(_deployment_feedback_until_msec - Time.get_ticks_msec()) / 1000.0)


func _begin_deployment_feedback() -> void:
	# Preserve a readable landing beat even at the fastest playback speed.
	var delay := 0.65 * GamePreferences.battle_animation_duration_scale() / GamePreferences.STANDARD_ANIMATION_DURATION_SCALE
	_deployment_feedback_until_msec = Time.get_ticks_msec() + ceili(delay * 1000.0)


func _wait_for_deployment_feedback() -> void:
	while is_inside_tree() and _deployment_feedback_delay() > 0.0:
		await get_tree().create_timer(_deployment_feedback_delay()).timeout


func _defer_deployment_feedback(feedback: Callable) -> bool:
	var delay := _deployment_feedback_delay()
	if delay <= 0.0:
		return false
	get_tree().create_timer(delay).timeout.connect(func():
		if is_inside_tree() and not battle_finished: feedback.call()
	)
	return true


# Pop-in landing effect for a freshly summoned card in a slot.
func _play_summon_feedback(slot_ui: Control) -> void:
	_begin_deployment_feedback()
	if slot_ui == null or not is_instance_valid(slot_ui):
		return
	# Screen refreshes are coalesced and deferred. Summon callers mutate game
	# state, queue the refresh, then request feedback; wait until the new CardUI
	# actually exists instead of silently dropping the animation.
	if _screen_refresh_queued:
		_play_summon_feedback.call_deferred(slot_ui)
		return
	AppAudio.play("summon")
	var card_ui = slot_ui.get("current_card_ui")
	if card_ui == null or not is_instance_valid(card_ui):
		return
	if card_ui.get("current_card_data") != null: _show_splash(card_ui.current_card_data)
	BattleFx.summon_landing($CanvasLayer, slot_ui, _ui_scale())


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
		_append_move_entry(entries, dst_ui, to_dst, src_center, dst_ui)
		_append_move_entry(entries, src_ui, to_src, dst_center, src_ui)
	else:
		# Pre-swap: the moved card sits in source_slot, the displaced card in target_slot.
		_append_move_entry(entries, src_ui, to_dst, Vector2.INF, dst_ui)
		_append_move_entry(entries, dst_ui, to_src, Vector2.INF, src_ui)
	BattleFx.move_swap($CanvasLayer, entries, _ui_scale())


func _append_move_entry(entries: Array, slot_ui: Control, delta: Vector2, start_pos: Vector2 = Vector2.INF, target_slot: Control = null) -> void:
	var card_ui = slot_ui.get("current_card_ui")
	if card_ui == null or not is_instance_valid(card_ui):
		return
	entries.append([card_ui, delta, start_pos, target_slot])


func _turn_owner_text() -> String:
	if not PlayerData.is_online_battle() and PlayerData.battle_mode == "hotseat":
		return Locale.t("battle.hotseat_turn", [game.current_player])
	return Locale.t("battle.your_turn") if game.current_player == _view_player() else Locale.t("battle.opponent_turn")


func _play_skill_cast_feedback(player: int, slot: int, skill_index: int = -1) -> void:
	if _defer_action_feedback(_play_skill_cast_feedback.bind(player,slot,skill_index)): return
	if _defer_random_feedback(_play_skill_cast_feedback.bind(player,slot,skill_index)): return
	if _defer_deployment_feedback(_play_skill_cast_feedback.bind(player, slot, skill_index)): return
	# Hand-cast spells have no field slot; render an arcane burst + projectile
	# flying from the hand toward the battlefield center instead.
	if slot < 0:
		_play_spell_cast_from_hand_feedback()
		return
	var source: CardData = _field_for_player(player).slots[slot]
	if source != null:
		var ability := ""
		if skill_index < 0:
			for i in source.skills.size():
				if source.skills[i].get("trigger", "") == SkillEngine.TRIGGER_ON_ACTIVATE:
					skill_index=i
					break
		if skill_index >= 0 and skill_index < source.skills.size() and source.skills[skill_index].get("trigger", "") == SkillEngine.TRIGGER_ON_ACTIVATE:
			ability = str(source.skills[skill_index].get("skill_name", "")).strip_edges()
			if ability.is_empty(): ability = ("技能 %d" if Locale.language=="zh" else "Skill %d") % (skill_index+1)
		_show_splash(source,ability)
	var slot_ui := _slot_ui_for_player(player, slot)
	var target := _card_feedback_target(slot_ui)
	if target == null or not is_instance_valid(target):
		return
	var center: Vector2 = slot_ui.global_position + slot_ui.size / 2
	BattleFx.skill_cast_pulse($CanvasLayer, target, center, _ui_scale())


# Arcane burst at the hand + a projectile flying to the battlefield center for
# spells cast directly from hand (slot == -1).
func _show_unit_action_splash(player: int, slot: int) -> void:
	var field := _field_for_player(player)
	if slot >= 0 and slot < field.slots.size():
		_show_splash(field.slots[slot])


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
	if delta > 0: AppAudio.play("heal")
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
func _show_floating_for(player: int, slot: int, delta: int, zero_damage: bool = false) -> void:
	_show_combat_feedback_for(player, slot, delta, zero_damage)


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
	_random_action_before = _capture_random_board()
	_random_attack_motion.clear()
	_action_broadcast = {"kind": kind, "player": player, "source": source_name, "target": target_name}
	_action_feedback_next_group = 0
	_action_feedback_group_stack = [0]
	for key in extra.keys():
		_action_broadcast[key] = extra[key]
	_action_hp_events.clear()
	_action_presentation_events.clear()
	_action_damage_events.clear()
	_action_parasite_events.clear()
	_action_failed_events.clear()


func _finish_action_broadcast() -> void:
	if _action_broadcast.is_empty():
		_action_hp_events.clear()
		_action_presentation_events.clear()
		_action_damage_events.clear()
		_action_parasite_events.clear()
		_action_failed_events.clear()
		return
	var event := _action_broadcast.duplicate(true)
	event["hp_events"] = _action_hp_events.duplicate(true)
	event["presentation_events"] = _order_random_feedback(_action_presentation_events,_random_action_before)
	event["damage_events"] = _action_damage_events.duplicate(true)
	event["parasite_events"] = _action_parasite_events.duplicate(true)
	event["failed_events"] = _action_failed_events.duplicate(true)
	_queue_presentation_feedback(event["presentation_events"])
	var text := _format_action_broadcast(event)
	_show_combat_broadcast(text, str(event.get("kind", "system")))
	if PlayerData.is_online_battle() and NetworkManager.is_authority():
		_pending_feedback_events.append({"kind": "broadcast", "event": event})
	_action_broadcast.clear()
	_action_hp_events.clear()
	_action_presentation_events.clear()
	_action_damage_events.clear()
	_action_parasite_events.clear()
	_action_failed_events.clear()
	_action_feedback_group_stack.clear()


func _format_action_broadcast(event: Dictionary) -> String:
	return BattleLogFormatter.format_event(event, _view_player())


# Cross-layer interface implemented by the action, presentation, and network components.
func _bind_battle_inputs() -> void:
	pass

func _build_action_log() -> void:
	pass


func _show_combat_broadcast(_text: String, _kind: String = "system", _recovered_turn: int = -1) -> void:
	pass


func _show_splash(_card: CardData, _skill_name: String = "") -> void:
	pass



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

func _on_card_discarded(card_data: CardData, _drop_position: Vector2 = Vector2.INF):
	pass

func _on_card_drag_cast_on_enemy(card_data: CardData, origin_ui, enemy_slot_index: int) -> void:
	pass

func _on_card_drag_summoned(card_data, origin_ui, slot_index: int):
	pass

func _on_end_turn_pressed():
	pass

func _on_enemy_slot_clicked(enemy_index: int):
	pass

func _on_make_zero_cost_select(reduction: int, cost_mode: String, _current_player: int, hand: Array, target: String, _random_count: int) -> void:
	pass

func _on_hand_entry_resolved(_card: CardData, _player: int, _destination: String, _source: String, _source_meta: Dictionary) -> void:
	pass

func _on_enemy_hand_discarded(_actor: int,_before_count: int,_cards: Array) -> void:
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

func _play_discard_feedback(_start: Vector2 = Vector2.INF, _token: int = -1) -> void:
	pass


func _discard_source_position(player: int, location: String, index: int) -> Vector2:
	if location == "field":
		var slot := _slot_ui_for_player(player,index)
		if slot != null: return slot.get_global_rect().get_center()
	if player == _view_player() and index >= 0 and index < hand_container.get_child_count():
		return (hand_container.get_child(index) as Control).get_global_rect().get_center()
	return call("_draw_fly_target_for_player",player)

func _play_draw_fly_feedback(player: int, count: int) -> void:
	pass

func _play_hand_card_enter_feedback(card_ui: Control) -> void:
	pass

func _prepare_hand_entry_ui(_card_ui: Control, _card_data: CardData) -> void:
	pass

func _play_hand_resolution_feedback(_card: CardData, _player: int, _destination: String, _source: String, _source_meta: Dictionary) -> void:
	pass

func _play_staged_hand_entry(_event: Dictionary) -> void:
	pass

func _queue_hp_feedback(_events: Array) -> void:
	pass

func _queue_presentation_feedback(_events: Array) -> void:
	pass

func _feedback_stage_span(_events: Array) -> int:
	return 0

func _play_opening_draw_feedback() -> void:
	pass

func _record_match_history(outcome: String, result: String) -> void:
	pass

func _refresh_hand_ui():
	pass

func reset_hand_ui_from_game_state() -> void:
	pass

func _update_wait_hint_layout() -> void:
	pass

func cancel_attack():
	pass

func update_entire_screen():
	pass


func _update_battle_status_huds() -> void:
	pass

func _apply_deaths():
	pass

func _hand_index_of(card_ui) -> int:
	return 0

func _host_apply_attack(source_slot: int, target_slot: int, player: int) -> void:
	pass

func _host_apply_cast(hand_index: int, skill_index: int, target_slot: int, player: int, target_player: int = 0) -> void:
	pass

func _host_apply_discard(location: String, index: int, player: int, _drop_position: Vector2 = Vector2.INF) -> void:
	pass

func _host_apply_end_turn(player: int, _allow_face_mana: bool = true) -> void:
	pass

func _host_apply_move(source_slot: int, target_slot: int, player: int) -> void:
	pass

func _host_apply_parasite(hand_index: int, target_player: int, target_slot: int, player: int) -> void:
	pass

func _host_apply_skill(slot_index: int, skill_index: int, target_slot: int, player: int) -> void:
	pass

func _host_apply_summon(hand_index: int, slot_index: int, player: int) -> void:
	pass

func _host_apply_summon_skill(slot_index: int, skill_index: int, target_slot: int, player: int, target_player: int = 0, commit_state: bool = true) -> void:
	pass

func _parasite_intent_source(hand_index: int, target_player: int) -> int:
	return 0

func _show_direct_damage(result: Dictionary):
	pass

func _wait_for_direct_damage() -> void:
	pass


func _play_death_feedback(_slot_ui: Control) -> void:
	pass

func _spell_intent_source(hand_index: int) -> int:
	return 0

func _sync_targeting_state():
	pass

func is_my_turn() -> bool:
	return false

func _owns_current_turn() -> bool:
	return false

func _turn_request_playback_pending() -> bool:
	return false

func _defer_random_feedback(_feedback: Callable) -> bool:
	return false

func _defer_action_feedback(feedback: Callable) -> bool:
	if _playing_deferred_feedback: return false
	_run_deferred_action_feedback.call_deferred(feedback)
	return true

func _run_deferred_action_feedback(feedback: Callable) -> void:
	if not is_inside_tree() or not feedback.is_valid(): return
	_playing_deferred_feedback = true
	feedback.call()
	_playing_deferred_feedback = false
	if _random_unbatched_events.is_empty(): _random_attack_motion.clear()

func _wait_for_random_feedback() -> void:
	pass

func _process_resume_sync() -> void:
	pass

func _on_resume_retry_pressed() -> void:
	pass

func _toggle_turn_cover():
	pass

func _update_pile_labels():
	pass

func _sync_face_mana_toggle() -> void:
	if not is_instance_valid(face_mana_button) or game == null: return
	var turn_key := "%d/%d" % [game.current_player,game.turn_number]
	if turn_key != _face_mana_turn_key or battle_finished:
		face_mana_button.set_pressed_no_signal(false)
		_face_mana_turn_key = turn_key
	face_mana_button.visible = game.battle_config.has("action_base")
	face_mana_button.disabled = not is_my_turn()

func _reset_face_mana_toggle() -> void:
	if is_instance_valid(face_mana_button): face_mana_button.set_pressed_no_signal(false)
