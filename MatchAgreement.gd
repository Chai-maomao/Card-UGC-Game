class_name MatchAgreement
extends Node

signal confirmation_opening
signal confirmation_completed
signal preparation_reset

var lobby: Node
var pending := false
var offer: Dictionary = {}
var local_accepted := false
var remote_accepted := false
var completed := false
var confirmation_blocked: Callable
var _card_art_pending := false
var _confirmation_deferred := false

func reset() -> void:
	pending = false
	offer.clear()
	local_accepted = false
	remote_accepted = false
	completed = false
	_card_art_pending = false
	_confirmation_deferred = false
	for child in get_children():
		if child is ConfirmationDialog:
			child.hide()
			child.queue_free()
	preparation_reset.emit()


func setup(owner_lobby: Node) -> void:
	lobby = owner_lobby
	NetworkManager.match_offer_received.connect(_receive_offer)
	NetworkManager.match_offer_accepted.connect(_receive_accept)
	NetworkManager.room_link_wait_changed.connect(_update_confirmation_feedback)


func _update_confirmation_feedback() -> void:
	var waiting := NetworkManager.room_link_waiting()
	for child in get_children():
		if child is ConfirmationDialog and not child.is_queued_for_deletion():
			var confirm: Button = child.get_ok_button()
			var move_focus := waiting and confirm.has_focus()
			confirm.disabled = waiting
			var status := child.get_node("MatchContent/ConfirmationStatus") as Label
			if waiting:
				status.text = Locale.t("wait.room_link_confirming")
			else:
				status.text = Locale.t("wait.modal_opponent_confirmed" if remote_accepted else "wait.modal_opponent_pending")
			if move_focus:
				child.get_cancel_button().grab_focus()


static func deck_signature(cards: Array) -> String:
	var entries: Array = []
	for card in cards:
		entries.append(SharePackage.gameplay_signature(PlayerData.serialize_card(card)))
	return BattleRepro.canonical_text(entries).sha256_text()


static func valid_config(config: Dictionary) -> bool:
	config = config.duplicate()
	for key in ["draw_pile_visible", "draw_pile_ordered"]:
		if config.has(key):
			if not config[key] is bool: return false
			config.erase(key)
	var clock := preload("res://BattleActionClock.gd")
	if config.has(clock.KEYS[0]):
		if not config[clock.KEYS[0]] is bool: return false
		config.erase(clock.KEYS[0])
	for key in [clock.KEYS[1], clock.KEYS[2]]:
		if not config.has(key): continue
		var seconds: Variant = config[key]
		if not (seconds is int or seconds is float) or seconds < clock.MIN_SECONDS or seconds > clock.MAX_SECONDS or seconds != floor(seconds):
			return false
		config.erase(key)
	if config.has("mana_increment"):
		var increment: Variant = config["mana_increment"]
		if not (increment is int or increment is float) or increment != floor(increment) or increment < 1 or increment > 10:
			return false
		config.erase("mana_increment")
	if config.has("face_damage_compensation_mana"):
		var mana: Variant = config["face_damage_compensation_mana"]
		if not (mana is int or mana is float) or mana < 1 or mana > PlayerData.MAX_FACE_DAMAGE_COMPENSATION_MANA or mana != floor(mana):
			return false
		config.erase("face_damage_compensation_mana")
	for item in [["mana_per_turn", 0, 10], ["draw_per_turn", 1, 8], ["starting_hp", 1, 99], ["second_extra_cards", 0, 5], ["second_extra_mana", 0, 10]]:
		var value: Variant = config.get(item[0])
		if not (value is int or value is float) or float(value) != floor(float(value)) or value < item[1] or value > item[2]: return false
	for key in ["death_compensation", "face_damage_compensation"]:
		if not config.get(key) is bool: return false
	for key in ["action_base", "action_empty_slot_factor", "action_empty_hand_factor", "action_mana_factor"]:
		if not config.has(key):
			if config.size() != 7: return false
			continue # legacy local rules
		var value: Variant = config[key]
		if not (value is int or value is float) or not is_finite(float(value)) or value < 0 or value > 20: return false
	return config.size() == 7 or config.size() == 11


static func digest(data: Dictionary) -> String:
	return BattleRepro.canonical_text(data).sha256_text()


func begin(card_art_pending: bool = false) -> void:
	if pending: return
	pending = true
	_card_art_pending = card_art_pending
	if NetworkManager.is_authority():
		offer = {"id": Crypto.new().generate_random_bytes(12).hex_encode(), "rules": PlayerData.battle_config.duplicate(true), "p1": deck_signature(PlayerData.battle_deck), "p2": deck_signature(PlayerData.opponent_battle_deck)}
		if NetworkManager.session_mode == NetworkManager.SESSION_MODE_ROOM:
			offer["preparation"] = NetworkManager.room_preparation_generation
		NetworkManager.rpc_match_offer.rpc(offer)
		_show_offer()
	else:
		_show_received_offer()


func _receive_offer(data: Dictionary) -> void:
	if NetworkManager.is_authority() or data.get("room_preview", false) or not valid_config(data.get("rules", {})): return
	if not lobby.i_am_ready or lobby.cancelling_preparation: return
	if NetworkManager.session_mode == NetworkManager.SESSION_MODE_ROOM:
		if not NetworkManager.room_preparation_available or data.get("preparation") != NetworkManager.room_preparation_generation:
			return
	if not NetworkManager.valid_battle_match_id(str(data.get("id", ""))): return
	if not offer.is_empty(): return
	offer = data.duplicate(true)
	_show_received_offer()


func _show_received_offer() -> void:
	if not pending or offer.is_empty():
		return
	if str(offer.get("p2", "")) != deck_signature(PlayerData.battle_deck) or str(offer.get("p1", "")) != deck_signature(PlayerData.opponent_battle_deck):
		offer.clear()
		if NetworkManager.session_mode == NetworkManager.SESSION_MODE_ROOM:
			lobby.cancel_match_preparation("offer_mismatch")
		return
	_show_offer()


func resume_deferred_confirmation() -> void:
	if _confirmation_deferred:
		_show_offer()


func _show_offer() -> void:
	if confirmation_blocked.is_valid() and confirmation_blocked.call():
		_confirmation_deferred = true
		return
	_confirmation_deferred = false
	confirmation_opening.emit()
	var dialog := ConfirmationDialog.new()
	dialog.dialog_hide_on_ok = false
	dialog.title = "确认本局规则和牌组" if Locale.language == "zh" else "Confirm match rules and decks"
	var rules: Dictionary = offer.rules
	var text := ("我方 %d 张，对手 %d 张。双方确认后开局。" if Locale.language == "zh" else "Your deck: %d cards. Opponent: %d cards. The match starts when both players confirm.") % [PlayerData.battle_deck.size(), PlayerData.opponent_battle_deck.size()]
	if _card_art_pending:
		text += "\n" + Locale.t("wait.art_fallback")
	elif NetworkManager.is_dedicated_server and not NetworkManager.server_allows_card_art:
		text += "\n" + Locale.t("wait.art_relay_disabled")
	text += "\n\n"
	for row in BattleFieldRules.rows(rules):
		text += "%s: %s\n" % [str(row[0]).trim_suffix(":"), row[1]]
	var deck_rows := [["我方", PlayerData.battle_deck], ["对方", PlayerData.opponent_battle_deck]] if Locale.language == "zh" else [["You", PlayerData.battle_deck], ["Opponent", PlayerData.opponent_battle_deck]]
	for pair in deck_rows:
		var names: PackedStringArray = []
		for card in pair[1]: names.append(card.card_name)
		text += "\n%s: %s" % [pair[0], ", ".join(names)]
	var content := VBoxContainer.new()
	content.name = "MatchContent"
	content.add_theme_constant_override("separation", 10)
	var notice := Label.new()
	notice.name = "ConfirmationStatus"
	notice.set_meta("keyword_literal", true)
	UITheme.apply_label(notice)
	content.add_child(notice)
	var scroll := ScrollContainer.new()
	scroll.name = "MatchDetails"
	scroll.custom_minimum_size = Vector2(620, 312)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(label)
	dialog.add_child(content)
	add_child(dialog)
	dialog.confirmed.connect(func():
		if NetworkManager.room_link_waiting():
			return
		local_accepted = true
		PlayerData.battle_config = rules.duplicate(true)
		NetworkManager.rpc_match_offer_accept.rpc(digest(offer), NetworkManager.player_number)
		dialog.hide()
		dialog.queue_free()
		_finish()
	)
	dialog.canceled.connect(func():
		dialog.queue_free()
		if lobby.has_method("cancel_match_preparation"):
			lobby.cancel_match_preparation()
		else:
			lobby._on_back_pressed()
	)
	UITheme.apply_dialog(dialog, true)
	dialog.get_ok_button().text = Locale.t("wait.confirm_match")
	dialog.get_cancel_button().text = Locale.t("wait.cancel_preparation")
	_update_confirmation_feedback()
	dialog.popup_centered()
	if dialog.get_ok_button().disabled:
		dialog.get_cancel_button().grab_focus()
	else:
		dialog.get_ok_button().grab_focus()


func _receive_accept(hash_value: String) -> void:
	if not offer.is_empty() and hash_value == digest(offer):
		remote_accepted = true
		_update_confirmation_feedback()
		_finish()


func _finish() -> void:
	if completed or not (local_accepted and remote_accepted): return
	completed = true
	confirmation_completed.emit()
	if NetworkManager.is_authority(): lobby._continue_agreed_start()
