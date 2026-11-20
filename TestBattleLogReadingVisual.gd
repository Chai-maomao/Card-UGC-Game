extends "res://TestTabletop3DVisual.gd"

func _enter_tree() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS,true)
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)

var failed := false

func _check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func _wheel(at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_WHEEL_DOWN
	event.pressed = true
	get_viewport().push_input(event,true)
	await get_tree().process_frame
	event = event.duplicate()
	event.pressed = false
	get_viewport().push_input(event,true)
	await get_tree().process_frame

func _verify() -> void:
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280,720)
	await get_tree().create_timer(0.25).timeout
	battle._clear_action_log()
	var literal := "[color=red]卡牌[/color]"
	for i in range(16):
		battle._show_combat_broadcast(BattleLogFormatter.format_event({"kind":"attack","player":1,"source":literal+str(i),"target":"守卫"},1),"attack")
	await _click(_center(battle.action_log_button))
	await get_tree().process_frame
	var text: RichTextLabel = battle.action_log_text
	_check(literal in text.get_parsed_text(),"UGC brackets must be rendered literally")
	_check("攻击敌方【守卫】" in text.get_parsed_text() and not "生命" in text.get_parsed_text(),"displayed records must only contain actions")
	await _press_inspector_key(KEY_TAB)
	_check(text.has_focus(), "Tab from Close must focus the log body")
	await _press_inspector_key(KEY_PAGEDOWN)
	_check(text.get_v_scroll_bar().value > 2, "Page Down must reveal older records from the log body")
	await _press_inspector_key(KEY_PAGEUP)
	_check(is_zero_approx(text.get_v_scroll_bar().value), "Page Up must return to the top of the log")
	await _press_inspector_key(KEY_PAGEDOWN)
	var older_scroll := text.get_v_scroll_bar().value
	var older_text := text.get_parsed_text()
	battle._show_combat_broadcast(BattleLogFormatter.format_event({"kind":"skill","player":2,"source":"键盘返回记录","skill":"洞察"},1),"skill")
	await get_tree().process_frame
	_check(is_equal_approx(older_scroll, text.get_v_scroll_bar().value) and text.get_parsed_text() == older_text
		and battle._action_log_latest.visible, "incoming records must preserve the keyboard reading position")
	await _press_inspector_key(KEY_HOME)
	_check(text.has_focus() and "键盘返回记录" in text.get_parsed_text() and is_zero_approx(text.get_v_scroll_bar().value)
		and not battle._action_log_latest.visible, "Home from the log body must show queued records at the top and preserve focus")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/ui-refinement-20261113/log-keyboard-latest.png")
	await _press_inspector_key(KEY_PAGEDOWN)
	await _press_inspector_key(KEY_HOME)
	_check(text.has_focus() and is_zero_approx(text.get_v_scroll_bar().value),
		"Home must still scroll to the top when there are no queued records")
	for i in range(7): await _wheel(text.get_global_rect().get_center())
	_check(text.get_v_scroll_bar().value>2,"actual wheel input must scroll to older records")
	var scroll := text.get_v_scroll_bar().value
	var visible_text := text.get_parsed_text()
	battle._show_combat_broadcast(BattleLogFormatter.format_event({"kind":"skill","player":2,"source":"新到记录","skill":"洞察"},1),"skill")
	await get_tree().process_frame
	_check(is_equal_approx(scroll,text.get_v_scroll_bar().value) and text.get_parsed_text()==visible_text,"new records must not move or replace an older record being read")
	_check(battle._action_log_latest.visible,"pending records must expose an explicit return to latest")
	await RenderingServer.frame_post_draw
	var motion := InputEventMouseMotion.new()
	motion.position = battle._action_log_latest.get_global_rect().get_center()
	motion.global_position = motion.position
	get_viewport().push_input(motion,true)
	await get_tree().process_frame
	await _click(battle._action_log_latest.get_global_rect().get_center())
	await get_tree().process_frame
	_check("新到记录" in text.get_parsed_text() and text.get_v_scroll_bar().value==0 and not battle._action_log_latest.visible,"return to latest must reveal new records and clear its indicator")
	_check(battle._action_log_close.has_focus(), "the disappearing Latest button must hand focus back to Close")
	for language in ["zh","en"]:
		Locale.language = language
		for size in [Vector2i(1280,720),Vector2i(960,540)]:
			get_window().size = size
			await get_tree().create_timer(0.15).timeout
			battle._sync_tabletop()
			for i in range(5):
				var near: MeshInstance3D = battle.tabletop.sockets[i]
				var far: MeshInstance3D = battle.tabletop.sockets[i+5]
				_check(absf(near.scale.x-far.scale.x)<0.002 and absf(near.scale.z-far.scale.z)<0.002,"near and far sockets must share physical dimensions")
				var near_rect := _projected_bounds(near)
				var far_rect := _projected_bounds(far)
				_check(far_rect.size.x<near_rect.size.x and far_rect.size.y<near_rect.size.y,"perspective must make distant sockets smaller on screen")
				_check(battle.enemy_side_ui.get_child(i).get_global_rect().has_point(far_rect.get_center()),"projected sockets must remain inside their real input areas")
			_check(battle.action_log_panel.position.y>=battle.enemy_side_ui.get_global_rect().end.y,"battle log must not cover the enemy row")
			_check(battle.action_log_panel.get_global_rect().encloses(text.get_global_rect()),"log text must keep its panel padding")
			battle._refresh_action_log_text()
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://artifacts/ui-refinement-20261113/log-reading-%s-%d.png" % [language,size.x])
	battle._close_action_log()
	Locale.language = "zh"
	await _check_keyboard_log_actions()
	# Click the actual rendered enemy card after its projection changed.
	var enemy_rect := _projected_bounds(battle.tabletop.sockets[9])
	await _click(enemy_rect.get_center())
	_check(is_instance_valid(battle.card_inspector) and battle.card_inspector.visible,"projected enemy card must still open its inspector")
	if is_instance_valid(battle.card_inspector): battle.card_inspector.hide()
	battle._clear_action_log()
	_check(battle._action_log_entries.is_empty() and text.get_parsed_text().is_empty(),"clear must remove all displayed and pending records")
	battle.queue_free()
	await get_tree().process_frame
	if not failed: print("TEST_BATTLE_LOG_READING_OK native-wheel,stable-reading,latest,ugc-literals,clear,projection,input,two-sizes,two-languages,keyboard")
	get_tree().quit(1 if failed else 0)

func _check_keyboard_log_actions() -> void:
	var entries: int = battle._action_log_entries.size()
	var panel: Control = battle.action_log_panel
	var buttons := panel.find_children("*", "Button", true, false)
	var close: Button = buttons.filter(func(button: Button): return button.text == Locale.t("common.close"))[0]
	var clear: Button = buttons.filter(func(button: Button): return button.text == Locale.t("battle.clear_log"))[0]
	battle.action_log_button.grab_focus()
	await _press_inspector_key(KEY_ENTER)
	_check(panel.visible and close.has_focus(), "opening the log by keyboard must focus Close")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/ui-refinement-20261113/log-keyboard-entry.png")
	await _press_inspector_key(KEY_ENTER)
	_check(not panel.visible and battle._action_log_entries.size() == entries,
		"Enter after opening must close the log without deleting records")
	_check(battle.action_log_button.has_focus(), "closing the log must restore focus to its opener")
	if panel.visible:
		battle._close_action_log()
		return
	await _press_inspector_key(KEY_ENTER)
	for i in range(buttons.size()):
		if clear.has_focus():
			break
		await _press_inspector_key(KEY_TAB)
	_check(clear.has_focus(), "Clear must remain reachable through keyboard traversal")
	await _press_inspector_key(KEY_ENTER)
	_check(panel.visible and battle._action_log_entries.is_empty(), "explicitly activating Clear must empty the open log")
	await _press_inspector_key(KEY_ESCAPE)
	_check(not panel.visible and battle.action_log_button.has_focus(), "Escape must return to the log opener")


func _projected_bounds(mesh: MeshInstance3D) -> Rect2:
	var bounds: AABB = mesh.get_aabb()
	var result := Rect2()
	for i in range(8):
		var p: Vector2 = battle.tabletop.camera.unproject_position(mesh.global_transform*bounds.get_endpoint(i))
		result = Rect2(p,Vector2.ZERO) if i==0 else result.expand(p)
	return result
