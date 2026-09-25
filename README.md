# 斗罗大陆 · 猎魂

第一人称联机猎魂游戏。玩法参考 How to Fish：用**引魂索**把魂兽拽上天，趁它在空中用**唐门暗器**击杀。最多 8 人联机。

用 [Godot 4.7.2](https://godotengine.org) 做，打包成 Windows 程序；联机走一台很小的中继服务器（`server/`，部署在 Render 免费版的法兰克福机房）。

## 下载试玩

每次推送代码，GitHub Actions 会自动跑测试并打包 Windows 版，发布在本仓库的 **Releases** 页面（`latest-<分支名>`）。下载 `DouluoHunter-Windows.zip`，解压后双击 `DouluoHunter.exe`。详细说明见 [docs/玩家说明.txt](docs/玩家说明.txt)。

## 第二版有什么

| 内容 | 说明 |
|---|---|
| 地图 | 第一章 · 湖心岛（晴天）：风铃草原、兔子洞、月光花丛、湖水、码头、暗器铺、北坡祭坛。第二章 · 落日森林（黄昏）：狼穴、泥潭、古树林和千年古树、毒沼、行脚商人 |
| 画面 | 真实地面贴图混合、程序生成的树（树皮 + 树叶贴片，随风摆）、真实草丛、Poly Haven 的石头灌木蕨类花、HDR 天空、远山、萤火虫、体积雾（高画质）；设置里可选 低 / 中 / 高 |
| 魂兽 | 第一章：柔骨兔、鬼藤、风铃鸟、月光蛾；第二章：疾风魔狼（扑人）、铁甲犀（皮厚、冲撞）、金刚猿（扔石头）、曼陀罗蛇。分十年 / 百年 / 千年 |
| 暗器 | 袖箭（手枪）、诸葛神弩（冲锋）、孔雀翎（步枪）、暴雨梨花针（霰弹）、追魂穿心弩（狙击，带瞄准镜）。每把有自己的后坐图案、随机散布、第一发精准、移动/跳跃/蹲下影响、开镜、镜头冲击 |
| 成长 | 金魂币买暗器、升级（伤害 / 弹匣 / 换弹 / 稳定）、道具（佛怒唐莲、回血丹、引兽香）；修为升级，每 10 级瓶颈要吸收魂环 |
| 魂环 · 魂技 | 9 种武魂，每个魂环二选一，共 54 个魂技（控制、爆发、位移、增益、治疗、护盾……），Q / C / X 释放；K 看武魂面板 |
| Boss | 湖主 · 千年曼陀罗蛇（钻水、扑咬、毒液、召唤）；森林之主 · 人面魔蛛（蛛网减速、扑跳）。掉魂骨（永久属性）和魂环 |
| 任务 | 每章一串任务，左上角显示，屏幕上有指路标记；打完 Boss 坐乌篷船去下一章 |
| 联机 | 创建房间得到 4 位房间码，朋友输入即可加入；房主算魂兽和 Boss，每人的等级、魂环、暗器存自己电脑上 |

素材：天空、植物和石头模型来自 [Poly Haven](https://polyhaven.com)，地面和树皮贴图、树叶草叶图集来自 [ambientCG](https://ambientcg.com)，都是 CC0（免费商用、不用署名）。下载和处理脚本在 `tools/fetch_assets.py`、`tools/prepare_assets.py`。

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
- 换魂兽模型：把 `.glb` 放到 `game/assets/models/<名字>.glb`（`rabbit` / `vine` / `bird` / `moth`），会自动替换掉几何体拼的模型。
- 自动测试：

```bash
godot --headless --path game --import
godot --headless --path game -- --autotest=solo            # 整个流程：抓魂兽、买暗器、压枪、魂环魂技、Boss、坐船、第二章
(cd server && npm install && npm test)                     # 中继服务器
# 联机：先起服务器，再开房主和客人
(cd server && PORT=18931 node server.js &)
godot --headless --path game -- --autotest=host --server=ws://127.0.0.1:18931 --room=TEST &
godot --headless --path game -- --autotest=client --server=ws://127.0.0.1:18931 --room=TEST
```
