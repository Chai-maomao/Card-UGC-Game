extends Control

const TEXT_COLOR := Color("fff0bc")
const ABOVE_OUTLINE := Color("a63730")

var text: String
var _line := TextLine.new()
var _draw_origin: Vector2
var _outline_size: int
var _outline_color: Color


func update(damage: int, preview: Control, hp_bar: ProgressBar, ui_scale: float) -> void:
	text = str(damage)
	var font := UITheme.medium_font()
	var outer_font_size := maxi(10, roundi(11 * ui_scale))
	var inner_font_size := mini(outer_font_size, floori(preview.size.y * 0.8))
	var inner_outline := maxi(2, roundi(3 * ui_scale))
	var fill := hp_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if inner_font_size >= 9 and fill != null:
		_line.clear()
		_line.add_string(text, font, inner_font_size)
		var bounds := _glyph_bounds(inner_outline)
		if bounds.size.x + 2.0 * ui_scale <= preview.size.x and bounds.size.y <= preview.size.y:
			_draw_origin = preview.size * 0.5 - bounds.get_center() - Vector2(0, _line.get_line_ascent())
			_outline_size = inner_outline
			_outline_color = fill.bg_color
			queue_redraw()
			return

	_line.clear()
	_line.add_string(text, font, outer_font_size)
	var line_height := _line.get_size().y
	var top := maxf(2.0, hp_bar.global_position.y - line_height - 5.0)
	_draw_origin = Vector2((preview.size.x - _line.get_line_width()) * 0.5, top + 2.0 - preview.global_position.y)
	_outline_size = maxi(2, roundi(2 * ui_scale))
	_outline_color = ABOVE_OUTLINE
	queue_redraw()


func _glyph_bounds(outline_size: int) -> Rect2:
	var server := TextServerManager.get_primary_interface()
	var bounds := Rect2()
	var advance := 0.0
	# Font line metrics include blank space around the visible digits.
	for glyph in server.shaped_text_get_glyphs(_line.get_rid()):
		var font_rid: RID = glyph.font_rid
		var index: int = glyph.index
		var raster_size := Vector2i(glyph.font_size, outline_size)
		server.font_render_glyph(font_rid, raster_size, index)
		var offset := server.font_get_glyph_offset(font_rid, raster_size, index)
		var glyph_size := server.font_get_glyph_size(font_rid, raster_size, index)
		var rect := Rect2(Vector2(advance, 0) + glyph.offset + offset, glyph_size)
		bounds = rect if not bounds.has_area() else bounds.merge(rect)
		advance += glyph.advance
	return bounds


func _draw() -> void:
	_line.draw_outline(get_canvas_item(), _draw_origin, _outline_size, _outline_color)
	_line.draw(get_canvas_item(), _draw_origin, TEXT_COLOR)
