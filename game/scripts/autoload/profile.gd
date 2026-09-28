extends Node
## 个人存档：灵石、灵力等级、灵环、神通、暗器和升级、道具、灵骨、章节进度。
## 存在自己电脑上（user://profile.json）。联机时每个人用自己的存档，房主的存档决定当前章节。

signal changed

var path := "user://profile.json"   # 自动测试会换成别的文件，不碰玩家的存档
const VERSION := 4          # 3：没有清单任务了（旧存档的任务进度清零），100 级，神通槽，配件；4：第十一版每章前面多了"通关秘境、修炼到 N 级"两个任务

var money := 0
var xp := 0
var level := 1
var weapons: Array = ["xiujian"]
var upgrades := {}          # 暗器 id -> {"dmg": 0, "mag": 0, "reload": 0, "stab": 0}
var items := {"grenade": 2, "pill": 1}
var rings: Array = []       # [{"age": int, "skill": String, "beast": String}]
var bones: Array = []        # 拥有的灵骨 "id@年份"（包括装上的）
var equipped := {}           # 部位 -> "id@年份"
var bag := {}                # （旧版素材，已不用）
var food := 100.0            # 饱食度
var bait := "grass"          # 当前鱼饵
var bounties: Array = []     # 悬赏 [{"ch", "species", "age", "affix", "reward"}]
var skins: Array = ["default"]      # 拥有的暗器皮肤（买的、Boss、猎灵录；熟练度皮肤和自己画的不在这里）
var skin := "default"               # 没单独设过的暗器穿这个
var skin_of := {}                   # 暗器 -> 皮肤（第十二版：每把暗器可以穿不同的皮肤）
var charms: Array = []              # 买过的挂件
var charm_of := {}                  # 暗器 -> 挂件
var mastery := {}                   # 暗器 -> 熟练度经验
var paint := {}                     # 暗器 -> {"finish": 颜料质感}（图存在 user://paint/）
var outfits: Array = ["default"]    # 拥有的装扮
var outfit := "default"
var codex := {}                     # 猎灵录：灵兽 -> {"k": 杀了几只, "s": 星星（位：1 杀 5 只 / 2 带词缀 / 4 千年或精英）}
var skill_slots: Array = [-1, -1, -1]   # Q / E / F 三个神通槽装的是第几个灵环的神通（-1 空）
var ring_hole := -1                  # 用散魂丹散掉的灵环位置（下一个吸收的补在这里），-1 = 没有
var attach_owned := {}              # 暗器 -> [买过的配件]
var attach_on := {}                 # 暗器 -> {部位: 配件}
var stats := {}                     # 成就用的计数
var achieved := {}                  # 已完成的成就 id -> true
var god := false                    # 飞升了（通关）
var max_chapter := 1                # 去过的最远一章（渡船能回以前的岛）
var rebirth := 0                    # 转生了几次（飞升以后可以转生，换灵相从头再来，永久变强，灵兽也更凶）
var boss_tier := {}                 # 每个 Boss 打赢了几次：再召唤就是"二重、三重"，血更厚、奖励更高
var materials := {}                 # 王魄：灵兽 -> 个数（打灵兽王掉，给暗器附魔用）
var enchant := {}                   # 暗器 -> 附魔 id（Data.ENCHANTS）
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
	# 烤肉去掉了：旧存档里的烤肉按收购价折成灵石
	if int(items.get("meat", 0)) > 0:
		money += int(items["meat"]) * int(Data.SELL_ITEMS.get("meat", 12))
	items.erase("meat")
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
	ring_hole = int(d.get("ring_hole", -1))
	if ring_hole > rings.size():
		ring_hole = -1
	attach_owned = d.get("attach_owned", {})
	attach_on = d.get("attach_on", {})
	stats = d.get("stats", {})
	achieved = d.get("achieved", {})
	god = bool(d.get("god", false))
	rebirth = int(d.get("rebirth", 0))
	boss_tier = d.get("boss_tier", {})
	materials = d.get("materials", {})
	enchant = d.get("enchant", {})
	skin = str(d.get("skin", "default"))
	outfit = str(d.get("outfit", "default"))
	if not skin in skins:
		skin = "default"
	if not outfit in outfits:
		outfit = "default"
	skin_of = d.get("skin_of", {})
	charms = (d.get("charms", []) as Array).filter(func(s): return Data.CHARMS.has(str(s)))
	charm_of = d.get("charm_of", {})
	mastery = d.get("mastery", {})
	paint = d.get("paint", {})
	chapter = int(d.get("chapter", 1))
	max_chapter = maxi(int(d.get("max_chapter", chapter)), chapter)
	quest = int(d.get("quest", 0))
	quest_count = int(d.get("quest_count", 0))
	var ver := int(d.get("version", 1))
	if ver < 3:
		# 旧存档：任务表换了，任务进度从头算（修炼到 X 级的任务，等级够了会马上完成）
		quest = 0
		quest_count = 0
		for i in rings.size():
			if i < 3 and int(skill_slots[i]) < 0:
				skill_slots[i] = i
	elif ver == 3:
		# 第十一版：每章的任务从 [猎王, 祭坛, Boss, 坐船] 变成 [秘境, 修炼到 N 级, 祭坛, Boss, 坐船]，
		# 已经过了第一个任务的往后挪一格（不然会卡在"击败 Boss"而祭坛又召唤不了）
		if quest >= 1:
			quest += 1
		else:
			quest_count = 0
	kills = int(d.get("kills", 0))
	loadout = d.get("loadout", weapons.duplicate())
	if ver <= 3:
		# 第十一版以前倒下会把手里的暗器丢掉（谁捡到归谁），玩家的存档因此暗器全没了、只能空手打。
		# 买过、升级过的暗器都还回来
		for w in upgrades:
			if Data.WEAPONS.has(str(w)) and str(w) != "fist" and not str(w) in weapons:
				weapons.append(str(w))
				loadout.append(str(w))
	if weapons.is_empty():
		weapons = ["xiujian"]
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
		"skin_of": skin_of, "charms": charms, "charm_of": charm_of, "mastery": mastery, "paint": paint,
		"skill_slots": skill_slots, "ring_hole": ring_hole, "attach_owned": attach_owned, "attach_on": attach_on, "stats": stats, "achieved": achieved, "god": god, "max_chapter": max_chapter, "rebirth": rebirth, "boss_tier": boss_tier, "materials": materials, "enchant": enchant,
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
	var st: Dictionary = d.get("stats", {}) if typeof(d.get("stats", {})) == TYPE_DICTIONARY else {}
	return "%d 级 · %s · %d 环 · 玩了 %s" % [int(d.get("level", 1)), nm, (d.get("rings", []) as Array).size(), play_time_text(float(st.get("play_s", 0.0)))]


## 这个存档玩了多久（"3 小时 12 分" / "25 分钟"）
static func play_time_text(sec: float) -> String:
	var m := int(sec / 60.0)
	if m < 60:
		return "%d 分钟" % m
	return "%d 小时 %d 分" % [m / 60, m % 60]


## 在游戏里（不算菜单）每 10 秒记一次时长
var _play_acc := 0.0


func add_play_time(dt: float) -> void:
	_play_acc += dt
	if _play_acc >= 10.0:
		stats["play_s"] = float(stats.get("play_s", 0.0)) + _play_acc
		_play_acc = 0.0
		mark_dirty()


func reset() -> void:
	_defaults()
	save_profile()
	changed.emit()


## 转生：飞升以后从 1 级、第一章重新来（可以换灵相，神通全新），
## 留下：外观、成就、猎灵录、配件、一成灵石；每转一次：自己伤害 / 体力 +25%，灵兽血量 / 伤害 +30%
func rebirth_power() -> float:
	return 1.0 + 0.25 * rebirth


func rebirth_hard() -> float:
	return 1.0 + 0.3 * rebirth


func do_rebirth() -> bool:
	if not god:
		return false
	var keep := {"skins": skins, "skin": skin, "outfits": outfits, "outfit": outfit, "achieved": achieved, "stats": stats,
		"codex": codex, "attach_owned": attach_owned, "money": money / 10, "rebirth": rebirth + 1,
		"skin_of": skin_of, "charms": charms, "charm_of": charm_of, "mastery": mastery, "paint": paint}
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
	skin_of = {}
	charms = []
	charm_of = {}
	mastery = {}
	paint = {}
	codex = {}
	skill_slots = [-1, -1, -1]
	ring_hole = -1
	attach_owned = {}
	attach_on = {}
	stats = {}
	achieved = {}
	god = false
	max_chapter = 1
	rebirth = 0
	boss_tier = {}
	materials = {}
	enchant = {}
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


# ------------------------------------------------------------------ 灵石

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


## 把第 ring 个灵环的神通装到第 k 个键（Q/E/F）；已经装在别的键上就两个键互换
func set_skill_slot(k: int, ring: int) -> void:
	var old := int(skill_slots[k])
	for j in skill_slots.size():
		if j != k and int(skill_slots[j]) == ring:
			skill_slots[j] = old
	skill_slots[k] = ring
	mark_dirty()


# ------------------------------------------------------------------ 王魄和附魔

func add_material(species: String, n := 1) -> void:
	materials[species] = int(materials.get(species, 0)) + n
	mark_dirty()


## 这个附魔能用的王魄一共有几个
func enchant_mats(eid: String) -> int:
	var t := 0
	for sp in Data.ENCHANTS[eid]["mats"]:
		t += int(materials.get(sp, 0))
	return t


func can_enchant(eid: String) -> bool:
	var e: Dictionary = Data.ENCHANTS[eid]
	return enchant_mats(eid) >= int(e["n"]) and money >= int(e["price"])


## 给暗器附魔（换附魔也一样，旧的直接替换掉）
func do_enchant(weapon: String, eid: String) -> bool:
	if not can_enchant(eid):
		return false
	var e: Dictionary = Data.ENCHANTS[eid]
	var need := int(e["n"])
	for sp in e["mats"]:
		var have := int(materials.get(sp, 0))
		var use := mini(have, need)
		if use > 0:
			materials[sp] = have - use
			need -= use
		if need <= 0:
			break
	spend(int(e["price"]))
	enchant[weapon] = eid
	mark_dirty()
	return true


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
	# 灵骨：爆头加成、伤害加成
	d["headshot"] = d["headshot"] * (1.0 + bone_bonus("headshot"))
	d["damage"] = d["damage"] * (1.0 + bone_bonus("dmg") + codex_stars() * 0.005)
	var rk := 1.0 / (1.0 + bone_bonus("reload"))
	d["reload"] = d["reload"] * rk
	d["reload_empty"] = d["reload_empty"] * rk
	d["recoil_mult"] = float(d.get("recoil_mult", 1.0)) * clampf(1.0 - bone_bonus("recoil"), 0.4, 1.0)
	# 熟练度：一点点手感（换弹、开镜、伤害、后坐）
	var ml := mastery_level(id)
	if ml > 0:
		var mr := 1.0 - Data.mastery_bonus(ml, "reload")
		d["reload"] = d["reload"] * mr
		d["reload_empty"] = d["reload_empty"] * mr
		d["ads_time"] = float(d["ads_time"]) * (1.0 - Data.mastery_bonus(ml, "ads"))
		var mk := 1.0 + Data.mastery_bonus(ml, "dmg")
		d["damage"] = d["damage"] * mk
		if d.has("splash_dmg"):
			d["splash_dmg"] = float(d["splash_dmg"]) * mk
		d["recoil_mult"] = float(d["recoil_mult"]) * (1.0 - Data.mastery_bonus(ml, "recoil"))
	return d


# ------------------------------------------------------------------ 熟练度

func mastery_xp(w: String) -> int:
	return int(mastery.get(w, 0))


func mastery_level(w: String) -> int:
	return Data.mastery_level(mastery_xp(w))


## 加熟练度，返回升到的新等级（没升级返回 -1）
func add_mastery(w: String, n: int) -> int:
	if not Data.WEAPONS.has(w) or w == "fist" or n <= 0:
		return -1
	var before := mastery_level(w)
	mastery[w] = mastery_xp(w) + n
	mark_dirty()
	var after := mastery_level(w)
	return after if after > before else -1


# ------------------------------------------------------------------ 每把暗器的皮肤、挂件

## 这把暗器现在穿的皮肤
func skin_for(w: String) -> String:
	var s := str(skin_of.get(w, skin))
	return s if owns_skin(w, s) else ("default" if not owns_skin(w, skin) else skin)


## 这把暗器能不能穿这款皮肤：买的 / Boss / 猎灵录是所有暗器通用；熟练度皮肤看这把的熟练度；自己画的要先画
func owns_skin(w: String, id: String) -> bool:
	var d: Dictionary = Data.GUN_SKINS.get(id, {})
	if d.is_empty():
		return false
	if d.has("mastery"):
		return mastery_level(w) >= int(d["mastery"])
	if bool(d.get("paint", false)):
		return GunSkin.has_paint(w)
	return id in skins


## 给一把暗器穿皮肤；w 空 = 所有暗器（能穿的都换上，其余不动）
func wear_skin(w: String, id: String) -> void:
	if w == "":
		if id in skins:
			skin = id
			skin_of.clear()
	elif owns_skin(w, id):
		skin_of[w] = id
	mark_dirty()


func charm_for(w: String) -> String:
	var c := str(charm_of.get(w, ""))
	return c if c in charms else ""


func buy_charm(id: String) -> bool:
	if id in charms or not Data.CHARMS.has(id) or not spend(int(Data.CHARMS[id]["price"])):
		return false
	charms.append(id)
	mark_dirty()
	return true


## 挂上 / 摘下（同一个再点一次就摘下）
func set_charm(w: String, id: String) -> void:
	if charm_for(w) == id or id == "":
		charm_of.erase(w)
	elif id in charms:
		charm_of[w] = id
	mark_dirty()


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


# ------------------------------------------------------------------ 等级与灵环

func level_cap() -> int:
	# 每 10 级要一个灵环才能突破
	return mini((rings.size() + 1) * 10, Data.MAX_LEVEL)


func max_rings() -> int:
	return Data.MAX_RINGS


## 卡在瓶颈：到了下一个灵环要求的等级，还没吸收那个灵环
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


## 下一个吸收的灵环是第几个（从 0 数）：用散魂丹散掉过的，先补那个位置
func next_ring_index() -> int:
	return ring_hole if ring_hole >= 0 and ring_hole <= rings.size() else rings.size()


func can_absorb(age: int) -> String:
	## 返回空字符串表示可以；否则返回原因
	if rings.size() >= max_rings():
		return "已经有 %d 个灵环了" % max_rings()
	if not at_bottleneck():
		return "要修炼到 %d 级瓶颈才能吸收灵环" % level_cap()
	var ni := next_ring_index()
	var min_age: int = Data.RING_MIN_AGE[ni]
	if age < min_age:
		return "第%d灵环至少要%s的灵兽" % [ni + 1, Data.age_name(min_age)]
	return ""


func add_ring(age: int, skill: String, beast: String) -> void:
	var at := next_ring_index()
	rings.insert(at, {"age": age, "skill": skill, "beast": beast})
	ring_hole = -1
	# 神通槽记的是第几个灵环：插在中间的，后面的往后挪一格
	for i in skill_slots.size():
		if int(skill_slots[i]) >= at:
			skill_slots[i] = int(skill_slots[i]) + 1
	# 神通槽有空就自动装上
	for i in skill_slots.size():
		if int(skill_slots[i]) < 0:
			skill_slots[i] = at
			break
	mark_dirty()


## 散魂丹：散掉第 i 个灵环（神通跟着没了），下一个吸收的灵环补在这个位置。一次只能空一个
func remove_ring(i: int) -> String:
	if i < 0 or i >= rings.size():
		return "没有这个灵环"
	if ring_hole >= 0:
		return "先把上次散掉的第%s灵环补上" % Data.RING_NAMES[ring_hole]
	if not use_item("scatter_pill"):
		return "要一颗散魂丹（暗器铺 → 道具）"
	rings.remove_at(i)
	ring_hole = i
	for k in skill_slots.size():
		var s := int(skill_slots[k])
		if s == i:
			skill_slots[k] = -1
		elif s > i:
			skill_slots[k] = s - 1
	mark_dirty()
	return ""


## 猎灵录一共几颗星（每颗：体力 +2、伤害 +0.5%）
func codex_stars() -> int:
	var n := 0
	for sp in codex:
		var s := int(codex[sp].get("s", 0))
		n += (s & 1) + ((s >> 1) & 1) + ((s >> 2) & 1)
	return n


func species_stars(sp: String) -> int:
	var s := int(codex.get(sp, {}).get("s", 0))
	return (s & 1) + ((s >> 1) & 1) + ((s >> 2) & 1)


## 打死一只：记进猎灵录，返回这次新点亮的星（0 = 没有）
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
	return (100.0 + (level - 1) * 7.0 + bone_bonus("hp") * (1.0 + level * 0.02) + codex_stars() * 3.0) * rebirth_power()


## 自己最强的一把暗器的输出（x = 一发，y = 每秒），灵兽血量下限按它算（Data.hp_floor）
func output() -> Vector2:
	var best := Vector2.ZERO
	for id in weapons:
		if not Data.WEAPONS.has(str(id)):
			continue
		var d := weapon_stats(str(id))
		var o := Data.weapon_output(d) * Data.level_damage(level) * rebirth_power()
		if o.y > best.y:
			best = o
	return best


func max_soul() -> float:
	return 60.0 + (level - 1) * 4.0 + bone_bonus("soul")


## 装上的灵骨加起来的某项属性
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


## 拿到一块灵骨。unique = true 时已经有同种的就不要（Boss 灵骨每人一块）。部位空着就自动装上
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
