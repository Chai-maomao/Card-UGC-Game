extends Control
const Preview = preload("res://presentation/TabletopDragPreview.gd")
var battle: Node
var source: Control
var dragging := false
var pressed_here := false

func _has_point(point: Vector2) -> bool:
	if not is_instance_valid(source) or source.get_meta("tabletop_arriving",false): return false
	var fan = source.get_parent()
	if fan.has_method("card_at_pointer"):
		return fan.card_at_pointer(get_global_transform()*point) == source
	return Rect2(Vector2.ZERO,size).has_point(point)

func _set_hover(enabled: bool) -> void:
	if not is_instance_valid(source) or (enabled and source.get_meta("tabletop_arriving",false)): return
	if enabled and get_viewport().gui_is_dragging(): return
	var fan = source.get_parent()
	if fan.has_method("focus_card"): fan.focus_card(source,enabled)
	battle.tabletop.hover(10+source.get_index(),enabled)
	battle.tabletop_hand_hover(source,enabled)

func _gui_input(event: InputEvent) -> void:
	if not is_instance_valid(source) or source.get_meta("tabletop_arriving",false):
		pressed_here = false
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		battle.tabletop_hand_inspect(source)
		accept_event()
		return
	if event.is_action_pressed("ui_accept"):
		battle.tabletop_hand_clicked(source)
		accept_event()
		return
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT: return
	if event.pressed:
		pressed_here = true
		dragging = false
	elif pressed_here:
		pressed_here = false
		if not dragging and not get_viewport().gui_is_dragging():
			battle.tabletop_hand_clicked(source)
	accept_event()

func _get_drag_data(at: Vector2) -> Variant:
	if not is_instance_valid(source) or source.get_meta("tabletop_arriving",false): return null
	dragging = true
	var fan = source.get_parent()
	if is_instance_valid(fan.focused_card): fan.focus_card(fan.focused_card,false)
	battle.tabletop_selected_hand = null
	if is_instance_valid(battle.card_inspector): battle.card_inspector.hide()
	if not battle.is_my_turn(): return null
	set_drag_preview(Preview.make(source.current_card_data,at))
	return {"card_data":source.current_card_data,"card_ui":source}

func _ready() -> void:
	focus_entered.connect(func(): _set_hover(true))
	focus_exited.connect(func(): _set_hover(false))
	mouse_entered.connect(func(): AppAudio.play_hover(source,true); _set_hover(true))
	mouse_exited.connect(func(): _set_hover(false))
