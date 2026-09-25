extends Node
## 游戏数据表。调数值主要改这里：暗器、魂兽、魂技、章节任务、商店价格。

const PROTOCOL_VERSION := "m2-1"

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
const AGES := [
	{"name": "十年", "color": Color(0.95, 0.95, 0.92), "hp": 1.0, "reward": 1.0, "xp": 1.0, "scale": 1.0, "mass": 1.0, "weight": 70.0, "ring_drop": 0.18, "ring_power": 1.0},
	{"name": "百年", "color": Color(1.0, 0.82, 0.25), "hp": 2.6, "reward": 3.0, "xp": 3.0, "scale": 1.25, "mass": 1.5, "weight": 25.0, "ring_drop": 0.55, "ring_power": 1.3},
	{"name": "千年", "color": Color(0.68, 0.36, 1.0), "hp": 6.5, "reward": 10.0, "xp": 9.0, "scale": 1.6, "mass": 2.4, "weight": 5.0, "ring_drop": 1.0, "ring_power": 1.7},
	{"name": "万年", "color": Color(0.12, 0.1, 0.12), "hp": 16.0, "reward": 30.0, "xp": 25.0, "scale": 2.0, "mass": 4.0, "weight": 0.0, "ring_drop": 1.0, "ring_power": 2.2},
]

# ================================================================ 魂兽
# habitat：在哪里能用引魂索引出来；motion：落地后怎么跑
# armor：身体减伤（头不减）；hurt：落地后会不会攻击玩家（伤害值）
# model：assets/models/creatures 里的模型；fit + size：按长(l)/高(h)/宽(w)缩放到多少米；tint：颜色；glow：发光
const BEASTS := {
	# 第一章 · 湖心岛
	"rabbit": {"name": "柔骨兔", "habitat": "burrow", "hp": 30.0, "reward": 10, "xp": 10, "motion": "hop",
		"model": "bunny", "fit": "h", "size": 0.8, "tint": Color(1.0, 0.97, 0.98)},
	"vine": {"name": "鬼藤", "habitat": "water", "hp": 36.0, "reward": 14, "xp": 12, "motion": "slither"},
	"bird": {"name": "风铃鸟", "habitat": "meadow", "hp": 24.0, "reward": 15, "xp": 12, "motion": "fly",
		"model": "pigeon", "fit": "w", "size": 1.0, "tint": Color(0.55, 1.0, 0.95)},
	"moth": {"name": "月光蛾", "habitat": "flowers", "hp": 26.0, "reward": 12, "xp": 10, "motion": "flutter",
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
	"bat": {"name": "夜翼魔蝠", "habitat": "roost", "hp": 80.0, "reward": 48, "xp": 44, "motion": "fly",
		"model": "bat", "fit": "w", "size": 1.6, "tint": Color(0.8, 0.7, 1.0)},
	"raptor": {"name": "疾爪龙", "habitat": "thicket", "hp": 130.0, "reward": 56, "xp": 52, "motion": "run", "hurt": 18.0,
		"model": "raptor", "fit": "l", "size": 2.8, "tint": Color(0.7, 0.85, 0.7)},
	"spiderling": {"name": "地穴魔蛛", "habitat": "nest", "hp": 100.0, "reward": 52, "xp": 48, "motion": "run", "hurt": 14.0,
		"model": "spider", "fit": "w", "size": 1.8, "tint": Color(0.85, 0.6, 1.0)},
	"frog": {"name": "碧磷蟾", "habitat": "bog", "hp": 90.0, "reward": 46, "xp": 42, "motion": "hop",
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
	"icefish": {"name": "冰鳞鱼", "habitat": "icelake", "hp": 120.0, "reward": 64, "xp": 58, "motion": "slither",
		"model": "fish1", "fit": "l", "size": 1.4, "tint": Color(0.75, 0.95, 1.2), "glow": Color(0.1, 0.25, 0.35)},
	# 第五章 · 海神岛
	"crab": {"name": "铁钳蟹", "habitat": "beach", "hp": 220.0, "reward": 90, "xp": 82, "motion": "charge", "armor": 0.4, "hurt": 22.0,
		"model": "crab", "fit": "w", "size": 1.5, "tint": Color(1.2, 0.7, 0.55)},
	"gull": {"name": "海魂鸥", "habitat": "cliff", "hp": 140.0, "reward": 86, "xp": 78, "motion": "fly",
		"model": "pigeon", "fit": "w", "size": 1.4, "tint": Color(1.25, 1.25, 1.3)},
	"reeffish": {"name": "彩鳞鱼", "habitat": "reef", "hp": 150.0, "reward": 84, "xp": 76, "motion": "slither",
		"model": "fish2", "fit": "l", "size": 1.2},
	"shark": {"name": "深海魔鲨", "habitat": "deep", "hp": 260.0, "reward": 110, "xp": 96, "motion": "slither", "hurt": 22.0,
		"model": "shark", "fit": "l", "size": 3.0, "tint": Color(0.75, 0.85, 1.0)},
	"manta": {"name": "幽灵鳐", "habitat": "abyss", "hp": 240.0, "reward": 120, "xp": 104, "motion": "flutter",
		"model": "manta", "fit": "w", "size": 2.6, "tint": Color(0.6, 0.7, 1.1), "glow": Color(0.1, 0.2, 0.6)},
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

const WEAPONS := {
	"xiujian": {
		"name": "袖箭", "cat": "手枪 · 半自动", "desc": "唐门入门暗器。射速快、爆头伤害高，适合点射。",
		"price": 0, "mode": "semi", "rpm": 420, "damage": 28.0, "headshot": 2.2, "pellets": 1,
		"mag": 12, "reload": 1.05, "reload_empty": 1.35, "per_shell": false,
		"range": 160.0, "falloff": Vector3(40, 120, 0.6),
		"hip": 1.1, "ads": 0.18, "move": 1.2, "air": 3.5, "crouch": 0.8,
		"bloom": 0.55, "bloom_max": 3.5, "bloom_recover": 7.0,
		"pattern": [Vector2(0, 1.7)], "jitter": 0.35, "ads_recoil": 0.75,
		"view_punch": 1.3, "recover_delay": 0.06, "recover_speed": 16.0,
		"ads_fov": 0.82, "ads_time": 0.11, "ads_move": 0.8,
		"impulse": 2.2, "lift": 0.55, "shake": 0.14,
		"tracer": Color(0.75, 0.95, 1.0), "sound": "xiujian_fire", "bolt": true,
	},
	"zhuge": {
		"name": "诸葛神弩", "cat": "冲锋 · 全自动", "desc": "连发弩，一秒十五箭。近中距离压制，移动射击也稳。",
		"price": 650, "mode": "auto", "rpm": 900, "damage": 15.0, "headshot": 1.8, "pellets": 1,
		"mag": 36, "reload": 1.8, "reload_empty": 2.2, "per_shell": false,
		"range": 120.0, "falloff": Vector3(18, 60, 0.55),
		"hip": 1.7, "ads": 0.55, "move": 0.7, "air": 3.0, "crouch": 0.85,
		"bloom": 0.14, "bloom_max": 2.2, "bloom_recover": 5.0,
		"pattern": "smg", "jitter": 0.18, "ads_recoil": 0.7,
		"view_punch": 0.45, "recover_delay": 0.09, "recover_speed": 22.0,
		"ads_fov": 0.8, "ads_time": 0.13, "ads_move": 0.85,
		"impulse": 0.85, "lift": 0.5, "shake": 0.05,
		"tracer": Color(1.0, 0.85, 0.5), "sound": "zhuge_fire", "bolt": true,
	},
	"kongque": {
		"name": "孔雀翎", "cat": "步枪 · 全自动", "desc": "唐门四大暗器之一。伤害高、开镜第一发极准，连射要压枪。",
		"price": 1500, "mode": "auto", "rpm": 600, "damage": 31.0, "headshot": 2.0, "pellets": 1,
		"mag": 30, "reload": 2.1, "reload_empty": 2.6, "per_shell": false,
		"range": 200.0, "falloff": Vector3(50, 150, 0.7),
		"hip": 2.2, "ads": 0.08, "move": 3.0, "air": 4.0, "crouch": 0.75,
		"bloom": 0.32, "bloom_max": 4.5, "bloom_recover": 7.5,
		"pattern": "rifle", "jitter": 0.12, "ads_recoil": 0.8,
		"view_punch": 0.85, "recover_delay": 0.1, "recover_speed": 15.0,
		"ads_fov": 0.7, "ads_time": 0.19, "ads_move": 0.75,
		"impulse": 1.35, "lift": 0.5, "shake": 0.09,
		"tracer": Color(0.45, 1.0, 0.85), "sound": "kongque_fire", "bolt": true,
	},
	"baoyu": {
		"name": "暴雨梨花针", "cat": "霰弹 · 泵动", "desc": "一次十四根银针。近身一发把魂兽轰上天。",
		"price": 300, "mode": "semi", "rpm": 75, "damage": 9.0, "headshot": 1.5, "pellets": 14,
		"mag": 6, "reload": 0.45, "reload_empty": 0.45, "per_shell": true,
		"range": 70.0, "falloff": Vector3(9, 30, 0.3),
		"hip": 5.2, "ads": 3.8, "move": 0.8, "air": 1.5, "crouch": 0.9,
		"bloom": 0.0, "bloom_max": 0.0, "bloom_recover": 1.0,
		"pattern": [Vector2(0, 4.2)], "jitter": 0.8, "ads_recoil": 0.85,
		"view_punch": 3.2, "recover_delay": 0.1, "recover_speed": 12.0,
		"ads_fov": 0.88, "ads_time": 0.15, "ads_move": 0.85,
		"impulse": 0.95, "lift": 0.65, "shake": 0.45,
		"tracer": Color(0.9, 0.92, 1.0), "sound": "baoyu_fire", "bolt": false,
	},
	"zhuihun": {
		"name": "追魂穿心弩", "cat": "狙击 · 拉栓", "desc": "带铜制瞄镜的重弩。一箭贯穿，爆头直接带走千年魂兽。",
		"price": 2400, "mode": "bolt", "rpm": 48, "damage": 150.0, "headshot": 2.5, "pellets": 1,
		"mag": 5, "reload": 2.7, "reload_empty": 3.1, "per_shell": false, "cycle": 1.1,
		"range": 400.0, "falloff": Vector3(200, 400, 0.9), "pierce": 3,
		"hip": 6.5, "ads": 0.0, "move": 5.0, "air": 8.0, "crouch": 0.7,
		"bloom": 0.0, "bloom_max": 0.0, "bloom_recover": 1.0,
		"pattern": [Vector2(0, 5.0)], "jitter": 0.6, "ads_recoil": 1.0,
		"view_punch": 4.0, "recover_delay": 0.12, "recover_speed": 10.0,
		"ads_fov": 0.25, "ads_time": 0.28, "ads_move": 0.55, "scope": true,
		"impulse": 7.0, "lift": 0.45, "shake": 0.5,
		"tracer": Color(1.0, 0.95, 0.7), "sound": "zhuihun_fire", "bolt": true,
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

# 升级：每把暗器 4 项，每项 3 级。价格 = 暗器基础价 × 系数（袖箭按 250 算）
const UPGRADES := {
	"dmg": {"name": "淬毒箭头", "desc": "伤害 +12%", "per": 0.12},
	"mag": {"name": "扩容机匣", "desc": "弹匣 +25%", "per": 0.25},
	"reload": {"name": "唐门机括", "desc": "换弹快 12%", "per": 0.12},
	"stab": {"name": "稳定弩臂", "desc": "后坐 -15%，散布 -10%", "per": 0.15},
}
const UPGRADE_COST := [0.35, 0.7, 1.2]

# 道具
const ITEMS := {
	"grenade": {"name": "佛怒唐莲", "desc": "唐门至高暗器。按 G 投掷，爆炸把周围魂兽全部炸上天", "price": 60, "max": 5, "key": "G"},
	"pill": {"name": "回血丹", "desc": "按 H 使用，立刻恢复 60 点体力", "price": 40, "max": 5, "key": "H"},
	"lure_gold": {"name": "引兽香", "desc": "接下来 5 次咬钩必定是百年以上的魂兽", "price": 120, "max": 3, "key": "自动"},
}

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
# 每 10 级是一个瓶颈，要吸收魂环才能继续升级。第 n 个魂环至少要这个年份
const RING_MIN_AGE := [0, 1, 1, 2, 2, 3, 3, 3, 3]
const MAX_LEVEL := 50

func xp_to_next(level: int) -> int:
	return 30 + level * 12 + int(level * level * 0.2)


## 联机时"猎杀 N 只"的任务按人数加量（每多一个人 +75%），不然几个人一起打太快
func quest_target(q: Dictionary, players: int) -> int:
	var n := int(q.get("n", 1))
	if str(q.get("type", "")) in ["kill", "hunt"] and players > 1:
		return ceili(n * (1.0 + 0.75 * (players - 1)))
	return n


func titles(level: int) -> String:
	var t := ["魂士", "魂师", "大魂师", "魂尊", "魂宗", "魂王", "魂帝", "魂圣", "魂斗罗", "封号斗罗"]
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
	"lyc_mark": {"name": "蓝银寄生", "type": "mark", "target": "aim", "radius": 6.0, "dur": 8.0, "mult": 1.35, "cost": 30, "cd": 12.0, "desc": "寄生的魂兽受到的伤害 +35%"},
	"lyc_pull": {"name": "蓝银牵引", "type": "pull", "target": "aim", "radius": 12.0, "dur": 3.0, "force": 18.0, "cost": 30, "cd": 12.0, "desc": "把 12 米内的魂兽拉到一起"},
	"lyc_cage": {"name": "蓝银囚笼", "type": "root", "target": "aim", "radius": 10.0, "dur": 5.0, "damage": 25.0, "cost": 50, "cd": 20.0, "desc": "大范围定身 5 秒"},
	"lyc_dance": {"name": "蓝银乱舞", "type": "rain", "target": "aim", "radius": 6.0, "damage": 30.0, "impulse": 7.0, "waves": 3, "cost": 50, "cd": 18.0, "desc": "连续三波突刺，把魂兽一直挑在空中"},
	# 镰刀
	"ld_whirl": {"name": "旋风斩", "type": "launch", "target": "self", "radius": 5.5, "damage": 45.0, "impulse": 8.0, "cost": 25, "cd": 7.0, "desc": "以自己为中心横扫，把身边魂兽砍飞"},
	"ld_scythe": {"name": "死神之镰", "type": "beam", "target": "dir", "range": 40.0, "damage": 90.0, "pierce": 5, "cost": 25, "cd": 7.0, "desc": "一道贯穿 40 米的镰刀光"},
	"ld_reap": {"name": "收割", "type": "buff", "target": "self", "stat": "dmg", "amount": 0.35, "dur": 8.0, "cost": 30, "cd": 16.0, "desc": "8 秒内自己伤害 +35%"},
	"ld_fly": {"name": "飞镰", "type": "projectile", "target": "dir", "speed": 35.0, "radius": 4.0, "damage": 70.0, "impulse": 6.0, "cost": 30, "cd": 10.0, "desc": "掷出旋转飞镰，命中爆开"},
	"ld_doom": {"name": "死神降临", "type": "launch", "target": "self", "radius": 11.0, "damage": 120.0, "impulse": 11.0, "cost": 55, "cd": 22.0, "desc": "大范围收割"},
	"ld_shadow": {"name": "镰影", "type": "dash", "target": "dir", "dist": 12.0, "damage": 60.0, "radius": 3.0, "cost": 30, "cd": 8.0, "desc": "化成镰影冲刺，路过的魂兽受伤"},
	# 香肠
	"xc_heal": {"name": "香肠回复", "type": "heal", "target": "self", "radius": 15.0, "amount": 45.0, "cost": 25, "cd": 10.0, "desc": "15 米内所有队友回复 45 体力"},
	"xc_boost": {"name": "香肠增幅", "type": "buff", "target": "self", "radius": 15.0, "stat": "dmg", "amount": 0.2, "dur": 12.0, "team": true, "cost": 30, "cd": 18.0, "desc": "全队伤害 +20%，持续 12 秒"},
	"xc_regen": {"name": "镜像香肠", "type": "buff", "target": "self", "radius": 15.0, "stat": "regen", "amount": 8.0, "dur": 10.0, "team": true, "cost": 30, "cd": 16.0, "desc": "全队每秒回复 8 体力"},
	"xc_fly": {"name": "飞行香肠", "type": "buff", "target": "self", "radius": 15.0, "stat": "speed", "amount": 0.3, "dur": 10.0, "team": true, "cost": 30, "cd": 16.0, "desc": "全队移速和换弹 +30%"},
	"xc_big": {"name": "大香肠", "type": "shield", "target": "self", "radius": 15.0, "amount": 60.0, "dur": 10.0, "team": true, "cost": 50, "cd": 24.0, "desc": "全队 60 点护盾"},
	"xc_boom": {"name": "爆炸香肠", "type": "projectile", "target": "dir", "speed": 28.0, "radius": 6.0, "damage": 110.0, "impulse": 10.0, "cost": 45, "cd": 14.0, "desc": "扔出会爆炸的香肠"},
	# 白虎
	"bh_guard": {"name": "白虎护身障", "type": "shield", "target": "self", "amount": 60.0, "dur": 8.0, "cost": 25, "cd": 12.0, "desc": "自己获得 60 点护盾"},
	"bh_wave": {"name": "白虎烈光波", "type": "beam", "target": "dir", "range": 35.0, "damage": 80.0, "pierce": 4, "cost": 25, "cd": 7.0, "desc": "一道贯穿的光波"},
	"bh_vajra": {"name": "白虎金刚变", "type": "buff", "target": "self", "stat": "dmg", "amount": 0.4, "dur": 8.0, "cost": 30, "cd": 16.0, "desc": "8 秒内伤害 +40%"},
	"bh_meteor": {"name": "白虎流星雨", "type": "rain", "target": "aim", "radius": 7.0, "damage": 40.0, "impulse": 6.0, "waves": 4, "cost": 35, "cd": 14.0, "desc": "准星处落下四波流星"},
	"bh_charge": {"name": "白虎冲击", "type": "dash", "target": "dir", "dist": 14.0, "damage": 80.0, "radius": 3.5, "impulse": 8.0, "cost": 40, "cd": 12.0, "desc": "猛冲撞飞路上的魂兽"},
	"bh_roar": {"name": "白虎咆哮", "type": "mark", "target": "self", "radius": 14.0, "dur": 10.0, "mult": 1.4, "cost": 45, "cd": 20.0, "desc": "身边魂兽受到伤害 +40%"},
	# 幽冥灵猫
	"ym_dash": {"name": "幽冥突刺", "type": "dash", "target": "dir", "dist": 10.0, "damage": 40.0, "radius": 2.5, "cost": 20, "cd": 5.0, "desc": "瞬间突进 10 米"},
	"ym_claw": {"name": "幽冥影爪", "type": "beam", "target": "dir", "range": 14.0, "damage": 110.0, "pierce": 2, "cost": 25, "cd": 7.0, "desc": "近距离高伤害爪击"},
	"ym_clone": {"name": "鬼影分身", "type": "buff", "target": "self", "stat": "crit", "amount": 1.0, "dur": 6.0, "cost": 30, "cd": 16.0, "desc": "6 秒内每一发都算爆头"},
	"ym_slash": {"name": "幽冥斩", "type": "launch", "target": "aim", "radius": 4.5, "damage": 55.0, "impulse": 9.0, "cost": 30, "cd": 9.0, "desc": "在准星处斩出一道影刃，把魂兽挑飞"},
	"ym_hundred": {"name": "幽冥百爪", "type": "rain", "target": "aim", "radius": 6.0, "damage": 30.0, "impulse": 4.0, "waves": 6, "cost": 50, "cd": 18.0, "desc": "六连爪影"},
	"ym_ghost": {"name": "幽冥灵魂", "type": "buff", "target": "self", "stat": "speed", "amount": 0.5, "dur": 8.0, "cost": 35, "cd": 16.0, "desc": "移速 +50%"},
	# 火凤凰
	"hf_fire": {"name": "凤凰火线", "type": "projectile", "target": "dir", "speed": 40.0, "radius": 4.5, "damage": 65.0, "impulse": 5.0, "burn": 8.0, "cost": 25, "cd": 6.0, "desc": "火球命中爆开，灼烧魂兽"},
	"hf_bath": {"name": "浴火", "type": "buff", "target": "self", "stat": "regen", "amount": 10.0, "dur": 8.0, "cost": 25, "cd": 14.0, "desc": "8 秒内每秒回 10 体力"},
	"hf_wing": {"name": "凤翼天翔", "type": "leap", "target": "self", "height": 12.0, "radius": 6.0, "damage": 60.0, "impulse": 8.0, "cost": 30, "cd": 10.0, "desc": "冲上高空，落地炸飞周围魂兽"},
	"hf_rain": {"name": "火雨", "type": "rain", "target": "aim", "radius": 7.0, "damage": 35.0, "impulse": 3.0, "waves": 5, "burn": 6.0, "cost": 35, "cd": 14.0, "desc": "准星处降下火雨"},
	"hf_blast": {"name": "凤凰啸天击", "type": "projectile", "target": "dir", "speed": 30.0, "radius": 9.0, "damage": 160.0, "impulse": 12.0, "burn": 12.0, "cost": 55, "cd": 20.0, "desc": "巨大的凤凰火球"},
	"hf_rebirth": {"name": "涅槃", "type": "heal", "target": "self", "radius": 20.0, "amount": 100.0, "cost": 55, "cd": 30.0, "desc": "全队回满体力"},
	# 七宝琉璃塔
	"qb_power": {"name": "力量增幅", "type": "buff", "target": "self", "radius": 20.0, "stat": "dmg", "amount": 0.25, "dur": 12.0, "team": true, "cost": 25, "cd": 16.0, "desc": "全队伤害 +25%"},
	"qb_speed": {"name": "速度增幅", "type": "buff", "target": "self", "radius": 20.0, "stat": "speed", "amount": 0.3, "dur": 12.0, "team": true, "cost": 25, "cd": 16.0, "desc": "全队移速和换弹 +30%"},
	"qb_soul": {"name": "魂力增幅", "type": "buff", "target": "self", "radius": 20.0, "stat": "soul", "amount": 1.0, "dur": 12.0, "team": true, "cost": 20, "cd": 20.0, "desc": "全队魂力恢复翻倍"},
	"qb_guard": {"name": "防御增幅", "type": "shield", "target": "self", "radius": 20.0, "amount": 50.0, "dur": 10.0, "team": true, "cost": 35, "cd": 20.0, "desc": "全队 50 点护盾"},
	"qb_seven": {"name": "七宝转出有琉璃", "type": "buff", "target": "self", "radius": 25.0, "stat": "all", "amount": 0.35, "dur": 12.0, "team": true, "cost": 55, "cd": 28.0, "desc": "全队伤害、移速、换弹全部 +35%"},
	"qb_weak": {"name": "削弱", "type": "mark", "target": "self", "radius": 16.0, "dur": 10.0, "mult": 1.4, "cost": 40, "cd": 18.0, "desc": "16 米内魂兽受到伤害 +40%"},
	# 昊天锤
	"ht_slam": {"name": "重锤", "type": "launch", "target": "aim", "radius": 5.5, "damage": 50.0, "impulse": 11.0, "cost": 25, "cd": 7.0, "desc": "锤子砸地，把一片魂兽震上天"},
	"ht_throw": {"name": "大须弥锤", "type": "projectile", "target": "dir", "speed": 30.0, "radius": 5.0, "damage": 90.0, "impulse": 9.0, "cost": 30, "cd": 9.0, "desc": "扔出昊天锤"},
	"ht_break": {"name": "破甲", "type": "mark", "target": "aim", "radius": 7.0, "dur": 10.0, "mult": 1.5, "cost": 30, "cd": 14.0, "desc": "准星处魂兽受到伤害 +50%（无视铁甲犀的甲）"},
	"ht_nine": {"name": "昊天九绝", "type": "buff", "target": "self", "stat": "dmg", "amount": 0.45, "dur": 8.0, "cost": 35, "cd": 16.0, "desc": "8 秒内伤害 +45%"},
	"ht_storm": {"name": "乱披风锤法", "type": "rain", "target": "aim", "radius": 6.5, "damage": 60.0, "impulse": 10.0, "waves": 3, "cost": 50, "cd": 18.0, "desc": "三连砸，魂兽落不了地"},
	"ht_true": {"name": "昊天真身", "type": "shield", "target": "self", "amount": 120.0, "dur": 10.0, "cost": 50, "cd": 24.0, "desc": "自己 120 点护盾"},
	# 六翼天使
	"ls_light": {"name": "天使圣光", "type": "beam", "target": "dir", "range": 50.0, "damage": 85.0, "pierce": 5, "cost": 25, "cd": 7.0, "desc": "贯穿的圣光"},
	"ls_shield": {"name": "圣光护盾", "type": "shield", "target": "self", "radius": 15.0, "amount": 40.0, "dur": 10.0, "team": true, "cost": 30, "cd": 16.0, "desc": "全队 40 点护盾"},
	"ls_wing": {"name": "天使之翼", "type": "leap", "target": "self", "height": 14.0, "radius": 5.0, "damage": 50.0, "impulse": 7.0, "cost": 25, "cd": 9.0, "desc": "展翼飞上高空"},
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
	"bh_body": {"name": "白虎真身", "type": "shield", "target": "self", "amount": 220.0, "dur": 12.0, "cost": 60, "cd": 26.0, "desc": "自己 220 点护盾"},
	"bh_king": {"name": "白虎流星雨·极", "type": "rain", "target": "aim", "radius": 11.0, "damage": 100.0, "impulse": 9.0, "waves": 6, "cost": 75, "cd": 30.0, "desc": "六轮流星"},
	"bh_rage": {"name": "邪眸白虎", "type": "buff", "target": "self", "stat": "all", "amount": 0.5, "dur": 12.0, "cost": 70, "cd": 32.0, "desc": "伤害、移速、换弹 +50%"},
	"ym_blink": {"name": "幽冥瞬影", "type": "dash", "target": "dir", "dist": 18.0, "damage": 160.0, "radius": 3.5, "impulse": 7.0, "cost": 50, "cd": 10.0, "desc": "瞬移 18 米，路上的魂兽受重创"},
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
}

# 每个武魂的魂技树：第 1/2/3/4/5 魂环各两个选项
const SKILL_TREE := {
	"lyc": [["lyc_root", "lyc_spike"], ["lyc_mark", "lyc_pull"], ["lyc_cage", "lyc_dance"], ["lyc_wall", "lyc_storm"], ["lyc_king", "lyc_life"]],
	"ld": [["ld_whirl", "ld_scythe"], ["ld_reap", "ld_fly"], ["ld_doom", "ld_shadow"], ["ld_moon", "ld_harvest"], ["ld_god", "ld_fury"]],
	"xc": [["xc_heal", "xc_boost"], ["xc_regen", "xc_fly"], ["xc_big", "xc_boom"], ["xc_feast", "xc_power"], ["xc_giant", "xc_nuke"]],
	"bh": [["bh_guard", "bh_wave"], ["bh_vajra", "bh_meteor"], ["bh_charge", "bh_roar"], ["bh_tiger", "bh_body"], ["bh_king", "bh_rage"]],
	"ym": [["ym_dash", "ym_claw"], ["ym_clone", "ym_slash"], ["ym_hundred", "ym_ghost"], ["ym_blink", "ym_night"], ["ym_true", "ym_storm"]],
	"hf": [["hf_fire", "hf_bath"], ["hf_wing", "hf_rain"], ["hf_blast", "hf_rebirth"], ["hf_meteor", "hf_wall"], ["hf_true", "hf_sun"]],
	"qb": [["qb_power", "qb_speed"], ["qb_soul", "qb_guard"], ["qb_seven", "qb_weak"], ["qb_break", "qb_wall"], ["qb_nine", "qb_heal"]],
	"ht": [["ht_slam", "ht_throw"], ["ht_break", "ht_nine"], ["ht_storm", "ht_true"], ["ht_quake", "ht_break2"], ["ht_nine2", "ht_fall"]],
	"ls": [["ls_light", "ls_shield"], ["ls_wing", "ls_judge"], ["ls_sword", "ls_domain"], ["ls_holy", "ls_bless"], ["ls_god", "ls_true"]],
}
const SKILL_KEYS := ["Q", "C", "X", "Z", "V"]
const RING_NAMES := ["一", "二", "三", "四", "五", "六", "七", "八", "九"]

# ================================================================ 魂骨（Boss 掉落，被动加成）
const BONES := {
	"mandala_skull": {"name": "曼陀罗蛇头骨", "desc": "爆头伤害 +15%", "stat": "headshot", "amount": 0.15},
	"mandala_spine": {"name": "曼陀罗蛇躯干骨", "desc": "最大体力 +30", "stat": "hp", "amount": 30.0},
	"spider_leg": {"name": "人面魔蛛八蛛矛", "desc": "伤害 +10%", "stat": "dmg", "amount": 0.1},
	"spider_eye": {"name": "人面魔蛛之眼", "desc": "魂力上限 +25", "stat": "soul", "amount": 25.0},
	"titan_arm": {"name": "泰坦巨猿右臂骨", "desc": "伤害 +12%", "stat": "dmg", "amount": 0.12},
	"titan_heart": {"name": "泰坦巨猿躯干骨", "desc": "最大体力 +50", "stat": "hp", "amount": 50.0},
	"dragon_wing": {"name": "冰霜巨龙翼骨", "desc": "爆头伤害 +20%", "stat": "headshot", "amount": 0.2},
	"dragon_scale": {"name": "冰霜巨龙头骨", "desc": "魂力上限 +40", "stat": "soul", "amount": 40.0},
	"whale_bone": {"name": "深海魔鲸脊骨", "desc": "伤害 +15%", "stat": "dmg", "amount": 0.15},
	"whale_heart": {"name": "深海魔鲸之心", "desc": "最大体力 +80", "stat": "hp", "amount": 80.0},
}

# ================================================================ Boss
const BOSSES := {
	# ai：water 水里钻来钻去 / land 地上 / air 天上飞
	"mandala": {"name": "湖主 · 千年曼陀罗蛇", "hp": 7500.0, "reward": 400, "xp": 400, "bones": ["mandala_skull", "mandala_spine"], "age": 2, "ai": "water",
		"model": "snake_angry", "fit": "h", "size": 9.0, "tint": Color(1.0, 0.5, 1.2), "summon": "snake", "ring_beast": "snake"},
	"spider": {"name": "森林之主 · 人面魔蛛", "hp": 13000.0, "reward": 800, "xp": 900, "bones": ["spider_leg", "spider_eye"], "age": 2, "ai": "land",
		"model": "spider", "fit": "w", "size": 8.5, "tint": Color(0.6, 0.45, 0.7), "summon": "wolf", "ring_beast": "wolf"},
	"titan": {"name": "星斗之王 · 泰坦巨猿", "hp": 20000.0, "reward": 1400, "xp": 1800, "bones": ["titan_arm", "titan_heart"], "age": 2, "ai": "land",
		"model": "yeti", "fit": "h", "size": 9.0, "tint": Color(0.42, 0.36, 0.34), "summon": "raptor", "ring_beast": "stag", "throws": true},
	"icedragon": {"name": "极北之主 · 冰霜巨龙", "hp": 28000.0, "reward": 2200, "xp": 2800, "bones": ["dragon_wing", "dragon_scale"], "age": 2, "ai": "air",
		"model": "dragon", "fit": "w", "size": 16.0, "tint": Color(0.6, 0.85, 1.3), "glow": Color(0.1, 0.3, 0.6), "summon": "husky", "ring_beast": "icehorn"},
	"whale": {"name": "海神岛之主 · 深海魔鲸", "hp": 38000.0, "reward": 3500, "xp": 4000, "bones": ["whale_bone", "whale_heart"], "age": 2, "ai": "water",
		"model": "whale", "fit": "l", "size": 22.0, "tint": Color(0.55, 0.6, 0.9), "summon": "shark", "ring_beast": "shark"},
}

# ================================================================ 章节与任务
# type：kill 击杀数 / buy 买暗器 / level 等级 / rings 魂环数 / altar 点祭坛 / boss 打 Boss / boat 坐船
const CHAPTERS := {
	1: {
		"name": "第一章 · 湖心岛", "map": "island", "boss": "mandala", "next": 2,
		"intro": "圣魂村外的湖心小岛。先用引魂索抓几只魂兽练练手，再去码头边的唐门暗器铺换把好暗器。",
		"quests": [
			{"type": "kill", "n": 1, "text": "用引魂索拽出一只魂兽，在空中打死它", "reward": 30},
			{"type": "kill", "n": 8, "text": "猎杀 8 只魂兽（金魂币可以在暗器铺花）", "reward": 80},
			{"type": "buy", "n": 1, "text": "去码头边的唐门暗器铺（按 F）买一把新暗器", "reward": 50, "target": "shop"},
			{"type": "hunt", "species": "moth", "n": 3, "text": "去月光花丛抓 3 只月光蛾", "reward": 60},
			{"type": "level", "n": 10, "text": "魂力修炼到 10 级", "reward": 80},
			{"type": "rings", "n": 1, "text": "猎杀魂兽，吸收第一个魂环（到 10 级瓶颈才能吸收）", "reward": 100},
			{"type": "altar", "n": 1, "text": "去北边山坡的祭坛（按 F）点燃曼陀罗香，召唤湖主", "reward": 0, "target": "altar"},
			{"type": "boss", "n": 1, "text": "击败湖主 · 千年曼陀罗蛇", "reward": 0},
			{"type": "boat", "n": 1, "text": "去码头尽头的船（按 F），前往落日森林", "reward": 0, "target": "boat"},
		],
	},
	2: {
		"name": "第二章 · 落日森林", "map": "forest", "boss": "spider", "next": 3,
		"intro": "落日森林，傍晚的光从树缝里漏下来。这里的魂兽会反击：魔狼会扑人，铁甲犀会冲撞，金刚猿会扔石头。",
		"quests": [
			{"type": "kill", "n": 10, "text": "在落日森林猎杀 10 只魂兽", "reward": 150},
			{"type": "hunt", "species": "wolf", "n": 4, "text": "去狼穴猎杀 4 只疾风魔狼（小心它扑人）", "reward": 120},
			{"type": "hunt", "species": "rhino", "n": 3, "text": "去泥潭猎杀 3 只铁甲犀（打头不减伤）", "reward": 150},
			{"type": "level", "n": 20, "text": "魂力修炼到 20 级", "reward": 150},
			{"type": "rings", "n": 2, "text": "吸收第二个魂环（至少百年）", "reward": 200},
			{"type": "altar", "n": 1, "text": "去森林中心古树下的祭坛（按 F），召唤森林之主", "reward": 0, "target": "altar"},
			{"type": "boss", "n": 1, "text": "击败森林之主 · 人面魔蛛", "reward": 0},
			{"type": "boat", "n": 1, "text": "去码头的船（按 F），前往星斗大森林", "reward": 0, "target": "boat"},
		],
	},
	3: {
		"name": "第三章 · 星斗大森林", "map": "deepforest", "boss": "titan", "next": 4,
		"intro": "斗罗大陆最大的魂兽森林，古木参天、终年雾气缭绕，林间长着会发光的蓝银草。这里的魂兽成群出没，百年、千年的越来越多。",
		"quests": [
			{"type": "kill", "n": 12, "text": "在星斗大森林猎杀 12 只魂兽", "reward": 250},
			{"type": "hunt", "species": "stag", "n": 4, "text": "去鬼眼鹿林猎杀 4 只鬼眼鹿", "reward": 200},
			{"type": "hunt", "species": "bat", "n": 4, "text": "去蝠巢枯林打下 4 只夜翼魔蝠", "reward": 200},
			{"type": "upgrade", "n": 1, "text": "去行脚商人那里升级一次暗器（按 F）", "reward": 150, "target": "shop"},
			{"type": "hunt", "species": "raptor", "n": 3, "text": "去龙爪荆棘猎杀 3 只疾爪龙", "reward": 250},
			{"type": "hunt", "species": "spiderling", "n": 3, "text": "去魔蛛巢穴猎杀 3 只地穴魔蛛", "reward": 250},
			{"type": "level", "n": 30, "text": "魂力修炼到 30 级", "reward": 300},
			{"type": "rings", "n": 3, "text": "吸收第三个魂环（至少百年）", "reward": 400},
			{"type": "altar", "n": 1, "text": "去星斗古树下的祭坛（按 F），唤醒星斗之王", "reward": 0, "target": "altar"},
			{"type": "boss", "n": 1, "text": "击败星斗之王 · 泰坦巨猿", "reward": 0},
			{"type": "boat", "n": 1, "text": "去码头的船（按 F），前往极北之地", "reward": 0, "target": "boat"},
		],
	},
	4: {
		"name": "第四章 · 极北之地", "map": "snow", "boss": "icedragon", "next": 5,
		"intro": "终年冰雪的极北之地。冰甲龙皮糙肉厚，雪魔猿会扔冰块，冰湖里的冰鳞鱼要用引魂索拽出来。",
		"quests": [
			{"type": "kill", "n": 15, "text": "在极北之地猎杀 15 只魂兽", "reward": 350},
			{"type": "hunt", "species": "husky", "n": 4, "text": "去雪狼洞猎杀 4 只雪原狼", "reward": 300},
			{"type": "hunt", "species": "icefish", "n": 5, "text": "从冰湖里拽出 5 只冰鳞鱼", "reward": 300},
			{"type": "hunt", "species": "icehorn", "n": 3, "text": "去冰原猎杀 3 只冰甲龙（打头）", "reward": 400},
			{"type": "hunt", "species": "snowape", "n": 3, "text": "去冰窟猎杀 3 只雪魔猿", "reward": 400},
			{"type": "hunt", "species": "icedeer", "n": 3, "text": "去冰晶林猎杀 3 只冰角鹿", "reward": 350},
			{"type": "level", "n": 40, "text": "魂力修炼到 40 级", "reward": 450},
			{"type": "rings", "n": 4, "text": "吸收第四个魂环（至少千年）", "reward": 600},
			{"type": "altar", "n": 1, "text": "去北边冰崖上的祭坛（按 F），召唤冰霜巨龙", "reward": 0, "target": "altar"},
			{"type": "boss", "n": 1, "text": "击败极北之主 · 冰霜巨龙（它会飞，躲开冰息）", "reward": 0},
			{"type": "boat", "n": 1, "text": "去码头的船（按 F），前往海神岛", "reward": 0, "target": "boat"},
		],
	},
	5: {
		"name": "第五章 · 海神岛", "map": "sea", "boss": "whale", "next": 0,
		"intro": "传说中的海神岛。浅海有彩鳞鱼，深海有魔鲨，海渊里的幽灵鳐会在空中滑翔。打败深海魔鲸，就是真正的封号斗罗。",
		"quests": [
			{"type": "kill", "n": 15, "text": "在海神岛猎杀 15 只魂兽", "reward": 500},
			{"type": "hunt", "species": "reeffish", "n": 5, "text": "从浅海拽出 5 只彩鳞鱼", "reward": 400},
			{"type": "hunt", "species": "crab", "n": 4, "text": "去金沙滩猎杀 4 只铁钳蟹", "reward": 450},
			{"type": "hunt", "species": "gull", "n": 4, "text": "去海崖打下 4 只海魂鸥", "reward": 450},
			{"type": "hunt", "species": "shark", "n": 4, "text": "把引魂索抛进深海，猎杀 4 只深海魔鲨", "reward": 550},
			{"type": "hunt", "species": "manta", "n": 3, "text": "抛到最远的海渊，猎杀 3 只幽灵鳐", "reward": 600},
			{"type": "level", "n": 50, "text": "魂力修炼到 50 级", "reward": 700},
			{"type": "rings", "n": 5, "text": "吸收第五个魂环（至少千年）", "reward": 1000},
			{"type": "altar", "n": 1, "text": "去北岸的海神祭坛（按 F），召唤深海魔鲸", "reward": 0, "target": "altar"},
			{"type": "boss", "n": 1, "text": "击败海神岛之主 · 深海魔鲸", "reward": 0},
			{"type": "end", "n": 1, "text": "通关！你已经是魂圣了。继续在海神岛猎杀千年魂兽吧", "reward": 0},
		],
	},
}


# ================================================================ 工具函数

func age_name(age: int) -> String:
	return AGES[clampi(age, 0, AGES.size() - 1)]["name"]


func age_color(age: int) -> Color:
	return AGES[clampi(age, 0, AGES.size() - 1)]["color"]


## 越往后的章节，百年、千年魂兽越多
const AGE_WEIGHTS := {1: [70.0, 25.0, 5.0], 2: [62.0, 30.0, 8.0], 3: [52.0, 36.0, 12.0], 4: [42.0, 40.0, 18.0], 5: [32.0, 43.0, 25.0]}


func roll_age(rng: RandomNumberGenerator, min_age := 0, chapter := 1) -> int:
	var w: Array = AGE_WEIGHTS.get(chapter, AGE_WEIGHTS[1])
	var total := 0.0
	for i in range(min_age, w.size()):
		total += float(w[i])
	var r := rng.randf() * total
	for i in range(min_age, w.size()):
		r -= float(w[i])
		if r <= 0.0:
			return i
	return min_age


func beast_max_hp(species: String, age: int) -> float:
	return BEASTS[species]["hp"] * AGES[age]["hp"]


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
	var sk := 1.0 - 0.1 * lv_stab
	for k in ["hip", "ads", "move", "bloom"]:
		d[k] = d[k] * sk
	return d


func upgrade_price(id: String, level: int) -> int:
	var base := maxi(int(WEAPONS[id]["price"]), 250)
	return int(round(base * UPGRADE_COST[clampi(level, 0, UPGRADE_COST.size() - 1)] / 10.0)) * 10


func quest(chapter: int, idx: int) -> Dictionary:
	var qs: Array = CHAPTERS[chapter]["quests"]
	if idx < 0 or idx >= qs.size():
		return {}
	return qs[idx]
