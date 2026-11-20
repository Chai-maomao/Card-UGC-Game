extends Node
var failures: Array[String] = []
func _ready() -> void:
	Locale.language = "zh"
	NetworkManager.close_connection()
	PlayerData.skill_tutorial_active = false
	await _empty_pile()
	await _normal_skill()
	_face_choice()
	_parasite_contribution()
	_spell_coverage()
	_export_art()
	if failures.is_empty(): print("TEST_SCREENSHOT_FIXES_OK"); get_tree().quit(0)
	else:
		for failure in failures: push_error(failure)
		get_tree().quit(1)
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _game():
	var game = HeadlessBattleSimulator._create_game([],[],91,PlayerData.DEFAULT_BATTLE_CONFIG)
	game.turn_number = 2
	return game
func _empty_pile() -> void:
	var popup = preload("res://CardCollectionDialog.gd").show_cards(self,[],"弃牌堆")
	await get_tree().process_frame
	popup._layout()
	check(popup.card_uis.is_empty() and popup.panel.size.y > 100,"empty discard viewer must render its empty message")
	popup.queue_free()
	await get_tree().process_frame
func _normal_skill() -> void:
	PlayerData.card_draft = {"card_type":"minion","skill1":{}}
	PlayerData.editing_skill_index = 0
	var editor = preload("res://SkillEditor.tscn").instantiate()
	add_child(editor)
	await get_tree().process_frame
	await get_tree().process_frame
	editor.current_trigger_key = SkillEngine.TRIGGER_ON_BOARD_CHANGED
	editor.effect_data = [{"effect":"gain_mana","target":"self","value":1}]
	var errors = SkillErrorChecker.new()
	errors.editor = editor
	check(errors.collect_errors().is_empty(),"normal board-change skill must compile without talent-only errors")
	check(not SkillErrorChecker.collect_semantic_issues(editor.effect_data,editor.current_trigger_key,true).is_empty(),"talent mode retains its restricted vocabulary")
	editor.queue_free()
	await get_tree().process_frame
func _face_choice() -> void:
	var game = _game()
	game.player_field.slots = [CardData.new("A",1,3,2),CardData.new("B",1,3,4),null,null,null]
	game.player_field.action_points = 0
	game.player_field.actions_taken = 1
	game.player_field.current_mana = 4
	var saved: Dictionary = game.export_initial_state()
	var copy = game.copy_for_simulation()
	var kept: Dictionary = game.end_player_turn(false)
	var paid: Dictionary = copy.end_player_turn(true)
	check(kept.total_damage == 0 and game.player_field.current_mana == 4,"AP-only must skip attacks requiring Elixir")
	check(paid.total_damage == 6 and copy.player_field.current_mana == 1,"accepting Elixir pays the actual increasing costs")
	var replay = _game()
	replay.apply_initial_state(saved,false)
	check(BattleRepro.apply_action(replay,{"type":"end_turn","allow_face_mana":false}).ok and replay.player2_field.player_hp == 30,"replay must preserve the decline choice")
func _parasite_contribution() -> void:
	var game = _game()
	var metrics := BattleMetrics.new()
	game.metrics_callable = metrics.record
	var host := CardData.new("Host",1,8,2)
	var parasite := CardData.new("Parasite",1,1,2)
	parasite.card_type = "parasite"
	host.parasite_cards.append(parasite)
	game.player_field.slots[0] = host
	game.player2_field.slots[0] = CardData.new("Victim",1,10,1)
	check(not game.execute_attack(0,0).is_empty(),"host attack fixture must execute")
	check(metrics.cards.get("Parasite",{}).get("damage",0) == 2 and metrics.cards.get("Host",{}).get("damage",0) == 2,"parasite and host split the actual attack contribution")
	var incoming = _game()
	var shield_metrics := BattleMetrics.new()
	incoming.metrics_callable = shield_metrics.record
	incoming.player_field.slots[0] = CardData.new("Attacker",1,8,4)
	var defender := CardData.new("Defender",1,8,1)
	var shield := CardData.new("Absorber",1,1,1)
	shield.card_type = "parasite"
	defender.parasite_cards.append(shield)
	incoming.player2_field.slots[0] = defender
	incoming.execute_attack(0,0)
	check(defender.hp == 8 and shield_metrics.cards.get("Absorber",{}).get("damage_prevented",0) == 4,"one-HP parasite that blocks the hit must receive actual prevention credit")
func _spell_coverage() -> void:
	for effect in ["damage","draw_cards","gain_attack"]:
		var game = _game()
		var metrics := BattleMetrics.new()
		game.metrics_callable = metrics.record
		var skill := {"trigger":"on_cast","effects":[{"effect":effect,"target":"target_single" if effect != "draw_cards" else "self","target_side":"enemy" if effect == "damage" else "ally","value":2}]}
		var spell := CardData.new("Spell-"+effect,1,1,0,[skill])
		spell.card_type = "spell"
		game.player_hand = [spell]
		game.player_field.slots[0] = CardData.new("Ally",1,5,1)
		game.player2_field.slots[0] = CardData.new("Enemy",1,5,1)
		check(game.cast_spell(0,0,0,2 if effect == "damage" else 1),"spell fixture must cast: "+effect)
		var row: Dictionary = metrics.cards.get(spell.card_name,{})
		if effect == "damage": check(row.get("damage",0) == 2,"direct spell damage remains measurable")
		else: check(row.get("unmeasured_effects",0) > 0,"unmeasured spell benefit must be disclosed: "+effect)
func _export_art() -> void:
	var image := Image.create(8,8,false,Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	var normal := "user://share-normal.png"
	var damaged := "user://share-damaged.png"
	image.save_png(normal)
	image.fill(Color.BLUE)
	image.save_png(damaged)
	var card := CardData.new("Art",1,2,1)
	card.art_path = normal
	card.damaged_art_path = damaged
	var package: Dictionary = JSON.parse_string(PlayerData.serialize_cards_for_share([card]))
	check(PlayerData.parse_share_package(JSON.stringify(package)).get("ok",false),"portable dual-art export must pass real import validation")
	var payload: Dictionary = package.cards[0]
	check(not payload.get("art_base64","").is_empty() and not payload.get("damaged_art_base64","").is_empty(),"export must embed both art files")
	var restored := CardData.new("Restored",0,1,0)
	PlayerData._restore_shared_art(restored,payload)
	check(FileAccess.get_sha256(restored.art_path) == FileAccess.get_sha256(normal) and FileAccess.get_sha256(restored.damaged_art_path) == FileAccess.get_sha256(damaged),"import must restore both embedded images byte for byte")

	card.card_type = "spell"
	card.hp = 1
	check(CardArtwork.selected_path(card) == normal,"legacy spell must always display its normal art")
	var spell_draft := PlayerData.card_to_draft(card)
	spell_draft["damaged_art_path"] = damaged
	check(PlayerData.build_card_from_draft(spell_draft).damaged_art_path.is_empty(),"spell drafts must discard damaged art")
	var legacy_data := PlayerData.serialize_card(card)
	legacy_data["damaged_art_path"] = damaged
	check(PlayerData.deserialize_card(legacy_data).damaged_art_path.is_empty(),"legacy spell loading must discard damaged art")
	var spell_package: Dictionary = JSON.parse_string(PlayerData.serialize_cards_for_share([card]))
	check(not spell_package.cards[0].has("damaged_art_base64"),"spell export must exclude damaged art")
	var spell := CardData.new("Spell",1,0,0)
	spell.card_type = "spell"
	PlayerData._restore_shared_art(spell,payload)
	check(not spell.art_path.is_empty() and spell.damaged_art_path.is_empty(),"spell import keeps normal art only")
	check(PlayerData.card_art_transfers([card]).size() == 1,"spell network transfer must send normal art only")
	PlayerData.apply_received_art([spell],PlayerData.DAMAGED_ART_INDEX_OFFSET,damaged)
	check(spell.damaged_art_path.is_empty(),"spell must reject legacy damaged-art transfers")
