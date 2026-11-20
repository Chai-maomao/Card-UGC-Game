extends Node

var failures: Array[String] = []


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual suite requires a renderer")
		get_tree().quit(1)
		return
	NetworkManager.close_connection()
	PlayerData.practice_challenge_id = ""
	PlayerData.card_playtest_context = {}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/ui-review"))
	for dimensions in [Vector2i(1280, 720), Vector2i(960, 540)]:
		var viewport := SubViewport.new()
		viewport.size = dimensions
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		for language in ["zh", "en"]:
			Locale.language = language
			for entry in [["menu", "MainMenu"], ["collection", "MyCards"], ["editor", "CardEditor"], ["skills", "SkillEditor"], ["settings", "SettingsMenu"], ["online", "MultiplayerMenu"], ["deck", "BattleDeckSelect"], ["battle", "Main"]]:
				PlayerData.init_card_draft()
				PlayerData.editing_skill_index = 0
				PlayerData.battle_config = PlayerData.DEFAULT_BATTLE_CONFIG.duplicate(true)
				PlayerData.configure_hotseat_battle(CardDatabase.beginner_deck(), CardDatabase.beginner_deck())
				PlayerData.battle_select_mode = "practice"
				var scene = load("res://%s.tscn" % entry[1]).instantiate()
				viewport.add_child(scene)
				await get_tree().create_timer(0.35).timeout
				if entry[0] == "collection":
					scene._show_deck_cards(PlayerData.deck_library[0].get("id", ""))
					await get_tree().create_timer(0.6).timeout
				if entry[0] == "battle":
					var game = scene.game
					game.turn_number = 2
					game.player_hand.clear()
					for index in range(8):
						game.player_hand.append(CardData.new("卡牌 %d" % (index + 1), index % 4 + 1, 5, 2, []))
					game.player_hand[3].skills = [{"skill_name": "手牌技能", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "effects": [{"effect": SkillEngine.EFFECT_HEAL, "target": SkillEngine.TARGET_SELF, "value": 1}]}]
					game.player_field.slots[0] = CardData.new("先锋", 2, 5, 3, [])
					game.player2_field.slots[0] = CardData.new("守卫", 2, 6, 2, [])
					game.reset_action_budget(1)
					scene.reset_hand_ui_from_game_state()
					scene.update_entire_screen()
					await get_tree().create_timer(2.0).timeout
				await _settle()
				await _capture(viewport, "%s-%s-%dx%d" % [entry[0], language, dimensions.x, dimensions.y])
				if entry[0] == "battle":
					_check(not scene.action_log_button.get_global_rect().intersects(scene.enemy_status_hud.get_global_rect()), "battle log button does not cover the status HUD")
					for hud in [scene.player_status_hud, scene.enemy_status_hud]:
						var status_content = hud.get_node("Margin/Content")
						var action_bar = status_content.get_node("ActionBar")
						_check(action_bar.visible and action_bar.size.is_equal_approx(status_content.get_node("ManaBar").size), "action and Elixir bars share their dimensions")
						_check(hud.get_global_rect().grow(2).encloses(action_bar.get_global_rect()), "action bar fits inside the status HUD")
					var hand: Control = scene.hand_container
					var dock: Rect2 = scene.hand_area.get_global_rect()
					_check(hand.get_child_count() == 8, "eight cards are represented")
					for card in hand.get_children():
						_check(dock.grow(2).encloses(card.get_global_rect()), "eight-card resting hand exceeds its dock")
					var inspected = hand.get_child(3)
					var rest_screen_y := 0.0
					if scene.get("tabletop")!=null: rest_screen_y = scene.tabletop.camera.unproject_position(scene.tabletop.cards[13].top.global_position).y
					var motion := InputEventMouseMotion.new()
					motion.position = inspected.global_position + inspected.size * Vector2(0.4, 0.3)
					if scene.get("tabletop")!=null: motion.position.x = (inspected.global_position.x+hand.get_child(4).global_position.x)*.5
					viewport.push_input(motion, true)
					await get_tree().create_timer(0.16).timeout
					if scene.get("tabletop") != null:
						var actor: Dictionary = scene.tabletop.cards[13]
						var lift_deadline := Time.get_ticks_msec() + 1500
						while (not actor.get("hover",false) or scene.tabletop.camera.unproject_position(actor.top.global_position).y >= rest_screen_y-5) and Time.get_ticks_msec() < lift_deadline:
							await get_tree().process_frame
						_check(actor.get("hover",false) and scene.tabletop.camera.unproject_position(actor.top.global_position).y<rest_screen_y-5,"hover must visibly lift the physical hand card on screen")
						await _capture(viewport,"hand-hover-%s-%dx%d" % [language,dimensions.x,dimensions.y])
						# The visible action panel replaces the hidden legacy skill buttons.
						var inspect_event := InputEventMouseButton.new()
						inspect_event.position = inspected.get_global_rect().get_center()
						inspect_event.button_index = MOUSE_BUTTON_RIGHT
						inspect_event.pressed = true
						viewport.push_input(inspect_event,true)
						await get_tree().process_frame
						_check(is_instance_valid(scene.card_inspector) and scene.card_inspector.visible and scene.card_inspector.find_child("TabletopSkill0",true,false)!=null,"right-click must expose the actual hand skill")
						scene.card_inspector.hide()
						motion = InputEventMouseMotion.new()
						motion.position = Vector2(20,dimensions.y*0.5)
						viewport.push_input(motion,true)
						await get_tree().create_timer(0.35).timeout
						var rest_deadline := Time.get_ticks_msec() + 1500
						while (actor.get("hover",false) or actor.root.position.distance_to(actor.target) >= 0.01) and Time.get_ticks_msec() < rest_deadline:
							await get_tree().process_frame
						_check(not actor.get("hover",false) and actor.root.position.distance_to(actor.target)<0.01,"hover exit must restore the resting physical pose: hover=%s distance=%.4f focused=%s returning=%s"%[actor.get("hover",false),actor.root.position.distance_to(actor.target),inspected.get_meta("hand_focused",false),inspected.get_meta("hand_returning",false)])
					else:
						_check(inspected.z_index == 20 and inspected.scale.x > 1.1, "hovered card rises above neighbours and enlarges (z=%d scale=%s)" % [inspected.z_index, inspected.scale])
						await _capture(viewport, "hand-hover-%s-%dx%d" % [language, dimensions.x, dimensions.y])
						_check(inspected.skill1_btn.visible, "skill-button hover fixture must be visible")
						motion = InputEventMouseMotion.new()
						motion.position = inspected.skill1_btn.get_global_rect().get_center()
						viewport.push_input(motion, true)
						await get_tree().create_timer(0.2).timeout
						_check(inspected.z_index == 20 and inspected.scale.x > 1.1 and bool(inspected.get("_pointer_inside")), "hover stays enlarged over the skill button")
						await _capture(viewport, "hand-skill-hover-%s-%dx%d" % [language, dimensions.x, dimensions.y])
						motion = InputEventMouseMotion.new()
						motion.position = Vector2(20, dimensions.y * 0.5)
						viewport.push_input(motion, true)
						await get_tree().create_timer(0.16).timeout
						_check(inspected.scale.is_equal_approx(Vector2.ONE) and inspected.position.is_equal_approx(inspected.get_meta("hand_rest_position")), "hover restores the stable layout")
				if entry[0] == "deck":
					scene._show_battle_config_popup([])
					await get_tree().create_timer(0.35).timeout
					await _settle()
					await _capture(viewport, "rules-%s-%dx%d" % [language, dimensions.x, dimensions.y])
				viewport.remove_child(scene)
				scene.free()
				await _settle()
		remove_child(viewport)
		viewport.free()
	Locale.language = "zh"
	if failures.is_empty():
		print("TEST_MODERN_UI_VISUAL_OK: 8-card hand, hover, 8 screens, rules, zh/en, 1280/960")
		get_tree().quit(0)
	else:
		for failure in failures: push_error("TEST_MODERN_UI_VISUAL_FAILED: " + failure)
		get_tree().quit(1)


func _settle() -> void:
	for index in range(6): await get_tree().process_frame


func _capture(viewport: SubViewport, name: String) -> void:
	await RenderingServer.frame_post_draw
	_check(viewport.get_texture().get_image().save_png("res://artifacts/ui-review/" + name + ".png") == OK, "screenshot saved")


func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
