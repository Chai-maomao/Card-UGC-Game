extends Control

signal inspect_step(path: Array)

var skill: Dictionary
var source_hp: SpinBox
var target_hp: SpinBox
var report: RichTextLabel
var last_game: RefCounted
var stage: Control
var pause_button: Button
var replay_button: Button
var _initial: Dictionary
var _steps: Array = []
var _final: Dictionary
var _shown_step_count := 0
var _selection = preload("res://SkillTrialSelection.gd").new()
var _picker: CanvasLayer
var selection_button: Button
var _trial_seed := 0
var _run_hp := Vector2i(10,10)
var _resume_step := 0
var incoming_damage: SpinBox
var _incoming_row: HBoxContainer
var _hint: Label

func _t(zh: String, en: String) -> String:
	return zh if Locale.language == "zh" else en

func _ready() -> void:
	var popup := UITheme.make_popup_layer(self, 120)
	var frame := CenterContainer.new()
	popup.layer.add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	UITheme.apply_popup_frame(panel, "gold", false)
	panel.custom_minimum_size = Vector2(minf(760, get_viewport_rect().size.x-48), minf(640, get_viewport_rect().size.y-48))
	frame.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	title.text = _t("试放当前技能", "Try this skill")
	UITheme.apply_title(title, 20)
	box.add_child(title)
	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.apply_label(_hint)
	_hint.add_theme_font_size_override("font_size",14)
	box.add_child(_hint)
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 44
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	source_hp = _hp_input(row, _t("自身生命", "Your unit HP"))
	target_hp = _hp_input(row, _t("目标生命", "Target HP"))
	_incoming_row = HBoxContainer.new()
	_incoming_row.add_theme_constant_override("separation",8)
	row.add_child(_incoming_row)
	incoming_damage = _hp_input(_incoming_row,_t("受到伤害", "Incoming damage"))
	incoming_damage.max_value = 99
	incoming_damage.value = 6
	stage = preload("res://SkillTrialStage.gd").new()
	box.add_child(stage)
	stage.step_resolved.connect(_show_report_through)
	stage.hand_requested.connect(_show_hand)
	stage.playback_finished.connect(_on_playback_finished)
	stage.pause_changed.connect(func(paused: bool):
		pause_button.text = _t("继续", "Resume") if paused else _t("暂停", "Pause"))
	report = RichTextLabel.new()
	report.custom_minimum_size = Vector2(0, 56)
	report.size_flags_vertical = Control.SIZE_EXPAND_FILL
	report.bbcode_enabled = true
	report.meta_underlined = false
	report.scroll_following = true
	report.tooltip_text = _t("点击记录，返回对应积木。", "Click a step to return to its block.")
	report.meta_clicked.connect(func(meta: Variant):
		var index := str(meta).to_int()
		if index >= 0 and index < _steps.size():
			inspect_step.emit(_steps[index].path)
			queue_free())
	report.add_theme_font_size_override("normal_font_size", 15)
	report.add_theme_color_override("default_color", UITheme.COLOR_TEXT)
	box.add_child(report)
	var actions := HBoxContainer.new()
	box.add_child(actions)
	for text in [_t("试一次", "Run"), _t("重播", "Replay"), _t("暂停", "Pause"), _t("显示结果", "Show result"), _t("选择卡牌", "Choose cards"), Locale.t("common.back")]:
		var button := Button.new()
		button.text = text
		UITheme.apply_button(button, "primary" if actions.get_child_count() == 0 else "secondary")
		actions.add_child(button)
		if actions.get_child_count() == 1: button.pressed.connect(run_trial)
		elif actions.get_child_count() == 2:
			replay_button = button
			button.tooltip_text = _t("重看这次结果，不重新随机。", "Replay this result without rolling again.")
			button.pressed.connect(_replay)
		elif actions.get_child_count() == 3:
			pause_button = button
			button.pressed.connect(stage.toggle_pause)
		elif actions.get_child_count() == 4: button.pressed.connect(stage.finish)
		elif actions.get_child_count() == 5:
			selection_button = button
			selection_button.hide()
			button.pressed.connect(_show_picker)
		else: button.pressed.connect(queue_free)
	run_trial()

func _hp_input(row: HBoxContainer, text: String) -> SpinBox:
	var label := Label.new()
	label.text = text
	UITheme.apply_label(label)
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = 30
	spin.value = 10
	spin.custom_minimum_size.x = 90
	UITheme.apply_input(spin)
	row.add_child(spin)
	spin.custom_minimum_size.x = ceilf(spin.get_combined_minimum_size().x)
	return spin

func run_trial() -> void:
	if is_instance_valid(_picker): _picker.queue_free()
	_picker = null
	_selection.choices.clear()
	_trial_seed = Time.get_ticks_usec()
	_run_hp = Vector2i(int(source_hp.value),int(target_hp.value))
	var continuous: bool = skill.get("trigger","") == SkillEngine.TRIGGER_ALWAYS
	_incoming_row.visible = continuous
	_hint.text = _t("模拟己方受到一次伤害，观察当前天赋的作用。", "Test one incoming hit against your unit with this talent.") if continuous else _t("双方各有 1 个单位、3 张手牌和 5 点圣水，攻击分别为 3 和 2。", "Each side has 1 unit, 3 cards and 5 elixir. Your unit has 3 attack; the enemy has 2.")
	_simulate()

func _simulate(start_index := 0) -> void:
	var game = preload("res://GameState.gd").new()
	game.quiet = true
	game.initialize_fields(PlayerData.DEFAULT_BATTLE_CONFIG)
	game.turn_number = 3
	game.game_rng.seed = _trial_seed
	var source := CardData.new(_t("自身", "Your unit"), 1, 30, 3)
	var target := CardData.new(_t("目标", "Target"), 1, 30, 2)
	source.art_path = str(PlayerData.card_draft.get("art_path", ""))
	source.damaged_art_path = str(PlayerData.card_draft.get("damaged_art_path", ""))
	source.hp = _run_hp.x
	target.hp = _run_hp.y
	game.player_field.slots[2] = source
	game.player2_field.slots[2] = target
	game.player_field.current_mana = 5
	game.player2_field.current_mana = 5
	for i in range(3):
		game.player_hand.append(CardData.new(_t("手牌 %d", "Hand card %d") % (i+1), i+1, 3+i, 1+i))
		game.player2_hand.append(CardData.new(_t("敌方手牌 %d", "Enemy hand card %d") % (i+1), i+1, 3+i, 1+i))
		game.shared_discard.append(CardData.new(_t("弃牌 %d", "Discard card %d") % (i+1),i+1,4+i,2))
	for i in range(12): game.shared_deck.append(CardData.new(_t("牌库卡牌 %d", "Deck card %d") % (i+1),i%4+1,3+i%5,1+i%3))
	var context: Dictionary = game.make_skill_context(2, 2)
	var initial := _snapshot(game,source,target)
	var frames: Array = []
	context["trace_callable"] = func(entry):
		if not _selection.pending.is_empty(): return
		frames.append({"entry":entry.duplicate(true),"before":_snapshot(game,source,target)})
	if skill.get("trigger","") == SkillEngine.TRIGGER_ALWAYS:
		_selection.pending = {}
		source.skills = [skill.duplicate(true)]
		frames.append({"entry":{"event":"test_hit","path":[],"target":source.card_name,"value":int(incoming_damage.value)},"before":_snapshot(game,source,target)})
		var lost := source.take_damage(int(incoming_damage.value))
		frames.back().entry["lost"] = lost
	else:
		_selection.run(skill,source,game,context,frames)
	# Discard cleanup restores the live card's base stats. The stage must keep
	# the lethal result rather than display that storage reset as a full heal.
	var shown_source := source.duplicate_card()
	var shown_target := target.duplicate_card()
	game.cleanup_deaths()
	last_game = game
	var final_state := _snapshot(game,shown_source,shown_target)
	var steps: Array = []
	for i in range(frames.size()):
		var text := _describe(frames[i].entry)
		if not text.is_empty():
			steps.append({"text":text,"path":frames[i].entry.path,"target":frames[i].entry.get("target",""),"origin":1 if frames[i].entry.event == "test_hit" else 0,"event":frames[i].entry.event,"before":frames[i].before,"after":frames[i+1].before if i+1 < frames.size() else final_state})
	_initial = initial
	_steps = steps
	_final = final_state
	selection_button.visible = not _selection.pending.is_empty()
	selection_button.disabled = true
	_play_from(start_index)

func _replay() -> void:
	_play_from(0)

func _play_from(start_index: int) -> void:
	report.clear()
	_shown_step_count = 0
	_show_report_through(start_index - 1)
	pause_button.disabled = false
	selection_button.disabled = true
	stage.play(_steps[start_index].before if start_index < _steps.size() else _initial,_steps,_final,start_index)

func _on_playback_finished() -> void:
	if _steps.is_empty():
		report.text = _t("这次没有产生效果。", "No effect this time.")
	else:
		_show_report_through(_steps.size() - 1)
	pause_button.disabled = true
	if not _selection.pending.is_empty():
		stage.progress.text = _t("请选择卡牌", "Choose cards")
		selection_button.disabled = false
		_resume_step = maxi(0,_steps.size()-1)
		_show_picker.call_deferred()

func _show_picker() -> void:
	if _selection.pending.is_empty() or is_instance_valid(_picker): return
	var request: Dictionary = _selection.pending
	var title := _t("从牌库中选择卡牌", "Choose cards from the deck") if request.kind == "deck" else _t("从弃牌堆中选择卡牌", "Choose cards from the discard pile")
	if request.kind == "hand":
		var sides: bool = request.target in [SkillEngine.TARGET_SIDES,SkillEngine.TARGET_SELF_SIDES]
		title = Locale.t("battle.reduce_cost_title_sides" if sides else "battle.reduce_cost_title",[request.reduction,Locale.term("cost_reduction_mode",request.mode)])
	else:
		title += _t("（最多 %d 张）", " (up to %d)") % mini(request.limit,request.cards.size())
	_picker = preload("res://CardCollectionDialog.gd").show_cards(self,request.cards,title,request.limit,func(selected: Array):
		_selection.confirm(selected)
		_simulate(_resume_step))
	_picker.layer = 122
	_picker.limit_feedback = true
	_picker.selection_overlays[0].grab_focus.call_deferred()

func _show_hand(side: int) -> void:
	if is_instance_valid(_picker): return
	var hand: Array = last_game.player_hand if side == 0 else last_game.player2_hand
	_picker = preload("res://CardCollectionDialog.gd").show_cards(self,hand,_t("己方手牌", "Your hand") if side == 0 else _t("敌方手牌", "Enemy hand"))
	_picker.layer = 122

func _show_report_through(index: int) -> void:
	while _shown_step_count <= index and _shown_step_count < _steps.size():
		var step: Dictionary = _steps[_shown_step_count]
		var line: String = step.text.replace("[", "[lb]")
		if not step.path.is_empty():
			line = "[url=%d]%s[/url]" % [_shown_step_count, line]
		report.append_text(("\n" if _shown_step_count > 0 else "") + line)
		_shown_step_count += 1

func _describe(entry: Dictionary) -> String:
	match entry.event:
		"trigger": return ""
		"test_hit": return _t("敌方造成 %d 点伤害，实际受到 %d 点", "Enemy deals %d damage; your unit takes %d") % [entry.value,entry.lost]
		"selection": return _t("等待选择卡牌。", "Waiting for a card choice.")
		"condition": return _t("条件成立。", "The condition is true.") if entry.passed else _t("条件不成立。", "The condition is false.")
		"condition_false": return _t("条件不成立，跳过这个效果。", "The condition is false; this effect was skipped.")
		"probability_failed": return _t("这次概率判定没有成功。", "The chance roll failed this time.")
		"repeat": return _t("重复 %d 次：", "Repeat %d times:") % int(entry.count)
		"no_target": return _t("没有可以作用的目标。", "There is no suitable target.")
		"resolved":
			if entry.has("chosen"):
				var names := _t("、", ", ").join(entry.chosen)
				if entry.effect == SkillEngine.EFFECT_ZERO_COST:
					if entry.get("selection_neighbors",false):
						return _t("为%s及相邻手牌减少 %d 点费用", "Reduce the cost of %s and its neighbors by %d") % [names,entry.value]
					return _t("为 %s 减少 %d 点费用", "Reduce the cost of %s by %d") % [names,entry.value]
				return _t("将%s加入手牌", "Add %s to your hand") % names
			var list: Array = skill.get("effects", [])
			var effect: Dictionary = {}
			for part in entry.path:
				if part is int: effect = list[part]
				else: list = effect.get(part, [])
			effect = effect.duplicate(true)
			for key in ["value_var", "value_expr", "value_min", "value_max", "value_offset", "condition"]: effect.erase(key)
			effect["value"] = entry.value
			effect["probability"] = 100
			return SkillTextFormatter.format_effect_sentence(effect)
	return SkillTrace.describe(entry)

func _input(event: InputEvent) -> void:
	if not DevConsole.is_open() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if is_instance_valid(_picker): _picker.queue_free()
		else: queue_free()

func _snapshot(game: RefCounted, source: CardData, target: CardData) -> Dictionary:
	return {"source":source.duplicate_card(),"target":target.duplicate_card(),"hero":[game.player_field.player_hp,game.player2_field.player_hp],"mana":[game.player_field.current_mana,game.player2_field.current_mana],"hand":[game.player_hand.size(),game.player2_hand.size()]}
