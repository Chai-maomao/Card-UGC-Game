extends Node


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--release-smoke"):
		var check := preload("res://ReleaseSelfCheck.gd").new()
		get_tree().root.add_child.call_deferred(check)
	var target := _startup_target(OS.get_cmdline_user_args())
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
