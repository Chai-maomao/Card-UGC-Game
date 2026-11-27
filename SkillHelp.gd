class_name SkillHelp
extends RefCounted

const KEYWORD_PREFIX := "cardex-keyword:"
const KEYWORD_RULES := {
	"damage": ["effect", "damage"], "heal": ["effect", "heal"],
	"shield": ["effect", "shield"], "charm": ["effect", "charm"],
	"lifesteal": ["effect", "lifesteal_damage"], "cleanse": ["effect", "cleanse"],
	"dispel": ["effect", "dispel"], "execute": ["effect", "execute"],
	"drain": ["effect", "mana_drain"], "swap": ["effect", "swap_attack"],
	"clone": ["effect", "clone_enemy"], "copy": ["effect", "copy_hand"],
	"draw": ["effect", "draw_cards"], "max_hp": ["effect", "gain_max_hp"],
	"cap": ["effect", "damage_cap"], "parasite": ["card_type", "parasite"],
	"poison": ["buff", "poison"], "regen": ["buff", "regen"],
	"silence": ["buff", "silence"], "stun": ["buff", "stun"],
	"taunt": ["buff", "taunt"], "thorns": ["buff", "thorns"],
	"reduction": ["buff", "damage_reduction"], "immune": ["buff", "immune_lethal"],
	"dodge": ["buff", "dodge"],
	"untargetable": ["buff", "untargetable"],
	"misfortune": ["buff", "misfortune"], "luck": ["buff", "luck"], "refund": ["buff", "mana_refund"],
	"atk_boost": ["buff", "atk_boost"],
	"unit": ["card_type", "minion"], "spell": ["card_type", "spell"],
}

const EXTRA := {
	"keyword:elixir": ["圣水用来部署单位、施放法术、附着寄生牌，也能补足行动力。", "Spend elixir to deploy units, cast spells, attach parasites, or cover an action point shortfall."],
	"keyword:hp": ["生命归零时，单位离场，玩家出局。", "A unit leaves the field or a player is eliminated when their health reaches zero."],
	"keyword:attack": ["攻击力决定普通攻击造成的基础伤害。", "A unit's attack sets the base damage of its basic attacks."],
	"keyword:cost": ["费用是打出这张牌所需的圣水。", "A card's cost is the elixir needed to play it."],
	"keyword:zero": ["零费牌无需消耗圣水即可打出。", "A zero-cost card can be played without spending elixir."],
	"keyword:draw_pile": ["双方从同一牌库抽牌。牌库抽空时，将弃牌堆洗回牌库。", "Players draw from the shared deck. When it runs out, the discard pile is shuffled back into it."],
	"keyword:discard_pile": ["弃置的牌、退场的单位和结算后的法术会进入弃牌堆。", "Discarded cards, defeated units, and resolved spells go to the discard pile."],
	"keyword:discard": ["弃牌会把手牌或场上的牌移入弃牌堆。", "Discard a card to move it from a hand or the field to the discard pile."],
	"keyword:hand": ["手牌是你当前可以打出的卡牌。", "Your hand holds the cards you can play."],
	"keyword:turn": ["回合开始和结束时，会结算对应时机的技能与状态。", "Skills and statuses with a turn trigger resolve at the start or end of the turn."],
	"keyword:chance": ["达到触发条件时，按这个概率判定技能是否发动。", "When the trigger condition is met, roll this chance to activate the skill."],
	"keyword:uses": ["消耗一次可用次数后，剩余次数会减少。次数用尽后无法再发动。", "Each activation spends one use. The skill cannot activate after its uses run out."],
	"keyword:search": ["检索技能会让你查看牌库或弃牌堆，并选择卡牌加入手牌。", "Search skills let you look through the deck or discard pile and choose cards to add to your hand."],
	"effect:view_deck_select": ["查看牌库顶的牌，再选牌加入手牌。未指定查看张数时，查看可选张数的两倍。", "Look at the top of the deck and choose cards to add to your hand. By default, look at twice as many cards as you can keep."],
	"effect:view_discard_select": ["查看弃牌堆并选牌加入手牌。指定查看张数时，从弃牌堆前面取出候选牌。", "Choose cards from the discard pile to return to your hand. If a limit is set, choose from the first cards in the pile."],
	"effect:make_zero_cost": ["降低手牌费用，最低为 0。可自行选择、随机选牌，或让所有手牌降费。", "Reduce hand card costs to a minimum of 0. Choose cards yourself, pick them at random, or reduce all hand cards."],
	"effect:clone_enemy": ["复制敌方场上单位的当前状态，副本加入你的手牌。", "Copy an enemy unit in its current state into your hand."],
	"effect:match_max_hp": ["提高本局生命上限，并回复等量生命。离场后仍保留提高的上限。", "Raise max HP for this match and heal by the same amount. The increased maximum persists after leaving play."],
	"effect:damage_cap": ["这项持续天赋限制每次受到的伤害。", "This continuous talent caps the damage from each hit."],
	"effect:change_cost": ["选择「全部」时，调整所选阵营在场单位的费用。卡牌进入弃牌堆后仍保留这次费用变动。", "All targets units on the selected side of the field. Cards keep the cost change after going to the discard pile."],
	"effect:__if__": ["如果：条件成立才执行内部积木，否则跳过。", "If: run the enclosed blocks only when the condition is true."],
	"effect:__if_else__": ["条件成立时执行上方分支，否则执行下方分支。", "Run the first branch if the condition is true. Otherwise, run the second."],
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
	"math:rand": ["在两侧数值之间随机取一个整数，包含两端。", "Pick a random integer between both values, inclusive."],
	"buff:immune_lethal": ["抵挡一次致命伤害并保留 1 点生命，触发后消失。", "Survive one lethal hit at 1 HP. The effect is consumed when triggered."],
	"buff:dodge": ["被选为目标时判定一次。成功则这次行动失效。闪避率可以叠加，最高 100%。", "Roll once when chosen as a target. Success cancels the action. Dodge chances add up to 100%."],
	"card_type:minion": ["单位卡：消耗圣水部署到战场格子，有生命与攻击，可配置主动或被动技能。", "Unit: deploy into a field slot using mana. Has HP, attack, and active or passive skills."],
	"card_type:spell": ["法术卡：从手牌施放并立即结算技能，不占战场格子，结算后进入弃牌堆。", "Spell: cast from hand, resolve immediately, then discard. Does not occupy a field slot."],
	"card_type:parasite": ["寄生卡：附着到单位并给予攻击，可选择替宿主承担指向伤害，或不承伤并随宿主离场；可配置攻击、受伤或死亡被动。", "Parasite: attach to a unit and grant attack. It may absorb directed damage, or remain linked without absorbing until the host leaves play. Supports attack, damaged and death passives."],
}


static func keyword_description(id: String) -> String:
	if id == "ap":
		return Locale.t("battle.action_help")
	if KEYWORD_RULES.has(id):
		var rule: Array = KEYWORD_RULES[id]
		return description(rule[0], rule[1])
	return description("keyword", id)


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
