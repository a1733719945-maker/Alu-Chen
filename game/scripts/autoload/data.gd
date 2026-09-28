extends Node
## 游戏数据表。调数值主要改这里：暗器、灵兽、神通、章节任务、商店价格。

const PROTOCOL_VERSION := "m3-1"
var autotest := false      # 自动测试时关掉随机的东西（精英、兽潮、饥饿、灵兽性格）

## 字体：思源黑体（正文 Medium、强调 Bold、标题 Black），数字用 Barlow Condensed（窄体，像 FPS 游戏的弹药数）
var font_ui: Font = preload("res://assets/fonts/NotoSansSC-Medium.otf")
var font_bold: Font = preload("res://assets/fonts/NotoSansSC-Bold.otf")
var font_title: Font
var font_num: Font


func _init() -> void:
	var t := FontVariation.new()
	t.base_font = preload("res://assets/fonts/NotoSansSC-Black.otf")
	t.spacing_glyph = 2
	font_title = t
	var n := FontVariation.new()
	n.base_font = preload("res://assets/fonts/BarlowCondensed-Bold.woff")
	n.fallbacks = [font_bold]
	font_num = n
	# 裁剪过的思源黑体里没有的生僻字，用系统里的中文字体补上（不然显示成方框）
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "PingFang SC", "Noto Sans CJK SC", "WenQuanYi Micro Hei"])
	for f: Font in [font_ui, font_bold, t.base_font]:
		f.fallbacks = [sys]

# ================================================================ 灵相
const WUHUN := [
	{"id": "lyc", "fx": Color(0.25, 0.75, 1.0), "name": "青冥藤", "kind": "植物系 · 控制", "color": Color("6aa8ec"), "img": "res://assets/img/wuhun/w01.jpg"},
	{"id": "ld", "fx": Color(0.95, 0.15, 0.3), "name": "玄月镰", "kind": "器相 · 强攻", "color": Color("c9d3d0"), "img": "res://assets/img/wuhun/w02.jpg"},
	{"id": "xc", "fx": Color(1.0, 0.5, 0.2), "name": "灵葫", "kind": "食物系 · 辅助", "color": Color("e59a6b"), "img": "res://assets/img/wuhun/w03.jpg"},
	{"id": "bh", "fx": Color(1.0, 0.72, 0.2), "name": "白虎", "kind": "兽相 · 强攻", "color": Color("f1f1e6"), "img": "res://assets/img/wuhun/w04.jpg"},
	{"id": "ym", "fx": Color(0.62, 0.3, 1.0), "name": "玄夜灵猫", "kind": "兽相 · 敏攻", "color": Color("9c7be0"), "img": "res://assets/img/wuhun/w05.jpg"},
	{"id": "hf", "fx": Color(1.0, 0.38, 0.1), "name": "朱雀", "kind": "兽相 · 强攻", "color": Color("f0773f"), "img": "res://assets/img/wuhun/w06.jpg"},
	{"id": "qb", "fx": Color(0.3, 1.0, 0.8), "name": "九层玲珑塔", "kind": "器相 · 辅助", "color": Color("8fe3d0"), "img": "res://assets/img/wuhun/w07.jpg"},
	{"id": "ht", "fx": Color(0.45, 0.5, 1.0), "name": "镇岳锤", "kind": "器相 · 强攻", "color": Color("c0c6cc"), "img": "res://assets/img/wuhun/w08.jpg"},
	{"id": "ls", "fx": Color(1.0, 0.92, 0.55), "name": "九天玄女", "kind": "兽相 · 强攻", "color": Color("ffe08a"), "img": "res://assets/img/wuhun/w09.jpg"},
]

# ================================================================ 年份（灵环颜色）
# 十年碧、百年蔚蓝、千年紫、万年金、十万年赤、百万年七彩（原创配色，不用别的作品那套白黄紫黑红）。hp / reward / xp 是相对十年的倍数（经验、金币另外按章节放大，见 kill_xp / kill_money）
# glow：灵环发光的颜色
const AGES := [
	{"name": "十年", "color": Color(0.45, 0.95, 0.72), "glow": Color(0.45, 0.95, 0.72), "hp": 1.0, "reward": 1.0, "xp": 0.8, "scale": 1.0, "mass": 1.0, "ring_drop": 0.25, "ring_power": 1.0},
	{"name": "百年", "color": Color(0.3, 0.62, 1.0), "glow": Color(0.3, 0.62, 1.0), "hp": 1.8, "reward": 2.2, "xp": 1.1, "scale": 1.2, "mass": 1.5, "ring_drop": 0.4, "ring_power": 1.3},
	{"name": "千年", "color": Color(0.72, 0.4, 1.0), "glow": Color(0.72, 0.4, 1.0), "hp": 3.0, "reward": 4.5, "xp": 1.6, "scale": 1.45, "mass": 2.4, "ring_drop": 0.6, "ring_power": 1.7},
	{"name": "万年", "color": Color(1.0, 0.8, 0.28), "glow": Color(1.0, 0.8, 0.28), "hp": 5.0, "reward": 9.0, "xp": 2.6, "scale": 1.75, "mass": 4.0, "ring_drop": 0.8, "ring_power": 2.3},
	{"name": "十万年", "color": Color(1.0, 0.32, 0.12), "glow": Color(1.0, 0.32, 0.12), "hp": 9.0, "reward": 20.0, "xp": 5.0, "scale": 2.1, "mass": 6.0, "ring_drop": 1.0, "ring_power": 3.2},
	# 百万年（七彩，泛白）：只在第五章的三层秘境（秘境之主）出现。用户："第五关应该只有万年、十万年、百万年秘境"
	{"name": "百万年", "color": Color(1.0, 0.9, 0.97), "glow": Color(0.95, 0.85, 1.0), "hp": 12.0, "reward": 36.0, "xp": 8.0, "scale": 2.35, "mass": 8.0, "ring_drop": 1.0, "ring_power": 4.0},
]

# ================================================================ 灵兽
# habitat：在哪里能用引魂索引出来；motion：落地后怎么跑
# armor：身体减伤（头不减）；hurt：落地后会不会攻击玩家（伤害值）
# model：assets/models/creatures 里的模型；fit + size：按长(l)/高(h)/宽(w)缩放到多少米；tint：颜色；glow：发光
const BEASTS := {
	# 第一章 · 镜湖
	"rabbit": {"name": "玉兔", "habitat": "burrow", "hp": 30.0, "reward": 10, "xp": 10, "motion": "hop", "hurt": 5.0,
		"model": "bunny", "fit": "h", "size": 0.8, "tint": Color(1.0, 0.97, 0.98)},
	"vine": {"name": "噬灵藤", "habitat": "water", "hp": 36.0, "reward": 14, "xp": 12, "motion": "slither", "hurt": 7.0},
	"bird": {"name": "青鸾", "habitat": "meadow", "hp": 24.0, "reward": 15, "xp": 12, "motion": "fly", "hurt": 5.0,
		"model": "pigeon", "fit": "w", "size": 1.0, "tint": Color(0.55, 1.0, 0.95)},
	"moth": {"name": "月光蛾", "habitat": "flowers", "hp": 26.0, "reward": 12, "xp": 10, "motion": "flutter", "hurt": 4.0,
		"model": "wasp", "fit": "w", "size": 0.9, "tint": Color(0.75, 0.8, 1.2), "glow": Color(0.35, 0.45, 1.0)},
	# 第二章 · 落霞林
	"wolf": {"name": "追风狼", "habitat": "den", "hp": 70.0, "reward": 30, "xp": 26, "motion": "run", "hurt": 12.0,
		"model": "wolf", "fit": "l", "size": 1.8, "tint": Color(0.72, 0.78, 0.9)},
	"rhino": {"name": "铁甲兕", "habitat": "mud", "hp": 120.0, "reward": 40, "xp": 34, "motion": "charge", "armor": 0.5, "hurt": 22.0, "heavy": true,
		"model": "bull", "fit": "l", "size": 2.6, "tint": Color(0.62, 0.66, 0.74), "horn": true},
	"ape": {"name": "山魈", "habitat": "grove", "hp": 90.0, "reward": 36, "xp": 30, "motion": "throw", "hurt": 15.0, "tall": true,
		"model": "yeti", "fit": "h", "size": 1.9, "tint": Color(0.62, 0.45, 0.34)},
	"snake": {"name": "碧鳞蛇", "habitat": "swamp", "hp": 60.0, "reward": 30, "xp": 26, "motion": "slither", "hurt": 8.0,
		"model": "snake", "fit": "h", "size": 1.2, "tint": Color(0.95, 0.55, 1.2)},
	# 第三章 · 苍梧林海
	"stag": {"name": "夫诸", "habitat": "glade", "hp": 110.0, "reward": 50, "xp": 46, "motion": "run", "hurt": 14.0, "tall": true,
		"model": "stag", "fit": "l", "size": 2.3, "tint": Color(0.55, 0.6, 0.85), "glow": Color(0.1, 0.35, 0.8)},
	"bat": {"name": "夜翼蝠", "habitat": "roost", "hp": 80.0, "reward": 48, "xp": 44, "motion": "fly", "hurt": 11.0,
		"model": "bat", "fit": "w", "size": 1.6, "tint": Color(0.8, 0.7, 1.0)},
	"raptor": {"name": "疾爪蜥", "habitat": "thicket", "hp": 130.0, "reward": 56, "xp": 52, "motion": "run", "hurt": 18.0,
		"model": "raptor", "fit": "l", "size": 2.8, "tint": Color(0.7, 0.85, 0.7)},
	"spiderling": {"name": "地穴毒蛛", "habitat": "nest", "hp": 100.0, "reward": 52, "xp": 48, "motion": "run", "hurt": 14.0,
		"model": "spider", "fit": "w", "size": 1.8, "tint": Color(0.85, 0.6, 1.0)},
	"frog": {"name": "碧眼蟾", "habitat": "bog", "hp": 90.0, "reward": 46, "xp": 42, "motion": "hop", "hurt": 10.0,
		"model": "frog", "fit": "l", "size": 1.0, "tint": Color(0.6, 1.1, 0.8), "glow": Color(0.05, 0.3, 0.15)},
	# 第四章 · 朔北冰原
	"husky": {"name": "雪原狼", "habitat": "snowden", "hp": 150.0, "reward": 70, "xp": 64, "motion": "run", "hurt": 18.0,
		"model": "husky", "fit": "l", "size": 2.0, "tint": Color(1.1, 1.12, 1.2)},
	"icedeer": {"name": "冰角鹿", "habitat": "frostgrove", "hp": 160.0, "reward": 72, "xp": 66, "motion": "run", "hurt": 12.0, "tall": true,
		"model": "deer", "fit": "l", "size": 2.1, "tint": Color(0.8, 0.95, 1.2), "glow": Color(0.1, 0.35, 0.5)},
	"icehorn": {"name": "冰甲龙", "habitat": "icefield", "hp": 260.0, "reward": 90, "xp": 80, "motion": "charge", "armor": 0.5, "hurt": 28.0, "heavy": true,
		"model": "triceratops", "fit": "l", "size": 3.4, "tint": Color(0.7, 0.9, 1.15)},
	"snowape": {"name": "雪猱", "habitat": "icecave", "hp": 200.0, "reward": 80, "xp": 72, "motion": "throw", "hurt": 20.0, "tall": true,
		"model": "yeti", "fit": "h", "size": 2.3, "tint": Color(1.05, 1.08, 1.15)},
	"icefish": {"name": "冰鳞鱼", "habitat": "icelake", "hp": 120.0, "reward": 64, "xp": 58, "motion": "slither", "hurt": 12.0,
		"model": "fish1", "fit": "l", "size": 1.4, "tint": Color(0.75, 0.95, 1.2), "glow": Color(0.1, 0.25, 0.35)},
	# 第五章 · 归墟
	"crab": {"name": "铁钳蟹", "habitat": "beach", "hp": 220.0, "reward": 90, "xp": 82, "motion": "charge", "armor": 0.4, "hurt": 22.0,
		"model": "crab", "fit": "w", "size": 1.5, "tint": Color(1.2, 0.7, 0.55)},
	"gull": {"name": "贪金鸥", "habitat": "cliff", "hp": 140.0, "reward": 86, "xp": 78, "motion": "fly", "hurt": 14.0,
		"model": "pigeon", "fit": "w", "size": 1.4, "tint": Color(1.25, 1.25, 1.3)},
	"reeffish": {"name": "彩鳞鱼", "habitat": "reef", "hp": 150.0, "reward": 84, "xp": 76, "motion": "slither", "hurt": 12.0,
		"model": "fish2", "fit": "l", "size": 1.2},
	"shark": {"name": "深海狂鲨", "habitat": "deep", "hp": 260.0, "reward": 110, "xp": 96, "motion": "slither", "hurt": 22.0,
		"model": "shark", "fit": "l", "size": 3.0, "tint": Color(0.75, 0.85, 1.0)},
	"manta": {"name": "幽灵鳐", "habitat": "abyss", "hp": 240.0, "reward": 120, "xp": 104, "motion": "flutter", "hurt": 16.0,
		"model": "manta", "fit": "w", "size": 2.6, "tint": Color(0.6, 0.7, 1.1), "glow": Color(0.1, 0.2, 0.6)},
}

# ================================================================ 灵兽的独门本事（凶暴的和精英会用）
# 每一招都有前摇（wind 秒）：灵兽发光、地上出现范围圈、头顶冒招式名。看到了就翻滚 / 跑出圈能躲开。
# at：self 以灵兽为中心，target 砸在前摇开始时你站的地方（跑开就没事）
# dmg：相对咬一口的倍数；push 击退；pull 拉过去；root 定身秒数；slow 减速比例 + dur；blind 致盲秒数；
# vuln 受伤加深秒数；silence 封神通秒数；poison / bleed 持续掉血；steal 叼走灵石比例；shield 打碎护盾；heal 吸血回复
const BEAST_SKILLS := {
	"rabbit": {"name": "玉兔蹬腿", "cd": 6.0, "wind": 0.45, "range": 3.5, "radius": 3.2, "at": "self", "dmg": 1.3, "push": 12.0},
	"vine": {"name": "噬灵藤缠绕", "cd": 8.0, "wind": 0.8, "range": 9.0, "radius": 2.6, "at": "target", "dmg": 0.6, "root": 1.6},
	"bird": {"name": "鸾鸣音波", "cd": 7.0, "wind": 0.8, "range": 10.0, "radius": 6.0, "at": "self", "dmg": 0.8, "push": 10.0},
	"moth": {"name": "月光磷粉", "cd": 9.0, "wind": 0.7, "range": 8.0, "radius": 4.5, "at": "self", "dmg": 0.4, "blind": 2.5},
	"wolf": {"name": "狼嚎", "cd": 12.0, "wind": 0.9, "range": 25.0, "radius": 20.0, "at": "self", "dmg": 0.0, "howl": 6.0},
	"rhino": {"name": "铁蹄震地", "cd": 9.0, "wind": 0.9, "range": 6.0, "radius": 5.5, "at": "self", "dmg": 1.3, "push": 7.0, "slow": 0.5, "dur": 2.0, "shield": true},
	"ape": {"name": "山魈捶地", "cd": 8.0, "wind": 0.9, "range": 5.0, "radius": 5.0, "at": "self", "dmg": 1.5, "push": 9.0},
	"snake": {"name": "碧鳞毒雾", "cd": 9.0, "wind": 0.6, "range": 13.0, "radius": 3.6, "at": "target", "dmg": 0.7, "slow": 0.4, "dur": 2.0},
	"stag": {"name": "夫诸凝视", "cd": 11.0, "wind": 1.0, "range": 26.0, "radius": 2.0, "at": "target", "dmg": 0.8, "vuln": 6.0},
	"bat": {"name": "吸血", "cd": 7.0, "wind": 0.5, "range": 4.0, "radius": 3.6, "at": "self", "dmg": 1.3, "heal": 3.0},
	"raptor": {"name": "扑杀", "cd": 7.0, "wind": 0.55, "range": 12.0, "min": 4.0, "radius": 2.6, "at": "target", "dmg": 1.5, "root": 0.8, "leap": true},
	"spiderling": {"name": "蛛网", "cd": 8.0, "wind": 0.5, "range": 14.0, "radius": 3.0, "at": "target", "dmg": 0.3, "slow": 0.65, "dur": 3.0},
	"frog": {"name": "长舌卷人", "cd": 8.0, "wind": 0.6, "range": 12.0, "min": 3.0, "radius": 2.3, "at": "target", "dmg": 0.8, "pull": 15.0},
	"husky": {"name": "雪狼嚎", "cd": 12.0, "wind": 0.9, "range": 25.0, "radius": 20.0, "at": "self", "dmg": 0.0, "howl": 6.0},
	"icedeer": {"name": "冰霜新星", "cd": 10.0, "wind": 1.0, "range": 7.0, "radius": 6.0, "at": "self", "dmg": 0.8, "root": 1.4},
	"icehorn": {"name": "冰甲震地", "cd": 9.0, "wind": 0.9, "range": 7.0, "radius": 6.5, "at": "self", "dmg": 1.3, "push": 6.0, "slow": 0.5, "dur": 2.5, "shield": true},
	"snowape": {"name": "雪崩捶地", "cd": 8.0, "wind": 1.0, "range": 6.0, "radius": 6.0, "at": "self", "dmg": 1.6, "push": 10.0, "slow": 0.4, "dur": 2.0},
	"icefish": {"name": "冰刺", "cd": 7.0, "wind": 0.5, "range": 12.0, "radius": 2.6, "at": "target", "dmg": 1.0, "slow": 0.5, "dur": 2.0},
	"crab": {"name": "铁钳夹击", "cd": 9.0, "wind": 0.6, "range": 4.0, "radius": 3.2, "at": "self", "dmg": 1.6, "root": 1.2, "shield": true},
	"gull": {"name": "叼钱", "cd": 10.0, "wind": 0.4, "range": 5.0, "radius": 3.6, "at": "self", "dmg": 0.3, "steal": 0.03},
	"reeffish": {"name": "彩鳞闪光", "cd": 9.0, "wind": 0.7, "range": 10.0, "radius": 5.0, "at": "self", "dmg": 0.3, "blind": 2.2},
	"shark": {"name": "撕咬流血", "cd": 8.0, "wind": 0.5, "range": 4.5, "radius": 3.6, "at": "self", "dmg": 1.4, "bleed": 0.3, "dur": 5.0},
	"manta": {"name": "幽灵电击", "cd": 10.0, "wind": 0.9, "range": 10.0, "radius": 6.0, "at": "self", "dmg": 1.0, "silence": 3.0},
}

const HABITATS := {
	"water": {"name": "湖水", "beast": "vine"},
	"burrow": {"name": "兔子洞", "beast": "rabbit"},
	"meadow": {"name": "鸾鸣草原", "beast": "bird"},
	"flowers": {"name": "月光花丛", "beast": "moth"},
	"den": {"name": "狼穴", "beast": "wolf"},
	"mud": {"name": "泥潭", "beast": "rhino"},
	"grove": {"name": "古树林", "beast": "ape"},
	"swamp": {"name": "毒沼", "beast": "snake"},
	"glade": {"name": "夫诸林", "beast": "stag"},
	"roost": {"name": "蝠巢枯林", "beast": "bat"},
	"thicket": {"name": "龙爪荆棘", "beast": "raptor"},
	"nest": {"name": "毒蛛巢穴", "beast": "spiderling"},
	"bog": {"name": "碧眼沼", "beast": "frog"},
	"snowden": {"name": "雪狼洞", "beast": "husky"},
	"frostgrove": {"name": "冰晶林", "beast": "icedeer"},
	"icefield": {"name": "冰原", "beast": "icehorn"},
	"icecave": {"name": "冰窟", "beast": "snowape"},
	"icelake": {"name": "冰湖", "beast": "icefish"},
	"beach": {"name": "金沙滩", "beast": "crab"},
	"cliff": {"name": "海崖", "beast": "gull"},
	"reef": {"name": "浅海珊瑚", "beast": "reeffish"},
	"deep": {"name": "深海", "beast": "shark"},
	"abyss": {"name": "海渊", "beast": "manta"},
}

# ================================================================ 灵兽性格（每只拽出来的时候随机，房主决定）
# flee   胆小：落地就逃回窝里 / 水里
# fierce 凶暴：盯住最近的玩家一直打，不逃，打到死为止
# sly    狡猾：落地先装死几秒，你一走近就突然窜回去
# bone   灵骨兽：全身金光，跑得飞快，打死必掉一块灵骨
const TEMPERS := {
	"flee": {"name": "", "color": Color(0.85, 0.85, 0.85)},
	"fierce": {"name": "凶暴", "color": Color(1.0, 0.32, 0.26)},
	"sly": {"name": "狡猾", "color": Color(0.55, 0.95, 0.6)},
	"bone": {"name": "灵骨", "color": Color(1.0, 0.84, 0.3)},
	"elite": {"name": "精英", "color": Color(1.0, 0.55, 0.15)},
}

# ================================================================ 精英灵兽（小 Boss）
# 每张地图在陆地栖息地附近固定几个点刷，不用引魂索拽；走近 20 米或者打它就会过来打人，
# 跑出 45 米就回老家回血。打死以后 2 分钟在原地重生，必掉灵骨。
# 灵兽王（原来的精英）：每张图 3 只，守在自己的地盘，打它们拿灵环、灵骨和王魄（附魔材料）
const ELITE_HP := 14.0
const ELITE_SIZE := 2.0
const ELITE_DMG := 2.2
const ELITE_REWARD := 12.0
const ELITE_RESPAWN := 360.0
const ELITE_MAX := 3
const KING_BIND_TIME := 5.0      # 捆魂：按住几秒
const KING_BIND_CD := 18.0
const KING_XP_LEVELS := 1.5      # 打死一只灵兽王，全队每人多拿大约这一章 2.5 级的修为（主线靠猎王，不靠刷小怪）

# ================================================================ 符阵附魔：用灵兽王掉的"王魄"给暗器附魔，命中有几率触发
# mats：哪些灵兽王的王魄能用（任意组合凑够 n 个）；kind 是命中效果（SkillSystem.host_empower）
const ENCHANTS := {
	"bind": {"name": "缠魂", "kind": "root", "chance": 0.2, "frac": 0.4, "n": 2, "price": 800, "mats": ["rabbit", "moth", "spiderling", "frog"], "color": Color(0.4, 0.9, 0.5), "desc": "命中 20% 几率缠住灵兽 1 秒"},
	"thunder": {"name": "雷鸣", "kind": "chain", "chance": 0.25, "frac": 0.6, "n": 2, "price": 800, "mats": ["bird", "bat", "gull"], "color": Color(0.5, 0.8, 1.0), "desc": "命中 25% 几率放出闪电，弹到旁边 2 只灵兽"},
	"bleed": {"name": "裂伤", "kind": "bleed", "chance": 0.35, "frac": 0.5, "n": 2, "price": 1500, "mats": ["wolf", "raptor", "husky"], "color": Color(0.95, 0.2, 0.25), "desc": "命中 35% 几率让灵兽流血，自己回一点血"},
	"blast": {"name": "爆裂", "kind": "explode", "chance": 0.2, "frac": 0.7, "n": 2, "price": 2500, "mats": ["rhino", "ape", "crab"], "color": Color(1.0, 0.55, 0.2), "desc": "命中 20% 几率炸开（3.5 米）"},
	"quake": {"name": "震魂", "kind": "quake", "chance": 0.15, "frac": 0.9, "n": 3, "price": 6000, "mats": ["rhino", "ape", "icehorn", "snowape"], "color": Color(0.8, 0.7, 0.5), "desc": "命中 15% 几率震出冲击波（4.5 米），把灵兽掀飞"},
	"flame": {"name": "焚魂", "kind": "burn", "chance": 0.3, "frac": 0.5, "n": 2, "price": 5000, "mats": ["stag", "icedeer", "raptor"], "color": Color(1.0, 0.4, 0.1), "desc": "命中 30% 几率点燃灵兽和它旁边的灵兽"},
	"frost": {"name": "霜寒", "kind": "root", "chance": 0.3, "frac": 0.5, "n": 3, "price": 9000, "mats": ["husky", "icedeer", "icehorn", "snowape"], "color": Color(0.6, 0.9, 1.0), "desc": "命中 30% 几率冻住灵兽 1 秒"},
}
const ENCHANT_ORDER := ["bind", "thunder", "bleed", "blast", "flame", "quake", "frost"]
const AGGRESSIVE := ["wolf", "rhino", "ape", "snake", "raptor", "spiderling", "husky", "icehorn", "snowape", "crab", "shark", "stag", "icedeer", "bat"]


func roll_temper(rng: RandomNumberGenerator, species: String, age: int, bait := "grass") -> String:
	var bd: Dictionary = BAITS.get(bait, BAITS["grass"])
	var bone := (0.04 + age * 0.03) * float(bd["bone"])
	var fierce := (0.62 if species in AGGRESSIVE else 0.4) + age * 0.08 + float(bd["fierce"])
	var sly := 0.12
	var r := rng.randf()
	if r < bone:
		return "bone"
	r -= bone
	if r < fierce:
		return "fierce"
	r -= fierce
	if r < sly:
		return "sly"
	return "flee"


# ================================================================ 战利品（打死灵兽掉在地上，捡起来丢进收购箱换灵石）
const LOOT_PART := {"hop": "绒毛", "slither": "鳞片", "fly": "羽翎", "flutter": "翅鳞", "run": "利齿", "charge": "硬角", "throw": "兽骨"}
const KILL_MONEY := 1.0          # 打死直接拿灵石（素材已经去掉了）
const LOOT_VALUE := 0.7
const SELL_ITEMS := {"pill": 20, "grenade": 30, "meat": 12, "soul_pill": 20, "haste_pill": 20, "guard_pill": 30, "rage_pill": 40, "giant_pill": 35}


## 素材的 key："mat:<灵兽>:<年份>"
func mat_key(species: String, age: int) -> String:
	return "mat:%s:%d" % [species, age]


func item_name(kind: String, key: String) -> String:
	match kind:
		"mat":
			var p := key.split(":")
			if p.size() < 3 or not BEASTS.has(p[1]):
				return "素材"
			return "%s%s%s" % [age_name(int(p[2])), BEASTS[p[1]]["name"], LOOT_PART.get(BEASTS[p[1]]["motion"], "兽骨")]
		"bone":
			return bone_name(key)
		"gun":
			return str(WEAPONS.get(key, {"name": "暗器"})["name"])
		"item":
			return str(ITEMS.get(key, {"name": key})["name"])
	return key


func item_value(kind: String, key: String) -> int:
	match kind:
		"mat":
			var p := key.split(":")
			if p.size() < 3 or not BEASTS.has(p[1]):
				return 5
			return maxi(roundi(float(BEASTS[p[1]]["reward"]) * float(AGES[int(p[2])]["reward"]) * LOOT_VALUE), 3)
		"bone":
			return 150 * [1, 4, 15, 60, 200][clampi(bone_age(key), 0, 4)]
		"item":
			return int(float(SELL_ITEMS.get(key, 10)) * float(CH_PRICE.get(cur_chapter, 1.0)))
		"gun":
			return int(WEAPONS.get(key, {"price": 0})["price"]) / 2
	return 0


func item_color(kind: String, key: String) -> Color:
	match kind:
		"mat":
			var p := key.split(":")
			return age_color(int(p[2])) if p.size() >= 3 else Color.WHITE
		"bone":
			return Color(1.0, 0.85, 0.35)
		"gun":
			return Color(0.6, 0.9, 1.0)
	return Color(1.0, 0.6, 0.5)

# ================================================================ 千机阁暗器
# 后坐（CS / COD 的做法）：
#   pattern      每一发往哪边跳（度）：x 左右、y 向上。连射时按顺序叠加，停火后回正
#   jitter       每发额外的随机抖动
#   view_punch   只晃镜头、不影响弹道的"顶一下"，负责手感的冲击力
# 散布：
#   hip / ads    腰射 / 开镜 的基础散布（度）
#   move         全速移动时额外增加的散布；air 跳在空中；crouch 蹲下乘的系数
#   bloom        每发增加的散布，停火后按 bloom_recover 每秒恢复；刚开第一枪最准
# 第十二版多了五把，每把一种新机制：寒梅袖箭（三连发）、追星针（精确射手）、子母雷珠（爆炸 + 子弹再炸）、
# 流沙机弩（越打越快的机枪）、天心泪（按住蓄力，满了一箭穿透所有）
const WEAPON_ORDER := ["xiujian", "meihua", "baoyu", "zhuge", "longxu", "kongque", "zimu", "hansha", "zhuihun", "guanyin"]
# 副手（2 号键，一直在身上的那种小暗器）；其余的是主暗器（1 号键，按一次换下一把）
const SIDEARMS := ["xiujian", "meihua"]
# 拿着暗器跑的速度（越重越慢）；空手最快
const MOVE_K := {"xiujian": 0.96, "meihua": 0.96, "zhuge": 0.92, "longxu": 0.88, "kongque": 0.88, "baoyu": 0.9, "zimu": 0.88,
	"hansha": 0.8, "zhuihun": 0.84, "guanyin": 0.9, "fist": 1.15}
# 暗器跟着章节开放
const WEAPON_UNLOCK := {"xiujian": 1, "baoyu": 1, "meihua": 1, "zhuge": 2, "longxu": 2, "kongque": 3, "zimu": 3, "zhuihun": 4, "hansha": 4, "guanyin": 5}
# 开火方式的中文（暗器铺卡片上）
const MODE_NAME := {"semi": "单发", "auto": "连发", "bolt": "拉栓", "burst": "三连发", "charge": "蓄力"}

const WEAPONS := {
	"xiujian": {
		"name": "袖箭", "cat": "手枪", "desc": "千机阁入门暗器。射速快、爆头伤害高，适合点射。",
		"price": 250, "mode": "semi", "rpm": 420, "damage": 28.0, "headshot": 2.2, "pellets": 1,
		"mag": 12, "reload": 1.05, "reload_empty": 1.35, "per_shell": false,
		"range": 160.0, "falloff": Vector3(40, 120, 0.6),
		"hip": 1.1, "ads": 0.18, "move": 1.2, "air": 3.5, "crouch": 0.8,
		"bloom": 0.7, "bloom_max": 4.0, "bloom_recover": 7.0,
		"pattern": [Vector2(0, 2.8)], "jitter": 0.55, "ads_recoil": 0.8,
		"view_punch": 2.2, "recover_delay": 0.07, "recover_speed": 14.0,
		"ads_fov": 0.86, "ads_time": 0.11, "ads_move": 0.8,
		"impulse": 2.2, "lift": 0.55, "shake": 0.2,
		"tracer": Color(1.0, 0.72, 0.3), "sound": "xiujian_fire", "bolt": true,
	},
	"zhuge": {
		"name": "连机神弩", "cat": "冲锋", "desc": "连发弩，一秒十五箭。近中距离压制，连射上跳很快，要往下拉。",
		"price": 2800, "mode": "auto", "rpm": 900, "damage": 22.0, "headshot": 1.8, "pellets": 1,
		"mag": 36, "reload": 1.8, "reload_empty": 2.2, "per_shell": false,
		"range": 120.0, "falloff": Vector3(18, 60, 0.55),
		"hip": 1.9, "ads": 0.6, "move": 0.8, "air": 3.0, "crouch": 0.85,
		"bloom": 0.2, "bloom_max": 2.6, "bloom_recover": 5.0,
		"pattern": "smg", "recoil_scale": 2.3, "jitter": 0.35, "ads_recoil": 0.75,
		"view_punch": 1.0, "recover_delay": 0.09, "recover_speed": 22.0,
		"ads_fov": 0.86, "ads_time": 0.13, "ads_move": 0.85,
		"impulse": 0.85, "lift": 0.5, "shake": 0.09,
		"tracer": Color(1.0, 0.85, 0.5), "sound": "zhuge_fire", "bolt": true,
	},
	"kongque": {
		"name": "流光翎", "cat": "步枪", "desc": "千机阁四大暗器之一。伤害高、第一发极准，连射后坐很大，要压枪。",
		"price": 12000, "mode": "auto", "rpm": 600, "damage": 52.0, "headshot": 2.0, "pellets": 1,
		"mag": 30, "reload": 2.1, "reload_empty": 2.6, "per_shell": false,
		"range": 200.0, "falloff": Vector3(50, 150, 0.7),
		"hip": 2.4, "ads": 0.1, "move": 3.0, "air": 4.0, "crouch": 0.75,
		"bloom": 0.4, "bloom_max": 5.0, "bloom_recover": 7.5,
		"pattern": "rifle", "recoil_scale": 1.8, "jitter": 0.25, "ads_recoil": 0.8,
		"view_punch": 1.6, "recover_delay": 0.1, "recover_speed": 15.0,
		"ads_fov": 0.84, "ads_time": 0.18, "ads_move": 0.75,
		"impulse": 1.35, "lift": 0.5, "shake": 0.14,
		"tracer": Color(0.45, 1.0, 0.85), "sound": "kongque_fire", "bolt": true,
	},
	"baoyu": {
		"name": "千丝雨针", "cat": "霰弹", "desc": "一次十四根银针。近身一发把灵兽轰上天，后坐像被人推了一把。",
		"price": 400, "mode": "semi", "rpm": 75, "damage": 13.0, "headshot": 1.5, "pellets": 14,
		"mag": 6, "reload": 0.45, "reload_empty": 0.45, "per_shell": true,
		"range": 70.0, "falloff": Vector3(9, 30, 0.3),
		"hip": 5.2, "ads": 3.8, "move": 0.8, "air": 1.5, "crouch": 0.9,
		"bloom": 0.0, "bloom_max": 0.0, "bloom_recover": 1.0,
		"pattern": [Vector2(0, 7.0)], "jitter": 1.2, "ads_recoil": 0.9,
		"view_punch": 5.0, "recover_delay": 0.1, "recover_speed": 12.0,
		"ads_fov": 0.9, "ads_time": 0.15, "ads_move": 0.85,
		"impulse": 0.95, "lift": 0.65, "shake": 0.6,
		"tracer": Color(0.9, 0.92, 1.0), "sound": "baoyu_fire", "bolt": false,
	},
	"zhuihun": {
		"name": "穿云弩", "cat": "狙击", "desc": "重弩，一箭贯穿。要装狙击镜才好用（暗器铺 → 配件）。",
		"price": 40000, "mode": "bolt", "rpm": 48, "damage": 420.0, "headshot": 2.5, "pellets": 1,
		"mag": 5, "reload": 2.7, "reload_empty": 3.1, "per_shell": false, "cycle": 1.1,
		"range": 1500.0, "falloff": Vector3(1500, 1500, 1.0), "pierce": 3,
		"hip": 6.5, "ads": 0.0, "move": 5.0, "air": 8.0, "crouch": 0.7,
		"bloom": 0.0, "bloom_max": 0.0, "bloom_recover": 1.0,
		"pattern": [Vector2(0, 8.5)], "jitter": 0.8, "ads_recoil": 1.0,
		"view_punch": 6.0, "recover_delay": 0.12, "recover_speed": 10.0,
		"ads_fov": 0.84, "ads_time": 0.28, "ads_move": 0.55,
		"impulse": 7.0, "lift": 0.45, "shake": 0.7,
		"tracer": Color(1.0, 0.95, 0.7), "sound": "zhuihun_fire", "bolt": true,
	},
	# ---- 第十二版新增 ----
	# 三连发：扣一下出三箭（burst），三箭之间 burst_gap 秒；射速 rpm 是两次扣扳机之间
	"meihua": {
		"name": "寒梅袖箭", "cat": "手枪", "desc": "扣一下连出三箭，像梅花一样落在一处。三箭都爆头最痛。",
		"price": 1500, "mode": "burst", "burst": 3, "burst_gap": 0.055, "rpm": 150, "damage": 30.0, "headshot": 2.0, "pellets": 1,
		"mag": 21, "reload": 1.25, "reload_empty": 1.6, "per_shell": false,
		"range": 150.0, "falloff": Vector3(35, 100, 0.6),
		"hip": 1.3, "ads": 0.25, "move": 1.1, "air": 3.5, "crouch": 0.8,
		"bloom": 0.3, "bloom_max": 3.0, "bloom_recover": 7.0,
		"pattern": [Vector2(0, 1.0), Vector2(0.2, 1.2), Vector2(-0.2, 1.4)], "jitter": 0.3, "ads_recoil": 0.8,
		"view_punch": 1.3, "recover_delay": 0.14, "recover_speed": 12.0,
		"ads_fov": 0.86, "ads_time": 0.12, "ads_move": 0.8,
		"impulse": 1.5, "lift": 0.5, "shake": 0.1,
		"tracer": Color(1.0, 0.55, 0.72), "sound": "xiujian_fire", "pitch": 1.18, "bolt": true,
	},
	# 精确射手：一发一发，开镜几乎没有散布，爆头倍数高，能穿两只
	"longxu": {
		"name": "追星针", "cat": "射手", "desc": "细如龙须，远处一针入脑。开镜极准，爆头 ×2.6，能穿透两只。",
		"price": 6000, "mode": "semi", "rpm": 240, "damage": 88.0, "headshot": 2.6, "pellets": 1,
		"mag": 10, "reload": 2.0, "reload_empty": 2.5, "per_shell": false, "pierce": 2,
		"range": 400.0, "falloff": Vector3(80, 300, 0.75),
		"hip": 3.0, "ads": 0.04, "move": 2.5, "air": 5.0, "crouch": 0.75,
		"bloom": 0.9, "bloom_max": 4.0, "bloom_recover": 6.0,
		"pattern": [Vector2(0.1, 3.2)], "jitter": 0.5, "ads_recoil": 0.75,
		"view_punch": 2.8, "recover_delay": 0.08, "recover_speed": 12.0,
		"ads_fov": 0.8, "ads_time": 0.2, "ads_move": 0.7,
		"impulse": 3.0, "lift": 0.5, "shake": 0.25,
		"tracer": Color(0.7, 0.9, 1.0), "sound": "kongque_fire", "pitch": 0.8, "bolt": true,
	},
	# 爆炸：打到哪里炸到哪里（splash 米内，中心伤害 splash_dmg，边上三成）；炸完再散出 children 颗子弹，0.3 秒后各炸一次
	"zimu": {
		"name": "子母雷珠", "cat": "爆破", "desc": "母胆炸开，再散出三颗子胆各炸一次。打一群最好，一颗一颗往里装。",
		"price": 18000, "mode": "semi", "rpm": 70, "damage": 70.0, "headshot": 1.5, "pellets": 1,
		"splash": 4.5, "splash_dmg": 110.0, "children": 3,
		"mag": 4, "reload": 0.6, "reload_empty": 0.6, "per_shell": true,
		"range": 120.0, "falloff": Vector3(40, 120, 0.8),
		"hip": 2.2, "ads": 0.8, "move": 1.5, "air": 3.0, "crouch": 0.85,
		"bloom": 0.0, "bloom_max": 0.0, "bloom_recover": 1.0,
		"pattern": [Vector2(0, 6.0)], "jitter": 0.8, "ads_recoil": 0.9,
		"view_punch": 4.5, "recover_delay": 0.12, "recover_speed": 10.0,
		"ads_fov": 0.88, "ads_time": 0.2, "ads_move": 0.75,
		"impulse": 5.0, "lift": 1.0, "shake": 0.5,
		"tracer": Color(1.0, 0.55, 0.2), "sound": "baoyu_fire", "pitch": 0.7, "bolt": false,
	},
	# 机枪：按住越打越快（spinup 秒从一半射速转到满），弹匣很大，很重
	"hansha": {
		"name": "流沙机弩", "cat": "机枪", "desc": "机括越转越快，一匣九十发。刚开火慢，按住一秒多才到最快。很重。",
		"price": 32000, "mode": "auto", "rpm": 840, "spinup": 1.2, "damage": 40.0, "headshot": 1.6, "pellets": 1,
		"mag": 90, "reload": 3.4, "reload_empty": 3.9, "per_shell": false,
		"range": 180.0, "falloff": Vector3(35, 120, 0.6),
		"hip": 2.6, "ads": 0.7, "move": 1.4, "air": 4.0, "crouch": 0.7,
		"bloom": 0.12, "bloom_max": 2.5, "bloom_recover": 4.0,
		"pattern": "smg", "recoil_scale": 1.6, "jitter": 0.3, "ads_recoil": 0.7,
		"view_punch": 0.9, "recover_delay": 0.1, "recover_speed": 18.0,
		"ads_fov": 0.86, "ads_time": 0.26, "ads_move": 0.6,
		"impulse": 0.7, "lift": 0.35, "shake": 0.08,
		"tracer": Color(0.95, 0.85, 0.5), "sound": "zhuge_fire", "pitch": 0.75, "bolt": true,
	},
	# 蓄力：按住左键蓄力（charge 秒蓄满），松开发射，伤害 ×(1 ~ charge_k)；蓄满了穿透一路上所有灵兽，散布也跟着收拢
	"guanyin": {
		"name": "天心泪", "cat": "蓄力", "desc": "千机阁第一暗器。按住蓄力，松开出手；蓄满一滴泪，贯穿一路上所有灵兽。",
		"price": 120000, "mode": "charge", "charge": 1.0, "charge_k": 5.0, "rpm": 240, "damage": 180.0, "headshot": 2.2, "pellets": 1,
		"mag": 6, "reload": 2.4, "reload_empty": 2.8, "per_shell": false,
		"range": 600.0, "falloff": Vector3(600, 600, 1.0),
		"hip": 2.5, "ads": 0.3, "move": 1.5, "air": 3.0, "crouch": 0.8,
		"bloom": 0.0, "bloom_max": 0.0, "bloom_recover": 1.0,
		"pattern": [Vector2(0, 5.0)], "jitter": 0.4, "ads_recoil": 0.8,
		"view_punch": 4.0, "recover_delay": 0.12, "recover_speed": 10.0,
		"ads_fov": 0.82, "ads_time": 0.2, "ads_move": 0.7,
		"impulse": 6.0, "lift": 0.6, "shake": 0.45,
		"tracer": Color(0.8, 0.95, 1.0), "sound": "zhuihun_fire", "pitch": 1.25, "bolt": true,
	},
	# 一把暗器都没有（全卖了 / 丢了）：空手打，伤害跟等级涨
	"fist": {
		"name": "空手", "cat": "", "desc": "没暗器的时候用拳头打。",
		"price": 0, "mode": "melee", "rpm": 170, "damage": 22.0, "headshot": 1.5, "pellets": 1,
		"mag": 1, "reload": 0.1, "reload_empty": 0.1, "per_shell": false,
		"range": 3.2, "falloff": Vector3(3, 4, 1),
		"hip": 0.0, "ads": 0.0, "move": 0.0, "air": 0.0, "crouch": 1.0,
		"bloom": 0.0, "bloom_max": 0.0, "bloom_recover": 1.0,
		"pattern": [Vector2(0, 0.6)], "jitter": 0.3, "ads_recoil": 1.0,
		"view_punch": 1.8, "recover_delay": 0.05, "recover_speed": 20.0,
		"ads_fov": 1.0, "ads_time": 0.1, "ads_move": 1.0,
		"impulse": 7.0, "lift": 0.9, "shake": 0.15,
		"tracer": Color(1, 1, 1), "sound": "punch", "bolt": false,
	},
}
# 连射后坐图案。停火后回正，所以只要记住前十几发往哪跳，往反方向拉鼠标就能压住
const PATTERNS := {
	"smg": [
		Vector2(0.0, 0.25), Vector2(0.03, 0.34), Vector2(-0.02, 0.4), Vector2(0.05, 0.44), Vector2(0.08, 0.45),
		Vector2(0.1, 0.43), Vector2(0.06, 0.4), Vector2(-0.05, 0.36), Vector2(-0.15, 0.3), Vector2(-0.2, 0.26),
		Vector2(-0.18, 0.22), Vector2(-0.08, 0.2), Vector2(0.06, 0.2), Vector2(0.18, 0.18), Vector2(0.24, 0.16),
		Vector2(0.2, 0.15), Vector2(0.08, 0.15), Vector2(-0.08, 0.14), Vector2(-0.2, 0.14), Vector2(-0.22, 0.13),
		Vector2(-0.1, 0.12), Vector2(0.05, 0.12), Vector2(0.18, 0.12), Vector2(0.2, 0.11), Vector2(0.1, 0.11),
	],
	"rifle": [
		Vector2(0.0, 0.3), Vector2(0.02, 0.5), Vector2(-0.03, 0.72), Vector2(0.06, 0.88), Vector2(0.12, 0.98),
		Vector2(0.1, 1.0), Vector2(0.14, 0.95), Vector2(0.18, 0.88), Vector2(0.1, 0.8), Vector2(0.02, 0.62),
		Vector2(-0.45, 0.32), Vector2(-0.62, 0.28), Vector2(-0.72, 0.25), Vector2(-0.6, 0.22), Vector2(-0.48, 0.2),
		Vector2(-0.35, 0.18), Vector2(-0.15, 0.15), Vector2(0.1, 0.15), Vector2(0.42, 0.16), Vector2(0.6, 0.16),
		Vector2(0.7, 0.15), Vector2(0.62, 0.14), Vector2(0.48, 0.13), Vector2(0.3, 0.12), Vector2(0.12, 0.12),
		Vector2(-0.2, 0.12), Vector2(-0.35, 0.1), Vector2(-0.3, 0.1), Vector2(-0.2, 0.1), Vector2(-0.1, 0.1),
	],
}

# 升级：每把暗器 4 项，每项 5 级。价格 = 暗器价格 × 系数（便宜的按 400 算）
const UPGRADES := {
	"dmg": {"name": "淬毒箭头", "desc": "伤害 +12%", "per": 0.12},
	"mag": {"name": "扩容机匣", "desc": "弹匣 +20%", "per": 0.2},
	"reload": {"name": "千机机括", "desc": "换弹快 10%", "per": 0.1},
	"stab": {"name": "稳定弩臂", "desc": "后坐 -12%，散布 -8%", "per": 0.12},
}
const UPGRADE_COST := [0.25, 0.45, 0.75, 1.1, 1.6]

# 配件：暗器铺买，默认都没有（只有机械照门）。price 是暗器价格的倍数（便宜的按 400 算）
# 瞄具（sight）一次只能装一个：红点 / 全息 放大一点点；2 倍镜、狙击镜 开镜是全屏瞄准镜（狙击镜滚轮 4~12 倍）
const ATTACH := {
	"red": {"name": "红点瞄具", "slot": "sight", "price": 0.3, "ads_fov": 0.8, "desc": "开镜时一颗红点，比照门清楚"},
	"holo": {"name": "全息瞄具", "slot": "sight", "price": 0.35, "ads_fov": 0.78, "desc": "圈点准星，近中距离好用"},
	"x2": {"name": "2 倍镜", "slot": "sight", "price": 0.5, "zoom": 2.2, "desc": "开镜放大 2 倍多（全屏瞄准镜）"},
	"x4": {"name": "4 倍镜", "slot": "sight", "price": 0.55, "zoom": 4.0, "desc": "开镜放大 4 倍（全屏瞄准镜），中远距离"},
	"scope": {"name": "狙击镜", "slot": "sight", "price": 0.6, "zoom": 6.0, "variable": true, "desc": "4~12 倍，开镜后滚轮调倍率，调好会记住"},
	"brake": {"name": "枪口制退器", "slot": "muzzle", "price": 0.3, "recoil_v": 0.72, "desc": "连射上跳 -28%"},
	"comp": {"name": "补偿器", "slot": "muzzle", "price": 0.3, "recoil_h": 0.6, "recoil_v": 0.9, "desc": "左右抖动 -40%，上跳 -10%"},
	"silencer": {"name": "消音器", "slot": "muzzle", "price": 0.35, "quiet": true, "recoil_v": 0.9, "desc": "枪声小、没有枪口火光，上跳 -10%"},
	"grip": {"name": "垂直握把", "slot": "under", "price": 0.3, "recoil_h": 0.55, "spread": 0.85, "desc": "左右抖动 -45%，散布 -15%"},
	"angled": {"name": "斜握把", "slot": "under", "price": 0.25, "ads_k": 0.8, "recoil_v": 0.92, "desc": "开镜快 20%，上跳 -8%"},
	"laser": {"name": "激光指示器", "slot": "under", "price": 0.2, "hip": 0.65, "desc": "腰射散布 -35%"},
	"extmag": {"name": "扩容弹匣", "slot": "mag", "price": 0.35, "mag_k": 1.5, "reload_k": 1.15, "desc": "弹匣 +50%，换弹慢 15%"},
	"fastmag": {"name": "快拔弹匣", "slot": "mag", "price": 0.3, "reload_k": 0.7, "desc": "换弹快 30%"},
	"soulmag": {"name": "灵晶弹匣", "slot": "mag", "price": 0.6, "dmg_k": 1.06, "mag_k": 0.8, "desc": "伤害 +6%，弹匣 -20%（箭头泛着魂光）"},
	"lstock": {"name": "轻型枪托", "slot": "stock", "price": 0.25, "ads_k": 0.75, "move_k": 1.04, "desc": "开镜快 25%，跑得快 4%"},
	"hstock": {"name": "战术枪托", "slot": "stock", "price": 0.3, "recoil_all": 0.82, "ads_k": 1.1, "desc": "后坐 -18%，开镜慢 10%"},
}
const ATTACH_SLOTS := [["sight", "瞄具"], ["muzzle", "枪口"], ["under", "枪管下"], ["mag", "弹匣"], ["stock", "枪托"]]
const ATTACH_OK := {
	"xiujian": ["red", "brake", "comp", "silencer", "laser", "extmag", "fastmag", "soulmag"],
	"meihua": ["red", "holo", "brake", "comp", "silencer", "laser", "extmag", "fastmag", "soulmag"],
	"baoyu": ["red", "holo", "grip", "angled", "laser", "extmag", "fastmag", "lstock", "hstock"],
	"zhuge": ["red", "holo", "x2", "brake", "comp", "silencer", "grip", "angled", "laser", "extmag", "fastmag", "soulmag", "lstock", "hstock"],
	"longxu": ["red", "holo", "x2", "x4", "scope", "brake", "comp", "silencer", "grip", "angled", "laser", "extmag", "fastmag", "soulmag", "lstock", "hstock"],
	"kongque": ["red", "holo", "x2", "x4", "scope", "brake", "comp", "silencer", "grip", "angled", "laser", "extmag", "fastmag", "soulmag", "lstock", "hstock"],
	"zimu": ["red", "holo", "x2", "grip", "angled", "laser", "fastmag", "lstock", "hstock"],
	"hansha": ["red", "holo", "x2", "x4", "brake", "comp", "grip", "angled", "laser", "extmag", "fastmag", "soulmag", "lstock", "hstock"],
	"zhuihun": ["x2", "x4", "scope", "brake", "silencer", "laser", "extmag", "fastmag", "soulmag", "lstock", "hstock"],
	"guanyin": ["red", "holo", "x2", "x4", "scope", "laser", "soulmag", "lstock", "hstock"],
}

# ================================================================ 暗器熟练度：用哪把打死灵兽，哪把涨熟练度（每把暗器自己算）
# 升级给一点点手感（换弹、开镜、伤害、后坐），3 / 6 / 10 级送这把暗器专属的质感皮肤
const MASTERY_XP := [0, 60, 160, 320, 540, 820, 1180, 1620, 2160, 2800, 3600]   # 到第 i 级一共要多少
const MASTERY_MAX := 10
const MASTERY_PERKS := {
	2: {"reload": 0.05, "text": "换弹快 5%"},
	3: {"skin": "steel", "text": "皮肤「精钢」"},
	4: {"ads": 0.08, "text": "开镜快 8%"},
	5: {"dmg": 0.03, "text": "伤害 +3%"},
	6: {"skin": "blackgold", "text": "皮肤「黑金」"},
	7: {"recoil": 0.08, "text": "后坐 -8%"},
	8: {"dmg": 0.03, "text": "伤害再 +3%"},
	9: {"reload": 0.05, "text": "换弹再快 5%"},
	10: {"skin": "master", "text": "皮肤「千机大师 · 流光」"},
}


## 打死一只给多少熟练度：年份越高越多，爆头、空中、灵兽王另加
func mastery_gain(age: int, head: bool, air: bool, elite: bool) -> int:
	return 10 + 5 * clampi(age, 0, 4) + (5 if head else 0) + (3 if air else 0) + (60 if elite else 0)


func mastery_level(xp: int) -> int:
	var lv := 0
	for i in MASTERY_XP.size():
		if xp >= int(MASTERY_XP[i]):
			lv = i
	return mini(lv, MASTERY_MAX)


## 熟练度到 lv 级一共给了多少某项加成（reload / ads / dmg / recoil）
func mastery_bonus(lv: int, key: String) -> float:
	var t := 0.0
	for k in MASTERY_PERKS:
		if int(k) <= lv:
			t += float(MASTERY_PERKS[k].get(key, 0.0))
	return t


# ================================================================ 自己画的皮肤：画上去的颜料是什么质感
const PAINT_FINISH := {
	"matte": {"name": "哑光", "metal": 0.0, "rough": 0.85, "coat": 0.0},
	"gloss": {"name": "亮漆", "metal": 0.0, "rough": 0.35, "coat": 1.0},
	"metal": {"name": "金属", "metal": 0.9, "rough": 0.25, "coat": 0.0},
	"chrome": {"name": "镜面", "metal": 1.0, "rough": 0.06, "coat": 0.0},
}
const PAINT_FINISH_ORDER := ["matte", "gloss", "metal", "chrome"]

# ================================================================ 挂件：挂在暗器上，走路、开火会晃（纯外观，每把暗器单独挂）
const CHARMS := {
	"tassel": {"name": "红流苏", "price": 800, "desc": "一串红穗子，跑起来甩来甩去"},
	"jade": {"name": "玉佩", "price": 2500, "desc": "一块碧玉平安扣，下面坠着穗子"},
	"bell": {"name": "金铃", "price": 4000, "desc": "一只小金铃，开火时晃一下"},
	"rabbit": {"name": "玉兔", "price": 6000, "desc": "一只小兔子挂件"},
	"ring": {"name": "灵环挂坠", "price": 12000, "desc": "一枚小灵环，颜色是你最高的灵环"},
	"lotus": {"name": "雷莲", "price": 30000, "desc": "一朵发光的小雷莲"},
}
const CHARM_ORDER := ["tassel", "jade", "bell", "rabbit", "ring", "lotus"]


func attach_price(weapon: String, a: String) -> int:
	return int(round(maxf(float(WEAPONS[weapon]["price"]), 400.0) * float(ATTACH[a]["price"]) / 10.0)) * 10

# 道具
const ITEMS := {
	"grenade": {"name": "九转雷莲", "desc": "千机阁至高暗器。按 3 拿出来左键扔，爆炸把周围灵兽全部炸上天", "price": 60, "max": 5, "key": "3"},
	# 丹药：4 号位（再按 4 换下一种），左键吃。回血丹也能按 H 直接吃
	"pill": {"name": "回血丹", "desc": "按 H 直接吃（或者 4 号位左键吃）：马上回 60 体力，解毒、解定身和减速", "price": 40, "max": 5, "key": "H", "color": Color(1.0, 0.35, 0.35)},
	"soul_pill": {"name": "回魂丹", "desc": "灵力马上回六成——神通接着放", "price": 45, "max": 5, "key": "4", "color": Color(0.4, 0.7, 1.0)},
	"haste_pill": {"name": "疾风丹", "desc": "20 秒内跑得快 35%（追逃跑的灵兽王、躲红圈）", "price": 45, "max": 3, "key": "4", "color": Color(0.45, 1.0, 0.6)},
	"guard_pill": {"name": "金刚丹", "desc": "20 秒内受到的伤害 -40%（硬吃 Boss 的招）", "price": 70, "max": 3, "key": "4", "color": Color(1.0, 0.8, 0.3)},
	"rage_pill": {"name": "破境丹", "desc": "20 秒境界临时突破：暗器伤害 +40%，灵力回得快一倍", "price": 90, "max": 3, "key": "4", "ch": 2, "color": Color(1.0, 0.3, 0.8)},
	"giant_pill": {"name": "巨灵丹", "desc": "变大 15 秒：伤害 +20%、跑得更快、站得更高看得更远", "price": 80, "max": 3, "key": "4", "ch": 2, "color": Color(1.0, 0.55, 0.2)},
	# 用户：灵环吸收了就改不了，万一不满意——散魂丹：K 灵相面板里点那个灵环的「散」，再去猎一个补在同一个位置
	"scatter_pill": {"name": "散魂丹", "desc": "散掉一个不满意的灵环（K 灵相面板点那个灵环的「散」），神通跟着没了；再去猎一只补上同一个位置", "price": 400, "max": 2, "key": "K", "color": Color(0.7, 0.7, 0.85)},
	"lure_gold": {"name": "引兽香", "desc": "接下来 5 次咬钩必定是百年以上的灵兽", "price": 120, "max": 3, "key": "自动", "ch": 3},
	# 烤肉和饱食度去掉了（用户：没什么作用）。留着这一项只为了读旧存档（读档时折成灵石）
	"meat": {"name": "烤灵兽肉", "desc": "", "price": 15, "max": 10, "key": "4", "hidden": true},
	"bait_blood": {"name": "血腥饵 ×5", "desc": "钓上来的百年灵兽多，灵兽更凶，常带词缀，奖励 +30%", "price": 45, "max": 60, "key": "B", "bundle": 5, "ch": 2},
	"bait_soul": {"name": "灵晶饵 ×5", "desc": "千年灵兽出现率高好几倍，带词缀的更多（突破第四、五灵环靠它）", "price": 110, "max": 60, "key": "B", "bundle": 5, "ch": 3},
	"bait_gold": {"name": "金骨饵 ×5", "desc": "灵骨兽出现率 ×5，想刷灵骨就用它", "price": 130, "max": 60, "key": "B", "bundle": 5, "ch": 2},
}

# ================================================================ 鱼饵（引魂索每次咬钩消耗一个，按 B 换）
# w：十年 / 百年 / 千年 / 万年 的出现权重乘数；fierce：凶暴概率加成；affix：词缀概率加成；bone：灵骨兽概率倍数；reward：奖励倍数
const BAITS := {
	"grass": {"name": "青草饵", "item": "", "w": [1.0, 0.25, 0.04, 0.02], "fierce": 0.0, "affix": 0.0, "bone": 1.0, "reward": 1.0},
	"blood": {"name": "血腥饵", "item": "bait_blood", "w": [0.6, 1.4, 1.0, 0.8], "fierce": 0.3, "affix": 0.15, "bone": 1.0, "reward": 1.3},
	"soul": {"name": "灵晶饵", "item": "bait_soul", "w": [0.25, 1.2, 3.5, 2.5], "fierce": 0.1, "affix": 0.3, "bone": 1.5, "reward": 1.2},
	"gold": {"name": "金骨饵", "item": "bait_gold", "w": [0.8, 1.0, 1.2, 1.0], "fierce": 0.0, "affix": 0.1, "bone": 5.0, "reward": 1.0},
}
const BAIT_ORDER := ["grass", "blood", "soul", "gold"]
# 4 号位按 4 轮换的丹药顺序
const PILL_ORDER := ["pill", "soul_pill", "haste_pill", "guard_pill", "rage_pill", "giant_pill"]


## 灵兽、海鸥、宝藏随手掉的丹药：回血丹、回魂丹常见，别的少
func random_pill() -> String:
	var r := randf()
	if r < 0.4:
		return "pill"
	if r < 0.68:
		return "soul_pill"
	if r < 0.8:
		return "haste_pill"
	if r < 0.9:
		return "guard_pill"
	return "rage_pill" if r < 0.96 else "giant_pill"


func roll_age_bait(rng: RandomNumberGenerator, chapter: int, bait: String) -> int:
	var w: Array = AGE_WEIGHTS.get(chapter, AGE_WEIGHTS[1])
	var m: Array = BAITS.get(bait, BAITS["grass"])["w"]
	var ws: Array = []
	var total := 0.0
	for i in w.size():
		ws.append(float(w[i]) * float(m[mini(i, m.size() - 1)]))
		total += float(ws[i])
	if total <= 0.0:
		for i in w.size():
			if float(w[i]) > 0.0:
				return i
	var r := rng.randf() * total
	for i in ws.size():
		if float(ws[i]) <= 0.0:
			continue
		r -= float(ws[i])
		if r <= 0.0:
			return i
	for i in range(ws.size() - 1, -1, -1):
		if float(ws[i]) > 0.0:
			return i
	return 0


# ================================================================ 灵兽词缀（让每只灵兽打法不一样）
const AFFIXES := {
	"frenzy": {"name": "狂暴", "desc": "半血以下更快、更狠"},
	"armor": {"name": "坚甲", "desc": "打身体减伤一半，打头不减"},
	"split": {"name": "分裂", "desc": "死了分裂成两只小的"},
	"blast": {"name": "自爆", "desc": "死后一秒爆炸，快跑"},
	"swift": {"name": "疾速", "desc": "跑得飞快"},
	"regen": {"name": "再生", "desc": "两秒没挨打就回血"},
	"thunder": {"name": "雷暴", "desc": "落地震出雷环"},
}


func roll_affixes(rng: RandomNumberGenerator, age: int, chapter: int, bait: String, elite := false) -> Array:
	var chance := 0.08 + age * 0.1 + chapter * 0.03 + float(BAITS.get(bait, BAITS["grass"])["affix"]) + (0.6 if elite else 0.0)
	var keys: Array = AFFIXES.keys()
	var out: Array = []
	if rng.randf() < chance:
		out.append(keys[rng.randi() % keys.size()])
		if rng.randf() < chance * 0.4:
			var k2: String = keys[rng.randi() % keys.size()]
			if not k2 in out:
				out.append(k2)
	return out


func affix_names(affixes: Array) -> String:
	var n: Array = []
	for a in affixes:
		n.append(str(AFFIXES.get(a, {"name": a})["name"]))
	return "·".join(n)


# ================================================================ 饱食度、悬赏、兽潮
const FOOD_MAX := 100.0
const FOOD_DRAIN := 100.0 / 720.0      # 12 分钟从满到空（跑步饿得快）
const MEAT_FOOD := 40.0
const BOUNTY_N := 3
# 每张图自己的"奇遇"（代替原来千篇一律的兽潮）：天色 / 天气变化 + 专属灵兽 + 一只王
# mode：flock 天上飞过的一大群（打下来奖励 ×3），pack 从四面八方冲过来；env：天色天气
const CH_EVENTS := {
	1: {"name": "青鸾过境", "desc": "一大群青鸾从湖上飞过，在它们飞走之前打下来——每只奖励 ×3", "species": ["bird"], "n": 14, "mode": "flock", "king": "", "env": "gold", "color": Color(0.6, 1.0, 0.9)},
	2: {"name": "狼王夜袭", "desc": "天黑了。疾风狼王带着狼群从林子里扑出来，打死狼王必掉灵骨", "species": ["wolf"], "n": 10, "mode": "pack", "king": "wolf", "env": "night", "color": Color(1.0, 0.45, 0.35)},
	3: {"name": "苍梧兽潮", "desc": "星辰坠落，苍梧林海的灵兽成群冲出来，夫诸王压阵", "species": ["stag", "raptor", "spiderling"], "n": 12, "mode": "pack", "king": "stag", "env": "stars", "color": Color(0.7, 0.6, 1.0)},
	4: {"name": "朔北暴风雪", "desc": "暴风雪来了，看不远、走不快，雪原狼群借着风雪偷袭，冰甲龙王压阵", "species": ["husky", "snowape"], "n": 12, "mode": "pack", "king": "icehorn", "env": "blizzard", "color": Color(0.7, 0.9, 1.0)},
	5: {"name": "归墟怒潮", "desc": "风暴压境，铁钳蟹爬满沙滩，贪金鸥成群俯冲，蟹王压阵", "species": ["crab", "gull"], "n": 14, "mode": "pack", "king": "crab", "env": "storm", "color": Color(0.5, 0.75, 1.0)},
}
const TIDE_FIRST := 300.0              # 进图 5 分钟后第一次奇遇
const TIDE_GAP := [380.0, 520.0]
const TIDE_TIME := 75.0

# ================================================================ 外观：暗器皮肤、装扮（暗器铺"外观"页买；打败每章 Boss 送一款）
# 第十二版：皮肤不再只是换颜色（用户："要质感，例如金属反光那种"）。每款皮肤是一种材质（GunSkin 着色器）：
#   pal       暗器上各部分的底色（wood 木身 / lacquer 漆身 / black 黑件 / bronze 青铜 / gold 金 / iron 铁）
#   pat       身子（木、漆、黑件）的花纹：wood 木纹 fade 渐变 damascus 大马士革 carbon 碳纤维 marble 玉石纹 flow 流光 lava 熔岩
#             galaxy 星河 scales 龙鳞 pearl 珠光 circuit 回路 ice 冰晶 smoke 暗影烟 caustic 水波 aurora 极光 brushed 拉丝 web 蛛网；
#             pat_wood / pat_lacquer / pat_black 单独指定某一部分
#   c2 / c3   花纹的第二、第三个颜色（c3 一般是发光色）；glow_k 发光强度；speed 动画快慢；scale 花纹大小
#   body_metal / body_rough / coat   身子的金属度、粗糙度、清漆；trim_pat / trim_metal / trim_rough 包边（青铜金铁）
#   glow      发光小部件（翎羽、灵晶）的颜色
# 解锁：price 灵石买；boss 打败 Boss；codex 集齐猎灵录；mastery 这把暗器熟练度到几级；paint 自己画
const GUN_SKINS := {
	"default": {"name": "千机原色", "price": 0, "desc": "木纹、朱漆、青铜，千机阁的老样子",
		"pat": "plain", "pat_wood": "wood", "coat": 0.6, "body_rough": 0.45, "trim_rough": 0.32},
	"paint": {"name": "自己画", "price": 0, "paint": true, "desc": "在暗器铺 → 外观 → 自己画，每把暗器画自己的",
		"pat": "plain", "coat": 0.6, "body_rough": 0.45},
	"carbon": {"name": "碳纤维", "price": 4000, "desc": "黑色碳纤维编织，清漆面，红色金属包边",
		"pal": {"wood": Color(0.1, 0.1, 0.11), "lacquer": Color(0.1, 0.1, 0.11), "black": Color(0.07, 0.07, 0.08), "bronze": Color(0.32, 0.33, 0.35), "gold": Color(0.85, 0.1, 0.08), "iron": Color(0.3, 0.31, 0.33)},
		"pat": "carbon", "c2": Color(0.02, 0.02, 0.025), "glow": Color(1.0, 0.25, 0.2), "trim_rough": 0.22},
	"jade": {"name": "碧玉", "price": 2000, "desc": "整块碧玉雕出来，玉里有细细的发光玉脉",
		"pal": {"wood": Color(0.2, 0.55, 0.42), "lacquer": Color(0.16, 0.5, 0.38), "bronze": Color(0.92, 0.92, 0.86), "gold": Color(0.96, 0.95, 0.88), "iron": Color(0.75, 0.85, 0.8), "black": Color(0.08, 0.2, 0.15)},
		"pat": "marble", "c2": Color(0.5, 0.85, 0.68), "c3": Color(0.5, 1.0, 0.75), "glow_k": 0.5, "body_metal": 0.0, "body_rough": 0.12, "coat": 1.0, "glow": Color(0.4, 1.0, 0.7)},
	"chrome": {"name": "镜面铬", "price": 8000, "desc": "镜子一样的铬，照得出天空",
		"pal": {"wood": Color(0.86, 0.87, 0.9), "lacquer": Color(0.86, 0.87, 0.9), "black": Color(0.3, 0.3, 0.32), "bronze": Color(1.0, 0.8, 0.45), "gold": Color(1.0, 0.82, 0.45), "iron": Color(0.8, 0.8, 0.82)},
		"pat": "plain", "body_metal": 1.0, "body_rough": 0.04, "trim_pat": "plain", "trim_rough": 0.08, "glow": Color(0.6, 0.9, 1.0)},
	"blood": {"name": "血玉", "price": 5000, "desc": "暗红血玉，玉脉里流着红光，金色包边",
		"pal": {"wood": Color(0.32, 0.03, 0.05), "lacquer": Color(0.45, 0.02, 0.05), "bronze": Color(0.18, 0.17, 0.19), "gold": Color(1.0, 0.72, 0.28), "iron": Color(0.14, 0.13, 0.14), "black": Color(0.06, 0.02, 0.02)},
		"pat": "marble", "c2": Color(0.7, 0.08, 0.1), "c3": Color(1.0, 0.18, 0.1), "glow_k": 0.8, "body_rough": 0.14, "coat": 1.0, "trim_rough": 0.15, "glow": Color(1.0, 0.15, 0.1)},
	"ice": {"name": "寒冰", "price": 12000, "desc": "朔北寒冰打磨，边缘透着冷光，冰屑一闪一闪",
		"pal": {"wood": Color(0.72, 0.86, 0.96), "lacquer": Color(0.55, 0.76, 0.95), "bronze": Color(0.86, 0.95, 1.0), "gold": Color(0.7, 0.9, 1.0), "iron": Color(0.6, 0.72, 0.84), "black": Color(0.25, 0.36, 0.5)},
		"pat": "ice", "c2": Color(0.9, 0.97, 1.0), "c3": Color(0.5, 0.9, 1.0), "glow_k": 1.0, "body_metal": 0.3, "body_rough": 0.08, "coat": 1.0, "glow": Color(0.4, 0.9, 1.0)},
	"damascus": {"name": "大马士革", "price": 20000, "desc": "千层折叠钢，一圈圈弯曲的钢纹，金色包边",
		"pal": {"wood": Color(0.62, 0.63, 0.66), "lacquer": Color(0.62, 0.63, 0.66), "black": Color(0.3, 0.3, 0.32), "bronze": Color(0.95, 0.75, 0.35), "gold": Color(0.95, 0.75, 0.35), "iron": Color(0.4, 0.41, 0.43)},
		"pat": "damascus", "c2": Color(0.16, 0.17, 0.19), "body_metal": 1.0, "body_rough": 0.2, "trim_rough": 0.18, "glow": Color(1.0, 0.8, 0.4)},
	"shadow": {"name": "暗影", "price": 30000, "desc": "通体哑光黑，表面飘着一缕缕紫色的烟",
		"pal": {"wood": Color(0.05, 0.045, 0.06), "lacquer": Color(0.07, 0.05, 0.09), "bronze": Color(0.12, 0.1, 0.14), "gold": Color(0.55, 0.3, 0.9), "iron": Color(0.08, 0.08, 0.1), "black": Color(0.03, 0.03, 0.04)},
		"pat": "smoke", "c2": Color(0.12, 0.06, 0.16), "c3": Color(0.7, 0.35, 1.0), "glow_k": 1.8, "body_rough": 0.75, "glow": Color(0.7, 0.35, 1.0)},
	"fade": {"name": "渐变镭射", "price": 40000, "desc": "阳极氧化的金属，从金色渐变到粉紫，糖果一样的光泽",
		"pal": {"wood": Color(1.0, 0.82, 0.2), "lacquer": Color(1.0, 0.82, 0.2), "black": Color(0.35, 0.2, 0.6), "bronze": Color(0.9, 0.9, 0.92), "gold": Color(0.95, 0.95, 0.97), "iron": Color(0.85, 0.85, 0.88)},
		"pat": "fade", "c2": Color(1.0, 0.3, 0.55), "c3": Color(0.35, 0.3, 1.0), "body_metal": 0.85, "body_rough": 0.16, "trim_rough": 0.1, "glow": Color(1.0, 0.5, 0.9)},
	"magma": {"name": "熔岩", "price": 50000, "desc": "黑色岩壳，裂缝里的岩浆一明一暗",
		"pal": {"wood": Color(0.13, 0.1, 0.09), "lacquer": Color(0.13, 0.1, 0.09), "black": Color(0.08, 0.06, 0.05), "bronze": Color(0.3, 0.2, 0.15), "gold": Color(1.0, 0.45, 0.12), "iron": Color(0.18, 0.15, 0.13)},
		"pat": "lava", "c2": Color(0.35, 0.1, 0.02), "c3": Color(1.0, 0.38, 0.06), "glow_k": 3.2, "glow": Color(1.0, 0.45, 0.1)},
	"pearl": {"name": "幻彩珠光", "price": 60000, "desc": "珍珠白底，换个角度看就变一种颜色",
		"pal": {"wood": Color(0.92, 0.92, 0.96), "lacquer": Color(0.92, 0.92, 0.96), "black": Color(0.5, 0.5, 0.55), "bronze": Color(0.95, 0.95, 0.97), "gold": Color(1.0, 0.9, 0.95), "iron": Color(0.8, 0.8, 0.85)},
		"pat": "pearl", "body_metal": 0.55, "body_rough": 0.18, "coat": 1.0, "trim_rough": 0.1, "glow": Color(0.8, 0.7, 1.0)},
	"circuit": {"name": "符阵回路", "price": 80000, "desc": "符阵器一样的黑色机身，发光的回路里扫过一道光",
		"pal": {"wood": Color(0.08, 0.09, 0.11), "lacquer": Color(0.08, 0.09, 0.11), "black": Color(0.05, 0.05, 0.06), "bronze": Color(0.2, 0.22, 0.25), "gold": Color(0.2, 0.85, 1.0), "iron": Color(0.14, 0.15, 0.17)},
		"pat": "circuit", "c2": Color(0.15, 0.4, 0.5), "c3": Color(0.2, 0.9, 1.0), "glow_k": 2.5, "body_metal": 0.6, "body_rough": 0.3, "glow": Color(0.2, 0.9, 1.0)},
	"dragon": {"name": "金龙", "price": 90000, "desc": "纯金龙鳞，一片一片刻出来的",
		"pal": {"wood": Color(1.0, 0.78, 0.3), "lacquer": Color(1.0, 0.78, 0.3), "bronze": Color(1.0, 0.85, 0.45), "gold": Color(1.0, 0.9, 0.55), "iron": Color(0.8, 0.6, 0.25), "black": Color(0.5, 0.33, 0.1)},
		"pat": "scales", "c2": Color(0.42, 0.26, 0.07), "body_metal": 1.0, "body_rough": 0.16, "trim_rough": 0.12, "glow": Color(1.0, 0.85, 0.4)},
	"star": {"name": "星河", "price": 160000, "desc": "深蓝星云在暗器上慢慢流动，星星一闪一闪",
		"pal": {"wood": Color(0.02, 0.03, 0.1), "lacquer": Color(0.02, 0.03, 0.1), "bronze": Color(0.5, 0.6, 1.0), "gold": Color(0.8, 0.85, 1.0), "iron": Color(0.1, 0.12, 0.25), "black": Color(0.01, 0.015, 0.05)},
		"pat": "galaxy", "c2": Color(0.35, 0.15, 0.6), "c3": Color(0.85, 0.9, 1.0), "glow_k": 2.0, "body_rough": 0.2, "coat": 1.0, "glow": Color(0.5, 0.7, 1.0)},
	# 熟练度皮肤（每把暗器自己练到 3 / 6 / 10 级）
	"steel": {"name": "精钢", "price": 0, "mastery": 3, "desc": "这把暗器熟练度 3 级解锁：拉丝精钢，金色包边",
		"pal": {"wood": Color(0.6, 0.62, 0.65), "lacquer": Color(0.6, 0.62, 0.65), "black": Color(0.22, 0.22, 0.24), "bronze": Color(0.9, 0.7, 0.35), "gold": Color(0.95, 0.75, 0.35), "iron": Color(0.45, 0.46, 0.48)},
		"pat": "brushed", "body_metal": 1.0, "body_rough": 0.3, "glow": Color(0.6, 0.9, 1.0)},
	"blackgold": {"name": "黑金", "price": 0, "mastery": 6, "desc": "这把暗器熟练度 6 级解锁：黑钢折叠纹，抛光金包边",
		"pal": {"wood": Color(0.12, 0.12, 0.13), "lacquer": Color(0.12, 0.12, 0.13), "black": Color(0.05, 0.05, 0.05), "bronze": Color(1.0, 0.78, 0.3), "gold": Color(1.0, 0.8, 0.35), "iron": Color(0.9, 0.7, 0.3)},
		"pat": "damascus", "c2": Color(0.03, 0.03, 0.035), "body_metal": 0.9, "body_rough": 0.28, "trim_pat": "plain", "trim_rough": 0.1, "glow": Color(1.0, 0.8, 0.35)},
	"master": {"name": "千机大师 · 流光", "price": 0, "mastery": 10, "desc": "这把暗器熟练度 10 级解锁：金身上流着金光",
		"pal": {"wood": Color(0.95, 0.75, 0.3), "lacquer": Color(0.95, 0.75, 0.3), "black": Color(0.25, 0.18, 0.08), "bronze": Color(1.0, 0.95, 0.85), "gold": Color(1.0, 0.95, 0.85), "iron": Color(0.9, 0.85, 0.75)},
		"pat": "flow", "c2": Color(1.0, 0.9, 0.5), "c3": Color(1.0, 0.82, 0.4), "glow_k": 2.2, "body_metal": 1.0, "body_rough": 0.15, "trim_rough": 0.08, "glow": Color(1.0, 0.85, 0.4)},
	# Boss 皮肤
	"mandala": {"name": "碧鳞", "price": 0, "boss": "mandala", "desc": "打败镜湖之主 · 千年碧鳞蛟解锁：紫色蛇身上流着绿光",
		"pal": {"wood": Color(0.3, 0.12, 0.35), "lacquer": Color(0.42, 0.1, 0.45), "bronze": Color(0.35, 0.75, 0.35), "gold": Color(0.6, 1.0, 0.4), "iron": Color(0.2, 0.15, 0.22)},
		"pat": "flow", "c2": Color(0.5, 0.2, 0.55), "c3": Color(0.7, 1.0, 0.4), "glow_k": 2.0, "body_metal": 0.3, "body_rough": 0.3, "coat": 0.8, "glow": Color(0.7, 1.0, 0.4)},
	"spider": {"name": "毒蛛", "price": 0, "boss": "spider", "desc": "打败落霞林之主 · 千目蛛母解锁：黑底上发光的红色蛛网",
		"pal": {"wood": Color(0.06, 0.045, 0.045), "lacquer": Color(0.1, 0.02, 0.03), "bronze": Color(0.6, 0.05, 0.08), "gold": Color(0.9, 0.2, 0.2), "iron": Color(0.12, 0.1, 0.1)},
		"pat": "web", "c2": Color(0.3, 0.02, 0.04), "c3": Color(1.0, 0.15, 0.2), "glow_k": 2.5, "body_rough": 0.5, "glow": Color(1.0, 0.2, 0.25)},
	"titan": {"name": "朱厌", "price": 0, "boss": "titan", "desc": "打败苍梧之王 · 朱厌解锁：岩石身躯，裂缝透着火光",
		"pal": {"wood": Color(0.3, 0.24, 0.2), "lacquer": Color(0.35, 0.27, 0.22), "bronze": Color(0.55, 0.5, 0.45), "gold": Color(1.0, 0.7, 0.3), "iron": Color(0.3, 0.28, 0.26)},
		"pat": "lava", "c2": Color(0.35, 0.2, 0.1), "c3": Color(1.0, 0.55, 0.15), "glow_k": 2.2, "glow": Color(1.0, 0.6, 0.2)},
	"frostdragon": {"name": "冰螭", "price": 0, "boss": "icedragon", "desc": "打败朔北之主 · 冰螭解锁：冰蓝龙鳞",
		"pal": {"wood": Color(0.82, 0.9, 1.0), "lacquer": Color(0.7, 0.85, 1.0), "bronze": Color(0.4, 0.7, 1.0), "gold": Color(0.6, 0.95, 1.0), "iron": Color(0.8, 0.88, 0.95)},
		"pat": "scales", "pat_black": "ice", "c2": Color(0.3, 0.5, 0.78), "c3": Color(0.5, 0.95, 1.0), "glow_k": 1.0, "body_metal": 0.85, "body_rough": 0.12, "glow": Color(0.5, 0.95, 1.0)},
	"abyss": {"name": "深海", "price": 0, "boss": "whale", "desc": "打败归墟之主 · 玄鲲解锁：深海的光纹在暗器上流动",
		"pal": {"wood": Color(0.03, 0.12, 0.2), "lacquer": Color(0.04, 0.2, 0.3), "bronze": Color(0.2, 0.6, 0.7), "gold": Color(0.4, 0.95, 0.9), "iron": Color(0.05, 0.15, 0.2)},
		"pat": "caustic", "c2": Color(0.05, 0.25, 0.35), "c3": Color(0.3, 1.0, 0.9), "glow_k": 1.5, "body_rough": 0.25, "coat": 1.0, "glow": Color(0.3, 1.0, 0.9)},
	# 猎灵录皮肤
	"lake": {"name": "湖光", "price": 0, "codex": "island", "desc": "集齐镜湖的猎灵录解锁：湖底的光纹",
		"pal": {"wood": Color(0.55, 0.75, 0.85), "lacquer": Color(0.35, 0.6, 0.8), "bronze": Color(0.95, 0.95, 1.0), "gold": Color(0.7, 0.95, 1.0), "iron": Color(0.5, 0.6, 0.7)},
		"pat": "caustic", "c2": Color(0.35, 0.6, 0.8), "c3": Color(0.85, 1.0, 1.0), "glow_k": 0.8, "body_metal": 0.5, "body_rough": 0.2, "glow": Color(0.6, 0.9, 1.0)},
	"sunset": {"name": "落霞", "price": 0, "codex": "forest", "desc": "集齐落霞林的猎灵录解锁：夕阳的渐变金属",
		"pal": {"wood": Color(0.95, 0.75, 0.3), "lacquer": Color(0.95, 0.75, 0.3), "bronze": Color(1.0, 0.75, 0.4), "gold": Color(1.0, 0.8, 0.45), "iron": Color(0.45, 0.25, 0.15), "black": Color(0.3, 0.1, 0.1)},
		"pat": "fade", "c2": Color(0.9, 0.35, 0.12), "c3": Color(0.45, 0.1, 0.25), "body_metal": 0.75, "body_rough": 0.22, "glow": Color(1.0, 0.6, 0.25)},
	"starwood": {"name": "苍梧", "price": 0, "codex": "deepforest", "desc": "集齐苍梧林海的猎灵录解锁：青色星云",
		"pal": {"wood": Color(0.03, 0.1, 0.12), "lacquer": Color(0.03, 0.12, 0.14), "bronze": Color(0.4, 0.8, 1.0), "gold": Color(0.5, 1.0, 0.95), "iron": Color(0.12, 0.2, 0.25)},
		"pat": "galaxy", "c2": Color(0.05, 0.35, 0.4), "c3": Color(0.5, 1.0, 0.95), "glow_k": 1.6, "body_rough": 0.25, "coat": 1.0, "glow": Color(0.3, 0.9, 1.0)},
	"aurora": {"name": "极光", "price": 0, "codex": "snow", "desc": "集齐朔北冰原的猎灵录解锁：一条条飘动的极光",
		"pal": {"wood": Color(0.06, 0.08, 0.14), "lacquer": Color(0.06, 0.08, 0.14), "bronze": Color(0.8, 0.6, 1.0), "gold": Color(0.6, 1.0, 0.85), "iron": Color(0.7, 0.75, 0.9)},
		"pat": "aurora", "c2": Color(0.3, 1.0, 0.6), "c3": Color(0.6, 0.4, 1.0), "glow_k": 2.0, "body_rough": 0.3, "coat": 1.0, "glow": Color(0.5, 1.0, 0.8)},
	"tide": {"name": "海潮", "price": 0, "codex": "sea", "desc": "集齐归墟的猎灵录解锁：碧海水纹，金色包边",
		"pal": {"wood": Color(0.05, 0.3, 0.4), "lacquer": Color(0.1, 0.45, 0.55), "bronze": Color(0.9, 0.85, 0.6), "gold": Color(1.0, 0.95, 0.7), "iron": Color(0.1, 0.25, 0.3)},
		"pat": "caustic", "c2": Color(0.1, 0.5, 0.6), "c3": Color(0.7, 1.0, 1.0), "glow_k": 1.2, "body_rough": 0.2, "coat": 1.0, "glow": Color(0.4, 1.0, 1.0)},
}
const GUN_SKIN_ORDER := ["default", "paint", "carbon", "jade", "chrome", "blood", "ice", "damascus", "shadow", "fade", "magma", "pearl", "circuit", "dragon", "star",
	"steel", "blackgold", "master", "mandala", "spider", "titan", "frostdragon", "abyss", "lake", "sunset", "starwood", "aurora", "tide"]

# ================================================================ 猎灵录：每张图的每种灵兽三颗星（在一张图多待的理由）
# ★ 猎杀 5 只；★★ 猎杀一只带词缀的；★★★ 猎杀一只千年以上的，或者它的精英（王）
# 每颗星永久：体力 +2、伤害 +0.5%。一张图的星星全部集齐，送这张图的专属暗器皮肤
const CODEX_KILLS := 5
const CODEX_MAP_SKIN := {"island": "lake", "forest": "sunset", "deepforest": "starwood", "snow": "aurora", "sea": "tide"}
# 装扮：长袍颜色、衣服上的点缀色、帽子（队友看到的样子，也是第一人称的袖子）
const OUTFITS := {
	"default": {"name": "素白长衫", "price": 0, "robe": Color(0.92, 0.92, 0.88), "hat": "", "desc": "新手修士的衣服"},
	"tang": {"name": "千机黑袍", "price": 1500, "robe": Color(0.09, 0.09, 0.12), "accent": Color(0.9, 0.7, 0.3), "hat": "douli", "desc": "黑袍金边，戴竹帽"},
	"flame": {"name": "赤焰袍", "price": 6000, "robe": Color(0.68, 0.1, 0.07), "accent": Color(1.0, 0.6, 0.2), "hat": "", "desc": "火红长袍"},
	"frost": {"name": "冰蓝袍", "price": 6000, "robe": Color(0.55, 0.75, 0.95), "accent": Color(0.92, 0.97, 1.0), "hat": "hood", "desc": "冰蓝长袍带兜帽"},
	"gold": {"name": "金甲", "price": 60000, "robe": Color(0.85, 0.63, 0.22), "accent": Color(1.0, 0.9, 0.5), "hat": "crown", "desc": "一身金甲，头戴金冠"},
	"sea": {"name": "归墟袍", "price": 0, "boss": "whale", "robe": Color(0.1, 0.4, 0.5), "accent": Color(0.5, 1.0, 0.9), "hat": "crown", "desc": "通关归墟解锁"},
}
const OUTFIT_ORDER := ["default", "tang", "flame", "frost", "gold", "sea"]


# ================================================================ 成就（J 或者暂停菜单里看）
# stat：Profile.stats 里的计数到 n 就完成；special：别的条件（World._ach_specials 里判断）
const ACHIEVEMENTS := [
	{"id": "kill_1", "name": "初次猎灵", "desc": "打死第一只灵兽", "stat": "kills", "n": 1, "reward": 50},
	{"id": "kill_100", "name": "百兽猎手", "desc": "打死 100 只灵兽", "stat": "kills", "n": 100, "reward": 1500},
	{"id": "kill_500", "name": "五百斩", "desc": "打死 500 只灵兽", "stat": "kills", "n": 500, "reward": 12000},
	{"id": "kill_2000", "name": "千兽猎王", "desc": "打死 2000 只灵兽", "stat": "kills", "n": 2000, "reward": 80000},
	{"id": "air_50", "name": "空中杀手", "desc": "空中击杀 50 只", "stat": "air_kills", "n": 50, "reward": 1200},
	{"id": "juggle_8", "name": "天女散花", "desc": "空中连击 8 下以上打死一只", "stat": "juggle8", "n": 1, "reward": 1500},
	{"id": "head_100", "name": "百步穿杨", "desc": "爆头击杀 100 只", "stat": "head_kills", "n": 100, "reward": 3000},
	{"id": "far_80", "name": "一击夺命", "desc": "80 米外打死一只", "stat": "far80", "n": 1, "reward": 2000},
	{"id": "affix_2", "name": "硬骨头", "desc": "打死一只带两个词缀的灵兽", "stat": "affix2", "n": 1, "reward": 1500},
	{"id": "elite_1", "name": "斩王", "desc": "打死第一只精英（王）", "stat": "elites", "n": 1, "reward": 800},
	{"id": "elite_30", "name": "王者克星", "desc": "打死 30 只精英", "stat": "elites", "n": 30, "reward": 30000},
	{"id": "boss_mandala", "name": "镜湖之主陨落", "desc": "击败镜湖之主 · 千年碧鳞蛟", "stat": "boss_mandala", "n": 1, "reward": 1000},
	{"id": "boss_spider", "name": "落霞林之主", "desc": "击败千目蛛母", "stat": "boss_spider", "n": 1, "reward": 4000},
	{"id": "boss_titan", "name": "撼山", "desc": "击败万年朱厌", "stat": "boss_titan", "n": 1, "reward": 12000},
	{"id": "boss_icedragon", "name": "屠龙", "desc": "击败万年冰螭", "stat": "boss_icedragon", "n": 1, "reward": 30000},
	{"id": "boss_whale", "name": "镇海", "desc": "击败十万年玄鲲", "stat": "boss_whale", "n": 1, "reward": 80000},
	{"id": "nohit_1", "name": "片叶不沾身", "desc": "一下都没挨，击败一位灵主", "stat": "nohit", "n": 1, "reward": 6000},
	{"id": "nohit_5", "name": "五岳无痕", "desc": "无伤击败灵主 5 次", "stat": "nohit", "n": 5, "reward": 60000},
	{"id": "pdodge_20", "name": "间不容发", "desc": "极限闪避 20 次", "stat": "perfect_dodges", "n": 20, "reward": 3000},
	{"id": "tide_20", "name": "守住兽潮", "desc": "在兽潮里打死 20 只", "stat": "tide_kills", "n": 20, "reward": 2500},
	{"id": "bone_1", "name": "第一块灵骨", "desc": "捡到一块灵骨", "stat": "bones", "n": 1, "reward": 600},
	{"id": "bone_6", "name": "六骨齐全", "desc": "六个部位都装上灵骨", "special": "bones6", "reward": 25000},
	{"id": "ring_1", "name": "第一灵环", "desc": "吸收第一个灵环", "special": "rings1", "reward": 200},
	{"id": "ring_5", "name": "五环加身", "desc": "吸收五个灵环", "special": "rings5", "reward": 8000},
	{"id": "ring_wan", "name": "万年灵环", "desc": "吸收一个万年灵环", "special": "wannian", "reward": 20000},
	{"id": "lv_20", "name": "金丹", "desc": "修炼到 20 级", "special": "lv20", "reward": 500},
	{"id": "lv_50", "name": "炼虚", "desc": "修炼到 50 级", "special": "lv50", "reward": 10000},
	{"id": "lv_80", "name": "渡劫", "desc": "修炼到 80 级", "special": "lv80", "reward": 40000},
	{"id": "god", "name": "飞升", "desc": "修炼到 100 级、吸收第十灵环", "special": "god", "reward": 200000},
	{"id": "bounty_10", "name": "赏金猎人", "desc": "完成 10 个悬赏", "stat": "bounties", "n": 10, "reward": 3000},
	{"id": "codex_1", "name": "图鉴大师", "desc": "集齐一张图的猎灵录", "stat": "codex_maps", "n": 1, "reward": 5000},
	{"id": "revive_5", "name": "救死扶伤", "desc": "把倒地的队友拉起来 5 次", "stat": "revives", "n": 5, "reward": 1500},
	{"id": "gull_10", "name": "海鸥克星", "desc": "打下 10 只海鸥", "stat": "gulls", "n": 10, "reward": 1500},
	{"id": "nest_1", "name": "捣毁巢穴", "desc": "打爆一个灵兽巢穴", "stat": "nests", "n": 1, "reward": 1000},
	{"id": "nest_20", "name": "巢穴克星", "desc": "打爆 20 个灵兽巢穴", "stat": "nests", "n": 20, "reward": 20000},
	{"id": "sell_50", "name": "千机阁贵客", "desc": "往收购箱卖 50 件东西", "stat": "sold", "n": 50, "reward": 2000},
	{"id": "arsenal", "name": "千机全套", "desc": "五把暗器同时拿在手里", "special": "arsenal", "reward": 20000},
	{"id": "skins_5", "name": "爱美的修士", "desc": "拥有 5 款暗器皮肤", "special": "skins5", "reward": 5000},
]


# ================================================================ 引魂索
const LURE := {
	"min_speed": 13.0, "max_speed": 30.0, "charge_time": 0.55, "up": 0.28,
	"gravity": 18.0, "bite_min": 0.9, "bite_max": 2.4, "bite_window": 1.1,
	"reel_time": 2.4,
	"launch_height": 7.5,
	"hurry_after": 2,
}

# ================================================================ 击杀加成（对应 How to Fish 的 Killscore）
const KILL_BONUS := {
	"air": 1.5, "headshot": 1.25, "juggle_step": 0.12, "juggle_max": 1.0, "far": 1.2, "far_dist": 25.0,
	"assist": 0.4,      # 帮忙打过的队友拿 40%
	"team_xp": 0.35,    # 没打的队友也拿一部分修为
}

# ================================================================ 修士等级与灵环
# 每 10 级是一个瓶颈，要吸收灵环才能继续升级。第 n 个灵环至少要这个年份：
# 一 十年 / 二三 百年 / 四五 千年 / 六~九 万年 / 十 十万年（归墟之主掉）。100 级 + 第十灵环 = 飞升（通关）
const RING_MIN_AGE := [0, 1, 1, 2, 2, 3, 3, 3, 3, 4]
const MAX_LEVEL := 100
const MAX_RINGS := 10

## 升一级要的修为：越往后越多（指数），每章大约 20 级
func xp_to_next(level: int) -> int:
	return int(40.0 * pow(1.065, level)) + 8 * level


# ================================================================ 数值：经验、金币、价格都按章节放大
# 每只灵兽属于哪一章（它住在哪张图）
const SPECIES_CH := {
	"rabbit": 1, "vine": 1, "bird": 1, "moth": 1,
	"wolf": 2, "rhino": 2, "ape": 2, "snake": 2,
	"stag": 3, "bat": 3, "raptor": 3, "spiderling": 3, "frog": 3,
	"husky": 4, "icedeer": 4, "icehorn": 4, "snowape": 4, "icefish": 4,
	"crab": 5, "gull": 5, "reeffish": 5, "shark": 5, "manta": 5,
}
const CH_REF_LEVEL := {1: 10, 2: 30, 3: 50, 4: 70, 5: 90}      # 这一章大概在多少级
const CH_MONEY := {1: 12.0, 2: 45.0, 3: 120.0, 4: 280.0, 5: 600.0}   # 这一章一只普通灵兽给多少灵石
const CH_PRICE := {1: 1.0, 2: 3.0, 3: 8.0, 4: 20.0, 5: 45.0}         # 道具、鱼饵价格倍数
const KILLS_PER_LEVEL := 12.0                                      # 这一章里大约杀多少只升一级
var cur_chapter := 1                                               # 当前地图是第几章（World 设置）


func species_rel(species: String, key: String) -> float:
	var ch := int(SPECIES_CH.get(species, 1))
	var tot := 0.0
	var n := 0
	for s in SPECIES_CH:
		if int(SPECIES_CH[s]) == ch:
			tot += float(BEASTS[s][key])
			n += 1
	return float(BEASTS[species][key]) / maxf(tot / maxi(n, 1), 0.001)


## 打死一只给多少修为：这一章的参考等级升一级要的修为 / 12 × 年份倍数 × 这种灵兽相对同章平均的强弱
func kill_xp(species: String, age: int) -> float:
	var ch := int(SPECIES_CH.get(species, 1))
	return float(xp_to_next(int(CH_REF_LEVEL[ch]))) / KILLS_PER_LEVEL * float(AGES[age]["xp"]) * species_rel(species, "xp")


func kill_money(species: String, age: int) -> float:
	var ch := int(SPECIES_CH.get(species, 1))
	return float(CH_MONEY[ch]) * float(AGES[age]["reward"]) * species_rel(species, "reward")


func item_price(id: String) -> int:
	return int(round(float(ITEMS[id]["price"]) * float(CH_PRICE.get(cur_chapter, 1.0))))


## 玩家伤害：等级（每级 +1.2%）；灵骨、猎灵录、升级、神通在别处乘
func level_damage(level: int) -> float:
	return 1.0 + level * 0.012


## 灵力护体：等级越高受到的伤害越少（每级 0.4%，90 级减 36%，最多 40%）
## 第十版加的：用户说"没有任何加防御的东西，渡劫修士也被打 1-2 下就死"
func level_armor(level: int) -> float:
	return minf(level * 0.004, 0.4)


## 联机时"猎杀 N 只"的任务按人数加量（每多一个人 +75%），不然几个人一起打太快
func quest_target(q: Dictionary, players: int) -> int:
	var n := int(q.get("n", 1))
	if str(q.get("type", "")) in ["kill", "hunt"] and players > 1:
		return ceili(n * (1.0 + 0.75 * (players - 1)))
	return n


func titles(level: int) -> String:
	var t := ["炼气", "筑基", "金丹", "元婴", "化神", "炼虚", "合体", "大乘", "渡劫", "真仙", "飞升者"]
	return t[clampi(level / 10, 0, t.size() - 1)]


# ================================================================ 神通
# 每个灵相 3 个灵环位，每个位有两个神通可选（吸收灵环时二选一）
# type：launch 炸飞 / root 定身 / mark 易伤 / pull 牵引 / beam 光束 / projectile 飞弹 /
#       rain 范围连击 / buff 增益 / heal 治疗 / shield 护盾 / dash 冲刺 / leap 跳跃
# target：self 以自己为中心 / aim 以准星指向的地面为中心 / dir 朝准星方向
const SKILLS := {
	# 青冥藤
	"lyc_root": {"name": "青冥缠绕", "type": "root", "target": "aim", "radius": 6.0, "dur": 3.5, "damage": 10.0, "cost": 25, "cd": 8.0, "desc": "准星处 6 米内的灵兽被青冥藤缠住，空中的也会被吊在原地"},
	"lyc_spike": {"name": "青冥突刺", "type": "launch", "target": "aim", "radius": 4.5, "damage": 30.0, "impulse": 9.0, "cost": 25, "cd": 7.0, "desc": "地面刺出青冥藤，把灵兽挑上天"},
	"lyc_mark": {"name": "青冥飞索", "type": "grapple", "target": "dir", "range": 40.0, "cost": 15, "cd": 5.0, "desc": "青冥藤缠住准星处，把自己拉过去（能上树、上崖、跨过水面）"},
	"lyc_pull": {"name": "青冥牵引", "type": "pull", "target": "aim", "radius": 12.0, "dur": 3.0, "force": 18.0, "cost": 30, "cd": 12.0, "desc": "把 12 米内的灵兽拉到一起"},
	"lyc_cage": {"name": "青冥囚笼", "type": "root", "target": "aim", "radius": 10.0, "dur": 5.0, "damage": 25.0, "cost": 50, "cd": 20.0, "desc": "大范围定身 5 秒"},
	"lyc_dance": {"name": "青冥藤灵", "type": "summon", "target": "aim", "kind": "vine", "dur": 12.0, "damage": 35.0, "rate": 0.8, "range": 14.0, "root": 0.8, "cost": 45, "cd": 20.0, "desc": "召唤一株青冥藤灵守在准星处 12 秒，不停抽打附近的灵兽并把它们缠住"},
	# 玄月镰
	"ld_whirl": {"name": "旋风斩", "type": "launch", "target": "self", "radius": 5.5, "damage": 45.0, "impulse": 8.0, "cost": 25, "cd": 7.0, "desc": "以自己为中心横扫，把身边灵兽砍飞"},
	"ld_scythe": {"name": "玄月之镰", "type": "beam", "target": "dir", "range": 40.0, "damage": 90.0, "pierce": 5, "cost": 25, "cd": 7.0, "desc": "一道贯穿 40 米的玄月镰光"},
	"ld_reap": {"name": "镰影步", "type": "blink", "target": "dir", "dist": 14.0, "stat": "dmg", "amount": 0.3, "dur": 4.0, "cost": 20, "cd": 6.0, "desc": "瞬移到准星方向 14 米外，之后 4 秒伤害 +30%"},
	"ld_fly": {"name": "飞镰", "type": "projectile", "target": "dir", "speed": 35.0, "radius": 4.0, "damage": 70.0, "impulse": 6.0, "cost": 30, "cd": 10.0, "desc": "掷出旋转飞镰，命中爆开"},
	"ld_doom": {"name": "玄月降临", "type": "blackhole", "target": "aim", "radius": 12.0, "pull_t": 2.0, "force": 20.0, "damage": 160.0, "impulse": 12.0, "cost": 55, "cd": 22.0, "desc": "准星处打开死亡旋涡，把灵兽拖进去再绞碎"},
	"ld_shadow": {"name": "镰刃风暴", "type": "orbit", "target": "self", "kind": "scythe", "n": 3, "radius": 3.5, "dur": 6.0, "damage": 45.0, "cost": 30, "cd": 12.0, "desc": "三把玄月镰绕身旋转 6 秒，贴身的灵兽被切"},
	# 灵葫
	"xc_heal": {"name": "灵葫回复", "type": "heal", "target": "self", "radius": 15.0, "amount": 45.0, "cost": 25, "cd": 10.0, "desc": "15 米内所有队友回复 45 体力"},
	"xc_boost": {"name": "灵葫增幅", "type": "buff", "target": "self", "radius": 15.0, "stat": "dmg", "amount": 0.2, "dur": 12.0, "team": true, "cost": 30, "cd": 18.0, "desc": "全队伤害 +20%，持续 12 秒"},
	"xc_regen": {"name": "镜像灵葫", "type": "buff", "target": "self", "radius": 15.0, "stat": "regen", "amount": 8.0, "dur": 10.0, "team": true, "cost": 30, "cd": 16.0, "desc": "全队每秒回复 8 体力"},
	"xc_fly": {"name": "飞行灵葫", "type": "fly", "target": "self", "radius": 15.0, "stat": "speed", "amount": 0.25, "dur": 8.0, "team": true, "cost": 30, "cd": 18.0, "desc": "自己飞 8 秒（空格上升、Ctrl 下降），全队移速 +25%"},
	"xc_big": {"name": "大灵葫", "type": "shield", "target": "self", "radius": 15.0, "amount": 60.0, "dur": 10.0, "team": true, "cost": 50, "cd": 24.0, "desc": "全队 60 点护盾"},
	"xc_boom": {"name": "爆炸灵葫", "type": "projectile", "target": "dir", "speed": 28.0, "radius": 6.0, "damage": 110.0, "impulse": 10.0, "cost": 45, "cd": 14.0, "desc": "扔出会爆炸的灵葫"},
	# 白虎
	"bh_guard": {"name": "白虎护身障", "type": "shield", "target": "self", "amount": 60.0, "dur": 8.0, "cost": 25, "cd": 12.0, "desc": "自己获得 60 点护盾"},
	"bh_wave": {"name": "白虎烈光波", "type": "beam", "target": "dir", "range": 35.0, "damage": 80.0, "pierce": 4, "cost": 25, "cd": 7.0, "desc": "一道贯穿的光波"},
	"bh_vajra": {"name": "白虎金刚变", "type": "giant", "target": "self", "scale": 1.5, "dr": 0.35, "dmg": 0.25, "dur": 10.0, "cost": 30, "cd": 18.0, "desc": "身体变大 1.5 倍 10 秒：受伤 -35%，伤害 +25%"},
	"bh_meteor": {"name": "白虎流星雨", "type": "rain", "target": "aim", "radius": 7.0, "damage": 40.0, "impulse": 6.0, "waves": 4, "cost": 35, "cd": 14.0, "desc": "准星处落下四波流星"},
	"bh_charge": {"name": "白虎冲击", "type": "dash", "target": "dir", "dist": 14.0, "damage": 80.0, "radius": 3.5, "impulse": 8.0, "cost": 40, "cd": 12.0, "desc": "猛冲撞飞路上的灵兽"},
	"bh_roar": {"name": "白虎咆哮", "type": "mark", "target": "self", "radius": 14.0, "dur": 10.0, "mult": 1.4, "cost": 45, "cd": 20.0, "desc": "身边灵兽受到伤害 +40%"},
	# 玄夜灵猫
	"ym_dash": {"name": "玄夜突刺", "type": "dash", "target": "dir", "dist": 10.0, "damage": 40.0, "radius": 2.5, "cost": 20, "cd": 5.0, "desc": "瞬间突进 10 米"},
	"ym_claw": {"name": "玄夜影爪", "type": "beam", "target": "dir", "range": 14.0, "damage": 110.0, "pierce": 2, "cost": 25, "cd": 7.0, "desc": "近距离高伤害爪击"},
	"ym_clone": {"name": "鬼影分身", "type": "summon", "target": "self", "kind": "cat", "dur": 8.0, "damage": 60.0, "rate": 0.5, "range": 12.0, "cost": 30, "cd": 16.0, "desc": "放出一只玄夜猫影 8 秒，飞快地抓 12 米内的灵兽"},
	"ym_slash": {"name": "玄夜斩", "type": "launch", "target": "aim", "radius": 4.5, "damage": 55.0, "impulse": 9.0, "cost": 30, "cd": 9.0, "desc": "在准星处斩出一道影刃，把灵兽挑飞"},
	"ym_hundred": {"name": "玄夜爪环", "type": "orbit", "target": "self", "kind": "claw", "n": 5, "radius": 3.0, "dur": 8.0, "damage": 40.0, "cost": 50, "cd": 18.0, "desc": "五道爪影绕身 8 秒，贴身的灵兽被撕碎"},
	"ym_ghost": {"name": "玄夜灵魂", "type": "invis", "target": "self", "stat": "speed", "amount": 0.5, "dur": 6.0, "cost": 30, "cd": 16.0, "desc": "隐身 6 秒：灵兽和 Boss 看不见你，移速 +50%"},
	# 朱雀
	"hf_fire": {"name": "朱雀火线", "type": "projectile", "target": "dir", "speed": 40.0, "radius": 4.5, "damage": 65.0, "impulse": 5.0, "burn": 8.0, "cost": 25, "cd": 6.0, "desc": "火球命中爆开，灼烧灵兽"},
	"hf_bath": {"name": "浴火", "type": "buff", "target": "self", "stat": "dr", "amount": 0.4, "stat2": "regen", "amount2": 10.0, "dur": 8.0, "cost": 25, "cd": 14.0, "desc": "8 秒内受伤 -40%，每秒回 10 体力"},
	"hf_wing": {"name": "凤翼天翔", "type": "leap", "target": "self", "height": 12.0, "radius": 6.0, "damage": 60.0, "impulse": 8.0, "cost": 30, "cd": 10.0, "desc": "冲上高空，落地炸飞周围灵兽"},
	"hf_rain": {"name": "火雨", "type": "rain", "target": "aim", "radius": 7.0, "damage": 35.0, "impulse": 3.0, "waves": 5, "burn": 6.0, "cost": 35, "cd": 14.0, "desc": "准星处降下火雨"},
	"hf_blast": {"name": "朱雀啸天击", "type": "projectile", "target": "dir", "speed": 30.0, "radius": 9.0, "damage": 160.0, "impulse": 12.0, "burn": 12.0, "cost": 55, "cd": 20.0, "desc": "巨大的朱雀火球"},
	"hf_rebirth": {"name": "涅槃", "type": "heal", "target": "self", "radius": 20.0, "amount": 100.0, "cost": 55, "cd": 30.0, "desc": "全队回满体力"},
	# 九层玲珑塔
	"qb_power": {"name": "力量增幅", "type": "buff", "target": "self", "radius": 20.0, "stat": "dmg", "amount": 0.25, "dur": 12.0, "team": true, "cost": 25, "cd": 16.0, "desc": "全队伤害 +25%"},
	"qb_speed": {"name": "速度增幅", "type": "buff", "target": "self", "radius": 20.0, "stat": "speed", "amount": 0.3, "dur": 12.0, "team": true, "cost": 25, "cd": 16.0, "desc": "全队移速和换弹 +30%"},
	"qb_soul": {"name": "灵力增幅", "type": "buff", "target": "self", "radius": 20.0, "stat": "soul", "amount": 1.0, "dur": 12.0, "team": true, "cost": 20, "cd": 20.0, "desc": "全队灵力恢复翻倍"},
	"qb_guard": {"name": "防御增幅", "type": "buff", "target": "self", "radius": 20.0, "stat": "dr", "amount": 0.3, "dur": 10.0, "team": true, "cost": 35, "cd": 20.0, "desc": "全队受伤 -30%，持续 10 秒"},
	"qb_seven": {"name": "玲珑宝光", "type": "buff", "target": "self", "radius": 25.0, "stat": "all", "amount": 0.35, "dur": 12.0, "team": true, "cost": 55, "cd": 28.0, "desc": "全队伤害、移速、换弹全部 +35%"},
	"qb_weak": {"name": "削弱", "type": "mark", "target": "self", "radius": 16.0, "dur": 10.0, "mult": 1.4, "cost": 40, "cd": 18.0, "desc": "16 米内灵兽受到伤害 +40%"},
	# 镇岳锤
	"ht_slam": {"name": "重锤", "type": "launch", "target": "aim", "radius": 5.5, "damage": 50.0, "impulse": 11.0, "cost": 25, "cd": 7.0, "desc": "锤子砸地，把一片灵兽震上天"},
	"ht_throw": {"name": "大岳锤", "type": "projectile", "target": "dir", "speed": 30.0, "radius": 5.0, "damage": 90.0, "impulse": 9.0, "cost": 30, "cd": 9.0, "desc": "扔出镇岳锤"},
	"ht_break": {"name": "破甲", "type": "mark", "target": "aim", "radius": 7.0, "dur": 10.0, "mult": 1.5, "cost": 30, "cd": 14.0, "desc": "准星处灵兽受到伤害 +50%（无视铁甲兕的甲）"},
	"ht_nine": {"name": "镇岳九式", "type": "buff", "target": "self", "stat": "dmg", "amount": 0.45, "dur": 8.0, "cost": 35, "cd": 16.0, "desc": "8 秒内伤害 +45%"},
	"ht_storm": {"name": "疾风锤法", "type": "rain", "target": "aim", "radius": 6.5, "damage": 60.0, "impulse": 10.0, "waves": 3, "cost": 50, "cd": 18.0, "desc": "三连砸，灵兽落不了地"},
	"ht_true": {"name": "镇岳真身", "type": "giant", "target": "self", "scale": 1.8, "dr": 0.5, "dmg": 0.4, "dur": 10.0, "cost": 50, "cd": 24.0, "desc": "镇岳锤真身：体型 ×1.8，受伤 -50%，伤害 +40%"},
	# 九天玄女
	"ls_light": {"name": "玄女圣光", "type": "beam", "target": "dir", "range": 50.0, "damage": 85.0, "pierce": 5, "cost": 25, "cd": 7.0, "desc": "贯穿的圣光"},
	"ls_shield": {"name": "圣光护盾", "type": "shield", "target": "self", "radius": 15.0, "amount": 40.0, "dur": 10.0, "team": true, "cost": 30, "cd": 16.0, "desc": "全队 40 点护盾"},
	"ls_wing": {"name": "玄女之翼", "type": "fly", "target": "self", "dur": 7.0, "cost": 25, "cd": 14.0, "desc": "展开六翼飞 7 秒（空格上升、Ctrl 下降），落地砸飞周围灵兽", "radius": 5.0, "damage": 50.0, "impulse": 7.0},
	"ls_judge": {"name": "审判", "type": "launch", "target": "aim", "radius": 7.0, "damage": 70.0, "impulse": 9.0, "cost": 35, "cd": 11.0, "desc": "准星处降下审判之光"},
	"ls_sword": {"name": "玄女圣剑", "type": "beam", "target": "dir", "range": 70.0, "damage": 200.0, "pierce": 8, "cost": 55, "cd": 20.0, "desc": "一剑贯穿"},
	"ls_domain": {"name": "神圣领域", "type": "domain", "target": "self", "radius": 18.0, "dur": 12.0, "dps": 50.0, "ally_stat": "all", "ally_amount": 0.3, "cost": 55, "cd": 28.0, "desc": "18 米神圣领域 12 秒：队友全属性 +30%，灵兽持续被圣光灼烧"},
	# ---- 第四、第五灵环 ----
	"lyc_wall": {"name": "青冥领域", "type": "domain", "target": "self", "radius": 12.0, "dur": 8.0, "dps": 40.0, "root_every": 2.0, "ally_stat": "dr", "ally_amount": 0.25, "cost": 60, "cd": 24.0, "desc": "脚下展开 12 米青冥领域 8 秒：灵兽持续掉血、每 2 秒被缠住一次；队友在里面受伤 -25%"},
	"lyc_storm": {"name": "青冥缠丝", "type": "chain", "target": "aim", "damage": 90.0, "jumps": 6, "range": 12.0, "root": 1.5, "cost": 55, "cd": 16.0, "desc": "一根青冥丝从准星处连到最多 7 只灵兽，每只都被缠住"},
	"lyc_king": {"name": "青冥帝 · 万藤归一", "type": "blackhole", "target": "aim", "radius": 13.0, "pull_t": 2.2, "force": 22.0, "damage": 300.0, "impulse": 14.0, "cost": 75, "cd": 30.0, "desc": "准星处万藤聚合，把 13 米内的灵兽全部拖到一起，2 秒后炸开"},
	"lyc_life": {"name": "青冥生命", "type": "heal", "target": "self", "radius": 25.0, "amount": 120.0, "cost": 70, "cd": 32.0, "desc": "全队回复 120 体力"},
	"ld_moon": {"name": "血月之镰", "type": "beam", "target": "dir", "range": 60.0, "damage": 260.0, "pierce": 8, "cost": 60, "cd": 18.0, "desc": "一道血色镰光"},
	"ld_harvest": {"name": "灵魂收割场", "type": "domain", "target": "aim", "radius": 12.0, "dur": 8.0, "dps": 70.0, "mult": 1.4, "cost": 60, "cd": 24.0, "desc": "准星处 12 米收割场 8 秒：灵兽持续掉血，受到伤害 +40%"},
	"ld_god": {"name": "玄月镰影", "type": "summon", "target": "self", "kind": "scythe", "dur": 12.0, "damage": 90.0, "rate": 0.6, "range": 16.0, "cost": 75, "cd": 30.0, "desc": "一把巨镰浮在身边 12 秒，自动劈砍 16 米内的灵兽"},
	"ld_fury": {"name": "嗜血狂镰", "type": "empower", "target": "self", "kind": "bleed", "dur": 12.0, "frac": 0.6, "cost": 70, "cd": 30.0, "desc": "12 秒内暗器命中让灵兽流血（额外 60% 伤害），打中还给自己回血"},
	"xc_feast": {"name": "灵葫补给站", "type": "summon", "target": "self", "kind": "sausage", "dur": 14.0, "damage": 30.0, "rate": 1.0, "range": 12.0, "heal": 18.0, "cost": 60, "cd": 26.0, "desc": "放下一根会发光的大灵葫 14 秒：每秒给 10 米内队友回血，还会砸附近的灵兽"},
	"xc_power": {"name": "灵葫结界", "type": "domain", "target": "self", "radius": 14.0, "dur": 10.0, "dps": 30.0, "ally_stat": "dmg", "ally_amount": 0.4, "cost": 60, "cd": 26.0, "desc": "14 米结界 10 秒：队友伤害 +40%，灵兽持续掉血"},
	"xc_giant": {"name": "灵葫护卫环", "type": "orbit", "target": "self", "kind": "sausage", "n": 4, "radius": 3.2, "dur": 12.0, "damage": 60.0, "cost": 75, "cd": 30.0, "desc": "四根灵葫绕身转 12 秒，撞飞贴身的灵兽"},
	"xc_nuke": {"name": "灵葫黑洞", "type": "blackhole", "target": "aim", "radius": 14.0, "pull_t": 2.4, "force": 24.0, "damage": 280.0, "impulse": 14.0, "cost": 75, "cd": 30.0, "desc": "巨型灵葫变成黑洞，吸住 14 米内的灵兽然后爆炸"},
	"bh_tiger": {"name": "白虎魂灵", "type": "summon", "target": "self", "kind": "tiger", "dur": 14.0, "damage": 140.0, "rate": 1.0, "range": 18.0, "impulse": 7.0, "cost": 60, "cd": 26.0, "desc": "召唤白虎魂灵 14 秒，扑向 18 米内的灵兽，一扑一个"},
	"bh_body": {"name": "白虎真身", "type": "giant", "target": "self", "scale": 2.2, "dr": 0.6, "dmg": 0.5, "dur": 12.0, "cost": 60, "cd": 28.0, "desc": "化身巨虎 12 秒：体型 ×2.2，受伤 -60%，伤害 +50%"},
	"bh_king": {"name": "白虎流星雨·极", "type": "rain", "target": "aim", "radius": 11.0, "damage": 100.0, "impulse": 9.0, "waves": 6, "cost": 75, "cd": 30.0, "desc": "六轮流星"},
	"bh_rage": {"name": "啸风白虎", "type": "empower", "target": "self", "kind": "explode", "dur": 12.0, "frac": 0.45, "cost": 70, "cd": 32.0, "desc": "12 秒内每一发暗器命中都会炸开（范围 3.5 米，额外 45% 伤害）"},
	"ym_blink": {"name": "玄夜瞬影", "type": "blink", "target": "dir", "dist": 18.0, "damage": 160.0, "radius": 3.5, "stat": "crit", "amount": 1.0, "dur": 3.0, "cost": 50, "cd": 10.0, "desc": "瞬移 18 米，路上的灵兽受重创，之后 3 秒每发都算爆头"},
	"ym_night": {"name": "玄夜夜", "type": "domain", "target": "aim", "radius": 16.0, "dur": 10.0, "dps": 35.0, "mult": 1.55, "cost": 60, "cd": 24.0, "desc": "准星处降下 16 米黑夜 10 秒：灵兽持续掉血，受到伤害 +55%"},
	"ym_true": {"name": "玄夜真身", "type": "empower", "target": "self", "kind": "chain", "dur": 12.0, "frac": 0.6, "cost": 70, "cd": 32.0, "desc": "12 秒内每一发命中都会弹到旁边两只灵兽（60% 伤害）"},
	"ym_storm": {"name": "玄夜连爪", "type": "chain", "target": "aim", "damage": 150.0, "jumps": 10, "range": 13.0, "cost": 75, "cd": 26.0, "desc": "爪影在 11 只灵兽之间连跳"},
	"hf_meteor": {"name": "朱雀魂灵", "type": "summon", "target": "self", "kind": "phoenix", "dur": 14.0, "damage": 110.0, "rate": 0.9, "range": 24.0, "burn": 14.0, "cost": 60, "cd": 22.0, "desc": "召唤一只朱雀在头顶盘旋 14 秒，朝 24 米内的灵兽吐火球"},
	"hf_wall": {"name": "朱雀火域", "type": "domain", "target": "aim", "radius": 12.0, "dur": 10.0, "dps": 80.0, "burn": 20.0, "cost": 60, "cd": 24.0, "desc": "准星处 12 米火海 10 秒，灵兽被烧"},
	"hf_true": {"name": "朱雀真身", "type": "leap", "target": "self", "height": 20.0, "radius": 12.0, "damage": 260.0, "impulse": 12.0, "cost": 75, "cd": 30.0, "desc": "化身朱雀冲天，落地烧毁一片"},
	"hf_sun": {"name": "烈阳", "type": "blackhole", "target": "aim", "radius": 14.0, "pull_t": 2.2, "force": 22.0, "damage": 340.0, "impulse": 15.0, "burn": 30.0, "cost": 75, "cd": 30.0, "desc": "准星处升起一颗小太阳，把灵兽吸过去再爆燃"},
	"qb_break": {"name": "玲珑破界", "type": "domain", "target": "aim", "radius": 16.0, "dur": 12.0, "dps": 20.0, "mult": 1.7, "cost": 60, "cd": 26.0, "desc": "准星处 16 米玲珑结界 12 秒，里面的灵兽受到伤害 +70%"},
	"qb_wall": {"name": "玲珑宝塔", "type": "summon", "target": "self", "kind": "tower", "dur": 16.0, "damage": 100.0, "rate": 0.8, "range": 26.0, "heal": 10.0, "cost": 60, "cd": 26.0, "desc": "放下一座九层玲珑塔 16 秒：射光打 26 米内的灵兽，每秒给身边队友回血"},
	"qb_nine": {"name": "九层玲珑", "type": "buff", "target": "self", "radius": 30.0, "stat": "all", "amount": 0.55, "dur": 14.0, "team": true, "cost": 80, "cd": 34.0, "desc": "全队伤害、移速、换弹 +55%"},
	"qb_heal": {"name": "玲珑之光", "type": "heal", "target": "self", "radius": 30.0, "amount": 160.0, "cost": 70, "cd": 30.0, "desc": "全队回复 160 体力"},
	"ht_quake": {"name": "镇岳震", "type": "launch", "target": "self", "radius": 14.0, "damage": 220.0, "impulse": 14.0, "cost": 60, "cd": 20.0, "desc": "一锤砸地，把周围 14 米全震上天"},
	"ht_break2": {"name": "镇岳引力", "type": "blackhole", "target": "aim", "radius": 16.0, "pull_t": 2.4, "force": 26.0, "damage": 420.0, "impulse": 16.0, "cost": 60, "cd": 24.0, "desc": "镇岳锤砸出引力场，把 16 米内的灵兽拖过来再一锤砸飞"},
	"ht_nine2": {"name": "镇岳九式 · 附体", "type": "empower", "target": "self", "kind": "quake", "dur": 12.0, "frac": 0.7, "cost": 70, "cd": 30.0, "desc": "12 秒内每一发命中都震出冲击波（范围 4.5 米，额外 70% 伤害）"},
	"ht_fall": {"name": "天锤陨落", "type": "projectile", "target": "dir", "speed": 26.0, "radius": 13.0, "damage": 340.0, "impulse": 15.0, "cost": 75, "cd": 30.0, "desc": "镇岳锤化成陨石砸下"},
	"ls_holy": {"name": "圣光链", "type": "chain", "target": "aim", "damage": 150.0, "jumps": 8, "range": 14.0, "cost": 60, "cd": 20.0, "desc": "圣光在 9 只灵兽之间连锁"},
	"ls_bless": {"name": "玄女祝福", "type": "heal", "target": "self", "radius": 30.0, "amount": 160.0, "cost": 60, "cd": 26.0, "desc": "全队回复 160 体力"},
	"ls_god": {"name": "玄女神剑", "type": "beam", "target": "dir", "range": 90.0, "damage": 420.0, "pierce": 12, "cost": 80, "cd": 30.0, "desc": "一剑贯穿 90 米"},
	"ls_true": {"name": "玄女真身", "type": "summon", "target": "self", "kind": "angel", "dur": 16.0, "damage": 160.0, "rate": 0.7, "range": 30.0, "cost": 80, "cd": 34.0, "desc": "召唤一位玄女真身在身边 16 秒，用圣光射 30 米内的灵兽"},
	# ---- 万年灵环（第六~九环）和十万年灵环（第十环，神技）----
	"lyc_net": {"name": "青冥荆棘环", "type": "orbit", "target": "self", "kind": "thorn", "n": 6, "radius": 4.0, "dur": 10.0, "damage": 120.0, "cost": 80, "cd": 28.0, "desc": "六根青冥荆棘绕着你转 10 秒，碰到的灵兽被扎"},
	"lyc_thorn": {"name": "青冥附体", "type": "empower", "target": "self", "kind": "root", "dur": 12.0, "frac": 0.5, "cost": 80, "cd": 30.0, "desc": "12 秒内暗器打中的灵兽被缠住，并多受 50% 伤害"},
	"lyc_shen": {"name": "青冥帝 · 神降", "shen": true, "type": "launch", "target": "aim", "radius": 24.0, "damage": 1800.0, "impulse": 16.0, "cost": 100, "cd": 45.0, "desc": "神技：青冥帝真身降临，一大片全部挑飞"},
	"ld_hell": {"name": "地狱之镰", "type": "beam", "target": "dir", "range": 90.0, "damage": 900.0, "pierce": 20, "cost": 85, "cd": 26.0, "desc": "一道贯穿 90 米的地狱镰光"},
	"ld_step": {"name": "玄月连斩", "type": "chain", "target": "aim", "damage": 400.0, "jumps": 8, "range": 14.0, "cost": 80, "cd": 18.0, "desc": "镰光从准星处连斩 9 只灵兽"},
	"ld_shen": {"name": "玄月神镰", "shen": true, "type": "rain", "target": "aim", "radius": 18.0, "damage": 700.0, "impulse": 12.0, "waves": 7, "cost": 100, "cd": 45.0, "desc": "神技：七轮玄月镰影横扫一大片"},
	"xc_feast2": {"name": "灵葫神宴", "type": "heal", "target": "self", "radius": 40.0, "amount": 400.0, "cost": 85, "cd": 30.0, "desc": "40 米内全队回复 400 体力"},
	"xc_rain2": {"name": "灵葫雨 · 极", "type": "rain", "target": "aim", "radius": 14.0, "damage": 300.0, "impulse": 13.0, "waves": 6, "cost": 85, "cd": 28.0, "desc": "六轮爆炸灵葫从天而降"},
	"xc_shen": {"name": "灵葫之神", "shen": true, "type": "buff", "target": "self", "radius": 40.0, "stat": "all", "amount": 0.8, "dur": 16.0, "team": true, "cost": 100, "cd": 45.0, "desc": "神技：全队伤害、移速、换弹 +80%，持续 16 秒"},
	"bh_king2": {"name": "白虎灭世", "type": "beam", "target": "dir", "range": 90.0, "damage": 1100.0, "pierce": 15, "cost": 85, "cd": 26.0, "desc": "灭世光波贯穿 90 米"},
	"bh_giant2": {"name": "白虎领域", "type": "domain", "target": "self", "radius": 16.0, "dur": 10.0, "dps": 150.0, "mult": 1.3, "ally_stat": "dr", "ally_amount": 0.35, "cost": 85, "cd": 32.0, "desc": "16 米白虎领域 10 秒：灵兽持续掉血、受伤 +30%，队友受伤 -35%"},
	"bh_shen": {"name": "白虎之神", "shen": true, "type": "launch", "target": "self", "radius": 22.0, "damage": 2000.0, "impulse": 16.0, "cost": 100, "cd": 45.0, "desc": "神技：白虎神一声怒吼，22 米全部震飞"},
	"ym_shadow2": {"name": "玄夜万影", "type": "rain", "target": "aim", "radius": 14.0, "damage": 320.0, "impulse": 7.0, "waves": 9, "cost": 85, "cd": 28.0, "desc": "九轮玄夜爪影"},
	"ym_blink2": {"name": "玄夜神行", "type": "blink", "target": "dir", "dist": 30.0, "damage": 900.0, "radius": 5.0, "stat": "crit", "amount": 1.0, "dur": 5.0, "cost": 80, "cd": 16.0, "desc": "瞬移 30 米重创路上的灵兽，之后 5 秒每发都是爆头"},
	"ym_shen": {"name": "玄夜之神", "shen": true, "type": "buff", "target": "self", "stat": "all", "amount": 0.9, "stat2": "crit", "amount2": 1.0, "dur": 12.0, "cost": 100, "cd": 45.0, "desc": "神技：12 秒内伤害、移速 +90%，每一发都是爆头"},
	"hf_sky": {"name": "朱雀火环", "type": "orbit", "target": "self", "kind": "fire", "n": 6, "radius": 5.0, "dur": 12.0, "damage": 180.0, "burn": 30.0, "cost": 85, "cd": 28.0, "desc": "六团朱雀火绕身 12 秒，烧穿靠近的灵兽"},
	"hf_wing2": {"name": "涅槃之焰", "type": "empower", "target": "self", "kind": "burn", "dur": 14.0, "frac": 0.6, "cost": 85, "cd": 28.0, "desc": "14 秒内暗器命中点燃灵兽，还会溅射火焰"},
	"hf_shen": {"name": "朱雀之神", "shen": true, "type": "projectile", "target": "dir", "speed": 30.0, "radius": 20.0, "damage": 2400.0, "impulse": 18.0, "burn": 60.0, "cost": 100, "cd": 45.0, "desc": "神技：化身朱雀撞出去，炸出 20 米火海"},
	"qb_nine2": {"name": "玲珑光环", "type": "orbit", "target": "self", "kind": "gem", "n": 9, "radius": 4.0, "dur": 14.0, "damage": 150.0, "cost": 85, "cd": 32.0, "desc": "九颗宝珠绕身 14 秒"},
	"qb_break2": {"name": "玲珑折光", "type": "chain", "target": "aim", "damage": 250.0, "jumps": 12, "range": 15.0, "mult": 1.6, "cost": 85, "cd": 30.0, "desc": "一道光在 13 只灵兽之间折射，被照到的受到伤害 +60%"},
	"qb_shen": {"name": "玲珑塔之神", "shen": true, "type": "heal", "target": "self", "radius": 50.0, "amount": 999.0, "cost": 100, "cd": 45.0, "desc": "神技：50 米内全队回满体力"},
	"ht_true2": {"name": "镇岳锤灵", "type": "summon", "target": "self", "kind": "hammer", "dur": 14.0, "damage": 400.0, "rate": 1.4, "range": 20.0, "radius": 5.0, "impulse": 12.0, "cost": 85, "cd": 32.0, "desc": "一柄巨锤浮在身边 14 秒，自己砸向 20 米内的灵兽（范围伤害）"},
	"ht_storm2": {"name": "锤影环", "type": "orbit", "target": "self", "kind": "hammer", "n": 4, "radius": 5.0, "dur": 12.0, "damage": 300.0, "cost": 85, "cd": 28.0, "desc": "四把锤影绕身 12 秒"},
	"ht_shen": {"name": "镇岳神锤", "shen": true, "type": "projectile", "target": "dir", "speed": 26.0, "radius": 22.0, "damage": 2600.0, "impulse": 18.0, "cost": 100, "cd": 45.0, "desc": "神技：镇岳锤化飞升锤砸下，22 米寸草不生"},
	"ls_judge2": {"name": "玄女审判 · 极", "type": "rain", "target": "aim", "radius": 16.0, "damage": 450.0, "impulse": 10.0, "waves": 6, "cost": 85, "cd": 28.0, "desc": "六道审判圣光"},
	"ls_wing2": {"name": "九天光刃", "type": "orbit", "target": "self", "kind": "feather", "n": 6, "radius": 4.5, "dur": 12.0, "damage": 250.0, "cost": 85, "cd": 28.0, "desc": "六片光羽绕身 12 秒"},
	"ls_shen": {"name": "玄女之神", "shen": true, "type": "beam", "target": "dir", "range": 150.0, "damage": 3000.0, "pierce": 30, "cost": 100, "cd": 45.0, "desc": "神技：玄女神剑一剑贯穿 150 米"},
}

# 每个灵相的神通树：第 1/2/3/4/5 灵环各两个选项
const SKILL_TREE := {
	"lyc": [["lyc_root", "lyc_spike"], ["lyc_mark", "lyc_pull"], ["lyc_cage", "lyc_dance"], ["lyc_wall", "lyc_storm"], ["lyc_king", "lyc_life"], ["lyc_net", "lyc_thorn"], ["lyc_shen"]],
	"ld": [["ld_whirl", "ld_scythe"], ["ld_reap", "ld_fly"], ["ld_doom", "ld_shadow"], ["ld_moon", "ld_harvest"], ["ld_god", "ld_fury"], ["ld_hell", "ld_step"], ["ld_shen"]],
	"xc": [["xc_heal", "xc_boost"], ["xc_regen", "xc_fly"], ["xc_big", "xc_boom"], ["xc_feast", "xc_power"], ["xc_giant", "xc_nuke"], ["xc_feast2", "xc_rain2"], ["xc_shen"]],
	"bh": [["bh_guard", "bh_wave"], ["bh_vajra", "bh_meteor"], ["bh_charge", "bh_roar"], ["bh_tiger", "bh_body"], ["bh_king", "bh_rage"], ["bh_king2", "bh_giant2"], ["bh_shen"]],
	"ym": [["ym_dash", "ym_claw"], ["ym_clone", "ym_slash"], ["ym_hundred", "ym_ghost"], ["ym_blink", "ym_night"], ["ym_true", "ym_storm"], ["ym_shadow2", "ym_blink2"], ["ym_shen"]],
	"hf": [["hf_fire", "hf_bath"], ["hf_wing", "hf_rain"], ["hf_blast", "hf_rebirth"], ["hf_meteor", "hf_wall"], ["hf_true", "hf_sun"], ["hf_sky", "hf_wing2"], ["hf_shen"]],
	"qb": [["qb_power", "qb_speed"], ["qb_soul", "qb_guard"], ["qb_seven", "qb_weak"], ["qb_break", "qb_wall"], ["qb_nine", "qb_heal"], ["qb_nine2", "qb_break2"], ["qb_shen"]],
	"ht": [["ht_slam", "ht_throw"], ["ht_break", "ht_nine"], ["ht_storm", "ht_true"], ["ht_quake", "ht_break2"], ["ht_nine2", "ht_fall"], ["ht_true2", "ht_storm2"], ["ht_shen"]],
	"ls": [["ls_light", "ls_shield"], ["ls_wing", "ls_judge"], ["ls_sword", "ls_domain"], ["ls_holy", "ls_bless"], ["ls_god", "ls_true"], ["ls_judge2", "ls_wing2"], ["ls_shen"]],
}
const SKILL_SLOTS := 3         # 三个神通槽：Q / E / F（在 K 灵相面板里选哪三个神通装上去）
# 神通由 灵相 + 灵兽种类 + 年份 决定，吸收之前不告诉你是什么：
# 同一个灵相吸收同一种灵兽，永远得到同一个神通；年份越高，从越强的一档里出（十年 → 第 1~2 档，百年 → 2~3，千年 → 4~5，万年 → 第 6 档，十万年 → 神技）
const AGE_TIERS := [[0, 1], [1, 2], [3, 4], [5], [6], [6]]


## 神通在第几档（0 十年~百年 … 5 万年 6 神技），特效按档次加层
func skill_tier(sid: String) -> int:
	for tree in SKILL_TREE.values():
		for t in (tree as Array).size():
			if sid in tree[t]:
				return t
	return 0


func skill_for(wid: String, species: String, age: int, owned: Array) -> String:
	var tree: Array = SKILL_TREE.get(wid, SKILL_TREE["lyc"])
	var cands: Array = []
	for t in AGE_TIERS[clampi(age, 0, AGE_TIERS.size() - 1)]:
		cands.append_array(tree[t])
	var h := absi(hash(wid + "|" + species))
	for k in cands.size():
		var sid: String = cands[(h + k) % cands.size()]
		if not sid in owned:
			return sid
	# 这一档都有了：从别的档里找一个没有的
	for tier in tree:
		for sid in tier:
			if not sid in owned:
				return str(sid)
	return str(cands[h % cands.size()])
const RING_NAMES := ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]

# ================================================================ 灵骨
# 六个部位各装一块（K 打开灵相面板换）。灵骨兽必掉、千年灵兽小概率掉、Boss 必掉。
# 地上的灵骨谁都能捡，也能丢给队友，或者丢进收购箱卖掉。
# 存档里一块灵骨写成 "id@年份"，百年 ×1.5、千年 ×2.2（二段跳、滑翔这种开关型的不变）
# stat：hp 体力 / soul 灵力 / dmg 伤害 / headshot 爆头 / dr 减伤 / speed 移速 / reload 换弹 / recoil 后坐 /
#       jump 跳跃高度 / djump 二段跳 / glide 滑翔 / breath 水下憋气 / swim 游泳 / regen 回血 / sell 卖价
const BONE_SLOTS := ["head", "torso", "larm", "rarm", "lleg", "rleg"]
const BONE_SLOT_NAMES := {"head": "头骨", "torso": "躯干骨", "larm": "左臂骨", "rarm": "右臂骨", "lleg": "左腿骨", "rleg": "右腿骨"}
const BONE_AGE_MULT := [1.0, 1.5, 2.2, 3.2, 4.5, 6.0]
const BONE_SWITCH := ["djump", "glide"]
const BONES := {
	# ---- 灵兽灵骨
	"rabbit_leg": {"name": "玉兔左腿骨", "slot": "lleg", "stat": "jump", "amount": 0.25, "beast": "rabbit"},
	"vine_torso": {"name": "噬灵藤躯干骨", "slot": "torso", "stat": "regen", "amount": 1.5, "beast": "vine"},
	"bird_arm": {"name": "青鸾左臂骨", "slot": "larm", "stat": "glide", "amount": 1.0, "stat2": "speed", "amount2": 0.05, "beast": "bird"},
	"moth_head": {"name": "月光蛾头骨", "slot": "head", "stat": "soul", "amount": 20.0, "beast": "moth"},
	"wolf_leg": {"name": "追风狼右腿骨", "slot": "rleg", "stat": "speed", "amount": 0.1, "beast": "wolf"},
	"rhino_torso": {"name": "铁甲兕躯干骨", "slot": "torso", "stat": "dr", "amount": 0.1, "stat2": "hp", "amount2": 15.0, "beast": "rhino"},
	"ape_arm": {"name": "山魈右臂骨", "slot": "rarm", "stat": "dmg", "amount": 0.08, "beast": "ape"},
	"snake_head": {"name": "碧鳞蛇头骨", "slot": "head", "stat": "headshot", "amount": 0.1, "beast": "snake"},
	"stag_head": {"name": "夫诸头骨", "slot": "head", "stat": "headshot", "amount": 0.12, "stat2": "soul", "amount2": 10.0, "beast": "stag"},
	"bat_arm": {"name": "夜翼蝠左臂骨", "slot": "larm", "stat": "glide", "amount": 1.0, "stat2": "dmg", "amount2": 0.04, "beast": "bat"},
	"raptor_leg": {"name": "疾爪蜥左腿骨", "slot": "lleg", "stat": "djump", "amount": 1.0, "beast": "raptor"},
	"spider_arm": {"name": "地穴毒蛛右臂骨", "slot": "rarm", "stat": "reload", "amount": 0.12, "beast": "spiderling"},
	"frog_leg": {"name": "碧眼蟾右腿骨", "slot": "rleg", "stat": "jump", "amount": 0.4, "stat2": "swim", "amount2": 0.2, "beast": "frog"},
	"husky_leg": {"name": "雪原狼左腿骨", "slot": "lleg", "stat": "speed", "amount": 0.12, "beast": "husky"},
	"icedeer_head": {"name": "冰角鹿头骨", "slot": "head", "stat": "soul", "amount": 30.0, "beast": "icedeer"},
	"icehorn_torso": {"name": "冰甲龙躯干骨", "slot": "torso", "stat": "dr", "amount": 0.15, "beast": "icehorn"},
	"snowape_arm": {"name": "雪猱右臂骨", "slot": "rarm", "stat": "dmg", "amount": 0.1, "stat2": "recoil", "amount2": 0.1, "beast": "snowape"},
	"icefish_torso": {"name": "冰鳞鱼躯干骨", "slot": "torso", "stat": "breath", "amount": 12.0, "stat2": "swim", "amount2": 0.4, "beast": "icefish"},
	"crab_arm": {"name": "铁钳蟹左臂骨", "slot": "larm", "stat": "recoil", "amount": 0.2, "beast": "crab"},
	"gull_head": {"name": "贪金鸥头骨", "slot": "head", "stat": "sell", "amount": 0.2, "beast": "gull"},
	"reef_head": {"name": "彩鳞鱼头骨", "slot": "head", "stat": "breath", "amount": 10.0, "beast": "reeffish"},
	"shark_torso": {"name": "深海狂鲨躯干骨", "slot": "torso", "stat": "swim", "amount": 0.6, "stat2": "breath", "amount2": 15.0, "beast": "shark"},
	"manta_arm": {"name": "幽灵鳐左臂骨", "slot": "larm", "stat": "glide", "amount": 1.0, "stat2": "soul", "amount2": 15.0, "beast": "manta"},
	# ---- Boss 灵骨（都是千年的）
	"mandala_skull": {"name": "碧鳞蛟头骨", "slot": "head", "stat": "headshot", "amount": 0.08, "stat2": "soul", "amount2": 10.0},
	"mandala_spine": {"name": "碧鳞蛟躯干骨", "slot": "torso", "stat": "hp", "amount": 15.0, "stat2": "regen", "amount2": 1.0},
	"spider_leg": {"name": "千目蛛母蛛足", "slot": "rleg", "stat": "djump", "amount": 1.0, "stat2": "dmg", "amount2": 0.04},
	"spider_eye": {"name": "千目蛛母之眼", "slot": "head", "stat": "soul", "amount": 12.0, "stat2": "headshot", "amount2": 0.05},
	"titan_arm": {"name": "朱厌右臂骨", "slot": "rarm", "stat": "dmg", "amount": 0.07, "stat2": "recoil", "amount2": 0.08},
	"titan_heart": {"name": "朱厌躯干骨", "slot": "torso", "stat": "hp", "amount": 25.0, "stat2": "dr", "amount2": 0.05},
	"dragon_wing": {"name": "冰螭左臂骨", "slot": "larm", "stat": "glide", "amount": 1.0, "stat2": "headshot", "amount2": 0.08},
	"dragon_scale": {"name": "冰螭头骨", "slot": "head", "stat": "soul", "amount": 18.0, "stat2": "dmg", "amount2": 0.04},
	"whale_bone": {"name": "玄鲲右腿骨", "slot": "rleg", "stat": "swim", "amount": 0.5, "stat2": "speed", "amount2": 0.06},
	"whale_heart": {"name": "玄鲲躯干骨", "slot": "torso", "stat": "hp", "amount": 35.0, "stat2": "breath", "amount2": 20.0},
}
const BONE_BY_BEAST := {
	"rabbit": "rabbit_leg", "vine": "vine_torso", "bird": "bird_arm", "moth": "moth_head", "wolf": "wolf_leg",
	"rhino": "rhino_torso", "ape": "ape_arm", "snake": "snake_head", "stag": "stag_head", "bat": "bat_arm",
	"raptor": "raptor_leg", "spiderling": "spider_arm", "frog": "frog_leg", "husky": "husky_leg",
	"icedeer": "icedeer_head", "icehorn": "icehorn_torso", "snowape": "snowape_arm", "icefish": "icefish_torso",
	"crab": "crab_arm", "gull": "gull_head", "reeffish": "reef_head", "shark": "shark_torso", "manta": "manta_arm",
}


## "wolf_leg@1" -> ["wolf_leg", 1]；旧存档里没有 @ 的是 Boss 掉的千年灵骨
func bone_id(entry: String) -> String:
	return entry.get_slice("@", 0)


func bone_age(entry: String) -> int:
	return int(entry.get_slice("@", 1)) if "@" in entry else 2


func bone_data(entry: String) -> Dictionary:
	return BONES.get(bone_id(entry), {})


func bone_name(entry: String) -> String:
	var d := bone_data(entry)
	if d.is_empty():
		return "灵骨"
	return "%s%s" % [age_name(bone_age(entry)), d["name"]]


## 一块灵骨某个属性加多少（算上年份）
func bone_stat(entry: String, stat: String) -> float:
	var d := bone_data(entry)
	var v := 0.0
	var k: float = BONE_AGE_MULT[clampi(bone_age(entry), 0, BONE_AGE_MULT.size() - 1)]
	for pair in [["stat", "amount"], ["stat2", "amount2"]]:
		if str(d.get(pair[0], "")) == stat:
			v += float(d[pair[1]]) * (1.0 if stat in BONE_SWITCH else k)
	return v


func bone_desc(entry: String) -> String:
	var d := bone_data(entry)
	var out: Array = []
	for pair in [["stat", "amount"], ["stat2", "amount2"]]:
		var st := str(d.get(pair[0], ""))
		if st == "":
			continue
		var v := bone_stat(entry, st)
		match st:
			"hp":
				out.append("体力 +%d" % roundi(v))
			"soul":
				out.append("灵力 +%d" % roundi(v))
			"dmg":
				out.append("伤害 +%d%%" % roundi(v * 100))
			"headshot":
				out.append("爆头 +%d%%" % roundi(v * 100))
			"dr":
				out.append("受伤 -%d%%" % roundi(v * 100))
			"speed":
				out.append("移速 +%d%%" % roundi(v * 100))
			"reload":
				out.append("换弹 +%d%%" % roundi(v * 100))
			"recoil":
				out.append("后坐 -%d%%" % roundi(v * 100))
			"jump":
				out.append("跳跃 +%d%%" % roundi(v * 100))
			"djump":
				out.append("二段跳（空中再按空格）")
			"glide":
				out.append("滑翔（空中按住空格）")
			"breath":
				out.append("水下憋气 +%d 秒" % roundi(v))
			"swim":
				out.append("游泳 +%d%%" % roundi(v * 100))
			"regen":
				out.append("每秒回血 %.1f" % v)
			"sell":
				out.append("卖价 +%d%%" % roundi(v * 100))
	return "，".join(out)

# ================================================================ Boss
const BOSSES := {
	# ai：water 水里钻来钻去 / land 地上 / air 天上飞
	"mandala": {"name": "镜湖之主 · 千年碧鳞蛟", "lore": "吞下第一块天枢碎片的蛟，三千年未曾离湖", "shard": 1, "hp": 12000.0, "reward": 720, "xp": 450, "bones": ["mandala_skull", "mandala_spine"], "age": 2, "ai": "water",
		"model": "snake_angry", "fit": "h", "size": 12.0, "tint": Color(1.0, 0.5, 1.2), "summon": "snake", "ring_beast": "snake", "weak": Vector3(0, 0.34, -0.3), "holy": Color(0.85, 0.55, 1.0)},
	"spider": {"name": "落霞林之主 · 千目蛛母", "lore": "千只眼睛，一张网——林子里的每一根丝，都连着它", "shard": 2, "hp": 35000.0, "reward": 2700, "xp": 1300, "bones": ["spider_leg", "spider_eye"], "age": 2, "ai": "land",
		"model": "spider", "fit": "w", "size": 13.0, "tint": Color(0.6, 0.45, 0.7), "summon": "spiderling", "ring_beast": "wolf", "weak": Vector3(0, 0.2, -0.4), "holy": Color(1.0, 0.45, 0.6)},
	"titan": {"name": "苍梧之王 · 万年朱厌", "lore": "《山海经》：见则大兵", "shard": 3, "hp": 85000.0, "reward": 7200, "xp": 3400, "bones": ["titan_arm", "titan_heart"], "age": 3, "ai": "land",
		"model": "yeti", "fit": "h", "size": 24.0, "tint": Color(0.42, 0.36, 0.34), "summon": "raptor", "ring_beast": "stag", "throws": true, "weak": Vector3(0, 0.36, -0.15), "holy": Color(1.0, 0.8, 0.4)},
	"icedragon": {"name": "朔北之主 · 万年冰螭", "lore": "它呼一口气，一整片海就冻成了冰原", "shard": 4, "hp": 130000.0, "reward": 16800, "xp": 10000, "bones": ["dragon_wing", "dragon_scale"], "age": 3, "ai": "air",
		"model": "dragon", "fit": "w", "size": 22.0, "tint": Color(0.6, 0.85, 1.3), "glow": Color(0.1, 0.3, 0.6), "summon": "husky", "ring_beast": "icehorn", "weak": Vector3(0, 0.25, -0.42), "holy": Color(0.6, 0.9, 1.0)},
	"whale": {"name": "归墟之主 · 十万年玄鲲", "lore": "北冥有鱼，其名为鲲。鲲之大，不知其几千里也", "shard": 5, "hp": 200000.0, "reward": 36000, "xp": 33000, "bones": ["whale_bone", "whale_heart"], "age": 4, "ai": "water",
		"model": "whale", "fit": "l", "size": 30.0, "tint": Color(0.55, 0.6, 0.9), "summon": "shark", "ring_beast": "shark", "weak": Vector3(0, 0.15, -0.44), "holy": Color(0.5, 0.8, 1.0)},
}

# ================================================================ 章节
# 不再有清单式任务。每章只有一条主线：修炼到 boss_level 级 → 去祭坛召唤 Boss → 打赢了所有人上船去下一张图。
# 其他都是自己挑的目标：悬赏、精英灵兽（王）、猎灵录、成就、灵骨、外观、兽潮。
# Boss 打赢以后祭坛还能再召唤（刷灵骨、灵环），渡船也能回以前去过的岛。
# 最后一章：修炼到 100 级、吸收第十灵环（十万年，归墟之主掉）= 飞升，通关。
const CHAPTERS := {
	1: {
		"name": "第一章 · 镜湖", "map": "island", "boss": "mandala", "next": 2, "levels": [1, 20], "boss_level": 15,
		"intro": "碧鳞蛟盘踞镜湖三千年，湖底压着第一块天枢碎片。先按 L 在猎灵榜上挑一只灵兽去猎——它的灵环决定你悟出什么神通；地图上的「秘」是洞天秘境，刷修为和灵骨。",
		"story": "栖霞村外，镜湖。碧鳞蛟吞下第一块天枢碎片，三千年未曾离湖。",
		"quests": [
			{"type": "dungeon", "n": 1, "text": "闯一次这座岛的洞天秘境（地图上的「秘」，走过去按 F）", "reward": 0, "target": "dungeon"},
			{"type": "level", "n": 15, "text": "修炼到 15 级（秘境刷修为；卡在瓶颈就按 L 挑灵兽去猎，炼化灵环破境）", "reward": 0},
			{"type": "altar", "n": 1, "text": "去北边山坡的古天坛（按 F）叩天，逼出镜湖之主 · 千年碧鳞蛟", "reward": 0, "target": "altar"},
			{"type": "boss", "n": 1, "text": "击败镜湖之主 · 千年碧鳞蛟，夺回第一块天枢碎片", "reward": 0},
			{"type": "boat", "n": 1, "text": "所有人到码头尽头的船边按 F，一起去落霞林", "reward": 0, "target": "boat"},
		],
	},
	2: {
		"name": "第二章 · 落霞林", "map": "forest", "boss": "spider", "next": 3, "levels": [20, 40], "boss_level": 35,
		"intro": "过了湖，是永远停在黄昏的落霞林。千目蛛母的丝织满了林子——这里的灵兽会反击：恶狼扑人，铁甲兕冲撞，山魈扔石头。",
		"story": "落霞林，永远停在黄昏。千目蛛母的丝，织满了整片林子。",
		"quests": [
			{"type": "dungeon", "n": 1, "text": "闯一次这座岛的洞天秘境（地图上的「秘」，走过去按 F）", "reward": 0, "target": "dungeon"},
			{"type": "level", "n": 35, "text": "修炼到 35 级（秘境刷修为；卡在瓶颈就按 L 挑灵兽去猎，炼化灵环破境）", "reward": 0},
			{"type": "altar", "n": 1, "text": "去森林中心古树下的古天坛（按 F）叩天，逼出落霞林之主", "reward": 0, "target": "altar"},
			{"type": "boss", "n": 1, "text": "击败落霞林之主 · 千目蛛母，夺回第二块天枢碎片", "reward": 0},
			{"type": "boat", "n": 1, "text": "所有人上船（按 F），去苍梧林海", "reward": 0, "target": "boat"},
		],
	},
	3: {
		"name": "第三章 · 苍梧林海", "map": "deepforest", "boss": "titan", "next": 4, "levels": [40, 60], "boss_level": 55,
		"intro": "苍梧林海，苍墟最大的古林，终年雾气不散。《山海经》说朱厌\"见则大兵\"——它快醒了。这里没有十年灵兽，百年、千年成群出没。",
		"story": "苍梧林海。朱厌一睁眼，天下便起刀兵——它已经开始醒了。",
		"quests": [
			{"type": "dungeon", "n": 1, "text": "闯一次这座岛的洞天秘境（地图上的「秘」，走过去按 F）", "reward": 0, "target": "dungeon"},
			{"type": "level", "n": 55, "text": "修炼到 55 级（秘境刷修为；卡在瓶颈就按 L 挑灵兽去猎，炼化灵环破境）", "reward": 0},
			{"type": "altar", "n": 1, "text": "去苍梧古木下的古天坛（按 F）叩天，唤醒苍梧之王", "reward": 0, "target": "altar"},
			{"type": "boss", "n": 1, "text": "击败苍梧之王 · 万年朱厌，夺回第三块天枢碎片", "reward": 0},
			{"type": "boat", "n": 1, "text": "所有人上船（按 F），去朔北冰原", "reward": 0, "target": "boat"},
		],
	},
	4: {
		"name": "第四章 · 朔北冰原", "map": "snow", "boss": "icedragon", "next": 5, "levels": [60, 80], "boss_level": 75,
		"intro": "朔北终年不见日。冰螭呼一口气，一整片海就冻成了冰原。千年灵兽遍地，万年灵兽开始出现；被咬会冻得走不快。",
		"story": "朔北冰原，终年不见日。冰螭呼一口气，一整片海就冻成了冰。",
		"quests": [
			{"type": "dungeon", "n": 1, "text": "闯一次这座岛的洞天秘境（地图上的「秘」，走过去按 F）", "reward": 0, "target": "dungeon"},
			{"type": "level", "n": 75, "text": "修炼到 75 级（秘境刷修为；卡在瓶颈就按 L 挑灵兽去猎，炼化灵环破境）", "reward": 0},
			{"type": "altar", "n": 1, "text": "去北边冰崖上的古天坛（按 F）叩天，逼出冰螭", "reward": 0, "target": "altar"},
			{"type": "boss", "n": 1, "text": "击败朔北之主 · 万年冰螭，夺回第四块天枢碎片", "reward": 0},
			{"type": "boat", "n": 1, "text": "所有人上船（按 F），去归墟", "reward": 0, "target": "boat"},
		],
	},
	5: {
		"name": "第五章 · 归墟", "map": "sea", "boss": "whale", "next": 0, "levels": [80, 100], "boss_level": 95,
		"intro": "众水归处，名曰归墟。最后一块天枢碎片在玄鲲腹中——北冥有鱼，其名为鲲。夺回它，修到真仙圆满、十环加身，天门就会重开。",
		"story": "归墟，众水归处。北冥有鱼，其名为鲲——最后一块碎片，在它腹中。",
		"quests": [
			{"type": "dungeon", "n": 1, "text": "闯一次这座岛的洞天秘境（地图上的「秘」，走过去按 F）", "reward": 0, "target": "dungeon"},
			{"type": "level", "n": 95, "text": "修炼到 95 级（秘境刷修为；卡在瓶颈就按 L 挑灵兽去猎，炼化灵环破境）", "reward": 0},
			{"type": "altar", "n": 1, "text": "去北岸的归墟天坛（按 F）叩天，逼出玄鲲", "reward": 0, "target": "altar"},
			{"type": "boss", "n": 1, "text": "击败归墟之主 · 十万年玄鲲，夺回最后一块天枢碎片", "reward": 0},
			{"type": "god", "n": 1, "text": "飞升：修炼到 100 级（真仙圆满），炼化第十灵环（十万年，玄鲲掉；天坛可以再叩出它）——天门重开", "reward": 0},
		],
	},
}

# ================================================================ 工具函数

func age_name(age: int) -> String:
	return AGES[clampi(age, 0, AGES.size() - 1)]["name"]


func age_color(age: int) -> Color:
	return AGES[clampi(age, 0, AGES.size() - 1)]["color"]


## 越往后的章节，百年、千年灵兽越多
## 每章灵兽的年份：第三章起没有十年的，第五章出万年（黑色灵环）。权重依次是 十年 / 百年 / 千年 / 万年
const AGE_WEIGHTS := {1: [70.0, 28.0, 2.0, 0.0], 2: [30.0, 55.0, 15.0, 0.0], 3: [0.0, 55.0, 42.0, 3.0], 4: [0.0, 20.0, 60.0, 20.0], 5: [0.0, 0.0, 45.0, 55.0]}
## 每章灵兽的攻击力倍数，和每章灵兽的特点（被咬到时）
## 第十版：后面章节的攻击力涨得比玩家血量快太多（第五章普通一口掉一半血），压平了；
## 普通咬一口再 ×BITE_K，有前摇、能躲的招（红圈）保持原来的疼
const CH_POWER := {1: 1.0, 2: 1.2, 3: 1.4, 4: 1.6, 5: 1.8}
## 灵主（Boss）招式的伤害倍数（第十三版）。以前用 CH_POWER：玩家血（100 + 7×等级）和护体（每级 0.4%）涨得比它快，
## 一记 40 的招在第一章掉 14% 血、到第五章只掉 7%——最后的 Boss 反而最不疼。现在按"打 Boss 时的等级（15/35/55/75/95）
## 挨一记 40 的招掉多少血"反推：第一章约 18%，每章多一点，第五章约 22%（有灵骨、猎灵录的血多，实际少一些）。
## 大招（全场、海啸）是 55~70，一下三成多——想无伤就得躲
const BOSS_DMG_CH := {1: 0.95, 2: 1.85, 3: 3.0, 4: 4.5, 5: 6.5}
const BEAST_DMG := 1.8        # 灵兽伤害总倍数（用户说第一章升到 15 级基本没掉过血）
const BITE_K := 0.7
## 没有前摇的普通一口最多掉多少血（按这一章的参考等级算，已扣护体）：小怪 12%、灵兽王 22%。
## 第十三版核算：第二章百年铁甲兕王一口能掉 37%，第五章十万年猎物一口 26%，躲不了的伤害不该这么疼；有红圈的招不受这个限制
const BITE_CAP := 0.12
const BITE_CAP_KING := 0.22


func bite_cap(chapter: int, king: bool) -> float:
	var lv := int(CH_REF_LEVEL.get(chapter, 10))
	var hp := 100.0 + (lv - 1) * 7.0
	return (BITE_CAP_KING if king else BITE_CAP) * hp / (1.0 - level_armor(lv))
## 第二章原来是"被咬中毒持续掉血"，用户说一直掉血很烦，去掉了
const CH_TRAIT := {1: "", 2: "", 3: "pack", 4: "frost", 5: "drag"}
const TRAIT_TEXT := {
	"poison": "这里的灵兽带毒：被咬会中毒，持续掉血",
	"pack": "这里的灵兽成群：拽出一只，同窝的会跑来帮忙",
	"frost": "这里的灵兽带寒气：被咬会冻得走不快",
	"drag": "这里的海兽会把人往它那边拖，小心被拖下水",
}


func roll_age(rng: RandomNumberGenerator, min_age := 0, chapter := 1) -> int:
	var w: Array = AGE_WEIGHTS.get(chapter, AGE_WEIGHTS[1])
	var total := 0.0
	for i in range(min_age, w.size()):
		total += float(w[i])
	if total <= 0.0:
		for i in w.size():
			if float(w[i]) > 0.0:
				return maxi(i, min_age)
		return min_age
	var r := rng.randf() * total
	for i in range(min_age, w.size()):
		if float(w[i]) <= 0.0:
			continue
		r -= float(w[i])
		if r <= 0.0:
			return i
	return min_age


## ================================================================ 第十一版：野外猎灵 + 秘境（world/hunt.gd、world/dungeon.gd）
## 野外不再刷怪：按 L（或码头边的猎灵榜）挑一只灵兽，卡片上写着它的灵环会给你哪个神通。
## 它在岛上游荡，不标准确位置：跟着发光的踪迹、听吼声找过去，55 米内才看得清。打倒它 → 站着吸收灵环（单人快，联机要队友护法）。
## 刷修为、灵石、灵骨在秘境：每座岛三个入口（地图上的「秘」），进去三波灵兽 → 秘境之主 → 宝箱。
const HUNT_REVEAL := 30.0              # 离猎物这么近才看得到它（远了要看爪痕锁定）
const HUNT_CHANNEL_SOLO := 10.0        # 单人吸收灵环站多久
const HUNT_CHANNEL_TEAM := 25.0        # 联机吸收灵环站多久（队友护法）
const HUNT_WAVE_GAP := 7.0             # 联机护法时隔几秒来一波
# 这一章猎物、一层秘境的年份（十年 / 百年 / 千年 / 万年）。第五章从万年起（秘境：万年 / 十万年 / 百万年）
const CH_AGE := {1: 0, 2: 1, 3: 1, 4: 2, 5: 3}

## 秘境三层：年份 = 这一章的基础年份 + 层数（最高百万年）；waves = 每波几只（单人），联机每多一人每波 +2
const DG_TIERS := [
	{"name": "一层", "add": 0, "waves": [3, 4, 5], "reward": 1.0},
	{"name": "二层", "add": 1, "waves": [4, 5, 6], "reward": 1.8},
	{"name": "三层", "add": 2, "waves": [5, 6, 7], "reward": 3.0},
]
## 每次进秘境随机一个词条（换着花样打，奖励也跟着变）
const DG_MODS := {
	"swarm": {"name": "兽潮", "desc": "每波多来两只", "reward": 1.4, "color": Color(1.0, 0.6, 0.35)},
	"armor": {"name": "坚甲", "desc": "灵兽血量 +50%", "reward": 1.3, "color": Color(0.7, 0.8, 1.0)},
	"meteor": {"name": "陨星", "desc": "地上会出红圈砸陨石", "reward": 1.3, "color": Color(1.0, 0.4, 0.3)},
	"swift": {"name": "疾风", "desc": "灵兽都跑得飞快", "reward": 1.3, "color": Color(0.5, 1.0, 0.8)},
	"frenzy": {"name": "狂暴", "desc": "灵兽半血以下发狂", "reward": 1.3, "color": Color(1.0, 0.3, 0.5)},
}
const DG_BOSS_HP_SOLO := 0.45          # 秘境之主 / 猎物的血量（相对灵兽王）：单人
const DG_BOSS_HP_PER := 0.4            # 每多一个人加这么多
const DG_MOB_HP := 0.75                # 秘境小怪的血量（相对野外同样的灵兽）
const DG_MOB_DMG := 0.75               # 秘境小怪的伤害
# 猎场的猎物（相对灵兽王的血量）：单人 / 每多一人；两成血以下虚弱，能活捉
const HUNT_HP_SOLO := 0.6
const HUNT_HP_PER := 0.45
const HUNT_WEAK := 0.2
const DG_MOB_DMG_CH := {1: 1.0, 2: 1.0, 3: 0.92, 4: 0.85, 5: 0.68}   # 后面几章再乘一点（机器人：第五章站着不动只用狙击，打到第三波才倒）
# 秘境小怪血量按章再乘：第五章秘境整体高了一档年份（千年 → 万年起），血量压回来一些
const DG_MOB_HP_CH := {1: 1.0, 2: 1.0, 3: 1.0, 4: 0.92, 5: 0.65}


## 这一章某层秘境的年份
func dg_age(chapter: int, tier: int) -> int:
	return clampi(int(CH_AGE.get(chapter, 0)) + int(DG_TIERS[tier]["add"]), 0, AGES.size() - 1)


## 某层秘境推荐等级
func dg_level(chapter: int, tier: int) -> int:
	var lv: Array = CHAPTERS[chapter]["levels"]
	return int(lerpf(float(lv[0]) + 2.0, float(lv[1]), float(tier) / 2.0))

## 灵兽血量：基础 × 年份 × 章节（后面的图的灵兽厚得多，玩家的暗器、升级、等级、灵骨也跟着涨）
## 参考（按这一章的参考等级、主力暗器、升级估算，不算灵骨和神通）：
##   第一章 袖箭 约 0.3 秒一只 · 第二章 连机神弩 0.5 秒 · 第三章 流光翎 0.9 秒 · 第四章 2.4 秒（狙击爆头一发）· 第五章 3.8 秒（灵骨、神通能快一倍）
const CH_HP := {1: 1.0, 2: 2.0, 3: 4.0, 4: 6.0, 5: 8.0}


## 第十一版补丁：怪不再一枪一只（用户："伤害基本都是秒杀"）。
## 灵兽血量有个下限：按这一章该有的暗器（REF_KIT：暗器、等级、伤害升级），最少要打 HP_SHOTS 下、持续开火 HP_TTK 秒；
## 玩家的暗器比这一章强，下限也跟着涨（HP_FOLLOW：0.75 次方，强还是打得快一点，只是不会一枪一只）
const REF_KIT := {1: ["xiujian", 10, 2], 2: ["zhuge", 30, 3], 3: ["kongque", 50, 3], 4: ["kongque", 70, 5], 5: ["zhuihun", 90, 5]}
const HP_SHOTS := [3.0, 4.0, 5.0, 7.0, 10.0]
const HP_TTK := [0.5, 0.8, 1.2, 1.7, 2.4]
const HP_FOLLOW := 0.75
const ELITE_FLOOR := 12.0              # 灵兽王 / 秘境之主的下限倍数


## 一套暗器的输出：x = 一发的伤害，y = 每秒伤害
func kit_output(weapon: String, level: int, upg_dmg: int) -> Vector2:
	var d := weapon_stats(weapon, {"dmg": upg_dmg})
	return weapon_output(d) * level_damage(level)


func ref_output(chapter: int) -> Vector2:
	var k: Array = REF_KIT.get(chapter, REF_KIT[1])
	return kit_output(str(k[0]), int(k[1]), int(k[2]))


## 这一章某个年份的灵兽，血量至少要这么多（player：玩家的输出，Vector2.ZERO = 按这一章的标准算）
func hp_floor(chapter: int, age: int, player: Vector2) -> float:
	var r := ref_output(chapter)
	var p := player if player.x > 0.0 else r
	var a := clampi(age, 0, HP_SHOTS.size() - 1)
	var shot := pow(p.x, HP_FOLLOW) * pow(r.x, 1.0 - HP_FOLLOW)
	var dps := pow(p.y, HP_FOLLOW) * pow(r.y, 1.0 - HP_FOLLOW)
	# "最少几发"只是不让一枪一只：打得慢的（狙击、天心泪）不能因此要打五六发，最多按持续开火时间的 2.5 倍算
	return maxf(minf(shot * HP_SHOTS[a], dps * HP_TTK[a] * 2.5), dps * HP_TTK[a])


func beast_max_hp(species: String, age: int) -> float:
	# 自动测试是功能测试（能不能拽、能不能打死），用的是 1 级的暗器，不乘章节血量
	var ch_k := 1.0 if autotest else float(CH_HP.get(int(SPECIES_CH.get(species, 1)), 1.0)) * Profile.rebirth_hard()
	return BEASTS[species]["hp"] * AGES[clampi(age, 0, AGES.size() - 1)]["hp"] * ch_k


## 神通特效用的颜色（比界面上的灵相颜色更饱和，白虎、玄女这种浅色的也看得清）
func wuhun_fx_color(idx: int) -> Color:
	var w: Dictionary = WUHUN[clampi(idx, 0, WUHUN.size() - 1)]
	return w.get("fx", w["color"])


func wuhun_color(idx: int) -> Color:
	return WUHUN[clampi(idx, 0, WUHUN.size() - 1)]["color"]


func wuhun_id(idx: int) -> String:
	return WUHUN[clampi(idx, 0, WUHUN.size() - 1)]["id"]


func pattern(w: Dictionary) -> Array:
	var p: Variant = w["pattern"]
	if p is String:
		return PATTERNS[p]
	return p


## 暗器数值（算上升级）
func weapon_stats(id: String, upgrades: Dictionary) -> Dictionary:
	var d: Dictionary = WEAPONS[id].duplicate(true)
	d["id"] = id
	var lv_dmg := int(upgrades.get("dmg", 0))
	var lv_mag := int(upgrades.get("mag", 0))
	var lv_rel := int(upgrades.get("reload", 0))
	var lv_stab := int(upgrades.get("stab", 0))
	d["damage"] = d["damage"] * (1.0 + UPGRADES["dmg"]["per"] * lv_dmg)
	d["mag"] = int(round(d["mag"] * (1.0 + UPGRADES["mag"]["per"] * lv_mag)))
	var rk := 1.0 - UPGRADES["reload"]["per"] * lv_rel
	d["reload"] = d["reload"] * rk
	d["reload_empty"] = d["reload_empty"] * rk
	d["recoil_mult"] = 1.0 - UPGRADES["stab"]["per"] * lv_stab
	var sk := 1.0 - 0.08 * lv_stab
	for k in ["hip", "ads", "move", "bloom"]:
		d[k] = d[k] * sk
	return d


## 装上配件以后的数值：瞄具改开镜倍率、全屏瞄准镜；枪口 / 握把 / 激光改后坐和散布；弹匣改弹量、换弹、伤害；枪托改开镜、移速、后坐
func apply_attach(d: Dictionary, on: Dictionary) -> Dictionary:
	d["recoil_v"] = 1.0
	d["recoil_h"] = 1.0
	d["move_k"] = 1.0
	d["attach"] = on.duplicate()
	var ads_k := 1.0
	for slot in on:
		var a: Dictionary = ATTACH.get(str(on[slot]), {})
		if a.is_empty():
			continue
		if a.has("ads_fov"):
			d["ads_fov"] = float(a["ads_fov"])
		if a.has("zoom"):
			d["scope"] = true
			d["zoom"] = float(a["zoom"])
			d["variable"] = bool(a.get("variable", false))
			d["ads_time"] = maxf(float(d["ads_time"]), 0.22)
		d["recoil_v"] = float(d["recoil_v"]) * float(a.get("recoil_v", 1.0))
		d["recoil_h"] = float(d["recoil_h"]) * float(a.get("recoil_h", 1.0))
		d["recoil_mult"] = float(d.get("recoil_mult", 1.0)) * float(a.get("recoil_all", 1.0))
		for k in ["hip", "ads", "move"]:
			d[k] = float(d[k]) * float(a.get("spread", 1.0))
		d["hip"] = float(d["hip"]) * float(a.get("hip", 1.0))
		d["mag"] = maxi(int(round(float(d["mag"]) * float(a.get("mag_k", 1.0)))), 1)
		for k in ["reload", "reload_empty"]:
			d[k] = float(d[k]) * float(a.get("reload_k", 1.0))
		d["damage"] = float(d["damage"]) * float(a.get("dmg_k", 1.0))
		if d.has("splash_dmg"):
			d["splash_dmg"] = float(d["splash_dmg"]) * float(a.get("dmg_k", 1.0))
		d["move_k"] = float(d["move_k"]) * float(a.get("move_k", 1.0))
		ads_k *= float(a.get("ads_k", 1.0))
		if bool(a.get("quiet", false)):
			d["quiet"] = true
	d["ads_time"] = float(d["ads_time"]) * ads_k
	return d


## 一发和每秒的伤害（估算，给血量下限、暗器铺用）：三连发、蓄力、爆炸都算进去
func weapon_output(d: Dictionary) -> Vector2:
	var shot := float(d["damage"]) * float(d["pellets"])
	var cycle := 60.0 / float(d["rpm"])
	match str(d["mode"]):
		"burst":
			shot *= float(d.get("burst", 1))
			cycle += float(d.get("burst_gap", 0.0)) * (float(d.get("burst", 1)) - 1.0)
		"charge":
			shot *= float(d.get("charge_k", 1.0))
			cycle += float(d.get("charge", 0.0))
		"bolt":
			cycle = maxf(cycle, float(d.get("cycle", 0.0)))
	if d.has("splash_dmg"):
		# 母胆中心 + 三颗子胆（打一只的时候大约吃到一半）
		shot += float(d["splash_dmg"]) * (1.0 + 0.45 * float(d.get("children", 0)) * 0.5)
	return Vector2(shot, shot / maxf(cycle, 0.01))


func upgrade_price(id: String, level: int) -> int:
	var base := maxi(int(WEAPONS[id]["price"]), 400)
	return int(round(base * UPGRADE_COST[clampi(level, 0, UPGRADE_COST.size() - 1)] / 10.0)) * 10


func quest(chapter: int, idx: int) -> Dictionary:
	var qs: Array = CHAPTERS[chapter]["quests"]
	if idx < 0 or idx >= qs.size():
		return {}
	return qs[idx]
