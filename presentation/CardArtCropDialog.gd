extends CanvasLayer

class CropView extends Control:
	var image: Image
	var face: Control
	var center := Vector2(0.5,0.5)
	var zoom := 1.0
	var dragging := false
	var last_pointer := Vector2.ZERO
	const ART := Rect2(32,93,320,303)
	func source_rect() -> Rect2i:
		var dimensions := Vector2(image.get_size())
		var fit := maxf(ART.size.x/dimensions.x,ART.size.y/dimensions.y)*zoom
		var span := ART.size/fit
		var origin := (center*dimensions-span*0.5).clamp(Vector2.ZERO,dimensions-span)
		center = (origin+span*0.5)/dimensions
		return Rect2i(Vector2i(origin),Vector2i(span).max(Vector2i.ONE))
	func refresh() -> void:
		var preview := image.get_region(source_rect())
		preview.resize(320,303,Image.INTERPOLATE_BILINEAR)
		face.art = ImageTexture.create_from_image(preview)
		face.queue_redraw()
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed and ART.has_point(event.position)
			last_pointer = event.position
			accept_event()
		elif event is InputEventMouseMotion and dragging:
			var fit := maxf(ART.size.x/image.get_width(),ART.size.y/image.get_height())*zoom
			center -= (event.position-last_pointer)/fit/Vector2(image.get_size())
			last_pointer = event.position
			refresh()
			accept_event()

var source_image: Image
var preview_card: CardData
var on_saved: Callable
var crop_view: CropView
var _error: Label

func _ready() -> void:
	layer = 150
	var backdrop := ColorRect.new()
	UITheme.apply_overlay(backdrop)
	add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	UITheme.apply_popup_frame(panel, "dark", false)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,20)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",12)
	margin.add_child(box)
	var title := Label.new()
	title.text = Locale.t("editor.crop_title")
	UITheme.apply_title(title,24)
	box.add_child(title)
	var holder := Control.new()
	var scale_value := minf(0.78,(get_viewport().get_visible_rect().size.y-200)/528.0)
	holder.custom_minimum_size = Vector2(384,528)*scale_value
	box.add_child(holder)
	crop_view = CropView.new()
	crop_view.name = "CropView"
	crop_view.size = Vector2(384,528)
	crop_view.scale = Vector2.ONE*scale_value
	crop_view.mouse_default_cursor_shape = Control.CURSOR_DRAG
	crop_view.image = source_image
	holder.add_child(crop_view)
	var face := preload("res://presentation/ClassicBattleCardFace.gd").new()
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.size = Vector2(384,528)
	crop_view.add_child(face)
	face.bind(preview_card,false)
	crop_view.face = face
	crop_view.refresh()
	var zoom_label := Label.new()
	zoom_label.text = Locale.t("editor.crop_zoom")
	UITheme.apply_label(zoom_label)
	box.add_child(zoom_label)
	var zoom := HSlider.new()
	zoom.min_value = 1
	zoom.max_value = 4
	zoom.step = 0.01
	zoom.value = 1
	box.add_child(zoom)
	zoom.value_changed.connect(func(value): crop_view.zoom=value; crop_view.refresh())
	_error = Label.new()
	_error.text = Locale.t("editor.art_save_failed")
	_error.hide()
	UITheme.apply_label(_error)
	box.add_child(_error)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation",12)
	box.add_child(buttons)
	for action in ["cancel","confirm"]:
		var button := Button.new()
		button.text = Locale.t("common."+action) if action == "cancel" else Locale.t("battle.confirm")
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.apply_button(button,"primary" if action == "confirm" else "secondary")
		buttons.add_child(button)
		button.pressed.connect(_confirm if action == "confirm" else queue_free)
	set_meta("popup_close",queue_free)

func _confirm() -> void:
	var cropped := source_image.get_region(crop_view.source_rect())
	if cropped.get_width()>1024: cropped.resize(1024,roundi(1024.0*303/320),Image.INTERPOLATE_LANCZOS)
	var bytes := cropped.save_png_to_buffer()
	while bytes.size()>PlayerData.MAX_ART_BYTES and cropped.get_width()>64:
		var width := maxi(64,int(cropped.get_width()*0.8))
		cropped.resize(width,maxi(1,roundi(width*303.0/320)),Image.INTERPOLATE_LANCZOS)
		bytes = cropped.save_png_to_buffer()
	if bytes.is_empty():
		_error.show()
		return
	DirAccess.make_dir_recursive_absolute("user://arts")
	var path := "user://arts/crop-"+Crypto.new().generate_random_bytes(8).hex_encode()+".png"
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null:
		_error.show()
		return
	file.store_buffer(bytes)
	var error := file.get_error()
	file.close()
	if error != OK:
		_error.show()
		return
	if on_saved.is_valid(): on_saved.call(path)
	queue_free()
