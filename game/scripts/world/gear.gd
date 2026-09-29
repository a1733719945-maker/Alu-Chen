class_name Gear
## 装备树（2026-09-29，长线第一根柱子，CLAUDE.md 7.5）：猎王 → 拿部位材料 → 做护具 / 锻暗器 → 去猎更难的。
##
## 护具：头盔 / 身甲 / 护腕 / 靴四件，每种灵兽王一套（用这只王的部位材料 + 王魄 + 灵石做）。
##   每件都有一点护体（章节越后面越厚）；同一类套装（KIND，比如追风狼和雪原狼都是"疾风"）混穿也算件数：
##   两件开一个小加成，四件开**改打法的技能**（用户："加按钮 / 加倍数不算好玩"）。"猎 A 拿装备，才好打 B"：
##   见机套（极限闪避后一箭翻倍）好打冲锋多的王，缠魂套（捆得久）好活捉，铁甲套好扛大招……
## 锻造：每把暗器五品（碧 / 赤 / 玄 / 霜 / 幽），第 N 品用第 N 章灵兽王的部位材料和王魄，第五品还要一颗灵核；每品 +FORGE_DMG 伤害。
##   哪一种暗器都不是最强（Data.weapon_stats 按章节拉平），投入过的那把更强
## 灵核：猎场猎物打死 / 活捉时每人 CORE_RATE 几率掉一颗，连着 CORE_PITY 次没掉下次必掉（保底）
##
## 客人的套装发在 prog / hello 里（peer_info[peer]["gear"]），房主算捆魂、打晕时按它

const SLOTS := ["head", "body", "arms", "legs"]
const SLOT_NAMES := {"head": "盔", "body": "甲", "arms": "护腕", "legs": "靴"}
## 每件要这只王的哪些部位（会飞的没有背甲，身甲用翼）+ MAT 个王魄 + 灵石
const COST := {"head": {"head": 2}, "body": {"back": 2}, "arms": {"head": 1, "tail": 1}, "legs": {"tail": 2}}
const MAT := 1
const PRICE := 300
## 每种灵兽王的护具是哪一类套装
const KIND := {"wolf": "swift", "husky": "swift", "raptor": "swift",
	"rhino": "iron", "icehorn": "iron", "crab": "iron",
	"ape": "breaker", "snowape": "breaker",
	"spiderling": "bind", "vine": "bind",
	"bird": "sky", "bat": "sky", "gull": "sky", "moth": "sky",
	"stag": "hunter", "icedeer": "hunter",
	"snake": "counter", "frog": "counter",
	"rabbit": "renew"}
## 套装技能（不写数字：用户说描述得太详细）
const SKILLS := {
	"swift": {"name": "疾风", "two": "跑得快一点", "four": "翻滚冷却减半，翻完一阵跑得飞快", "color": Color(0.55, 0.9, 0.75)},
	"iron": {"name": "铁甲", "two": "挨打少一点", "four": "血少的时候挨打再少一大截", "color": Color(0.75, 0.78, 0.85)},
	"breaker": {"name": "破势", "two": "打头更痛", "four": "打头把王打晕得快得多", "color": Color(1.0, 0.6, 0.35)},
	"bind": {"name": "缠魂", "two": "捆住的王挨你打更痛", "four": "引魂索捆得更久", "color": Color(0.5, 0.95, 0.55)},
	"sky": {"name": "凌空", "two": "跳得更高", "four": "人在空中开火更痛、也不散", "color": Color(0.6, 0.85, 1.0)},
	"hunter": {"name": "追猎", "two": "开镜更快", "four": "离得越远打得越痛", "color": Color(0.95, 0.85, 0.5)},
	"counter": {"name": "见机", "two": "极限闪避回更多灵力", "four": "极限闪避后下一箭翻倍", "color": Color(0.7, 0.6, 1.0)},
	"renew": {"name": "回春", "two": "回血更快", "four": "打中灵兽王回一点血", "color": Color(1.0, 0.6, 0.7)},
}
const KIND_ORDER := ["swift", "iron", "breaker", "bind", "sky", "hunter", "counter", "renew"]

## 锻造
const FORGE_MAX := 5
const FORGE_DMG := 0.08
const FORGE_NAME := {1: "碧", 2: "赤", 3: "玄", 4: "霜", 5: "幽"}
const FORGE_PARTS := 3
const FORGE_MATS := 2
const FORGE_PRICE := 600
## 灵核
const CORE_RATE := 0.04
const CORE_PITY := 10

## 套装数值（改这里）
const SWIFT_SPEED := 0.06
const IRON_K := 0.94
const IRON_LOW_K := 0.7
const BREAKER_HEAD := 1.08
const BREAKER_STUN := 0.6
const BIND_DMG := 1.12
const BIND_TIME := 1.5
const SKY_JUMP := 1.15
const SKY_DMG := 1.25
const HUNTER_ADS := 0.85
const HUNTER_FAR := 0.25
const COUNTER_SOUL := 2.0
const RENEW_REGEN := 1.3
const RENEW_LEECH := 0.015


# ------------------------------------------------------------------ 护具

static func fly(sp: String) -> bool:
	return str(Data.BEASTS.get(sp, {}).get("motion", "")) in ["fly", "flutter"]


## 能做护具的灵兽（有套装的）
static func species() -> Array:
	var out: Array = []
	for sp in Data.SPECIES_CH:
		if KIND.has(sp):
			out.append(sp)
	out.sort_custom(func(a, b): return int(Data.SPECIES_CH[a]) < int(Data.SPECIES_CH[b]))
	return out


static func piece_name(sp: String, slot: String) -> String:
	return "%s%s" % [str(Data.BEASTS[sp]["name"]), str(SLOT_NAMES[slot])]


## 这件要什么：{"parts": {"狼|head": 2}, "mat": 1, "money": 900}
static func cost(sp: String, slot: String) -> Dictionary:
	var ps := {}
	for p in COST[slot]:
		var part := str(p)
		if part == "back" and fly(sp):
			part = "wing"
		ps["%s|%s" % [sp, part]] = int(COST[slot][p])
	var ch := int(Data.SPECIES_CH.get(sp, 1))
	return {"parts": ps, "mat": MAT, "money": int(PRICE * float(Data.CH_PRICE.get(ch, 1.0)))}


static func owns(sp: String, slot: String) -> bool:
	return Profile.gear.has("%s|%s" % [sp, slot])


static func can_craft(sp: String, slot: String) -> bool:
	if owns(sp, slot):
		return false
	var c := cost(sp, slot)
	for k in c["parts"]:
		if int(Profile.parts.get(k, 0)) < int(c["parts"][k]):
			return false
	return int(Profile.materials.get(sp, 0)) >= int(c["mat"]) and Profile.money >= int(c["money"])


static func craft(sp: String, slot: String) -> bool:
	if not can_craft(sp, slot):
		return false
	var c := cost(sp, slot)
	for k in c["parts"]:
		Profile.parts[k] = int(Profile.parts[k]) - int(c["parts"][k])
	Profile.materials[sp] = int(Profile.materials[sp]) - int(c["mat"])
	Profile.spend(int(c["money"]))
	Profile.gear["%s|%s" % [sp, slot]] = 1
	# 做出来就穿上
	Profile.gear_on[slot] = sp
	Profile.mark_dirty()
	return true


static func toggle(sp: String, slot: String) -> void:
	if not owns(sp, slot):
		return
	if str(Profile.gear_on.get(slot, "")) == sp:
		Profile.gear_on.erase(slot)
	else:
		Profile.gear_on[slot] = sp
	Profile.mark_dirty()


## 这件护具的护体（章节越后面越厚）
static func piece_armor(sp: String) -> float:
	return 0.01 + 0.005 * float(Data.SPECIES_CH.get(sp, 1))


## 身上穿的：护体加起来
static func armor() -> float:
	var t := 0.0
	for slot in Profile.gear_on:
		t += piece_armor(str(Profile.gear_on[slot]))
	return t


## 身上每一类套装穿了几件：{"swift": 2, ...}
static func worn() -> Dictionary:
	var out := {}
	for slot in Profile.gear_on:
		var k := str(KIND.get(str(Profile.gear_on[slot]), ""))
		if k != "":
			out[k] = int(out.get(k, 0)) + 1
	return out


## 自己这一类套装穿了几件
static func n(kind: String) -> int:
	return int(worn().get(kind, 0))


## 某个人（房主算捆魂 / 打晕时用）这一类穿了几件
static func peer_n(world: Node, peer: int, kind: String) -> int:
	if peer == Net.my_id:
		return n(kind)
	var info: Dictionary = world.peer_info.get(peer, {})
	return int((info.get("gear", {}) as Dictionary).get(kind, 0))


# ------------------------------------------------------------------ 锻造

static func grade(weapon: String) -> int:
	return int(Profile.forge.get(weapon, 0))


static func forged_name(weapon: String) -> String:
	var g := grade(weapon)
	var nm := str(Data.WEAPONS[weapon]["name"])
	return nm if g <= 0 else "%s·%s" % [nm, str(FORGE_NAME[g])]


## 锻到下一品要什么：第 g 品用第 g 章灵兽王的部位（任意）FORGE_PARTS 个 + 王魄 FORGE_MATS 个 + 灵石，第五品再加一颗灵核
static func forge_cost(weapon: String) -> Dictionary:
	var g := grade(weapon) + 1
	if g > FORGE_MAX:
		return {}
	return {"grade": g, "parts": FORGE_PARTS, "mats": FORGE_MATS, "core": 1 if g >= FORGE_MAX else 0,
		"money": int(FORGE_PRICE * float(Data.CH_PRICE.get(g, 1.0)))}


## 第 ch 章灵兽王的部位材料一共有几个（不算灵核）
static func ch_parts(ch: int) -> int:
	var t := 0
	for k in Profile.parts:
		var sp := str(k).get_slice("|", 0)
		if str(k).get_slice("|", 1) != "core" and int(Data.SPECIES_CH.get(sp, 0)) == ch:
			t += int(Profile.parts[k])
	return t


static func ch_mats(ch: int) -> int:
	var t := 0
	for sp in Profile.materials:
		if int(Data.SPECIES_CH.get(str(sp), 0)) == ch:
			t += int(Profile.materials[sp])
	return t


static func cores() -> int:
	var t := 0
	for k in Profile.parts:
		if str(k).get_slice("|", 1) == "core":
			t += int(Profile.parts[k])
	return t


static func can_forge(weapon: String) -> bool:
	var c := forge_cost(weapon)
	if c.is_empty():
		return false
	var g := int(c["grade"])
	return ch_parts(g) >= int(c["parts"]) and ch_mats(g) >= int(c["mats"]) and cores() >= int(c["core"]) and Profile.money >= int(c["money"])


static func forge(weapon: String) -> bool:
	if not can_forge(weapon):
		return false
	var c := forge_cost(weapon)
	var g := int(c["grade"])
	_take_parts(func(k: String) -> bool:
		return k.get_slice("|", 1) != "core" and int(Data.SPECIES_CH.get(k.get_slice("|", 0), 0)) == g, int(c["parts"]))
	var need := int(c["mats"])
	for sp in Profile.materials.keys():
		if need <= 0:
			break
		if int(Data.SPECIES_CH.get(str(sp), 0)) != g:
			continue
		var use := mini(int(Profile.materials[sp]), need)
		Profile.materials[sp] = int(Profile.materials[sp]) - use
		need -= use
	if int(c["core"]) > 0:
		_take_parts(func(k: String) -> bool: return k.get_slice("|", 1) == "core", int(c["core"]))
	Profile.spend(int(c["money"]))
	Profile.forge[weapon] = g
	Profile.mark_dirty()
	return true


static func _take_parts(ok: Callable, need: int) -> void:
	# 先用最多的那种
	var keys: Array = Profile.parts.keys().filter(func(k): return ok.call(str(k)) and int(Profile.parts[k]) > 0)
	keys.sort_custom(func(a, b): return int(Profile.parts[a]) > int(Profile.parts[b]))
	for k in keys:
		if need <= 0:
			return
		var use := mini(int(Profile.parts[k]), need)
		Profile.parts[k] = int(Profile.parts[k]) - use
		need -= use


# ------------------------------------------------------------------ 灵核

## 猎场猎物打死 / 活捉：每个人自己掷一次（连着 CORE_PITY 次没掉，下次必掉）。返回掉没掉
static func roll_core(sp: String, captured: bool) -> bool:
	var key := "core_pity"
	var miss := int(Profile.stats.get(key, 0))
	var rate := CORE_RATE * (1.5 if captured else 1.0)
	if miss + 1 >= CORE_PITY or randf() < rate:
		Profile.stats[key] = 0
		Profile.add_part(sp, "core")
		return true
	Profile.stats[key] = miss + 1
	Profile.mark_dirty()
	return false
