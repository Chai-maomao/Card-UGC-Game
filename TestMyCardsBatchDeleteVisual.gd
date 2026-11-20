extends Node
func _enter_tree() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS,true)
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)

func _ready() -> void:
	get_window().mode=Window.MODE_WINDOWED
	get_window().size=Vector2i(1280,720)
	Locale.set_language("zh")
	var source := PlayerData.create_deck("删除测试",CardDatabase.playtest_deck().slice(0,4))
	var other := PlayerData.create_deck("保留测试",CardDatabase.playtest_deck().slice(0,3))
	var cards: Array = PlayerData.get_cards_for_deck(source.id).duplicate()
	var screen = load("res://MyCards.tscn").instantiate()
	add_child(screen)
	await settle()
	screen._show_deck_cards(source.id)
	await settle()
	assert(button(screen.action_bar,Locale.t("deck.copy_to")).get_node_or_null("KeywordText")==null,"Copy to Deck is an ordinary menu button, not the Copy effect")
	await capture("copy-to-deck-plain")
	screen._on_delete_card(cards[0].instance_id)
	await settle()
	var panel := screen.find_child("CollectionConfirmPanel",true,false) as PanelContainer
	assert(panel.size.y<200,"confirmation must fit its content")
	await capture("delete-single-compact")
	await click(button(panel,Locale.t("common.cancel")).get_global_rect().get_center())
	await settle()
	assert(PlayerData.get_cards_for_deck(source.id).size()==4)
	var export_button = button(screen.action_bar,Locale.t("share.export_selected"))
	var delete_button = button(screen.action_bar,Locale.t("mycards.delete_selected"))
	assert(delete_button.get_index()==export_button.get_index()+1,"delete selected must sit beside export selected")
	for index in range(2):
		var ui: Control = screen.card_grid.get_child(index).get_child(0)
		await click(ui.get_global_rect().get_center())
	assert(screen.selected_instance_ids.size()==2)
	await click(delete_button.get_global_rect().get_center())
	await settle()
	panel = screen.find_child("CollectionConfirmPanel",true,false)
	await capture("delete-selected-compact")
	await click(button(panel,Locale.t("common.cancel")).get_global_rect().get_center())
	await settle()
	assert(PlayerData.get_cards_for_deck(source.id).size()==4)
	await click(delete_button.get_global_rect().get_center())
	await settle()
	panel = screen.find_child("CollectionConfirmPanel",true,false)
	await click(button(panel,Locale.t("common.confirm")).get_global_rect().get_center())
	await settle()
	assert(PlayerData.get_cards_for_deck(source.id).size()==2)
	assert(PlayerData.find_deck_card(source.id,cards[0].instance_id)==null and PlayerData.find_deck_card(source.id,cards[1].instance_id)==null)
	assert(PlayerData.get_cards_for_deck(other.id).size()==3,"batch delete must leave other decks unchanged")
	var saved := FileAccess.get_file_as_string(PlayerData.save_path)
	assert(not saved.contains(cards[0].instance_id) and not saved.contains(cards[1].instance_id),"deleted instances must be removed from saved data")
	screen._show_deck_manager()
	await settle()
	screen._delete_deck(source.id)
	await settle()
	panel = screen.find_child("CollectionConfirmPanel",true,false)
	assert(panel.size.y<220)
	await capture("delete-deck-compact")
	await click(button(panel,Locale.t("common.cancel")).get_global_rect().get_center())
	screen.queue_free()
	await settle()
	print("TEST_MY_CARDS_BATCH_DELETE_OK")
	get_tree().quit(0)
func button(root: Node,text: String):
	for candidate in root.find_children("*","Button",true,false):
		if candidate.text==text:return candidate
	assert(false,"button not found: "+text)
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
