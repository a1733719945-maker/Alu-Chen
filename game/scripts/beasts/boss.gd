class_name Boss
extends Node3D
## Boss：房主算 AI 和血量，客人按快照插值显示。
##
## mandala 千年曼陀罗蛇：待在湖里，头露出水面。
##   喷毒 —— 毒液落地变成毒池；蛇尾砸 —— 地上先出红圈，1.3 秒后砸下；
##   潜水 —— 沉下去，从玩家附近的水里跃出；半血以下召唤小蛇
## spider 人面魔蛛：在古树林里爬。
##   吐网 —— 被网到会减速；跳砸 —— 红圈预警后跳过来；喷毒；半血以下更快
## 打头（脸）是弱点，伤害 ×2；打身体 ×0.6

const INTERP_DELAY := 0.1

var world: Node
var kind := "mandala"
var proxy := false
var max_hp := 3000.0
var hp := 3000.0
var state := "emerge"
var state_t := 0.0
var phase := 1
var damagers := {}
var dead := false

var head: Node3D                 # 头（也是整体位置）
var parts: Array[StaticBody3D] = []
var segs: Array[Node3D] = []     # 蛇身
var legs: Array[Node3D] = []     # 蛛腿
var body_node: Node3D
var _path: Array[Vector3] = []   # 头走过的路径，蛇身跟着
var _path_t := 0.0
var _move_to := Vector3.ZERO
var _anchor := Vector3.ZERO
var _atk_cd := 3.0
var _dive_cd := 14.0
var _summon_cd := 10.0
var _yaw := 0.0
var _t := 0.0
var _snaps: Array = []
var _root_t := 0.0


func setup(p_world: Node, p_kind: String, p_hp: float, p_proxy: bool, anchor: Vector3) -> void:
	world = p_world
	kind = p_kind
	proxy = p_proxy
	max_hp = p_hp
	hp = p_hp
	_anchor = anchor
	name = "Boss"
	if kind == "mandala":
		_build_snake()
	else:
		_build_spider()


# ------------------------------------------------------------------ 模型

func _part_body(parent: Node3D, r: float, weak: bool) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = U.LAYER_BEAST
	b.collision_mask = 0
	b.set_meta("boss", true)
	b.set_meta("weak", weak)
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = r
	cs.shape = sh
	b.add_child(cs)
	b.top_level = true
	parent.add_child(b)
	parts.append(b)
	return b


func _build_snake() -> void:
	var skin := U.mat(Color(0.22, 0.08, 0.28), 0.45)
	var belly := U.mat(Color(0.7, 0.55, 0.3), 0.6)
	var mark := U.glow(Color(1.0, 0.3, 0.7), 2.5)
	var eye := U.glow(Color(0.9, 1.0, 0.25), 5.0)
	var fang := U.mat(Color(0.95, 0.95, 0.9), 0.4)
	head = Node3D.new()
	head.name = "Head"
	head.top_level = true
	add_child(head)
	U.part(head, U.sphere(1.3, 18, 12), skin, Vector3.ZERO, Vector3.ZERO, Vector3(1.1, 0.75, 1.5))
	U.part(head, U.sphere(0.95, 14, 10), belly, Vector3(0, -0.35, -0.2), Vector3.ZERO, Vector3(1.0, 0.5, 1.3))
	for side in [-1.0, 1.0]:
		U.part(head, U.sphere(0.2, 8, 6), eye, Vector3(0.68 * side, 0.35, -1.0))
		U.part(head, U.cyl(0.0, 0.1, 0.55, 6), fang, Vector3(0.35 * side, -0.55, -1.45), Vector3(0.15, 0, 0))
	# 曼陀罗花冠
	for k in 8:
		var a := TAU * k / 8.0
		U.part(head, U.cyl(0.0, 0.32, 1.2, 5), mark, Vector3(cos(a) * 0.9, 0.9, 0.4 + sin(a) * 0.6), Vector3(-0.7 + sin(a) * 0.3, a, 0))
	var ring := U.part(head, U.torus(2.4, 2.6, 64, 6), U.glow(Data.age_color(2), 4.0), Vector3(0, -0.6, 0.6), Vector3.ZERO, Vector3.ONE, false)
	ring.name = "Ring"
	var hb := _part_body(self, 1.35, true)
	hb.set_meta("follow", head)
	for i in 16:
		var t := float(i) / 15.0
		var seg := Node3D.new()
		seg.top_level = true
		add_child(seg)
		var r := lerpf(1.15, 0.45, t)
		U.part(seg, U.sphere(r, 14, 10), skin)
		U.part(seg, U.sphere(r * 0.85, 10, 6), belly, Vector3(0, -r * 0.35, 0), Vector3.ZERO, Vector3(1.0, 0.6, 1.0))
		if i % 2 == 0:
			U.part(seg, U.sphere(r * 0.3, 6, 4), mark, Vector3(0, r * 0.85, 0))
		segs.append(seg)
		var sb := _part_body(self, r, false)
		sb.set_meta("follow", seg)
	head.global_position = _anchor + Vector3(0, -6, 0)
	for i in 60:
		_path.append(head.global_position)


func _build_spider() -> void:
	var shell := U.mat(Color(0.12, 0.08, 0.14), 0.4)
	var hairy := U.mat(Color(0.2, 0.14, 0.18), 0.9)
	var face := U.mat(Color(0.88, 0.82, 0.78), 0.6)
	var mark := U.glow(Color(0.7, 0.2, 1.0), 2.5)
	var eye := U.glow(Color(1.0, 0.2, 0.2), 5.0)
	head = Node3D.new()
	head.name = "Head"
	head.top_level = true
	add_child(head)
	body_node = Node3D.new()
	head.add_child(body_node)
	U.part(body_node, U.sphere(1.6, 18, 12), shell, Vector3(0, 0.6, 1.6), Vector3.ZERO, Vector3(1.0, 0.85, 1.2))
	U.part(body_node, U.sphere(0.45, 10, 6), mark, Vector3(0, 1.8, 1.4))
	U.part(body_node, U.sphere(1.0, 14, 10), hairy, Vector3(0, 0.3, -0.1), Vector3.ZERO, Vector3(1.0, 0.8, 1.0))
	# 人面：一张苍白的脸
	U.part(body_node, U.sphere(0.62, 14, 10), face, Vector3(0, 0.35, -0.95), Vector3.ZERO, Vector3(1.0, 1.1, 0.6))
	for side in [-1.0, 1.0]:
		U.part(body_node, U.sphere(0.1, 8, 6), eye, Vector3(0.22 * side, 0.5, -1.28))
		U.part(body_node, U.sphere(0.06, 6, 4), eye, Vector3(0.45 * side, 0.75, -1.15))
	U.part(body_node, U.box(Vector3(0.3, 0.05, 0.05)), U.mat(Color(0.3, 0.05, 0.08)), Vector3(0, 0.12, -1.3))
	var ring := U.part(body_node, U.torus(2.6, 2.8, 64, 6), U.glow(Data.age_color(2), 4.0), Vector3(0, -0.4, 0.4), Vector3.ZERO, Vector3.ONE, false)
	ring.name = "Ring"
	for k in 8:
		var side := -1.0 if k % 2 == 0 else 1.0
		var zz := -0.6 + (k / 2) * 0.55
		var leg := Node3D.new()
		leg.position = Vector3(0.7 * side, 0.4, zz)
		body_node.add_child(leg)
		var upper := Node3D.new()
		upper.rotation = Vector3(0, 0, -0.9 * side)
		leg.add_child(upper)
		U.part(upper, U.capsule(0.13, 1.6), hairy, Vector3(0.7 * side, 0, 0), Vector3(0, 0, PI / 2))
		var lower := Node3D.new()
		lower.position = Vector3(1.45 * side, 0, 0)
		lower.rotation = Vector3(0, 0, 1.9 * side)
		upper.add_child(lower)
		U.part(lower, U.capsule(0.1, 1.9), shell, Vector3(0.85 * side, 0, 0), Vector3(0, 0, PI / 2))
		leg.set_meta("side", side)
		leg.set_meta("phase", float(k) * 0.8)
		legs.append(leg)
	var hb := _part_body(self, 0.75, true)
	hb.set_meta("follow", head)
	hb.set_meta("offset", Vector3(0, 0.35, -0.95))
	var bb := _part_body(self, 1.7, false)
	bb.set_meta("follow", head)
	bb.set_meta("offset", Vector3(0, 0.6, 1.2))
	var cb := _part_body(self, 1.1, false)
	cb.set_meta("follow", head)
	cb.set_meta("offset", Vector3(0, 0.3, 0.0))
	head.global_position = _anchor + Vector3(0, 12, 0)


# ------------------------------------------------------------------ 房主：受伤

func take_hit(dmg: float, weak: bool, shooter: int) -> float:
	if dead:
		return 0.0
	var real := dmg * (1.7 if weak else 0.6)
	hp -= real
	damagers[shooter] = float(damagers.get(shooter, 0.0)) + real
	if hp <= max_hp * 0.5 and phase == 1:
		phase = 2
		world.boss_phase2()
	if hp <= 0.0:
		hp = 0.0
		dead = true
		world.boss_died(self)
	return real


func root(t: float) -> void:
	_root_t = maxf(_root_t, t * 0.5)


func center() -> Vector3:
	return head.global_position


# ------------------------------------------------------------------ 房主：AI

func _set_state(s: String) -> void:
	state = s
	state_t = 0.0


func _process(dt: float) -> void:
	_t += dt
	if proxy:
		_interpolate()
	elif not dead:
		_think(dt)
	_update_visual(dt)


func _targets() -> Array:
	return world.alive_players()


func _pick_target() -> Dictionary:
	var ps := _targets()
	if ps.is_empty():
		return {}
	return ps[randi() % ps.size()]


func _think(dt: float) -> void:
	state_t += dt
	var speed_k := 0.5 if _root_t > 0.0 else (1.35 if phase == 2 else 1.0)
	_root_t = maxf(_root_t - dt, 0.0)
	if kind == "mandala":
		_think_snake(dt, speed_k)
	else:
		_think_spider(dt, speed_k)


func _think_snake(dt: float, speed_k: float) -> void:
	var h := head.global_position
	match state:
		"emerge":
			var target := _anchor + Vector3(0, 4.5, 0)
			head.global_position = h.lerp(target, 1.0 - exp(-2.0 * dt))
			if state_t > 2.5:
				_set_state("idle")
				_move_to = _patrol_point()
		"idle":
			_atk_cd -= dt * speed_k
			_dive_cd -= dt * speed_k
			if phase == 2:
				_summon_cd -= dt
				if _summon_cd <= 0.0:
					_summon_cd = 11.0
					world.boss_summon(self, "snake", 2)
			var to := _move_to - h
			if to.length() < 1.5:
				_move_to = _patrol_point()
			head.global_position = h + to.limit_length(3.2 * speed_k * dt)
			head.global_position.y = _anchor.y + 4.5 + sin(_t * 1.3) * 0.8
			_face_toward(world.nearest_player_pos(h), dt)
			if _dive_cd <= 0.0:
				_dive_cd = 16.0
				_set_state("dive")
			elif _atk_cd <= 0.0:
				var tp := _pick_target()
				if not tp.is_empty():
					var near: bool = Vector2(tp["pos"].x - h.x, tp["pos"].z - h.z).length() < 22.0
					if near and randf() < 0.55:
						_atk_cd = 3.2
						world.boss_telegraph(tp["pos"], 5.5, 1.3, 32.0, "slam", h)
					else:
						_atk_cd = 3.0 if phase == 1 else 2.2
						var n := 1 if phase == 1 else 3
						for i in n:
							var off := Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)) * (0 if i == 0 else 1)
							world.boss_projectile("spit", h + Vector3(0, -0.5, 0) - head.global_basis.z * 1.5, tp["pos"] + off, 1.2, 3.5, 14.0)
		"dive":
			head.global_position.y = move_toward(h.y, _anchor.y - 6.0, 6.0 * dt)
			if state_t > 1.6:
				var tp := _pick_target()
				var pos := _anchor
				if not tp.is_empty():
					pos = world.water_point_near(tp["pos"])
				head.global_position = Vector3(pos.x, _anchor.y - 6.0, pos.z)
				_move_to = pos
				world.boss_telegraph(Vector3(pos.x, 0.0, pos.z), 6.5, 1.3, 30.0, "leap", pos)
				_set_state("leap")
		"leap":
			if state_t > 1.2:
				head.global_position = head.global_position.lerp(Vector3(_move_to.x, _anchor.y + 5.0, _move_to.z), 1.0 - exp(-6.0 * dt))
			if state_t > 2.4:
				_anchor = Vector3(head.global_position.x, _anchor.y, head.global_position.z)
				_set_state("idle")
				_move_to = _patrol_point()


func _patrol_point() -> Vector3:
	return _anchor + Vector3(randf_range(-14, 14), 0, randf_range(-8, 8))


func _think_spider(dt: float, speed_k: float) -> void:
	var h := head.global_position
	var ground: float = world.island.height_at(h.x, h.z)
	match state:
		"emerge":
			# 从树冠上掉下来
			head.global_position.y = move_toward(h.y, ground + 1.6, 14.0 * dt)
			if state_t > 1.5:
				_set_state("idle")
		"idle":
			_atk_cd -= dt * speed_k
			var tp: Dictionary = world.nearest_player(h)
			if tp.is_empty():
				return
			var to: Vector3 = tp["pos"] - h
			to.y = 0
			var dist := to.length()
			var dir := to.normalized()
			var side := dir.cross(Vector3.UP)
			var want := dir * (1.0 if dist > 14.0 else (-1.0 if dist < 9.0 else 0.0)) + side * 0.6
			var np := h + want.normalized() * 4.5 * speed_k * dt
			var c := Vector3(_anchor.x, 0, _anchor.z)
			if Vector3(np.x, 0, np.z).distance_to(c) < 30.0:
				head.global_position = Vector3(np.x, world.island.height_at(np.x, np.z) + 1.6, np.z)
			_face_toward(tp["pos"], dt)
			if _atk_cd <= 0.0:
				var r := randf()
				if r < 0.35:
					_atk_cd = 2.2 if phase == 1 else 1.6
					var n := 1 if phase == 1 else 3
					for i in n:
						var off := Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5)) * (0 if i == 0 else 1)
						world.boss_projectile("web", h + Vector3(0, 0.4, 0) - head.global_basis.z * 1.2, tp["pos"] + off, 0.9, 2.2, 10.0)
				elif r < 0.65:
					_atk_cd = 2.6
					world.boss_projectile("spit", h + Vector3(0, 0.4, 0) - head.global_basis.z * 1.2, tp["pos"], 1.1, 3.5, 14.0)
				else:
					_atk_cd = 3.4
					_move_to = tp["pos"]
					world.boss_telegraph(tp["pos"], 5.0, 1.3, 40.0, "leap", tp["pos"])
					_set_state("leap")
		"leap":
			if state_t < 1.3:
				head.global_position.y = world.island.height_at(h.x, h.z) + 1.6 - sin(state_t / 1.3 * PI) * 0.4
			elif state_t < 1.8:
				var k := (state_t - 1.3) / 0.5
				var p := h.lerp(Vector3(_move_to.x, h.y, _move_to.z), k)
				p.y = world.island.height_at(p.x, p.z) + 1.6 + sin(k * PI) * 6.0
				head.global_position = p
			else:
				_set_state("idle")


func _face_toward(p: Vector3, dt: float) -> void:
	var to := p - head.global_position
	to.y = 0
	if to.length() < 0.1:
		return
	var target_yaw := atan2(-to.x, -to.z)
	_yaw = lerp_angle(_yaw, target_yaw, 1.0 - exp(-3.0 * dt))


# ------------------------------------------------------------------ 同步

func snapshot() -> Array:
	return [head.global_position, _yaw, hp / max_hp, state]


func push_snapshot(s: Array) -> void:
	_snaps.append([Time.get_ticks_msec() / 1000.0, s[0], float(s[1])])
	hp = float(s[2]) * max_hp
	state = str(s[3])
	if _snaps.size() > 12:
		_snaps.pop_front()


func _interpolate() -> void:
	if _snaps.is_empty():
		return
	var t := Time.get_ticks_msec() / 1000.0 - INTERP_DELAY
	var s1: Array = _snaps[-1]
	var s0: Array = s1
	var k := 1.0
	for i in range(_snaps.size() - 1):
		if t >= _snaps[i][0] and t <= _snaps[i + 1][0]:
			s0 = _snaps[i]
			s1 = _snaps[i + 1]
			k = (t - s0[0]) / maxf(s1[0] - s0[0], 0.0001)
			break
	head.global_position = (s0[1] as Vector3).lerp(s1[1], k)
	_yaw = lerp_angle(float(s0[2]), float(s1[2]), k)


# ------------------------------------------------------------------ 画面（房主和客人都跑）

func _update_visual(dt: float) -> void:
	head.global_basis = Basis(Vector3.UP, _yaw)
	if kind == "mandala":
		_path_t += dt
		if _path_t > 0.06:
			_path_t = 0.0
			_path.push_front(head.global_position)
			if _path.size() > 80:
				_path.pop_back()
		for i in segs.size():
			var idx := mini((i + 1) * 3, _path.size() - 1)
			var p: Vector3 = _path[idx]
			# 越往后越沉进水里
			p.y = lerpf(p.y - 1.0, _anchor.y - 1.2, clampf(float(i) / segs.size() * 1.6, 0.0, 1.0))
			p.y += sin(_t * 2.0 + i * 0.7) * 0.25
			segs[i].global_position = p
		var ring := head.get_node("Ring")
		ring.rotation.y += dt * 0.8
	else:
		var moving := state == "idle"
		for leg in legs:
			var ph: float = leg.get_meta("phase")
			var sd: float = leg.get_meta("side")
			leg.rotation.y = sin(_t * 8.0 + ph) * (0.35 if moving else 0.08)
			leg.rotation.z = sin(_t * 8.0 + ph + PI / 2) * (0.2 if moving else 0.05) * sd
		body_node.position.y = sin(_t * 3.0) * 0.1
		body_node.get_node("Ring").rotation.y += dt * 0.8
	for b in parts:
		var f: Node3D = b.get_meta("follow")
		var off: Vector3 = b.get_meta("offset", Vector3.ZERO)
		b.global_position = f.global_transform * off
