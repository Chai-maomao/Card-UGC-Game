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

@onready var enemy_side_ui = $CanvasLayer/MainBackground/MainLayout/EnemySide
@onready var player_side_ui = $CanvasLayer/MainBackground/MainLayout/PlayerSide
@onready var mana_label = $CanvasLayer/MainBackground/MainLayout/MiddleInfoBar/InfoHBox/ManaLabel
@onready var status_toggle_button = $CanvasLayer/MainBackground/MainLayout/MiddleInfoBar/InfoHBox/StatusToggleButton
@onready var end_turn_button = $CanvasLayer/MainBackground/MainLayout/MiddleInfoBar/InfoHBox/EndTurnButton
@onready var attack_arrow = $CanvasLayer/AttackArrow
@onready var hand_container = $CanvasLayer/MainBackground/MainLayout/HandArea/HandScroll/HandContainer
@onready var splash_panel = $CanvasLayer/SplashPanel
@onready var splash_art = $CanvasLayer/SplashPanel/SplashArt
@onready var splash_name = $CanvasLayer/SplashPanel/SplashName
@onready var splash_text = $CanvasLayer/SplashPanel/SplashText
@onready var discard_zone = $CanvasLayer/DiscardZone

var splash_tween: Tween
var turn_cover: ColorRect
var turn_wait_hint: Panel
var draw_pile_btn: Button
var discard_pile_btn: Button
var debug_state_btn: Button
var help_btn: Button
var toast_label: Label
var toast_tween: Tween
var combat_broadcast_label: Label
var combat_broadcast_tween: Tween
var show_enemy_status: bool = false
var practice_ai_running: bool = false
var battle_finished: bool = false
var _turn_ending: bool = false  # 防止短时间内重复点击结束按钮
var feedback_targets: Dictionary = {}
var _pending_feedback_events: Array = []
var _action_broadcast: Dictionary = {}
var _action_hp_events: Array = []
var _action_damage_events: Array = []
var _action_parasite_events: Array = []
var _action_failed_events: Array = []
const BASE_VIEWPORT_SIZE := Vector2(1152, 648)
const BASE_CARD_SIZE := Vector2(120, 160)
const BASE_SLOT_SIZE := BASE_CARD_SIZE
const BASE_PILE_BUTTON_SIZE := Vector2(120, 50)
const BASE_DEBUG_BUTTON_SIZE := Vector2(130, 50)
const BASE_HELP_BUTTON_SIZE := Vector2(90, 50)


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
	UITheme.apply_app_background($CanvasLayer/MainBackground)
	UITheme.apply_panel($CanvasLayer/MainBackground/MainLayout/MiddleInfoBar, "gold")
	UITheme.apply_panel(discard_zone, "dark")
	UITheme.apply_panel(splash_panel, "gold")
	UITheme.apply_label(mana_label)
	UITheme.apply_button(status_toggle_button, "secondary")
	UITheme.apply_button(end_turn_button, "primary")
	for btn in [draw_pile_btn, discard_pile_btn, debug_state_btn, help_btn]:
		UITheme.apply_button(btn, "secondary")
	var discard_label := $CanvasLayer/DiscardZone/DiscardLabel
	UITheme.apply_label(discard_label)
	UITheme.apply_title(splash_name, 18)
	UITheme.apply_label(splash_text)


func _apply_responsive_layout() -> void:
	var s := _ui_scale()
	var viewport_size := get_viewport_rect().size
	var bottom_y: float = max(0.0, viewport_size.y - 48.0 * s)

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

	# Middle info bar (mana label + buttons)
	if mana_label:
		mana_label.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	if status_toggle_button:
		status_toggle_button.add_theme_font_size_override("font_size", max(10, int(14 * s)))
		status_toggle_button.custom_minimum_size = Vector2(120 * s, 0)
	if end_turn_button:
		end_turn_button.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	var info_hbox := $CanvasLayer/MainBackground/MainLayout/MiddleInfoBar/InfoHBox
	info_hbox.add_theme_constant_override("separation", int(20 * s))

	# Spacers
	$CanvasLayer/MainBackground/MainLayout/TopSpacer.custom_minimum_size = Vector2(0, 12 * s)
	$CanvasLayer/MainBackground/MainLayout/MidSpacer.custom_minimum_size = Vector2(0, 8 * s)
	$CanvasLayer/MainBackground/MainLayout/BottomSpacer.custom_minimum_size = Vector2(0, 6 * s)
	$CanvasLayer/MainBackground/MainLayout/HandSpacer.custom_minimum_size = Vector2(0, 4 * s)
	$CanvasLayer/MainBackground/MainLayout/HandArea.custom_minimum_size = Vector2(0, 170 * s)

	# Pile buttons (bottom-left)
	var pile_gap := 10.0 * s
	var pile_x := 20.0 * s
	if draw_pile_btn:
		UITheme.apply_button(draw_pile_btn, "secondary")
		_scale_control(draw_pile_btn, BASE_PILE_BUTTON_SIZE)
		draw_pile_btn.position = Vector2(pile_x, bottom_y)
		draw_pile_btn.add_theme_font_size_override("font_size", max(9, int(12 * s)))
		pile_x += BASE_PILE_BUTTON_SIZE.x * s + pile_gap
	if discard_pile_btn:
		UITheme.apply_button(discard_pile_btn, "secondary")
		_scale_control(discard_pile_btn, BASE_PILE_BUTTON_SIZE)
		discard_pile_btn.position = Vector2(pile_x, bottom_y)
		discard_pile_btn.add_theme_font_size_override("font_size", max(9, int(12 * s)))
		pile_x += BASE_PILE_BUTTON_SIZE.x * s + pile_gap
	if debug_state_btn:
		UITheme.apply_button(debug_state_btn, "secondary")
		_scale_control(debug_state_btn, BASE_DEBUG_BUTTON_SIZE)
		debug_state_btn.position = Vector2(pile_x, bottom_y)
		debug_state_btn.add_theme_font_size_override("font_size", max(9, int(12 * s)))
		pile_x += BASE_DEBUG_BUTTON_SIZE.x * s + pile_gap
	if help_btn:
		UITheme.apply_button(help_btn, "secondary")
		_scale_control(help_btn, BASE_HELP_BUTTON_SIZE)
		help_btn.position = Vector2(pile_x, bottom_y)
		help_btn.add_theme_font_size_override("font_size", max(9, int(12 * s)))
	_scale_toast()
	_update_wait_hint_layout()

	# Discard zone (bottom-right anchored – offsets only, no size)
	if discard_zone:
		discard_zone.offset_left = -170.0 * s
		discard_zone.offset_top = -80.0 * s
		discard_zone.offset_right = 0.0
		discard_zone.offset_bottom = 0.0
		var discard_label := $CanvasLayer/DiscardZone/DiscardLabel
		discard_label.text = Locale.t("battle.discard_zone")
		discard_label.add_theme_font_size_override("font_size", max(10, int(18 * s)))


func _on_viewport_size_changed() -> void:
	_apply_responsive_layout()
	update_entire_screen()


# ============================================
# Helpers
# ============================================

func _view_player() -> int:
	if NetworkManager.is_online:
		return my_player
	if PlayerData.battle_mode == "practice":
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
		# Ship combat feedback from this action so the non-authority can replay
		# presentation without running combat logic itself.
		state["_hp_events"] = _pending_hp_events.duplicate()
		state["_feedback_events"] = _pending_feedback_events.duplicate()
		_pending_hp_events.clear()
		_pending_feedback_events.clear()
		NetworkManager.rpc_authority_state.rpc(state)


func _apply_authority_state(state: Dictionary, label: String = "authority") -> void:
	game.apply_initial_state(state)
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
	if not NetworkManager.is_online or NetworkManager.is_authority():
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
var _disconnect_reconnect_btn: Button
var _disconnect_back_btn: Button


func _ready():
	game = load("res://GameState.gd").new()
	_init_network()
	game.init_game(Callable(self, "_on_game_draw_cards"))
	_build_turn_cover()
	_build_pile_buttons()
	_apply_theme()
	if $CanvasLayer/MainBackground:
		$CanvasLayer/MainBackground.mouse_filter = Control.MOUSE_FILTER_PASS
		$CanvasLayer/MainBackground.gui_input.connect(_on_battle_background_gui_input)

	var p_slots = player_side_ui.get_children()
	var e_slots = enemy_side_ui.get_children()

	for i in range(p_slots.size()):
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
	if status_toggle_button:
		status_toggle_button.pressed.connect(_on_status_toggle_pressed)

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
	_play_opening_draw_feedback.call_deferred()
	if NetworkManager.is_online and not NetworkManager.is_authority():
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
		_play_hand_card_enter_feedback(card_ui)
		# Hand cards drawn mid-game also need skill-signal connections.
		var hand: Array = _my_hand()
		var hi: int = hand.find(card_data)
		if hi >= 0:
			_connect_hand_card_signals(card_ui, hi)


# ============================================
# Contextual tip toast
# ============================================

func _build_toast() -> void:
	toast_label = Label.new()
	toast_label.name = "TipToast"
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label.anchor_left = 0.5
	toast_label.anchor_right = 0.5
	toast_label.anchor_top = 0.18
	toast_label.anchor_bottom = 0.18
	toast_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.85)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	toast_label.add_theme_stylebox_override("normal", style)
	toast_label.add_theme_color_override("font_color", Color(1, 0.95, 0.7))
	toast_label.modulate.a = 0.0
	$CanvasLayer.add_child(toast_label)
	_scale_toast()


func _scale_toast() -> void:
	if toast_label == null:
		return
	var s := _ui_scale()
	toast_label.add_theme_font_size_override("font_size", max(12, int(20 * s)))
	toast_label.custom_minimum_size = Vector2(360 * s, 0)
	toast_label.offset_left = -180.0 * s
	toast_label.offset_right = 180.0 * s


# Show a short fading tip. Pass a Locale key; args fill % placeholders.
func _show_toast(key: String, args := []) -> void:
	if toast_label == null:
		_build_toast()
	toast_label.text = Locale.t(key, args)
	if toast_tween and toast_tween.is_valid():
		toast_tween.kill()
	toast_label.modulate.a = 0.0
	$CanvasLayer.move_child(toast_label, $CanvasLayer.get_child_count() - 1)
	toast_tween = create_tween()
	toast_tween.tween_property(toast_label, "modulate:a", 1.0, 0.15)
	toast_tween.tween_interval(1.8)
	toast_tween.tween_property(toast_label, "modulate:a", 0.0, 0.4)


func _build_combat_broadcast() -> void:
	_build_toast()


func _scale_combat_broadcast() -> void:
	_scale_toast()


func _show_combat_broadcast(text: String) -> void:
	if text.strip_edges() == "":
		return
	if toast_label == null:
		_build_toast()
	toast_label.text = text
	if toast_tween and toast_tween.is_valid():
		toast_tween.kill()
	toast_label.modulate.a = 0.0
	$CanvasLayer.move_child(toast_label, $CanvasLayer.get_child_count() - 1)
	toast_tween = create_tween()
	toast_tween.tween_property(toast_label, "modulate:a", 1.0, 0.06)
	toast_tween.tween_interval(3.1)
	toast_tween.tween_property(toast_label, "modulate:a", 0.0, 0.14)


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


func _spawn_floating_text(pos: Vector2, delta: int) -> void:
	_spawn_combat_text(pos, delta)


func _spawn_combat_text(pos: Vector2, delta: int, strong: bool = false) -> void:
	if delta == 0:
		return
	var is_damage: bool = delta < 0
	var lbl := Label.new()
	lbl.text = ("-%d" % -delta) if is_damage else ("+%d" % delta)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", Color(1.0, 0.22, 0.12) if is_damage else Color(0.35, 1.0, 0.58))
	lbl.add_theme_color_override("font_outline_color", Color(0.08, 0.02, 0.01, 0.95) if is_damage else Color(0.02, 0.08, 0.03, 0.95))
	lbl.add_theme_constant_override("outline_size", 5 if strong else 4)
	lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	lbl.add_theme_constant_override("shadow_offset_x", 2)
	lbl.add_theme_constant_override("shadow_offset_y", 3)
	lbl.add_theme_font_size_override("font_size", 42 if strong else 34)
	lbl.pivot_offset = Vector2(34, 20)
	var side_offset: Vector2 = Vector2(16, -30) if is_damage else Vector2(-16, -26)
	var random_offset := Vector2(randf_range(-20.0, 20.0), randf_range(-10.0, 12.0))
	lbl.position = pos + side_offset + random_offset
	lbl.scale = Vector2(0.55, 0.55) if is_damage else Vector2(0.68, 0.68)
	lbl.modulate.a = 0.0
	$CanvasLayer.add_child(lbl)
	$CanvasLayer.move_child(lbl, $CanvasLayer.get_child_count() - 1)

	var rise: float = (56.0 if is_damage else 68.0) + randf_range(-6.0, 8.0)
	var drift: float = (12.0 if is_damage else -10.0) + randf_range(-18.0, 18.0)
	var peak_scale: Vector2 = Vector2(1.55, 1.55) if strong and is_damage else (Vector2(1.34, 1.34) if is_damage else Vector2(1.18, 1.18))
	var settle_scale: Vector2 = Vector2(1.14, 1.14) if is_damage else Vector2(1.0, 1.0)
	var twn := create_tween()
	twn.set_parallel(true)
	twn.tween_property(lbl, "modulate:a", 1.0, 0.07)
	twn.tween_property(lbl, "scale", peak_scale, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	twn.tween_property(lbl, "position", lbl.position + Vector2(drift, -rise), 0.82).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	twn.tween_property(lbl, "scale", settle_scale, 0.18).set_delay(0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	twn.tween_property(lbl, "modulate:a", 0.0, 0.28).set_delay(0.50)
	twn.chain().tween_callback(lbl.queue_free)


func _spawn_impact_ring(center: Vector2, damage: bool = true) -> void:
	var ring := ColorRect.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.color = Color(1.0, 0.22, 0.12, 0.30) if damage else Color(0.35, 1.0, 0.58, 0.24)
	ring.size = Vector2(38, 38)
	ring.pivot_offset = ring.size / 2
	ring.position = center - ring.size / 2
	$CanvasLayer.add_child(ring)
	$CanvasLayer.move_child(ring, $CanvasLayer.get_child_count() - 1)
	var twn := create_tween()
	twn.set_parallel(true)
	twn.tween_property(ring, "scale", Vector2(2.0, 2.0), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	twn.tween_property(ring, "modulate:a", 0.0, 0.22)
	twn.chain().tween_callback(ring.queue_free)


func _spawn_heal_particles(center: Vector2, amount: int) -> void:
	var count: int = clampi(4 + amount, 5, 10)
	for i in range(count):
		var dot := ColorRect.new()
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.color = Color(0.38, 1.0, 0.58, 0.78)
		var size: float = 5.0 + float(i % 3)
		dot.size = Vector2(size, size)
		dot.pivot_offset = dot.size / 2
		var start_angle: float = TAU * float(i) / float(count)
		var start_radius: float = 14.0 + float(i % 2) * 6.0
		var start: Vector2 = center + Vector2(cos(start_angle), sin(start_angle)) * start_radius
		dot.position = start
		$CanvasLayer.add_child(dot)
		$CanvasLayer.move_child(dot, $CanvasLayer.get_child_count() - 1)
		var end: Vector2 = start + Vector2(cos(start_angle) * 10.0, -34.0 - float(i % 4) * 6.0)
		var twn := create_tween()
		twn.set_parallel(true)
		twn.tween_property(dot, "position", end, 0.55 + float(i % 3) * 0.05).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		twn.tween_property(dot, "scale", Vector2(0.25, 0.25), 0.55)
		twn.tween_property(dot, "modulate:a", 0.0, 0.36).set_delay(0.18)
		twn.chain().tween_callback(dot.queue_free)


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
		_show_combat_broadcast(_format_action_broadcast(event.get("event", {})))
	elif kind == "broadcast_text":
		_show_combat_broadcast(Locale.t(event.get("text_key", "")))
	elif kind == "attack":
		_play_attack_feedback(player, slot, int(event.get("target_slot", -1)))
	elif kind == "skill":
		_play_skill_cast_feedback(player, slot)
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


func _play_attack_feedback(player: int, source_slot: int, target_slot: int = -1) -> void:
	var slot_ui := _slot_ui_for_player(player, source_slot)
	var target := _card_feedback_target(slot_ui)
	if target == null or not is_instance_valid(target):
		return
	var base_position: Vector2 = target.position if target is Control else Vector2.ZERO
	var base_scale: Vector2 = target.scale if target is Control else Vector2.ONE
	var base_modulate: Color = target.modulate
	var direction := Vector2(0, -10)
	if target_slot >= 0:
		var target_ui := _slot_ui_for_player(_opponent_of_player(player), target_slot)
		if target_ui != null:
			var diff: Vector2 = target_ui.global_position - slot_ui.global_position
			if diff.length() > 0.0:
				direction = diff.normalized() * 14.0
	target.modulate = Color(1.25, 1.16, 0.72, 1.0)
	var twn := create_tween()
	twn.set_parallel(false)
	if target is Control:
		twn.tween_property(target, "position", base_position + direction, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		twn.parallel().tween_property(target, "scale", base_scale * 1.06, 0.08)
		twn.tween_property(target, "position", base_position, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		twn.parallel().tween_property(target, "scale", base_scale, 0.12)
	twn.parallel().tween_property(target, "modulate", base_modulate, 0.16)


func _play_skill_cast_feedback(player: int, slot: int) -> void:
	var slot_ui := _slot_ui_for_player(player, slot)
	var target := _card_feedback_target(slot_ui)
	if target == null or not is_instance_valid(target):
		return
	var base_scale: Vector2 = target.scale if target is Control else Vector2.ONE
	var base_modulate: Color = target.modulate
	target.modulate = Color(0.72, 0.9, 1.35, 1.0)
	var center: Vector2 = slot_ui.global_position + slot_ui.size / 2
	_spawn_impact_ring(center, false)
	var twn := create_tween()
	twn.set_parallel(true)
	if target is Control:
		twn.tween_property(target, "scale", base_scale * 1.08, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		twn.tween_property(target, "scale", base_scale, 0.18).set_delay(0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	twn.tween_property(target, "modulate", base_modulate, 0.26)


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
	var key: int = target.get_instance_id()
	if not feedback_targets.has(key):
		feedback_targets[key] = {
			"position": target.position if target is Control else Vector2.ZERO,
			"scale": target.scale if target is Control else Vector2.ONE,
			"modulate": target.modulate,
			"tween": null,
		}
	var data: Dictionary = feedback_targets[key]
	var old_tween: Tween = data.get("tween")
	if old_tween != null and old_tween.is_valid():
		old_tween.kill()
	if target is Control:
		target.position = data["position"]
		target.scale = data["scale"]
	target.modulate = data["modulate"]
	var base_modulate: Color = data["modulate"]
	var base_position: Vector2 = data["position"]
	var base_scale: Vector2 = data["scale"]
	var flash := Color(1.0, 0.44, 0.34) if delta < 0 else Color(0.54, 1.0, 0.64)
	var twn := create_tween()
	data["tween"] = twn
	feedback_targets[key] = data
	twn.set_parallel(false)
	twn.tween_property(target, "modulate", flash, 0.04)
	if target is Control:
		if delta < 0:
			twn.parallel().tween_property(target, "scale", Vector2(base_scale.x * 1.07, base_scale.y * 0.92), 0.04)
			twn.parallel().tween_property(target, "position", base_position + Vector2(8, -1), 0.035)
			twn.tween_property(target, "position", base_position + Vector2(-7, 1), 0.04)
			twn.parallel().tween_property(target, "scale", Vector2(base_scale.x * 0.96, base_scale.y * 1.05), 0.04)
			twn.tween_property(target, "position", base_position + Vector2(5, 0), 0.035)
			twn.tween_property(target, "position", base_position + Vector2(-3, 0), 0.035)
			twn.tween_property(target, "position", base_position, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			twn.parallel().tween_property(target, "scale", base_scale, 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			twn.parallel().tween_property(target, "scale", base_scale * 1.07, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			twn.tween_property(target, "scale", base_scale, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	twn.tween_property(target, "modulate", base_modulate, 0.18)
	twn.finished.connect(_finish_card_feedback.bind(key, base_position, base_scale, base_modulate))


func _finish_card_feedback(key: int, base_position: Vector2, base_scale: Vector2, base_modulate: Color) -> void:
	var target := instance_from_id(key) as CanvasItem
	if target != null and is_instance_valid(target):
		if target is Control:
			target.position = base_position
			target.scale = base_scale
		target.modulate = base_modulate
	feedback_targets.erase(key)


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
	_show_combat_broadcast(text)
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
			var skill_name: String = event.get("skill", "技能")
			return _format_skill_broadcast(subject, skill_name, hp_events, damage_events, parasite_events, failed_events)
		"cast":
			return _format_skill_broadcast(subject, "施放", hp_events, damage_events, parasite_events, failed_events)
	return ""


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
			heals.append("%s恢复了%d点生命" % [ev.get("card", "单位"), delta])
	var target_detail := _damage_detail_for(damage_events, target_player, target_slot)
	if target_damage == 0 and not target_detail.is_empty():
		target_damage = int(target_detail.get("actual", 0))
	var target_declared: int = base_damage if effective_damage != base_damage else int(target_detail.get("declared", effective_damage))
	var parts := []
	var intro := "%s攻击了%s%s" % [subject, _side_text(target_player), target]
	if target_declared > 0 and (target_damage > 0 or target_declared != target_damage):
		if target_declared != target_damage:
			parts.append("%s，原本造成%d点伤害，但因为一些原因，实际造成%d点伤害" % [intro, target_declared, target_damage])
		else:
			parts.append("%s，造成%d点伤害" % [intro, target_damage])
	else:
		parts.append(intro)
	if adjacent_damage > 0:
		parts.append("并且对%s两边的%d个单位共造成%d点溅射伤害" % [target, adjacent_count, adjacent_damage])
	if other_damage > 0:
		parts.append("并且对其他%d个单位共造成%d点伤害" % [other_count, other_damage])
	if kill_mana:
		parts.append("击杀目标，圣水+1")
	parts.append_array(_format_parasite_broadcast_parts(parasite_events))
	parts.append_array(heals)
	return "，".join(parts) + "。"


func _format_skill_broadcast(subject: String, action_name: String, hp_events: Array, damage_events: Array, parasite_events: Array, failed_events: Array) -> String:
	var parts := ["%s使用了%s" % [subject, action_name]]
	var has_result := not damage_events.is_empty()
	for ev in hp_events:
		if int(ev.get("delta", 0)) > 0:
			has_result = true
	for fail in failed_events:
		var misfortune: int = int(fail.get("misfortune", 0))
		if misfortune > 0 and not has_result:
			parts.append("但由于霉运%d%%状态，技能无效" % misfortune)
		elif has_result:
			parts.append("但有部分概率触发的效果没有生效")
		else:
			parts.append("但技能没有生效")
	for dmg in damage_events:
		var actual: int = int(dmg.get("actual", 0))
		var declared: int = int(dmg.get("declared", actual))
		if declared <= 0:
			continue
		var target_name: String = dmg.get("target", "单位")
		var player: int = int(dmg.get("player", 0))
		if declared != actual:
			parts.append("对%s%s原本造成%d点伤害，但因为一些原因，实际造成%d点伤害" % [_side_text(player), target_name, declared, actual])
		else:
			parts.append("对%s%s造成%d点伤害" % [_side_text(player), target_name, actual])
	var heal_by_card := {}
	for ev in hp_events:
		var card_name: String = ev.get("card", "单位")
		var delta: int = int(ev.get("delta", 0))
		if delta > 0:
			heal_by_card[card_name] = int(heal_by_card.get(card_name, 0)) + delta
	for card_name in heal_by_card.keys():
		parts.append("使%s%s恢复%d点生命" % [_side_text(_player_for_event_card(hp_events, card_name)), card_name, int(heal_by_card[card_name])])
	parts.append_array(_format_parasite_broadcast_parts(parasite_events))
	return "，".join(parts) + "。"


func _format_parasite_broadcast_parts(parasite_events: Array) -> Array:
	var parts := []
	for ev in parasite_events:
		var declared: int = int(ev.get("declared", 0))
		var actual: int = int(ev.get("actual", 0))
		if declared <= 0:
			continue
		var parasite_name: String = ev.get("parasite", "寄生卡")
		if declared != actual:
			parts.append("对寄生卡%s原本造成%d点伤害，但因为一些原因，实际造成%d点伤害" % [parasite_name, declared, actual])
		else:
			parts.append("对寄生卡%s造成%d点伤害" % [parasite_name, actual])
		if bool(ev.get("destroyed", false)):
			parts.append("寄生卡%s退场" % parasite_name)
	return parts


func _damage_detail_for(damage_events: Array, player: int, slot: int) -> Dictionary:
	for ev in damage_events:
		if int(ev.get("player", 0)) == player and int(ev.get("slot", -1)) == slot:
			return ev
	return {}


func _damage_modifier_text(damage_event: Dictionary) -> String:
	if damage_event.is_empty():
		return ""
	var parts := []
	var reduction_pct: int = int(damage_event.get("reduction_pct", 0))
	if reduction_pct > 0:
		parts.append("由于目标的减伤%d%%状态" % reduction_pct)
	var temp_hp_before: int = int(damage_event.get("temp_hp_before", 0))
	if temp_hp_before > 0:
		parts.append("由于目标的护盾吸收")
	if parts.is_empty():
		return ""
	return "，" + "，".join(parts)


func _player_for_event_card(events: Array, card_name: String) -> int:
	for ev in events:
		if ev.get("card", "") == card_name:
			return int(ev.get("player", 0))
	return 0


func _side_text(player: int) -> String:
	if player == _view_player():
		return "己方"
	if player == _opponent_player():
		return "对方"
	return ""


# ============================================
# Misc
# ============================================

func _on_card_discarded(card_data: CardData):
	if not is_my_turn(): return
	var card_location := _find_card_location(card_data)
	if NetworkManager.is_online:
		if NetworkManager.is_authority():
			_host_apply_discard(card_location["location"], card_location["index"], game.current_player)
		else:
			NetworkManager.rpc_intent_discard.rpc(card_location["location"], card_location["index"], game.current_player)
		return
	if game.discard_card(card_data):
		_show_combat_broadcast(Locale.t("tip.discard_mana"))
		_refresh_hand_ui()
		update_entire_screen()
		_play_discard_feedback()


func _on_battle_background_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not (current_attacker_idx != -1 or summon_targeting or activate_targeting or cast_targeting or parasite_targeting):
			return
		if _point_is_over_battle_slot(get_global_mouse_position()):
			return
		cancel_attack()
		update_entire_screen()


func _point_is_over_battle_slot(point: Vector2) -> bool:
	for slot in _my_slots_ui() + _their_slots_ui():
		if slot is Control and Rect2(slot.global_position, slot.size).has_point(point):
			return true
	return false


func _skill_needs_targeting(skill: Dictionary) -> bool:
	return SpellRules.needs_target(skill)


func _manual_target_side(skill: Dictionary) -> String:
	for eff in _skill_effects_for_targeting(skill):
		var target_name: String = eff.get("target", "")
		if target_name in [SkillEngine.TARGET_SINGLE, SkillEngine.TARGET_SIDES]:
			var side: String = eff.get("target_side", SkillEngine.TARGET_SIDE_ENEMY)
			return SkillEngine.TARGET_SIDE_ALLY if side == SkillEngine.TARGET_SIDE_ALLY else SkillEngine.TARGET_SIDE_ENEMY
	return SkillEngine.TARGET_SIDE_ENEMY


func _manual_target_is_enemy(skill: Dictionary) -> bool:
	return _manual_target_side(skill) != SkillEngine.TARGET_SIDE_ALLY


func _manual_target_card_for_skill(skill: Dictionary, target_slot: int) -> CardData:
	var field := _my_field() if _manual_target_side(skill) == SkillEngine.TARGET_SIDE_ALLY else _their_field()
	return field.slots[target_slot] if target_slot >= 0 and target_slot < field.slots.size() else null

# ============================================
# Splash art
# ============================================

func _show_splash(card: CardData) -> void:
	if splash_tween and splash_tween.is_valid():
		splash_tween.kill()
	splash_name.text = card.card_name
	var has_art: bool = false
	if card.art_path != "":
		var load_path: String = card.art_path
		if load_path.begins_with("user://"):
			load_path = ProjectSettings.globalize_path(load_path)
		var img = Image.new()
		var err = img.load(load_path)
		if err == OK:
			var tex = ImageTexture.create_from_image(img)
			if tex != null:
				splash_art.texture = tex
				splash_art.visible = true
				splash_text.visible = false
				has_art = true
	if not has_art:
		splash_art.visible = false
		splash_text.visible = true
		splash_text.text = card.card_name
	splash_panel.modulate.a = 1.0
	var off_x := -get_viewport_rect().size.x
	splash_panel.position.x = off_x
	splash_tween = create_tween()
	splash_tween.tween_property(splash_panel, "position:x", 0.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	splash_tween.tween_interval(0.5)
	splash_tween.tween_property(splash_panel, "position:x", off_x, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

# ============================================
# Summon
# ============================================

func _on_card_drag_summoned(card_data, origin_ui, slot_index: int):
	card_data = card_data as CardData
	if card_data == null:
		return
	if not game.is_player_turn or not is_my_turn():
		return

	var their_field = _their_field()
	for i in range(5):
		if their_field.slots[i] == card_data:
			return

	var field = _my_field()

	var source_slot := -1
	for i in range(5):
		if field.slots[i] == card_data:
			source_slot = i
			break

	if source_slot >= 0:
		if NetworkManager.is_online:
			if NetworkManager.is_authority():
				_host_apply_move(source_slot, slot_index, game.current_player)
			else:
				NetworkManager.rpc_intent_move_card.rpc(source_slot, slot_index, game.current_player)
			return
		var displaced: CardData = field.slots[slot_index]
		field.slots[slot_index] = card_data
		field.slots[source_slot] = displaced
		update_entire_screen()
		return

	var hand_index := _my_hand().find(card_data)
	if card_data.is_parasite():
		_execute_parasite_attach(hand_index, _view_player(), slot_index)
		return
	if card_data.is_spell():
		_on_card_drag_cast(card_data, origin_ui, hand_index, slot_index)
		return
	if NetworkManager.is_online:
		if NetworkManager.is_authority():
			_host_apply_summon(hand_index, slot_index, game.current_player)
		else:
			NetworkManager.rpc_intent_summon.rpc(hand_index, slot_index, game.current_player)
		return

	var ok = game.summon_card(card_data, slot_index)
	if not ok:
		return
	if origin_ui and is_instance_valid(origin_ui):
		origin_ui.queue_free()

	# on_summon skills are no longer auto-triggered; the player activates them
	# manually this turn via the skill buttons (see _on_skill_activated).
	_refresh_hand_ui()
	_check_charm_overflow()
	_apply_deaths()
	_check_charm_overflow()
	update_entire_screen()

# ============================================
# Spell cast (from hand)
# ============================================

# Called when a spell or parasite card's skill button is clicked in hand.
func _on_hand_card_skill_activated(hand_index: int, skill_index: int = SpellRules.CAST_SKILL_INDEX) -> void:
	var hand := _my_hand()
	if hand_index < 0 or hand_index >= hand.size():
		return
	var card: CardData = hand[hand_index]
	if card != null and card.is_parasite():
		_start_parasite_attach_from_hand(hand_index)
		return
	_start_spell_cast_from_hand(hand_index, skill_index)


func _start_parasite_attach_from_hand(hand_index: int) -> void:
	if not is_my_turn():
		return
	var hand := _my_hand()
	if hand_index < 0 or hand_index >= hand.size():
		return
	var card_data: CardData = hand[hand_index]
	var attach_check: Dictionary = ParasiteRules.can_attach(card_data, _first_available_parasite_target(), game.active_field().get_total_mana())
	if not attach_check.get("ok", false) and attach_check.get("reason", "") == ParasiteRules.REASON_NO_MANA:
		_show_toast("tip.insufficient_mana")
		return
	parasite_targeting = true
	parasite_hand_index = hand_index
	if attack_arrow:
		attack_arrow.visible = true
	_sync_targeting_state()
	update_entire_screen()


func _first_available_parasite_target() -> CardData:
	for field in [_my_field(), _their_field()]:
		for card in field.slots:
			if card != null and card.is_alive():
				return card
	return null


func _start_spell_cast_from_hand(hand_index: int, skill_index: int = SpellRules.CAST_SKILL_INDEX) -> void:
	if not is_my_turn():
		return
	var hand := _my_hand()
	if hand_index < 0 or hand_index >= hand.size():
		return
	var card_data: CardData = hand[hand_index]
	var cast_check: Dictionary = SpellRules.can_cast(card_data, game.active_field().get_total_mana(), skill_index)
	if not cast_check.get("ok", false):
		if cast_check.get("reason", "") == SpellRules.REASON_NO_MANA:
			_show_toast("tip.insufficient_mana")
		return
	if cast_check.get("needs_target", false):
		if game.turn_number <= 1 and _manual_target_is_enemy(cast_check.get("skill", {})):
			print("Turn 1: enemy-targeting spells are not allowed!")
			_show_toast("tip.no_enemy_skill_turn1")
			return
		cast_targeting = true
		cast_hand_index = hand_index
		cast_skill_index = skill_index
		if attack_arrow:
			attack_arrow.visible = true
		_sync_targeting_state()
		update_entire_screen()
		return
	_execute_spell_cast(hand_index, skill_index, -1)


# Core cast execution, shared by local and online paths.
func _execute_spell_cast(hand_index: int, skill_index: int, target_slot: int, target_player: int = 0) -> void:
	var hand := _my_hand()
	if hand_index < 0 or hand_index >= hand.size():
		return
	var cast_check: Dictionary = SpellRules.can_cast(hand[hand_index], game.active_field().get_total_mana(), skill_index)
	if not cast_check.get("ok", false):
		if cast_check.get("reason", "") == SpellRules.REASON_NO_MANA:
			_show_toast("tip.insufficient_mana")
		return
	if NetworkManager.is_online:
		if NetworkManager.is_authority():
			_host_apply_cast(hand_index, skill_index, target_slot, game.current_player)
		else:
			NetworkManager.rpc_intent_activate_skill.rpc(_spell_intent_source(hand_index), skill_index, target_slot, game.current_player)
		return
	var spell_name: String = hand[hand_index].card_name
	var target_card := _manual_target_card_for_skill(cast_check.get("skill", {}), target_slot)
	_begin_action_broadcast("cast", game.current_player, spell_name, target_card.card_name if target_card != null else "")
	if game.cast_spell(hand_index, skill_index, target_slot, target_player):
		_finish_action_broadcast()
		_play_skill_cast_feedback(game.current_player, -1)
		_refresh_hand_ui()
		_apply_deaths()
		_check_charm_overflow()
		update_entire_screen()
		_check_and_show_game_over()
	else:
		_action_broadcast.clear()
		_action_hp_events.clear()
		_action_damage_events.clear()
		_action_parasite_events.clear()
		_action_failed_events.clear()


# Drag-to-cast shortcut — delegates to the skill-button handler.
func _on_card_drag_cast(card_data: CardData, origin_ui, hand_index: int, slot_index: int) -> void:
	if card_data == null or not card_data.is_spell():
		return
	if slot_index >= 0:
		_execute_spell_cast(hand_index, SpellRules.CAST_SKILL_INDEX, slot_index)
		return
	_start_spell_cast_from_hand(hand_index, SpellRules.CAST_SKILL_INDEX)


func _on_card_drag_cast_on_enemy(card_data: CardData, origin_ui, enemy_slot_index: int) -> void:
	if card_data == null:
		return
	var hand_index := _my_hand().find(card_data)
	if hand_index < 0:
		return
	if card_data.is_parasite():
		_execute_parasite_attach(hand_index, _opponent_player(), enemy_slot_index)
		return
	if not card_data.is_spell():
		return
	_execute_spell_cast(hand_index, SpellRules.CAST_SKILL_INDEX, enemy_slot_index)


func _execute_parasite_attach(hand_index: int, target_player: int, target_slot: int) -> void:
	var hand := _my_hand()
	if hand_index < 0 or hand_index >= hand.size():
		return
	var card: CardData = hand[hand_index]
	var target_field := _field_for_player(target_player)
	var target: CardData = target_field.slots[target_slot] if target_slot >= 0 and target_slot < target_field.slots.size() else null
	var attach_check: Dictionary = ParasiteRules.can_attach(card, target, game.active_field().get_total_mana())
	if not attach_check.get("ok", false):
		if attach_check.get("reason", "") == ParasiteRules.REASON_NO_MANA:
			_show_toast("tip.insufficient_mana")
		return
	if NetworkManager.is_online:
		if NetworkManager.is_authority():
			_host_apply_parasite(hand_index, target_player, target_slot, game.current_player)
		else:
			NetworkManager.rpc_intent_activate_skill.rpc(_parasite_intent_source(hand_index, target_player), 0, target_slot, game.current_player)
		return
	var parasite_name: String = card.card_name
	_begin_action_broadcast("parasite", game.current_player, parasite_name, target.card_name if target != null else "")
	if game.attach_parasite(hand_index, target_player, target_slot):
		_finish_action_broadcast()
		_refresh_hand_ui()
		update_entire_screen()
	else:
		_action_broadcast.clear()
		_action_hp_events.clear()
		_action_damage_events.clear()
		_action_parasite_events.clear()
		_action_failed_events.clear()


# ============================================
# Skill activation
# ============================================

func _on_skill_activated(slot_index: int, skill_index: int):
	if not game.is_player_turn or not is_my_turn():
		return
	var card: CardData = _my_field().slots[slot_index]
	if card == null:
		return
	if card.skills_used.has(skill_index):
		return
	if skill_index >= card.skills.size():
		return
	var skill: Dictionary = card.skills[skill_index]
	if card.is_silenced() and skill.get("skill_type", SkillEngine.SKILL_TYPE_NORMAL) != SkillEngine.SKILL_TYPE_TALENT:
		return
	var trig: String = skill.get("trigger", "")
	var is_summon: bool = trig == SkillEngine.TRIGGER_ON_SUMMON
	var is_activate: bool = trig == SkillEngine.TRIGGER_ON_ACTIVATE
	if not is_summon and not is_activate:
		return
	# on_summon abilities can only be used on the turn the card was summoned,
	# and are independent of attack/action state. on_activate keeps its rules.
	if is_summon and not card.summoned_this_turn:
		return
	if is_activate and card.has_attacked:
		return
	if _skill_needs_targeting(skill):
		if game.turn_number <= 1 and _manual_target_is_enemy(skill):
			print("Turn 1: enemy-targeting skills are not allowed!")
			_show_toast("tip.no_enemy_skill_turn1")
			return
		if is_summon:
			summon_targeting = true
			summon_source_slot = slot_index
			summon_skill_idx = skill_index
		else:
			activate_targeting = true
			activate_source_slot = slot_index
			activate_skill_idx = skill_index
		if attack_arrow:
			attack_arrow.visible = true
		_sync_targeting_state()
		update_entire_screen()
	else:
		if NetworkManager.is_online:
			if is_summon:
				if NetworkManager.is_authority():
					_host_apply_summon_skill(slot_index, skill_index, -1, game.current_player)
				else:
					NetworkManager.rpc_intent_summon_skill.rpc(slot_index, skill_index, -1, game.current_player)
			else:
				if NetworkManager.is_authority():
					_host_apply_skill(slot_index, skill_index, -1, game.current_player)
				else:
					NetworkManager.rpc_intent_activate_skill.rpc(slot_index, skill_index, -1, game.current_player)
			return
		card.skills_used.append(skill_index)
		_begin_action_broadcast("summon_skill" if is_summon else "skill", game.current_player, card.card_name, "", {"skill": skill.get("skill_name", "技能")})
		if is_summon:
			game.trigger_summon_skills(slot_index, -1, skill_index)
		else:
			game.trigger_activate_skills(slot_index, -1, skill_index)
		_finish_action_broadcast()
		_play_skill_cast_feedback(game.current_player, slot_index)
		_refresh_hand_ui()
		_check_charm_overflow()
		_show_splash(card)
		_apply_deaths()
		_check_charm_overflow()
		update_entire_screen()


# ============================================
# Attack
# ============================================

func _on_attack_requested(slot_index: int):
	if not game.is_player_turn or not is_my_turn():
		return
	if game.turn_number <= 1:
		print("Turn 1: attacks are not allowed!")
		_show_toast("tip.no_attack_turn1")
		return
	var field = _my_field()
	if field.slots[slot_index] == null:
		return
	if field.slots[slot_index].has_acted:
		return
	if field.slots[slot_index].is_silenced() and not field.slots[slot_index].attack_ignores_silence:
		return
	current_attacker_idx = slot_index
	if attack_arrow:
		attack_arrow.visible = true
	_sync_targeting_state()


func _targeting_skill_wants_ally() -> bool:
	var skill := _current_targeting_skill()
	if skill.is_empty():
		return false
	for eff in _skill_effects_for_targeting(skill):
		var target_name: String = eff.get("target", "")
		if target_name in [SkillEngine.TARGET_SINGLE, SkillEngine.TARGET_SIDES] and eff.get("target_side", SkillEngine.TARGET_SIDE_ENEMY) == SkillEngine.TARGET_SIDE_ALLY:
			return true
	return false


func _current_targeting_skill() -> Dictionary:
	if summon_targeting:
		var summon_card: CardData = _my_field().slots[summon_source_slot] if summon_source_slot >= 0 else null
		return summon_card.skills[summon_skill_idx] if summon_card != null and summon_skill_idx >= 0 and summon_skill_idx < summon_card.skills.size() else {}
	if activate_targeting:
		var active_card: CardData = _my_field().slots[activate_source_slot] if activate_source_slot >= 0 else null
		return active_card.skills[activate_skill_idx] if active_card != null and activate_skill_idx >= 0 and activate_skill_idx < active_card.skills.size() else {}
	if cast_targeting:
		var hand := _my_hand()
		var spell: CardData = hand[cast_hand_index] if cast_hand_index >= 0 and cast_hand_index < hand.size() else null
		return SpellRules.spell_skill(spell, cast_skill_index)
	return {}


func _skill_effects_for_targeting(skill: Dictionary) -> Array:
	var effects: Array = skill.get("effects", [])
	if effects.is_empty() and (skill.get("target", "") != "" or skill.get("effect", "") != ""):
		return [skill]
	return effects


func _apply_targeted_skill_to_selected_side(target_player: int, target_slot: int) -> void:
	if summon_targeting:
		_apply_summon_skill_target(target_player, target_slot)
		return
	if activate_targeting:
		_apply_activate_skill_target(target_player, target_slot)
		return
	if cast_targeting:
		_apply_cast_skill_target(target_player, target_slot)


func _apply_summon_skill_target(target_player: int, target_slot: int) -> void:
	var source_card: CardData = _my_field().slots[summon_source_slot]
	var target_card: CardData = _field_for_player(target_player).slots[target_slot]
	var summon_skill: Dictionary = source_card.skills[summon_skill_idx] if source_card != null and summon_skill_idx < source_card.skills.size() else {}
	if NetworkManager.is_online:
		if NetworkManager.is_authority():
			_host_apply_summon_skill(summon_source_slot, summon_skill_idx, target_slot, game.current_player)
		else:
			NetworkManager.rpc_intent_summon_skill.rpc(summon_source_slot, summon_skill_idx, target_slot, game.current_player)
		cancel_attack()
		return
	source_card.skills_used.append(summon_skill_idx)
	_begin_action_broadcast("summon_skill", game.current_player, source_card.card_name if source_card != null else "单位", target_card.card_name if target_card != null else "", {"skill": summon_skill.get("skill_name", "技能")})
	game.trigger_summon_skills(summon_source_slot, target_slot, summon_skill_idx, target_player)
	_finish_action_broadcast()
	_play_skill_cast_feedback(game.current_player, summon_source_slot)
	_refresh_hand_ui()
	_check_charm_overflow()
	_show_splash(source_card)
	cancel_attack()
	_apply_deaths()
	_check_charm_overflow()
	update_entire_screen()


func _apply_activate_skill_target(target_player: int, target_slot: int) -> void:
	var source_card: CardData = _my_field().slots[activate_source_slot]
	var target_card: CardData = _field_for_player(target_player).slots[target_slot]
	var activate_skill: Dictionary = source_card.skills[activate_skill_idx] if source_card != null and activate_skill_idx < source_card.skills.size() else {}
	if NetworkManager.is_online:
		if NetworkManager.is_authority():
			_host_apply_skill(activate_source_slot, activate_skill_idx, target_slot, game.current_player)
		else:
			NetworkManager.rpc_intent_activate_skill.rpc(activate_source_slot, activate_skill_idx, target_slot, game.current_player)
		cancel_attack()
		return
	source_card.skills_used.append(activate_skill_idx)
	_begin_action_broadcast("skill", game.current_player, source_card.card_name if source_card != null else "单位", target_card.card_name if target_card != null else "", {"skill": activate_skill.get("skill_name", "技能")})
	game.trigger_activate_skills(activate_source_slot, target_slot, activate_skill_idx, target_player)
	_finish_action_broadcast()
	_play_skill_cast_feedback(game.current_player, activate_source_slot)
	_refresh_hand_ui()
	_check_charm_overflow()
	_show_splash(source_card)
	cancel_attack()
	_apply_deaths()
	_check_charm_overflow()
	update_entire_screen()
	_check_and_show_game_over()


func _apply_cast_skill_target(target_player: int, target_slot: int) -> void:
	_execute_spell_cast(cast_hand_index, cast_skill_index, target_slot, target_player)
	cancel_attack()


func _on_player_slot_clicked(index: int):
	if not is_my_turn(): return
	if parasite_targeting:
		if _my_field().slots[index] == null:
			cancel_attack()
			return
		_execute_parasite_attach(parasite_hand_index, _view_player(), index)
		cancel_attack()
		return
	if _targeting_skill_wants_ally():
		if _my_field().slots[index] == null:
			cancel_attack()
			return
		_apply_targeted_skill_to_selected_side(_view_player(), index)
		return
	if current_attacker_idx != -1:
		cancel_attack()
	update_entire_screen()


func _on_enemy_slot_clicked(enemy_index: int):
	if not is_my_turn(): return
	if summon_targeting or activate_targeting or cast_targeting or parasite_targeting or current_attacker_idx != -1:
		_on_opponent_slot_clicked(enemy_index)
	else:
		update_entire_screen()


func _on_opponent_slot_clicked(index: int):
	if parasite_targeting:
		if _their_field().slots[index] == null:
			cancel_attack()
			return
		_execute_parasite_attach(parasite_hand_index, _opponent_player(), index)
		cancel_attack()
		return

	if _targeting_skill_wants_ally():
		cancel_attack()
		return

	if summon_targeting:
		if _their_field().slots[index] == null:
			cancel_attack()
			return
		if _their_field().has_any_taunt():
			var target_card = _their_field().slots[index]
			if target_card == null or not target_card.has_taunt():
				print("Must target a taunt minion first!")
				_show_toast("tip.taunt_skill_first")
				return
		if NetworkManager.is_online:
			if NetworkManager.is_authority():
				_host_apply_summon_skill(summon_source_slot, summon_skill_idx, index, game.current_player)
			else:
				NetworkManager.rpc_intent_summon_skill.rpc(summon_source_slot, summon_skill_idx, index, game.current_player)
			cancel_attack()
			return
		_my_field().slots[summon_source_slot].skills_used.append(summon_skill_idx)
		var summon_card: CardData = _my_field().slots[summon_source_slot]
		var summon_skill: Dictionary = summon_card.skills[summon_skill_idx] if summon_card != null and summon_skill_idx < summon_card.skills.size() else {}
		_begin_action_broadcast("summon_skill", game.current_player, summon_card.card_name if summon_card != null else "单位", _their_field().slots[index].card_name, {"skill": summon_skill.get("skill_name", "技能")})
		game.trigger_summon_skills(summon_source_slot, index, summon_skill_idx)
		_finish_action_broadcast()
		_play_skill_cast_feedback(game.current_player, summon_source_slot)
		_refresh_hand_ui()
		_check_charm_overflow()
		if summon_card != null:
			_show_splash(summon_card)
		summon_targeting = false
		summon_source_slot = -1
		last_hovered_target = -1
		if attack_arrow:
			attack_arrow.visible = false
		_apply_deaths()
		_check_charm_overflow()
		update_entire_screen()
		return

	if activate_targeting:
		if _their_field().slots[index] == null:
			cancel_attack()
			return
		if _their_field().has_any_taunt():
			var target_card = _their_field().slots[index]
			if target_card == null or not target_card.has_taunt():
				print("Must target a taunt minion first!")
				_show_toast("tip.taunt_skill_first")
				return
		if NetworkManager.is_online:
			if NetworkManager.is_authority():
				_host_apply_skill(activate_source_slot, activate_skill_idx, index, game.current_player)
			else:
				NetworkManager.rpc_intent_activate_skill.rpc(activate_source_slot, activate_skill_idx, index, game.current_player)
			cancel_attack()
			return
		_my_field().slots[activate_source_slot].skills_used.append(activate_skill_idx)
		var card: CardData = _my_field().slots[activate_source_slot]
		var activate_skill: Dictionary = card.skills[activate_skill_idx] if card != null and activate_skill_idx < card.skills.size() else {}
		_begin_action_broadcast("skill", game.current_player, card.card_name if card != null else "单位", _their_field().slots[index].card_name, {"skill": activate_skill.get("skill_name", "技能")})
		game.trigger_activate_skills(activate_source_slot, index, activate_skill_idx)
		_finish_action_broadcast()
		_play_skill_cast_feedback(game.current_player, activate_source_slot)
		_refresh_hand_ui()
		_check_charm_overflow()
		_show_splash(card)
		activate_targeting = false
		activate_source_slot = -1
		last_hovered_target = -1
		if attack_arrow:
			attack_arrow.visible = false
		_apply_deaths()
		_check_charm_overflow()
		update_entire_screen()
		_check_and_show_game_over()
		return

	if cast_targeting:
		if _their_field().slots[index] == null:
			cancel_attack()
			return
		if _their_field().has_any_taunt():
			var target_card = _their_field().slots[index]
			if target_card == null or not target_card.has_taunt():
				print("Must target a taunt minion first!")
				_show_toast("tip.taunt_skill_first")
				return
		if NetworkManager.is_online:
			if NetworkManager.is_authority():
				_host_apply_cast(cast_hand_index, cast_skill_index, index, game.current_player)
			else:
				NetworkManager.rpc_intent_activate_skill.rpc(_spell_intent_source(cast_hand_index), cast_skill_index, index, game.current_player)
			cancel_attack()
			return
		_execute_spell_cast(cast_hand_index, cast_skill_index, index)
		cast_targeting = false
		cast_hand_index = -1
		cast_skill_index = -1
		last_hovered_target = -1
		if attack_arrow:
			attack_arrow.visible = false
		return

	if current_attacker_idx == -1:
		return
	if _their_field().slots[index] == null:
		cancel_attack()
		return
	if _their_field().has_any_taunt():
		var target_card = _their_field().slots[index]
		if target_card == null or not target_card.has_taunt():
			print("Must attack a taunt minion first!")
			_show_toast("tip.taunt_first")
			return
	if NetworkManager.is_online:
		if NetworkManager.is_authority():
			_host_apply_attack(current_attacker_idx, index, game.current_player)
		else:
			NetworkManager.rpc_intent_attack.rpc(current_attacker_idx, index, game.current_player)
		cancel_attack()
		return
	var victim: CardData = _their_field().slots[index]
	var attacker_slot: int = current_attacker_idx
	var attacker_card: CardData = _my_field().slots[attacker_slot]
	var base_damage: int = attacker_card.atk if attacker_card != null else 0
	var effective_damage: int = attacker_card.effective_atk() if attacker_card != null else 0
	_begin_action_broadcast("attack", game.current_player, attacker_card.card_name if attacker_card != null else "单位", victim.card_name if victim != null else "单位", {"base_damage": base_damage, "effective_damage": effective_damage, "target_player": _opponent_player(), "target_slot": index})
	game.execute_attack(attacker_slot, index)
	if victim != null and not victim.is_alive():
		_action_broadcast["kill_mana"] = true
	_finish_action_broadcast()
	var card: CardData = _my_field().slots[attacker_slot]
	_play_attack_feedback(game.current_player, attacker_slot, index)
	_show_splash(card)
	_apply_deaths()
	_check_charm_overflow()
	_refresh_hand_ui()
	update_entire_screen()
	cancel_attack()
	_check_and_show_game_over()


func cancel_attack():
	if NetworkManager.is_online and (current_attacker_idx != -1 or summon_targeting or activate_targeting or cast_targeting or parasite_targeting):
		NetworkManager.rpc_targeting_arrow.rpc(-1, -1, game.current_player)
	current_attacker_idx = -1
	summon_targeting = false
	activate_targeting = false
	cast_targeting = false
	parasite_targeting = false
	cast_hand_index = -1
	cast_skill_index = -1
	parasite_hand_index = -1
	last_hovered_target = -1
	if attack_arrow:
		attack_arrow.visible = false


# ============================================
# Turn
# ============================================

func _on_end_turn_pressed():
	if not game.is_player_turn or not is_my_turn():
		return
	if _turn_ending:
		return
	_turn_ending = true
	end_turn_button.disabled = true
	if NetworkManager.is_online:
		if NetworkManager.is_authority():
			await _host_apply_end_turn(game.current_player)
			_turn_ending = false
		else:
			NetworkManager.rpc_intent_end_turn.rpc(game.current_player)
			# Non-authority stays locked until authority state arrives
		return
	await _run_local_end_turn()
	_turn_ending = false


func _run_local_end_turn() -> void:
	var result = game.end_player_turn()
	_show_direct_damage(result)
	end_turn_button.disabled = true
	update_entire_screen()
	if _check_and_show_game_over():
		return
	await get_tree().create_timer(0.5).timeout
	game.start_new_turn()
	_refresh_hand_ui()
	end_turn_button.disabled = false
	update_entire_screen()
	if PlayerData.battle_mode == "practice" and game.current_player == 2:
		_start_practice_ai_turn.call_deferred()


func _start_practice_ai_turn() -> void:
	if NetworkManager.is_online or PlayerData.battle_mode != "practice" or game.current_player != 2 or practice_ai_running:
		return
	await _run_practice_ai_turn()


func _run_practice_ai_turn() -> void:
	practice_ai_running = true
	end_turn_button.disabled = true
	update_entire_screen()
	await get_tree().create_timer(0.35).timeout
	_practice_ai_play_cards()
	_apply_deaths()
	_check_charm_overflow()
	_refresh_hand_ui()
	update_entire_screen()
	await get_tree().create_timer(0.25).timeout
	_practice_ai_use_skills()
	_apply_deaths()
	_check_charm_overflow()
	_refresh_hand_ui()
	update_entire_screen()
	await get_tree().create_timer(0.35).timeout
	_practice_ai_attack_with_ready_cards()
	_apply_deaths()
	_check_charm_overflow()
	_refresh_hand_ui()
	update_entire_screen()
	if _check_and_show_game_over():
		practice_ai_running = false
		return
	await get_tree().create_timer(0.35).timeout
	practice_ai_running = false
	await _run_local_end_turn()


func _practice_ai_play_cards() -> void:
	match PlayerData.practice_ai_difficulty:
		"easy":
			_practice_ai_summon_cards(1, false)
		"hard":
			_practice_ai_summon_cards(5, true)
		_:
			_practice_ai_summon_cards(1, true)


func _practice_ai_summon_cards(max_cards: int, prefer_expensive: bool) -> void:
	var saved_player: int = game.current_player
	game.current_player = 2
	var played := 0
	while played < max_cards:
		var choice := _practice_ai_choose_summon(prefer_expensive)
		if choice.is_empty():
			break
		if game.summon_card(choice["card"], choice["slot"]):
			played += 1
		else:
			break
	game.current_player = saved_player


func _practice_ai_choose_summon(prefer_expensive: bool) -> Dictionary:
	var hand: Array = game.player2_hand
	var field: BattleField = game.player2_field
	var empty_slot := -1
	for slot in range(field.slots.size()):
		if field.slots[slot] == null:
			empty_slot = slot
			break
	if empty_slot < 0:
		return {}
	var best_index := -1
	var best_score := -999999
	for h in range(hand.size()):
		var card: CardData = hand[h]
		if card == null or card.cost > field.get_total_mana():
			continue
		var score := card.cost if prefer_expensive else -h
		if PlayerData.practice_ai_difficulty == "hard":
			score += card.atk * 2 + card.max_hp
		if score > best_score:
			best_score = score
			best_index = h
	if best_index < 0:
		return {}
	return {"card": hand[best_index], "slot": empty_slot}


func _practice_ai_use_skills() -> void:
	if PlayerData.practice_ai_difficulty != "hard":
		return
	var saved_player: int = game.current_player
	game.current_player = 2
	for slot in range(game.player2_field.slots.size()):
		var card: CardData = game.player2_field.slots[slot]
		if card == null or card.is_silenced():
			continue
		for skill_idx in range(card.skills.size()):
			if card.skills_used.has(skill_idx):
				continue
			var skill: Dictionary = card.skills[skill_idx]
			var trigger: String = skill.get("trigger", "")
			if trigger != SkillEngine.TRIGGER_ON_ACTIVATE and not (trigger == SkillEngine.TRIGGER_ON_SUMMON and card.summoned_this_turn):
				continue
			var target_slot := _practice_ai_skill_target_slot(skill)
			if target_slot == -2:
				continue
			card.skills_used.append(skill_idx)
			if trigger == SkillEngine.TRIGGER_ON_SUMMON:
				game.trigger_summon_skills(slot, target_slot, skill_idx)
			else:
				game.trigger_activate_skills(slot, target_slot, skill_idx)
			_play_skill_cast_feedback(2, slot)
			_show_splash(card)
			_apply_deaths()
			if game.check_game_over() != "":
				game.current_player = saved_player
				return
	game.current_player = saved_player


func _practice_ai_skill_target_slot(skill: Dictionary) -> int:
	for eff in skill.get("effects", []):
		var normalized := _TargetResolver.normalize_effect_target(eff)
		var target: String = normalized.get("target", SkillEngine.TARGET_SELF)
		if target in [SkillEngine.TARGET_SINGLE, SkillEngine.TARGET_SIDES]:
			var effect: String = normalized.get("effect", "")
			if effect in [SkillEngine.EFFECT_HEAL, SkillEngine.EFFECT_SHIELD, SkillEngine.EFFECT_ADD_BUFF, SkillEngine.EFFECT_DRAW_CARDS]:
				return -2
			var slot := _practice_ai_best_target_slot()
			return slot if slot >= 0 else -2
	return -1


func _practice_ai_attack_with_ready_cards() -> void:
	if game.turn_number <= 1:
		return
	var saved_player: int = game.current_player
	game.current_player = 2
	for slot in range(game.player2_field.slots.size()):
		var card: CardData = game.player2_field.slots[slot]
		if card == null or card.has_acted or card.is_silenced():
			continue
		var target_slot := _practice_ai_attack_target_slot(card)
		if target_slot < 0:
			continue
		game.execute_attack(slot, target_slot)
		_play_attack_feedback(2, slot, target_slot)
		_show_splash(card)
		_apply_deaths()
		if game.check_game_over() != "":
			break
	game.current_player = saved_player


func _practice_ai_attack_target_slot(attacker: CardData) -> int:
	if PlayerData.practice_ai_difficulty == "easy":
		return _practice_ai_first_attack_target()
	return _practice_ai_best_target_slot(attacker)


func _practice_ai_first_attack_target() -> int:
	for i in range(game.player_field.slots.size()):
		var target: CardData = game.player_field.slots[i]
		if target != null and target.is_alive() and target.has_taunt():
			return i
	for i in range(game.player_field.slots.size()):
		var target: CardData = game.player_field.slots[i]
		if target != null and target.is_alive():
			return i
	return -1


func _practice_ai_best_target_slot(attacker: CardData = null) -> int:
	var best_slot := -1
	var best_score := -999999
	for i in range(game.player_field.slots.size()):
		var target: CardData = game.player_field.slots[i]
		if target == null or not target.is_alive():
			continue
		if game.player_field.has_any_taunt() and not target.has_taunt():
			continue
		var score := 0
		if target.has_taunt():
			score += 1000
		if attacker != null and attacker.effective_atk() >= target.hp:
			score += 500
		score += target.atk * 6 + (target.max_hp - target.hp) * 2 - target.hp
		if PlayerData.practice_ai_difficulty == "hard":
			score += target.cost * 3
		if score > best_score:
			best_score = score
			best_slot = i
	return best_slot


func _on_status_toggle_pressed():
	show_enemy_status = not show_enemy_status
	update_entire_screen()


# ============================================
# Helpers
# ============================================

func _show_direct_damage(result: Dictionary):
	if not result.get("triggered", false):
		return
	var total: int = result["total_damage"]
	if total <= 0:
		return
	await get_tree().create_timer(0.3).timeout
	var vp_size = get_viewport().get_visible_rect().size
	_spawn_combat_text(Vector2(vp_size.x / 2, vp_size.y / 2 - 80), -total, true)


func _apply_deaths():
	var dead = game.cleanup_deaths()
	var p_slots = player_side_ui.get_children()
	var e_slots = enemy_side_ui.get_children()
	for idx in dead.get("p1", []):
		var slot_ui = (p_slots if _view_player() == 1 else e_slots)[idx]
		_play_death_feedback(slot_ui)
	for idx in dead.get("p2", []):
		var slot_ui = (e_slots if _view_player() == 1 else p_slots)[idx]
		_play_death_feedback(slot_ui)
	if not dead.get("p1", []).is_empty() or not dead.get("p2", []).is_empty():
		_refresh_hand_ui()


func _play_death_feedback(slot_ui: Control) -> void:
	if slot_ui == null:
		return
	var card_ui = slot_ui.get("current_card_ui")
	if card_ui == null or not is_instance_valid(card_ui):
		slot_ui.set_card(null)
		return
	var ghost: Control = card_ui.duplicate()
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.global_position = card_ui.global_position
	ghost.size = card_ui.size
	ghost.scale = card_ui.scale
	$CanvasLayer.add_child(ghost)
	$CanvasLayer.move_child(ghost, $CanvasLayer.get_child_count() - 1)
	slot_ui.set_card(null)
	var base_position: Vector2 = ghost.position
	var base_scale: Vector2 = ghost.scale
	var twn := create_tween()
	twn.set_parallel(true)
	twn.tween_property(ghost, "modulate:a", 0.0, 0.24)
	twn.tween_property(ghost, "position", base_position + Vector2(0, 18), 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	twn.tween_property(ghost, "scale", base_scale * 0.82, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	twn.chain().tween_callback(ghost.queue_free)


func _refresh_hand_ui():
	for child in hand_container.get_children():
		child.queue_free()
	var hand: Array = _my_hand()
	for i in range(hand.size()):
		var card_data: CardData = hand[i]
		var card_ui = card_ui_scene.instantiate()
		hand_container.add_child(card_ui)
		card_ui.set_card(card_data)
		_scale_control(card_ui, BASE_CARD_SIZE)
		_connect_hand_card_signals(card_ui, i)
	_update_pile_labels()


func _connect_hand_card_signals(card_ui, hand_index: int) -> void:
	card_ui.skill1_requested.connect(_on_hand_card_skill_activated.bind(hand_index, SpellRules.CAST_SKILL_INDEX))


func _play_hand_card_enter_feedback(card_ui: Control) -> void:
	if card_ui == null or not is_instance_valid(card_ui):
		return
	var base_position: Vector2 = card_ui.position
	var base_scale: Vector2 = card_ui.scale
	card_ui.modulate.a = 0.0
	card_ui.position = base_position + Vector2(0, 18)
	card_ui.scale = base_scale * 0.92
	var twn := create_tween()
	twn.set_parallel(true)
	twn.tween_property(card_ui, "modulate:a", 1.0, 0.18)
	twn.tween_property(card_ui, "position", base_position, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	twn.tween_property(card_ui, "scale", base_scale, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _play_draw_fly_feedback(player: int, count: int) -> void:
	if draw_pile_btn == null or count <= 0:
		return
	var start: Vector2 = draw_pile_btn.global_position + draw_pile_btn.size / 2
	var target: Vector2 = _draw_fly_target_for_player(player)
	for i in range(count):
		_spawn_draw_fly_card(start, target, i)


func _play_opening_draw_feedback() -> void:
	await get_tree().process_frame
	_play_draw_fly_feedback(1, min(3, game.player_hand.size()))
	_play_draw_fly_feedback(2, min(3, game.player2_hand.size()))


func _draw_fly_target_for_player(player: int) -> Vector2:
	if player == _view_player():
		return hand_container.global_position + Vector2(hand_container.size.x * 0.5, hand_container.size.y * 0.35)
	var enemy_slots: Array = enemy_side_ui.get_children()
	if enemy_slots.size() > 0:
		var first: Control = enemy_slots[0]
		var last: Control = enemy_slots[enemy_slots.size() - 1]
		var left: float = first.global_position.x
		var right: float = last.global_position.x + last.size.x
		return Vector2((left + right) * 0.5, first.global_position.y - 28 * _ui_scale())
	return enemy_side_ui.global_position + enemy_side_ui.size / 2


func _spawn_draw_fly_card(start: Vector2, target: Vector2, index: int) -> void:
	var card_back := Panel.new()
	card_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_back.size = Vector2(52, 72) * _ui_scale()
	card_back.pivot_offset = card_back.size / 2
	card_back.position = start - card_back.size / 2 + Vector2(index * 7, -index * 5)
	card_back.modulate.a = 0.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.19, 0.34, 0.96)
	style.border_color = Color(0.95, 0.78, 0.32, 0.95)
	style.set_border_width_all(max(1, int(2 * _ui_scale())))
	style.set_corner_radius_all(max(5, int(7 * _ui_scale())))
	card_back.add_theme_stylebox_override("panel", style)
	var shine := ColorRect.new()
	shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shine.color = Color(1.0, 1.0, 1.0, 0.08)
	shine.anchor_right = 1.0
	shine.anchor_bottom = 0.28
	card_back.add_child(shine)
	$CanvasLayer.add_child(card_back)
	$CanvasLayer.move_child(card_back, $CanvasLayer.get_child_count() - 1)
	var lift: float = -78.0 * _ui_scale() - index * 8.0
	var mid: Vector2 = (start + target) * 0.5 + Vector2(0, lift)
	var duration: float = 0.58 + index * 0.07
	var twn := create_tween()
	twn.set_parallel(false)
	twn.tween_property(card_back, "modulate:a", 1.0, 0.08)
	twn.parallel().tween_property(card_back, "scale", Vector2(1.08, 1.08), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	twn.tween_property(card_back, "position", mid - card_back.size / 2, duration * 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	twn.tween_property(card_back, "position", target - card_back.size / 2 + Vector2(index * 5, 0), duration * 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	twn.parallel().tween_property(card_back, "scale", Vector2(0.82, 0.82), duration * 0.55)
	twn.parallel().tween_property(card_back, "modulate:a", 0.0, 0.16).set_delay(duration * 0.35)
	twn.chain().tween_callback(card_back.queue_free)


func _play_discard_feedback() -> void:
	var target: Control = discard_pile_btn if discard_pile_btn != null else discard_zone
	if target == null or not is_instance_valid(target):
		return
	var base_modulate: Color = target.modulate
	var base_scale: Vector2 = target.scale
	var center: Vector2 = target.global_position + target.size / 2
	_spawn_combat_text(center + Vector2(0, -10), 1)
	var twn := create_tween()
	twn.set_parallel(true)
	twn.tween_property(target, "modulate", Color(0.7, 1.0, 0.72, 1.0), 0.08)
	twn.tween_property(target, "scale", base_scale * 1.04, 0.08)
	twn.tween_property(target, "modulate", base_modulate, 0.18).set_delay(0.08)
	twn.tween_property(target, "scale", base_scale, 0.18).set_delay(0.08)


func _check_and_show_game_over() -> bool:
	var result: String = game.check_game_over()
	if result == "":
		return false
	_show_result(result)
	return true


func _show_result(result: String):
	if battle_finished:
		return
	battle_finished = true
	practice_ai_running = false
	cancel_attack()
	if mana_label:
		mana_label.text = "[ %s ]" % _result_title(result)
	if end_turn_button:
		end_turn_button.disabled = true
	_show_battle_result_page(result)


func _on_opponent_disconnected() -> void:
	if battle_finished:
		return
	battle_finished = true
	practice_ai_running = false
	cancel_attack()
	remote_arrow_source = -1
	remote_arrow_target = -1
	if attack_arrow:
		attack_arrow.visible = false
	_show_combat_broadcast("对手已断开连接！" if Locale.language == "zh" else "Opponent disconnected!")
	if mana_label:
		mana_label.text = "[ %s ]" % Locale.t("result.connection_lost_title")
	if end_turn_button:
		end_turn_button.disabled = true
	_show_disconnect_result_page()


func _on_opponent_reconnected() -> void:
	if not _disconnect_overlay:
		return
	_disconnect_overlay.queue_free()
	_disconnect_overlay = null
	_disconnect_reconnect_btn = null
	_disconnect_back_btn = null
	battle_finished = false
	my_player = NetworkManager.player_number
	update_entire_screen()


# ============================================
# Skill interaction handlers (view discard/deck, zero cost)
# ============================================

func _on_shuffle_discard_into_deck() -> void:
	if game.shared_discard.is_empty():
		return
	game.shared_deck = game.shared_discard.duplicate()
	game.shared_discard.clear()
	if NetworkManager.is_online:
		game._shuffle_shared_deck()
	else:
		game.shared_deck.shuffle()
	print("[Main] Discard shuffled into deck (%d cards)" % game.shared_deck.size())


func _on_view_discard_select(count: int, draw_count: int, current_player: int, hand: Array) -> void:
	if game.shared_discard.is_empty():
		return
	var cards: Array = game.shared_discard
	if draw_count > 0:
		cards = cards.slice(0, min(draw_count, cards.size()))
	_show_pile_selection_popup(cards, count, "discard", hand, current_player)


func _on_view_deck_select(count: int, draw_count: int, current_player: int, hand: Array) -> void:
	if game.shared_deck.is_empty():
		return
	var draw_n: int = draw_count if draw_count > 0 else count * 2
	var display_cards: Array = game.shared_deck.slice(0, min(draw_n, game.shared_deck.size()))
	_show_pile_selection_popup(display_cards, count, "deck", hand, current_player)


func _on_make_zero_cost_select(count: int, _current_player: int, hand: Array, target: String, _random_count: int) -> void:
	var candidates: Array = []
	for card in hand:
		if card is CardData and card.cost > 0 and not card.zero_cost_until_deploy:
			candidates.append(card)
	if candidates.is_empty():
		return
	# For SIDES, player picks 1 card (neighbors auto-included)
	var pick_count: int = 1 if target in [SkillEngine.TARGET_SIDES, SkillEngine.TARGET_SELF_SIDES] else min(count, candidates.size())
	_show_zero_cost_selection_popup(candidates, pick_count, hand, target)


func _show_pile_selection_popup(cards: Array, count: int, source: String, hand: Array, _player: int) -> void:
	var popup := UITheme.make_popup_layer(self, 120)
	var layer: CanvasLayer = popup["layer"]
	var panel := Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -320
	panel.offset_top = -300
	panel.offset_right = 320
	panel.offset_bottom = 300
	panel.clip_contents = true
	UITheme.apply_popup_frame(panel, "gold")
	layer.add_child(panel)
	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var title := Label.new()
	var max_slots := SkillEngine.MAX_HAND_SIZE - hand.size()
	title.text = Locale.t("battle.choose_keep") + (" (%s)" % source)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, 18)
	box.add_child(title)
	var hint := Label.new()
	hint.text = Locale.t("battle.hand_remaining") % [max_slots, min(count, max_slots)]
	UITheme.apply_label(hint, true)
	box.add_child(hint)

	var selected_indices: Dictionary = {}
	var grid_scroll: ScrollContainer = ScrollContainer.new()
	grid_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_scroll.custom_minimum_size = Vector2(0, 300 * _ui_scale())
	box.add_child(grid_scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid_scroll.add_child(grid)

	for i in range(cards.size()):
		var card: CardData = cards[i]
		var card_box := VBoxContainer.new()
		card_box.custom_minimum_size = Vector2(100, 140) * _ui_scale()
		card_box.add_theme_constant_override("separation", 2)
		var card_ui := card_ui_scene.instantiate()
		card_ui.set_card(card)
		card_ui.apply_ui_scale(_ui_scale() * 0.7)
		card_ui.set_skill_preview_visible(true)
		card_box.add_child(card_ui)
		var check := CheckBox.new()
		check.text = card.card_name
		check.clip_text = true
		check.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		check.toggled.connect(func(pressed: bool):
			if pressed:
				if selected_indices.size() >= count:
					check.button_pressed = false
					return
				selected_indices[i] = true
			else:
				selected_indices.erase(i)
		)
		card_box.add_child(check)
		grid.add_child(card_box)

	var confirm_btn := Button.new()
	confirm_btn.text = Locale.t("battle.confirm")
	confirm_btn.custom_minimum_size = Vector2(160, 36)
	UITheme.apply_button(confirm_btn, "primary")
	confirm_btn.pressed.connect(func():
		if selected_indices.is_empty():
			return
		layer.queue_free()
		for idx in selected_indices.keys():
			if hand.size() >= SkillEngine.MAX_HAND_SIZE:
				break
			var chosen: CardData = cards[int(idx)]
			hand.append(chosen.duplicate_card() if source == "deck" else chosen)
			if source == "deck":
				game.shared_deck.erase(chosen)
			elif source == "discard":
				game.shared_discard.erase(chosen)
		_refresh_hand_ui()
		update_entire_screen()
	)
	box.add_child(confirm_btn)

	var close_btn := Button.new()
	close_btn.text = Locale.t("battle.close")
	UITheme.apply_button(close_btn, "secondary")
	close_btn.pressed.connect(layer.queue_free)
	box.add_child(close_btn)


func _show_zero_cost_selection_popup(candidates: Array, count: int, hand: Array = [], target: String = SkillEngine.TARGET_SELF) -> void:
	var popup := UITheme.make_popup_layer(self, 120)
	var layer: CanvasLayer = popup["layer"]
	var panel := Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -280
	panel.offset_top = -240
	panel.offset_right = 280
	panel.offset_bottom = 240
	panel.clip_contents = true
	UITheme.apply_popup_frame(panel, "gold")
	layer.add_child(panel)
	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var include_sides: bool = target in [SkillEngine.TARGET_SIDES, SkillEngine.TARGET_SELF_SIDES]
	var title := Label.new()
	if include_sides:
		title.text = "选择一张卡牌降为0费（自动包含相邻卡牌，部署后恢复原费用）" if Locale.language == "zh" else "Choose a card to reduce to 0 cost (neighbors included, restored after deploy)"
	else:
		title.text = "选择要降为0费的卡牌（部署后恢复原费用）" if Locale.language == "zh" else "Choose cards to reduce to 0 cost (restored after deploy)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, 16)
	box.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	var grid_scroll: ScrollContainer = ScrollContainer.new()
	grid_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_scroll.custom_minimum_size = Vector2(0, 220 * _ui_scale())
	grid_scroll.add_child(grid)
	box.add_child(grid_scroll)

	var selected_indices: Dictionary = {}
	for i in range(min(candidates.size(), 8)):
		var card: CardData = candidates[i]
		var card_box := VBoxContainer.new()
		card_box.add_theme_constant_override("separation", 2)
		var card_ui := card_ui_scene.instantiate()
		card_ui.set_card(card)
		card_ui.apply_ui_scale(_ui_scale() * 0.7)
		card_ui.set_skill_preview_visible(true)
		card_box.add_child(card_ui)
		var check := CheckBox.new()
		check.text = card.card_name
		check.clip_text = true
		check.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		check.toggled.connect(func(pressed: bool):
			if pressed:
				if selected_indices.size() >= count:
					check.button_pressed = false
					return
				selected_indices[i] = true
			else:
				selected_indices.erase(i)
		)
		card_box.add_child(check)
		grid.add_child(card_box)

	var confirm_btn := Button.new()
	confirm_btn.text = Locale.t("battle.confirm")
	confirm_btn.custom_minimum_size = Vector2(160, 36)
	UITheme.apply_button(confirm_btn, "primary")
	confirm_btn.pressed.connect(func():
		if selected_indices.is_empty():
			return
		layer.queue_free()
		if include_sides and not hand.is_empty():
			# SIDES: apply to chosen card plus its hand neighbors
			var applied: Array = []
			for idx in selected_indices.keys():
				var chosen: CardData = candidates[int(idx)]
				var hand_idx: int = hand.find(chosen)
				if hand_idx >= 0 and not (chosen in applied):
					applied.append(chosen)
					for offset in [-1, 1]:
						var adj_idx : int = hand_idx + offset
						if adj_idx >= 0 and adj_idx < hand.size():
							var adj_card: CardData = hand[adj_idx]
							if adj_card is CardData and adj_card.cost > 0 and not adj_card.zero_cost_until_deploy and not (adj_card in applied):
								applied.append(adj_card)
			for card in applied:
				card.cost = 0
				card.zero_cost_until_deploy = true
		else:
			for idx in selected_indices.keys():
				var chosen: CardData = candidates[int(idx)]
				chosen.cost = 0
				chosen.zero_cost_until_deploy = true
		_refresh_hand_ui()
		update_entire_screen()
	)
	box.add_child(confirm_btn)

	var close_btn := Button.new()
	close_btn.text = Locale.t("battle.close")
	UITheme.apply_button(close_btn, "secondary")
	close_btn.pressed.connect(layer.queue_free)
	box.add_child(close_btn)


func _show_disconnect_result_page() -> void:
	var old_layer := $CanvasLayer.get_node_or_null("BattleResultLayer")
	if old_layer:
		old_layer.queue_free()
	var layer := Control.new()
	layer.name = "BattleResultLayer"
	_disconnect_overlay = layer
	layer.anchor_right = 1.0
	layer.anchor_bottom = 1.0
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	$CanvasLayer.add_child(layer)
	$CanvasLayer.move_child(layer, $CanvasLayer.get_child_count() - 1)

	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.015, 0.018, 0.026, 0.86)
	layer.add_child(bg)

	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	layer.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(540, 320) * _ui_scale()
	UITheme.apply_panel(panel, "gold")
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	margin.add_child(box)

	var title := Label.new()
	title.text = Locale.t("result.connection_lost_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, 36)
	box.add_child(title)

	var body := Label.new()
	body.text = Locale.t("result.connection_lost_body")
	body.name = "BodyLabel"
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.apply_label(body, true)
	body.add_theme_font_size_override("font_size", 18)
	box.add_child(body)

	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 18)
	box.add_child(button_row)

	var reconnect_btn := Button.new()
	reconnect_btn.text = Locale.t("result.reconnect")
	reconnect_btn.custom_minimum_size = Vector2(150, 48)
	reconnect_btn.disabled = not NetworkManager.can_reconnect_to_last_game_room()
	UITheme.apply_button(reconnect_btn, "primary")
	reconnect_btn.pressed.connect(_on_disconnect_reconnect_pressed)
	button_row.add_child(reconnect_btn)
	_disconnect_reconnect_btn = reconnect_btn

	var multiplayer_btn := Button.new()
	multiplayer_btn.text = Locale.t("result.back_multiplayer")
	multiplayer_btn.custom_minimum_size = Vector2(170, 48)
	UITheme.apply_button(multiplayer_btn, "secondary")
	multiplayer_btn.pressed.connect(_on_disconnect_back_multiplayer_pressed)
	button_row.add_child(multiplayer_btn)
	_disconnect_back_btn = multiplayer_btn

	var menu_btn := Button.new()
	menu_btn.text = Locale.t("result.back_menu")
	menu_btn.custom_minimum_size = Vector2(160, 48)
	UITheme.apply_button(menu_btn, "secondary")
	menu_btn.pressed.connect(_on_result_back_menu_pressed)
	button_row.add_child(menu_btn)

	layer.modulate.a = 0.0
	panel.scale = Vector2(0.88, 0.88)
	var twn := create_tween()
	twn.set_parallel(true)
	twn.tween_property(layer, "modulate:a", 1.0, 0.20)
	twn.tween_property(panel, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_disconnect_reconnect_pressed() -> void:
	var err := NetworkManager.reconnect_to_last_game_room()
	if err != OK:
		if _disconnect_overlay:
			var body := _disconnect_overlay.get_node_or_null("CenterContainer/PanelContainer/MarginContainer/VBoxContainer/BodyLabel")
			if body:
				body.text = Locale.t("result.reconnect_failed")
			if _disconnect_reconnect_btn:
				_disconnect_reconnect_btn.disabled = true
		return
	if _disconnect_reconnect_btn:
		_disconnect_reconnect_btn.disabled = true
	if _disconnect_back_btn:
		_disconnect_back_btn.disabled = true
	if _disconnect_overlay:
		var body := _disconnect_overlay.get_node_or_null("CenterContainer/PanelContainer/MarginContainer/VBoxContainer/BodyLabel")
		if body:
			body.text = Locale.t("result.reconnecting")


func _on_reconnect_failed() -> void:
	if not _disconnect_overlay:
		return
	if _disconnect_reconnect_btn:
		_disconnect_reconnect_btn.disabled = false
	if _disconnect_back_btn:
		_disconnect_back_btn.disabled = false
	var body := _disconnect_overlay.get_node_or_null("CenterContainer/PanelContainer/MarginContainer/VBoxContainer/BodyLabel")
	if body:
		body.text = Locale.t("result.reconnect_failed")


func _on_disconnect_back_multiplayer_pressed() -> void:
	NetworkManager.close_connection()
	get_tree().change_scene_to_file("res://MultiplayerMenu.tscn")


func _result_winner_player(result: String) -> int:
	if result == "p1_wins":
		return 1
	if result == "p2_wins":
		return 2
	return 0


func _did_local_player_win(result: String) -> bool:
	var winner := _result_winner_player(result)
	if winner == 0:
		return false
	if NetworkManager.is_online:
		return winner == my_player
	if PlayerData.battle_mode == "practice":
		return winner == 1
	return winner == _view_player()


func _result_title(result: String) -> String:
	var winner := _result_winner_player(result)
	if NetworkManager.is_online:
		return Locale.t("result.online_win") if _did_local_player_win(result) else Locale.t("result.online_loss")
	if PlayerData.battle_mode == "practice":
		return Locale.t("result.practice_win") if winner == 1 else Locale.t("result.practice_loss")
	if result == "p1_wins":
		return Locale.t("result.p1_wins")
	if result == "p2_wins":
		return Locale.t("result.p2_wins")
	return Locale.t("result.finished")


func _result_mode_text() -> String:
	if NetworkManager.is_online:
		return Locale.t("result.mode_online")
	if PlayerData.battle_mode == "practice":
		return Locale.t("result.mode_practice")
	return Locale.t("result.mode_hotseat")


func _show_battle_result_page(result: String) -> void:
	var old_layer := $CanvasLayer.get_node_or_null("BattleResultLayer")
	if old_layer:
		old_layer.queue_free()
	var layer := Control.new()
	layer.name = "BattleResultLayer"
	layer.anchor_right = 1.0
	layer.anchor_bottom = 1.0
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	$CanvasLayer.add_child(layer)
	$CanvasLayer.move_child(layer, $CanvasLayer.get_child_count() - 1)

	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.015, 0.018, 0.026, 0.82)
	layer.add_child(bg)

	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	layer.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 360) * _ui_scale()
	UITheme.apply_panel(panel, "gold")
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	margin.add_child(box)

	var title := Label.new()
	title.text = _result_title(result)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, 42)
	box.add_child(title)

	var outcome := Label.new()
	outcome.text = Locale.t("result.victory") if _did_local_player_win(result) else Locale.t("result.defeat")
	if not NetworkManager.is_online and PlayerData.battle_mode != "practice":
		outcome.text = Locale.t("result.finished")
	outcome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_label(outcome, true)
	outcome.add_theme_font_size_override("font_size", 18)
	box.add_child(outcome)

	var mode_label := Label.new()
	var mode_text := _result_mode_text()
	if PlayerData.battle_mode == "practice":
		mode_text = "%s · %s" % [mode_text, Locale.t("menu.ai_%s" % PlayerData.practice_ai_difficulty)]
	mode_label.text = mode_text
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_label(mode_label, true)
	box.add_child(mode_label)

	var summary := Label.new()
	summary.text = Locale.t("result.summary", [game.turn_number, game.player_field.player_hp, game.player2_field.player_hp])
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_label(summary)
	summary.add_theme_font_size_override("font_size", 18)
	box.add_child(summary)

	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 18)
	box.add_child(button_row)

	var again_btn := Button.new()
	again_btn.text = Locale.t("result.play_again")
	again_btn.custom_minimum_size = Vector2(160, 48)
	UITheme.apply_button(again_btn, "primary")
	again_btn.pressed.connect(_on_result_play_again_pressed)
	button_row.add_child(again_btn)

	var menu_btn := Button.new()
	menu_btn.text = Locale.t("result.back_menu")
	menu_btn.custom_minimum_size = Vector2(160, 48)
	UITheme.apply_button(menu_btn, "secondary")
	menu_btn.pressed.connect(_on_result_back_menu_pressed)
	button_row.add_child(menu_btn)

	layer.modulate.a = 0.0
	panel.scale = Vector2(0.88, 0.88)
	var twn := create_tween()
	twn.set_parallel(true)
	twn.tween_property(layer, "modulate:a", 1.0, 0.20)
	twn.tween_property(panel, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_result_play_again_pressed() -> void:
	if NetworkManager.is_online:
		NetworkManager.close_connection()
		get_tree().change_scene_to_file("res://MainMenu.tscn")
		return
	get_tree().reload_current_scene()


func _on_result_back_menu_pressed() -> void:
	NetworkManager.close_connection()
	get_tree().change_scene_to_file("res://MainMenu.tscn")


# ============================================
# UI refresh
# ============================================

func update_entire_screen():
	if battle_finished:
		return
	if mana_label:
		if game.is_player_turn:
			var viewed_player := _view_player()
			if NetworkManager.is_online and show_enemy_status:
				viewed_player = _opponent_player()
			var f = _field_for_player(viewed_player)
			var hand_size := _hand_for_player(viewed_player).size()
			var view_text := Locale.t("battle.view_turn", [game.current_player])
			if NetworkManager.is_online:
				var who := Locale.t("battle.enemy") if show_enemy_status else Locale.t("battle.you")
				view_text = Locale.t("battle.viewing", [viewed_player, who])
			mana_label.text = Locale.t("battle.status_line", [
				view_text, f.get_total_mana(), f.max_mana,
				f.player_hp, hand_size, 6, game.turn_number
			])
		else:
			mana_label.text = Locale.t("battle.switching")
	if status_toggle_button:
		status_toggle_button.visible = NetworkManager.is_online
		status_toggle_button.text = Locale.t("battle.enemy_info") if not show_enemy_status else Locale.t("battle.my_info")

	var my_field = _my_field()
	var their_field = _their_field()
	var p_slots = player_side_ui.get_children()
	var e_slots = enemy_side_ui.get_children()

	for i in range(5):
		_scale_control(p_slots[i], BASE_SLOT_SIZE)
		_scale_control(e_slots[i], BASE_SLOT_SIZE)
		p_slots[i].set_card(my_field.slots[i])
		if my_field.slots[i] != null and p_slots[i].current_card_ui != null:
			p_slots[i].current_card_ui.set_card(my_field.slots[i])
			_scale_control(p_slots[i].current_card_ui, BASE_CARD_SIZE)

		e_slots[i].set_card(their_field.slots[i])
		if their_field.slots[i] != null and e_slots[i].current_card_ui != null:
			e_slots[i].current_card_ui.set_card(their_field.slots[i])
			_scale_control(e_slots[i].current_card_ui, BASE_CARD_SIZE)
	_toggle_turn_cover()


func _process(_delta):
	if is_my_turn():
		var source: int = -1
		if current_attacker_idx != -1:
			source = current_attacker_idx
		elif summon_targeting:
			source = summon_source_slot
		elif activate_targeting:
			source = activate_source_slot

		if source != -1:
			var slot_ui = _my_slots_ui()[source]
			var start_pos = slot_ui.global_position + slot_ui.size / 2
			var end_pos = get_global_mouse_position()
			attack_arrow.points = [start_pos, end_pos]
			attack_arrow.visible = true

			var hovered := -1
			for i in range(5):
				var e_slot = _their_slots_ui()[i]
				var rect := Rect2(e_slot.global_position, e_slot.size)
				if rect.has_point(get_global_mouse_position()):
					hovered = i
					break
			if hovered != last_hovered_target:
				last_hovered_target = hovered
				if NetworkManager.is_online:
					NetworkManager.rpc_targeting_arrow.rpc(source, hovered, game.current_player)
		else:
			attack_arrow.visible = false
			last_hovered_target = -1
	else:
		if remote_arrow_source >= 0 and remote_arrow_target >= 0:
			var src_slots = _their_slots_ui()
			var src_ui = src_slots[remote_arrow_source]
			var start_pos = src_ui.global_position + src_ui.size / 2
			var tgt_slots = _my_slots_ui()
			var tgt_ui = tgt_slots[remote_arrow_target]
			var end_pos = tgt_ui.global_position + tgt_ui.size / 2
			attack_arrow.points = [start_pos, end_pos]
			attack_arrow.visible = true
		else:
			attack_arrow.visible = false


# ============================================
# Network
# ============================================

var my_player: int = 0
var remote_arrow_source: int = -1
var remote_arrow_target: int = -1
var last_hovered_target: int = -1
var _charm_popup_active: bool = false
# Authority collects hp_changed events during an action, then ships them in the
# state broadcast so the non-authority client can replay floating text.
var _pending_hp_events: Array = []

func is_my_turn() -> bool:
	if not NetworkManager.is_online:
		if PlayerData.battle_mode == "practice":
			return game.current_player == 1 and not practice_ai_running
		return true
	return game.current_player == my_player


func _init_network():
	if not NetworkManager.is_online:
		my_player = 0
		return
	my_player = NetworkManager.player_number
	EventBus.rpc_initial_state_received.connect(_on_rpc_initial_state)
	EventBus.rpc_initial_state_requested.connect(_on_rpc_initial_state_requested)
	EventBus.rpc_authority_state_received.connect(_on_rpc_authority_state)
	EventBus.rpc_summon_received.connect(_on_rpc_summon)
	EventBus.rpc_summon_skill_received.connect(_on_rpc_summon_skill)
	EventBus.rpc_attack_received.connect(_on_rpc_attack)
	EventBus.rpc_activate_skill_received.connect(_on_rpc_skill)
	EventBus.rpc_end_turn_received.connect(_on_rpc_end_turn)
	EventBus.rpc_discard_received.connect(_on_rpc_discard)
	EventBus.rpc_move_received.connect(_on_rpc_move)
	EventBus.rpc_intent_summon_received.connect(_on_rpc_intent_summon)
	EventBus.rpc_intent_summon_skill_received.connect(_on_rpc_intent_summon_skill)
	EventBus.rpc_intent_attack_received.connect(_on_rpc_intent_attack)
	EventBus.rpc_intent_activate_skill_received.connect(_on_rpc_intent_skill)
	EventBus.rpc_intent_end_turn_received.connect(_on_rpc_intent_end_turn)
	EventBus.rpc_intent_discard_received.connect(_on_rpc_intent_discard)
	EventBus.rpc_intent_move_received.connect(_on_rpc_intent_move)
	EventBus.rpc_targeting_arrow_received.connect(_on_rpc_targeting_arrow)
	EventBus.rpc_splash_received.connect(_on_rpc_splash)
	NetworkManager.opponent_disconnected.connect(_on_opponent_disconnected)
	NetworkManager.connected.connect(_on_opponent_reconnected)
	NetworkManager.game_connection_failed.connect(_on_reconnect_failed)


func _sync_targeting_state():
	if not NetworkManager.is_online:
		return
	var source := -1
	if current_attacker_idx != -1:
		source = current_attacker_idx
	elif summon_targeting:
		source = summon_source_slot
	elif activate_targeting:
		source = activate_source_slot
	# cast_targeting/parasite_targeting start from hand cards, so source stays -1.

	if source >= 0:
		NetworkManager.rpc_targeting_arrow.rpc(source, last_hovered_target, game.current_player)
	else:
		NetworkManager.rpc_targeting_arrow.rpc(-1, -1, game.current_player)


func _on_rpc_targeting_arrow(source_slot: int, target_slot: int, player: int):
	if player == my_player: return
	remote_arrow_source = source_slot
	remote_arrow_target = target_slot


func _on_rpc_splash(player: int, slot_index: int):
	# Only the authority broadcasts this RPC, and the authority never receives its
	# own call_remote, so any peer that gets here is the non-authority client and
	# must always render it (the client never shows the splash locally on its own
	# actions — it only sends an intent and waits for the authority to resolve).
	_update_remote_splash(player, slot_index)


# Authority-side: show the splash locally and tell the opponent to show the same.
# Capture the acting card before deaths are applied so its art/name still resolves.
func _authority_splash(player: int, slot_index: int) -> void:
	if slot_index < 0:
		return
	var field = game.player_field if player == 1 else game.player2_field
	var card: CardData = field.slots[slot_index]
	if card != null:
		_show_splash(card)
	if NetworkManager.is_online:
		NetworkManager.rpc_splash.rpc(player, slot_index)


func _on_rpc_initial_state(state: Dictionary):
	if NetworkManager.is_authority():
		return
	_apply_authority_state(state, "initial")


func _on_rpc_initial_state_requested(_peer_id: int):
	if not NetworkManager.is_authority():
		return
	_broadcast_authority_state("initial request")
	NetworkManager.rpc_initial_state.rpc(game.export_initial_state())


func _on_rpc_authority_state(state: Dictionary):
	if NetworkManager.is_authority():
		return
	_apply_authority_state(state, "remote authority")


func _host_apply_summon(hand_index: int, slot_index: int, player: int) -> void:
	if not NetworkManager.is_authority() or player != game.current_player:
		return
	var hand = _hand_for_player(player)
	if hand_index < 0 or hand_index >= hand.size():
		return
	var saved = game.current_player
	game.current_player = player
	var card: CardData = hand[hand_index]
	if not game.summon_card(card, slot_index):
		game.current_player = saved
		return
	game.current_player = saved
	# on_summon skills are activated manually by the summoning player this turn;
	# nothing auto-fires here. The summoned_this_turn flag travels in the state.
	_refresh_hand_ui()
	update_entire_screen()
	_broadcast_authority_state("summon")


func _host_apply_summon_skill(slot_index: int, skill_index: int, target_slot: int, player: int) -> void:
	if not NetworkManager.is_authority() or player != game.current_player:
		return
	var source_card: CardData = _field_for_player(player).slots[slot_index]
	var target_card: CardData = _field_for_player(_opponent_of_player(player)).slots[target_slot] if target_slot >= 0 else null
	var skill: Dictionary = source_card.skills[skill_index] if source_card != null and skill_index < source_card.skills.size() else {}
	_begin_action_broadcast("summon_skill", player, source_card.card_name if source_card != null else "单位", target_card.card_name if target_card != null else "", {"skill": skill.get("skill_name", "技能")})
	var saved = game.current_player
	game.current_player = player
	var card: CardData = game.active_field().slots[slot_index]
	if card != null and not card.skills_used.has(skill_index):
		card.skills_used.append(skill_index)
	game.trigger_summon_skills(slot_index, target_slot, skill_index)
	game.current_player = saved
	_finish_action_broadcast()
	_play_skill_cast_feedback(player, slot_index)
	_record_feedback_event("skill", player, slot_index)
	_authority_splash(player, slot_index)
	_apply_deaths()
	_check_charm_overflow()
	_refresh_hand_ui()
	update_entire_screen()
	if _check_and_show_game_over():
		_broadcast_authority_state("game over")
		return
	_broadcast_authority_state("summon skill")


func _host_apply_attack(source_slot: int, target_slot: int, player: int) -> void:
	if not NetworkManager.is_authority() or player != game.current_player:
		return
	var attacker: CardData = _field_for_player(player).slots[source_slot]
	var victim: CardData = _field_for_player(_opponent_of_player(player)).slots[target_slot]
	var base_damage: int = attacker.atk if attacker != null else 0
	var effective_damage: int = attacker.effective_atk() if attacker != null else 0
	_begin_action_broadcast("attack", player, attacker.card_name if attacker != null else "单位", victim.card_name if victim != null else "单位", {"base_damage": base_damage, "effective_damage": effective_damage, "target_player": _opponent_of_player(player), "target_slot": target_slot})
	var saved = game.current_player
	game.current_player = player
	var result: Dictionary = game.execute_attack(source_slot, target_slot)
	game.current_player = saved
	if victim != null and not victim.is_alive():
		_action_broadcast["kill_mana"] = true
	_finish_action_broadcast()
	if not result.is_empty():
		_play_attack_feedback(player, source_slot, target_slot)
		_record_feedback_event("attack", player, source_slot, {"target_slot": target_slot})
		_authority_splash(player, source_slot)
	_apply_deaths()
	_check_charm_overflow()
	_refresh_hand_ui()
	update_entire_screen()
	if _check_and_show_game_over():
		_broadcast_authority_state("game over")
		return
	_broadcast_authority_state("attack")


func _host_apply_skill(slot_index: int, skill_index: int, target_slot: int, player: int) -> void:
	if not NetworkManager.is_authority() or player != game.current_player:
		return
	var source_card: CardData = _field_for_player(player).slots[slot_index]
	var target_card: CardData = _field_for_player(_opponent_of_player(player)).slots[target_slot] if target_slot >= 0 else null
	var skill: Dictionary = source_card.skills[skill_index] if source_card != null and skill_index < source_card.skills.size() else {}
	_begin_action_broadcast("skill", player, source_card.card_name if source_card != null else "单位", target_card.card_name if target_card != null else "", {"skill": skill.get("skill_name", "技能")})
	var saved = game.current_player
	game.current_player = player
	var card: CardData = game.active_field().slots[slot_index]
	if card != null and not card.skills_used.has(skill_index):
		card.skills_used.append(skill_index)
	game.trigger_activate_skills(slot_index, target_slot, skill_index)
	game.current_player = saved
	_finish_action_broadcast()
	_play_skill_cast_feedback(player, slot_index)
	_record_feedback_event("skill", player, slot_index)
	_authority_splash(player, slot_index)
	_apply_deaths()
	_check_charm_overflow()
	_refresh_hand_ui()
	update_entire_screen()
	if _check_and_show_game_over():
		_broadcast_authority_state("game over")
		return
	_broadcast_authority_state("activate skill")


func _host_apply_parasite(hand_index: int, target_player: int, target_slot: int, player: int) -> void:
	if not NetworkManager.is_authority() or player != game.current_player:
		return
	var hand := _hand_for_player(player)
	var parasite_card: CardData = hand[hand_index] if hand_index >= 0 and hand_index < hand.size() else null
	var target_field := _field_for_player(target_player)
	var target_card: CardData = target_field.slots[target_slot] if target_slot >= 0 and target_slot < target_field.slots.size() else null
	_begin_action_broadcast("parasite", player, parasite_card.card_name if parasite_card != null else "寄生", target_card.card_name if target_card != null else "")
	var saved = game.current_player
	game.current_player = player
	var attach_ok: bool = game.attach_parasite(hand_index, target_player, target_slot)
	game.current_player = saved
	if not attach_ok:
		_action_broadcast.clear()
		_action_hp_events.clear()
		return
	_finish_action_broadcast()
	_refresh_hand_ui()
	update_entire_screen()
	_broadcast_authority_state("attach parasite")


func _host_apply_cast(hand_index: int, skill_index: int, target_slot: int, player: int) -> void:
	if not NetworkManager.is_authority() or player != game.current_player:
		return
	var hand := _hand_for_player(player)
	var spell_card: CardData = hand[hand_index] if hand_index >= 0 and hand_index < hand.size() else null
	_begin_action_broadcast("cast", player, spell_card.card_name if spell_card != null else "法术", "")
	var saved = game.current_player
	game.current_player = player
	var cast_ok: bool = game.cast_spell(hand_index, skill_index, target_slot)
	game.current_player = saved
	if not cast_ok:
		_action_broadcast.clear()
		_action_hp_events.clear()
		return
	_finish_action_broadcast()
	_play_skill_cast_feedback(player, -1)
	_record_feedback_event("cast", player, -1)
	_apply_deaths()
	_check_charm_overflow()
	_refresh_hand_ui()
	update_entire_screen()
	if _check_and_show_game_over():
		_broadcast_authority_state("game over")
		return
	_broadcast_authority_state("cast spell")


func _host_apply_discard(location: String, index: int, player: int) -> void:
	if not NetworkManager.is_authority() or player != game.current_player:
		return
	var card: CardData = null
	if location == "hand":
		var hand = _hand_for_player(player)
		if index >= 0 and index < hand.size():
			card = hand[index]
	elif location == "field":
		var field = _field_for_player(player)
		if index >= 0 and index < field.slots.size():
			card = field.slots[index]
	if card == null:
		return
	var saved = game.current_player
	game.current_player = player
	game.discard_card(card)
	game.current_player = saved
	_refresh_hand_ui()
	update_entire_screen()
	_show_combat_broadcast(Locale.t("tip.discard_mana"))
	_play_discard_feedback()
	_record_feedback_event("broadcast_text", player, -1, {"text_key": "tip.discard_mana"})
	_record_feedback_event("discard", player, -1)
	_broadcast_authority_state("discard")


func _host_apply_move(source_slot: int, target_slot: int, player: int) -> void:
	if not NetworkManager.is_authority() or player != game.current_player:
		return
	var field = _field_for_player(player)
	if source_slot < 0 or source_slot >= field.slots.size() or target_slot < 0 or target_slot >= field.slots.size():
		return
	var displaced = field.slots[target_slot]
	field.slots[target_slot] = field.slots[source_slot]
	field.slots[source_slot] = displaced
	update_entire_screen()
	_broadcast_authority_state("move")


func _host_apply_end_turn(player: int) -> void:
	if not NetworkManager.is_authority() or player != game.current_player:
		return
	remote_arrow_source = -1
	var result = game.end_player_turn()
	_show_direct_damage(result)
	end_turn_button.disabled = true
	update_entire_screen()
	if _check_and_show_game_over():
		_broadcast_authority_state("game over")
		return
	await get_tree().create_timer(0.3).timeout
	game.start_new_turn()
	_refresh_hand_ui()
	end_turn_button.disabled = false
	update_entire_screen()
	_broadcast_authority_state("end turn")


func _spell_intent_source(hand_index: int) -> int:
	return -1000 - hand_index


func _parasite_intent_source(hand_index: int, target_player: int) -> int:
	return (-2000 - hand_index) if target_player == 1 else (-3000 - hand_index)


func _is_parasite_intent_source(source_slot: int) -> bool:
	return source_slot <= -2000 and source_slot > -4000


func _parasite_hand_index_from_intent(source_slot: int) -> int:
	return (-2000 - source_slot) if source_slot > -3000 else (-3000 - source_slot)


func _parasite_target_player_from_intent(source_slot: int) -> int:
	return 1 if source_slot > -3000 else 2


func _is_spell_intent_source(source_slot: int) -> bool:
	return source_slot <= -1000 and source_slot > -2000


func _spell_hand_index_from_intent(source_slot: int) -> int:
	return -1000 - source_slot


func _on_rpc_intent_summon(hand_index: int, slot_index: int, player: int):
	_host_apply_summon(hand_index, slot_index, player)


func _on_rpc_intent_summon_skill(slot_index: int, skill_index: int, target_slot: int, player: int):
	_host_apply_summon_skill(slot_index, skill_index, target_slot, player)


func _on_rpc_intent_attack(source_slot: int, target_slot: int, player: int):
	_host_apply_attack(source_slot, target_slot, player)


func _on_rpc_intent_skill(slot_index: int, skill_index: int, target_slot: int, player: int):
	if _is_parasite_intent_source(slot_index):
		_host_apply_parasite(_parasite_hand_index_from_intent(slot_index), _parasite_target_player_from_intent(slot_index), target_slot, player)
		return
	if _is_spell_intent_source(slot_index):
		_host_apply_cast(_spell_hand_index_from_intent(slot_index), skill_index, target_slot, player)
		return
	_host_apply_skill(slot_index, skill_index, target_slot, player)


func _on_rpc_intent_end_turn(player: int):
	await _host_apply_end_turn(player)


func _on_rpc_intent_discard(location: String, index: int, player: int):
	_host_apply_discard(location, index, player)


func _on_rpc_intent_move(source_slot: int, target_slot: int, player: int):
	_host_apply_move(source_slot, target_slot, player)


func _on_rpc_summon(_hand_index: int, _slot_index: int, _player: int):
	return


func _on_rpc_summon_skill(_slot_index: int, _skill_index: int, _target_slot: int, _player: int):
	return


func _on_rpc_attack(_source_slot: int, _target_slot: int, _player: int):
	return


func _on_rpc_skill(_slot_index: int, _skill_index: int, _target_slot: int, _player: int):
	return


func _on_rpc_end_turn(_player: int):
	return


func _on_rpc_discard(_location: String, _index: int, _player: int):
	return


func _on_rpc_move(_source_slot: int, _target_slot: int, _player: int):
	return


func _update_remote_splash(player: int, slot_index: int):
	var field = game.player_field if player == 1 else game.player2_field
	var card = field.slots[slot_index]
	if card != null:
		_show_splash(card)

func _build_turn_cover():
	turn_cover = ColorRect.new()
	turn_cover.name = "TurnCover"
	turn_cover.visible = false
	turn_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	turn_cover.anchor_right = 1.0
	turn_cover.anchor_bottom = 1.0
	turn_cover.color = Color(0.0, 0.0, 0.0, 0.34)
	$CanvasLayer.add_child(turn_cover)

	turn_wait_hint = Panel.new()
	turn_wait_hint.name = "TurnWaitHint"
	turn_wait_hint.visible = false
	turn_wait_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	turn_wait_hint.anchor_left = 0.5
	turn_wait_hint.anchor_right = 0.5
	turn_wait_hint.anchor_top = 1.0
	turn_wait_hint.anchor_bottom = 1.0
	UITheme.apply_panel(turn_wait_hint, "gold")
	var lbl = Label.new()
	lbl.name = "Label"
	lbl.text = Locale.t("battle.waiting")
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.anchor_right = 1.0
	lbl.anchor_bottom = 1.0
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", 16)
	UITheme.apply_label(lbl, true)
	turn_wait_hint.add_child(lbl)
	$CanvasLayer.add_child(turn_wait_hint)
	_update_wait_hint_layout()


func _update_wait_hint_layout() -> void:
	if turn_wait_hint == null:
		return
	var s := _ui_scale()
	var hint_size := Vector2(260, 36) * s
	turn_wait_hint.offset_left = -hint_size.x / 2.0
	turn_wait_hint.offset_right = hint_size.x / 2.0
	turn_wait_hint.offset_top = -hint_size.y - 10.0 * s
	turn_wait_hint.offset_bottom = -10.0 * s
	var lbl := turn_wait_hint.get_node_or_null("Label")
	if lbl:
		lbl.add_theme_font_size_override("font_size", max(10, int(15 * s)))


func _toggle_turn_cover():
	var show = (NetworkManager.is_online and not is_my_turn()) or (PlayerData.battle_mode == "practice" and game.current_player == 2)
	if turn_cover:
		turn_cover.visible = show
		$CanvasLayer.move_child(turn_cover, max(0, $CanvasLayer.get_child_count() - 2))
	if turn_wait_hint:
		_update_wait_hint_layout()
		turn_wait_hint.visible = show
		$CanvasLayer.move_child(turn_wait_hint, $CanvasLayer.get_child_count() - 1)


# ============================================
# Draw/Discard pile UI
# ============================================

func _build_pile_buttons():
	draw_pile_btn = Button.new()
	draw_pile_btn.text = Locale.t("battle.draw_pile")
	draw_pile_btn.pressed.connect(_on_draw_pile_clicked)
	UITheme.apply_button(draw_pile_btn, "secondary")
	$CanvasLayer.add_child(draw_pile_btn)

	discard_pile_btn = Button.new()
	discard_pile_btn.text = Locale.t("battle.discard_pile")
	discard_pile_btn.pressed.connect(_on_discard_pile_clicked)
	UITheme.apply_button(discard_pile_btn, "secondary")
	$CanvasLayer.add_child(discard_pile_btn)

	help_btn = Button.new()
	help_btn.text = Locale.t("help.button")
	help_btn.pressed.connect(_on_help_clicked)
	UITheme.apply_button(help_btn, "secondary")
	$CanvasLayer.add_child(help_btn)

	_update_pile_labels()
	_apply_responsive_layout()


func _on_debug_state_clicked():
	_print_authority_state("button")
	if NetworkManager.is_online and NetworkManager.is_authority():
		NetworkManager.rpc_authority_state.rpc(game.export_initial_state())


func _on_help_clicked():
	_show_help_popup()


# Static rules manual — blur overlay + scrollable mechanics text.
func _show_help_popup():
	var s := _ui_scale()
	var popup_layer := CanvasLayer.new()
	popup_layer.layer = 100
	add_child(popup_layer)

	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	var mat := ShaderMaterial.new()
	mat.shader = load("res://blur.gdshader")
	mat.set_shader_parameter("strength", 2.5)
	bg.material = mat
	bg.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			popup_layer.queue_free()
	)
	popup_layer.add_child(bg)

	var panel := Panel.new()
	UITheme.apply_panel(panel, "gold")
	panel.clip_contents = true
	panel.anchor_left = 0.15
	panel.anchor_right = 0.85
	panel.anchor_top = 0.1
	panel.anchor_bottom = 0.9
	popup_layer.add_child(panel)

	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", int(20 * s))
	margin.add_theme_constant_override("margin_right", int(20 * s))
	margin.add_theme_constant_override("margin_top", int(16 * s))
	margin.add_theme_constant_override("margin_bottom", int(16 * s))
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(12 * s))
	margin.add_child(vbox)

	var title := Label.new()
	title.text = Locale.t("help.title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, max(16, int(24 * s)))
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_FILL
	vbox.add_child(scroll)

	var body := Label.new()
	body.text = Locale.t("help.body", [SkillEngine.MAX_HAND_SIZE])
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	body.add_theme_font_size_override("font_size", max(12, int(17 * s)))
	UITheme.apply_label(body)
	scroll.add_child(body)

	var close_btn := Button.new()
	close_btn.text = Locale.t("help.close")
	close_btn.custom_minimum_size = Vector2(100, 40) * s
	close_btn.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UITheme.apply_button(close_btn, "secondary")
	close_btn.pressed.connect(popup_layer.queue_free)
	vbox.add_child(close_btn)


func _update_pile_labels():
	if not draw_pile_btn or not discard_pile_btn:
		return
	var field = _my_field()
	if field:
		draw_pile_btn.text = Locale.t("battle.deck", [game.shared_deck.size()])
		discard_pile_btn.text = Locale.t("battle.discard", [game.shared_discard.size()])


func _on_draw_pile_clicked():
	var field = _my_field()
	if not field: return
	_show_pile_viewer(game.shared_deck, Locale.t("battle.draw_pile_title", [game.shared_deck.size()]))


func _on_discard_pile_clicked():
	var field = _my_field()
	if not field: return
	_show_pile_viewer(game.shared_discard, Locale.t("battle.discard_pile_title", [game.shared_discard.size()]))


func _show_pile_viewer(cards: Array, title_text: String):
	if cards.is_empty():
		return

	var s := _ui_scale()
	var popup_layer := CanvasLayer.new()
	popup_layer.layer = 100
	add_child(popup_layer)

	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	var mat := ShaderMaterial.new()
	mat.shader = load("res://blur.gdshader")
	mat.set_shader_parameter("strength", 2.5)
	bg.material = mat
	bg.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			popup_layer.queue_free()
	)
	popup_layer.add_child(bg)

	var panel := Panel.new()
	UITheme.apply_panel(panel, "gold")
	panel.clip_contents = true
	panel.anchor_left = 0.1
	panel.anchor_right = 0.9
	panel.anchor_top = 0.1
	panel.anchor_bottom = 0.9
	popup_layer.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.add_theme_constant_override("separation", int(10 * s))
	panel.add_child(vbox)

	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, max(15, int(20 * s)))
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_FILL
	vbox.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", int(8 * s))
	grid.add_theme_constant_override("v_separation", int(8 * s))
	scroll.add_child(grid)

	for c in cards:
		var cui := card_ui_scene.instantiate()
		grid.add_child(cui)
		cui.set_card(c)
		if cui.has_method("set_skill_preview_visible"):
			cui.call("set_skill_preview_visible", true)
		else:
			cui.set_actions_visible(false)
		if cui.has_method("apply_ui_scale"):
			cui.call("apply_ui_scale", s)

	var close_btn := Button.new()
	close_btn.text = Locale.t("battle.close")
	close_btn.custom_minimum_size = Vector2(100, 40) * s
	close_btn.add_theme_font_size_override("font_size", max(10, int(14 * s)))
	UITheme.apply_button(close_btn, "secondary")
	close_btn.pressed.connect(popup_layer.queue_free)
	vbox.add_child(close_btn)



# ============================================
# Charm overflow
# ============================================

func _check_charm_overflow():
	if _charm_popup_active:
		return
	var hand = _my_hand()
	if hand.size() <= SkillEngine.MAX_HAND_SIZE:
		return
	var charmed_cards = hand.filter(func(c): return c != null and c.is_charmed())
	if charmed_cards.is_empty():
		return
	var non_charmed = hand.size() - charmed_cards.size()
	var max_picks = max(0, SkillEngine.MAX_HAND_SIZE - non_charmed)
	if max_picks <= 0:
		for c in charmed_cards:
			hand.erase(c)
		_refresh_hand_ui()
		return
	if max_picks >= charmed_cards.size():
		while hand.size() > SkillEngine.MAX_HAND_SIZE:
			hand.erase(charmed_cards.pop_back())
		_refresh_hand_ui()
		return
	_show_charm_selection(charmed_cards, max_picks)


func _show_charm_selection(charmed_cards: Array, max_picks: int):
	_charm_popup_active = true
	var popup_layer := CanvasLayer.new()
	popup_layer.layer = 100
	add_child(popup_layer)

	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	var mat := ShaderMaterial.new()
	mat.shader = load("res://blur.gdshader")
	mat.set_shader_parameter("strength", 2.5)
	bg.material = mat
	popup_layer.add_child(bg)

	var panel := Panel.new()
	UITheme.apply_panel(panel, "gold")
	panel.anchor_left = 0.1
	panel.anchor_right = 0.9
	panel.anchor_top = 0.15
	panel.anchor_bottom = 0.85
	popup_layer.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	panel.add_child(vbox)

	var title := Label.new()
	title.text = Locale.t("battle.choose_keep")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, 22)
	vbox.add_child(title)

	var info := Label.new()
	info.text = Locale.t("battle.hand_remaining", [max_picks, max_picks])
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 16)
	UITheme.apply_label(info, true)
	vbox.add_child(info)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_FILL
	vbox.add_child(scroll)

	var card_hbox := HBoxContainer.new()
	card_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	scroll.add_child(card_hbox)

	var selected := {}
	for c in charmed_cards:
		selected[c] = false

	var card_uis := []
	for c in charmed_cards:
		var cui := card_ui_scene.instantiate()
		card_hbox.add_child(cui)
		cui.set_card(c)
		cui.modulate = Color(0.4, 0.4, 0.4)
		card_uis.append(cui)

		var click_handler = func(event: InputEvent, card_data: CardData, ui: Control):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				selected[card_data] = not selected[card_data]
				if selected[card_data]:
					ui.modulate = Color.WHITE
				else:
					ui.modulate = Color(0.4, 0.4, 0.4)
				var sel_count := 0
				for v in selected.values():
					if v: sel_count += 1
				if sel_count > max_picks:
					selected[card_data] = false
					ui.modulate = Color(0.4, 0.4, 0.4)
		cui.gui_input.connect(click_handler.bind(c, cui))

	var confirm_btn := Button.new()
	confirm_btn.text = Locale.t("battle.confirm")
	confirm_btn.custom_minimum_size = Vector2(120, 40)
	vbox.add_child(confirm_btn)

	confirm_btn.pressed.connect(func():
		var hand = _my_hand()
		for c in charmed_cards:
			if not selected.get(c, false):
				hand.erase(c)
		_charm_popup_active = false
		popup_layer.queue_free()
		_refresh_hand_ui()
	)
