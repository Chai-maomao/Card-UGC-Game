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
	cards[0].art_path = CardArtwork.NORMAL
	cards[1].art_path = CardArtwork.DAMAGED
	var screen = load("res://MyCards.tscn").instantiate()
	add_child(screen)
	await settle()
	await _check_deck_cover(screen, source, cards[1])
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
	var import_button = button(screen.top_bar,Locale.t("share.import_append"))
	var export_deck_button = button(screen.top_bar,Locale.t("share.export_deck"))
	var export_button = button(screen.top_bar,Locale.t("share.export_selected"))
	var delete_button = button(screen.action_bar,Locale.t("mycards.delete_selected"))
	assert(import_button.get_index()+1==export_deck_button.get_index() and export_deck_button.get_index()+1==export_button.get_index(),"deck file actions must be together")
	assert(export_button.disabled,"export selected must require a selection")
	await click(export_deck_button.get_global_rect().get_center())
	var package: Dictionary = JSON.parse_string(screen.pending_export_text)
	assert(package.type=="deck" and package.deck.name==source.name and package.cards.size()==4)
	assert(UIMotion.close_top_popup())
	await settle()
	for index in range(2):
		var ui: Control = screen.card_grid.get_child(index).get_child(0)
		await click(ui.get_global_rect().get_center())
	assert(screen.selected_instance_ids.size()==2)
	await click(export_button.get_global_rect().get_center())
	package = JSON.parse_string(screen.pending_export_text)
	assert(package.type=="cards" and not package.has("deck") and package.cards.size()==2)
	assert(UIMotion.close_top_popup())
	await settle()
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
	assert(PlayerData.get_deck(source.id).get("cover_instance_id", "").is_empty(),
		"removing the chosen card must restore the automatic cover")
	screen._show_deck_manager()
	await settle()
	screen._delete_deck(source.id)
	await settle()
	panel = screen.find_child("CollectionConfirmPanel",true,false)
	assert(panel.size.y<220)
	await capture("delete-deck-compact")
	await click(button(panel,Locale.t("common.cancel")).get_global_rect().get_center())
	await _check_copy_conflicts(screen)
	screen.queue_free()
	await settle()
	print("TEST_MY_CARDS_BATCH_DELETE_OK")
	get_tree().quit(0)

func _check_copy_conflicts(screen: Control) -> void:
	var art := CardData.new("卡图冲突", 1, 4, 1)
	art.art_path = CardArtwork.NORMAL
	var stats := CardData.new("数值冲突", 1, 4, 1)
	var same := CardData.new("重复卡", 1, 4, 1)
	var target := PlayerData.create_deck("复制目标", [art, stats, same])
	var incoming_art := art.duplicate_card()
	incoming_art.art_path = CardArtwork.DAMAGED
	var incoming_stats := CardData.new(stats.card_name, 1, 4, 3)
	var source := PlayerData.create_deck("复制来源", [incoming_art, incoming_stats, same, CardData.new("新卡", 2, 4, 1)])
	var originals := PlayerData.get_cards_for_deck(target.id).duplicate()
	var saved := FileAccess.get_file_as_bytes(PlayerData.save_path)
	screen._show_deck_cards(source.id)
	await settle()
	for slot in screen.card_grid.get_children():
		var card_view: Control = slot.get_child(0)
		await click(card_view.get_global_rect().get_center())
	assert(screen.selected_instance_ids.size() == 4)
	for cancel in [true, false]:
		await click(button(screen.action_bar, Locale.t("deck.copy_to")).get_global_rect().get_center())
		await settle()
		var picker := UIMotion.top_popup()
		await click(button(picker, target.name).get_global_rect().get_center())
		await click(button(picker, Locale.t("battle.confirm")).get_global_rect().get_center())
		await settle()
		var first := UIMotion.top_popup()
		var first_panel_count := first.get_children().filter(func(node): return node is Panel).size()
		assert(first_panel_count > 1, "multiple conflicts must appear as a stack")
		var previews := first.find_children("*", "Control", true, false).filter(func(node): return node.get("current_card_data") is CardData)
		assert(previews.size() == 2 and previews[0].current_card_data.art_path == CardArtwork.NORMAL
			and previews[1].current_card_data.art_path == CardArtwork.DAMAGED, "an art-only change must show both arts in the conflict dialog")
		var actions := first.find_children("*", "Button", true, false).map(func(node): return node.text)
		assert(actions.has(Locale.t("share.overwrite")) and not actions.has(Locale.t("share.rename_local")))
		if not cancel:
			await capture("copy-conflict-stack")
		await click(button(first, Locale.t("share.rename_incoming")).get_global_rect().get_center())
		await settle()
		var second := UIMotion.top_popup()
		assert(second != null and second != first, "the second conflict needs its own prompt")
		assert(FileAccess.get_file_as_bytes(PlayerData.save_path) == saved, "resolving one dialog must not write a partial copy")
		if cancel:
			await click(button(second, Locale.t("common.cancel")).get_global_rect().get_center())
			await settle()
			assert(FileAccess.get_file_as_bytes(PlayerData.save_path) == saved)
			continue
		await click(button(second, Locale.t("share.overwrite")).get_global_rect().get_center())
		await settle()
		var cards := PlayerData.get_cards_for_deck(target.id)
		assert(cards.size() == 5, "the batch must add the renamed and the new cards, and skip the identical one")
		assert(PlayerData.find_deck_card(target.id, originals[0].instance_id).art_path == CardArtwork.NORMAL)
		assert(PlayerData.find_deck_card(target.id, originals[1].instance_id).base_atk == 3)
		assert(cards.any(func(card): return card.card_name == "卡图冲突 2" and card.art_path == CardArtwork.DAMAGED))
		assert(PlayerData.get_cards_for_deck(source.id)[0].card_name == incoming_art.card_name)

func _check_deck_cover(screen: Control, deck: Dictionary, chosen: CardData) -> void:
	var tile: Control
	for candidate in screen.card_grid.get_children():
		var labels: Array[Node] = candidate.find_children("*", "Label", true, false)
		if labels.any(func(label): return label.text == deck.name):
			tile = candidate
			break
	assert(tile != null)
	var cover: TextureRect = tile.find_child("DeckCover", true, false)
	assert(cover.texture.resource_path == CardArtwork.NORMAL)
	var more: MenuButton = tile.find_children("*", "MenuButton", true, false)[0]
	screen.scroll_container.ensure_control_visible(more)
	await settle()
	await click(more.get_global_rect().get_center())
	var menu := more.get_popup()
	assert(menu.visible)
	await click(Vector2(menu.position) + Vector2(menu.size) * Vector2(0.5, 0.34))
	await settle()
	var dialog := UIMotion.top_popup()
	assert(dialog != null and dialog.heading == Locale.t("deck.set_cover") and dialog.cards.size() == deck.cards.size())
	var option: Control = dialog.selection_overlays[1]
	await click(option.get_global_rect().get_center())
	await click(dialog.confirm_button.get_global_rect().get_center())
	await settle()
	assert(cover.texture.resource_path == CardArtwork.DAMAGED, "the deck tile must display the chosen artwork")
	PlayerData.load_library()
	assert(PlayerData.get_deck(deck.id).cover_instance_id == chosen.instance_id)
	assert(CardArtwork.deck_cover(PlayerData.get_deck(deck.id)).resource_path == CardArtwork.DAMAGED)
	await capture("deck-cover-selected")

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
