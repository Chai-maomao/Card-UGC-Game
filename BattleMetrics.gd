class_name BattleMetrics
extends RefCounted

# Observations are local diagnostics, never synchronized game state.
const VERSION := 3
const UNKNOWN := "__unattributed__"
const MAX_STATUS_ORIGINS := 2048
const KEYS := ["summons", "casts", "attaches", "skills", "attacks", "automatic_attacks", "unit_actions", "action_points_spent", "mana_spent", "temporary_mana_spent", "action_mana_spent", "mana_gained", "enemy_mana_gained", "mana_refunded", "mana_removed", "mana_drained", "damage", "hero_damage", "parasite_damage", "shield_damage", "friendly_damage", "healing", "enemy_healing", "shield_granted", "damage_prevented", "unmeasured_effects"]
var cards: Dictionary = {}
var by_identity: Dictionary = {}
var identity_names: Dictionary = {}
var status_origins: Array = []
var lost_status_origins := 0


static func empty() -> Dictionary:
	var result := {}
	for key in KEYS: result[key] = 0
	return result


static func identity_of(card: CardData) -> String:
	if card == null: return UNKNOWN
	if not card.card_id.is_empty(): return card.card_id
	return "anonymous:" + var_to_str([card.card_name, card.base_cost, card.base_max_hp, card.base_atk, card.card_type, card.gender, card.parasite_damage_mode, card.skills]).sha256_text()


func clear() -> void:
	cards.clear()
	by_identity.clear()
	identity_names.clear()
	status_origins.clear()
	lost_status_origins = 0


func record(event: Dictionary) -> void:
	var kind := str(event.get("kind", ""))
	if kind == "reset":
		clear()
		return
	if kind == "status_origin":
		_prune_status_origins()
		if status_origins.size() >= MAX_STATUS_ORIGINS:
			lost_status_origins += 1
			return
		status_origins.append({"status": event.status, "target": event.get("status_target"), "source": event.source.duplicate(true), "source_player": event.source_player})
		return
	if event.has("status"):
		for index in range(status_origins.size() - 1, -1, -1):
			var origin: Dictionary = status_origins[index]
			if is_same(origin.status, event.status):
				event = event.duplicate()
				event.source = origin.source
				event.source_player = origin.source_player
				if kind == "status_expired": status_origins.remove_at(index)
				break
		if kind == "status_expired": return
	var source: Dictionary = event.get("source", {})
	var name := str(source.get("name", UNKNOWN))
	if name.is_empty(): name = UNKNOWN
	if not cards.has(name): cards[name] = empty()
	var identity := str(source.get("identity", UNKNOWN))
	if not by_identity.has(identity): by_identity[identity] = empty()
	identity_names[identity] = name
	_add_event(cards[name], event)
	_add_event(by_identity[identity], event)


func _add_event(row: Dictionary, event: Dictionary) -> void:
	var kind := str(event.get("kind", ""))
	var amount := maxi(0, int(event.get("amount", 0)))
	match kind:
		"payment":
			row.mana_spent += int(event.get("mana", 0))
			row.temporary_mana_spent += int(event.get("temporary_mana", 0))
			row.action_points_spent += int(event.get("points", 0))
			var action := str(event.get("action", ""))
			match action:
				"summon": row.summons += 1
				"cast": row.casts += 1
				"attach": row.attaches += 1
				"activate": row.skills += 1
				"attack": row.attacks += 1
				"automatic": row.automatic_attacks += 1
			if action in ["activate", "attack", "automatic"]:
				row.unit_actions += 1
				row.action_mana_spent += int(event.get("mana", 0))
		"damage", "parasite_damage", "shield_damage":
			var friendly := int(event.get("source_player", 0)) == int(event.get("target_player", -1))
			if friendly:
				if kind != "shield_damage": row.friendly_damage += amount
			elif kind == "shield_damage":
				row.shield_damage += amount
			else:
				row.damage += amount
				if kind == "parasite_damage": row.parasite_damage += amount
				if event.get("hero", false): row.hero_damage += amount
		"healing":
			if int(event.get("source_player", 0)) == int(event.get("target_player", -1)):
				row.healing += amount
			else: row.enemy_healing += amount
		"shield": row.shield_granted += amount
		"damage_prevented": row.damage_prevented += amount
		"unmeasured_effect": row.unmeasured_effects += 1
		"mana_gained":
			if int(event.get("source_player", 0)) == int(event.get("target_player", -1)): row.mana_gained += amount
			else: row.enemy_mana_gained += amount
		"mana_refunded": row.mana_refunded += amount
		"mana_removed": row.mana_removed += amount
		"mana_drained": row.mana_drained += amount


func _prune_status_origins() -> void:
	for index in range(status_origins.size() - 1, -1, -1):
		var target_ref: Variant = status_origins[index].get("target")
		if not target_ref is WeakRef: continue
		var target: CardData = target_ref.get_ref()
		var retained := false
		if target != null:
			for status in target.status_effects:
				if is_same(status, status_origins[index].status):
					retained = true
					break
		if not retained: status_origins.remove_at(index)


func snapshot() -> Dictionary:
	_prune_status_origins()
	return {"metrics_version": VERSION, "cards": cards.duplicate(true), "by_identity": by_identity.duplicate(true), "identity_names": identity_names.duplicate(), "lost_status_origins": lost_status_origins}
