class_name HuntTrip
extends Node
## 猎场里的一次猎灵（第十二版补丁：用户说猎灵"没有抓 Boss 的感觉、地图太小、没有探索感和成就感"）。
##
## 在猎灵榜上挑了灵兽 → 全队去这一章的猎场（Island 的 hunting 模式，640 米见方，外圈是山）：
##   · 猎物在几片区域之间走，要跟着爪痕、脚印、吼声找（Hunt 里）；重伤了跑回很远的巢穴睡觉，偷袭伤害 ×2.5；
##     两成血以下"虚弱"，用引魂索捆住就能活捉（奖励更多）
##   · 地图里藏着 14 处宝藏（山顶、水边、山脊……，远远能看到一道金光），每个人自己找自己的
##   · 各处有成群的灵兽（有人走近才刷出来，一半凶的会扑上来），打光了过几分钟再来
##   · 别的灵兽的地盘里有灵兽王守着大宝箱（地图上标"王"），打倒它才能开（每人一份）
##   · 限时 25 分钟；全队倒下回营地一共 3 次就失败
##   · 打死 / 活捉以后结算：用时、倒下次数、击杀还是活捉 → 评级 S/A/B/C → 报酬；记最快纪录。
##     两分半后自动回岛，按 L 马上回（以前是营地旗子按 F，用户说 F 和神通冲突回不去）
##
## 联机：房主管时间、倒下次数、结算、灵兽群和守宝的王，每秒发 htst；倒下 htfaint，结算 htdone，失败 htfail，
## 守宝的王倒下 htguard，客人想回岛 htback，回岛 huntback。

const LIMIT := 1500.0
const MAX_FAINTS := 3
const RETURN_AFTER := 150.0
const FAIL_RETURN := 14.0
const RATING_K := {"S": 1.6, "A": 1.3, "B": 1.0, "C": 0.8}
const RATING_COL := {"S": Color(1.0, 0.82, 0.3), "A": Color(0.55, 0.9, 1.0), "B": Color(0.7, 0.95, 0.6), "C": Color(0.8, 0.8, 0.85)}
# 灵兽群：有人走到 PACK_NEAR 以内（又不在眼前 PACK_MIN）才刷；打光了 PACK_AGAIN 秒后再来；同时最多 PACK_CAP 只
const PACK_NEAR := 110.0
const PACK_MIN := 35.0
const PACK_AGAIN := 200.0
const PACK_CAP := 22
# 守宝的灵兽王：走近 GUARD_NEAR 才刷；血量比猎物薄（单人 GUARD_HP，每多一人 + GUARD_HP_PER）
const GUARD_NEAR := 140.0
const GUARD_HP := 0.4
const GUARD_HP_PER := 0.3
const TREASURE_SEE := 150.0     # 小宝藏的金光多远看得到

var world: World
var info := {}                  # {"species", "age", "seed", "by"}
var t := 0.0
var faints := 0
var phase := "hunt"             # hunt / done / fail
var result := {}
var back_t := 0.0
var guard_dead: Array = []      # 每个守宝点的王倒下了没有（房主同步）
var wilds_on := not Data.autotest   # 自动测试时不刷灵兽群（测试里单独打开）
var _sync_t := 0.0
var _found := {}                # 宝藏序号 -> true（自己的）
var _nodes: Array = []          # 宝藏的模型
var _gfound := {}               # 开过的大宝箱（自己的）
var _gnodes: Array = []         # 大宝箱的模型
var _flag := Vector3.ZERO
var _ret_confirm := 0.0         # 地上还有灵环时，按两次 L 才回岛
# 房主
var _packs: Array = []          # {"pos", "sp", "ids", "cd", "killed"}
var _guard_ids: Array = []      # 每个守宝点刷出来的王（0 = 还没刷）
var _pack_t := 0.0
# 界面
var _top: Label
var _panel: PanelContainer
var _panel_t := 0.0


func _ready() -> void:
	_flag = world.island.spawn + Vector3(6.0, 0.0, 0.0)
	_flag.y = world.island.height_at(_flag.x, _flag.z)
	for i in world.island.guard_spots.size():
		guard_dead.append(false)
		_guard_ids.append(0)
	_build_treasures()
	_build_chests()
	_build_ui()
	if Net.is_host():
		_host_setup_packs()
	# 以前这里写了三行规则（爪痕、脚印、活捉、限时、倒下几次、宝藏、守宝王），用户说游戏描述得太详细：只留标题和限时
	var om: Dictionary = Hunt.OMENS.get(str(info.get("omen", "")), {})
	var sub := "限时 %d 分钟" % int(LIMIT / 60.0)
	if not om.is_empty():
		sub = "本周天象 · %s · %s" % [str(om["name"]), sub]
		# 天色：血月是夜里、风雨是暴雨大雾、金鳞是金色的黄昏
		if str(om["env"]) != "":
			world._event_env(str(om["env"]), 99999.0)
	world.hud._show_banner("猎杀%s%s" % ["历战" if bool(info.get("tempered", false)) else "", species_name()], sub, Color(1.0, 0.62, 0.25), 4.0)


func species_name() -> String:
	var sp := str(info.get("species", ""))
	return "%s%s王" % [Data.age_name(int(info.get("age", 0))), Data.BEASTS[sp]["name"]] if Data.BEASTS.has(sp) else "灵兽王"


func _process(dt: float) -> void:
	if phase == "hunt":
		t += dt
		if Net.is_host() and t >= LIMIT:
			host_fail("时间到了，猎物跑掉了")
	else:
		back_t = maxf(back_t - dt, 0.0)
		if Net.is_host() and back_t <= 0.0 and not Data.autotest:
			host_return()
	_ret_confirm = maxf(_ret_confirm - dt, 0.0)
	if Net.is_host():
		_host_wilds(dt)
		_sync_t -= dt
		if _sync_t <= 0.0:
			_sync_t = 1.0
			Net.send(0, "htst", [t, faints, phase, back_t, guard_dead])
	_update_treasures()
	_update_ui(dt)


# ------------------------------------------------------------------ 倒下、结算、回岛（房主）

## 自己倒下回了营地（被队友救起来不算）
func on_my_faint() -> void:
	if phase != "hunt":
		return
	if Net.is_host():
		host_faint(Net.my_id)
	else:
		Net.send_host("htfaint", [])


func host_faint(peer: int) -> void:
	if phase != "hunt":
		return
	faints += 1
	var m := ["%s 倒下回营地了（%d / %d）" % [world.peer_name(peer), faints, MAX_FAINTS]]
	Net.send(0, "feedall", m)
	world.hud.feed(str(m[0]), Color(1.0, 0.5, 0.4))
	if faints >= MAX_FAINTS:
		host_fail("全队倒下 %d 次，猎灵失败" % MAX_FAINTS)


## 猎物死了 / 被活捉了：算评级和报酬，发给大家
func host_finish(captured: bool) -> void:
	if phase != "hunt":
		return
	var sp := str(info.get("species", "rabbit"))
	var age := int(info.get("age", 0))
	var rating := "C"
	if faints == 0 and t < 480.0:
		rating = "S"
	elif faints <= 1 and t < 840.0:
		rating = "A"
	elif faints <= 1:
		rating = "B"
	var tempered := bool(info.get("tempered", false))
	var omen := str(info.get("omen", ""))
	var k: float = float(RATING_K[rating]) * (1.5 if captured else 1.0) * (1.5 if tempered else 1.0) * (Hunt.OMEN_REWARD if omen != "" else 1.0)
	var money := roundi(Data.kill_money(sp, age) * 10.0 * k)
	var xp := roundi(Data.kill_xp(sp, age) * 8.0 * k)
	# 活捉没有"打死"那一下的奖励，补上
	if captured:
		money += roundi(Data.kill_money(sp, age) * Data.ELITE_REWARD)
		xp += roundi(Data.xp_to_next(int(Data.CH_REF_LEVEL.get(world.chapter, 10))) * Data.KING_XP_LEVELS)
	var r := {"captured": captured, "time": t, "faints": faints, "rating": rating, "money": money, "xp": xp, "species": sp, "age": age, "tempered": tempered, "omen": omen, "week": int(info.get("week", 0))}
	Net.send(0, "htdone", [r])
	_on_done(r)


func host_fail(reason: String) -> void:
	if phase != "hunt":
		return
	var m := [reason]
	Net.send(0, "htfail", m)
	_on_fail(m)


func host_return() -> void:
	back_t = 9999.0
	Net.send(0, "huntback", [world.chapter])
	world.travel_back()


## 客人想回岛：告诉房主（房主按 L 一起回），不然到时间自动回
func request_return() -> void:
	if Net.is_host():
		host_return()
	else:
		Net.send_host("htback", [])
		world.hud.toast("已经告诉房主——房主按 L 就一起回岛（%s 后也会自动回）" % _fmt(back_t), Color(0.9, 0.9, 0.9), 3.0)


## L 键：猎完了（或失败了）马上回岛。F 是神通键，以前只能在营地旗子按 F 回，用户找不到、按了放神通
func key_return() -> void:
	if phase == "hunt":
		world.hud.toast("还在猎灵：猎完了按 L 回岛（要放弃就回营地旗子按 F）", Color(1.0, 0.8, 0.5), 3.0)
		return
	if phase == "done" and not world.rings.is_empty() and _ret_confirm <= 0.0:
		_ret_confirm = 4.0
		world.hud.toast("地上还有灵环没吸收——4 秒内再按一次 L 就回岛", Color(1.0, 0.8, 0.5), 4.0)
		return
	_ret_confirm = 0.0
	request_return()


# ------------------------------------------------------------------ 消息

func on_message(from: int, type: String, data: Variant) -> void:
	match type:
		"htst":
			if not Net.is_host():
				var d: Array = data
				t = float(d[0])
				faints = int(d[1])
				phase = str(d[2])
				back_t = float(d[3])
				if d.size() > 4:
					var gd: Array = d[4]
					for i in mini(gd.size(), guard_dead.size()):
						if bool(gd[i]) and not guard_dead[i]:
							_on_guard_down(i, false)
		"htfaint":
			if Net.is_host():
				host_faint(from)
		"htdone":
			_on_done((data as Array)[0])
		"htfail":
			_on_fail(data)
		"htguard":
			_on_guard_down(int((data as Array)[0]), true)
		"htback":
			if Net.is_host():
				var m := "%s 想回岛了——按 L 一起回岛" % world.peer_name(from)
				world.hud.toast(m, Color(1.0, 0.85, 0.5), 4.0)
				world.hud.feed(m, Color(1.0, 0.85, 0.5))


func _on_done(r: Dictionary) -> void:
	if phase == "done":
		return
	phase = "done"
	result = r
	back_t = RETURN_AFTER
	world.lock_music("victory", 40.0)
	world.earn(int(r["money"]))
	world._gain(0, int(r["xp"]))
	Profile.count("hunts")
	if bool(r["captured"]):
		Profile.count("captures")
		# 灵宠：活捉的灵兽王驯成灵宠（没带灵宠的话马上带上）
		var psp := str(r["species"])
		if Data.BEASTS.has(psp):
			var first := not Profile.pets.has(psp)
			Profile.pets[psp] = maxi(int(Profile.pets.get(psp, 0)), int(r["age"]))
			if Profile.pet == "":
				Profile.pet = psp
				world.refresh_pet()
				world._broadcast_prog()
			Profile.mark_dirty()
			if first:
				world.hud.toast("%s驯成了灵宠" % str(Data.BEASTS[psp]["name"]), Color(0.6, 0.9, 1.0), 4.0)
	# 灵核（装备树第五品要）：每人自己掷，连着没掉有保底
	var sp := str(r["species"])
	var tempered := bool(r.get("tempered", false))
	# 猎过一次这种灵兽，猎灵榜上就有它的历战王
	Profile.stats["hunted_" + sp] = int(Profile.stats.get("hunted_" + sp, 0)) + 1
	if Data.BEASTS.has(sp) and Gear.roll_core(sp, bool(r["captured"]), 3.0 if tempered or str(r.get("omen", "")) == "gold" else 1.0):
		world.hud.feed("+ %s灵核" % str(Data.BEASTS[sp]["name"]), UiKit.GOLD)
		Sfx.play("rare", -2.0)
	var key := "hunt_best_%s_%d%s" % [str(r["species"]), int(r["age"]), "_t" if tempered else ""]
	var best := int(Profile.stats.get(key, 0))
	var new_best := best == 0 or int(r["time"]) < best
	if new_best:
		Profile.stats[key] = int(r["time"])
		Profile.mark_dirty()
	r["best"] = int(Profile.stats[key])
	r["new_best"] = new_best
	# 每周天象：本周最快（猎灵榜上那只的卡片显示）
	if str(r.get("omen", "")) != "":
		var wk := "omen_best_%d_%d" % [int(r.get("week", 0)), world.chapter]
		if int(Profile.stats.get(wk, 0)) == 0 or int(r["time"]) < int(Profile.stats[wk]):
			Profile.stats[wk] = int(r["time"])
			Profile.mark_dirty()
	Sfx.play("quest_done", 0.0)
	_show_panel(true, r, "")


func _on_fail(d: Array) -> void:
	if phase != "hunt":
		return
	phase = "fail"
	back_t = FAIL_RETURN
	Sfx.play("death", -4.0)
	_show_panel(false, {}, str(d[0]))


# ------------------------------------------------------------------ 灵兽群、守宝的灵兽王（房主）

## 在各片区域、山头、山脊、水塘边定好灵兽群的位置（人走近了才刷出来，省性能）
func _host_setup_packs() -> void:
	var isl := world.island
	var rng := RandomNumberGenerator.new()
	rng.seed = int(info.get("seed", 1)) + 77
	var land_sp: Array = world._map_species().filter(func(s): return not isl.is_water_habitat(str(Data.BEASTS[s]["habitat"])))
	if land_sp.is_empty():
		return
	var camp := Vector2(isl.spawn.x, isl.spawn.z)
	var nest := Vector2(isl.nest.x, isl.nest.z)
	var spots: Array = []
	for h in isl.habitats:
		# 巢穴那边安安静静的（猎物回去睡觉，好偷袭）
		if str(h.get("role", "")) == "nest":
			continue
		for k in 2:
			spots.append((h["center"] as Vector2) + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(10.0, float(h["radius"]) + 6.0))
	for hl in isl.hills:
		spots.append((hl[0] as Vector2) + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(10.0, 20.0))
	for g in isl.ridges:
		spots.append((g[0] as Vector2).lerp(g[1], 0.25))
		spots.append((g[0] as Vector2).lerp(g[1], 0.8))
	for pd in isl.ponds:
		spots.append((pd["center"] as Vector2) + Vector2.from_angle(rng.randf() * TAU) * (float(pd["radius"]) + 10.0))
	for q: Vector2 in spots:
		if not isl.is_land(q.x, q.y) or q.distance_to(camp) < 70.0 or q.distance_to(nest) < 45.0 or q.length() > isl.rim_r - 20.0:
			continue
		var sp := world._species_near(Vector3(q.x, 0, q.y), land_sp)
		_packs.append({"pos": isl.ground_point(q.x, q.y), "sp": sp, "ids": [], "cd": 0.0, "killed": 0})


func _host_wilds(dt: float) -> void:
	_pack_t -= dt
	if _pack_t > 0.0:
		return
	_pack_t = 1.0
	# 没倒地的人（刚复活无敌的、隐身的也算：走到哪儿哪儿就有灵兽）
	var pl: Array = world.all_players().filter(func(e): return e["alive"])
	var live := 0
	for pk in _packs:
		var ids: Array = pk["ids"]
		var had := not ids.is_empty()
		for id in ids.duplicate():
			if not world.beasts.has(id):
				ids.erase(id)
		if had and ids.is_empty():
			# 打光了：过一阵再来；只是人走远了被收掉的：下次走近马上刷
			pk["cd"] = PACK_AGAIN if int(pk["killed"]) > 0 else 0.0
			pk["killed"] = 0
		live += ids.size()
		pk["cd"] = maxf(float(pk["cd"]) - 1.0, 0.0)
	# 守宝的王：刷出来以后不见了（不该发生）就当没刷过
	for i in _guard_ids.size():
		if int(_guard_ids[i]) != 0 and not world.beasts.has(int(_guard_ids[i])) and not guard_dead[i]:
			_guard_ids[i] = 0
	if not wilds_on or pl.is_empty():
		return
	for pk in _packs:
		if live >= PACK_CAP:
			break
		if not (pk["ids"] as Array).is_empty() or float(pk["cd"]) > 0.0:
			continue
		var near := _nearest(pl, pk["pos"])
		if near <= PACK_NEAR and near >= PACK_MIN:
			live += host_spawn_pack(pk)
	for i in _guard_ids.size():
		if not guard_dead[i] and int(_guard_ids[i]) == 0 and _nearest(pl, world.island.guard_spots[i]["pos"]) < GUARD_NEAR:
			host_spawn_guard(i)


func _nearest(pl: Array, p: Vector3) -> float:
	var near := INF
	for e in pl:
		near = minf(near, (e["pos"] as Vector3).distance_to(p))
	return near


## 刷一群：2~4 只（联机多一两只），年份不超过猎物；凶的物种大多会扑上来
func host_spawn_pack(pk: Dictionary) -> int:
	var rng := world.rng
	var sp := str(pk["sp"])
	var n := rng.randi_range(2, 4) + mini(world.hunt._team_n() - 1, 2)
	var temper := "fierce" if rng.randf() < (0.75 if sp in Data.AGGRESSIVE else 0.3) else "flee"
	var base := int(Data.CH_AGE.get(world.chapter, 0))
	var top := int(info.get("age", base))
	var c: Vector3 = pk["pos"]
	var cnt := 0
	for k in n:
		var q := c + Vector3(rng.randf_range(-4.0, 4.0), 0, rng.randf_range(-4.0, 4.0))
		if not world.island.is_land(q.x, q.z):
			continue
		q.y = world.island.height_at(q.x, q.z) + 0.4
		var age := clampi(base - (1 if rng.randf() < 0.6 else 0), 0, top)
		var b := world._host_spawn_wild(q, sp, age, temper)
		if b:
			(pk["ids"] as Array).append(b.id)
			cnt += 1
	return cnt


func guard_species(i: int) -> String:
	return str(Data.HABITATS[str(world.island.guard_spots[i]["type"])]["beast"])


## 守宝的王年份：这一章的年份，不超过猎物
func guard_age() -> int:
	return clampi(int(Data.CH_AGE.get(world.chapter, 0)), 0, int(info.get("age", 0)))


func guard_name(i: int) -> String:
	return "%s%s王" % [Data.age_name(guard_age()), Data.BEASTS[guard_species(i)]["name"]]


func host_spawn_guard(i: int) -> Beast:
	var sp := guard_species(i)
	var age := guard_age()
	var pos: Vector3 = world.island.guard_spots[i]["pos"] + Vector3(0, 0.8, 0)
	var id := world.next_beast_id
	world.next_beast_id += 1
	var affixes: Array = [] if Data.autotest else Data.roll_affixes(world.rng, age, world.chapter, "grass", true).slice(0, 1)
	var b := world._spawn_beast(id, sp, age, pos, Vector3.ZERO, 1, false, "elite", affixes)
	Net.send(0, "bsp", [id, sp, age, pos, Vector3.ZERO, 1, "elite", affixes])
	b.max_hp *= GUARD_HP + GUARD_HP_PER * float(world.hunt._team_n() - 1)
	b.hp = b.max_hp
	b.hunt_role = "guard"
	b.spawn_pos = pos
	_guard_ids[i] = id
	return b


## World._host_kill 调：记灵兽群打死了几只；守宝的王倒下 → 大宝箱能开了
func host_on_kill(b: Beast) -> void:
	for pk in _packs:
		if b.id in (pk["ids"] as Array):
			pk["killed"] = int(pk["killed"]) + 1
			return
	for i in _guard_ids.size():
		if int(_guard_ids[i]) == b.id and not guard_dead[i]:
			Net.send(0, "htguard", [i])
			_on_guard_down(i, true)
			return


func _on_guard_down(i: int, tell: bool) -> void:
	if i < 0 or i >= guard_dead.size() or guard_dead[i]:
		return
	guard_dead[i] = true
	var n: Node3D = _gnodes[i]
	var beam := n.get_node_or_null("Beam") as MeshInstance3D
	if beam and not _gfound.has(i):
		(beam.material_override as ShaderMaterial).set_shader_parameter("color", Color(1.0, 0.82, 0.35))
	if tell:
		var m := "守宝的%s倒下了——「%s」的大宝箱能开了（每人一份）" % [guard_name(i), world.island.zone_name(n.global_position)]
		world.hud.feed(m, UiKit.GOLD)
		if n.global_position.distance_to(world.player.global_position) < 120.0:
			world.hud.toast(m, UiKit.GOLD, 3.5)


# ------------------------------------------------------------------ 宝藏（每个人自己找）

func _beam(n: Node3D, col: Color, h: float, r: float, hdr: float) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Beam"
	mi.mesh = U.cyl(r, r, h, 12)
	mi.material_override = FxLib.smat("pillar", {"color": col, "hdr": hdr, "half_h": h * 0.5, "top": 0.25, "rim_k": 0.7, "speed": 0.35})
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, h * 0.5 + 0.3, 0)
	n.add_child(mi)


func _build_treasures() -> void:
	var gold := U.mat(Color(0.95, 0.72, 0.3), 0.3, 0.0, 0.85)
	var wood := U.mat(Color(0.4, 0.25, 0.13), 0.7)
	for i in world.island.treasures.size():
		var p: Vector3 = world.island.treasures[i]
		var n := Node3D.new()
		world.add_child(n)
		n.global_position = p
		U.part(n, U.box(Vector3(0.9, 0.55, 0.6)), wood, Vector3(0, 0.28, 0))
		U.part(n, U.box(Vector3(0.95, 0.1, 0.65)), gold, Vector3(0, 0.58, 0))
		var gl := U.part(n, U.sphere(0.22, 10, 8), U.glow(Color(1.0, 0.85, 0.4), 3.5), Vector3(0, 0.95, 0), Vector3.ZERO, Vector3.ONE, false)
		gl.name = "Glow"
		var l := OmniLight3D.new()
		l.name = "Light"
		l.light_color = Color(1.0, 0.8, 0.4)
		l.light_energy = 1.2
		l.omni_range = 6.0
		l.position = Vector3(0, 1.0, 0)
		n.add_child(l)
		# 远远能看到一道淡淡的金光（用户：大地图里要有东西可找）
		_beam(n, Color(1.0, 0.78, 0.3), 22.0, 0.35, 0.8)
		n.visible = false
		_nodes.append(n)


## 灵兽王守着的大宝箱：大一号、红光（王倒下了变金光），一直看得到
func _build_chests() -> void:
	var gold := U.mat(Color(0.95, 0.72, 0.3), 0.3, 0.0, 0.85)
	var wood := U.mat(Color(0.28, 0.12, 0.08), 0.6)
	for i in world.island.guard_spots.size():
		var p: Vector3 = world.island.guard_spots[i]["pos"]
		var n := Node3D.new()
		world.add_child(n)
		n.global_position = p
		U.part(n, U.box(Vector3(1.6, 0.9, 1.0)), wood, Vector3(0, 0.45, 0))
		U.part(n, U.cyl(0.52, 0.52, 1.6, 12), wood, Vector3(0, 0.9, 0), Vector3(0, 0, PI * 0.5), Vector3(1.0, 1.0, 1.0))
		for x in [-0.6, 0.0, 0.6]:
			U.part(n, U.box(Vector3(0.1, 1.5, 1.08)), gold, Vector3(x, 0.72, 0))
		U.part(n, U.box(Vector3(0.24, 0.3, 0.1)), gold, Vector3(0, 0.75, 0.55))
		var l := OmniLight3D.new()
		l.name = "Light"
		l.light_color = Color(1.0, 0.6, 0.3)
		l.light_energy = 1.6
		l.omni_range = 9.0
		l.position = Vector3(0, 1.6, 0)
		n.add_child(l)
		_beam(n, Color(1.0, 0.35, 0.2), 40.0, 0.6, 1.1)
		_gnodes.append(n)


func _update_treasures() -> void:
	var me := world.player.global_position
	for i in _nodes.size():
		var n: Node3D = _nodes[i]
		var d := n.global_position.distance_to(me)
		n.visible = d < TREASURE_SEE
		var g := n.get_node_or_null("Glow") as Node3D
		if g and not _found.has(i) and d < 60.0:
			g.position.y = 0.95 + sin(Time.get_ticks_msec() / 400.0 + i) * 0.12
	for i in _gnodes.size():
		var n2: Node3D = _gnodes[i]
		n2.visible = n2.global_position.distance_to(me) < 420.0


func found_list() -> Array:
	var out: Array = []
	for i in _found:
		out.append(world.island.treasures[i])
	return out


## 地图 / 罗盘上的守宝点：[位置, 字, 颜色, 说明]
func guard_marks() -> Array:
	var out: Array = []
	for i in world.island.guard_spots.size():
		var p: Vector3 = world.island.guard_spots[i]["pos"]
		if not guard_dead[i]:
			# 用"守"不用"王"：罗盘上的"王"留给锁定了的猎物
			out.append([p, "守", Color(1.0, 0.55, 0.15), "守宝 · %s" % guard_name(i)])
		elif not _gfound.has(i):
			out.append([p, "箱", Color(1.0, 0.85, 0.35), "大宝箱（能开了）"])
	return out


func interactables() -> Array:
	var out: Array = []
	var me := world.player.global_position
	for i in _nodes.size():
		if _found.has(i):
			continue
		var p: Vector3 = world.island.treasures[i]
		if p.distance_to(me) < 3.5:
			out.append({"id": "htreasure", "idx": i, "pos": p + Vector3(0, 1.0, 0), "r": 3.2, "text": "按 F 打开宝藏", "act": true})
	for i in _gnodes.size():
		if _gfound.has(i):
			continue
		var p2: Vector3 = world.island.guard_spots[i]["pos"]
		if p2.distance_to(me) < 4.0:
			if guard_dead[i]:
				out.append({"id": "htchest", "idx": i, "pos": p2 + Vector3(0, 1.0, 0), "r": 3.6, "text": "按 F 打开灵兽王的宝箱", "act": true})
			else:
				# 锁着的时候 F 照样放神通（act = false）
				out.append({"id": "htchest", "idx": i, "pos": p2 + Vector3(0, 1.0, 0), "r": 3.6, "text": "%s守着这个宝箱——打倒它才能开" % guard_name(i), "act": false})
	var txt := "按 F 放弃猎灵，回岛" if phase == "hunt" else "按 F 回岛（随时可以按 L）"
	out.append({"id": "htflag", "pos": _flag + Vector3(0, 1.2, 0), "r": 3.2, "text": txt, "act": true})
	return out


func interact(it: Dictionary) -> void:
	match str(it["id"]):
		"htreasure":
			_open_treasure(int(it["idx"]))
		"htchest":
			if guard_dead[int(it["idx"])]:
				_open_chest(int(it["idx"]))
		"htflag":
			if phase == "hunt" and not Net.is_host():
				world.hud.toast("只有房主能放弃猎灵", Color(0.9, 0.9, 0.9))
				return
			if phase == "hunt":
				host_fail("放弃了这次猎灵")
			else:
				request_return()


func _open_treasure(i: int) -> void:
	if _found.has(i):
		return
	_found[i] = true
	var n: Node3D = _nodes[i]
	for c in ["Glow", "Light", "Beam"]:
		var q := n.get_node_or_null(c)
		if q:
			q.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var ch := world.chapter
	var money := roundi(float(Data.CH_MONEY.get(ch, 12.0)) * rng.randf_range(6.0, 12.0))
	world.earn(money)
	var got: Array = ["%d 灵石" % money]
	var r := rng.randf()
	if r < 0.35:
		_give_item("pill", got)
	elif r < 0.55:
		_give_item("grenade", got)
	elif r < 0.7:
		Profile.items["bait_soul"] = Profile.item_count("bait_soul") + 5
		got.append("灵晶饵 ×5")
	elif r < 0.78:
		# 稀有：一块这一章年份的灵骨
		_give_bone(rng, got)
	Profile.count("treasures")
	Profile.mark_dirty()
	world.fx.aura_burst(n.global_position + Vector3(0, 0.6, 0), Color(1.0, 0.85, 0.4), 2.0)
	Sfx.play("coin", -2.0)
	Sfx.play("rare", -6.0, 0.0, 1.2)
	world.hud.toast("宝藏：%s（%d / %d）" % ["、".join(got), _found.size(), _nodes.size()], Color(1.0, 0.85, 0.4), 4.0)


## 大宝箱：一大笔灵石、回血丹 + 雷莲，一半多的机会有灵骨
func _open_chest(i: int) -> void:
	if _gfound.has(i):
		return
	_gfound[i] = true
	var n: Node3D = _gnodes[i]
	for c in ["Light", "Beam"]:
		var q := n.get_node_or_null(c)
		if q:
			q.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var money := roundi(float(Data.CH_MONEY.get(world.chapter, 12.0)) * rng.randf_range(28.0, 40.0))
	world.earn(money)
	var got: Array = ["%d 灵石" % money]
	_give_item("pill", got)
	_give_item("grenade", got)
	if rng.randf() < 0.6:
		_give_bone(rng, got)
	Profile.count("treasures")
	Profile.mark_dirty()
	world.fx.aura_burst(n.global_position + Vector3(0, 0.8, 0), Color(1.0, 0.8, 0.35), 3.5)
	world.fx.ring_breakthrough(n.global_position, Color(1.0, 0.8, 0.35), 0)
	Sfx.play("coin", 0.0)
	Sfx.play("rare", -3.0, 0.0, 1.0)
	world.hud._show_banner("灵兽王的宝箱", "、".join(got), UiKit.GOLD, 4.0)


func _give_item(id: String, got: Array) -> void:
	Profile.items[id] = mini(Profile.item_count(id) + 1, int(Data.ITEMS[id]["max"]))
	got.append(str(Data.ITEMS[id]["name"]))


func _give_bone(rng: RandomNumberGenerator, got: Array) -> void:
	var ids: Array = Data.BONES.keys().filter(func(b): return Data.BONES[b].has("beast"))
	if ids.is_empty():
		return
	var entry := "%s@%d" % [str(ids[rng.randi() % ids.size()]), int(Data.CH_AGE.get(world.chapter, 0))]
	if Profile.add_bone(entry):
		got.append("灵骨【%s】" % Data.bone_name(entry))
		world.player.on_bones_changed()


# ------------------------------------------------------------------ 界面

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_top = UiKit.bold("", 17, Color(1.0, 0.85, 0.6), 4)
	_top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 以前在正上方（和灵兽王的大血条叠在一起）：挪到右上小地图和灵石下面，右对齐
	_top.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiKit.place(_top, Vector4(1, 0, 1, 0), Vector4(-420, 292, -18, 316))
	layer.add_child(_top)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiKit.glass_style(0.72, 28, 20))
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.place(_panel, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-300, -190, 300, 150))
	_panel.visible = false
	layer.add_child(_panel)


func _fmt(sec: float) -> String:
	var s := maxi(int(sec), 0)
	return "%d:%02d" % [s / 60, s % 60]


func _guards_left() -> String:
	if guard_dead.is_empty():
		return ""
	return " · 守宝王 %d/%d" % [guard_dead.count(true), guard_dead.size()]


func _update_ui(dt: float) -> void:
	var txt := ""
	var who := "按 L" if Net.is_host() else "房主按 L"
	match phase:
		"hunt":
			# 只写剩多少时间（倒下过才写倒下几次）；以前一行写了猎杀谁、剩余、倒下、宝藏、守宝王（用户：描述得太详细）
			txt = _fmt(LIMIT - t) + (("  ·  倒下 %d/%d" % [faints, MAX_FAINTS]) if faints > 0 else "")
		"done":
			txt = "%s 回岛" % who
		"fail":
			txt = "猎灵失败"
	_top.text = txt
	if _panel.visible:
		_panel_t -= dt
		if _panel_t <= 0.0:
			_panel.visible = false


func _show_panel(ok: bool, r: Dictionary, reason: String) -> void:
	for c in _panel.get_children():
		c.queue_free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(v)
	v.add_child(UiKit.kicker("猎场", Color(1.0, 0.62, 0.25), 15))
	if not ok:
		v.add_child(UiKit.title("猎灵失败", 44, UiKit.RED))
		v.add_child(UiKit.label(reason, 18, UiKit.MOON))
		v.add_child(UiKit.label("%d 秒后回岛" % int(FAIL_RETURN), 15, UiKit.MIST))
		_panel.visible = true
		_panel_t = FAIL_RETURN
		return
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 20)
	v.add_child(head)
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	hv.add_child(UiKit.title("活捉成功" if bool(r["captured"]) else "猎灵完成", 44, UiKit.GOLD))
	hv.add_child(UiKit.label(species_name(), 20, UiKit.MOON))
	var rt := str(r["rating"])
	var big := UiKit.num(rt, 96, RATING_COL.get(rt, UiKit.MOON), 6)
	head.add_child(big)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 28)
	g.add_theme_constant_override("v_separation", 4)
	v.add_child(g)
	var rows := [["用时", _fmt(float(r["time"])) + ("（新纪录！）" if bool(r.get("new_best", false)) else "（最快 %s）" % _fmt(float(r.get("best", 0))))],
		["倒下", "%d 次" % int(r["faints"])],
		["方式", "活捉（报酬 ×1.5）" if bool(r["captured"]) else "击杀"],
		["报酬", "+%d 灵石 · +%d 修为" % [int(r["money"]), int(r["xp"])]]]
	for row in rows:
		g.add_child(UiKit.label(str(row[0]), 16, UiKit.MIST))
		g.add_child(UiKit.bold(str(row[1]), 17, UiKit.MOON))
	v.add_child(UiKit.label("灵环掉在猎物倒下的地方，记得去吸收", 14, UiKit.MIST))
	v.add_child(UiKit.key_hint("L", ("回岛" if Net.is_host() else "房主按了就一起回岛") + "（%s 后自动回）" % _fmt(RETURN_AFTER), 16, UiKit.GOLD))
	_panel.visible = true
	_panel_t = 14.0
