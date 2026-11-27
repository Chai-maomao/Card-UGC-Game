extends Node2D

var _scrim: CanvasLayer

func _ready() -> void:
	get_parent().size_changed.connect(queue_redraw)
	get_parent().about_to_popup.connect(queue_redraw)
	get_parent().visibility_changed.connect(_update_scrim)
	if get_parent().has_signal("title_changed"): get_parent().connect("title_changed",queue_redraw)
	queue_redraw()


func _update_scrim() -> void:
	var dialog := get_parent() as AcceptDialog
	if not dialog.visible or not dialog.is_embedded():
		if is_instance_valid(_scrim):
			_scrim.hide()
		return
	if not is_instance_valid(_scrim):
		_scrim = CanvasLayer.new()
		_scrim.layer = 1000
		var shade := ColorRect.new()
		UITheme.apply_overlay(shade)
		shade.color.a = 0.54
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_scrim.add_child(shade)
		dialog.get_parent().get_viewport().add_child(_scrim)
	_scrim.show()


func _exit_tree() -> void:
	if is_instance_valid(_scrim):
		_scrim.queue_free()


func _draw() -> void:
	var dialog := get_parent() as AcceptDialog
	if dialog == null: return
	var font := UITheme.bold_font()
	var text := dialog.title
	var inset := UITheme.DIALOG_INSET
	var width := maxf(1, dialog.size.x - 2 * inset)
	var font_size := 19
	while text.length()>1 and font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>width:
		text = text.left(text.length()-2)+"…"
	draw_string(font, Vector2(inset, 18 + font.get_ascent(font_size)), text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, UITheme.Tokens.TITLE)
	draw_line(Vector2(inset, 52), Vector2(inset + width, 52), Color(UITheme.Tokens.TOOLTIP_BORDER, 0.62))
