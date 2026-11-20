extends Node

var failures: Array[String] = []

func _enter_tree() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS,true)
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH,true)

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1)
		return
	NetworkManager.close_connection()
	PlayerData.practice_challenge_id = ""
	PlayerData.card_playtest_context = {}
	PlayerData.configure_hotseat_battle(CardDatabase.beginner_deck(), CardDatabase.beginner_deck())
	var external_path := ProjectSettings.globalize_path("res://artifacts/action-art-external.webp")
	var fixture := load("res://res/ui/icons/cardex_app_icon.png") as Texture2D
	_check(fixture.get_image().save_webp(external_path) == OK, "external WebP fixture saved")
	for profile in [
		{"size": Vector2i(1280, 720), "language": "zh"},
		{"size": Vector2i(960, 540), "language": "zh"},
		{"size": Vector2i(1280, 720), "language": "en"},
		{"size": Vector2i(960, 540), "language": "en"},
	]:
		var dimensions: Vector2i = profile["size"]
		Locale.language = profile["language"]
		var viewport := SubViewport.new()
		viewport.size = dimensions
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		var battle = load("res://Main.tscn").instantiate()
		viewport.add_child(battle)
		await get_tree().create_timer(0.6).timeout
		var card := CardData.new("行动展示", 1, 5, 2, [{"skill_name": "治疗", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [{"effect": SkillEngine.EFFECT_HEAL, "target": SkillEngine.TARGET_SELF, "value": 1}]}])
		card.art_path = "res://res/ui/icons/cardex_app_icon.png"
		battle.game.current_player = 1
		battle.game.turn_number = 2
		battle.game.player_field.slots[0] = card
		battle.game.player2_field.slots[0] = CardData.new("守卫", 1, 9, 1, [])
		battle.game.reset_action_budget(1)
		battle.update_entire_screen()
		await get_tree().process_frame
		await get_tree().process_frame
		battle._play_summon_feedback(battle._my_slots_ui()[0])
		await _check_splash(battle, viewport, "deploy")
		battle._on_attack_requested(0)
		battle._on_opponent_slot_clicked(0)
		await _check_splash(battle, viewport, "attack")
		var ready_deadline := Time.get_ticks_msec()+4000
		while battle.is_resolution_locked() and Time.get_ticks_msec()<ready_deadline:
			await get_tree().process_frame
		_check(not battle.is_resolution_locked(),"attack feedback must finish before activating a skill")
		card.has_attacked = false
		card.has_acted = false
		battle._on_skill_activated(0, 0)
		await _check_splash(battle, viewport, "skill")
		battle.splash_tween.kill()
		battle.splash_panel.modulate.a = 0
		battle._play_skill_cast_feedback(1, 0)
		await _check_splash(battle, viewport, "ai-skill")
		battle.splash_tween.kill()
		battle.splash_panel.modulate.a = 0
		battle._replay_feedback_event({"kind": "attack", "player": 1, "slot": 0, "target_slot": 0})
		await _check_splash(battle, viewport, "remote-attack")
		await get_tree().create_timer(1.1).timeout
		_check(battle.splash_panel.modulate.a < 0.01, "action art fades after its hold")
		var blank := CardData.new("无图片卡牌" if Locale.language == "zh" else "A Card Without Artwork", 1, 5, 1, [])
		battle._show_splash(blank)
		_check(battle.splash_panel.card_view.visible and battle.splash_panel.card_view.current_card_data == blank, "missing art uses the standard full card face")
		await get_tree().create_timer(0.32).timeout
		_check(battle.splash_panel.size.x <= 200 * battle._ui_scale() + 0.1, "a long fallback name must not widen the left gutter")
		_check(battle.splash_panel.card_view._printed_face.art == load("res://res/tabletop/unillustrated_card.png"), "a card without custom artwork uses the default illustration")
		await _capture(viewport, "no-art")
		blank.art_path = "user://arts/missing-action-art-fixture.webp"
		battle._show_splash(blank)
		_check(battle.splash_panel.card_view._printed_face.art == load("res://res/tabletop/unillustrated_card.png"), "unavailable art uses the default without retaining the prior image")
		card.art_path = external_path
		battle._show_splash(card)
		await _check_splash(battle, viewport, "external-webp")
		await _check_slide_motion(battle, viewport, card)
		# Exit while a live reveal owns its callback, then wait past its lifetime.
		battle._show_splash(card)
		viewport.remove_child(battle)
		battle.free()
		await get_tree().create_timer(1.1).timeout
		remove_child(viewport)
		viewport.free()
	if failures.is_empty():
		print("TEST_ACTION_ART_VISUAL_OK")
		get_tree().quit(0)
	else:
		for failure in failures: push_error("TEST_ACTION_ART_VISUAL_FAILED: " + failure)
		get_tree().quit(1)


func _check_splash(battle: Node, viewport: SubViewport, action: String) -> void:
	await get_tree().create_timer(0.32).timeout
	var panel: Control = battle.splash_panel
	_check(panel.modulate.a > 0.9 and battle.splash_panel.card_view.current_card_data != null and battle.splash_panel.illustration.texture != null, action + " must display artwork")
	_check(panel.card_view.visible and not panel.illustration.visible and not panel.skill_name.visible,action+" uses the same full card as a basic attack")
	var rect := panel.get_global_rect()
	_check(Rect2(Vector2.ZERO, viewport.size).encloses(rect), action + " artwork must fit the viewport")
	_check(rect.end.x <= viewport.size.x * 0.25, action + " artwork stays in the left gutter")
	for control in battle._my_slots_ui() + battle._their_slots_ui() + [battle.enemy_status_hud, battle.player_status_hud, battle.hand_area, battle.turn_label, battle.end_turn_button, battle.combat_broadcast_panel]:
		_check(not rect.grow(4).intersects(control.get_global_rect()), action + " artwork must not cover " + str(control.name))
	_check(panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "art must not capture battle input")
	for child in panel.get_children():
		_check(child.mouse_filter == Control.MOUSE_FILTER_IGNORE, "art children must not capture battle input")
	await _capture(viewport, action)


func _check_slide_motion(battle: Node, viewport: SubViewport, card: CardData) -> void:
	battle._show_splash(card)
	var panel: Control = battle.splash_panel
	_check(panel.get_global_rect().end.x < 0, "entry starts completely outside the left edge")
	# Step the actual tween to inspect both travel directions without relying
	# on OS frame timing. Other action checks above use normal runtime playback.
	var tween: Tween = battle.splash_tween
	tween.pause()
	tween.custom_step(0.11)
	var entering_x: float = panel.position.x
	_check(entering_x < 16 * battle._ui_scale() and panel.get_global_rect().end.x > 0, "entry travels right from the left edge")
	await _capture(viewport, "entering")
	tween.custom_step(0.12)
	_check(panel.position.x > entering_x, "entry reaches the left gutter")
	tween.custom_step(0.55)
	tween.custom_step(0.11)
	_check(panel.position.x < 16 * battle._ui_scale() and panel.position.x > -panel.size.x, "exit travels left")
	await _capture(viewport, "exiting")
	var previous_progress: float = battle.splash_slide_progress
	var original_size := viewport.size
	viewport.size = Vector2i(960, 540) if original_size.x == 1280 else Vector2i(1280, 720)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(is_equal_approx(battle.splash_slide_progress, previous_progress), "resize preserves travel progress")
	_check(is_equal_approx(panel.position.x, lerpf(-panel.size.x - 16 * battle._ui_scale(), 16 * battle._ui_scale(), previous_progress)), "resize repositions the reveal at the same travel progress")
	battle._show_splash(CardData.new("新的行动", 1, 5, 1, []))
	_check(not tween.is_valid() and panel.get_global_rect().end.x < 0, "a new action cancels the old exit and restarts on the left")
	battle.splash_tween.pause()
	battle.splash_tween.custom_step(1.1)
	_check(panel.get_global_rect().end.x < 0 and panel.modulate.a == 0, "exit finishes entirely offscreen and hidden")
	viewport.size = original_size
	await get_tree().process_frame
	await get_tree().process_frame


func _capture(viewport: SubViewport, stage: String) -> void:
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://artifacts/left-action/%s-%s-%dx%d.png" % [Locale.language, stage, viewport.size.x, viewport.size.y])


func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
