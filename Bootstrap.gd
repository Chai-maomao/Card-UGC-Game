extends Node


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--party-server"):
		_listen_for_party(args)
		return
	if args.has("--release-smoke"):
		var check := preload("res://ReleaseSelfCheck.gd").new()
		get_tree().root.add_child.call_deferred(check)
	var target := _startup_target(args)
	call_deferred("_open_target", target)


func _startup_target(args: PackedStringArray) -> String:
	if args.has("--server") or args.has("--room-server"):
		return "res://server.tscn"
	var progress := TutorialProgress.new(PlayerData.tutorial_progress_path)
	var error := progress.initialize_startup(PlayerData.had_saved_library_on_startup)
	PlayerData.startup_tutorial_pending = progress.needs_startup_tutorial()
	if error != OK:
		push_warning("Could not initialize tutorial progress (error %d)" % error)
		PlayerData.startup_tutorial_pending = not PlayerData.had_saved_library_on_startup and not progress.is_finished()
	return "res://MainMenu.tscn"


func _open_target(target: String) -> void:
	UIMotion.replace_scene(target,true)


func _listen_for_party(args: PackedStringArray) -> void:
	var room := NetworkManager.team_room
	var port: int = room.PORT
	var size := 3
	for arg in args:
		if arg.begins_with("--party-port="):
			port = arg.trim_prefix("--party-port=").to_int()
		if arg.begins_with("--party-size="):
			size = arg.trim_prefix("--party-size=").to_int()
	var match_mode := OS.get_environment("CARDEX_MATCHMAKING_MODE")
	var invite := OS.get_environment("CARDEX_PARTY_INVITE")
	var owner := OS.get_environment("CARDEX_PARTY_OWNER")
	var error: Error
	if match_mode.is_empty():
		error = room.host_dedicated(size, port, invite, owner)
	else:
		var ratings: Variant = JSON.parse_string(OS.get_environment("CARDEX_MATCH_RATINGS"))
		error = room.host_matchmade(port, match_mode, {owner: 1, invite: 2},
			OS.get_environment("CARDEX_MATCH_RESULT"), ratings if ratings is Array else [])
	if error != OK:
		push_error("Could not open the party room. Check its size, UDP port and CARDEX_PARTY_INVITE (8–32 hex characters). Error %d." % error)
		get_tree().quit(1)
		return
	print("TEAM_SERVER_LISTENING %d %d" % [port, size])
