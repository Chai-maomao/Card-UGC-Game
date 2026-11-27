extends Control

const Lessons = preload("res://AdvancedTutorialLessons.gd")
const Exercises = preload("res://AdvancedTutorialExercises.gd")
const RulesEditor = preload("res://presentation/BattleRulesEditor.gd")
const BattleScene = preload("res://Main.tscn")

var _battle: Node2D
var _previous_mode: String


func _ready() -> void:
	_previous_mode = PlayerData.battle_mode
	PlayerData.battle_mode = "tutorial"
	_open_chapter(0)


func _open_chapter(index: int) -> void:
	if is_instance_valid(_battle):
		remove_child(_battle)
		_battle.queue_free()
	var guide := Guide.new()
	guide.chapter = index
	guide.chapter_requested.connect(_open_chapter, CONNECT_DEFERRED)
	guide.exit_requested.connect(_on_back_pressed)
	_battle = BattleScene.instantiate()
	_battle.tutorial_scenario_setup = Exercises.setup.bind(Lessons.IDS[index])
	_battle.tutorial_controller = guide
	add_child(_battle)


func cancel_pending_battle_selection() -> bool:
	return is_instance_valid(_battle) and _battle.cancel_pending_battle_selection()


func _on_back_pressed() -> void:
	UIMotion.go_back("res://MainMenu.tscn")


func _exit_tree() -> void:
	PlayerData.battle_mode = _previous_mode


class Guide extends BattleTutorialController:
	signal chapter_requested(index: int)
	signal exit_requested

	enum Step { INTRO, SKILL, AIM, DEPLOY, ATTACK_SOURCE, ATTACK_TARGET, DISCARD, END_TURN, RULES, RESOLVING, RESULT }

	var chapter := 0
	var step: Step
	var _id: String
	var _focus: Control
	var _supplemented_damage := 0
	var _details: Button
	var _retry: Button
	var _chapter_picker: OptionButton
	var _sample_rules := PlayerData.DEFAULT_BATTLE_CONFIG.duplicate(true)
	var _rules_popup: CanvasLayer

	func start(owner_battle: Node) -> void:
		battle = owner_battle
		_id = Lessons.IDS[chapter]
		_build_ui()
		instruction_panel.name = "AdvancedTutorialGuide"
		body_label.name = "LessonInstruction"
		body_label.custom_minimum_size.y = 0
		step_label.text = Locale.t("tutorial.chapter_position", [chapter + 1, Lessons.IDS.size()])
		var heading := title_label.get_parent()
		_chapter_picker = OptionButton.new()
		_chapter_picker.name = "ChapterPicker"
		_chapter_picker.custom_minimum_size.x = 180
		_chapter_picker.fit_to_longest_item = false
		_chapter_picker.clip_text = true
		UITheme.apply_button(_chapter_picker, "secondary")
		for id in Lessons.IDS:
			_chapter_picker.add_item(Lessons.title(id))
		_chapter_picker.select(chapter)
		_chapter_picker.item_selected.connect(func(index: int): chapter_requested.emit(index))
		heading.add_child(_chapter_picker)
		_details = Button.new()
		_details.name = "LessonDetails"
		_details.text = _t("本章规则", "Lesson rules")
		UITheme.apply_button(_details, "secondary")
		_details.pressed.connect(_show_details)
		exit_button.get_parent().add_child(_details)
		_retry = Button.new()
		_retry.text = _t("再练一次", "Retry")
		UITheme.apply_button(_retry, "secondary")
		_retry.pressed.connect(func(): chapter_requested.emit(chapter))
		exit_button.get_parent().add_child(_retry)
		if _id == "turn":
			_supplemented_damage = int(battle.game.preview_end_turn_attacks(true).total_damage)
			battle.face_mana_button.toggled.connect(_payment_changed)
		_show_step(Step.INTRO)

	func allows(action: String, context: Dictionary = {}) -> bool:
		var allowed := false
		match action:
			"skill":
				allowed = step == Step.SKILL and context.slot == 0 and context.skill == 0
			"skill_target":
				allowed = battle.activate_targeting and step in [Step.SKILL, Step.AIM] 					and context.slot == 2 and context.player == (1 if _id == "control" else 2)
			"summon":
				allowed = step == Step.DEPLOY and context.slot == 2
			"attack_source":
				allowed = step == Step.ATTACK_SOURCE and context.slot == 0
			"attack_target":
				allowed = step == Step.ATTACK_TARGET
			"discard":
				allowed = step == Step.DISCARD and context.get("location") == "hand"
			"end_turn":
				allowed = step == Step.END_TURN and not battle.face_mana_button.button_pressed
		if not allowed:
			_remind()
		return allowed

	func notify_action(action: String, _context: Dictionary = {}) -> void:
		if action == "attack_source":
			_show_step(Step.ATTACK_TARGET)
		elif action in ["skill", "end_turn", "summon", "attack_target", "discard"]:
			_show_step(Step.RESOLVING)

	func _show_step(value: Step) -> void:
		step = value
		title_label.text = Lessons.title(_id)
		_chapter_picker.disabled = step == Step.RESOLVING
		skip_button.text = _t("跳过本章", "Skip chapter")
		skip_button.visible = step not in [Step.RESOLVING, Step.RESULT] and chapter < Lessons.IDS.size() - 1
		skip_button.custom_minimum_size.x = 104
		_details.visible = step != Step.RESOLVING
		_retry.visible = step == Step.RESULT
		next_button.visible = step in [Step.INTRO, Step.RULES, Step.RESULT]
		if step == Step.INTRO:
			next_button.text = _t("开始练习", "Start practice")
		elif step == Step.RULES:
			next_button.text = _t("试改战场设置", "Try battle settings")
		else:
			next_button.text = _t("完成", "Finish") if chapter == Lessons.IDS.size() - 1 else _t("下一章", "Next chapter")
		next_button.custom_minimum_size.x = 148
		next_button.disabled = false
		match step:
			Step.INTRO:
				body_label.text = Lessons.objective(_id)
			Step.SKILL:
				body_label.text = _skill_instruction()
			Step.DEPLOY:
				body_label.text = _t("把高亮的护盾新兵拖到高亮空格。留意圣水和新兵的护盾。", "Drag the highlighted Shield Recruit into the marked empty slot. Watch your Elixir and its shield.")
			Step.ATTACK_SOURCE:
				body_label.text = _t("打开高亮单位，点击「攻击」。", "Open the highlighted unit and select Attack.")
			Step.ATTACK_TARGET:
				body_label.text = _t("点选有嘲讽的卫兵完成普攻。也可以先试试旁边的斥候。", "Attack the Guard with Taunt. You can try selecting the nearby Scout first.")
			Step.DISCARD:
				body_label.text = _t("把高亮手牌拖到右下方的弃牌堆。", "Drag the highlighted hand card onto the discard pile at the bottom right.")
			Step.AIM:
				body_label.text = _t("点选高亮的己方卫兵。", "Select the highlighted allied Guard.") if _id == "control" else _t("点选高亮的敌方卫兵。", "Select the highlighted enemy Guard.")
			Step.END_TURN:
				_payment_changed(battle.face_mana_button.button_pressed)
			Step.RULES:
				body_label.text = _t("打开战场设置，把每回合抽牌调到 4 张，再确认看看行动力怎么变。", "Open battle settings, raise draw per turn to four, and confirm to see how action points change.")
			Step.RESOLVING:
				body_label.text = _t("看这次操作如何结算。", "Watch the action resolve.")
			Step.RESULT:
				body_label.text = Exercises.result(battle.game, _id, _supplemented_damage)

	func _skill_instruction() -> String:
		match _id:
			"triggers":
				return _t("打开高亮卡牌，点击「架起护盾」。发动概率是 0%，看看资源和剩余次数怎么变。", "Open the highlighted card and select Raise Shield. It has a 0% trigger chance. Watch your resources and remaining uses.")
			"targets":
				return _t("打开高亮卡牌，点击「横扫」，再选择敌方卫兵。留意卫兵左侧的空格。", "Open the highlighted card and select Sweep, then target the enemy Guard. Notice the empty slot on its left.")
			"damage":
				return _t("打开高亮卡牌，点击「吸血」，再选择有减伤和护盾的敌方卫兵。", "Open the highlighted card and select Lifesteal, then target the enemy Guard with damage reduction and shield.")
			"control":
				return _t("打开高亮卡牌，点击「净化」，再选择中毒的己方卫兵。", "Open the highlighted card and select Cleanse, then target the poisoned allied Guard.")
			"charm":
				return _t("打开高亮卡牌，点击「招降」，再选择敌方卫兵。", "Open the highlighted card, select Recruit, then target the enemy Guard.")
			_:
				return _t("手牌已经满了。打开高亮卡牌，点击「补给」再抽一张牌。", "Your hand is full. Open the highlighted card and select Resupply to draw one more.")

	func _payment_changed(enabled: bool) -> void:
		if step != Step.END_TURN:
			return
		body_label.text = _t("先关闭高亮的「圣水补付」。", "Turn off the highlighted Elixir Supplement.") if enabled else _t("悬停「结束回合」查看自动攻击预览，然后点击它。", "Hover over End Turn to preview the automatic attack, then click it.")

	func _phase_focus_controls() -> Array:
		match step:
			Step.SKILL, Step.ATTACK_SOURCE:
				var inspector: Control = battle.card_inspector
				if is_instance_valid(inspector) and inspector.visible and inspector.get_meta("friendly_slot", -1) == 0:
					var action_name := "TabletopSkill0" if step == Step.SKILL else "TabletopAttack"
					var action := inspector.find_child(action_name, true, false) as Button
					if is_instance_valid(action):
						return [action]


				return [battle.player_side_ui.get_child(0)]
			Step.DEPLOY, Step.DISCARD:
				var destination: Control = battle.player_side_ui.get_child(2) if step == Step.DEPLOY else battle.discard_zone
				return [battle.hand_container.get_child(0), destination] if battle.hand_container.get_child_count() else [destination]
			Step.ATTACK_TARGET:
				return [battle.enemy_side_ui.get_child(2)]
			Step.AIM:
				var row: Control = battle.player_side_ui if _id == "control" else battle.enemy_side_ui
				return [row.get_child(2)]
			Step.END_TURN:
				return [battle.face_mana_button if battle.face_mana_button.button_pressed else battle.end_turn_button]
			Step.RESULT:
				if _id == "charm" and battle.hand_container.get_child_count() > 0:
					return [battle.hand_container.get_child(0)]
				return []
			_:
				return []

	func _process(_delta: float) -> void:
		if not is_instance_valid(battle) or not is_instance_valid(instruction_panel):
			return
		if step == Step.SKILL and battle.activate_targeting:
			_show_step(Step.AIM)
		elif step == Step.AIM and not battle.activate_targeting:
			_show_step(Step.SKILL)
		elif step == Step.ATTACK_TARGET and battle.current_attacker_idx == -1:
			_show_step(Step.ATTACK_SOURCE)
		elif step == Step.RESOLVING and not battle.is_resolution_locked() and battle._deployment_feedback_delay() <= 0 \
				and battle._hp_feedback_batches.is_empty() and not battle.hand_container.get_children().any(_hand_card_arriving):
			_show_step(Step.RESULT)
		_position_panel()
		var controls := _phase_focus_controls()
		var control: Control = controls[0] if not controls.is_empty() else null
		if not is_instance_valid(_focus) or _focus != control:
			_clear_focus()
			_focus = control
			if control != null:
				_focus_controls(controls)
		_refresh_focus(controls)

	func _hand_card_arriving(card: Node) -> bool:
		return card.get_meta("tabletop_arriving", false)

	func _position_panel() -> void:
		var area: Vector2 = battle.get_viewport_rect().size
		var width := minf(680, area.x - 28.0)
		instruction_panel.custom_minimum_size.x = width
		instruction_panel.size = Vector2(width, instruction_panel.get_combined_minimum_size().y)
		var skill_open: bool = is_instance_valid(battle.card_inspector) and battle.card_inspector.visible
		var use_top := step in [Step.DEPLOY, Step.DISCARD] or (step == Step.RESULT and _id == "charm") \
			or (step in [Step.SKILL, Step.ATTACK_SOURCE] and not skill_open)
		var y := area.y - instruction_panel.size.y - 14.0
		if use_top:
			var hud_bottom: float = battle.enemy_status_hud.get_global_rect().end.y
			var turn_top: float = battle.middle_info_bar.get_global_rect().position.y
			y = maxf(14.0, minf(hud_bottom + 6.0, turn_top - instruction_panel.size.y - 6.0))
		instruction_panel.position = Vector2((area.x - width) / 2.0, y)

	func _on_next() -> void:
		if step == Step.INTRO:
			match _id:
				"deployment": _show_step(Step.DEPLOY)
				"taunt": _show_step(Step.ATTACK_SOURCE)
				"discard": _show_step(Step.DISCARD)
				"turn": _show_step(Step.END_TURN)
				"custom": _show_step(Step.RULES)
				_: _show_step(Step.SKILL)
		elif step == Step.RULES:
			_open_rules()
		elif step == Step.RESULT:
			_on_skip()

	func _on_skip() -> void:
		if step == Step.RESOLVING:
			return
		if chapter + 1 < Lessons.IDS.size():
			chapter_requested.emit(chapter + 1)
		else:
			_on_exit()

	func _on_exit() -> void:
		exit_requested.emit()

	func _open_rules() -> void:
		if is_instance_valid(_rules_popup):
			return
		_rules_popup = RulesEditor.open(battle.get_parent(), _sample_rules.duplicate(true), func(): return false, _apply_rules)
		UIMotion.register_popup(_rules_popup)

	func _apply_rules(config: Dictionary) -> void:
		var before := Exercises.sample_turn(_sample_rules)
		_sample_rules = config
		_show_step(Step.RESULT)
		body_label.text = Exercises.rule_preview(config) + "
" + _t("改动前摸 %d 张牌，有 %d 行动力。", "Before the change you drew %d cards and had %d action points.") % [before.hand, before.points]

	func _show_details() -> void:
		var popup := UITheme.make_popup_layer(battle, 150)
		var layer: CanvasLayer = popup.layer
		UIMotion.register_popup(layer)
		var margin := MarginContainer.new()
		layer.add_child(margin)
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side in ["left", "right", "top", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 32)
		var panel := PanelContainer.new()
		margin.add_child(panel)
		UITheme.apply_popup_frame(panel, "gold", true, true)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 12)
		panel.add_child(box)
		var title := Label.new()
		title.text = Lessons.title(_id)
		UITheme.apply_title(title, 22)
		box.add_child(title)
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		box.add_child(scroll)
		var content := VBoxContainer.new()
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.add_theme_constant_override("separation", 12)
		scroll.add_child(content)
		for section in Lessons.sections(_id):
			var heading := Label.new()
			heading.text = section[0]
			UITheme.apply_title(heading, 18)
			content.add_child(heading)
			var text := Label.new()
			text.text = section[1]
			text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			UITheme.apply_label(text)
			content.add_child(text)
		var close := Button.new()
		close.text = Locale.t("common.close")
		UITheme.apply_button(close, "secondary")
		close.pressed.connect(layer.queue_free)
		box.add_child(close)
		close.grab_focus()

	func _t(zh: String, en: String) -> String:
		return zh if Locale.language == "zh" else en
