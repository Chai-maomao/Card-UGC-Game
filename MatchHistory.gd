extends Control

const UITheme = preload("res://UITheme.gd")
const BASE_VIEWPORT_SIZE := Vector2(1152, 648)

const COLOR_WIN := Color(0.42, 0.95, 0.58)
const COLOR_LOSS := Color(1.0, 0.48, 0.45)
const COLOR_NEUTRAL := Color(0.88, 0.82, 0.66)
const STAT_KEYS := [
	"summons", "spells", "parasites", "cards_drawn",
	"card_damage", "hero_damage", "kills", "mana_spent",
]

var list_box: VBoxContainer
var empty_label: Label
var count_label: Label
var summary_box: HBoxContainer
var outcome_filter: OptionButton
var mode_filter: OptionButton
var _outcome_options: Array = []
var _mode_options: Array = []
var _page_margin: MarginContainer
var _root_box: VBoxContainer
var _header: HBoxContainer


# ============================================
# 纯逻辑（便于无头测试）
# ============================================

# entries 按最新在前排列；返回 {total, wins, losses, win_rate, streak_type,
# streak_count, avg_turns, avg_duration}
static func compute_summary(entries: Array) -> Dictionary:
	var summary := {
		"total": entries.size(),
		"wins": 0,
		"losses": 0,
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
	summary["win_rate"] = int(round(float(summary["wins"]) / float(entries.size()) * 100.0))
	summary["avg_turns"] = int(round(float(turn_total) / float(entries.size())))
	if duration_count > 0:
		summary["avg_duration"] = int(round(float(duration_total) / float(duration_count)))
	# 连胜/连败：从最新一条开始数
	var streak_outcome := str(entries[0].get("outcome", ""))
	if streak_outcome == "victory":
		summary["streak_type"] = "win"
	elif streak_outcome == "defeat" or streak_outcome == "forfeit":
		summary["streak_type"] = "loss"
	if summary["streak_type"] != "none":
		var count := 0
		for entry in entries:
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


static func format_duration(seconds: int) -> String:
	var clamped: int = maxi(0, seconds)
	return Locale.t("history.duration_format", [int(clamped / 60.0), clamped % 60])


# ============================================
# UI 构建
# ============================================

func _ready() -> void:
	_build_ui()
	_refresh_list()
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
		_page_margin.add_theme_constant_override("margin_top", int(30.0 * s))
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
	var title := Label.new()
	title.text = Locale.t("history.title")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, 32)
	header.add_child(title)
	var clear := Button.new()
	clear.text = Locale.t("history.clear")
	UITheme.apply_button(clear, "danger")
	clear.pressed.connect(_show_clear_confirmation)
	header.add_child(clear)

	count_label = Label.new()
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_label(count_label, true)
	root.add_child(count_label)

	# ---- 总览面板 ----
	var overview_panel := PanelContainer.new()
	UITheme.apply_panel(overview_panel, "dark")
	root.add_child(overview_panel)
	var overview_margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		overview_margin.add_theme_constant_override(side, 12)
	overview_panel.add_child(overview_margin)
	summary_box = HBoxContainer.new()
	summary_box.add_theme_constant_override("separation", 10)
	overview_margin.add_child(summary_box)

	# ---- 筛选栏 ----
	var filter_bar := HBoxContainer.new()
	filter_bar.add_theme_constant_override("separation", 14)
	filter_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(filter_bar)
	outcome_filter = _build_filter_option(filter_bar, "history.filter_outcome", ["all", "victory", "defeat", "finished", "forfeit"], _outcome_options)
	mode_filter = _build_filter_option(filter_bar, "history.filter_mode", ["all", "online", "practice", "hotseat"], _mode_options)

	# ---- 战绩列表 ----
	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UITheme.apply_panel(frame, "dark")
	root.add_child(frame)
	var inner := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		inner.add_theme_constant_override(side, 14)
	frame.add_child(inner)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 10)
	scroll.add_child(list_box)
	empty_label = Label.new()
	empty_label.text = Locale.t("history.empty")
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_label.custom_minimum_size = Vector2(0, 160)
	UITheme.apply_label(empty_label, true)
	list_box.add_child(empty_label)


func _build_filter_option(bar: HBoxContainer, caption_key: String, values: Array, sink: Array) -> OptionButton:
	var caption := Label.new()
	caption.text = Locale.t(caption_key)
	UITheme.apply_label(caption, true)
	bar.add_child(caption)
	var option := OptionButton.new()
	for value in values:
		var label: String = Locale.t("history.filter_all") if value == "all" else _outcome_text(str(value)) if value in ["victory", "defeat", "finished", "forfeit"] else _mode_text(str(value))
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
	count_label.text = Locale.t("history.count", [all_entries.size(), PlayerData.MAX_MATCH_HISTORY])
	_refresh_summary(all_entries)
	var entries := filtered_entries(all_entries, _current_filter(outcome_filter, _outcome_options), _current_filter(mode_filter, _mode_options))
	if entries.is_empty():
		empty_label = Label.new()
		empty_label.text = Locale.t("history.empty") if all_entries.is_empty() else Locale.t("history.empty_filtered")
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.custom_minimum_size = Vector2(0, 160)
		UITheme.apply_label(empty_label, true)
		list_box.add_child(empty_label)
		return
	for entry in entries:
		list_box.add_child(_make_match_card(entry))
	UITheme.animate_list_enter(list_box)


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
	summary_box.add_child(_make_summary_tile(str(summary["total"]), Locale.t("history.overview.total"), COLOR_NEUTRAL))
	summary_box.add_child(_make_summary_tile(str(summary["wins"]), Locale.t("history.overview.wins"), COLOR_WIN))
	summary_box.add_child(_make_summary_tile(str(summary["losses"]), Locale.t("history.overview.losses"), COLOR_LOSS))
	summary_box.add_child(_make_summary_tile("%d%%" % int(summary["win_rate"]), Locale.t("history.overview.win_rate"), COLOR_NEUTRAL))
	summary_box.add_child(_make_summary_tile(streak_text, Locale.t("history.overview.streak"), COLOR_WIN if summary["streak_type"] == "win" else (COLOR_LOSS if summary["streak_type"] == "loss" else COLOR_NEUTRAL)))
	summary_box.add_child(_make_summary_tile(str(summary["avg_turns"]), Locale.t("history.overview.avg_turns"), COLOR_NEUTRAL))
	summary_box.add_child(_make_summary_tile(format_duration(int(summary["avg_duration"])), Locale.t("history.overview.avg_duration"), COLOR_NEUTRAL))


func _make_summary_tile(value: String, caption: String, accent: Color) -> PanelContainer:
	var tile := PanelContainer.new()
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.add_theme_stylebox_override("panel", UITheme.panel_style(
		Color(0.10, 0.115, 0.15, 0.92), accent * Color(1, 1, 1, 0.35), 1, 8,
		Color(accent.r, accent.g, accent.b, 0.10), 3
	))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	tile.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	margin.add_child(box)
	var value_label := Label.new()
	value_label.text = value
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", 21)
	value_label.add_theme_color_override("font_color", accent)
	box.add_child(value_label)
	var caption_label := Label.new()
	caption_label.text = caption
	caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption_label.add_theme_font_size_override("font_size", 11)
	caption_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED)
	box.add_child(caption_label)
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
	card.custom_minimum_size = Vector2(0, 84)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", UITheme.panel_style(
		Color(0.115, 0.13, 0.165, 0.95),
		accent * Color(1, 1, 1, 0.55), 1, 10,
		Color(0, 0, 0, 0.35), 4
	))
	card.gui_input.connect(_on_card_input.bind(entry, card))
	var outer := HBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	card.add_child(outer)

	# 左侧色条
	var strip := ColorRect.new()
	strip.custom_minimum_size = Vector2(6, 0)
	strip.color = accent
	outer.add_child(strip)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	outer.add_child(body)

	# 第一行：结果徽章 + 模式 + 时间 + 回合 + 用时
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	body.add_child(top)
	top.add_child(_make_badge(_outcome_text(outcome), accent))
	top.add_child(_make_badge(_mode_text(str(entry.get("mode", ""))), UITheme.COLOR_TEXT_MUTED))
	var meta := Label.new()
	var meta_parts: Array = [_format_time(int(entry.get("timestamp", 0)))]
	var turns := int(entry.get("turns", 0))
	if turns > 0:
		meta_parts.append(Locale.t("history.turns_only", [turns]))
	var duration := int(entry.get("duration", 0))
	if duration > 0:
		meta_parts.append(Locale.t("history.duration", [format_duration(duration)]))
	meta.text = "   ·   ".join(meta_parts)
	meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_label(meta, true)
	meta.add_theme_font_size_override("font_size", 13)
	top.add_child(meta)

	# 第二行：双方生命条
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 12)
	body.add_child(hp_row)
	hp_row.add_child(_make_hp_bar(Locale.t("history.you"), int(entry.get("player_hp", 0)), 20, COLOR_WIN))
	hp_row.add_child(_make_hp_bar(Locale.t("history.opponent"), int(entry.get("opponent_hp", 0)), 20, COLOR_LOSS))
	return card


func _on_card_input(event: InputEvent, entry: Dictionary, card: Control) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
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
	label.text = "%s %d" % [caption, max(0, hp)]
	label.custom_minimum_size = Vector2(96, 0)
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", color)
	box.add_child(label)
	var bar := ProgressBar.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size = Vector2(0, 12)
	bar.min_value = 0
	bar.max_value = max(1, max_hp)
	bar.value = max(0, hp)
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", UITheme.panel_style(Color(0.05, 0.06, 0.08, 0.9), Color(0.2, 0.22, 0.27, 0.8), 1, 5))
	bar.add_theme_stylebox_override("fill", UITheme.panel_style(Color(color.r, color.g, color.b, 0.85), color, 1, 5))
	box.add_child(bar)
	return box


# ============================================
# 详情弹窗
# ============================================

func _show_detail(entry: Dictionary) -> void:
	var popup := UITheme.make_popup_layer(self, 120)
	var layer: CanvasLayer = popup["layer"]
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
	UITheme.apply_panel(panel, "gold")
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
	title.text = "%s · %s" % [_outcome_text(outcome), _mode_text(str(entry.get("mode", "")))]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title, 26)
	title.add_theme_color_override("font_color", accent)
	box.add_child(title)

	var subtitle := Label.new()
	var sub_parts: Array = [
		_format_time(int(entry.get("timestamp", 0))),
		Locale.t("history.turn_hp", [int(entry.get("turns", 0)), int(entry.get("player_hp", 0)), int(entry.get("opponent_hp", 0))]),
	]
	var duration := int(entry.get("duration", 0))
	if duration > 0:
		sub_parts.append(Locale.t("history.duration", [format_duration(duration)]))
	subtitle.text = "\n".join(sub_parts)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_label(subtitle, true)
	box.add_child(subtitle)

	box.add_child(_make_hp_bar(Locale.t("history.you"), int(entry.get("player_hp", 0)), 20, COLOR_WIN))
	box.add_child(_make_hp_bar(Locale.t("history.opponent"), int(entry.get("opponent_hp", 0)), 20, COLOR_LOSS))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var scroll_box := VBoxContainer.new()
	scroll_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_box.add_theme_constant_override("separation", 12)
	scroll.add_child(scroll_box)

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
	deck_title.text = Locale.t("history.deck_compare")
	UITheme.apply_title(deck_title, 18)
	scroll_box.add_child(deck_title)
	var decks := HBoxContainer.new()
	decks.add_theme_constant_override("separation", 16)
	scroll_box.add_child(decks)
	decks.add_child(_make_deck_column(Locale.t("history.your_cards"), entry.get("deck_cards", []), COLOR_WIN, str(entry.get("deck_name", ""))))
	decks.add_child(_make_deck_column(Locale.t("history.opponent_cards"), entry.get("opponent_cards", []), COLOR_LOSS, ""))

	var version := Label.new()
	version.text = "%s · %s" % [
		Locale.t("history.version", [str(entry.get("app_version", ""))]),
		Locale.t("history.deck_name", [str(entry.get("deck_name", Locale.t("history.unknown_deck")))]),
	]
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_label(version, true)
	version.add_theme_font_size_override("font_size", 12)
	scroll_box.add_child(version)

	var close := Button.new()
	close.text = Locale.t("battle.close")
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UITheme.apply_button(close, "secondary")
	close.pressed.connect(layer.queue_free)
	box.add_child(close)
	UITheme.animate_popup_enter(panel)


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
	bar.add_theme_stylebox_override("background", UITheme.panel_style(Color(0.05, 0.06, 0.08, 0.9), Color(0.2, 0.22, 0.27, 0.8), 1, 4))
	bar.add_theme_stylebox_override("fill", UITheme.panel_style(Color(COLOR_WIN.r, COLOR_WIN.g, COLOR_WIN.b, 0.8), COLOR_WIN, 1, 4))
	row.add_child(bar)
	return row


func _make_deck_column(caption: String, cards: Array, accent: Color, deck_name: String) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = caption
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", accent)
	box.add_child(title)
	if deck_name != "":
		var name_label := Label.new()
		name_label.text = deck_name
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
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	box.add_child(flow)
	var shown: int = 0
	for card_name in cards:
		if shown >= 30:
			break
		flow.add_child(_make_card_chip(str(card_name), accent))
		shown += 1
	if cards.size() > 30:
		var more := Label.new()
		more.text = "… +%d" % (cards.size() - 30)
		UITheme.apply_label(more, true)
		more.add_theme_font_size_override("font_size", 12)
		box.add_child(more)
	return box


func _make_card_chip(text: String, accent: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", UITheme.panel_style(
		Color(accent.r, accent.g, accent.b, 0.10), Color(accent.r, accent.g, accent.b, 0.45), 1, 5
	))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 1)
	margin.add_theme_constant_override("margin_bottom", 1)
	chip.add_child(margin)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	margin.add_child(label)
	return chip


func _show_clear_confirmation() -> void:
	if PlayerData.match_history.is_empty():
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = Locale.t("history.clear")
	dialog.dialog_text = Locale.t("history.clear_confirm")
	dialog.ok_button_text = Locale.t("common.confirm")
	dialog.cancel_button_text = Locale.t("common.cancel")
	dialog.confirmed.connect(func():
		PlayerData.clear_match_history()
		_refresh_list()
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.confirmed.connect(dialog.queue_free)
	add_child(dialog)
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
