class_name MatchAgreement
extends Node

var lobby: Node
var pending := false
var offer: Dictionary = {}
var local_accepted := false
var remote_accepted := false
var completed := false


func setup(owner_lobby: Node) -> void:
	lobby = owner_lobby
	NetworkManager.match_offer_received.connect(_receive_offer)
	NetworkManager.match_offer_accepted.connect(_receive_accept)


static func deck_signature(cards: Array) -> String:
	var entries: Array = []
	for card in cards:
		entries.append(SharePackage.gameplay_signature(PlayerData.serialize_card(card)))
	return BattleRepro.canonical_text(entries).sha256_text()


static func valid_config(config: Dictionary) -> bool:
	for item in [["mana_per_turn", 0, 10], ["draw_per_turn", 1, 6], ["starting_hp", 1, 99], ["second_extra_cards", 0, 5], ["second_extra_mana", 0, 10]]:
		var value: Variant = config.get(item[0])
		if not (value is int or value is float) or float(value) != floor(float(value)) or value < item[1] or value > item[2]: return false
	for key in ["death_compensation", "face_damage_compensation"]:
		if not config.get(key) is bool: return false
	return config.size() == 7


static func digest(data: Dictionary) -> String:
	return BattleRepro.canonical_text(data).sha256_text()


func begin() -> void:
	if pending: return
	pending = true
	if NetworkManager.is_authority():
		offer = {"rules": PlayerData.battle_config.duplicate(true), "p1": deck_signature(PlayerData.battle_deck), "p2": deck_signature(PlayerData.opponent_battle_deck)}
		NetworkManager.rpc_match_offer.rpc(offer)
		_show_offer()
	elif not offer.is_empty():
		_show_offer()


func _receive_offer(data: Dictionary) -> void:
	if NetworkManager.is_authority() or not valid_config(data.get("rules", {})): return
	if str(data.get("p2", "")) != deck_signature(PlayerData.battle_deck) or str(data.get("p1", "")) != deck_signature(PlayerData.opponent_battle_deck): return
	if not offer.is_empty(): return
	offer = data.duplicate(true)
	if pending: _show_offer()


func _show_offer() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "确认本局规则和牌组" if Locale.language == "zh" else "Confirm match rules and decks"
	var rules: Dictionary = offer.rules
	var text := ""
	for key in PlayerData.DEFAULT_BATTLE_CONFIG:
		var shown := str(rules[key])
		if rules[key] is bool:
			shown = ("开启" if rules[key] else "关闭") if Locale.language == "zh" else ("On" if rules[key] else "Off")
		text += "%s: %s\n" % [Locale.t("battle_config." + key), shown]
	text += ("\n双方已交换所选牌组；本局使用全部已提交卡牌。\n我方 %d 张，对方 %d 张。确认后等待双方同意。" if Locale.language == "zh" else "\nBoth submitted decks are included in this match.\nYour cards: %d; opponent: %d. Both players must agree.") % [PlayerData.battle_deck.size(), PlayerData.opponent_battle_deck.size()]
	var deck_rows := [["我方", PlayerData.battle_deck], ["对方", PlayerData.opponent_battle_deck]] if Locale.language == "zh" else [["You", PlayerData.battle_deck], ["Opponent", PlayerData.opponent_battle_deck]]
	for pair in deck_rows:
		var names: PackedStringArray = []
		for card in pair[1]: names.append(card.card_name)
		text += "\n%s: %s" % [pair[0], ", ".join(names)]
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(620, 340)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(label)
	dialog.add_child(scroll)
	dialog.get_ok_button().text = "确认" if Locale.language == "zh" else "Confirm"
	dialog.get_cancel_button().text = "取消" if Locale.language == "zh" else "Cancel"
	add_child(dialog)
	dialog.confirmed.connect(func():
		local_accepted = true
		PlayerData.battle_config = rules.duplicate(true)
		NetworkManager.rpc_match_offer_accept.rpc(digest(offer), NetworkManager.player_number)
		dialog.queue_free()
		_finish()
	)
	dialog.canceled.connect(func(): lobby._on_back_pressed())
	UITheme.apply_dialog(dialog, true)
	dialog.popup_centered()


func _receive_accept(hash_value: String) -> void:
	if not offer.is_empty() and hash_value == digest(offer):
		remote_accepted = true
		_finish()


func _finish() -> void:
	if completed or not (local_accepted and remote_accepted): return
	completed = true
	if NetworkManager.is_authority(): lobby._continue_agreed_start()
