# 苍墟 · 猎灵 —— 项目记忆

给接手这个项目的 Claude 看的。先读完这份，再动代码。

## 和用户沟通

- **全程用中文**，思考和说明都不要写英文。说明要短、直接，多用列表。
- 用户在德国工作，这个游戏是业余做来**和朋友们一起联机玩**的。
- 用户会说 token 不够、让"快速处理"：这时只做必要的检查（`--check-only`、相关的一小段自动测试或一张截图），不要把五章全流程全跑一遍。CI 推送后会自动跑全流程。
- 做完一轮就提交、推送，然后告诉用户改了什么、有什么没做完。
- **两个账号同时做**（2026-09-29 用户定的：大号在云端、小号在本机，用户想到什么随时跟其中一个说）：开工前先读 `docs/正在做.md` 并登记，别做对方正在做的事；提交小、勤推，推送被拒就 `git pull --rebase --autostash`，冲突两边都保留。
- **用户完全信任你来做决定，别问选择题**。拿不准时自己选"玩家手上、眼睛里感受变化最大"的方案，做完告诉用户选了什么、为什么。只有真正要用户动手的事（Meshy / Tripo 生成模型、Dola 生成图）才找用户，而且一次列全。
- 2026-09-29 起用户换了一个 Claude 账号，在**本机 Windows 桌面**上做（仓库在 `C:\Users\zlche\OneDrive\文档\Alu-Chen`）。本机工具：Godot `%LOCALAPPDATA%\Programs\Godot\Godot_v4.7.2-stable_win64_console.exe`、Python 3.12、Node 24、ffmpeg（winget 装的）、git、gh。有独立显卡：开窗口截图很快（29 张约 2 分钟），截图输出放 `%TEMP%\claude\shots*`（短路径、没有中文）

## 用户提过的要求（别再犯）

| 反馈 | 现在的做法 |
|---|---|
| 不喜欢中式古风 / 毛笔字体 | 思源黑体（Noto Sans SC，裁剪过）+ Barlow Condensed 数字 |
| UI 太山寨；要参考厉害的游戏 | 第七版整体重做（见版本历史 11）：参考 Apex / 命运2 的 HUD、怪物猎人的狩猎目标、Valorant 的菜单、使命召唤的改枪属性条。**全屏面板用毛玻璃背景，不要灰盒子；不要粗黑描边；少写长句** |
| 技能键太多；Q 轮盘"一坨屎"；自动选技能没有操作感 | **Q / E / F 三个神通槽**，K 面板里自己选装哪个；不要轮盘 |
| 灵兽在天上掉不下来 | 空中分段重力、连击上推力递减有上限、尸体摔到地上再消失（`beast.gd` 顶部常量） |
| 要像 CoD / CS 的枪感 | 每把暗器有后坐图案、随机散布、第一发精准、开镜、镜头冲击（`gun.gd`、`data.gd` 的 WEAPONS） |
| 要好看的 3D 模型 | Quaternius CC0 动画模型（`assets/models/creatures`） |
| 至少 4 小时流程，和朋友玩；指向性清单任务不好玩、会卡关 | 五章、100 级飞升、十个灵环；没有清单任务，只有等级 → Boss → 渡船 |
| 画面要好 | Poly Haven HDR 天空、CC0 地面贴图、程序树、草、体积雾，画质 低/中/高 |
| 灵兽太容易逃、没多样性 | 四种性格（凶暴的追着打不逃、狡猾装死、灵骨兽必掉灵骨），逃跑时间 24 秒 |
| 要 How to Fish 那样丢出去卖 | T 丢出手上的东西，丢进暗器铺旁的收购箱卖钱；放久了海鸥叼走 |
| 不要背包、要数字键物品栏 | 1-5 物品栏，T 丢的是手上拿的东西；不掉素材、不乱掉灵环 |
| Boss 打不到身体、在水下、复活后仇恨还在 | 包围盒受击体积、露出水面、神通按表面距离、复活保护 + 脱战 |
| 神通要有位移、减伤、变大、加速 | 飞索、瞬移、变大、飞行、隐身、减伤 |
| 队友互动 | 丢东西给队友、倒地掉暗器队友能捡、按住 F 救人、海鸥叼走倒地的人 |
| 枪没配件、没手感 | 全息 / 光学瞄具、夜光照门、激光、制退器、抛壳、新枪声、更狠的后坐；**用户还想要更好的枪感，下一轮继续** |
| 在水上飘很怪 | 深水会沉，要游、要憋气，憋不住掉血；灵环落水沉底或冲上岸 |
| Boss 太卡通 | 着色器流光 + 灵环 + 光轮 + 光柱 + 出场字幕 |
| 手机上"很难射击、不合理"，要 **Mac 版**（很多朋友是 Mac 电脑） | 做了（见下面"Mac 版"一节）。手机版代码和 APK 还留着，但用户不再主推 |
| 过场动画点屏幕跳不过；平板玩着玩着黑屏卡死 | 过场在 `_input` 里接点击（全屏控件会吃掉点击）；换地图 / 坐船 / 进游戏先盖"正在前往……"再建世界（`Main._loading_layer`）。黑屏卡死没查到确切原因，用户转去 Mac 了 |
| 要手机版（朋友安卓、苹果都有） | 先做安卓：同一套代码加触屏操作 + 手机画质，CI 自动打 APK 一起发到 Releases；苹果版要苹果开发者账号（99 美元/年）才能发给朋友（TestFlight）；打包可以用 GitHub Actions 的 macOS 机器（用户不用买 Mac），但要在开发者后台建 App、证书 / 描述文件或 API Key 存进 GitHub Secrets。**还没做**，等用户有账号再说 |
| 验证很费 token | 改完先打包、告诉用户怎么更新，**等用户说要验证再跑全流程**；只做语法检查和一两段短测 |
| Boss 太卡通、要更好的素材 | 还没解决：需要写实的怪物模型，免费 CC0 里没有合适的，要用户提供 Sketchfab 账号 / 付费素材，或者接受现在的着色器方案 |
| 狙击镜画中画看着头晕；红点镜一圈蓝光 | 全屏瞄准镜；镜片几乎透明 |
| 配件要买、东西都能卖、卖了能再买、没暗器用拳头 | 第五版已做 |
| 灵兽没差异 | 每种灵兽一个有前摇、能躲的独门招式 |
| 短时间小爽、中时间大爽 | 升级 / 配件 / 连杀是小爽；灵环突破、新神通档次特效、Boss、新岛是大爽 |
| 要有投入、紧迫感、耐玩 | 鱼饵、饱食度、词缀、悬赏、兽潮、精英、外观、每章更难 |
| 复活了全岛的怪都来追我 | 凶暴的只追 32 米内的人（打过它 / 正在打的 55 米）`Beast.AGGRO_RANGE / _pick_target` |
| 没有防御，渡劫修士也被打 1-2 下就死 | 灵力护体：每级减伤 0.4%（`Data.level_armor`，灵相面板显示"护体"）；后期章节攻击倍数压平；普通咬 ×0.7，红圈大招不变 |
| 第二章被咬中毒一直掉血很烦 | 去掉了（`CH_TRAIT[2] = ""`，碧鳞蛇毒雾改成减速，碧眼蟾不带毒）。**别再加持续掉血** |
| 灵相真身"和神通有任何差别吗" | 关掉了（`Combo.TRUE_BODY = false`）。**加按钮 / 加倍数不算好玩**，要改结构：给玩家目标、风险、取舍、队友分工 |
| 不要 roguelite（选卡、随机强化） | 方向是"组队猎灵兽王" |
| 单人远征没法玩；猎到的灵环和普通怪掉的没区别；"刷怪只放在副本里" | 第十一版：野外只猎自己挑的灵兽（猎灵榜写明神通），刷怪在秘境；单人吸收快（10 秒） |
| 秘境卡脚、灵兽卡墙 | `_cyl_collider(pos, …)` 的 pos 是**圆柱的底**（以前传成中心，地面碰撞高了 1 米）；`Dungeon._keep_inside` 卡住 3 秒拉回中间 |
| 秘境里怪不打人、贴墙不动，一层秘境冒出千年兔子 | 秘境场地让 `Island.is_land` 返回真，野外随机刷的胆小灵兽被刷进了秘境。`World._host_wild` 跳过秘境里的人和 `Island.on_floor` 的点；`Dungeon._keep_inside` 收掉场地里不是秘境的灵兽；秘境之主叫的小弟算秘境灵兽（`World._minion`）。野外凶的物种一半会主动打人 |
| Boss 打死显示"掉落千年灵环"（玄鲲是十万年） | `Hud.boss_defeated` 里写死了"千年"，改成按 Boss 年份；钓灵兽的"千年灵兽！"提示也按年份 |
| 抓 Boss 没感觉、线索没用、地图太小、没有探索感和成就感 | 猎场（版本历史 18）：猎灵榜挑了灵兽，全队去一张 640 米的大地图猎它 |
| 秘境往右（东）走还是卡脚 | `Player` 的地图边界（离岛中心 150 米外不能往外走）把 900 米外的秘境也挡了，秘境里不算边界；自动测试 dungeon 阶段会往四个方向走一遍 |
| 猎物路太好找、没有探索感 | 爪痕追踪（`Hunt.clues`，按 F 查看，3 处锁定 45 秒），罗盘平时不标；`HUNT_REVEAL` 30 米 |
| 我秒怪物（太简单） | 灵兽血量下限 `Data.hp_floor`（按队伍最强暗器的输出，至少 3~10 枪，打得慢的暗器有上限）；`Profile.output / World.team_output` |
| 皮肤只是换色；要金属反光的质感、自己画、更多暗器 / 熟练度 / 配件 / 外观 | 第十二版（见版本历史 17） |
| 猎完按 F 回岛和神通键冲突、回不去 | 猎场里 **L 键回岛**（`HuntTrip.key_return`，地上还有灵环要按两次）；F 只在营地旗子旁边管用 |
| 猎场那么大只有一个 Boss | 灵兽群（`HuntTrip._packs`，走近才刷）、守宝的灵兽王 + 大宝箱（`Island.guard_spots`），宝藏远处有金光（版本历史 19） |
| 秘境打完左上角还挂着秘境信息、没有庆祝感 | `Dungeon._update_ui` 以前只在秘境里刷新；通关加烟花 + 结算面板（`_fireworks / _show_result`） |
| 千年秘境掉万年灵环；第五章还有千年秘境 | 秘境之主和秘境同年份；新增**百万年**（`AGES[5]`），第五章秘境 万年 / 十万年 / 百万年（`CH_AGE[5] = 3`） |
| 上一个秘境没吸收的灵环留到下一个秘境 | `Dungeon._end_run` 收掉场地里的灵环 |
| 第二章落霞林整张图巨亮 | `WorldBuilder.ENV.forest` 曝光 / 泛光 / 体积雾阳光都压低了（还没截图看过） |
| 挂件看不见；切枪只是把枪拿出来没手感（要像 CoD） | 挂件挂到暗器左侧前段、大一半；切枪 = 收枪（右下沉走）+ 掏枪（翻上来、冲过头落稳、咔哒），第一次掏带机括的拉栓（`ViewModel._switch_anim`） |
| 吃肉没用 | 烤肉和饱食度去掉，换成 6 种丹药（4 号位再按 4 换）；**散魂丹**在 K 面板散掉不满意的灵环、猎一只补回同一个位置（`Profile.ring_hole`） |
| 营地帐篷是倒过来的 | `WorldBuilder._camp` 布片转角正负号反了 |
| Boss 除了数值没区别、后面的 Boss 和第一个招式一样、全靠数值没有操作感（要学鬼泣） | 第十三版：每个灵主一套招（`Boss._art_*` + `world/boss_arts.gd`），都有预兆；破绽 / 极限闪避 / 无伤击败；顶尖操作 + 运气能无伤 |
| 和原著版权冲突的名字 | 全部换成原创（对照表 `docs/世界观.md` 第六节 + 版本历史 20）。**以后新加内容不要用任何现成小说的名词** |
| 没有剧情：为什么升级、为什么打 Boss、飞升只为了转生？要有中国修仙小说底子的好故事 | `docs/世界观.md`：天倾 → 五块天枢碎片 → 五大灵主 → 飞升 → 九重天 / 轮回；章节横幅、任务、Boss 出场字幕、过场动画都跟着讲 |
| 过场动画敷衍；进秘境 / 猎场没动画；开场要有动画教怎么玩 | 全部用 Remotion 重画（`tools/boat_anim`）：序章、渡海、进秘境、进猎场、飞升；**别再用简单的 2D 图形凑** |
| 拿别人用 Claude 做的"名画 + 纪录片字幕"短片对比，说游戏里的串场"太丑"（代码画的 SVG 色块） | 第十四版：画面全换成**公有领域的西洋名画**（用户选的：西洋名画，不要中国古画、不要实机画面），慢推镜头 + 调色 + 光尘粒子 + 衬线双语字幕 + 左上角细线标签 / 大数字 + 米白纸片卡片（版本历史 21）。用户问过"名画有没有 IP 问题"：没有（画家都死了一百多年，博物馆开放图库是 CC0，出处写在 `assets/cutscene/CREDITS.txt`） |
| 不要找用户要模型 / 贴图 | 自己画（Remotion / 程序生成）或者网上找 CC0 |
| 看了 AI 做的国风仙侠 CG（云海天宫、白龙、仙人背影），"我喜欢这种感觉"，要国风过场 | **例外**：这种画面只有 AI 生图做得出，用户同意自己用 Dola / 即梦生成、我写提示词（见版本历史 22）。图放 `tools/boat_anim/ai/NN`，`prep_ai.py` 裁水印 |
| Boss 要"超级大，跳起来踩我一脚掉很多血" | 朱厌 24 米高 + 跃击（版本历史 22）；其他 Boss 放大 1.3~1.5 倍 |
| 剧情"只撑起了背景，没有边玩边了解，也不够深入" | 重写成叩天之战（`docs/世界观.md`），按"边玩边讲"放进游戏：灵主台词、天枢记忆、青崖子、灵环记忆、秘境刻字（版本历史 23），后面还有青崖子 NPC、残碑、结局二选一 |
| 队友模型敷衍 | 程序模型重做（`RemotePlayer`），用户也可以放 `assets/models/player/player.glb`（提示词见版本历史 20） |
| 秘境里的 Boss 掉进水里就不见了 | 灵兽王（猎物 / 守宝王 / 秘境之主）活过 90 秒一碰水就被当成"逃走"删掉。现在王下水往老家游、泡 8 秒直接回老家；`World.beast_escaped` 对王只拉回不删 |
| 自己生成的 Boss 模型被涂成白色 | `spider.glb` / `whale.glb` 文件里**没有贴图和材质**（只有形状）→ 用程序皮肤（`Boss.SKIN_SHADER`，3D 噪声 + 发光纹路）；有贴图的自定义模型**不再叠流光层**（`_decorate` 里 `_custom` 不加 next_pass）。想要原样贴图：Tripo 重新导出"带贴图"的 GLB |
| 巨猿攻击太少、砸哪没提示、没威严；所有 Boss 打着不紧张 | 招间隔 0.4~0.9 秒、破绽缩短、贴身的人会被拍（`Boss._swat`）；出招前身子后仰抬起（`Boss.windup`）；会打到自己的招：屏幕四边红光 + 「！」（`Hud.danger`，`BossArts._warn`）；大圈震屏 + 轰鸣、巨兽走路冲锋震地；暴怒一声长啸全场一震；灵主血量下限按全队输出至少打 55 秒（`Data.BOSS_TTK`） |
| 成神没有专属 BGM、打完 Boss 没有庆祝曲 | `victory.ogg`（Solis Triumphi）打完灵主 / 秘境 / 猎场 / 试炼放；`ascend.ogg`（For Her）飞升放；`World.lock_music(名字, 秒)` 期间不被战斗曲换掉 |
| 存档要显示玩了多久 | `Profile.stats["play_s"]`（`add_play_time`，每 10 秒记一次），菜单存档按钮第一行 |
| 掏枪 / 切枪 / 开镜关镜没有机械感 | 真录音（CC0）：收枪 holster、掏枪 draw_light/heavy、拉栓 rack、落稳 settle、开镜 ads_in、关镜 ads_out；开镜到位 / 关镜手上一顿（`ViewModel.ads_settle`）；切枪慢一点 |
| 每关都是同一个玩法，要 CF 打僵尸（捡武器、守点）和割草 | 试炼（版本历史 26）：尸潮守关 + 万兽割草，码头边试炼碑 |
| 武器要像 2KOL2 那样升星突破（gamble） | 暗器升星（版本历史 27） |
| 船、帐篷、补给站更豪华，花钱加装饰 | 装饰（版本历史 27） |
| UI 和地图往国风改 | 版本历史 28。**标题用思源宋体（印刷体），不是毛笔字**——用户以前说过不要毛笔字体 |
| 人物模型"单机看不到" | 队友模型只有联机时看得到（单机是第一人称）。已做：灵相面板（K）左上角 `SelfPreview` 转着看自己 |
| 僵尸模式"图这么小"、僵尸应该过来打人、"直接参考 CF 生化追击"；挨打没伤害数字、不知道僵尸剩多少血；地上捡的枪没有瞄具 | 版本历史 30：尸潮追击（近 500 米古城长街、三道城门守点 + 渡口等船、只追人咬人、伤害数字、头顶血条、尸王大血条、兵器架的枪按品质带配件） |
| **整个游戏"质感很差"：第一人称的手像"巧克力手"，僵尸、桥是几个形状凑的，枪是几个方块凑的，很多低质模型，很难进入剧情。"要把各个模型都优化，游戏尺寸变大可以接受，但无法接受低质感"** | **还没做，下一步最优先**，见文末"交接"一节。用户说的"整体画风改成修仙国风"指的就是这个：模型和材质的质感，不只是 UI |
| "国风修仙风的 CG 你还没做，我**不要现在这个西洋风 CG**" | 还没做：序章 / 渡海 / 秘境 / 猎场 / 飞升 / 灵主全部换成 AI 国风图（`tools/boat_anim/ai/01~10`，见交接），西洋名画版以后不用 |
| 蛛母、玄鲲模型要重做（给了豆包 + Tripo / Meshy 提示词） | 用户用 Meshy 生成了**带贴图**的 GLB，放在 `tools/incoming_models/spider_meshy.glb`、`whale_meshy.glb`（各 12 MB），还没换进游戏（见交接） |

## 仓库和发布

- 仓库：`a1733719945-maker/Alu-Chen`，开发分支 `claude/douluo-multiplayer-game-lza8mi`（也是默认分支），**不要**建 PR，除非用户要求。
- 每次推送，GitHub Actions（`.github/workflows/build.yml`）会：中继服务器测试 → 导入 → 单人全流程自动测试 → 联机测试 → 打包 Windows → 发到 Releases 的 `latest-claude-douluo-multiplayer-game-lza8mi`。
- 下载页：https://github.com/a1733719945-maker/Alu-Chen/releases/tag/latest-claude-douluo-multiplayer-game-lza8mi （`DouluoHunter-Windows.zip` + Mac `CangxuHunter-Mac.zip` + 安卓 `CangxuHunter.apk`）
- 联机服务器：Render 免费版 `https://douluo-relay.onrender.com`（2026-09-25 用户已部署，法兰克福，已验证 WebSocket 能连）。游戏默认连 `wss://douluo-relay.onrender.com`（`settings.gd` 的 `DEFAULT_SERVER`）。15 分钟没人会休眠，第一次连要等约 1 分钟。浏览器打开网址能看到房间数和在线人数。

## 版本历史

1. `6efaec7` 第一版：引魂索 + 联机
2. `81002e7` 第二版：成长、灵环神通、Boss、第二章、CS 式枪感、画面
3. `fe59d2a` 第三版：五章、3D 动画灵兽和 Boss、新字体、物理
4. `ff03fb5` 神通单键 Q + 轮盘，图标化 HUD
5. 第四版（2026-09-26，在用户本机 Windows 桌面会话里做的，本机没有 git/Python/Node，改完打包成补丁让用户上传）：
   - 灵兽性格 `Data.TEMPERS`（胆小 / 凶暴 / 狡猾 / 灵骨兽），`Beast._fierce`、`_swim`
   - 地上的东西 + 收购箱 + 海鸥：`world/loot.gd`（`Loot`）。**没有背包**（用户不要）：物品栏 1 主暗器 / 2 袖箭 / 3 雷莲 / 4 回血丹 / 5 灵骨（`Player.select_slot`），T 丢出手上的东西（`Player._drop_current`），左键用道具。灵兽不掉素材，只掉灵骨、偶尔掉药和雷莲
   - 灵环只在有人卡瓶颈、年份够的时候掉（`World._host_maybe_drop_ring`），用户说捡一堆灵环不合理
   - 弹道：`Fx.tracer` 是朝镜头的辉光光迹（TRACER_SHADER）+ 飞行的弩箭模型 `Fx.bolt_model`；用户说原来的弹道是"白色方框"
   - 跑步时按左键 / 右键会取消冲刺、马上开枪 / 开镜；设置页有返回键和 Esc；HUD 暗器名不写"手枪 · 半自动"
   - 灵骨六部位：`Data.BONES / BONE_SLOTS / bone_stat`，存档 `Profile.bones`（"id@年份"）+ `equipped` + `bag`
   - 倒地 / 队友按住 F 救 / 海鸥叼走 / 倒地掉暗器：`World._update_down`、`_update_revive`，`Player.lost_guns / borrowed`
   - 下水会沉、憋气、溺水：`Player._physics_process`（swimming）、`under / air`；HUD 水下滤镜，`Sfx.set_underwater`
   - 神通新类型：giant 变大、blink 瞬移、grapple 飞索、fly 飞行、invis 隐身，buff 支持 stat2（减伤 dr）
   - Boss：受击体积按模型包围盒（`Boss._measure_box`，头是弱点球，`Data.BOSSES.weak`），`surface_dist / segment_hit` 给神通用；
     90 米脱战、没目标回血；外观 `Boss._decorate`（HOLY_SHADER 流光 + 边缘光、四个灵环、光轮、光柱、光点）；HUD `boss_intro` 出场字幕
   - 暗器配件（`WeaponModels._holo / _acog / _attachments`，准星是 RETICLE_SHADER）、抛壳 `Fx.shell`、星形火光
   - 新音效用 `tools/GenSfx2.cs` + `tools/gen_sfx2.ps1` 合成（Windows 自带 PowerShell 就能跑）。**跑过 gen_sfx.py 以后要再跑一次 gen_sfx2.ps1**，不然枪声会被旧版覆盖
   - 用户反馈"Remotion 画 Boss"：Remotion 只能出 2D 视频 / 图片，做不了 3D 模型，所以用着色器和特效来做威猛、神圣感

6. 第四版后续（4.2，同一天，用户边玩边提）：
   - 按键重排：Q 攻击神通 / F 辅助神通（没东西可交互时）/ 双击 Shift 位移神通，**不要轮盘**（`SkillSystem.cast_cat`、`CATS`）；轻点 Ctrl 翻滚（0.36 秒无敌，`Player._roll_t`）；M 地图（`ui/map_view.gd`）；B 鱼饵
   - 神通 = 灵相 + 灵兽种类 + 年份决定（`Data.skill_for`、`AGE_TIERS`），吸收前不告诉玩家，不再二选一
   - 鱼饵 `Data.BAITS`（咬钩扣）、词缀 `Data.AFFIXES`（Beast.affixes）、饱食度 `Profile.food`、烤肉、悬赏 `Profile.bounties`（World._check_bounty）、兽潮 `World._host_tide`
   - 精英灵兽（小 Boss，temper = "elite"）固定刷新点 `World._init_elites`；陆地灵兽不消失（跑回老家转悠 `Beast._roam_tick`）
   - 每章差异：`AGE_WEIGHTS` 第三章起没有十年、第五章万年；`CH_POWER` 伤害倍数；`CH_TRAIT` 毒 / 成群 / 冰冻 / 拖拽
   - 外观：`Data.GUN_SKINS / OUTFITS`，暗器铺"外观"页，Boss 送专属皮肤；联机同步在 hello / prog 里
   - Boss 新招：延迟重击（红圈最后 0.35 秒才出）、冲击环、扇形连扫、二阶段全场大招（绿圈安全）——`World.boss_shockwave / boss_cone / boss_ultimate`，`Boss._moves`；Boss 只留一个年份灵环
   - 狙击镜是画中画（`ViewModel._setup_scope`，SubViewport + LENS_SHADER，手里的东西在 VM_LAYER 层），流光翎是红点；弹道是 TRACER_SHADER + 弩箭模型
   - 海鸥能打下来（`Loot._host_gull_hit`），叼着的东西 / 人会掉下来
   - 开船过场动画：`tools/boat_anim`（Remotion，React + SVG）渲染成 `assets/cutscene/voyage/000~149.jpg`（导入设成有损压缩），`ui/voyage.gd` 播放，`main._travel` 调用。重新渲染：装便携 Node，在**短路径**（比如 %TEMP%\ba）里 `npm install` 和 `npm run render`（长路径下 npm 安装脚本会失败）
   - 自动测试时 `Data.autotest = true`：关掉精英、兽潮、饥饿，钓上来的灵兽固定胆小无词缀（`bait = "test"`），不然随机因素会让 CI 偶发失败
   - 用户问答后又改了四点：暗器按章节开放（`Data.WEAPON_UNLOCK`，暗器铺显示"第X章开放"）；猎灵录（`Profile.codex`、`World._codex_kill`，每种灵兽 3 星，集齐一张图送专属皮肤 `CODEX_MAP_SKIN`）；所有粒子用圆形渐变贴图（`Fx._soft_tex`）；坐船要所有人按 F（`World._host_boat_check`）
   - 开船动画最后转成了一个 Ogg Theora 视频 `assets/cutscene/voyage.ogv`（ffmpeg：`-c:v libtheora -q:v 8`），`ui/voyage.gd` 用 VideoStreamPlayer 播。原因：GitHub 网页上传一次最多 100 个文件，150 帧图片传不上去
   - **教训**：PowerShell 批量替换时，单个 `@(@(a,b))` 会被拆开，把整个文件的某个字母全换掉了（出过一次事故，从备份恢复）。现在用 `Rep 文件 旧 新` 一对一替换；函数别叫 `R`（是内置别名）

7. 第五版（2026-09-26，飞升之路，按用户 15 条反馈大改，本机做的补丁包）：
   - **没有清单任务**：`Data.CHAPTERS` 每章只有 等级 → 祭坛 → Boss → 渡船（第五章是 god）；祭坛按 `boss_level`（15/35/55/75/95）开放，
     打赢后 3 分钟可再召唤（`World._can_summon`、`_altar_cd`）；渡船 `World.boat_destinations()` 能去下一章和去过的岛，按 F 弹 `Hud.open_boat_picker`
   - **100 级、十个灵环**：`Data.MAX_LEVEL / MAX_RINGS / RING_MIN_AGE`，`AGES` 五档带 glow（万年黑环暗红光，十万年红）；飞升 `World._check_god` 播 `assets/cutscene/ending.ogv`
   - 灵环掉落：瓶颈的人优先；其他按年份概率掉、30 秒散掉，按 F 炼化精华涨修为（`World._gain_essence`）
   - **神通槽**：Q / E / F 三个槽（`Profile.skill_slots`、`set_skill_slot`，K 面板点按钮装），`SkillSystem.cast_slot`；左下角三个技能框（`Hud._sk_boxes`）
   - 引魂索改成 G / 鼠标中键；E 是第二神通；F 是交互或第三神通
   - 数值（`data.gd` 的"数值"一节）：`SPECIES_CH / CH_REF_LEVEL / CH_MONEY / CH_PRICE / CH_HP`，`kill_xp / kill_money / item_price / beast_max_hp / level_damage`；
     神通威力 = 年份倍率 × (1 + 等级 × 2%)（房主上限 12）；雷莲伤害按章节涨
   - 暗器：`WEAPONS` 重做（后坐更大、`recoil_scale`），`fist` 空手（`Player._melee`、`ViewModel.punch`、`World.local_melee`）；
     所有暗器能卖（`Profile.sell_weapon`，暗器铺"卖出"），卖了能再买；**配件要买**（`Data.ATTACH / ATTACH_OK / apply_attach`，`Profile.attach_owned / attach_on`，暗器铺"配件"页），
     模型按装的配件搭（`WeaponModels.build(id, skin, outfit, on)`、`_iron / _optic`）
   - 狙击镜 / 2 倍镜：**全屏瞄准镜**（`ScopeOverlay`，开镜时 ViewModel 整个藏起来），去掉了画中画（用户说头晕）；红点 / 全息玻璃去掉蓝边
   - 枪声换成 freesound CC0 真实录音（`tools/fetch_sfx_freesound.ps1`，署名在 `assets/sfx/CREDITS_freesound.txt`），每发叠一层低频 thud
   - **灵兽独门招式** `Data.BEAST_SKILLS`（23 种）：凶暴 / 精英灵兽 `Beast._special_tick` 前摇 → `World.beast_telegraph`（地上出圈、头顶招式名）→ `host_beast_special` → `_apply_beast_special`；
     玩家负面状态 `Player.root_t / slow / vuln_t / silence_t`（翻滚无敌能躲；定身连按空格挣脱），`Hud.blind`
   - 成就 `Data.ACHIEVEMENTS`（`World._ach_check`，J 面板 `Hud.toggle_achievements`）；连杀奖励（`World._streak`）
   - 爽感特效：`Fx.level_up_burst`（升级）、`ring_breakthrough`（灵环突破 + `Hud.flash`）、`skill_flourish`（神通按档次 `Data.skill_tier` 加法阵 / 光柱 / 万年黑红魂火 / 神技金光）、Boss 死亡神光
   - 过场：`tools/boat_anim` 重做成 1280×720 三镜头开船（6 秒）+ 飞升结局 `Ending.tsx`（10 秒），渲染 mp4 再 ffmpeg 转 ogv（`-c:v libtheora -q:v 8`）
   - 碧眼沼 / 毒沼：`Island._raw_height` 水塘改成大片缓坡浅滩
   - 字体：裁剪过的思源黑体缺字时用系统字体补（`Data._init` 里的 SystemFont fallback）；本机没有 Python 跑 `subset_fonts.py`，新字尽量用常用字

8. 第五版补丁 2（2026-09-26 用户试玩反馈：太简单、1 小时通关、没有重玩动力、中间关卡没记忆点）：
   - 难度：`Data.BEAST_DMG`（灵兽伤害 ×1.8）、凶暴概率提高、`Player.REGEN_*` 变慢；`KILLS_PER_LEVEL` 12 → 24
   - 每张图的奇遇 `Data.CH_EVENTS`（代替兽潮）：`World._host_tide / _on_tide / _event_env`（天色天气 tween + 粒子）/ `_host_tide_king`
   - 转生 `Profile.rebirth / do_rebirth / rebirth_power / rebirth_hard`（主菜单按钮）；Boss 重数 `Profile.boss_tier`、`World.boss_tier / _boss_k`
   - 三个存档位 `Profile.slot / use_slot / slot_summary`，`Settings.save_slot`，菜单按钮
   - X 收起暗器（`holster`，fist 一直在 guns 里）、`Data.MOVE_K` 暗器重量影响移速、V 检视（`ViewModel.inspect`）
   - 瞬狙（`Gun.spread` 开镜六成就准，`scoped` 阈值 0.6）、切枪取消拉栓、狙击 range 1500 不衰减；Boss 挨打 15 秒内不回血（`Boss._since_hit`）
   - 海鸥群 `Loot._flock`（FLOCK_N 只盘旋、俯冲叼东西、叼着不走、打下来掉东西 + 按距离给钱、40 秒补一只；消息 gflock / gdive）
   - 瓶颈感应：`Lure` 钓到需要年份的机会 30%；精英年份按章节 `[1,1,2,3,3]`
   - 鱼饵按章节开放（`ITEMS` 的 `ch`）；Boss 大招期间不出别的招、绿圈判定 5.8 米
   - 自定义 Boss 模型：`assets/models/bosses/<kind>.glb`（`BeastModels.custom_boss_path / instance_custom`，按包围盒自动缩放）
   - 修：换地图后鼠标没锁（旧 World._exit_tree 把鼠标放出来了），4 号位烤肉名字，击杀音效变轻，拳头音效重新下载

9. 第五版补丁 3（用户：第三章就犯困、后面的神通只是数值变化特效简陋、倒地拉人太傻）：
   - 倒地：`World._on_player_died` 直接被海鸥叼上天（`Loot._update_carry` 在上空转圈，`end_carry`），打下海鸥 → `gull_dropped_me` → `_fall_t` 落地 `revive_here`；空格 / 超时 `_respawn_at_dock`。不再有"按住 F 救人"
   - 新神通类型（`Data.SKILLS` 里改了千年以上的一批，id 不变存档兼容）：summon / orbit / chain / blackhole / domain / empower，神技加 `"shen": true`。
     房主逻辑 `SkillSystem._new_skill_host / _update_summons / _update_orbits / _chain / _update_domains / _update_delayed / host_empower`；
     特效 `Fx.spirit_body / summon_visual / summon_attack / orbit_visual / chain_fx / blackhole_fx / domain_fx / meteor_strike / shen_manifest / shield_bubble / empower_hit`；
     灵相附体 `Player.empower`，`World.local_fire` 命中时处理；特效颜色 `Data.WUHUN[].fx`（`wuhun_fx_color`）
   - 野生灵兽 `World._host_wild`（`_host_spawn_wild`）；灵兽巢穴 `world/nests.gd`（`Nests`，StaticBody meta "nest"，消息 nesthit / nesthp / nestdown / nestup / nestsync）
   - 引魂索飞索：`Lure` 钉在地上（`_on_ground`）再按 G → `Player.grapple_to`
   - 背景音乐 `Sfx.play_music`（assets/music，freesound CC0，CREDITS.txt），`World._update_music` 按 Boss / 奇遇 / 战斗 / 探索切换；设置里音乐音量
   - 自动测试新增阶段：skills2（新神通）、events（奇遇 + 海鸥群）、down（倒地救人）、nests（巢穴）、bossshot（看 Boss 模型）
   - Boss 模型：用户用 Tripo / Meshy 生成的 GLB 放在 `assets/models/bosses`，太大的用 `tools/shrink_glb.gd`（Godot 自带减面 + 贴图缩到 1K）压到 3 MB 左右

10. 第六版（2026-09-27）：用户说零星加乐趣没用，要整体变好玩，但**明确不要肉鸽**（他们上一个游戏就是 2D 肉鸽，做到一半被打断撤掉了）。
   方向："组队猎灵环"，学《怪物猎人》——每座岛的核心是 3 只灵兽王：
   - 精英升级成灵兽王：`Data.ELITE_*`（血 ×14、体型 ×2、伤害 ×2.2、奖励 ×12、6 分钟重生、每图 3 只），`Beast.display_name` 显示"百年青鸾王"
   - 灵兽王 AI（`Beast._elite`）：`_king_tick` 大招（slam 震地 / pounce 扑杀 / roar 咆哮，`World.king_move` 用 boss_telegraph / boss_shockwave），
     半血 `_phase2` 暴怒叫小弟（`World.king_phase2`），1/4 血 `_retreat` 逃回巢穴回血（`_king_retreat_tick`，只逃一次）
   - 引魂索钩灵兽（`Lure._fly` 射线含灵兽层 → `World.host_hook`）：小灵兽拽上天；灵兽王捆魂 `Beast.add_rope / bind`（单人 1 根、联机 2 根，3.5 秒内），消息 hook / hookfx / kingrope / kingbind / kingmv / kingev
   - 奖励：`_host_maybe_drop_ring` 灵兽王每个需要的人一个灵环；`_on_kill` 发王魄 `Profile.materials`
   - 符阵附魔 `Data.ENCHANTS / ENCHANT_ORDER`，`Profile.enchant / do_enchant`，暗器铺"附魔"页，`World.local_fire` 命中按几率触发（复用 `SkillSystem.host_empower`）
   - HUD：左上灵兽王列表（`World.king_list`，距离方向 / 重生倒计时），顶上血条（`World.focus_king`），打王时放 Boss 音乐
   - 自动测试阶段 kings

11. 第七版（2026-09-27）：用户要"整体 UI 参考厉害的游戏优化"。全部界面重做，逻辑没动：
   - 样式库 `ui_kit.gd`：颜色（GOLD 主操作 / JADE 信息 / RED 危险 / MOON MIST DIM 三档灰白）、`kicker`（眉题）、`header`、`section`（小标题 + 细线）、`chip`、`stat_bar`、`tabs`（下划线分页）、`menu_item`（左对齐大字菜单）、`card_button`（整张可点的卡）、`key_hint`、`ring_dot`、`panel_head`；
     `blur_material / backdrop`：读屏幕 mipmap 做毛玻璃（全屏面板的底）；`make_theme()` 在 `main._ready` 合进引擎默认主题（输入框、滑条、勾选框、下拉、滚动条、提示）
   - HUD `hud.gd`：左上目标（括号里的话拆成小字）+ 狩猎目标卡（方向箭头、距离、血条、暴怒 / 捆住 / 逃回巢穴）+ 悬赏；上中罗盘（`_draw_compass`，地点 `_compass_marks`）+ 魂类 Boss 血条（掉血先白后缩）+ 提示条；
     右上小地图、灵石、成就卡、击杀信息；左下等级六边形徽章、体力（护盾叠加）、灵力、修为、饱食、状态标签；下中交互提示（"按 F xxx" 拆成键帽）、神通方块（冷却扇形、好了闪一下）；右下弹药大数字 + 物品栏格子
   - 灵兽头顶的名字和血条改成 HUD 画（`Hud._draw_plates`，只画近的、挨过打的、灵兽王），`Beast._hp_label` 只用来取位置、隐藏了
   - 倒地：画面变灰（读屏幕）+ 倒计时条 + [空格]；受伤方向改成红色弧；Boss 出场字幕、章节横幅改成两边细线
   - 面板：暂停（左边大字菜单、右边按键表）、暗器铺（暗器两列卡片 + 属性条，升级格子）、灵相（立绘渐隐、灵环圆环、灵骨六格）、成就（三列卡片，完成的排前）、神通二选一（两张大卡）、渡船（目的地卡）、设置（分段）、主菜单（左菜单 + 右灵相立绘和九宫格头像 + 存档卡）、大地图（标题栏 + 图例）
   - 自动测试 `uishots`：一次截全部界面（`--autotest=shots --plan=menu,uishots,done --out=目录`，本机有显卡，不要 --headless）

12. 第八版（2026-09-27）：用户说特效劣质，全部特效重做（`fx/fx.gd` 函数名和参数都没变，外面不用改）：
   - 贴图 `assets/fx/*.png` 全是程序生成的：`tools/make_fx_textures.gd`（`godot --headless --path game --script ../tools/make_fx_textures.gd`，约 11 秒）。
     glow / flare（星芒）/ spark（火花条）/ smoke（2×2 烟团）/ ring（冲击环）/ halo（灵环）/ warn（预警圈）/ scorch（焦痕）/ crack（裂纹）/ noise / swirl（漩涡）/ slash（月牙斩）/ magic（法阵）。
     **发光贴图 RGB = 透明度**（贴花的发光只看 RGB，白 RGB 会整块方片发光）；`.import` 里开了 mipmap
   - `fx/fx_lib.gd`（`FxLib`）：贴图 / 粒子材质 `pmat` / 平面 `quad_mat` / 朝镜头 `bill_mat` 缓存，着色器 SPARK（按速度拉长）、FIRE（鼓包翻滚的火球）、PILLAR（光柱 / 光壁 / 冲击墙）、BEAM（光束 / 闪电）、SPIRIT（魂灵）、SHIELD（六边形护盾）；
     `soul_ring`（灵兽脚下和掉落的灵环）、`no_decals`（灵兽、Boss、队友、手里暗器放第 2 渲染层，地面贴花只投第 1 层）
   - 一个特效叠几层：闪光 `_flash` → 主体 → 火花 `_sparks` / 光点 `_glows` / 火团 `_fire` / 烟 `_smoke` / 碎屑 `_bits` → 地面 `_ground`（陆地用 Decal 贴花，水面用平面）→ 灯 `_light` → 震镜头 `_shake`
   - 环境泛光改成 SCREEN，多开第 4 层（`world_builder._environment`）；Boss 冲击墙、扇形预警改成着色器（`world._on_shockwave / _on_cone / _cone_shader`）
   - **坑**：项目开了 MSAA，3D 里读屏幕（热浪扭曲）和读深度（软粒子 proximity_fade）都会出错（画面变暗、烟整团淡没），所以都关了（`_distort` 空函数、`pmat` 不开 soft）
   - 自动测试 `fxshots`：正前方一个接一个放 30 种特效截图（`--autotest=shots --plan=fxshots,done --out=目录 [--only=explosion,beam]`）。**要开窗口，会抢焦点，用户在玩游戏时别跑，先问**
   - 没来得及看效果的：烟（关了软粒子以后）、光束（改成连贯光带以后）、爆炸后的烟和焦痕。下次先跑 `--only=explosion_smoke,poof,beam,chain` 看

13. 第八版补丁（2026-09-27 用户试玩反馈）：
   - 开枪一片雾 + 黑屏抖动：`Fx.muzzle_flash` 在自己枪口（镜头前半米）放了烟团，糊满屏幕。现在不放烟，镜头附近的火光缩小；打到身边 3 米内也不出烟
   - 字太多：普通命中不飘伤害数字（只有爆头 / 击杀）；灵兽头顶名字只有灵兽王、准星对着、挨过打又很近才显示；招式名不飘；自己的击杀不进右边消息；逃跑的灰字没了；
     任务只留一句；死了的灵兽王不列；悬赏挪到 Tab 修士榜；神通格子不写名字；左下不写称号和灵力数字；章节横幅只留第一句；世界里的路牌 / 掉落物名字走近才显示（`visibility_range_end`）
   - 神通打不动后面的怪：`SkillSystem._dk()` = 章节血量倍数 × 转生难度，所有神通伤害（`_sdmg / _boss_hit` / 灼烧）都乘它；灵相附体 / 附魔的伤害来自暗器，不乘
   - 天上飞的鸟 / 蛾子 / 蝙蝠 / 海鸥能打了：`WorldBuilder._critters`（灵兽层的球，meta "critter"），暗器或引魂索打中 → `World.critter_hit` → 房主刷一只真的灵兽掉下来，天上那只藏 90 秒（消息 critter / critterhide）
   - 不再刷小怪升级：每章第一个任务从"修炼到 N 级"改成"猎杀岛上的 3 只灵兽王"（任务类型 kings，岛上不到 3 只按实际数算）；
     灵兽王死了全队每人加 `Data.KING_XP_LEVELS`（2.5）级这一章的修为；`KILLS_PER_LEVEL` 24 → 12
   - 自动测试新阶段 critters（打飞鸟 + 灵兽王任务计数）

14. 第九版（2026-09-27）：用户说"只是减少了升级要刷的怪，没有增加乐趣，只是缩短时长"。加了两个改变手感的系统（`world/combo.gd`，`Combo`，World 持有 `world.combo`）：
   - 猎灵连击：空中命中 +1（爆头 +1）、地上命中 +0.25、空中击杀 +4、地上击杀 +1.5；3 秒不加分就断（变身时 5 秒）。评级 `Combo.RANKS` D→SSS，
     奖励倍数 1.0→2.5（`World._on_kill` 里乘在自己拿的灵石和修为上）；命中音调 `combo.pitch()`；升评级 `Hud.combo_rank_up`，S 以上发消息 crank 给队友
   - 灵相真身：连击充能（`TB_PER_POINT / TB_PER_KILL`），满了按 Z（动作 true_body）变身 12 秒：伤害 +120%、移速 +25%、子弹不耗（每帧补满弹匣）、
     天上法相 `Fx.shen_manifest` + `Fx.true_body_aura`（自己不放光焰粒子，会糊镜头）+ 屏幕四边一圈光（`Hud._tb_edge`）；消息 tb，25 米内队友伤害 +30%
   - HUD：左边中间评级大字母 + 连击数 + 奖励倍数 + 快断的条；神通格子上面灵相真身充能条（满了闪 + Z 键帽）
   - 自动测试阶段 combo（逻辑）、comboshot（截图）
   - 用户对"好玩"的要求：**要改变每一刻手上的体验，不是调时长 / 数值**。下次想新玩法先想"打得好和打得烂有什么区别、有没有爽到顶的时刻、朋友之间有没有互动"

15. 第十版（2026-09-27）：用户试玩反馈"仇恨全岛、没防御、中毒烦、还是不好玩"，否掉了"灵环自选 / 猎王克制 / 融合技"，同意做**猎灵远征**（试玩只有苍梧林海）：
   - 修：仇恨范围（见上表）；灵兽被圆石头挤到地形下面会一直往下掉（凭空消失），`Beast._physics_process` 里低于地面 1.2 米就拉回地面；
     等级减伤 `Player.defense()`；`CH_POWER` 压成 1.0 / 1.2 / 1.4 / 1.6 / 1.8，`BITE_K` 0.7；第二章不中毒；灵相真身关掉
   - 第十版还做了一个"猎灵远征"试玩（单独的模式），用户试了说单人没法玩、吸收的灵环和普通怪掉的没区别——第十一版并进了正式玩法，远征模式删了（`expedition.gd` 只剩空壳，网页上传删不掉旧文件）

16. 第十一版（2026-09-28，用户睡觉前授权"整个游戏新做、随便定内容、可以开窗口测试"，重点是游戏性、质感、可玩性）。按用户自己的想法改了结构：
   **野外只猎指定的灵兽，刷怪只在秘境里。**
   - 野外（`world.gd`）：不再有成群的凶暴灵兽（`_host_wild` 只刷少量胆小的）、兽潮（`_host_tide` 关了）、灵兽巢穴（`Nests` 不 setup）、固定的灵兽王（不 `_init_elites`）、悬赏（清空）。
     普通灵兽**不掉灵环**（`_host_maybe_drop_ring` 只剩灵兽王分支）。引魂索钓灵兽照旧（钓鱼、卖钱、练空中连击）
   - 猎灵（`world/hunt.gd`，`Hunt`，`world.hunt`）：
     - 猎灵榜：L 键或码头边的告示牌（`WorldBuilder._board`，`board_pos`）→ `Hud.open_board`。列出这座岛陆地上 / 天上的灵兽（水里的不行），
       每只两个年份（`Hunt.base_age` 和再高一档），**卡片上写着吸收后会领悟的神通**（`Hunt.skill_preview` = `Data.skill_for`，和吸收时算的一样）
     - 挑了 → 消息 hreq → 房主在离大家远的地方刷一只灵兽王（`hunt_role = "target"`，血量 ×(0.55 + 0.4×多的人数)），在栖息地之间逛（`home_speed`）
     - 不标准确位置：发光脚印 hfp、吼声 hroar（罗盘准 6 秒）、罗盘方向偏 ±35 度，55 米内弹"发现猎物"
     - **吸收任何灵环都要站着**（`Hunt.host_absorb`，消息 absorb 由它接管）：单人 10 秒、只来一小波；联机 25 秒、每 7 秒一波冲吸收的人（`focus_peer`），队友护法；
       吸收的人倒下 / 被技能带离 5 米 → 失败，灵环掉回原地（hchend / hchq）
   - 秘境（`world/dungeon.gd`，`Dungeon`，`world.dungeon`）：
     - 每座岛三个入口（`_place_portals` 按岛的数据算，每台电脑一样；离码头近的一层、远的三层），年份 `Data.dg_age`（`CH_AGE` + 层数），推荐等级 `dg_level`
     - 场地在地图外高空 `ARENA = (900, 420, 0)`（比远处的山高，不然会插进山里），`Island.add_floor` 让 `height_at` 在场地里返回平台高度——红圈、脚印、落地、灵兽物理都照常用
     - 一局：准备 5 秒 → 三波（`DG_TIERS.waves`，联机每多一人 +2）从三个兽门出来 → 秘境之主（灵兽王，`hunt_role = "dgboss"`，不逃回巢）+ 场地红圈陨石 → 通关：灵石、修为、宝箱（回血丹、雷莲、二层以上灵骨）、
       灵环（卡瓶颈的人）、王魄；记最快时间（`Profile.stats["dg_best_章_层"]`）；完成章节任务 dungeon
     - 每局一个随机词条 `DG_MODS`（兽潮 / 坚甲 / 陨星 / 疾风 / 狂暴），奖励跟着涨
     - 同时只有一局；队友随时从同一个入口进来；人都走了（或都倒下回码头）就结束；被打飞出墙的灵兽拉回来（`_keep_inside`）
     - 消息 dgst / dgenter / dgin / dgleave / dggate / dgboss / dgmet / dgclear / dgend
   - 章节任务：通关一次秘境 → 修炼到 N 级 → 祭坛 → Boss → 渡船（`CHAPTERS.quests`，类型 dungeon）；`KING_XP_LEVELS` 2.5 → 1.5
   - 第一次进第十一版：章节横幅后弹一次"新玩法"（`Profile.stats["v11_intro"]`）
   - 自动测试：`huntrun`（猎灵榜 → 踪迹 → 打死 → 吸收，学到的就是卡片上的神通 → 倒下打断）、`dungeon`（三个入口 → 进 → 打完 → 奖励 / 宝箱 / 纪录 / 任务 → 离开 → 倒下失败）、
     `dgshot`（截图，要开窗口）、联机 `--autotest=host --dg=1` + `--autotest=client --dg=1`
   - **灵兽掉到地形下面**：追人时被圆石头挤下去会一直掉（第十版发现），`Beast._physics_process` 里拉回地面
   - **倒下不再丢暗器**（`Player.drop_guns_on_death` 返回空）：用户两个真存档的 `weapons` 都是空的（倒下丢光了），89 级只能空手打——"打不动、一来就死"的一大原因。
     存档版本 4（`Profile.VERSION`）：版本 3 的存档读进来时，`upgrades` 里有的暗器全部还回去；任务下标往后挪一格（新章节任务多了两个）
   - 自动测试 `bot`：`--from_save=profile.json --tier=0`，拿玩家真存档的拷贝（只读）让机器人站在台子上自动瞄准开枪打一局秘境，看掉多少血、多久通关——调单人难度用。
     `migrate`：旧存档任务下标升级
   - 秘境调过的数（按机器人）：小怪血量 `DG_MOB_HP` 0.75、出场间隔 1.1 秒、单人每波 3/4/5（一层）

17. 第十一版补丁 + 第十二版（2026-09-28，用户试玩第十一版的 6 条反馈 + 要求枪械系统大改）：
   - 补丁：秘境碰撞（见上表）、爪痕追踪（`Hunt.clues / read_clue / located`，消息 hst 里带 region 和 clues）、
     远处 / 狙击 / 爆炸必飘伤害数字（`World._apply_hits` 的 heavy）、冲撞型灵兽贴身直接咬（`Beast` 的 "charge" 分支）、
     血量下限 `Data.hp_floor`（`REF_KIT / HP_SHOTS / HP_TTK / HP_FOLLOW / ELITE_FLOOR`，`Data.weapon_output` 把三连发 / 蓄力 / 爆炸算进输出），
     后面章节秘境小怪伤害再乘 `DG_MOB_DMG_CH`
   - 新暗器（`Data.WEAPONS`，`WEAPON_ORDER` 十把）：寒梅袖箭 meihua（mode "burst"，`burst / burst_gap`）、追星针 longxu（射手，pierce 2）、
     子母雷珠 zimu（`splash / splash_dmg / children`，`World._blast / _child_blast`，消息 blast）、流沙机弩 hansha（`spinup`，`Gun.heat`，模型里 Rotor 会转）、
     天心泪 guanyin（mode "charge"，`charge / charge_k`，`Player._charge_input`，`Gun.charge`，满了穿透 8 只 + 光束；准星外一圈蓄力环 `Crosshair`；模型里 Tear 随蓄力变亮）。
     副手 `Data.SIDEARMS`（2 号键在袖箭和寒梅袖箭之间换，`Player.sidearms / _is_side`）。`local_fire(g, …, k, pierce_over)`，命中结算拆成 `World._apply_hits`
   - 配件：新部位 mag（扩容 / 快拔 / 灵晶弹匣）、stock（轻型 / 战术枪托），枪口补偿器、消音器（`quiet`：枪声小、没火光），斜握把，4 倍镜（`WeaponModels._x4`）；
     `Data.ATTACH_SLOTS`，`apply_attach` 支持 mag_k / reload_k / dmg_k / ads_k / move_k / recoil_all / quiet。瞄具和配件用自己的黑色材质（`WeaponModels._om`），不跟皮肤
   - 熟练度：`Profile.mastery`（暗器 -> 经验），`Data.MASTERY_XP / MASTERY_PERKS / mastery_gain / mastery_bonus`，`World._mastery_kill`（本地击杀时按手里的暗器算），
     加成在 `Profile.weapon_stats` 里；3 / 6 / 10 级送这把暗器的皮肤（皮肤里 `"mastery": N`）
   - 皮肤材质：`player/gun_skin.gd`（`GunSkin`）一个着色器画 18 种花纹（木纹、渐变、大马士革、碳纤维、玉脉、流光、熔岩、星云、龙鳞、珠光、回路、冰晶、暗影烟、水波、极光、拉丝、蛛网），
     按"暗器根节点坐标"算（`bind_part` 把零件相对根节点的变换写进 instance uniform），金属靠天空反射。`Data.GUN_SKINS` 每项加了 pat / c2 / c3 / body_metal / body_rough / coat / glow_k 等字段（说明在 data.gd 里）。
     每把暗器单独穿：`Profile.skin_of / skin_for / owns_skin / wear_skin`；联机同步 skin_of（hello 第 9 项、prog 第 6 项、info "skins"）
   - 自己画：`ui/paint_panel.gd`（`PaintPanel`），画布 512×256 从右侧面投影（`GunSkin.box2to1(WeaponModels.side_box(id))`，左边枪尾右边枪口），
     存 `user://paint/<存档文件名>_<暗器>.png`，质感 `Profile.paint[暗器].finish`（`Data.PAINT_FINISH`）；队友看到的是原色
   - 挂件：`Data.CHARMS`，`Profile.charms / charm_of`，`WeaponModels._charm`（节点 Charm，`ViewModel._animate_extras` 像摆一样晃）
   - 暗器铺：暗器卡片显示开火方式和熟练度；配件页先选暗器、按部位分；外观页 = 选暗器 + 3D 预览（`ui/gun_preview.gd`，`GunPreview`，可拖动转）+ 皮肤卡片（点了先预览）+ 挂件 + 熟练度 + "自己画"
   - 自动测试：`guns2`（五把新暗器的机制、熟练度、新配件、10 × 28 个暗器皮肤组合、自己画、挂件、外观页和画板）、`gunshots`（截图，要开窗口）
   - **教训**：PowerShell 拼接文件时读一个超长路径的文件失败（要 `\\?\` 前缀），`$t2` 变成空，结果把 data.gd 写成了 0 字节——
     从 v11 的补丁包 + 会话记录里的每次修改重放才恢复。**写回文件前先检查新内容的长度**，读写都用短路径（`%TEMP%\rec`）
18. 猎场（2026-09-28，用户选的方向："专门的大猎场"）：
   - 猎灵榜挑灵兽 → `Hunt.host_request` 发 huntgo → `World.go_hunt` → `Main._change_map` 盖一层"正在前往猎场"再建新世界 `World.new(chapter, hunting)`；
     回岛 `HuntTrip.host_return` 发 huntback → `World.travel_back`。都不改章节进度。中途加入的客人从 init 第 9 项拿到 hunting
   - 地图：`Island.new(map_id, hunt_seed, species)` 的 hunting 模式（`island.size` 641，`half` 320；岛还是 321）：`_define_hunt` 摆 6~7 片区域（猎物的老窝 home、巢穴 nest、这一章别的栖息地，带 label）、
     山头 hills、山脊 ridges、水塘；`_hunt_height` 外圈一圈高山；`_place_hunt_landmarks` 营地（spawn）、宝藏 `treasures`、小路；`zone_name(pos)`。
     **所有用到地图大小的地方改成 `island.size / island.half`**（world_builder、map_view），`WorldBuilder._ext() / _area_k()` 按面积放大树、石头、草的范围和数量；猎场不建码头 / 暗器铺 / 祭坛 / 告示牌，建营地 `_camp`（补给箱 = 暗器铺，`camp_pos`）；秘境不在猎场建入口
   - `world/hunt_trip.gd`（`HuntTrip`，`world.trip`）：限时 25 分钟、全队倒下回营地 3 次失败（`World._respawn_at_dock` → `on_my_faint`）、10 处宝藏（每人自己找，`_open_treasure`）、结算评级 S/A/B/C（用时 + 倒下次数，活捉 ×1.5）、最快纪录 `stats["hunt_best_物种_年份"]`、两分半自动回岛 / 营地旗子按 F 回；消息 htst / htfaint / htdone / htfail / htback
   - 猎物（`Hunt.host_spawn_trip_target`）：在老窝出现（离营地几百米），血 ×`HUNT_HP_SOLO/PER`，在区域之间逛；爪痕 24 米一处、60 米内看得见，看爪痕放出寻魂蝶（`_butterflies`）飞向它去的方向；
     三成血逃回巢穴（`Beast.nest_pos`），在巢穴睡着（`Beast.napping`，头上 Zzz，消息 ksleep），偷袭 ×2.5；三成五以下一路滴血（hblood）；两成以下虚弱（`Beast.weak`，速度 ×0.6），
     引魂索捆住 2.5 秒活捉（`World.host_hook` → `Hunt.host_capture_start / _host_captured`，消息 hcap，王魄 ×2）。岛上的猎灵榜不再在岛上刷猎物
   - **坑**：`Beast` 是 RigidBody3D，`sleeping` 是引擎自带属性，自己的变量不能叫这个（改叫 napping）
   - 自动测试：`huntrun`（去猎场 → 爪痕锁定 → 逃回巢穴睡觉 → 偷袭 → 虚弱活捉 → 结算 → 吸收灵环 → 开宝藏 → 回岛）、`huntfail`（倒下 3 次失败回岛）；联机 dghost / dgclient 在秘境之后一起去猎场、结算、回岛
19. 猎场补丁 + 一堆试玩反馈（2026-09-28，用户边玩边提，见上表最后几行）：
   - 猎场内容（`hunt_trip.gd`）：房主在各区域 / 山头 / 山脊 / 水塘边定 20 多处灵兽群（`_host_setup_packs`），有人走到 35~110 米才刷（`_host_wilds`，同时最多 22 只，打光了 200 秒再来，年份不超过猎物），`World._host_wild` 在猎场不刷；
     守宝的灵兽王（`hunt_role = "guard"`，走近 140 米才刷，血比猎物薄，**不掉灵环**，王的修为算一半）守着大宝箱（红光柱，王倒下变金光，每人开一份：一大笔钱、回血丹、雷莲、六成灵骨），消息 htguard，htst 第 5 项是守宝王死没死；
     地图 / 罗盘上标"守"（王）和"箱"（能开了）；小宝藏 14 处、150 米外能看到淡金光柱
   - 回岛：**L 键**（`key_return`；客人按了是告诉房主，房主按 L 一起回）；结算面板和顶上一行写着
   - 秘境：左上卡片出来就收；通关烟花 + 结算面板；秘境之主不再高一档；场地里剩的灵环收掉；年份最高到百万年（第四章三层十万年、第五章 万年 / 十万年 / 百万年），第五章小怪血 ×0.65、伤害 ×0.68 补回来；第一波不低于这一章的年份
   - 丹药（`Data.PILL_ORDER`）：回血丹（H）、回魂丹、疾风丹、金刚丹、破境丹、巨灵丹，`Player.eat_pill`；4 号位再按 4 换（`cur_pill / owned_pills`）；增益显示在左下状态标签；灵兽 / 海鸥 / 巢穴掉 `Data.random_pill()`；旧存档的烤肉折成钱
   - 散魂丹 `scatter_pill`：`Profile.remove_ring(i)` 留一个洞 `ring_hole`，`next_ring_index()` 先补洞，`add_ring` 插回原位置、神通槽跟着挪；K 面板每个灵环有「散」（点两次）
   - 切枪动画（`ViewModel.set_weapon` 返回能开枪的时间给 `Player.switch_t`）、挂件位置（`WeaponModels._charm` 按暗器大小算）
   - 自动测试：huntrun 加了灵兽群 / 守宝王 / 大宝箱 / L 回岛；dungeon 加了结算面板、出来卡片消失、三层之主年份；新阶段 `pills`（丹药 + 散魂丹）
20. 第十三版（2026-09-28 夜，用户睡觉前授权"不要问我、随便改、全部跑一遍、注意伤害数值"）：
   - **灵主招式**（学鬼泣：每个 Boss 几套机制，顶尖操作 + 运气能无伤）：`world/boss_arts.gd`（`BossArts`，`world.arts`）是招式积木——
     `lane`（直线）/ `sweep`（扇形扫）/ `circle`（圈，late = 最后一刻才出）/ `rain`（一串落点）/ `wall`（带缺口的推进墙）/ `vortex`（吸人漩涡）/ `chase`（追着人落）；
     风格 `poison / silk / rock / ice / water / fire`（`_impact` 冰锥、毒雾、蛛丝、碎石、水柱、火），消息 ba。伤害 = 招式数 × `_k()`（`Data.BOSS_DMG_CH` × 重数）
   - `Boss._moves` → `_art_mandala / _art_spider / _art_titan / _art_dragon / _art_whale`（按权重 `_pick`，二阶段多两招），`_lunge`（冲撞，again 连冲）、`_act_tick`（charge / climb）、`_later`（延时出招）。
     每招的名字见 autotest 的 `ARTS`。旧的 `_atk_cd / _dive_cd` 设成 1e9 不用了
   - 破绽：`BossArts.stun(b, 秒)`（冲撞撞空、砸下来、跃出水面后），`Boss.stun_t`，挨打 ×1.3、弱点 ×2，头上「破绽」，消息 bstun
   - 极限闪避：`Player.take_damage(amount, from, tick)`——翻滚无敌期间被非持续伤害（tick = false）打到 → `_perfect_dodge()`（4 秒伤害 +30%、灵力 +15%、`stats.perfect_dodges`）
   - 无伤击败：`World.boss_nohit`（出场时 true，挨打就 false）→ 报酬 ×1.5、`stats.nohit / nohit_<kind>`，成就 nohit_1 / nohit_5 / pdodge_20
   - 灵兽独门招式的样子按种类（`World.BEAST_FX`）
   - **伤害核算**（这次完整跑时）：玩家血 100 + 7×(等级-1)、护体每级 0.4%。灵主按 `BOSS_DMG_CH` 反推（第一章 18% → 第五章 22%，大招三成多）。
     `Data.bite_cap(章, 是不是王)`：没前摇的一口最多掉 12%（王 22%），有红圈的独门招 ×2，灵兽王震地 / 扑杀 / 咆哮 ≈34% / 39% / 22%（`World.king_move`），山魈扔石头 ×1.5。
     以前第二章百年铁甲兕王一口 37%、第五章十万年猎物一记扑杀 80%。秘境小怪一口 3%~11%（`DG_MOB_DMG_CH`）
   - **改名**（避开原著 IP，内部 id 全没变，存档兼容）：斗罗大陆 → 苍墟，魂环 → 灵环，魂技 → 神通，武魂 → 灵相，魂兽 → 灵兽，魂骨 → 灵骨，金魂币 → 灵石，唐门 → 千机阁，佛怒唐莲 → 九转雷莲；
     暗器 连机神弩 / 流光翎 / 千丝雨针 / 穿云弩 / 寒梅袖箭 / 追星针 / 子母雷珠 / 流沙机弩 / 天心泪；灵相 青冥藤 / 玄月镰 / 灵葫 / 啸风白虎 / 玄夜灵猫 / 朱雀 / 九层玲珑塔 / 镇岳锤 / 九天玄女；
     Boss 碧鳞蛟 / 千目蛛母 / 朱厌 / 冰螭 / 玄鲲；地图 镜湖 / 落霞林 / 苍梧林海 / 朔北冰原 / 归墟；境界 炼气…真仙 → 飞升；转生 → 轮回。
     仓库名、Render 服务名、exe 名（DouluoHunter）没改（改了用户的下载链接和服务器地址会断）。
     **教训**：`server/test.js` 连接地址里的名字是 URL 编码的（`%E5%94%90%E4%B8%89`），按中文替换没换到，断言改了、发的没改，CI 第一步就挂了。改名以后还要搜 URL 编码 / `\u` 转义的旧名字，并在本机跑一次 `node test.js`
   - **世界观** `docs/世界观.md`：天倾、天枢五块碎片、五大灵主、栖霞村青崖子、九重天 / 轮回。接进游戏：`CHAPTERS` 的 intro / story / 任务文字、`BOSSES` 的 lore / shard（出场字幕 `Hud.boss_intro(name, lore)`、打死后"天枢碎片 N / 5"）、
     Boss 名字后面"第 N 重天"（轮回重数）、菜单副标题和「序章」按钮
   - **过场动画**全部重画（`tools/boat_anim/src`：`lib.tsx` 公用零件（云海、浮岛、星空、光点、字幕、胶片颗粒、暗角、遮幅）、`figures.tsx`（五个灵主、天门、青崖子、孩子、船）、`Prologue.tsx`（48 秒六幕 + 怎么玩）、`Clips.tsx`（渡海 / 飞升九重天 / 进秘境 / 进猎场 / 灵葫立绘））。
     渲染：`%TEMP%\ba`（短路径）里 `render_all.ps1`（Remotion → mp4 → ffmpeg libtheora `-q:v 6~7` → ogv）。`ui/voyage.gd` 通用播放器（video / length / title / captions / music，空格跳过）。
     第一次进游戏播序章（`stats.prologue`），进秘境 `Dungeon.enter`、去猎场 `Main._change_map`、飞升 `World._check_god` 都播。旧的 ending.ogv 不用了（网页上删不掉就留着）
   - 字体重新裁剪（`%TEMP%\fsub`：npm subset-font，GB2312 一级字 + 所有脚本里的字，从 NotoSansSC 可变字体按 500 / 700 / 900 粗细实例化，文件名不变）。**加了新字要重跑**，检查脚本 `check_glyphs2.gd`
   - 队友模型（`RemotePlayer`）程序重做：长衣三片下摆、腰带穗子、围巾、披风、发髻飘带、膝盖手肘两节、箭囊；走跑弯膝、摆衣、冲刺前倾、蹲。
     放 `assets/models/player/player.glb`（或 .gltf）就换成自定义模型（按高度缩到 1.85 米，动画按名字找 idle / walk|run / jump，`BeastModels.instance_custom`）。给用户的 Tripo / Meshy 提示词：
     "original Chinese xianxia monster hunter, young cultivator, layered long coat with split hem, cloth sash with tassel, short cape, leather bracers and boots, hair in topknot with ribbon, quiver on back, empty hands, A-pose, stylized realistic, game-ready ~20k tris, rigged humanoid with idle / walk / run animations, export GLB"
   - 自动测试新阶段：`bossarts`（五个灵主每招都放一遍 + 破绽 + 极限闪避）、`mateshot`（队友模型截图）、`cineshot`（过场动画在游戏里的样子截图）；这些要开窗口截图的别在用户玩的时候跑
21. 第十四版 · 名画过场（2026-09-28，在云端 Linux 会话里做的）：
   - 为什么：代码画的 SVG 色块再怎么调也像 PPT；用户给的参考片是**现成的高质量画面**（名画 / AI 插画）+ 纪录片式剪辑。这里没有 AI 画图，所以用公有领域名画
   - `tools/boat_anim`：`art.json`（每张画的画家、年份、收藏馆、许可、下载地址、要裁的画框）→ `python3 fetch_art.py` 下到 `public/art/`（长边 3200）+ 字体到 `public/fonts/`（思源宋体、EB Garamond、Courier Prime，OFL）+ 生成 `src/artdims.json`；`public/` 不进仓库
     - 下载的坑：维基**原图**接口和 API 都限流（429），用 3840 宽的缩略图（尺寸必须是维基规定的档位，2560 会 400），每张歇几秒；芝加哥艺术博物馆的图片服务器挡脚本（403），不用它；大都会、克利夫兰的开放接口直接能用（CC0）
   - `src/cine.tsx` 零件：`Film`（黑场 + 暗角 + 等字体加载）、`Shot`（名画镜头：`a` / `b` 两个机位 = 原画里的中心点 0~1 + 放大倍数，缓动推过去；调色 `grade`、粒子 `fx` = dust / embers / snow / mist、贴在画上的光 `glow`、震屏 `shake`；每个镜头底部和左上角自带压暗，亮画上字也清楚）、`Sub`（中文衬线 + 英文斜体字幕）、`Label`（左上细线标签）、`BigStat`（左上滚动大数字）、`Title`、`PaperCard`（纸片卡片，打字机标题）、`ShardFall`（五块天枢坠落）、`Flash`
   - `src/Films.tsx`：`Prologue`（48 秒）、`Voyage`（`Voyage1~5`，每章一段：月下出海 → 目的地名画 + "前往 · 第几章" + 这一章的故事，都画在视频里）、`DungeonGate`、`HuntGate`、`Ascend`；分镜注释写在文件里。旧的 SVG 分镜（Prologue / Clips / Voyage / Ending / figures）删了，灵葫立绘挪到 `Gourd.tsx`
   - 渲染：`./render_all.sh`（Linux：`apt-get install ffmpeg` 带 libtheora；Remotion 用 Playwright 预装的 `/opt/pw-browsers/chromium_headless_shell-*/…/headless_shell`；4 核约 15 分钟）。1920x1080 渲染 → 1600x900 + 轻微降噪 → Theora **按码率**编码（按质量编码铜版画 4 秒就 20 MB）：序章 2.6 Mbps、渡海 / 猎场 3.5、飞升 3、秘境 7（线条最密）
   - 游戏里：`Main._travel` 播 `voyage_<章>.ogv`（没有就退回旧的叠字方式）；`voyage.gd` 叠一层胶片颗粒着色器（颗粒画进视频体积翻几倍）；旧的 `voyage.ogv`、`ending.ogv` 删了
   - 调镜头：改 `Films.tsx` 里的机位 / 时间，`npx remotion still out/bundle Prologue out/x.jpg --frame=N --browser-executable=…` 单帧看（先 `npx remotion bundle src/index.ts --out-dir out/bundle`），比整段渲染快得多

22. Boss 放大 + 朱厌跃击（2026-09-28）：
   - `Data.BOSSES` 的 size：碧鳞蛟 12、蛛母 13、朱厌 24（高）、冰螭 22、玄鲲 30；受击盒按模型包围盒自动跟着变，弱点球上限 6 米；陆地 Boss 从 14 + 身高的高空砸下来出场
   - `Boss._gk`：招式范围按体型放大（朱厌的拳圈、冲锋宽度）；巨兽走路每一步震地（`_update_visual` 里按走的距离，`fx._shake` + thud）
   - 朱厌跃击 `Boss._leap / _leap_tick`（act type "leap"）：蹲 0.8 秒 → 跳上高空跟着人 → 1.9 秒锁定落点出红圈 → 3.2 秒砸下（`LEAP_DMG` 95 × 章节系数，第三章 55 级约掉一半血）+ 外圈冲击波（跳起来躲）→ 破绽 3 秒；二阶段 stomp2 连跳两次。第一次跳会提示怎么躲
   - 自动测试 bossarts：站位绕 Boss 一圈找陆地；**被打倒后要走 `w._respawn_at_dock()`**（只 `p.revive()` 的话倒地计时 `_carry_t` 还在走，几秒后会被自动送回码头，下一个 Boss 的测试就找不到人）
   - 国风过场：用户用 Dola AI 生成了 13 张图（提示词在会话里：九重天、天门、天倾、浮岛、苍墟、五灵主、青崖子、修行之道、天宫全景）。**聊天里干活途中发来的图不会存成文件**，要等我空闲时发、或者传到 GitHub `tools/boat_anim/ai/`。目前只收到第 1 张（`ai/01.webp`），`FilmsCN.tsx` 里有 8 秒试片 CNTest；`cine.tsx` 加了流云（`fx: 'clouds'`，`public/fx/clouds.png` 由 prep_ai.py 生成）、天光（`rays`）、竖排题字 `VTitle`、朱红印章 `Seal`
23. 剧情第一阶段（2026-09-28）：
   - 剧本 `docs/世界观.md` 重写：三万年前太初宗在天坛前**叩天**（天上收灵税、人间大旱），守门的天枢星君**云岫**把自己碎成五块关死天门；五灵主是替她守碎片、快撑不住的守门者（每个一种情绪：等 / 记 / 战 / 忘 / 归）；**青崖子就是当年的主将沈青崖**；结局二选一（重铸天枢 / 让她安息，都是好结局）；轮回 = 北斗九重（天枢篇、天璇篇……）
   - 文字都在 `scripts/world/story.gd`（`Story`）：`LORDS`（出场 / 半血 / 临死 / 天枢记忆三句 / 青崖子到岸和打完）、`lord_intro`（再叩天："又是你。"）、`heaven_name`（"第二重天 · 天璇"）、`RING_MEMORY`（23 种灵兽各一句）、`INSCRIPTIONS`（每章秘境三层刻字）、`STELES`（残碑，第三阶段用）
   - 游戏里：`Hud.say(who, text)`（底部那一列正上方的字幕，一句一句排队）、`Hud.memory(title, lines)`（天枢记忆文字版：压暗画面，三句浮出来，十几秒自己散）；`World._on_boss_spawn / _on_boss_phase2 / _lord_story`（第一次打倒：临死一句 → 8.5 秒后天枢记忆 → 青崖子一句，`Profile.stats["story_<kind>"]`）；第一次到岛青崖子说一句（`stats["sage_arrive_<章>"]`）；`finish_absorb` 灵环记忆；秘境结算面板残壁刻字
   - 新字要进字体：`岫玑璇阙髻` 是这次补的。**做法（Linux）**：从 google/fonts 下 NotoSansSC 可变字体，`fontTools.varLib.instancer` 按 500 / 700 / 900 实例化，`fontTools.subset` 收"原来的字 + 所有脚本里的汉字"，覆盖 `assets/fonts/NotoSansSC-*.otf`（里面是 glyf，名字还叫 otf），再 `--import`
   - 自动测试 boss 阶段：打倒灵主必须触发剧情（`story_<kind>` + 字幕队列）

24. 剧情二 + 一批试玩反馈（2026-09-28 晚）：
   - 青崖子 NPC（`world/sage.gd`，`Sage`）：程序拼的独眼老猎人（斗笠、白发白须、眼罩、蓑衣、长弓、猎叉），站在天坛边，走近按 F 说话（`Sage.lines_now`：到岸那句 + 主线提示 `Story.sage_hint` + 闲话 `Story.SAGE_IDLE`，打完灵主换一套；轮回过会多一句）
   - Boss：见上表（掉水、涂白、压迫感）。`Boss.SKIN_OF` 五个灵主的程序皮肤颜色
25. 音乐 + 游戏时长 + 枪的机械感：见上表
26. 试炼（`world/trial.gd`，`Trial`；僵尸群 `world/horde.gd`，`Horde`）：
   - 码头边试炼碑（地图「试」，`Trial._place_stele` 在猎灵榜旁边找空地）→ `Hud.open_trial_picker` 两张卡
   - 僵尸不用刚体灵兽，自己算：清朝跳尸（官帽、黄符、补子、双手平伸），一个 MultiMesh 画，程序网格 `Horde._build_mesh`（UV.x 记部件），一蹦一蹦（`HOP / STEP / REST`），2 米一格分桶推开，障碍物是圆（`obstacles`）。kind 0 小尸 / 1 跳尸 / 2 铁尸 / 3 尸王
   - 命中：开枪 `World.local_fire` → `Trial.shot`（射线和竖胶囊求最近距离，头部 ×爆头）；爆炸 `World._blast` → `Trial.blast`；拳头 `Player._melee` → `Trial.melee`；神通（房主）`SkillSystem._launch / _beam` → `Trial.host_area / host_beam`
   - 联机：房主出怪 hdsp、谁打中发 hdhit（每台电脑扣一样的血，自己那一下打死的算自己的）、每台电脑自己算咬没咬到自己、阵眼只有房主算；中途加入的人会收到场上已有的僵尸
   - 尸潮守关：场地 `SIEGE (-900, 420, 0)` 半径 36，四个尸门、阵眼 1000 血、内圈八段矮墙、四座箭楼、六个兵器架（`Player.trial_gun / trial_k`，品质 凡 / 灵 / 玄 / 天 = 伤害 ×1 / 1.35 / 1.8 / 2.5，出了试炼还回去）；每波 8+4n 只、每五波尸王（砸地红圈）；波间回阵眼 15%；记 `stats["siege_best_章"]`
   - 万兽割草：场地 `MUSOU (0, 420, -900)` 半径 62，场上保持 150 只（每多一人 +45，上限 340），三分钟；子弹多穿两只；斩 60 只攒满灵爆（Z，15 米全清）；百人斩 / 千人斩横幅；记 `stats["musou_best_章"]`
   - 倒下：还在打就在场地里复活（`Trial.on_respawn`，在 `_respawn_at_dock` 最后调）
   - 岛外的场地判断统一用 `World.away()`（秘境或试炼）
   - 自动测试 `siege`、`musou`（在全流程 dungeon 后面）
27. 暗器升星 + 装饰：
   - 升星（`Data.STAR_*`、`star_price / star_mult / star_floor / star_color`，`Profile.stars / star_bless / star_try`）：1~10 星，成功率 100% → 26%，每颗 +6% 伤害，3 / 6 / 9 星突破（王魄 1 / 2 / 3，灵光蓝 / 紫电 / 金身，额外伤害），突破过的不掉回去；4 星以上失败一半几率掉一颗（护星符 +60% 灵石就不掉），失败攒祝福 +5%。暗器铺「升星」页：星星闪一阵再揭晓（`ShopPanel._do_star`）；HUD 暗器名后面 ★N；3 星以上手里暗器飘光点（`ViewModel._star_aura`）。轮回保留星数
   - 装饰（`Data.DECOR / DECOR_ORDER`，`Profile.decor`，`world/decor.gd`，`Decor`）：暗器铺「装饰」页买 / 摆上 / 收起；联机时所有人摆上的都出现（hello 第 10 项、prog 第 7 项、peer_info["decor"]）。基础（人人都有）：船舷朱漆金边、船尾灯、铺子「暗器」幌子、营地兵器架和火把
   - 自动测试 `stars`、`decor`（第一章 pills 后面），截图 `decorshot`
28. 国风（用户："游戏整体，要把 UI 啊地图啊往国风去改"）：
   - 字体：标题 `NotoSerifSC-Black`、眉题 / 地图字 `NotoSerifSC-Bold`（思源宋体，从 google/fonts 可变字体按 900 / 700 实例化，裁成和黑体一样的字；**加新字时宋体也要重新裁**）；`Data.font_serif`
   - `UiKit`：颜色偏暖（墨、赭金、朱砂、青玉、月白），`seal()` 朱红印章（面板标题左边，取眉题第一个字），小标题前金色 ◆，全屏毛玻璃背后三层水墨远山 + 一轮淡朱日（`BLUR_SHADER`）
   - 大地图 / 小地图（`map_view.gd`）：宣纸底、按高度上墨、每 3 米等高线、海岸浓墨、水面淡青晕染和波纹、小路朱砂虚线、地点是方印、自己是朱红箭头
   - 岛上地标（`Decor._landmarks`）：最高的空地一座七层八角宝塔（檐角挂灯、金葫芦顶）、靠海一座六角红柱亭子、小路两边每 26 米一对石灯笼
   - 还没截图检查的：新字体下的各个面板（`uishots`）、宝塔和亭子在岛上的样子
29. 灵主出场镜头 + 自己的人物预览（`3cc35bf`）：
   - `world/boss_cine.gd`（`BossCine`，CanvasLayer）：每个灵主每一重天第一次出场（`stats["cine_<kind>_<tier>"]`）播 6.5 秒镜头：仰拍绕转、电影黑边、宋体名号 + 朱印、台词；空格 / Esc / 点击跳过；`World._on_boss_spawn` 调，自动测试 / 秘境里不播
   - `ui/self_preview.gd`（`SelfPreview`）：SubViewport 里一个 `RemotePlayer`，喂"原地站着"的假快照，拿着手里的暗器，慢慢转、可拖动；放在灵相面板立绘上
30. 尸潮追击（2026-09-29，交接前最后一轮；本机 `--plan=chase,musou,done` 全过，没截图、没测联机）：
   - 取代了尸潮守关（siege，小圆场地 + 阵眼）。`world/trial.gd` 重写：MODES 是 `chase` / `musou`（割草没改）
   - 场地：`CHASE (-900, 420, 0)` 往北（-z）一条长街，半宽 14，北头 z = -470；`Island.add_floor_rect`（新，长方形地面）让高度在这里也对
     - 两边铺面（飞檐、红灯笼、招牌）+ 暗巷口，整条街两面墙是碰撞；路上板车 / 货箱 / 碎石堆当掩体（`_chase_obst` 给僵尸绕）
     - 三道城门 `GATES = [-110, -220, -330]`（城墙 + 城楼 + 两扇大门，`_gate_nodes`，开门时禁用门的碰撞），每道门南边一个守点（绿色符阵 + 火盆，`zone_center(i)`），北头渡口 `ESCAPE_Z` 守到渡船划过来
   - 流程（房主算）：准备 10 秒 → run（边打边往北走，身后 + 前面巷子口出僵尸 `_host_chase_spawn / _spawn_point`）→ 有人走进守点 → hold（守 `HOLD = [30, 35, 40, 45]` 秒，守点里有活人才走时间；第二关和渡口来尸王，≥3 人两只）→ 开门（`_open_gate`：全员回四成血、发钱和修为）→ … → 渡口守满 = 逃出生天
   - 续命：全队 2 + 人数 次（`run["lives"]`），房主看谁新倒下扣一次（`_was_dead`），扣到负数失败；倒下在最近过的城门后站起来（`cp_spawn`，`on_respawn`）
   - 僵尸（`horde.gd`）：新增 kind 4 疾尸；只追人（`goal = INF`），除尸王都咬人（`BITE_K`），尸王隔 3 秒砸最近的人（`_host_kings` → `World.boss_telegraph`，消息 trslam）；挨打往后退（`apply_hits`）；`bounds`（Rect2）把僵尸限在"南头到下一道关着的门"之间（`_update_bounds`）；去掉了砸阵眼
   - 血量 `_unit_hp`：按全队最强暗器一发（跳尸 2.6 发、疾尸 1.8、铁尸 8、尸王 55 × 人数加成），越往后越厚
   - 伤害数字：追击里每一枪都飘（`Fx.damage_number(..., force=true)`）；割草只飘铁尸和爆头。血条：`Trial._draw_plates`（挨打 4 秒内 / 铁尸，40 米内），尸王在屏幕上方一条大血条
   - 兵器架：起点 3 个 + 每个守点 2 个，越往后品质越好（凡 / 灵 / 玄 / 天 = 伤害 ×1 / 1.35 / 1.8 / 2.5）；**配件** `Trial.roll_attach(id, q)`：凡品一个瞄具（狙击 / 射手优先高倍镜，其他优先红点 / 全息）、灵品 + 枪口、玄品 + 枪管下 + 弹匣、天品 + 枪托。
     捡起来：`Player.trial_gun / trial_k / trial_attach` + `ViewModel.attach_override`（模型按这套配件搭），`Profile.weapon_stats(id, on)` 第二个参数传这套配件；出了试炼还回去（`_drop_trial_gun`）
   - 消息：trst（[mode, phase, cp, hold, t, lives, kills]）/ trenter / trin / trleave / trrack（[[id, q, 配件]]）/ trgate / trhold / trlife / trslam / trburst / trend / hdsp / hdhit
   - 纪录：`stats["chase_best_<章>"]`（过了几道门，逃出去 = 4）、`stats["chase_time_<章>"]`；`Trial.best_text` 给试炼面板和结算用
   - 自动测试 `chase`（默认 plan 里代替了 siege）：兵器架配件 → 捡枪带配件 → **站着不动会被咬** → 开枪飘数字、血条 → 三道门守到渡口 → 结算 → 枪还回去 → 第二局续命用完失败
31. 第一个 AI 生成模型：跳尸（2026-09-29，`10ecbfd`，质感提升的试验，**成功**，截图用户看过）：
   - 用户用 Meshy 生成（A 字姿势、19.6 万面、12 MB）→ `tools/shrink_glb.gd` 减到 6112 面、贴图 1K（780 KB）→ `tools/pose_jiangshi.py`（numpy 直接改 GLB 顶点）：胳膊绕肩膀转到**向前平伸**（按沿胳膊的距离和离胳膊中轴的距离做平滑权重，衣服不撕）、转 180°（glTF 正面 +Z → 游戏 -Z）、脚底放 0、缩到 1.9 米
   - `Horde._load_model()` 读 `assets/models/horde/jiangshi.glb` 的网格和贴图，`SHADER_TEX`（颜色 / 法线 / ORM 贴图，`TEX_TINT` 按种类调色，下摆跳起来往后飘、伸直的手上下晃，轮廓淡绿尸气、尸王暗红，挨打红闪）；没文件就退回程序模型 `_build_mesh`；场上超过 140 只关影子
   - 截图阶段 `chaseshot`（近看一排僵尸、挨打血条、长街远景）
   - **这套流程可以复用**：AI 模型 → shrink_glb 减面 → 必要时 numpy 改姿势 / 朝向 → 预览图（xvfb + 一个 SubViewport 脚本，三个角度拼一张，约 1 分钟）→ 接进游戏 → 截图
   - 截图里还能看到的问题：起点兵器架的光柱太粗太亮挡视线（`99d8a02` 改细了）；第一人称"巧克力手"、街边房子是方块（32 改了）
32. 质感第一轮（2026-09-29，换账号后第一轮，小号在本机 Windows 做的；和 31 同时进行）：纯色方块 → 真 PBR 材质
   - `scripts/mat_lib.gd`（`MatLib`）：21 种 CC0 贴图（`tools/fetch_materials.py` 从 ambientCG 下，`assets/textures/mat`，约 31 MB）：瓦 roof、漆 lacquer（带清漆）、木 wood / hardwood / planks、金 gold、青铜 bronze、黄铜 brass、乌铁 iron、布 cloth / canvas、皮 leather、花岗岩 stone、石板路 cobble、青砖 brick、汉白玉 marble、白墙 plaster、麻绳 rope、竹 bamboo、茅草 thatch、灯笼纸 paper_lamp（透光发光）。
     全部三向投影不用 UV；world = true 按世界坐标（建筑），false 按模型坐标（船、暗器、手）。去色贴图（瓦、漆、布、皮、纸、墙）靠 tint 上色，传进去的就是想要的颜色
   - `world/props.gd`（`Props`）：`rbox` 倒角方块（边上接高光，暗器全部零件、牌坊、铺子、长街都换了）、`lathe` 旋转体、`lantern` 中式灯笼（竹骨纸灯身 + 漆木盖 + 金穗）
   - `WorldBuilder._wood / _stone / _cloth` 改走 MatLib（以前木头是**树皮贴图**、石头和瓦是悬崖岩石），新增 `_tiles(c)` 青瓦；`_surface("rock", …)` 当瓦的地方都换了
   - 暗器：`GunSkin` 着色器加真实细节层（`DETAIL`：木件紫檀木纹、漆件漆面、黑件皮革、包边青铜 / 金 / 乌铁；只取明暗 + 法线 + 粗糙度，颜色还是皮肤的，花纹皮肤细节减半）
   - 手：`WeaponModels.fist / sleeve` 重做——半指皮手套、手指三节绕握把弯、露出的指节是皮肤（`_skin_mat` 次表面散射）、皮护腕 + 两道青铜箍、布料袖子
   - 装饰 / 铺子 / 牌坊（斗拱、青绿彩画、鸱吻、柱础、金箍）/ 宝塔（白墙）/ 亭子 / 收购箱（铜包角）/ 长街（白墙木框铺面、木格窗、石板路、青砖城墙、九路门钉朱红城门）都换了材质；长街小零件 70 米外不画
   - 3D 模型提示词一次列全在 `docs/3D模型提示词.md`（混元 3D Studio 用的中文提示词：朱厌、玩家人物（也当第一人称的手）、三把暗器、青崖子、乌篷船、石狮子），用户生成后放 `tools/incoming_models/`
   - 两个账号同时改了代码：两边都写了 `chaseshot`，合并时留了 31 那个（摆一排僵尸近看，更全）
   - **截图要把窗口放到屏幕外**：`--position 2500,0`（用户只有一块 1920×1080 屏幕，窗口弹在桌面上会打扰用户，用户点到窗口（比如开了暂停菜单）自动测试会停住，看起来像卡死）。别用 `--always-on-top`。用 `Start-Process … -PassThru` + `WaitForExit(毫秒)`，超时就 Kill
33. 朱厌：混元 3D 生成 + 混元 3D Studio 绑骨骼 + 8 段动作（2026-09-29，大号，和 32 同时进行）：
   - 用户的流程：混元国际版（3d.hunyuanglobal.com）图生 3D（面数选 50k）→ **3D Studio** 里骨骼绑定 + 动作模板 → **每个动作单独导出一个 FBX**（每个都带整个模型，约 53 MB，文件名和动作名都是乱码）→ 聊天附件放不下，**传到 GitHub Release 草稿**（我用 `curl https://api.github.com/repos/…/releases` 能列出草稿、按 asset id 带 `Accept: application/octet-stream` 下载）
   - 骨架是 Mixamo 命名的 28 根人形骨头（Hips / Spine / LeftArm …，没有尾巴骨）
   - `tools/fbx_to_glb.gd`：`-- 输出.glb 贴图边长 名字=文件.fbx …`（第一个当底，其他只取动作；`名字@90=` 整段动作绕竖轴转 90°）。做三件事：动作合进一个库、**尾巴改绑到 Hips**（人形骨架没尾巴骨，尾巴被绑到腿上一动就拉成长条；在身后、胯以下、离腿远的点做种子沿三角形长，按贴图颜色排除红色的手脚）、贴图缩 2K（50 MB → 5.8 MB）
   - 认动作：`animsheet.gd` 类的脚本（xvfb + SubViewport）每个文件抽 7 帧拼成一张总表看。这次 8 段：idle 2.0 秒、walk 1.22、run 0.53、attack 抡臂过头砸下 2.67、attack2 快拳 0.75（**整段是侧着的，转了 90°**）、jump 双臂上举 → 起跳 → 双拳砸地 3.7、roar 张臂咆哮 4.15、death 仰头吼 → 倒地 4.15
   - 接进游戏：`BeastModels.ROLE_KEYS` 加 walk / attack2 / attack3 / roar / jump；`_animate_model` 慢的时候走、快了跑（`walk_max` = 身高 × 0.5），巨兽动作按体型放慢（`gait_len` = 身高 × 0.35）；`play_role("attack")` 在 attack / attack2 / attack3 里随机；跃击一开始放 jump（×0.7 速，落地对上砸下来）；`Boss.roar_anim()` 出场镜头（`BossCine`）和暴怒（`World._on_boss_phase2`）时咆哮；只有死亡动作时不会被当成待机循环；没骨骼 / 没走跑动作的 Boss 用程序步态（`_static_model`：一步一沉、左右晃、前倾、喘气）
   - 自动测试：第三章 boss、bossarts（朱厌 8 招）全过；**还没在游戏里截图看动作**
   - 以后别的灵主照这个流程：混元生成 → Studio 绑骨骼（只支持人形；蛛母 / 蛟 / 鲲不是人形，要另想：程序化腿、身体波浪摆）

34. 混元模型第一批接进游戏（2026-09-29，小号；用户把模型放在 GitHub Release **草稿**里，`gh api` 按 asset id 下载到 `tools/_downloads/hunyuan`，不进仓库）：
   - 流程：`tools/preview_model.gd`（三个角度拼一张图，看朝向 / 大小 / 面数 / 骨头）→ 静态的用 `tools/shrink_glb.gd` 减到约 1.25 万面 → 带骨骼的用 `tools/fbx_to_glb.gd -- --notail …`（人形**要加 --notail**，不然长衫后摆被当尾巴绑到胯上，跑起来脚边拉出长条）
   - 队友 `assets/models/player/player.glb`（六段动作 idle / walk / run / sprint / jump / crouch）：`RemotePlayer` 按速度、冲刺、蹲、空中选动作；`player/aim_ik.gd`（`AimIK`，SkeletonModifier3D）两节 IK 让两只手端着暗器、枪口跟着 pitch；暗器挂在 `_gun_root`（每帧摆到右手目标点）
   - 暗器 `assets/models/weapons/<id>.glb`（zhuge / kongque / xiujian）：`WeaponModels.MODEL_FIT`（yaw：流光翎枪口朝 +Z 要转 180°；k：长度倍数），`_swap_model` 藏掉代码枪身（蒙皮材质 + 玉 / 翎羽 / 弦），模型按原范围摆；手、配件、Muzzle / Sight / Mag 挂点照旧；`build_small` 也用模型。
     皮肤：`GunSkin.model_material`（着色器 `d_uv = 1`）：按模型 UV 取明暗 + 法线 + ORM，金属（ORM.b）保留原色，其他换皮肤颜色 / 花纹；默认皮肤用原材质。流光翎模型自带瞄准镜
   - 乌篷船 `props/boat.glb`（`WorldBuilder._boat`，meta "model"：Decor 不加船舷灯，锦帆桅杆挪到船头）、石狮子 `props/stone_lion.glb`（`Decor._d_lions`，**别用负缩放镜像**：法线贴图光照会反）、青崖子 `npc/sage.glb`（老将军，待机动作；`Sage` 整个人慢慢侧身看玩家）
   - `Props.place_model(parent, path, size, fit, base, yaw)`：按长 / 高缩放、底面贴地
   - **截图 / 自动测试的启动方式改成** `Start-Process … -WindowStyle Hidden` + Godot 的 `--log-file 文件`（不重定向 stdout）：窗口不出现在用户桌面上；以前重定向 stdout + 屏幕外窗口有两次渲染卡住（用户看到"无响应"窗口）

35. 镜湖场景样板（2026-09-29，大号；`26bb9c4` → `199f5cc`，第四版截图还没看）：用户说"地面、树这些质感不行"，先拿第一章做样板
   - 树（`world_builder.gd`）：中式树种 `_hs_pine`（黄山松：S 形干、细枝、枝头一团团松针，`_pine_pad` 是压扁椭球里十几张斜贴片）、`_bamboo`（竹丛）、`_willow`（垂柳，垂下的柳条贴片）、红枫、桃花；`_tree_kinds` / `_tree_kind_at` 按高度、坡度、噪声决定种什么（水边柳、成片竹林、陡坡和高处黄山松）。
     叶片贴图 `tools/make_cn_foliage.py` 用 ambientCG 真树叶照片拼（竹叶、柳条、桃花、红枫、松针团、荷叶、竹竿）
   - 海上峰林 `_karst_peaks` / `_karst_mesh`（15 座，竖向凹槽、水痕、台阶、苔绿，峰顶种黄山松，码头方向留空）；远山 `_mountains` 镜湖用四道分开的山脊（`ridges`，远的一层比一层淡），不再是一片尖三角锥
   - 光和雾（`ENV.island`）：上午斜阳、偏暖，低处一层薄雾（`fog_h / fog_hd`），高画质开体积雾
   - 地面：草 11 万丛、按噪声变色变疏密；地面草色和草丛对齐（草丛着色器加了 `tint`）；土偏褐；陡坡上石头；荷塘 `_lotus`
   - 宝塔 `Decor._pagoda` 重做成木构（`_story / _pingzuo / _dougong`，曲面飞檐 `_roof_mesh` + 垂脊 `_roof_ridges`，小零件按材质合并 `_acc_add / _acc_flush`）；亭子换曲面攒尖顶；路牌 `_sign` 改成宋体竖写的木牌
   - 修：秘境 / 试炼场地在 900 米外 420 米高的空中，从岛上看是天上一个灰色椭圆 → 镜头不在 560 米内就藏起来（`WorldBuilder._hide_far_arenas`）
   - 截图阶段 `sceneshot`（码头、草原、山坡近看宝塔，藏 HUD 和手）；对比图用 `before/` 目录的旧截图

## 还没做 / 可以继续

- 国风 CG、模型质感、蛛母 / 玄鲲新模型：见文末"交接"
- 剧情三：残碑 + 《苍墟志》、天坛结局二选一（重铸 / 安息）、北斗九重轮回篇名
- 突围模式、近战模式（用户提过，还没做）
- 数值是按公式估的（见 data.gd 注释），没有真人从 1 级玩到 100 级；等用户反馈再调 `CH_HP / CH_MONEY / KILLS_PER_LEVEL`
- 第十三版的灵主招式只由自动测试放过一遍，没有真人打过：等用户说哪招太难躲 / 太简单再调（`Boss._art_*` 里的前摇秒数、半径、伤害）
- 本机全流程超过 10 分钟，工具会在 10 分钟时把后台进程一起杀掉：分两段跑（`--plan` 前半段 + `--chapter=5 --plan=huntrun,huntfail,done`）
## 手机版（安卓，2026-09-28）

- **同一套代码**，不是分支：`Settings.touch_active()`（`touch` = -1 自动 / 0 关 / 1 开；手机上自动开；电脑上加 `-- --touch` 参数测试）。
- 触屏层 `ui/touch_controls.gd`（`TouchControls`，world 里创建，layer 50）：左半屏浮动摇杆（推出圈外往前 = 冲刺），右半屏滑动转视角（`Player.touch_look`），右下一圈按钮、左上暂停 + 菜单、物品栏 / 小地图 / 大地图直接点 HUD 上的格子（`Hud.hotbar_rect / minimap_rect / bigmap_rect`）。
  - 按钮用 `Input.action_press/release` 直接改动作状态（在 `_input` 里、手指按下那一刻），同一帧物理和逻辑都能看到 `is_action_just_pressed`。**别改成在 `_process` 里 `parse_input_event`**：玩家脚本先跑就错过"刚按下"，半自动枪、跳都会失灵（踩过这个坑）。
  - `pause / wuhun_panel / achievements / hunt_board` 是 `_unhandled_input` 里看事件的，用 `Input.parse_input_event.call_deferred(InputEventAction)`。
  - 触屏时去掉鼠标按键绑定（`Settings._strip_mouse_bindings`），因为第一根手指会被模拟成鼠标左键。
  - 辅助瞄准 `Player._aim_assist`（开火 / 开镜 / 转视角时，准星 7° 内看得见的灵兽或 Boss 弱点轻轻吸过去，设置可关）。
- HUD 触屏布局 `Hud.touch_layout(on)`：弹药画在开火键里、物品栏挪到下中（神通格子隐藏，神通在按钮上）、左上让出暂停键、小地图缩小、金币挪到小地图左边、击杀消息挪左边、成就卡改到上方正中、大地图按屏幕高度缩放。提示文字里的键名用 `UiKit.keys()` 换成触屏说法。
- 界面缩放：玩的时候 `root.content_scale_factor = Settings.hud_ui_scale()`（按屏幕英寸算，手机约 1.4~1.6），**打开面板 / 暂停 / 主菜单时恢复 1**（面板按 900 高设计，放大会超出屏幕）。刘海屏用 `DisplayServer.get_display_safe_area()` 左右让位（`Hud.set_safe_insets`）。
- 手机画质：默认低画质、`render_scale` 0.75（3D 分辨率）、草 ×0.6、阴影距离 ×0.7、关 MSAA、阴影图 1024；Mobile 渲染器没有 SSAO / SSIL / 体积雾，`world_builder` 里只在 Forward+ 开。
- 项目设置：横屏（sensor landscape）、`quit_on_go_back=false`（返回键 = Esc，`main._notification`）、`import_etc2_astc=true`（纹理多导一份手机格式）。
- 导出：`export_presets.cfg` 的 "Android"（只打 arm64，包名 `com.aluchen.cangxu`，minSdk 24，联网权限），签名密钥 `tools/android/release.keystore`（别名 cangxu，密码 cangxu-friends，写在 CI 里）。**密钥别换**：换了以后手机上不能覆盖安装，要卸载重装、存档会丢。CI 用 GitHub 机器自带的 Android SDK + JDK 17，`version/code` 用运行编号。APK 约 230 MB（5 张 HDR 天空各 8 MB 是大头，以后可以压）。
- 本机导出安卓：SDK 在 `~/android-sdk`（cmdline-tools + build-tools 35 + platform-tools），导出模板要有 `android_release.apk`；编辑器设置 `export/android/android_sdk_path`；环境变量 `GODOT_ANDROID_KEYSTORE_RELEASE_PATH/USER/PASSWORD`。
- 自动测试 `touch` 阶段：模拟手指（`InputEventScreenTouch/Drag`）测摇杆 + 冲刺、滑屏、开火、引魂索蓄力甩出、菜单 → 灵相 → 返回。截图：`xvfb-run ... --rendering-method mobile --resolution 1280x576 -- --autotest=shots --plan=touch,done --out=...`（20:9 手机比例 + 手机渲染器）。
- 没有真机测过：性能、手感、按钮位置都要等用户和朋友试了反馈再调（`TouchControls._define_buttons` 里的位置和半径、`touch_look` 的 0.11°/像素、辅助瞄准强度）。

## Mac 版（2026-09-28）

- 导出预设 "macOS"（`export_presets.cfg` 的 preset.3）：通用二进制（Intel + M 芯片），包名 `com.aluchen.cangxu`，`codesign/codesign=1` = 引擎自带的 **ad-hoc 签名**（Linux 上就能签；M 芯片的 Mac 必须有签名才能跑），**没有苹果公证**（要 99 美元/年开发者账号）。
  所以朋友第一次打开要到"系统设置 → 隐私与安全性 → 仍要打开"，或者终端 `xattr -cr 苍墟·猎灵.app`（说明在 `docs/Mac第一次打开.txt`，CI 塞进 zip 里）。
- CI 在 Linux 机器上导出：模板 `macos.zip` 从官方 tpz 里解出来（缓存键 `…-win-linux-android-mac`），导出 zip 后追加说明文件，发布成 `CangxuHunter-Mac.zip`（约 215 MB，里面是 `苍墟·猎灵.app`）。本机只取 macos.zip 模板的办法：HTTP Range 分段读 tpz 的中央目录（会话里写过 `rz.py`）。
- 通用二进制要求同时有 S3TC/BPTC 和 ETC2/ASTC 贴图（`import_etc2_astc=true` 已开）。Mac 上默认用 Metal（M 芯片）/ MoltenVK（Intel），Forward+。
- Mac 专门处理（`settings.gd`）：
  - 第一次启动默认中画质、3D 渲染比例按屏幕像素算到约 230 万像素（`mac_render_scale`，Retina 笔记本约 0.65），电脑上降分辨率用 FSR 放大；
  - 窗口比屏幕大时缩到可用区域九成（`_fit_window`，13 寸 MacBook 放不下 1600×900）；
  - **Godot 在 Mac 上把"按住 Ctrl + 左键"当成右键**，蹲原来只有 Ctrl（蹲着开枪会变开镜），现在 C 也是蹲（`crouch: [KEY_CTRL, KEY_C]`）；画板撤销 Cmd+Z 也行。
- 没有真 Mac 测过：性能、全屏、触控板、Metal 下的画面都等朋友反馈。

## 技术概要

- Godot **4.7.2**，GDScript，Forward+，Jolt 物理。项目在 `game/`。
- 数据全在 `game/scripts/autoload/data.gd`：暗器、灵兽（BEASTS）、年份（AGES、AGE_WEIGHTS）、神通（SKILLS、SKILL_TREE，9 灵相 × 5 环 × 2 选 1）、Boss（BOSSES）、章节和任务（CHAPTERS）、奖励倍率（KILL_BONUS）、`xp_to_next`。
- 存档 `profile.gd`（等级、灵环、暗器、道具、灵骨、章节进度）；设置和按键 `settings.gd`。
- 地图：`island.gd`（MAPS：island / forest / deepforest / snow / sea 的地形、栖息地、水域深度）+ `world_builder.gd`（ENV 每个地图的天空光照雾，树草石头等）。
- 一局游戏的逻辑和联机同步：`world.gd`（房主算灵兽、Boss、任务，广播给客人）。灵兽 `beasts/beast.gd`（房主是刚体，客人是插值代理），模型和动画 `beast_models.gd`，Boss `boss.gd`（ai = water / land / air）。
- 界面：`ui/ui_kit.gd`（样式库和全局主题，新界面先用这里的零件）、`hud.gd`（HUD、神通二选一、暂停、成就、渡船）、`menu.gd`、`shop_panel.gd`、`wuhun_panel.gd`、`settings_panel.gd`、`map_view.gd`。
- 中继服务器：`server/server.js`（Node + ws），`render.yaml` 一键部署。

## 测试和截图

```bash
cd game
godot --headless --path . --import                       # 加了新素材后
godot --headless --path . --check-only --quit            # 语法检查（最快）
godot --headless --path . -- --autotest=solo             # 五章全流程（本机约 10 分钟）
godot --headless --path . -- --autotest=solo --chapter=4 "--plan=hunt:icelake+icefield,boss,done"   # 只测一段
godot --headless --path . -- --autotest=solo "--plan=phys,done"      # 只测灵兽物理
# 截图（xvfb + lavapipe 软件渲染，很慢，一张 1–2 分钟）
xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver vulkan --resolution 1280x720 -- --autotest=shots --plan=hudshot,done --out=/某个目录
# 联机：先起服务器，再开房主和客人（见 README）
```

- autotest 阶段：`phys`、`hunt:<栖息地,...>`、`shop`、`recoil`、`sniper`、`ring`、`boss`、`boat`、`tour`、`hudshot`、`uishots`（全部界面截图）、`kings`、`aggro`、`huntrun`、`huntfail`、`dungeon`、`dgshot`、`guns2`、`gunshots`、`pills`、`bossarts`、`mateshot`、`cineshot`、`bot`、`done`；模式 `solo / shots / host / client / zoo / measure / vm`（host / client 加 `--dg=1` 测猎灵和秘境联机）。
- `huntrun` 会改等级和灵环，放在 `--plan` 最后面，别和 `ring` 这种要新存档的阶段连着跑。
- 改了中文文字（新字）后要重跑 `tools/subset_fonts.py <原始 otf 目录>`，不然新字会显示成方框。原始字体在 notofonts/noto-cjk 的 raw.githubusercontent.com 上。

## 素材和工具

- `tools/fetch_assets.py`（Poly Haven / ambientCG）、`prepare_assets.py`（树叶草叶贴片）、`set_texture_imports.py`、`fetch_models.py` + `gdrive.py`（Quaternius 模型在公开 Google Drive）、`fetch_icons.py`（game-icons.net）、`subset_fonts.py`、`gen_sfx.py`（合成全部音效）。
- 许可：Poly Haven / ambientCG / Quaternius 是 CC0；字体 SIL OFL；game-icons.net 是 **CC BY 3.0，要署名**（README 里已写）。
- FBX 模型朝 +Z，要转 180°；模型真实尺寸在 `assets/models/creatures/measure.json`（`--autotest=measure` 生成）。

## 还可以做的（用户没明确要求，按优先级）

1. 界面第七版已重做；还可以做：神通 / 道具的专属图标（现在按类型共用 game-icons 剪影）、手柄支持、界面动画（面板滑入）。
2. 第五章归墟的画面还没截图检查过；第三章苍梧林海的光照偏白天。
3. 右下暗器名"袖箭 · 手枪 · 半自动"文字偏长，可以简化成图标 + 名字。
4. 游戏时长（约 4 小时以上）是按经验曲线估算的，没有真人跑过；等用户和朋友玩完问反馈再调数值。

## 交接（2026-09-29，用户换另一个 Claude 账号继续）

上一个账号 token 用完了。**接手的先读完这一节，按顺序做**。用户原话在反馈表最后几行。

### 1. 最优先：全面提升模型质感（用户"无法接受目前这种低质感游戏"）

**进度（2026-09-29）**：第一轮做完（版本历史 31）：材质库 + 倒角 + 手 + 暗器细节 + 建筑 / 码头 / 长街。还差：
等用户用混元生成 `docs/3D模型提示词.md` 里的模型（朱厌、人物 / 手、暗器、青崖子、船、石狮子）再接进游戏（跳尸已换，`10ecbfd`）；队友 `RemotePlayer` 和青崖子 `Sage` 的程序模型还没换材质；
兵器架、祭坛、秘境、猎场营地还是 U.mat 纯色（`grep "U.mat(" game/scripts` 能找到剩下的）

用户点名的：
- **第一人称的手**（`player/viewmodel.gd` 里拼的手臂 / 手掌）——"巧克力手"：方块圆柱拼的、颜色像巧克力。要换成像样的手 + 袖子（修仙风：长袖、护腕、布料褶皱），手指分开有关节，皮肤材质
- **僵尸**（`world/horde.gd` 的 `_build_mesh`，程序网格拼的清朝跳尸）
- **桥**（岛上的桥 / 码头，`world/world_builder.gd`，几个方块）
- **枪 / 暗器**（`player/weapon_models.gd`，每把都是方块圆柱拼的；配件、瞄具也是）
- 以及"很多东西"：船、帐篷、铺子、祭坛、宝塔 / 亭子 / 装饰（`world/decor.gd`）、追击长街的房子和城门（`world/trial.gd`）、队友（`RemotePlayer`）、青崖子（`world/sage.gd`）

用户接受：**安装包变大没关系**。别找用户要素材（"不要找用户要模型 / 贴图"），但他们自己在用 Meshy / Tripo 生成模型，可以写提示词请他们生成（蛛母 / 玄鲲就是这样来的）。

建议做法（按收益排）：
1. 先截图看现状（`--autotest=shots`：`hudshot` / `gunshots` / `mateshot` / `decorshot`；xvfb + lavapipe 很慢，一张 1~15 分钟），列一张"丑模型清单"给用户确认先后
2. 能下到 CC0 高质量素材的先下：Poly Haven 模型（木桥、中式 / 木质道具、石头）、Quaternius（已有 `tools/fetch_models.py`）、Kenney；**ambientCG / Poly Haven 的 PBR 贴图**（木头、石头、瓦、布料、铜、铁）——现在很多零件是纯色材质，换成 PBR 贴图 + 法线质感就能上一大截
3. 手和暗器：CC0 的第一人称手臂很少，可以写 Meshy / Tripo 提示词请用户生成（例："first-person arms with long flowing sleeves and leather bracers, xianxia style, rigged, game-ready"；"ornate Chinese mechanical crossbow, bronze and dark lacquered wood, game-ready"），放 `assets/models/weapons/<id>.glb`，`WeaponModels.build` 有文件就用文件（仿 Boss 的 `custom_boss_path`），没有就退回程序模型；配件挂点要对上
4. 僵尸：MultiMesh 需要一个网格——可以用生成的清朝僵尸 GLB 取网格塞进 MultiMesh（动画靠顶点着色器摆，现在就是 UV.x 记部件的做法）
5. 每做一类就截图发用户对比

### 2. 国风修仙 CG（替换现在所有西洋名画过场）

- 用户用 Dola AI 生成的图在 `tools/boat_anim/ai/`（上传时叫"国风仙侠CG (N).png"，我按剧情顺序改成了数字名，`prep_ai.py` 只认数字名）：
  - `01.webp` 第一张（九重天 / 天宫，`FilmsCN.tsx` 的 8 秒试片 CNTest 用的它）
  - `02.png` 叩天之战：天坛前千军万马，天门大开、飞剑雷火
  - `03.png` 云岫：白衣金冠的星君在天门前张开双臂、火焰飘带（碎身关门那一刻），前景是沈青崖的背影和将士
  - `04.png` 云海上的天门，五道金光（五块天枢碎片）坠向人间
  - `05.png` 青崖子：独眼白发老人坐在废墟天坛前，香烛、夕阳，水墨味
  - `06.png` 碧鳞蛟：月下湖面盘着的青龙
  - `07.png` 千目蛛母：红叶林里紫光蛛网、网上挂着幽魂女子
  - `08.png` 朱厌：白毛赤手火猿蹲在山巅，背后火焰
  - `09.png` 冰螭：冰原白龙，冰窟里躺着一位金甲将军，旁边两个人影
  - `10.png` 玄鲲：巨浪里紫光鳞甲的巨鲸
- 每张 2848×1600，右下角"Dola AI"水印：`python3 prep_ai.py`（`CUT_BOTTOM = 0.11` 已经设好）裁掉底部一条 → `public/art/aiNN.jpg` + 尺寸表
- **聊天里贴的图不会存成文件**；用户会传到 GitHub 这个文件夹（网页上传单个文件别超过 25 MB）
- 要做的片子（Remotion，照 `tools/boat_anim/src/FilmsCN.tsx`：`cine.tsx` 的 `Shot` 推镜 + 流云 `clouds` + 天光 `rays` + 竖排题字 `VTitle` + 朱印 `Seal` + 衬线字幕）：
  - **序章**：02 叩天 → 03 云岫碎身 → 04 天枢坠落 → 01 天宫 → 05 青崖子（剧本 `docs/世界观.md`、台词 `scripts/world/story.gd`）
  - **五个灵主各一段**：06~10，接在 `BossCine`（游戏内出场镜头）前面，或者打倒后的天枢记忆（`Hud.memory`）
  - 渡海 / 秘境 / 猎场 / 飞升：没有专门的图，先用这些图的局部（04 天门当飞升、01 天宫当九重天），或者写新提示词请用户生成（风格：国风仙侠、电影感、云海金光、写实 CG、16:9）
  - **渲染好以后把西洋名画版全部换掉**（`assets/cutscene/*.ogv`：`Main._travel` / `Dungeon.enter` / `Main._change_map` / `World._check_god` 播的那些）。渲染见版本历史 21（`render_all.sh`，1920×1080 → 1600×900 Theora 按码率）

### 3. 蛛母 / 玄鲲新模型

- `tools/incoming_models/spider_meshy.glb`（Meshy "Widow of the Violet Veil"）、`whale_meshy.glb`（Meshy "Abyssal Bonemaw"），都**带贴图**，各 12 MB
- 做法：`tools/shrink_glb.gd` 减面 + 贴图缩到 1K（压到约 3 MB）→ 覆盖 `game/assets/models/bosses/spider.glb`、`whale.glb`（现在这两个没贴图，靠 `Boss.SKIN_SHADER`）→ `--import` → 截图看朝向 / 大小（`BeastModels.instance_custom` 按包围盒自动缩放；有贴图的不叠流光层）→ Meshy 模型多半没骨骼动画，确认 Boss 整体移动 / 摆动正常
- 换好以后删掉 `tools/incoming_models/`

### 4. 尸潮追击收尾

- 见版本历史 30。交接前本机 `--autotest=solo "--plan=chase,musou,done"` 全过；推送后先看 CI 全流程（里面有 chase）绿没绿，红了就不会发新版本，要先修
- 长街截图：`chaseshot`（已有）；房子和城门的材质第一轮已换（版本历史 31）
- 联机没测过（host / client 的 `--dg=1` 里没加追击）

### 5. 其他

- 剧情三（残碑、《苍墟志》、结局二选一、北斗九重篇名）、突围 / 近战模式：见"还没做"

### 6. 素材从哪来（2026-09-29 和用户聊定的，**用户说"先放一下，帮我记住"，等用户开口再做**）

- 用户的参照是 **CS、LoL、PUBG**（和朋友平时玩的），所以对低质模型特别生气。目标不是 CS2 画面，而是"统一、干净、不露怯"：风格统一比精度重要，光照 + PBR 材质能救很多
- 用户看了西方商店（Fab / CGTrader / RenderHub）的中国风素材：**除了 Fab 的 Modular Chinese mountain town，其他都偏劣质，而且贵**。用户愿意花钱，但要先给他看"买什么、长什么样"
- 定下来的方向：**用国内 AI 工具，基本不花钱**
  - 模型：豆包 / 即梦 / Dola 出国风概念图 → **腾讯混元 3D Studio**（用户已注册；每天免费点数、中文提示词；图生 3D 带贴图；**部件拆分**：暗器弹匣 / 机括、蛛母的腿能拆开单独动；**骨骼绑定支持人形和非人形** + 预设动作模板）转成模型 → 我们接进游戏。用户嫌 Meshy 是国外价格，**以后首选混元**；Tripo（北京 VAST）/ Rodin（上海影眸，贴图最好，30 美元 / 月起）是备选；人形绑骨骼 + 动作也可以用免费的 Mixamo
  - 动作怎么来：跳尸整个身子僵着蹦，**静态模型就够**；暗器的后坐 / 掏枪是代码动整把枪，零件（弹匣、拉栓、弩臂）要拆开生成或用混元部件拆分；第一人称的手 = 生成一个完整人形 + 自动绑骨骼，只显示胳膊，握枪用代码 IK；Boss：朱厌（人形）用骨骼绑定 + 动作模板，蛟 / 螭 / 玄鲲（长条身子）用代码让身体沿长度波浪摆（不用骨骼），蛛母用程序化腿（腿单独生成、代码让八条腿找地面交替迈）
  - 试验顺序（2026-09-29 定的）：跳尸（验证能接进游戏）→ 朱厌（验证绑骨骼 + 动作）→ 玄鲲（验证代码摆动）→ 手和暗器（工作量最大）
  - 国内素材站（爱给网、CG模型网等）国风模型和**音效**多、便宜或免费，要看清"可商用 / 仅个人"
  - **别用从游戏里扒的模型**（剑网3、天涯明月刀之类，很多廉价短剧就是这么来的，是盗版）
  - AI 修仙短剧大多是 AI 视频模型（即梦、可灵）直接生成的画面，不是 3D 模型，没有"共用模型"可以拿
- **国风 CG 的新做法**：把 `tools/boat_anim/ai/` 那 10 张图丢进即梦 / 可灵做"图生视频"（云动、龙游、飘带飞），比 Remotion 推镜头强得多；我们负责剪辑、字幕、配乐、接进游戏
- 分工：**用户用国内 AI 工具出图、出模型、出视频片段；我们写提示词（一次列全）、接进游戏、剪辑**
- 买来的 / 生成的原始素材文件：付费素材**不能放进公开仓库**（等于再分发），打包进游戏可以；要另想私有存放的办法

### 7. 可玩性路线（2026-09-29 和用户聊定的，质感那一轮做完就按这个走）

我对现状的判断（用户认同）：**系统很多，每个都浅，没有一个打磨到上瘾**。CS 只做"拆包 / 守包"一件事做到极致；我们的"那一件事"是**组队猎灵兽王**，现在它只是十几个玩法之一。打怪反馈不够（不会踉跄、不会断角）、队友没有分工、没有真人从头玩到尾过。

**硬规矩：用户和朋友大概一半单人、一半多人 → 单人必须完整好玩，多人是锦上添花；不能做成"没有奶就打不过"。** 参考怪物猎人：核心是"人对怪"，不是队伍配置。

按顺序做，**每一步做成能玩的版本 → 用户和朋友玩一晚 → 问三个问题：哪一刻最爽 / 哪里无聊 / 哪里看不懂**：

1. **样板狩猎**：先挑**一只**王（比如第一章猎场的猎物），只改它，做到 15 分钟都紧张，再复制到别的王
   - 部位破坏：2~3 个能打断的部位（角 / 尾 / 翅 / 背甲），集中打会断（模型上真的掉下来、王摔一跤）；断尾就没有甩尾招、断翅就飞不起来；每个部位掉专属材料 →"打哪里"变成决策
   - 硬直倒地：打头攒晕值，满了倒地 5 秒露弱点，全队集火（整场最爽的时刻，打得好和打得烂的区别）
   - 怒气 / 疲劳：暴怒更快更狠 → 怒完喘气、变慢，是捆 / 活捉的窗口（一张一弛）
   - 最后一击：濒死逃回巢穴 → 捆住活捉还是打死，奖励不同（已有一部分，打磨）
   - 这只王顺便用新的高质量模型（第 6 条的素材方案），"画面 + 玩法"一起做出样子
2. **灵宠**（怪物猎人的"猫"）：单人时带一只，帮忙吸引注意、偶尔捆一下、倒下拉你起来；人越多越弱（四人时只跟着跑）。**活捉的灵兽王可以驯化成灵宠**，每只王的灵宠能力不同（蛛母吐丝定身、朱厌帮你挡一下）→ 活捉有动机、多一条收集线
3. **软分工**：灵相决定**擅长**什么，不是**只能**干什么——人人都能捆、能救人、能打弱点；控类捆得更久、守类护盾更大、破类打部位更痛。王的一些招设计成"配合更轻松"（大招可以躲进守类的护盾；被捆住时弱点露出来），但一个人也打得过
4. **装备循环**：每只王的材料做专属暗器 / 护具（蛛母的毒针、朱厌的火甲），带套装效果 →"猎 A 拿装备，才好打 B"，目标自然连起来；再加千年王 / 历战王、最快 / 无伤纪录给高手追
5. **收枝叶**：秘境、试炼、钓灵兽不删，降成配角（秘境变成刷某种材料的地方，试炼是休闲），菜单和流程围着"猎王"转
- 王的血量 / 攻击频率按人数调（已有），一个人不会被磨死，四个人也不会太轻松

### 8. 大号第二次交接（2026-09-29，用户让小号接着做，大号停）

1. **用户刚做好的模型**（7 把暗器里的几把 + 2 种灵兽，按 `docs/3D模型提示词.md` 第二批生成）：接进游戏
   - 暗器照版本历史 34 的流程（`WeaponModels.MODEL_FIT` / `_swap_model`）。流沙机弩的转管（节点 Rotor）、天心泪的泪滴（节点 Tear）要从模型里按位置切出来单独动（或者让用户拆部件生成）
   - 灵兽是**静态模型、没有骨骼**（跟用户说好了"动作用代码做"）：`BeastModels` 现在全是带骨骼动画的 Quaternius 模型，要加一条"静态模型 + 代码动作"的路：
     鱼 / 蛇 / 藤身体波浪摆、鸟 / 蛾 / 蝠 / 鳐扇翅膀、兔 / 蟾整只一蹦一蹦、蛛 / 蟹腿交替迈、四条腿的按位置把腿切开前后摆（可以学跳尸的顶点着色器 `Horde.SHADER_TEX`，或 Boss 的程序步态 `Boss._static_model`）。
     攻击 / 受击 / 死亡也要有（前扑、后仰、翻倒）。文件名 `beast_<物种 id>.glb`，姿势要求见提示词文档
   - 山魈是人形，用混元绑骨骼后借用朱厌的 8 段动作（骨头名字一样，都是 Mixamo 那套）
2. **镜湖样板收尾**（版本历史 35）：第四版截图还没看。`sceneshot` 截图 → 和 `before/` 比 → 还丑的地方接着改 → 用户点头了再推到其他四张图（落霞林、苍梧林海、朔北冰原、归墟，每张图的树种和光各自定）。
   第三版截图里看到的问题：草一丛丛露黄土、黄山松近看像扁饼、宝塔平白墙、远山灰三角锥、天上灰椭圆——第四版都改了，要确认
3. **国风 CG**：用户看不了 md 文件，图生视频提示词已经用文字发给用户了。**用户不想做视频也没关系**：直接用 `tools/boat_anim/ai/01~10` 的静图做 Remotion 版（`FilmsCN.tsx` 慢推 + 流云 + 天光 + 竖排题字 + 朱印），先换掉西洋名画版；用户以后做了视频再替换
4. 蛛母 / 玄鲲（`tools/incoming_models/` 的 Meshy 模型）：还没接（见第 3 节）

