class_name ParasiteRules
extends RefCounted

const _GameplayLog = preload("res://GameplayLog.gd")

const REASON_OK := "ok"
const REASON_NOT_PARASITE := "not_parasite"
const REASON_NO_MANA := "no_mana"
const REASON_NO_TARGET := "no_target"


static func is_parasite(card: CardData) -> bool:
	return card != null and card.is_parasite()


static func can_attach(card: CardData, target: CardData, current_mana: int) -> Dictionary:
	if not is_parasite(card):
		return {"ok": false, "reason": REASON_NOT_PARASITE}
	if target == null or not target.is_selectable():
		return {"ok": false, "reason": REASON_NO_TARGET}
	if card.cost > current_mana:
		return {"ok": false, "reason": REASON_NO_MANA}
	return {"ok": true, "reason": REASON_OK}


static func normalize_parasite_card(card: CardData) -> void:
	if not is_parasite(card):
		return
	card.parasite_damage_mode = CardData.normalize_parasite_damage_mode(card.parasite_damage_mode)
	for i in range(card.skills.size() - 1, -1, -1):
		var skill: Dictionary = card.skills[i]
		if str(skill.get("skill_type", SkillEngine.SKILL_TYPE_NORMAL)) == SkillEngine.SKILL_TYPE_TALENT \
				or not is_passive_trigger(skill.get("trigger", "")):
			card.skills.remove_at(i)


static func is_passive_trigger(trigger: String) -> bool:
	return trigger in [SkillEngine.TRIGGER_ON_ATTACK, SkillEngine.TRIGGER_ON_DAMAGED, SkillEngine.TRIGGER_ON_DEATH]


static func trigger_host_passives(trigger: String, host: CardData, context: Dictionary) -> void:
	if host == null or host.skills_disabled() or host.parasite_cards.is_empty():
		return
	for parasite in host.parasite_cards:
		if not parasite is CardData:
			continue
		for skill_index in range(parasite.skills.size()):
			var skill_dict: Dictionary = parasite.skills[skill_index]
			if skill_dict.get("trigger", "") == trigger and is_passive_trigger(trigger):
				var external_context := context.duplicate()
				external_context["metric_source_card"] = parasite
				SkillEngine.trigger_external_skill(skill_dict, host, external_context, parasite, skill_index)


static func attach(card: CardData, target: CardData) -> void:
	if card == null or target == null:
		return
	normalize_parasite_card(card)
	card.hp = card.max_hp
	target.parasite_cards.append(card)


static func release_all_to_discard(host: CardData, discard_pile: Array) -> void:
	if host == null or host.parasite_cards.is_empty():
		return
	for parasite in host.parasite_cards:
		if parasite is CardData:
			parasite.reset_to_base()
			discard_pile.append(parasite)
	host.parasite_cards.clear()


static func has_damage_absorber(host: CardData) -> bool:
	return active_damage_absorber(host) != null


# Damage resolution walks attachments from newest to oldest. Returning the
# same card keeps the HP affordance aligned with the next intercepted hit.
static func active_damage_absorber(host: CardData) -> CardData:
	if host == null:
		return null
	for i in range(host.parasite_cards.size() - 1, -1, -1):
		var parasite = host.parasite_cards[i]
		if parasite is CardData and parasite.parasite_absorbs_host_damage():
			return parasite
	return null


static func absorb_damage(target: CardData, amount: int, discard_pile: Array) -> int:
	return absorb_damage_detail(target, amount, discard_pile).get("remaining", amount)


static func absorb_damage_detail(target: CardData, amount: int, discard_pile: Array) -> Dictionary:
	var result := {"remaining": amount, "absorbed": 0, "parasite": null, "destroyed": false}
	if target == null or amount <= 0:
		return result
	for i in range(target.parasite_cards.size() - 1, -1, -1):
		var parasite: CardData = target.parasite_cards[i]
		if parasite == null:
			target.parasite_cards.remove_at(i)
			continue
		if not parasite.parasite_absorbs_host_damage():
			continue
		var before_hp: int = parasite.hp
		parasite.hp = max(0, parasite.hp - amount)
		var absorbed: int = before_hp - parasite.hp
		var destroyed := parasite.hp <= 0
		result = {"remaining": 0, "prevented": mini(amount,target.hp+target.temp_hp), "absorbed": absorbed, "parasite": parasite, "destroyed": destroyed}
		_GameplayLog.write("  [Parasite] %s blocks %d for %s (HP: %d/%d)" % [parasite.card_name, amount, target.card_name, parasite.hp, parasite.max_hp])
		if destroyed:
			target.parasite_cards.remove_at(i)
			parasite.reset_to_base()
			discard_pile.append(parasite)
		return result
	return result
