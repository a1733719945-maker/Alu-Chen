extends Node
## 游戏数据表。调数值主要改这里：暗器、魂兽、魂技、章节任务、商店价格。

const PROTOCOL_VERSION := "m3-1"
var autotest := false      # 自动测试时关掉随机的东西（精英、兽潮、饥饿、魂兽性格）

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

# ================================================================ 武魂
const WUHUN := [
	{"id": "lyc", "name": "蓝银草", "kind": "植物系 · 控制", "color": Color("6aa8ec"), "img": "res://assets/img/wuhun/w01.jpg"},
	{"id": "ld", "name": "镰刀", "kind": "器武魂 · 强攻", "color": Color("c9d3d0"), "img": "res://assets/img/wuhun/w02.jpg"},
	{"id": "xc", "name": "香肠", "kind": "食物系 · 辅助", "color": Color("e59a6b"), "img": "res://assets/img/wuhun/w03.jpg"},
	{"id": "bh", "name": "白虎", "kind": "兽武魂 · 强攻", "color": Color("f1f1e6"), "img": "res://assets/img/wuhun/w04.jpg"},
	{"id": "ym", "name": "幽冥灵猫", "kind": "兽武魂 · 敏攻", "color": Color("9c7be0"), "img": "res://assets/img/wuhun/w05.jpg"},
	{"id": "hf", "name": "火凤凰", "kind": "兽武魂 · 强攻", "color": Color("f0773f"), "img": "res://assets/img/wuhun/w06.jpg"},
	{"id": "qb", "name": "七宝琉璃塔", "kind": "器武魂 · 辅助", "color": Color("8fe3d0"), "img": "res://assets/img/wuhun/w07.jpg"},
	{"id": "ht", "name": "昊天锤", "kind": "器武魂 · 强攻", "color": Color("c0c6cc"), "img": "res://assets/img/wuhun/w08.jpg"},
	{"id": "ls", "name": "六翼天使", "kind": "兽武魂 · 强攻", "color": Color("ffe08a"), "img": "res://assets/img/wuhun/w09.jpg"},
]

# ================================================================ 年份（魂环颜色）
# 十年白、百年黄、千年紫、万年黑、十万年红。hp / reward / xp 是相对十年的倍数（经验、金币另外按章节放大，见 kill_xp / kill_money）
# glow：魂环发光的颜色（万年的环是黑的，边上发暗红光，不然看不见）
const AGES := [
	{"name": "十年", "color": Color(0.95, 0.95, 0.92), "glow": Color(0.95, 0.95, 0.92), "hp": 1.0, "reward": 1.0, "xp": 0.8, "scale": 1.0, "mass": 1.0, "ring_drop": 0.25, "ring_power": 1.0},
	{"name": "百年", "color": Color(1.0, 0.82, 0.25), "glow": Color(1.0, 0.82, 0.25), "hp": 1.8, "reward": 2.2, "xp": 1.1, "scale": 1.2, "mass": 1.5, "ring_drop": 0.4, "ring_power": 1.3},
	{"name": "千年", "color": Color(0.68, 0.36, 1.0), "glow": Color(0.68, 0.36, 1.0), "hp": 3.0, "reward": 4.5, "xp": 1.6, "scale": 1.45, "mass": 2.4, "ring_drop": 0.6, "ring_power": 1.7},
	{"name": "万年", "color": Color(0.08, 0.06, 0.08), "glow": Color(0.75, 0.08, 0.12), "hp": 5.0, "reward": 9.0, "xp": 2.6, "scale": 1.75, "mass": 4.0, "ring_drop": 0.8, "ring_power": 2.3},
	{"name": "十万年", "color": Color(1.0, 0.1, 0.08), "glow": Color(1.0, 0.1, 0.08), "hp": 9.0, "reward": 20.0, "xp": 5.0, "scale": 2.1, "mass": 6.0, "ring_drop": 1.0, "ring_power": 3.2},
]

# ================================================================ 魂兽
# habitat：在哪里能用引魂索引出来；motion：落地后怎么跑
# armor：身体减伤（头不减）；hurt：落地后会不会攻击玩家（伤害值）
# model：assets/models/creatures 里的模型；fit + size：按长(l)/高(h)/宽(w)缩放到多少米；tint：颜色；glow：发光
const BEASTS := {
	# 第一章 · 湖心岛
	"rabbit": {"name": "柔骨兔", "habitat": "burrow", "hp": 30.0, "reward": 10, "xp": 10, "motion": "hop", "hurt": 5.0,
		"model": "bunny", "fit": "h", "size": 0.8, "tint": Color(1.0, 0.97, 0.98)},
	"vine": {"name": "鬼藤", "habitat": "water", "hp": 36.0, "reward": 14, "xp": 12, "motion": "slither", "hurt": 7.0},
	"bird": {"name": "风铃鸟", "habitat": "meadow", "hp": 24.0, "reward": 15, "xp": 12, "motion": "fly", "hurt": 5.0,
		"model": "pigeon", "fit": "w", "size": 1.0, "tint": Color(0.55, 1.0, 0.95)},
	"moth": {"name": "月光蛾", "habitat": "flowers", "hp": 26.0, "reward": 12, "xp": 10, "motion": "flutter", "hurt": 4.0,
		"model": "wasp", "fit": "w", "size": 0.9, "tint": Color(0.75, 0.8, 1.2), "glow": Color(0.35, 0.45, 1.0)},
	# 第二章 · 落日森林
	"wolf": {"name": "疾风魔狼", "habitat": "den", "hp": 70.0, "reward": 30, "xp": 26, "motion": "run", "hurt": 12.0,
		"model": "wolf", "fit": "l", "size": 1.8, "tint": Color(0.72, 0.78, 0.9)},
	"rhino": {"name": "铁甲犀", "habitat": "mud", "hp": 120.0, "reward": 40, "xp": 34, "motion": "charge", "armor": 0.5, "hurt": 22.0, "heavy": true,
		"model": "bull", "fit": "l", "size": 2.6, "tint": Color(0.62, 0.66, 0.74), "horn": true},
	"ape": {"name": "金刚猿", "habitat": "grove", "hp": 90.0, "reward": 36, "xp": 30, "motion": "throw", "hurt": 15.0, "tall": true,
		"model": "yeti", "fit": "h", "size": 1.9, "tint": Color(0.62, 0.45, 0.34)},
	"snake": {"name": "曼陀罗蛇", "habitat": "swamp", "hp": 60.0, "reward": 30, "xp": 26, "motion": "slither", "hurt": 8.0,
		"model": "snake", "fit": "h", "size": 1.2, "tint": Color(0.95, 0.55, 1.2)},
	# 第三章 · 星斗大森林
	"stag": {"name": "鬼眼鹿", "habitat": "glade", "hp": 110.0, "reward": 50, "xp": 46, "motion": "run", "hurt": 14.0, "tall": true,
		"model": "stag", "fit": "l", "size": 2.3, "tint": Color(0.55, 0.6, 0.85), "glow": Color(0.1, 0.35, 0.8)},
	"bat": {"name": "夜翼魔蝠", "habitat": "roost", "hp": 80.0, "reward": 48, "xp": 44, "motion": "fly", "hurt": 11.0,
		"model": "bat", "fit": "w", "size": 1.6, "tint": Color(0.8, 0.7, 1.0)},
	"raptor": {"name": "疾爪龙", "habitat": "thicket", "hp": 130.0, "reward": 56, "xp": 52, "motion": "run", "hurt": 18.0,
		"model": "raptor", "fit": "l", "size": 2.8, "tint": Color(0.7, 0.85, 0.7)},
	"spiderling": {"name": "地穴魔蛛", "habitat": "nest", "hp": 100.0, "reward": 52, "xp": 48, "motion": "run", "hurt": 14.0,
		"model": "spider", "fit": "w", "size": 1.8, "tint": Color(0.85, 0.6, 1.0)},
	"frog": {"name": "碧磷蟾", "habitat": "bog", "hp": 90.0, "reward": 46, "xp": 42, "motion": "hop", "hurt": 10.0,
		"model": "frog", "fit": "l", "size": 1.0, "tint": Color(0.6, 1.1, 0.8), "glow": Color(0.05, 0.3, 0.15)},
	# 第四章 · 极北之地
	"husky": {"name": "雪原狼", "habitat": "snowden", "hp": 150.0, "reward": 70, "xp": 64, "motion": "run", "hurt": 18.0,
		"model": "husky", "fit": "l", "size": 2.0, "tint": Color(1.1, 1.12, 1.2)},
	"icedeer": {"name": "冰角鹿", "habitat": "frostgrove", "hp": 160.0, "reward": 72, "xp": 66, "motion": "run", "hurt": 12.0, "tall": true,
		"model": "deer", "fit": "l", "size": 2.1, "tint": Color(0.8, 0.95, 1.2), "glow": Color(0.1, 0.35, 0.5)},
	"icehorn": {"name": "冰甲龙", "habitat": "icefield", "hp": 260.0, "reward": 90, "xp": 80, "motion": "charge", "armor": 0.5, "hurt": 28.0, "heavy": true,
		"model": "triceratops", "fit": "l", "size": 3.4, "tint": Color(0.7, 0.9, 1.15)},
	"snowape": {"name": "雪魔猿", "habitat": "icecave", "hp": 200.0, "reward": 80, "xp": 72, "motion": "throw", "hurt": 20.0, "tall": true,
		"model": "yeti", "fit": "h", "size": 2.3, "tint": Color(1.05, 1.08, 1.15)},
	"icefish": {"name": "冰鳞鱼", "habitat": "icelake", "hp": 120.0, "reward": 64, "xp": 58, "motion": "slither", "hurt": 12.0,
		"model": "fish1", "fit": "l", "size": 1.4, "tint": Color(0.75, 0.95, 1.2), "glow": Color(0.1, 0.25, 0.35)},
	# 第五章 · 海神岛
	"crab": {"name": "铁钳蟹", "habitat": "beach", "hp": 220.0, "reward": 90, "xp": 82, "motion": "charge", "armor": 0.4, "hurt": 22.0,
		"model": "crab", "fit": "w", "size": 1.5, "tint": Color(1.2, 0.7, 0.55)},
	"gull": {"name": "海魂鸥", "habitat": "cliff", "hp": 140.0, "reward": 86, "xp": 78, "motion": "fly", "hurt": 14.0,
		"model": "pigeon", "fit": "w", "size": 1.4, "tint": Color(1.25, 1.25, 1.3)},
	"reeffish": {"name": "彩鳞鱼", "habitat": "reef", "hp": 150.0, "reward": 84, "xp": 76, "motion": "slither", "hurt": 12.0,
		"model": "fish2", "fit": "l", "size": 1.2},
	"shark": {"name": "深海魔鲨", "habitat": "deep", "hp": 260.0, "reward": 110, "xp": 96, "motion": "slither", "hurt": 22.0,
		"model": "shark", "fit": "l", "size": 3.0, "tint": Color(0.75, 0.85, 1.0)},
	"manta": {"name": "幽灵鳐", "habitat": "abyss", "hp": 240.0, "reward": 120, "xp": 104, "motion": "flutter", "hurt": 16.0,
		"model": "manta", "fit": "w", "size": 2.6, "tint": Color(0.6, 0.7, 1.1), "glow": Color(0.1, 0.2, 0.6)},
}

# ================================================================ 魂兽的独门本事（凶暴的和精英会用）
# 每一招都有前摇（wind 秒）：魂兽发光、地上出现范围圈、头顶冒招式名。看到了就翻滚 / 跑出圈能躲开。
# at：self 以魂兽为中心，target 砸在前摇开始时你站的地方（跑开就没事）
# dmg：相对咬一口的倍数；push 击退；pull 拉过去；root 定身秒数；slow 减速比例 + dur；blind 致盲秒数；
# vuln 受伤加深秒数；silence 封魂技秒数；poison / bleed 持续掉血；steal 叼走金魂币比例；shield 打碎护盾；heal 吸血回复
const BEAST_SKILLS := {
	"rabbit": {"name": "柔骨蹬腿", "cd": 6.0, "wind": 0.45, "range": 3.5, "radius": 3.2, "at": "self", "dmg": 1.3, "push": 12.0},
	"vine": {"name": "鬼藤缠绕", "cd": 8.0, "wind": 0.8, "range": 9.0, "radius": 2.6, "at": "target", "dmg": 0.6, "root": 1.6},
	"bird": {"name": "风铃音波", "cd": 7.0, "wind": 0.8, "range": 10.0, "radius": 6.0, "at": "self", "dmg": 0.8, "push": 10.0},
	"moth": {"name": "月光磷粉", "cd": 9.0, "wind": 0.7, "range": 8.0, "radius": 4.5, "at": "self", "dmg": 0.4, "blind": 2.5},
	"wolf": {"name": "狼嚎", "cd": 12.0, "wind": 0.9, "range": 25.0, "radius": 20.0, "at": "self", "dmg": 0.0, "howl": 6.0},
	"rhino": {"name": "铁蹄震地", "cd": 9.0, "wind": 0.9, "range": 6.0, "radius": 5.5, "at": "self", "dmg": 1.3, "push": 7.0, "slow": 0.5, "dur": 2.0, "shield": true},
	"ape": {"name": "金刚捶地", "cd": 8.0, "wind": 0.9, "range": 5.0, "radius": 5.0, "at": "self", "dmg": 1.5, "push": 9.0},
	"snake": {"name": "曼陀罗毒雾", "cd": 9.0, "wind": 0.6, "range": 13.0, "radius": 3.6, "at": "target", "dmg": 0.4, "poison": 0.35, "dur": 5.0},
	"stag": {"name": "鬼眼凝视", "cd": 11.0, "wind": 1.0, "range": 26.0, "radius": 2.0, "at": "target", "dmg": 0.8, "vuln": 6.0},
	"bat": {"name": "吸血", "cd": 7.0, "wind": 0.5, "range": 4.0, "radius": 3.6, "at": "self", "dmg": 1.3, "heal": 3.0},
	"raptor": {"name": "扑杀", "cd": 7.0, "wind": 0.55, "range": 12.0, "min": 4.0, "radius": 2.6, "at": "target", "dmg": 1.5, "root": 0.8, "leap": true},
	"spiderling": {"name": "蛛网", "cd": 8.0, "wind": 0.5, "range": 14.0, "radius": 3.0, "at": "target", "dmg": 0.3, "slow": 0.65, "dur": 3.0},
	"frog": {"name": "长舌卷人", "cd": 8.0, "wind": 0.6, "range": 12.0, "min": 3.0, "radius": 2.3, "at": "target", "dmg": 0.8, "pull": 15.0, "poison": 0.2, "dur": 3.0},
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
	"meadow": {"name": "风铃草原", "beast": "bird"},
	"flowers": {"name": "月光花丛", "beast": "moth"},
	"den": {"name": "狼穴", "beast": "wolf"},
	"mud": {"name": "泥潭", "beast": "rhino"},
	"grove": {"name": "古树林", "beast": "ape"},
	"swamp": {"name": "毒沼", "beast": "snake"},
	"glade": {"name": "鬼眼鹿林", "beast": "stag"},
	"roost": {"name": "蝠巢枯林", "beast": "bat"},
	"thicket": {"name": "龙爪荆棘", "beast": "raptor"},
	"nest": {"name": "魔蛛巢穴", "beast": "spiderling"},
	"bog": {"name": "碧磷沼", "beast": "frog"},
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

# ================================================================ 魂兽性格（每只拽出来的时候随机，房主决定）
# flee   胆小：落地就逃回窝里 / 水里
# fierce 凶暴：盯住最近的玩家一直打，不逃，打到死为止
# sly    狡猾：落地先装死几秒，你一走近就突然窜回去
# bone   魂骨兽：全身金光，跑得飞快，打死必掉一块魂骨
const TEMPERS := {
	"flee": {"name": "", "color": Color(0.85, 0.85, 0.85)},
	"fierce": {"name": "凶暴", "color": Color(1.0, 0.32, 0.26)},
	"sly": {"name": "狡猾", "color": Color(0.55, 0.95, 0.6)},
	"bone": {"name": "魂骨", "color": Color(1.0, 0.84, 0.3)},
	"elite": {"name": "精英", "color": Color(1.0, 0.55, 0.15)},
}

# ================================================================ 精英魂兽（小 Boss）
# 每张地图在陆地栖息地附近固定几个点刷，不用引魂索拽；走近 20 米或者打它就会过来打人，
# 跑出 45 米就回老家回血。打死以后 2 分钟在原地重生，必掉魂骨。
const ELITE_HP := 4.0
const ELITE_SIZE := 1.55
const ELITE_DMG := 2.0
const ELITE_REWARD := 6.0
const ELITE_RESPAWN := 120.0
const ELITE_MAX := 5
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


# ================================================================ 战利品（打死魂兽掉在地上，捡起来丢进收购箱换金魂币）
const LOOT_PART := {"hop": "绒毛", "slither": "鳞片", "fly": "羽翎", "flutter": "翅鳞", "run": "利齿", "charge": "硬角", "throw": "兽骨"}
const KILL_MONEY := 1.0          # 打死直接拿金魂币（素材已经去掉了）
const LOOT_VALUE := 0.7
const SELL_ITEMS := {"pill": 20, "grenade": 30, "meat": 12}


## 素材的 key："mat:<魂兽>:<年份>"
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

# ================================================================ 唐门暗器
# 后坐（CS / COD 的做法）：
#   pattern      每一发往哪边跳（度）：x 左右、y 向上。连射时按顺序叠加，停火后回正
#   jitter       每发额外的随机抖动
#   view_punch   只晃镜头、不影响弹道的"顶一下"，负责手感的冲击力
# 散布：
#   hip / ads    腰射 / 开镜 的基础散布（度）
#   move         全速移动时额外增加的散布；air 跳在空中；crouch 蹲下乘的系数
#   bloom        每发增加的散布，停火后按 bloom_recover 每秒恢复；刚开第一枪最准
const WEAPON_ORDER := ["xiujian", "zhuge", "kongque", "baoyu", "zhuihun"]
# 拿着暗器跑的速度（越重越慢）；空手最快
const MOVE_K := {"xiujian": 0.96, "zhuge": 0.92, "kongque": 0.88, "baoyu": 0.9, "zhuihun": 0.84, "fist": 1.15}
# 暗器跟着章节开放：第一章只有袖箭和梨花针，第二章诸葛神弩，第三章孔雀翎，第四章追魂穿心弩
const WEAPON_UNLOCK := {"xiujian": 1, "baoyu": 1, "zhuge": 2, "kongque": 3, "zhuihun": 4}

const WEAPONS := {
	"xiujian": {
		"name": "袖箭", "cat": "手枪", "desc": "唐门入门暗器。射速快、爆头伤害高，适合点射。",
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
		"name": "诸葛神弩", "cat": "冲锋", "desc": "连发弩，一秒十五箭。近中距离压制，连射上跳很快，要往下拉。",
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
		"name": "孔雀翎", "cat": "步枪", "desc": "唐门四大暗器之一。伤害高、第一发极准，连射后坐很大，要压枪。",
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
		"name": "暴雨梨花针", "cat": "霰弹", "desc": "一次十四根银针。近身一发把魂兽轰上天，后坐像被人推了一把。",
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
		"name": "追魂穿心弩", "cat": "狙击", "desc": "重弩，一箭贯穿。要装狙击镜才好用（暗器铺 → 配件）。",
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
	"reload": {"name": "唐门机括", "desc": "换弹快 10%", "per": 0.1},
	"stab": {"name": "稳定弩臂", "desc": "后坐 -12%，散布 -8%", "per": 0.12},
}
const UPGRADE_COST := [0.25, 0.45, 0.75, 1.1, 1.6]

# 配件：暗器铺买，默认都没有（只有机械照门）。price 是暗器价格的倍数（便宜的按 400 算）
# 瞄具（sight）一次只能装一个：红点 / 全息 放大一点点；2 倍镜、狙击镜 开镜是全屏瞄准镜（狙击镜滚轮 4~12 倍）
const ATTACH := {
	"red": {"name": "红点瞄具", "slot": "sight", "price": 0.3, "ads_fov": 0.8, "desc": "开镜时一颗红点，比照门清楚"},
	"holo": {"name": "全息瞄具", "slot": "sight", "price": 0.35, "ads_fov": 0.78, "desc": "圈点准星，近中距离好用"},
	"x2": {"name": "2 倍镜", "slot": "sight", "price": 0.5, "zoom": 2.2, "desc": "开镜放大 2 倍多（全屏瞄准镜）"},
	"scope": {"name": "狙击镜", "slot": "sight", "price": 0.6, "zoom": 6.0, "variable": true, "desc": "4~12 倍，开镜后滚轮调倍率，调好会记住"},
	"brake": {"name": "枪口制退器", "slot": "muzzle", "price": 0.3, "recoil_v": 0.72, "desc": "连射上跳 -28%"},
	"grip": {"name": "垂直握把", "slot": "under", "price": 0.3, "recoil_h": 0.55, "spread": 0.85, "desc": "左右抖动 -45%，散布 -15%"},
	"laser": {"name": "激光指示器", "slot": "under", "price": 0.2, "hip": 0.65, "desc": "腰射散布 -35%"},
}
const ATTACH_OK := {
	"xiujian": ["red", "brake", "laser"],
	"baoyu": ["red", "holo", "grip", "laser"],
	"zhuge": ["red", "holo", "x2", "brake", "grip", "laser"],
	"kongque": ["red", "holo", "x2", "scope", "brake", "grip", "laser"],
	"zhuihun": ["x2", "scope", "brake", "laser"],
}


func attach_price(weapon: String, a: String) -> int:
	return int(round(maxf(float(WEAPONS[weapon]["price"]), 400.0) * float(ATTACH[a]["price"]) / 10.0)) * 10

# 道具
const ITEMS := {
	"grenade": {"name": "佛怒唐莲", "desc": "唐门至高暗器。按 3 拿出来左键扔，爆炸把周围魂兽全部炸上天", "price": 60, "max": 5, "key": "3"},
	"pill": {"name": "回血丹", "desc": "按 H 直接吃（或者按 4 拿出来左键吃），立刻恢复 40% 体力，还能解毒", "price": 40, "max": 5, "key": "H"},
	"lure_gold": {"name": "引兽香", "desc": "接下来 5 次咬钩必定是百年以上的魂兽", "price": 120, "max": 3, "key": "自动", "ch": 3},
	"meat": {"name": "烤魂兽肉", "desc": "按 4 拿出来（再按 4 在肉和回血丹之间换），左键吃：饱食 +40、体力 +10。打死魂兽也常掉", "price": 15, "max": 10, "key": "4"},
	"bait_blood": {"name": "血腥饵 ×5", "desc": "钓上来的百年魂兽多，魂兽更凶，常带词缀，奖励 +30%", "price": 45, "max": 60, "key": "B", "bundle": 5, "ch": 2},
	"bait_soul": {"name": "魂晶饵 ×5", "desc": "千年魂兽出现率高好几倍，带词缀的更多（突破第四、五魂环靠它）", "price": 110, "max": 60, "key": "B", "bundle": 5, "ch": 3},
	"bait_gold": {"name": "金骨饵 ×5", "desc": "魂骨兽出现率 ×5，想刷魂骨就用它", "price": 130, "max": 60, "key": "B", "bundle": 5, "ch": 2},
}

# ================================================================ 鱼饵（引魂索每次咬钩消耗一个，按 B 换）
# w：十年 / 百年 / 千年 / 万年 的出现权重乘数；fierce：凶暴概率加成；affix：词缀概率加成；bone：魂骨兽概率倍数；reward：奖励倍数
const BAITS := {
	"grass": {"name": "青草饵", "item": "", "w": [1.0, 0.25, 0.04, 0.02], "fierce": 0.0, "affix": 0.0, "bone": 1.0, "reward": 1.0},
	"blood": {"name": "血腥饵", "item": "bait_blood", "w": [0.6, 1.4, 1.0, 0.8], "fierce": 0.3, "affix": 0.15, "bone": 1.0, "reward": 1.3},
	"soul": {"name": "魂晶饵", "item": "bait_soul", "w": [0.25, 1.2, 3.5, 2.5], "fierce": 0.1, "affix": 0.3, "bone": 1.5, "reward": 1.2},
	"gold": {"name": "金骨饵", "item": "bait_gold", "w": [0.8, 1.0, 1.2, 1.0], "fierce": 0.0, "affix": 0.1, "bone": 5.0, "reward": 1.0},
}
const BAIT_ORDER := ["grass", "blood", "soul", "gold"]


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


# ================================================================ 魂兽词缀（让每只魂兽打法不一样）
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
# 每张图自己的"奇遇"（代替原来千篇一律的兽潮）：天色 / 天气变化 + 专属魂兽 + 一只王
# mode：flock 天上飞过的一大群（打下来奖励 ×3），pack 从四面八方冲过来；env：天色天气
const CH_EVENTS := {
	1: {"name": "风铃鸟迁徙", "desc": "一大群风铃鸟从湖上飞过，在它们飞走之前打下来——每只奖励 ×3", "species": ["bird"], "n": 14, "mode": "flock", "king": "", "env": "gold", "color": Color(0.6, 1.0, 0.9)},
	2: {"name": "狼王夜袭", "desc": "天黑了。疾风狼王带着狼群从林子里扑出来，打死狼王必掉魂骨", "species": ["wolf"], "n": 10, "mode": "pack", "king": "wolf", "env": "night", "color": Color(1.0, 0.45, 0.35)},
	3: {"name": "星斗兽潮", "desc": "星辰坠落，星斗大森林的魂兽成群冲出来，鬼眼鹿王压阵", "species": ["stag", "raptor", "spiderling"], "n": 12, "mode": "pack", "king": "stag", "env": "stars", "color": Color(0.7, 0.6, 1.0)},
	4: {"name": "极北暴风雪", "desc": "暴风雪来了，看不远、走不快，雪原狼群借着风雪偷袭，冰甲龙王压阵", "species": ["husky", "snowape"], "n": 12, "mode": "pack", "king": "icehorn", "env": "blizzard", "color": Color(0.7, 0.9, 1.0)},
	5: {"name": "海神怒潮", "desc": "风暴压境，铁钳蟹爬满沙滩，海魂鸥成群俯冲，蟹王压阵", "species": ["crab", "gull"], "n": 14, "mode": "pack", "king": "crab", "env": "storm", "color": Color(0.5, 0.75, 1.0)},
}
const TIDE_FIRST := 300.0              # 进图 5 分钟后第一次奇遇
const TIDE_GAP := [380.0, 520.0]
const TIDE_TIME := 75.0

# ================================================================ 外观：暗器皮肤、装扮（暗器铺"外观"页买；打败每章 Boss 送一款）
# pal：换掉暗器模型的哪些材质颜色；glow：发光部件的颜色；metal：金属感
const GUN_SKINS := {
	"default": {"name": "唐门原色", "price": 0, "desc": "木头、朱漆、青铜，唐门的老样子"},
	"jade": {"name": "碧玉", "price": 2000, "desc": "整块碧玉雕出来的暗器，温润发亮",
		"pal": {"wood": Color(0.2, 0.55, 0.42), "lacquer": Color(0.16, 0.5, 0.38), "bronze": Color(0.92, 0.92, 0.86), "gold": Color(0.96, 0.95, 0.88), "iron": Color(0.75, 0.85, 0.8), "black": Color(0.08, 0.18, 0.14)}, "glow": Color(0.4, 1.0, 0.7), "metal": 0.4},
	"blood": {"name": "血玉", "price": 5000, "desc": "暗红血玉，金色包边，杀气很重",
		"pal": {"wood": Color(0.32, 0.03, 0.05), "lacquer": Color(0.5, 0.02, 0.05), "bronze": Color(0.18, 0.17, 0.19), "gold": Color(1.0, 0.72, 0.28), "iron": Color(0.14, 0.13, 0.14), "black": Color(0.05, 0.02, 0.02)}, "glow": Color(1.0, 0.15, 0.1), "metal": 0.6},
	"ice": {"name": "寒冰", "price": 12000, "desc": "极北寒冰打磨，冷光闪闪",
		"pal": {"wood": Color(0.72, 0.86, 0.96), "lacquer": Color(0.55, 0.76, 0.95), "bronze": Color(0.86, 0.95, 1.0), "gold": Color(0.7, 0.9, 1.0), "iron": Color(0.6, 0.72, 0.84), "black": Color(0.2, 0.3, 0.42)}, "glow": Color(0.4, 0.9, 1.0), "metal": 0.8},
	"shadow": {"name": "暗影", "price": 30000, "desc": "通体哑光黑，幽紫色的光",
		"pal": {"wood": Color(0.06, 0.05, 0.07), "lacquer": Color(0.1, 0.06, 0.12), "bronze": Color(0.12, 0.1, 0.14), "gold": Color(0.55, 0.3, 0.9), "iron": Color(0.08, 0.08, 0.1), "black": Color(0.03, 0.03, 0.04)}, "glow": Color(0.7, 0.35, 1.0), "metal": 0.3},
	"dragon": {"name": "金龙", "price": 90000, "desc": "纯金打造，金光闪闪，土豪专用",
		"pal": {"wood": Color(0.85, 0.62, 0.2), "lacquer": Color(0.95, 0.72, 0.25), "bronze": Color(1.0, 0.82, 0.35), "gold": Color(1.0, 0.9, 0.5), "iron": Color(0.8, 0.6, 0.25), "black": Color(0.45, 0.3, 0.1)}, "glow": Color(1.0, 0.85, 0.4), "metal": 1.0},
	"star": {"name": "星河", "price": 160000, "desc": "深蓝夜空里流着星光",
		"pal": {"wood": Color(0.05, 0.07, 0.2), "lacquer": Color(0.08, 0.1, 0.3), "bronze": Color(0.5, 0.6, 1.0), "gold": Color(0.8, 0.85, 1.0), "iron": Color(0.1, 0.12, 0.25), "black": Color(0.02, 0.03, 0.08)}, "glow": Color(0.5, 0.7, 1.0), "metal": 0.7},
	"mandala": {"name": "曼陀罗", "price": 0, "boss": "mandala", "desc": "打败湖主 · 千年曼陀罗蛇解锁",
		"pal": {"wood": Color(0.3, 0.12, 0.35), "lacquer": Color(0.42, 0.1, 0.45), "bronze": Color(0.35, 0.75, 0.35), "gold": Color(0.6, 1.0, 0.4), "iron": Color(0.2, 0.15, 0.22)}, "glow": Color(0.7, 1.0, 0.4), "metal": 0.4},
	"spider": {"name": "魔蛛", "price": 0, "boss": "spider", "desc": "打败森林之主 · 人面魔蛛解锁",
		"pal": {"wood": Color(0.08, 0.06, 0.06), "lacquer": Color(0.3, 0.02, 0.04), "bronze": Color(0.6, 0.05, 0.08), "gold": Color(0.9, 0.2, 0.2), "iron": Color(0.12, 0.1, 0.1)}, "glow": Color(1.0, 0.2, 0.25), "metal": 0.5},
	"titan": {"name": "泰坦", "price": 0, "boss": "titan", "desc": "打败星斗之王 · 泰坦巨猿解锁",
		"pal": {"wood": Color(0.35, 0.28, 0.22), "lacquer": Color(0.45, 0.36, 0.28), "bronze": Color(0.55, 0.5, 0.45), "gold": Color(1.0, 0.7, 0.3), "iron": Color(0.3, 0.28, 0.26)}, "glow": Color(1.0, 0.6, 0.2), "metal": 0.3},
	"frostdragon": {"name": "冰霜巨龙", "price": 0, "boss": "icedragon", "desc": "打败极北之主 · 冰霜巨龙解锁",
		"pal": {"wood": Color(0.9, 0.95, 1.0), "lacquer": Color(0.7, 0.85, 1.0), "bronze": Color(0.4, 0.7, 1.0), "gold": Color(0.6, 0.95, 1.0), "iron": Color(0.8, 0.88, 0.95)}, "glow": Color(0.5, 0.95, 1.0), "metal": 0.9},
	"lake": {"name": "湖光", "price": 0, "codex": "island", "desc": "集齐湖心岛的猎魂录（每种魂兽三颗星）解锁",
		"pal": {"wood": Color(0.55, 0.75, 0.85), "lacquer": Color(0.35, 0.6, 0.8), "bronze": Color(0.95, 0.95, 1.0), "gold": Color(0.7, 0.95, 1.0), "iron": Color(0.5, 0.6, 0.7)}, "glow": Color(0.6, 0.9, 1.0), "metal": 0.6},
	"sunset": {"name": "落日", "price": 0, "codex": "forest", "desc": "集齐落日森林的猎魂录解锁",
		"pal": {"wood": Color(0.7, 0.35, 0.15), "lacquer": Color(0.85, 0.4, 0.12), "bronze": Color(1.0, 0.75, 0.4), "gold": Color(1.0, 0.8, 0.45), "iron": Color(0.45, 0.25, 0.15)}, "glow": Color(1.0, 0.6, 0.25), "metal": 0.5},
	"starwood": {"name": "星斗", "price": 0, "codex": "deepforest", "desc": "集齐星斗大森林的猎魂录解锁",
		"pal": {"wood": Color(0.1, 0.18, 0.2), "lacquer": Color(0.08, 0.3, 0.35), "bronze": Color(0.4, 0.8, 1.0), "gold": Color(0.5, 1.0, 0.95), "iron": Color(0.12, 0.2, 0.25)}, "glow": Color(0.3, 0.9, 1.0), "metal": 0.5},
	"aurora": {"name": "极光", "price": 0, "codex": "snow", "desc": "集齐极北之地的猎魂录解锁",
		"pal": {"wood": Color(0.85, 0.9, 1.0), "lacquer": Color(0.5, 0.95, 0.75), "bronze": Color(0.8, 0.6, 1.0), "gold": Color(0.6, 1.0, 0.85), "iron": Color(0.7, 0.75, 0.9)}, "glow": Color(0.5, 1.0, 0.8), "metal": 0.7},
	"tide": {"name": "海潮", "price": 0, "codex": "sea", "desc": "集齐海神岛的猎魂录解锁",
		"pal": {"wood": Color(0.05, 0.3, 0.4), "lacquer": Color(0.1, 0.5, 0.6), "bronze": Color(0.9, 0.85, 0.6), "gold": Color(1.0, 0.95, 0.7), "iron": Color(0.1, 0.25, 0.3)}, "glow": Color(0.4, 1.0, 1.0), "metal": 0.6},
	"abyss": {"name": "深海", "price": 0, "boss": "whale", "desc": "打败海神岛之主 · 深海魔鲸解锁",
		"pal": {"wood": Color(0.03, 0.12, 0.2), "lacquer": Color(0.04, 0.2, 0.3), "bronze": Color(0.2, 0.6, 0.7), "gold": Color(0.4, 0.95, 0.9), "iron": Color(0.05, 0.15, 0.2)}, "glow": Color(0.3, 1.0, 0.9), "metal": 0.6},
}
const GUN_SKIN_ORDER := ["default", "jade", "blood", "ice", "shadow", "dragon", "star", "mandala", "spider", "titan", "frostdragon", "abyss", "lake", "sunset", "starwood", "aurora", "tide"]

# ================================================================ 猎魂录：每张图的每种魂兽三颗星（在一张图多待的理由）
# ★ 猎杀 5 只；★★ 猎杀一只带词缀的；★★★ 猎杀一只千年以上的，或者它的精英（王）
# 每颗星永久：体力 +2、伤害 +0.5%。一张图的星星全部集齐，送这张图的专属暗器皮肤
const CODEX_KILLS := 5
const CODEX_MAP_SKIN := {"island": "lake", "forest": "sunset", "deepforest": "starwood", "snow": "aurora", "sea": "tide"}
# 装扮：长袍颜色、衣服上的点缀色、帽子（队友看到的样子，也是第一人称的袖子）
const OUTFITS := {
	"default": {"name": "素白长衫", "price": 0, "robe": Color(0.92, 0.92, 0.88), "hat": "", "desc": "新手魂师的衣服"},
	"tang": {"name": "唐门黑袍", "price": 1500, "robe": Color(0.09, 0.09, 0.12), "accent": Color(0.9, 0.7, 0.3), "hat": "douli", "desc": "黑袍金边，戴竹帽"},
	"flame": {"name": "赤焰袍", "price": 6000, "robe": Color(0.68, 0.1, 0.07), "accent": Color(1.0, 0.6, 0.2), "hat": "", "desc": "火红长袍"},
	"frost": {"name": "冰蓝袍", "price": 6000, "robe": Color(0.55, 0.75, 0.95), "accent": Color(0.92, 0.97, 1.0), "hat": "hood", "desc": "冰蓝长袍带兜帽"},
	"gold": {"name": "金甲", "price": 60000, "robe": Color(0.85, 0.63, 0.22), "accent": Color(1.0, 0.9, 0.5), "hat": "crown", "desc": "一身金甲，头戴金冠"},
	"sea": {"name": "海神袍", "price": 0, "boss": "whale", "robe": Color(0.1, 0.4, 0.5), "accent": Color(0.5, 1.0, 0.9), "hat": "crown", "desc": "通关海神岛解锁"},
}
const OUTFIT_ORDER := ["default", "tang", "flame", "frost", "gold", "sea"]


# ================================================================ 成就（J 或者暂停菜单里看）
# stat：Profile.stats 里的计数到 n 就完成；special：别的条件（World._ach_specials 里判断）
const ACHIEVEMENTS := [
	{"id": "kill_1", "name": "初次猎魂", "desc": "打死第一只魂兽", "stat": "kills", "n": 1, "reward": 50},
	{"id": "kill_100", "name": "百兽猎手", "desc": "打死 100 只魂兽", "stat": "kills", "n": 100, "reward": 1500},
	{"id": "kill_500", "name": "五百斩", "desc": "打死 500 只魂兽", "stat": "kills", "n": 500, "reward": 12000},
	{"id": "kill_2000", "name": "千兽猎王", "desc": "打死 2000 只魂兽", "stat": "kills", "n": 2000, "reward": 80000},
	{"id": "air_50", "name": "空中杀手", "desc": "空中击杀 50 只", "stat": "air_kills", "n": 50, "reward": 1200},
	{"id": "juggle_8", "name": "天女散花", "desc": "空中连击 8 下以上打死一只", "stat": "juggle8", "n": 1, "reward": 1500},
	{"id": "head_100", "name": "百步穿杨", "desc": "爆头击杀 100 只", "stat": "head_kills", "n": 100, "reward": 3000},
	{"id": "far_80", "name": "追魂夺命", "desc": "80 米外打死一只", "stat": "far80", "n": 1, "reward": 2000},
	{"id": "affix_2", "name": "硬骨头", "desc": "打死一只带两个词缀的魂兽", "stat": "affix2", "n": 1, "reward": 1500},
	{"id": "elite_1", "name": "斩王", "desc": "打死第一只精英（王）", "stat": "elites", "n": 1, "reward": 800},
	{"id": "elite_30", "name": "王者克星", "desc": "打死 30 只精英", "stat": "elites", "n": 30, "reward": 30000},
	{"id": "boss_mandala", "name": "湖主陨落", "desc": "击败湖主 · 千年曼陀罗蛇", "stat": "boss_mandala", "n": 1, "reward": 1000},
	{"id": "boss_spider", "name": "森林之主", "desc": "击败人面魔蛛", "stat": "boss_spider", "n": 1, "reward": 4000},
	{"id": "boss_titan", "name": "撼山", "desc": "击败万年泰坦巨猿", "stat": "boss_titan", "n": 1, "reward": 12000},
	{"id": "boss_icedragon", "name": "屠龙", "desc": "击败万年冰霜巨龙", "stat": "boss_icedragon", "n": 1, "reward": 30000},
	{"id": "boss_whale", "name": "镇海", "desc": "击败十万年深海魔鲸", "stat": "boss_whale", "n": 1, "reward": 80000},
	{"id": "tide_20", "name": "守住兽潮", "desc": "在兽潮里打死 20 只", "stat": "tide_kills", "n": 20, "reward": 2500},
	{"id": "bone_1", "name": "第一块魂骨", "desc": "捡到一块魂骨", "stat": "bones", "n": 1, "reward": 600},
	{"id": "bone_6", "name": "六骨齐全", "desc": "六个部位都装上魂骨", "special": "bones6", "reward": 25000},
	{"id": "ring_1", "name": "第一魂环", "desc": "吸收第一个魂环", "special": "rings1", "reward": 200},
	{"id": "ring_5", "name": "五环魂王", "desc": "吸收五个魂环", "special": "rings5", "reward": 8000},
	{"id": "ring_wan", "name": "万年魂环", "desc": "吸收一个万年魂环", "special": "wannian", "reward": 20000},
	{"id": "lv_20", "name": "魂尊", "desc": "修炼到 20 级", "special": "lv20", "reward": 500},
	{"id": "lv_50", "name": "魂王", "desc": "修炼到 50 级", "special": "lv50", "reward": 10000},
	{"id": "lv_80", "name": "魂斗罗", "desc": "修炼到 80 级", "special": "lv80", "reward": 40000},
	{"id": "god", "name": "成神", "desc": "修炼到 100 级、吸收第十魂环", "special": "god", "reward": 200000},
	{"id": "bounty_10", "name": "赏金猎人", "desc": "完成 10 个悬赏", "stat": "bounties", "n": 10, "reward": 3000},
	{"id": "codex_1", "name": "图鉴大师", "desc": "集齐一张图的猎魂录", "stat": "codex_maps", "n": 1, "reward": 5000},
	{"id": "revive_5", "name": "救死扶伤", "desc": "把倒地的队友拉起来 5 次", "stat": "revives", "n": 5, "reward": 1500},
	{"id": "gull_10", "name": "海鸥克星", "desc": "打下 10 只海鸥", "stat": "gulls", "n": 10, "reward": 1500},
	{"id": "sell_50", "name": "唐门商人", "desc": "往收购箱卖 50 件东西", "stat": "sold", "n": 50, "reward": 2000},
	{"id": "arsenal", "name": "唐门全套", "desc": "五把暗器同时拿在手里", "special": "arsenal", "reward": 20000},
	{"id": "skins_5", "name": "爱美的魂师", "desc": "拥有 5 款暗器皮肤", "special": "skins5", "reward": 5000},
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

# ================================================================ 魂师等级与魂环
# 每 10 级是一个瓶颈，要吸收魂环才能继续升级。第 n 个魂环至少要这个年份：
# 一 十年 / 二三 百年 / 四五 千年 / 六~九 万年 / 十 十万年（海神岛之主掉）。100 级 + 第十魂环 = 成神（通关）
const RING_MIN_AGE := [0, 1, 1, 2, 2, 3, 3, 3, 3, 4]
const MAX_LEVEL := 100
const MAX_RINGS := 10

## 升一级要的修为：越往后越多（指数），每章大约 20 级
func xp_to_next(level: int) -> int:
	return int(40.0 * pow(1.065, level)) + 8 * level


# ================================================================ 数值：经验、金币、价格都按章节放大
# 每只魂兽属于哪一章（它住在哪张图）
const SPECIES_CH := {
	"rabbit": 1, "vine": 1, "bird": 1, "moth": 1,
	"wolf": 2, "rhino": 2, "ape": 2, "snake": 2,
	"stag": 3, "bat": 3, "raptor": 3, "spiderling": 3, "frog": 3,
	"husky": 4, "icedeer": 4, "icehorn": 4, "snowape": 4, "icefish": 4,
	"crab": 5, "gull": 5, "reeffish": 5, "shark": 5, "manta": 5,
}
const CH_REF_LEVEL := {1: 10, 2: 30, 3: 50, 4: 70, 5: 90}      # 这一章大概在多少级
const CH_MONEY := {1: 12.0, 2: 45.0, 3: 120.0, 4: 280.0, 5: 600.0}   # 这一章一只普通魂兽给多少金魂币
const CH_PRICE := {1: 1.0, 2: 3.0, 3: 8.0, 4: 20.0, 5: 45.0}         # 道具、鱼饵价格倍数
const KILLS_PER_LEVEL := 24.0                                      # 这一章里大约杀多少只升一级
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


## 打死一只给多少修为：这一章的参考等级升一级要的修为 / 12 × 年份倍数 × 这种魂兽相对同章平均的强弱
func kill_xp(species: String, age: int) -> float:
	var ch := int(SPECIES_CH.get(species, 1))
	return float(xp_to_next(int(CH_REF_LEVEL[ch]))) / KILLS_PER_LEVEL * float(AGES[age]["xp"]) * species_rel(species, "xp")


func kill_money(species: String, age: int) -> float:
	var ch := int(SPECIES_CH.get(species, 1))
	return float(CH_MONEY[ch]) * float(AGES[age]["reward"]) * species_rel(species, "reward")


func item_price(id: String) -> int:
	return int(round(float(ITEMS[id]["price"]) * float(CH_PRICE.get(cur_chapter, 1.0))))


## 玩家伤害：等级（每级 +1.2%）；魂骨、猎魂录、升级、魂技在别处乘
func level_damage(level: int) -> float:
	return 1.0 + level * 0.012


## 联机时"猎杀 N 只"的任务按人数加量（每多一个人 +75%），不然几个人一起打太快
func quest_target(q: Dictionary, players: int) -> int:
	var n := int(q.get("n", 1))
	if str(q.get("type", "")) in ["kill", "hunt"] and players > 1:
		return ceili(n * (1.0 + 0.75 * (players - 1)))
	return n


func titles(level: int) -> String:
	var t := ["魂士", "魂师", "大魂师", "魂尊", "魂宗", "魂王", "魂帝", "魂圣", "魂斗罗", "封号斗罗", "神"]
	return t[clampi(level / 10, 0, t.size() - 1)]


# ================================================================ 魂技
# 每个武魂 3 个魂环位，每个位有两个魂技可选（吸收魂环时二选一）
# type：launch 炸飞 / root 定身 / mark 易伤 / pull 牵引 / beam 光束 / projectile 飞弹 /
#       rain 范围连击 / buff 增益 / heal 治疗 / shield 护盾 / dash 冲刺 / leap 跳跃
# target：self 以自己为中心 / aim 以准星指向的地面为中心 / dir 朝准星方向
const SKILLS := {
	# 蓝银草
	"lyc_root": {"name": "蓝银缠绕", "type": "root", "target": "aim", "radius": 6.0, "dur": 3.5, "damage": 10.0, "cost": 25, "cd": 8.0, "desc": "准星处 6 米内的魂兽被蓝银草缠住，空中的也会被吊在原地"},
	"lyc_spike": {"name": "蓝银突刺", "type": "launch", "target": "aim", "radius": 4.5, "damage": 30.0, "impulse": 9.0, "cost": 25, "cd": 7.0, "desc": "地面刺出蓝银草，把魂兽挑上天"},
	"lyc_mark": {"name": "蓝银飞索", "type": "grapple", "target": "dir", "range": 40.0, "cost": 15, "cd": 5.0, "desc": "蓝银草缠住准星处，把自己拉过去（能上树、上崖、跨过水面）"},
	"lyc_pull": {"name": "蓝银牵引", "type": "pull", "target": "aim", "radius": 12.0, "dur": 3.0, "force": 18.0, "cost": 30, "cd": 12.0, "desc": "把 12 米内的魂兽拉到一起"},
	"lyc_cage": {"name": "蓝银囚笼", "type": "root", "target": "aim", "radius": 10.0, "dur": 5.0, "damage": 25.0, "cost": 50, "cd": 20.0, "desc": "大范围定身 5 秒"},
	"lyc_dance": {"name": "蓝银乱舞", "type": "rain", "target": "aim", "radius": 6.0, "damage": 30.0, "impulse": 7.0, "waves": 3, "cost": 50, "cd": 18.0, "desc": "连续三波突刺，把魂兽一直挑在空中"},
	# 镰刀
	"ld_whirl": {"name": "旋风斩", "type": "launch", "target": "self", "radius": 5.5, "damage": 45.0, "impulse": 8.0, "cost": 25, "cd": 7.0, "desc": "以自己为中心横扫，把身边魂兽砍飞"},
	"ld_scythe": {"name": "死神之镰", "type": "beam", "target": "dir", "range": 40.0, "damage": 90.0, "pierce": 5, "cost": 25, "cd": 7.0, "desc": "一道贯穿 40 米的镰刀光"},
	"ld_reap": {"name": "镰影步", "type": "blink", "target": "dir", "dist": 14.0, "stat": "dmg", "amount": 0.3, "dur": 4.0, "cost": 20, "cd": 6.0, "desc": "瞬移到准星方向 14 米外，之后 4 秒伤害 +30%"},
	"ld_fly": {"name": "飞镰", "type": "projectile", "target": "dir", "speed": 35.0, "radius": 4.0, "damage": 70.0, "impulse": 6.0, "cost": 30, "cd": 10.0, "desc": "掷出旋转飞镰，命中爆开"},
	"ld_doom": {"name": "死神降临", "type": "launch", "target": "self", "radius": 11.0, "damage": 120.0, "impulse": 11.0, "cost": 55, "cd": 22.0, "desc": "大范围收割"},
	"ld_shadow": {"name": "镰影", "type": "dash", "target": "dir", "dist": 12.0, "damage": 60.0, "radius": 3.0, "cost": 30, "cd": 8.0, "desc": "化成镰影冲刺，路过的魂兽受伤"},
	# 香肠
	"xc_heal": {"name": "香肠回复", "type": "heal", "target": "self", "radius": 15.0, "amount": 45.0, "cost": 25, "cd": 10.0, "desc": "15 米内所有队友回复 45 体力"},
	"xc_boost": {"name": "香肠增幅", "type": "buff", "target": "self", "radius": 15.0, "stat": "dmg", "amount": 0.2, "dur": 12.0, "team": true, "cost": 30, "cd": 18.0, "desc": "全队伤害 +20%，持续 12 秒"},
	"xc_regen": {"name": "镜像香肠", "type": "buff", "target": "self", "radius": 15.0, "stat": "regen", "amount": 8.0, "dur": 10.0, "team": true, "cost": 30, "cd": 16.0, "desc": "全队每秒回复 8 体力"},
	"xc_fly": {"name": "飞行香肠", "type": "fly", "target": "self", "radius": 15.0, "stat": "speed", "amount": 0.25, "dur": 8.0, "team": true, "cost": 30, "cd": 18.0, "desc": "自己飞 8 秒（空格上升、Ctrl 下降），全队移速 +25%"},
	"xc_big": {"name": "大香肠", "type": "shield", "target": "self", "radius": 15.0, "amount": 60.0, "dur": 10.0, "team": true, "cost": 50, "cd": 24.0, "desc": "全队 60 点护盾"},
	"xc_boom": {"name": "爆炸香肠", "type": "projectile", "target": "dir", "speed": 28.0, "radius": 6.0, "damage": 110.0, "impulse": 10.0, "cost": 45, "cd": 14.0, "desc": "扔出会爆炸的香肠"},
	# 白虎
	"bh_guard": {"name": "白虎护身障", "type": "shield", "target": "self", "amount": 60.0, "dur": 8.0, "cost": 25, "cd": 12.0, "desc": "自己获得 60 点护盾"},
	"bh_wave": {"name": "白虎烈光波", "type": "beam", "target": "dir", "range": 35.0, "damage": 80.0, "pierce": 4, "cost": 25, "cd": 7.0, "desc": "一道贯穿的光波"},
	"bh_vajra": {"name": "白虎金刚变", "type": "giant", "target": "self", "scale": 1.5, "dr": 0.35, "dmg": 0.25, "dur": 10.0, "cost": 30, "cd": 18.0, "desc": "身体变大 1.5 倍 10 秒：受伤 -35%，伤害 +25%"},
	"bh_meteor": {"name": "白虎流星雨", "type": "rain", "target": "aim", "radius": 7.0, "damage": 40.0, "impulse": 6.0, "waves": 4, "cost": 35, "cd": 14.0, "desc": "准星处落下四波流星"},
	"bh_charge": {"name": "白虎冲击", "type": "dash", "target": "dir", "dist": 14.0, "damage": 80.0, "radius": 3.5, "impulse": 8.0, "cost": 40, "cd": 12.0, "desc": "猛冲撞飞路上的魂兽"},
	"bh_roar": {"name": "白虎咆哮", "type": "mark", "target": "self", "radius": 14.0, "dur": 10.0, "mult": 1.4, "cost": 45, "cd": 20.0, "desc": "身边魂兽受到伤害 +40%"},
	# 幽冥灵猫
	"ym_dash": {"name": "幽冥突刺", "type": "dash", "target": "dir", "dist": 10.0, "damage": 40.0, "radius": 2.5, "cost": 20, "cd": 5.0, "desc": "瞬间突进 10 米"},
	"ym_claw": {"name": "幽冥影爪", "type": "beam", "target": "dir", "range": 14.0, "damage": 110.0, "pierce": 2, "cost": 25, "cd": 7.0, "desc": "近距离高伤害爪击"},
	"ym_clone": {"name": "鬼影分身", "type": "buff", "target": "self", "stat": "crit", "amount": 1.0, "dur": 6.0, "cost": 30, "cd": 16.0, "desc": "6 秒内每一发都算爆头"},
	"ym_slash": {"name": "幽冥斩", "type": "launch", "target": "aim", "radius": 4.5, "damage": 55.0, "impulse": 9.0, "cost": 30, "cd": 9.0, "desc": "在准星处斩出一道影刃，把魂兽挑飞"},
	"ym_hundred": {"name": "幽冥百爪", "type": "rain", "target": "aim", "radius": 6.0, "damage": 30.0, "impulse": 4.0, "waves": 6, "cost": 50, "cd": 18.0, "desc": "六连爪影"},
	"ym_ghost": {"name": "幽冥灵魂", "type": "invis", "target": "self", "stat": "speed", "amount": 0.5, "dur": 6.0, "cost": 30, "cd": 16.0, "desc": "隐身 6 秒：魂兽和 Boss 看不见你，移速 +50%"},
	# 火凤凰
	"hf_fire": {"name": "凤凰火线", "type": "projectile", "target": "dir", "speed": 40.0, "radius": 4.5, "damage": 65.0, "impulse": 5.0, "burn": 8.0, "cost": 25, "cd": 6.0, "desc": "火球命中爆开，灼烧魂兽"},
	"hf_bath": {"name": "浴火", "type": "buff", "target": "self", "stat": "dr", "amount": 0.4, "stat2": "regen", "amount2": 10.0, "dur": 8.0, "cost": 25, "cd": 14.0, "desc": "8 秒内受伤 -40%，每秒回 10 体力"},
	"hf_wing": {"name": "凤翼天翔", "type": "leap", "target": "self", "height": 12.0, "radius": 6.0, "damage": 60.0, "impulse": 8.0, "cost": 30, "cd": 10.0, "desc": "冲上高空，落地炸飞周围魂兽"},
	"hf_rain": {"name": "火雨", "type": "rain", "target": "aim", "radius": 7.0, "damage": 35.0, "impulse": 3.0, "waves": 5, "burn": 6.0, "cost": 35, "cd": 14.0, "desc": "准星处降下火雨"},
	"hf_blast": {"name": "凤凰啸天击", "type": "projectile", "target": "dir", "speed": 30.0, "radius": 9.0, "damage": 160.0, "impulse": 12.0, "burn": 12.0, "cost": 55, "cd": 20.0, "desc": "巨大的凤凰火球"},
	"hf_rebirth": {"name": "涅槃", "type": "heal", "target": "self", "radius": 20.0, "amount": 100.0, "cost": 55, "cd": 30.0, "desc": "全队回满体力"},
	# 七宝琉璃塔
	"qb_power": {"name": "力量增幅", "type": "buff", "target": "self", "radius": 20.0, "stat": "dmg", "amount": 0.25, "dur": 12.0, "team": true, "cost": 25, "cd": 16.0, "desc": "全队伤害 +25%"},
	"qb_speed": {"name": "速度增幅", "type": "buff", "target": "self", "radius": 20.0, "stat": "speed", "amount": 0.3, "dur": 12.0, "team": true, "cost": 25, "cd": 16.0, "desc": "全队移速和换弹 +30%"},
	"qb_soul": {"name": "魂力增幅", "type": "buff", "target": "self", "radius": 20.0, "stat": "soul", "amount": 1.0, "dur": 12.0, "team": true, "cost": 20, "cd": 20.0, "desc": "全队魂力恢复翻倍"},
	"qb_guard": {"name": "防御增幅", "type": "buff", "target": "self", "radius": 20.0, "stat": "dr", "amount": 0.3, "dur": 10.0, "team": true, "cost": 35, "cd": 20.0, "desc": "全队受伤 -30%，持续 10 秒"},
	"qb_seven": {"name": "七宝转出有琉璃", "type": "buff", "target": "self", "radius": 25.0, "stat": "all", "amount": 0.35, "dur": 12.0, "team": true, "cost": 55, "cd": 28.0, "desc": "全队伤害、移速、换弹全部 +35%"},
	"qb_weak": {"name": "削弱", "type": "mark", "target": "self", "radius": 16.0, "dur": 10.0, "mult": 1.4, "cost": 40, "cd": 18.0, "desc": "16 米内魂兽受到伤害 +40%"},
	# 昊天锤
	"ht_slam": {"name": "重锤", "type": "launch", "target": "aim", "radius": 5.5, "damage": 50.0, "impulse": 11.0, "cost": 25, "cd": 7.0, "desc": "锤子砸地，把一片魂兽震上天"},
	"ht_throw": {"name": "大须弥锤", "type": "projectile", "target": "dir", "speed": 30.0, "radius": 5.0, "damage": 90.0, "impulse": 9.0, "cost": 30, "cd": 9.0, "desc": "扔出昊天锤"},
	"ht_break": {"name": "破甲", "type": "mark", "target": "aim", "radius": 7.0, "dur": 10.0, "mult": 1.5, "cost": 30, "cd": 14.0, "desc": "准星处魂兽受到伤害 +50%（无视铁甲犀的甲）"},
	"ht_nine": {"name": "昊天九绝", "type": "buff", "target": "self", "stat": "dmg", "amount": 0.45, "dur": 8.0, "cost": 35, "cd": 16.0, "desc": "8 秒内伤害 +45%"},
	"ht_storm": {"name": "乱披风锤法", "type": "rain", "target": "aim", "radius": 6.5, "damage": 60.0, "impulse": 10.0, "waves": 3, "cost": 50, "cd": 18.0, "desc": "三连砸，魂兽落不了地"},
	"ht_true": {"name": "昊天真身", "type": "giant", "target": "self", "scale": 1.8, "dr": 0.5, "dmg": 0.4, "dur": 10.0, "cost": 50, "cd": 24.0, "desc": "昊天锤真身：体型 ×1.8，受伤 -50%，伤害 +40%"},
	# 六翼天使
	"ls_light": {"name": "天使圣光", "type": "beam", "target": "dir", "range": 50.0, "damage": 85.0, "pierce": 5, "cost": 25, "cd": 7.0, "desc": "贯穿的圣光"},
	"ls_shield": {"name": "圣光护盾", "type": "shield", "target": "self", "radius": 15.0, "amount": 40.0, "dur": 10.0, "team": true, "cost": 30, "cd": 16.0, "desc": "全队 40 点护盾"},
	"ls_wing": {"name": "天使之翼", "type": "fly", "target": "self", "dur": 7.0, "cost": 25, "cd": 14.0, "desc": "展开六翼飞 7 秒（空格上升、Ctrl 下降），落地砸飞周围魂兽", "radius": 5.0, "damage": 50.0, "impulse": 7.0},
	"ls_judge": {"name": "审判", "type": "launch", "target": "aim", "radius": 7.0, "damage": 70.0, "impulse": 9.0, "cost": 35, "cd": 11.0, "desc": "准星处降下审判之光"},
	"ls_sword": {"name": "天使圣剑", "type": "beam", "target": "dir", "range": 70.0, "damage": 200.0, "pierce": 8, "cost": 55, "cd": 20.0, "desc": "一剑贯穿"},
	"ls_domain": {"name": "神圣领域", "type": "buff", "target": "self", "radius": 18.0, "stat": "all", "amount": 0.3, "dur": 12.0, "team": true, "cost": 55, "cd": 28.0, "desc": "全队伤害、移速 +30%，每秒回 5 体力"},
	# ---- 第四、第五魂环 ----
	"lyc_wall": {"name": "蓝银囚牢", "type": "root", "target": "aim", "radius": 14.0, "dur": 6.0, "damage": 60.0, "cost": 60, "cd": 22.0, "desc": "14 米内所有魂兽定身 6 秒"},
	"lyc_storm": {"name": "蓝银风暴", "type": "rain", "target": "aim", "radius": 9.0, "damage": 60.0, "impulse": 9.0, "waves": 5, "cost": 60, "cd": 20.0, "desc": "五波蓝银突刺，魂兽一直落不了地"},
	"lyc_king": {"name": "蓝银皇降临", "type": "launch", "target": "aim", "radius": 14.0, "damage": 240.0, "impulse": 13.0, "cost": 75, "cd": 30.0, "desc": "蓝银皇虚影破土而出，大范围挑飞"},
	"lyc_life": {"name": "蓝银生命", "type": "heal", "target": "self", "radius": 25.0, "amount": 120.0, "cost": 70, "cd": 32.0, "desc": "全队回复 120 体力"},
	"ld_moon": {"name": "血月之镰", "type": "beam", "target": "dir", "range": 60.0, "damage": 260.0, "pierce": 8, "cost": 60, "cd": 18.0, "desc": "一道血色镰光"},
	"ld_harvest": {"name": "灵魂收割", "type": "mark", "target": "self", "radius": 18.0, "dur": 12.0, "mult": 1.6, "cost": 60, "cd": 24.0, "desc": "18 米内魂兽受到伤害 +60%"},
	"ld_god": {"name": "死神领域", "type": "rain", "target": "aim", "radius": 10.0, "damage": 90.0, "impulse": 8.0, "waves": 6, "cost": 75, "cd": 30.0, "desc": "六轮死神镰影"},
	"ld_fury": {"name": "狂镰", "type": "buff", "target": "self", "stat": "dmg", "amount": 0.7, "dur": 10.0, "cost": 70, "cd": 30.0, "desc": "10 秒内伤害 +70%"},
	"xc_feast": {"name": "香肠盛宴", "type": "heal", "target": "self", "radius": 25.0, "amount": 150.0, "cost": 60, "cd": 26.0, "desc": "全队回复 150 体力"},
	"xc_power": {"name": "力量香肠", "type": "buff", "target": "self", "radius": 25.0, "stat": "dmg", "amount": 0.45, "dur": 14.0, "team": true, "cost": 60, "cd": 26.0, "desc": "全队伤害 +45%"},
	"xc_giant": {"name": "巨型香肠", "type": "shield", "target": "self", "radius": 25.0, "amount": 150.0, "dur": 12.0, "team": true, "cost": 75, "cd": 34.0, "desc": "全队 150 点护盾"},
	"xc_nuke": {"name": "香肠天降", "type": "rain", "target": "aim", "radius": 10.0, "damage": 110.0, "impulse": 12.0, "waves": 4, "cost": 75, "cd": 30.0, "desc": "天上掉下四轮爆炸香肠"},
	"bh_tiger": {"name": "白虎裂光", "type": "beam", "target": "dir", "range": 60.0, "damage": 280.0, "pierce": 8, "cost": 60, "cd": 18.0, "desc": "巨大的裂光波"},
	"bh_body": {"name": "白虎真身", "type": "giant", "target": "self", "scale": 2.2, "dr": 0.6, "dmg": 0.5, "dur": 12.0, "cost": 60, "cd": 28.0, "desc": "化身巨虎 12 秒：体型 ×2.2，受伤 -60%，伤害 +50%"},
	"bh_king": {"name": "白虎流星雨·极", "type": "rain", "target": "aim", "radius": 11.0, "damage": 100.0, "impulse": 9.0, "waves": 6, "cost": 75, "cd": 30.0, "desc": "六轮流星"},
	"bh_rage": {"name": "邪眸白虎", "type": "buff", "target": "self", "stat": "all", "amount": 0.5, "dur": 12.0, "cost": 70, "cd": 32.0, "desc": "伤害、移速、换弹 +50%"},
	"ym_blink": {"name": "幽冥瞬影", "type": "blink", "target": "dir", "dist": 18.0, "damage": 160.0, "radius": 3.5, "stat": "crit", "amount": 1.0, "dur": 3.0, "cost": 50, "cd": 10.0, "desc": "瞬移 18 米，路上的魂兽受重创，之后 3 秒每发都算爆头"},
	"ym_night": {"name": "幽冥夜", "type": "mark", "target": "self", "radius": 20.0, "dur": 12.0, "mult": 1.55, "cost": 60, "cd": 24.0, "desc": "20 米内魂兽受到伤害 +55%"},
	"ym_true": {"name": "幽冥真身", "type": "buff", "target": "self", "stat": "crit", "amount": 1.0, "dur": 12.0, "cost": 70, "cd": 32.0, "desc": "12 秒内每一发都算爆头"},
	"ym_storm": {"name": "幽冥爪暴", "type": "rain", "target": "aim", "radius": 9.0, "damage": 70.0, "impulse": 6.0, "waves": 8, "cost": 75, "cd": 30.0, "desc": "八连爪影"},
	"hf_meteor": {"name": "凤凰流星", "type": "rain", "target": "aim", "radius": 10.0, "damage": 90.0, "impulse": 7.0, "waves": 5, "burn": 14.0, "cost": 60, "cd": 22.0, "desc": "五颗火流星砸下，灼烧魂兽"},
	"hf_wall": {"name": "凤凰火墙", "type": "mark", "target": "aim", "radius": 12.0, "dur": 12.0, "mult": 1.5, "cost": 60, "cd": 24.0, "desc": "火墙里的魂兽受到伤害 +50%"},
	"hf_true": {"name": "火凤凰真身", "type": "leap", "target": "self", "height": 20.0, "radius": 12.0, "damage": 260.0, "impulse": 12.0, "cost": 75, "cd": 30.0, "desc": "化身火凤凰冲天，落地烧毁一片"},
	"hf_sun": {"name": "凤凰啸天击·极", "type": "projectile", "target": "dir", "speed": 34.0, "radius": 12.0, "damage": 320.0, "impulse": 14.0, "burn": 20.0, "cost": 75, "cd": 30.0, "desc": "超大凤凰火球"},
	"qb_break": {"name": "琉璃破", "type": "mark", "target": "aim", "radius": 16.0, "dur": 14.0, "mult": 1.7, "cost": 60, "cd": 26.0, "desc": "准星处魂兽受到伤害 +70%"},
	"qb_wall": {"name": "琉璃护壁", "type": "shield", "target": "self", "radius": 25.0, "amount": 110.0, "dur": 12.0, "team": true, "cost": 60, "cd": 26.0, "desc": "全队 110 点护盾"},
	"qb_nine": {"name": "九宝琉璃", "type": "buff", "target": "self", "radius": 30.0, "stat": "all", "amount": 0.55, "dur": 14.0, "team": true, "cost": 80, "cd": 34.0, "desc": "全队伤害、移速、换弹 +55%"},
	"qb_heal": {"name": "琉璃之光", "type": "heal", "target": "self", "radius": 30.0, "amount": 160.0, "cost": 70, "cd": 30.0, "desc": "全队回复 160 体力"},
	"ht_quake": {"name": "昊天震", "type": "launch", "target": "self", "radius": 14.0, "damage": 220.0, "impulse": 14.0, "cost": 60, "cd": 20.0, "desc": "一锤砸地，把周围 14 米全震上天"},
	"ht_break2": {"name": "昊天碎甲", "type": "mark", "target": "self", "radius": 18.0, "dur": 12.0, "mult": 1.6, "cost": 60, "cd": 24.0, "desc": "身边魂兽受到伤害 +60%，无视护甲"},
	"ht_nine2": {"name": "昊天九绝·极", "type": "buff", "target": "self", "stat": "dmg", "amount": 0.8, "dur": 10.0, "cost": 70, "cd": 30.0, "desc": "10 秒内伤害 +80%"},
	"ht_fall": {"name": "天锤陨落", "type": "projectile", "target": "dir", "speed": 26.0, "radius": 13.0, "damage": 340.0, "impulse": 15.0, "cost": 75, "cd": 30.0, "desc": "昊天锤化成陨石砸下"},
	"ls_holy": {"name": "圣光审判", "type": "rain", "target": "aim", "radius": 11.0, "damage": 100.0, "impulse": 9.0, "waves": 5, "cost": 60, "cd": 22.0, "desc": "五道审判之光"},
	"ls_bless": {"name": "天使祝福", "type": "heal", "target": "self", "radius": 30.0, "amount": 160.0, "cost": 60, "cd": 26.0, "desc": "全队回复 160 体力"},
	"ls_god": {"name": "天使神剑", "type": "beam", "target": "dir", "range": 90.0, "damage": 420.0, "pierce": 12, "cost": 80, "cd": 30.0, "desc": "一剑贯穿 90 米"},
	"ls_true": {"name": "六翼天使真身", "type": "buff", "target": "self", "radius": 25.0, "stat": "all", "amount": 0.5, "dur": 14.0, "team": true, "cost": 80, "cd": 34.0, "desc": "全队伤害、移速 +50%"},
	# ---- 万年魂环（第六~九环）和十万年魂环（第十环，神技）----
	"lyc_net": {"name": "蓝银天网", "type": "root", "target": "aim", "radius": 22.0, "dur": 7.0, "damage": 400.0, "cost": 85, "cd": 30.0, "desc": "22 米内的魂兽全部被蓝银天网吊住 7 秒"},
	"lyc_thorn": {"name": "蓝银荆棘海", "type": "rain", "target": "aim", "radius": 14.0, "damage": 260.0, "impulse": 10.0, "waves": 6, "cost": 85, "cd": 28.0, "desc": "六波荆棘从地下刺出"},
	"lyc_shen": {"name": "蓝银皇 · 神降", "type": "launch", "target": "aim", "radius": 24.0, "damage": 1800.0, "impulse": 16.0, "cost": 100, "cd": 45.0, "desc": "神技：蓝银皇真身降临，一大片全部挑飞"},
	"ld_hell": {"name": "地狱之镰", "type": "beam", "target": "dir", "range": 90.0, "damage": 900.0, "pierce": 20, "cost": 85, "cd": 26.0, "desc": "一道贯穿 90 米的地狱镰光"},
	"ld_step": {"name": "死神步", "type": "blink", "target": "dir", "dist": 26.0, "damage": 600.0, "radius": 5.0, "stat": "dmg", "amount": 0.5, "dur": 6.0, "cost": 80, "cd": 18.0, "desc": "瞬移 26 米斩过路上所有魂兽，之后 6 秒伤害 +50%"},
	"ld_shen": {"name": "死神之神镰", "type": "rain", "target": "aim", "radius": 18.0, "damage": 700.0, "impulse": 12.0, "waves": 7, "cost": 100, "cd": 45.0, "desc": "神技：七轮死神镰影横扫一大片"},
	"xc_feast2": {"name": "香肠神宴", "type": "heal", "target": "self", "radius": 40.0, "amount": 400.0, "cost": 85, "cd": 30.0, "desc": "40 米内全队回复 400 体力"},
	"xc_rain2": {"name": "香肠雨 · 极", "type": "rain", "target": "aim", "radius": 14.0, "damage": 300.0, "impulse": 13.0, "waves": 6, "cost": 85, "cd": 28.0, "desc": "六轮爆炸香肠从天而降"},
	"xc_shen": {"name": "香肠之神", "type": "buff", "target": "self", "radius": 40.0, "stat": "all", "amount": 0.8, "dur": 16.0, "team": true, "cost": 100, "cd": 45.0, "desc": "神技：全队伤害、移速、换弹 +80%，持续 16 秒"},
	"bh_king2": {"name": "白虎灭世", "type": "beam", "target": "dir", "range": 90.0, "damage": 1100.0, "pierce": 15, "cost": 85, "cd": 26.0, "desc": "灭世光波贯穿 90 米"},
	"bh_giant2": {"name": "白虎法身", "type": "giant", "target": "self", "scale": 2.8, "dr": 0.7, "dmg": 0.8, "dur": 14.0, "cost": 85, "cd": 32.0, "desc": "化身巨虎法身：体型 ×2.8，受伤 -70%，伤害 +80%"},
	"bh_shen": {"name": "白虎之神", "type": "launch", "target": "self", "radius": 22.0, "damage": 2000.0, "impulse": 16.0, "cost": 100, "cd": 45.0, "desc": "神技：白虎神一声怒吼，22 米全部震飞"},
	"ym_shadow2": {"name": "幽冥万影", "type": "rain", "target": "aim", "radius": 14.0, "damage": 320.0, "impulse": 7.0, "waves": 9, "cost": 85, "cd": 28.0, "desc": "九轮幽冥爪影"},
	"ym_blink2": {"name": "幽冥神行", "type": "blink", "target": "dir", "dist": 30.0, "damage": 900.0, "radius": 5.0, "stat": "crit", "amount": 1.0, "dur": 5.0, "cost": 80, "cd": 16.0, "desc": "瞬移 30 米重创路上的魂兽，之后 5 秒每发都是爆头"},
	"ym_shen": {"name": "幽冥之神", "type": "buff", "target": "self", "stat": "all", "amount": 0.9, "stat2": "crit", "amount2": 1.0, "dur": 12.0, "cost": 100, "cd": 45.0, "desc": "神技：12 秒内伤害、移速 +90%，每一发都是爆头"},
	"hf_sky": {"name": "焚天", "type": "rain", "target": "aim", "radius": 16.0, "damage": 420.0, "impulse": 9.0, "waves": 6, "burn": 40.0, "cost": 85, "cd": 28.0, "desc": "六颗天火砸下，烧成一片火海"},
	"hf_wing2": {"name": "凤凰神翼", "type": "fly", "target": "self", "dur": 10.0, "radius": 14.0, "damage": 800.0, "impulse": 12.0, "cost": 85, "cd": 28.0, "desc": "展开神翼飞 10 秒，落地炸飞 14 米"},
	"hf_shen": {"name": "火凤凰之神", "type": "projectile", "target": "dir", "speed": 30.0, "radius": 20.0, "damage": 2400.0, "impulse": 18.0, "burn": 60.0, "cost": 100, "cd": 45.0, "desc": "神技：化身火凤凰撞出去，炸出 20 米火海"},
	"qb_nine2": {"name": "九宝神光", "type": "buff", "target": "self", "radius": 40.0, "stat": "all", "amount": 0.7, "dur": 16.0, "team": true, "cost": 85, "cd": 32.0, "desc": "全队伤害、移速、换弹 +70%"},
	"qb_break2": {"name": "琉璃碎天", "type": "mark", "target": "aim", "radius": 30.0, "dur": 16.0, "mult": 2.2, "cost": 85, "cd": 30.0, "desc": "30 米内魂兽受到伤害 ×2.2"},
	"qb_shen": {"name": "九宝琉璃神", "type": "heal", "target": "self", "radius": 50.0, "amount": 999.0, "cost": 100, "cd": 45.0, "desc": "神技：50 米内全队回满体力"},
	"ht_true2": {"name": "昊天真身 · 极", "type": "giant", "target": "self", "scale": 2.6, "dr": 0.65, "dmg": 0.9, "dur": 14.0, "cost": 85, "cd": 32.0, "desc": "体型 ×2.6，受伤 -65%，伤害 +90%"},
	"ht_storm2": {"name": "乱披风锤法 · 极", "type": "rain", "target": "aim", "radius": 15.0, "damage": 480.0, "impulse": 14.0, "waves": 6, "cost": 85, "cd": 28.0, "desc": "六连重锤，魂兽根本落不了地"},
	"ht_shen": {"name": "昊天神锤", "type": "projectile", "target": "dir", "speed": 26.0, "radius": 22.0, "damage": 2600.0, "impulse": 18.0, "cost": 100, "cd": 45.0, "desc": "神技：昊天锤化成神锤砸下，22 米寸草不生"},
	"ls_judge2": {"name": "天使审判 · 极", "type": "rain", "target": "aim", "radius": 16.0, "damage": 450.0, "impulse": 10.0, "waves": 6, "cost": 85, "cd": 28.0, "desc": "六道审判圣光"},
	"ls_wing2": {"name": "六翼神飞", "type": "fly", "target": "self", "dur": 12.0, "radius": 14.0, "damage": 900.0, "impulse": 12.0, "cost": 85, "cd": 28.0, "desc": "六翼展开飞 12 秒，落地圣光炸飞 14 米"},
	"ls_shen": {"name": "天使之神", "type": "beam", "target": "dir", "range": 150.0, "damage": 3000.0, "pierce": 30, "cost": 100, "cd": 45.0, "desc": "神技：天使神剑一剑贯穿 150 米"},
}

# 每个武魂的魂技树：第 1/2/3/4/5 魂环各两个选项
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
const SKILL_SLOTS := 3         # 三个魂技槽：Q / E / F（在 K 武魂面板里选哪三个魂技装上去）
# 魂技由 武魂 + 魂兽种类 + 年份 决定，吸收之前不告诉你是什么：
# 同一个武魂吸收同一种魂兽，永远得到同一个魂技；年份越高，从越强的一档里出（十年 → 第 1~2 档，百年 → 2~3，千年 → 4~5，万年 → 第 6 档，十万年 → 神技）
const AGE_TIERS := [[0, 1], [1, 2], [3, 4], [5], [6]]


## 魂技在第几档（0 十年~百年 … 5 万年 6 神技），特效按档次加层
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

# ================================================================ 魂骨
# 六个部位各装一块（K 打开武魂面板换）。魂骨兽必掉、千年魂兽小概率掉、Boss 必掉。
# 地上的魂骨谁都能捡，也能丢给队友，或者丢进收购箱卖掉。
# 存档里一块魂骨写成 "id@年份"，百年 ×1.5、千年 ×2.2（二段跳、滑翔这种开关型的不变）
# stat：hp 体力 / soul 魂力 / dmg 伤害 / headshot 爆头 / dr 减伤 / speed 移速 / reload 换弹 / recoil 后坐 /
#       jump 跳跃高度 / djump 二段跳 / glide 滑翔 / breath 水下憋气 / swim 游泳 / regen 回血 / sell 卖价
const BONE_SLOTS := ["head", "torso", "larm", "rarm", "lleg", "rleg"]
const BONE_SLOT_NAMES := {"head": "头骨", "torso": "躯干骨", "larm": "左臂骨", "rarm": "右臂骨", "lleg": "左腿骨", "rleg": "右腿骨"}
const BONE_AGE_MULT := [1.0, 1.5, 2.2, 3.2, 4.5]
const BONE_SWITCH := ["djump", "glide"]
const BONES := {
	# ---- 魂兽魂骨
	"rabbit_leg": {"name": "柔骨兔左腿骨", "slot": "lleg", "stat": "jump", "amount": 0.25, "beast": "rabbit"},
	"vine_torso": {"name": "鬼藤躯干骨", "slot": "torso", "stat": "regen", "amount": 1.5, "beast": "vine"},
	"bird_arm": {"name": "风铃鸟左臂骨", "slot": "larm", "stat": "glide", "amount": 1.0, "stat2": "speed", "amount2": 0.05, "beast": "bird"},
	"moth_head": {"name": "月光蛾头骨", "slot": "head", "stat": "soul", "amount": 20.0, "beast": "moth"},
	"wolf_leg": {"name": "疾风魔狼右腿骨", "slot": "rleg", "stat": "speed", "amount": 0.1, "beast": "wolf"},
	"rhino_torso": {"name": "铁甲犀躯干骨", "slot": "torso", "stat": "dr", "amount": 0.1, "stat2": "hp", "amount2": 15.0, "beast": "rhino"},
	"ape_arm": {"name": "金刚猿右臂骨", "slot": "rarm", "stat": "dmg", "amount": 0.08, "beast": "ape"},
	"snake_head": {"name": "曼陀罗蛇头骨", "slot": "head", "stat": "headshot", "amount": 0.1, "beast": "snake"},
	"stag_head": {"name": "鬼眼鹿头骨", "slot": "head", "stat": "headshot", "amount": 0.12, "stat2": "soul", "amount2": 10.0, "beast": "stag"},
	"bat_arm": {"name": "夜翼魔蝠左臂骨", "slot": "larm", "stat": "glide", "amount": 1.0, "stat2": "dmg", "amount2": 0.04, "beast": "bat"},
	"raptor_leg": {"name": "疾爪龙左腿骨", "slot": "lleg", "stat": "djump", "amount": 1.0, "beast": "raptor"},
	"spider_arm": {"name": "地穴魔蛛右臂骨", "slot": "rarm", "stat": "reload", "amount": 0.12, "beast": "spiderling"},
	"frog_leg": {"name": "碧磷蟾右腿骨", "slot": "rleg", "stat": "jump", "amount": 0.4, "stat2": "swim", "amount2": 0.2, "beast": "frog"},
	"husky_leg": {"name": "雪原狼左腿骨", "slot": "lleg", "stat": "speed", "amount": 0.12, "beast": "husky"},
	"icedeer_head": {"name": "冰角鹿头骨", "slot": "head", "stat": "soul", "amount": 30.0, "beast": "icedeer"},
	"icehorn_torso": {"name": "冰甲龙躯干骨", "slot": "torso", "stat": "dr", "amount": 0.15, "beast": "icehorn"},
	"snowape_arm": {"name": "雪魔猿右臂骨", "slot": "rarm", "stat": "dmg", "amount": 0.1, "stat2": "recoil", "amount2": 0.1, "beast": "snowape"},
	"icefish_torso": {"name": "冰鳞鱼躯干骨", "slot": "torso", "stat": "breath", "amount": 12.0, "stat2": "swim", "amount2": 0.4, "beast": "icefish"},
	"crab_arm": {"name": "铁钳蟹左臂骨", "slot": "larm", "stat": "recoil", "amount": 0.2, "beast": "crab"},
	"gull_head": {"name": "海魂鸥头骨", "slot": "head", "stat": "sell", "amount": 0.2, "beast": "gull"},
	"reef_head": {"name": "彩鳞鱼头骨", "slot": "head", "stat": "breath", "amount": 10.0, "beast": "reeffish"},
	"shark_torso": {"name": "深海魔鲨躯干骨", "slot": "torso", "stat": "swim", "amount": 0.6, "stat2": "breath", "amount2": 15.0, "beast": "shark"},
	"manta_arm": {"name": "幽灵鳐左臂骨", "slot": "larm", "stat": "glide", "amount": 1.0, "stat2": "soul", "amount2": 15.0, "beast": "manta"},
	# ---- Boss 魂骨（都是千年的）
	"mandala_skull": {"name": "曼陀罗蛇王头骨", "slot": "head", "stat": "headshot", "amount": 0.08, "stat2": "soul", "amount2": 10.0},
	"mandala_spine": {"name": "曼陀罗蛇王躯干骨", "slot": "torso", "stat": "hp", "amount": 15.0, "stat2": "regen", "amount2": 1.0},
	"spider_leg": {"name": "人面魔蛛八蛛矛", "slot": "rleg", "stat": "djump", "amount": 1.0, "stat2": "dmg", "amount2": 0.04},
	"spider_eye": {"name": "人面魔蛛之眼", "slot": "head", "stat": "soul", "amount": 12.0, "stat2": "headshot", "amount2": 0.05},
	"titan_arm": {"name": "泰坦巨猿右臂骨", "slot": "rarm", "stat": "dmg", "amount": 0.07, "stat2": "recoil", "amount2": 0.08},
	"titan_heart": {"name": "泰坦巨猿躯干骨", "slot": "torso", "stat": "hp", "amount": 25.0, "stat2": "dr", "amount2": 0.05},
	"dragon_wing": {"name": "冰霜巨龙左臂骨", "slot": "larm", "stat": "glide", "amount": 1.0, "stat2": "headshot", "amount2": 0.08},
	"dragon_scale": {"name": "冰霜巨龙头骨", "slot": "head", "stat": "soul", "amount": 18.0, "stat2": "dmg", "amount2": 0.04},
	"whale_bone": {"name": "深海魔鲸右腿骨", "slot": "rleg", "stat": "swim", "amount": 0.5, "stat2": "speed", "amount2": 0.06},
	"whale_heart": {"name": "深海魔鲸躯干骨", "slot": "torso", "stat": "hp", "amount": 35.0, "stat2": "breath", "amount2": 20.0},
}
const BONE_BY_BEAST := {
	"rabbit": "rabbit_leg", "vine": "vine_torso", "bird": "bird_arm", "moth": "moth_head", "wolf": "wolf_leg",
	"rhino": "rhino_torso", "ape": "ape_arm", "snake": "snake_head", "stag": "stag_head", "bat": "bat_arm",
	"raptor": "raptor_leg", "spiderling": "spider_arm", "frog": "frog_leg", "husky": "husky_leg",
	"icedeer": "icedeer_head", "icehorn": "icehorn_torso", "snowape": "snowape_arm", "icefish": "icefish_torso",
	"crab": "crab_arm", "gull": "gull_head", "reeffish": "reef_head", "shark": "shark_torso", "manta": "manta_arm",
}


## "wolf_leg@1" -> ["wolf_leg", 1]；旧存档里没有 @ 的是 Boss 掉的千年魂骨
func bone_id(entry: String) -> String:
	return entry.get_slice("@", 0)


func bone_age(entry: String) -> int:
	return int(entry.get_slice("@", 1)) if "@" in entry else 2


func bone_data(entry: String) -> Dictionary:
	return BONES.get(bone_id(entry), {})


func bone_name(entry: String) -> String:
	var d := bone_data(entry)
	if d.is_empty():
		return "魂骨"
	return "%s%s" % [age_name(bone_age(entry)), d["name"]]


## 一块魂骨某个属性加多少（算上年份）
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
				out.append("魂力 +%d" % roundi(v))
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
	"mandala": {"name": "湖主 · 千年曼陀罗蛇", "hp": 12000.0, "reward": 720, "xp": 450, "bones": ["mandala_skull", "mandala_spine"], "age": 2, "ai": "water",
		"model": "snake_angry", "fit": "h", "size": 9.0, "tint": Color(1.0, 0.5, 1.2), "summon": "snake", "ring_beast": "snake", "weak": Vector3(0, 0.34, -0.3), "holy": Color(0.85, 0.55, 1.0)},
	"spider": {"name": "森林之主 · 人面魔蛛", "hp": 35000.0, "reward": 2700, "xp": 1300, "bones": ["spider_leg", "spider_eye"], "age": 2, "ai": "land",
		"model": "spider", "fit": "w", "size": 8.5, "tint": Color(0.6, 0.45, 0.7), "summon": "wolf", "ring_beast": "wolf", "weak": Vector3(0, 0.2, -0.4), "holy": Color(1.0, 0.45, 0.6)},
	"titan": {"name": "星斗之王 · 万年泰坦巨猿", "hp": 85000.0, "reward": 7200, "xp": 3400, "bones": ["titan_arm", "titan_heart"], "age": 3, "ai": "land",
		"model": "yeti", "fit": "h", "size": 9.0, "tint": Color(0.42, 0.36, 0.34), "summon": "raptor", "ring_beast": "stag", "throws": true, "weak": Vector3(0, 0.36, -0.15), "holy": Color(1.0, 0.8, 0.4)},
	"icedragon": {"name": "极北之主 · 万年冰霜巨龙", "hp": 130000.0, "reward": 16800, "xp": 10000, "bones": ["dragon_wing", "dragon_scale"], "age": 3, "ai": "air",
		"model": "dragon", "fit": "w", "size": 16.0, "tint": Color(0.6, 0.85, 1.3), "glow": Color(0.1, 0.3, 0.6), "summon": "husky", "ring_beast": "icehorn", "weak": Vector3(0, 0.25, -0.42), "holy": Color(0.6, 0.9, 1.0)},
	"whale": {"name": "海神岛之主 · 十万年深海魔鲸", "hp": 200000.0, "reward": 36000, "xp": 33000, "bones": ["whale_bone", "whale_heart"], "age": 4, "ai": "water",
		"model": "whale", "fit": "l", "size": 22.0, "tint": Color(0.55, 0.6, 0.9), "summon": "shark", "ring_beast": "shark", "weak": Vector3(0, 0.15, -0.44), "holy": Color(0.5, 0.8, 1.0)},
}

# ================================================================ 章节
# 不再有清单式任务。每章只有一条主线：修炼到 boss_level 级 → 去祭坛召唤 Boss → 打赢了所有人上船去下一张图。
# 其他都是自己挑的目标：悬赏、精英魂兽（王）、猎魂录、成就、魂骨、外观、兽潮。
# Boss 打赢以后祭坛还能再召唤（刷魂骨、魂环），渡船也能回以前去过的岛。
# 最后一章：修炼到 100 级、吸收第十魂环（十万年，海神岛之主掉）= 成神，通关。
const CHAPTERS := {
	1: {
		"name": "第一章 · 湖心岛", "map": "island", "boss": "mandala", "next": 2, "levels": [1, 20], "boss_level": 15,
		"intro": "圣魂村外的湖心小岛。甩出引魂索把魂兽拽上天，在空中打死它们。修炼到 15 级，就能去北坡祭坛召唤湖主。",
		"quests": [
			{"type": "level", "n": 15, "text": "修炼到 15 级（打魂兽、悬赏、精英、兽潮都给修为）", "reward": 0},
			{"type": "altar", "n": 1, "text": "去北边山坡的祭坛（按 F），召唤湖主 · 千年曼陀罗蛇", "reward": 0, "target": "altar"},
			{"type": "boss", "n": 1, "text": "击败湖主 · 千年曼陀罗蛇", "reward": 0},
			{"type": "boat", "n": 1, "text": "所有人到码头尽头的船边按 F，一起去落日森林", "reward": 0, "target": "boat"},
		],
	},
	2: {
		"name": "第二章 · 落日森林", "map": "forest", "boss": "spider", "next": 3, "levels": [20, 40], "boss_level": 35,
		"intro": "落日森林，傍晚的光从树缝里漏下来。这里的魂兽会反击：魔狼扑人，铁甲犀冲撞，金刚猿扔石头，被咬会中毒。",
		"quests": [
			{"type": "level", "n": 35, "text": "修炼到 35 级", "reward": 0},
			{"type": "altar", "n": 1, "text": "去森林中心古树下的祭坛（按 F），召唤森林之主", "reward": 0, "target": "altar"},
			{"type": "boss", "n": 1, "text": "击败森林之主 · 人面魔蛛", "reward": 0},
			{"type": "boat", "n": 1, "text": "所有人上船（按 F），去星斗大森林", "reward": 0, "target": "boat"},
		],
	},
	3: {
		"name": "第三章 · 星斗大森林", "map": "deepforest", "boss": "titan", "next": 4, "levels": [40, 60], "boss_level": 55,
		"intro": "斗罗大陆最大的魂兽森林，古木参天、终年雾气环绕。这里没有十年魂兽了，百年、千年成群出没。",
		"quests": [
			{"type": "level", "n": 55, "text": "修炼到 55 级", "reward": 0},
			{"type": "altar", "n": 1, "text": "去星斗古树下的祭坛（按 F），唤醒星斗之王", "reward": 0, "target": "altar"},
			{"type": "boss", "n": 1, "text": "击败星斗之王 · 万年泰坦巨猿", "reward": 0},
			{"type": "boat", "n": 1, "text": "所有人上船（按 F），去极北之地", "reward": 0, "target": "boat"},
		],
	},
	4: {
		"name": "第四章 · 极北之地", "map": "snow", "boss": "icedragon", "next": 5, "levels": [60, 80], "boss_level": 75,
		"intro": "终年冰雪的极北之地。千年魂兽遍地，万年魂兽开始出现。被咬会冻得走不快。",
		"quests": [
			{"type": "level", "n": 75, "text": "修炼到 75 级", "reward": 0},
			{"type": "altar", "n": 1, "text": "去北边冰崖上的祭坛（按 F），召唤冰霜巨龙", "reward": 0, "target": "altar"},
			{"type": "boss", "n": 1, "text": "击败极北之主 · 万年冰霜巨龙", "reward": 0},
			{"type": "boat", "n": 1, "text": "所有人上船（按 F），去海神岛", "reward": 0, "target": "boat"},
		],
	},
	5: {
		"name": "第五章 · 海神岛", "map": "sea", "boss": "whale", "next": 0, "levels": [80, 100], "boss_level": 95,
		"intro": "传说中的海神岛，千年、万年海兽横行。打败十万年的深海魔鲸，吸收它的魂环，修炼到 100 级——成神。",
		"quests": [
			{"type": "level", "n": 95, "text": "修炼到 95 级", "reward": 0},
			{"type": "altar", "n": 1, "text": "去北岸的海神祭坛（按 F），召唤深海魔鲸", "reward": 0, "target": "altar"},
			{"type": "boss", "n": 1, "text": "击败海神岛之主 · 十万年深海魔鲸", "reward": 0},
			{"type": "god", "n": 1, "text": "成神：修炼到 100 级，吸收第十魂环（十万年，深海魔鲸掉；祭坛可以再召唤它）", "reward": 0},
		],
	},
}

# ================================================================ 工具函数

func age_name(age: int) -> String:
	return AGES[clampi(age, 0, AGES.size() - 1)]["name"]


func age_color(age: int) -> Color:
	return AGES[clampi(age, 0, AGES.size() - 1)]["color"]


## 越往后的章节，百年、千年魂兽越多
## 每章魂兽的年份：第三章起没有十年的，第五章出万年（黑色魂环）。权重依次是 十年 / 百年 / 千年 / 万年
const AGE_WEIGHTS := {1: [70.0, 28.0, 2.0, 0.0], 2: [30.0, 55.0, 15.0, 0.0], 3: [0.0, 55.0, 42.0, 3.0], 4: [0.0, 20.0, 60.0, 20.0], 5: [0.0, 0.0, 45.0, 55.0]}
## 每章魂兽的攻击力倍数，和每章魂兽的特点（被咬到时）
const CH_POWER := {1: 1.0, 2: 1.35, 3: 1.8, 4: 2.3, 5: 3.0}
const BEAST_DMG := 1.8        # 魂兽伤害总倍数（用户说第一章升到 15 级基本没掉过血）
const CH_TRAIT := {1: "", 2: "poison", 3: "pack", 4: "frost", 5: "drag"}
const TRAIT_TEXT := {
	"poison": "这里的魂兽带毒：被咬会中毒，持续掉血",
	"pack": "这里的魂兽成群：拽出一只，同窝的会跑来帮忙",
	"frost": "这里的魂兽带寒气：被咬会冻得走不快",
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


## 魂兽血量：基础 × 年份 × 章节（后面的图的魂兽厚得多，玩家的暗器、升级、等级、魂骨也跟着涨）
## 参考（按这一章的参考等级、主力暗器、升级估算，不算魂骨和魂技）：
##   第一章 袖箭 约 0.3 秒一只 · 第二章 诸葛神弩 0.5 秒 · 第三章 孔雀翎 0.9 秒 · 第四章 2.4 秒（狙击爆头一发）· 第五章 3.8 秒（魂骨、魂技能快一倍）
const CH_HP := {1: 1.0, 2: 2.0, 3: 4.0, 4: 6.0, 5: 8.0}


func beast_max_hp(species: String, age: int) -> float:
	# 自动测试是功能测试（能不能拽、能不能打死），用的是 1 级的暗器，不乘章节血量
	var ch_k := 1.0 if autotest else float(CH_HP.get(int(SPECIES_CH.get(species, 1)), 1.0)) * Profile.rebirth_hard()
	return BEASTS[species]["hp"] * AGES[clampi(age, 0, AGES.size() - 1)]["hp"] * ch_k


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


## 装上配件以后的数值：瞄具改开镜倍率、全屏瞄准镜；制退器 / 握把 / 激光改后坐和散布
func apply_attach(d: Dictionary, on: Dictionary) -> Dictionary:
	d["recoil_v"] = 1.0
	d["recoil_h"] = 1.0
	d["attach"] = on.duplicate()
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
		for k in ["hip", "ads", "move"]:
			d[k] = float(d[k]) * float(a.get("spread", 1.0))
		d["hip"] = float(d["hip"]) * float(a.get("hip", 1.0))
	return d


func upgrade_price(id: String, level: int) -> int:
	var base := maxi(int(WEAPONS[id]["price"]), 400)
	return int(round(base * UPGRADE_COST[clampi(level, 0, UPGRADE_COST.size() - 1)] / 10.0)) * 10


func quest(chapter: int, idx: int) -> Dictionary:
	var qs: Array = CHAPTERS[chapter]["quests"]
	if idx < 0 or idx >= qs.size():
		return {}
	return qs[idx]
