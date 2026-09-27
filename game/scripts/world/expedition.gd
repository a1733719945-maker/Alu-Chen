class_name Expedition
extends Node
## 猎魂远征（第十版试玩，只有星斗大森林）。
##
## 用户说"就是打打打刷怪，不好玩；卡关了也没理由继续玩"。一趟远征是一次有目的、有风险的出猎：
##   1. 猎物：房主按队伍里谁卡在瓶颈、要什么年份的魂环，挑一只魂兽王当猎物。它在森林里走来走去，
##      地图上不标准确位置——跟着地上发光的踪迹、听它的吼声找过去，55 米内才看得清。
##   2. 打倒：王的大招（红圈能躲）、半血暴怒、四分之一血逃回去；引魂索捆住它集火。
##   3. 护法：王掉的魂环要站着吸收 40 秒，不能走（能开枪）。魂环的气息一波波引来魂兽，
##      全冲着吸收的人去——队友守住他；他倒了就吸收失败，魂环掉回原地。
##   4. 天色：黄昏 → 夜晚 → 血月 → 夜晚 → 血月……天黑了魂兽更多；血月时"夜猎者"（万年疾爪龙王）
##      出来追人。它比走路快、比冲刺慢：冲刺甩得掉，也能全队围杀它（奖励最高）。船边营地它不进。
##   5. 背包：远征里打怪的金魂币、王魂先装进背包，走回船边按 F 存进去才算你的——
##      夜晚存 ×1.3、血月存 ×1.8。倒下了背包掉在原地，自己走回去捡；没捡回来又倒下，上一个就没了。
##
## 联机：房主算天色、猎物、夜猎者、护法和刷怪，每秒发一次 "expst"；背包是每个人自己的。

const FP_COLOR := Color(0.35, 0.95, 1.0)
const PREY_COL := Color(1.0, 0.62, 0.25)
const HUNTER_COL := Color(1.0, 0.25, 0.2)
const PHASE_COL := {"dusk": Color(1.0, 0.78, 0.5), "night": Color(0.65, 0.78, 1.0), "blood": Color(1.0, 0.3, 0.28)}
const DIRS := ["北", "东北", "东", "东南", "南", "西南", "西", "西北"]

var world: World
# 大家都有（房主算好发过来）
var phase := "dusk"
var phase_t := 0.0
var day := 1
var target_id := 0
var target_species := ""
var target_age := 0
var hunter_id := 0
var channel := {}                  # 正在护法：{"peer", "age", "species", "pos", "t", "dur"}
var next_t := 0.0                  # 下一只猎物多久后出现
# 房主
var hp_k := 1.0                    # 按队伍平均等级调的魂兽血量倍数
var dmg_k := 1.0                   # 魂兽伤害倍数
var team_k := 1.0                  # 猎物 / 夜猎者按人数加血
var _k_t := 0.0
var _sync_t := 0.0
var _wander_t := 0.0
var _roar_t := 25.0
var _fp_last := Vector3.ZERO
var _wave_t := 0.0
var _wave_ids: Array = []
var _extra_t := 10.0
var _steer_t := 0.0
var _hunter_wait := 0.0
var _hunter_done := false
var _hunter_leave := false
var _hunter_lair := Vector3.ZERO
var _prey := 0
var _last_species := ""
var hold := false                  # 自动截图用：房主逻辑暂停
# 自己
var bag_money := 0
var bag_mats := {}
var dropped := {}                  # 倒下时掉的背包 {"pos", "money", "mats", "node"}
var _got_state := false
var _prints: Array = []
var _ch_node: Node3D
var _quit_sent := false
var _fuzz := 0.0
var _fuzz_t := 0.0
var _ping_t := 0.0                 # 刚听到吼声：几秒内罗盘上标准确方向
var _heart_t := 0.0
var _night_env := {}
var _night_rot := Vector3.ZERO
var _cur_sky := "sky_night"
var _env_tw: Tween
# 界面
var _box: VBoxContainer
var _day: Label
var _phase_name: Label
var _phase_time: Label
var _phase_k: Label
var _t_card: PanelContainer
var _t_arrow: Control
var _t_name: Label
var _t_clue: Label
var _t_hp: ProgressBar
var _c_card: PanelContainer
var _c_name: Label
var _c_bar: ProgressBar
var _c_time: Label
var _bag: Label
var _bag_drop: Label
var _danger: PanelContainer
var _danger_text: Label


func _ready() -> void:
	_save_night_env()
	_build_ui()
	if Net.is_host():
		phase = "dusk"
		phase_t = float(Data.EXP_PHASE["dusk"]["t"])
		next_t = 8.0
		_recalc_k()
		_got_state = true
	_apply_phase(phase, true)
	world.hud._show_banner(Data.EXP_NAME, "跟着踪迹找到猎物 · 守住吸收魂环的人 · 背着战利品回船", UiKit.GOLD, 6.0)


func _exit_tree() -> void:
	# 中途退出：背包里的只带回一半（从船边走的会先全部存好）
	if has_bag():
		Profile.add_money(roundi(bag_money * 0.5))
		for sp in bag_mats:
			Profile.add_material(str(sp), int(bag_mats[sp]))
		bag_money = 0
		bag_mats = {}
		Profile.save_profile()


func _process(dt: float) -> void:
	if Net.is_host() and not hold:
		_host(dt)
	else:
		phase_t = maxf(phase_t - dt, 0.0)
		next_t = maxf(next_t - dt, 0.0)
		if not channel.is_empty():
			channel["t"] = minf(float(channel["t"]) + dt, float(channel["dur"]))
	_local(dt)


# ------------------------------------------------------------------ 房主

func _host(dt: float) -> void:
	phase_t -= dt
	if phase_t <= 0.0:
		_host_phase(str(Data.EXP_PHASE[phase]["next"]))
	_k_t -= dt
	if _k_t <= 0.0:
		_k_t = 5.0
		_recalc_k()
	_host_target(dt)
	_host_hunter(dt)
	_host_channel(dt)
	_host_extra(dt)
	_sync_t -= dt
	if _sync_t <= 0.0:
		_sync()


func _sync() -> void:
	_sync_t = 1.0
	Net.send(0, "expst", _state())


func _state() -> Array:
	var ch: Array = []
	if not channel.is_empty():
		ch = [int(channel["peer"]), int(channel["age"]), str(channel["species"]), channel["pos"], float(channel["t"]), float(channel["dur"])]
	return [phase, phase_t, day, target_id, target_species, target_age, hunter_id, ch, next_t]


## 难度跟着队伍平均等级走（50 级 = 星斗大森林原本的难度）
func _recalc_k() -> void:
	var n := maxi(world.peer_info.size(), 1)
	team_k = 1.0 + 0.5 * float(n - 1)
	if Data.autotest:
		hp_k = 1.0
		dmg_k = 1.0
		return
	var avg := _avg_level()
	hp_k = clampf(pow(avg / 50.0, 1.5), 0.45, 3.0)
	dmg_k = clampf(1.0 + (avg - 50.0) * 0.007, 0.8, 1.35)


func _avg_level() -> float:
	var tot := 0.0
	var n := 0
	for id in world.peer_info:
		tot += float(Profile.level if int(id) == Net.my_id else int(world.peer_info[id].get("level", 1)))
		n += 1
	return tot / float(maxi(n, 1))


func _host_phase(nx: String) -> void:
	if phase == "blood" and nx == "night":
		day += 1
	phase = nx
	phase_t = float(Data.EXP_PHASE[nx]["t"])
	if nx == "blood":
		_hunter_done = false
		_hunter_leave = false
		_hunter_wait = 10.0
	_apply_phase(nx, false)
	_phase_banner(nx)
	_sync()


func _camp_dist(p: Vector3) -> float:
	return Vector2(p.x - world.island.spawn.x, p.z - world.island.spawn.z).length()


func _land_species() -> Array:
	return world._map_species().filter(func(s): return not world.island.is_water_habitat(str(Data.BEASTS[s]["habitat"])))


## 猎物：队伍里卡在瓶颈的人要什么年份，就挑什么年份的王（没人卡瓶颈就按平均等级）
func _target_spec() -> Array:
	var need := -1
	for id in world.peer_info:
		var mine := int(id) == Net.my_id
		var lv: int = Profile.level if mine else int(world.peer_info[id].get("level", 1))
		var nr: int = Profile.rings.size() if mine else (world.peer_info[id].get("rings", []) as Array).size()
		if nr < Data.MAX_RINGS and lv >= (nr + 1) * 10:
			need = maxi(need, int(Data.RING_MIN_AGE[nr]))
	var avg := _avg_level()
	var age := clampi(need, 1, 3) if need >= 0 else (1 if avg < 35.0 else (2 if avg < 70.0 else 3))
	var pool: Array = []
	for sp in _land_species():
		if str(Data.BEASTS[sp]["motion"]) in ["fly", "flutter"] or sp == Data.EXP_HUNTER:
			continue
		pool.append(sp)
	if pool.size() > 1:
		pool.erase(_last_species)
	var species: String = str(pool[randi() % pool.size()]) if not pool.is_empty() else "stag"
	_last_species = species
	return [species, age]


## 离所有人都远、离营地也远的一块陆地（猎物、夜猎者从这里出来）
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
			if not world.island.is_land(p.x, p.z):
				continue
			var md := INF
			for q in pl:
				var qp: Vector3 = q["pos"]
				md = minf(md, Vector2(p.x - qp.x, p.z - qp.z).length())
			var s := minf(md, min_d * 1.6) + randf() * 20.0 + minf(_camp_dist(p), 80.0) * 0.3
			if s > bs:
				bs = s
				best = p
	if bs == -INF:
		best = world.island.spawn + Vector3(40, 0, 40)
	best.y = world.island.height_at(best.x, best.z) + 0.6
	return best


## 猎物换地方：去附近另一片栖息地
func _wander_point(from: Vector3) -> Vector3:
	var cands: Array = []
	for h in world.island.habitats:
		var type := str(h["type"])
		if not Data.HABITATS.has(type) or world.island.is_water_habitat(type):
			continue
		var c: Vector2 = h["center"]
		var p := Vector3(c.x, 0, c.y)
		var d := Vector2(p.x - from.x, p.z - from.z).length()
		if d < 25.0 or d > 130.0 or _camp_dist(p) < 55.0:
			continue
		cands.append(p)
	var p2: Vector3 = from + Vector3(randf_range(-40, 40), 0, randf_range(-40, 40))
	if not cands.is_empty():
		p2 = (cands[randi() % cands.size()] as Vector3) + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))
	if not world.island.is_land(p2.x, p2.z) or _camp_dist(p2) < 45.0:
		p2 = from
	p2.y = world.island.height_at(p2.x, p2.z) + 0.6
	return p2


func _spawn_elite(species: String, age: int, pos: Vector3, affixes: Array) -> Beast:
	var id := world.next_beast_id
	world.next_beast_id += 1
	var b := world._spawn_beast(id, species, age, pos, Vector3.ZERO, 1, false, "elite", affixes)
	Net.send(0, "bsp", [id, species, age, pos, Vector3.ZERO, 1, "elite", affixes])
	return b


func _spawn_target() -> void:
	var spec := _target_spec()
	var species := str(spec[0])
	var age := int(spec[1])
	var pos := _far_point(90.0)
	var affixes: Array = [] if Data.autotest else Data.roll_affixes(world.rng, age, world.chapter, "grass", true)
	var b := _spawn_elite(species, age, pos, affixes)
	b.max_hp *= team_k
	b.hp = b.max_hp
	b.home_speed = 3.2
	b.exp_role = "target"
	target_id = b.id
	target_species = species
	target_age = age
	_fp_last = pos
	_roar_t = 5.0
	_wander_t = 20.0
	_sync()
	var m := ["新的猎物：%s%s王 · 跟着地上发光的踪迹找它" % [Data.age_name(age), Data.BEASTS[species]["name"]], 0]
	Net.send(0, "expev", m)
	_on_ev(m)


func _host_target(dt: float) -> void:
	if target_id != 0 and not world.beasts.has(target_id):
		target_id = 0
		next_t = 30.0
		_sync()
	if target_id == 0:
		next_t -= dt
		if next_t <= 0.0:
			_spawn_target()
		return
	var b: Beast = world.beasts[target_id]
	var fp := b.global_position
	# 踪迹：它走过的地方留一对发光的脚印
	if fp.distance_to(_fp_last) > 3.2 and b.state != Beast.State.AIR:
		_fp_last = fp
		var m := [fp, b.global_basis.x]
		Net.send(0, "expfp", m)
		_on_fp(m)
	_roar_t -= dt
	if _roar_t <= 0.0:
		_roar_t = randf_range(24.0, 34.0)
		var r := [fp, "target"]
		Net.send(0, "exproar", r)
		_on_roar(r)
	# 没人在打它：隔一会儿换一片栖息地
	_wander_t -= dt
	if _wander_t <= 0.0 and b._aggro_t <= 0.0 and not b._retreat and world.nearest_player_pos(fp).distance_to(fp) > 30.0:
		_wander_t = randf_range(25.0, 40.0)
		b.spawn_pos = _wander_point(fp)


func _spawn_hunter() -> void:
	var pos := _far_point(100.0)
	_hunter_lair = pos
	var b := _spawn_elite(Data.EXP_HUNTER, 3, pos, [])
	b.max_hp *= Data.EXP_HUNTER_HP * team_k
	b.hp = b.max_hp
	b.aggro_k = 1.8
	b.speed_cap = Data.EXP_HUNTER_SPEED
	b.home_speed = 6.2
	b.exp_role = "hunter"
	b.avoid_c = world.island.spawn
	b.avoid_r = Data.EXP_CAMP_R
	b._rested = true      # 夜猎者不逃回巢养伤
	hunter_id = b.id
	_prey = 0
	_sync()
	var r := [pos, "hunter"]
	Net.send(0, "exproar", r)
	_on_roar(r)


## 夜猎者：一直往离它最近的人（营地外的）那边走；60 米内就扑上去打。人都进营地了就在营地外面转
func _host_hunter(dt: float) -> void:
	if phase != "blood":
		if hunter_id != 0:
			_hunter_leave = true
	elif hunter_id == 0 and not _hunter_done:
		_hunter_wait -= dt
		if _hunter_wait <= 0.0:
			_spawn_hunter()
	if hunter_id == 0:
		return
	var b: Beast = world.beasts.get(hunter_id)
	if b == null or not b.alive():
		hunter_id = 0
		_sync()
		return
	_steer_t -= dt
	if _steer_t > 0.0:
		return
	_steer_t = 0.5
	var camp := world.island.spawn
	if _hunter_leave:
		b.focus_peer = 0
		b._aggro_t = 0.0
		b.spawn_pos = _hunter_lair
		if world.nearest_player_pos(b.global_position).distance_to(b.global_position) > 40.0:
			world.beast_escaped(b, "despawn")
			hunter_id = 0
			_hunter_leave = false
			var m := ["血月落下，夜猎者退回了森林深处", 1]
			Net.send(0, "expev", m)
			_on_ev(m)
			_sync()
		return
	var prey := {}
	var pd := INF
	for p in world.alive_players():
		var pp: Vector3 = p["pos"]
		if _camp_dist(pp) < Data.EXP_CAMP_R:
			continue
		var d := Vector2(pp.x - b.global_position.x, pp.z - b.global_position.z).length()
		if d < pd:
			pd = d
			prey = p
	if prey.is_empty():
		b.focus_peer = 0
		b._aggro_t = 0.0
		var away := b.global_position - camp
		away.y = 0.0
		if away.length() < 1.0:
			away = Vector3.RIGHT
		b.spawn_pos = camp + away.normalized() * (Data.EXP_CAMP_R + 12.0)
		_prey = 0
		return
	b.spawn_pos = prey["pos"]
	if pd < 60.0:
		b.focus_peer = int(prey["peer"])
		b._aggro_t = maxf(b._aggro_t, 1.0)
		if _prey != b.focus_peer:
			_prey = b.focus_peer
			var m2 := [_prey, b.global_position]
			Net.send(0, "exphunt", m2)
			_on_hunt(m2)
	else:
		b.focus_peer = 0
		_prey = 0


## 天黑以后：隔一会儿在有人的地方外面刷一小群凶的（只追 32 米内的人）
func _host_extra(dt: float) -> void:
	if phase == "dusk" or Data.autotest:
		return
	_extra_t -= dt
	if _extra_t > 0.0:
		return
	_extra_t = 14.0 if phase == "night" else 10.0
	if world.beasts.size() > 24:
		return
	var pl := world.alive_players()
	if pl.is_empty():
		return
	var p: Vector3 = pl[randi() % pl.size()]["pos"]
	if _camp_dist(p) < Data.EXP_CAMP_R:
		return
	var land_sp := _land_species()
	if land_sp.is_empty():
		return
	for tries in 10:
		var a := randf() * TAU
		var r := randf_range(40.0, 55.0)
		var q := p + Vector3(cos(a) * r, 0, sin(a) * r)
		if not world.island.is_land(q.x, q.z) or _camp_dist(q) < Data.EXP_CAMP_R + 10.0:
			continue
		var sp := world._species_near(q, land_sp)
		for k in randi_range(2, 3):
			var qq := q + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
			if world.island.is_land(qq.x, qq.z):
				qq.y = world.island.height_at(qq.x, qq.z) + 0.4
				world._host_spawn_wild(qq, sp, Data.roll_age(world.rng, 1, world.chapter), "fierce")
		return


## 房主：有人要吸收魂环（远征里要护法：站着 40 秒）
func host_absorb(from: int, rid: int) -> void:
	if not world.rings.has(rid):
		return
	if not channel.is_empty():
		var tip := "%s 正在吸收魂环，等他吸收完再来" % world.peer_name(int(channel["peer"]))
		if from == Net.my_id:
			world.hud.toast(tip, Color(1.0, 0.8, 0.5), 3.0)
		else:
			Net.send(from, "hint", [tip])
		return
	var here := false
	for p in world.all_players():
		if int(p["peer"]) == from:
			here = true
	if not here:
		return
	var r: Dictionary = world.rings[rid]
	# 就在魂环掉的地方吸收（魂环悬在地上一人高）
	var pos: Vector3 = (r["pos"] as Vector3) - Vector3(0, 1.2, 0)
	Net.send(0, "ringgone", [rid, from])
	world._on_ring_gone([rid, from])
	channel = {"peer": from, "age": int(r["age"]), "species": str(r["species"]), "pos": pos, "t": 0.0, "dur": Data.EXP_CHANNEL}
	_wave_t = 3.0
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
	if _wave_t <= 0.0:
		_wave_t = Data.EXP_WAVE_GAP
		_host_wave()


## 护法的一波：从同一个方向来一群凶的，只冲吸收魂环的人
func _host_wave() -> void:
	var pos: Vector3 = channel["pos"]
	var land_sp := _land_species()
	if land_sp.is_empty():
		return
	var n := 2 + (world._all_peers().size() - 1) + (1 if float(channel["t"]) > float(channel["dur"]) * 0.5 else 0)
	var age := clampi(int(channel["age"]) - 1, 1, 2)
	var a0 := randf() * TAU
	for i in n:
		for tries in 8:
			var a := a0 + randf_range(-0.7, 0.7)
			var r := randf_range(24.0, 32.0)
			var q := pos + Vector3(cos(a) * r, 0, sin(a) * r)
			if not world.island.is_land(q.x, q.z):
				continue
			q.y = world.island.height_at(q.x, q.z) + 0.4
			var b: Beast = world._host_spawn_wild(q, world._species_near(q, land_sp), age, "fierce")
			if b:
				b.focus_peer = int(channel["peer"])
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
		world._host_drop_ring(c["pos"] + Vector3(0, 1.0, 0), int(c["age"]), str(c["species"]), 180.0)
	var msg := [int(c["peer"]), ok, int(c["age"]), str(c["species"]), c["pos"]]
	Net.send(0, "expchend", msg)
	_on_channel_end(msg)
	_sync()


## 房主：有魂兽死了（World._host_kill 调）
func host_on_kill(b: Beast) -> void:
	_wave_ids.erase(b.id)
	if b.id == target_id:
		target_id = 0
		next_t = 35.0
		var m := ["魂环掉在地上——吸收要站 %d 秒，队友护法" % int(Data.EXP_CHANNEL), 2]
		Net.send(0, "expev", m)
		_on_ev(m)
		_sync()
	elif b.id == hunter_id:
		hunter_id = 0
		_hunter_done = true
		var m2 := ["夜猎者被猎杀了！", 3]
		Net.send(0, "expev", m2)
		_on_ev(m2)
		_sync()


# ------------------------------------------------------------------ 消息

func on_message(from: int, type: String, data: Variant) -> void:
	match type:
		"expst":
			if not Net.is_host():
				_apply_state(data)
		"expfp":
			_on_fp(data)
		"exproar":
			_on_roar(data)
		"expchend":
			_on_channel_end(data)
		"expchq":
			if Net.is_host() and not channel.is_empty() and int(channel["peer"]) == from:
				_host_end_channel(false)
		"exphunt":
			_on_hunt(data)
		"expev":
			_on_ev(data)


func _apply_state(d: Array) -> void:
	var ph := str(d[0])
	if ph != phase or not _got_state:
		var first := not _got_state
		_got_state = true
		phase = ph
		_apply_phase(ph, first)
		if not first:
			_phase_banner(ph)
	phase_t = float(d[1])
	day = int(d[2])
	target_id = int(d[3])
	target_species = str(d[4])
	target_age = int(d[5])
	hunter_id = int(d[6])
	next_t = float(d[8]) if d.size() > 8 else 0.0
	var ch: Array = d[7]
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
	if pos.distance_to(world.player.global_position) > 170.0:
		return
	var side: Vector3 = d[1]
	side.y = 0.0
	side = side.normalized() if side.length() > 0.01 else Vector3.RIGHT
	for s in [-1.0, 1.0]:
		var n := world.fx._ground(pos + side * 0.4 * s, "glow", FP_COLOR, 0.6, 110.0, 25.0, 3.0)
		_prints.append(n)
	while _prints.size() > 90:
		var o: Node = _prints.pop_front()
		if is_instance_valid(o):
			o.queue_free()


func _dir_name(pos: Vector3) -> String:
	var me := world.player.global_position
	var bearing := rad_to_deg(atan2(pos.x - me.x, -(pos.z - me.z)))
	return str(DIRS[posmod(roundi(bearing / 45.0), 8)])


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _on_roar(d: Array) -> void:
	var pos: Vector3 = d[0]
	var kind := str(d[1])
	var dist := _flat(pos, world.player.global_position)
	Sfx.play("boss_roar", clampf(-2.0 - dist * 0.04, -16.0, -2.0), 0.05, 0.8 if kind == "target" else 0.55)
	if kind == "hunter":
		world.hud._show_banner("血月 · 夜猎者出没", "它比你走路快、比你冲刺慢 · 船边营地它不进", HUNTER_COL, 4.5)
		return
	_ping_t = 6.0
	if dist > Data.EXP_REVEAL:
		world.hud.toast("%s边传来吼声 · 约 %d 米" % [_dir_name(pos), roundi(dist / 25.0) * 25], PREY_COL, 3.5)


func _on_hunt(d: Array) -> void:
	var peer := int(d[0])
	if peer == Net.my_id:
		world.hud._show_banner("夜猎者盯上你了", "冲刺跑回船边营地，或者叫上队友围杀它", HUNTER_COL, 3.5)
		Sfx.play("boss_roar", 0.0, 0.0, 0.55)
		world.player.trauma = minf(world.player.trauma + 0.4, 1.0)
	else:
		world.hud.feed("夜猎者盯上了 %s" % world.peer_name(peer), HUNTER_COL)


func _on_ev(d: Array) -> void:
	var t := str(d[0])
	match int(d[1]):
		0:
			world.hud.toast(t, PREY_COL, 5.0)
			Sfx.play("rare", -4.0, 0.0, 0.8)
		2:
			world.hud._show_banner("猎物倒下", t, UiKit.GOLD, 5.0)
		3:
			world.hud._show_banner("猎杀夜猎者", "最危险的猎物 · 王魂进背包，地上有万年魂环", HUNTER_COL, 6.0)
			Sfx.play("quest_done", 0.0)
		_:
			world.hud.feed(t, Color(0.85, 0.85, 0.9))


# ------------------------------------------------------------------ 护法

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
		world.hud._show_banner("护法", "站着吸收 %d 秒：不能走动，能开枪 · 魂环的气息会引来一波波魂兽" % int(channel["dur"]), col, 4.0)
	else:
		world.hud.toast("%s 开始吸收%s魂环——去护法，别让魂兽碰到他" % [world.peer_name(int(channel["peer"])), Data.age_name(age)], col, 4.0)
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
			world.hud.toast("吸收被打断了——魂环掉回了原地，回去重新吸收", Color(1.0, 0.6, 0.45), 5.0)
	elif ok:
		world.fx._pillar(pos, col, 1.6, 40.0, 0.8)
		world.hud.feed("%s 吸收了%s魂环！" % [world.peer_name(peer), Data.age_name(age)], col)
	else:
		world.hud.feed("%s 的吸收被打断了，魂环掉回了地上" % world.peer_name(peer), Color(1.0, 0.6, 0.45))


## 吸收的人脚下两圈转着的魂环、一盏灯；别人看还有一道光柱（自己看会糊一脸，不加）
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


# ------------------------------------------------------------------ 背包

func add_bag(money: int) -> void:
	bag_money += maxi(money, 0)


func add_mat(species: String, n := 1) -> void:
	bag_mats[species] = int(bag_mats.get(species, 0)) + n


func has_bag() -> bool:
	return bag_money > 0 or not bag_mats.is_empty()


func _mat_n(m: Dictionary) -> int:
	var n := 0
	for k in m:
		n += int(m[k])
	return n


func bank_k() -> float:
	return float(Data.EXP_PHASE[phase]["k"])


## 在船边存战利品：按现在的天色乘倍数
func bank() -> void:
	if not has_bag():
		return
	var k := bank_k()
	var got := roundi(bag_money * k)
	Profile.add_money(got)
	for sp in bag_mats:
		Profile.add_material(str(sp), int(bag_mats[sp]))
	var mt := _mat_n(bag_mats)
	var sub := "+%d 金魂币" % got
	if k > 1.0:
		sub += "（%s ×%.1f）" % [Data.EXP_PHASE[phase]["name"], k]
	if mt > 0:
		sub += "  · 王魂 ×%d" % mt
	world.hud._show_banner("战利品入账", sub, UiKit.GOLD, 4.0)
	Sfx.play("sell", 0.0)
	Sfx.play("coin", -2.0)
	bag_money = 0
	bag_mats = {}
	Profile.count("exp_banks")
	Profile.save_profile()


func on_my_death() -> void:
	world.player.channeling = false
	if Net.is_host() and not channel.is_empty() and int(channel["peer"]) == Net.my_id:
		_host_end_channel(false)
	if not dropped.is_empty():
		_free_drop()
		world.hud.feed("上一个掉的背包没捡回来，丢了", Color(1.0, 0.5, 0.4))
	if has_bag():
		var pos := world.player.global_position
		dropped = {"pos": pos, "money": bag_money, "mats": bag_mats.duplicate(), "node": _drop_node(pos)}
		world.hud.feed("背包掉在了倒下的地方（%d 金魂币）——回去捡" % bag_money, Color(1.0, 0.75, 0.45))
		bag_money = 0
		bag_mats = {}


func pick_bag() -> void:
	if dropped.is_empty():
		return
	bag_money += int(dropped["money"])
	var m: Dictionary = dropped["mats"]
	for sp in m:
		add_mat(str(sp), int(m[sp]))
	_free_drop()
	world.hud.toast("捡回了背包", UiKit.GOLD, 2.5)
	Sfx.play("pickup", 0.0)


func _free_drop() -> void:
	var n: Variant = dropped.get("node")
	if n is Node and is_instance_valid(n):
		(n as Node).queue_free()
	dropped = {}


## 掉在地上的背包：一个发光的袋子 + 一道金色光柱（远远就看得到）
func _drop_node(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	world.fx.add_child(n)
	n.global_position = pos
	U.part(n, U.sphere(0.32, 10, 8), U.glow(Color(1.0, 0.72, 0.3), 2.0), Vector3(0, 0.35, 0), Vector3.ZERO, Vector3(1, 0.8, 1), false)
	U.part(n, U.cyl(0.05, 0.05, 16.0, 6), U.glow(Color(1.0, 0.8, 0.35), 3.0), Vector3(0, 8.0, 0), Vector3.ZERO, Vector3.ONE, false)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.75, 0.35)
	l.light_energy = 1.5
	l.omni_range = 5.0
	l.position = Vector3(0, 1.0, 0)
	n.add_child(l)
	return n


func interactables() -> Array:
	var out: Array = []
	if not dropped.is_empty():
		out.append({"id": "expbag", "pos": (dropped["pos"] as Vector3) + Vector3(0, 1.0, 0), "r": 3.0, "text": "按 F 捡回背包（%d 金魂币）" % int(dropped["money"]), "act": true})
	return out


func boat_text() -> String:
	var k := bank_k()
	return "按 F 把战利品存进船里（%d 金魂币%s）" % [bag_money, (" ×%.1f" % k) if k > 1.0 else ""]


# ------------------------------------------------------------------ 天色

func _pano() -> PanoramaSkyMaterial:
	return world.builder.env.sky.sky_material as PanoramaSkyMaterial


func _save_night_env() -> void:
	var env: Environment = world.builder.env
	var sun: DirectionalLight3D = world.builder.sun
	_night_env = {"sun_col": sun.light_color, "sun_e": sun.light_energy, "ambient": env.ambient_light_energy, "exposure": env.tonemap_exposure,
		"fog_col": env.fog_light_color, "fog_d": env.fog_density, "sky_e": _pano().energy_multiplier, "vol": env.volumetric_fog_albedo, "sat": env.adjustment_saturation}
	_night_rot = env.sky_rotation


func _phase_env(ph: String) -> Dictionary:
	var e := _night_env.duplicate()
	match ph:
		"dusk":
			e["sun_col"] = Color(1.0, 0.74, 0.5)
			e["sun_e"] = 1.25
			e["ambient"] = 0.8
			e["exposure"] = 1.05
			e["fog_col"] = Color(0.62, 0.5, 0.46)
			e["fog_d"] = 0.0035
			e["sky_e"] = 0.9
			e["vol"] = Color(1.0, 0.85, 0.7)
			e["sat"] = 1.1
		"blood":
			e["sun_col"] = Color(1.0, 0.32, 0.26)
			e["sun_e"] = 0.55
			e["ambient"] = 0.5
			e["fog_col"] = Color(0.24, 0.05, 0.06)
			e["fog_d"] = 0.0055
			e["sky_e"] = 0.4
			e["vol"] = Color(1.0, 0.35, 0.3)
			e["sat"] = 1.15
	return e


func _set_sky(sky_name: String) -> void:
	_cur_sky = sky_name
	_pano().panorama = load("res://assets/sky/%s.hdr" % sky_name)
	if sky_name == "sky_dusk":
		# 黄昏的天空图里太阳转到和灯光一样的方向（地图原本的月亮方向）
		var dir: Vector3 = world.builder._sky_dir(0.613, 4.7)
		world.builder.env.sky_rotation = Vector3(0, atan2(dir.x, -dir.z) - deg_to_rad(-40.0), 0)
	else:
		world.builder.env.sky_rotation = _night_rot


func _apply_phase(ph: String, instant: bool) -> void:
	var e := _phase_env(ph)
	var sky := "sky_dusk" if ph == "dusk" else "sky_night"
	var env: Environment = world.builder.env
	var sun: DirectionalLight3D = world.builder.sun
	if _env_tw and _env_tw.is_valid():
		_env_tw.kill()
	if instant:
		_set_sky(sky)
		_pano().energy_multiplier = float(e["sky_e"])
		sun.light_color = e["sun_col"]
		sun.light_energy = float(e["sun_e"])
		env.ambient_light_energy = float(e["ambient"])
		env.tonemap_exposure = float(e["exposure"])
		env.fog_light_color = e["fog_col"]
		env.fog_density = float(e["fog_d"])
		env.volumetric_fog_albedo = e["vol"]
		env.adjustment_saturation = float(e["sat"])
		return
	var dur := 8.0
	_env_tw = create_tween().set_parallel(true)
	_env_tw.tween_property(sun, "light_color", e["sun_col"], dur)
	_env_tw.tween_property(sun, "light_energy", float(e["sun_e"]), dur)
	_env_tw.tween_property(env, "ambient_light_energy", float(e["ambient"]), dur)
	_env_tw.tween_property(env, "tonemap_exposure", float(e["exposure"]), dur)
	_env_tw.tween_property(env, "fog_light_color", e["fog_col"], dur)
	_env_tw.tween_property(env, "fog_density", float(e["fog_d"]), dur)
	_env_tw.tween_property(env, "volumetric_fog_albedo", e["vol"], dur)
	_env_tw.tween_property(env, "adjustment_saturation", float(e["sat"]), dur)
	if sky != _cur_sky:
		# 换天空图：先暗下去，换图，再亮起来
		var sw := create_tween()
		sw.tween_property(_pano(), "energy_multiplier", 0.02, dur * 0.4)
		sw.tween_callback(_set_sky.bind(sky))
		sw.tween_property(_pano(), "energy_multiplier", float(e["sky_e"]), dur * 0.6)
	else:
		_env_tw.tween_property(_pano(), "energy_multiplier", float(e["sky_e"]), dur)


func _phase_banner(ph: String) -> void:
	var k := float(Data.EXP_PHASE[ph]["k"])
	match ph:
		"night":
			world.hud._show_banner("入夜", "魂兽多起来了 · 这时候回船存战利品 ×%.1f" % k, PHASE_COL["night"], 4.0)
		"blood":
			world.hud._show_banner("血月", "夜猎者要出来了 · 这时候回船存战利品 ×%.1f" % k, PHASE_COL["blood"], 4.5)
			Sfx.play("boss_roar", -4.0, 0.0, 0.5)
		_:
			world.hud._show_banner(str(Data.EXP_PHASE[ph]["name"]), "", PHASE_COL.get(ph, UiKit.GOLD), 3.0)


## 音乐：夜猎者在附近就放 Boss 曲
func hunter_near() -> bool:
	var hb: Beast = world.beasts.get(hunter_id) if hunter_id != 0 else null
	return hb != null and hb.alive() and _flat(hb.global_position, world.player.global_position) < 60.0


# ------------------------------------------------------------------ 自己这边：每帧

func _local(dt: float) -> void:
	var p: Player = world.player
	var tb: Beast = world.beasts.get(target_id) if target_id != 0 else null
	if tb:
		tb.exp_role = "target"
	var hb: Beast = world.beasts.get(hunter_id) if hunter_id != 0 else null
	if hb:
		hb.exp_role = "hunter"
		if not hb.has_meta("exp_deco"):
			_decorate_hunter(hb)
	_ping_t = maxf(_ping_t - dt, 0.0)
	_fuzz_t -= dt
	if _fuzz_t <= 0.0:
		_fuzz_t = 8.0
		_fuzz = randf_range(-1.0, 1.0)
	# 吸收时被技能带离了原地：算放弃
	if not channel.is_empty() and int(channel["peer"]) == Net.my_id and not _quit_sent:
		if _flat(p.global_position, channel["pos"]) > 5.0:
			_quit_sent = true
			if Net.is_host():
				_host_end_channel(false)
			else:
				Net.send_host("expchq", [])
	_update_ui(dt, tb, hb)


## 夜猎者：身上一圈红光、头顶一道红色魂环，远远就认得出
func _decorate_hunter(b: Beast) -> void:
	b.set_meta("exp_deco", true)
	var s: float = float(Data.AGES[b.age]["scale"]) * b.size_k
	var bs := BeastModels.body_size(b.species) * s
	var l := OmniLight3D.new()
	l.light_color = HUNTER_COL
	l.light_energy = 3.0
	l.omni_range = maxf(bs.length() * 1.5, 6.0)
	l.position = Vector3(0, bs.y * 0.5, 0)
	b.add_child(l)
	var ring := FxLib.soul_ring(HUNTER_COL, HUNTER_COL, bs.x * 0.35 + 0.4, 3.0)
	ring.position = Vector3(0, bs.y * 0.95, 0)
	b.add_child(ring)
	var tw := ring.create_tween().set_loops()
	tw.tween_property(ring, "rotation:y", TAU, 1.6).as_relative()


## 猎物在罗盘上的位置：离得远只知道个大概方向（偏 ±35 度，8 秒换一次），刚吼过、走近了才准
func _fuzzy_pos(pos: Vector3) -> Vector3:
	var me := world.player.global_position
	var d := _flat(pos, me)
	if d < Data.EXP_REVEAL or _ping_t > 0.0:
		return pos
	var a := _fuzz * clampf((d - Data.EXP_REVEAL) / 200.0, 0.0, 1.0) * deg_to_rad(35.0)
	var v := (pos - me).rotated(Vector3.UP, a)
	return me + v


func compass_marks() -> Array:
	var out: Array = []
	var me := world.player.global_position
	var tb: Beast = world.beasts.get(target_id) if target_id != 0 else null
	if tb and tb.alive():
		var near := _flat(tb.global_position, me) < Data.EXP_REVEAL or _ping_t > 0.0
		out.append([_fuzzy_pos(tb.global_position), "猎", PREY_COL if near else Color(PREY_COL.r, PREY_COL.g, PREY_COL.b, 0.7)])
	var hb: Beast = world.beasts.get(hunter_id) if hunter_id != 0 else null
	if hb and hb.alive() and _flat(hb.global_position, me) < 140.0:
		out.append([hb.global_position, "夜", HUNTER_COL])
	if not dropped.is_empty():
		out.append([dropped["pos"], "包", UiKit.GOLD])
	if not channel.is_empty() and int(channel["peer"]) != Net.my_id:
		out.append([channel["pos"], "护", UiKit.JADE])
	return out


## 画面上的◆标记：队友在吸收（去护法）> 自己掉的背包
func marker() -> Variant:
	if not channel.is_empty() and int(channel["peer"]) != Net.my_id:
		return (channel["pos"] as Vector3) + Vector3(0, 2.5, 0)
	if not dropped.is_empty():
		return (dropped["pos"] as Vector3) + Vector3(0, 1.5, 0)
	return null


# ------------------------------------------------------------------ 界面（左上角，替换原来的章节任务）

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
	q.visible = false
	var tl: Control = q.get_parent()
	_box = _vbox(7)
	tl.add_child(_box)
	tl.move_child(_box, 0)
	var head := _hbox(8)
	_box.add_child(head)
	head.add_child(hud._painter(Vector2(10, 10), func(c: Control):
		c.draw_colored_polygon(PackedVector2Array([Vector2(5, 0), Vector2(10, 5), Vector2(5, 10), Vector2(0, 5)]), UiKit.GOLD)))
	var k := UiKit.kicker("猎魂远征", UiKit.GOLD, 13)
	UiKit._text_style(k, 3)
	head.add_child(k)
	_day = UiKit.kicker("", UiKit.MIST, 13)
	UiKit._text_style(_day, 3)
	head.add_child(_day)
	var ph := _hbox(10)
	_box.add_child(ph)
	_phase_name = UiKit.bold("", 24, Color.WHITE, 3)
	ph.add_child(_phase_name)
	_phase_time = UiKit.num("", 18, UiKit.MOON, 3)
	_phase_time.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ph.add_child(_phase_time)
	_phase_k = UiKit.bold("", 14, UiKit.GOLD, 3)
	_phase_k.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ph.add_child(_phase_k)
	# 猎物
	_t_card = _card(PREY_COL)
	_box.add_child(_t_card)
	var th := _hbox(10)
	_t_card.add_child(th)
	_t_arrow = hud._painter(Vector2(26, 26), func(c: Control):
		var a := float(c.get_meta("a", 0.0))
		var ctr := Vector2(13, 13)
		c.draw_circle(ctr, 12.0, Color(0, 0, 0, 0.35))
		if not c.get_meta("on", false):
			c.draw_arc(ctr, 11.0, 0.0, TAU, 24, Color(1, 1, 1, 0.25), 1.5, true)
			return
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
	# 护法
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
	# 背包
	var br := _hbox(8)
	_box.add_child(br)
	var ic := UiKit.icon("coin", 16, UiKit.GOLD)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	br.add_child(ic)
	_bag = UiKit.bold("", 16, UiKit.GOLD, 3)
	br.add_child(_bag)
	_bag_drop = UiKit.label("", 14, Color(1.0, 0.72, 0.5), 3)
	br.add_child(_bag_drop)
	# 夜猎者靠近：罗盘和提示下面一条红色的
	var dc := CenterContainer.new()
	dc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.place(dc, Vector4(0.5, 0, 0.5, 0), Vector4(-300, 196, 300, 236))
	hud._root.add_child(dc)
	_danger = PanelContainer.new()
	var ds := UiKit.glass_style(0.55, 16, 6)
	ds.border_color = HUNTER_COL
	ds.set_border_width_all(1)
	_danger.add_theme_stylebox_override("panel", ds)
	_danger.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_danger.visible = false
	dc.add_child(_danger)
	_danger_text = UiKit.bold("", 17, Color(1.0, 0.55, 0.5), 2)
	_danger.add_child(_danger_text)


func _update_ui(dt: float, tb: Beast, hb: Beast) -> void:
	var me := world.player.global_position
	var P: Dictionary = Data.EXP_PHASE[phase]
	_day.text = "· 第 %d 夜" % day
	_phase_name.text = str(P["name"])
	_phase_name.add_theme_color_override("font_color", PHASE_COL.get(phase, Color.WHITE))
	var s := int(maxf(phase_t, 0.0))
	_phase_time.text = "%d:%02d" % [s / 60, s % 60]
	_phase_k.text = ("回船存战利品 ×%.1f" % float(P["k"])) if float(P["k"]) > 1.0 else ""
	# 猎物
	if tb and tb.alive():
		_t_card.visible = true
		_t_name.text = tb.display_name()
		var d := _flat(tb.global_position, me)
		var near := d < Data.EXP_REVEAL
		if near:
			_t_clue.text = "%d 米" % int(d)
		elif _ping_t > 0.0:
			_t_clue.text = "吼声 · %s边 约 %d 米" % [_dir_name(tb.global_position), roundi(d / 25.0) * 25]
		else:
			_t_clue.text = "踪迹 · %s边 约 %d 米" % [_dir_name(_fuzzy_pos(tb.global_position)), maxi(roundi(d / 50.0) * 50, 50)]
		_t_hp.visible = near or tb.hp < tb.max_hp - 0.5
		_t_hp.value = tb.hp / tb.max_hp
		_t_arrow.set_meta("on", true)
		_t_arrow.set_meta("a", world.hud._rel_angle(_fuzzy_pos(tb.global_position)))
	elif target_id == 0:
		_t_card.visible = true
		_t_name.text = "下一只猎物"
		_t_clue.text = "%d 秒后出现" % ceili(next_t) if next_t > 0.0 else "马上出现"
		_t_hp.visible = false
		_t_arrow.set_meta("on", false)
	else:
		_t_card.visible = false
	_t_arrow.queue_redraw()
	# 护法
	_c_card.visible = not channel.is_empty()
	if _c_card.visible:
		var peer := int(channel["peer"])
		_c_name.text = "%s 吸收%s魂环" % ["你在" if peer == Net.my_id else world.peer_name(peer), Data.age_name(int(channel["age"]))]
		_c_bar.value = float(channel["t"]) / maxf(float(channel["dur"]), 0.1)
		_c_time.text = "%d / %d 秒" % [int(channel["t"]), int(channel["dur"])]
	# 背包
	var mt := _mat_n(bag_mats)
	_bag.text = "背包 %d%s" % [bag_money, ("  · 王魂 ×%d" % mt) if mt > 0 else ""]
	_bag_drop.text = ("· 掉落的背包 %d 米" % int(_flat(dropped["pos"], me))) if not dropped.is_empty() else ""
	# 夜猎者靠近：心跳、屏幕边发红
	var hd := INF
	if hb and hb.alive():
		hd = _flat(hb.global_position, me)
	var on := hd < 90.0 and not world.player.dead
	_danger.visible = on
	if on:
		var k := clampf(1.0 - hd / 90.0, 0.0, 1.0)
		_danger_text.text = "夜猎者 · %d 米" % int(hd)
		_danger.modulate.a = 0.75 + 0.25 * sin(Time.get_ticks_msec() / 120.0)
		_heart_t -= dt
		if _heart_t <= 0.0:
			_heart_t = lerpf(1.3, 0.45, k)
			Sfx.play("thud", -18.0 + k * 12.0, 0.0, 0.6)
			world.hud._vig_t = maxf(world.hud._vig_t, 0.12 + 0.3 * k)
