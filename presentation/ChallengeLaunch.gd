extends Control

const LaunchFrame = preload("res://presentation/BattleLaunchFrame.gd")


func _ready() -> void:
	UITheme.apply_app_background(self)
	var restore := UIMotion.consume_restore_state().get_slice(":", 1)
	var chosen: String = restore if restore in PracticeChallenges.IDS else PracticeChallenges.IDS[0]
	var launch := LaunchFrame.new()
	add_child(launch)
	launch.setup(PracticeChallenges.catalog_title(), "", "practice")

	var back := Button.new()
	back.text = Locale.t("common.back")
	add_child(back)
	UITheme.place_page_back(self, back)
	back.pressed.connect(_on_back_pressed)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	launch.bind_form(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 14)
	scroll.add_child(margin)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	margin.add_child(list)
	for challenge_id: String in PracticeChallenges.IDS:
		var item := Button.new()
		item.text = PracticeChallenges.title(challenge_id)
		item.alignment = HORIZONTAL_ALIGNMENT_LEFT
		item.custom_minimum_size.y = 44
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.apply_button(item, "outlined", false)
		list.add_child(item)
		item.pressed.connect(PracticeChallenges.start.bind(challenge_id))
		if challenge_id == chosen:
			item.grab_focus.call_deferred()


func _on_back_pressed() -> void:
	UIMotion.go_back("res://MainMenu.tscn")
