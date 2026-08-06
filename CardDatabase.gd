class_name CardDatabase
extends RefCounted

const _TargetResolver = preload("res://SkillTargetResolver.gd")

# ============================================
# Preset card database — all built-in cards defined here
# ============================================

# Player starter cards
static func player_starters() -> Array:
	return [
		CardData.new("Misaka",     3, 4, 3, []),
		CardData.new("Kuroko",     2, 3, 2, []),
		CardData.new("Uiharu",     1, 2, 1, []),
		CardData.new("Saten",      2, 4, 2, []),
	]


# Default library seeded into a player's collection on first launch.
# Five vanilla bodies plus five skill cards.
static func starter_library() -> Array:
	return [
		# --- No-skill bodies (cost / hp / atk) ---
		CardData.new("狂战士", 4, 4, 5, []),
		CardData.new("骑士",   3, 5, 3, []),
		CardData.new("哥布林", 1, 2, 2, []),
		CardData.new("巨人",   5, 8, 3, []),
		CardData.new("野蛮人", 3, 4, 4, []),

		# --- 精灵: 召唤时魅惑 1 个目标 ---
		CardData.new("精灵", 4, 3, 1, [
			_fx_skill("魅惑", SkillEngine.TRIGGER_ON_SUMMON, [
				_fx(SkillEngine.TARGET_SINGLE, SkillEngine.EFFECT_CHARM, 1, "", 0, 1),
			]),
		]),

		# --- 牧师: 主动为自己及两边治疗 2 点生命 ---
		CardData.new("牧师", 2, 4, 1, [
			_fx_skill("祈祷", SkillEngine.TRIGGER_ON_ACTIVATE, [
				_fx(SkillEngine.TARGET_SELF_SIDES, SkillEngine.EFFECT_HEAL, 2),
			]),
		]),

		# --- 圣骑士: 主动为自己及两边提供 2 点护盾 ---
		CardData.new("圣骑士", 3, 3, 3, [
			_fx_skill("圣盾", SkillEngine.TRIGGER_ON_ACTIVATE, [
				_fx(SkillEngine.TARGET_SELF_SIDES, SkillEngine.EFFECT_SHIELD, 2),
			]),
		]),

		# --- 猎手: 受伤时回复 1 点生命，并有 50% 概率获得减伤 50% ---
		CardData.new("猎手", 2, 3, 2, [
			_fx_skill("闪躲", SkillEngine.TRIGGER_ON_DAMAGED, [
				_fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_HEAL, 1),
				_fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_ADD_BUFF, 50, SkillEngine.BUFF_DAMAGE_REDUCTION, 1, 0, 50),
			]),
		]),

		# --- 女巫: 主动为敌方目标添加霉运 75%，持续 1 回合 ---
		CardData.new("女巫", 3, 3, 1, [
			_fx_skill("诅咒", SkillEngine.TRIGGER_ON_ACTIVATE, [
				_fx(SkillEngine.TARGET_SINGLE, SkillEngine.EFFECT_ADD_BUFF, 75, SkillEngine.BUFF_MISFORTUNE, 1),
			]),
		]),

		# --- 炮术师: 主动随机轰击 2 个敌人，每个造成 1-3 点伤害 ---
		CardData.new("炮术师", 4, 4, 2, [
			_fx_skill("随机炮击", SkillEngine.TRIGGER_ON_ACTIVATE, [
				_fx_random(SkillEngine.TARGET_ALL, SkillEngine.EFFECT_DAMAGE, 1, 3, "", 0, 2, 100, SkillEngine.TARGET_SIDE_ENEMY),
			]),
		]),

		# --- 军旗手: 召唤时根据我方场上随从数量为全体友方加护盾 ---
		CardData.new("军旗手", 3, 4, 1, [
			_fx_skill("列阵护卫", SkillEngine.TRIGGER_ON_SUMMON, [
				_fx_var(SkillEngine.TARGET_ALL, SkillEngine.EFFECT_SHIELD, SkillEngine.VAR_FIELD_ALLY, 0, "", 0, 0, 100, SkillEngine.TARGET_SIDE_ALLY),
			]),
		]),

		# --- 荆棘守卫: 召唤时获得嘲讽与反伤 ---
		CardData.new("荆棘守卫", 3, 6, 1, [
			_fx_skill("荆棘壁垒", SkillEngine.TRIGGER_ON_SUMMON, [
				_fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_ADD_BUFF, 1, SkillEngine.BUFF_TAUNT, 2),
				_fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_ADD_BUFF, 1, SkillEngine.BUFF_THORNS, 2),
			]),
		]),

		# --- 学者: 召唤时抽牌 ---
		CardData.new("学者", 2, 2, 1, [
			_fx_skill("战术整理", SkillEngine.TRIGGER_ON_SUMMON, [
				_fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_DRAW_CARDS, 1),
			]),
		]),

		# --- 血刃刺客: 主动造成吸血伤害 ---
		CardData.new("血刃刺客", 3, 4, 2, [
			_fx_skill("血刃突袭", SkillEngine.TRIGGER_ON_ACTIVATE, [
				_fx(SkillEngine.TARGET_SINGLE, SkillEngine.EFFECT_LIFESTEAL_DAMAGE, 3),
			]),
		]),

		# --- 处刑者: 主动斩杀低生命敌人 ---
		CardData.new("处刑者", 4, 5, 3, [
			_fx_skill("终结打击", SkillEngine.TRIGGER_ON_ACTIVATE, [
				_fx(SkillEngine.TARGET_SINGLE, SkillEngine.EFFECT_EXECUTE, 3),
			]),
		]),

		# --- 修女: 净化友方负面状态并治疗 ---
		CardData.new("修女", 2, 4, 1, [
			_fx_skill("净化祷言", SkillEngine.TRIGGER_ON_ACTIVATE, [
				_fx(SkillEngine.TARGET_SINGLE, SkillEngine.EFFECT_CLEANSE, 0, "", 0, 0, 100, SkillEngine.TARGET_SIDE_ALLY),
				_fx(SkillEngine.TARGET_SINGLE, SkillEngine.EFFECT_HEAL, 2, "", 0, 0, 100, SkillEngine.TARGET_SIDE_ALLY),
			]),
		]),

		# --- 破法者: 驱散敌方正面状态 ---
		CardData.new("破法者", 3, 4, 2, [
			_fx_skill("破法", SkillEngine.TRIGGER_ON_ACTIVATE, [
				_fx(SkillEngine.TARGET_SINGLE, SkillEngine.EFFECT_DISPEL, 0, "", 0, 0, 100, SkillEngine.TARGET_SIDE_ENEMY),
			]),
		]),

		# --- 炼金术士: 低血量时获得圣水 ---
		CardData.new("炼金术士", 2, 3, 1, [
			_fx_skill("应急炼成", SkillEngine.TRIGGER_ON_DAMAGED, [
				_fx_condition(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_GAIN_MANA, 2, SkillEngine.CONDITION_SOURCE_HP_PCT, SkillEngine.CONDITION_OP_LTE, 50),
			]),
		]),

		# --- 训练官: 召唤时永久强化相邻友军攻击 ---
		CardData.new("训练官", 3, 4, 1, [
			_fx_skill("战术训练", SkillEngine.TRIGGER_ON_SUMMON, [
				_fx(SkillEngine.TARGET_SELF_SIDES, SkillEngine.EFFECT_GAIN_ATTACK, 1),
			]),
		]),

		# --- 古树: 召唤时永久提升自身生命上限 ---
		CardData.new("古树", 5, 7, 2, [
			_fx_skill("扎根生长", SkillEngine.TRIGGER_ON_SUMMON, [
				_fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_GAIN_MAX_HP, 3),
			]),
		]),

		# --- 共生虫(寄生): 附着到己方或敌方单位，给予攻击并优先承伤 ---
		_parasite_card("共生虫", 2, 3, 2),

		# --- 火球术(法术): 对单个敌人造成 4 点伤害 ---
		_spell_card("火球术", 3, [
			_fx_skill("火球", SkillEngine.TRIGGER_ON_CAST, [
				_fx(SkillEngine.TARGET_SINGLE, SkillEngine.EFFECT_DAMAGE, 4),
			]),
		]),

		# --- 智慧祷言(法术): 抽 2 张牌 ---
		_spell_card("智慧祷言", 2, [
			_fx_skill("智慧祷言", SkillEngine.TRIGGER_ON_CAST, [
				_fx(SkillEngine.TARGET_SELF, SkillEngine.EFFECT_DRAW_CARDS, 2),
			]),
		]),
	]


# Enemy presets by difficulty
static func goblin_warrior() -> CardData:
	return CardData.new("Goblin Warrior",  1, 2, 3, [])


static func goblin_archer() -> CardData:
	return CardData.new("Goblin Archer",   1, 3, 2, [])


static func goblin_shaman() -> CardData:
	return CardData.new("Goblin Shaman",   1, 2, 1, [
		_sample_skill("Heal Wave", SkillEngine.TRIGGER_ON_SUMMON, SkillEngine.TARGET_SELF_SIDES, SkillEngine.EFFECT_HEAL, 2),
	])


static func wolf_rider() -> CardData:
	return CardData.new("Wolf Rider",      3, 5, 4, [
		_sample_skill("Swipe", SkillEngine.TRIGGER_ON_ATTACK, SkillEngine.TARGET_SIDES, SkillEngine.EFFECT_DAMAGE, 2),
	])


static func boss_troll() -> CardData:
	return CardData.new("Boss Troll",      5, 12, 6, [
		_sample_skill("Roar", SkillEngine.TRIGGER_ON_SUMMON, SkillEngine.TARGET_SELF, SkillEngine.EFFECT_ADD_BUFF, 4, SkillEngine.BUFF_ATK_BOOST, 2),
		_sample_skill("Thick Skin", SkillEngine.TRIGGER_ON_SUMMON, SkillEngine.TARGET_SELF, SkillEngine.EFFECT_SHIELD, 5),
	])


# Enemy waves
static func enemy_wave(difficulty: int) -> Array:
	match difficulty:
		1:
			return [goblin_warrior(), goblin_archer()]
		2:
			return [goblin_shaman(), goblin_warrior(), wolf_rider()]
		3:
			return [wolf_rider(), wolf_rider(), boss_troll()]
		_:
			return [goblin_warrior(), goblin_warrior()]


# ============================================
# Helpers
# ============================================

static func _sample_skill(sname: String, trigger: String, target: String, effect: String, value: int, buff: String = "", duration: int = 0) -> Dictionary:
	var s: Dictionary = {
		"skill_name": sname,
		"trigger": trigger,
		"target": target,
		"effect": effect,
		"value": value,
		"buff_id": buff,
		"duration": duration,
	}
	return s


# Build a skill in the multi-effect format the editor produces.
static func _fx_skill(sname: String, trigger: String, effects: Array, probability: int = 100) -> Dictionary:
	return {
		"skill_name": sname,
		"trigger": trigger,
		"probability": probability,
		"effects": effects,
	}


# Build a single effect entry. random_count = 0 means "all matched targets".
static func _fx(target: String, effect: String, value: int, buff: String = "", duration: int = 0, random_count: int = 0, probability: int = 100, target_side: String = "") -> Dictionary:
	var eff := _TargetResolver.normalize_effect_target({
		"target": target,
		"target_side": target_side if target_side != "" else _TargetResolver.default_target_side(target),
		"effect": effect,
		"value": value,
		"buff_id": buff,
		"duration": duration,
		"random_count": random_count,
		"probability": probability,
	})
	return eff


static func _fx_random(target: String, effect: String, value_min: int, value_max: int, buff: String = "", duration: int = 0, random_count: int = 0, probability: int = 100, target_side: String = "") -> Dictionary:
	var eff := _TargetResolver.normalize_effect_target({
		"target": target,
		"target_side": target_side if target_side != "" else _TargetResolver.default_target_side(target),
		"effect": effect,
		"value_min": value_min,
		"value_max": value_max,
		"buff_id": buff,
		"duration": duration,
		"random_count": random_count,
		"probability": probability,
	})
	return eff


static func _fx_var(target: String, effect: String, value_var: String, value_offset: int = 0, buff: String = "", duration: int = 0, random_count: int = 0, probability: int = 100, target_side: String = "") -> Dictionary:
	var eff := _TargetResolver.normalize_effect_target({
		"target": target,
		"target_side": target_side if target_side != "" else _TargetResolver.default_target_side(target),
		"effect": effect,
		"value_var": value_var,
		"value_offset": value_offset,
		"buff_id": buff,
		"duration": duration,
		"random_count": random_count,
		"probability": probability,
	})
	return eff


static func _fx_condition(target: String, effect: String, value: int, condition_type: String, condition_op: String, condition_value: int, buff: String = "", duration: int = 0, random_count: int = 0, probability: int = 100, target_side: String = "") -> Dictionary:
	var eff := _fx(target, effect, value, buff, duration, random_count, probability, target_side)
	eff["condition_type"] = condition_type
	eff["condition_op"] = condition_op
	eff["condition_value"] = condition_value
	return eff


# Build a parasite card: a card that attaches to a unit, grants its attack,
# and loses parasite HP before the host takes directed damage.
static func _parasite_card(sname: String, cost: int, hp: int, atk: int) -> CardData:
	var card := CardData.new(sname, cost, hp, atk, [])
	card.card_type = "parasite"
	return card


# Build a spell card: a card with no body (hp/atk = 0) that triggers on_cast
# when played from hand and moves directly to the discard pile.
static func _spell_card(sname: String, cost: int, skills: Array) -> CardData:
	var card := CardData.new(sname, cost, 0, 0, skills)
	card.card_type = "spell"
	return card
