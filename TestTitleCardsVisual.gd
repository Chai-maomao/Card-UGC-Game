extends Node

func _ready() -> void:
	assert(DisplayServer.get_name() != "headless")
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280,720)
	PlayerData.startup_tutorial_pending = false
	AppPreferences.set_value("title_card_ids",[])
	var copied_card: CardData = PlayerData.card_library[0]
	PlayerData.create_deck("展示卡牌副本测试", [copied_card, copied_card])
	var settings = load("res://SettingsMenu.tscn").instantiate()
	add_child(settings)
	await settle()
	settings._show_category("gameplay")
	await settle()
	await click(settings._title_cards_button.get_global_rect().get_center())
	await settle()
	var picker = settings.get_children().filter(func(n): return n.get_script() == preload("res://CardCollectionDialog.gd"))[0]
	for index in range(6):
		await click(picker.selection_overlays[index].get_global_rect().get_center())
	assert(picker.selected_order.size()==5,"the sixth card must be refused")
	await capture("title-card-picker")
	await click(picker.confirm_button.get_global_rect().get_center())
	await settle()
	var ids: Array = AppPreferences.get_value("title_card_ids")
	assert(ids.size()==5)
	var config := ConfigFile.new()
	assert(config.load(AppPreferences.PATH)==OK)
	assert(config.get_value("presentation","title_card_ids")==ids,"selected cards must persist")
	settings.queue_free()
	await settle()
	var menu = load("res://MainMenu.tscn").instantiate()
	add_child(menu)
	await settle()
	assert(menu.tabletop_menu.display_cards.size()==5)
	for index in range(5):
		assert(menu.tabletop_menu.display_cards[index].card_id==ids[index],"menu must show the selected cards in selection order")
	await get_tree().create_timer(0.5).timeout
	await capture("title-five-selected-cards")
	get_window().size=Vector2i(960,540)
	await settle()
	await capture("title-five-selected-cards-960")
	menu.queue_free()
	await settle()
	# Missing/deleted library cards fall back to the default display.
	AppPreferences.set_value("title_card_ids",["deleted-card"])
	menu = load("res://MainMenu.tscn").instantiate()
	add_child(menu)
	await settle()
	assert(menu.tabletop_menu.display_cards.size()==3)
	menu.queue_free()
	await settle()
	# A saved choice for a card with deck copies must restore as one checkmark.
	AppPreferences.set_value("title_card_ids", [])
	settings = load("res://SettingsMenu.tscn").instantiate()
	add_child(settings)
	await settle()
	settings._choose_title_cards()
	await settle()
	picker = settings.get_children().filter(func(n): return n.get_script() == preload("res://CardCollectionDialog.gd"))[0]
	await click(picker.selection_overlays[0].get_global_rect().get_center())
	await click(picker.confirm_button.get_global_rect().get_center())
	await settle()
	assert(AppPreferences.get_value("title_card_ids") == [copied_card.card_id])
	settings._choose_title_cards()
	await settle()
	picker = settings.get_children().filter(func(n): return n.get_script() == preload("res://CardCollectionDialog.gd"))[0]
	var choices: Array = picker.cards.filter(func(card): return card.card_id == copied_card.card_id)
	if choices.size() != 1 or picker.selected_order.size() != 1:
		push_error("One saved display card must have one row and one checkmark, got %d rows and %d checkmarks." % [choices.size(), picker.selected_order.size()])
		get_tree().quit(1)
		return
	var selected_index: int = picker.selected_order[0]
	await click(picker.selection_overlays[selected_index].get_global_rect().get_center())
	assert(picker.selected_order.is_empty(), "one click must clear the saved card")
	assert(not picker.confirm_button.disabled)
	await click(picker.confirm_button.get_global_rect().get_center())
	assert((AppPreferences.get_value("title_card_ids") as Array).is_empty())
	settings.queue_free()
	await settle()
	menu = load("res://MainMenu.tscn").instantiate()
	add_child(menu)
	await settle()
	assert(menu.tabletop_menu.display_cards.size() == 3, "confirming the cleared selection must restore default cards")
	menu.queue_free()
	await settle()
	print("TEST_TITLE_CARDS_VISUAL_OK")
	get_tree().quit(0)

func settle() -> void:
	await get_tree().create_timer(0.4).timeout

func click(point: Vector2) -> void:
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position=point
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=pressed
		event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
		get_viewport().push_input(event,true)
		await get_tree().process_frame

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/"+label+".png")
