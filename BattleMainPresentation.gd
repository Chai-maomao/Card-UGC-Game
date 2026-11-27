extends "res://presentation/BattleFeedbackTimeline.gd"


# The presentation layer is the sole owner of the battle log implementation.
const ACTION_LOG_MAX := 60
const TARGETING_ARROW_REFRESH_MS := 250
const DamagePreviewAmount = preload("res://presentation/DamagePreviewAmount.gd")
var _action_log_entries: Array = []
var _action_log_latest: Button
var _action_log_close: Button
var _action_log_waiting := false

func _end_turn_preview_text() -> String:
	var plan: Dictionary = game.preview_end_turn_attacks(face_mana_button.button_pressed)
	var lines: Array[String] = [Locale.t("battle.end_preview_title")]
	if plan.reason == "first_turn":
		lines.append(Locale.t("battle.end_preview_first"))
	elif plan.reason == "defended":
		lines.append(Locale.t("battle.end_preview_defended"))
	else:
		if game.battle_config.has("action_base"):
			lines.append(Locale.t("battle.end_preview_total", [plan.total_damage, plan.points, plan.mana]))
		else:
			lines.append(("自动攻击对方玩家，共造成 %d 点伤害。" if Locale.language == "zh" else "Your units will attack the opposing player for %d damage.") % plan.total_damage)
		for hit in plan.cards_hit:
			if game.battle_config.has("action_base"):
				lines.append(Locale.t("battle.end_preview_hit", [int(hit.slot) + 1, str(hit.card_name).left(24), hit.dmg, hit.points, hit.mana]))
			else:
				lines.append(("%s：伤害 %d" if Locale.language == "zh" else "%s: %d damage") % [str(hit.card_name).left(24), hit.dmg])
		if not plan.blocked.is_empty():
			lines.append(Locale.t("battle.end_preview_blocked", [plan.blocked.size()]))
	lines.append(Locale.t("battle.end_preview_temp"))
	if plan.conditional:
		lines.append(Locale.t("battle.end_preview_conditional"))
	return "\n".join(lines)


var _pending_hand_arrivals: Array = []
var _hand_arrival_sort_connected := false
var _discard_pile_feedback_tween: Tween = null
var _discard_pile_feedback_target: Control = null
var _discard_pile_rest_modulate := Color.WHITE
var _discard_pile_rest_scale := Vector2.ONE
@onready var combat_broadcast_panel: Label = $CanvasLayer/MainBackground/MainLayout/MiddleInfoBar/InfoHBox/CombatBroadcastStrip
@onready var combat_broadcast_label: Label = combat_broadcast_panel
var _action_log_unread := 0
var _combat_broadcast_kind := "system"

const FEED_KIND_COLOR := {
	"attack": UITheme.Tokens.ENEMY,
	"skill": UITheme.Tokens.TEAL,
	"cast": UITheme.Tokens.TEAL,
	"summon_skill": UITheme.Tokens.TEAL,
	"warn": UITheme.Tokens.WARNING,
	"system": UITheme.Tokens.PRIMARY_HOVER,
}

# ============================================
# Helpers
# ============================================

# The latest action lives in the centre information bar, between both lanes.
# Full wording remains in the log, while the persistent one-line summary never
# covers an enemy card or disappears before the player has read it.
func _show_combat_broadcast(text: String, kind: String = "system", recovered_turn: int = -1) -> void:
	if text.strip_edges().is_empty():
		return
	if kind == "parasite" and recovered_turn < 0: AppAudio.play("summon")
	_append_action_log(text, kind, recovered_turn)
	if not is_instance_valid(combat_broadcast_panel):
		return
	_combat_broadcast_kind = kind
	combat_broadcast_panel.text = BattleLogFormatter.summary(text.strip_edges().replace("\n", " "))
	combat_broadcast_panel.tooltip_text = text.strip_edges()
	_refresh_combat_broadcast_color()
	if turn_wait_hint != null and not battle_finished:
		_toggle_turn_cover()


func _refresh_combat_broadcast_color() -> void:
	var tint: Color = FEED_KIND_COLOR.get(_combat_broadcast_kind, FEED_KIND_COLOR["system"])
	combat_broadcast_panel.add_theme_color_override("font_color", tint.darkened(0.45) if UITheme.Tokens.light_mode else tint.lightened(0.28))


func _build_action_log() -> void:
	action_log_button = Button.new()
	action_log_button.text = Locale.t("battle.action_log")
	UITheme.apply_button(action_log_button, "secondary")
	$CanvasLayer.add_child(action_log_button)

	# Keep the one-line summary and waiting hint in control of their own visibility.
	combat_broadcast_panel.set_meta("keyword_literal", true)
	UITheme.apply_label(combat_broadcast_panel, true)
	combat_broadcast_panel.autowrap_mode = TextServer.AUTOWRAP_OFF
	combat_broadcast_panel.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	combat_broadcast_panel.max_lines_visible = 1
	combat_broadcast_panel.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed: _toggle_action_log())
	var broadcast_style := UITheme.panel_style(
		UITheme.COLOR_PANEL_DARK, UITheme.Tokens.BORDER, 1, 8, Color.TRANSPARENT, 0
	)
	broadcast_style.content_margin_top = 2
	broadcast_style.content_margin_bottom = 2
	combat_broadcast_panel.add_theme_stylebox_override("normal", broadcast_style)
	action_log_panel = PanelContainer.new()
	action_log_panel.name = "ActionLogPanel"
	action_log_panel.visible = false
	action_log_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	UITheme.apply_popup_frame(action_log_panel, "dark", false, true)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	action_log_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	box.add_child(header)
	var title := Label.new()
	title.text = Locale.t("battle.action_log_hint")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_title(title, 16)
	header.add_child(title)
	if PlayerData.is_card_playtest_active():
		var inspector := PlaytestInspector.new()
		add_child(inspector)
		inspector.setup(self, header)
	if not _active_challenge_id.is_empty():
		_challenge_controller = ChallengeController.new()
		add_child(_challenge_controller)
		_challenge_controller.setup(self, header, _active_challenge_id)
	var clear_btn := Button.new()
	clear_btn.text = Locale.t("battle.clear_log")
	clear_btn.custom_minimum_size = Vector2(64, 26)
	UITheme.apply_button(clear_btn, "utility")
	clear_btn.add_theme_font_size_override("font_size",12)
	clear_btn.pressed.connect(_clear_action_log)
	header.add_child(clear_btn)
	_action_log_close = Button.new()
	_action_log_close.text = Locale.t("common.close")
	_action_log_close.custom_minimum_size = Vector2(56, 26)
	UITheme.apply_button(_action_log_close, "secondary")
	_action_log_close.add_theme_font_size_override("font_size",12)
	_action_log_close.pressed.connect(_close_action_log)
	header.add_child(_action_log_close)
	action_log_text = RichTextLabel.new()
	action_log_text.bbcode_enabled = true
	action_log_text.fit_content = false
	action_log_text.scroll_active = true
	action_log_text.selection_enabled = true
	action_log_text.context_menu_enabled = true
	action_log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	action_log_text.add_theme_font_size_override("normal_font_size", 14)
	action_log_text.add_theme_font_size_override("bold_font_size", 14)
	action_log_text.add_theme_font_override("normal_font", UITheme.regular_font())
	action_log_text.add_theme_font_override("bold_font", UITheme.medium_font())
	action_log_text.add_theme_color_override("default_color", UITheme.COLOR_TEXT)
	action_log_text.add_theme_constant_override("line_separation", 4)
	action_log_text.gui_input.connect(_on_action_log_body_input)
	box.add_child(action_log_text)
	_action_log_latest = Button.new()
	_action_log_latest.name = "LatestLogEntries"
	_action_log_latest.hide()
	UITheme.apply_button(_action_log_latest, "utility")
	_action_log_latest.pressed.connect(_show_latest_action_log)
	box.add_child(_action_log_latest)
	var exporter := preload("res://BattlePositionExporter.gd").new()
	add_child(exporter)
	exporter.setup(self, box)
	var dismiss_area := ColorRect.new()
	dismiss_area.name = "ActionLogDismissArea"
	dismiss_area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dismiss_area.color = Color(0, 0, 0, 0.20)
	dismiss_area.z_index = 80
	dismiss_area.hide()
	dismiss_area.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_close_action_log()
			dismiss_area.accept_event())
	$CanvasLayer.add_child(dismiss_area)
	action_log_panel.z_index = 81
	action_log_panel.visibility_changed.connect(func(): dismiss_area.visible = action_log_panel.visible)
	$CanvasLayer.add_child(action_log_panel)
	action_log_button.pressed.connect(_toggle_action_log)


func _toggle_action_log() -> void:
	action_log_panel.visible = not action_log_panel.visible
	if action_log_panel.visible:
		UIMotion.register_popup(action_log_panel, _action_log_close)
		_show_latest_action_log()


func _show_latest_action_log() -> void:
	_action_log_unread = 0
	_action_log_waiting = false
	if _action_log_latest.has_focus():
		_action_log_close.grab_focus()
	_action_log_latest.hide()
	_refresh_action_log_text()


func _on_action_log_body_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.keycode != KEY_HOME or event.get_modifiers_mask() != 0:
		return
	if _action_log_waiting:
		_show_latest_action_log()
	else:
		action_log_text.scroll_to_line(0)
	action_log_text.accept_event()


func _close_action_log() -> void:
	action_log_panel.visible = false


func _clear_action_log() -> void:
	_action_log_entries.clear()
	_show_latest_action_log()


func _append_action_log(text: String, kind: String, recovered_turn: int) -> void:
	if action_log_text == null:
		return
	var turn := recovered_turn if recovered_turn > 0 else (int(game.turn_number) if game != null else 1)
	_action_log_entries.push_front({"turn": turn, "kind": kind, "text": text.strip_edges()})
	if _action_log_entries.size() > ACTION_LOG_MAX:
		_action_log_entries.resize(ACTION_LOG_MAX)
	var reading_older := action_log_panel.visible and (_action_log_waiting or action_log_text.get_v_scroll_bar().value > 2 or not action_log_text.get_selected_text().is_empty())
	if not action_log_panel.visible or reading_older:
		_action_log_unread += 1
	if reading_older:
		_action_log_waiting = true
		_action_log_latest.text = Locale.t("battle.log.view_latest", [_action_log_unread])
		_action_log_latest.show()
		_refresh_action_log_button()
		return
	_refresh_action_log_text()


func _refresh_action_log_text() -> void:
	if action_log_text == null:
		return
	var parts: Array[String] = []
	var previous_turn := -1
	for entry in _action_log_entries:
		var turn := int(entry.get("turn", 1))
		if turn != previous_turn:
			var turn_color := UITheme.Tokens.BRASS if UITheme.Tokens.light_mode else Color("c9a965")
			parts.append("[b][color=#%s]%s[/color][/b]" % [turn_color.to_html(false), Locale.t("battle.log.turn_header", [turn])])
			previous_turn = turn
		var kind := str(entry.get("kind", "system"))
		var color: Color = FEED_KIND_COLOR.get(kind, FEED_KIND_COLOR["system"])
		# Escape opening brackets once; escaping the inserted closing brackets
		# again corrupts literal UGC names such as [color=red]...[/color].
		var body := preload("res://presentation/SkillDescription.gd").colored(str(entry.get("text", "")),14,false)
		var separator := "; " if Locale.language == "en" else "；"
		var lines := body.split(separator)
		var heading := str(lines[0])
		var details := ""
		for index in range(1, lines.size()):
			details += "\n" + str(lines[index]).strip_edges()
		var heading_color := color.darkened(0.45) if UITheme.Tokens.light_mode else color.lightened(0.42)
		parts.append("[b][color=#%s]%s[/color][/b]%s" % [heading_color.to_html(false), heading, details])
	action_log_text.clear()
	action_log_text.append_text("\n".join(parts))
	action_log_text.scroll_to_line(0)
	_refresh_action_log_button()


func _refresh_action_log_button() -> void:
	if action_log_button == null:
		return
	action_log_button.text = Locale.t("battle.action_log")
	var dot := action_log_button.get_node_or_null("UnreadDot") as Control
	if dot == null:
		dot = preload("res://presentation/UnreadLogDot.gd").new()
		dot.name = "UnreadDot"
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		action_log_button.add_child(dot)
		dot.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		dot.offset_left = -13
		dot.offset_right = -5
		dot.offset_top = 5
		dot.offset_bottom = 13
	dot.visible = _action_log_unread > 0

var _hero_damage_running: Dictionary = {}
var _hero_hp_shown: Dictionary = {}
var _hero_resources_shown: Dictionary = {}

func _show_direct_damage(result: Dictionary):
	if _defer_random_feedback(_show_direct_damage.bind(result.duplicate(true))): return
	if not result.get("triggered",false) or int(result.get("total_damage",0)) <= 0: return
	_record_feedback_event("hero_damage",int(result.get("attacking_player",game.current_player)),-1,{"result":result})
	var damaged_player := int(result.get("damaged_player",3-game.current_player))
	var attacking_player := int(result.get("attacking_player",game.current_player))
	if result.get("resources_before") is Dictionary:
		_hero_resources_shown[attacking_player] = result.resources_before.duplicate()
	var target_hud: Panel = player_status_hud if damaged_player == _view_player() else enemy_status_hud
	var hud_state: Dictionary = _status_hud_state.get(target_hud.get_instance_id(), {})
	var hp_bar_before: ProgressBar = target_hud.get_node("Margin/Content/HpBar")
	_hero_hp_shown[damaged_player] = int(hud_state.get("hp", hp_bar_before.value))
	_hero_damage_running[damaged_player] = int(_hero_damage_running.get(damaged_player,0))+1
	var last_impact: Tween
	for hit in result.get("cards_hit",[]):
		var slot := _slot_ui_for_player(attacking_player,int(hit.get("slot",-1)))
		if slot == null: continue
		var hud: Panel = player_status_hud if damaged_player == _view_player() else enemy_status_hud
		var hp_bar: ProgressBar = hud.get_node("Margin/Content/HpBar")
		var start := slot.get_global_rect().get_center()
		var target := hp_bar.get_global_rect().get_center()
		if hit.get("resources_after") is Dictionary:
			_hero_resources_shown[attacking_player] = hit.resources_after.duplicate()
		_update_battle_status_huds()
		_play_hero_attack_feedback(attacking_player,int(hit.slot))
		var trail := Line2D.new()
		trail.name = "HeroStrikeTrail"
		trail.set_meta("battle_fx_kind","hero_strike")
		trail.width = 2.5*_ui_scale()
		trail.default_color = UITheme.COLOR_GOLD
		trail.z_index = 35
		$CanvasLayer.add_child(trail)
		var tween := trail.create_tween()
		tween.tween_method(func(t: float):
			trail.points = PackedVector2Array([start.lerp(target,maxf(0,t-0.18)),start.lerp(target,t)])
		,0.0,1.0,0.22*GamePreferences.battle_animation_duration_scale()).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		await tween.finished
		if not is_instance_valid(hp_bar):
			trail.queue_free()
			_hero_damage_running[damaged_player] = maxi(0,int(_hero_damage_running.get(damaged_player,1))-1)
			_hero_hp_shown.erase(damaged_player)
			_hero_resources_shown.erase(attacking_player)
			return
		last_impact = BattleFx.status_bar_feedback($CanvasLayer,hp_bar,-int(hit.dmg),"damage",_ui_scale())
		AppAudio.play("heavy" if int(hit.dmg) >= 4 else "hurt")
		_hero_hp_shown[damaged_player] = maxi(0, int(_hero_hp_shown[damaged_player]) - maxi(0, int(hit.dmg)))
		_update_battle_status_huds()
		trail.queue_free()
		await get_tree().create_timer(0.07*GamePreferences.battle_animation_duration_scale()).timeout
	if last_impact != null and last_impact.is_running():
		await last_impact.finished
	_hero_damage_running[damaged_player] = maxi(0,int(_hero_damage_running.get(damaged_player,1))-1)
	_hero_hp_shown.erase(damaged_player)
	_hero_resources_shown.erase(attacking_player)


func _wait_for_direct_damage() -> void:
	await _wait_for_random_feedback()
	while _hero_damage_running.values().any(func(count): return int(count) > 0):
		await get_tree().process_frame


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
	if not _playing_random_action and (_random_feedback_pending>0 or not _random_unbatched_events.is_empty()) and slot_ui != null:
		var center := slot_ui.get_global_rect().get_center()
		_defer_random_feedback(_play_random_death_feedback.bind(center,_hold_pile_addition(1)))
		return
	AppAudio.play("death")
	if slot_ui == null:
		return
	var card_ui = slot_ui.get("current_card_ui")
	if card_ui == null or not is_instance_valid(card_ui):
		slot_ui.set_card(null)
		return
	BattleFx.death_fade(
		$CanvasLayer,
		card_ui,
		_ui_scale(),
		_discard_fly_target(),
		Callable(self, "_play_death_discard_feedback").bind(_hold_pile_addition(1))
	)
	slot_ui.set_card(null)


func _play_random_death_feedback(center: Vector2,token: int) -> void:
	var origin := Control.new()
	origin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	origin.position = center
	$CanvasLayer.add_child(origin)
	AppAudio.play("death")
	BattleFx.death_fade($CanvasLayer,origin,_ui_scale(),_discard_fly_target(),Callable(self,"_play_death_discard_feedback").bind(token))
	origin.queue_free()


func _play_death_discard_feedback(token: int = -1) -> void:
	_finish_pile_addition(token)
	_play_discard_pile_arrival(UITheme.Tokens.ENEMY)


# Incremental hand refresh: hand mutations preserve order (plays remove a
# card, draws append), so existing card nodes are matched by card reference
# and reused. Only genuinely new cards are instantiated, replaying the entry
# tween for them alone — the old full rebuild re-instantiated the whole hand
# and replayed every entry animation after each action, causing visible
# flicker and frame spikes.
func _refresh_hand_ui():
	var hand: Array = _deployment_preview()["hand"]
	var children: Array = hand_container.get_children()
	# Fast path: identical card sequence — only castability tint can drift.
	if children.size() == hand.size():
		var identical := true
		for i in range(hand.size()):
			if children[i].get("current_card_data") != hand[i]:
				identical = false
				break
		if identical:
			for i in range(hand.size()):
				children[i].refresh_cost_display()
				_apply_hand_castability(children[i], hand[i])
			_update_pile_labels()
			return
	# Order-preserving match: for each hand entry, find the first not-yet-used
	# node whose card instance is identical.
	var reuse: Array = []
	var matched := {}
	for i in range(hand.size()):
		var node = null
		for j in range(children.size()):
			if matched.has(j):
				continue
			if children[j].get("current_card_data") == hand[i]:
				node = children[j]
				matched[j] = true
				break
		reuse.append(node)
	# Drop unmatched nodes (played/left the hand).
	for j in range(children.size()):
		if not matched.has(j):
			# A touch release can still be routed to the drag source after the
			# drop callback. Retire it from the hand layout while keeping it in
			# the tree until Godot finishes dispatching the current input.
			children[j].hide()
			children[j].reparent(self, false)
			children[j].queue_free()
	for i in range(hand.size()):
		var card_data: CardData = hand[i]
		var card_ui = reuse[i]
		if card_ui == null:
			card_ui = card_ui_scene.instantiate()
			hand_container.add_child(card_ui)
			card_ui.set_card(card_data)
			_scale_control(card_ui, BASE_CARD_SIZE)
			card_ui.is_hand_card = true
			_connect_hand_card_signals(card_ui)
			_prepare_hand_entry_ui(card_ui, card_data)
		else:
			# Reused node: refresh texts only (cost/charm state may have
			# changed in place); skip entry feedback to avoid flicker.
			card_ui.set_card(card_data)
			_apply_hand_castability(card_ui, card_data)
		# Effects triggered by a discard can draw, copy, or otherwise rearrange
		# the hand before this refresh. Reused controls keep their old sibling
		# index unless moved explicitly, so make the authoritative hand array the
		# sole ordering source after every mutation.
		hand_container.move_child(card_ui, i)
	_update_pile_labels()


# Challenge retries replace CardData objects wholesale. Force the hand view to
# discard every cached node so no dragged, modified, or removed card face can
# survive into the restored puzzle state.
func reset_hand_ui_from_game_state() -> void:
	_pile_arrivals.clear()
	if hand_container == null:
		return
	for child in hand_container.get_children():
		hand_container.remove_child(child)
		child.queue_free()
	_pending_hand_entry_ids.clear()
	_deferred_hand_arrival_refs.clear()
	_pending_hand_arrivals.clear()
	if hand_container.sort_children.is_connected(_flush_pending_hand_arrivals):
		hand_container.sort_children.disconnect(_flush_pending_hand_arrivals)
	_hand_arrival_sort_connected = false
	_refresh_hand_ui()


# Only an actual discount is green. Ordinary affordable cards stay white and
# unaffordable cards are red; this keeps "green" semantically unambiguous.
func _apply_hand_castability(card_ui, card_data: CardData) -> void:
	if card_data == null:
		return
	var affordable: bool = _field_for_player(_view_player()).get_total_mana() >= card_data.cost
	var color := UITheme.Tokens.CARD_DISCOUNT if card_data.is_cost_reduced() \
		else (UITheme.Tokens.INK if affordable else UITheme.Tokens.CARD_DANGER)
	# Re-applying the same theme override marks the label dirty every refresh;
	# skip when the cached tint still matches (CardUI invalidates on set_card).
	if color.is_equal_approx(card_ui.get("_last_cost_color")):
		return
	card_ui.set("_last_cost_color", color)
	var cost_label = card_ui.get("cost_label")
	if cost_label:
		cost_label.add_theme_color_override("font_color", color)


# Signals are bound to the node itself (not a hand index) so hand nodes can be
# reused across incremental refreshes without re-connecting.
func _connect_hand_card_signals(card_ui) -> void:
	card_ui.skill1_requested.connect(_on_hand_card_skill_activated.bind(card_ui, SpellRules.CAST_SKILL_INDEX))


func _hand_index_of(card_ui) -> int:
	if hand_container == null or card_ui == null or not is_instance_valid(card_ui):
		return -1
	return hand_container.get_children().find(card_ui)


func _play_hand_card_enter_feedback(card_ui: Control) -> void:
	_finish_hand_arrival(card_ui)
	BattleFx.hand_card_enter($CanvasLayer, card_ui, _ui_scale())


func _finish_hand_arrival(card_ui: Control) -> void:
	if card_ui.get_meta("tabletop_arriving", false):
		card_ui.set_meta("tabletop_arriving", false)
		card_ui.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_INHERITED
		card_ui.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED


func _prepare_hand_entry_ui(card_ui: Control, card_data: CardData) -> void:
	var entry_key := _hand_entry_key(card_data)
	if card_data != null and _pending_hand_entry_ids.has(entry_key):
		var pending = _pending_hand_entry_ids.get(entry_key, {})
		_pending_hand_entry_ids.erase(entry_key)
		card_ui.modulate.a = 0.0
		card_ui.set_meta("tabletop_arriving", true)
		card_ui.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
		card_ui.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
		if pending is Dictionary and bool(pending.get("deferred", false)):
			_deferred_hand_arrival_refs[entry_key] = weakref(card_ui)
			return
		var reveal_delay := 0.50
		if pending is Dictionary:
			reveal_delay = float(pending.get("reveal_delay", reveal_delay))
		get_tree().create_timer(reveal_delay + _deployment_feedback_delay()).timeout.connect(_reveal_arriving_hand_card.bind(weakref(card_ui)))
		if pending is Dictionary and pending.has("feedback"):
			_pending_hand_arrivals.append({
				"reference": weakref(card_ui),
				"card": card_data,
				"feedback": pending["feedback"],
			})
			if not _hand_arrival_sort_connected:
				_hand_arrival_sort_connected = true
				hand_container.sort_children.connect(_flush_pending_hand_arrivals, CONNECT_ONE_SHOT)
			hand_container.queue_sort()
		return
	_play_hand_card_enter_feedback(card_ui)


func _reveal_arriving_hand_card(reference: WeakRef) -> void:
	var card_ui: Control = reference.get_ref()
	if card_ui != null and is_instance_valid(card_ui):
		_play_hand_card_enter_feedback(card_ui)


func _start_arriving_hand_card(reference: WeakRef, card: CardData, feedback: Dictionary) -> void:
	var card_ui: Control = reference.get_ref()
	if card_ui == null or not is_instance_valid(card_ui):
		return
	_play_hand_resolution_feedback(
		card,
		int(feedback.get("player", _view_player())),
		"hand",
		str(feedback.get("source", "generated")),
		feedback.get("source_meta", {}),
		card_ui.global_position + card_ui.size * 0.5
	)


func _flush_pending_hand_arrivals() -> void:
	_hand_arrival_sort_connected = false
	var arrivals := _pending_hand_arrivals.duplicate()
	_pending_hand_arrivals.clear()
	for arrival: Dictionary in arrivals:
		_start_arriving_hand_card(arrival["reference"], arrival["card"], arrival["feedback"])


func _on_hand_entry_resolved(card: CardData, player: int, destination: String, source: String, source_meta: Dictionary) -> void:
	source_meta = source_meta.duplicate(true)
	_reserve_hand_pile_arrivals(source_meta,destination,source)
	var batch_index := maxi(0, int(source_meta.get("batch_index", 0)))
	var network_meta := source_meta.duplicate(true)
	# Screen coordinates are local to one client's layout/viewpoint. The remote
	# peer reconstructs a correct source from player + slot instead.
	network_meta.erase("source_position")
	var entry_event := {
		"kind": "hand_entry",
		"player": player,
		"slot": -1,
		"destination": destination,
		"source": source,
		"source_meta": network_meta,
		"instance_id": card.instance_id,
		"entry_key": _hand_entry_key(card),
		"card_name": card.card_name,
	}
	if not _action_broadcast.is_empty():
		entry_event["feedback_group"] = int(_action_feedback_group_stack.back()) if not _action_feedback_group_stack.is_empty() else 0
		_action_presentation_events.append(entry_event)
		if destination == "hand" and player == _view_player():
			_pending_hand_entry_ids[_hand_entry_key(card)] = {"deferred": true}
		return
	if not _random_unbatched_events.is_empty():
		_random_unbatched_events.append(entry_event)
		if destination=="hand" and player==_view_player(): _pending_hand_entry_ids[_hand_entry_key(card)]={"deferred":true}
		return
	if destination == "hand" and player == _view_player():
		var reveal_delay := (BattleFx.draw_card_arrival_delay(batch_index) + BattleFx.reshuffle_arrival_delay(int(source_meta.get("reshuffle_count", 0)))) if source == "deck" else BattleFx.travel_card_arrival_delay(batch_index)
		_pending_hand_entry_ids[_hand_entry_key(card)] = {
			"reveal_delay": reveal_delay,
			"feedback": {
				"player": player,
				"source": source,
				"source_meta": source_meta.duplicate(true),
			},
		}
	else:
		_play_hand_resolution_feedback(card, player, destination, source, source_meta)
	if destination == "discard":
		_spawn_toast(Locale.t("tip.hand_overflow", [card.card_name]), "warn", 2.0)
	_record_feedback_event("hand_entry", player, -1, {
		"destination": destination,
		"source": source,
		"source_meta": network_meta,
		"instance_id": card.instance_id,
		"card_name": card.card_name,
	})


func _play_staged_hand_entry(event: Dictionary) -> void:
	var player := int(event.get("player", 0))
	var destination := str(event.get("destination", ""))
	var source := str(event.get("source", "generated"))
	var source_meta: Dictionary = event.get("source_meta", {}).duplicate(true)
	var card := _find_feedback_card(str(event.get("instance_id", "")))
	var entry_key := str(event.get("entry_key", event.get("instance_id", "")))
	if destination == "hand" and player == _view_player():
		var batch_index := maxi(0, int(source_meta.get("batch_index", 0)))
		var delay := (BattleFx.draw_card_arrival_delay(batch_index) + BattleFx.reshuffle_arrival_delay(int(source_meta.get("reshuffle_count", 0)))) if source == "deck" else BattleFx.travel_card_arrival_delay(batch_index)
		var reference: WeakRef = _deferred_hand_arrival_refs.get(entry_key)
		var card_ui: Control = reference.get_ref() if reference != null else null
		_deferred_hand_arrival_refs.erase(entry_key)
		if card_ui != null and is_instance_valid(card_ui):
			_play_hand_resolution_feedback(card, player, destination, source, source_meta, card_ui.global_position + card_ui.size * 0.5)
			get_tree().create_timer(delay + _deployment_feedback_delay()).timeout.connect(_reveal_arriving_hand_card.bind(weakref(card_ui)))
			return
		if _pending_hand_entry_ids.has(entry_key):
			# The timeline can run before the next hand refresh (for example,
			# when the AI returns a damaged card to the local hand).
			_pending_hand_entry_ids[entry_key] = {
				"reveal_delay": delay,
				"feedback": {"player": player, "source": source, "source_meta": source_meta},
			}
			return
	_play_hand_resolution_feedback(card, player, destination, source, source_meta)
	if destination == "discard":
		_spawn_toast(Locale.t("tip.hand_overflow", [str(event.get("card_name", Locale.t("battle.card")))]), "warn", 2.0)


# Replays one action as contiguous causal stages. Consecutive events from the
# same effect share a frame; returning from a nested trigger starts a new stage.
func _hand_entry_key(card: CardData) -> String:
	if card == null:
		return ""
	if not card.instance_id.is_empty():
		return card.instance_id
	# Hand-authored tests and transient generated cards can exist before a
	# persistent instance id is assigned. Object identity keeps their pending
	# arrival timing independent within the same local draw batch.
	return "runtime:%d" % card.get_instance_id()


func _play_hand_resolution_feedback(card: CardData, player: int, destination: String, source: String, source_meta: Dictionary, target_override: Vector2 = Vector2.INF) -> void:
	if _defer_deployment_feedback(_play_hand_resolution_feedback.bind(card, player, destination, source, source_meta, target_override)): return
	var reshuffle_count := int(source_meta.get("reshuffle_count", 0)) if source == "deck" else 0
	if reshuffle_count > 0:
		if int(source_meta.get("batch_index", 0)) == 0:
			AppAudio.play("shuffle")
			var token := int(source_meta.get("reshuffle_arrival_token",-1))
			var remaining: Vector2i = _pile_arrivals.get(token,Vector2i.ZERO)
			BattleFx.spawn_reshuffle_cards($CanvasLayer, _discard_fly_target(), _hand_resolution_source_position(player, "deck", {}), reshuffle_count, _ui_scale(), _on_reshuffle_icon_arrival.bind(token,remaining.x))
		var after_shuffle := source_meta.duplicate(true)
		after_shuffle.erase("reshuffle_count")
		get_tree().create_timer(BattleFx.reshuffle_arrival_delay(reshuffle_count)).timeout.connect(
			_play_hand_resolution_feedback.bind(card, player, destination, source, after_shuffle, target_override))
		return
	var start := _hand_resolution_source_position(player, source, source_meta)
	var target := target_override if target_override != Vector2.INF else (_hand_card_target(card, player) if destination == "hand" else _discard_fly_target())
	var batch_index := maxi(0, int(source_meta.get("batch_index", 0)))
	if batch_index == 0:
		var single_draw := source == "deck" and destination == "hand" and int(source_meta.get("batch_size", 1)) == 1
		AppAudio.play("draw_single" if single_draw else "draw")
	if destination == "discard":
		var ghost := BattleFx.make_transfer_icon(_ui_scale())
		var hand_edge := _draw_fly_target_for_player(player) + Vector2(0,-60*_ui_scale())
		hand_edge.y = clampf(hand_edge.y,80,get_viewport_rect().size.y-90*_ui_scale())
		BattleFx.overflow_card_control($CanvasLayer,ghost,start,hand_edge,target,batch_index,_ui_scale())
	elif source == "deck":
		BattleFx.spawn_draw_fly_card($CanvasLayer,start,target,batch_index,_ui_scale())
	else:
		BattleFx.travel_card_control($CanvasLayer,BattleFx.make_transfer_icon(_ui_scale()),start,target,batch_index,_ui_scale())
	if destination == "discard":
		get_tree().create_timer(BattleFx.overflow_card_arrival_delay(batch_index)).timeout.connect(_play_overflow_discard_feedback.bind(int(source_meta.get("discard_arrival_token",-1))))


func _hand_card_target(card: CardData, player: int) -> Vector2:
	if player == _view_player() and card != null:
		for child in hand_container.get_children():
			if child.get("current_card_data") == card:
				return child.global_position + child.size * 0.5
	return _draw_fly_target_for_player(player)


func _play_overflow_discard_feedback(token: int = -1) -> void:
	_finish_pile_addition(token)
	_play_discard_pile_arrival(UITheme.Tokens.WARNING)


func _on_reshuffle_icon_arrival(index: int, icon_count: int, token: int, total: int) -> void:
	var amount := floori(float(total)*(index+1)/icon_count)-floori(float(total)*index/icon_count)
	_finish_pile_addition(token,amount)


func _play_discard_pile_arrival(tint: Color) -> void:
	var target: Control = discard_pile_btn if discard_pile_btn != null else discard_zone
	if target == null or not is_instance_valid(target):
		return
	# Several cards can arrive before the previous pulse finishes. Restart from
	# one stable rest state so a tinted intermediate frame never becomes the
	# next pulse's baseline and leaves the pile permanently red/orange.
	if _discard_pile_feedback_target != target:
		_discard_pile_feedback_target = target
		_discard_pile_rest_modulate = target.modulate
		_discard_pile_rest_scale = target.scale
	if _discard_pile_feedback_tween != null and _discard_pile_feedback_tween.is_valid():
		_discard_pile_feedback_tween.kill()
	target.modulate = _discard_pile_rest_modulate
	target.scale = _discard_pile_rest_scale
	var duration_scale := GamePreferences.battle_animation_duration_scale()
	_discard_pile_feedback_tween = create_tween().set_parallel(true)
	_discard_pile_feedback_tween.tween_property(target, "modulate", tint, 0.08 * duration_scale)
	_discard_pile_feedback_tween.tween_property(target, "scale", _discard_pile_rest_scale * 1.04, 0.08 * duration_scale)
	_discard_pile_feedback_tween.tween_property(target, "modulate", _discard_pile_rest_modulate, 0.18 * duration_scale).set_delay(0.08 * duration_scale)
	_discard_pile_feedback_tween.tween_property(target, "scale", _discard_pile_rest_scale, 0.18 * duration_scale).set_delay(0.08 * duration_scale)
	_discard_pile_feedback_tween.chain().tween_callback(_finish_discard_pile_arrival.bind(target))


func _finish_discard_pile_arrival(target: Control) -> void:
	if target != null and is_instance_valid(target) and target == _discard_pile_feedback_target:
		target.modulate = _discard_pile_rest_modulate
		target.scale = _discard_pile_rest_scale
	_discard_pile_feedback_tween = null


func _set_ghost_mouse_filter(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_set_ghost_mouse_filter(child)


func _hand_resolution_source_position(player: int, source: String, source_meta: Dictionary) -> Vector2:
	var exact = source_meta.get("source_position", null)
	if exact is Vector2 and exact != Vector2.ZERO:
		return exact
	if source == "deck" and draw_pile_btn != null:
		return draw_pile_btn.global_position + draw_pile_btn.size / 2
	if source == "discard" and discard_pile_btn != null:
		return discard_pile_btn.global_position + discard_pile_btn.size / 2
	if source == "field":
		var source_player: int = int(source_meta.get("source_player", player))
		var source_slot: int = int(source_meta.get("source_slot", -1))
		var slot_ui := _slot_ui_for_player(source_player, source_slot)
		if slot_ui != null:
			return slot_ui.global_position + slot_ui.size / 2
	if source == "hand" and player == _view_player():
		var source_id := str(source_meta.get("source_instance_id", ""))
		for index in range(_my_hand().size()):
			var hand_card: CardData = _my_hand()[index]
			if hand_card.instance_id == source_id and index < hand_container.get_child_count():
				var card_ui: Control = hand_container.get_child(index)
				return card_ui.global_position + card_ui.size / 2
	return _draw_fly_target_for_player(player)


func _discard_fly_target() -> Vector2:
	var target: Control = discard_pile_btn if discard_pile_btn != null else discard_zone
	if target != null:
		return target.global_position + target.size / 2
	return get_viewport_rect().size * Vector2(0.9, 0.8)


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
	if index == 0: AppAudio.play("draw")
	BattleFx.spawn_draw_fly_card($CanvasLayer, start, target, index, _ui_scale())


func _play_discard_feedback(start: Vector2 = Vector2.INF, token: int = -1) -> void:
	var target: Control = discard_pile_btn if discard_pile_btn != null else discard_zone
	if target == null or not is_instance_valid(target):
		return
	var center: Vector2 = target.global_position + target.size / 2
	var origin := start if start != Vector2.INF else get_global_mouse_position()
	if token < 0: token = _hold_pile_addition(1)
	BattleFx.absorb_discard_card($CanvasLayer,origin,center,_ui_scale(),_on_manual_discard_arrival.bind(token))
	_update_pile_labels()


func _on_manual_discard_arrival(token: int) -> void:
	_finish_pile_addition(token)
	AppAudio.play("discard")
	_play_discard_pile_arrival(UITheme.Tokens.PAPER)


func _check_and_show_game_over() -> bool:
	var result: String = game.check_game_over()
	if result == "":
		return false
	_show_result(result)
	return true


func _show_result(result: String):
	if battle_finished or _result_waiting_for_feedback:
		return
	if PlayerData.is_online_battle():
		NetworkManager.mark_lan_match_finished()
	var losing_hud: Control = enemy_status_hud if _did_local_player_win(result) else player_status_hud
	var hp_bar := losing_hud.get_node("Margin/Content/HpBar") as ProgressBar
	if _has_result_feedback_pending() or _result_hp_animating(hp_bar):
		_result_waiting_for_feedback = true
		update_entire_screen()
		while is_inside_tree() and not battle_finished and (_has_result_feedback_pending() or _result_hp_animating(hp_bar)):
			await get_tree().process_frame
		_result_waiting_for_feedback = false
		if not is_inside_tree() or battle_finished:
			return
	battle_finished = true
	AppAudio.play("victory" if _did_local_player_win(result) else "defeat")
	practice_ai_running = false
	cancel_attack()
	if not _is_party_battle() and not NetworkManager.has_live_server_room() and not NetworkManager.can_return_to_lan_room() and not PlayerData.is_card_playtest_active():
		NetworkManager.clear_room_session()
	if _end_turn_pulse and _end_turn_pulse.is_valid():
		_end_turn_pulse.kill()
		_end_turn_pulse = null
	if end_turn_button:
		end_turn_button.scale = Vector2.ONE
	if turn_label:
		turn_label.text = "[ %s ]" % _result_title(result)
	if end_turn_button:
		end_turn_button.disabled = true
	_show_battle_result_page(result)


func _has_result_feedback_pending() -> bool:
	return (not _plain_feedback_batches.is_empty() or _hp_feedback_running or not _hp_feedback_batches.is_empty()
		or _random_feedback_pending > 0 or not _random_unbatched_events.is_empty()
		or (splash_tween != null and splash_tween.is_running())
		or _hero_damage_running.values().any(func(count): return int(count) > 0))


func _result_hp_animating(hp_bar: ProgressBar) -> bool:
	var tween: Tween = _status_value_tweens.get(hp_bar.get_instance_id())
	return tween != null and tween.is_running() and is_zero_approx(float(hp_bar.get_meta("status_animation_target", -1)))

func _prepare_finished_battle_result() -> void:
	if not battle_finished:
		return
	for popup in get_tree().get_nodes_in_group("battle_modal"):
		if is_ancestor_of(popup):
			popup.hide()
			popup.queue_free()
	if is_instance_valid(action_log_panel):
		_close_action_log()
	if is_instance_valid(turn_wait_hint):
		turn_wait_hint.hide()
	if is_instance_valid(turn_cover):
		turn_cover.hide()
	get_viewport().gui_cancel_drag()
	# Battle presentations such as the discard picker have their own canvas.
	$CanvasLayer.layer = 100


func _show_disconnect_result_page(resume_sync_failed: bool = false) -> void:
	_prepare_finished_battle_result()
	var old_layer := $CanvasLayer.get_node_or_null("BattleResultLayer")
	if old_layer:
		old_layer.queue_free()
	var layer := Control.new()
	layer.name = "BattleResultLayer"
	layer.z_index = 100
	_disconnect_overlay = null if resume_sync_failed else layer
	layer.anchor_right = 1.0
	layer.anchor_bottom = 1.0
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	$CanvasLayer.add_child(layer)
	$CanvasLayer.move_child(layer, $CanvasLayer.get_child_count() - 1)

	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(UITheme.Tokens.PANEL_DARK,0.86)
	layer.add_child(bg)

	var center := CenterContainer.new()
	center.anchor_right = 0.68
	center.anchor_bottom = 1.0
	layer.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(540, 240) * _ui_scale()
	UITheme.apply_popup_frame(panel, "dark", false)
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
	title.name = "TitleLabel"
	if resume_sync_failed:
		title.text = Locale.t("result.resume_failed_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	UITheme.apply_title(title, 36)
	box.add_child(title)

	var body := Label.new()
	body.name = "BodyLabel"
	if resume_sync_failed:
		body.text = Locale.t("result.resume_failed_body")
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.apply_label(body, true)
	body.add_theme_font_size_override("font_size", 18)
	box.add_child(body)

	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	box.add_child(actions)

	if resume_sync_failed:
		var retry_btn := Button.new()
		retry_btn.text = Locale.t("result.retry_resume")
		retry_btn.custom_minimum_size.y = 42
		UITheme.apply_selection_entry(retry_btn)
		retry_btn.add_theme_font_size_override("font_size", 20 + 2 * int(AppPreferences.get_value("text_size")))
		retry_btn.pressed.connect(_on_resume_retry_pressed)
		actions.add_child(retry_btn)

	var multiplayer_btn := Button.new()
	multiplayer_btn.custom_minimum_size.y = 42
	UITheme.apply_selection_entry(multiplayer_btn)
	multiplayer_btn.add_theme_font_size_override("font_size", 20 + 2 * int(AppPreferences.get_value("text_size")))
	multiplayer_btn.pressed.connect(_on_online_result_back_pressed)
	actions.add_child(multiplayer_btn)
	_online_result_back_btn = multiplayer_btn
	_refresh_online_result_destination()

	var menu_btn := Button.new()
	menu_btn.text = Locale.t("result.back_menu")
	menu_btn.custom_minimum_size.y = 42
	UITheme.apply_selection_entry(menu_btn)
	menu_btn.add_theme_font_size_override("font_size", 20 + 2 * int(AppPreferences.get_value("text_size")))
	menu_btn.pressed.connect(_on_result_back_menu_pressed.bind(menu_btn))
	actions.add_child(menu_btn)
	if not resume_sync_failed:
		layer.set_meta("popup_close", _on_online_result_back_pressed)
		UIMotion.register_popup(layer)

	UITheme.fade_enter(layer, 0.20)


func _refresh_online_result_destination() -> void:
	if not is_instance_valid(_online_result_back_btn):
		return
	var room_available := NetworkManager.has_live_server_room() or NetworkManager.can_return_to_lan_room()
	_online_result_back_btn.text = Locale.t("result.back_room" if room_available else "result.back_multiplayer")
	if not is_instance_valid(_disconnect_overlay):
		var result := $CanvasLayer.get_node_or_null("BattleResultLayer")
		var room_notice := result.find_child("RoomNotice", true, false) as Label if result else null
		if room_notice:
			if NetworkManager.is_dedicated_server:
				var notice_key := ""
				if not room_available:
					notice_key = "result.room_connection_lost_after_match"
				elif NetworkManager.room_wait_reason == "opponent_connection_lost":
					notice_key = "result.room_opponent_disconnected"
				elif NetworkManager.room_wait_reason == "opponent_left":
					notice_key = "result.lan_guest_left"
				room_notice.text = Locale.t(notice_key) if not notice_key.is_empty() else ""
			elif NetworkManager.has_vacant_lan_room_after_match():
				room_notice.text = Locale.t("result.lan_guest_left")
			elif NetworkManager.session_mode == NetworkManager.SESSION_MODE_LAN_CLIENT and not NetworkManager.is_online:
				room_notice.text = Locale.t("result.lan_guest_connection_lost")
			else:
				room_notice.text = ""
			room_notice.visible = not room_notice.text.is_empty()
		return
	var title := _disconnect_overlay.find_child("TitleLabel", true, false) as Label
	var body := _disconnect_overlay.find_child("BodyLabel", true, false) as Label
	if room_available:
		var opponent_lost_link := NetworkManager.room_wait_reason == "opponent_connection_lost"
		title.text = Locale.t("result.opponent_connection_lost_title" if opponent_lost_link else "result.opponent_left_title")
		body.text = Locale.t("result.opponent_left_body")
	else:
		title.text = Locale.t("result.connection_lost_title")
		body.text = Locale.t("result.room_connection_lost_body" if NetworkManager.is_dedicated_server else "result.connection_lost_body")


func _on_online_result_back_pressed() -> void:
	if NetworkManager.room_departure_pending:
		return
	if _return_to_server_room():
		return
	if NetworkManager.can_return_to_lan_room():
		PlayerData.return_to_waiting_room = true
		UIMotion.replace_scene("res://DirectLobby.tscn", true)
		return
	NetworkManager.close_connection()
	NetworkManager.clear_room_session()
	UIMotion.replace_scene("res://MainMenu.tscn", true, "online")


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
	if PlayerData.is_online_battle():
		return winner == my_player
	if PlayerData.battle_mode == "practice":
		return winner == 1
	return winner == _view_player()


func _result_title(result: String) -> String:
	var winner := _result_winner_player(result)
	if PlayerData.is_online_battle():
		return Locale.t("result.online_win") if _did_local_player_win(result) else Locale.t("result.online_loss")
	if PlayerData.battle_mode == "practice":
		return Locale.t("result.practice_win") if winner == 1 else Locale.t("result.practice_loss")
	if result == "p1_wins":
		return Locale.t("result.p1_wins")
	if result == "p2_wins":
		return Locale.t("result.p2_wins")
	return Locale.t("result.finished")


func _result_mode_text() -> String:
	if PlayerData.is_online_battle():
		return Locale.t("result.mode_online")
	if PlayerData.battle_mode == "practice":
		return Locale.t("result.mode_practice")
	return Locale.t("result.mode_hotseat")


func _result_summary_text() -> String:
	if PlayerData.is_online_battle() or PlayerData.battle_mode == "practice":
		return Locale.t("result.summary_personal", [game.turn_number, _my_field().player_hp, _their_field().player_hp])
	return Locale.t("result.summary", [game.turn_number, game.player_field.player_hp, game.player2_field.player_hp])


func _show_battle_result_page(result: String) -> void:
	_prepare_finished_battle_result()
	_record_match_history("victory" if _did_local_player_win(result) else ("finished" if not PlayerData.is_online_battle() and PlayerData.battle_mode != "practice" else "defeat"), result)
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
	bg.color = Color(UITheme.Tokens.PANEL_DARK, 0.88)
	layer.add_child(bg)

	var center := CenterContainer.new()
	center.anchor_right = 0.68
	center.anchor_bottom = 1.0
	layer.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 320) * _ui_scale()
	UITheme.apply_popup_frame(panel, "dark", false)
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
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	UITheme.apply_title(title, 42)
	box.add_child(title)

	var mode_label := Label.new()
	var mode_text := _result_mode_text()
	if not _is_party_battle() and PlayerData.battle_mode == "practice":
		mode_text = "%s（%s）" % [mode_text, Locale.t("menu.ai_%s" % PlayerData.practice_ai_difficulty)]
	mode_label.text = mode_text
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	UITheme.apply_label(mode_label, true)
	box.add_child(mode_label)

	var summary := Label.new()
	summary.text = _result_summary_text()
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.apply_label(summary)
	summary.add_theme_font_size_override("font_size", 18)
	box.add_child(summary)

	if PlayerData.is_online_battle():
		var room_notice := Label.new()
		room_notice.name = "RoomNotice"
		room_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		room_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UITheme.apply_label(room_notice, true)
		room_notice.hide()
		box.add_child(room_notice)

	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	box.add_child(actions)

	if PlayerData.is_card_playtest_active():
		var edit_btn := Button.new()
		edit_btn.text = Locale.t("common.back") if PlayerData.card_playtest_context.has("exit_scene") else Locale.t("result.back_editor")
		edit_btn.custom_minimum_size.y = 42
		UITheme.apply_selection_entry(edit_btn)
		edit_btn.add_theme_font_size_override("font_size", 20 + 2 * int(AppPreferences.get_value("text_size")))
		edit_btn.pressed.connect(_on_result_back_editor_pressed)
		actions.add_child(edit_btn)

	var again_btn := Button.new()
	again_btn.custom_minimum_size.y = 42
	UITheme.apply_selection_entry(again_btn)
	again_btn.add_theme_font_size_override("font_size", 20 + 2 * int(AppPreferences.get_value("text_size")))
	actions.add_child(again_btn)
	if PlayerData.is_online_battle() or _is_party_battle():
		_online_result_back_btn = again_btn
		again_btn.pressed.connect(_on_online_result_back_pressed)
		_refresh_online_result_destination()
	else:
		again_btn.text = Locale.t("result.play_again")
		again_btn.pressed.connect(func(): UIMotion.replace_scene("res://Main.tscn", true))

	var menu_btn := Button.new()
	menu_btn.text = Locale.t("result.back_menu")
	menu_btn.custom_minimum_size.y = 42
	UITheme.apply_selection_entry(menu_btn)
	menu_btn.add_theme_font_size_override("font_size", 20 + 2 * int(AppPreferences.get_value("text_size")))
	menu_btn.pressed.connect(_on_result_back_menu_pressed.bind(menu_btn))
	actions.add_child(menu_btn)

	var back_action := _on_result_back_menu_pressed
	if PlayerData.is_online_battle():
		back_action = _on_online_result_back_pressed
	elif PlayerData.is_card_playtest_active():
		back_action = _on_result_back_editor_pressed
	layer.set_meta("popup_close", back_action)
	UIMotion.register_popup(layer)

	UITheme.fade_enter(layer, 0.20)
	# Leave the result and its choices as the focus of the settled table.
	if _did_local_player_win(result):
		BattleFx.screen_flash($CanvasLayer, UITheme.Tokens.WARNING, 0.12, 0.30)
	else:
		BattleFx.screen_flash($CanvasLayer, UITheme.Tokens.PRIMARY, 0.12, 0.30)


func _return_to_server_room() -> bool:
	if not NetworkManager.return_to_server_room():
		return false
	PlayerData.return_to_waiting_room = true
	UIMotion.replace_scene("res://DedicatedLobby.tscn", true)
	return true


func _on_result_back_editor_pressed() -> void:
	var destination := str(PlayerData.card_playtest_context.get("exit_scene","res://CardEditor.tscn"))
	if PlayerData.restore_after_card_playtest():
		UIMotion.replace_scene(destination,true)


func _on_result_back_menu_pressed(menu_button: Button = null) -> void:
	if NetworkManager.room_departure_pending:
		return
	var result := $CanvasLayer.get_node_or_null("BattleResultLayer")
	var show_departure := is_instance_valid(result) and is_instance_valid(menu_button) and NetworkManager.has_live_server_room()
	var room_button := _online_result_back_btn
	if show_departure:
		result.set_meta("popup_close_locked", true)
		menu_button.disabled = true
		menu_button.text = Locale.t("wait.leaving_room")
		if is_instance_valid(room_button):
			room_button.disabled = true
	var departed := await NetworkManager.leave_online_room()
	if not is_inside_tree():
		return
	if not departed:
		if show_departure and is_instance_valid(result) and is_instance_valid(menu_button):
			result.remove_meta("popup_close_locked")
			menu_button.disabled = false
			menu_button.text = Locale.t("result.back_menu")
			if is_instance_valid(room_button):
				room_button.disabled = false
			menu_button.grab_focus()
		return
	PlayerData.restore_after_card_playtest()
	UIMotion.replace_scene("res://MainMenu.tscn",true)


# ============================================
# UI refresh
# ============================================

func _update_status_hud(hud: Panel, field: BattleField, hand_size: int, enemy: bool, active: bool, player_number: int, preview_mana: int = -1) -> void:
	if hud == null or field == null:
		return
	var content := hud.get_node("Margin/Content") as HBoxContainer
	(content.get_node("SideLabel") as Label).text = Locale.t("battle.enemy") if enemy else Locale.t("battle.you")
	if not PlayerData.is_online_battle() and PlayerData.battle_mode == "hotseat":
		(content.get_node("SideLabel") as Label).text = Locale.t("battle.hotseat_player", [_opponent_player() if enemy else _view_player()])
	var random_resources: Dictionary = _random_resource_override.get(str(player_number),{})
	var shown_hp := int(random_resources.get("hp",_hero_hp_shown.get(player_number, field.player_hp)))
	if shown_hp == 0 and _confirmed_game != null:
		var confirmed_field: BattleField = _confirmed_game.player_field if player_number == 1 else _confirmed_game.player2_field
		shown_hp = confirmed_field.player_hp
	(content.get_node("HpLabel") as Label).text = Locale.t("battle.hp_value", [shown_hp, field.max_player_hp])
	var shown_mana := preview_mana if preview_mana >= 0 else field.get_total_mana()
	var resources: Dictionary = _hero_resources_shown.get(player_number,{})
	if not random_resources.is_empty(): resources = random_resources
	shown_mana = int(resources.get("mana",shown_mana))
	var shown_points := int(resources.get("points",field.action_points))
	(content.get_node("ManaLabel") as Label).text = Locale.t("battle.mana_value", [shown_mana, field.max_mana])
	var action_label := content.get_node("HandLabel") as Label
	action_label.text = Locale.t("battle.action_points", [shown_points, field.action_budget]) if game.battle_config.has("action_base") else Locale.t("battle.hand_count", [hand_size, SkillEngine.MAX_HAND_SIZE])
	action_label.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	action_label.tooltip_text = Locale.t("battle.hand_count", [hand_size, SkillEngine.MAX_HAND_SIZE]) + "\n" + Locale.t("battle.action_help")

	var hp_bar := content.get_node("HpBar") as ProgressBar
	hp_bar.max_value = max(1, field.max_player_hp)
	var mana_bar := content.get_node("ManaBar") as ProgressBar
	mana_bar.max_value = max(1, max(field.max_mana, shown_mana))
	var hp_value: int = clampi(shown_hp, 0, field.max_player_hp)
	var mana_value: int = maxi(0, shown_mana)
	# Predictions can update the displayed total, but only confirmed state
	# and staged authority playback should announce a gain.
	var feedback_mana := mana_value
	if _confirmed_game != null and not resources.has("mana"):
		var confirmed_field: BattleField = _confirmed_game.player_field if player_number == 1 else _confirmed_game.player2_field
		feedback_mana = maxi(0, confirmed_field.get_total_mana())
	var action_bar := content.get_node("ActionBar") as ProgressBar
	action_bar.visible = game.battle_config.has("action_base")
	action_bar.max_value = max(1, field.action_budget)
	action_bar.tooltip_text = action_label.text + "\n" + Locale.t("battle.action_help")
	var hud_key: int = hud.get_instance_id()
	var previous: Dictionary = _status_hud_state.get(hud_key, {})
	var same_player: bool = int(previous.get("player", -1)) == player_number
	var may_animate: bool = same_player and not _suppress_status_feedback_once
	var hp_delta: int = hp_value - int(previous.get("hp", hp_value)) if same_player else 0
	var mana_delta: int = feedback_mana - int(previous.get("feedback_mana", feedback_mana)) if same_player else 0
	_set_status_bar_value(hp_bar, hp_value, may_animate and not _hero_hp_shown.has(player_number))
	_set_status_bar_value(mana_bar, mana_value, may_animate)
	_set_status_bar_value(action_bar, shown_points, may_animate)
	if may_animate and hp_delta != 0 and int(_hero_damage_running.get(player_number,0)) == 0:
		if hp_delta > 0: AppAudio.play("heal")
		BattleFx.status_bar_feedback($CanvasLayer, hp_bar, hp_delta, "heal" if hp_delta > 0 else "damage", _ui_scale())
	if may_animate and mana_delta > 0:
		AppAudio.play("mana")
		BattleFx.status_bar_feedback($CanvasLayer, mana_bar, mana_delta, "mana", _ui_scale())
	_status_hud_state[hud_key] = {"player": player_number, "hp": hp_value, "feedback_mana": feedback_mana, "action": shown_points}
	_apply_status_hud_theme(hud, enemy, active)


func _set_status_bar_value(bar: ProgressBar, target_value: float, animate: bool, duration: float = 0.38) -> void:
	var key: int = bar.get_instance_id()
	var old_tween: Tween = _status_value_tweens.get(key)
	var should_animate: bool = animate and not bool(AppPreferences.get_value("reduced_motion"))
	if should_animate and old_tween != null and old_tween.is_valid() and old_tween.is_running() \
			and is_equal_approx(float(bar.get_meta("status_animation_target",bar.value)),target_value):
		return
	if old_tween != null and old_tween.is_valid():
		old_tween.kill()
	bar.scale = Vector2.ONE
	if not should_animate or is_equal_approx(bar.value,target_value):
		bar.value = target_value
		_status_value_tweens.erase(key)
		return
	bar.set_meta("status_animation_target",target_value)
	bar.pivot_offset = bar.size * 0.5
	var twn := create_tween().set_parallel(true)
	twn.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	twn.tween_property(bar, "value", target_value, duration)
	twn.tween_property(bar, "scale", Vector2(1.0, 1.16), 0.09)
	twn.tween_property(bar, "scale", Vector2.ONE, 0.22).set_delay(0.09).set_trans(Tween.TRANS_BACK)
	_status_value_tweens[key] = twn


func _refresh_end_turn_damage_preview() -> void:
	if game == null or not is_instance_valid(enemy_status_hud): return
	var content: HBoxContainer = enemy_status_hud.get_node("Margin/Content")
	var hp_bar: ProgressBar = content.get_node("HpBar")
	var active: bool = game.is_player_turn and game.current_player == _view_player() and not battle_finished \
		and not (_challenge_controller != null and _challenge_controller.finished)
	var damage := int(game.preview_end_turn_attacks(face_mana_button.button_pressed).total_damage) if active else 0
	preload("res://presentation/ResourceCostPreview.gd").update(hp_bar,damage,_their_field().player_hp,false,Color("f4cf61"))
	var overlay := hp_bar.get_node_or_null("ResourceCostPreview") as Control
	if damage<=0 or overlay==null: return
	var amount := overlay.get_node_or_null("DamageAmount") as DamagePreviewAmount
	if amount == null:
		amount = DamagePreviewAmount.new()
		amount.name = "DamageAmount"
		amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(amount)
	amount.update(damage, overlay, hp_bar, _ui_scale())


func _opponent_hand_count() -> int:
	return _hand_for_player(_opponent_player()).size()


func _update_battle_status_huds() -> void:
	if game == null:
		return
	var turn_active: bool = game.is_player_turn and not (_challenge_controller != null and _challenge_controller.finished)
	var my_turn_active: bool = turn_active and game.current_player == _view_player()
	var enemy_turn_active: bool = turn_active and not my_turn_active
	var preview := _deployment_preview()
	_update_status_hud(player_status_hud, _my_field(), preview["hand"].size(), false, my_turn_active, _view_player(), preview["mana"])
	_update_status_hud(enemy_status_hud, _their_field(), _opponent_hand_count(), true, enemy_turn_active, _opponent_player())
	_refresh_end_turn_damage_preview()
	_suppress_status_feedback_once = false


# Coalesces full-screen refreshes: dozens of action paths call this within the
# same frame (play card -> stats -> glows -> turn HUD). Running the whole
# rebuild once per frame (deferred, so it still reflects the final state) cuts
# per-action UI spikes that read as input lag.
func update_entire_screen():
	if battle_finished or _screen_refresh_queued:
		return
	_screen_refresh_queued = true
	_do_update_entire_screen.call_deferred()


func _do_update_entire_screen() -> void:
	_screen_refresh_queued = false
	_update_pile_labels()
	_sync_face_mana_toggle()
	if battle_finished:
		return
	if _web_playback_allows_input() and not is_resolution_locked() and is_instance_valid(_resolution_blocker):
		_resolution_blocker.hide()
	if turn_label:
		if _challenge_controller != null and _challenge_controller.finished:
			turn_label.text = Locale.t("battle.challenge_finished")
		elif _result_waiting_for_feedback:
			turn_label.text = Locale.t("battle.finishing_match")
		elif _enemy_swap_is_pending():
			turn_label.text = Locale.t("battle.swap_drag")
		elif not game.pending_cost_choices.is_empty() and game.pending_cost_choices.front().player != _view_player():
			turn_label.text = Locale.t("battle.waiting_card_choice")
		elif game.is_player_turn:
			var turn_owner := _turn_owner_text()
			turn_label.text = ("%s，%s" if Locale.language=="zh" else "%s: %s") % [Locale.t("battle.turn_label", [game.turn_number]), turn_owner]
		else:
			turn_label.text = Locale.t("battle.switching")
	_update_battle_status_huds()
	if end_turn_button:
		end_turn_button.disabled = _turn_ending or not _owns_current_turn()
		end_turn_button.tooltip_text = "" if _challenge_controller != null and _challenge_controller.finished else _end_turn_preview_text()

	var my_slots := _random_visible_slots(_view_player(),_visible_player_slots())
	var their_field = _their_field()
	var their_slots := _random_visible_slots(3-_view_player(),their_field.slots)
	var p_slots = player_side_ui.get_children()
	var e_slots = enemy_side_ui.get_children()

	for i in range(5):
		p_slots[i].set_card(my_slots[i])
		e_slots[i].set_card(their_slots[i])
	for slot_index in range(p_slots.size()):
		var card_ui = p_slots[slot_index].current_card_ui
		if card_ui == null: continue
		var interactive: bool = game.is_player_turn and is_my_turn() and game.current_player == _view_player()
		var ready: Dictionary = game.unit_action_readiness(slot_index)
		if card_ui.normal_atk_btn != null:
			card_ui.normal_atk_btn.disabled = not interactive or not ready.attack
			card_ui.normal_atk_btn.modulate = Color.WHITE
		for entry in [[card_ui.skill1_btn, 0], [card_ui.skill2_btn, 1], [card_ui.skill3_btn, 2]]:
			if entry[1] >= card_ui.current_card_data.skills.size(): continue
			if str(card_ui.current_card_data.skills[entry[1]].get("trigger", "")) != SkillEngine.TRIGGER_ON_ACTIVATE: continue
			if not interactive or not ready.skills.has(entry[1]):
				entry[0].disabled = true
				entry[0].modulate = Color.WHITE
				if not game.can_pay_action():
					entry[0].tooltip_text += "\n" + Locale.t("tip.insufficient_action")
				elif game.turn_number <= 1 and SkillRegistry.skill_changes_enemy_hp_or_presence(card_ui.current_card_data.skills[entry[1]]):
					entry[0].tooltip_text += "\n" + Locale.t("tip.no_enemy_hp_effect_turn1")
	_toggle_turn_cover()
	_update_action_glows()
	_update_ui_state_motion()
	_refresh_hand_castability()
	_apply_hp_presentation_overrides()
	if _random_board_override.is_empty() and _random_feedback_pending==0 and _random_unbatched_events.is_empty():
		_random_last_shown_board = _capture_random_board()


# Re-applies green/red cost tinting to every hand card so the affordance stays
# correct after mana changes (summons, casts, turn advances, ...).
func _refresh_hand_castability() -> void:
	if hand_container == null or game == null:
		return
	for card_ui in hand_container.get_children():
		var card_data = card_ui.get("current_card_data")
		if card_data != null:
			_apply_hand_castability(card_ui, card_data)


# Attention pulse on the end-turn button while the player can act, and a soft
# pop on the turn label whenever the active turn changes.
func _update_ui_state_motion() -> void:
	if end_turn_button != null:
		var want_pulse: bool = not battle_finished and end_turn_button.visible and not end_turn_button.disabled
		if want_pulse:
			if _end_turn_pulse == null or not _end_turn_pulse.is_valid():
				end_turn_button.pivot_offset = end_turn_button.size / 2
				_end_turn_pulse = create_tween().set_loops()
				_end_turn_pulse.tween_property(end_turn_button, "scale", Vector2(1.035, 1.035), 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
				_end_turn_pulse.tween_property(end_turn_button, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		else:
			if _end_turn_pulse and _end_turn_pulse.is_valid():
				_end_turn_pulse.kill()
				_end_turn_pulse = null
			end_turn_button.scale = Vector2.ONE
	if turn_label != null and turn_label.text != "" and turn_label.text != _turn_last_text:
		_turn_last_text = turn_label.text
		if _turn_pop_tween and _turn_pop_tween.is_valid():
			_turn_pop_tween.kill()
		turn_label.pivot_offset = Vector2(0, turn_label.size.y * 0.5)
		_turn_pop_tween = create_tween()
		_turn_pop_tween.tween_property(turn_label, "scale", Vector2(1.06, 1.06), 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_turn_pop_tween.tween_property(turn_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(_delta):
	_sync_face_mana_toggle()
	_process_resume_sync()
	if remote_arrow_source >= 0 and (not _can_show_remote_targeting() or Time.get_ticks_msec() >= _remote_arrow_expires_at):
		remote_arrow_source = -1
		remote_arrow_target = -1
	if is_my_turn():
		var source: int = -1
		var from_hand: bool = false
		if current_attacker_idx != -1:
			source = current_attacker_idx
		elif summon_targeting:
			source = summon_source_slot
		elif activate_targeting:
			source = activate_source_slot
		elif cast_targeting or parasite_targeting:
			# Spells / parasites cast from hand: the arrow originates at the hand.
			from_hand = true

		if source != -1 or from_hand:
			var start_pos: Vector2
			if from_hand:
				start_pos = hand_container.global_position + Vector2(hand_container.size.x * 0.5, hand_container.size.y * 0.35)
			else:
				var slot_ui = _my_slots_ui()[source]
				start_pos = slot_ui.global_position + slot_ui.size / 2
			var end_pos := _targeting_pointer_position()
			attack_arrow.points = [start_pos, end_pos]
			attack_arrow.visible = true

			var hovered := -1
			var hover_slots := _their_slots_ui()
			if _is_party_battle() and (summon_targeting or activate_targeting):
				hover_slots.append_array(_my_slots_ui())
			for i in hover_slots.size():
				var slot: Control = hover_slots[i]
				if slot.get_global_rect().has_point(end_pos):
					hovered = i
					break
			# Hand-cast aiming is private; only field-source arrows sync to the opponent.
			if not from_hand:
				var hovering_changed := hovered != last_hovered_target
				last_hovered_target = hovered
				if PlayerData.is_online_battle() or _is_party_battle():
					var now := Time.get_ticks_msec()
					if hovering_changed or (hovered >= 0 and now >= _next_targeting_refresh):
						_next_targeting_refresh = now + TARGETING_ARROW_REFRESH_MS
						_sync_targeting_state()
		else:
			attack_arrow.visible = false
			last_hovered_target = -1
	else:
		var points := _remote_targeting_points()
		attack_arrow.visible = not points.is_empty()
		if attack_arrow.visible:
			attack_arrow.points = points
	_update_slot_highlights()


func _targeting_pointer_position() -> Vector2:
	return get_global_mouse_position()


func _remote_targeting_points() -> PackedVector2Array:
	if remote_arrow_source < 0 or remote_arrow_target < 0:
		return PackedVector2Array()
	return _targeting_points(_their_slots_ui()[remote_arrow_source], _my_slots_ui()[remote_arrow_target])


func _targeting_points(source: Control, target: Control) -> PackedVector2Array:
	return PackedVector2Array([source.get_global_rect().get_center(), target.get_global_rect().get_center()])


func _can_show_remote_targeting() -> bool:
	return game.is_player_turn and game.current_player != _view_player() and not battle_finished \
		and not _result_waiting_for_feedback and not match_paused and not _waiting_for_room_link()
