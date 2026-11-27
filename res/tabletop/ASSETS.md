# 桌面卡面资源

- 文件：`res/tabletop/unillustrated_card.png`
- 用途：没有用户卡图时的默认插画，用户上传的卡图优先。
- 生成：2026-11-12，内置 `image_gen`；没有使用 CLI 或外部素材。
- 原图保留在本机 Codex generated_images 中；游戏依赖的是仓库内副本。

最终生成提示词：

Create a single premium fantasy card illustration bitmap asset, portrait 3:4. NOT a card frame, NOT a UI mockup. Fill the entire image edge to edge with art. Subject: a weathered ivory-and-antique-brass astrolabe relic resting within a broken dark basalt archway, small carved stone steps, pale moths, sparse dried botanical stems. An atmospheric still life with dramatic physical form, hand painted oil and fine nineteenth century copperplate engraving textures; rich charcoal teal shadows, aged gold highlights, warm bone whites. Quiet mystery and tangible craft, beautiful focal hierarchy legible at small size. Painterly naturalistic materials, restrained intricate detail, directional light from upper left. No text, no letters, no borders, no magical circles, no neon, no glowing interface elements, no purple, no repeated geometric UI shapes, no humanoid people. This is an original neutral illustration for unillustrated user-created cards in a dark stone tabletop card game.

## 受伤差分

- 文件：`res/tabletop/unillustrated_card_damaged.png`。
- 来源：对本项目默认插画进行内置 image_gen 编辑，2026-11-14。
- 保留原场景和钟表上半部；破碎下半部埋在足量的钟体碎片、金属构件和石块中。
- 用于没有自定义主卡面的受伤状态。单张自定义卡图不会借用这张差分；上传第二张卡图时优先显示用户差分。

## 标题页桌面道具

- `title-dice.png` 和 `title-wheel.png` 来自用户提供的透明底素材。
- 道具沿标题页牌桌平面投影，转盘在纵深方向略微压缩。阴影由图片的透明轮廓在场景中生成。

## 开战入口插画

- `launch/quick-play-v2.webp` 为古象牙骰子和单张绿金牌背的桌面静物。用于随机对战入口及练习准备页。
- `launch/friend-room.webp` 为桌面两侧相对摆放的绿金卡组。用于好友房间、局域网、派对和热座准备。
- `launch/ranked-tournament.webp` 为置于桌面的黄铜赛事盾牌。用于排位入口及排位选组页。2026-11-27 通过内置图像生成制作，游戏使用 WebP 副本。
- 两张图均于 2026-11-26 通过内置图像生成制作，保留暗色下沿供本地化标题叠放。原始 PNG 保存在本机生成图目录。游戏使用压缩后的 WebP 副本。
