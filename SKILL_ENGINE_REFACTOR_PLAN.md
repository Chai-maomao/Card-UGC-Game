# 技能引擎重构计划（Plan Mode）

> 聚焦技能引擎区块，允许底层改动，目标：**编辑器易读性、技能可拓展性、效果正确触发**。
> 本文件为只读调研结论 + 实施计划，确认后开始执行。

---

## 一、现状问题清单

### P1 技能知识碎片化（可拓展性的最大痛点）

| 问题 | 位置 |
| --- | --- |
| `EFFECT_*`/`BUFF_*` 常量在 **3 个文件重复定义**，改一个效果要同步 3 处 | [SkillEngine.gd](file:///c:/Users/admin/Documents/card-ugc-game/SkillEngine.gd#L40-L66)、[SkillEffectApplier.gd](file:///c:/Users/admin/Documents/card-ugc-game/SkillEffectApplier.gd#L6-L24)、[SkillTextFormatter.gd](file:///c:/Users/admin/Documents/card-ugc-game/SkillTextFormatter.gd#L8-L33) |
| 旧版"单效果格式"兼容逻辑 **重复 4 份** | [SkillEngine.gd](file:///c:/Users/admin/Documents/card-ugc-game/SkillEngine.gd#L214-L225)、[SkillTextFormatter.gd](file:///c:/Users/admin/Documents/card-ugc-game/SkillTextFormatter.gd#L168-L171)、[SkillEditor.gd](file:///c:/Users/admin/Documents/card-ugc-game/SkillEditor.gd#L1126-L1134)、[CardEditor.gd](file:///c:/Users/admin/Documents/card-ugc-game/CardEditor.gd#L377-L380) |
| 正面/负面 buff 列表硬编码在净化/驱散实现里 | [SkillEffectApplier.gd](file:///c:/Users/admin/Documents/card-ugc-game/SkillEffectApplier.gd#L23-L24) |

**后果**：新增一个效果目前需改动约 8~10 处（3 份常量 + 编辑器 `EFFECT_KEYS` + Locale 4 张表 + 计分表 + 派发 match），极易漏改导致静默错误。

### P2 技能编辑器可读性差

| 问题 | 位置 |
| --- | --- |
| `_open_effect_popup()` 单个函数约 **500 行**，嵌套十几个 lambda，UI 构建/状态同步/预览逻辑交织 | [SkillEditor.gd](file:///c:/Users/admin/Documents/card-ugc-game/SkillEditor.gd#L389-L897) |
| **魔法索引**：`effect_sel.selected == 2/5`、`buff_sel.selected in [5,6]`，下拉列表顺序一改就静默出错 | [SkillEditor.gd](file:///c:/Users/admin/Documents/card-ugc-game/SkillEditor.gd#L857-L926) |
| 下拉选项由硬编码 const 数组 + 手工索引维护 | [SkillEditor.gd](file:///c:/Users/admin/Documents/card-ugc-game/SkillEditor.gd#L969-L1024) |
| 弹窗遮罩自建 blur，未复用已有 `UITheme.make_popup_layer` | [SkillEditor.gd](file:///c:/Users/admin/Documents/card-ugc-game/SkillEditor.gd#L393-L421)（对比 [CardEditor.gd](file:///c:/Users/admin/Documents/card-ugc-game/CardEditor.gd#L398)） |

### P3 效果触发正确性问题（Bug）

| # | Bug | 位置 |
| --- | --- | --- |
| B1 | **吸血伤害致死仍触发 TRIGGER_ON_DAMAGED**（HP 归零后触发，违反硬约束"受伤触发仅在非致命伤害后"）。普通伤害路径有 `is_alive()` 守卫，吸血路径漏了 | [SkillEffectApplier.gd](file:///c:/Users/admin/Documents/card-ugc-game/SkillEffectApplier.gd#L131-L132) vs [SkillEffectApplier.gd](file:///c:/Users/admin/Documents/card-ugc-game/SkillEffectApplier.gd#L82-L84) |
| B2 | `allow_dead_source` 对 `on_damaged` 也放行死亡目标（应仅 `on_death`） | [SkillEngine.gd](file:///c:/Users/admin/Documents/card-ugc-game/SkillEngine.gd#L202) |
| B3 | **手牌类效果**（抽牌/圣水/选牌/0费）**完全跳过 `_passes_effect_condition`**，条件被静默忽略 | [SkillEngine.gd](file:///c:/Users/admin/Documents/card-ugc-game/SkillEngine.gd#L198-L207) |
| B4 | `var t := vmin` 违反"显式声明类型"工程约定 | [SkillEngine.gd](file:///c:/Users/admin/Documents/card-ugc-game/SkillEngine.gd#L357) |
| B5 | `_effect_can_apply_without_live_target` 硬编码列表，与 applier 派发无对应关系，新增效果易漏加 | [SkillEngine.gd](file:///c:/Users/admin/Documents/card-ugc-game/SkillEngine.gd#L210-L211) |

---

## 二、总体设计

**核心思路：把"技能领域知识"收拢到一个单一来源（SkillRegistry），让编辑器/格式化/执行/测试都从它读取；把编辑器效果弹窗拆成独立类。**

```
SkillEngine（常量 + 执行主流程）
   └─ 查询 ──▶ SkillRegistry（新增：效果/状态/触发器/目标/变量/条件 元数据目录）
                   ▲                          ▲
SkillEffectApplier（派发+实现）      SkillEditor ──▶ SkillEffectForm（新增：弹窗类）
SkillTextFormatter（文案模板）          │                 │
CardEditor / CardUI（消费方）           └─ 下拉数据源 ←───┘
```

- **SkillEngine 保留全部 `const`**（全项目引用点太多，不迁移），作为标识符唯一来源。
- **SkillRegistry 是"知识层"**：元数据表 + 查询函数，驱动编辑器下拉、派发分类、净化/驱散、值校验。
- **SkillEffectForm 是"界面层"**：弹窗 UI 独立成类，SkillEditor 只负责打开/接收结果。
- 存档与数据全部使用 **字符串 id**（如 `"damage"`），下拉顺序调整**不破坏存档**。

---

## 三、分阶段改动明细

### Phase 1 — 基建（新增 2 个能力）

1. **新增 [SkillRegistry.gd](file:///c:/Users/admin/Documents/card-ugc-game/SkillRegistry.gd)（class_name 静态类）**
   - `EFFECT_META`：effect_id → `{ requires_live_target, allows_negative, force_self, uses_value }`
   - `BUFF_META`：buff_id → `{ polarity: "negative"/"positive"/"neutral", value_meaningful }`
   - `TRIGGER_META`：trigger_id → `{ passive }`（passive=可作天赋）
   - `EFFECT_IDS / BUFF_IDS / TARGET_IDS / TARGET_SIDE_IDS / VALUE_VAR_IDS / CONDITION_IDS / CONDITION_OP_IDS`：编辑器下拉顺序（与现有 `EFFECT_KEYS` 等**完全一致**，避免 UI 顺序变化）
   - 查询函数：`is_hand_effect() / allows_negative() / force_self() / uses_value() / buff_polarity() / buff_uses_value() / negative_buffs() / positive_buffs() / trigger_is_passive()`
2. **SkillTargetResolver 新增 `static func legacy_skill_effects(skill) -> Array`**：旧版单效果格式归一化，消灭 4 份重复实现。

### Phase 2 — 常量去重

3. **SkillEffectApplier.gd**：删除重复 `const`，改引用 `SkillEngine.*`；`NEGATIVE_BUFFS/POSITIVE_BUFFS` 改为 `SkillRegistry.negative_buffs()/positive_buffs()`。
4. **SkillTextFormatter.gd**：删除重复 `const`，改引用 `SkillEngine.*`；`format_skill_tooltip` 的旧格式 fallback 改调 `legacy_skill_effects`。

### Phase 3 — 触发正确性修复

5. **SkillEngine.gd**
   - B5：`_effect_can_apply_without_live_target` → `SkillRegistry.is_hand_effect()`
   - B2：`allow_dead_source` 仅当 `trigger == TRIGGER_ON_DEATH`
   - B3：手牌类效果也执行条件校验（以 source_card 作为伪目标求值；`TARGET_HP_PCT`/`TARGET_HAS_BUFF` 语义 = 自身状态，写入文档）
   - B4：`var t: int = vmin`
   - 旧格式 fallback → `legacy_skill_effects`
6. **SkillEffectApplier.gd**
   - B1：`_apply_lifesteal_damage` 补 `is_alive()` 守卫，与 `_apply_damage` 一致
   - 抽取公共 `_trigger_damaged_safe(target, context)` 供两条伤害路径复用

### Phase 4 — 编辑器可读性重构

7. **新增 [SkillEffectForm.gd](file:///c:/Users/admin/Documents/card-ugc-game/SkillEffectForm.gd)（extends Control，纯代码构建，复用 `UITheme.make_popup_layer`）**
   - 接口：`setup(scale, existing_effect)` / `get_result() -> Dictionary` / `confirmed` 信号
   - 内部：下拉全部由 `SkillRegistry` 生成，状态同步用**键值查找**（`EFFECT_IDS[sel.selected]`），无魔法索引；预览/校验逻辑收敛为命名函数
8. **SkillEditor.gd 瘦身**
   - `_open_effect_popup` 删减为：创建 `SkillEffectForm` 实例 → `setup` → 接收 `confirmed` 结果
   - 删除 `EFFECT_KEYS/BUFF_KEYS/VAR_KEYS/...` 硬编码数组与魔法索引
   - `_load_skill` 旧格式 fallback → `legacy_skill_effects`

### Phase 5 — 收尾

9. **CardEditor.gd**：`_format_skill_short` 旧格式 fallback → `legacy_skill_effects`
10. 在计划文档末尾沉淀"**如何新增一个效果**"检查清单（改造后 6 处即可）

### 涉及文件一览

| 文件 | 动作 |
| --- | --- |
| SkillRegistry.gd | 新增 |
| SkillEffectForm.gd | 新增 |
| SkillEngine.gd | 修改（B2/B3/B4/B5 + dedup） |
| SkillEffectApplier.gd | 修改（去重 + B1） |
| SkillTextFormatter.gd | 修改（去重） |
| SkillTargetResolver.gd | 修改（+legacy_skill_effects） |
| SkillEditor.gd | 重构（大改） |
| CardEditor.gd | 小改（dedup） |
| Locale.gd | **不改**（文案表已完备，仅新增效果时按需补充） |

---

## 四、测试与验证

新增 **TestSkillRegistry.gd + .tscn**（沿用现有测试场景模式），覆盖：

1. **目录完整性**：`EFFECT_META/BUFF_META/TRIGGER_META` 与 SkillEngine 常量全集一致；`EFFECT_IDS/BUFF_IDS` 每项在 Locale 均有翻译
2. **B1 回归**：吸血伤害致死 → 目标不触发 `on_damaged`；非致命吸血 → 正常触发
3. **B2 回归**：`on_death` 技能效果可指向死亡自身；`on_damaged` 不放过死亡目标
4. **B3 回归**：抽牌效果带 `condition_*` 时不满足则整段跳过
5. **归一化**：旧格式 skill（`effect/value` 单效果）→ `legacy_skill_effects` 输出与手工构造等价
6. 回归：现有 5 个测试场景（TestSkillTargeting / TestSpellCast / TestParasiteCard / TestCardEditorSkillSummary / TestBalanceEvaluator）+ 编辑器手测（打开弹窗、增删改效果、保存重载）

## 五、风险与兼容性

| 风险 | 缓解 |
| --- | --- |
| SkillEditor 大规模重构引入 UI 回归 | Phase 4 前置 Phase 1-3 全量通过；编辑器弹窗手测清单；`EFFECT_IDS` 顺序与现有 `EFFECT_KEYS` 逐项对齐 |
| 常量引用迁移编译错误 | 改后立即跑 Godot 编译检查（`--check-only` 或打开编辑器），错误面小且集中 |
| 存档兼容 | 存档/卡库存字符串 id，顺序调整与常量重排不影响旧数据 |
| B3 语义变更（手牌效果突然受条件约束） | 现状是无约束（静默忽略），修复后**有条件的**手牌效果才受影响；写进改动说明，测试覆盖 |

## 六、改造后"如何新增一个效果"（实际落地）

> 最终实现（二轮迭代）：SkillEngine 已改为 `extends SkillRegistry`（常量零 re-export），执行派发 / 文案模板 / 平衡计分全部由 `SkillRegistry.EFFECT_META` 驱动。**无需再改任何 match**。

1. `SkillRegistry` 加 `const EFFECT_X` + `EFFECT_META` 条目（`requires_live_target/allows_negative/force_self/uses_value/handler/template/polarity/score_kind/score_weight`，编辑器与执行/计分自动联动）+ `EFFECT_IDS`（如需进下拉）
2. `SkillEffectApplier` 写实现函数（统一签名 `(target, value, skill, context)`），`apply_effect` 自动查表派发
3. `Locale` 加 zh/en 词条（`effect`/`effect_value`/`editor_effect`/`effect_sentence` 模板）
4. 平衡计分自动生效（读 `score_kind/score_weight`；新公式类型才需改 BalanceEvaluator）
5. `TestSkillRegistry` 自动校验契约完整性（新效果漏词条/漏字段会报错）

相比重构前（约 6 处改动），新增效果只需 **3 处**，且 `apply_effect` / `format_effect_sentence` / `_effect_score` 三个 match 全部消失，改由注册表自动联动。
