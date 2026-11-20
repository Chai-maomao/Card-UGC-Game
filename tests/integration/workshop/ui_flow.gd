extends Node

func _ready() -> void:
	Locale.set_language("zh")
	var screen = load("res://Workshop.tscn").instantiate()
	add_child(screen)
	await pause()
	while screen._loading: await pause()
	assert(screen._offset == 0)
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
	await screen._view_package(mine.items[0])
	await pause()
	var preview = screen.find_children("*","ConfirmationDialog",true,false)[0]
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
	screen.queue_free()
	await pause()
	print("TEST_WORKSHOP_UI_FLOW_OK")
	get_tree().quit(0)
func pause():await get_tree().create_timer(0.04).timeout
