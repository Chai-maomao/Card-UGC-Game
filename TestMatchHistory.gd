extends Node

const MatchHistoryScript = preload("res://MatchHistory.gd")
var failed := false


func _ready() -> void:
	_test_compute_summary()
	_test_filtered_entries()
	_test_entry_stats()
	_test_format_duration()
	await _test_scene_render()
	if not failed:
		print("TEST_MATCH_HISTORY_OK")
	get_tree().quit(1 if failed else 0)


func _make_entry(outcome: String, mode: String, turns: int, duration: int, local: int, p1_stats: Dictionary, p2_stats: Dictionary) -> Dictionary:
	var entry := {
		"outcome": outcome,
		"mode": mode,
		"turns": turns,
		"duration": duration,
		"local_player": local,
		"timestamp": 1787200000,
		"player_hp": 12,
		"opponent_hp": 0,
		"deck_name": "测试卡组",
		"deck_cards": ["卫兵", "治疗术"],
		"opponent_cards": ["刺客"],
		"app_version": "0.11",
	}
	if not p1_stats.is_empty():
		entry["stats_p1"] = p1_stats
	if not p2_stats.is_empty():
		entry["stats_p2"] = p2_stats
	return entry


func _test_compute_summary() -> void:
	var empty := MatchHistoryScript.compute_summary([])
	_assert(int(empty["total"]) == 0, "empty summary should have zero total")
	_assert(int(empty["streak_count"]) == 0, "empty summary should have no streak")
	_assert(int(empty["avg_duration"]) == 0, "empty summary should have zero avg duration")

	# 最新在前：胜/胜/负 + 一条旧格式（无 duration）
	var entries := [
		_make_entry("victory", "practice", 8, 600, 1, {"summons": 5}, {}),
		_make_entry("victory", "online", 10, 480, 2, {"summons": 3}, {}),
		_make_entry("defeat", "practice", 6, 300, 1, {"summons": 1}, {}),
		{"outcome": "finished", "mode": "hotseat", "turns": 4, "timestamp": 1787100000},
	]
	var summary := MatchHistoryScript.compute_summary(entries)
	_assert(int(summary["total"]) == 4, "summary total mismatch")
	_assert(int(summary["wins"]) == 2, "summary wins mismatch")
	_assert(int(summary["losses"]) == 1, "summary losses mismatch")
	_assert(int(summary["win_rate"]) == 67, "a hotseat finish should not affect personal win rate")
	_assert(str(summary["streak_type"]) == "win", "streak type should be win")
	_assert(int(summary["streak_count"]) == 2, "streak count should be 2")
	_assert(int(summary["avg_turns"]) == 7, "avg turns should be 7")
	_assert(int(summary["avg_duration"]) == 460, "avg duration should be 460s")

	# 连败口径：defeat 与 forfeit 都计入
	var loss_streak := [
		_make_entry("forfeit", "practice", 2, 60, 1, {}, {}),
		_make_entry("defeat", "practice", 5, 200, 1, {}, {}),
	]
	var loss_summary := MatchHistoryScript.compute_summary(loss_streak)
	_assert(str(loss_summary["streak_type"]) == "loss", "forfeit should start a loss streak")
	_assert(int(loss_summary["streak_count"]) == 2, "loss streak should span defeat+forfeit")
	_assert(int(loss_summary["losses"]) == 2, "forfeit should count as a loss")
	entries.push_front(_make_entry("interrupted", "online", 1, 50, 2, {}, {}))
	var interrupted := MatchHistoryScript.compute_summary(entries)
	_assert(int(interrupted["total"]) == 5, "the interruption should appear in match history")
	_assert(int(interrupted["wins"]) == 2 and int(interrupted["losses"]) == 1 and int(interrupted["win_rate"]) == 67, "the interruption must not affect wins, losses or win rate")
	_assert(interrupted["streak_type"] == "win" and int(interrupted["streak_count"]) == 2, "the interruption should leave the completed streak intact")
	entries.push_front({"outcome": "finished", "mode": "ranked", "result": "3"})
	var draw := MatchHistoryScript.compute_summary(entries)
	_assert(int(draw["win_rate"]) == 50 and int(draw["streak_count"]) == 0, "a competitive draw should count in the win rate and end a streak")


func _test_filtered_entries() -> void:
	var entries := [
		_make_entry("victory", "online", 8, 600, 1, {"summons": 5}, {}),
		_make_entry("defeat", "practice", 6, 300, 1, {"summons": 1}, {}),
		_make_entry("victory", "practice", 9, 420, 1, {"summons": 2}, {}),
	]
	_assert(MatchHistoryScript.filtered_entries(entries, "all", "all").size() == 3, "no filter should keep all entries")
	_assert(MatchHistoryScript.filtered_entries(entries, "victory", "all").size() == 2, "outcome filter mismatch")
	_assert(MatchHistoryScript.filtered_entries(entries, "victory", "practice").size() == 1, "combined filter mismatch")
	_assert(MatchHistoryScript.filtered_entries(entries, "all", "hotseat").size() == 0, "unknown mode should match nothing")


func _test_entry_stats() -> void:
	# 本地是玩家2：you 应取 stats_p2
	var entry := _make_entry("victory", "online", 8, 600, 2,
		{"summons": 1, "kills": 0}, {"summons": 4, "kills": 3})
	var stats := MatchHistoryScript.entry_stats(entry)
	_assert(bool(stats["has_stats"]), "stats should be available")
	_assert(int(stats["you"].get("summons", 0)) == 4, "you stats should come from stats_p2")
	_assert(int(stats["opp"].get("summons", 0)) == 1, "opp stats should come from stats_p1")

	# 旧格式：无 stats 字段
	var legacy := {"outcome": "defeat", "mode": "practice", "turns": 5, "local_player": 1}
	var legacy_stats := MatchHistoryScript.entry_stats(legacy)
	_assert(not bool(legacy_stats["has_stats"]), "legacy entry should have no stats")


func _test_format_duration() -> void:
	var language: String = Locale.language
	Locale.language = "zh"
	_assert(MatchHistoryScript.format_duration(0) == "0秒", "zero duration formatting mismatch")
	_assert(MatchHistoryScript.format_duration(65) == "1分5秒", "65s formatting mismatch")
	_assert(MatchHistoryScript.format_duration(600) == "10分", "600s formatting mismatch")
	_assert(MatchHistoryScript.format_duration(98293) == "27小时18分13秒", "long duration should keep clear unit labels")
	_assert(MatchHistoryScript.format_duration(-5) == "0秒", "negative duration should clamp to zero")
	Locale.language = "en"
	_assert(MatchHistoryScript.format_duration(98293) == "27h 18m 13s", "English duration should keep clear unit labels")
	Locale.language = language


func _test_scene_render() -> void:
	# 用混合数据（新格式+旧格式）渲染真实场景，确保 UI 构建不崩溃
	var saved: Array = PlayerData.match_history
	var display_test := DisplayServer.get_name() != "headless" and OS.get_cmdline_user_args().has("--visual")
	PlayerData.match_history = [
		_make_entry("victory", "online", 9, 540, 2,
			{"summons": 2, "spells": 1, "parasites": 0, "cards_drawn": 11, "card_damage": 18, "hero_damage": 20, "kills": 4, "mana_spent": 30},
			{"summons": 5, "spells": 3, "parasites": 1, "cards_drawn": 12, "card_damage": 26, "hero_damage": 8, "kills": 2, "mana_spent": 34}),
		_make_entry("defeat", "practice", 6, 98293, 1, {"summons": 3}, {"summons": 4}),
		{"outcome": "finished", "mode": "hotseat", "turns": 4, "timestamp": 1787100000, "player_hp": 3, "opponent_hp": 3},
		{"outcome": "interrupted", "mode": "online", "turns": 2, "timestamp": 1787200000, "player_hp": 12, "opponent_hp": 15},
	]
	var starter_cards := CardDatabase.starter_library()
	var recorded: Dictionary = PlayerData.match_history[1]
	recorded["deck_name"] = "默认卡组"
	recorded["deck_card_faces"] = PlayerData.snapshot_history_cards(starter_cards.slice(0, 4))
	recorded["opponent_card_faces"] = PlayerData.snapshot_history_cards(starter_cards.slice(4, 8))
	var scene: Control = load("res://MatchHistory.tscn").instantiate()
	add_child(scene)
	# _ready 已运行：总览 + 筛选 + 卡片应已生成
	var summary_tiles: int = (scene.get("summary_box") as HBoxContainer).get_child_count()
	_assert(summary_tiles == 3, "summary panel should render win rate, matches and streak, got %d tiles" % summary_tiles)
	var cards := 0
	for child in (scene.get("list_box") as VBoxContainer).get_children():
		if child is PanelContainer:
			cards += 1
	_assert(cards == 4, "should render 4 match cards, got %d" % cards)
	if display_test:
		await RenderingServer.frame_post_draw
		_assert(get_viewport().get_texture().get_image().save_png("user://match-history-durations.png") == OK, "could not capture the duration labels")
	await get_tree().process_frame
	var rows := (scene.get("list_box") as VBoxContainer).find_children("*", "PanelContainer", false, false)
	(rows[0] as Control).grab_focus()
	_press_key(KEY_DOWN)
	_assert(get_viewport().gui_get_focus_owner() == rows[1], "Down did not move focus to the next match")
	_press_key(KEY_ENTER)
	await get_tree().process_frame
	var detail := scene.get_node_or_null("MatchDetail")
	_assert(detail != null and UIMotion.top_popup() == detail, "Enter did not open the focused match")
	if detail != null:
		var card_faces := detail.find_children("*", "Control", true, false).filter(
			func(node): return node.get_script() == preload("res://presentation/ClassicBattleCardFace.gd"))
		_assert(card_faces.size() == 8, "both recorded decks should render standard card faces")
		if card_faces.size() == 8:
			var source: CardData = starter_cards[4]
			var opponent_face = card_faces[4]
			_assert(opponent_face.card.card_name == source.card_name and opponent_face.card.cost == source.cost
				and opponent_face.shown_hp == source.max_hp and opponent_face.shown_attack == source.atk
				and opponent_face.art != null, "standard face should render the saved opponent card stats and art")
	if display_test and detail != null:
		var detail_scroll := detail.find_children("*", "ScrollContainer", true, false)[0] as ScrollContainer
		await get_tree().process_frame
		for label: Label in detail_scroll.find_children("*", "Label", true, false):
			if label.text == Locale.t("history.deck_compare"):
				detail_scroll.scroll_vertical = maxi(0, roundi(label.global_position.y - detail_scroll.global_position.y) - 6)
				break
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		_assert(get_viewport().get_texture().get_image().save_png("user://match-history-detail.png") == OK, "could not capture the focused match details")
	_press_key(KEY_ESCAPE)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(UIMotion.top_popup() == null and get_viewport().gui_get_focus_owner() == rows[1], "Escape did not restore the focused match")
	var hover := InputEventMouseMotion.new()
	hover.position = Vector2(2, 2)
	get_viewport().push_input(hover, true)
	hover.position = (rows[0] as Control).get_global_rect().get_center()
	get_viewport().push_input(hover, true)
	await get_tree().process_frame
	_assert(get_viewport().gui_get_focus_owner() == rows[0], "hover did not move focus to the match under the pointer")
	var outcome_filter := scene.get("outcome_filter") as OptionButton
	var interrupted_index := -1
	for index in range(outcome_filter.item_count):
		if outcome_filter.get_item_text(index) == Locale.t("history.outcome.interrupted"):
			interrupted_index = index
			break
	_assert(interrupted_index >= 0, "the history filter is missing interrupted matches")
	if interrupted_index < 0:
		return
	outcome_filter.select(interrupted_index)
	outcome_filter.item_selected.emit(interrupted_index)
	await get_tree().process_frame
	var list := scene.get("list_box") as VBoxContainer
	_assert(list.find_children("*", "PanelContainer", false, false).size() == 1, "filter did not isolate the interrupted match")
	var mode_filter := scene.get("mode_filter") as OptionButton
	var online_index: int = scene.get("_mode_options").find("online")
	mode_filter.select(online_index)
	mode_filter.item_selected.emit(online_index)
	await get_tree().process_frame
	var summary := scene.get("summary_box") as HBoxContainer
	var values := summary.find_children("*", "Label", true, false)
	_assert(values.any(func(label): return label.text == "100%"), "mode summary should keep the online victory even when the list only shows interruptions")
	if display_test:
		await RenderingServer.frame_post_draw
		_assert(get_viewport().get_texture().get_image().save_png("user://match-history-interrupted.png") == OK, "could not capture the interrupted match list")
	await _test_ranked_history_render(scene, display_test)
	# 空历史也应正常渲染
	PlayerData.match_history = []
	scene._refresh_list()
	PlayerData.match_history = saved
	scene.queue_free()
	await get_tree().process_frame


func _test_ranked_history_render(scene: Control, capture: bool) -> void:
	var ranked := _make_entry("victory", "ranked", 8, 420, 1, {}, {})
	ranked.merge({"deck_name": "Aurora", "player_max_hp": 35, "opponent_max_hp": 30,
		"ranked_match_id": "settled", "ranked_settlement": {"before": 1000, "after": 1018, "multiplier": 1.12}}, true)
	var pending := _make_entry("defeat", "ranked", 4, 240, 1, {}, {})
	pending["ranked_match_id"] = "pending"
	var legacy := _make_entry("defeat", "ranked", 2, 120, 1, {}, {})
	PlayerData.match_history = [ranked, pending, legacy]
	var modes := scene.get("mode_filter") as OptionButton
	var outcomes := scene.get("outcome_filter") as OptionButton
	modes.select(int(scene.get("_mode_options").find("ranked")))
	outcomes.select(0)
	modes.item_selected.emit(modes.selected)
	await get_tree().process_frame
	var list := scene.get("list_box") as VBoxContainer
	var rows := list.find_children("*", "PanelContainer", false, false)
	var labels := list.find_children("*", "Label", true, false)
	_assert(rows.size() == 3, "ranked mode should render all three ranked matches")
	_assert(labels.any(func(label): return label.text == "+18"), "ranked list is missing the settled rating change")
	_assert(labels.any(func(label): return label.text == Locale.t("history.rating_pending")), "ranked list must distinguish a pending rating")
	_assert(labels.any(func(label): return label.text == Locale.t("history.rating_missing")), "ranked list must distinguish a legacy record")
	if rows.is_empty():
		return
	if capture:
		await RenderingServer.frame_post_draw
		_assert(get_viewport().get_texture().get_image().save_png("user://match-history-ranked.png") == OK, "could not capture ranked history")
	(rows[0] as Control).grab_focus()
	_press_key(KEY_ENTER)
	await get_tree().process_frame
	var detail := scene.get_node_or_null("MatchDetail")
	_assert(detail != null, "ranked match should open its details")
	if detail == null:
		return
	var bars := detail.find_children("*", "ProgressBar", true, false)
	_assert(bars.size() == 2 and int(bars[0].max_value) == 35 and int(bars[1].max_value) == 30, "health bars should use each recorded maximum")
	if capture:
		await RenderingServer.frame_post_draw
		_assert(get_viewport().get_texture().get_image().save_png("user://match-history-ranked-detail.png") == OK, "could not capture ranked detail")
	_press_key(KEY_ESCAPE)
	await get_tree().process_frame
	await get_tree().process_frame
	(rows[2] as Control).grab_focus()
	_press_key(KEY_ENTER)
	await get_tree().process_frame
	var old_detail := scene.get_node_or_null("MatchDetail")
	_assert(old_detail != null and old_detail.find_children("*", "ProgressBar", true, false).is_empty(), "legacy HP should be shown without inventing a maximum")
	_press_key(KEY_ESCAPE)
	await get_tree().process_frame


func _press_key(key: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.pressed = pressed
		get_viewport().push_input(event, true)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	failed = true
	push_error("TEST_MATCH_HISTORY_FAILED: %s" % message)
