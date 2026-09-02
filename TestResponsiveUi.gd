extends Node

const REQUIRED_SIZES: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1280, 800),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]
const LANGUAGES := ["zh", "en"]
const SCENES := [
	["main_menu", "res://MainMenu.tscn", "CenterContainer"],
	["settings", "res://SettingsMenu.tscn", "CenterContainer"],
	["card_editor", "res://CardEditor.tscn", "Panel"],
	["skill_editor", "res://SkillEditor.tscn", "Panel"],
	["history", "res://MatchHistory.tscn", ""],
	["battle", "res://Main.tscn", "CanvasLayer/MainBackground"],
]

var _failures := 0


func _ready() -> void:
	_assert(bool(ProjectSettings.get_setting("display/window/size/resizable", false)),
		"the project window must be user-resizable")
	for required_size in REQUIRED_SIZES:
		_assert(required_size in WindowSizeController.WINDOW_PRESETS,
			"missing resolution preset %s" % required_size)
	PlayerData.battle_mode = "practice"
	PlayerData.card_draft = _test_card_draft()
	PlayerData.editing_skill_index = 1
	var saved_history: Array = PlayerData.match_history
	PlayerData.match_history = [_history_entry()]

	for language in LANGUAGES:
		Locale.language = language
		for viewport_size in REQUIRED_SIZES:
			for scene_spec in SCENES:
				await _exercise_scene(str(scene_spec[0]), str(scene_spec[1]), str(scene_spec[2]), viewport_size, language)

	PlayerData.match_history = saved_history
	if _failures > 0:
		push_error("TEST_RESPONSIVE_UI_FAILED: %d assertion(s)" % _failures)
		get_tree().quit(1)
		return
	print("TEST_RESPONSIVE_UI_OK matrices=%d scenes=%d popups=3" % [REQUIRED_SIZES.size() * LANGUAGES.size(), SCENES.size()])
	get_tree().quit(0)


func _exercise_scene(tag: String, path: String, key_path: String, viewport_size: Vector2i, language: String) -> void:
	if tag == "card_editor" or tag == "skill_editor":
		PlayerData.card_draft = _test_card_draft()
		PlayerData.editing_skill_index = 1
	var viewport := SubViewport.new()
	viewport.name = "Viewport_%s_%s_%s" % [tag, language, viewport_size]
	viewport.size = viewport_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var packed := load(path) as PackedScene
	_assert(packed != null, "%s failed to load" % path)
	if packed == null:
		viewport.queue_free()
		return
	var scene := packed.instantiate()
	viewport.add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	_finish_layout_tweens()
	await get_tree().process_frame

	var bounds := Rect2(Vector2.ZERO, Vector2(viewport_size))
	var key_control: Control = scene as Control if key_path == "" else scene.get_node_or_null(key_path) as Control
	_assert(key_control != null, "%s %s %s has no key layout control" % [tag, language, viewport_size])
	if key_control:
		_assert(_rect_is_usable(key_control.get_global_rect(), bounds),
			"%s %s %s key panel is outside viewport: %s" % [tag, language, viewport_size, key_control.get_global_rect()])
	_check_interactive_controls(scene, bounds, "%s %s %s" % [tag, language, viewport_size])
	if tag == "battle":
		await _check_battle_2d_layout(scene, bounds, "%s %s" % [language, viewport_size])

	# Exercise three representative modal layouts under the same matrix: menu
	# choice, battlefield rules, and the data-dense history detail view.
	if tag == "main_menu":
		scene.call("_show_battle_mode_popup")
		await _check_latest_popup(scene, bounds, "%s battle-mode popup" % [language])
	elif tag == "battle":
		scene.call("_show_help_popup")
		await _check_latest_popup(scene, bounds, "%s battle-help popup" % [language])
	elif tag == "history":
		scene.call("_show_detail", _history_entry())
		await _check_latest_popup(scene, bounds, "%s history-detail popup" % [language])

	viewport.remove_child(scene)
	scene.free()
	remove_child(viewport)
	viewport.free()
	await get_tree().process_frame


func _check_battle_2d_layout(scene: Node, bounds: Rect2, tag: String) -> void:
	var layout := scene.get_node_or_null("CanvasLayer/MainBackground/MainLayout") as Control
	_assert(layout != null and layout.visible, "%s has no active 2D battlefield" % tag)
	_assert(scene.get_node_or_null("BattleStage3D") == null, "%s still contains the retired 3D stage" % tag)
	var enemy_hud := scene.get("enemy_status_hud") as Control
	var player_hud := scene.get("player_status_hud") as Control
	var enemy_row := scene.get("enemy_side_ui") as Control
	var player_row := scene.get("player_side_ui") as Control
	var hand_area := scene.get("hand_area") as Control
	var hand_container := scene.get("hand_container") as Control
	var discard_zone := scene.get("discard_zone") as Control
	var draw_button := scene.get("draw_pile_btn") as Control
	for toolbar_name in ["abandon_battle_button", "action_log_button", "help_btn"]:
		var toolbar_button := scene.get(toolbar_name) as Control
		_assert(not _controls_overlap(enemy_hud, toolbar_button), "%s enemy HUD overlaps %s" % [tag, toolbar_name])
	_assert(not _controls_overlap(enemy_hud, enemy_row), "%s enemy HUD overlaps the enemy field" % tag)
	_assert(not _controls_overlap(player_hud, player_row), "%s player HUD overlaps the player field" % tag)
	_assert(not _controls_overlap(player_hud, hand_area), "%s player HUD overlaps the hand dock" % tag)
	_assert(not _controls_overlap(hand_area, discard_zone), "%s discard target overlaps the hand dock" % tag)
	_assert(not _controls_overlap(hand_area, draw_button), "%s draw pile overlaps the hand dock" % tag)
	_assert(_rect_inside(hand_area.get_global_rect(), bounds, 2.0), "%s hand dock exceeds viewport" % tag)
	for card in hand_container.get_children():
		_assert(_rect_inside((card as Control).get_global_rect(), hand_area.get_global_rect(), 2.0), "%s hand card exceeds its dock" % tag)


func _controls_overlap(first: Control, second: Control) -> bool:
	return first != null and second != null and first.visible and second.visible \
		and first.get_global_rect().intersects(second.get_global_rect())


func _check_latest_popup(scene: Node, bounds: Rect2, tag: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_finish_layout_tweens()
	await get_tree().process_frame
	var layers := scene.find_children("*", "CanvasLayer", false, false)
	_assert(not layers.is_empty(), "%s was not created" % tag)
	if layers.is_empty():
		return
	var layer: CanvasLayer = layers[layers.size() - 1]
	var found_panel := false
	for child in layer.get_children():
		if child is Panel or child is PanelContainer:
			found_panel = true
			var panel := child as Control
			_assert(_rect_inside(panel.get_global_rect(), bounds, 2.0),
				"%s panel exceeds viewport: %s" % [tag, panel.get_global_rect()])
	_assert(found_panel, "%s has no panel" % tag)
	_check_interactive_controls(layer, bounds, tag)


func _check_interactive_controls(root: Node, bounds: Rect2, tag: String) -> void:
	var controls: Array[Node] = root.find_children("*", "BaseButton", true, false)
	var visible_count := 0
	for node in controls:
		var control := node as Control
		if control == null or not control.is_visible_in_tree():
			continue
		visible_count += 1
		var rect := control.get_global_rect()
		_assert(rect.size.x >= 8.0 and rect.size.y >= 8.0,
			"%s has zero-sized interactive control %s: %s" % [tag, control.name, rect])
		if _has_scroll_ancestor(control, root):
			continue
		_assert(_rect_inside(rect, bounds, 2.0),
			"%s interactive control %s exceeds viewport: %s" % [tag, control.name, rect])
	_assert(visible_count > 0, "%s exposes no visible interactive controls" % tag)


func _has_scroll_ancestor(control: Control, root: Node) -> bool:
	var cursor := control.get_parent()
	while cursor != null and cursor != root:
		if cursor is ScrollContainer:
			return true
		cursor = cursor.get_parent()
	return false


func _finish_layout_tweens() -> void:
	for tween in get_tree().get_processed_tweens():
		if tween != null and tween.is_valid():
			tween.custom_step(10.0)


func _rect_is_usable(rect: Rect2, bounds: Rect2) -> bool:
	return rect.size.x > 8.0 and rect.size.y > 8.0 and rect.intersects(bounds)


func _rect_inside(rect: Rect2, bounds: Rect2, tolerance: float) -> bool:
	return rect.position.x >= bounds.position.x - tolerance \
		and rect.position.y >= bounds.position.y - tolerance \
		and rect.end.x <= bounds.end.x + tolerance \
		and rect.end.y <= bounds.end.y + tolerance


func _test_card_draft() -> Dictionary:
	return {
		"name": "Responsive Test", "cost": 2, "hp": 4, "atk": 2,
		"gender": "nonhuman", "card_type": "minion", "art_path": "",
		"skill1": {}, "skill2": {}, "skill3": {},
	}


func _history_entry() -> Dictionary:
	return {
		"outcome": "victory", "mode": "practice", "turns": 9,
		"duration": 540, "local_player": 1, "timestamp": 1787200000,
		"player_hp": 12, "opponent_hp": 0, "deck_name": "Responsive Deck",
		"deck_cards": ["Guard", "Healing", "Mage"],
		"opponent_cards": ["Assassin", "Fighter"], "app_version": AppVersion.VERSION,
		"stats_p1": {"summons": 3, "spells": 2, "kills": 4, "mana_spent": 28},
		"stats_p2": {"summons": 4, "spells": 1, "kills": 2, "mana_spent": 25},
	}


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("RESPONSIVE_UI: %s" % message)
