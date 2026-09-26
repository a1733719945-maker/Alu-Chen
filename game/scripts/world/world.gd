class_name World
extends Node3D
## 一局游戏：地图、玩家、魂兽、Boss、任务、奖励、联机同步。
##
## 联机分工：
##   每个玩家 —— 算自己的移动、开枪射线、引魂索、魂技目标、自己受到的伤害，命中结果发给房主
##   房主     —— 生成魂兽和 Boss、算它们的物理和血量、分奖励、推进任务，再广播给大家
## 每个人的金魂币、等级、魂环存在自己的存档里；章节进度用房主的存档。

signal leave_requested
signal travel_requested(chapter: int)

const PLAYER_SNAP_RATE := 30.0
const BEAST_SNAP_RATE := 20.0
const BOSS_SNAP_RATE := 15.0
const RESPAWN_TIME := 5.0
const DOWN_TIME_TEAM := 25.0     # 联机时倒地多久没人救，海鸥来叼走
const DOWN_TIME_SOLO := 4.0
const REVIVE_TIME := 2.5         # 队友按住 F 多久能拉起来
const CARRY_TIME := 4.2

var chapter := 1
var island: Island
var builder: WorldBuilder
var fx: Fx
var hud: Hud
var skills: SkillSystem
var loot: Loot
var player: Player
var players_root: Node3D
var beasts_root: Node3D
var remotes := {}          # peer id -> RemotePlayer
var peer_info := {}        # peer id -> {"name", "wuhun", "level", "rings"}
var beasts := {}           # beast id -> Beast
var boss: Boss
var next_beast_id := 1
var stats := {}            # peer id -> {"kills": int, "earned": int}
var rng := RandomNumberGenerator.new()
var paused := false
var ui_open := false

# 任务（房主推进，大家显示）
var quest_idx := 0
var quest_count := 0
var quest_target := 1          # 当前任务要做到多少（联机按人数加量，房主算好发给大家）

var rings := {}            # 地上的魂环 rid -> {"pos", "age", "species", "node", "t"}
var next_ring_id := 1
var _hazards: Array = []   # 飞行中的毒液 / 蛛网 / 石头
var _pools: Array = []     # 毒池
var _telegraphs: Array = []
var _grenades: Array = []
var _player_snap_t := 0.0
var _beast_snap_t := 0.0
var _boss_snap_t := 0.0
var _t := 0.0
var _respawn_t := 0.0
var _pool_tick := 0.0
var _last_prog := []
var _down_t := 0.0
var _carry_t := -1.0
var _revive_t := 0.0
var _revive_peer := 0
var _boat_ready := {}      # 房主：谁已经上船按了 F
var _boat_count := [0, 1]  # 大家显示用：[已上船, 总人数]
var _i_boarded := false
var elites := {}           # 精英刷新点 key -> {"species", "age", "pos", "id", "t"}（房主）
var _elite_init := false
var _cap_t := 0.0
var _tide_t := Data.TIDE_FIRST   # 下一波兽潮倒计时（房主）
var _tide_left := 0
var _tide_spawn_t := 0.0
var _tide_total := 0
var _tide_king_done := true


func _init(p_chapter := 1) -> void:
	chapter = p_chapter


func _ready() -> void:
	add_to_group("world")
	Data.cur_chapter = chapter
	rng.randomize()
	var ch: Dictionary = Data.CHAPTERS[chapter]
	island = Island.new(str(ch["map"]))
	var t0 := Time.get_ticks_msec()
	builder = WorldBuilder.new(island, self, chapter)
	builder.build()
	print("[world] 第 %d 章地图搭好了，用了 %d 毫秒" % [chapter, Time.get_ticks_msec() - t0])
	Settings.changed.connect(builder.apply_quality)
	players_root = Node3D.new()
	players_root.name = "Players"
	add_child(players_root)
	beasts_root = Node3D.new()
	beasts_root.name = "Beasts"
	add_child(beasts_root)
	fx = Fx.new()
	fx.name = "Fx"
	add_child(fx)
	skills = SkillSystem.new()
	skills.world = self
	add_child(skills)

	player = Player.new()
	player.name = "LocalPlayer"
	player.world = self
	players_root.add_child(player)
	player.teleport(island.spawn + Vector3(0, 0.3, 0))
	player.look_to(island.spawn_yaw, deg_to_rad(-4))
	fx.set_camera(player.cam)
	player.died.connect(_on_player_died)
	player.hurt.connect(func(amount, dir): hud.hurt(amount, dir))

	hud = Hud.new()
	hud.world = self
	add_child(hud)
	player.lure.hint.connect(hud.toast)
	player.ammo_changed.connect(hud.on_ammo)
	player.weapon_changed.connect(hud.on_weapon)
	hud.on_weapon(player.gun)
	loot = Loot.new()
	add_child(loot)
	loot.setup(self)

	if Net.is_host():
		quest_idx = Profile.quest if Profile.chapter == chapter else 0
		quest_count = Profile.quest_count if Profile.chapter == chapter else 0
	_stat(Net.my_id)
	peer_info[Net.my_id] = _my_info()
	Net.peer_left.connect(_on_peer_left)
	Profile.changed.connect(_on_profile_changed)
	Sfx.play_ambient("ambient", -16.0)
	capture_mouse(true)
	var ch_trait := str(Data.CH_TRAIT.get(chapter, ""))
	hud.chapter_banner(str(ch["name"]), str(ch["intro"]) + (("\n" + str(Data.TRAIT_TEXT[ch_trait])) if ch_trait != "" else ""))
	_ensure_bounties()
	_last_prog = [Profile.level, Profile.rings.size()]
	if Net.is_host():
		get_tree().create_timer(0.5).timeout.connect(_host_check_quest)


func _exit_tree() -> void:
	if Settings.changed.is_connected(builder.apply_quality):
		Settings.changed.disconnect(builder.apply_quality)
	Profile.save_profile()
	# 换地图时旧世界比新世界晚一帧才删掉：新世界已经在了就别把鼠标放出来（以前要点一下鼠标才能转视角）
	for w in get_tree().get_nodes_in_group("world"):
		if w != self and is_instance_valid(w):
			return
	Sfx.stop_ambient()
	Sfx.set_underwater(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _my_info() -> Dictionary:
	return {"name": Settings.display_name(), "wuhun": Settings.wuhun, "level": Profile.level, "rings": _ring_summary(), "outfit": Profile.outfit, "skin": Profile.skin}


func _ring_summary() -> Array:
	var out := []
	for r in Profile.rings:
		out.append(int(r["age"]))
	return out


func capture_mouse(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func set_paused(p: bool) -> void:
	paused = p
	_refresh_input()
	hud.show_pause(p)


func set_ui_open(o: bool) -> void:
	ui_open = o
	_refresh_input()


func _refresh_input() -> void:
	var free := not paused and not ui_open
	player.input_enabled = free
	capture_mouse(free)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if ui_open:
			hud.close_panels()
		else:
			set_paused(not paused)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("wuhun_panel") and not paused:
		hud.toggle_wuhun()
	elif event.is_action_pressed("achievements") and not paused:
		hud.toggle_achievements()
	elif event.is_action_pressed("fullscreen"):
		Settings.toggle_fullscreen()
	elif event.is_action_pressed("toggle_fps"):
		Settings.show_fps = not Settings.show_fps
		Settings.save_settings()
	elif event is InputEventMouseButton and event.pressed and not paused and not ui_open and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		capture_mouse(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not paused and not ui_open and is_inside_tree() and not Data.autotest:
		set_paused(true)


func _process(dt: float) -> void:
	_t += dt
	builder.animate(_t)
	_player_snap_t += dt
	if _player_snap_t >= 1.0 / PLAYER_SNAP_RATE:
		_player_snap_t = 0.0
		Net.send(0, "ps", player.net_state())
	if Net.is_host():
		_beast_snap_t += dt
		if _beast_snap_t >= 1.0 / BEAST_SNAP_RATE:
			_beast_snap_t = 0.0
			_send_beast_snapshot()
		if boss and not boss.dead:
			_boss_snap_t += dt
			if _boss_snap_t >= 1.0 / BOSS_SNAP_RATE:
				_boss_snap_t = 0.0
				Net.send(0, "bsnap", boss.snapshot())
		_host_rings(dt)
		_host_elites(dt)
		_host_tide(dt)
		_altar_cd = maxf(_altar_cd - dt, 0.0)
	_ach_t += dt
	if _ach_t > 3.0:
		_ach_t = 0.0
		_ach_check()
	_update_hazards(dt)
	_update_boss_moves(dt)
	_update_grenades(dt)
	_update_rings_visual(dt)
	_update_down(dt)
	_update_revive(dt)


# ------------------------------------------------------------------ 工具

func raycast(from: Vector3, to: Vector3, mask: int, exclude: Array = []) -> Dictionary:
	var ex: Array[RID] = []
	for e in exclude:
		ex.append(e)
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, ex)
	return get_world_3d().direct_space_state.intersect_ray(q)


## alive：没倒地；target：魂兽和 Boss 能打的（没倒地、没隐身、刚复活的几秒也不打）
func all_players() -> Array:
	var out := [{"peer": Net.my_id, "pos": player.global_position, "alive": not player.dead, "target": not player.dead and not player.untargetable()}]
	for id in remotes:
		var r: RemotePlayer = remotes[id]
		out.append({"peer": id, "pos": r.global_position, "alive": not r.is_dead(), "target": not r.is_dead() and not r.untargetable()})
	return out


## 魂兽和 Boss 会攻击的玩家
func alive_players() -> Array:
	return all_players().filter(func(p): return p["target"])


func nearest_player(p: Vector3) -> Dictionary:
	var best := {}
	var bd := INF
	for pl in alive_players():
		var d: float = (pl["pos"] as Vector3).distance_to(p)
		if d < bd:
			bd = d
			best = pl
	return best


func nearest_player_pos(p: Vector3) -> Vector3:
	var n := nearest_player(p)
	return n["pos"] if not n.is_empty() else player.global_position


## 离某点最近的水面位置（Boss 从这里跃出）
func water_point_near(p: Vector3) -> Vector3:
	var best := island.boss_pos
	for i in 24:
		var a := TAU * i / 24.0
		for r in [8.0, 14.0, 20.0, 28.0]:
			var q := p + Vector3(cos(a) * r, 0, sin(a) * r)
			if not island.is_land(q.x, q.z) and island.height_at(q.x, q.z) < -2.0:
				if q.distance_to(p) < best.distance_to(p):
					best = Vector3(q.x, Island.WATER_Y, q.z)
	return best


func _stat(id: int) -> Dictionary:
	if not stats.has(id):
		stats[id] = {"kills": 0, "earned": 0}
	return stats[id]


func caster_color(peer: int) -> Color:
	var info: Dictionary = peer_info.get(peer, {})
	return Data.wuhun_color(int(info.get("wuhun", 0)))


func peer_name(peer: int) -> String:
	if peer == Net.my_id:
		return Settings.display_name()
	var info: Dictionary = peer_info.get(peer, {})
	return str(info.get("name", Net.peer_name(peer)))


# ------------------------------------------------------------------ 开枪（本地玩家）

func _falloff(w: Dictionary, dist: float) -> float:
	var f: Vector3 = w["falloff"]
	var k := clampf((dist - f.x) / maxf(f.y - f.x, 0.01), 0.0, 1.0)
	return lerpf(1.0, f.z, k)


func local_fire(g: Gun, origin: Vector3, dirs: Array[Vector3], muzzle: Vector3) -> void:
	var w: Dictionary = g.d
	var ends: Array = []
	var per_beast := {}
	var boss_dmg := 0.0
	var boss_weak := false
	var exclude := [player.get_rid()]
	var single: bool = w["pellets"] == 1
	var pierce := int(w.get("pierce", 1))
	var dmg_mult := player.damage_mult()
	var crit := player.crit_active()
	for dir in dirs:
		var to: Vector3 = origin + dir * float(w["range"])
		var from := origin
		var ex := exclude.duplicate()
		var end := to
		var left := pierce
		while left > 0:
			var hit := raycast(from, to, U.LAYER_WORLD | U.LAYER_BEAST, ex)
			var hit_dist := INF if hit.is_empty() else origin.distance_to(hit["position"])
			var water_dist := INF
			if dir.y < -0.001 and origin.y > Island.WATER_Y:
				water_dist = (origin.y - Island.WATER_Y) / -dir.y
				var wp := origin + dir * water_dist
				if island.is_land(wp.x, wp.z) or water_dist > float(w["range"]):
					water_dist = INF
			if water_dist < hit_dist:
				end = origin + dir * water_dist
				if single or randf() < 0.3:
					fx.splash(end)
				break
			if hit.is_empty():
				break
			end = hit["position"]
			var col: Object = hit["collider"]
			if col is Beast and (col as Beast).alive():
				var b := col as Beast
				var head := b.is_head(int(hit["shape"])) or crit
				var dmg: float = float(w["damage"]) * _falloff(w, hit_dist) * (float(w["headshot"]) if head else 1.0) * dmg_mult
				if not per_beast.has(b.id):
					per_beast[b.id] = {"dmg": 0.0, "imp": Vector3.ZERO, "pts": Vector3.ZERO, "n": 0, "head": false, "dist": hit_dist}
				var h: Dictionary = per_beast[b.id]
				h["dmg"] += dmg
				h["imp"] += dir * float(w["impulse"]) + Vector3.UP * float(w["impulse"]) * float(w["lift"])
				h["pts"] += b.to_local(end)
				h["n"] += 1
				h["head"] = h["head"] or head
				fx.impact_beast(end, hit["normal"], Data.age_color(b.age), head)
				if w.get("bolt", false) and single:
					fx.stick_arrow(end, dir, b)
				left -= 1
				ex.append(b.get_rid())
				from = end
				continue
			elif col is Node and (col as Node).has_meta("gull"):
				# 打海鸥：它叼着的东西 / 队友会掉下来
				fx.impact_beast(end, hit["normal"], Color(0.95, 0.95, 1.0), false)
				hud.hitmarker(false, false)
				Sfx.play("hit", -3.0, 0.05)
				Net.send_host("gullhit", [int((col as Node).get_meta("gull"))])
				break
			elif col is Node and (col as Node).has_meta("boss"):
				var weak: bool = bool((col as Node).get_meta("weak")) or crit
				boss_dmg += float(w["damage"]) * _falloff(w, hit_dist) * (float(w["headshot"]) if weak else 1.0) * dmg_mult
				boss_weak = boss_weak or weak
				fx.impact_beast(end, hit["normal"], Color(0.8, 0.3, 1.0), weak)
				break
			else:
				fx.impact_world(end, hit["normal"])
				if w.get("bolt", false) and (single or randf() < 0.2):
					fx.stick_arrow(end, dir, null)
				break
		ends.append(end)
	for e in ends:
		if single:
			fx.tracer(muzzle, e, w["tracer"], 0.06 if g.id != "zhuihun" else 0.09, 300.0 if g.id != "zhuihun" else 420.0, 5.0, true)
		else:
			fx.tracer(muzzle, e, w["tracer"], 0.025, 240.0, 1.8)
	fx.muzzle_flash(muzzle, dirs[0], w["tracer"], not single or g.id == "zhuihun")
	Net.send(0, "shot", [g.id, muzzle, ends])

	for id in per_beast:
		var h: Dictionary = per_beast[id]
		var b: Beast = beasts.get(id)
		if not b:
			continue
		var local_pt: Vector3 = h["pts"] / float(h["n"])
		var shown: float = h["dmg"] * b.armor_factor(h["head"])
		hud.hitmarker(h["head"], false)
		Sfx.play("hit_head" if h["head"] else "hit", -1.0 if h["head"] else -4.0, 0.05)
		if Net.is_host():
			var before := b.alive()
			var real := b.take_hit(h["dmg"], h["imp"], local_pt, h["head"], Net.my_id, h["dist"])
			var killed := before and b.hp <= 0.0
			fx.damage_number(b.global_position + Vector3(0, 0.3, 0), real, h["head"], killed)
			if killed:
				_host_kill(b)
		else:
			b.flinch(h["imp"])
			fx.damage_number(b.global_position + Vector3(0, 0.3, 0), shown, h["head"])
			Net.send(1, "hit", [id, h["dmg"], h["imp"], local_pt, h["head"], h["dist"]])
	if boss_dmg > 0.0 and boss:
		hud.hitmarker(boss_weak, false)
		Sfx.play("hit_head" if boss_weak else "hit", -2.0, 0.05)
		fx.damage_number(boss.center() + Vector3(randf_range(-1, 1), 2.0, 0), boss_dmg * (1.7 if boss_weak else 0.6), boss_weak)
		if Net.is_host():
			host_boss_damage(boss_dmg, boss_weak, Net.my_id)
		else:
			Net.send(1, "bhit", [boss_dmg, boss_weak])


## 空手出拳打中了东西
func local_melee(g: Gun, _origin: Vector3, dir: Vector3, hit: Dictionary) -> void:
	var w: Dictionary = g.d
	var col: Object = hit["collider"]
	var dmg := float(w["damage"]) * player.damage_mult()
	var imp := dir * float(w["impulse"]) + Vector3.UP * float(w["impulse"]) * float(w["lift"])
	var at: Vector3 = hit["position"]
	Sfx.play("punch", 0.0, 0.08)
	if col is Beast and (col as Beast).alive():
		var b := col as Beast
		var head := b.is_head(int(hit.get("shape", 0))) or player.crit_active()
		if head:
			dmg *= float(w["headshot"])
		fx.impact_beast(at, hit["normal"], Data.age_color(b.age), head)
		hud.hitmarker(head, false)
		var local_pt := b.to_local(at)
		if Net.is_host():
			var before := b.alive()
			var real := b.take_hit(dmg, imp, local_pt, head, Net.my_id, 2.0)
			fx.damage_number(b.global_position + Vector3(0, 0.3, 0), real, head, before and b.hp <= 0.0)
			if before and b.hp <= 0.0:
				_host_kill(b)
		else:
			b.flinch(imp)
			fx.damage_number(b.global_position + Vector3(0, 0.3, 0), dmg * b.armor_factor(head), head)
			Net.send(1, "hit", [b.id, dmg, imp, local_pt, head, 2.0])
	elif col is Node and (col as Node).has_meta("boss") and boss:
		var weak := bool((col as Node).get_meta("weak")) or player.crit_active()
		fx.impact_beast(at, hit["normal"], Color(0.8, 0.3, 1.0), weak)
		hud.hitmarker(weak, false)
		fx.damage_number(at, dmg * (1.7 if weak else 0.6), weak)
		if Net.is_host():
			host_boss_damage(dmg, weak, Net.my_id)
		else:
			Net.send(1, "bhit", [dmg, weak])
	elif col is Node and (col as Node).has_meta("gull"):
		Net.send_host("gullhit", [int((col as Node).get_meta("gull"))])
	else:
		fx.impact_world(at, hit["normal"])


# ------------------------------------------------------------------ 引魂索拽出魂兽

func request_yank(pos: Vector3, habitat: String, species: String, age: int, bait := "grass") -> void:
	Net.send_host("yank", [pos, habitat, species, age, player.global_position, bait])


## 这一点有没有能站的东西（地面、码头、浮冰），有就返回高度，没有返回 -INF
func _solid_y(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 80.0, z), Vector3(x, Island.WATER_Y - 0.4, z), U.LAYER_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or float(hit["position"].y) < Island.WATER_Y + 0.05:
		return -INF
	return float(hit["position"].y)


func _launch_velocity(from: Vector3, owner_pos: Vector3, _species: String) -> Vector3:
	var to_owner := owner_pos - from
	to_owner.y = 0.0
	var d := to_owner.length()
	var dir := to_owner.normalized() if d >= 2.0 else Vector3.RIGHT
	var land: Vector3
	if d < 2.0:
		land = from + Vector3(1.5, 0, 0)
	else:
		land = owner_pos - dir * clampf(d * 0.3, 3.0, 7.0)
	# 落点在水里的话，沿着往玩家的方向找到岸（或码头）再落，不然魂兽一落地就逃回水里了
	var ly := _solid_y(land.x, land.z)
	var k := 0
	while ly == -INF and k < 40:
		land += dir * 0.75
		ly = _solid_y(land.x, land.z)
		k += 1
		if (land - owner_pos).dot(dir) > 5.0:
			break
	land.y = ly if ly != -INF else Island.WATER_Y
	var apex := maxf(from.y, land.y) + float(Data.LURE["launch_height"]) * rng.randf_range(0.85, 1.15)
	var vy := Beast.launch_vy(apex - from.y)
	var t_total := Beast.flight_time(vy, from.y - land.y)
	var hor := land - from
	hor.y = 0.0
	return hor / t_total + Vector3(0, vy, 0)


func _host_spawn(owner: int, pos: Vector3, species: String, age: int, owner_pos: Vector3, temper := "", bait := "grass", with_affix := true) -> Beast:
	if not Data.BEASTS.has(species):
		return null
	age = clampi(age, 0, 3)
	var id := next_beast_id
	next_beast_id += 1
	var spawn := pos + Vector3(0, 0.4, 0)
	if not island.is_land(pos.x, pos.z):
		spawn.y = maxf(spawn.y, Island.WATER_Y + 0.3)
	var vel := _launch_velocity(spawn, owner_pos, species)
	if bait == "test":
		# 自动测试：固定胆小、没词缀，结果稳定
		temper = "flee"
		with_affix = false
	if temper == "":
		temper = Data.roll_temper(rng, species, age, bait)
	var affixes: Array = Data.roll_affixes(rng, age, chapter, bait) if with_affix else []
	var b := _spawn_beast(id, species, age, spawn, vel, owner, false, temper, affixes)
	b.reward_k = float(Data.BAITS.get(bait, Data.BAITS["grass"])["reward"])
	Net.send(0, "bsp", [id, species, age, spawn, vel, owner, temper, affixes])
	if temper == "fierce" and owner == Net.my_id:
		hud.toast("凶暴的%s！它会一直追着你打" % Data.BEASTS[species]["name"], Color(1.0, 0.45, 0.35), 2.5)
	elif temper == "bone":
		hud.feed("魂骨兽出现了！打死它必掉魂骨", UiKit.GOLD)
	return b


func _spawn_beast(id: int, species: String, age: int, pos: Vector3, vel: Vector3, owner: int, proxy: bool, temper := "flee", affixes: Array = []) -> Beast:
	var b := Beast.new()
	b.setup(self, id, species, age, owner, proxy, temper, affixes)
	beasts_root.add_child(b)
	b.launch(pos, vel)
	beasts[id] = b
	if island.is_land(pos.x, pos.z):
		fx.dirt_puff(pos)
	else:
		fx.splash(pos, true)
		Sfx.play_at("splash_big", pos, 0.0)
	Sfx.play_at("emerge_" + species, pos, 0.0, 0.08)
	if age >= 1:
		Sfx.play_at("rare", pos, -4.0 if age == 1 else 2.0, 0.0, 1.0 if age == 1 else 0.8)
	return b


# ------------------------------------------------------------------ 房主：伤害、击杀、奖励

func host_skill_damage(b: Beast, dmg: float, imp: Vector3, caster: int) -> bool:
	if not b.alive():
		return false
	var before := b.hp
	if dmg > 0.0 or imp != Vector3.ZERO:
		b.take_hit(dmg, imp, Vector3.ZERO, false, caster, 0.0, true)
	if dmg > 0.0:
		var real := before - b.hp
		Net.send(0, "dmgnum", [b.global_position + Vector3(0, 0.3, 0), real])
		fx.damage_number(b.global_position + Vector3(0, 0.3, 0), real, false, b.hp <= 0.0)
	if b.hp <= 0.0:
		_host_kill(b)
		return true
	return false


func host_boss_damage(dmg: float, weak: bool, shooter: int) -> void:
	if boss and not boss.dead:
		boss.take_hit(dmg, weak, shooter)


func beast_burned_out(b: Beast) -> void:
	if Net.is_host() and b.alive():
		_host_kill(b)


func _all_peers() -> Array:
	var out := [Net.my_id]
	out.append_array(remotes.keys())
	return out


func _host_kill(b: Beast) -> void:
	if not b.alive():
		return
	var killer := b.last_hitter
	var base: float = Data.kill_money(b.species, b.age)
	var xp: float = Data.kill_xp(b.species, b.age)
	var mult := 1.0
	var tags: Array = []
	var KB: Dictionary = Data.KILL_BONUS
	if b.last_hit_air:
		mult *= KB["air"]
		tags.append("空中击杀 ×%.1f" % KB["air"])
		if b.air_hits >= 2:
			var j := minf((b.air_hits - 1) * float(KB["juggle_step"]), KB["juggle_max"])
			mult *= 1.0 + j
			tags.append("空中连击 %d 下 +%d%%" % [b.air_hits, roundi(j * 100)])
	if b.last_headshot:
		mult *= KB["headshot"]
		tags.append("爆头 ×%.2f" % KB["headshot"])
	if b.last_dist >= KB["far_dist"]:
		mult *= KB["far"]
		tags.append("远距离 %d 米 ×%.1f" % [roundi(b.last_dist), KB["far"]])
	if b.temper == "elite":
		mult *= Data.ELITE_REWARD
		tags.append("精英 ×%d" % int(Data.ELITE_REWARD))
	if not b.affixes.is_empty():
		mult *= 1.0 + 0.5 * b.affixes.size()
		tags.append("%s +%d%%" % [Data.affix_names(b.affixes), 50 * b.affixes.size()])
	if b.reward_k > 1.0:
		mult *= b.reward_k
		tags.append("鱼饵 ×%.1f" % b.reward_k)
	var reward := roundi(base * mult * Data.KILL_MONEY)
	var xp_total := roundi(xp * mult)
	var rewards := {}
	for peer in _all_peers():
		if peer == killer:
			rewards[peer] = [reward, xp_total]
		elif b.damagers.has(peer):
			rewards[peer] = [roundi(reward * float(KB["assist"])), roundi(xp_total * 0.7)]
		else:
			rewards[peer] = [0, roundi(xp_total * float(KB["team_xp"]))]
	var st := _stat(killer)
	st["kills"] += 1
	st["earned"] += reward
	var msg := [b.id, killer, b.species, b.age, b.global_position, tags, rewards, st["kills"], st["earned"], b.affixes, b.temper == "elite"]
	Net.send(0, "bk", msg)
	_on_kill(msg)
	# 词缀：分裂成两只小的；自爆（先出红圈）
	if "split" in b.affixes:
		for i in 2:
			_host_spawn(1, b.global_position + Vector3(randf_range(-1, 1), 0.3, randf_range(-1, 1)), b.species, maxi(b.age - 1, 0), nearest_player_pos(b.global_position), "fierce", "grass", false)
	if "blast" in b.affixes:
		boss_telegraph(b.global_position, 5.5, 1.1, 30.0 * (1.0 + b.age * 0.5), "slam", b.global_position)
	_host_maybe_drop_ring(b, killer)
	_host_drop_loot(b)
	_host_quest_event("kill", 1)
	_host_quest_event("hunt", 1, b.species)


func beast_escaped(b: Beast, reason: String) -> void:
	if not Net.is_host() or not b.alive():
		return
	var msg := [b.id, reason, b.global_position]
	if Data.autotest:
		print("[autotest] 魂兽逃走：%s %s %s state=%d life=%.1f 地面 %.2f" % [b.species, reason, b.global_position, b.state, b.life, island.height_at(b.global_position.x, b.global_position.z)])
	Net.send(0, "be", msg)
	_on_escape(msg)


## 打死魂兽掉东西：魂骨兽必掉魂骨，千年的小概率掉；偶尔掉回血丹、佛怒唐莲
func _host_drop_loot(b: Beast) -> void:
	var at := b.global_position + Vector3(0, 0.5, 0)
	# 魂兽肉：吃了回饱食度，也能丢进收购箱卖
	var meats := (3 if b.temper == "elite" else (1 if rng.randf() < 0.55 else 0))
	for i in meats:
		loot.spawn("item", "meat", 1, 0, at, Vector3(randf_range(-2, 2), 5.0, randf_range(-2, 2)))
	var r := rng.randf()
	if r < 0.07 + b.age * 0.03:
		loot.spawn("item", "pill", 1, 0, at, Vector3(randf_range(-2, 2), 5.5, randf_range(-2, 2)))
	elif r < 0.11 + b.age * 0.05:
		loot.spawn("item", "grenade", 1, 0, at, Vector3(randf_range(-2, 2), 5.5, randf_range(-2, 2)))
	if b.temper == "elite":
		loot.spawn("item", "pill", 1, 0, at, Vector3(randf_range(-2, 2), 6.0, randf_range(-2, 2)))
	var chance := 0.012 + (0.05 if b.age >= 2 else 0.0)
	if b.temper == "bone" or b.temper == "elite" or rng.randf() < chance:
		var bid: String = Data.BONE_BY_BEAST.get(b.species, "")
		if bid != "":
			loot.spawn("bone", "%s@%d" % [bid, b.age], 1, 0, at, Vector3(randf_range(-1.5, 1.5), 7.0, randf_range(-1.5, 1.5)))
			var msg := "%s掉落了魂骨【%s】！" % [Data.BEASTS[b.species]["name"], Data.bone_name("%s@%d" % [bid, b.age])]
			Net.send(0, "feedall", [msg])
			hud.feed(msg, UiKit.GOLD)


# ------------------------------------------------------------------ 成就

var _ach_t := 0.0
var _tide_until := 0.0


func ach_count(key: String, n := 1) -> void:
	Profile.count(key, n)
	_ach_check()


func _ach_check() -> void:
	for a in Data.ACHIEVEMENTS:
		var id := str(a["id"])
		if Profile.achieved.has(id):
			continue
		var ok := false
		if a.has("stat"):
			ok = Profile.stat(str(a["stat"])) >= int(a["n"])
		else:
			ok = _ach_special(str(a["special"]))
		if ok:
			Profile.achieved[id] = true
			Profile.add_money(int(a["reward"]))
			hud.achievement(str(a["name"]), str(a["desc"]), int(a["reward"]))
			Sfx.play("level_up", -3.0, 0.0, 1.2)


func _ach_special(k: String) -> bool:
	match k:
		"bones6":
			return Profile.equipped.size() >= 6
		"rings1":
			return Profile.rings.size() >= 1
		"rings5":
			return Profile.rings.size() >= 5
		"wannian":
			for r in Profile.rings:
				if int(r["age"]) >= 3:
					return true
			return false
		"lv20":
			return Profile.level >= 20
		"lv50":
			return Profile.level >= 50
		"lv80":
			return Profile.level >= 80
		"god":
			return Profile.god
		"arsenal":
			return Profile.weapons.size() >= 5
		"skins5":
			return Profile.skins.size() >= 5
	return false


## 击杀成就：从击杀消息的加成标签里看空中、连击、爆头、远距离
func _ach_kill(tags: Array, affixes: Array, elite: bool) -> void:
	Profile.count("kills")
	for t in tags:
		var s := str(t)
		if s.begins_with("空中击杀"):
			Profile.count("air_kills")
		elif s.begins_with("空中连击") and int(s.get_slice(" ", 1)) >= 8:
			Profile.count("juggle8")
		elif s.begins_with("爆头"):
			Profile.count("head_kills")
		elif s.begins_with("远距离") and int(s.get_slice(" ", 1)) >= 80:
			Profile.count("far80")
	if affixes.size() >= 2:
		Profile.count("affix2")
	if elite:
		Profile.count("elites")
	if Time.get_ticks_msec() / 1000.0 < _tide_until:
		Profile.count("tide_kills")
	_ach_check()


## 成神：100 级 + 第十魂环。播结局动画，之后还能接着玩
func _check_god() -> void:
	if Profile.god or Profile.level < Data.MAX_LEVEL or Profile.rings.size() < Data.MAX_RINGS:
		return
	Profile.god = true
	Profile.mark_dirty()
	_ach_check()
	Net.send(0, "feedall", ["%s 成神了！" % Settings.display_name()])
	if Data.autotest:
		return
	var v := Voyage.new()
	v.video = "res://assets/cutscene/ending.ogv"
	v.length = 10.0
	v.title = "成神 · %s" % Settings.display_name()
	get_tree().root.add_child(v)
	v.finished.connect(func(): hud._show_banner("成神！", "你已经是神了。还可以坐船回任何一个岛，继续猎魂、刷魂骨和外观。", UiKit.GOLD, 9.0))


# ------------------------------------------------------------------ 猎魂录：每种魂兽三颗星，集齐一张图送专属皮肤

func _codex_kill(species: String, age: int, affixes: Array, elite: bool) -> void:
	var gained := Profile.codex_kill(species, age, not affixes.is_empty(), elite)
	if gained == 0:
		return
	var what := []
	if gained & 1:
		what.append("猎杀 %d 只" % Data.CODEX_KILLS)
	if gained & 2:
		what.append("打倒带词缀的")
	if gained & 4:
		what.append("打倒千年 / 精英")
	var stars := Profile.species_stars(species)
	hud.toast("猎魂录 · %s %s（%s）  体力 +2  伤害 +0.5%%" % [Data.BEASTS[species]["name"], "★".repeat(stars) + "☆".repeat(3 - stars), "，".join(what)], UiKit.GOLD, 4.0)
	Sfx.play("quest_done", -4.0)
	player.on_bones_changed()
	# 这张图的魂兽全部三颗星：送专属皮肤
	var all3 := true
	for sp in _map_species():
		if Profile.species_stars(str(sp)) < 3:
			all3 = false
	var skin := str(Data.CODEX_MAP_SKIN.get(island.map_id, ""))
	if all3 and skin != "" and Profile.unlock_look("skin", skin):
		Profile.count("codex_maps")
		hud._show_banner("猎魂录 · %s 集齐！" % str(Data.CHAPTERS[chapter]["name"]), "解锁专属暗器皮肤【%s】（暗器铺 → 外观）" % Data.GUN_SKINS[skin]["name"], UiKit.GOLD, 6.0)


## 这张图猎魂录的进度（武魂面板用）：[[魂兽 id, 星星数], ...]
func codex_page() -> Array:
	var out: Array = []
	for sp in _map_species():
		out.append([sp, Profile.species_stars(str(sp))])
	return out


# ------------------------------------------------------------------ 悬赏（每个人自己的，打完换新的）

## 这张地图上能抓到的魂兽
func _map_species() -> Array:
	var out: Array = []
	for h in island.habitats:
		var type := str(h["type"])
		if Data.HABITATS.has(type):
			var s := str(Data.HABITATS[type]["beast"])
			if not s in out:
				out.append(s)
	for w in island.water_types:
		if Data.HABITATS.has(str(w)):
			var s2 := str(Data.HABITATS[str(w)]["beast"])
			if not s2 in out:
				out.append(s2)
	return out


func _ensure_bounties() -> void:
	Profile.bounties = Profile.bounties.filter(func(b): return int(b.get("ch", 0)) == chapter and Data.BEASTS.has(str(b.get("species", ""))))
	while Profile.bounties.size() < Data.BOUNTY_N:
		Profile.bounties.append(_new_bounty())
	Profile.mark_dirty()
	hud.update_bounties()


func _new_bounty() -> Dictionary:
	var sp := _map_species()
	var species: String = sp[rng.randi() % sp.size()] if not sp.is_empty() else "rabbit"
	var age := Data.roll_age(rng, 0, chapter)
	if rng.randf() < 0.35:
		age = mini(age + 1, 2)
	var affix := ""
	if rng.randf() < 0.4:
		var keys: Array = Data.AFFIXES.keys()
		affix = str(keys[rng.randi() % keys.size()])
	var base: float = Data.kill_money(species, age) * 5.0 * (1.7 if affix != "" else 1.0)
	return {"ch": chapter, "species": species, "age": age, "affix": affix, "reward": maxi(roundi(base / 10.0) * 10, 30)}


func bounty_text(b: Dictionary) -> String:
	var a := str(b.get("affix", ""))
	return "%s%s%s · %s  →  %d" % [Data.age_name(int(b["age"])), ("以上 · " if int(b["age"]) > 0 else " · "), ("[%s]" % Data.AFFIXES[a]["name"]) if a != "" else "", Data.BEASTS[b["species"]]["name"], int(b["reward"])]


func _check_bounty(species: String, age: int, affixes: Array) -> void:
	for i in Profile.bounties.size():
		var b: Dictionary = Profile.bounties[i]
		if str(b["species"]) != species or age < int(b["age"]):
			continue
		if str(b.get("affix", "")) != "" and not str(b["affix"]) in affixes:
			continue
		Profile.add_money(int(b["reward"]))
		Profile.count("bounties")
		hud.quest_done("悬赏完成：%s" % bounty_text(b), int(b["reward"]))
		Sfx.play("sell", 0.0)
		Profile.bounties[i] = _new_bounty()
		Profile.mark_dirty()
		hud.update_bounties()
		return


# ------------------------------------------------------------------ 奇遇：每张图自己的事件（Data.CH_EVENTS），隔 6~8 分钟一次

func _host_tide(dt: float) -> void:
	if boss or Data.autotest:
		return
	var ev: Dictionary = Data.CH_EVENTS.get(chapter, {})
	if _tide_left > 0:
		_tide_spawn_t -= dt
		if _tide_spawn_t <= 0.0:
			_tide_spawn_t = rng.randf_range(0.6, 1.2) if str(ev.get("mode", "")) == "flock" else rng.randf_range(1.8, 3.0)
			_tide_left -= 1
			_host_tide_spawn(ev)
			# 一半的时候王出来
			if not _tide_king_done and _tide_left <= _tide_total / 2:
				_tide_king_done = true
				_host_tide_king(ev)
			if _tide_left <= 0:
				_tide_t = rng.randf_range(Data.TIDE_GAP[0], Data.TIDE_GAP[1])
		return
	_tide_t -= dt
	if _tide_t <= 0.0:
		_tide_total = int(ev.get("n", 8)) + 3 * (_all_peers().size() - 1)
		_tide_left = _tide_total
		_tide_king_done = str(ev.get("king", "")) == ""
		_tide_spawn_t = 3.0
		Net.send(0, "tide", [chapter])
		_on_tide([chapter])


func _on_tide(msg: Array = []) -> void:
	var ch := int(msg[0]) if msg.size() > 0 else chapter
	var ev: Dictionary = Data.CH_EVENTS.get(ch, {})
	_tide_until = Time.get_ticks_msec() / 1000.0 + Data.TIDE_TIME
	hud._show_banner("奇遇 · %s" % ev.get("name", "兽潮"), str(ev.get("desc", "")), ev.get("color", Color(1.0, 0.4, 0.3)), 5.0)
	Sfx.play("boss_roar", 0.0, 0.0, 1.2)
	player.trauma = minf(player.trauma + 0.5, 1.0)
	_event_env(str(ev.get("env", "")), Data.TIDE_TIME)


## 奇遇的天色天气：慢慢变过去，结束后变回来
var _env_saved := {}


func _event_env(kind: String, dur: float) -> void:
	var env: Environment = builder.env
	var sun: DirectionalLight3D = builder.sun
	if env == null or sun == null or kind == "":
		return
	if _env_saved.is_empty():
		_env_saved = {"sun": sun.light_energy, "sky": env.background_energy_multiplier, "amb": env.ambient_light_energy, "fog": env.fog_density, "sun_c": sun.light_color}
	var sun_k := 1.0
	var fog_k := 1.0
	var tint: Color = _env_saved["sun_c"]
	match kind:
		"gold":
			tint = Color(1.0, 0.8, 0.55)
		"night":
			sun_k = 0.18
			fog_k = 1.6
			tint = Color(0.55, 0.65, 1.0)
		"stars":
			sun_k = 0.35
			tint = Color(0.75, 0.7, 1.0)
		"blizzard":
			sun_k = 0.55
			fog_k = 7.0
		"storm":
			sun_k = 0.4
			fog_k = 3.0
			tint = Color(0.7, 0.8, 1.0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(sun, "light_energy", float(_env_saved["sun"]) * sun_k, 3.0)
	tw.tween_property(sun, "light_color", tint, 3.0)
	tw.tween_property(env, "background_energy_multiplier", float(_env_saved["sky"]) * lerpf(1.0, sun_k, 0.8), 3.0)
	tw.tween_property(env, "ambient_light_energy", float(_env_saved["amb"]) * lerpf(1.0, sun_k, 0.7), 3.0)
	tw.tween_property(env, "fog_density", float(_env_saved["fog"]) * fog_k, 3.0)
	tw.chain().tween_interval(dur)
	tw.chain().tween_property(sun, "light_energy", float(_env_saved["sun"]), 4.0)
	tw.parallel().tween_property(sun, "light_color", _env_saved["sun_c"], 4.0)
	tw.parallel().tween_property(env, "background_energy_multiplier", float(_env_saved["sky"]), 4.0)
	tw.parallel().tween_property(env, "ambient_light_energy", float(_env_saved["amb"]), 4.0)
	tw.parallel().tween_property(env, "fog_density", float(_env_saved["fog"]), 4.0)
	# 下雪 / 下雨 / 星星坠落：跟着玩家的粒子
	if kind in ["blizzard", "storm", "stars"]:
		var p := CPUParticles3D.new()
		p.amount = 500 if kind != "stars" else 60
		p.lifetime = 2.5 if kind == "storm" else 5.0
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(30, 1, 30)
		p.direction = Vector3(0.3, -1, 0.1)
		p.spread = 10.0
		p.gravity = Vector3(0, -30.0 if kind == "storm" else -3.0, 0)
		p.initial_velocity_min = 8.0 if kind == "storm" else 1.0
		p.initial_velocity_max = 14.0 if kind == "storm" else 3.0
		var q := QuadMesh.new()
		q.size = Vector2(0.03, 0.6) if kind == "storm" else (Vector2(0.12, 0.12) if kind == "blizzard" else Vector2(0.25, 0.25))
		p.mesh = q
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED if kind != "storm" else BaseMaterial3D.BILLBOARD_FIXED_Y
		m.albedo_color = {"blizzard": Color(1, 1, 1, 0.85), "storm": Color(0.7, 0.8, 1.0, 0.45), "stars": Color(0.8, 0.75, 1.0, 1.0)}[kind]
		if kind == "stars":
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_texture = fx._soft_tex if kind != "storm" else null
		p.material_override = m
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		player.add_child(p)
		p.position = Vector3(0, 18, 0)
		p.emitting = true
		get_tree().create_timer(dur + 2.0).timeout.connect(func():
			if is_instance_valid(p):
				p.emitting = false
				get_tree().create_timer(5.0).timeout.connect(p.queue_free))


func _host_tide_spawn(ev: Dictionary) -> void:
	var targets := alive_players()
	if targets.is_empty():
		return
	var tp: Dictionary = targets[rng.randi() % targets.size()]
	var center: Vector3 = tp["pos"]
	var sp: Array = (ev.get("species", []) as Array).filter(func(s): return Data.BEASTS.has(str(s)))
	if sp.is_empty():
		sp = _map_species().filter(func(s): return not island.is_water_habitat(str(Data.BEASTS[s]["habitat"])))
	if sp.is_empty():
		return
	var species: String = sp[rng.randi() % sp.size()]
	if str(ev.get("mode", "")) == "flock":
		# 天上飞过的鸟群：在高处出现，打下来奖励 ×3
		var a0 := rng.randf() * TAU
		var p0 := center + Vector3(cos(a0) * 30.0, 16.0 + rng.randf() * 8.0, sin(a0) * 30.0)
		var b0 := _host_spawn(1, p0, species, Data.roll_age(rng, 0, chapter), center, "flee", "grass")
		if b0:
			b0.reward_k *= 3.0
		return
	for k in 16:
		var a := rng.randf() * TAU
		var r := rng.randf_range(24.0, 36.0)
		var p := center + Vector3(cos(a) * r, 0, sin(a) * r)
		if island.is_land(p.x, p.z) or Data.BEASTS[species]["motion"] in ["fly", "flutter"]:
			p.y = maxf(island.height_at(p.x, p.z), Island.WATER_Y) + 0.3
			_host_spawn(1, p, species, Data.roll_age(rng, 0, chapter), center, "fierce", "blood")
			return


## 奇遇里的王：精英，打死必掉魂骨
func _host_tide_king(ev: Dictionary) -> void:
	var king := str(ev.get("king", ""))
	var targets := alive_players()
	if king == "" or targets.is_empty() or not Data.BEASTS.has(king):
		return
	var center: Vector3 = targets[0]["pos"]
	for k in 20:
		var a := rng.randf() * TAU
		var p := center + Vector3(cos(a) * 26.0, 0, sin(a) * 26.0)
		if island.is_land(p.x, p.z):
			p.y = island.height_at(p.x, p.z) + 0.5
			var age: int = [1, 1, 2, 3, 3][clampi(chapter - 1, 0, 4)]
			_host_spawn(1, p, king, age, center, "elite", "blood")
			var msg := ["%s王来了！" % Data.BEASTS[king]["name"]]
			Net.send(0, "feedall", msg)
			hud.feed(str(msg[0]), Color(1.0, 0.6, 0.3))
			return

## 精英魂兽（小 Boss）：每张地图在陆地栖息地附近固定几个点，打死了 2 分钟后原地重生
func _host_elites(dt: float) -> void:
	if Data.autotest:
		return
	if not _elite_init:
		if _t < 3.0:
			return
		_elite_init = true
		_init_elites()
	for key in elites:
		var e: Dictionary = elites[key]
		if int(e["id"]) != 0:
			if not beasts.has(int(e["id"])):
				e["id"] = 0
				e["t"] = Data.ELITE_RESPAWN
			continue
		e["t"] = float(e["t"]) - dt
		if float(e["t"]) <= 0.0:
			_host_spawn_elite(key)
	# 地上游荡的魂兽太多了：收掉离所有人最远的普通魂兽
	_cap_t += dt
	if _cap_t > 2.0:
		_cap_t = 0.0
		if beasts.size() > 28:
			var far: Beast = null
			var fd := 60.0
			for b: Beast in beasts.values():
				if b.alive() and b.temper != "elite":
					var d := nearest_player_pos(b.global_position).distance_to(b.global_position)
					if d > fd:
						fd = d
						far = b
			if far:
				beast_escaped(far, "despawn")


func _init_elites() -> void:
	# 精英的年份：第一、二章百年，第三章千年，第四、五章万年（第六~九魂环可以打王拿）
	var age: int = [1, 1, 2, 3, 3][clampi(chapter - 1, 0, 4)]
	for h in island.habitats:
		if elites.size() >= Data.ELITE_MAX:
			break
		var type := str(h["type"])
		if not Data.HABITATS.has(type) or island.is_water_habitat(type):
			continue
		var species := str(Data.HABITATS[type]["beast"])
		# 守在栖息地往岛中心那边一点，路过就能碰到
		var c: Vector2 = h["center"]
		var p := c + (-c).normalized() * minf(8.0, c.length() * 0.2)
		if not island.is_land(p.x, p.y):
			p = c
		if not island.is_land(p.x, p.y):
			continue
		elites[type] = {"species": species, "age": age, "pos": Vector3(p.x, island.height_at(p.x, p.y) + 0.6, p.y), "id": 0, "t": 0.0}


func _host_spawn_elite(key: String) -> void:
	var e: Dictionary = elites[key]
	var id := next_beast_id
	next_beast_id += 1
	e["id"] = id
	var pos: Vector3 = e["pos"]
	var affixes: Array = Data.roll_affixes(rng, int(e["age"]), chapter, "grass", true)
	_spawn_beast(id, str(e["species"]), int(e["age"]), pos, Vector3.ZERO, 1, false, "elite", affixes)
	Net.send(0, "bsp", [id, e["species"], e["age"], pos, Vector3.ZERO, 1, "elite", affixes])


## 魔狼 / 犀牛 咬到玩家（章节越后越疼，还带这一章的特点：毒 / 冰冻 / 拖拽）
func beast_bite(b: Beast, peer: int, dmg: float) -> void:
	dmg *= float(Data.CH_POWER.get(chapter, 1.0)) * Data.BEAST_DMG * Profile.rebirth_hard()
	var ch_trait := str(Data.CH_TRAIT.get(chapter, ""))
	if peer == Net.my_id:
		player.take_damage(dmg, b.global_position)
		_apply_trait(ch_trait, b.global_position, dmg)
	else:
		Net.send(peer, "dmg", [dmg, b.global_position, ch_trait])
	Sfx.play_at("bite_attack", b.global_position, 0.0, 0.1)


func _apply_trait(ch_trait: String, from: Vector3, dmg: float) -> void:
	if player.dead or Data.autotest:
		return
	match ch_trait:
		"poison":
			player.poison(maxf(dmg * 0.25, 2.0), 4.0)
		"frost":
			player.slow(0.45, 2.5)
			hud.toast("被冻住了，走不快", Color(0.6, 0.85, 1.0), 1.5)
		"drag":
			var to := from - player.global_position
			to.y = 0.0
			player.velocity += to.normalized() * 9.0 + Vector3.UP * 3.0
			hud.toast("被拖过去了！", Color(0.6, 0.8, 1.0), 1.2)


## 金刚猿扔石头
func beast_throw_rock(b: Beast, target: Vector3) -> void:
	var from := b.global_position + Vector3(0, 1.4 * Data.AGES[b.age]["scale"], 0)
	var dmg: float = float(Data.BEASTS[b.species].get("hurt", 12.0)) * (1.0 + b.age * 0.5) * float(Data.CH_POWER.get(chapter, 1.0)) * Data.BEAST_DMG
	_host_hazard("rock", from, target, 1.0, 2.2, dmg)


# ------------------------------------------------------------------ 魂兽的独门本事（Data.BEAST_SKILLS）

## 房主：魂兽开始前摇，告诉大家（地上出圈、头顶冒招式名）
func beast_telegraph(b: Beast, sk: Dictionary, at: Vector3) -> void:
	var center: Vector3 = b.global_position if str(sk["at"]) == "self" else at
	var msg := [b.id, b.species, center, float(sk["wind"]), float(sk["radius"]) * b.size_k]
	Net.send(0, "btel", msg)
	_on_btel(msg)


func _on_btel(msg: Array) -> void:
	var sk: Dictionary = Data.BEAST_SKILLS.get(str(msg[1]), {})
	if sk.is_empty():
		return
	var center: Vector3 = msg[2]
	var g: float = island.height_at(center.x, center.z)
	var ctrl := sk.has("root") or sk.has("blind") or sk.has("silence") or sk.has("slow") or sk.has("pull") or sk.has("vuln")
	var col := Color(0.75, 0.35, 1.0) if ctrl else Color(1.0, 0.25, 0.15)
	if not sk.has("howl"):
		var t := fx.telegraph(Vector3(center.x, maxf(g, Island.WATER_Y), center.z), float(msg[4]), float(msg[3]), col)
		get_tree().create_timer(float(msg[3]) + 0.1).timeout.connect(t.queue_free)
	var b: Beast = beasts.get(int(msg[0]))
	var at: Vector3 = b.global_position if b else center
	var l := U.label3d(str(sk["name"]) + "！", 56, col.lightened(0.3), 10)
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0011
	fx.add_child(l)
	l.global_position = at + Vector3(0, 2.6, 0)
	var tw := l.create_tween()
	tw.tween_property(l, "global_position:y", at.y + 3.4, float(msg[3]) + 0.4)
	tw.parallel().tween_property(l, "modulate:a", 0.0, float(msg[3]) + 0.4).set_ease(Tween.EASE_IN)
	tw.tween_callback(l.queue_free)
	Sfx.play_at("bite_attack", at, 2.0, 0.1, 0.6)


## 房主：前摇结束，圈里的人中招
func host_beast_special(b: Beast, sk: Dictionary, at: Vector3) -> void:
	var center: Vector3 = b.global_position if str(sk["at"]) == "self" else at
	var r := float(sk["radius"]) * b.size_k
	var base: float = float(Data.BEASTS[b.species].get("hurt", 8.0)) * (1.0 + b.age * 0.5) * (Data.ELITE_DMG if b.temper == "elite" else 1.0) * b._dmgk() * float(Data.CH_POWER.get(chapter, 1.0)) * Data.BEAST_DMG * Profile.rebirth_hard()
	var dmg := base * float(sk.get("dmg", 1.0))
	if sk.has("howl"):
		for o: Beast in beasts.values():
			if o.alive() and o.global_position.distance_to(b.global_position) < r:
				o.enrage_t = float(sk["howl"])
	var hit := 0
	for pl in alive_players():
		var p: Vector3 = pl["pos"]
		if Vector2(p.x - center.x, p.z - center.z).length() > r or absf(p.y - center.y) > r + 2.0:
			continue
		hit += 1
		var msg := [b.species, dmg, base, b.global_position]
		if int(pl["peer"]) == Net.my_id:
			_apply_beast_special(msg)
		else:
			Net.send(int(pl["peer"]), "bsk", msg)
	if hit > 0:
		if sk.has("heal"):
			b.hp = minf(b.hp + dmg * float(sk["heal"]) * hit, b.max_hp)
		if sk.has("steal"):
			b.reward_k += 0.5 * hit
	var fxm := [b.species, center, r]
	Net.send(0, "bskfx", fxm)
	_on_bskfx(fxm)


## 客人 / 自己：中了魂兽的招
func _apply_beast_special(msg: Array) -> void:
	var sk: Dictionary = Data.BEAST_SKILLS.get(str(msg[0]), {})
	if sk.is_empty() or player.dead:
		return
	if player.invuln_t > 0.0:
		hud.toast("躲开了%s！" % sk["name"], Color(0.6, 1.0, 0.7), 1.0)
		return
	var dmg := float(msg[1])
	var base := float(msg[2])
	var from: Vector3 = msg[3]
	if dmg > 0.0:
		player.take_damage(dmg, from)
	var away := player.global_position - from
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else -player.aim_dir()
	var txt := str(sk["name"])
	var col := Color(1.0, 0.6, 0.5)
	if sk.has("push"):
		player.velocity += away * float(sk["push"]) + Vector3.UP * float(sk["push"]) * 0.4
	if sk.has("pull"):
		player.velocity += -away * float(sk["pull"]) + Vector3.UP * 4.0
		txt += "：被拽过去了"
	if sk.has("root"):
		player.root(float(sk["root"]))
		txt += "：动不了（连按空格挣脱）"
		col = Color(0.8, 0.6, 1.0)
	if sk.has("slow"):
		player.slow(float(sk["slow"]), float(sk.get("dur", 2.0)))
		txt += "：走不快"
	if sk.has("blind"):
		hud.blind(float(sk["blind"]), Color(0.75, 0.8, 1.0) if msg[0] != "reeffish" else Color(1.0, 0.7, 0.9))
		txt += "：看不见了"
	if sk.has("vuln"):
		player.vuln_t = maxf(player.vuln_t, float(sk["vuln"]))
		txt += "：被盯上了，受到伤害 +30%"
		col = Color(0.6, 0.8, 1.0)
	if sk.has("silence"):
		player.silence_t = maxf(player.silence_t, float(sk["silence"]))
		txt += "：电麻了，放不了魂技"
		col = Color(0.5, 0.8, 1.0)
	if sk.has("poison"):
		player.poison(maxf(base * float(sk["poison"]), 2.0), float(sk.get("dur", 4.0)))
	if sk.has("bleed"):
		player.poison(maxf(base * float(sk["bleed"]), 2.0), float(sk.get("dur", 4.0)))
		txt += "：流血了"
	if sk.has("shield") and player.shield > 0.0:
		player.shield = 0.0
		txt += "：护盾被打碎"
	if sk.has("steal"):
		var n := mini(int(Profile.money * float(sk["steal"])), int(float(Data.CH_MONEY.get(chapter, 12.0)) * 8.0))
		if n > 0:
			Profile.add_money(-n)
			txt += "：叼走了 %d 金魂币（打下它能多拿回来）" % n
			col = UiKit.GOLD
	hud.toast(txt, col, 1.8)


func _on_bskfx(msg: Array) -> void:
	var sk: Dictionary = Data.BEAST_SKILLS.get(str(msg[0]), {})
	var c: Vector3 = msg[1]
	var r := float(msg[2])
	if sk.is_empty():
		return
	if sk.has("howl"):
		fx.aura_burst(c, Color(1.0, 0.4, 0.3), r * 0.3)
		Sfx.play_at("boss_roar", c, -4.0, 0.1, 1.6)
		return
	if sk.has("root"):
		fx.vines(c, r, Color(0.6, 0.4, 1.0) if msg[0] != "icedeer" else Color(0.6, 0.9, 1.0))
	elif sk.has("blind"):
		fx._burst(c + Vector3.UP, Vector3.UP, Color(0.8, 0.85, 1.0, 0.9) if msg[0] == "moth" else Color(1.0, 0.6, 0.9, 0.9), 70, 5.0, 1.2, 3.0, true, -1.0, 180.0)
	elif sk.has("silence"):
		fx.vortex(c, r, Color(0.4, 0.7, 1.0))
	elif sk.has("poison") or sk.has("bleed"):
		var pool := fx.poison_pool(c, r * 0.8)
		get_tree().create_timer(3.0).timeout.connect(pool.queue_free)
	elif msg[0] == "spiderling":
		fx.web_burst(c)
	else:
		fx.slam(c, r)
	Sfx.play_at("skill_launch", c, -2.0, 0.1)


var _streak := 0
var _streak_at := -99.0


func _on_kill(msg: Array) -> void:
	var id := int(msg[0])
	var killer := int(msg[1])
	var species := str(msg[2])
	var age := int(msg[3])
	var pos: Vector3 = msg[4]
	var tags: Array = msg[5]
	var rewards: Dictionary = msg[6]
	var st := _stat(killer)
	st["kills"] = int(msg[7])
	st["earned"] = int(msg[8])
	var b: Beast = beasts.get(id)
	if b:
		# 尸体摔到地上、播完死亡动画再化成魂光（Beast.die）
		pos = b.global_position
		beasts.erase(id)
		b.die()
		fx.impact_beast(pos + Vector3(0, 0.3, 0), Vector3.UP, Data.age_color(age), true)
	else:
		fx.death_burst(pos, Data.age_color(age), age)
	if age >= 2:
		Sfx.play_at("kill_burst", pos, -6.0, 0.08)
	var mine: Array = rewards.get(Net.my_id, rewards.get(str(Net.my_id), [0, 0]))
	var who := peer_name(killer)
	if killer == Net.my_id:
		_ach_kill(tags, msg[9] if msg.size() > 9 else [], bool(msg[10]) if msg.size() > 10 else false)
		_check_bounty(species, age, msg[9] if msg.size() > 9 else [])
		_codex_kill(species, age, msg[9] if msg.size() > 9 else [], bool(msg[10]) if msg.size() > 10 else false)
	hud.feed("%s 击杀 %s·%s" % [who, Data.age_name(age), Data.BEASTS[species]["name"]], Data.age_color(age))
	_gain(int(mine[0]), int(mine[1]))
	if killer == Net.my_id:
		Profile.kills += 1
		hud.hitmarker(false, true)
		# 连杀：5 秒内接着杀，每多一只多 15% 金魂币（最多 +75%）
		var now := Time.get_ticks_msec() / 1000.0
		_streak = _streak + 1 if now - _streak_at < 5.0 else 1
		_streak_at = now
		var bonus := int(float(mine[0]) * 0.15 * mini(_streak - 1, 5))
		if bonus > 0:
			Profile.add_money(bonus)
			tags = tags.duplicate()
			tags.append("%s  +%d 金魂币" % [["", "", "双杀", "三连杀", "四连杀", "五连杀"][mini(_streak, 5)] if _streak <= 5 else "%d 连杀！" % _streak, bonus])
		hud.kill_popup(int(mine[0]) + bonus, int(mine[1]), tags, species, age)
		Sfx.play("kill", -9.0, 0.12)
		Sfx.play("coin", -4.0, 0.03)


## 炼化魂环精华：相当于打死 4 只这种魂兽的修为
func _gain_essence(age: int, species: String) -> void:
	var xp := int(Data.kill_xp(species, age) * 4.0)
	fx.absorb(player, Data.age_color(age))
	Sfx.play("absorb", -6.0, 0.0, 1.3)
	hud.toast("炼化了%s魂环精华：修为 +%d" % [Data.age_name(age), xp], Data.AGES[age]["glow"], 2.0)
	_gain(0, xp)


## 自己拿到金魂币和修为
func _gain(money: int, xp: int) -> void:
	if money > 0:
		Profile.add_money(money)
	if xp > 0:
		var was_cap := Profile.at_bottleneck()
		var ups := Profile.add_xp(xp)
		if ups > 0:
			hud.level_up(Profile.level)
			Sfx.play("level_up", -2.0)
			player.hp = Profile.max_hp()
			fx.level_up_burst(player.global_position, Profile.rings.size())
			_broadcast_prog()
			_check_god()
		if Profile.at_bottleneck() and not was_cap:
			hud.toast("到瓶颈了！猎杀魂兽，吸收第%d魂环才能继续修炼（至少%s）" % [Profile.rings.size() + 1, Data.age_name(Data.RING_MIN_AGE[Profile.rings.size()])], Color(1.0, 0.85, 0.4), 6.0)


func _on_escape(msg: Array) -> void:
	var id := int(msg[0])
	var reason := str(msg[1])
	var b: Beast = beasts.get(id)
	if not b:
		return
	var nm: String = Data.BEASTS[b.species]["name"]
	var pos := b.global_position
	_remove_beast(b)
	match reason:
		"splash":
			fx.splash(pos, true)
			Sfx.play_at("splash_big", pos, -2.0)
			hud.feed("%s 逃回了水里" % nm, Color(0.7, 0.7, 0.7))
		"burrow":
			fx.dirt_puff(pos)
			hud.feed("%s 逃回了窝里" % nm, Color(0.7, 0.7, 0.7))
		"despawn":
			pass
		"fly":
			fx.poof(pos)
			hud.feed("%s 飞走了" % nm, Color(0.7, 0.7, 0.7))
		_:
			fx.poof(pos)
			hud.feed("%s 逃走了" % nm, Color(0.7, 0.7, 0.7))


func _remove_beast(b: Beast) -> void:
	b.state = Beast.State.GONE
	beasts.erase(b.id)
	b.queue_free()


# ------------------------------------------------------------------ 魂环

## 魂环只在有人用得上的时候才掉：有人卡在瓶颈、这只魂兽的年份也够。
## 地上已经有够多没人吸收的魂环就不掉了（不会掉一地没用的魂环）
func _host_maybe_drop_ring(b: Beast, killer: int) -> void:
	# 打的人卡在瓶颈、但这只年份不够：告诉他要什么年份（免得以为魂环不掉）
	var kinfo: Dictionary = peer_info.get(killer, {})
	var knr: int = (kinfo.get("rings", []) as Array).size()
	var klv := int(kinfo.get("level", 1))
	if knr < Data.MAX_RINGS and klv >= (knr + 1) * 10 and b.age < int(Data.RING_MIN_AGE[knr]):
		var tip := "这只年份不够，不掉魂环：第%s魂环要%s以上的魂兽（换血腥饵 / 魂晶饵钓，或者打王、打 Boss）" % [Data.RING_NAMES[knr], Data.age_name(int(Data.RING_MIN_AGE[knr]))]
		if killer == Net.my_id:
			hud.toast(tip, Color(1.0, 0.8, 0.5), 4.0)
		else:
			Net.send(killer, "hint", [tip])
	var need := 0
	var killer_needs := false
	for id in peer_info:
		var info: Dictionary = peer_info[id]
		var lv := int(info.get("level", 1))
		var nr: int = (info.get("rings", []) as Array).size()
		if nr < Data.MAX_RINGS and lv >= (nr + 1) * 10 and b.age >= int(Data.RING_MIN_AGE[nr]):
			need += 1
			if int(id) == killer:
				killer_needs = true
	if need > rings.size() and (killer_needs or rng.randf() < 0.6):
		_host_drop_ring(b.global_position + Vector3(0, 1.0, 0), b.age, b.species)
		return
	# 没人要的魂环也按年份概率掉（十年 25% … 十万年 100% 的一半），30 秒后散掉；
	# 走过去按 F 能炼化魂环精华，涨一截修为
	if rings.size() < 6 and rng.randf() < float(Data.AGES[b.age]["ring_drop"]) * 0.5:
		_host_drop_ring(b.global_position + Vector3(0, 1.0, 0), b.age, b.species, 30.0)


func _host_drop_ring(pos: Vector3, age: int, species: String, life := 90.0) -> void:
	# 魂兽多半死在半空：魂环落到地面上方一人高，走过去就能吸收
	# 掉进水里的：浅水沉到水底（潜下去拿，注意憋气），深水冲到最近的岸边
	var g := island.height_at(pos.x, pos.z)
	if island.is_land(pos.x, pos.z):
		pos.y = g + 1.2
	elif g > Island.WATER_Y - 6.0:
		pos.y = g + 1.0
	else:
		var best := pos
		var bd := INF
		for i in 32:
			var a := TAU * i / 32.0
			for r in [6.0, 12.0, 18.0, 26.0, 36.0, 50.0]:
				var q := pos + Vector3(cos(a) * r, 0, sin(a) * r)
				if island.is_land(q.x, q.z) and r < bd:
					bd = r
					best = q
		pos = Vector3(best.x, island.height_at(best.x, best.z) + 1.2, best.z)
	var rid := next_ring_id
	next_ring_id += 1
	var msg := [rid, pos, age, species, life]
	Net.send(0, "ring", msg)
	_on_ring(msg)


func _on_ring(msg: Array) -> void:
	var rid := int(msg[0])
	var pos: Vector3 = msg[1]
	var age := int(msg[2])
	var node := fx.soul_ring(pos, Data.age_color(age))
	var life := float(msg[4]) if msg.size() > 4 else 90.0
	rings[rid] = {"pos": pos, "age": age, "species": str(msg[3]), "node": node, "t": 0.0, "life": life}
	if Profile.can_absorb(age) == "":
		hud.feed("掉落了%s魂环！走过去按 F 吸收" % Data.age_name(age), Data.age_color(age))
	Sfx.play_at("ring_drop", pos, 0.0)


func _host_rings(dt: float) -> void:
	for rid in rings.keys():
		rings[rid]["t"] += dt
		if rings[rid]["t"] > float(rings[rid].get("life", 90.0)):
			Net.send(0, "ringgone", [rid, 0])
			_on_ring_gone([rid, 0])


func _on_ring_gone(msg: Array) -> void:
	var rid := int(msg[0])
	if rings.has(rid):
		var n: Node3D = rings[rid]["node"]
		if is_instance_valid(n):
			n.queue_free()
		rings.erase(rid)


func _update_rings_visual(dt: float) -> void:
	for rid in rings:
		var n: Node3D = rings[rid]["node"]
		if is_instance_valid(n):
			n.rotation.y += dt * 1.5
			n.position.y = rings[rid]["pos"].y + sin(_t * 2.0 + rid) * 0.15


func _start_absorb(age: int, species: String) -> void:
	player.busy_t = 3.0
	hud.absorb_start(age, species)
	fx.absorb(player, Data.age_color(age))
	Sfx.play("absorb", -2.0)
	# 魂技由武魂 + 魂兽 + 年份决定，吸收完才揭晓
	get_tree().create_timer(3.0).timeout.connect(func(): _reveal_skill(age, species))


func _reveal_skill(age: int, species: String) -> void:
	var owned: Array = []
	for r in Profile.rings:
		owned.append(str(r["skill"]))
	var sid := Data.skill_for(Data.wuhun_id(Settings.wuhun), species, age, owned)
	finish_absorb(age, species, sid)
	var s: Dictionary = Data.SKILLS[sid]
	var key := "按 K 把它装到 Q / E / F"
	var slot := Profile.skill_slots.find(Profile.rings.size() - 1)
	if slot >= 0:
		key = "已经装在 %s 键上（K 面板里可以换）" % ["Q", "E", "F"][slot]
	hud._show_banner("领悟魂技 · %s" % s["name"], "%s\n%s" % [s["desc"], key], Data.AGES[age]["glow"], 6.0)


## 界面选好魂技后调用
func finish_absorb(age: int, species: String, sid: String) -> void:
	Profile.add_ring(age, sid, species)
	var ups := Profile.add_xp(0)
	player.soul = Profile.max_soul()
	player.hp = Profile.max_hp()
	skills.current = Profile.rings.size() - 1
	# 大提升：魂环突破，全屏一闪，魂环从脚下升起
	fx.ring_breakthrough(player.global_position, Data.age_color(age), Profile.rings.size())
	player.trauma = 0.7
	player.hud_flash(Data.age_color(age))
	hud.toast("吸收了%s魂环！获得魂技【%s】" % [Data.age_name(age), Data.SKILLS[sid]["name"]], Data.AGES[age]["glow"], 6.0)
	Sfx.play("level_up", -2.0)
	_broadcast_prog()
	_check_god()
	_ach_check()
	if ups > 0:
		hud.level_up(Profile.level)


# ------------------------------------------------------------------ 交互（F）

## act = true：按 F 真的会做点什么（开店、召唤、上船、吸收、救人）；false 的只显示说明，F 照样放第三个魂技
func interactables() -> Array:
	var out := [
		{"id": "shop", "pos": builder.shop_door, "r": 3.5, "text": "按 F 打开唐门暗器铺", "act": true},
		{"id": "altar", "pos": island.altar_pos + Vector3(0, 1, 0), "r": 3.5, "text": _altar_text(), "act": _can_summon()},
		{"id": "boat", "pos": builder.boat_pos + Vector3(0, 1.0, 0), "r": 4.2, "text": _boat_text(), "act": not boat_destinations().is_empty()},
	]
	for id in remotes:
		var rp: RemotePlayer = remotes[id]
		if rp.is_dead() and not player.dead:
			out.append({"id": "revive", "peer": id, "pos": rp.global_position + Vector3(0, 0.6, 0), "r": 2.6, "text": "按住 F 把 %s 拉起来" % peer_name(id), "act": true})
	for rid in rings:
		var r: Dictionary = rings[rid]
		var why := Profile.can_absorb(int(r["age"]))
		var t := "按 F 吸收%s魂环（%s）" % [Data.age_name(int(r["age"])), Data.BEASTS[r["species"]]["name"]] if why == "" else "%s魂环：%s" % [Data.age_name(int(r["age"])), why]
		var ess := why != "" and not Profile.at_bottleneck()
		if ess:
			t = "按 F 炼化%s魂环精华（+修为）" % Data.age_name(int(r["age"]))
		out.append({"id": "ring", "rid": rid, "pos": r["pos"], "r": 2.6, "text": t, "ok": why == "", "act": why == "" or ess, "essence": ess})
	return out


## Boss 打赢过了（主线到了坐船 / 成神）
func boss_cleared() -> bool:
	return str(_cur_quest().get("type", "")) in ["boat", "god"] or quest_idx >= (Data.CHAPTERS[chapter]["quests"] as Array).size()


var _altar_cd := 0.0


func _can_summon() -> bool:
	if boss:
		return false
	var t := str(_cur_quest().get("type", ""))
	return t == "altar" or (boss_cleared() and _altar_cd <= 0.0)


## 渡船能去哪：Boss 打赢了可以去下一章；以前去过的岛随时能回去
func boat_destinations() -> Array:
	var out: Array = []
	var nxt := int(Data.CHAPTERS[chapter].get("next", 0))
	for c in range(1, Data.CHAPTERS.size() + 1):
		if c == chapter:
			continue
		if c <= Profile.max_chapter or (c == nxt and boss_cleared()):
			out.append(c)
	return out


func _cur_quest() -> Dictionary:
	return Data.quest(chapter, quest_idx)


func _altar_text() -> String:
	if boss:
		return "祭坛（Boss 已经出现了）"
	if _cur_quest().get("type", "") == "altar":
		return "按 F 点燃祭坛，召唤 Boss"
	if boss_cleared():
		if _altar_cd > 0.0:
			return "祭坛：%d 秒后可以再次召唤 Boss" % ceili(_altar_cd)
		return "按 F 再次召唤 Boss（刷魂骨、魂环）"
	return "祭坛：修炼到 %d 级才能召唤 Boss（现在 %d 级）" % [int(Data.CHAPTERS[chapter]["boss_level"]), Profile.level]


func _boat_text() -> String:
	if boat_destinations().is_empty():
		return "渡船：打败这里的 Boss 之后才能去下一个岛"
	if _i_boarded:
		return "你已经上船了（%d/%d），等其他人都按 F" % [_boat_count[0], _boat_count[1]]
	return "按 F 上船选目的地（人齐了一起出发，已上船 %d/%d）" % [_boat_count[0], maxi(_boat_count[1], _all_peers().size())]


func nearest_interactable() -> Dictionary:
	var best := {}
	var bd := INF
	for it in interactables():
		var d: float = (it["pos"] as Vector3).distance_to(player.global_position + Vector3(0, 1, 0))
		if d < float(it["r"]) and d < bd:
			bd = d
			best = it
	return best


func interact() -> void:
	var it := nearest_interactable()
	if it.is_empty():
		return
	match str(it["id"]):
		"shop":
			hud.open_shop()
		"altar":
			if _can_summon():
				Net.send_host("altar", [])
			else:
				hud.toast(_altar_text(), Color(0.9, 0.9, 0.9))
		"boat":
			var ds := boat_destinations()
			if ds.is_empty():
				hud.toast(_boat_text(), Color(0.9, 0.9, 0.9))
			else:
				hud.open_boat_picker(ds)
		"ring":
			if it.get("ok", false):
				Net.send_host("absorb", [it["rid"]])
			elif it.get("essence", false):
				Net.send_host("essence", [it["rid"]])
			else:
				hud.toast(str(it["text"]), Color(1, 0.8, 0.6), 4.0)


# ------------------------------------------------------------------ 商店回调

func on_bought_weapon(id: String) -> void:
	player.rebuild_guns()
	for i in player.guns.size():
		if player.guns[i].id == id:
			player.switch_weapon(i)
	Net.send_host("qev", ["buy", 1])


func on_sold_weapon(_id: String) -> void:
	player.rebuild_guns()
	_broadcast_prog()


func on_attach_changed() -> void:
	player.rebuild_guns()
	player.viewmodel.apply_look()


func on_upgraded(_id: String) -> void:
	player.rebuild_guns()
	Net.send_host("qev", ["upgrade", 1])


# ------------------------------------------------------------------ 任务（房主推进）

func _host_quest_event(type: String, n: int, arg := "") -> void:
	if not Net.is_host():
		return
	var q := _cur_quest()
	if q.is_empty() or q["type"] != type:
		return
	if type == "hunt" and str(q.get("species", "")) != arg:
		return
	quest_count += n
	_host_check_quest()


func _host_check_quest() -> void:
	if not Net.is_host():
		return
	var q := _cur_quest()
	if q.is_empty():
		return
	var done := false
	quest_target = Data.quest_target(q, maxi(peer_info.size(), 1))
	match str(q["type"]):
		"kill", "buy", "altar", "boss", "hunt", "upgrade":
			done = quest_count >= quest_target
		"level":
			var mx := 0
			for id in peer_info:
				mx = maxi(mx, int(peer_info[id].get("level", 1)))
			quest_count = mx
			done = mx >= int(q["n"])
		"rings":
			var mx := 0
			for id in peer_info:
				mx = maxi(mx, (peer_info[id].get("rings", []) as Array).size())
			quest_count = mx
			done = mx >= int(q["n"])
		"end":
			done = false
	if done:
		var msg := [chapter, quest_idx, int(q.get("reward", 0))]
		Net.send(0, "qdone", msg)
		_on_quest_done(msg)
		quest_idx += 1
		quest_count = 0
		_host_check_quest()
	_host_sync_quest()


func _host_sync_quest() -> void:
	Profile.chapter = chapter
	Profile.quest = quest_idx
	Profile.quest_count = quest_count
	Profile.mark_dirty()
	Net.send(0, "quest", [chapter, quest_idx, quest_count, quest_target])
	hud.update_quest()


func _on_quest_done(msg: Array) -> void:
	var q := Data.quest(int(msg[0]), int(msg[1]))
	var reward := int(msg[2])
	if reward > 0:
		Profile.add_money(reward)
	hud.quest_done(str(q.get("text", "")), reward)
	Sfx.play("quest_done", -2.0)


func _broadcast_prog() -> void:
	peer_info[Net.my_id] = _my_info()
	var p := [Profile.level, _ring_summary(), Profile.outfit, Profile.skin]
	if p == _last_prog:
		return
	_last_prog = p
	Net.send(0, "prog", p)
	if Net.is_host():
		_host_check_quest()


func _on_profile_changed() -> void:
	hud.update_quest()


# ------------------------------------------------------------------ Boss

var boss_tier := 0
var _boss_k := 1.0


func _host_spawn_boss() -> void:
	var kind := str(Data.CHAPTERS[chapter]["boss"])
	var n := _all_peers().size()
	# 打赢过的 Boss 再召唤：二重、三重……血更厚、招更狠、奖励更高
	var tier := int(Profile.boss_tier.get(kind, 0))
	var hp: float = float(Data.BOSSES[kind]["hp"]) * (1.0 + 0.6 * (n - 1)) * (1.0 + 0.7 * tier) * Profile.rebirth_hard()
	var anchor := island.boss_pos
	var msg := [kind, hp, anchor, tier]
	Net.send(0, "bossspawn", msg)
	_on_boss_spawn(msg)


func _on_boss_spawn(msg: Array) -> void:
	if boss:
		return
	boss = Boss.new()
	add_child(boss)
	boss.setup(self, str(msg[0]), float(msg[1]), not Net.is_host(), msg[2])
	boss_tier = int(msg[3]) if msg.size() > 3 else 0
	_boss_k = (1.0 + 0.25 * boss_tier) * Profile.rebirth_hard()
	var bname := str(Data.BOSSES[msg[0]]["name"]) + ((" · %s重" % ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"][mini(boss_tier, 9)]) if boss_tier > 0 else "")
	hud.boss_bar(bname)
	hud.boss_intro(bname)
	Sfx.play("boss_roar", 2.0)
	if str(Data.BOSSES[msg[0]].get("ai", "")) == "water":
		fx.splash(msg[2], true)
	player.trauma = 0.8


func boss_phase2() -> void:
	Net.send(0, "bphase", [])
	_on_boss_phase2()


func _on_boss_phase2() -> void:
	hud.toast("Boss 暴怒了！攻击更快", Color(1, 0.4, 0.3), 4.0)
	Sfx.play("boss_roar", 3.0, 0.0, 0.85)


func boss_summon(b: Boss, species: String, n: int) -> void:
	for i in n:
		var tp := nearest_player(b.center())
		var tpos: Vector3 = tp["pos"] if not tp.is_empty() else player.global_position
		_host_spawn(1, b.center() + Vector3(randf_range(-3, 3), -2.0, randf_range(-3, 3)), species, 1, tpos, "fierce")


func boss_died(b: Boss) -> void:
	var kind := b.kind
	var d: Dictionary = Data.BOSSES[kind]
	var rewards := {}
	for peer in _all_peers():
		rewards[peer] = [int(d["reward"]), int(d["xp"])]
	var msg := [kind, rewards]
	Net.send(0, "bossdead", msg)
	_on_boss_dead(msg)
	for i in _all_peers().size():
		_host_drop_ring(b.center() + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)), int(d["age"]), str(d.get("ring_beast", "wolf")))
	_host_quest_event("boss", 1)
	_altar_cd = 180.0


func _on_boss_dead(msg: Array) -> void:
	var kind := str(msg[0])
	var d: Dictionary = Data.BOSSES[kind]
	var rewards: Dictionary = msg[1]
	var mine: Array = rewards.get(Net.my_id, [0, 0])
	if boss:
		# 神圣的陨落：天上打下光柱，金光冲天，一圈圈冲击波
		var bp: Vector3 = boss.center()
		var holy: Color = d.get("holy", Color(1.0, 0.86, 0.45))
		fx.ring_breakthrough(bp, holy, 0)
		fx.skill_flourish(bp, holy, 6, 10.0)
		player.trauma = minf(player.trauma + 0.6, 1.0)
		boss.die_visual()     # 播死亡动画、摔下来，自己炸掉
		boss = null
	hud.boss_bar("")
	# 重数越高奖励越多（每重 +60%），下次召唤再加一重
	var tier_k := 1.0 + 0.6 * boss_tier
	_gain(int(float(mine[0]) * tier_k), int(float(mine[1]) * tier_k))
	Profile.count("boss_" + kind)
	Profile.boss_tier[kind] = maxi(int(Profile.boss_tier.get(kind, 0)), boss_tier + 1)
	Profile.mark_dirty()
	# 魂骨：每人拿一块自己还没有的
	# 每章 Boss 送一款专属外观
	for sid in Data.GUN_SKINS:
		if str(Data.GUN_SKINS[sid].get("boss", "")) == kind and Profile.unlock_look("skin", sid):
			hud.feed("解锁了暗器皮肤【%s】（暗器铺 → 外观）" % Data.GUN_SKINS[sid]["name"], UiKit.GOLD)
	for oid in Data.OUTFITS:
		if str(Data.OUTFITS[oid].get("boss", "")) == kind and Profile.unlock_look("outfit", oid):
			hud.feed("解锁了装扮【%s】（暗器铺 → 外观）" % Data.OUTFITS[oid]["name"], UiKit.GOLD)
	var got := ""
	var bone_age := mini(int(d["age"]) + boss_tier / 2, 4)    # 二重、三重掉的魂骨年份更高
	for bid in d["bones"]:
		if Profile.add_bone("%s@%d" % [str(bid), bone_age], true):
			got = "%s@%d" % [str(bid), bone_age]
			player.on_bones_changed()
			break
	hud.boss_defeated(str(d["name"]), int(mine[0]), got)
	Sfx.play("quest_done", 0.0)
	player.rebuild_guns()


# ------------------------------------------------------------------ 危险物：毒液、蛛网、石头、红圈

func boss_projectile(kind: String, from: Vector3, to: Vector3, flight: float, radius: float, dmg: float) -> void:
	_host_hazard(kind, from, to, flight, radius, dmg * float(Data.CH_POWER.get(chapter, 1.0)) * _boss_k)


func _host_hazard(kind: String, from: Vector3, to: Vector3, flight: float, radius: float, dmg: float) -> void:
	var g := island.height_at(to.x, to.z)
	to.y = maxf(g, Island.WATER_Y)
	var msg := [kind, from, to, flight, radius, dmg]
	Net.send(0, "hz", msg)
	_on_hazard(msg)


func _on_hazard(msg: Array) -> void:
	var kind := str(msg[0])
	var col := Color(0.6, 1.0, 0.3) if kind == "spit" else (Color(0.9, 0.9, 0.95) if kind == "web" else Color(0.5, 0.42, 0.35))
	var node := fx.hazard_ball(kind, col)
	_hazards.append({"kind": kind, "from": msg[1], "to": msg[2], "flight": float(msg[3]), "radius": float(msg[4]), "dmg": float(msg[5]), "t": 0.0, "node": node})
	Sfx.play_at("spit" if kind != "rock" else "throw", msg[1], 0.0, 0.1)


## late = true：红圈只在砸下来前 0.35 秒才出现（要看 Boss 起手、听声音判断，翻滚躲）
func boss_telegraph(center: Vector3, radius: float, delay: float, dmg: float, kind: String, _src: Vector3, late := false) -> void:
	center.y = maxf(island.height_at(center.x, center.z), Island.WATER_Y)
	dmg *= float(Data.CH_POWER.get(chapter, 1.0))
	var msg := [center, radius, delay, dmg, kind, late]
	Net.send(0, "tg", msg)
	_on_telegraph(msg)


func _on_telegraph(msg: Array) -> void:
	var late := msg.size() > 5 and bool(msg[5]) and float(msg[2]) > 0.45
	var e := {"center": msg[0], "radius": float(msg[1]), "t": float(msg[2]), "dmg": float(msg[3]), "kind": str(msg[4]), "node": null}
	if late:
		Sfx.play_at("boss_roar", msg[0], -6.0, 0.05, 1.5)
		get_tree().create_timer(float(msg[2]) - 0.35).timeout.connect(func():
			if _telegraphs.has(e):
				e["node"] = fx.telegraph(e["center"], e["radius"], 0.35))
	else:
		e["node"] = fx.telegraph(msg[0], float(msg[1]), float(msg[2]))
	_telegraphs.append(e)


# ------------------------------------------------------------------ Boss 的新招式：冲击环、扇形横扫、全场大招（留安全区）

var _waves: Array = []
var _cones: Array = []
var _zones: Array = []


## 冲击环：从中心往外扩的一圈红墙，贴地的人被扫到。跳过去或者翻滚穿过去
func boss_shockwave(center: Vector3, max_r: float, speed: float, dmg: float) -> void:
	center.y = maxf(island.height_at(center.x, center.z), Island.WATER_Y)
	var msg := [center, max_r, speed, dmg * float(Data.CH_POWER.get(chapter, 1.0)) * _boss_k]
	Net.send(0, "sw", msg)
	_on_shockwave(msg)


func _on_shockwave(msg: Array) -> void:
	var n := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.9
	cm.cap_top = false
	cm.cap_bottom = false
	cm.radial_segments = 64
	n.mesh = cm
	n.material_override = U.glow(Color(1.0, 0.35, 0.15), 3.0, true)
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.add_child(n)
	n.global_position = (msg[0] as Vector3) + Vector3(0, 0.45, 0)
	_waves.append({"c": msg[0], "r": 0.5, "max": float(msg[1]), "spd": float(msg[2]), "dmg": float(msg[3]), "hit": false, "node": n})
	Sfx.play_at("slam", msg[0], 4.0)


## 扇形横扫：地上先出扇形，一会儿后扇形里的人挨打
func boss_cone(origin: Vector3, dir: Vector3, half: float, reach: float, delay: float, dmg: float) -> void:
	origin.y = maxf(island.height_at(origin.x, origin.z), Island.WATER_Y)
	var msg := [origin, Vector3(dir.x, 0, dir.z).normalized(), half, reach, delay, dmg * float(Data.CH_POWER.get(chapter, 1.0)) * _boss_k]
	Net.send(0, "cone", msg)
	_on_cone(msg)


func _on_cone(msg: Array) -> void:
	var o: Vector3 = msg[0]
	var d: Vector3 = msg[1]
	var half := float(msg[2])
	var reach := float(msg[3])
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 18
	var base := atan2(d.x, d.z)
	for i in seg:
		var a0 := base - half + 2.0 * half * i / seg
		var a1 := base - half + 2.0 * half * (i + 1) / seg
		im.surface_add_vertex(Vector3.ZERO)
		im.surface_add_vertex(Vector3(sin(a0), 0, cos(a0)) * reach)
		im.surface_add_vertex(Vector3(sin(a1), 0, cos(a1)) * reach)
	im.surface_end()
	var n := MeshInstance3D.new()
	n.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.2, 0.1, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	n.material_override = m
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.add_child(n)
	n.global_position = o + Vector3(0, 0.15, 0)
	_cones.append({"o": o, "d": d, "half": half, "reach": reach, "t": float(msg[4]), "dmg": float(msg[5]), "node": n})


## 全场大招：一大片都会被砸，只有几个绿圈安全（翻滚也躲不掉，要跑进绿圈）
func boss_ultimate(center: Vector3, radius: float, safes: Array, delay: float, dmg: float) -> void:
	var msg := [center, radius, safes, delay, dmg * float(Data.CH_POWER.get(chapter, 1.0)) * _boss_k]
	Net.send(0, "ult", msg)
	_on_ultimate(msg)


func _on_ultimate(msg: Array) -> void:
	var nodes: Array = [fx.telegraph(msg[0], float(msg[1]), float(msg[3]))]
	for s in msg[2]:
		nodes.append(fx.telegraph(s, 5.0, 0.3, Color(0.3, 1.0, 0.4)))
	_zones.append({"c": msg[0], "r": float(msg[1]), "safes": msg[2], "t": float(msg[3]), "dmg": float(msg[4]), "nodes": nodes})
	hud._show_banner("躲进绿圈！", "Boss 要砸整片地了", Color(0.5, 1.0, 0.5), float(msg[3]))
	Sfx.play("boss_roar", 3.0, 0.0, 0.7)
	player.trauma = minf(player.trauma + 0.6, 1.0)


func _update_boss_moves(dt: float) -> void:
	var me := player.global_position
	var my_ground: float = island.height_at(me.x, me.z)
	for w in _waves.duplicate():
		w["r"] = float(w["r"]) + float(w["spd"]) * dt
		var n: MeshInstance3D = w["node"]
		if is_instance_valid(n):
			n.scale = Vector3(w["r"], 1.0, w["r"])
		var c: Vector3 = w["c"]
		var d := Vector2(me.x - c.x, me.z - c.z).length()
		if not w["hit"] and not player.dead and absf(d - float(w["r"])) < 0.9 and me.y - maxf(my_ground, Island.WATER_Y) < 0.7:
			w["hit"] = true
			player.take_damage(float(w["dmg"]), c)
			var push := Vector3(me.x - c.x, 0, me.z - c.z).normalized()
			player.velocity += push * 7.0 + Vector3.UP * 5.0
		if float(w["r"]) > float(w["max"]):
			_waves.erase(w)
			if is_instance_valid(n):
				n.queue_free()
	for cn in _cones.duplicate():
		cn["t"] = float(cn["t"]) - dt
		if float(cn["t"]) <= 0.0:
			_cones.erase(cn)
			var n2: MeshInstance3D = cn["node"]
			if is_instance_valid(n2):
				n2.queue_free()
			var o: Vector3 = cn["o"]
			var to := Vector3(me.x - o.x, 0, me.z - o.z)
			fx.shockwave(o + (cn["d"] as Vector3) * float(cn["reach"]) * 0.5, float(cn["reach"]) * 0.5, Color(1.0, 0.4, 0.2))
			Sfx.play_at("slam", o, 0.0, 0.1, 1.2)
			if to.length() < float(cn["reach"]) and to.normalized().angle_to(cn["d"]) < float(cn["half"]) and absf(me.y - o.y) < 3.5:
				player.take_damage(float(cn["dmg"]), o)
				player.velocity += to.normalized() * 6.0 + Vector3.UP * 3.0
	for z in _zones.duplicate():
		z["t"] = float(z["t"]) - dt
		if float(z["t"]) <= 0.0:
			_zones.erase(z)
			for nd in z["nodes"]:
				if is_instance_valid(nd):
					(nd as Node).queue_free()
			var c2: Vector3 = z["c"]
			fx.explosion(c2 + Vector3.UP, 12.0, Color(1.0, 0.5, 0.3))
			Sfx.play_at("boom", c2, 6.0)
			player.trauma = 1.0
			var safe := false
			for s in z["safes"]:
				if Vector2(me.x - (s as Vector3).x, me.z - (s as Vector3).z).length() < 5.8:
					safe = true
			if not safe and Vector2(me.x - c2.x, me.z - c2.z).length() < float(z["r"]) and not player.dead:
				var inv := player.invuln_t
				player.invuln_t = 0.0
				player.take_damage(float(z["dmg"]), c2)
				player.invuln_t = inv


func _update_hazards(dt: float) -> void:
	var me := player.global_position
	for h in _hazards.duplicate():
		h["t"] += dt
		var k := clampf(h["t"] / h["flight"], 0.0, 1.0)
		var p: Vector3 = (h["from"] as Vector3).lerp(h["to"], k)
		p.y += sin(k * PI) * 6.0
		var n: Node3D = h["node"]
		if is_instance_valid(n):
			n.global_position = p
		if k >= 1.0:
			_hazards.erase(h)
			if is_instance_valid(n):
				n.queue_free()
			var at: Vector3 = h["to"]
			var inside := Vector2(me.x - at.x, me.z - at.z).length() < float(h["radius"]) and absf(me.y - at.y) < 3.0
			match str(h["kind"]):
				"spit":
					_pools.append({"pos": at, "radius": float(h["radius"]), "t": 5.0, "dps": float(h["dmg"]), "node": fx.poison_pool(at, float(h["radius"]))})
					Sfx.play_at("splash_small", at, 0.0)
				"web":
					fx.web_burst(at)
					if inside:
						player.take_damage(float(h["dmg"]), at)
						player.add_buff("speed", -0.5, 3.0)
						hud.toast("被蛛网缠住了，移动变慢", Color(0.9, 0.9, 0.95))
				"rock":
					fx.dirt_puff(at)
					Sfx.play_at("thud", at, 2.0)
					if inside:
						player.take_damage(float(h["dmg"]), at)
	_pool_tick += dt
	for pl in _pools.duplicate():
		pl["t"] -= dt
		if pl["t"] <= 0.0:
			_pools.erase(pl)
			if is_instance_valid(pl["node"]):
				pl["node"].queue_free()
			continue
		if _pool_tick >= 0.25:
			var at: Vector3 = pl["pos"]
			if Vector2(me.x - at.x, me.z - at.z).length() < float(pl["radius"]) and absf(me.y - at.y) < 2.5:
				player.take_damage(float(pl["dps"]) * 0.25, at)
	if _pool_tick >= 0.25:
		_pool_tick = 0.0
	for tg in _telegraphs.duplicate():
		tg["t"] -= dt
		if tg["t"] <= 0.0:
			_telegraphs.erase(tg)
			if is_instance_valid(tg["node"]):
				tg["node"].queue_free()
			var c: Vector3 = tg["center"]
			fx.slam(c, float(tg["radius"]))
			Sfx.play_at("slam", c, 3.0)
			if Vector2(me.x - c.x, me.z - c.z).length() < float(tg["radius"]):
				player.take_damage(float(tg["dmg"]), c)
				var push := me - c
				push.y = 0
				player.velocity += push.normalized() * 8.0 + Vector3.UP * 6.0
			if player.global_position.distance_to(c) < 30.0:
				player.trauma = minf(player.trauma + 0.4, 1.0)


# ------------------------------------------------------------------ 佛怒唐莲

func throw_grenade(pos: Vector3, vel: Vector3) -> void:
	_spawn_grenade(pos, vel, Net.my_id, true)
	Net.send(0, "grenade", [pos, vel])


func _spawn_grenade(pos: Vector3, vel: Vector3, owner: int, auth: bool) -> void:
	_grenades.append({"pos": pos, "vel": vel, "t": 0.0, "owner": owner, "auth": auth, "node": fx.lotus()})


func _update_grenades(dt: float) -> void:
	for g in _grenades.duplicate():
		g["t"] += dt
		var p0: Vector3 = g["pos"]
		var v: Vector3 = g["vel"]
		v.y -= 18.0 * dt
		var p1 := p0 + v * dt
		var hit := raycast(p0, p1, U.LAYER_WORLD | U.LAYER_BEAST, [player.get_rid()])
		if not hit.is_empty():
			if hit["collider"] is Beast or g["t"] > 0.25:
				p1 = hit["position"]
				g["t"] = 99.0
			else:
				var nrm: Vector3 = hit["normal"]
				v = v.bounce(nrm) * 0.45
				p1 = hit["position"] + nrm * 0.05
		g["pos"] = p1
		g["vel"] = v
		var n: Node3D = g["node"]
		if is_instance_valid(n):
			n.global_position = p1
			n.rotation.y += dt * 12.0
		if g["t"] >= 1.4:
			_grenades.erase(g)
			if is_instance_valid(n):
				n.queue_free()
			fx.lotus_explosion(p1)
			Sfx.play_at("boom", p1, 4.0, 0.05)
			var me := player.global_position
			if me.distance_to(p1) < 20.0:
				player.trauma = minf(player.trauma + (0.6 if me.distance_to(p1) < 8.0 else 0.25), 1.0)
			if g["auth"]:
				Net.send_host("boom", [p1])


func _host_boom(pos: Vector3, owner: int) -> void:
	# 佛怒唐莲跟着章节变强（不然后面的图炸不动）
	var base := 160.0 * float(Data.CH_HP.get(chapter, 1.0)) * 2.5
	for b in skills._beasts_in(pos, 7.0):
		var dmg := base * (1.0 - clampf(b.global_position.distance_to(pos) / 8.0, 0.0, 0.7))
		var away: Vector3 = b.global_position - pos
		away.y = 0
		host_skill_damage(b, dmg, (away.normalized() * 3.0 + Vector3.UP * 11.0) * b.mass, owner)
	if boss and not boss.dead and boss.surface_dist(pos) < 7.0:
		host_boss_damage(base, false, owner)


# ------------------------------------------------------------------ 魂技特效（大家都放）

func skill_fx(sid: String, center: Vector3, dir: Vector3, caster: int, origin: Vector3) -> void:
	var s: Dictionary = Data.SKILLS.get(sid, {})
	if s.is_empty():
		return
	var col := caster_color(caster)
	var tier := Data.skill_tier(sid)
	if tier == 5:
		col = col.lerp(Color(0.8, 0.05, 0.1), 0.6)
	elif tier >= 6:
		col = Color(1.0, 0.86, 0.45)
	var who0: Vector3 = player.global_position if caster == Net.my_id else (remotes[caster].global_position if remotes.has(caster) else center)
	var fc: Vector3 = center if str(s.get("target", "self")) == "aim" or str(s["type"]) in ["launch", "leap", "root", "mark", "pull", "rain"] else who0
	fx.skill_flourish(fc, col, tier, float(s.get("radius", 4.0)))
	match str(s["type"]):
		"launch", "leap":
			fx.shockwave(center, float(s["radius"]), col)
		"root":
			fx.vines(center, float(s["radius"]), col)
		"mark":
			fx.sigil(center, float(s["radius"]), Color(0.8, 0.35, 1.0))
		"pull":
			fx.vortex(center, float(s["radius"]), col)
		"beam":
			fx.beam(origin, dir, float(s["range"]), col)
		"dash", "blink":
			fx.beam(center, Vector3(dir.x, 0, dir.z).normalized(), float(s["dist"]), col, 0.6)
		"grapple":
			fx.beam(origin, dir, float(s.get("range", 30.0)), col, 0.08)
		"giant", "fly", "invis":
			var who2: Vector3 = player.global_position if caster == Net.my_id else (remotes[caster].global_position if remotes.has(caster) else center)
			fx.aura_burst(who2, col, 3.0)
			fx.shockwave(who2, 4.0, col)
		"rain":
			fx.sigil(center, float(s["radius"]), col)
		"buff", "heal", "shield":
			var who: Vector3 = player.global_position if caster == Net.my_id else (remotes[caster].global_position if remotes.has(caster) else center)
			fx.aura_burst(who, col, float(s.get("radius", 3.0)))
	var snd := str(s["type"])
	snd = {"blink": "dash", "grapple": "pull", "giant": "buff", "fly": "leap", "invis": "buff"}.get(snd, snd)
	Sfx.play_at("skill_" + snd, center, 0.0, 0.05)


func broadcast_fx(kind: String, center: Vector3, radius: float, caster: int) -> void:
	Net.send(0, "fxw", [kind, center, radius, caster])
	_on_fxw([kind, center, radius, caster])


func _on_fxw(msg: Array) -> void:
	fx.shockwave(msg[1], float(msg[2]), caster_color(int(msg[3])))
	Sfx.play_at("skill_launch", msg[1], -3.0, 0.1)


func remote_ring_flash(peer: int, slot: int) -> void:
	if remotes.has(peer):
		remotes[peer].flash_ring(slot)


# ------------------------------------------------------------------ 死亡与复活

func _on_player_died() -> void:
	var team := false
	for id in remotes:
		if not remotes[id].is_dead():
			team = true
	_down_t = DOWN_TIME_TEAM if team else DOWN_TIME_SOLO
	_carry_t = -1.0
	hud.death_countdown(_down_t, team)
	Sfx.play("death", 0.0)
	Net.send(0, "died", [])
	hud.feed("%s 倒下了" % Settings.display_name(), Color(1, 0.5, 0.4))
	# 手里的暗器掉在地上（袖箭除外），队友可以捡起来用，也可以还给你
	for e in player.drop_guns_on_death():
		loot.spawn("gun", str(e[0]), 1, int(e[1]), player.global_position + Vector3(0, 1.0, 0), Vector3(randf_range(-2, 2), 4.0, randf_range(-2, 2)), 0)


## 倒地：等队友救；时间到了（或者按空格放弃）海鸥飞下来把你叼走，回码头复活
func _update_down(dt: float) -> void:
	if not player.dead:
		return
	if _carry_t >= 0.0:
		_carry_t += dt
		if _carry_t > CARRY_TIME:
			_carry_t = -1.0
			player.carried = false
			player.revive()
			player.teleport(island.spawn + Vector3(0, 0.5, 0))
			player.invuln_t = 4.0
			hud.death_countdown(-1.0)
		return
	_down_t -= dt
	var team := false
	for id in remotes:
		if not remotes[id].is_dead():
			team = true
	hud.death_countdown(_down_t, team)
	var give_up := player.input_enabled and Input.is_action_just_pressed("jump")
	if _down_t <= 0.0 or give_up:
		_carry_t = 0.0
		player.carried = true
		loot.gull_carry(player, true, -Net.my_id)
		Net.send(0, "gullbody", [Net.my_id])
		hud.death_countdown(-2.0)


## 换了外观：自己手里的重建，告诉队友
func on_look_changed() -> void:
	player.viewmodel.apply_look()
	_broadcast_prog()


## 叼着我的海鸥被打下来了：掉回地上，接着等队友救
func gull_dropped_me() -> void:
	if _carry_t < 0.0:
		return
	_carry_t = -1.0
	player.carried = false
	_down_t = 15.0
	hud.feed("海鸥被打下来了，你掉回了地上！", Color(0.6, 1.0, 0.7))


## 按住 F 把倒地的队友拉起来
func _update_revive(dt: float) -> void:
	var it := nearest_interactable() if not player.dead else {}
	var holding := player.input_enabled and not player.dead and Input.is_action_pressed("interact") and str(it.get("id", "")) == "revive"
	if not holding:
		if _revive_t > 0.0:
			hud.revive_progress(-1.0)
		_revive_t = 0.0
		_revive_peer = 0
		return
	var peer := int(it["peer"])
	if peer != _revive_peer:
		_revive_peer = peer
		_revive_t = 0.0
	_revive_t += dt
	hud.revive_progress(_revive_t / REVIVE_TIME)
	if _revive_t >= REVIVE_TIME:
		_revive_t = 0.0
		_revive_peer = 0
		hud.revive_progress(-1.0)
		Net.send(peer, "revive", [Net.my_id])
		Profile.count("revives")
		hud.feed("你把 %s 拉了起来" % peer_name(peer), Color(0.6, 1.0, 0.7))
		Sfx.play("heal", -2.0)


# ------------------------------------------------------------------ 同步

func _send_beast_snapshot() -> void:
	if beasts.is_empty() or not Net.is_online():
		return
	var arr := PackedFloat32Array()
	for b: Beast in beasts.values():
		if not b.alive():
			continue
		var q := b.quaternion
		var p := b.global_position
		arr.append_array([float(b.id), p.x, p.y, p.z, q.x, q.y, q.z, q.w, float(b.snapshot_state()), b.hp / b.max_hp])
	Net.send(0, "bs", arr)


func _on_peer_left(id: int) -> void:
	if remotes.has(id):
		hud.feed("%s 离开了" % peer_name(id), Color(0.8, 0.8, 0.8))
		remotes[id].queue_free()
		remotes.erase(id)
	peer_info.erase(id)
	if Net.is_host():
		_host_check_quest.call_deferred()   # 人数变了，任务量跟着变
		if not _boat_ready.is_empty():
			_host_boat_check.call_deferred("")


func _add_remote(id: int, info: Dictionary) -> void:
	var is_new := not peer_info.has(id)
	peer_info[id] = info
	if is_new and Net.is_host():
		_host_check_quest.call_deferred()
	if remotes.has(id):
		remotes[id].set_info(info)
		return
	var r := RemotePlayer.new()
	r.setup(self, id, info)
	players_root.add_child(r)
	r.set_camera(player.cam)
	remotes[id] = r
	_stat(id)
	hud.feed("%s 加入了" % str(info.get("name", "魂师")), Color(0.6, 0.95, 0.7))


func hello_payload(want_reply: bool) -> Array:
	return [Settings.display_name(), Settings.wuhun, want_reply, Profile.level, _ring_summary(), Profile.outfit, Profile.skin]


func _info_from_hello(d: Array) -> Dictionary:
	return {"name": str(d[0]), "wuhun": int(d[1]), "level": int(d[3]) if d.size() > 3 else 1, "rings": d[4] if d.size() > 4 else [],
		"outfit": str(d[5]) if d.size() > 5 else "default", "skin": str(d[6]) if d.size() > 6 else "default"}


## 联机消息都从 Main 转到这里（Main 会先缓存世界还没建好时收到的消息）
func on_message(from: int, type: String, data: Variant) -> void:
	match type:
		"hello":
			var d: Array = data
			_add_remote(from, _info_from_hello(d))
			if bool(d[2]):
				Net.send(from, "hello", hello_payload(false))
				if Net.is_host():
					_send_init(from)
					_host_check_quest()
		"prog":
			var d: Array = data
			if peer_info.has(from):
				peer_info[from]["level"] = int(d[0])
				peer_info[from]["rings"] = d[1]
				if d.size() > 3:
					peer_info[from]["outfit"] = str(d[2])
					peer_info[from]["skin"] = str(d[3])
				if remotes.has(from):
					remotes[from].set_info(peer_info[from])
			if Net.is_host():
				_host_check_quest()
		"ps":
			if remotes.has(from):
				remotes[from].push_snapshot(data)
		"shot":
			var d: Array = data
			var w: Dictionary = Data.WEAPONS.get(str(d[0]), Data.WEAPONS["xiujian"])
			var muzzle: Vector3 = d[1]
			if remotes.has(from):
				muzzle = remotes[from].muzzle_global()
			var single: bool = w["pellets"] == 1
			for e in d[2]:
				fx.tracer(muzzle, e, w["tracer"], 0.06 if single else 0.025, 300.0 if single else 240.0, 5.0 if single else 1.8, single)
			Sfx.play_at(w["sound"], muzzle, 0.0, 0.06)
		"yank":
			if Net.is_host():
				var d: Array = data
				_host_spawn(from, d[0], str(d[2]), int(d[3]), d[4], "", str(d[5]) if d.size() > 5 else "grass")
				# 星斗大森林：成群的魂兽，同窝的会跑来帮忙
				if str(Data.CH_TRAIT.get(chapter, "")) == "pack" and rng.randf() < 0.45 and not Data.autotest:
					for k in rng.randi_range(1, 2):
						var a := rng.randf() * TAU
						var q: Vector3 = (d[4] as Vector3) + Vector3(cos(a) * 18.0, 0, sin(a) * 18.0)
						if island.is_land(q.x, q.z):
							q.y = island.height_at(q.x, q.z) + 0.3
							_host_spawn(1, q, str(d[2]), int(d[3]), d[4], "fierce", "grass")
		"hit":
			if Net.is_host():
				var d: Array = data
				var b: Beast = beasts.get(int(d[0]))
				if b and b.alive():
					b.take_hit(float(d[1]), d[2], d[3], bool(d[4]), from, float(d[5]))
					if b.hp <= 0.0:
						_host_kill(b)
		"bhit":
			if Net.is_host():
				host_boss_damage(float(data[0]), bool(data[1]), from)
		"bsp":
			var d: Array = data
			if not beasts.has(int(d[0])):
				_spawn_beast(int(d[0]), str(d[1]), int(d[2]), d[3], d[4], int(d[5]), true, str(d[6]) if d.size() > 6 else "flee", d[7] if d.size() > 7 else [])
		"bs":
			var arr: PackedFloat32Array = data
			var i := 0
			while i + 9 < arr.size():
				var b: Beast = beasts.get(int(arr[i]))
				if b:
					b.push_snapshot(Vector3(arr[i + 1], arr[i + 2], arr[i + 3]), Quaternion(arr[i + 4], arr[i + 5], arr[i + 6], arr[i + 7]).normalized(), int(arr[i + 8]))
					b.set_hp_from_ratio(arr[i + 9])
				i += 10
		"bk":
			_on_kill(data)
		"be":
			_on_escape(data)
		"dmgnum":
			fx.damage_number(data[0], float(data[1]), false)
		"btel":
			_on_btel(data)
		"bsk":
			_apply_beast_special(data)
		"bskfx":
			_on_bskfx(data)
		"dmg":
			player.take_damage(float(data[0]), data[1])
			if (data as Array).size() > 2:
				_apply_trait(str(data[2]), data[1], float(data[0]))
		"ring":
			_on_ring(data)
		"ringgone":
			_on_ring_gone(data)
		"absorb":
			if Net.is_host():
				var rid := int(data[0])
				if rings.has(rid):
					var r: Dictionary = rings[rid]
					Net.send(0, "ringgone", [rid, from])
					var ok := [rid, r["age"], r["species"]]
					_on_ring_gone([rid, from])
					if from == Net.my_id:
						_start_absorb(int(ok[1]), str(ok[2]))
					else:
						Net.send(from, "absorbok", ok)
		"absorbok":
			_start_absorb(int(data[1]), str(data[2]))
		"essence":
			if Net.is_host() and rings.has(int(data[0])):
				var r2: Dictionary = rings[int(data[0])]
				var ok2 := [int(data[0]), r2["age"], r2["species"]]
				Net.send(0, "ringgone", [int(data[0]), from])
				_on_ring_gone([int(data[0]), from])
				if from == Net.my_id:
					_gain_essence(int(ok2[1]), str(ok2[2]))
				else:
					Net.send(from, "essenceok", ok2)
		"essenceok":
			_gain_essence(int(data[1]), str(data[2]))
		"skill":
			if Net.is_host():
				var d: Array = data
				skills.host_apply(str(d[0]), float(d[1]), d[2], d[3], from)
		"skillhit":
			if Net.is_host():
				var d: Array = data
				skills.host_projectile_hit(str(d[0]), float(d[1]), d[2], from)
		"skfx":
			var d: Array = data
			skill_fx(str(d[0]), d[1], d[2], from, d[3])
		"skproj":
			var d: Array = data
			skills.remote_projectile(str(d[0]), d[1], d[2], from)
		"fxw":
			_on_fxw(data)
		"ringflash":
			remote_ring_flash(from, int(data[0]))
		"buff":
			var d: Array = data
			if player.global_position.distance_to(d[3]) <= float(d[4]):
				player.add_buff(str(d[0]), float(d[1]), float(d[2]))
				fx.aura_burst(player.global_position, caster_color(from), 1.5)
				hud.toast("%s 给你加了增益" % peer_name(from), caster_color(from), 2.0)
		"heal":
			var d: Array = data
			if player.global_position.distance_to(d[1]) <= float(d[2]):
				player.heal(float(d[0]))
				fx.heal_burst(player.global_position)
		"shield":
			var d: Array = data
			if player.global_position.distance_to(d[2]) <= float(d[3]):
				player.add_shield(float(d[0]), float(d[1]))
		"grenade":
			var d: Array = data
			_spawn_grenade(d[0], d[1], from, false)
		"boom":
			if Net.is_host():
				_host_boom(data[0], from)
		"hz":
			_on_hazard(data)
		"tg":
			_on_telegraph(data)
		"sw":
			_on_shockwave(data)
		"cone":
			_on_cone(data)
		"ult":
			_on_ultimate(data)
		"bossspawn":
			_on_boss_spawn(data)
		"bsnap":
			if boss and boss.proxy:
				boss.push_snapshot(data)
		"bphase":
			_on_boss_phase2()
		"bossdead":
			_on_boss_dead(data)
		"quest":
			var d: Array = data
			quest_idx = int(d[1])
			quest_count = int(d[2])
			quest_target = int(d[3]) if d.size() > 3 else int(_cur_quest().get("n", 1))
			hud.update_quest()
		"qdone":
			_on_quest_done(data)
		"qev":
			if Net.is_host():
				var d: Array = data
				_host_quest_event(str(d[0]), int(d[1]), str(d[2]) if d.size() > 2 else "")
		"altar":
			if Net.is_host() and _can_summon():
				_host_spawn_boss()
				_host_quest_event("altar", 1)
		"boat":
			if Net.is_host():
				var dest := int(data[0]) if (data is Array and (data as Array).size() > 0) else int(Data.CHAPTERS[chapter]["next"])
				if dest in boat_destinations():
					if dest != _boat_dest:
						_boat_ready.clear()
						_boat_dest = dest
					_boat_ready[from] = true
					_host_boat_check(peer_name(from))
		"boatready":
			_on_boat_ready(data)
		"travel":
			_travel(int(data[0]))
		"died":
			hud.feed("%s 倒下了！走过去按住 F 拉他起来" % peer_name(from), Color(1, 0.5, 0.4))
		"revive":
			if player.dead and _carry_t < 0.0:
				player.revive_here(0.5)
				hud.death_countdown(-1.0)
				hud.feed("%s 把你拉了起来" % peer_name(from), Color(0.6, 1.0, 0.7))
				Sfx.play("heal", -2.0)
				fx.heal_burst(player.global_position)
		"gullbody":
			var gp := int(data[0])
			if remotes.has(gp):
				loot.gull_carry(remotes[gp], false, -gp)
				hud.feed("海鸥把 %s 叼走了……" % peer_name(gp), Color(0.8, 0.85, 0.9))
		"feedall":
			hud.feed(str(data[0]), UiKit.GOLD)
		"hint":
			hud.toast(str(data[0]), Color(1.0, 0.8, 0.5), 4.0)
		"tide":
			_on_tide(data if data is Array else [])
		"gi", "gitake", "gigone", "gull", "gullhit", "gulldown", "gdive", "gflock":
			loot.on_message(from, type, data)
		"init":
			_apply_init(data)


## 所有人都上船按了 F 才出发（有人走了也重新算）
func _host_boat_check(who: String) -> void:
	var peers := _all_peers()
	for k in _boat_ready.keys():
		if not k in peers:
			_boat_ready.erase(k)
	var msg := [_boat_ready.size(), peers.size(), who, _boat_dest]
	Net.send(0, "boatready", msg)
	_on_boat_ready(msg)
	if _boat_ready.size() >= peers.size() and _boat_dest > 0:
		Net.send(0, "travel", [_boat_dest])
		_travel(_boat_dest)


var _boat_dest := 0


## 在船边选好目的地，上船
func board(dest: int) -> void:
	_i_boarded = true
	Net.send_host("boat", [dest])


func _on_boat_ready(msg: Array) -> void:
	_boat_count = [int(msg[0]), int(msg[1])]
	var dname := ""
	if msg.size() > 3 and Data.CHAPTERS.has(int(msg[3])):
		dname = "，去%s" % Data.CHAPTERS[int(msg[3])]["name"]
	if str(msg[2]) != "":
		hud.feed("%s 上船了（%d/%d%s）" % [str(msg[2]), int(msg[0]), int(msg[1]), dname], Color(0.6, 0.85, 1.0))
	if int(msg[0]) < int(msg[1]):
		hud.toast("已上船 %d/%d，等所有人走到船边按 F" % [int(msg[0]), int(msg[1])], Color(0.6, 0.85, 1.0), 3.0)


func _travel(next: int) -> void:
	Profile.max_chapter = maxi(Profile.max_chapter, next)
	if Net.is_host():
		Profile.chapter = next
		Profile.quest = 0
		Profile.quest_count = 0
		Profile.save_profile()
	travel_requested.emit(next)


func _send_init(to: int) -> void:
	var list := []
	for b: Beast in beasts.values():
		if b.alive():
			list.append([b.id, b.species, b.age, b.global_position, b.owner_peer, b.hp / b.max_hp, b.temper, b.affixes])
	var rl := []
	for rid in rings:
		var r: Dictionary = rings[rid]
		rl.append([rid, r["pos"], r["age"], r["species"]])
	var bs := []
	if boss and not boss.dead:
		bs = [boss.kind, boss.max_hp, boss._anchor, boss.hp / boss.max_hp]
	Net.send(to, "init", [chapter, quest_idx, quest_count, list, rl, bs, stats, loot.init_list()])


func _apply_init(d: Array) -> void:
	quest_idx = int(d[1])
	quest_count = int(d[2])
	for e in d[3]:
		if not beasts.has(int(e[0])):
			var b := _spawn_beast(int(e[0]), str(e[1]), int(e[2]), e[3], Vector3.ZERO, int(e[4]), true, str(e[6]) if e.size() > 6 else "flee", e[7] if e.size() > 7 else [])
			b.set_hp_from_ratio(float(e[5]))
	for r in d[4]:
		if not rings.has(int(r[0])):
			_on_ring(r)
	var bs: Array = d[5]
	if bs.size() >= 4 and not boss:
		_on_boss_spawn([bs[0], bs[1], bs[2]])
		boss.hp = float(bs[3]) * boss.max_hp
	var s: Dictionary = d[6]
	for k in s:
		stats[int(k)] = s[k]
	if d.size() > 7:
		for gi in d[7]:
			loot.on_message(1, "gi", gi)
	hud.update_quest()


func leave() -> void:
	leave_requested.emit()
