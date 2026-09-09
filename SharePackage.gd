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


static func summary(package: Dictionary, local_cards: Array = []) -> String:
	var info := metadata(package.get("provenance", {}))
	var diff := changes(package, local_cards)
	if Locale.language == "zh":
		return "作者：%s\n内容版本：%s\n来源：%s\n\n卡牌 %d 张：新增 %d，玩法变更 %d，玩法相同 %d。\n作者与来源为分享者填写；卡图差异未计入玩法比较。" % [info.author, info.revision, info.source, package.get("cards", []).size(), diff.added, diff.changed, diff.unchanged]
	return "Author: %s\nContent revision: %s\nSource: %s\n\n%d cards: %d new, %d gameplay changes, %d unchanged.\nAttribution is supplied by the sharer; artwork is excluded from gameplay comparison." % [info.author, info.revision, info.source, package.get("cards", []).size(), diff.added, diff.changed, diff.unchanged]


static func edit_metadata(parent: Node, package: Dictionary, accepted: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "分享信息" if Locale.language == "zh" else "Share details"
	var box := VBoxContainer.new()
	dialog.add_child(box)
	var inputs := {}
	var info := metadata(package.get("provenance", {}))
	for field in [["author", "作者 / Author", 80], ["revision", "内容版本 / Revision", 40], ["source", "原作或来源 / Source", 240]]:
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
	dialog.popup_centered()
