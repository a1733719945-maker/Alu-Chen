class_name Hunt
extends Node
## 猎灵（第十一版）：野外不刷怪，只猎自己挑的灵兽。
##
## 猎灵榜（L）列出这座岛能猎的灵兽，每张卡写明它的灵环会给你哪个神通。
## 挑一只 → 房主让它在离大家远的地方出现，在栖息地之间游荡。**要自己找**（用户：以前"路太好找了，没有探索的感觉"）：
##   榜上只说它在哪一带出没；它走过的地方每隔十几米留一处爪痕（走近才看得见，35 米外看不到），
##   走过去按 F 查看：它往哪个方向去了、痕迹新不新。看过 3 处就"锁定"它 45 秒（罗盘上标准确位置）；
##   它隔半分钟吼一声，140 米内才听得到，只知道方向；30 米内直接看得到它。脚印只在 45 米内显示。
## 打倒它（王的大招、半血暴怒、引魂索捆魂）→ 掉灵环（卡瓶颈、年份够的每人一个）、王魄、灵骨、一大截修为。
## 吸收灵环（任何灵环都一样）：站着不动，能开枪。单人 10 秒、只来一小波；联机 25 秒，灵兽一波波冲吸收的人，队友护法。
## 吸收的人倒下 → 失败，灵环掉回原地。
##
## 联机：房主管猎物和护法，每秒发 "hst"；踪迹 hfp、吼声 hroar、护法结束 hchend、放弃 hchq、挑猎物 hreq、提示 hev。

const FP_COLOR := Color(0.35, 0.95, 1.0)
const PREY_COL := Color(1.0, 0.62, 0.25)
const DIRS := ["北", "东北", "东", "东南", "南", "西南", "西", "西北"]

var world: World
# 大家都有（房主算好发过来）
var target_id := 0
var target_species := ""
var target_age := 0
var region := ""                   # 猎物在哪一带出没（栖息地名字）
var clues: Array = []              # 痕迹 [[id, 位置, 往哪走 x, z], ...]（房主算好发过来）
var channel := {}                  # 正在吸收灵环：{"peer", "age", "species", "pos", "t", "dur"}
# 房主
var _sync_t := 0.0
var _wander_t := 0.0
var _roar_t := 25.0
var _fp_last := Vector3.ZERO
var _wave_t := 0.0
var _waves_left := 0
var _wave_ids: Array = []
var _clue_id := 1
var _clue_last := Vector3.INF
var hold := false                  # 自动截图用：房主逻辑暂停
var weak := false                  # 猎物虚弱了（两成血以下，能活捉）
var _blood_last := Vector3.INF
var _cap_id := 0                   # 正在活捉的猎物
var _cap_t := 0.0
var _weak_told := false
# 自己
var _prints: Array = []
var _ch_node: Node3D
var _quit_sent := false
var _found_id := 0                 # 已经"发现"过的猎物（走进 30 米弹一次横幅）
var _clue_nodes := {}              # 痕迹 id -> {"node", "pos", "dir", "t", "read"}
var _clue_target := 0              # 痕迹是哪一只猎物的（换猎物就清掉）
var _track := 0                    # 看过几处痕迹（3 处锁定）
var _lock_t := 0.0                 # 锁定还剩几秒：罗盘上标准确位置
var _last_read := ""               # 最近一处痕迹说了什么
# 界面
var _box: VBoxContainer
var _t_card: PanelContainer
var _t_arrow: Control
var _t_name: Label
var _t_clue: Label
var _t_hp: ProgressBar
var _c_card: PanelContainer
var _c_name: Label
var _c_bar: ProgressBar
var _c_time: Label


func _ready() -> void:
	_build_ui()
	# 猎场：过一会儿猎物出现在它的老窝（离营地很远）
	if world.island.hunting and Net.is_host():
		get_tree().create_timer(1.5).timeout.connect(host_spawn_trip_target)


## 猎场里的一些距离：地图大，踪迹间隔大、看得远、吼声传得远
func _gap() -> float:
	return 24.0 if world.island.hunting else 16.0


func _see() -> float:
	return 60.0 if world.island.hunting else 35.0


func _process(dt: float) -> void:
	if Net.is_host() and not hold:
		_host(dt)
	elif not channel.is_empty():
		channel["t"] = minf(float(channel["t"]) + dt, float(channel["dur"]))
	_local(dt)


# ------------------------------------------------------------------ 猎灵榜（界面在 Hud.open_board）

## 这座岛能猎哪些灵兽：陆地上的和天上飞的（水里的不行，找不到踪迹）
func species_list() -> Array:
	var out: Array = []
	for sp in world._map_species():
		if not world.island.is_water_habitat(str(Data.BEASTS[sp]["habitat"])):
			out.append(sp)
	return out


## 默认的猎物年份：够自己下一个灵环用，最少是这一章的年份
func base_age() -> int:
	var need := int(Data.RING_MIN_AGE[mini(Profile.next_ring_index(), Data.MAX_RINGS - 1)])
	return clampi(maxi(int(Data.CH_AGE.get(world.chapter, 0)), need), 0, 4)


## 自己吸收这只灵兽的灵环会领悟哪个神通（和吸收时算的是同一个）
func skill_preview(species: String, age: int) -> String:
	var owned: Array = []
	for r in Profile.rings:
		owned.append(str(r["skill"]))
	return Data.skill_for(Data.wuhun_id(Settings.wuhun), species, age, owned)


func request(species: String, age: int) -> void:
	Net.send_host("hreq", [species, age])


# ------------------------------------------------------------------ 房主

func _host(dt: float) -> void:
	_host_target(dt)
	_host_channel(dt)
	_sync_t -= dt
	if _sync_t <= 0.0:
		_sync()


func _sync() -> void:
	_sync_t = 1.0
	var ch: Array = []
	if not channel.is_empty():
		ch = [int(channel["peer"]), int(channel["age"]), str(channel["species"]), channel["pos"], float(channel["t"]), float(channel["dur"])]
	Net.send(0, "hst", [target_id, target_species, target_age, ch, region, clues, weak])


func _team_n() -> int:
	return maxi(world._all_peers().size(), 1)


func _land_species() -> Array:
	return world._map_species().filter(func(s): return not world.island.is_water_habitat(str(Data.BEASTS[s]["habitat"])))


func _spawn_dist(p: Vector3) -> float:
	return Vector2(p.x - world.island.spawn.x, p.z - world.island.spawn.z).length()


## 离所有人都远、离码头也远的一块陆地（猎物从这里出来）
func _far_point(min_d: float) -> Vector3:
	var best := Vector3.ZERO
	var bs := -INF
	var pl := world.all_players()
	for h in world.island.habitats:
		var type := str(h["type"])
		if not Data.HABITATS.has(type) or world.island.is_water_habitat(type):
			continue
		var c: Vector2 = h["center"]
		for k in 3:
			var p := Vector3(c.x + randf_range(-10, 10), 0, c.y + randf_range(-10, 10))
			if not world.island.is_land(p.x, p.z) or world.island.slope_at(p.x, p.z) > 0.8:
				continue
			var md := INF
			for q in pl:
				var qp: Vector3 = q["pos"]
				md = minf(md, Vector2(p.x - qp.x, p.z - qp.z).length())
			var s := minf(md, min_d * 1.6) + randf() * 20.0 + minf(_spawn_dist(p), 80.0) * 0.3
			if s > bs:
				bs = s
				best = p
	if bs == -INF:
		best = world.island.spawn + Vector3(40, 0, -40)
	best.y = world.island.height_at(best.x, best.z) + 0.6
	return best


## 猎物换地方：去另一片栖息地附近（猎场：别的区域，不去巢穴，更喜欢自己的地盘）
func _wander_point(from: Vector3) -> Vector3:
	var cands: Array = []
	var hunting := world.island.hunting
	var own := str(Data.BEASTS.get(target_species, {"habitat": ""})["habitat"])
	for h in world.island.habitats:
		var type := str(h["type"])
		if not Data.HABITATS.has(type) or world.island.is_water_habitat(type):
			continue
		if hunting and str(h.get("role", "")) == "nest":
			continue
		var c: Vector2 = h["center"]
		var p := Vector3(c.x, 0, c.y)
		var d := Vector2(p.x - from.x, p.z - from.z).length()
		if d < 25.0 or d > (360.0 if hunting else 140.0) or _spawn_dist(p) < (70.0 if hunting else 40.0):
			continue
		cands.append(p)
		if hunting and type == own:
			cands.append(p)
	var p2: Vector3 = from + Vector3(randf_range(-40, 40), 0, randf_range(-40, 40))
	if not cands.is_empty():
		p2 = (cands[randi() % cands.size()] as Vector3) + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))
	if not world.island.is_land(p2.x, p2.z) or _spawn_dist(p2) < 35.0:
		p2 = from
	p2.y = world.island.height_at(p2.x, p2.z) + 0.6
	return p2


## 有人在猎灵榜上挑了一只：全队去这一章的猎场（第十二版补丁：以前是在岛上刷一只，岛太小、没有探索感）
func host_request(from: int, species: String, age: int) -> void:
	if not Data.BEASTS.has(species):
		return
	var why := ""
	if world.island.hunting:
		why = "已经在猎场里了：先把这只猎完（猎完按 L 回岛）"
	elif world.dungeon and world.dungeon.inside:
		why = "有人在秘境里，等出来再去猎场"
	elif world.boss:
		why = "Boss 还在，打完再去猎场"
	if why != "":
		if from == Net.my_id:
			world.hud.toast(why, Color(1.0, 0.8, 0.5), 3.5)
		else:
			Net.send(from, "hint", [why])
		return
	age = clampi(age, 0, 4)
	var info := {"species": species, "age": age, "seed": randi() % 2000000000 + 1, "by": from}
	var m := ["%s 挑了猎物：%s%s王——全队出发去猎场" % [world.peer_name(from), Data.age_name(age), Data.BEASTS[species]["name"]], 0]
	Net.send(0, "hev", m)
	_on_ev(m)
	await get_tree().create_timer(1.2).timeout
	if not is_instance_valid(world):
		return
	Net.send(0, "huntgo", [info])
	world.go_hunt(info)


## 猎场：猎物出现在它的老窝（离营地很远），重伤了逃回另一头的巢穴
func host_spawn_trip_target() -> void:
	var info: Dictionary = world.hunting
	var species := str(info.get("species", ""))
	if not Data.BEASTS.has(species):
		return
	var age := clampi(int(info.get("age", 0)), 0, 4)
	var pos := world.island.home + Vector3(0, 0.8, 0)
	var id := world.next_beast_id
	world.next_beast_id += 1
	var affixes: Array = [] if Data.autotest else Data.roll_affixes(world.rng, age, world.chapter, "grass", true).slice(0, 1)
	var b := world._spawn_beast(id, species, age, pos, Vector3.ZERO, 1, false, "elite", affixes)
	Net.send(0, "bsp", [id, species, age, pos, Vector3.ZERO, 1, "elite", affixes])
	# 猎场的猎物是这一趟的主菜：比岛上的灵兽王厚一点
	b.max_hp *= Data.HUNT_HP_SOLO + Data.HUNT_HP_PER * float(_team_n() - 1)
	b.hp = b.max_hp
	b.home_speed = 3.4
	b.hunt_role = "target"
	b.spawn_pos = pos
	b.nest_pos = world.island.nest + Vector3(0, 0.6, 0)
	target_id = id
	target_species = species
	target_age = age
	weak = false
	_weak_told = false
	region = world.island.zone_name(pos)
	_fp_last = pos
	_roar_t = 10.0
	_wander_t = 40.0
	# 它是从别处走过来的：来路上已经有两处爪痕
	clues.clear()
	var back := Vector3.RIGHT
	for tries in 16:
		var a0 := randf() * TAU
		back = Vector3(cos(a0), 0, sin(a0))
		var q1 := pos + back * 48.0
		var q2 := pos + back * 24.0
		if world.island.is_land(q1.x, q1.z) and world.island.is_land(q2.x, q2.z):
			break
	for k in [48.0, 24.0]:
		var q: Vector3 = pos + back * float(k)
		if world.island.is_land(q.x, q.z):
			_add_clue(q, -back)
	_clue_last = pos
	_add_clue(pos, -back)
	_sync()
	var m := ["猎物 %s 在「%s」一带出没——去那边找地上的爪痕（走近按 F 看）" % [b.display_name(), region], 0]
	Net.send(0, "hev", m)
	_on_ev(m)


func _host_target(dt: float) -> void:
	if target_id != 0 and not world.beasts.has(target_id):
		target_id = 0
		_sync()
	if target_id == 0:
		return
	var b: Beast = world.beasts[target_id]
	var fp := b.global_position
	# 爪痕：走出 16 米（猎场 24 米）留一处（带着它往哪走）
	if _clue_last == Vector3.INF or Vector2(fp.x - _clue_last.x, fp.z - _clue_last.z).length() > _gap():
		var mv := fp - (_clue_last if _clue_last != Vector3.INF else fp)
		_clue_last = fp
		if world.island.is_land(fp.x, fp.z):
			_add_clue(fp, mv)
			region = world.island.zone_name(fp) if world.island.hunting else region
			_sync()
	# 踪迹：它走过的地方留一对发光的脚印（飞的印在它下面的地上）
	if Vector2(fp.x - _fp_last.x, fp.z - _fp_last.z).length() > 3.2 and b.state != Beast.State.AIR:
		_fp_last = fp
		var m := [Vector3(fp.x, world.island.height_at(fp.x, fp.z), fp.z), b.global_basis.x]
		Net.send(0, "hfp", m)
		_on_fp(m)
	# 猎场：重伤了一路滴血（红色的血迹，老远就看得到），追着血迹找巢穴
	if world.island.hunting and b.hp < b.max_hp * 0.35:
		if _blood_last == Vector3.INF or Vector2(fp.x - _blood_last.x, fp.z - _blood_last.z).length() > 6.0:
			_blood_last = fp
			var bm := [Vector3(fp.x, world.island.height_at(fp.x, fp.z), fp.z)]
			Net.send(0, "hblood", bm)
			_on_blood(bm)
	# 虚弱：两成血以下，一瘸一拐，能活捉
	var w: bool = world.island.hunting and b.hp < b.max_hp * Data.HUNT_WEAK
	if w != weak:
		weak = w
		b.weak = w
		_sync()
		if w and not _weak_told:
			_weak_told = true
			var wm := ["%s 虚弱了！用引魂索（G）捆住它就能活捉——活捉报酬 ×1.5" % b.display_name(), 3]
			Net.send(0, "hev", wm)
			_on_ev(wm)
	# 活捉：捆住以后别打死它，捆满 2.5 秒就捉住了
	if _cap_id == b.id:
		if b.root_t > 0.0:
			_cap_t -= dt
			if _cap_t <= 0.0:
				_host_captured(b)
				return
		else:
			_cap_id = 0
			var cm := ["%s 挣脱了！" % b.display_name(), 1]
			Net.send(0, "hev", cm)
			_on_ev(cm)
	_roar_t -= dt
	if _roar_t <= 0.0:
		_roar_t = randf_range(22.0, 32.0)
		var r := [fp]
		Net.send(0, "hroar", r)
		_on_roar(r)
	# 没人在打它：隔一会儿换一片栖息地
	_wander_t -= dt
	if _wander_t <= 0.0 and b._aggro_t <= 0.0 and not b._retreat and not b.napping and world.nearest_player_pos(fp).distance_to(fp) > 30.0:
		_wander_t = randf_range(35.0, 55.0) if world.island.hunting else randf_range(25.0, 40.0)
		b.spawn_pos = _wander_point(fp)


## 房主：猎物虚弱时被引魂索捆住了（World.host_hook）
func host_capture_start(b: Beast) -> void:
	if not world.island.hunting or b.id != target_id or _cap_id == b.id:
		return
	_cap_id = b.id
	_cap_t = 2.5
	var m := ["正在活捉 %s……别打死它！" % b.display_name(), 3]
	Net.send(0, "hev", m)
	_on_ev(m)


func _host_captured(b: Beast) -> void:
	_cap_id = 0
	var pos := b.global_position
	# 灵环照样掉（活捉的灵兽献出灵环），再加两个王魄
	world._host_maybe_drop_ring(b, 0)
	var m := [b.species, pos]
	Net.send(0, "hcap", m)
	_on_captured(m)
	target_id = 0
	world.beast_escaped(b, "despawn")
	_sync()
	if world.trip:
		world.trip.host_finish(true)


func _on_captured(d: Array) -> void:
	var sp := str(d[0])
	var pos: Vector3 = d[1]
	world.fx.ring_breakthrough(pos, Color(0.45, 0.8, 1.0), 0)
	world.fx.chain_fx([pos + Vector3(0, 6, 0), pos, pos + Vector3(3, 0.5, 0), pos + Vector3(-3, 0.5, 0)], Color(0.45, 0.8, 1.0))
	Sfx.play_at("absorb", pos, 0.0)
	if world.player.global_position.distance_to(pos) < 120.0:
		Profile.add_material(sp, 2)
		world.hud.feed("活捉！获得 %s王魄 ×2（暗器铺 → 附魔）" % Data.BEASTS[sp]["name"], UiKit.GOLD)
	world.hud._show_banner("活捉成功", "灵环掉在它身边 · 王魄 ×2", Color(0.45, 0.8, 1.0), 3.0)


## 血迹：红色的光点，60 秒后淡掉，80 米内看得到
func _on_blood(d: Array) -> void:
	var pos: Vector3 = d[0]
	if pos.distance_to(world.player.global_position) > 80.0:
		return
	var n := world.fx._ground(pos + Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4)), "glow", Color(1.0, 0.12, 0.08), 0.8, 60.0, 30.0, 2.5)
	_prints.append(n)


## 猎物在哪一带：离它最近的栖息地的名字
func _region_name(p: Vector3) -> String:
	var best := "岛上"
	var bd := INF
	for h in world.island.habitats:
		var type := str(h["type"])
		if not Data.HABITATS.has(type):
			continue
		var d := Vector2(p.x, p.z).distance_to(h["center"])
		if d < bd:
			bd = d
			best = str(Data.HABITATS[type]["name"])
	return best


func _add_clue(p: Vector3, move: Vector3) -> void:
	move.y = 0.0
	if move.length() < 0.1:
		move = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	move = move.normalized()
	clues.append([_clue_id, Vector3(p.x, world.island.height_at(p.x, p.z), p.z), snappedf(move.x, 0.01), snappedf(move.z, 0.01)])
	_clue_id += 1
	while clues.size() > 10:
		clues.pop_front()
	_sync_clue_nodes()


## 房主：有灵兽死了（World._host_kill 调）
func host_on_kill(b: Beast) -> void:
	_wave_ids.erase(b.id)
	if b.id == target_id:
		target_id = 0
		_cap_id = 0
		var m := ["灵环掉在地上了——走过去按 F 吸收", 2]
		Net.send(0, "hev", m)
		_on_ev(m)
		_sync()
		if world.trip:
			world.trip.host_finish(false)


## 房主：有人要吸收灵环。站在灵环那里不动，时间到了才学会
func host_absorb(from: int, rid: int) -> void:
	if not world.rings.has(rid):
		return
	if not channel.is_empty():
		var tip := "%s 正在吸收灵环，等他吸收完再来" % world.peer_name(int(channel["peer"]))
		if from == Net.my_id:
			world.hud.toast(tip, Color(1.0, 0.8, 0.5), 3.0)
		else:
			Net.send(from, "hint", [tip])
		return
	var here := false
	for p in world.all_players():
		if int(p["peer"]) == from and bool(p["alive"]):
			here = true
	if not here:
		return
	var r: Dictionary = world.rings[rid]
	Net.send(0, "ringgone", [rid, from])
	world._on_ring_gone([rid, from])
	var solo := _team_n() == 1
	channel = {"peer": from, "age": int(r["age"]), "species": str(r["species"]), "pos": (r["pos"] as Vector3) - Vector3(0, 1.2, 0), "t": 0.0,
		"dur": Data.HUNT_CHANNEL_SOLO if solo else Data.HUNT_CHANNEL_TEAM}
	# 单人只来一小波；联机隔几秒来一波，队友护法
	_waves_left = 1 if solo else 99
	_wave_t = 2.0
	_on_channel_start()
	_sync()


func _host_channel(dt: float) -> void:
	if channel.is_empty():
		return
	var peer := int(channel["peer"])
	var alive := false
	for p in world.all_players():
		if int(p["peer"]) == peer and bool(p["alive"]):
			alive = true
	if not alive:
		_host_end_channel(false)
		return
	channel["t"] = float(channel["t"]) + dt
	if float(channel["t"]) >= float(channel["dur"]):
		_host_end_channel(true)
		return
	_wave_t -= dt
	if _wave_t <= 0.0 and _waves_left > 0:
		_wave_t = Data.HUNT_WAVE_GAP
		_waves_left -= 1
		_host_wave()


## 护法的一波：从同一个方向来几只凶的，只冲吸收灵环的人
func _host_wave() -> void:
	var pos: Vector3 = channel["pos"]
	var land_sp := _land_species()
	if land_sp.is_empty():
		return
	var n := 2 if _team_n() == 1 else 1 + _team_n()
	var age := clampi(int(channel["age"]) - 1, 0, 2)
	var a0 := randf() * TAU
	for i in n:
		for tries in 10:
			var a := a0 + randf_range(-0.7, 0.7)
			var r := randf_range(14.0, 28.0)
			var q := pos + Vector3(cos(a) * r, 0, sin(a) * r)
			if not world.island.is_land(q.x, q.z):
				continue
			q.y = world.island.height_at(q.x, q.z) + 0.4
			var b: Beast = world._host_spawn_wild(q, world._species_near(q, land_sp), age, "fierce")
			if b:
				b.focus_peer = int(channel["peer"])
				b.aggro_k = 2.0
				_wave_ids.append(b.id)
			break


func _host_end_channel(ok: bool) -> void:
	var c := channel
	channel = {}
	for id in _wave_ids:
		var b: Beast = world.beasts.get(id)
		if b:
			b.focus_peer = 0
	_wave_ids.clear()
	if not ok:
		world._host_drop_ring((c["pos"] as Vector3) + Vector3(0, 1.0, 0), int(c["age"]), str(c["species"]), 180.0)
	var msg := [int(c["peer"]), ok, int(c["age"]), str(c["species"]), c["pos"]]
	Net.send(0, "hchend", msg)
	_on_channel_end(msg)
	_sync()


## 自己死了：自己在吸收的话算失败
func on_my_death() -> void:
	world.player.channeling = false
	if Net.is_host() and not channel.is_empty() and int(channel["peer"]) == Net.my_id:
		_host_end_channel(false)


# ------------------------------------------------------------------ 消息

func on_message(from: int, type: String, data: Variant) -> void:
	match type:
		"hst":
			if not Net.is_host():
				_apply_state(data)
		"hfp":
			_on_fp(data)
		"hroar":
			_on_roar(data)
		"hchend":
			_on_channel_end(data)
		"hchq":
			if Net.is_host() and not channel.is_empty() and int(channel["peer"]) == from:
				_host_end_channel(false)
		"hreq":
			if Net.is_host():
				var d: Array = data
				host_request(from, str(d[0]), int(d[1]))
		"hev":
			_on_ev(data)
		"hblood":
			_on_blood(data)
		"hcap":
			_on_captured(data)


func _apply_state(d: Array) -> void:
	target_id = int(d[0])
	target_species = str(d[1])
	target_age = int(d[2])
	if d.size() > 5:
		region = str(d[4])
		clues = d[5]
		_sync_clue_nodes()
	if d.size() > 6:
		weak = bool(d[6])
	var ch: Array = d[3]
	if ch.is_empty():
		if not channel.is_empty():
			_channel_visual(false)
			if int(channel["peer"]) == Net.my_id:
				world.player.channeling = false
		channel = {}
		return
	var same := not channel.is_empty() and int(channel["peer"]) == int(ch[0])
	channel = {"peer": int(ch[0]), "age": int(ch[1]), "species": str(ch[2]), "pos": ch[3], "t": float(ch[4]), "dur": float(ch[5])}
	if not same:
		_on_channel_start()


func _on_fp(d: Array) -> void:
	var pos: Vector3 = d[0]
	if pos.distance_to(world.player.global_position) > (70.0 if world.island.hunting else 45.0):
		return
	var side: Vector3 = d[1]
	side.y = 0.0
	side = side.normalized() if side.length() > 0.01 else Vector3.RIGHT
	for s in [-1.0, 1.0]:
		var n := world.fx._ground(pos + side * 0.4 * s, "glow", FP_COLOR, 0.55, 50.0, 20.0, 2.5)
		_prints.append(n)
	while _prints.size() > 90:
		var o: Node = _prints.pop_front()
		if is_instance_valid(o):
			o.queue_free()


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _dir_name(pos: Vector3) -> String:
	var me := world.player.global_position
	var bearing := rad_to_deg(atan2(pos.x - me.x, -(pos.z - me.z)))
	return str(DIRS[posmod(roundi(bearing / 45.0), 8)])


func _on_roar(d: Array) -> void:
	var pos: Vector3 = d[0]
	var dist := _flat(pos, world.player.global_position)
	if world.dungeon and world.dungeon.inside:
		return
	# 离得太远听不到；听到了也只知道大概方向
	if dist > (240.0 if world.island.hunting else 140.0):
		return
	Sfx.play("boss_roar", clampf(-2.0 - dist * 0.08, -16.0, -2.0), 0.05, 0.8)
	if dist > Data.HUNT_REVEAL:
		world.hud.toast("%s边传来吼声" % _dir_name(pos), PREY_COL, 3.0)


func _on_ev(d: Array) -> void:
	var t := str(d[0])
	match int(d[1]):
		0:
			world.hud.toast(t, PREY_COL, 5.0)
			Sfx.play("rare", -4.0, 0.0, 0.8)
		2:
			world.hud._show_banner("猎物倒下", t, UiKit.GOLD, 4.0)
		3:
			world.hud.toast(t, Color(0.45, 0.8, 1.0), 4.5)
			Sfx.play("rare", -4.0, 0.0, 1.1)
		_:
			world.hud.feed(t, Color(0.85, 0.85, 0.9))


# ------------------------------------------------------------------ 吸收灵环

func _on_channel_start() -> void:
	var age := int(channel["age"])
	var col: Color = Data.AGES[age]["glow"]
	var pos: Vector3 = channel["pos"]
	_channel_visual(true)
	_quit_sent = false
	if int(channel["peer"]) == Net.my_id:
		var p: Player = world.player
		p.channeling = true
		p.busy_t = 0.0
		world.fx.absorb(p, col)
		var sub := "站着不能走，能开枪 · " + ("灵兽会一波波冲你来，队友护法" if _team_n() > 1 else "会来一小波灵兽")
		world.hud._show_banner("吸收%s灵环" % Data.age_name(age), sub, col, 3.0)
	else:
		world.hud.toast("%s 开始吸收%s灵环——去护法，别让灵兽碰到他" % [world.peer_name(int(channel["peer"])), Data.age_name(age)], col, 4.0)
	Sfx.play_at("absorb", pos, 0.0)


func _on_channel_end(msg: Array) -> void:
	var peer := int(msg[0])
	var ok := bool(msg[1])
	var age := int(msg[2])
	var sp := str(msg[3])
	var pos: Vector3 = msg[4]
	channel = {}
	_channel_visual(false)
	var col: Color = Data.AGES[age]["glow"]
	if peer == Net.my_id:
		world.player.channeling = false
		if ok:
			world._reveal_skill(age, sp)
		elif not world.player.dead:
			world.hud.toast("吸收被打断了——灵环掉回了原地，回去重新吸收", Color(1.0, 0.6, 0.45), 5.0)
	elif ok:
		world.fx._pillar(pos, col, 1.6, 40.0, 0.8)
		world.hud.feed("%s 吸收了%s灵环！" % [world.peer_name(peer), Data.age_name(age)], col)
	else:
		world.hud.feed("%s 的吸收被打断了，灵环掉回了地上" % world.peer_name(peer), Color(1.0, 0.6, 0.45))


## 吸收的人脚下两圈转着的灵环、一盏灯；别人看还有一道光柱（自己看会糊一脸，不加）
func _channel_visual(on: bool) -> void:
	if _ch_node and is_instance_valid(_ch_node):
		_ch_node.queue_free()
	_ch_node = null
	if not on or channel.is_empty():
		return
	var age := int(channel["age"])
	var col: Color = Data.AGES[age]["glow"]
	var pos: Vector3 = channel["pos"]
	_ch_node = Node3D.new()
	world.fx.add_child(_ch_node)
	_ch_node.global_position = pos
	var r1 := FxLib.soul_ring(col, col, 2.4, 2.4)
	r1.position.y = 0.12
	_ch_node.add_child(r1)
	var t1 := r1.create_tween().set_loops()
	t1.tween_property(r1, "rotation:y", TAU, 3.0).as_relative()
	var r2 := FxLib.soul_ring(col.lerp(Color.WHITE, 0.3), col, 1.5, 2.0)
	r2.position.y = 1.3
	_ch_node.add_child(r2)
	var t2 := r2.create_tween().set_loops()
	t2.tween_property(r2, "rotation:y", -TAU, 2.0).as_relative()
	if int(channel["peer"]) != Net.my_id:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.8
		cm.bottom_radius = 0.8
		cm.height = 30.0
		cm.cap_top = false
		cm.cap_bottom = false
		cm.radial_segments = 24
		var m := FxLib.smat("pillar", {"color": col, "hdr": 1.3, "half_h": 15.0, "speed": 0.9, "top": 0.5})
		U.part(_ch_node, cm, m, Vector3(0, 15.0, 0), Vector3.ZERO, Vector3.ONE, false)
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 2.5
	l.omni_range = 12.0
	l.position = Vector3(0, 2.0, 0)
	_ch_node.add_child(l)


# ------------------------------------------------------------------ 自己这边：每帧

func _local(dt: float) -> void:
	var p: Player = world.player
	var tb: Beast = world.beasts.get(target_id) if target_id != 0 else null
	if tb:
		tb.hunt_role = "target"
	_lock_t = maxf(_lock_t - dt, 0.0)
	# 换了猎物：痕迹、追踪进度清零
	if _clue_target != target_id:
		_clue_target = target_id
		_track = 0
		_lock_t = 0.0
		_last_read = ""
		_sync_clue_nodes()
	# 痕迹走近了才看得见
	for id in _clue_nodes:
		var c: Dictionary = _clue_nodes[id]
		var n: Node3D = c["node"]
		if is_instance_valid(n):
			n.visible = _flat(c["pos"], p.global_position) < _see()
	# 第一次走到猎物 30 米内：发现它了
	if tb and tb.alive() and _found_id != tb.id and not p.dead and _flat(tb.global_position, p.global_position) < Data.HUNT_REVEAL:
		_found_id = tb.id
		world.hud._show_banner("发现猎物", tb.display_name(), PREY_COL, 2.5)
		Sfx.play("boss_roar", -3.0, 0.0, 0.85)
		p.trauma = minf(p.trauma + 0.25, 1.0)
	# 吸收时被技能带离了原地：算放弃
	if not channel.is_empty() and int(channel["peer"]) == Net.my_id and not _quit_sent:
		if _flat(p.global_position, channel["pos"]) > 5.0:
			_quit_sent = true
			if Net.is_host():
				_host_end_channel(false)
			else:
				Net.send_host("hchq", [])
	_update_ui(tb)


## 看得到猎物在哪：锁定了、或者就在 30 米内
func located() -> bool:
	var tb: Beast = world.beasts.get(target_id) if target_id != 0 else null
	return tb != null and tb.alive() and (_lock_t > 0.0 or _flat(tb.global_position, world.player.global_position) < Data.HUNT_REVEAL)


# ------------------------------------------------------------------ 爪痕（自己看）

## 按房主发来的痕迹列表摆出 / 收掉地上的爪痕
func _sync_clue_nodes() -> void:
	var ids := {}
	for c in clues:
		ids[int(c[0])] = true
		if _clue_nodes.has(int(c[0])):
			continue
		var pos: Vector3 = c[1]
		var node := Node3D.new()
		world.fx.add_child(node)
		node.global_position = pos
		# 三道爪痕（月牙斩贴图）+ 一点暗暗的光点，35 米外看不到
		var d := world.fx._ground(pos + Vector3(0, 0.3, 0), "slash", Color(1.0, 0.72, 0.35), 2.2, -1.0, 0.0, 2.2)
		d.reparent(node)
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.9, 0.9)
		q.mesh = qm
		q.material_override = FxLib.bill_mat("glow", Color(1.0, 0.7, 0.35), 2.0)
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		q.position = Vector3(0, 0.5, 0)
		node.add_child(q)
		var tw := q.create_tween().set_loops()
		tw.tween_property(q, "scale", Vector3.ONE * 1.4, 0.9).set_trans(Tween.TRANS_SINE)
		tw.tween_property(q, "scale", Vector3.ONE * 0.7, 0.9).set_trans(Tween.TRANS_SINE)
		node.visible = false
		_clue_nodes[int(c[0])] = {"node": node, "pos": pos, "dir": Vector2(float(c[2]), float(c[3])), "t": Time.get_ticks_msec() / 1000.0, "read": false}
	for id in _clue_nodes.keys():
		if not ids.has(id) or target_id == 0:
			var n: Node = _clue_nodes[id]["node"]
			if is_instance_valid(n):
				n.queue_free()
			_clue_nodes.erase(id)


## 走到没看过的爪痕旁边：按 F 查看
func interactables() -> Array:
	var out: Array = []
	var me := world.player.global_position
	for id in _clue_nodes:
		var c: Dictionary = _clue_nodes[id]
		if not bool(c["read"]) and _flat(c["pos"], me) < 3.0:
			out.append({"id": "hclue", "cid": int(id), "pos": (c["pos"] as Vector3) + Vector3(0, 1.0, 0), "r": 3.2, "text": "按 F 查看痕迹", "act": true})
	return out


func read_clue(cid: int) -> void:
	if not _clue_nodes.has(cid):
		return
	var c: Dictionary = _clue_nodes[cid]
	if bool(c["read"]):
		return
	c["read"] = true
	var n: Node3D = c["node"]
	if is_instance_valid(n):
		for ch in n.get_children():
			if ch is MeshInstance3D:
				(ch as MeshInstance3D).visible = false
	var dir: Vector2 = c["dir"]
	var dname := str(DIRS[posmod(roundi(rad_to_deg(atan2(dir.x, -dir.y)) / 45.0), 8)])
	var age := Time.get_ticks_msec() / 1000.0 - float(c["t"])
	# 最新的一处（它刚走过）比旧的准
	var newest := true
	for o in clues:
		if int(o[0]) > cid:
			newest = false
	var fresh := "还很新，它刚过去" if newest or age < 40.0 else ("有一会儿了" if age < 150.0 else "是旧的了")
	_butterflies(c["pos"], cid, dir)
	_last_read = "往%s去了 · %s" % [dname, fresh]
	Sfx.play("pickup", -6.0, 0.0, 0.8)
	_track += 1
	if _lock_t > 0.0:
		_lock_t += 20.0
		world.hud.toast("痕迹：%s · 锁定 +20 秒" % _last_read, PREY_COL, 3.0)
	elif _track >= 3:
		_track = 0
		_lock_t = 45.0
		world.hud._show_banner("锁定猎物", "罗盘上标出了它的位置（45 秒）", PREY_COL, 2.5)
		Sfx.play("rare", -2.0, 0.0, 0.9)
	else:
		world.hud.toast("痕迹：%s · 再看 %d 处就能锁定它" % [_last_read, 3 - _track], PREY_COL, 3.5)


## 寻魂蝶：看过的爪痕里飞出几只发光的蝴蝶，飞向它接下来去的地方（下一处更新的爪痕；最新的一处就飞向猎物），飞 40 米左右
func _butterflies(from: Vector3, cid: int, dir: Vector2) -> void:
	var to := from + Vector3(dir.x, 0, dir.y) * 40.0
	var next_id := INF
	for o in clues:
		if int(o[0]) > cid and float(o[0]) < next_id:
			next_id = float(o[0])
			to = o[1]
	if next_id == INF:
		var tb: Beast = world.beasts.get(target_id) if target_id != 0 else null
		if tb and tb.alive():
			to = tb.global_position
	var flat := Vector3(to.x - from.x, 0, to.z - from.z)
	if flat.length() > 45.0:
		to = from + flat.normalized() * 45.0
	to.y = world.island.height_at(to.x, to.z) + 1.5
	var mat := FxLib.bill_mat("glow", Color(0.55, 0.9, 1.0), 3.0)
	for k in 4:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.55, 0.55)
		q.mesh = qm
		q.material_override = mat
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.fx.add_child(q)
		var a := from + Vector3(randf_range(-0.6, 0.6), 1.0, randf_range(-0.6, 0.6))
		q.global_position = a
		var mid := (a + to) * 0.5 + Vector3(randf_range(-6, 6), randf_range(3.0, 6.0), randf_range(-6, 6))
		var dur := randf_range(4.5, 6.0)
		var tw := q.create_tween()
		tw.tween_method(func(s: float):
			if is_instance_valid(q):
				var p1 := a.lerp(mid, s)
				var p2 := mid.lerp(to, s)
				q.global_position = p1.lerp(p2, s) + Vector3(0, sin(s * 18.0 + k) * 0.25, 0), 0.0, 1.0, dur).set_delay(k * 0.18)
		tw.tween_property(q, "scale", Vector3.ONE * 0.01, 1.2)
		tw.tween_callback(q.queue_free)


func compass_marks() -> Array:
	var out: Array = []
	if world.dungeon and world.dungeon.inside:
		return out
	var tb: Beast = world.beasts.get(target_id) if target_id != 0 else null
	if tb and located():
		out.append([tb.global_position, "猎", PREY_COL])
	if not channel.is_empty() and int(channel["peer"]) != Net.my_id:
		out.append([channel["pos"], "护", UiKit.JADE])
	return out


## 画面上的◆标记：队友在吸收灵环（去护法）
func marker() -> Variant:
	if not channel.is_empty() and int(channel["peer"]) != Net.my_id:
		return (channel["pos"] as Vector3) + Vector3(0, 2.5, 0)
	return null


# ------------------------------------------------------------------ 界面（左上角，任务下面）

func _card(border: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var st := UiKit.glass_style(0.42, 10, 6)
	st.border_color = border
	st.border_width_left = 3
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _hbox(sep: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


func _vbox(sep: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


func _build_ui() -> void:
	var hud: Hud = world.hud
	var q: Control = hud._quest_text.get_parent()
	var tl: Control = q.get_parent()
	_box = _vbox(6)
	tl.add_child(_box)
	tl.move_child(_box, q.get_index() + 1)
	# 猎物
	_t_card = _card(PREY_COL)
	_t_card.visible = false
	_box.add_child(_t_card)
	var th := _hbox(10)
	_t_card.add_child(th)
	_t_arrow = hud._painter(Vector2(26, 26), func(c: Control):
		var a := float(c.get_meta("a", 0.0))
		var ctr := Vector2(13, 13)
		c.draw_circle(ctr, 12.0, Color(0, 0, 0, 0.35))
		var tip := ctr + Vector2(0, -9).rotated(a)
		var l := ctr + Vector2(-6, 6).rotated(a)
		var rr := ctr + Vector2(6, 6).rotated(a)
		var m := ctr + Vector2(0, 2).rotated(a)
		c.draw_colored_polygon(PackedVector2Array([tip, rr, m, l]), PREY_COL))
	th.add_child(_t_arrow)
	var tv := _vbox(2)
	th.add_child(tv)
	var tk := _hbox(10)
	tv.add_child(tk)
	var tkk := UiKit.kicker("猎物", PREY_COL, 12)
	tkk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tk.add_child(tkk)
	_t_name = UiKit.bold("", 16, Color(1.0, 0.85, 0.6), 3)
	tk.add_child(_t_name)
	_t_clue = UiKit.label("", 14, UiKit.MOON, 3)
	tv.add_child(_t_clue)
	_t_hp = UiKit.bar(Color(1.0, 0.42, 0.28), 230, 3)
	tv.add_child(_t_hp)
	# 吸收灵环 / 护法
	_c_card = _card(UiKit.JADE)
	_c_card.visible = false
	_box.add_child(_c_card)
	var cv := _vbox(3)
	_c_card.add_child(cv)
	var ck := _hbox(10)
	cv.add_child(ck)
	var ckk := UiKit.kicker("护法", UiKit.JADE, 12)
	ckk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ck.add_child(ckk)
	_c_name = UiKit.bold("", 16, Color.WHITE, 3)
	ck.add_child(_c_name)
	var cb := _hbox(10)
	cv.add_child(cb)
	_c_bar = UiKit.bar(UiKit.JADE, 200, 5)
	_c_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cb.add_child(_c_bar)
	_c_time = UiKit.num("", 15, UiKit.JADE, 3)
	cb.add_child(_c_time)


func _update_ui(tb: Beast) -> void:
	var me := world.player.global_position
	var inside: bool = world.dungeon != null and world.dungeon.inside
	_t_card.visible = tb != null and tb.alive() and not inside
	if _t_card.visible:
		_t_name.text = tb.display_name()
		var d := _flat(tb.global_position, me)
		var near := d < Data.HUNT_REVEAL
		var dots := "●".repeat(_track) + "○".repeat(3 - _track)
		if weak:
			_t_clue.text = "虚弱 · %d 米 · 用引魂索（G）捆住就能活捉" % int(d)
		elif tb.napping or tb.has_node("Zzz"):
			_t_clue.text = "在巢穴里睡着了 · %d 米 · 悄悄摸过去偷袭（×2.5）" % int(d)
		elif near:
			_t_clue.text = "%d 米" % int(d)
		elif _lock_t > 0.0:
			_t_clue.text = "已锁定 · %d 米（%d 秒）" % [int(d), ceili(_lock_t)]
		elif _last_read != "":
			_t_clue.text = "追踪 %s · 最近的痕迹：%s" % [dots, _last_read]
		else:
			_t_clue.text = "在「%s」一带出没 · 找地上的爪痕 %s" % [region, dots]
		_t_hp.visible = near or tb.hp < tb.max_hp - 0.5
		_t_hp.value = tb.hp / tb.max_hp
		_t_arrow.visible = located()
		if _t_arrow.visible:
			_t_arrow.set_meta("a", world.hud._rel_angle(tb.global_position))
			_t_arrow.queue_redraw()
	_c_card.visible = not channel.is_empty()
	if _c_card.visible:
		var peer := int(channel["peer"])
		_c_name.text = "%s吸收%s灵环" % ["你在" if peer == Net.my_id else world.peer_name(peer) + " ", Data.age_name(int(channel["age"]))]
		_c_bar.value = float(channel["t"]) / maxf(float(channel["dur"]), 0.1)
		_c_time.text = "%d / %d 秒" % [int(channel["t"]), int(channel["dur"])]
