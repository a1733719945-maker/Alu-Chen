class_name World
extends Node3D
## 一局游戏：岛、玩家、魂兽、联机同步、击杀结算。
##
## 联机分工：
##   每个玩家 —— 算自己的移动、开枪射线、引魂索，命中结果发给房主
##   房主     —— 生成魂兽、算魂兽物理和血量、结算金魂币，再广播给大家

signal leave_requested

const PLAYER_SNAP_RATE := 30.0
const BEAST_SNAP_RATE := 20.0

var island: Island
var builder: WorldBuilder
var fx: Fx
var hud: Hud
var player: Player
var players_root: Node3D
var beasts_root: Node3D
var remotes := {}          # peer id -> RemotePlayer
var beasts := {}           # beast id -> Beast
var next_beast_id := 1
var wallet := 0            # 全队共用的金魂币
var stats := {}            # peer id -> {"kills": int, "earned": int}
var rng := RandomNumberGenerator.new()
var paused := false
var _player_snap_t := 0.0
var _beast_snap_t := 0.0
var _t := 0.0


func _ready() -> void:
	rng.randomize()
	island = Island.new()
	builder = WorldBuilder.new(island, self)
	builder.build()
	players_root = Node3D.new()
	players_root.name = "Players"
	add_child(players_root)
	beasts_root = Node3D.new()
	beasts_root.name = "Beasts"
	add_child(beasts_root)
	fx = Fx.new()
	fx.name = "Fx"
	add_child(fx)

	player = Player.new()
	player.name = "LocalPlayer"
	player.world = self
	players_root.add_child(player)
	player.teleport(island.spawn + Vector3(0, 0.3, 0))
	player.look_to(island.spawn_yaw, deg_to_rad(-4))
	fx.set_camera(player.cam)

	hud = Hud.new()
	hud.world = self
	add_child(hud)
	player.lure.hint.connect(hud.toast)
	player.ammo_changed.connect(hud.on_ammo)
	player.weapon_changed.connect(hud.on_weapon)
	hud.on_weapon(0)

	_stat(Net.my_id)
	Net.message.connect(_on_message)
	Net.peer_left.connect(_on_peer_left)
	Net.peer_joined.connect(_on_peer_joined)
	Net.send(0, "hello", [Settings.display_name(), Settings.wuhun, true])
	Sfx.play_ambient("ambient", -16.0)
	capture_mouse(true)
	hud.toast("按住 E 蓄力，松开把引魂索甩进水里、兔子洞、草原或花丛", Color(0.8, 0.95, 1.0), 6.0)


func _exit_tree() -> void:
	Sfx.stop_ambient()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func capture_mouse(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func set_paused(p: bool) -> void:
	paused = p
	player.input_enabled = not p
	capture_mouse(not p)
	hud.show_pause(p)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		set_paused(not paused)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("fullscreen"):
		Settings.toggle_fullscreen()
	elif event.is_action_pressed("toggle_fps"):
		Settings.show_fps = not Settings.show_fps
		Settings.save_settings()
	elif event is InputEventMouseButton and event.pressed and not paused and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		capture_mouse(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not paused and is_inside_tree():
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


# ------------------------------------------------------------------ 工具

func raycast(from: Vector3, to: Vector3, mask: int, exclude: Array[RID] = []) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
	return get_world_3d().direct_space_state.intersect_ray(q)


func nearest_player_pos(p: Vector3) -> Vector3:
	var best := player.global_position
	for r in remotes.values():
		if (r as Node3D).global_position.distance_to(p) < best.distance_to(p):
			best = r.global_position
	return best


func _stat(id: int) -> Dictionary:
	if not stats.has(id):
		stats[id] = {"kills": 0, "earned": 0}
	return stats[id]


# ------------------------------------------------------------------ 开枪（本地玩家）

func _falloff(w: Dictionary, dist: float) -> float:
	var k := clampf((dist - w["falloff_start"]) / maxf(w["falloff_end"] - w["falloff_start"], 0.01), 0.0, 1.0)
	return lerpf(1.0, w["falloff_min"], k)


func local_fire(wi: int, origin: Vector3, dirs: Array[Vector3], muzzle: Vector3) -> void:
	var w: Dictionary = Data.WEAPONS[wi]
	var ends: Array = []
	var per_beast := {}
	var exclude: Array[RID] = [player.get_rid()]
	var single: bool = w["pellets"] == 1
	for dir in dirs:
		var to: Vector3 = origin + dir * w["range"]
		var hit := raycast(origin, to, U.LAYER_WORLD | U.LAYER_BEAST, exclude)
		var end := to
		var hit_dist := INF if hit.is_empty() else origin.distance_to(hit["position"])
		# 子弹打进水里就停
		var water_dist := INF
		if dir.y < -0.001 and origin.y > Island.WATER_Y:
			water_dist = (origin.y - Island.WATER_Y) / -dir.y
			var wp := origin + dir * water_dist
			if island.is_land(wp.x, wp.z) or water_dist > w["range"]:
				water_dist = INF
		if water_dist < hit_dist:
			end = origin + dir * water_dist
			if single or randf() < 0.3:
				fx.splash(end)
		elif not hit.is_empty():
			end = hit["position"]
			var col: Object = hit["collider"]
			if col is Beast and (col as Beast).alive():
				var b := col as Beast
				var head := b.is_head(int(hit["shape"]))
				var dmg: float = w["damage"] * _falloff(w, hit_dist) * (w["headshot"] if head else 1.0)
				if not per_beast.has(b.id):
					per_beast[b.id] = {"dmg": 0.0, "imp": Vector3.ZERO, "pts": Vector3.ZERO, "n": 0, "head": false, "dist": hit_dist}
				var h: Dictionary = per_beast[b.id]
				h["dmg"] += dmg
				h["imp"] += dir * w["impulse"] + Vector3.UP * w["impulse"] * w["lift"]
				h["pts"] += b.to_local(end)
				h["n"] += 1
				h["head"] = h["head"] or head
				fx.impact_beast(end, hit["normal"], Data.age_color(b.age), head)
			else:
				fx.impact_world(end, hit["normal"])
		ends.append(end)
	for e in ends:
		if single:
			fx.tracer(muzzle, e, w["tracer"], 0.02, 380.0, 4.0)
		else:
			fx.tracer(muzzle, e, w["tracer"], 0.009, 260.0, 1.6)
	fx.muzzle_flash(muzzle, dirs[0], w["tracer"], not single)
	Net.send(0, "shot", [wi, muzzle, ends])

	for id in per_beast:
		var h: Dictionary = per_beast[id]
		var b: Beast = beasts.get(id)
		if not b:
			continue
		var local_pt: Vector3 = h["pts"] / float(h["n"])
		hud.hitmarker(h["head"], false)
		Sfx.play("hit_head" if h["head"] else "hit", -2.0 if h["head"] else -4.0, 0.05)
		if Net.is_host():
			var killed := _host_apply_hit(b, h["dmg"], h["imp"], local_pt, h["head"], Net.my_id, h["dist"])
			fx.damage_number(b.global_position + Vector3(0, 0.3, 0), h["dmg"], h["head"], killed)
		else:
			b.flinch(h["imp"])
			fx.damage_number(b.global_position + Vector3(0, 0.3, 0), h["dmg"], h["head"])
			Net.send(1, "hit", [id, h["dmg"], h["imp"], local_pt, h["head"], h["dist"]])


# ------------------------------------------------------------------ 引魂索拽出魂兽

func request_yank(pos: Vector3, habitat: String, species: String, age: int) -> void:
	Net.send_host("yank", [pos, habitat, species, age, player.global_position])


func _launch_velocity(from: Vector3, owner_pos: Vector3, species: String) -> Vector3:
	var g := 9.8 * float(Data.BEASTS[species]["gravity"])
	var to_owner := owner_pos - from
	to_owner.y = 0.0
	var d := to_owner.length()
	var land: Vector3
	if d < 2.0:
		land = from + Vector3(1.5, 0, 0)
	else:
		# 落在玩家面前几米，正好是最好打的位置
		land = owner_pos - to_owner.normalized() * clampf(d * 0.3, 3.0, 7.0)
	land.y = island.height_at(land.x, land.z) if island.is_land(land.x, land.z) else Island.WATER_Y
	var apex := maxf(from.y, land.y) + float(Data.LURE["launch_height"]) * rng.randf_range(0.85, 1.15)
	var vy := sqrt(2.0 * g * (apex - from.y))
	var t_total := vy / g + sqrt(2.0 * maxf(apex - land.y, 0.1) / g)
	var hor := land - from
	hor.y = 0.0
	return hor / t_total + Vector3(0, vy, 0)


func _host_spawn(owner: int, pos: Vector3, species: String, age: int, owner_pos: Vector3) -> void:
	if not Data.BEASTS.has(species):
		return
	age = clampi(age, 0, Data.AGES.size() - 1)
	var id := next_beast_id
	next_beast_id += 1
	var spawn := pos + Vector3(0, 0.4, 0)
	if not island.is_land(pos.x, pos.z):
		spawn.y = maxf(spawn.y, Island.WATER_Y + 0.3)
	var vel := _launch_velocity(spawn, owner_pos, species)
	_spawn_beast(id, species, age, spawn, vel, owner, false)
	Net.send(0, "bsp", [id, species, age, spawn, vel, owner])


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


# ------------------------------------------------------------------ 房主：命中、击杀、逃跑

func _host_apply_hit(b: Beast, dmg: float, imp: Vector3, local_pt: Vector3, head: bool, shooter: int, dist: float) -> bool:
	if not b.alive():
		return false
	var dead := b.take_hit(dmg, imp, local_pt, head, shooter, dist)
	if dead:
		_host_kill(b)
	return dead


func _host_kill(b: Beast) -> void:
	var killer := b.last_hitter
	var base: float = float(Data.BEASTS[b.species]["reward"]) * float(Data.AGES[b.age]["reward"])
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
	wallet += reward
	var st := _stat(killer)
	st["kills"] += 1
	st["earned"] += reward
	var msg := [b.id, killer, reward, tags, b.species, b.age, b.global_position, wallet, st["kills"], st["earned"]]
	Net.send(0, "bk", msg)
	_on_kill(msg)


func beast_escaped(b: Beast, reason: String) -> void:
	if not Net.is_host() or not b.alive():
		return
	var msg := [b.id, reason, b.global_position]
	Net.send(0, "be", msg)
	_on_escape(msg)


func _on_kill(msg: Array) -> void:
	var id := int(msg[0])
	var killer := int(msg[1])
	var reward := int(msg[2])
	var tags: Array = msg[3]
	var species := str(msg[4])
	var age := int(msg[5])
	var pos: Vector3 = msg[6]
	wallet = int(msg[7])
	var st := _stat(killer)
	st["kills"] = int(msg[8])
	st["earned"] = int(msg[9])
	var b: Beast = beasts.get(id)
	if b:
		pos = b.global_position
		_remove_beast(b)
	fx.death_burst(pos, Data.age_color(age), age)
	Sfx.play_at("kill_burst", pos, 0.0, 0.05)
	var who := Net.peer_name(killer)
	hud.feed("%s 击杀 %s·%s  +%d" % [who, Data.age_name(age), Data.BEASTS[species]["name"], reward], Data.age_color(age))
	hud.set_wallet(wallet)
	if killer == Net.my_id:
		hud.hitmarker(false, true)
		hud.kill_popup(reward, tags, species, age)
		Sfx.play("kill", -1.0)
		Sfx.play("coin", -4.0, 0.03)


func _on_escape(msg: Array) -> void:
	var id := int(msg[0])
	var reason := str(msg[1])
	var pos: Vector3 = msg[2]
	var b: Beast = beasts.get(id)
	if not b:
		return
	var nm: String = Data.BEASTS[b.species]["name"]
	pos = b.global_position
	_remove_beast(b)
	match reason:
		"splash":
			fx.splash(pos, true)
			Sfx.play_at("splash_big", pos, -2.0)
			hud.feed("%s 逃回了水里" % nm, Color(0.7, 0.7, 0.7))
		"burrow":
			fx.dirt_puff(pos)
			hud.feed("%s 钻回了洞里" % nm, Color(0.7, 0.7, 0.7))
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
		arr.append_array([float(b.id), p.x, p.y, p.z, q.x, q.y, q.z, q.w, float(b.state), b.hp / b.max_hp])
	Net.send(0, "bs", arr)


func _on_peer_joined(_id: int, _name: String) -> void:
	pass  # 等对方的 hello 再建人物


func _on_peer_left(id: int) -> void:
	if remotes.has(id):
		hud.feed("%s 离开了" % remotes[id].get_meta("name", "魂师"), Color(0.8, 0.8, 0.8))
		remotes[id].queue_free()
		remotes.erase(id)


func _add_remote(id: int, nm: String, wuhun: int) -> void:
	if remotes.has(id):
		return
	var r := RemotePlayer.new()
	r.setup(self, id, nm, wuhun)
	r.set_meta("name", nm)
	players_root.add_child(r)
	r.set_camera(player.cam)
	remotes[id] = r
	_stat(id)
	hud.feed("%s 加入了" % nm, Color(0.6, 0.95, 0.7))


func _on_message(from: int, type: String, data: Variant) -> void:
	match type:
		"hello":
			var d: Array = data
			_add_remote(from, str(d[0]), int(d[1]))
			if bool(d[2]):
				Net.send(from, "hello", [Settings.display_name(), Settings.wuhun, false])
				if Net.is_host():
					_send_init(from)
		"ps":
			if remotes.has(from):
				remotes[from].push_snapshot(data)
		"shot":
			var d: Array = data
			var w: Dictionary = Data.WEAPONS[clampi(int(d[0]), 0, Data.WEAPONS.size() - 1)]
			var muzzle: Vector3 = d[1]
			if remotes.has(from):
				muzzle = remotes[from].muzzle_global()
			for e in d[2]:
				fx.tracer(muzzle, e, w["tracer"], 0.02 if w["pellets"] == 1 else 0.009, 380.0 if w["pellets"] == 1 else 260.0, 4.0 if w["pellets"] == 1 else 1.6)
			Sfx.play_at(w["sound"], muzzle, 0.0, 0.06)
		"yank":
			if Net.is_host():
				var d: Array = data
				_host_spawn(from, d[0], str(d[2]), int(d[3]), d[4])
		"hit":
			if Net.is_host():
				var d: Array = data
				var b: Beast = beasts.get(int(d[0]))
				if b:
					_host_apply_hit(b, float(d[1]), d[2], d[3], bool(d[4]), from, float(d[5]))
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
		"init":
			var d: Array = data
			wallet = int(d[0])
			hud.set_wallet(wallet)
			for e in d[1]:
				if not beasts.has(int(e[0])):
					var b := _spawn_beast(int(e[0]), str(e[1]), int(e[2]), e[3], Vector3.ZERO, int(e[4]), true)
					b.set_hp_from_ratio(float(e[5]))
			var s: Dictionary = d[2]
			for k in s:
				stats[int(k)] = s[k]


func _send_init(to: int) -> void:
	var list := []
	for b: Beast in beasts.values():
		if b.alive():
			list.append([b.id, b.species, b.age, b.global_position, b.owner_peer, b.hp / b.max_hp])
	Net.send(to, "init", [wallet, list, stats])


func leave() -> void:
	leave_requested.emit()
