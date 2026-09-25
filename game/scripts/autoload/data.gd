extends Node
## 游戏数据表。调数值主要改这里。

const PROTOCOL_VERSION := "m1-3"

var font_ui: Font = preload("res://assets/fonts/NotoSansSC.ttf")
var font_title: Font = preload("res://assets/fonts/MaShanZheng.ttf")

# ---------------------------------------------------------------- 武魂（第一版只影响外观颜色）
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

# ---------------------------------------------------------------- 年份（魂环颜色）
enum Age { TEN, HUNDRED, THOUSAND }
const AGES := [
	{"name": "十年", "color": Color(0.95, 0.95, 0.92), "hp": 1.0, "reward": 1.0, "scale": 1.0, "mass": 1.0, "weight": 74.0},
	{"name": "百年", "color": Color(1.0, 0.82, 0.25), "hp": 2.6, "reward": 3.0, "scale": 1.25, "mass": 1.5, "weight": 23.0},
	{"name": "千年", "color": Color(0.68, 0.36, 1.0), "hp": 6.5, "reward": 10.0, "scale": 1.6, "mass": 2.4, "weight": 3.0},
]

# ---------------------------------------------------------------- 魂兽
# habitat：在哪里能用引魂索引出来
# hp / reward：十年基础值，再乘年份倍率
# motion：落地后的行为（hop 跳着逃 / fly 飞走 / flutter 飘走 / slither 爬回水里）
const BEASTS := {
	"rabbit": {"name": "柔骨兔", "habitat": "burrow", "hp": 30.0, "reward": 10, "motion": "hop", "img": "res://assets/img/beasts/b01.png", "gravity": 0.55},
	"vine": {"name": "鬼藤", "habitat": "water", "hp": 36.0, "reward": 14, "motion": "slither", "img": "res://assets/img/beasts/b02.png", "gravity": 0.6},
	"bird": {"name": "风铃鸟", "habitat": "meadow", "hp": 24.0, "reward": 15, "motion": "fly", "img": "res://assets/img/beasts/b03.png", "gravity": 0.35},
	"moth": {"name": "月光蛾", "habitat": "flowers", "hp": 26.0, "reward": 12, "motion": "flutter", "img": "res://assets/img/beasts/b13.png", "gravity": 0.22},
}

const HABITATS := {
	"water": {"name": "水湾", "beast": "vine"},
	"burrow": {"name": "兔子洞", "beast": "rabbit"},
	"meadow": {"name": "风铃草原", "beast": "bird"},
	"flowers": {"name": "月光花丛", "beast": "moth"},
}

# ---------------------------------------------------------------- 唐门暗器
# damage：单发伤害；pellets：一次射出几根；spread：腰射散布（度）
# impulse：打中魂兽时推它的力度（空中连击靠这个）；lift：额外往上挑的比例
const WEAPONS := [
	{
		"id": "xiujian", "name": "袖箭", "desc": "唐门基础暗器，射速快，爆头伤害翻倍",
		"damage": 26.0, "headshot": 2.0, "pellets": 1, "spread": 0.55, "ads_spread": 0.05,
		"interval": 0.13, "auto": false, "mag": 10, "reload": 1.15, "reload_per_shell": false,
		"range": 180.0, "falloff_start": 60.0, "falloff_end": 160.0, "falloff_min": 0.6,
		"recoil_pitch": 1.25, "recoil_yaw": 0.45, "recoil_recover": 11.0, "shake": 0.16,
		"impulse": 2.2, "lift": 0.55, "ads_fov": 0.72, "ads_time": 0.11,
		"tracer": Color(0.75, 0.95, 1.0), "sound": "xiujian_fire",
	},
	{
		"id": "baoyu", "name": "暴雨梨花针", "desc": "一次射出十四根银针，近距离一发带走",
		"damage": 8.0, "headshot": 1.5, "pellets": 14, "spread": 5.2, "ads_spread": 3.8,
		"interval": 0.78, "auto": false, "mag": 5, "reload": 0.48, "reload_per_shell": true,
		"range": 70.0, "falloff_start": 9.0, "falloff_end": 30.0, "falloff_min": 0.3,
		"recoil_pitch": 5.2, "recoil_yaw": 1.2, "recoil_recover": 7.5, "shake": 0.5,
		"impulse": 0.95, "lift": 0.6, "ads_fov": 0.86, "ads_time": 0.14,
		"tracer": Color(0.9, 0.92, 1.0), "sound": "baoyu_fire",
	},
]

# ---------------------------------------------------------------- 引魂索
const LURE := {
	"min_speed": 13.0, "max_speed": 30.0, "charge_time": 0.55, "up": 0.28,
	"gravity": 18.0, "bite_min": 0.9, "bite_max": 2.4, "bite_window": 1.1,
	"reel_time": 2.4,       # 千年魂兽要拽多久
	"launch_height": 7.5,   # 魂兽被甩上天的高度（相对落点）
	"hurry_after": 2,       # 连续几次没咬钩后，下一次必定很快咬
}

# ---------------------------------------------------------------- 击杀加成（对应 How to Fish 的 Killscore）
const KILL_BONUS := {
	"air": 1.5,          # 空中击杀
	"headshot": 1.25,    # 爆头终结
	"juggle_step": 0.12, # 空中每多挨一下 +12%
	"juggle_max": 1.0,   # 最多 +100%
	"far": 1.2,          # 25 米外
	"far_dist": 25.0,
}


func age_name(age: int) -> String:
	return AGES[clampi(age, 0, AGES.size() - 1)]["name"]


func age_color(age: int) -> Color:
	return AGES[clampi(age, 0, AGES.size() - 1)]["color"]


func roll_age(rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for a in AGES:
		total += a["weight"]
	var r := rng.randf() * total
	for i in AGES.size():
		r -= AGES[i]["weight"]
		if r <= 0.0:
			return i
	return 0


func beast_max_hp(species: String, age: int) -> float:
	return BEASTS[species]["hp"] * AGES[age]["hp"]


func wuhun_color(idx: int) -> Color:
	return WUHUN[clampi(idx, 0, WUHUN.size() - 1)]["color"]
