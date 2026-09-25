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

var chapter := 1
var island: Island
var builder: WorldBuilder
var fx: Fx
var hud: Hud
var skills: SkillSystem
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


func _init(p_chapter := 1) -> void:
	chapter = p_chapter


func _ready() -> void:
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

	if Net.is_host():
		quest_idx = Profile.quest if Profile.chapter == chapter else 0
		quest_count = Profile.quest_count if Profile.chapter == chapter else 0
	_stat(Net.my_id)
	peer_info[Net.my_id] = _my_info()
	Net.peer_left.connect(_on_peer_left)
	Profile.changed.connect(_on_profile_changed)
	Sfx.play_ambient("ambient", -16.0)
	capture_mouse(true)
	hud.chapter_banner(str(ch["name"]), str(ch["intro"]))
	_last_prog = [Profile.level, Profile.rings.size()]
	if Net.is_host():
		get_tree().create_timer(0.5).timeout.connect(_host_check_quest)


func _exit_tree() -> void:
	if Settings.changed.is_connected(builder.apply_quality):
		Settings.changed.disconnect(builder.apply_quality)
	Sfx.stop_ambient()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Profile.save_profile()


func _my_info() -> Dictionary:
	return {"name": Settings.display_name(), "wuhun": Settings.wuhun, "level": Profile.level, "rings": _ring_summary()}


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
	elif event.is_action_pressed("fullscreen"):
		Settings.toggle_fullscreen()
	elif event.is_action_pressed("toggle_fps"):
		Settings.show_fps = not Settings.show_fps
		Settings.save_settings()
	elif event is InputEventMouseButton and event.pressed and not paused and not ui_open and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		capture_mouse(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not paused and not ui_open and is_inside_tree():
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
	_update_hazards(dt)
	_update_grenades(dt)
	_update_rings_visual(dt)
	if player.dead:
		_respawn_t -= dt
		hud.death_countdown(_respawn_t)
		if _respawn_t <= 0.0:
			player.revive()
			player.teleport(island.spawn + Vector3(0, 0.5, 0))
			hud.death_countdown(-1.0)


# ------------------------------------------------------------------ 工具

func raycast(from: Vector3, to: Vector3, mask: int, exclude: Array = []) -> Dictionary:
	var ex: Array[RID] = []
	for e in exclude:
		ex.append(e)
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, ex)
	return get_world_3d().direct_space_state.intersect_ray(q)


func all_players() -> Array:
	var out := [{"peer": Net.my_id, "pos": player.global_position, "alive": not player.dead}]
	for id in remotes:
		var r: RemotePlayer = remotes[id]
		out.append({"peer": id, "pos": r.global_position, "alive": not r.is_dead()})
	return out


func alive_players() -> Array:
	return all_players().filter(func(p): return p["alive"])


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
			fx.tracer(muzzle, e, w["tracer"], 0.02, 420.0, 4.0)
		else:
			fx.tracer(muzzle, e, w["tracer"], 0.009, 280.0, 1.6)
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


# ------------------------------------------------------------------ 引魂索拽出魂兽

func request_yank(pos: Vector3, habitat: String, species: String, age: int) -> void:
	Net.send_host("yank", [pos, habitat, species, age, player.global_position])


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


func _host_spawn(owner: int, pos: Vector3, species: String, age: int, owner_pos: Vector3) -> Beast:
	if not Data.BEASTS.has(species):
		return null
	age = clampi(age, 0, 2)
	var id := next_beast_id
	next_beast_id += 1
	var spawn := pos + Vector3(0, 0.4, 0)
	if not island.is_land(pos.x, pos.z):
		spawn.y = maxf(spawn.y, Island.WATER_Y + 0.3)
	var vel := _launch_velocity(spawn, owner_pos, species)
	var b := _spawn_beast(id, species, age, spawn, vel, owner, false)
	Net.send(0, "bsp", [id, species, age, spawn, vel, owner])
	return b


func _spawn_beast(id: int, species: String, age: int, pos: Vector3, vel: Vector3, owner: int, proxy: bool) -> Beast:
	var b := Beast.new()
	b.setup(self, id, species, age, owner, proxy)
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
	var base: float = float(Data.BEASTS[b.species]["reward"]) * float(Data.AGES[b.age]["reward"])
	var xp: float = float(Data.BEASTS[b.species]["xp"]) * float(Data.AGES[b.age]["xp"])
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
	var reward := roundi(base * mult)
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
	var msg := [b.id, killer, b.species, b.age, b.global_position, tags, rewards, st["kills"], st["earned"]]
	Net.send(0, "bk", msg)
	_on_kill(msg)
	_host_maybe_drop_ring(b, killer)
	_host_quest_event("kill", 1)
	_host_quest_event("hunt", 1, b.species)


func beast_escaped(b: Beast, reason: String) -> void:
	if not Net.is_host() or not b.alive():
		return
	var msg := [b.id, reason, b.global_position]
	Net.send(0, "be", msg)
	_on_escape(msg)


## 魔狼 / 犀牛 咬到玩家
func beast_bite(b: Beast, peer: int, dmg: float) -> void:
	if peer == Net.my_id:
		player.take_damage(dmg, b.global_position)
	else:
		Net.send(peer, "dmg", [dmg, b.global_position])
	Sfx.play_at("bite_attack", b.global_position, 0.0, 0.1)


## 金刚猿扔石头
func beast_throw_rock(b: Beast, target: Vector3) -> void:
	var from := b.global_position + Vector3(0, 1.4 * Data.AGES[b.age]["scale"], 0)
	var dmg: float = float(Data.BEASTS[b.species].get("hurt", 12.0)) * (1.0 + b.age * 0.5)
	_host_hazard("rock", from, target, 1.0, 2.2, dmg)


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
	Sfx.play_at("kill_burst", pos, 0.0, 0.05)
	var mine: Array = rewards.get(Net.my_id, rewards.get(str(Net.my_id), [0, 0]))
	var who := peer_name(killer)
	hud.feed("%s 击杀 %s·%s" % [who, Data.age_name(age), Data.BEASTS[species]["name"]], Data.age_color(age))
	_gain(int(mine[0]), int(mine[1]))
	if killer == Net.my_id:
		Profile.kills += 1
		hud.hitmarker(false, true)
		hud.kill_popup(int(mine[0]), int(mine[1]), tags, species, age)
		Sfx.play("kill", -1.0)
		Sfx.play("coin", -4.0, 0.03)


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
			_broadcast_prog()
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

func _host_maybe_drop_ring(b: Beast, killer: int) -> void:
	var chance: float = float(Data.AGES[b.age]["ring_drop"])
	# 打的人正好卡在瓶颈、年份也够：必掉
	var info: Dictionary = peer_info.get(killer, {})
	var lv := int(info.get("level", 1))
	var nr: int = (info.get("rings", []) as Array).size()
	if nr < Data.RING_MIN_AGE.size() and lv >= (nr + 1) * 10 and b.age >= int(Data.RING_MIN_AGE[nr]):
		chance = 1.0
	if rng.randf() > chance:
		return
	_host_drop_ring(b.global_position + Vector3(0, 1.0, 0), b.age, b.species)


func _host_drop_ring(pos: Vector3, age: int, species: String) -> void:
	# 魂兽多半死在半空：魂环落到地面（或水面）上方一人高，走过去就能吸收
	var g := island.height_at(pos.x, pos.z)
	pos.y = maxf(g, Island.WATER_Y) + 1.2
	var rid := next_ring_id
	next_ring_id += 1
	var msg := [rid, pos, age, species]
	Net.send(0, "ring", msg)
	_on_ring(msg)


func _on_ring(msg: Array) -> void:
	var rid := int(msg[0])
	var pos: Vector3 = msg[1]
	var age := int(msg[2])
	var node := fx.soul_ring(pos, Data.age_color(age))
	rings[rid] = {"pos": pos, "age": age, "species": str(msg[3]), "node": node, "t": 0.0}
	hud.feed("掉落了%s魂环！走过去按 F 吸收" % Data.age_name(age), Data.age_color(age))
	Sfx.play_at("ring_drop", pos, 0.0)


func _host_rings(dt: float) -> void:
	for rid in rings.keys():
		rings[rid]["t"] += dt
		if rings[rid]["t"] > 90.0:
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
	get_tree().create_timer(3.0).timeout.connect(func(): hud.choose_skill(age, species))


## 界面选好魂技后调用
func finish_absorb(age: int, species: String, sid: String) -> void:
	Profile.add_ring(age, sid, species)
	var ups := Profile.add_xp(0)
	player.soul = Profile.max_soul()
	player.hp = Profile.max_hp()
	hud.toast("吸收了%s魂环！获得魂技【%s】（按 %s 释放）" % [Data.age_name(age), Data.SKILLS[sid]["name"], Data.SKILL_KEYS[Profile.rings.size() - 1]], Data.age_color(age), 6.0)
	Sfx.play("level_up", -2.0)
	_broadcast_prog()
	if ups > 0:
		hud.level_up(Profile.level)


# ------------------------------------------------------------------ 交互（F）

func interactables() -> Array:
	var out := [
		{"id": "shop", "pos": builder.shop_door, "r": 3.5, "text": "按 F 打开唐门暗器铺"},
		{"id": "altar", "pos": island.altar_pos + Vector3(0, 1, 0), "r": 3.5, "text": _altar_text()},
	]
	if int(Data.CHAPTERS[chapter].get("next", 0)) > 0:
		out.append({"id": "boat", "pos": builder.boat_pos + Vector3(0, 1.0, 0), "r": 4.2, "text": _boat_text()})
	for rid in rings:
		var r: Dictionary = rings[rid]
		var why := Profile.can_absorb(int(r["age"]))
		var t := "按 F 吸收%s魂环（%s）" % [Data.age_name(int(r["age"])), Data.BEASTS[r["species"]]["name"]] if why == "" else "%s魂环：%s" % [Data.age_name(int(r["age"])), why]
		out.append({"id": "ring", "rid": rid, "pos": r["pos"], "r": 2.6, "text": t, "ok": why == ""})
	return out


func _cur_quest() -> Dictionary:
	return Data.quest(chapter, quest_idx)


func _altar_text() -> String:
	if boss:
		return "祭坛（Boss 已经出现了）"
	if _cur_quest().get("type", "") == "altar":
		return "按 F 点燃祭坛，召唤 Boss"
	return "祭坛：先完成前面的任务"


func _boat_text() -> String:
	var nxt := int(Data.CHAPTERS[chapter].get("next", 0))
	if _cur_quest().get("type", "") == "boat" and Data.CHAPTERS.has(nxt):
		return "按 F 上船，前往%s" % Data.CHAPTERS[nxt]["name"]
	return "渡船：打败这里的 Boss 之后才能出发"


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
			if _cur_quest().get("type", "") == "altar" and not boss:
				Net.send_host("altar", [])
			else:
				hud.toast(_altar_text(), Color(0.9, 0.9, 0.9))
		"boat":
			if _cur_quest().get("type", "") == "boat":
				Net.send_host("boat", [])
			else:
				hud.toast(_boat_text(), Color(0.9, 0.9, 0.9))
		"ring":
			if it.get("ok", false):
				Net.send_host("absorb", [it["rid"]])
			else:
				hud.toast(str(it["text"]), Color(1, 0.8, 0.6), 4.0)


# ------------------------------------------------------------------ 商店回调

func on_bought_weapon(id: String) -> void:
	player.rebuild_guns()
	for i in player.guns.size():
		if player.guns[i].id == id:
			player.switch_weapon(i)
	Net.send_host("qev", ["buy", 1])


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
	var p := [Profile.level, _ring_summary()]
	if p == _last_prog:
		return
	_last_prog = p
	Net.send(0, "prog", p)
	if Net.is_host():
		_host_check_quest()


func _on_profile_changed() -> void:
	hud.update_quest()


# ------------------------------------------------------------------ Boss

func _host_spawn_boss() -> void:
	var kind := str(Data.CHAPTERS[chapter]["boss"])
	var n := _all_peers().size()
	var hp: float = float(Data.BOSSES[kind]["hp"]) * (1.0 + 0.6 * (n - 1))
	var anchor := island.boss_pos
	var msg := [kind, hp, anchor]
	Net.send(0, "bossspawn", msg)
	_on_boss_spawn(msg)


func _on_boss_spawn(msg: Array) -> void:
	if boss:
		return
	boss = Boss.new()
	add_child(boss)
	boss.setup(self, str(msg[0]), float(msg[1]), not Net.is_host(), msg[2])
	hud.boss_bar(str(Data.BOSSES[msg[0]]["name"]))
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
		_host_spawn(1, b.center() + Vector3(randf_range(-3, 3), -2.0, randf_range(-3, 3)), species, 1, tpos)


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


func _on_boss_dead(msg: Array) -> void:
	var kind := str(msg[0])
	var d: Dictionary = Data.BOSSES[kind]
	var rewards: Dictionary = msg[1]
	var mine: Array = rewards.get(Net.my_id, [0, 0])
	if boss:
		boss.die_visual()     # 播死亡动画、摔下来，自己炸掉
		boss = null
	hud.boss_bar("")
	_gain(int(mine[0]), int(mine[1]))
	# 魂骨：每人拿一块自己还没有的
	var got := ""
	for bid in d["bones"]:
		if Profile.add_bone(bid):
			got = bid
			break
	hud.boss_defeated(str(d["name"]), int(mine[0]), got)
	Sfx.play("quest_done", 0.0)
	player.rebuild_guns()


# ------------------------------------------------------------------ 危险物：毒液、蛛网、石头、红圈

func boss_projectile(kind: String, from: Vector3, to: Vector3, flight: float, radius: float, dmg: float) -> void:
	_host_hazard(kind, from, to, flight, radius, dmg)


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


func boss_telegraph(center: Vector3, radius: float, delay: float, dmg: float, kind: String, _src: Vector3) -> void:
	center.y = maxf(island.height_at(center.x, center.z), Island.WATER_Y)
	var msg := [center, radius, delay, dmg, kind]
	Net.send(0, "tg", msg)
	_on_telegraph(msg)


func _on_telegraph(msg: Array) -> void:
	var node := fx.telegraph(msg[0], float(msg[1]), float(msg[2]))
	_telegraphs.append({"center": msg[0], "radius": float(msg[1]), "t": float(msg[2]), "dmg": float(msg[3]), "kind": str(msg[4]), "node": node})


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
	for b in skills._beasts_in(pos, 7.0):
		var dmg := 160.0 * (1.0 - clampf(b.global_position.distance_to(pos) / 8.0, 0.0, 0.7))
		var away: Vector3 = b.global_position - pos
		away.y = 0
		host_skill_damage(b, dmg, (away.normalized() * 3.0 + Vector3.UP * 11.0) * b.mass, owner)
	if boss and boss.center().distance_to(pos) < 10.0:
		host_boss_damage(160.0, false, owner)


# ------------------------------------------------------------------ 魂技特效（大家都放）

func skill_fx(sid: String, center: Vector3, dir: Vector3, caster: int, origin: Vector3) -> void:
	var s: Dictionary = Data.SKILLS.get(sid, {})
	if s.is_empty():
		return
	var col := caster_color(caster)
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
		"dash":
			fx.beam(center, Vector3(dir.x, 0, dir.z).normalized(), float(s["dist"]), col, 0.6)
		"rain":
			fx.sigil(center, float(s["radius"]), col)
		"buff", "heal", "shield":
			var who: Vector3 = player.global_position if caster == Net.my_id else (remotes[caster].global_position if remotes.has(caster) else center)
			fx.aura_burst(who, col, float(s.get("radius", 3.0)))
	Sfx.play_at("skill_" + str(s["type"]), center, 0.0, 0.05)


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
	_respawn_t = RESPAWN_TIME
	hud.death_countdown(_respawn_t)
	Sfx.play("death", 0.0)
	Net.send(0, "died", [])
	hud.feed("%s 倒下了" % Settings.display_name(), Color(1, 0.5, 0.4))


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
	return [Settings.display_name(), Settings.wuhun, want_reply, Profile.level, _ring_summary()]


func _info_from_hello(d: Array) -> Dictionary:
	return {"name": str(d[0]), "wuhun": int(d[1]), "level": int(d[3]) if d.size() > 3 else 1, "rings": d[4] if d.size() > 4 else []}


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
				fx.tracer(muzzle, e, w["tracer"], 0.02 if single else 0.009, 420.0 if single else 280.0, 4.0 if single else 1.6)
			Sfx.play_at(w["sound"], muzzle, 0.0, 0.06)
		"yank":
			if Net.is_host():
				var d: Array = data
				_host_spawn(from, d[0], str(d[2]), int(d[3]), d[4])
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
				_spawn_beast(int(d[0]), str(d[1]), int(d[2]), d[3], d[4], int(d[5]), true)
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
		"dmg":
			player.take_damage(float(data[0]), data[1])
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
			if Net.is_host() and _cur_quest().get("type", "") == "altar" and not boss:
				_host_spawn_boss()
				_host_quest_event("altar", 1)
		"boat":
			if Net.is_host() and _cur_quest().get("type", "") == "boat":
				var next := int(Data.CHAPTERS[chapter]["next"])
				Net.send(0, "travel", [next])
				_travel(next)
		"travel":
			_travel(int(data[0]))
		"died":
			hud.feed("%s 倒下了" % peer_name(from), Color(1, 0.5, 0.4))
		"init":
			_apply_init(data)


func _travel(next: int) -> void:
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
			list.append([b.id, b.species, b.age, b.global_position, b.owner_peer, b.hp / b.max_hp])
	var rl := []
	for rid in rings:
		var r: Dictionary = rings[rid]
		rl.append([rid, r["pos"], r["age"], r["species"]])
	var bs := []
	if boss and not boss.dead:
		bs = [boss.kind, boss.max_hp, boss._anchor, boss.hp / boss.max_hp]
	Net.send(to, "init", [chapter, quest_idx, quest_count, list, rl, bs, stats])


func _apply_init(d: Array) -> void:
	quest_idx = int(d[1])
	quest_count = int(d[2])
	for e in d[3]:
		if not beasts.has(int(e[0])):
			var b := _spawn_beast(int(e[0]), str(e[1]), int(e[2]), e[3], Vector3.ZERO, int(e[4]), true)
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
	hud.update_quest()


func leave() -> void:
	leave_requested.emit()
