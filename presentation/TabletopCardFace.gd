extends Control
const CardScene = preload("res://CardUI.tscn")
var card: CardData
var view: Control
var fingerprint := ""
var shown_attack := 0

func bind(value: CardData, _opposing: bool) -> void:
	var signature := JSON.stringify(PlayerData.serialize_card(value))+str(value.has_attacked)+Locale.language
	if signature == fingerprint: return
	fingerprint = signature
	card = value
	shown_attack = value.effective_atk()
	if view == null:
		view = CardScene.instantiate()
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(view)
		view.set_battle_layout_preview(true)
		view.set_battle_drag_enabled(false)
		view.apply_ui_scale(3.2)
	view.set_card(value)
	view.set_battle_layout_preview(true)
	view.apply_ui_scale(3.2)
