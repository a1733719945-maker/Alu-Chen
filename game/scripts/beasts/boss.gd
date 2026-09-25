class_name Boss
extends Node3D
## Boss：房主算 AI 和血量，客人按快照插值显示。模型和数值在 Data.BOSSES 里。
##
## ai = water（千年曼陀罗蛇、深海魔鲸）：待在水里，头露出水面。
##   喷毒 —— 毒液落地变成毒池；尾巴砸 —— 地上先出红圈，1.3 秒后砸下；
##   潜水 —— 沉下去，从玩家附近的水里跃出；半血以下召唤小怪
## ai = land（人面魔蛛、泰坦巨猿）：在空地上绕着玩家走。
##   吐网 / 扔石头；跳砸 —— 红圈预警后跳过来；喷毒；半血以下更快
## ai = air（冰霜巨龙）：在天上盘旋。
##   冰息 —— 冻住的地方会减速；俯冲 —— 红圈预警后冲下来；半血以下召唤雪原狼
## 打头是弱点，伤害 ×1.7；打身体 ×0.6

const INTERP_DELAY := 0.1

var world: Node
var kind := "mandala"
var cfg: Dictionary
var ai := "water"
var proxy := false
var max_hp := 3000.0
var hp := 3000.0
var state := "emerge"
var state_t := 0.0
var phase := 1
var damagers := {}
var dead := false

var head: Node3D                 # 整个 Boss 的位置（模型中心）
var model: Node3D
var parts: Array[StaticBody3D] = []
var size := Vector3(4, 4, 4)     # 缩放后的宽、高、长
var _upright := false
var _move_to := Vector3.ZERO
var _anchor := Vector3.ZERO
var _atk_cd := 3.0
var _dive_cd := 14.0
var _summon_cd := 10.0
var _yaw := 0.0
var _t := 0.0
var _snaps: Array = []
var _root_t := 0.0
var _orbit := 0.0
var _last_pos := Vector3.ZERO
var _speed := 0.0
var _dying := -1.0
var _fall_v := 0.0


func setup(p_world: Node, p_kind: String, p_hp: float, p_proxy: bool, anchor: Vector3) -> void:
	world = p_world
	kind = p_kind
	cfg = Data.BOSSES[kind]
	ai = str(cfg.get("ai", "land"))
	proxy = p_proxy
	max_hp = p_hp
	hp = p_hp
	_anchor = anchor
	name = "Boss"
	_build()


# ------------------------------------------------------------------ 模型和碰撞

func _part_body(r: float, weak: bool, offset: Vector3) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = U.LAYER_BEAST
	b.collision_mask = 0
	b.set_meta("boss", true)
	b.set_meta("weak", weak)
	b.set_meta("offset", offset)
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = r
	cs.shape = sh
	b.add_child(cs)
	b.top_level = true
	add_child(b)
	parts.append(b)


func _build() -> void:
	head = Node3D.new()
	head.name = "Head"
	head.top_level = true
	add_child(head)
	model = BeastModels.instance_model(cfg)
	head.add_child(model)
	var d := BeastModels._dims(str(cfg["model"]))
	var k := BeastModels._model_scale(cfg)
	size = Vector3(float(d["w"]), float(d["h"]), float(d["l"])) * k
	_upright = size.y > size.z * 1.15
	# 年份光环
	var r := maxf(size.x, size.z) * 0.55
	var ring := U.part(head, U.torus(r, r + 0.25, 64, 6), U.glow(Data.age_color(2), 4.0), Vector3(0, -size.y * 0.35, 0), Vector3.ZERO, Vector3.ONE, false)
	ring.name = "Ring"
	# 碰撞：身体几个球，头是弱点
	if _upright:
		var rb := minf(size.x, size.z) * 0.45
		_part_body(rb, false, Vector3(0, -size.y * 0.2, 0))
		_part_body(rb * 0.9, false, Vector3(0, size.y * 0.05, 0))
		_part_body(rb * 0.75, true, Vector3(0, size.y * 0.3, -size.z * 0.1))
	else:
		var rb := minf(size.x, size.y) * 0.45
		_part_body(rb, false, Vector3(0, 0, size.z * 0.05))
		_part_body(rb * 0.85, false, Vector3(0, 0, size.z * 0.3))
		_part_body(rb * 0.7, true, Vector3(0, size.y * 0.1, -size.z * 0.36))
	match ai:
		"water":
			head.global_position = _anchor + Vector3(0, -size.y, 0)
		"land":
			head.global_position = _anchor + Vector3(0, 14, 0)
		"air":
			head.global_position = _anchor + Vector3(0, 40, 0)


## 露出水面 / 离地多高（模型中心）
func _hover() -> float:
	match ai:
		"water":
			return size.y * (0.35 if _upright else 0.18)
		"air":
			return 14.0
	return size.y * 0.5


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


## 弱点（头）的位置
func weak_point() -> Vector3:
	for b in parts:
		if b.get_meta("weak"):
			return b.global_position
	return head.global_position


# ------------------------------------------------------------------ 房主：AI

func _set_state(s: String) -> void:
	state = s
	state_t = 0.0
	if s in ["leap", "dive_attack"]:
		BeastModels.play_role(model, "attack")


## 死了：不能再被打中，播死亡动画；飞的摔下来，水里的沉下去，最后炸成魂光
func die_visual() -> void:
	dead = true
	_dying = 0.0
	for b in parts:
		b.collision_layer = 0
	head.get_node("Ring").visible = false
	BeastModels.play_role(model, "death")


func _dying_tick(dt: float) -> void:
	_dying += dt
	var p := head.global_position
	if ai == "water":
		p.y -= dt * size.y * 0.35
	else:
		var rest := maxf(world.island.height_at(p.x, p.z), Island.WATER_Y - size.y * 0.3) + size.y * 0.5
		if p.y > rest:
			_fall_v += 9.8 * 1.6 * dt
			p.y = maxf(p.y - _fall_v * dt, rest)
			if p.y <= rest:
				world.fx.explosion(p + Vector3(0, -size.y * 0.4, 0), size.x * 0.6, Color(0.75, 0.7, 0.6))
				Sfx.play_at("slam", p, 2.0)
	head.global_position = p
	if _dying > 2.4:
		_dying = -100.0
		world.fx.death_burst(p, Data.age_color(2), 3)
		world.fx.explosion(p, 8.0, Color(0.8, 0.3, 1.0))
		queue_free()


func _process(dt: float) -> void:
	_t += dt
	if _dying >= 0.0:
		_dying_tick(dt)
		return
	if _dying < -1.0:
		return
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
	match ai:
		"water":
			_think_water(dt, speed_k)
		"air":
			_think_air(dt, speed_k)
		_:
			_think_land(dt, speed_k)


func _summon_tick(dt: float) -> void:
	if phase != 2:
		return
	_summon_cd -= dt
	if _summon_cd <= 0.0:
		_summon_cd = 11.0
		world.boss_summon(self, str(cfg.get("summon", "wolf")), 2)


func _mouth() -> Vector3:
	return weak_point() - head.global_basis.z * size.z * 0.1


func _think_water(dt: float, speed_k: float) -> void:
	var h := head.global_position
	var surf := _anchor.y + _hover()
	match state:
		"emerge":
			var target := Vector3(_anchor.x, surf, _anchor.z)
			head.global_position = h.lerp(target, 1.0 - exp(-2.0 * dt))
			if state_t > 2.5:
				_set_state("idle")
				_move_to = _patrol_point()
		"idle":
			_atk_cd -= dt * speed_k
			_dive_cd -= dt * speed_k
			_summon_tick(dt)
			var to := _move_to - h
			to.y = 0
			if to.length() < 1.5:
				_move_to = _patrol_point()
			var np := h + to.limit_length(3.2 * speed_k * dt)
			np.y = surf + sin(_t * 1.3) * 0.8
			head.global_position = np
			_face_toward(world.nearest_player_pos(h) if _upright else _move_to, dt)
			if _dive_cd <= 0.0:
				_dive_cd = 16.0
				_set_state("dive")
			elif _atk_cd <= 0.0:
				var tp := _pick_target()
				if not tp.is_empty():
					var near: bool = Vector2(tp["pos"].x - h.x, tp["pos"].z - h.z).length() < 22.0 + size.z * 0.5
					if near and randf() < 0.55:
						_atk_cd = 3.2
						world.boss_telegraph(tp["pos"], 5.5, 1.3, 32.0, "slam", h)
						BeastModels.play_role(model, "attack")
					else:
						_atk_cd = 3.0 if phase == 1 else 2.2
						var n := 1 if phase == 1 else 3
						for i in n:
							var off := Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)) * (0 if i == 0 else 1)
							world.boss_projectile("spit", _mouth(), tp["pos"] + off, 1.2, 3.5, 14.0)
		"dive":
			head.global_position.y = move_toward(h.y, _anchor.y - size.y, 6.0 * dt)
			if state_t > 1.6:
				var tp := _pick_target()
				var pos := _anchor
				if not tp.is_empty():
					pos = world.water_point_near(tp["pos"])
				head.global_position = Vector3(pos.x, _anchor.y - size.y, pos.z)
				_move_to = pos
				world.boss_telegraph(Vector3(pos.x, 0.0, pos.z), 6.5 + size.z * 0.15, 1.3, 30.0, "leap", pos)
				_set_state("leap")
		"leap":
			if state_t > 1.2:
				head.global_position = head.global_position.lerp(Vector3(_move_to.x, surf + 1.5, _move_to.z), 1.0 - exp(-6.0 * dt))
			if state_t > 2.4:
				_anchor = Vector3(head.global_position.x, _anchor.y, head.global_position.z)
				_set_state("idle")
				_move_to = _patrol_point()


func _patrol_point() -> Vector3:
	return _anchor + Vector3(randf_range(-14, 14), 0, randf_range(-8, 8))


func _think_land(dt: float, speed_k: float) -> void:
	var h := head.global_position
	var ground: float = world.island.height_at(h.x, h.z)
	var off := _hover()
	match state:
		"emerge":
			# 从天上 / 树冠上落下来
			head.global_position.y = move_toward(h.y, ground + off, 14.0 * dt)
			if state_t > 1.5:
				_set_state("idle")
				world.boss_telegraph(Vector3(h.x, ground, h.z), size.x * 0.6 + 3.0, 0.1, 0.0, "slam", h)
		"idle":
			_atk_cd -= dt * speed_k
			_summon_tick(dt)
			var tp: Dictionary = world.nearest_player(h)
			if tp.is_empty():
				return
			var to: Vector3 = tp["pos"] - h
			to.y = 0
			var dist := to.length()
			var dir := to.normalized()
			var side := dir.cross(Vector3.UP)
			var keep := 11.0 + size.z * 0.4
			var want := dir * (1.0 if dist > keep + 4.0 else (-1.0 if dist < keep else 0.0)) + side * 0.6
			var np := h + want.normalized() * 4.5 * speed_k * dt
			var c := Vector3(_anchor.x, 0, _anchor.z)
			if Vector3(np.x, 0, np.z).distance_to(c) < 30.0:
				head.global_position = Vector3(np.x, world.island.height_at(np.x, np.z) + off, np.z)
			_face_toward(tp["pos"], dt)
			if _atk_cd <= 0.0:
				var r := randf()
				if r < 0.35:
					_atk_cd = 2.2 if phase == 1 else 1.6
					var n := 1 if phase == 1 else 3
					var kind2 := "rock" if cfg.get("throws", false) else "web"
					for i in n:
						var o := Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5)) * (0 if i == 0 else 1)
						world.boss_projectile(kind2, _mouth() + Vector3(0, 1, 0), tp["pos"] + o, 0.9 if kind2 == "web" else 1.1, 2.2 if kind2 == "web" else 2.8, 10.0 if kind2 == "web" else 22.0)
					BeastModels.play_role(model, "attack")
				elif r < 0.65:
					_atk_cd = 2.6
					world.boss_projectile("spit", _mouth(), tp["pos"], 1.1, 3.5, 14.0)
					BeastModels.play_role(model, "attack")
				else:
					_atk_cd = 3.4
					_move_to = tp["pos"]
					world.boss_telegraph(tp["pos"], 5.0 + size.x * 0.2, 1.3, 40.0, "leap", tp["pos"])
					_set_state("leap")
		"leap":
			if state_t < 1.3:
				head.global_position.y = ground + off - sin(state_t / 1.3 * PI) * 0.4
			elif state_t < 1.8:
				var k := (state_t - 1.3) / 0.5
				var p := h.lerp(Vector3(_move_to.x, h.y, _move_to.z), k)
				p.y = world.island.height_at(p.x, p.z) + off + sin(k * PI) * 6.0
				head.global_position = p
			else:
				_set_state("idle")


func _think_air(dt: float, speed_k: float) -> void:
	var h := head.global_position
	var c := _anchor
	var fly_y := _anchor.y + _hover() + 6.0
	match state:
		"emerge":
			head.global_position = h.lerp(Vector3(c.x, fly_y, c.z), 1.0 - exp(-1.5 * dt))
			_face_toward(world.nearest_player_pos(h), dt)
			if state_t > 3.0:
				_set_state("idle")
		"idle":
			_atk_cd -= dt * speed_k
			_summon_tick(dt)
			_orbit += dt * 0.28 * speed_k
			var tp: Vector3 = world.nearest_player_pos(h)
			var rad := 26.0
			var goal := Vector3(tp.x + cos(_orbit) * rad, fly_y + sin(_t * 0.7) * 3.0, tp.z + sin(_orbit) * rad)
			var np := h.lerp(goal, 1.0 - exp(-0.8 * dt))
			head.global_position = np
			var vel := np - h
			_face_toward(h + vel * 10.0 if vel.length() > 0.02 else tp, dt)
			if _atk_cd <= 0.0:
				var t2 := _pick_target()
				if t2.is_empty():
					return
				if randf() < 0.6:
					# 冰息：一串冰球，落地的地方结冰减速
					_atk_cd = 2.6 if phase == 1 else 1.8
					var n := 3 if phase == 1 else 5
					for i in n:
						var o := Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)) * (0 if i == 0 else 1)
						world.boss_projectile("web", _mouth(), t2["pos"] + o, 1.0 + i * 0.12, 3.0, 16.0)
					BeastModels.play_role(model, "attack")
				else:
					_atk_cd = 4.0
					_move_to = t2["pos"]
					world.boss_telegraph(t2["pos"], 7.0, 1.6, 45.0, "leap", t2["pos"])
					_set_state("dive_attack")
		"dive_attack":
			if state_t < 1.4:
				var to := _move_to - h
				to.y = 0
				_face_toward(_move_to, dt * 3.0)
				head.global_position = h.lerp(_move_to + Vector3(0, 3.0 + size.y * 0.3, 0) - to.normalized() * 6.0, 1.0 - exp(-2.5 * dt))
			elif state_t < 2.4:
				head.global_position = h.lerp(Vector3(h.x, fly_y, h.z), 1.0 - exp(-2.0 * dt))
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
	var ns := str(s[3])
	if ns != state and ns in ["leap", "dive_attack"]:
		BeastModels.play_role(model, "attack")
	state = ns
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
	var ring := head.get_node("Ring")
	ring.rotation.y += dt * 0.8
	var p := head.global_position
	if dt > 0.0:
		_speed = lerpf(_speed, p.distance_to(_last_pos) / dt, 1.0 - exp(-5.0 * dt))
	_last_pos = p
	var airborne := ai == "air" or state == "leap"
	BeastModels._animate_model(model, airborne, _speed, "fly" if ai == "air" else "run")
	for b in parts:
		b.global_position = head.global_transform * (b.get_meta("offset") as Vector3)
