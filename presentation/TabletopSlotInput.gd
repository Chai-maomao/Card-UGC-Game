extends Control
const Preview = preload("res://presentation/TabletopDragPreview.gd")

var battle: Node
var slot: Control
var opposing := false
var index := 0

var dragging := false
var pressed_here := false

func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		battle.tabletop_slot_clicked(opposing,index)
		accept_event()
		return
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT: return
	if event.pressed:
		pressed_here = true
		dragging = false
	elif pressed_here:
		pressed_here = false
		if not dragging and not get_viewport().gui_is_dragging():
			battle.tabletop_slot_clicked(opposing,index)
	accept_event()

func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("card_data") is CardData

func _drop_data(_at: Vector2, data: Variant) -> void:
	slot.card_dropped_here.emit(data.card_data,data.get("card_ui"))

func _get_drag_data(at: Vector2) -> Variant:
	dragging = true
	battle.tabletop_selected_hand = null
	if is_instance_valid(battle.card_inspector): battle.card_inspector.hide()
	if opposing or not battle.is_my_turn() or slot.current_card_data == null: return null
	var source: Control = slot.current_card_ui
	if source != null:
		set_drag_preview(Preview.make(slot.current_card_data,at))
	return {"card_data":slot.current_card_data,"card_ui":null}

func _ready() -> void:
	set_meta("suppress_hover_hint",true)
	focus_entered.connect(func(): battle.tabletop.hover(index+(5 if opposing else 0),true))
	focus_exited.connect(func(): battle.tabletop.hover(index+(5 if opposing else 0),false))
