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
var summon_skill_idx: int = -1
var activate_skill_idx: int = -1
var card_ui_scene = preload("res://CardUI.tscn")

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
var turn_cover: Panel
var draw_pile_btn: Button
var discard_pile_btn: Button
var debug_state_btn: Button
var help_btn: Button
var toast_label: Label
var toast_tween: Tween
var show_enemy_status: bool = false
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
	if draw_pile_btn:
		_scale_control(draw_pile_btn, BASE_PILE_BUTTON_SIZE)
		draw_pile_btn.position = Vector2(20 * s, bottom_y)
		draw_pile_btn.add_theme_font_size_override("font_size", max(9, int(12 * s)))
	if discard_pile_btn:
		_scale_control(discard_pile_btn, BASE_PILE_BUTTON_SIZE)
		discard_pile_btn.position = Vector2(150 * s, bottom_y)
		discard_pile_btn.add_theme_font_size_override("font_size", max(9, int(12 * s)))
	if debug_state_btn:
		_scale_control(debug_state_btn, BASE_DEBUG_BUTTON_SIZE)
		debug_state_btn.position = Vector2(280 * s, bottom_y)
		debug_state_btn.add_theme_font_size_override("font_size", max(9, int(12 * s)))
	if help_btn:
		_scale_control(help_btn, BASE_HELP_BUTTON_SIZE)
		help_btn.position = Vector2(420 * s, bottom_y)
		help_btn.add_theme_font_size_override("font_size", max(9, int(12 * s)))
	_scale_toast()

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
	if NetworkManager.is_online or my_player in [1, 2]:
		return my_player
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
		# Ship the hp changes from this action so the non-authority can replay
		# floating text (it never runs combat logic itself).
		state["_hp_events"] = _pending_hp_events.duplicate()
		_pending_hp_events.clear()
		NetworkManager.rpc_authority_state.rpc(state)


func _commit_authority_state(label: String) -> void:
	if NetworkManager.is_online and NetworkManager.is_authority():
		game.state_revision += 1
	_broadcast_authority_state(label)


func _apply_authority_state(state: Dictionary, label: String = "authority") -> void:
	game.apply_initial_state(state)
	_restore_local_art_paths()
	remote_arrow_source = -1
	remote_arrow_target = -1
	_refresh_hand_ui()
	_check_charm_overflow()
	update_entire_screen()
	# Replay floating text for damage/heal that happened on the authority.
	var hp_events: Array = state.get("_hp_events", [])
	for ev in hp_events:
		_show_floating_for(int(ev.get("player", 0)), int(ev.get("slot", -1)), int(ev.get("delta", 0)))
	_print_authority_state(label)
	var game_over: String = game.check_game_over()
	if game_over != "":
		_show_result(game_over)


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

func _ready():
	game = load("res://GameState.gd").new()
	_init_network()
	game.init_game(Callable(self, "_on_game_draw_cards"))
	_build_turn_cover()
	_build_pile_buttons()

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
		if p_slots[i].has_signal("card_dropped_here"):
			p_slots[i].card_dropped_here.connect(_on_card_drag_summoned.bind(i))

		e_slots[i].pressed.connect(_on_enemy_slot_clicked.bind(i))
		if e_slots[i].has_signal("slot_attack_requested"):
			e_slots[i].slot_attack_requested.connect(_on_attack_requested.bind(i))
		if e_slots[i].has_signal("slot_skill1_requested"):
			e_slots[i].slot_skill1_requested.connect(_on_skill_activated.bind(i, 0))
		if e_slots[i].has_signal("slot_skill2_requested"):
			e_slots[i].slot_skill2_requested.connect(_on_skill_activated.bind(i, 1))

	if end_turn_button:
		end_turn_button.text = Locale.t("battle.end_turn")
		end_turn_button.pressed.connect(_on_end_turn_pressed)
	if status_toggle_button:
		status_toggle_button.pressed.connect(_on_status_toggle_pressed)

	if discard_zone and discard_zone.has_signal("card_discarded"):
		discard_zone.card_discarded.connect(_on_card_discarded)
	if EventBus.has_signal("hp_changed"):
		EventBus.hp_changed.connect(_on_hp_changed)

	_refresh_hand_ui()
	_apply_responsive_layout()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	update_entire_screen()
	if NetworkManager.is_online:
		if NetworkManager.just_reconnected:
			_local_slot_rejoined = true
			match_paused = true
			update_entire_screen()
			call_deferred("_request_resume_state")
		elif not NetworkManager.is_authority():
			NetworkManager.rpc_request_initial_state.rpc()


func _on_game_draw_cards(amount: int):
	var drawn = game.draw_cards(amount)
	for card_data in drawn:
		var card_ui = card_ui_scene.instantiate()
		_active_hand_container().add_child(card_ui)
		card_ui.set_card(card_data)
		_scale_control(card_ui, BASE_CARD_SIZE)


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


# ============================================
# Floating text
# ============================================

func _on_hp_changed(target: CardData, delta: int, _new_hp: int):
	if delta == 0:
		return
	# Authority records the change (as player+slot) so it can be replayed as
	# floating text on the non-authority client, which never runs combat logic
	# and therefore never emits hp_changed itself.
	if NetworkManager.is_online and NetworkManager.is_authority():
		var loc := _locate_card_player_slot(target)
		if loc.slot >= 0:
			_pending_hp_events.append({"player": loc.player, "slot": loc.slot, "delta": delta})
	var pos: Vector2 = _find_card_slot_pos(target)
	if pos == Vector2.ZERO:
		return
	_spawn_floating_text(pos, delta)


# Creates the rising +/- damage/heal label at a screen position.
func _spawn_floating_text(pos: Vector2, delta: int) -> void:
	if delta == 0:
		return
	var is_damage: bool = delta < 0
	var lbl := Label.new()
	lbl.text = ("-%d" % -delta) if is_damage else ("+%d" % delta)
	lbl.add_theme_color_override("font_color", Color.RED if is_damage else Color.GREEN)
	lbl.add_theme_font_size_override("font_size", 33)
	lbl.position = pos + Vector2(20 + randi() % 40, -5 - randi() % 25)
	lbl.scale = Vector2(0.8, 0.8)
	$CanvasLayer.add_child(lbl)
	var twn := create_tween()
	twn.set_parallel(true)
	twn.tween_property(lbl, "position:y", lbl.position.y - 50, 0.8)
	twn.tween_property(lbl, "scale", Vector2(1.5, 1.5), 0.8)
	twn.tween_property(lbl, "modulate:a", 0.0, 0.8).set_delay(0.3)
	twn.chain().tween_callback(lbl.queue_free)


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
	if slot < 0 or slot > 4:
		return
	var slots_ui: Array = _my_slots_ui() if player == _view_player() else _their_slots_ui()
	if slot >= slots_ui.size():
		return
	_spawn_floating_text(slots_ui[slot].global_position, delta)


func _find_card_slot_pos(card: CardData) -> Vector2:
	var p_slots = player_side_ui.get_children()
	var e_slots = enemy_side_ui.get_children()
	for i in range(5):
		if _my_field().slots[i] == card:
			return p_slots[i].global_position
		if _their_field().slots[i] == card:
			return e_slots[i].global_position
	return Vector2.ZERO


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
		_show_toast("tip.discard_mana")
		_refresh_hand_ui()
		update_entire_screen()


func _skill_needs_targeting(skill: Dictionary) -> bool:
	var effects: Array = skill.get("effects", [])
	if effects.is_empty() and not skill.get("target", "").is_empty():
		effects = [{"target": skill.get("target", ""), "effect": skill.get("effect", "")}]
	for eff in effects:
		var ef: String = eff.get("effect", "")
		if ef == SkillEngine.EFFECT_DRAW_CARDS:
			continue
		var t: String = eff.get("target", "")
		if t == SkillEngine.TARGET_SINGLE or t == SkillEngine.TARGET_SIDES:
			return true
	return false

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

func _on_card_drag_summoned(card_data: CardData, origin_ui: Control, slot_index: int):
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
		if origin_ui and is_instance_valid(origin_ui):
			origin_ui.queue_free()
		update_entire_screen()
		return

	var hand_index := _my_hand().find(card_data)
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
	if card.is_silenced():
		return
	var skill: Dictionary = card.skills[skill_index]
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
		if game.turn_number <= 1:
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
		if is_summon:
			game.trigger_summon_skills(slot_index, -1, skill_index)
		else:
			game.trigger_activate_skills(slot_index, -1, skill_index)
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
	if field.slots[slot_index].is_silenced():
		return
	current_attacker_idx = slot_index
	if attack_arrow:
		attack_arrow.visible = true
	_sync_targeting_state()


func _on_player_slot_clicked(index: int):
	if not is_my_turn(): return
	if current_attacker_idx != -1:
		cancel_attack()
	update_entire_screen()


func _on_enemy_slot_clicked(enemy_index: int):
	if not is_my_turn(): return
	if summon_targeting or activate_targeting or current_attacker_idx != -1:
		_on_opponent_slot_clicked(enemy_index)
	else:
		update_entire_screen()


func _on_opponent_slot_clicked(index: int):
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
		game.trigger_summon_skills(summon_source_slot, index, summon_skill_idx)
		_refresh_hand_ui()
		_check_charm_overflow()
		var summon_card: CardData = _my_field().slots[summon_source_slot]
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
		game.trigger_activate_skills(activate_source_slot, index, activate_skill_idx)
		_refresh_hand_ui()
		_check_charm_overflow()
		var card: CardData = _my_field().slots[activate_source_slot]
		_show_splash(card)
		activate_targeting = false
		activate_source_slot = -1
		last_hovered_target = -1
		if attack_arrow:
			attack_arrow.visible = false
		_apply_deaths()
		_check_charm_overflow()
		update_entire_screen()
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
	game.execute_attack(current_attacker_idx, index)
	var card: CardData = _my_field().slots[current_attacker_idx]
	if victim != null and not victim.is_alive():
		_show_toast("tip.kill_mana")
	_show_splash(card)
	_apply_deaths()
	_check_charm_overflow()
	update_entire_screen()
	cancel_attack()


func cancel_attack():
	if NetworkManager.is_online and (current_attacker_idx != -1 or summon_targeting or activate_targeting):
		NetworkManager.rpc_targeting_arrow.rpc(-1, -1, game.current_player)
	current_attacker_idx = -1
	summon_targeting = false
	activate_targeting = false
	last_hovered_target = -1
	if attack_arrow:
		attack_arrow.visible = false


# ============================================
# Turn
# ============================================

func _on_end_turn_pressed():
	if not game.is_player_turn or not is_my_turn():
		return
	if NetworkManager.is_online:
		if NetworkManager.is_authority():
			await _host_apply_end_turn(game.current_player)
		else:
			NetworkManager.rpc_intent_end_turn.rpc(game.current_player)
		return
	var result = game.end_player_turn()
	_show_direct_damage(result)
	end_turn_button.disabled = true
	update_entire_screen()
	var game_over: String = game.check_game_over()
	if game_over != "":
		_show_result(game_over)
		return
	await get_tree().create_timer(0.5).timeout
	game.start_new_turn()
	_refresh_hand_ui()
	end_turn_button.disabled = false
	update_entire_screen()


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
	var attacking_player: int = result["attacking_player"]
	var cards_hit: Array = result["cards_hit"]

	for hit in cards_hit:
		var slot_idx: int = hit["slot"]
		var dmg: int = hit["dmg"]
		var slots = _my_slots_ui() if attacking_player == _view_player() else _their_slots_ui()
		var slot_ui = slots[slot_idx]
		var pos = slot_ui.global_position + slot_ui.size / 2 + Vector2(0, -20)
		var lbl := Label.new()
		lbl.text = "-%d" % dmg
		lbl.add_theme_color_override("font_color", Color.ORANGE)
		lbl.add_theme_font_size_override("font_size", 28)
		lbl.position = pos
		lbl.scale = Vector2(0.8, 0.8)
		$CanvasLayer.add_child(lbl)
		var twn := create_tween()
		twn.set_parallel(true)
		twn.tween_property(lbl, "position:y", lbl.position.y - 40, 0.7)
		twn.tween_property(lbl, "scale", Vector2(1.2, 1.2), 0.7)
		twn.tween_property(lbl, "modulate:a", 0.0, 0.7).set_delay(0.2)
		twn.chain().tween_callback(lbl.queue_free)

	await get_tree().create_timer(0.3).timeout
	var tlbl := Label.new()
	tlbl.text = "-%d" % total
	tlbl.add_theme_color_override("font_color", Color.RED)
	tlbl.add_theme_font_size_override("font_size", 48)
	tlbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var vp_size = get_viewport().get_visible_rect().size
	tlbl.position = Vector2(vp_size.x / 2 - 60, vp_size.y / 2 - 80)
	tlbl.scale = Vector2(0.5, 0.5)
	$CanvasLayer.add_child(tlbl)
	var twn2 := create_tween()
	twn2.set_parallel(true)
	twn2.tween_property(tlbl, "position:y", tlbl.position.y - 30, 0.8)
	twn2.tween_property(tlbl, "scale", Vector2(2.0, 2.0), 0.8)
	twn2.tween_property(tlbl, "modulate:a", 0.0, 0.8).set_delay(0.4)
	twn2.chain().tween_callback(tlbl.queue_free)


func _apply_deaths():
	var dead = game.cleanup_deaths()
	var p_slots = player_side_ui.get_children()
	var e_slots = enemy_side_ui.get_children()
	for idx in dead.get("p1", []):
		(p_slots if _view_player() == 1 else e_slots)[idx].set_card(null)
	for idx in dead.get("p2", []):
		(e_slots if _view_player() == 1 else p_slots)[idx].set_card(null)


func _refresh_hand_ui():
	for child in hand_container.get_children():
		child.queue_free()
	for card_data in _my_hand():
		var card_ui = card_ui_scene.instantiate()
		hand_container.add_child(card_ui)
		card_ui.set_card(card_data)
		_scale_control(card_ui, BASE_CARD_SIZE)
	_update_pile_labels()


func _show_result(result: String):
	NetworkManager.clear_room_session()
	if mana_label:
		mana_label.text = "[ %s ]" % result
	if end_turn_button:
		end_turn_button.disabled = true


# ============================================
# UI refresh
# ============================================

func update_entire_screen():
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
				view_text, f.current_mana, f.max_mana,
				f.player_hp, hand_size, 6, game.turn_number
			])
		else:
			mana_label.text = Locale.t("battle.switching")
	if status_toggle_button:
		status_toggle_button.visible = NetworkManager.is_online
		status_toggle_button.text = Locale.t("battle.enemy_info") if not show_enemy_status else Locale.t("battle.my_info")
	if end_turn_button:
		end_turn_button.disabled = match_paused or not game.is_player_turn or (NetworkManager.is_online and game.current_player != my_player)

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
var match_paused: bool = false
var _resume_waiting_for_player: int = 0
var _resume_expected_revision: int = -1
var _local_slot_rejoined: bool = false

func is_my_turn() -> bool:
	if match_paused:
		return false
	if not NetworkManager.is_online:
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
	EventBus.rpc_resume_state_requested.connect(_on_rpc_resume_state_requested)
	EventBus.rpc_resume_state_received.connect(_on_rpc_resume_state_received)
	EventBus.rpc_resume_state_ack_received.connect(_on_rpc_resume_state_ack)
	EventBus.rpc_resume_complete_received.connect(_on_rpc_resume_complete)
	NetworkManager.opponent_disconnected.connect(_on_opponent_disconnected)
	NetworkManager.reconnect_started.connect(_on_reconnect_started)
	NetworkManager.reconnect_transport_ready.connect(_on_reconnect_transport_ready)
	NetworkManager.reconnect_failed.connect(_on_reconnect_failed)


func _pause_for_reconnect() -> void:
	match_paused = true
	_resume_waiting_for_player = 0
	_resume_expected_revision = -1
	cancel_attack()
	remote_arrow_source = -1
	remote_arrow_target = -1
	if end_turn_button:
		end_turn_button.disabled = true
	update_entire_screen()


func _on_opponent_disconnected(_player: int) -> void:
	_pause_for_reconnect()


func _on_reconnect_started() -> void:
	_pause_for_reconnect()


func _on_reconnect_transport_ready() -> void:
	my_player = NetworkManager.player_number
	_local_slot_rejoined = true
	_pause_for_reconnect()
	call_deferred("_request_resume_state")


func _on_reconnect_failed(_reason: String) -> void:
	NetworkManager.clear_room_session()
	get_tree().change_scene_to_file.call_deferred("res://MainMenu.tscn")


func _request_resume_state() -> void:
	if not NetworkManager.is_online or my_player not in [1, 2]:
		return
	match_paused = true
	NetworkManager.rpc_request_resume_state.rpc(my_player, game.state_revision)
	update_entire_screen()


func _on_rpc_resume_state_requested(requesting_player: int, known_revision: int) -> void:
	if not NetworkManager.is_online or requesting_player == my_player:
		return
	# Normally only one side rejoined, so the continuously-online side is always
	# the recovery source. If both transports dropped together, both sides are
	# marked as rejoined and the higher committed revision wins deterministically.
	if _local_slot_rejoined and game.state_revision < known_revision:
		return
	_pause_for_reconnect()
	_resume_waiting_for_player = requesting_player
	_resume_expected_revision = game.state_revision
	NetworkManager.rpc_resume_state.rpc(game.export_initial_state(), my_player, requesting_player)


func _on_rpc_resume_state_received(state: Dictionary, source_player: int, target_player: int) -> void:
	if target_player != my_player or source_player == my_player:
		return
	match_paused = true
	_apply_authority_state(state, "reconnect recovery")
	_resume_expected_revision = game.state_revision
	NetworkManager.rpc_resume_state_ack.rpc(my_player, game.state_revision)


func _on_rpc_resume_state_ack(player: int, revision: int) -> void:
	if player != _resume_waiting_for_player or revision != _resume_expected_revision:
		return
	_resume_waiting_for_player = 0
	_resume_expected_revision = -1
	_finish_resume()
	NetworkManager.rpc_resume_complete.rpc(revision)


func _on_rpc_resume_complete(revision: int) -> void:
	if revision != game.state_revision:
		return
	_finish_resume()


func _finish_resume() -> void:
	match_paused = false
	_local_slot_rejoined = false
	NetworkManager.just_reconnected = false
	NetworkManager.opponent_peer_id = -1
	if end_turn_button:
		end_turn_button.disabled = not game.is_player_turn or not is_my_turn()
	update_entire_screen()


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
	var incoming_revision := int(state.get("state_revision", 0))
	if incoming_revision < game.state_revision:
		return
	_apply_authority_state(state, "remote authority")


func _host_apply_summon(hand_index: int, slot_index: int, player: int) -> void:
	if match_paused or not NetworkManager.is_authority() or player != game.current_player:
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
	_commit_authority_state("summon")


func _host_apply_summon_skill(slot_index: int, skill_index: int, target_slot: int, player: int) -> void:
	if match_paused or not NetworkManager.is_authority() or player != game.current_player:
		return
	var saved = game.current_player
	game.current_player = player
	var card: CardData = game.active_field().slots[slot_index]
	if card != null and not card.skills_used.has(skill_index):
		card.skills_used.append(skill_index)
	game.trigger_summon_skills(slot_index, target_slot, skill_index)
	game.current_player = saved
	_authority_splash(player, slot_index)
	_apply_deaths()
	_check_charm_overflow()
	_refresh_hand_ui()
	update_entire_screen()
	_commit_authority_state("summon skill")


func _host_apply_attack(source_slot: int, target_slot: int, player: int) -> void:
	if match_paused or not NetworkManager.is_authority() or player != game.current_player:
		return
	var saved = game.current_player
	game.current_player = player
	var result: Dictionary = game.execute_attack(source_slot, target_slot)
	game.current_player = saved
	if not result.is_empty():
		_authority_splash(player, source_slot)
	_apply_deaths()
	_check_charm_overflow()
	_refresh_hand_ui()
	update_entire_screen()
	_commit_authority_state("attack")


func _host_apply_skill(slot_index: int, skill_index: int, target_slot: int, player: int) -> void:
	if match_paused or not NetworkManager.is_authority() or player != game.current_player:
		return
	var saved = game.current_player
	game.current_player = player
	var card: CardData = game.active_field().slots[slot_index]
	if card != null and not card.skills_used.has(skill_index):
		card.skills_used.append(skill_index)
	game.trigger_activate_skills(slot_index, target_slot, skill_index)
	game.current_player = saved
	_authority_splash(player, slot_index)
	_apply_deaths()
	_check_charm_overflow()
	_refresh_hand_ui()
	update_entire_screen()
	_commit_authority_state("activate skill")


func _host_apply_discard(location: String, index: int, player: int) -> void:
	if match_paused or not NetworkManager.is_authority() or player != game.current_player:
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
	_commit_authority_state("discard")


func _host_apply_move(source_slot: int, target_slot: int, player: int) -> void:
	if match_paused or not NetworkManager.is_authority() or player != game.current_player:
		return
	var field = _field_for_player(player)
	if source_slot < 0 or source_slot >= field.slots.size() or target_slot < 0 or target_slot >= field.slots.size():
		return
	var displaced = field.slots[target_slot]
	field.slots[target_slot] = field.slots[source_slot]
	field.slots[source_slot] = displaced
	update_entire_screen()
	_commit_authority_state("move")


func _host_apply_end_turn(player: int) -> void:
	if match_paused or not NetworkManager.is_authority() or player != game.current_player:
		return
	remote_arrow_source = -1
	var result = game.end_player_turn()
	_show_direct_damage(result)
	end_turn_button.disabled = true
	update_entire_screen()
	var game_over: String = game.check_game_over()
	if game_over != "":
		_show_result(game_over)
		_commit_authority_state("game over")
		return
	game.start_new_turn()
	_refresh_hand_ui()
	end_turn_button.disabled = false
	update_entire_screen()
	_commit_authority_state("end turn")


func _on_rpc_intent_summon(hand_index: int, slot_index: int, player: int):
	_host_apply_summon(hand_index, slot_index, player)


func _on_rpc_intent_summon_skill(slot_index: int, skill_index: int, target_slot: int, player: int):
	_host_apply_summon_skill(slot_index, skill_index, target_slot, player)


func _on_rpc_intent_attack(source_slot: int, target_slot: int, player: int):
	_host_apply_attack(source_slot, target_slot, player)


func _on_rpc_intent_skill(slot_index: int, skill_index: int, target_slot: int, player: int):
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
	var overlay = ColorRect.new()
	overlay.name = "TurnOverlay"
	overlay.visible = false
	overlay.color = Color(0, 0, 0, 0.3)
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$CanvasLayer.add_child(overlay)

	turn_cover = Panel.new()
	turn_cover.visible = false
	turn_cover.anchor_right = 1.0
	turn_cover.anchor_bottom = 1.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.12, 0.14, 1.0)
	turn_cover.add_theme_stylebox_override("panel", bg)
	turn_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lbl = Label.new()
	lbl.text = Locale.t("battle.waiting")
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.anchor_right = 1.0
	lbl.anchor_bottom = 1.0
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	turn_cover.add_child(lbl)
	$CanvasLayer/MainBackground/MainLayout/HandArea.add_child(turn_cover)


func _toggle_turn_cover():
	var overlay = $CanvasLayer.get_node_or_null("TurnOverlay")
	if not turn_cover and not overlay: return
	var show = (NetworkManager.is_online or match_paused) and not is_my_turn()
	if turn_cover:
		turn_cover.visible = show
		if turn_cover.get_child_count() > 0 and turn_cover.get_child(0) is Label:
			turn_cover.get_child(0).text = Locale.t("battle.reconnecting") if match_paused else Locale.t("battle.waiting")
	if overlay: overlay.visible = show


# ============================================
# Draw/Discard pile UI
# ============================================

func _build_pile_buttons():
	# Create draw pile button in bottom-left area
	draw_pile_btn = Button.new()
	draw_pile_btn.text = Locale.t("battle.draw_pile")
	draw_pile_btn.custom_minimum_size = Vector2(120, 50)
	draw_pile_btn.position = Vector2(20, 600)
	draw_pile_btn.pressed.connect(_on_draw_pile_clicked)
	$CanvasLayer.add_child(draw_pile_btn)

	# Create discard pile button next to it
	discard_pile_btn = Button.new()
	discard_pile_btn.text = Locale.t("battle.discard_pile")
	discard_pile_btn.custom_minimum_size = Vector2(120, 50)
	discard_pile_btn.position = Vector2(150, 600)
	discard_pile_btn.pressed.connect(_on_discard_pile_clicked)
	$CanvasLayer.add_child(discard_pile_btn)

	debug_state_btn = Button.new()
	debug_state_btn.text = Locale.t("battle.debug_state")
	debug_state_btn.custom_minimum_size = Vector2(130, 50)
	debug_state_btn.position = Vector2(280, 600)
	debug_state_btn.pressed.connect(_on_debug_state_clicked)
	$CanvasLayer.add_child(debug_state_btn)

	help_btn = Button.new()
	help_btn.text = Locale.t("help.button")
	help_btn.custom_minimum_size = Vector2(90, 50)
	help_btn.position = Vector2(420, 600)
	help_btn.pressed.connect(_on_help_clicked)
	$CanvasLayer.add_child(help_btn)

	_update_pile_labels()


func _on_debug_state_clicked():
	_print_authority_state("button")
	if NetworkManager.is_online and NetworkManager.is_authority():
		NetworkManager.rpc_authority_state.rpc(game.export_initial_state())


func _on_help_clicked():
	_show_help_popup()


# Static rules manual — blur overlay + scrollable mechanics text.
func _show_help_popup():
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
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.14, 1.0)
	style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", style)
	panel.anchor_left = 0.15
	panel.anchor_right = 0.85
	panel.anchor_top = 0.1
	panel.anchor_bottom = 0.9
	popup_layer.add_child(panel)

	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = Locale.t("help.title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_FILL
	vbox.add_child(scroll)

	var body := Label.new()
	body.text = Locale.t("help.body", [SkillEngine.MAX_HAND_SIZE])
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	body.add_theme_font_size_override("font_size", 17)
	body.add_theme_color_override("font_color", Color(0.85, 0.85, 0.88))
	scroll.add_child(body)

	var close_btn := Button.new()
	close_btn.text = Locale.t("help.close")
	close_btn.custom_minimum_size = Vector2(100, 40)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
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
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.14, 1.0)
	style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", style)
	panel.anchor_left = 0.1
	panel.anchor_right = 0.9
	panel.anchor_top = 0.1
	panel.anchor_bottom = 0.9
	popup_layer.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	panel.add_child(vbox)

	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_FILL
	vbox.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 4
	scroll.add_child(grid)

	for c in cards:
		var cui := card_ui_scene.instantiate()
		grid.add_child(cui)
		cui.set_card(c)
		cui.set_actions_visible(false)

	var close_btn := Button.new()
	close_btn.text = Locale.t("battle.close")
	close_btn.custom_minimum_size = Vector2(100, 40)
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
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.14, 1.0)
	style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", style)
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
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	vbox.add_child(title)

	var info := Label.new()
	info.text = Locale.t("battle.hand_remaining", [max_picks, max_picks])
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 16)
	info.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
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
