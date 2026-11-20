extends Node

func _ready() -> void:
	var api := WorkshopClient.new()
	add_child(api)
	var refused := await api.sign_in("integration_player", "test-password-20261114", true)
	assert(not refused.get("ok",false) and refused.status_code == 403)
	var auth := await api.sign_in("integration_player", "test-password-20261114", true, "friend-test-invite")
	assert(auth.get("ok",false),str(auth))
	var original_decks := PlayerData.deck_library.size()
	var deck: Dictionary = PlayerData.deck_library[0]
	var original_image := Image.create(8,8,false,Image.FORMAT_RGBA8)
	original_image.fill(Color(0.3,0.7,0.8))
	original_image.save_png("user://workshop-test-art.png")
	original_image.fill(Color(0.8,0.4,0.3))
	original_image.save_png("user://workshop-test-hurt.png")
	deck.cards[0].art_path = "user://workshop-test-art.png"
	deck.cards[0].damaged_art_path = "user://workshop-test-hurt.png"
	var chance := SkillRegistry.make_chance_block(37)
	chance.then_effects = [{"effect":SkillEngine.EFFECT_GAIN_ATTACK,"target":SkillEngine.TARGET_SELF,"value":1}]
	deck.cards[0].skills = [{"skill_name":"概率","trigger":SkillEngine.TRIGGER_ON_ACTIVATE,"effects":[chance]}]
	var package := WorkshopClient.package_for_upload(deck)
	assert(not package.cards[0].art_base64.is_empty())
	assert(not package.cards[0].damaged_art_base64.is_empty())
	assert(not package.cards.is_empty())
	for card in package.cards:
		assert(str(card.get("art_path","")).is_empty())
		assert(str(card.get("damaged_art_path","")).is_empty())
	var upload := await api.request_api("/v1/packages",HTTPClient.METHOD_POST,{"title":"集成测试卡包","description":"实际游戏导出","package":package,"cover":WorkshopClient.cover_for_deck(deck)})
	assert(upload.get("ok",false),str(upload))
	var screen = load("res://Workshop.tscn").instantiate()
	add_child(screen)
	while screen._loading: await get_tree().create_timer(0.02).timeout
	assert(screen._offset == 1)
	var listing := await api.request_api("/v1/packages")
	assert(listing.items.size() == 1)
	await screen._view_package(listing.items[0])
	var dialogs = screen.find_children("*","ConfirmationDialog",true,false)
	assert(dialogs.size() == 1)
	var previews = dialogs[0].find_children("*","Control",true,false)
	var cards := 0
	for control in previews:
		if control.has_method("bind_card"): cards += 1
	assert(cards == package.cards.size())
	dialogs[0]._grid.get_child(1).pressed.emit()
	assert(dialogs[0]._details.get_child(0).text == package.cards[1].name)
	var save_path := PlayerData.save_path
	var previous_deck := PlayerData.current_deck_id
	var saved := FileAccess.get_file_as_bytes(save_path)
	PlayerData.save_path = "user://missing-workshop-import-directory/card_library.json"
	dialogs[0].confirmed.emit()
	PlayerData.save_path = save_path
	assert(PlayerData.deck_library.size() == original_decks and PlayerData.current_deck_id == previous_deck)
	assert(FileAccess.get_file_as_bytes(save_path) == saved)
	assert(screen._status.visible and screen._status.text == Locale.t("share.import_save_failed"))
	await get_tree().process_frame
	await screen._view_package(listing.items[0])
	dialogs = screen.find_children("*","ConfirmationDialog",true,false)
	assert(dialogs.size() == 1)
	dialogs[0].confirmed.emit()
	assert(PlayerData.deck_library.size() == original_decks+1)
	var imported: Dictionary = PlayerData.get_current_deck()
	assert(imported.cards.size() == package.cards.size())
	assert(imported.name == "集成测试卡包")
	assert(FileAccess.get_file_as_bytes(imported.cards[0].art_path) == FileAccess.get_file_as_bytes("user://workshop-test-art.png"))
	assert(FileAccess.get_file_as_bytes(imported.cards[0].damaged_art_path) == FileAccess.get_file_as_bytes("user://workshop-test-hurt.png"))
	assert(SkillRegistry.is_chance_block(imported.cards[0].skills[0].effects[0]))
	assert(int(imported.cards[0].skills[0].effects[0].condition.rhs.value) == 37)
	var logout := await api.request_api("/v1/logout",HTTPClient.METHOD_POST)
	assert(logout.get("ok",false))
	var denied := await api.request_api("/v1/packages",HTTPClient.METHOD_POST,{"title":"必须拒绝","package":package})
	assert(not denied.get("ok",false) and denied.status_code == 401)
	screen.queue_free()
	api.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("TEST_WORKSHOP_GAME_IMPORT_OK")
	get_tree().quit(0)
