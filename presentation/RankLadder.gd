extends Control

const Ranks = preload("res://RankTiers.gd")
const ORNAMENT = preload("res://res/ui/ranks/ladder-ornament.svg")
const STEP_HEIGHT := 20.0
const STEP_BASE := 9.0
const ROW_HEIGHT := 62.0
const METALS := [
	Color("#b98a67"), Color("#adbcc4"), Color("#d9b168"),
	Color("#8ec8b9"), Color("#90c5e3"), Color("#c7a9eb"),
]

var _current := -1
var _scroll: ScrollContainer
var _margin: MarginContainer
var _chart_slot: CenterContainer
var _compact := false


static func open(parent: Control, rating: int) -> void:
	var popup := UITheme.make_popup_layer(parent, 120)
	var layer: CanvasLayer = popup.layer
	layer.name = "RankLadder"
	layer.set_meta("popup_close", layer.queue_free)
	var page = load("res://presentation/RankLadder.gd").new()
	layer.add_child(page)
	page._build(layer, rating)


func _build(layer: CanvasLayer, rating: int) -> void:
	_current = Ranks.tier_index(rating) if rating >= 0 else -1
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := Panel.new()
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UITheme.apply_app_background(background)

	var ornament := TextureRect.new()
	ornament.texture = ORNAMENT
	ornament.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ornament.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	ornament.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ornament.self_modulate = Color("#856435") if UITheme.Tokens.light_mode else Color("#c3a679")
	add_child(ornament)
	ornament.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_scroll = ScrollContainer.new()
	add_child(_scroll)
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_top = 70
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_margin = MarginContainer.new()
	_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_margin.add_theme_constant_override("margin_bottom", 24)
	_scroll.add_child(_margin)
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 24)
	_margin.add_child(content)
	var title := _add_label(content, Locale.t("matchmaking.ladder_title"), 48)
	title.add_theme_font_override("font", UITheme.bold_font())
	title.add_theme_color_override("font_color", UITheme.Tokens.TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var rules := _add_label(content, Locale.t("matchmaking.ladder_rules"), 16, true)
	rules.set_meta("keyword_literal", true)
	rules.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_chart_slot = CenterContainer.new()
	content.add_child(_chart_slot)
	_scroll.resized.connect(_layout_chart)
	_layout_chart()

	var back := Button.new()
	back.text = Locale.t("common.back")
	add_child(back)
	UITheme.place_page_back(self, back)
	back.pressed.connect(layer.queue_free)
	UIMotion.register_popup(layer, back)


func _layout_chart() -> void:
	var width := _scroll.size.x
	_margin.custom_minimum_size.y = _scroll.size.y
	var inset := roundi(clampf(width * 0.045, 18.0, 72.0))
	_margin.add_theme_constant_override("margin_left", inset)
	_margin.add_theme_constant_override("margin_right", inset)
	var compact := width < 820.0
	if _chart_slot.get_child_count() == 0 or compact != _compact:
		_compact = compact
		_build_chart()
	var chart := _chart_slot.get_child(0) as Control
	chart.custom_minimum_size.x = minf(maxf(0.0, width - inset * 2.0 - 16.0), 1280.0)


func _build_chart() -> void:
	for child in _chart_slot.get_children():
		_chart_slot.remove_child(child)
		child.queue_free()
	var chart: BoxContainer = VBoxContainer.new() if _compact else HBoxContainer.new()
	chart.add_theme_constant_override("separation", 0 if _compact else 8)
	_chart_slot.add_child(chart)
	if _compact:
		chart.draw.connect(_draw_compact_track.bind(chart))
		chart.resized.connect(chart.queue_redraw)
		for index in range(Ranks.TIERS.size() - 1, -1, -1):
			chart.add_child(_make_tier(index))
	else:
		for index in Ranks.TIERS.size():
			chart.add_child(_make_pedestal(index))


func _draw_compact_track(chart: Control) -> void:
	var stroke := Color(UITheme.COLOR_GOLD, 0.76)
	var count: int = Ranks.TIERS.size()
	var start := Vector2(16, ROW_HEIGHT * 0.5)
	var end := Vector2(16, ROW_HEIGHT * (count - 0.5))
	chart.draw_line(start, end, stroke, 1.5, true)
	for index in count:
		var point := Vector2(start.x, ROW_HEIGHT * (count - index - 0.5))
		chart.draw_circle(point, 4.5 if index == _current else 2.5, stroke, true, -1.0, true)


func _make_pedestal(index: int) -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_END
	column.add_theme_constant_override("separation", 0)

	var selected := index == _current
	var accent: Color = METALS[index]
	var surface := UITheme.Tokens.PANEL_DARK
	var top_color := surface.lerp(accent, 0.25 if selected else 0.14)
	var side_color := top_color.darkened(0.16 if UITheme.Tokens.light_mode else 0.32)
	var rim := accent if selected else side_color.lerp(accent, 0.48)
	var border_width := 2 if selected else 1

	var pedestal := PanelContainer.new()
	var pedestal_style := UITheme.panel_style(side_color, rim, border_width, 4)
	pedestal_style.set_content_margin_all(0)
	pedestal_style.content_margin_bottom = border_width
	pedestal.add_theme_stylebox_override("panel", pedestal_style)
	column.add_child(pedestal)

	var faces := VBoxContainer.new()
	faces.add_theme_constant_override("separation", 0)
	pedestal.add_child(faces)

	var top := PanelContainer.new()
	var top_style := UITheme.panel_style(top_color, rim, border_width, 4)
	top_style.corner_radius_bottom_left = 5
	top_style.corner_radius_bottom_right = 5
	top_style.set_content_margin_all(7 + border_width)
	top_style.content_margin_bottom = 7
	top.add_theme_stylebox_override("panel", top_style)
	faces.add_child(top)
	top.add_child(_make_tier(index))

	var side := Control.new()
	side.custom_minimum_size.y = STEP_BASE + STEP_HEIGHT * index
	faces.add_child(side)
	return column


func _make_tier(index: int) -> Control:
	var tier: Dictionary = Ranks.TIERS[index]
	var selected := index == _current
	var contents: BoxContainer = HBoxContainer.new() if _compact else VBoxContainer.new()
	contents.add_theme_constant_override("separation", 8 if _compact else 3)
	contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _compact:
		contents.custom_minimum_size.y = ROW_HEIGHT
		var gutter := Control.new()
		gutter.custom_minimum_size.x = 27
		contents.add_child(gutter)
	else:
		contents.alignment = BoxContainer.ALIGNMENT_END

	var badge := TextureRect.new()
	badge.texture = tier.badge
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.custom_minimum_size = Vector2(48, 48) if _compact else Vector2(72, 89)
	contents.add_child(badge)
	var name := _add_label(contents, Locale.t("matchmaking.rank_" + str(tier.id)), 18)
	UITheme.apply_title(name, 18)
	if _compact:
		name.custom_minimum_size.x = 108
	else:
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var minimum := int(tier.minimum)
	var score := Locale.t("matchmaking.ladder_range", [minimum, int(Ranks.TIERS[index + 1].minimum) - 1]) \
		if index + 1 < Ranks.TIERS.size() else Locale.t("matchmaking.ladder_top", [minimum])
	var score_label := _add_label(contents, score, 14)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _compact:
		score_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if selected:
		var marker := _add_label(contents, Locale.t("matchmaking.ladder_current"), 12)
		marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		marker.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
		if _compact:
			marker.custom_minimum_size.x = 84
	else:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(84, 0) if _compact else Vector2(0, 19)
		contents.add_child(spacer)

	return contents


func _add_label(parent: Control, value: String, font_size: int, muted := false) -> Label:
	var label := Label.new()
	label.text = value
	UITheme.apply_label(label, muted)
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label
