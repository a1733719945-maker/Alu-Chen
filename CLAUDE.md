# 斗罗大陆 · 猎魂 —— 项目记忆

给接手这个项目的 Claude 看的。先读完这份，再动代码。

## 和用户沟通

- **全程用中文**，思考和说明都不要写英文。说明要短、直接，多用列表。
- 用户在德国工作，这个游戏是业余做来**和朋友们一起联机玩**的。
- 用户会说 token 不够、让"快速处理"：这时只做必要的检查（`--check-only`、相关的一小段自动测试或一张截图），不要把五章全流程全跑一遍。CI 推送后会自动跑全流程。
- 做完一轮就提交、推送，然后告诉用户改了什么、有什么没做完。

## 用户提过的要求（别再犯）

| 反馈 | 现在的做法 |
|---|---|
| 不喜欢中式古风 / 毛笔字体 | 思源黑体（Noto Sans SC，裁剪过）+ Barlow Condensed 数字 |
| UI 太山寨 | game-icons.net 剪影图标、半透明底板、斜切血条、少文字；菜单 / 暗器铺 / 武魂面板还可以继续现代化 |
| 技能键太多，WASD 时按不到 Z/C/V | 魂技只用 **Q**：轻按放当前魂技，按住 Q 弹出轮盘用鼠标选（`Player._skill_input`、`Hud.open_wheel`） |
| 魂兽在天上掉不下来 | 空中分段重力、连击上推力递减有上限、尸体摔到地上再消失（`beast.gd` 顶部常量） |
| 要像 CoD / CS 的枪感 | 每把暗器有后坐图案、随机散布、第一发精准、开镜、镜头冲击（`gun.gd`、`data.gd` 的 WEAPONS） |
| 要好看的 3D 模型 | Quaternius CC0 动画模型（`assets/models/creatures`） |
| 至少 4 小时流程，和朋友玩 | 五章、50 级、五个魂环；联机时"猎杀 N 只"按人数加量（`Data.quest_target`） |
| 画面要好 | Poly Haven HDR 天空、CC0 地面贴图、程序树、草、体积雾，画质 低/中/高 |

## 仓库和发布

- 仓库：`a1733719945-maker/Alu-Chen`，开发分支 `claude/douluo-multiplayer-game-lza8mi`（也是默认分支），**不要**建 PR，除非用户要求。
- 每次推送，GitHub Actions（`.github/workflows/build.yml`）会：中继服务器测试 → 导入 → 单人全流程自动测试 → 联机测试 → 打包 Windows → 发到 Releases 的 `latest-claude-douluo-multiplayer-game-lza8mi`。
- 下载页：https://github.com/a1733719945-maker/Alu-Chen/releases/tag/latest-claude-douluo-multiplayer-game-lza8mi （`DouluoHunter-Windows.zip`）
- 联机服务器：Render 免费版 `https://douluo-relay.onrender.com`（2026-09-25 用户已部署，法兰克福，已验证 WebSocket 能连）。游戏默认连 `wss://douluo-relay.onrender.com`（`settings.gd` 的 `DEFAULT_SERVER`）。15 分钟没人会休眠，第一次连要等约 1 分钟。浏览器打开网址能看到房间数和在线人数。

## 版本历史

1. `6efaec7` 第一版：引魂索 + 联机
2. `81002e7` 第二版：成长、魂环魂技、Boss、第二章、CS 式枪感、画面
3. `fe59d2a` 第三版：五章、3D 动画魂兽和 Boss、新字体、物理
4. `ff03fb5` 魂技单键 Q + 轮盘，图标化 HUD（当前最新，CI 通过、已发布）

## 技术概要

- Godot **4.7.2**，GDScript，Forward+，Jolt 物理。项目在 `game/`。
- 数据全在 `game/scripts/autoload/data.gd`：暗器、魂兽（BEASTS）、年份（AGES、AGE_WEIGHTS）、魂技（SKILLS、SKILL_TREE，9 武魂 × 5 环 × 2 选 1）、Boss（BOSSES）、章节和任务（CHAPTERS）、奖励倍率（KILL_BONUS）、`xp_to_next`。
- 存档 `profile.gd`（等级、魂环、暗器、道具、魂骨、章节进度）；设置和按键 `settings.gd`。
- 地图：`island.gd`（MAPS：island / forest / deepforest / snow / sea 的地形、栖息地、水域深度）+ `world_builder.gd`（ENV 每个地图的天空光照雾，树草石头等）。
- 一局游戏的逻辑和联机同步：`world.gd`（房主算魂兽、Boss、任务，广播给客人）。魂兽 `beasts/beast.gd`（房主是刚体，客人是插值代理），模型和动画 `beast_models.gd`，Boss `boss.gd`（ai = water / land / air）。
- 界面：`ui/hud.gd`（HUD、魂技轮盘、魂技二选一）、`ui_kit.gd`（配色、字体、图标、键帽）、`menu.gd`、`shop_panel.gd`、`wuhun_panel.gd`、`settings_panel.gd`。
- 中继服务器：`server/server.js`（Node + ws），`render.yaml` 一键部署。

## 测试和截图

```bash
cd game
godot --headless --path . --import                       # 加了新素材后
godot --headless --path . --check-only --quit            # 语法检查（最快）
godot --headless --path . -- --autotest=solo             # 五章全流程（本机约 10 分钟）
godot --headless --path . -- --autotest=solo --chapter=4 "--plan=hunt:icelake+icefield,boss,done"   # 只测一段
godot --headless --path . -- --autotest=solo "--plan=phys,done"      # 只测魂兽物理
# 截图（xvfb + lavapipe 软件渲染，很慢，一张 1–2 分钟）
xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver vulkan --resolution 1280x720 -- --autotest=shots --plan=hudshot,done --out=/某个目录
# 联机：先起服务器，再开房主和客人（见 README）
```

- autotest 阶段：`phys`、`hunt:<栖息地,...>`、`shop`、`recoil`、`sniper`、`ring`、`boss`、`boat`、`tour`、`hudshot`、`done`；模式 `solo / shots / host / client / zoo / measure / vm`。
- 改了中文文字（新字）后要重跑 `tools/subset_fonts.py <原始 otf 目录>`，不然新字会显示成方框。原始字体在 notofonts/noto-cjk 的 raw.githubusercontent.com 上。

## 素材和工具

- `tools/fetch_assets.py`（Poly Haven / ambientCG）、`prepare_assets.py`（树叶草叶贴片）、`set_texture_imports.py`、`fetch_models.py` + `gdrive.py`（Quaternius 模型在公开 Google Drive）、`fetch_icons.py`（game-icons.net）、`subset_fonts.py`、`gen_sfx.py`（合成全部音效）。
- 许可：Poly Haven / ambientCG / Quaternius 是 CC0；字体 SIL OFL；game-icons.net 是 **CC BY 3.0，要署名**（README 里已写）。
- FBX 模型朝 +Z，要转 180°；模型真实尺寸在 `assets/models/creatures/measure.json`（`--autotest=measure` 生成）。

## 还可以做的（用户没明确要求，按优先级）

1. 菜单、暗器铺、武魂面板、设置面板还是旧的平面样式，可以像 HUD 一样图标化、现代化。
2. 第五章海神岛的画面还没截图检查过；第三章星斗大森林的光照偏白天。
3. 右下暗器名"袖箭 · 手枪 · 半自动"文字偏长，可以简化成图标 + 名字。
4. 游戏时长（约 4 小时以上）是按经验曲线估算的，没有真人跑过；等用户和朋友玩完问反馈再调数值。
