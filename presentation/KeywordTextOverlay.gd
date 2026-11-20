extends RichTextLabel

# Keep the original control and its plain text API, input and layout ownership.
# Only the displayed text is enriched. No gameplay or saved text is rewritten.
const Words = preload("res://presentation/SkillDescription.gd")
const CLEAR := Color(1,1,1,0)
const BUTTON_COLORS := ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color","font_disabled_color","font_outline_color"]
var original_tint := Color.WHITE
var original_minimum := Vector2.ZERO
var applied_minimum := Vector2(-1,-1)
var button_colors: Dictionary = {}
var _signature: Array = []
var _writing := false

static func watch(control: Control) -> void:
	if control.get_meta("keyword_watched",0)==control.get_instance_id(): return
	control.set_meta("keyword_watched",control.get_instance_id())
	control.set_meta("keyword_refresh_queued",false)
	var reference: WeakRef = weakref(control)
	control.draw.connect(func(): _schedule(reference))
	control.resized.connect(func(): _schedule(reference))
	control.theme_changed.connect(func(): _schedule(reference))
	_schedule(reference)

static func _schedule(reference: WeakRef) -> void:
	var source = reference.get_ref()
	if not is_instance_valid(source) or not source.is_inside_tree(): return
	var overlay = source.get_node_or_null("KeywordText")
	if overlay != null and overlay._writing: return
	if source.get_meta("keyword_refresh_queued",false): return
	source.set_meta("keyword_refresh_queued",true)
	_refresh.call_deferred(reference)

static func _refresh(reference: WeakRef) -> void:
	var source = reference.get_ref()
	if not is_instance_valid(source) or not source.is_inside_tree(): return
	source.set_meta("keyword_refresh_queued",false)
	var overlay = source.get_node_or_null("KeywordText")
	var allowed: bool = not source.get_meta("keyword_literal",false) and not source.has_meta("section_title")
	if str(source.name).to_lower().ends_with("title") or str(source.name).to_lower().ends_with("titlelabel"): allowed=false
	# Authored names and entry fields must retain their exact appearance.
	var ancestor: Node = source
	while ancestor != null:
		if ancestor is LineEdit or ancestor is TextEdit or ancestor is SpinBox or ancestor is OptionButton or ancestor.get_meta("keyword_literal_fields",false): allowed=false;break
		ancestor=ancestor.get_parent()
	if source is Button and (source.icon != null or not source.get_meta("keyword_enabled",false)): allowed=false
	if not allowed or not Words.has_keywords(source.text):
		if overlay != null: overlay._restore(source)
		return
	if overlay == null:
		overlay=load("res://presentation/KeywordTextOverlay.gd").new()
		overlay.name="KeywordText"
		overlay.original_minimum=source.custom_minimum_size
		overlay.original_tint=source.get_meta("keyword_base_tint",source.self_modulate)
		overlay.button_colors=source.get_meta("keyword_base_colors",{}).duplicate(true)
		# Internal child stays outside ordinary label/button discovery and input.
		source.add_child(overlay,false,Node.INTERNAL_MODE_BACK)
	overlay._sync(source)

func _ready() -> void:
	bbcode_enabled=true
	fit_content=false
	scroll_active=false
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	focus_mode=Control.FOCUS_NONE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)

func _restore(source: Control) -> void:
	_writing=true
	if source is Label:
		source.self_modulate=original_tint
	else:
		for key: String in button_colors:
			var previous: Variant=button_colors[key][0]
			if previous == null: source.remove_theme_color_override(key)
			else: source.add_theme_color_override(key,previous)
	if source.custom_minimum_size==applied_minimum: source.custom_minimum_size=original_minimum
	source.remove_child(self)
	queue_free()

func _sync(source: Control) -> void:
	_writing=true
	var is_label := source is Label
	var font: Font=source.get_theme_font("font")
	var pixels: int=source.get_theme_font_size("font_size")
	var ink: Color=source.get_theme_color("font_color")
	var alignment: int=source.horizontal_alignment if is_label else source.alignment
	var wrap: int=source.autowrap_mode if is_label else TextServer.AUTOWRAP_OFF
	var outline: Color=source.get_theme_color("font_outline_color")
	var outline_size: int=source.get_theme_constant("outline_size")
	if is_label:
		var settings: LabelSettings=source.label_settings
		if settings != null:
			if settings.font != null: font=settings.font
			pixels=settings.font_size
			ink=settings.font_color
			outline=settings.outline_color
			outline_size=settings.outline_size
		if source.self_modulate != CLEAR: original_tint=source.self_modulate
		self_modulate=original_tint
		source.set_meta("keyword_base_tint",original_tint)
		source.self_modulate=CLEAR
	else:
		for key: String in BUTTON_COLORS:
			var current: Color=source.get_theme_color(key)
			if current != CLEAR or not button_colors.has(key):
				var previous: Variant=current if source.has_theme_color_override(key) else null
				button_colors[key]=[previous,current]
				source.add_theme_color_override(key,CLEAR)
		source.set_meta("keyword_base_colors",button_colors.duplicate(true))
		var state := "font_color"
		if source.disabled: state="font_disabled_color"
		elif source.is_pressed(): state="font_hover_pressed_color" if source.is_hovered() else "font_pressed_color"
		elif source.is_hovered(): state="font_hover_color"
		elif source.has_focus(): state="font_focus_color"
		ink=button_colors[state][1]
		if source.disabled and source.get_meta("tutorial_disabled_tint",false): ink.a=1.0
		outline=button_colors["font_outline_color"][1]
		# Keywords retain their meaning while unavailable buttons remain subdued.
		modulate=Color(1,1,1,0.45 if source.disabled else 1.0)
	var signature: Array=[source.text,source.size,font,pixels,ink,alignment,wrap,outline,outline_size,source.custom_minimum_size]
	if signature==_signature:
		_writing=false
		return
	add_theme_font_override("normal_font",font)
	add_theme_font_size_override("normal_font_size",pixels)
	add_theme_color_override("default_color",ink)
	add_theme_color_override("font_outline_color",outline)
	add_theme_constant_override("outline_size",outline_size)
	if is_label: add_theme_stylebox_override("normal",source.get_theme_stylebox("normal"))
	autowrap_mode=wrap
	text=_aligned(Words.colored(source.text,pixels,is_label),alignment)
	var content := Rect2(Vector2.ZERO,source.size)
	if not is_label:
		var style: StyleBox=source.get_theme_stylebox("normal")
		content.position=style.get_offset()
		content.size=(source.size-style.get_minimum_size()).max(Vector2.ZERO)
	position=content.position
	size=content.size
	var trimming: bool=source.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING
	if wrap==TextServer.AUTOWRAP_OFF and trimming and get_content_width()>content.size.x:
		var low := 0
		var high: int=source.text.length()
		while low<high:
			var middle: int=(low+high+1)/2
			text=_aligned(Words.colored(source.text.left(middle)+"…",pixels,is_label),alignment)
			if get_content_width()<=content.size.x: low=middle
			else: high=middle-1
		text=_aligned(Words.colored(source.text.left(low)+"…",pixels,is_label),alignment)
	# RichTextLabel's line height includes the icon; centre it on the source face.
	if wrap==TextServer.AUTOWRAP_OFF:
		var block_height: float=get_content_height()
		var vertical: int=source.vertical_alignment if is_label else VERTICAL_ALIGNMENT_CENTER
		if vertical==VERTICAL_ALIGNMENT_CENTER: position.y+=maxf(0,(content.size.y-block_height)*0.5)
		elif vertical==VERTICAL_ALIGNMENT_BOTTOM: position.y+=maxf(0,content.size.y-block_height)
		size.y=maxf(block_height,content.size.y-position.y+content.position.y)
	if source.custom_minimum_size!=applied_minimum: original_minimum=source.custom_minimum_size
	if source.get_parent() is Container:
		var minimum := original_minimum
		if wrap==TextServer.AUTOWRAP_OFF and not trimming:
			minimum.x=maxf(minimum.x,get_content_width()+(source.get_theme_stylebox("normal").get_minimum_size().x if not is_label else 0.0))
		elif wrap!=TextServer.AUTOWRAP_OFF:
			var height: float=get_content_height()
			if is_label and source.max_lines_visible>0:
				height=minf(height,source.get_line_height()*source.max_lines_visible)
			minimum.y=maxf(minimum.y,height)
		applied_minimum=minimum
		source.custom_minimum_size=minimum
	clip_contents=true
	_signature=[source.text,source.size,font,pixels,ink,alignment,wrap,outline,outline_size,source.custom_minimum_size]
	_writing=false

func _aligned(value: String, alignment: int) -> String:
	if alignment==HORIZONTAL_ALIGNMENT_CENTER: return "[center]"+value+"[/center]"
	if alignment==HORIZONTAL_ALIGNMENT_RIGHT: return "[right]"+value+"[/right]"
	return value
