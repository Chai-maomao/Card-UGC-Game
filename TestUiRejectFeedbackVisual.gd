extends Node

var pressed := 0

func _ready() -> void:
	await get_tree().create_timer(0.2).timeout
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280,720)
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)
	AppPreferences.set_value("reduced_motion",false)
	var surface := Control.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(surface)
	var box := VBoxContainer.new()
	box.position = Vector2(64,64)
	box.add_theme_constant_override("separation",20)
	surface.add_child(box)
	var disabled := _button(box,"不可用按钮",true)
	var enabled := _button(box,"可用按钮",false)
	var press_disables := _button(box,"按下后禁用",false)
	press_disables.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	press_disables.pressed.connect(func(): press_disables.disabled = true)
	await _settle()
	var original := disabled.position
	await _click(get_viewport(),disabled.get_global_rect().get_center())
	await get_tree().create_timer(0.09).timeout
	assert(disabled.has_node("UnavailableFeedback"),"clicking a real disabled Button must trigger the global hook")
	assert(pressed==0 and disabled.disabled,"feedback must not activate or enable the disabled button")
	assert(not disabled.position.is_equal_approx(original),"disabled button must visibly shake")
	await _capture("disabled-button-feedback")
	await _settle()
	await _settle()
	assert(disabled.position.is_equal_approx(original))
	assert(not disabled.has_node("UnavailableFeedback"))
	for i in range(8):
		await _click(get_viewport(),disabled.get_global_rect().get_center())
	await _settle()
	await _settle()
	assert(disabled.position.is_equal_approx(original),"rapid clicks must not accumulate offsets")
	await _click(get_viewport(),enabled.get_global_rect().get_center())
	assert(pressed==1 and not enabled.has_node("UnavailableFeedback"),"enabled buttons must work without false rejection")
	await _click(get_viewport(),press_disables.get_global_rect().get_center())
	assert(press_disables.disabled and not press_disables.has_node("UnavailableFeedback"),"a valid press that disables its button must not be rejected")
	# Buttons created later inside a native Godot Window use the same global hook.
	var popup := Window.new()
	popup.size = Vector2i(360,180)
	add_child(popup)
	var popup_button := _button(popup,"窗口内不可用",true)
	popup_button.position = Vector2(30,45)
	popup.show()
	await _settle()
	await _click(popup,popup_button.get_global_rect().get_center())
	assert(popup_button.has_node("UnavailableFeedback"),"native-window buttons must also be covered")
	popup.queue_free()
	await _settle()
	# The editor's guarded preview and unavailable history buttons must use the
	# same denial sound/mixer path as an insufficient-resource battle action.
	surface.hide()
	PlayerData.card_draft = {}
	PlayerData.editing_skill_index = 0
	var editor = load("res://SkillEditor.tscn").instantiate()
	add_child(editor)
	await _settle()
	for target in [editor.workbench.preview_tab,editor._undo_btn,editor._redo_btn]:
		await get_tree().create_timer(0.35).timeout
		var before := Time.get_ticks_msec()
		await _click(get_viewport(),target.get_global_rect().get_center())
		assert(target.has_node("UnavailableFeedback"),"editor rejection must flash the actual target button")
		if not AppAudio.players.is_empty():
			var matching := AppAudio.players.filter(func(p): return p.get_meta("sound","")=="denied" and int(p.get_meta("started_at",0))>=before)
			assert(matching.size()==1,"preview/undo/redo must each start one denial sound")
			assert(matching[0].bus=="SFX" and matching[0].stream==AppAudio.streams.denied,"editor and battle denials must share sound and mixer")
			assert(is_equal_approx(matching[0].volume_db,AppAudio.DENY_LEVEL_DB))
	editor.queue_free()
	await _settle()
	PlayerData.configure_hotseat_battle(CardDatabase.playtest_deck(),CardDatabase.playtest_deck())
	var battle = load("res://Main.tscn").instantiate()
	add_child(battle)
	await get_tree().create_timer(0.8).timeout
	var battle_sound_start := Time.get_ticks_msec()
	battle._show_toast("tip.insufficient_mana")
	if not AppAudio.players.is_empty():
		var voices := AppAudio.players.filter(func(p): return p.get_meta("sound","")=="denied" and int(p.get_meta("started_at",0))>=battle_sound_start)
		assert(voices.size()==1 and voices[0].bus=="SFX" and voices[0].stream==AppAudio.streams.denied,"battle resource denial must match editor denial")
		assert(is_equal_approx(voices[0].volume_db,AppAudio.DENY_LEVEL_DB))
	battle.queue_free()
	await _settle()
	var stream := load(AppAudio.DENY_SOUND) as AudioStreamMP3
	assert(stream != null and stream.get_length()>0 and not stream.loop)
	if not AppAudio.players.is_empty():
		AppAudio.play("denied","UI")
		var found := false
		for voice in AppAudio.players:
			if voice.get_meta("sound","")=="denied":
				assert(voice.stream == AppAudio.streams.denied and voice.bus=="SFX")
				found = true
		assert(found)
	print("TEST_UI_REJECT_FEEDBACK_VISUAL_OK")
	get_tree().quit(0)

func _button(parent: Node, text: String, disabled: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(260,48)
	button.disabled = disabled
	UITheme.apply_button(button)
	parent.add_child(button)
	if text=="可用按钮": button.pressed.connect(func(): pressed+=1)
	return button

func _click(viewport: Viewport, point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	viewport.push_input(motion,true)
	await get_tree().process_frame
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		viewport.push_input(event,true)
		await get_tree().process_frame

func _settle() -> void:
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/ui-refinement-20261113/%s.png" % name)
