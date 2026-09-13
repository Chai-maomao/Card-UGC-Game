class_name PracticeChallenges
extends RefCounted

const IDS := ["resource", "combination", "taunt", "cleanse", "dispel", "execute", "parasite"]


static func _t(zh: String, en: String) -> String:
	return zh if Locale.language == "zh" else en


static func title(id: String) -> String:
	match id:
		"resource": return _t("资源连锁：蓄势登场", "Resource chain")
		"combination": return _t("协同突破", "Combine effects")
		"taunt": return _t("突破防线", "Break the line")
		"cleanse": return _t("解除压制", "Cleanse")
		"dispel": return _t("瓦解守势", "Dispel")
		"execute": return _t("处刑线", "Execute threshold")
		"parasite": return _t("共生突击", "Parasite assault")
	return id


static func catalog_title() -> String:
	return _t("组合挑战", "Skill challenges")


static func difficulty(id: String) -> String:
	if id in ["resource", "combination", "taunt"]:
		return _t("基础", "Basic")
	if id in ["cleanse", "dispel"]:
		return _t("进阶", "Intermediate")
	return _t("高级", "Advanced")


static func objective(id: String) -> String:
	match id:
		"resource": return _t("本回合召唤 5 费巨人。你只有 2 点圣水，需要规划三张手牌的使用顺序。", "Summon the 5-cost Giant this turn. You have 2 mana and must plan the order of three cards.")
		"combination": return _t("本回合消灭守卫。先锋当前攻击不足，必须先强化再攻击。", "Defeat the Guard this turn. The Vanguard needs a buff before it attacks.")
		"taunt": return _t("先击破嘲讽盾墙，再消灭后方指挥官。两名攻击者必须分配正确。", "Break the taunting Shield Wall, then defeat the Commander. Assign both attackers correctly.")
		"cleanse": return _t("解除先锋的沉默，并在本回合消灭压制者。", "Remove Silence from the Vanguard and defeat the Suppressor this turn.")
		"dispel": return _t("移除敌方盾卫的嘲讽，然后消灭后排法师。", "Remove Taunt from the enemy Shield Guard, then defeat the Backline Mage.")
		"execute": return _t("把重甲守卫压到 3 点或更低生命，再用处刑者完成斩杀。", "Reduce the Armored Guard to 3 HP or less, then finish it with the Executioner.")
		"parasite": return _t("把共生虫附着到轻装剑士，再借助攻击加成消灭装甲守卫。", "Attach the Symbiote to the Light Swordsman, then use its attack bonus to defeat the Armored Guard.")
	return ""


static func hint(id: String) -> String:
	match id:
		"resource": return _t("提示：卡牌效果会立即结算。先找出能增加圣水的牌，再判断剩余圣水是否足够召唤巨人。", "Hint: card effects resolve immediately. Find the mana-generating card, then check whether enough mana remains for the Giant.")
		"combination": return _t("提示：先锋只有 2 点攻击，鼓舞能增加 3 点。先让增益结算。", "Hint: the Vanguard has 2 attack and Inspire adds 3. Resolve the buff first.")
		"taunt": return _t("提示：嘲讽存在时只能攻击嘲讽单位。把 2 攻破阵兵留给 2 血盾墙。", "Hint: while Taunt is active, only the taunting unit can be attacked. Save the 2-attack Breacher for the 2-HP wall.")
		"cleanse": return _t("提示：净化移除友方负面状态；治疗不能解除沉默。", "Hint: Cleanse removes negative effects from allies; healing does not remove Silence.")
		"dispel": return _t("提示：驱散移除敌方正面状态；净化用于友方负面状态。", "Hint: Dispel removes positive effects from enemies; Cleanse removes negative effects from allies.")
		"execute": return _t("提示：重甲守卫有 6 点生命。选择恰好造成 3 点伤害的法术，才能进入处刑线。", "Hint: the Armored Guard has 6 HP. Use the 3-damage spell to reach the execute threshold.")
		"parasite": return _t("提示：寄生牌需要选择宿主。附着到己方剑士会增加其攻击；附着到敌人会帮到对方。", "Hint: a Parasite needs a host. Attach it to your Swordsman for attack; attaching it to the enemy helps them.")
	return ""


static func lesson(id: String) -> String:
	match id:
		"resource": return _t("要点：临时圣水应在本回合使用；先花掉基础圣水会让后续连锁断裂。", "Lesson: temporary mana should be used this turn; spending base mana first breaks the sequence.")
		"combination": return _t("要点：增益先结算，随后攻击才能把提升的数值转化为有效交换。", "Lesson: resolve the buff first, then turn the increased stat into a favorable attack.")
		"taunt": return _t("要点：嘲讽限制目标；突破后还要保留足够攻击力处理真正威胁。", "Lesson: Taunt restricts targets; preserve enough attack to handle the real threat afterward.")
		"cleanse": return _t("要点：净化针对友方负面状态，能恢复被沉默单位的行动能力。", "Lesson: Cleanse removes negative effects from allies and restores a silenced unit's options.")
		"dispel": return _t("要点：驱散针对敌方正面状态，可拆掉嘲讽等防御结构。", "Lesson: Dispel removes positive enemy effects such as Taunt and opens protected targets.")
		"execute": return _t("要点：阈值技能需要先精确削血；伤害不足一旦让处刑者行动就无法补救。", "Lesson: threshold skills need precise setup; activating the Executioner too early wastes the payoff.")
		"parasite": return _t("要点：寄生体的宿主选择决定收益归属，附着后还能替宿主优先承受定向伤害。", "Lesson: a Parasite's host determines who gains its value, and it can absorb directed damage for that host.")
	return ""


static func configure(game: RefCounted, id: String) -> void:
	game.current_player = 1
	game.is_player_turn = true
	game.turn_number = 2
	game.player_field.slots = [null, null, null, null, null]
	game.player2_field.slots = [null, null, null, null, null]
	game.player_field.current_mana = 2
	game.player_field.temp_mana = 0
	game.player_hand.clear()
	game.player2_hand.clear()
	game.shared_deck.clear()
	game.shared_discard.clear()
	game.game_rng.seed = 3109
	match id:
		"resource":
			game.player_hand.append(_spell("蓄势", "gain_mana", 3, "self", "ally", 0))
			game.player_hand.append(CardData.new("巨人", 5, 8, 5))
			game.player_hand.append(CardData.new("斥候", 2, 3, 2))
			game.player2_field.slots[0] = CardData.new("守卫", 2, 5, 1)
		"combination":
			game.player_hand.append(_spell("鼓舞", "gain_attack", 3, "target_single", "ally", 1))
			game.player_field.slots[0] = CardData.new("先锋", 2, 5, 2)
			game.player2_field.slots[0] = CardData.new("守卫", 3, 5, 1)
		"taunt":
			game.player_field.current_mana = 0
			game.player_field.slots[0] = CardData.new("破阵兵", 2, 4, 2)
			game.player_field.slots[1] = CardData.new("游骑兵", 3, 4, 3)
			game.player2_field.slots[0] = _unit_with_buff("盾墙", 2, 2, 1, "taunt")
			game.player2_field.slots[1] = CardData.new("指挥官", 3, 3, 0)
		"cleanse":
			game.player_field.current_mana = 1
			game.player_field.slots[0] = _unit_with_buff("沉默先锋", 3, 5, 5, "silence")
			game.player2_field.slots[0] = CardData.new("压制者", 3, 5, 0)
			game.player_hand.append(_spell("净化术", "cleanse", 0, "target_single", "ally", 1))
			game.player_hand.append(_spell("治疗术", "heal", 2, "target_single", "ally", 1))
		"dispel":
			game.player_field.current_mana = 1
			game.player_field.slots[0] = CardData.new("突击手", 3, 5, 4)
			game.player2_field.slots[0] = _unit_with_buff("盾卫", 3, 8, 1, "taunt")
			game.player2_field.slots[1] = CardData.new("后排法师", 4, 4, 0)
			game.player_hand.append(_spell("破法", "dispel", 0, "target_single", "enemy", 1))
			game.player_hand.append(_spell("净化术", "cleanse", 0, "target_single", "ally", 1))
		"execute":
			game.player_field.current_mana = 1
			game.player_field.slots[0] = _active_unit("处刑者", 4, 5, 1, "终结打击", "execute", 3)
			game.player2_field.slots[0] = CardData.new("重甲守卫", 5, 6, 1)
			game.player_hand.append(_spell("精准削弱", "damage", 3, "target_single", "enemy", 1))
			game.player_hand.append(_spell("仓促射击", "damage", 2, "target_single", "enemy", 1))
		"parasite":
			game.player_field.current_mana = 1
			game.player_field.slots[0] = CardData.new("轻装剑士", 2, 5, 2)
			game.player2_field.slots[0] = CardData.new("装甲守卫", 4, 4, 1)
			game.player_hand.append(_parasite("共生虫", 1, 2, 2))
			game.player_hand.append(CardData.new("新兵", 1, 2, 1))


static func _spell(name: String, effect: String, value: int, target: String, side: String, cost: int) -> CardData:
	var card := CardData.new(name, cost, 1, 0, [{"skill_name": name, "trigger": "on_cast", "effects": [{"effect": effect, "value": value, "target": target, "target_side": side}]}])
	card.card_type = "spell"
	return card


static func _active_unit(name: String, cost: int, hp: int, atk: int, skill_name: String, effect: String, value: int) -> CardData:
	return CardData.new(name, cost, hp, atk, [{"skill_name": skill_name, "trigger": "on_activate", "effects": [{"effect": effect, "value": value, "target": "target_single", "target_side": "enemy"}]}])


static func _parasite(name: String, cost: int, hp: int, atk: int) -> CardData:
	var card := CardData.new(name, cost, hp, atk)
	card.card_type = "parasite"
	return card


static func _unit_with_buff(name: String, cost: int, hp: int, atk: int, buff_id: String) -> CardData:
	var card := CardData.new(name, cost, hp, atk)
	card.status_effects.append({"buff_id": buff_id, "value": 1, "duration": 2})
	return card


static func succeeded(game: RefCounted, id: String) -> bool:
	if game.turn_number != 2:
		return false
	match id:
		"resource": return _field_card(game.player_field, "巨人") != null
		"combination": return _field_card(game.player2_field, "守卫") == null
		"taunt": return _field_card(game.player2_field, "指挥官") == null
		"cleanse": return _field_card(game.player2_field, "压制者") == null
		"dispel": return _field_card(game.player2_field, "后排法师") == null
		"execute": return _field_card(game.player2_field, "重甲守卫") == null
		"parasite": return _field_card(game.player2_field, "装甲守卫") == null
	return false


static func stage(game: RefCounted, id: String) -> String:
	if succeeded(game, id):
		return "success"
	if game.turn_number != 2:
		return "failed"
	match id:
		"resource": return _resource_stage(game)
		"combination": return _combination_stage(game)
		"taunt": return _taunt_stage(game)
		"cleanse": return _cleanse_stage(game)
		"dispel": return _dispel_stage(game)
		"execute": return _execute_stage(game)
		"parasite": return _parasite_stage(game)
	return "failed"


static func _resource_stage(game: RefCounted) -> String:
	var giant := _hand_card(game.player_hand, "巨人")
	if giant == null:
		return "failed"
	var available: int = int(game.player_field.get_total_mana())
	if _hand_card(game.player_hand, "蓄势") != null:
		available += 3
	if available < giant.cost:
		return "failed"
	return "payoff" if _hand_card(game.player_hand, "蓄势") == null else "setup"


static func _combination_stage(game: RefCounted) -> String:
	var ally := _field_card(game.player_field, "先锋")
	if ally == null or ally.has_acted:
		return "failed"
	return "payoff" if ally.effective_atk() >= 5 else "setup"


static func _taunt_stage(game: RefCounted) -> String:
	var wall := _field_card(game.player2_field, "盾墙")
	var commander := _field_card(game.player2_field, "指挥官")
	if commander == null:
		return "success"
	if wall != null and wall.has_taunt():
		return "setup"
	for ally in game.player_field.slots:
		if ally != null and not ally.has_acted and not ally.is_silenced() and ally.effective_atk() >= commander.hp:
			return "payoff"
	return "failed"


static func _cleanse_stage(game: RefCounted) -> String:
	var ally := _field_card(game.player_field, "沉默先锋")
	if ally == null or ally.has_acted:
		return "failed"
	if not ally.is_silenced():
		return "payoff"
	return "setup" if _can_play(game, "净化术") else "failed"


static func _dispel_stage(game: RefCounted) -> String:
	var attacker := _field_card(game.player_field, "突击手")
	var guard := _field_card(game.player2_field, "盾卫")
	if attacker == null or attacker.has_acted:
		return "failed"
	if guard != null and guard.has_taunt():
		return "setup" if _can_play(game, "破法") else "failed"
	return "payoff"


static func _execute_stage(game: RefCounted) -> String:
	var executioner := _field_card(game.player_field, "处刑者")
	var guard := _field_card(game.player2_field, "重甲守卫")
	if executioner == null or executioner.has_acted or guard == null:
		return "failed"
	if guard.hp <= 3:
		return "payoff"
	return "setup" if _can_play(game, "精准削弱") else "failed"


static func _parasite_stage(game: RefCounted) -> String:
	var host := _field_card(game.player_field, "轻装剑士")
	if host == null or host.has_acted:
		return "failed"
	if not host.parasite_cards.is_empty():
		return "payoff"
	return "setup" if _can_play(game, "共生虫") else "failed"


static func failed(game: RefCounted, id: String) -> bool:
	return stage(game, id) == "failed"


static func progress(game: RefCounted, id: String) -> String:
	var current_stage := stage(game, id)
	if current_stage == "success":
		return _t("进度 2/2：目标完成。", "Progress 2/2: objective complete.")
	if current_stage == "failed":
		return _t("当前顺序已无法在本回合完成目标。", "The objective can no longer be completed this turn.")
	if current_stage == "setup":
		match id:
			"resource": return _t("进度 0/2：找出能启动资源连锁的手牌。", "Progress 0/2: find the card that starts the resource chain.")
			"combination": return _t("进度 0/2：先提升先锋的攻击力。", "Progress 0/2: increase the Vanguard's attack first.")
			"taunt": return _t("进度 0/2：先用合适的攻击者击破嘲讽盾墙。", "Progress 0/2: use the right attacker to break the taunting wall.")
			"cleanse": return _t("进度 0/2：先锋仍被沉默，先移除负面状态。", "Progress 0/2: the Vanguard is still silenced; remove the negative effect.")
			"dispel": return _t("进度 0/2：敌方嘲讽仍在，先移除正面状态。", "Progress 0/2: enemy Taunt is still active; remove the positive effect.")
			"execute": return _t("进度 0/2：重甲守卫尚未进入 3 血处刑线。", "Progress 0/2: the Armored Guard is still above the 3-HP execute threshold.")
			"parasite": return _t("进度 0/2：先把共生虫附着到正确宿主。", "Progress 0/2: attach the Symbiote to the correct host.")
	match id:
		"resource": return _t("进度 1/2：圣水已经补足，现在召唤巨人。", "Progress 1/2: mana is ready; summon the Giant.")
		"combination": return _t("进度 1/2：强化已完成，现在攻击守卫。", "Progress 1/2: the buff is ready; attack the Guard.")
		"taunt": return _t("进度 1/2：嘲讽已解除，用保留的强力单位消灭指挥官。", "Progress 1/2: Taunt is gone; use the stronger unit kept in reserve on the Commander.")
		"cleanse": return _t("进度 1/2：沉默已解除，现在攻击压制者。", "Progress 1/2: Silence is gone; attack the Suppressor.")
		"dispel": return _t("进度 1/2：嘲讽已驱散，现在攻击后排法师。", "Progress 1/2: Taunt is dispelled; attack the Backline Mage.")
		"execute": return _t("进度 1/2：目标已进入处刑线，发动终结打击。", "Progress 1/2: the target is in execute range; use Final Blow.")
		"parasite": return _t("进度 1/2：攻击加成已生效，现在攻击装甲守卫。", "Progress 1/2: the attack bonus is active; attack the Armored Guard.")
	return ""


static func failure_reason(game: RefCounted, id: String) -> String:
	if game.turn_number != 2:
		return _t("本回合已经结束，请重试并调整行动顺序。", "The turn ended; retry with a different action order.")
	match id:
		"resource":
			if _hand_card(game.player_hand, "巨人") == null:
				return _t("巨人已经离开手牌，目标无法完成。", "The Giant left your hand, so the objective cannot be completed.")
			return _t("你先消耗了基础圣水，剩余资源即使加上“蓄势”也不足 5 点。", "Base mana was spent too early; even Momentum can no longer reach 5 mana.")
		"combination": return _t("先锋在获得强化前已经行动，本回合无法再次攻击。", "The Vanguard acted before receiving the buff and cannot attack again this turn.")
		"taunt": return _t("高攻击单位被用来击破盾墙，剩余攻击者无法消灭指挥官。", "The stronger attacker was spent on the wall, leaving too little attack for the Commander.")
		"cleanse": return _t("圣水或行动已被消耗，先锋的沉默没有及时解除。净化和治疗用途不同。", "Mana or the action was spent before Silence was removed. Cleanse and healing serve different purposes.")
		"dispel": return _t("嘲讽没有被正确驱散，突击手已无法攻击后排目标。", "Taunt was not dispelled correctly, so the attacker can no longer reach the backline target.")
		"execute": return _t("目标没有降到 3 血处刑线，或处刑者过早行动。", "The target never reached 3 HP, or the Executioner acted too early.")
		"parasite": return _t("共生虫附着到了错误目标，或剑士在获得加成前已经行动。", "The Symbiote was attached to the wrong target, or the Swordsman acted before receiving its bonus.")
	return _t("目标已无法完成。", "The objective can no longer be completed.")


static func _can_play(game: RefCounted, card_name: String) -> bool:
	var card := _hand_card(game.player_hand, card_name)
	return card != null and card.cost <= game.player_field.get_total_mana()


static func _hand_card(hand: Array, card_name: String) -> CardData:
	for card in hand:
		if card != null and card.card_name == card_name:
			return card
	return null


static func _field_card(field: RefCounted, card_name: String) -> CardData:
	for card in field.slots:
		if card != null and card.card_name == card_name and card.is_alive():
			return card
	return null


static func show_picker(parent: Node) -> void:
	var existing := parent.get_node_or_null("ChallengePickerLayer")
	if existing != null:
		existing.queue_free()
	var popup := UITheme.make_popup_layer(parent, 150)
	var layer: CanvasLayer = popup["layer"]
	layer.name = "ChallengePickerLayer"
	var panel := PanelContainer.new()
	panel.name = "ChallengePicker"
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -330
	panel.offset_right = 330
	panel.offset_top = -310
	panel.offset_bottom = 310
	layer.add_child(panel)
	UITheme.apply_popup_frame(panel, "gold")
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 20)
	panel.add_child(margin)
	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 14)
	margin.add_child(root_box)
	var title_label := Label.new()
	title_label.text = _t("组合挑战 · 由浅入深", "Skill challenges · Learning path")
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_title(title_label, 24)
	root_box.add_child(title_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UITheme.apply_scrollbar(scroll.get_v_scroll_bar())
	root_box.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	for index in range(IDS.size()):
		var id: String = IDS[index]
		var button := Button.new()
		button.text = "%d. %s · %s" % [index + 1, title(id), difficulty(id)]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 42
		UITheme.apply_button(button, "primary" if index == 0 else "secondary")
		button.pressed.connect(func():
			layer.queue_free()
			NetworkManager.close_connection()
			PlayerData.configure_hotseat_battle(CardDatabase.beginner_deck(), CardDatabase.beginner_deck())
			PlayerData.practice_challenge_id = id
			UIMotion.change_scene("res://Main.tscn")
		)
		box.add_child(button)
		var label := Label.new()
		label.text = objective(id)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(530, 44)
		UITheme.apply_label(label, true)
		box.add_child(label)
	var close := Button.new()
	close.text = _t("关闭", "Close")
	close.custom_minimum_size = Vector2(120, 40)
	UITheme.apply_button(close, "secondary")
	close.pressed.connect(layer.queue_free)
	var close_row := HBoxContainer.new()
	close_row.alignment = BoxContainer.ALIGNMENT_CENTER
	close_row.add_child(close)
	root_box.add_child(close_row)
