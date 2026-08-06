extends Button

# ============================================
# Battlefield slot — receives cards, forwards signals
# ============================================

signal slot_attack_requested
signal slot_skill1_requested
signal slot_skill2_requested
signal slot_skill3_requested
signal card_dropped_here(card_data, dragging_card_ui)

var card_ui_scene = preload("res://CardUI.tscn")
var current_card_ui = null
var current_card_data: CardData = null
var ui_scale: float = 1.0
var visual_variant: String = "player"


func apply_ui_scale(scale_value: float) -> void:
	ui_scale = scale_value
	custom_minimum_size = Vector2(120, 160) * ui_scale
	size = custom_minimum_size
	if current_card_ui and is_instance_valid(current_card_ui):
		if current_card_ui.has_method("apply_ui_scale"):
			current_card_ui.call("apply_ui_scale", ui_scale)
		current_card_ui.position = Vector2.ZERO


func _ready():
	text = ""
	_refresh_visual()
	apply_ui_scale(ui_scale)


func set_visual_variant(variant: String) -> void:
	visual_variant = variant
	_refresh_visual()


func _refresh_visual() -> void:
	UITheme.apply_slot(self, visual_variant, current_card_data != null)


func set_card(card_data: CardData):
	if card_data != null and card_data == current_card_data and current_card_ui and is_instance_valid(current_card_ui):
		text = ""
		current_card_ui.set_card(card_data)
		apply_ui_scale(ui_scale)
		return

	clear_card()

	if card_data == null:
		text = ""
		_refresh_visual()
		return

	current_card_data = card_data
	text = ""
	var card_ui = card_ui_scene.instantiate()

	# Forward signals from CardUI
	if card_ui.has_signal("attack_requested"):
		card_ui.attack_requested.connect(func(): slot_attack_requested.emit())
	if card_ui.has_signal("skill1_requested"):
		card_ui.skill1_requested.connect(func(): slot_skill1_requested.emit())
	if card_ui.has_signal("skill2_requested"):
		card_ui.skill2_requested.connect(func(): slot_skill2_requested.emit())
	if card_ui.has_signal("skill3_requested"):
		card_ui.skill3_requested.connect(func(): slot_skill3_requested.emit())

	add_child(card_ui)
	card_ui.set_card(card_data)
	current_card_ui = card_ui
	_refresh_visual()
	apply_ui_scale(ui_scale)


func clear_card():
	text = ""
	if current_card_ui and is_instance_valid(current_card_ui):
		current_card_ui.queue_free()
	current_card_ui = null
	current_card_data = null
	_refresh_visual()


func _can_drop_data(_position: Vector2, data) -> bool:
	if typeof(data) != TYPE_DICTIONARY or not data.has("card_data"):
		return false
	return true


func _drop_data(_position: Vector2, data):
	var dragging_card_ui = data["card_ui"]
	var card_data: CardData = data["card_data"] as CardData

	print("Card dropped into slot: %s" % card_data.card_name)
	emit_signal("card_dropped_here", card_data, dragging_card_ui)
