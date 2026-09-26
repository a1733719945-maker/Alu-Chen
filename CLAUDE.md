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
| 技能键太多；Q 轮盘"一坨屎"；自动选技能没有操作感 | **Q / E / F 三个魂技槽**，K 面板里自己选装哪个；不要轮盘 |
| 魂兽在天上掉不下来 | 空中分段重力、连击上推力递减有上限、尸体摔到地上再消失（`beast.gd` 顶部常量） |
| 要像 CoD / CS 的枪感 | 每把暗器有后坐图案、随机散布、第一发精准、开镜、镜头冲击（`gun.gd`、`data.gd` 的 WEAPONS） |
| 要好看的 3D 模型 | Quaternius CC0 动画模型（`assets/models/creatures`） |
| 至少 4 小时流程，和朋友玩；指向性清单任务不好玩、会卡关 | 五章、100 级成神、十个魂环；没有清单任务，只有等级 → Boss → 渡船 |
| 画面要好 | Poly Haven HDR 天空、CC0 地面贴图、程序树、草、体积雾，画质 低/中/高 |
| 魂兽太容易逃、没多样性 | 四种性格（凶暴的追着打不逃、狡猾装死、魂骨兽必掉魂骨），逃跑时间 24 秒 |
| 要 How to Fish 那样丢出去卖 | T 丢出手上的东西，丢进暗器铺旁的收购箱卖钱；放久了海鸥叼走 |
| 不要背包、要数字键物品栏 | 1-5 物品栏，T 丢的是手上拿的东西；不掉素材、不乱掉魂环 |
| Boss 打不到身体、在水下、复活后仇恨还在 | 包围盒受击体积、露出水面、魂技按表面距离、复活保护 + 脱战 |
| 魂技要有位移、减伤、变大、加速 | 飞索、瞬移、变大、飞行、隐身、减伤 |
| 队友互动 | 丢东西给队友、倒地掉暗器队友能捡、按住 F 救人、海鸥叼走倒地的人 |
| 枪没配件、没手感 | 全息 / 光学瞄具、夜光照门、激光、制退器、抛壳、新枪声、更狠的后坐；**用户还想要更好的枪感，下一轮继续** |
| 在水上飘很怪 | 深水会沉，要游、要憋气，憋不住掉血；魂环落水沉底或冲上岸 |
| Boss 太卡通 | 着色器流光 + 魂环 + 光轮 + 光柱 + 出场字幕 |
| 验证很费 token | 改完先打包、告诉用户怎么更新，**等用户说要验证再跑全流程**；只做语法检查和一两段短测 |
| Boss 太卡通、要更好的素材 | 还没解决：需要写实的怪物模型，免费 CC0 里没有合适的，要用户提供 Sketchfab 账号 / 付费素材，或者接受现在的着色器方案 |
| 狙击镜画中画看着头晕；红点镜一圈蓝光 | 全屏瞄准镜；镜片几乎透明 |
| 配件要买、东西都能卖、卖了能再买、没暗器用拳头 | 第五版已做 |
| 魂兽没差异 | 每种魂兽一个有前摇、能躲的独门招式 |
| 短时间小爽、中时间大爽 | 升级 / 配件 / 连杀是小爽；魂环突破、新魂技档次特效、Boss、新岛是大爽 |
| 要有投入、紧迫感、耐玩 | 鱼饵、饱食度、词缀、悬赏、兽潮、精英、外观、每章更难 |

## 仓库和发布

- 仓库：`a1733719945-maker/Alu-Chen`，开发分支 `claude/douluo-multiplayer-game-lza8mi`（也是默认分支），**不要**建 PR，除非用户要求。
- 每次推送，GitHub Actions（`.github/workflows/build.yml`）会：中继服务器测试 → 导入 → 单人全流程自动测试 → 联机测试 → 打包 Windows → 发到 Releases 的 `latest-claude-douluo-multiplayer-game-lza8mi`。
- 下载页：https://github.com/a1733719945-maker/Alu-Chen/releases/tag/latest-claude-douluo-multiplayer-game-lza8mi （`DouluoHunter-Windows.zip`）
- 联机服务器：Render 免费版 `https://douluo-relay.onrender.com`（2026-09-25 用户已部署，法兰克福，已验证 WebSocket 能连）。游戏默认连 `wss://douluo-relay.onrender.com`（`settings.gd` 的 `DEFAULT_SERVER`）。15 分钟没人会休眠，第一次连要等约 1 分钟。浏览器打开网址能看到房间数和在线人数。

## 版本历史

1. `6efaec7` 第一版：引魂索 + 联机
2. `81002e7` 第二版：成长、魂环魂技、Boss、第二章、CS 式枪感、画面
3. `fe59d2a` 第三版：五章、3D 动画魂兽和 Boss、新字体、物理
4. `ff03fb5` 魂技单键 Q + 轮盘，图标化 HUD
5. 第四版（2026-09-26，在用户本机 Windows 桌面会话里做的，本机没有 git/Python/Node，改完打包成补丁让用户上传）：
   - 魂兽性格 `Data.TEMPERS`（胆小 / 凶暴 / 狡猾 / 魂骨兽），`Beast._fierce`、`_swim`
   - 地上的东西 + 收购箱 + 海鸥：`world/loot.gd`（`Loot`）。**没有背包**（用户不要）：物品栏 1 主暗器 / 2 袖箭 / 3 唐莲 / 4 回血丹 / 5 魂骨（`Player.select_slot`），T 丢出手上的东西（`Player._drop_current`），左键用道具。魂兽不掉素材，只掉魂骨、偶尔掉药和唐莲
   - 魂环只在有人卡瓶颈、年份够的时候掉（`World._host_maybe_drop_ring`），用户说捡一堆魂环不合理
   - 弹道：`Fx.tracer` 是朝镜头的辉光光迹（TRACER_SHADER）+ 飞行的弩箭模型 `Fx.bolt_model`；用户说原来的弹道是"白色方框"
   - 跑步时按左键 / 右键会取消冲刺、马上开枪 / 开镜；设置页有返回键和 Esc；HUD 暗器名不写"手枪 · 半自动"
   - 魂骨六部位：`Data.BONES / BONE_SLOTS / bone_stat`，存档 `Profile.bones`（"id@年份"）+ `equipped` + `bag`
   - 倒地 / 队友按住 F 救 / 海鸥叼走 / 倒地掉暗器：`World._update_down`、`_update_revive`，`Player.lost_guns / borrowed`
   - 下水会沉、憋气、溺水：`Player._physics_process`（swimming）、`under / air`；HUD 水下滤镜，`Sfx.set_underwater`
   - 魂技新类型：giant 变大、blink 瞬移、grapple 飞索、fly 飞行、invis 隐身，buff 支持 stat2（减伤 dr）
   - Boss：受击体积按模型包围盒（`Boss._measure_box`，头是弱点球，`Data.BOSSES.weak`），`surface_dist / segment_hit` 给魂技用；
     90 米脱战、没目标回血；外观 `Boss._decorate`（HOLY_SHADER 流光 + 边缘光、四个魂环、光轮、光柱、光点）；HUD `boss_intro` 出场字幕
   - 暗器配件（`WeaponModels._holo / _acog / _attachments`，准星是 RETICLE_SHADER）、抛壳 `Fx.shell`、星形火光
   - 新音效用 `tools/GenSfx2.cs` + `tools/gen_sfx2.ps1` 合成（Windows 自带 PowerShell 就能跑）。**跑过 gen_sfx.py 以后要再跑一次 gen_sfx2.ps1**，不然枪声会被旧版覆盖
   - 用户反馈"Remotion 画 Boss"：Remotion 只能出 2D 视频 / 图片，做不了 3D 模型，所以用着色器和特效来做威猛、神圣感

6. 第四版后续（4.2，同一天，用户边玩边提）：
   - 按键重排：Q 攻击魂技 / F 辅助魂技（没东西可交互时）/ 双击 Shift 位移魂技，**不要轮盘**（`SkillSystem.cast_cat`、`CATS`）；轻点 Ctrl 翻滚（0.36 秒无敌，`Player._roll_t`）；M 地图（`ui/map_view.gd`）；B 鱼饵
   - 魂技 = 武魂 + 魂兽种类 + 年份决定（`Data.skill_for`、`AGE_TIERS`），吸收前不告诉玩家，不再二选一
   - 鱼饵 `Data.BAITS`（咬钩扣）、词缀 `Data.AFFIXES`（Beast.affixes）、饱食度 `Profile.food`、烤肉、悬赏 `Profile.bounties`（World._check_bounty）、兽潮 `World._host_tide`
   - 精英魂兽（小 Boss，temper = "elite"）固定刷新点 `World._init_elites`；陆地魂兽不消失（跑回老家转悠 `Beast._roam_tick`）
   - 每章差异：`AGE_WEIGHTS` 第三章起没有十年、第五章万年；`CH_POWER` 伤害倍数；`CH_TRAIT` 毒 / 成群 / 冰冻 / 拖拽
   - 外观：`Data.GUN_SKINS / OUTFITS`，暗器铺"外观"页，Boss 送专属皮肤；联机同步在 hello / prog 里
   - Boss 新招：延迟重击（红圈最后 0.35 秒才出）、冲击环、扇形连扫、二阶段全场大招（绿圈安全）——`World.boss_shockwave / boss_cone / boss_ultimate`，`Boss._moves`；Boss 只留一个年份魂环
   - 狙击镜是画中画（`ViewModel._setup_scope`，SubViewport + LENS_SHADER，手里的东西在 VM_LAYER 层），孔雀翎是红点；弹道是 TRACER_SHADER + 弩箭模型
   - 海鸥能打下来（`Loot._host_gull_hit`），叼着的东西 / 人会掉下来
   - 开船过场动画：`tools/boat_anim`（Remotion，React + SVG）渲染成 `assets/cutscene/voyage/000~149.jpg`（导入设成有损压缩），`ui/voyage.gd` 播放，`main._travel` 调用。重新渲染：装便携 Node，在**短路径**（比如 %TEMP%\ba）里 `npm install` 和 `npm run render`（长路径下 npm 安装脚本会失败）
   - 自动测试时 `Data.autotest = true`：关掉精英、兽潮、饥饿，钓上来的魂兽固定胆小无词缀（`bait = "test"`），不然随机因素会让 CI 偶发失败
   - 用户问答后又改了四点：暗器按章节开放（`Data.WEAPON_UNLOCK`，暗器铺显示"第X章开放"）；猎魂录（`Profile.codex`、`World._codex_kill`，每种魂兽 3 星，集齐一张图送专属皮肤 `CODEX_MAP_SKIN`）；所有粒子用圆形渐变贴图（`Fx._soft_tex`）；坐船要所有人按 F（`World._host_boat_check`）
   - 开船动画最后转成了一个 Ogg Theora 视频 `assets/cutscene/voyage.ogv`（ffmpeg：`-c:v libtheora -q:v 8`），`ui/voyage.gd` 用 VideoStreamPlayer 播。原因：GitHub 网页上传一次最多 100 个文件，150 帧图片传不上去
   - **教训**：PowerShell 批量替换时，单个 `@(@(a,b))` 会被拆开，把整个文件的某个字母全换掉了（出过一次事故，从备份恢复）。现在用 `Rep 文件 旧 新` 一对一替换；函数别叫 `R`（是内置别名）

7. 第五版（2026-09-26，成神之路，按用户 15 条反馈大改，本机做的补丁包）：
   - **没有清单任务**：`Data.CHAPTERS` 每章只有 等级 → 祭坛 → Boss → 渡船（第五章是 god）；祭坛按 `boss_level`（15/35/55/75/95）开放，
     打赢后 3 分钟可再召唤（`World._can_summon`、`_altar_cd`）；渡船 `World.boat_destinations()` 能去下一章和去过的岛，按 F 弹 `Hud.open_boat_picker`
   - **100 级、十个魂环**：`Data.MAX_LEVEL / MAX_RINGS / RING_MIN_AGE`，`AGES` 五档带 glow（万年黑环暗红光，十万年红）；成神 `World._check_god` 播 `assets/cutscene/ending.ogv`
   - 魂环掉落：瓶颈的人优先；其他按年份概率掉、30 秒散掉，按 F 炼化精华涨修为（`World._gain_essence`）
   - **魂技槽**：Q / E / F 三个槽（`Profile.skill_slots`、`set_skill_slot`，K 面板点按钮装），`SkillSystem.cast_slot`；左下角三个技能框（`Hud._sk_boxes`）
   - 引魂索改成 G / 鼠标中键；E 是第二魂技；F 是交互或第三魂技
   - 数值（`data.gd` 的"数值"一节）：`SPECIES_CH / CH_REF_LEVEL / CH_MONEY / CH_PRICE / CH_HP`，`kill_xp / kill_money / item_price / beast_max_hp / level_damage`；
     魂技威力 = 年份倍率 × (1 + 等级 × 2%)（房主上限 12）；唐莲伤害按章节涨
   - 暗器：`WEAPONS` 重做（后坐更大、`recoil_scale`），`fist` 空手（`Player._melee`、`ViewModel.punch`、`World.local_melee`）；
     所有暗器能卖（`Profile.sell_weapon`，暗器铺"卖出"），卖了能再买；**配件要买**（`Data.ATTACH / ATTACH_OK / apply_attach`，`Profile.attach_owned / attach_on`，暗器铺"配件"页），
     模型按装的配件搭（`WeaponModels.build(id, skin, outfit, on)`、`_iron / _optic`）
   - 狙击镜 / 2 倍镜：**全屏瞄准镜**（`ScopeOverlay`，开镜时 ViewModel 整个藏起来），去掉了画中画（用户说头晕）；红点 / 全息玻璃去掉蓝边
   - 枪声换成 freesound CC0 真实录音（`tools/fetch_sfx_freesound.ps1`，署名在 `assets/sfx/CREDITS_freesound.txt`），每发叠一层低频 thud
   - **魂兽独门招式** `Data.BEAST_SKILLS`（23 种）：凶暴 / 精英魂兽 `Beast._special_tick` 前摇 → `World.beast_telegraph`（地上出圈、头顶招式名）→ `host_beast_special` → `_apply_beast_special`；
     玩家负面状态 `Player.root_t / slow / vuln_t / silence_t`（翻滚无敌能躲；定身连按空格挣脱），`Hud.blind`
   - 成就 `Data.ACHIEVEMENTS`（`World._ach_check`，J 面板 `Hud.toggle_achievements`）；连杀奖励（`World._streak`）
   - 爽感特效：`Fx.level_up_burst`（升级）、`ring_breakthrough`（魂环突破 + `Hud.flash`）、`skill_flourish`（魂技按档次 `Data.skill_tier` 加法阵 / 光柱 / 万年黑红魂火 / 神技金光）、Boss 死亡神光
   - 过场：`tools/boat_anim` 重做成 1280×720 三镜头开船（6 秒）+ 成神结局 `Ending.tsx`（10 秒），渲染 mp4 再 ffmpeg 转 ogv（`-c:v libtheora -q:v 8`）
   - 碧磷沼 / 毒沼：`Island._raw_height` 水塘改成大片缓坡浅滩
   - 字体：裁剪过的思源黑体缺字时用系统字体补（`Data._init` 里的 SystemFont fallback）；本机没有 Python 跑 `subset_fonts.py`，新字尽量用常用字

## 还没做 / 可以继续

- Boss 写实模型：免费 CC0 里没有合适的，要用户提供素材；现在靠着色器 + 光环 + 死亡神光
- 数值是按公式估的（见 data.gd 注释），没有真人从 1 级玩到 100 级；等用户反馈再调 `CH_HP / CH_MONEY / KILLS_PER_LEVEL`
- 菜单、设置面板还是旧样式
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
