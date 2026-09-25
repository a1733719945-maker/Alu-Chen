# 斗罗大陆 · 猎魂

第一人称联机猎魂游戏。玩法参考 How to Fish：用**引魂索**把魂兽拽上天，趁它在空中用**唐门暗器**击杀。最多 8 人联机。

用 [Godot 4.7.2](https://godotengine.org) 做，打包成 Windows 程序；联机走一台很小的中继服务器（`server/`，部署在 Render 免费版的法兰克福机房）。

## 下载试玩

每次推送代码，GitHub Actions 会自动跑测试并打包 Windows 版，发布在本仓库的 **Releases** 页面（`latest-<分支名>`）。下载 `DouluoHunter-Windows.zip`，解压后双击 `DouluoHunter.exe`。详细说明见 [docs/玩家说明.txt](docs/玩家说明.txt)。

## 第三版有什么

| 内容 | 说明 |
|---|---|
| 流程 | 五章，从头到通关估计 4 小时以上：湖心岛 → 落日森林 → 星斗大森林 → 极北之地 → 海神岛。每章一串任务（猎杀、指定魂兽、买/升级暗器、等级、魂环、祭坛、Boss、坐船） |
| 地图 | 湖心岛（晴天）、落日森林（黄昏）、星斗大森林（雾气古木、蓝银草、星斗古树）、极北之地（雪原、冰湖、冰晶、下雪）、海神岛（沙滩、海崖、珊瑚、浅海 / 深海 / 海渊三层） |
| 魂兽 | 23 种，除鬼藤外都是带动画的 3D 模型（Quaternius，CC0）：柔骨兔、风铃鸟、月光蛾、疾风魔狼、铁甲犀、金刚猿、曼陀罗蛇、鬼眼鹿、夜翼魔蝠、疾爪龙、地穴魔蛛、碧磷蟾、雪原狼、冰角鹿、冰甲龙、雪魔猿、冰鳞鱼、铁钳蟹、海魂鸥、彩鳞鱼、深海魔鲨、幽灵鳐……分十年 / 百年 / 千年，章节越后越多高年份 |
| 物理 | Jolt 物理引擎。空中分段重力（上升正常、最高点短暂滞空、下落加快）；空中连击每枪的上推力递减并有上限，魂兽一定会掉下来；被打死的魂兽带死亡动画摔到地上再消失；拽出来的魂兽落在岸上而不是水里 |
| Boss | 湖主 · 千年曼陀罗蛇、森林之主 · 人面魔蛛、星斗之王 · 泰坦巨猿（扔巨石）、极北之主 · 冰霜巨龙（飞行、冰息、俯冲）、海神岛之主 · 深海魔鲸。掉魂骨（永久属性）和魂环 |
| 成长 | 等级上限 50，每 10 级瓶颈要吸收魂环（第四、五环要千年）；9 种武魂 × 5 个魂环，每环二选一，共 90 个魂技，Q / C / X / Z / V 释放 |
| 暗器 | 袖箭（手枪）、诸葛神弩（冲锋）、孔雀翎（步枪）、暴雨梨花针（霰弹）、追魂穿心弩（狙击，带瞄准镜）。每把有自己的后坐图案、随机散布、第一发精准、移动/跳跃/蹲下影响、开镜、镜头冲击 |
| 界面 | 思源黑体（Noto Sans SC）+ Barlow Condensed 数字，扁平深色面板 |
| 联机 | 创建房间得到 4 位房间码，朋友输入即可加入；房主算魂兽和 Boss，每人的等级、魂环、暗器存自己电脑上 |

素材：天空、植物和石头模型来自 [Poly Haven](https://polyhaven.com)，地面和树皮贴图、树叶草叶图集来自 [ambientCG](https://ambientcg.com)，魂兽和 Boss 模型来自 [Quaternius](https://quaternius.com)，都是 CC0（免费商用、不用署名）。字体是思源黑体和 Barlow Condensed（SIL OFL）。下载和处理脚本在 `tools/fetch_assets.py`、`tools/prepare_assets.py`、`tools/fetch_models.py`、`tools/subset_fonts.py`。

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
  scripts/world/      地形（island.gd）、场景搭建（world_builder.gd）、魂技（skills.gd）、一局游戏的逻辑和同步（world.gd）
  scripts/player/     第一人称控制、暗器（gun.gd 后坐和散布）、枪模、引魂索、其他玩家的显示
  scripts/beasts/     魂兽（物理、AI、模型）、Boss
  scripts/ui/         主菜单、游戏界面、暗器铺、武魂面板、设置
  shaders/            地形混合、树叶、草、水
  assets/             字体、图片（来自之前的"斗罗猎魂"）、合成的音效、CC0 贴图和模型、天空
server/               联机中继服务器（Node.js）
tools/gen_sfx.py      合成全部音效
tools/fetch_assets.py 下载 CC0 素材；prepare_assets.py 生成树叶/草贴片；set_texture_imports.py 设置贴图导入
```

- 调数值：暗器（后坐图案、散布、射速……）、魂兽、魂技、Boss、任务、奖励倍率都在 `game/scripts/autoload/data.gd`；移动手感的常量在 `game/scripts/player/player.gd` 开头。
- 换魂兽模型：模型放在 `game/assets/models/creatures/`，在 `data.gd` 的 `BEASTS` / `BOSSES` 里写 `model`（文件名）、`fit` + `size`（按宽/高/长缩放到几米）、`tint`。动画按名字自动认（idle / run / jump / attack / death）。`--autotest=measure` 会重新量模型尺寸写进 `measure.json`，`--autotest=zoo` 出一张所有魂兽的预览图。
- 自动测试：

```bash
godot --headless --path game --import
godot --headless --path game -- --autotest=solo            # 整个流程：物理、抓魂兽、买暗器、压枪、魂环魂技、五章的 Boss 和坐船
godot --headless --path game -- --autotest=solo --chapter=4 "--plan=hunt:icelake+icefield,boss,done"   # 只测一段
(cd server && npm install && npm test)                     # 中继服务器
# 联机：先起服务器，再开房主和客人
(cd server && PORT=18931 node server.js &)
godot --headless --path game -- --autotest=host --server=ws://127.0.0.1:18931 --room=TEST &
godot --headless --path game -- --autotest=client --server=ws://127.0.0.1:18931 --room=TEST
```
