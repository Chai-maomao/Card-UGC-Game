extends RefCounted
static func open(parent: Control, can_edit: Callable) -> CanvasLayer:
	var locked := func(): return not can_edit.call()
	return preload("res://presentation/BattleRulesEditor.gd").open(parent, PlayerData.battle_config.duplicate(true), locked, func(config):
		if can_edit.call() and MatchAgreement.valid_config(config):
			PlayerData.battle_config = config)
