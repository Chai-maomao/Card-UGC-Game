extends Control

signal step_resolved(index: int)
signal playback_finished
signal pause_changed(paused: bool)
signal hand_requested(side: int)

var actors: Array[Control] = []
var cards: Array[Control] = []
var bars: Array[ProgressBar] = []
var health: Array[Label] = []
var resources: Array[RichTextLabel] = []
var action_label: Label
var _playback: Tween
var _motion: Tween
var _travel := 0.0
var _beam_alpha := 0.0
var _beam_color := Color("ddba72")
var _endpoint := 1
var _origin := 0
var _last_state: Dictionary
var playing := false
var paused := false
var progress: Label
var outcomes: Array[Label] = []

func _ready() -> void:
	custom_minimum_size.y = 292
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in range(2):
		var actor := Control.new()
		actor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		actor.size = Vector2(176,292)
		add_child(actor)
		actors.append(actor)
		var role := Label.new()
		role.text = ("己方单位" if i == 0 else "敌方单位") if Locale.language == "zh" else ("Your unit" if i == 0 else "Enemy unit")
		role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		role.size = Vector2(176,20)
		role.add_theme_color_override("font_color", (UITheme.Tokens.TEAL if i == 0 else UITheme.Tokens.ENEMY) if UITheme.Tokens.light_mode else (Color("88c6be") if i == 0 else Color("ed7772")))
		actor.add_child(role)
		var card = preload("res://CardUI.tscn").instantiate()
		card.set_meta("suppress_hover_hint",true)
		actor.add_child(card)
		card.apply_ui_scale(1.15)
		card.position = Vector2(19,26)
		card.set_battle_layout_preview(false)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for child in card.find_children("*","Control",true,false): child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cards.append(card)
		var outcome := Label.new()
		outcome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		outcome.position = Vector2(0,90)
		outcome.size = Vector2(176,44)
		outcome.add_theme_font_size_override("font_size",32)
		outcome.add_theme_color_override("font_outline_color",Color("101c22"))
		outcome.add_theme_constant_override("outline_size",7)
		outcome.modulate.a = 0
		actor.add_child(outcome)
		outcomes.append(outcome)
		var bar := ProgressBar.new()
		bar.position = Vector2(10,220)
		bar.custom_minimum_size = Vector2(156,6)
		bar.size = Vector2(156,6)
		bar.show_percentage = false
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color("ed7772")
		fill.set_corner_radius_all(3)
		fill.set_content_margin_all(0)
		bar.add_theme_stylebox_override("fill",fill)
		var background := fill.duplicate()
		background.bg_color = Color("101c22")
		bar.add_theme_stylebox_override("background",background)
		bar.size = Vector2(156,6)
		actor.add_child(bar)
		bars.append(bar)
		var hp := Label.new()
		hp.position = Vector2(0,230)
		hp.size = Vector2(176,20)
		hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UITheme.apply_label(hp)
		actor.add_child(hp)
		health.append(hp)
		var details := RichTextLabel.new()
		details.position = Vector2(0,254)
		details.size = Vector2(176,36)
		details.bbcode_enabled = true
		details.add_theme_color_override("default_color", UITheme.COLOR_TEXT)
		details.scroll_active = false
		details.add_theme_font_size_override("normal_font_size",12)
		details.meta_clicked.connect(func(_meta):
			if not playing: hand_requested.emit(i))
		details.tooltip_text = "查看手牌" if Locale.language == "zh" else "View hand"
		actor.add_child(details)
		resources.append(details)
	action_label = Label.new()
	action_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	action_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	action_label.add_theme_font_size_override("font_size",15)
	UITheme.apply_label(action_label)
	add_child(action_label)
	progress = Label.new()
	progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress.add_theme_font_size_override("font_size",13)
	progress.add_theme_color_override("font_color", UITheme.COLOR_TEXT_MUTED if UITheme.Tokens.light_mode else Color("afbaaf"))
	add_child(progress)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	if actors.size() != 2: return
	for bar in bars: bar.size = Vector2(156,6)
	actors[0].position = Vector2(28,0)
	actors[1].position = Vector2(size.x-204,0)
	action_label.position = Vector2(216,132)
	action_label.size = Vector2(maxf(80,size.x-432),74)
	progress.position = Vector2(204,58)
	progress.size = Vector2(maxf(80,size.x-408),24)

func _draw() -> void:
	if actors.size() != 2: return
	var start := actors[_origin].position + Vector2(88,118)
	var end := actors[_endpoint].position + Vector2(88,118)
	if _endpoint == _origin: start += Vector2(0, -55)
	if _beam_alpha > 0.001:
		var point := start.lerp(end,_travel)
		var color := Color(_beam_color,_beam_alpha)
		draw_line(start,point,Color(color, color.a*0.40),6,true)
		draw_line(start,point,color,2,true)
		draw_circle(point,4,color)

func _state(state: Dictionary, update_bars := true) -> void:
	for i in range(2):
		var card: CardData = state.source if i == 0 else state.target
		cards[i].set_card(card)
		cards[i].position = Vector2(19,26)
		bars[i].max_value = maxi(1,card.max_hp)
		if update_bars: bars[i].value = maxi(0,card.hp)
		health[i].text = "HP %d / %d" % [maxi(0,card.hp),card.max_hp]
		resources[i].text = ("[center]玩家生命 %d\n圣水 %d  [url=hand]手牌 %d[/url][/center]" if Locale.language == "zh" else "[center]Player HP %d\nElixir %d  [url=hand]Hand %d[/url][/center]") % [state.hero[i],state.mana[i],state.hand[i]]

func play(initial: Dictionary, steps: Array, final_state: Dictionary, start_index := 0) -> void:
	if _playback != null and _playback.is_valid(): _playback.kill()
	if _motion != null and _motion.is_valid(): _motion.kill()
	_layout()
	for card in cards: card.modulate = Color.WHITE
	for outcome in outcomes: outcome.modulate.a = 0
	_last_state = final_state
	_state(initial)
	action_label.text = ""
	playing = true
	paused = false
	pause_changed.emit(false)
	_playback = create_tween()
	var duration := 0.48 if not AppPreferences.get_value("reduced_motion") else 0.01
	for index in range(start_index,steps.size()):
		_playback.tween_callback(func():
			progress.text = ("步骤 %d / %d" if Locale.language == "zh" else "Step %d / %d") % [index+1,steps.size()]
			_step(index, steps[index], duration))
		_playback.tween_interval(duration)
	_playback.tween_callback(finish)

func _step(index: int, step: Dictionary, duration: float) -> void:
	if _motion != null and _motion.is_valid(): _motion.kill()
	action_label.text = ""
	var before: Dictionary = step.before
	var after: Dictionary = step.after
	if step.get("event") not in ["resolved","test_hit"]:
		_beam_alpha = 0
		_state(after)
		action_label.text = step.text
		step_resolved.emit(index)
		queue_redraw()
		return
	_motion = create_tween().set_parallel(true)
	_origin = int(step.get("origin",0))
	_endpoint = 1 if step.get("target","") == before.target.card_name else 0
	var delta: int = after.target.hp-before.target.hp if _endpoint == 1 else after.source.hp-before.source.hp
	_beam_color = Color("ed7772") if delta < 0 else Color("88c6a2") if delta > 0 else Color("ddba72")
	_travel = 0
	_beam_alpha = 0.9
	_motion.tween_method(func(value): _travel = value; queue_redraw(),0.0,1.0,duration*0.45)
	_motion.tween_method(func(value): _beam_alpha = value; queue_redraw(),0.9,0.0,duration*0.5).set_delay(duration*0.5)
	_motion.tween_callback(func():
		_state(after,false)
		action_label.text = step.text
		step_resolved.emit(index)
		cards[_endpoint].modulate = Color(1.12,0.88,0.85) if delta < 0 else Color(0.9,1.12,0.96)
		if delta != 0:
			outcomes[_endpoint].text = "%+d" % delta
			outcomes[_endpoint].add_theme_color_override("font_color",_beam_color)
			outcomes[_endpoint].position.y = 90
			outcomes[_endpoint].modulate.a = 1).set_delay(duration*0.45)
	_motion.tween_property(outcomes[_endpoint],"position:y",68,duration*0.5).set_delay(duration*0.45)
	_motion.tween_property(outcomes[_endpoint],"modulate:a",0,duration*0.25).set_delay(duration*0.75)
	_motion.tween_property(cards[_endpoint],"modulate",Color.WHITE,duration*0.5).set_delay(duration*0.5)
	for i in range(2):
		var card: CardData = after.source if i == 0 else after.target
		_motion.tween_property(bars[i],"value",maxi(0,card.hp),duration*0.5).set_delay(duration*0.45)

func finish() -> void:
	if _playback != null and _playback.is_valid(): _playback.kill()
	if _motion != null and _motion.is_valid(): _motion.kill()
	if not _last_state.is_empty(): _state(_last_state)
	for card in cards: card.modulate = Color.WHITE
	for outcome in outcomes: outcome.modulate.a = 0
	_beam_alpha = 0
	playing = false
	paused = false
	progress.text = "试放结束" if Locale.language == "zh" else "Finished"
	action_label.text = ""
	pause_changed.emit(false)
	playback_finished.emit()
	queue_redraw()

func toggle_pause() -> void:
	if not playing: return
	paused = not paused
	for tween in [_playback,_motion]:
		if tween != null and tween.is_valid():
			if paused: tween.pause()
			else: tween.play()
	pause_changed.emit(paused)
