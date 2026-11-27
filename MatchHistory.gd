extends Control

const UITheme = preload("res://UITheme.gd")
const BASE_VIEWPORT_SIZE := Vector2(1152, 648)
const CardFace = preload("res://presentation/ClassicBattleCardFace.gd")
const CARD_PREVIEW_SIZE := Vector2(92, 126.5)

var COLOR_WIN := UITheme.Tokens.SUCCESS
var COLOR_LOSS := UITheme.Tokens.WARNING
var COLOR_NEUTRAL := UITheme.Tokens.TITLE
const OUTCOMES := ["victory", "defeat", "finished", "forfeit", "interrupted"]
const STAT_KEYS := [
	"summons", "spells", "parasites", "cards_drawn",
	"card_damage", "hero_damage", "kills", "mana_spent",
]

var list_box: VBoxContainer
var empty_label: Label
var count_label: Label
var summary_box: HBoxContainer
var summary_averages: Label
var outcome_filter: OptionButton
var mode_filter: OptionButton
var _outcome_options: Array = []
var _mode_options: Array = []
var _page_margin: MarginContainer
var _root_box: VBoxContainer
var _header: HBoxContainer
var _history_controls: VBoxContainer
var _clear_button: Button
var _empty_history: CenterContainer
var _history_scroll: ScrollContainer


# ============================================
# 纯逻辑（便于无头测试）
# ============================================

# entries 按最新在前排列。
static func compute_summary(entries: Array) -> Dictionary:
	var summary := {
		"total": entries.size(),
		"wins": 0,
		"losses": 0,
		"scored_count": 0,
		"win_rate": 0,
		"streak_type": "none",
		"streak_count": 0,
		"avg_turns": 0,
		"avg_duration": 0,
	}
	if entries.is_empty():
		return summary
	var turn_total := 0
	var duration_total := 0
	var duration_count := 0
	for entry in entries:
		var outcome := str(entry.get("outcome", ""))
		if outcome == "victory":
			summary["wins"] = int(summary["wins"]) + 1
		elif outcome == "defeat" or outcome == "forfeit":
			summary["losses"] = int(summary["losses"]) + 1
		turn_total += int(entry.get("turns", 0))
		var duration := int(entry.get("duration", 0))
		if duration > 0:
			duration_total += duration
			duration_count += 1
	var scored_entries := entries.filter(func(entry):
		return entry.get("outcome") in ["victory", "defeat", "forfeit"] \
			or (entry.get("outcome") == "finished" and entry.get("mode") in ["ranked", "random"] and str(entry.get("result", "")) == "3"))
	summary["scored_count"] = scored_entries.size()
	if not scored_entries.is_empty():
		summary["win_rate"] = int(round(float(summary["wins"]) / float(scored_entries.size()) * 100.0))
	summary["avg_turns"] = int(round(float(turn_total) / float(entries.size())))
	if duration_count > 0:
		summary["avg_duration"] = int(round(float(duration_total) / float(duration_count)))
	# 连胜/连败：从最新一条开始数
	var streak_outcome := "" if scored_entries.is_empty() else str(scored_entries[0].get("outcome", ""))
	if streak_outcome == "victory":
		summary["streak_type"] = "win"
	elif streak_outcome == "defeat" or streak_outcome == "forfeit":
		summary["streak_type"] = "loss"
	if summary["streak_type"] != "none":
		var count := 0
		for entry in scored_entries:
			var outcome := str(entry.get("outcome", ""))
			var is_win: bool = outcome == "victory"
			var is_loss: bool = outcome == "defeat" or outcome == "forfeit"
			if summary["streak_type"] == "win" and is_win:
				count += 1
			elif summary["streak_type"] == "loss" and is_loss:
				count += 1
			else:
				break
		summary["streak_count"] = count
	return summary


# outcome_filter / mode_filter 取 "all" 或具体值
static func filtered_entries(entries: Array, outcome_filter: String, mode_filter: String) -> Array:
	var result: Array = []
	for entry in entries:
		if outcome_filter != "all" and str(entry.get("outcome", "")) != outcome_filter:
			continue
		if mode_filter != "all" and str(entry.get("mode", "")) != mode_filter:
			continue
		result.append(entry)
	return result


# 把一条战绩映射成本地视角：{you: stats, opp: stats, has_stats: bool}
static func entry_stats(entry: Dictionary) -> Dictionary:
	var local := int(entry.get("local_player", 1))
	var mine: Dictionary = entry.get("stats_p%d" % local, {})
	var theirs: Dictionary = entry.get("stats_p%d" % (3 - local), {})
	if mine.is_empty() and theirs.is_empty():
		return {"you": {}, "opp": {}, "has_stats": false}
	return {"you": mine, "opp": theirs, "has_stats": true}


static func format_duration(seconds: int, split_hours: bool = false) -> String:
	var clamped: int = maxi(0, seconds)
	@warning_ignore("integer_division")
	var hours := clamped / 3600
	@warning_ignore("integer_division")
	var minutes := (clamped % 3600) / 60
	var remainder := clamped % 60
	var parts := PackedStringArray()
	if hours > 0:
		parts.append(Locale.t("history.duration_hours", [hours]))
	if minutes > 0:
		parts.append(Locale.t("history.duration_minutes", [minutes]))
	if remainder > 0 or parts.is_empty():
		parts.append(Locale.t("history.duration_seconds", [remainder]))
	var separator := "" if Locale.language == "zh" else " "
	if split_hours and hours > 0 and parts.size() > 1:
		return parts[0] + "\n" + separator.join(parts.slice(1))
	return separator.join(parts)


# ============================================
# UI 构建
# ============================================

func _ready() -> void:
	_build_ui()
	_refresh_list()
	for entry in list_box.get_children():
		if entry.focus_mode == Control.FOCUS_ALL:
			entry.grab_focus()
			break
	_apply_responsive_layout()
	get_viewport().size_changed.connect(_apply_responsive_layout)


func _ui_scale() -> float:
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return 1.0
	# History is information-dense. Capping typography keeps useful rows visible
	# on large displays while margins still grow with the available canvas.
	return clampf(min(viewport_size.x / BASE_VIEWPORT_SIZE.x, viewport_size.y / BASE_VIEWPORT_SIZE.y), 0.85, 1.5)


func _apply_responsive_layout() -> void:
	var s := _ui_scale()
	if _page_margin:
		_page_margin.add_theme_constant_override("margin_left", int(52.0 * s))
		_page_margin.add_theme_constant_override("margin_right", int(52.0 * s))
		_page_margin.add_theme_constant_override("margin_top", maxi(80, int(30.0 * s)))
		_page_margin.add_theme_constant_override("margin_bottom", int(30.0 * s))
	if _root_box:
		_root_box.add_theme_constant_override("separation", int(14.0 * s))
	if _header:
		_header.add_theme_constant_override("separation", int(12.0 * s))
	if outcome_filter:
		outcome_filter.custom_minimum_size = Vector2(120, 34) * s
	if mode_filter:
		mode_filter.custom_minimum_size = Vector2(120, 34) * s


func _build_ui() -> void:
	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.apply_app_background(bg)
	add_child(bg)
	var margin := MarginContainer.new()
	_page_margin = margin
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 52)
	margin.add_theme_constant_override("margin_right", 52)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	add_child(margin)
	var root := VBoxContainer.new()
	_root_box = root
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	# ---- 标题栏 ----
	var header := HBoxContainer.new()
	_header = header
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)
	var back := Button.new()
	back.text = Locale.t("common.back")
	UITheme.apply_button(back, "secondary")
	back.pressed.connect(func(): UIMotion.go_back("res://MainMenu.tscn"))
	header.add_child(back)
	UITheme.place_page_back(self, back)
	var title := Label.new()
	title.text = Locale.t("history.title")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_title(title, 28)
	header.add_child(title)
	_clear_button = Button.new()
	_clear_button.text = Locale.t("history.clear")
	UITheme.apply_button(_clear_button, "utility")
	_clear_button.pressed.connect(_show_clear_confirmation)
	header.add_child(_clear_button)

	_history_controls = VBoxContainer.new()
	_history_controls.add_theme_constant_override("separation", 16)
	root.add_child(_history_controls)
	# ---- 总览面板 ----
	var overview := PanelContainer.new()
	UITheme.apply_panel(overview, "dark")
	_history_controls.add_child(overview)
	var overview_margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		overview_margin.add_theme_constant_override("margin_" + edge, 8)
	overview.add_child(overview_margin)
	var overview_content := VBoxContainer.new()
	overview_content.add_theme_constant_override("separation", 6)
	overview_margin.add_child(overview_content)
	summary_box = HBoxContainer.new()
	summary_box.add_theme_constant_override("separation", 10)
	overview_content.add_child(summary_box)
	summary_averages = Label.new()
	summary_averages.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_label(summary_averages, true)
	summary_averages.add_theme_font_size_override("font_size", 12)
	overview_content.add_child(summary_averages)

	# ---- 筛选栏 ----
	var filter_bar := HBoxContainer.new()
	filter_bar.add_theme_constant_override("separation", 14)
	_history_controls.add_child(filter_bar)
	outcome_filter = _build_filter_option(filter_bar, "history.filter_outcome", ["all"] + OUTCOMES, _outcome_options)
	mode_filter = _build_filter_option(filter_bar, "history.filter_mode", ["all", "online", "ranked", "random", "practice", "hotseat"], _mode_options)
	count_label = Label.new()
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_label(count_label, true)
	filter_bar.add_child(count_label)

	# ---- 战绩列表 ----
	_history_controls.add_child(UITheme.separator())
	var scroll := ScrollContainer.new()
	_history_scroll = scroll
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	root.add_child(scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 0)
	scroll.add_child(list_box)
	_empty_history = CenterContainer.new()
	_empty_history.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_empty_history)
	var empty := Label.new()
	empty.text = Locale.t("history.empty")
	UITheme.apply_label(empty, true)
	_empty_history.add_child(empty)


func _build_filter_option(bar: HBoxContainer, caption_key: String, values: Array, sink: Array) -> OptionButton:
	var caption := Label.new()
	caption.text = Locale.t(caption_key)
	UITheme.apply_label(caption, true)
	bar.add_child(caption)
	var option := OptionButton.new()
	for value in values:
		var label: String = Locale.t("history.filter_all") if value == "all" else _outcome_text(str(value)) if value in OUTCOMES else _mode_text(str(value))
		option.add_item(label)
		sink.append(str(value))
	option.select(0)
	option.custom_minimum_size = Vector2(120, 34)
	UITheme.apply_button(option, "secondary")
	option.item_selected.connect(func(_index: int): _refresh_list())
	bar.add_child(option)
	return option


func _current_filter(option: OptionButton, values: Array) -> String:
	var index := option.selected
	if index < 0 or index >= values.size():
		return "all"
	return str(values[index])


func _refresh_list() -> void:
	for child in list_box.get_children():
		child.queue_free()
	var all_entries: Array = PlayerData.match_history
	_history_controls.visible = not all_entries.is_empty()
	_clear_button.visible = not all_entries.is_empty()
	_empty_history.visible = all_entries.is_empty()
	_history_scroll.visible = not all_entries.is_empty()
	count_label.text = Locale.t("history.retention", [PlayerData.MAX_MATCH_HISTORY])
	if all_entries.is_empty():
		return
	var mode_entries := filtered_entries(all_entries, "all", _current_filter(mode_filter, _mode_options))
	_refresh_summary(mode_entries)
	var entries := filtered_entries(mode_entries, _current_filter(outcome_filter, _outcome_options), "all")
	if entries.is_empty():
		empty_label = Label.new()
		empty_label.text = Locale.t("history.empty_filtered")
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.custom_minimum_size = Vector2(0, 160)
		UITheme.apply_label(empty_label, true)
		list_box.add_child(empty_label)
		return
	for entry in entries:
		list_box.add_child(_make_match_card(entry))


func _refresh_summary(entries: Array) -> void:
	for child in summary_box.get_children():
		child.queue_free()
	var summary := compute_summary(entries)
	var streak_text: String = Locale.t("history.streak_none")
	if int(summary["streak_count"]) > 0:
		if summary["streak_type"] == "win":
			streak_text = Locale.t("history.streak_win", [int(summary["streak_count"])])
		elif summary["streak_type"] == "loss":
			streak_text = Locale.t("history.streak_loss", [int(summary["streak_count"])])
	var rate := "%d%%" % int(summary["win_rate"]) if int(summary["scored_count"]) > 0 else Locale.t("history.streak_none")
	summary_box.add_child(_make_summary_tile(rate, Locale.t("history.overview.win_rate"), COLOR_NEUTRAL, true))
	var record := Locale.t("history.overview.record", [summary["wins"], summary["losses"]])
	summary_box.add_child(_make_summary_tile(str(summary["total"]), record, COLOR_NEUTRAL))
	summary_box.add_child(_make_summary_tile(streak_text, Locale.t("history.overview.streak"), COLOR_WIN if summary["streak_type"] == "win" else (COLOR_LOSS if summary["streak_type"] == "loss" else COLOR_NEUTRAL)))
	summary_averages.visible = not entries.is_empty()
	summary_averages.text = Locale.t("history.overview.averages", [summary["avg_turns"], format_duration(int(summary["avg_duration"])) if summary["avg_duration"] > 0 else Locale.t("history.streak_none")])


func _make_summary_tile(value: String, caption: String, accent: Color, featured := false) -> MarginContainer:
	var tile := MarginContainer.new()
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	tile.add_child(box)
	var value_label := Label.new()
	value_label.text = value
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", 28 if featured else 18)
	value_label.add_theme_font_override("font", UITheme.medium_font())
	value_label.add_theme_color_override("font_color", accent)
	var caption_label := Label.new()
	caption_label.text = caption
	caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption_label.add_theme_font_size_override("font_size", 12)
	caption_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	box.add_child(caption_label)
	box.add_child(value_label)
	return tile


# ============================================
# 战绩卡片
# ============================================

func _outcome_color(outcome: String) -> Color:
	if outcome == "victory":
		return COLOR_WIN
	if outcome == "defeat" or outcome == "forfeit":
		return COLOR_LOSS
	return COLOR_NEUTRAL


func _make_match_card(entry: Dictionary) -> Control:
	var outcome := str(entry.get("outcome", ""))
	var accent := _outcome_color(outcome)
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 76)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.tooltip_text = Locale.t("history.open_detail")
	card.focus_mode = Control.FOCUS_ALL
	var rest := UITheme.list_row_style()
	rest.set_content_margin_all(8)
	rest.content_margin_left = 24
	card.add_theme_stylebox_override("panel", rest)
	UITheme.add_selection_focus(card)
	card.gui_input.connect(_on_card_input.bind(entry, card))

	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
	body.add_theme_constant_override("separation", 16)
	card.add_child(body)

	var result := Label.new()
	result.text = _outcome_text(outcome)
	result.custom_minimum_size.x = 112
	UITheme.apply_title(result, 18)
	result.add_theme_color_override("font_color", accent)
	body.add_child(result)
	var match_info := VBoxContainer.new()
	match_info.alignment = BoxContainer.ALIGNMENT_CENTER
	match_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	match_info.add_theme_constant_override("separation", 2)
	body.add_child(match_info)
	var mode := Label.new()
	mode.text = _mode_text(str(entry.get("mode", "")))
	UITheme.apply_label(mode)
	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", 18)
	match_info.add_child(identity)
	identity.add_child(mode)
	var deck_name := str(entry.get("deck_name", ""))
	if not deck_name.is_empty():
		var deck := Label.new()
		deck.set_meta("keyword_literal", true)
		deck.text = deck_name
		deck.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		deck.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.apply_label(deck)
		identity.add_child(deck)
	var meta := Label.new()
	var meta_parts := PackedStringArray()
	var timestamp := int(entry.get("timestamp", 0))
	if timestamp > 0:
		meta_parts.append(_format_time(timestamp))
	var turns := int(entry.get("turns", 0))
	if turns > 0:
		meta_parts.append(Locale.t("history.turns_only", [turns]))
	var duration := int(entry.get("duration", 0))
	if duration > 0:
		meta_parts.append(Locale.t("history.duration", [format_duration(duration)]))
	meta.text = ("，" if Locale.language=="zh" else ", ").join(meta_parts)
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.apply_label(meta, true)
	meta.add_theme_font_size_override("font_size", 13)
	meta.visible = not meta_parts.is_empty()
	match_info.add_child(meta)
	if entry.get("mode") == "ranked":
		var rating := Label.new()
		var receipt: Variant = entry.get("ranked_settlement")
		if PlayerData.valid_ranked_history_settlement(receipt):
			var delta := int(receipt.after) - int(receipt.before)
			rating.text = _format_rating_delta(delta)
			UITheme.apply_title(rating, 20)
			rating.add_theme_color_override("font_color", COLOR_WIN if delta > 0 else (COLOR_LOSS if delta < 0 else COLOR_NEUTRAL))
		else:
			rating.text = _rating_status(entry)
			UITheme.apply_label(rating, true)
		body.add_child(rating)
	var open := Label.new()
	open.text = "›"
	UITheme.apply_title(open, 20)
	open.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	body.add_child(open)
	return card


func _format_rating_delta(delta: int) -> String:
	return "−%d" % -delta if delta < 0 else ("%+d" % delta if delta > 0 else "0")


func _rating_status(entry: Dictionary) -> String:
	return Locale.t("history.rating_pending" if not str(entry.get("ranked_match_id", "")).is_empty() else "history.rating_missing")


func _on_card_input(event: InputEvent, entry: Dictionary, card: Control) -> void:
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
			or event.is_action_pressed("ui_accept"):
		card.grab_focus()
		_show_detail(entry)
		card.accept_event()


func _make_badge(text: String, accent: Color) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", UITheme.panel_style(
		Color(accent.r, accent.g, accent.b, 0.16), accent, 1, 6
	))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_bottom", 2)
	badge.add_child(margin)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", accent)
	margin.add_child(label)
	return badge


func _make_hp_bar(caption: String, hp: int, max_hp: int, color: Color) -> Control:
	var box := HBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = Locale.t("history.remaining_hp", [caption, maxi(0, hp)])
	label.custom_minimum_size.x = 124
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", color)
	box.add_child(label)
	if max_hp <= 0:
		return box
	var bar := ProgressBar.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size = Vector2(0, 12)
	bar.min_value = 0
	bar.max_value = max_hp
	bar.value = max(0, hp)
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", UITheme.panel_style(Color(UITheme.Tokens.PANEL_DARK,0.9), Color(UITheme.Tokens.DISABLED,0.8), 1, 5))
	bar.add_theme_stylebox_override("fill", UITheme.panel_style(Color(color.r, color.g, color.b, 0.85), color, 1, 5))
	box.add_child(bar)
	return box


# ============================================
# 详情弹窗
# ============================================

func _show_detail(entry: Dictionary) -> void:
	var popup := UITheme.make_popup_layer(self, 120)
	var layer: CanvasLayer = popup["layer"]
	layer.name = "MatchDetail"
	layer.set_meta("popup_close", layer.queue_free)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	var popup_size := Vector2(760, 600) * _ui_scale()
	var viewport_size := get_viewport_rect().size
	popup_size.x = minf(popup_size.x, viewport_size.x - 48.0)
	popup_size.y = minf(popup_size.y, viewport_size.y - 48.0)
	panel.offset_left = -popup_size.x * 0.5
	panel.offset_top = -popup_size.y * 0.5
	panel.offset_right = popup_size.x * 0.5
	panel.offset_bottom = popup_size.y * 0.5
	UITheme.apply_popup_frame(panel, "dark", false)
	layer.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 20)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	var outcome := str(entry.get("outcome", ""))
	var accent := _outcome_color(outcome)
	var title := Label.new()
	title.text = "%s（%s）" % [_outcome_text(outcome), _mode_text(str(entry.get("mode", "")))]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, 26)
	title.add_theme_color_override("font_color", accent)
	box.add_child(title)

	var subtitle := Label.new()
	var sub_parts: Array = [
		_format_time(int(entry.get("timestamp", 0))),
	]
	if int(entry.get("turns", 0)) > 0:
		sub_parts.append(Locale.t("history.turns_only", [int(entry.turns)]))
	var duration := int(entry.get("duration", 0))
	if duration > 0:
		sub_parts.append(Locale.t("history.duration", [format_duration(duration)]))
	subtitle.text = "\n".join(sub_parts)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_label(subtitle, true)
	box.add_child(subtitle)

	if entry.has("player_hp"):
		box.add_child(_make_hp_bar(Locale.t("history.you"), int(entry.player_hp), int(entry.get("player_max_hp", 0)), COLOR_WIN))
	if entry.has("opponent_hp"):
		box.add_child(_make_hp_bar(Locale.t("history.opponent"), int(entry.opponent_hp), int(entry.get("opponent_max_hp", 0)), COLOR_LOSS))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var scroll_box := VBoxContainer.new()
	scroll_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_box.add_theme_constant_override("separation", 12)
	scroll.add_child(scroll_box)
	if entry.get("mode") == "ranked":
		var heading := Label.new()
		heading.text = Locale.t("history.rating_title")
		UITheme.apply_title(heading, 18)
		scroll_box.add_child(heading)
		var score := Label.new()
		UITheme.apply_label(score)
		var receipt: Variant = entry.get("ranked_settlement")
		if PlayerData.valid_ranked_history_settlement(receipt):
			var delta := int(receipt.after) - int(receipt.before)
			score.text = Locale.t("history.rating_result", [int(receipt.before), int(receipt.after), _format_rating_delta(delta)])
			var multiplier: Variant = receipt.get("multiplier")
			if multiplier is float or multiplier is int:
				score.text += "\n" + Locale.t("history.rating_multiplier" if delta > 0 else "history.rating_multiplier_inactive", [float(multiplier)])
		else:
			score.text = _rating_status(entry)
		scroll_box.add_child(score)

	# 关键数据对比
	var stats := entry_stats(entry)
	if stats["has_stats"]:
		var stats_title := Label.new()
		stats_title.text = Locale.t("history.stats_title")
		UITheme.apply_title(stats_title, 18)
		scroll_box.add_child(stats_title)
		var legend := HBoxContainer.new()
		legend.add_theme_constant_override("separation", 16)
		scroll_box.add_child(legend)
		legend.add_child(_make_badge(Locale.t("history.you"), COLOR_WIN))
		legend.add_child(_make_badge(Locale.t("history.opponent"), COLOR_LOSS))
		for key in STAT_KEYS:
			scroll_box.add_child(_make_stat_row(key, stats["you"], stats["opp"]))
	else:
		var no_stats := Label.new()
		no_stats.text = Locale.t("history.stats_unavailable")
		no_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UITheme.apply_label(no_stats, true)
		scroll_box.add_child(no_stats)

	# 卡组对比
	var deck_title := Label.new()
	var shared_pool: bool = entry.get("mode") in ["ranked", "random"]
	deck_title.text = Locale.t("history.shared_pool" if shared_pool else "history.deck_compare")
	UITheme.apply_title(deck_title, 18)
	scroll_box.add_child(deck_title)
	var own_cards: Array = entry.get("deck_card_faces", entry.get("deck_cards", []))
	var opponent_cards: Array = entry.get("opponent_card_faces", entry.get("opponent_cards", []))
	var own_legacy := _index_legacy_cards(own_cards) if not entry.has("deck_card_faces") else {}
	if shared_pool:
		scroll_box.add_child(_make_deck_column("", own_cards, COLOR_NEUTRAL, "", own_legacy))
	else:
		var decks := HBoxContainer.new()
		decks.add_theme_constant_override("separation", 16)
		scroll_box.add_child(decks)
		var deck_name := str(entry.get("deck_name", ""))
		var opponent_legacy := _index_legacy_cards(opponent_cards) if not entry.has("opponent_card_faces") else {}
		decks.add_child(_make_deck_column(Locale.t("history.your_cards"), own_cards, COLOR_WIN, deck_name, own_legacy))
		decks.add_child(_make_deck_column(Locale.t("history.opponent_cards"), opponent_cards, COLOR_LOSS, "", opponent_legacy, not deck_name.is_empty()))

	var version := Label.new()
	version.set_meta("keyword_literal",true)
	version.text = "%s\n%s" % [
		Locale.t("history.version", [str(entry.get("app_version", ""))]),
		Locale.t("history.deck_name", [str(entry.get("deck_name", Locale.t("history.unknown_deck")))]),
	]
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_label(version, true)
	version.add_theme_font_size_override("font_size", 12)
	scroll_box.add_child(version)

	var close := Button.new()
	close.text = Locale.t("common.back")
	close.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	close.custom_minimum_size.y = 36
	UITheme.apply_selection_entry(close)
	close.pressed.connect(layer.queue_free)
	box.add_child(close)
	UIMotion.register_popup(layer, close)


# 双列数值 + 占比条：我方绿色靠左，对方红色靠右
func _make_stat_row(key: String, mine: Dictionary, theirs: Dictionary) -> Control:
	var label := Label.new()
	label.text = Locale.t("history.stat.%s" % key)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_label(label)
	label.add_theme_font_size_override("font_size", 13)
	var mine_value := int(mine.get(key, 0))
	var theirs_value := int(theirs.get(key, 0))
	var mine_label := Label.new()
	mine_label.text = str(mine_value)
	mine_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mine_label.custom_minimum_size = Vector2(52, 0)
	mine_label.add_theme_font_size_override("font_size", 16)
	mine_label.add_theme_color_override("font_color", COLOR_WIN if mine_value >= theirs_value else UITheme.COLOR_TEXT_MUTED)
	var theirs_label := Label.new()
	theirs_label.text = str(theirs_value)
	theirs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	theirs_label.custom_minimum_size = Vector2(52, 0)
	theirs_label.add_theme_font_size_override("font_size", 16)
	theirs_label.add_theme_color_override("font_color", COLOR_LOSS if theirs_value > mine_value else UITheme.COLOR_TEXT_MUTED)

	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	var top := HBoxContainer.new()
	row.add_child(top)
	top.add_child(mine_label)
	top.add_child(label)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(theirs_label)

	var total := mine_value + theirs_value
	var share := 0.5
	if total > 0:
		share = float(mine_value) / float(total)
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = share
	bar.custom_minimum_size = Vector2(0, 8)
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", UITheme.panel_style(Color(UITheme.Tokens.PANEL_DARK,0.9), Color(UITheme.Tokens.DISABLED,0.8), 1, 4))
	bar.add_theme_stylebox_override("fill", UITheme.panel_style(Color(COLOR_WIN.r, COLOR_WIN.g, COLOR_WIN.b, 0.8), COLOR_WIN, 1, 4))
	row.add_child(bar)
	return row


func _make_deck_column(caption: String, cards: Array, accent: Color, deck_name: String, legacy_cards: Dictionary, reserve_name_row: bool = false) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	if not caption.is_empty():
		var title := Label.new()
		title.text = caption
		title.add_theme_font_size_override("font_size", 14)
		title.add_theme_color_override("font_color", accent)
		box.add_child(title)
	if not deck_name.is_empty() or reserve_name_row:
		var name_label := Label.new()
		name_label.set_meta("keyword_literal",true)
		name_label.text = deck_name if not deck_name.is_empty() else " "
		UITheme.apply_label(name_label, true)
		name_label.add_theme_font_size_override("font_size", 12)
		box.add_child(name_label)
	if cards.is_empty():
		var none_label := Label.new()
		none_label.text = Locale.t("history.cards_unavailable")
		UITheme.apply_label(none_label, true)
		none_label.add_theme_font_size_override("font_size", 12)
		box.add_child(none_label)
		return box
	var flow := FlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	box.add_child(flow)
	for card in cards.slice(0, 30):
		flow.add_child(_make_history_card(card, legacy_cards))
	if cards.size() > 30:
		var more := Label.new()
		more.text = "… +%d" % (cards.size() - 30)
		UITheme.apply_label(more, true)
		more.add_theme_font_size_override("font_size", 12)
		box.add_child(more)
	return box


func _index_legacy_cards(recorded_names: Array) -> Dictionary:
	if recorded_names.is_empty():
		return {}
	var matching_decks: Array[Array] = []
	for deck: Dictionary in PlayerData.deck_library:
		var deck_cards: Array = deck.get("cards", [])
		if deck_cards.size() == recorded_names.size() and deck_cards.map(func(card: CardData): return card.card_name) == recorded_names:
			matching_decks.append(deck_cards)
	var candidates: Array = PlayerData.card_library + CardDatabase.starter_library()
	if not matching_decks.is_empty():
		candidates = []
		for deck_cards in matching_decks:
			candidates.append_array(deck_cards)
	var cards := {}
	for card: CardData in candidates:
		var face := MatchHistoryRepository.card_face(card)
		if not cards.has(card.card_name):
			cards[card.card_name] = face
		elif cards[card.card_name] != face:
			cards[card.card_name] = {}
	return cards


func _make_history_card(record: Variant, legacy_cards: Dictionary) -> Control:
	var cell := Control.new()
	cell.custom_minimum_size = CARD_PREVIEW_SIZE
	cell.mouse_filter = Control.MOUSE_FILTER_PASS
	var preview := CardFace.new()
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.size = Vector2(384, 528)
	preview.scale = Vector2.ONE * (CARD_PREVIEW_SIZE.x / preview.size.x)
	cell.add_child(preview)
	var data: Dictionary = record if record is Dictionary else legacy_cards.get(str(record), {})
	if not data.is_empty():
		var card := CardData.new(str(data.get("name", "")), int(data.get("cost", 0)), int(data.get("max_hp", 1)), int(data.get("atk", 0)), [])
		card.card_type = str(data.get("card_type", "minion"))
		card.art_path = str(data.get("art_path", ""))
		preview.bind(card, false)
		cell.tooltip_text = card.card_name if record is Dictionary else Locale.t("history.legacy_card_library", [card.card_name])
	else:
		preview.bind_name_only(str(record))
		cell.tooltip_text = Locale.t("history.legacy_card_name", [str(record)])
	return cell


func _show_clear_confirmation() -> void:
	if PlayerData.match_history.is_empty():
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = Locale.t("history.clear")
	dialog.dialog_text = Locale.t("history.clear_confirm")
	dialog.confirmed.connect(func():
		PlayerData.clear_match_history()
		_refresh_list()
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.confirmed.connect(dialog.queue_free)
	add_child(dialog)
	UITheme.apply_dialog(dialog, true)
	UITheme.apply_destructive_confirmation(dialog, Locale.t("history.clear"))
	var dialog_size := Vector2i(Vector2(430, 180) * _ui_scale())
	dialog_size.x = mini(dialog_size.x, int(get_viewport_rect().size.x - 32.0))
	dialog_size.y = mini(dialog_size.y, int(get_viewport_rect().size.y - 32.0))
	dialog.popup_centered(dialog_size)


# ============================================
# 文案辅助
# ============================================

func _mode_text(mode: String) -> String:
	match mode:
		"online": return Locale.t("result.mode_online")
		"ranked", "random": return Locale.t("matchmaking." + mode)
		"practice": return Locale.t("result.mode_practice")
		"hotseat": return Locale.t("result.mode_hotseat")
	return mode


func _outcome_text(outcome: String) -> String:
	return Locale.t("history.outcome.%s" % outcome)


func _format_time(timestamp: int) -> String:
	if timestamp <= 0:
		return "--"
	var dt := Time.get_datetime_dict_from_unix_time(timestamp)
	return "%04d-%02d-%02d  %02d:%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute]
