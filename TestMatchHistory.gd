extends Node

const MatchHistoryScript = preload("res://MatchHistory.gd")


func _ready() -> void:
	_test_compute_summary()
	_test_filtered_entries()
	_test_entry_stats()
	_test_format_duration()
	_test_scene_render()
	print("TEST_MATCH_HISTORY_OK")
	get_tree().quit(0)


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
	_assert(int(summary["win_rate"]) == 50, "win rate should be 50%")
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
	_assert(MatchHistoryScript.format_duration(0) == "0:00", "zero duration formatting mismatch")
	_assert(MatchHistoryScript.format_duration(65) == "1:05", "65s formatting mismatch")
	_assert(MatchHistoryScript.format_duration(600) == "10:00", "600s formatting mismatch")
	_assert(MatchHistoryScript.format_duration(-5) == "0:00", "negative duration should clamp to zero")


func _test_scene_render() -> void:
	# 用混合数据（新格式+旧格式）渲染真实场景，确保 UI 构建不崩溃
	var saved: Array = PlayerData.match_history
	PlayerData.match_history = [
		_make_entry("victory", "online", 9, 540, 2,
			{"summons": 2, "spells": 1, "parasites": 0, "cards_drawn": 11, "card_damage": 18, "hero_damage": 20, "kills": 4, "mana_spent": 30},
			{"summons": 5, "spells": 3, "parasites": 1, "cards_drawn": 12, "card_damage": 26, "hero_damage": 8, "kills": 2, "mana_spent": 34}),
		_make_entry("defeat", "practice", 6, 300, 1, {"summons": 3}, {"summons": 4}),
		{"outcome": "finished", "mode": "hotseat", "turns": 4, "timestamp": 1787100000, "player_hp": 3, "opponent_hp": 3},
	]
	var scene: Control = load("res://MatchHistory.tscn").instantiate()
	add_child(scene)
	# _ready 已运行：总览 + 筛选 + 卡片应已生成
	var summary_tiles: int = (scene.get("summary_box") as HBoxContainer).get_child_count()
	_assert(summary_tiles == 7, "summary panel should render 7 tiles, got %d" % summary_tiles)
	var cards := 0
	for child in (scene.get("list_box") as VBoxContainer).get_children():
		if child is PanelContainer:
			cards += 1
	_assert(cards == 3, "should render 3 match cards, got %d" % cards)
	# 空历史也应正常渲染
	PlayerData.match_history = []
	scene._refresh_list()
	PlayerData.match_history = saved
	scene.queue_free()


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("TEST_MATCH_HISTORY_FAILED: %s" % message)
	get_tree().quit(1)
