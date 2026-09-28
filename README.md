# 苍墟 · 猎灵

第一人称联机猎灵游戏。玩法参考 How to Fish：用**引魂索**把灵兽拽上天，趁它在空中用**千机阁暗器**击杀。最多 8 人联机。

用 [Godot 4.7.2](https://godotengine.org) 做，打包成 Windows、Mac 程序和安卓 APK（都能一起联机）；联机走一台很小的中继服务器（`server/`，部署在 Render 免费版的法兰克福机房）。

## 下载试玩

每次推送代码，GitHub Actions 会自动跑测试并打包 Windows 版和安卓版，发布在本仓库的 **Releases** 页面（`latest-<分支名>`）。

- 电脑：下载 `DouluoHunter-Windows.zip`，解压后双击 `DouluoHunter.exe`。
- Mac：下载 `CangxuHunter-Mac.zip`，解压后把“苍墟·猎灵”拖进应用程序（Intel 和 M 芯片通用）。没有苹果公证，第一次打开要到“系统设置 → 隐私与安全性”点“仍要打开”，见 [docs/Mac第一次打开.txt](docs/Mac第一次打开.txt)。
- 安卓手机：用手机浏览器下载 `CangxuHunter.apk` 安装（要允许"安装未知应用"）。触屏操作：左手浮动摇杆，右手滑屏转视角，右下一圈按钮。

详细说明见 [docs/玩家说明.txt](docs/玩家说明.txt)。

### 手机版是怎么做的

- 同一套代码：`Settings.touch_active()`（手机上自动开，电脑上加 `-- --touch` 参数可以测试）时，`ui/touch_controls.gd` 显示触屏按钮，按钮直接改输入动作的状态（`Input.action_press`），游戏逻辑不用区分键盘还是触屏；HUD 用 `Hud.touch_layout()` 换成触屏布局。
- 手机上默认低画质、3D 渲染分辨率 75%、草更少、阴影更近，用 Godot 的 Mobile 渲染器；界面按屏幕实际尺寸放大（打开面板时恢复原大小）。
- 安卓导出预设在 `game/export_presets.cfg`（只打 arm64），签名用 `tools/android/release.keystore`（固定密钥，更新时能覆盖安装）。
- 苹果版：代码通用，但要苹果开发者账号（99 美元/年，通过 TestFlight 发给朋友）；打包可以用 GitHub Actions 的 macOS 机器。还没做。

## 第三版有什么

| 内容 | 说明 |
|---|---|
| 流程 | 五章，从头到通关估计 4 小时以上：镜湖 → 落霞林 → 苍梧林海 → 朔北冰原 → 归墟。每章一串任务（猎杀、指定灵兽、买/升级暗器、等级、灵环、祭坛、Boss、坐船） |
| 地图 | 镜湖（晴天）、落霞林（黄昏）、苍梧林海（雾气古木、青冥藤、苍梧古木）、朔北冰原（雪原、冰湖、冰晶、下雪）、归墟（沙滩、海崖、珊瑚、浅海 / 深海 / 海渊三层） |
| 灵兽 | 23 种，除噬灵藤外都是带动画的 3D 模型（Quaternius，CC0）：玉兔、青鸾、月光蛾、追风狼、铁甲兕、山魈、碧鳞蛇、夫诸、夜翼蝠、疾爪蜥、地穴毒蛛、碧眼蟾、雪原狼、冰角鹿、冰甲龙、雪猱、冰鳞鱼、铁钳蟹、贪金鸥、彩鳞鱼、深海狂鲨、幽灵鳐……分十年 / 百年 / 千年，章节越后越多高年份 |
| 物理 | Jolt 物理引擎。空中分段重力（上升正常、最高点短暂滞空、下落加快）；空中连击每枪的上推力递减并有上限，灵兽一定会掉下来；被打死的灵兽带死亡动画摔到地上再消失；拽出来的灵兽落在岸上而不是水里 |
| Boss | 镜湖之主 · 千年碧鳞蛟、落霞林之主 · 千目蛛母、苍梧之王 · 朱厌（扔巨石）、朔北之主 · 冰螭（飞行、冰息、俯冲）、归墟之主 · 玄鲲。掉灵骨（永久属性）和灵环 |
| 成长 | 等级上限 50，每 10 级瓶颈要吸收灵环（第四、五环要千年）；9 种灵相 × 5 个灵环，每环二选一，共 90 个神通。只用一个键：轻按 Q 放当前神通，按住 Q 弹出神通轮盘用鼠标选 |
| 暗器 | 袖箭（手枪）、连机神弩（冲锋）、流光翎（步枪）、千丝雨针（霰弹）、穿云弩（狙击，带瞄准镜）。每把有自己的后坐图案、随机散布、第一发精准、移动/跳跃/蹲下影响、开镜、镜头冲击 |
| 界面 | 思源黑体（Noto Sans SC）+ Barlow Condensed 数字；game-icons.net 的剪影图标（神通、道具、灵石、任务）；斜切血条、半透明底板、神通轮盘 |
| 联机 | 创建房间得到 4 位房间码，朋友输入即可加入；房主算灵兽和 Boss，每人的等级、灵环、暗器存自己电脑上 |

素材：天空、植物和石头模型来自 [Poly Haven](https://polyhaven.com)，地面和树皮贴图、树叶草叶图集来自 [ambientCG](https://ambientcg.com)，灵兽和 Boss 模型来自 [Quaternius](https://quaternius.com)，都是 CC0（免费商用、不用署名）。字体是思源黑体和 Barlow Condensed（SIL OFL）。界面图标来自 [game-icons.net](https://game-icons.net)（作者 Lorc、Delapouite、Zeromancer，CC BY 3.0），下载脚本 `tools/fetch_icons.py`。下载和处理脚本在 `tools/fetch_assets.py`、`tools/prepare_assets.py`、`tools/fetch_models.py`、`tools/subset_fonts.py`。

## 部署联机服务器（Render 免费版）

只需要做一次：

1. 打开 <https://render.com>，用 GitHub 账号登录。
2. 右上角 **New** → **Blueprint**，选择这个仓库（`Alu-Chen`）。
3. Render 会读取仓库里的 `render.yaml`，自动创建一个叫 `douluo-relay` 的服务（法兰克福、免费版），点 **Apply**。
4. 等几分钟部署完成，在服务页面上方能看到地址，比如 `https://douluo-relay.onrender.com`。
5. 游戏里默认连的是 `wss://douluo-relay.onrender.com`。如果 Render 给的地址不一样（名字被占用时会带后缀），在游戏的 **设置 → 联机服务器** 里改成 `wss://你的地址`，或者告诉开发者改默认值。

免费版 15 分钟没人连接会休眠，第一个连接的人要等 1 分钟左右，游戏里会显示"正在唤醒服务器"。

## 开发

```
game/                 Godot 项目
  scripts/autoload/   全局：设置、数据表（data.gd 调数值）、存档（profile.gd）、联机、音效
  scripts/world/      地形（island.gd）、场景搭建（world_builder.gd）、神通（skills.gd）、一局游戏的逻辑和同步（world.gd）
  scripts/player/     第一人称控制、暗器（gun.gd 后坐和散布）、枪模、引魂索、其他玩家的显示
  scripts/beasts/     灵兽（物理、AI、模型）、Boss
  scripts/ui/         主菜单、游戏界面、暗器铺、灵相面板、设置
  shaders/            地形混合、树叶、草、水
  assets/             字体、图片（早期版本留下的）、合成的音效、CC0 贴图和模型、天空
server/               联机中继服务器（Node.js）
tools/gen_sfx.py      合成全部音效
tools/fetch_assets.py 下载 CC0 素材；prepare_assets.py 生成树叶/草贴片；set_texture_imports.py 设置贴图导入
```

- 调数值：暗器（后坐图案、散布、射速……）、灵兽、神通、Boss、任务、奖励倍率都在 `game/scripts/autoload/data.gd`；移动手感的常量在 `game/scripts/player/player.gd` 开头。
- 换灵兽模型：模型放在 `game/assets/models/creatures/`，在 `data.gd` 的 `BEASTS` / `BOSSES` 里写 `model`（文件名）、`fit` + `size`（按宽/高/长缩放到几米）、`tint`。动画按名字自动认（idle / run / jump / attack / death）。`--autotest=measure` 会重新量模型尺寸写进 `measure.json`，`--autotest=zoo` 出一张所有灵兽的预览图。
- 自动测试：

```bash
godot --headless --path game --import
godot --headless --path game -- --autotest=solo            # 整个流程：物理、抓灵兽、买暗器、压枪、灵环神通、五章的 Boss 和坐船
godot --headless --path game -- --autotest=solo --chapter=4 "--plan=hunt:icelake+icefield,boss,done"   # 只测一段
(cd server && npm install && npm test)                     # 中继服务器
# 联机：先起服务器，再开房主和客人
(cd server && PORT=18931 node server.js &)
godot --headless --path game -- --autotest=host --server=ws://127.0.0.1:18931 --room=TEST &
godot --headless --path game -- --autotest=client --server=ws://127.0.0.1:18931 --room=TEST
```
