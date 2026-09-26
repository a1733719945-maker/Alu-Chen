extends Node
## 个人存档：金魂币、魂力等级、魂环、魂技、暗器和升级、道具、魂骨、章节进度。
## 存在自己电脑上（user://profile.json）。联机时每个人用自己的存档，房主的存档决定当前章节。

signal changed

var path := "user://profile.json"   # 自动测试会换成别的文件，不碰玩家的存档
const VERSION := 3          # 3：没有清单任务了（旧存档的任务进度清零），100 级，魂技槽，配件

var money := 0
var xp := 0
var level := 1
var weapons: Array = ["xiujian"]
var upgrades := {}          # 暗器 id -> {"dmg": 0, "mag": 0, "reload": 0, "stab": 0}
var items := {"grenade": 2, "pill": 1}
var rings: Array = []       # [{"age": int, "skill": String, "beast": String}]
var bones: Array = []        # 拥有的魂骨 "id@年份"（包括装上的）
var equipped := {}           # 部位 -> "id@年份"
var bag := {}                # （旧版素材，已不用）
var food := 100.0            # 饱食度
var bait := "grass"          # 当前鱼饵
var bounties: Array = []     # 悬赏 [{"ch", "species", "age", "affix", "reward"}]
var skins: Array = ["default"]      # 拥有的暗器皮肤
var skin := "default"
var outfits: Array = ["default"]    # 拥有的装扮
var outfit := "default"
var codex := {}                     # 猎魂录：魂兽 -> {"k": 杀了几只, "s": 星星（位：1 杀 5 只 / 2 带词缀 / 4 千年或精英）}
var skill_slots: Array = [-1, -1, -1]   # Q / E / F 三个魂技槽装的是第几个魂环的魂技（-1 空）
var attach_owned := {}              # 暗器 -> [买过的配件]
var attach_on := {}                 # 暗器 -> {部位: 配件}
var stats := {}                     # 成就用的计数
var achieved := {}                  # 已完成的成就 id -> true
var god := false                    # 成神了（通关）
var max_chapter := 1                # 去过的最远一章（渡船能回以前的岛）
var rebirth := 0                    # 转生了几次（成神以后可以转生，换武魂从头再来，永久变强，魂兽也更凶）
var boss_tier := {}                 # 每个 Boss 打赢了几次：再召唤就是"二重、三重"，血更厚、奖励更高
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
	bones = bones.filter(func(b): return Data.BONES.has(Data.bone_id(str(b))))
	equipped = d.get("equipped", {})
	for s in equipped.keys():
		if not str(equipped[s]) in bones:
			equipped.erase(s)
	if equipped.is_empty():
		for b in bones:
			var slot := str(Data.bone_data(str(b)).get("slot", ""))
			if slot != "" and not equipped.has(slot):
				equipped[slot] = str(b)
	bag = d.get("bag", {})
	food = clampf(float(d.get("food", 100.0)), 0.0, 100.0)
	bait = str(d.get("bait", "grass"))
	if not Data.BAITS.has(bait):
		bait = "grass"
	bounties = d.get("bounties", [])
	skins = (d.get("skins", ["default"]) as Array).filter(func(s): return Data.GUN_SKINS.has(str(s)))
	outfits = (d.get("outfits", ["default"]) as Array).filter(func(s): return Data.OUTFITS.has(str(s)))
	if not "default" in skins:
		skins.append("default")
	if not "default" in outfits:
		outfits.append("default")
	codex = d.get("codex", {})
	skill_slots = d.get("skill_slots", [-1, -1, -1])
	while skill_slots.size() < 3:
		skill_slots.append(-1)
	attach_owned = d.get("attach_owned", {})
	attach_on = d.get("attach_on", {})
	stats = d.get("stats", {})
	achieved = d.get("achieved", {})
	god = bool(d.get("god", false))
	rebirth = int(d.get("rebirth", 0))
	boss_tier = d.get("boss_tier", {})
	skin = str(d.get("skin", "default"))
	outfit = str(d.get("outfit", "default"))
	if not skin in skins:
		skin = "default"
	if not outfit in outfits:
		outfit = "default"
	chapter = int(d.get("chapter", 1))
	max_chapter = maxi(int(d.get("max_chapter", chapter)), chapter)
	quest = int(d.get("quest", 0))
	quest_count = int(d.get("quest_count", 0))
	if int(d.get("version", 1)) < 3:
		# 旧存档：任务表换了，任务进度从头算（修炼到 X 级的任务，等级够了会马上完成）
		quest = 0
		quest_count = 0
		for i in rings.size():
			if i < 3 and int(skill_slots[i]) < 0:
				skill_slots[i] = i
	kills = int(d.get("kills", 0))
	loadout = d.get("loadout", weapons.duplicate())
	# 旧存档里可能有已经删掉的暗器
	weapons = weapons.filter(func(w): return Data.WEAPONS.has(w) and w != "fist")
	_fix_loadout()
	if not Data.CHAPTERS.has(chapter):
		chapter = 1
		quest = 0


func save_profile() -> void:
	_dirty = false
	_save_t = 0.0
	var d := {
		"version": VERSION, "money": money, "xp": xp, "level": level, "weapons": weapons,
		"upgrades": upgrades, "items": items, "rings": rings, "bones": bones, "equipped": equipped, "bag": bag, "food": food, "bait": bait, "bounties": bounties, "skins": skins, "skin": skin, "outfits": outfits, "outfit": outfit, "codex": codex,
		"skill_slots": skill_slots, "attach_owned": attach_owned, "attach_on": attach_on, "stats": stats, "achieved": achieved, "god": god, "max_chapter": max_chapter, "rebirth": rebirth, "boss_tier": boss_tier,
		"chapter": chapter, "quest": quest, "quest_count": quest_count, "kills": kills, "loadout": loadout,
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d, "  "))


func mark_dirty() -> void:
	_dirty = true
	changed.emit()


## 三个存档位：1 号是 user://profile.json（老存档就在这里），2、3 号是 profile_2 / profile_3
var slot := 1


static func slot_path(n: int) -> String:
	return "user://profile.json" if n <= 1 else "user://profile_%d.json" % n


func use_slot(n: int) -> void:
	if _dirty:
		save_profile()
	slot = clampi(n, 1, 3)
	path = slot_path(slot)
	_defaults()
	load_profile()
	changed.emit()


## 存档位的一行简介（菜单上显示）
func slot_summary(n: int) -> String:
	var p := slot_path(n)
	if not FileAccess.file_exists(p):
		return "空存档"
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	if typeof(d) != TYPE_DICTIONARY:
		return "空存档"
	var ch := int(d.get("chapter", 1))
	var nm: String = str(Data.CHAPTERS[ch]["name"]).split(" · ")[-1] if Data.CHAPTERS.has(ch) else ""
	return "%d 级 · %s · %d 环" % [int(d.get("level", 1)), nm, (d.get("rings", []) as Array).size()]


func reset() -> void:
	_defaults()
	save_profile()
	changed.emit()


## 转生：成神以后从 1 级、第一章重新来（可以换武魂，魂技全新），
## 留下：外观、成就、猎魂录、配件、一成金魂币；每转一次：自己伤害 / 体力 +25%，魂兽血量 / 伤害 +30%
func rebirth_power() -> float:
	return 1.0 + 0.25 * rebirth


func rebirth_hard() -> float:
	return 1.0 + 0.3 * rebirth


func do_rebirth() -> bool:
	if not god:
		return false
	var keep := {"skins": skins, "skin": skin, "outfits": outfits, "outfit": outfit, "achieved": achieved, "stats": stats,
		"codex": codex, "attach_owned": attach_owned, "money": money / 10, "rebirth": rebirth + 1}
	_defaults()
	for k in keep:
		set(k, keep[k])
	save_profile()
	changed.emit()
	return true


func _defaults() -> void:
	money = 0
	xp = 0
	level = 1
	weapons = ["xiujian"]
	upgrades = {}
	items = {"grenade": 2, "pill": 1}
	rings = []
	bones = []
	equipped = {}
	bag = {}
	food = 100.0
	bait = "grass"
	bounties = []
	skins = ["default"]
	skin = "default"
	outfits = ["default"]
	outfit = "default"
	codex = {}
	skill_slots = [-1, -1, -1]
	attach_owned = {}
	attach_on = {}
	stats = {}
	achieved = {}
	god = false
	max_chapter = 1
	rebirth = 0
	boss_tier = {}
	chapter = 1
	quest = 0
	quest_count = 0
	kills = 0
	loadout = ["xiujian"]


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


## 暗器是真的东西：买了才有；卖了、丢了、倒地掉了就没了，可以再买（升级和配件记在存档里，不会丢）
func buy_weapon(id: String) -> bool:
	if has_weapon(id) or not spend(int(Data.WEAPONS[id]["price"])):
		return false
	add_weapon(id)
	return true


func add_weapon(id: String) -> void:
	if id == "fist" or has_weapon(id):
		return
	weapons.append(id)
	_fix_loadout()
	mark_dirty()


func remove_weapon(id: String) -> void:
	weapons.erase(id)
	_fix_loadout()
	mark_dirty()


func sell_price(id: String) -> int:
	return int(Data.WEAPONS[id]["price"]) / 2


func sell_weapon(id: String) -> bool:
	if not has_weapon(id):
		return false
	remove_weapon(id)
	add_money(sell_price(id))
	count("sold")
	return true


# ------------------------------------------------------------------ 配件

func has_attach(w: String, a: String) -> bool:
	return a in (attach_owned.get(w, []) as Array)


func attach_of(w: String, slot: String) -> String:
	return str((attach_on.get(w, {}) as Dictionary).get(slot, ""))


func buy_attach(w: String, a: String) -> bool:
	if has_attach(w, a) or not spend(Data.attach_price(w, a)):
		return false
	var owned: Array = attach_owned.get(w, [])
	owned.append(a)
	attach_owned[w] = owned
	toggle_attach(w, a)
	return true


## 装上 / 卸下（同一个部位只能装一个）
func toggle_attach(w: String, a: String) -> void:
	if not has_attach(w, a):
		return
	var on: Dictionary = attach_on.get(w, {})
	var slot := str(Data.ATTACH[a]["slot"])
	if str(on.get(slot, "")) == a:
		on.erase(slot)
	else:
		on[slot] = a
	attach_on[w] = on
	mark_dirty()


## 把第 ring 个魂环的魂技装到第 k 个键（Q/E/F）；已经装在别的键上就两个键互换
func set_skill_slot(k: int, ring: int) -> void:
	var old := int(skill_slots[k])
	for j in skill_slots.size():
		if j != k and int(skill_slots[j]) == ring:
			skill_slots[j] = old
	skill_slots[k] = ring
	mark_dirty()


# ------------------------------------------------------------------ 成就计数

func count(key: String, n := 1) -> int:
	stats[key] = int(stats.get(key, 0)) + n
	mark_dirty()
	return int(stats[key])


func stat(key: String) -> int:
	return int(stats.get(key, 0))


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
	d = Data.apply_attach(d, attach_on.get(id, {}))
	# 魂骨：爆头加成、伤害加成
	d["headshot"] = d["headshot"] * (1.0 + bone_bonus("headshot"))
	d["damage"] = d["damage"] * (1.0 + bone_bonus("dmg") + codex_stars() * 0.005)
	var rk := 1.0 / (1.0 + bone_bonus("reload"))
	d["reload"] = d["reload"] * rk
	d["reload_empty"] = d["reload_empty"] * rk
	d["recoil_mult"] = float(d.get("recoil_mult", 1.0)) * clampf(1.0 - bone_bonus("recoil"), 0.4, 1.0)
	return d


# ------------------------------------------------------------------ 道具

func item_count(id: String) -> int:
	return int(items.get(id, 0))


func buy_item(id: String) -> bool:
	var it: Dictionary = Data.ITEMS[id]
	if id == "lure_gold":
		# 引兽香：一包管 5 次咬钩
		if item_count("gold_bites") >= 15 or not spend(Data.item_price(id)):
			return false
		items["gold_bites"] = item_count("gold_bites") + 5
		mark_dirty()
		return true
	var n := int(it.get("bundle", 1))
	if item_count(id) + n > int(it["max"]) or not spend(Data.item_price(id)):
		return false
	items[id] = item_count(id) + n
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
	return Data.MAX_RINGS


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
		return "已经有 %d 个魂环了" % max_rings()
	if not at_bottleneck():
		return "要修炼到 %d 级瓶颈才能吸收魂环" % level_cap()
	var min_age: int = Data.RING_MIN_AGE[rings.size()]
	if age < min_age:
		return "第%d魂环至少要%s的魂兽" % [rings.size() + 1, Data.age_name(min_age)]
	return ""


func add_ring(age: int, skill: String, beast: String) -> void:
	rings.append({"age": age, "skill": skill, "beast": beast})
	# 魂技槽有空就自动装上
	for i in skill_slots.size():
		if int(skill_slots[i]) < 0:
			skill_slots[i] = rings.size() - 1
			break
	mark_dirty()


## 猎魂录一共几颗星（每颗：体力 +2、伤害 +0.5%）
func codex_stars() -> int:
	var n := 0
	for sp in codex:
		var s := int(codex[sp].get("s", 0))
		n += (s & 1) + ((s >> 1) & 1) + ((s >> 2) & 1)
	return n


func species_stars(sp: String) -> int:
	var s := int(codex.get(sp, {}).get("s", 0))
	return (s & 1) + ((s >> 1) & 1) + ((s >> 2) & 1)


## 打死一只：记进猎魂录，返回这次新点亮的星（0 = 没有）
func codex_kill(sp: String, age: int, has_affix: bool, elite: bool) -> int:
	var e: Dictionary = codex.get(sp, {"k": 0, "s": 0})
	e["k"] = int(e.get("k", 0)) + 1
	var s := int(e.get("s", 0))
	var before := s
	if int(e["k"]) >= Data.CODEX_KILLS:
		s |= 1
	if has_affix:
		s |= 2
	if age >= 2 or elite:
		s |= 4
	e["s"] = s
	codex[sp] = e
	mark_dirty()
	var gained := s & ~before
	return gained


func max_hp() -> float:
	return (100.0 + (level - 1) * 5.0 + bone_bonus("hp") * (1.0 + level * 0.02) + codex_stars() * 3.0) * rebirth_power()


func max_soul() -> float:
	return 60.0 + (level - 1) * 4.0 + bone_bonus("soul")


## 装上的魂骨加起来的某项属性
func bone_bonus(stat: String) -> float:
	var t := 0.0
	for s in equipped:
		t += Data.bone_stat(str(equipped[s]), stat)
	return t


func has_bone_id(id: String) -> bool:
	for b in bones:
		if Data.bone_id(str(b)) == id:
			return true
	return false


## 拿到一块魂骨。unique = true 时已经有同种的就不要（Boss 魂骨每人一块）。部位空着就自动装上
func add_bone(entry: String, unique := false) -> bool:
	if unique and has_bone_id(Data.bone_id(entry)):
		return false
	if Data.bone_data(entry).is_empty():
		return false
	bones.append(entry)
	var slot := str(Data.bone_data(entry)["slot"])
	if not equipped.has(slot):
		equipped[slot] = entry
	mark_dirty()
	return true


func is_equipped(entry: String) -> bool:
	return entry in equipped.values()


func equip_bone(entry: String) -> void:
	if not entry in bones:
		return
	equipped[str(Data.bone_data(entry)["slot"])] = entry
	mark_dirty()


func unequip_slot(slot: String) -> void:
	equipped.erase(slot)
	mark_dirty()


## 丢出去 / 卖掉：从背包里拿走一块（装着的也会卸下）
func remove_bone(entry: String) -> bool:
	var i := bones.find(entry)
	if i < 0:
		return false
	bones.remove_at(i)
	for s in equipped.keys():
		if equipped[s] == entry and not entry in bones:
			equipped.erase(s)
	mark_dirty()
	return true


func add_mat(key: String, n := 1) -> void:
	bag[key] = int(bag.get(key, 0)) + n
	mark_dirty()


func take_mat(key: String) -> bool:
	if int(bag.get(key, 0)) <= 0:
		return false
	bag[key] = int(bag[key]) - 1
	if int(bag[key]) <= 0:
		bag.erase(key)
	mark_dirty()
	return true


## 外观：kind = "skin"（暗器皮肤）或 "outfit"（装扮）
func owns_look(kind: String, id: String) -> bool:
	return id in (skins if kind == "skin" else outfits)


func buy_look(kind: String, id: String) -> bool:
	var d: Dictionary = (Data.GUN_SKINS if kind == "skin" else Data.OUTFITS).get(id, {})
	if d.is_empty() or owns_look(kind, id) or d.has("boss") or d.has("codex") or not spend(int(d["price"])):
		return false
	(skins if kind == "skin" else outfits).append(id)
	mark_dirty()
	return true


func unlock_look(kind: String, id: String) -> bool:
	if owns_look(kind, id):
		return false
	(skins if kind == "skin" else outfits).append(id)
	mark_dirty()
	return true


func wear(kind: String, id: String) -> void:
	if not owns_look(kind, id):
		return
	if kind == "skin":
		skin = id
	else:
		outfit = id
	mark_dirty()


func title() -> String:
	return "%d 级%s%s" % [level, Data.titles(level), ("（第%d世）" % (rebirth + 1)) if rebirth > 0 else ""]
