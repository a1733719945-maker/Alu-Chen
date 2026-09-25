extends Node
## 个人存档：金魂币、魂力等级、魂环、魂技、暗器和升级、道具、魂骨、章节进度。
## 存在自己电脑上（user://profile.json）。联机时每个人用自己的存档，房主的存档决定当前章节。

signal changed

var path := "user://profile.json"   # 自动测试会换成别的文件，不碰玩家的存档
const VERSION := 2

var money := 0
var xp := 0
var level := 1
var weapons: Array = ["xiujian"]
var upgrades := {}          # 暗器 id -> {"dmg": 0, "mag": 0, "reload": 0, "stab": 0}
var items := {"grenade": 2, "pill": 1}
var rings: Array = []       # [{"age": int, "skill": String, "beast": String}]
var bones: Array = []
var chapter := 1
var quest := 0              # 当前章节的任务进度
var quest_count := 0        # 当前任务的计数（击杀数等）
var kills := 0
var loadout: Array = ["xiujian"]   # 按 1-5 键的顺序
var _dirty := false
var _save_t := 0.0


func _ready() -> void:
	load_profile()


func _process(dt: float) -> void:
	if _dirty:
		_save_t += dt
		if _save_t > 1.0:
			save_profile()


func load_profile() -> void:
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return
	money = int(d.get("money", 0))
	xp = int(d.get("xp", 0))
	level = int(d.get("level", 1))
	weapons = d.get("weapons", ["xiujian"])
	upgrades = d.get("upgrades", {})
	items = d.get("items", {"grenade": 2, "pill": 1})
	rings = d.get("rings", [])
	bones = d.get("bones", [])
	chapter = int(d.get("chapter", 1))
	quest = int(d.get("quest", 0))
	quest_count = int(d.get("quest_count", 0))
	kills = int(d.get("kills", 0))
	loadout = d.get("loadout", weapons.duplicate())
	# 旧存档里可能有已经删掉的暗器
	weapons = weapons.filter(func(w): return Data.WEAPONS.has(w))
	if weapons.is_empty():
		weapons = ["xiujian"]
	_fix_loadout()
	if not Data.CHAPTERS.has(chapter):
		chapter = 1
		quest = 0


func save_profile() -> void:
	_dirty = false
	_save_t = 0.0
	var d := {
		"version": VERSION, "money": money, "xp": xp, "level": level, "weapons": weapons,
		"upgrades": upgrades, "items": items, "rings": rings, "bones": bones,
		"chapter": chapter, "quest": quest, "quest_count": quest_count, "kills": kills, "loadout": loadout,
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d, "  "))


func mark_dirty() -> void:
	_dirty = true
	changed.emit()


func reset() -> void:
	money = 0
	xp = 0
	level = 1
	weapons = ["xiujian"]
	upgrades = {}
	items = {"grenade": 2, "pill": 1}
	rings = []
	bones = []
	chapter = 1
	quest = 0
	quest_count = 0
	kills = 0
	loadout = ["xiujian"]
	save_profile()
	changed.emit()


func _fix_loadout() -> void:
	var order: Array = []
	for w in Data.WEAPON_ORDER:
		if w in weapons:
			order.append(w)
	loadout = order


# ------------------------------------------------------------------ 金魂币

func add_money(n: int) -> void:
	money += n
	mark_dirty()


func spend(n: int) -> bool:
	if money < n:
		return false
	money -= n
	mark_dirty()
	return true


# ------------------------------------------------------------------ 暗器

func has_weapon(id: String) -> bool:
	return id in weapons


func buy_weapon(id: String) -> bool:
	if has_weapon(id) or not spend(int(Data.WEAPONS[id]["price"])):
		return false
	weapons.append(id)
	_fix_loadout()
	mark_dirty()
	return true


func upgrade_level(id: String, key: String) -> int:
	return int(upgrades.get(id, {}).get(key, 0))


func buy_upgrade(id: String, key: String) -> bool:
	var lv := upgrade_level(id, key)
	if lv >= Data.UPGRADE_COST.size():
		return false
	if not spend(Data.upgrade_price(id, lv)):
		return false
	if not upgrades.has(id):
		upgrades[id] = {}
	upgrades[id][key] = lv + 1
	mark_dirty()
	return true


func weapon_stats(id: String) -> Dictionary:
	var d := Data.weapon_stats(id, upgrades.get(id, {}))
	# 魂骨：爆头加成、伤害加成
	d["headshot"] = d["headshot"] * (1.0 + bone_bonus("headshot"))
	d["damage"] = d["damage"] * (1.0 + bone_bonus("dmg"))
	return d


# ------------------------------------------------------------------ 道具

func item_count(id: String) -> int:
	return int(items.get(id, 0))


func buy_item(id: String) -> bool:
	var it: Dictionary = Data.ITEMS[id]
	if id == "lure_gold":
		# 引兽香：一包管 5 次咬钩
		if item_count("gold_bites") >= 15 or not spend(int(it["price"])):
			return false
		items["gold_bites"] = item_count("gold_bites") + 5
		mark_dirty()
		return true
	if item_count(id) >= int(it["max"]) or not spend(int(it["price"])):
		return false
	items[id] = item_count(id) + 1
	mark_dirty()
	return true


func use_item(id: String) -> bool:
	if item_count(id) <= 0:
		return false
	items[id] = item_count(id) - 1
	mark_dirty()
	return true


# ------------------------------------------------------------------ 等级与魂环

func level_cap() -> int:
	# 每 10 级要一个魂环才能突破
	return mini((rings.size() + 1) * 10, Data.MAX_LEVEL)


func max_rings() -> int:
	return (Data.SKILL_TREE["lyc"] as Array).size()


## 卡在瓶颈：到了下一个魂环要求的等级，还没吸收那个魂环
func at_bottleneck() -> bool:
	return rings.size() < max_rings() and level >= (rings.size() + 1) * 10


## 加修为，返回升了几级
func add_xp(n: int) -> int:
	if n <= 0:
		return 0
	var ups := 0
	xp += n
	while level < level_cap() and xp >= Data.xp_to_next(level):
		xp -= Data.xp_to_next(level)
		level += 1
		ups += 1
	if level >= level_cap():
		xp = mini(xp, Data.xp_to_next(level) - 1)
	mark_dirty()
	return ups


func next_ring_index() -> int:
	return rings.size()


func can_absorb(age: int) -> String:
	## 返回空字符串表示可以；否则返回原因
	if rings.size() >= max_rings():
		return "这一版最多 %d 个魂环" % max_rings()
	if not at_bottleneck():
		return "要修炼到 %d 级瓶颈才能吸收魂环" % level_cap()
	var min_age: int = Data.RING_MIN_AGE[rings.size()]
	if age < min_age:
		return "第%d魂环至少要%s的魂兽" % [rings.size() + 1, Data.age_name(min_age)]
	return ""


func add_ring(age: int, skill: String, beast: String) -> void:
	rings.append({"age": age, "skill": skill, "beast": beast})
	mark_dirty()


func max_hp() -> float:
	return 100.0 + (level - 1) * 3.0 + bone_bonus("hp")


func max_soul() -> float:
	return 60.0 + (level - 1) * 4.0 + bone_bonus("soul")


func bone_bonus(stat: String) -> float:
	var t := 0.0
	for b in bones:
		var d: Dictionary = Data.BONES.get(b, {})
		if d.get("stat", "") == stat:
			t += float(d["amount"])
	return t


func add_bone(id: String) -> bool:
	if id in bones:
		return false
	bones.append(id)
	mark_dirty()
	return true


func title() -> String:
	return "%d 级%s" % [level, Data.titles(level)]
