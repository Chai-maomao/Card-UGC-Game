extends Node


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var target := "res://MainMenu.tscn"
	if args.has("--server") or args.has("--room-server"):
		target = "res://server.tscn"
	call_deferred("_open_target", target)


func _open_target(target: String) -> void:
	var error := get_tree().change_scene_to_file(target)
	if error != OK:
		push_error("Bootstrap could not open %s (error %d)" % [target, error])
		get_tree().quit(1)
