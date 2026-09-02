extends Node

const MenuScene = preload("res://MainMenu.tscn")

var failures: Array[String] = []


func _ready() -> void:
	NetworkManager.use_isolated_session_storage("menu-resume-ux")
	NetworkManager.clear_room_session()
	NetworkManager.configure_lan_session("127.0.0.1", 5499, 2, "TEST-MENU-RESUME")
	NetworkManager.mark_match_started()
	var menu = MenuScene.instantiate()
	add_child(menu)
	await get_tree().process_frame
	var start := menu.start_battle_btn as Button
	_assert(not menu.resume_battle_btn.visible and not menu.tutorial_btn.visible and not menu.online_btn.visible,
			"battle-related actions must not remain as separate home-page buttons")
	_assert(start.text == Locale.t("menu.battle_entry_resume"), "unified battle entry must expose resumable-match state")
	menu._show_battle_hub_popup()
	await get_tree().process_frame
	var resume := menu.battle_hub_resume_button as Button
	_assert(resume != null and resume.visible, "valid interrupted session must appear first in the battle hub")
	_assert(resume.has_theme_stylebox_override("normal"), "resume button must use the shared button theme")
	_assert(resume.tooltip_text == Locale.t("menu.resume_hint"), "resume button must explain its purpose")
	_assert(Locale.t("battle.command_sending") == Locale.t("battle.waiting"), "network command UI must use player-facing waiting copy")
	_assert(Locale.t("battle.command_received") == Locale.t("battle.waiting"), "network receipts must not expose implementation details")
	# Allows a real windowed inspection without touching the player's actual
	# resume file. The normal automated run continues through every assertion.
	if OS.get_cmdline_user_args().has("--visual-audit"):
		return
	menu._begin_saved_match_reconnect(resume)
	_assert(NetworkManager._reconnect_active, "resume button must enter the current saved-session reconnect loop")
	_assert(resume.disabled, "resume button must prevent duplicate reconnect attempts while running")
	NetworkManager.close_connection()
	menu.queue_free()
	NetworkManager.clear_room_session()
	NetworkManager.use_isolated_session_storage("")
	if failures.is_empty():
		print("TEST_MENU_RECONNECT_UX_OK")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("TEST_MENU_RECONNECT_UX_FAILED: %s" % failure)
		get_tree().quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
