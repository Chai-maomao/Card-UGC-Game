extends "res://TestTabletop3DVisual.gd"
func _enter_tree() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS,true)
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)
func _verify() -> void:
	await _click(Vector2(5,5))
	await get_tree().create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	var before := get_viewport().get_texture().get_image()
	before.save_png("res://artifacts/hand-overlap-20261115/hud-turn-before.png")
	var fill_samples: Array[PackedColorArray] = []
	var hp_values: Array[float] = []
	for hud in [battle.enemy_status_hud,battle.player_status_hud]:
		var bar := hud.get_node("Margin/Content/HpBar") as ProgressBar
		fill_samples.append(_sample_fill(bar, before))
		hp_values.append(bar.value)
	var previous_player: int = battle.game.current_player
	await _click(_center(battle.end_turn_button))
	var deadline := Time.get_ticks_msec()+6000
	while (battle.game.current_player==previous_player or battle._turn_ending) and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
	assert(battle.game.current_player!=previous_player,"real end-turn input must switch players")
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var after := get_viewport().get_texture().get_image()
	after.save_png("res://artifacts/hand-overlap-20261115/hud-turn-after.png")
	var index := 0
	for hud in [battle.enemy_status_hud,battle.player_status_hud]:
		var bar := hud.get_node("Margin/Content/HpBar") as ProgressBar
		assert(is_equal_approx(bar.value, hp_values[index]), "end turn must preserve undamaged player HP")
		assert(_sample_fill(bar, after) == fill_samples[index],
				"the solid fill color must remain stable when turn ownership changes")
		index+=1
	battle.queue_free()
	await get_tree().process_frame
	print("TEST_HUD_TURN_STYLE_VISUAL_OK")
	get_tree().quit()

func _sample_fill(bar: ProgressBar, image: Image) -> PackedColorArray:
	var rect := bar.get_global_rect()
	var scale_factor := Vector2(image.get_size())/get_viewport().get_visible_rect().size
	var colors := PackedColorArray()
	# Border antialiasing can sample the changing table underneath the HUD.
	for portion in [0.15, 0.5, 0.85]:
		var point := Vector2i((rect.position + rect.size * Vector2(portion, 0.5)) * scale_factor)
		colors.append(image.get_pixelv(point))
	return colors
