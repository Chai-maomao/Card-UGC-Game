extends Node

func _ready() -> void:
	Locale.set_language("zh")
	await pause()
	get_tree().current_scene = null
	assert(get_tree().change_scene_to_file("res://MainMenu.tscn") == OK)
	await get_tree().scene_changed
	get_tree().current_scene._workshop_button.pressed.emit()
	await get_tree().scene_changed
	var screen = get_tree().current_scene
	assert(screen.scene_file_path == "res://Workshop.tscn")
	var deadline := Time.get_ticks_msec() + 3000
	while screen._progress.visible and Time.get_ticks_msec() < deadline:
		await pause()
	assert(not screen._progress.visible and not screen._empty.visible and screen._items.get_child_count() == 7,
		"entering from the main menu must show the bundled packs even with an empty public catalog")
	assert(screen._offset == 0)
	await _verify_local_packs(screen)
	screen._upload_pressed()
	await pause()
	var login = screen.find_children("*","ConfirmationDialog",true,false)[0]
	var register = login.find_children("RegisterTab","Button",true,false)[0]
	register.set_pressed_no_signal(true)
	register.pressed.emit()
	login.find_children("UsernameInput","LineEdit",true,false)[0].text = "ui_player"
	login.find_children("PasswordInput","LineEdit",true,false)[0].text = "ui-test-password-2026"
	login.find_children("InviteCodeInput","LineEdit",true,false)[0].text = "friend-test-invite"
	login.find_children("RememberLogin","CheckButton",true,false)[0].set_pressed_no_signal(true)
	login.get_ok_button().pressed.emit()
	var upload
	for _i in range(80):
		await pause()
		for popup in screen.find_children("*","ConfirmationDialog",true,false):
			if popup.find_children("PackNameInput","LineEdit",true,false).size() > 0: upload = popup
		if upload != null: break
	assert(upload != null,"successful login must continue the upload action")
	assert(FileAccess.file_exists("user://workshop_session.cfg"))
	upload.find_children("PackNameInput","LineEdit",true,false)[0].text = "UI 联调卡包"
	upload.find_children("PackDescriptionInput","TextEdit",true,false)[0].text = "经过游戏表单上传的卡包。"
	upload.get_ok_button().pressed.emit()
	await pause()
	var before: Dictionary = await screen.client.browse("","new",0,true)
	assert(before.items.is_empty(),"upload needs explicit permission confirmation")
	upload.find_children("RightsConfirmation","CheckButton",true,false)[0].set_pressed_no_signal(true)
	upload.get_ok_button().pressed.emit()
	for _i in range(80):
		await pause()
		if screen._mine and not screen._loading and screen._offset == 1: break
	assert(screen._mine and screen._offset == 1)
	var mine: Dictionary = await screen.client.browse("","new",0,true)
	assert(mine.items.size() == 1 and mine.items[0].status == "pending")
	assert(not mine.items[0].preview.cover.is_empty())
	var public: Dictionary = await screen.client.browse("","new",0,false)
	assert(public.items.is_empty(),"unreviewed uploads must stay private")
	var old_count := PlayerData.deck_library.size()
	var open := screen._items.find_children("ViewWorkshopPack", "Button", true, false)[0] as Button
	await screen._view_package({"id": "0".repeat(32)})
	assert(not open.disabled and screen._status.visible and screen._status.text != "正在下载…", "a missing package must show its error and allow retry")
	var stalled_at := Time.get_ticks_msec()
	await screen._view_package({"id": "2".repeat(32)})
	assert(Time.get_ticks_msec() - stalled_at < 12500, "a stalled download must time out before the server finishes")
	assert(screen._status.visible and screen._status.text == "下载超时，请重试", "download timeout must be shown explicitly")
	assert(not open.disabled and not screen._search_button.disabled, "download timeout must allow retrying and searching")
	for index in range(3):
		open.grab_focus()
		open.pressed.emit()
		assert(open.disabled and screen._search_button.disabled, "view and search must wait for the current package")
		open.pressed.emit()
		screen._search.text_submitted.emit("")
		assert(screen._status.text == "正在下载…", "a second request must not overwrite the in-progress status")
		var preview: ConfirmationDialog
		for attempt in range(80):
			await pause()
			var previews: Array[Node] = screen.find_children("*", "ConfirmationDialog", true, false)
			if previews.size() == 1:
				preview = previews[0]
				break
		assert(preview != null and is_instance_valid(open) and not open.disabled, "the package must open and the catalog must remain usable")
		if index < 2:
			preview.canceled.emit()
			await pause()
		else:
			preview.get_ok_button().pressed.emit()
	await pause()
	assert(PlayerData.deck_library.size() == old_count+1)

	WorkshopClient.token = ""
	WorkshopClient.account_name = ""
	var reload := WorkshopClient.new()
	add_child(reload)
	var restored := await reload.restore_session()
	assert(restored.get("ok",false) and reload.display_name() == "ui_player")
	var second := WorkshopClient.new()
	add_child(second)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--workshop-other-origin="): second.origin = arg.trim_prefix("--workshop-other-origin=")
	var observed := await second.request_api("/v1/header_probe")
	assert(observed.get("ok",false))
	assert(not observed.sent_token,"a saved login must never be sent to another server")
	var signout := await reload.sign_out()
	assert(signout.get("ok",false))
	assert(not FileAccess.file_exists("user://workshop_session.cfg"))
	assert(not reload.authenticated())
	second.queue_free()
	reload.queue_free()
	var elapsed := await _back_during_download(screen)
	assert(get_tree().current_scene.scene_file_path == "res://MainMenu.tscn")
	assert(elapsed < 2000, "Back must finish before the stalled download")
	await get_tree().create_timer(0.3).timeout
	assert(UIMotion._overlay.color.a < 0.01, "the menu must finish fading in")
	print("TEST_WORKSHOP_UI_FLOW_OK")
	get_tree().quit(0)


func _back_during_download(screen) -> int:
	screen._view_package({"id": "1".repeat(32)})
	var request: HTTPRequest = screen.client.get_child(0)
	var deadline := Time.get_ticks_msec() + 2000
	while request.get_http_client_status() != HTTPClient.STATUS_BODY and Time.get_ticks_msec() < deadline:
		await pause()
	assert(request.get_http_client_status() == HTTPClient.STATUS_BODY, "slow download must start before going back")
	var started := Time.get_ticks_msec()
	for button in screen.get_children():
		if button is Button and button.text == "返回":
			button.pressed.emit()
			break
	await get_tree().scene_changed
	return Time.get_ticks_msec() - started


func _verify_local_packs(screen) -> void:
	var origin: String = screen.client.origin
	screen.client.origin = ""
	screen._search.text = "篮球"
	screen._reload()
	var buttons: Array[Node] = screen._items.find_children("ViewWorkshopPack", "Button", true, false)
	assert(buttons.size() == 1, "offline search must find the bundled basketball pack")
	buttons[0].pressed.emit()
	var previews: Array[Node] = screen.find_children("*", "ConfirmationDialog", false, false)
	assert(previews.size() == 1 and previews[0].title == "篮球", "bundled pack must open without a server")
	assert(previews[0]._cards.size() == 14)
	var before := PlayerData.deck_library.size()
	previews[0].get_ok_button().pressed.emit()
	await pause()
	assert(PlayerData.deck_library.size() == before + 1 and PlayerData.deck_library.back().name == "篮球",
		"bundled pack must import as a new deck")
	screen.client.origin = origin
	screen._search.clear()
	screen._reload()
	while screen._loading:
		await pause()


func pause():await get_tree().create_timer(0.04).timeout
