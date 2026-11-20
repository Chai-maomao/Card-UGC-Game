class_name SkillHelp
extends RefCounted

const EXTRA := {
	"effect:view_deck_select": ["查看牌库：查看指定张数，并选择其中的牌加入手牌；受手牌上限限制。", "Inspect the deck and choose cards to keep, respecting the hand limit."],
	"effect:view_discard_select": ["查看弃牌：从弃牌中选择卡牌加入手牌；受手牌上限限制。", "Choose cards from the discard pile to return to hand, respecting the hand limit."],
	"effect:make_zero_cost": ["降低费用：使指定手牌降低 X 费，最低为0；可设为本回合或本局永久。", "Reduce selected hand cards by X, to a minimum of 0; lasts this turn or permanently for the match."],
	"effect:clone_enemy": ["克隆敌方：在己方手牌创造与指定敌方场上单位当前状态完全相同的克隆体。", "Create an exact current-state clone of selected enemy field units in your hand."],
	"effect:match_max_hp": ["本局生命成长：生命上限与当前生命在本局永久增加，弃置、洗牌和再次抽到都保留。", "Permanently increase this card's max and current HP for the match, surviving discard and reshuffle."],
	"effect:damage_cap": ["单次伤害上限：持续天赋；每次受到的伤害不会超过设定值。", "Continuous talent: each individual hit cannot exceed this value."],
	"effect:change_cost": ["费用变动：正数提高、负数降低目标卡牌本局费用，最低为0；弃置与重洗后仍保留。", "Change cost for this match: positive raises it, negative lowers it, minimum 0; persists through discard and reshuffle."],
	"effect:__if__": ["如果：条件成立才执行内部积木，否则跳过。", "If: run the enclosed blocks only when the condition is true."],
	"effect:__if_else__": ["如果／否则：条件成立执行上方分支，否则执行下方分支。", "If/else: run the first branch when true, otherwise the second."],
	"effect:__repeat__": ["重复：按指定次数执行内部积木；受技能安全次数上限限制。", "Repeat the enclosed blocks the specified number of times, within safety limits."],
	"effect:__stop__": ["停止：不再执行当前分支中后面的积木。", "Stop executing the remaining blocks in the current branch."],
	"boolean:compare": ["比较：比较两侧数值，结果为成立或不成立。数值槽可放入变量与运算。", "Compare two values to produce true or false. Slots accept variables and expressions."],
	"boolean:has_buff": ["拥有状态：检查当前目标是否带有指定状态。", "Check whether the current target has the specified status."],
	"logic:and": ["并且：两侧条件都成立时才成立。", "AND: true only if both conditions are true."],
	"logic:or": ["或者：任意一侧条件成立时就成立。", "OR: true if either condition is true."],
	"logic:not": ["取反：将条件的成立与不成立互换。", "NOT: reverse the condition's result."],
	"math:+": ["加法：两侧数值相加。右键或触屏长按可设置结果取整方式。", "Add both values. Right-click or touch and hold to set result rounding."],
	"math:-": ["减法：左侧数值减去右侧数值。右键或触屏长按可设置结果取整方式。", "Subtract the right value from the left. Right-click or touch and hold for rounding."],
	"math:*": ["乘法：两侧数值相乘。右键或触屏长按可设置结果取整方式。", "Multiply both values. Right-click or touch and hold for rounding."],
	"math:/": ["除法：左侧除以右侧，默认四舍五入；右键或触屏长按可改向上或向下取整。除以零返回零。", "Divide left by right; round to nearest by default. Right-click or touch and hold for ceil/floor. Division by zero returns zero."],
	"math:rand": ["随机数：在两侧数值之间抽取一个整数，包含两端；上下界写反也可使用。", "Pick an integer between both values, inclusive. Reversed bounds are accepted."],
	"buff:immune_lethal": ["免死：抵挡一次致命伤害，触发后消耗。", "Survive one lethal hit; consumed when triggered."],
	"card_type:minion": ["单位卡：消耗圣水部署到战场格子，有生命与攻击，可配置主动或被动技能。", "Unit: deploy into a field slot using mana. Has HP, attack, and active or passive skills."],
	"card_type:spell": ["法术卡：从手牌施放并立即结算技能，不占战场格子，结算后进入弃牌堆。", "Spell: cast from hand, resolve immediately, then discard. Does not occupy a field slot."],
	"card_type:parasite": ["寄生卡：附着到单位并给予攻击，可选择替宿主承担指向伤害，或不承伤并随宿主离场；可配置攻击、受伤或死亡被动。", "Parasite: attach to a unit and grant attack. It may absorb directed damage, or remain linked without absorbing until the host leaves play. Supports attack, damaged and death passives."],
}


static func description(category: String, id: String, card_type: String = "") -> String:
	if category == "trigger":
		if card_type.is_empty(): card_type = str(PlayerData.card_draft.get("card_type","minion"))
		if card_type == "parasite" and ParasiteRules.is_passive_trigger(id):
			return Locale.t("skill_editor.trigger_help.parasite."+id)
		return Locale.t("skill_editor.trigger_help." + id)
	var key := category + ":" + id
	if EXTRA.has(key):
		return EXTRA[key][0 if Locale.language == "zh" else 1]
	var result := Locale.term("editor_" + category, id)
	return result if result != id else ""


static func palette(block: SkillPaletteBlock) -> String:
	if block.buff_id != "": return description("buff", block.buff_id)
	for pair in [["effect", block.effect_id], ["condition", block.condition_id], ["value_var", block.var_id],
		["boolean", block.boolean_kind], ["math", block.expr_kind], ["logic", block.logic_kind],
		["target", block.target_kind], ["target_side", block.side_kind]]:
		if pair[1] != "":
			return description(pair[0], pair[1])
	return ""
