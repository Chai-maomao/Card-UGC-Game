extends Node

const Picker = preload("res://CardCollectionDialog.gd")
const Game = preload("res://GameState.gd")
var failures: Array[String] = []


func _ready() -> void:
	NetworkManager.close_connection()
	PlayerData.configure_hotseat_battle(CardDatabase.playtest_deck(), CardDatabase.playtest_deck())
	_test_cost_lifecycle()
	var battle = preload("res://Main.tscn").instantiate()
	add_child(battle)
	await _settle()
	var cards: Array = []
	for i in range(6):
		var card: CardData = CardDatabase.playtest_deck()[0]
		card.card_name = "测试长名称卡牌 " + str(i)
		card.cost = 4
		card.base_cost = 4
		cards.append(card)
	battle.game.player_hand = cards.duplicate()
	battle._refresh_hand_ui()
	await _settle()
	var first_ui = battle.hand_container.get_child(0)
	battle._show_zero_cost_selection_popup(cards, 2, SkillRegistry.COST_REDUCTION_TURN, 1, cards)
	await _settle()
	var dialog = battle.get_child(battle.get_child_count() - 1)
	_assert(dialog.get_script() == Picker, "zero-cost selection must use the unified picker")
	dialog._select(true, 0)
	dialog._select(true, 1)
	_assert(dialog.selected.size() == 1, "selection must obey the one-card limit")
	_assert(dialog.selection_overlays[0].button_pressed and not dialog.selection_overlays[1].button_pressed, "the card mask must mark only the selected card")
	dialog._confirm()
	await _settle()
	_assert(cards[0].cost == 2 and cards[0].turn_cost_reduction == 2 and cards[1].cost == 4, "selection must reduce exactly the chosen card by X")
	_assert(battle.hand_container.get_child(0) == first_ui, "refresh must retain the existing hand node")
	_assert(first_ui.cost_label.text == Locale.t("card.cost", [2]), "reused node must display the changed cost immediately")
	_assert(first_ui.cost_label.get_theme_color("font_color") == UITheme.Tokens.CARD_DISCOUNT, "only a discounted card must show a green cost")
	var ordinary: Control = battle.hand_container.get_child(1)
	_assert(ordinary.cost_label.get_theme_color("font_color") == UITheme.Tokens.INK, "an affordable undiscounted card must show a neutral ink cost")
	battle.game.player_field.current_mana = 0
	battle._refresh_hand_ui()
	_assert(battle.hand_container.get_child(1).cost_label.get_theme_color("font_color") == UITheme.Tokens.CARD_DANGER, "an unaffordable card must show a red cost")
	_assert(battle.hand_container.get_child(0).cost_label.get_theme_color("font_color") == UITheme.Tokens.CARD_DISCOUNT, "a discounted card stays green even when unaffordable")
	var parasite: CardData = CardDatabase.playtest_deck().back()
	first_ui.set_card(parasite)
	_assert(first_ui.tooltip_text == "", "parasite face must not show its own redundant explanation")
	first_ui.tooltip_text = "old tooltip"
	first_ui.set_card(null)
	_assert(first_ui.tooltip_text.is_empty(), "empty reusable card must clear stale hints")
	var tinted := CardData.new("颜色恢复", 5, 2, 1)
	tinted.original_cost = 5
	tinted.cost = 0
	first_ui.set_card(tinted)
	tinted.reset_charm_cost()
	first_ui.refresh_cost_display()
	_assert(first_ui.cost_label.get_theme_color("font_color") == UITheme.Tokens.INK, "restored cost must clear the charm tint")
	first_ui.set_card(cards[0])
	_test_clone_and_lethal_preview(battle)
	if OS.get_cmdline_user_args().has("--visual"):
		DisplayServer.window_set_title("CARDEX · 降费与牌库弹窗验收")
		battle._show_zero_cost_selection_popup(cards.slice(1), 2, SkillRegistry.COST_REDUCTION_PERMANENT, 1, cards)
		return
	battle.queue_free()
	await _settle()
	for viewport_size in [Vector2i(640, 360), Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		var viewport := SubViewport.new()
		viewport.size = viewport_size
		add_child(viewport)
		for selecting in [false, true]:
			var picker = Picker.show_cards(viewport, cards, Locale.t("battle.reduce_cost_title", [2, Locale.term("cost_reduction_mode", SkillRegistry.COST_REDUCTION_TURN)]), 1 if selecting else 0)
			await _settle()
			_assert(Rect2(Vector2.ZERO, Vector2(viewport_size)).encloses(picker.panel.get_global_rect()), "popup must fit viewport " + str(viewport_size))
			_assert(picker.grid.size.x <= picker.scroll.size.x + 1, "grid must not overflow horizontally")
			for cell in picker.grid.get_children():
				var card_ui = cell.get_child(0).get_child(0)
				var face: Rect2 = card_ui.get_global_rect()
				_assert(not card_ui.get_node("CardShadow").visible, "cards embedded in a picker must not cast a loose-card shadow")
				_assert(absf(face.size.x / face.size.y - 0.75) < 0.001, "card preview must keep its aspect ratio")
				_assert(absf(card_ui.action_buttons.get_global_rect().get_center().x - face.get_center().x) < 1.1, "action grid must share the card centerline")
				for button in card_ui.action_buttons.get_children():
					if button.visible:
						if card_ui.action_buttons.columns == 1:
							_assert(absf(button.get_global_rect().get_center().x - face.get_center().x) < 1.1, "single-column skill button must share the card centerline")
						_assert(face.grow(1).encloses(button.get_global_rect()), "skill button must fit inside card")
				_assert(card_ui._get_drag_data(Vector2.ZERO) == null, "preview cards must not be draggable into battle")
			picker.queue_free()
			await _settle()
		viewport.queue_free()
		await _settle()
	if failures.is_empty():
		print("TEST_CARD_SELECTION_UI_OK: X-cost duration/clone/lethal preview, 4 sizes x 2 dialog modes")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("TEST_CARD_SELECTION_UI_FAILED: " + failure)
		get_tree().quit(1)


func _test_cost_lifecycle() -> void:
	var game := Game.new()
	game.quiet = true
	game.init_game(Callable(), 1)
	game.player_hand.clear()
	game.player2_hand.clear()
	var original := CardData.new("被魅惑者", 5, 8, 2)
	game.player2_field.slots[0] = original
	SkillEffectApplier._apply_charm(original, 1, {}, game.make_skill_context())
	var charmed: CardData = game.player_hand[0]
	_assert(charmed.cost == 0 and charmed.is_charmed(), "charm must move a free card into the caster hand")
	game.end_player_turn()
	_assert(charmed.cost == 5 and not charmed.is_charmed(), "charm must expire at the end of the current turn")
	game.is_player_turn = true
	var mana_before: int = game.player_field.current_mana
	var free := CardData.new("本回合降费", 3, 5, 1)
	free.apply_cost_reduction(9, false)
	game.player_hand = [free]
	game.player_field.current_mana = mana_before
	mana_before = game.player_field.current_mana
	_assert(game.summon_card(free, 0), "a reduction clamped to zero must be playable")
	_assert(free.cost == 3 and free.turn_cost_reduction == 0 and game.player_field.current_mana == mana_before, "playing must clear turn reduction after paying the reduced cost")
	var attachment := CardData.new("本回合寄生", 2, 3, 1)
	attachment.card_type = "parasite"
	attachment.apply_cost_reduction(2, false)
	game.player_hand.append(attachment)
	game.attach_parasite(game.player_hand.find(attachment), 1, 0)
	_assert(attachment.cost == 2 and attachment.turn_cost_reduction == 0, "parasite attachment counts as playing the card")
	var expiring := CardData.new("回合结束恢复", 4, 3, 1)
	expiring.apply_cost_reduction(2, false)
	game.active_hand().append(expiring)
	game.end_player_turn()
	_assert(expiring.cost == 4 and expiring.turn_cost_reduction == 0, "turn reduction must expire at owner turn end")
	var permanent := CardData.new("永久降费", 4, 3, 1)
	permanent.apply_cost_reduction(2, true)
	game.player_hand = [permanent]
	game.current_player = 1
	_assert(game.discard_card(permanent), "permanently discounted card must be discardable")
	_assert(permanent.cost == 2 and permanent.permanent_cost_reduction == 2, "permanent reduction must survive discard reset")
	game.shared_deck = [game.shared_discard.pop_back()]
	game.draw_cards(1, game.player_hand)
	_assert(game.player_hand.back().cost == 2, "permanent reduction must survive reshuffle and redraw")
	var restored: CardData = PlayerData.deserialize_card(PlayerData.serialize_card(permanent))
	_assert(restored.cost == 2 and restored.permanent_cost_reduction == 2, "battle serialization must preserve permanent cost reduction")
	var free_spell: CardData = CardDatabase.playtest_deck()[-2]
	free_spell.base_cost = 2
	free_spell.apply_cost_reduction(2, false)
	game.active_hand().append(free_spell)
	mana_before = game.active_field().current_mana
	_assert(game.cast_spell(game.active_hand().find(free_spell)), "temporary free spell must cast")
	_assert(free_spell.cost == 2 and free_spell.turn_cost_reduction == 0 and free_spell in game.shared_discard, "free spell must restore its cost on entering discard")
	_assert(game.active_field().current_mana == mana_before, "free spell must not spend mana")


func _test_clone_and_lethal_preview(battle) -> void:
	var source := CardData.new("来源", 1, 5, 4, [])
	var enemy := CardData.new("完整克隆目标", 3, 3, 2, [CardDatabase._fx_skill("测试", SkillEngine.TRIGGER_ON_ACTIVATE, [CardDatabase._fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_HEAL, 1)])])
	enemy.hp = 2
	enemy.temp_hp = 1
	enemy.field_atk_bonus = 2
	battle.game.player_field.slots[0] = source
	battle.game.player2_field.slots[0] = enemy
	battle.game.player_hand.clear()
	var clone_effect := {"target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "effect": SkillEngine.EFFECT_CLONE_ENEMY}
	SkillEffectApplier._apply_clone_enemy(enemy, 0, clone_effect, battle.game.make_skill_context(0, 0, 2))
	_assert(battle.game.player_hand.size() == 1, "clone must create one card in own hand")
	var clone: CardData = battle.game.player_hand[0]
	_assert(clone != enemy and clone.instance_id != enemy.instance_id, "clone must have independent object/runtime identity")
	_assert(clone.card_name == enemy.card_name and clone.hp == enemy.hp and clone.temp_hp == enemy.temp_hp and clone.effective_atk() == enemy.effective_atk() and clone.skills == enemy.skills, "clone must preserve the enemy card's complete current state")
	var wrong_side := CardData.new("己方不能克隆", 1, 2, 1)
	battle.game.player_field.slots[1] = wrong_side
	SkillEffectApplier._apply_clone_enemy(wrong_side, 0, clone_effect, battle.game.make_skill_context(0, 1, 1))
	_assert(battle.game.player_hand.size() == 1, "clone must reject a friendly battlefield target")

	battle.game.player_hand.clear()
	battle.game.player_field.slots[1] = null
	battle.game.player2_field.slots[0] = CardData.new("可击杀", 1, 3, 1)
	battle.current_attacker_idx = 0
	battle._update_slot_highlights()
	var enemy_slot = battle._their_slots_ui()[0]
	_assert(enemy_slot._lethal_hint, "a lethal attack target must receive the red lethal hint")
	battle.game.player2_field.slots[0].temp_hp = 2
	battle._update_slot_highlights()
	_assert(not enemy_slot._lethal_hint, "temporary HP must prevent a false lethal hint")
	battle.game.player2_field.slots[0].temp_hp = 0
	battle.game.player2_field.slots[0].immune_lethal = true
	battle._update_slot_highlights()
	_assert(not enemy_slot._lethal_hint, "lethal immunity must prevent a false lethal hint")
	battle.cancel_attack()

	source.skills = [{"skill_name": "致命火花", "trigger": SkillEngine.TRIGGER_ON_ACTIVATE, "probability": 100, "effects": [{"target": SkillEngine.TARGET_SINGLE, "target_side": SkillEngine.TARGET_SIDE_ENEMY, "effect": SkillEngine.EFFECT_DAMAGE, "value": 4, "probability": 100}]}]
	battle.game.player2_field.slots[0] = CardData.new("技能可击杀", 1, 4, 1)
	battle.activate_targeting = true
	battle.activate_source_slot = 0
	battle.activate_skill_idx = 0
	battle._update_slot_highlights()
	_assert(enemy_slot._lethal_hint, "a guaranteed lethal targeted damage skill must receive the red lethal hint")
	source.skills[0].probability = 50
	battle._update_slot_highlights()
	_assert(not enemy_slot._lethal_hint, "a chance-based skill must not show a misleading guaranteed-lethal hint")
	battle.cancel_attack()


func _settle() -> void:
	for frame in range(5):
		await get_tree().process_frame


func _assert(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)
