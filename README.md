# 斗罗大陆 · 猎魂

第一人称联机猎魂游戏。玩法参考 How to Fish：用**引魂索**把魂兽拽上天，趁它在空中用**唐门暗器**击杀。最多 8 人联机。

用 [Godot 4.7.2](https://godotengine.org) 做，打包成 Windows 程序；联机走一台很小的中继服务器（`server/`，部署在 Render 免费版的法兰克福机房）。

## 下载试玩

每次推送代码，GitHub Actions 会自动跑测试并打包 Windows 版，发布在本仓库的 **Releases** 页面（`latest-<分支名>`）。下载 `DouluoHunter-Windows.zip`，解压后双击 `DouluoHunter.exe`。详细说明见 [docs/玩家说明.txt](docs/玩家说明.txt)。

## 第一版（手感测试）有什么

| 内容 | 说明 |
|---|---|
| 地图 | 圣魂村外的湖心小岛：风铃草原、兔子洞、月光花丛、湖水、码头、暗器铺（下版开张） |
| 魂兽 | 柔骨兔（兔子洞）、鬼藤（湖水）、风铃鸟（草原）、月光蛾（花丛），分十年 / 百年 / 千年 |
| 暗器 | 袖箭（单发、爆头 ×2）、暴雨梨花针（一次 14 根针） |
| 引魂索 | 按住 E 蓄力甩出 → 1–3 秒咬住 → 按 E 拽上天；千年魂兽要拉扯 |
| 奖励 | 空中击杀 ×1.5、空中连击每下 +12%、爆头 ×1.25、25 米外 ×1.2；全队共用金魂币 |
| 联机 | 创建房间得到 4 位房间码，朋友输入即可加入；房主算魂兽，其他人命中结果发给房主 |

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
  scripts/autoload/   全局：设置、数据表（data.gd 调数值）、联机、音效
  scripts/world/      岛的地形（island.gd）、场景搭建、一局游戏的逻辑和同步（world.gd）
  scripts/player/     第一人称控制、暗器、引魂索、其他玩家的显示
  scripts/beasts/     魂兽（物理、逃跑 AI、模型）
  scripts/ui/         主菜单、游戏界面、设置
  assets/             字体、图片（来自之前的"斗罗猎魂"）、合成的音效
server/               联机中继服务器（Node.js）
tools/gen_sfx.py      合成全部音效
```

- 调手感：暗器、引魂索、奖励倍率都在 `game/scripts/autoload/data.gd`；移动和后坐的常量在 `game/scripts/player/player.gd` 开头。
- 换魂兽模型：把 `.glb` 放到 `game/assets/models/<名字>.glb`（`rabbit` / `vine` / `bird` / `moth`），会自动替换掉几何体拼的模型。
- 自动测试：

```bash
godot --headless --path game --import
godot --headless --path game -- --autotest=solo            # 四种栖息地 + 千年拉扯
(cd server && npm install && npm test)                     # 中继服务器
# 联机：先起服务器，再开房主和客人
(cd server && PORT=18931 node server.js &)
godot --headless --path game -- --autotest=host --server=ws://127.0.0.1:18931 --room=TEST &
godot --headless --path game -- --autotest=client --server=ws://127.0.0.1:18931 --room=TEST
```
