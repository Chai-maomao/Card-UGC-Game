# 从标题页开始的首次启动引导

## 玩家流程

首次启动在 CARDEX 标题页上依次介绍欢迎与创卡目标、界面对比度、我的卡牌与牌组、进入战斗、卡牌编辑器。欢迎页之后可以切换高对比或低对比，画面即时预览并保存到「设置 → 画面」。选定后可继续，每页也可以跳过教程。键盘可在当前页的可用控件之间切换。

最后的“开始创卡教学”进入现有真实 CardEditor → SkillEditor → CardEditor 复核 → 战场15步教学，不生成另一套简化玩法。完成或任意章节明确跳过后，后续启动进入普通菜单；仍可从“进入战斗 → 新手教程”重玩。退出/关闭但未完成的首次教学，下次启动从标题页重新开始，不承诺恢复中断前的具体步骤。

## 存档与兼容

沿用 `user://tutorial_progress.cfg`，通过 Godot 的用户存档目录定位，不写死 C 盘。Windows 默认位于 `%APPDATA%/Godot/app_userdata/CardUGCGame/`，随操作系统和运行账户的目录配置变化。

- TutorialProgress 使用 schema 3，保留原有 completed/skipped、editor_completed 和其他字段。
- Bootstrap 客户端先初始化并保存 startup.initialized/required，再进入原标题场景。新玩家的状态为 in_progress。
- PlayerData 在默认新手牌库生成前记录主存档或备份是否已存在。旧玩家没有新标记时直接迁移为无需强制引导；不冒充已完成/已跳过教程，也不改写收藏。
- 已存在的 required/in_progress 标记优先于后来创建的新手牌库存档，因此关闭后重启不会误判为老玩家。
- MainMenu 只消费一次本进程的启动标志，章节内退出可正常返回菜单；只有新进程会再次检查未完成状态。
- 标题、创卡、技能、战场章节共享当前会话的进度文件。完成或跳过时沿用已有保存路径。用 `--server` 或 `--room-server` 启动时会跳过客户端引导初始化。
- 存档写入失败时记录警告，首次引导与本次跳过仍可操作；无法持久保存时不能保证下次不会重复显示。

## 实现与退出边界

新增 TitleTutorialController，只为首次启动叠加教学，不重排或替换原标题菜单。教学文字引用实际本地化按钮名；透明输入盾持续拦截背景，四块遮罩露出当前目标。暂时保留禁用按钮的正常视觉，退出时恢复原来的禁用状态和主题覆盖。提示正文16px，中英文与小窗口采用换行布局。

召唤落地延迟 Tween 原先归全局 BattleFx 所有，退出战场后仍会调用已经释放的 CanvasLayer。专项先复现错误，再将此 Tween 绑定到实际 FX layer；层销毁后停止回调，保留正常召唤反馈与时长。

## 验证

测试进程的 APPDATA/LOCALAPPDATA 指向工作区 `artifacts/first-launch/sandbox-profile`，隔离真实用户存档。首次启动专项使用独立进度文件，校验收藏文件 SHA 不变。

- TestFirstLaunchTutorial：首次保存、标题门控、跳过恢复、重启策略、完成、旧 schema 2 兼容、旧牌库迁移、手动重玩、服务端绕过、禁用样式恢复、召唤中退出。
- 另用四个独立进程实际启动 Bootstrap：无牌库首启 → 未完成重启 → 跳过 → 再次启动。前三次进入引导，最后一次普通菜单，四次收藏 SHA 相同。日志为 startup-{first,restart,skip,after-skip}.log。
- TestFirstLaunchTutorialVisual 检查中英文、1280×720 和 960×540 实际画面，覆盖高低对比切换、引导步骤、跳过、提示与焦点。通过 Bootstrap 和 UIMotion 切场走完整创卡、召唤抽牌、攻击、结束和退出。
- 原生 Window 的模拟事件不会更新物理 OS 光标查询，背景点击会错误取消合成攻击。因此链路中的编辑器保持原生视口，战场场景嵌入可驱动鼠标的 SubViewport；仍执行实际 SceneTree 切场及真实输入，不直接设置完成状态，不修改生产攻击判断。

回归范围与最终结果记录于 CODEX_HANDOFF.md、DEVELOPMENT_ITERATIONS.md 和 artifacts/first-launch/verification.json。没有验证真人理解效果、移动触控、导出包或实际联网，也未重跑全部套件。自动托管继续暂停，未提交/发布。

最终8项逻辑通过：FirstLaunchTutorial、TutorialFlow、GuidedTutorialUx、ResponsiveUi、UiOverflow、MainArchitecture、ProjectImprovements、BattleStatusFx。三项实际GL视觉 FirstLaunchTutorialVisual、TutorialBasicsVisual、ModernUiVisual 通过；Godot4.6.3最终导入及上述日志无引擎错误，代表截图已查看。
