extends Node

const ToastFeed = preload("res://BattleToastFeed.gd")
var failures: Array[String] = []


func _ready() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var feed := ToastFeed.new()
	layer.add_child(feed)
	var first := feed.show_message("First", "warn", 10.0)
	feed.show_message("Second", "attack", 10.0)
	feed.show_message("Third", "skill", 10.0)
	var latest := feed.show_message("最新提示", "unknown-kind", 10.0, 0.5)
	_check(feed.get_child_count() == 3 and first.is_queued_for_deletion(),
		"a fourth message must evict the oldest while retaining a bounded queue")
	_check((feed.get_child(0).get_child(0) as Label).text == "Second",
		"eviction must preserve chronological message order")
	_check((latest.get_child(0) as Label).text == "最新提示" and latest.get_child(0).get_theme_font_size("font_size") == 11,
		"localized text and minimum readable scaled font size must be preserved")
	_check(feed.mouse_filter == Control.MOUSE_FILTER_IGNORE and latest.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"messages must not capture battle input")
	_check(feed.show_message(" ") == null,
		"empty messages must be ignored")
	_check(feed.get_child_count() == 3, "empty messages must not evict a real message")
	feed.reject_latest()
	var transient := feed.show_message("Transient", "system", 0.0)
	await get_tree().create_timer(0.7).timeout
	_check(not is_instance_valid(transient) and feed.get_child_count() == 2,
		"expired messages must release their UI without removing live messages")
	feed.show_message("Exit during animation", "warn", 0.0)
	var feed_ref: WeakRef = weakref(feed)
	layer.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(0.7).timeout
	_check(feed_ref.get_ref() == null, "leaving battle must release the feed and its active tweens")
	if failures.is_empty():
		print("TEST_BATTLE_TOAST_FEED_OK")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("TEST_BATTLE_TOAST_FEED_FAILED: " + failure)
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
