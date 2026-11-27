class_name SharePackage
extends RefCounted


static func metadata(value: Dictionary = {}) -> Dictionary:
	return {"author": str(value.get("author", "")).left(80), "revision": str(value.get("revision", "1")).left(40), "source": str(value.get("source", "")).left(240)}


static func build(cards: Array, deck: Dictionary = {}, provenance: Dictionary = {}) -> Dictionary:
	var result := {"version": 2, "type": "cards" if deck.is_empty() else "deck", "cards": cards, "provenance": metadata(provenance)}
	if not deck.is_empty(): result["deck"] = deck
	return result


static func gameplay_signature(card: Dictionary) -> String:
	var values := {}
	for key in ["name", "cost", "atk", "max_hp", "skills", "card_type", "gender", "parasite_damage_mode"]:
		values[key] = card.get(key)
	# Editor layout and disconnected blocks are authoring data, not game rules.
	if values.get("skills") is Array:
		values["skills"] = values["skills"].duplicate(true)
		for skill in values["skills"]:
			if skill is Dictionary: skill.erase("_workspace")
	return BattleRepro.canonical_text(values)


static func changes(package: Dictionary, local_cards: Array) -> Dictionary:
	var local := {}
	for card in local_cards:
		local[str(card.get("card_id", ""))] = card
	var result := {"added": 0, "changed": 0, "unchanged": 0}
	for card in package.get("cards", []):
		var id := str(card.get("card_id", ""))
		if id.is_empty() or not local.has(id): result.added += 1
		elif gameplay_signature(card) == gameplay_signature(local[id]): result.unchanged += 1
		else: result.changed += 1
	return result


static func summary(package: Dictionary) -> String:
	var info := metadata(package.get("provenance", {}))
	var card_count: int = package.get("cards", []).size()
	if Locale.language == "zh":
		return "作者：%s\n内容版本：%s\n来源：%s\n\n卡牌 %d 张" % [info.author, info.revision, info.source, card_count]
	var count_text := "%d card" if card_count == 1 else "%d cards"
	return "Author: %s\nContent revision: %s\nSource: %s\n\n%s" % [info.author, info.revision, info.source, count_text % card_count]


static func edit_metadata(parent: Node, package: Dictionary, accepted: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "分享信息" if Locale.language == "zh" else "Share details"
	var box := VBoxContainer.new()
	dialog.add_child(box)
	var inputs := {}
	var info := metadata(package.get("provenance", {}))
	var fields := [["author", "作者", 80], ["revision", "内容版本", 40], ["source", "原作或来源", 240]] if Locale.language == "zh" else [["author", "Author", 80], ["revision", "Content revision", 40], ["source", "Original work or source", 240]]
	for field in fields:
		var label := Label.new()
		label.text = field[1]
		box.add_child(label)
		var input := LineEdit.new()
		input.max_length = field[2]
		input.text = info[field[0]]
		input.custom_minimum_size.x = 440
		box.add_child(input)
		inputs[field[0]] = input
	dialog.confirmed.connect(func():
		var updated := {}
		for key in inputs: updated[key] = inputs[key].text
		package["provenance"] = metadata(updated)
		accepted.call(package)
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	parent.add_child(dialog)
	dialog.get_ok_button().text = "继续导出" if Locale.language == "zh" else "Continue"
	dialog.get_cancel_button().text = "取消" if Locale.language == "zh" else "Cancel"
	UITheme.apply_dialog(dialog, true)
	dialog.popup_centered()
