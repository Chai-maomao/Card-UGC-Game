extends RefCounted

const IDS := ["deployment", "triggers", "targets", "taunt", "damage", "control", "charm", "hand", "discard", "turn", "custom"]


static func _t(zh: String, en: String) -> String:
	return zh if Locale.language == "zh" else en


static func title(id: String) -> String:
	match id:
		"deployment": return _t("出牌与召唤效果", "Playing cards and summon effects")
		"triggers": return _t("发动时机与次数", "Triggers and uses")
		"targets": return _t("目标与结算顺序", "Targets and order")
		"taunt": return _t("普攻与嘲讽", "Basic attacks and Taunt")
		"damage": return _t("伤害与保护", "Damage and protection")
		"control": return _t("状态、寄生与易手", "Statuses and ownership")
		"charm": return _t("魅惑与临时零费", "Charm and temporary free play")
		"hand": return _t("手牌、检索与费用", "Hand, search and cost")
		"discard": return _t("主动弃牌与圣水", "Manual discard and Elixir")
		"turn": return _t("行动力与回合末", "Actions and turn end")
		"custom": return _t("自定义对局与卡牌", "Custom battles and cards")
	return ""


static func objective(id: String) -> String:
	match id:
		"deployment": return _t("练习把单位从手牌放到场上，并核对出牌费用和自动发动的效果。", "Play a unit from your hand and check its cost and automatic summon effect.")
		"triggers": return _t("观察主动技能没发动时，行动力、圣水和累计次数分别怎么变。", "See what happens to action points, Elixir and remaining uses when an active skill fails to trigger.")
		"targets": return _t("用横扫验证空格会不会隔开相邻目标。", "Use Sweep to see how an empty slot affects adjacent targets.")
		"taunt": return _t("场上有嘲讽时，试试普攻能选哪一个敌人。", "Find out who you can attack when an enemy has Taunt.")
		"damage": return _t("对有减伤和护盾的敌人使用吸血，比较技能伤害和实际扣血。", "Use Lifesteal against damage reduction and shield, then compare the stated damage with actual life lost.")
		"control": return _t("净化一张同时有中毒、嘲讽和护盾的牌，看看哪些效果还在。", "Cleanse a card with Poison, Taunt and shield, then see what remains.")
		"charm": return _t("把敌方单位移到自己的手牌，观察它的费用和场上的变化。", "Move an enemy unit into your hand and check its cost and the vacated slot.")
		"hand": return _t("满手时再抽一张，看看新牌去了哪里。", "Draw with a full hand and see where the incoming card goes.")
		"discard": return _t("主动弃掉一张手牌，比较它与满手溢出的圣水结算。", "Discard a hand card and compare its Elixir refund with hand overflow.")
		"turn": return _t("用圣水补付开关比较回合末自动攻击的结果。", "Use the Elixir Supplement toggle to compare end-of-turn attacks.")
		"custom": return _t("改一份练习用的战场规则，比较回合开始时的资源。", "Change the practice rules and compare the resources at turn start.")
	return ""


static func sections(id: String) -> Array:
	match id:
		"deployment": return [[title(id), objective(id)], [title("triggers"), sections("triggers")[0][1]]]
		"taunt": return [[title(id), sections("control")[1][1]]]
		"charm": return [[title(id), sections("control")[2][1]]]
		"discard": return [[title(id), sections("hand")[0][1]]]
		"triggers": return [
			[_t("先读触发时机", "Read the trigger first"), _t(
				"单位的「召唤时」随部署触发，需要目标时再选择。法术从手牌打出后结算，并进入弃牌堆。主动技能需要点开场上的单位使用。攻击时、被攻击时、受伤时和被治疗时各自对应不同事件，先看牌上的触发名称。",
				"A unit's summon skill triggers on deployment and may ask you for a target. A spell resolves when played from hand and then goes to the discard pile. Activate a field unit's active skill from its details. Attacking, being attacked, taking damage and being healed are separate triggers.\nCheck the trigger printed on the card.")],
			[_t("同一回合与累计次数", "This turn and remaining uses"), _t(
				"同一单位一回合内可以用不同的未用主动技能。用过主动就不能再普攻，普攻后也不能再用主动。有限次数跨回合累计，可在对局技能详情里查看。牌回到弃牌堆并重置后，重新抽到时会恢复可用次数。附着牌各自记录次数。",
				"A unit can use different unused active skills in the same turn. A basic attack and active skills exclude each other for that unit that turn. Use limits carry over between turns and appear in battle details. A card that resets in the discard pile gets its uses back when redrawn. Attachments track their own uses.")],
			[_t("判定失败也可能已付费", "A failed roll can still cost resources"), _t(
				"主动技能通过使用检查后先付款，再判定发动。发动概率没通过时，本次行动和资源已经花掉，累计次数还在。技能一旦发动，之后某个效果的条件不成立，或单个效果的概率没通过，仍会扣这次技能的累计次数。厄运从技能发动概率里减去相应百分点。",
				"An eligible active skill pays its cost before rolling to trigger. A failed trigger roll spends the action and resources while preserving the limited use. Once the skill triggers, a later failed effect roll or condition still uses that activation. Misfortune subtracts percentage points from the skill's trigger chance.")],
		]
		"targets": return [
			[_t("阵营、相邻格与本体", "Sides, adjacent slots and players"), _t(
				"「己方」与「敌方」跟随技能施加者。相邻指同一排紧挨着的格，空一格不会越过去，跨不过两边战场。「本体」指玩家的生命。能影响本体的效果会明确写出，选了敌方单位也不会波及本体。",
				"Allied and enemy are relative to the caster. Adjacent means the immediately neighboring slots in the same row, even if a slot is empty. A player target uses the player's life total. Selecting an enemy unit does not also select its player.")],
			[_t("被动反应中的目标", "Targets of reaction skills"), _t(
				"反应技能里的指定目标可以指向这次伤害或治疗的实际来源。若来源不在可选战场，或阵营不匹配，这个效果可能没有目标。看清反应的来源和目标，别用同一列的另一张牌来推断。",
				"A directed reaction can target the actual source of that hit or heal. The effect can have no target if the source is off the eligible board or on the wrong side. Check the source and target reported by the reaction.")],
			[_t("随机目标、随机数值、概率", "Random targets, values and chances"), _t(
				"限制随机目标数时，先从目标范围中抽取，再对抽中的目标检查条件。因此写着最多影响两张，实际可能少于两张。一个效果的普通随机数值通常掷一次，读目标攻击或生命的数值会对每个目标分别算。技能概率、效果概率和概率分支各判各的。",
				"With a random target limit, the engine samples candidates and then checks each selected target's condition, so fewer than the limit may be affected. A plain random amount is generally rolled once for the effect. Expressions that read target stats compute a value per target. Skill chance, effect chance and chance branches each roll separately.")],
			[_t("按积木的顺序读", "Read the blocks in order"), _t(
				"先执行上面的效果，再用此刻的场面判断后面的条件。条件分支选中一边执行，重复会再次执行里面的积木。停止会结束其所在列表的剩余效果。写连锁时，留意前面的伤害、抽牌或离场带来的变化。",
				"Effects resolve in order. Later conditions see the state at that point. A conditional chooses one branch, Repeat runs its contained blocks again, and Stop ends the rest of its own block list. Earlier damage, draws or departures can change what happens next.")],
		]
		"damage": return [
			[_t("用实际扣血计算吸血", "Lifesteal uses actual life lost"), _t(
				"常规伤害先算减伤并向下取整，再检查寄生代受与目标的单次伤害上限，护盾会优先承受余下伤害。吸血按目标实际失去的生命回复施加者，自己仍受生命上限限制。护盾挡住的伤害不计入回复。",
				"Ordinary damage applies reduction and rounds down, then checks parasite absorption and the target's damage cap. Shield takes the remaining damage before life. Lifesteal heals the caster by the target's actual life loss, up to the caster's maximum life. Shield loss gives no healing.")],
			[_t("处决、中毒和反伤", "Execute, poison and thorns"), _t(
				"处决看目标当前生命是否在阈值以内。普通护盾和减伤挡不住处决，致命免疫另行判定。中毒在受影响单位一方的回合结束时直接扣生命，护盾和致命免疫都挡不住。反伤只在受到普通攻击时发生。",
				"Execute checks if the target's current life is at or below its threshold. Ordinary shield and damage reduction cannot stop it. Lethal protection is checked separately. Poison directly removes life at the end of the afflicted unit's side's turn, bypassing both shield and lethal protection. Thorns responds to basic attacks.")],
			[_t("保护和回复各有时点", "Protection and recovery have different timing"), _t(
				"护盾在单位下一次己方回合开始时清除。再生在施加者的回合开始时回复，圣水返还则在施加者的回合结束时到账。攻击提升修改有效攻击。伤害上限约束单次伤害，是持续天赋时会受沉默和眩晕影响。",
				"Shield clears when the unit's side next starts a turn. Regeneration heals at the caster's turn start, while Elixir refund pays out at the caster's turn end. Attack boost changes effective attack. A damage cap limits individual hits and, as a continuous talent, can be disabled by Silence or Stun.")],
		]
		"control": return [
			[_t("谁该净化，谁该驱散", "Choose cleanse or dispel"), _t(
				"净化清负面状态，例如中毒、沉默和眩晕。驱散清正面状态，例如嘲讽和减伤。护盾单独计算，不会被这两个效果当作普通状态清掉。详情里会列出状态和剩余时间。",
				"Cleanse removes negative statuses such as Poison, Silence and Stun. Dispel removes positive statuses such as Taunt and damage reduction. Shield is tracked separately and is not removed as an ordinary status by these two effects. Card details show active statuses and timing.")],
			[_t("嘲讽、沉默与眩晕", "Taunt, Silence and Stun"), _t(
				"敌方有嘲讽时，普攻要先选嘲讽单位，技能看自己的目标规则。沉默会停用技能，单位仍可普攻。眩晕会立即禁用普攻和技能，含天赋。持续回合数从受影响单位所属玩家的下个回合起算。",
				"With enemy Taunt on the board, basic attacks must target a Taunt unit. Skills use their own targeting rules. Silence disables skills and still permits basic attacks. Stun immediately prevents basic attacks and skills, including talents. Count its duration from the affected unit's side's next turn.")],
			[_t("寄生、魅惑与克隆", "Parasites, charm and cloning"), _t(
				"寄生牌依附宿主，附加攻击，随宿主在攻击、受伤或死亡时触发。多张代受伤害的寄生牌中，最后附着的一张先挡整次伤害。自己被击破时也不会把多余伤害传给宿主。关联型仍会附加攻击。魅惑让目标离场并尝试进入施加者手牌，本回合零费。克隆保留敌方原牌，并尝试将带有当前状态的副本加入手牌。两者都受手牌上限影响。",
				"Parasites attach to a host, contribute attack and can trigger with it on attack, damage or death. The newest damage-absorbing attachment takes the entire hit, with no overflow to the host if it breaks. Linked attachments still add attack. Charm removes the target and tries to put it in the caster's hand at zero cost for this turn. Cloning keeps the original in play and sends a copy of its current state to your hand. Both are subject to the hand limit.")],
		]
		"hand": return [
			[_t("抽、选、弃与复制", "Draw, select, discard and copy"), _t(
				"双方共用牌库和弃牌堆。直接抽牌在牌库抽空时会洗回弃牌。检索先看指定范围，再选最多几张加入手牌，未选的牌留在原处。满手时新入的牌进弃牌堆。主动弃牌可回 1 圣水，受上限限制。被技能弃掉或溢出的牌不会因此回费。手牌复制会尝试把副本加入自己的手牌。",
				"Both sides share the draw and discard piles. Drawing reshuffles the discard pile when the draw pile runs out. Search shows candidates and lets you keep up to the stated number. Unselected cards stay in their pile. Incoming cards overflow into discard when the hand is full. Manual discard refunds 1 Elixir up to the cap. Forced discard and overflow grant no such refund. Copying a hand card tries to add a copy to your hand.")],
			[_t("这回合与这场对局", "This turn and this battle"), _t(
				"临时降费到回合结束，费用最低为 0。标明「本局」的改费按本局生效。场上增减攻击、交换基础攻击和战场生命上限变动，离场重置时会清理。标明「本局生命上限」的效果另行保留。降低上限只在当前生命超过新上限时把生命压低。",
				"Turn cost reductions expire at turn end. Costs cannot fall below zero. Match cost changes last for the battle. Field attack changes, base attack swaps and field maximum-life adjustments clear when the card resets on leaving play. A match maximum-life effect is retained separately. Lowering the cap only lowers current life when it exceeds the new maximum.")],
			[_t("圣水与抽牌先看归属", "Check who receives the resource"), _t(
				"获得或失去圣水会受资源上下限限制。圣水汲取从对方实际可扣的圣水中拿取。选手牌降费时，先读是指定手牌、随机手牌还是整手，也要看持续时间。",
				"Elixir gains and losses obey resource bounds. Elixir drain takes from the amount the opponent can actually lose. For hand cost reduction, check whether it selects a card, chooses randomly or affects the entire hand, and how long it lasts.")],
		]
		"turn": return [
			[_t("行动力为什么不一样", "Why action points vary"), _t(
				"回合开始技能和抽牌结算后，用基础行动力、空战场格、空手牌位算出本回合的行动力。普攻和主动技能的费用在全队按 0、1、2 递增。先付行动力，缺口按设定倍率向上取整，用圣水补足。出牌另付卡牌费用。普攻击杀会回 1 圣水，技能击杀不会自动回费。",
				"After start-of-turn skills and draws, action points are calculated from the base and your empty board and hand spaces. Basic attacks and active skills share a 0, 1, 2 progression across your team. Pay points first, then cover the shortfall with Elixir at the configured rate, rounded up. Playing a card pays its separate card cost. A kill from a basic attack refunds 1 Elixir. A skill kill does not grant that refund.")],
			[_t("回合结束前看一次预览", "Read the preview before ending the turn"), _t(
				"结束阶段先过期临时圣水，再结算返还、结束技能和状态。从第 2 回合起，若对方战场为空，己方未行动且付得起费用的单位会从左到右自动攻击本体。「圣水补付」决定自动攻击是否能用圣水。结束技能和状态可能让预览发生变化。",
				"Temporary Elixir expires before refunds, end-of-turn skills and status resolution. From round two, an empty enemy board allows unspent units that can pay to attack the player from left to right. The Elixir supplement toggle controls whether these automatic attacks may use Elixir. Turn-end skills and statuses can change the preview.")],
			[_t("首回合和操作限时", "Opening round and action timer"), _t(
				"普通对局首回合限制普攻和会改变敌方生命或在场状态的技能效果。治疗、保护和资源操作仍要按牌面与实际目标判断。开启限时时，先看每回合首次操作的时限，随后按成功操作重置。换位或操作失败不会续时。超时会正常结算回合结束。",
				"Ordinary matches restrict basic attacks and effects that change enemy life or board presence in the opening round. Healing, protection and resources still follow their own targeting and rules. With the timer enabled, the first action has its own window. Successful actions start the regular window. Moving cards or making an invalid move does not reset it. Timeout performs the normal end of turn.")],
		]
		"custom": return [
			[_t("每条房间规则会改什么", "What each room rule changes"), _t(
				"初始生命决定本体能承受多少伤害。固定或递增回费、抽牌张数和后手额外补偿会改变前后手节奏。行动力的基础值、空位系数和补付倍率要一起看。开启死亡补偿后，己方单位死亡可补抽一张。开启本体伤害补偿后，受到空场自动攻击的一方会按攻击单位数得到临时圣水。按抽牌顺序查看牌库也会透露之后摸到什么。",
				"Starting life decides how much damage a player can take. Fixed or growing Elixir, draw counts and second-player compensation change the opening pace. Read the action-point base, empty-space bonuses and Elixir exchange together. Death compensation draws a card when a friendly unit dies. Face-damage compensation gives the side hit by empty-board attacks temporary Elixir for each attacker. Ordered draw-pile inspection reveals future draws.")],
			[_t("对局前核对双方玩的规则", "Check the agreed rules before play"), _t(
				"本地双人由先选牌组的一方设置，后选的一方沿用同一规则。双人联机以开局确认的规则为准，开打后可以在「本局信息」查看。派对对战的房主可在派对大厅设置操作时限。限时的两个数值在开关开启时生效。改一条规则后，先观察一个回合的资源和选择空间。",
				"In local two-player setup the first deck selector sets the rules and the second uses the same settings. In online duels, the agreed rules apply. Check Match Info during play. A Party Battle host can set the timer in the party lobby. The two timer values take effect when enabled. After a change, watch what resources and choices a turn offers.")],
			[_t("写好说明，再试放和试打", "Write the rule, then try it"), _t(
				"写技能时，把时点、目标、数量和期限写在它们实际起作用的地方。比如「回合结束时，中毒单位失去 2 点生命」比「施加中毒值 2」更清楚。先在编辑器编译并用「试一次」检查正常、空目标和条件失败，再用试打观察真实的行动与资源。作者可以为随机效果多试几次，有次数限制的技能再试一次用尽后的行为。",
				"When writing a skill, name the timing, target, amount and duration where they matter. For example, say a poisoned unit loses 2 life at the end of its side's turn. Compile and use Try Once for a normal case, no legal target and a false condition. Then playtest action and resource costs. Try random cases more than once and check what happens after a limited skill runs out.")],
		]
	return []
