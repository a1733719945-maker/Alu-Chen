class_name Beast
extends RigidBody3D
## 一只被引魂索拽出来的魂兽。
##
## 房主电脑上：真正的物理刚体，被打中会被推飞（空中连击就靠这个）。
## 客人电脑上：proxy = true，冻结成运动学刚体，按房主发来的位置插值移动，
##             只用来显示和让射线打中。
##
## 落地后的行为（motion）：
##   hop 跳着逃回洞 / slither 爬回水里 / fly 飞走 / flutter 飘走
##   run 魔狼：先扑向最近的玩家咬一口，再逃回狼穴
##   charge 铁甲犀：冲撞最近的玩家，撞到后逃回泥潭
##   throw 金刚猿：朝玩家扔石头，然后逃回树林

enum State { AIR, GROUND, FLEE, GONE }

const ESCAPE_AFTER := 18.0
const INTERP_DELAY := 0.1
const FLAG_MARK := 1
const FLAG_ROOT := 2
const FLAG_BURN := 4

var id := 0
var species := "rabbit"
var age := 0
var hp := 30.0
var max_hp := 30.0
var owner_peer := 1
var proxy := false
var state: State = State.AIR
var world: Node

var air_hits := 0
var last_hitter := 0
var last_headshot := false
var last_dist := 0.0
var last_hit_air := false
var damagers := {}               # peer -> 造成的伤害（算助攻）
var life := 0.0
var ground_time := 0.0
var hop_timer := 0.0
var escape_target := Vector3.ZERO
var fly_dir := Vector3.ZERO
var spawn_pos := Vector3.ZERO
var attacked := false            # 魔狼 / 犀牛 / 猿猴 已经攻击过了
var attack_t := 0.0
var target_peer := 0

# 魂技效果（房主算）
var root_t := 0.0
var root_pos := Vector3.ZERO
var mark_t := 0.0
var mark_mult := 1.0
var armor_break := false
var burn_t := 0.0
var burn_dps := 0.0
var burn_by := 0
var pull_t := 0.0
var pull_center := Vector3.ZERO
var pull_force := 0.0
var flags := 0                   # 客人用来显示状态

var model: Node3D
var aura: Node3D
var head_shapes := {}
var _anim_t := 0.0
var _flinch := Vector3.ZERO
var _flinch_v := Vector3.ZERO
var _snaps: Array = []
var _hp_label: Label3D
var _status: Node3D


func setup(p_world: Node, p_id: int, p_species: String, p_age: int, p_owner: int, p_proxy: bool) -> void:
	world = p_world
	id = p_id
	species = p_species
	age = p_age
	owner_peer = p_owner
	proxy = p_proxy
	name = "B%d" % id
	max_hp = Data.beast_max_hp(species, age)
	hp = max_hp
	collision_layer = U.LAYER_BEAST
	collision_mask = U.LAYER_WORLD
	mass = Data.AGES[age]["mass"] * (2.0 if species == "rhino" else 1.0)
	gravity_scale = Data.BEASTS[species]["gravity"]
	linear_damp = 0.05
	angular_damp = 1.2
	continuous_cd = true
	var i := 0
	for s in BeastModels.shapes(species, age):
		var cs := CollisionShape3D.new()
		cs.shape = s["shape"]
		cs.transform = s["xform"]
		add_child(cs)
		if s["head"]:
			head_shapes[i] = true
		i += 1
	model = BeastModels.build(species, age)
	add_child(model)
	aura = BeastModels.aura(age, species)
	aura.top_level = true
	add_child(aura)
	_hp_label = U.label3d("", 34, Data.age_color(age), 8)
	_hp_label.top_level = true
	_hp_label.no_depth_test = true
	_hp_label.fixed_size = true
	_hp_label.pixel_size = 0.0009
	add_child(_hp_label)
	_status = Node3D.new()
	_status.top_level = true
	add_child(_status)
	if proxy:
		freeze = true
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	else:
		contact_monitor = true
		max_contacts_reported = 4


func launch(pos: Vector3, vel: Vector3) -> void:
	global_position = pos
	spawn_pos = pos
	linear_velocity = vel
	angular_velocity = Vector3(randf_range(-4, 4), randf_range(-6, 6), randf_range(-4, 4))
	if species in ["vine", "snake", "rhino"]:
		angular_velocity *= 0.5
	var flat := Vector3(vel.x, 0, vel.z)
	if flat.length() > 0.1:
		look_at_from_position(pos, pos + flat, Vector3.UP)
	if proxy:
		_snaps = [[_now(), pos, quaternion, State.AIR]]


func is_head(shape_idx: int) -> bool:
	return head_shapes.has(shape_idx)


func alive() -> bool:
	return state != State.GONE


func motion() -> String:
	return Data.BEASTS[species]["motion"]


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## 身体护甲（铁甲犀）：打头不减伤；被"破甲"后也不减
func armor_factor(headshot: bool) -> float:
	var a: float = float(Data.BEASTS[species].get("armor", 0.0))
	if headshot or armor_break or a <= 0.0:
		return 1.0
	return 1.0 - a


# ------------------------------------------------------------------ 房主：被打中

## impulse 是世界坐标下的冲量，local_point 是命中点相对魂兽的位置（魂兽本地坐标）
## 返回实际伤害
func take_hit(dmg: float, impulse: Vector3, local_point: Vector3, headshot: bool, shooter: int, dist: float) -> float:
	if state == State.GONE:
		return 0.0
	last_hit_air = state == State.AIR or (state == State.FLEE and motion() in ["fly", "flutter"])
	if last_hit_air:
		air_hits += 1
	last_hitter = shooter
	last_headshot = headshot
	last_dist = dist
	var real := dmg * armor_factor(headshot) * (mark_mult if mark_t > 0.0 else 1.0)
	hp -= real
	damagers[shooter] = float(damagers.get(shooter, 0.0)) + real
	if root_t <= 0.0:
		apply_impulse(impulse / (2.0 if species == "rhino" else 1.0), global_basis * local_point)
		if state == State.FLEE or state == State.GROUND:
			if impulse.y > 1.0:
				state = State.AIR
	if species == "bird":
		fly_dir = Vector3.ZERO
	return real


## 魂技：炸上天
func skill_launch(dmg: float, up: float, from: Vector3, shooter: int) -> float:
	var away := global_position - from
	away.y = 0
	var imp := away.normalized() * up * 0.25 + Vector3.UP * up
	root_t = 0.0
	return take_hit(dmg, imp * mass, Vector3.ZERO, false, shooter, 0.0)


# ------------------------------------------------------------------ 物理（房主）

func _physics_process(delta: float) -> void:
	if proxy or state == State.GONE:
		return
	life += delta
	var touching := get_contact_count() > 0
	var m := motion()
	_update_effects(delta)
	if state == State.GONE:
		return

	if root_t > 0.0:
		# 被蓝银草缠住：吊在原地
		linear_velocity = (root_pos - global_position) * 8.0
		angular_velocity = angular_velocity.lerp(Vector3.ZERO, 1.0 - exp(-8.0 * delta))
		return

	if global_position.y < Island.WATER_Y - 0.2 and not world.island.is_land(global_position.x, global_position.z):
		if m != "fly" or state != State.AIR:
			world.beast_escaped(self, "splash")
			return

	if life > ESCAPE_AFTER:
		world.beast_escaped(self, "timeout")
		return

	match state:
		State.AIR:
			if m == "fly" and life > 1.1 and linear_velocity.y < 1.0:
				state = State.FLEE
			elif m == "flutter" and life > 1.4 and linear_velocity.y < 0.5:
				state = State.FLEE
			elif touching and linear_velocity.y > -2.0 and life > 0.3:
				state = State.GROUND
				ground_time = 0.0
				air_hits = 0
				hop_timer = 0.25
				escape_target = world.island.escape_point(Data.BEASTS[species]["habitat"], global_position)
		State.GROUND:
			ground_time += delta
			if ground_time > 0.35:
				state = State.FLEE
		State.FLEE:
			_flee(delta, m, touching)


func _update_effects(delta: float) -> void:
	var f := 0
	if mark_t > 0.0:
		mark_t -= delta
		f |= FLAG_MARK
		if mark_t <= 0.0:
			armor_break = false
	if root_t > 0.0:
		root_t -= delta
		f |= FLAG_ROOT
		if root_t <= 0.0:
			gravity_scale = Data.BEASTS[species]["gravity"]
	if burn_t > 0.0:
		burn_t -= delta
		f |= FLAG_BURN
		hp -= burn_dps * delta
		damagers[burn_by] = float(damagers.get(burn_by, 0.0)) + burn_dps * delta
		if hp <= 0.0:
			last_hitter = burn_by
			world.beast_burned_out(self)
			return
	if pull_t > 0.0:
		pull_t -= delta
		var to := pull_center + Vector3.UP * 1.5 - global_position
		apply_central_force(to.limit_length(6.0) * pull_force * mass)
	flags = f


func _flee(delta: float, m: String, touching: bool) -> void:
	match m:
		"hop":
			hop_timer -= delta
			var to := escape_target - global_position
			to.y = 0
			if to.length() < 1.6:
				world.beast_escaped(self, "burrow")
				return
			if hop_timer <= 0.0 and touching:
				hop_timer = 0.42
				var dir := to.normalized()
				linear_velocity = dir * 4.2 + Vector3.UP * 3.6
				angular_velocity = Vector3.ZERO
				_face(dir, 1.0)
		"slither":
			var to := escape_target - global_position
			to.y = 0
			if to.length() < 1.2:
				world.beast_escaped(self, "splash")
				return
			if touching:
				var dir := to.normalized()
				linear_velocity = Vector3(dir.x * 3.4, minf(linear_velocity.y, 0.5), dir.z * 3.4)
				angular_velocity = Vector3.ZERO
				_face(dir, 0.3)
		"fly":
			if fly_dir == Vector3.ZERO:
				var away: Vector3 = global_position - world.nearest_player_pos(global_position)
				away.y = 0
				if away.length() < 0.1:
					away = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
				fly_dir = (away.normalized() + Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4))).normalized()
			gravity_scale = 0.0
			var target_v := fly_dir * 9.5 + Vector3.UP * 2.2
			linear_velocity = linear_velocity.lerp(target_v, 1.0 - exp(-2.5 * delta))
			angular_velocity = angular_velocity.lerp(Vector3.ZERO, 1.0 - exp(-6.0 * delta))
			_face(fly_dir, 0.15)
			if global_position.distance_to(spawn_pos) > 75.0:
				world.beast_escaped(self, "fly")
		"flutter":
			gravity_scale = 0.0
			var wob := Vector3(sin(life * 3.1) * 1.8, 1.1 + sin(life * 5.0) * 0.6, cos(life * 2.3) * 1.8)
			linear_velocity = linear_velocity.lerp(wob, 1.0 - exp(-3.0 * delta))
			angular_velocity = angular_velocity.lerp(Vector3.ZERO, 1.0 - exp(-6.0 * delta))
			if global_position.y > spawn_pos.y + 22.0:
				world.beast_escaped(self, "fly")
		"run", "charge":
			_attack_then_flee(delta, m, touching)
		"throw":
			if not attacked:
				attack_t += delta
				var tp: Dictionary = world.nearest_player(global_position)
				if not tp.is_empty():
					var dir: Vector3 = (tp["pos"] - global_position)
					dir.y = 0
					_face(dir.normalized(), 0.2)
				if attack_t > 0.6 and touching:
					attacked = true
					if not tp.is_empty():
						world.beast_throw_rock(self, tp["pos"])
			else:
				_run_to_escape(delta, touching, 6.5, "grove")


func _attack_then_flee(delta: float, m: String, touching: bool) -> void:
	if not attacked:
		attack_t += delta
		var tp: Dictionary = world.nearest_player(global_position)
		if tp.is_empty() or attack_t > 4.0:
			attacked = true
			return
		var to: Vector3 = tp["pos"] - global_position
		to.y = 0
		var dist := to.length()
		var dir := to.normalized()
		var speed := 9.0 if m == "run" else 11.0
		if m == "charge" and attack_t < 0.7:
			# 犀牛冲之前刨两下地
			speed = 0.0
			_face(dir, 0.3)
		if touching and speed > 0.0:
			linear_velocity = Vector3(dir.x * speed, minf(linear_velocity.y, 0.5), dir.z * speed)
			if m == "run" and dist < 5.0 and dist > 1.5:
				linear_velocity.y = 4.0   # 扑
			angular_velocity = Vector3.ZERO
			_face(dir, 0.35)
		if dist < 1.8:
			attacked = true
			world.beast_bite(self, int(tp["peer"]), float(Data.BEASTS[species].get("hurt", 10.0)) * (1.0 + age * 0.5))
			linear_velocity = -dir * 5.0 + Vector3.UP * 3.0
	else:
		_run_to_escape(delta, touching, 8.0, Data.BEASTS[species]["habitat"])


func _run_to_escape(_delta: float, touching: bool, speed: float, habitat: String) -> void:
	if escape_target == Vector3.ZERO or escape_target.distance_to(spawn_pos) < 0.01:
		escape_target = world.island.escape_point(habitat, global_position)
	var to := escape_target - global_position
	to.y = 0
	if to.length() < 2.0:
		world.beast_escaped(self, "burrow")
		return
	if touching:
		var dir := to.normalized()
		linear_velocity = Vector3(dir.x * speed, minf(linear_velocity.y, 0.5), dir.z * speed)
		angular_velocity = Vector3.ZERO
		_face(dir, 0.3)


func _face(dir: Vector3, strength: float) -> void:
	if dir.length() < 0.01:
		return
	var target := Basis.looking_at(dir, Vector3.UP)
	global_basis = global_basis.slerp(target, clampf(strength, 0.0, 1.0)).orthonormalized()


# ------------------------------------------------------------------ 客人：插值

func push_snapshot(pos: Vector3, rot: Quaternion, st: int) -> void:
	_snaps.append([_now(), pos, rot, st & 3])
	flags = st >> 4
	if _snaps.size() > 12:
		_snaps.pop_front()


func snapshot_state() -> int:
	return int(state) | (flags << 4)


func _process(delta: float) -> void:
	if state == State.GONE:
		return
	_anim_t += delta
	if proxy:
		_interpolate()
	_flinch_v += (-_flinch * 180.0 - _flinch_v * 16.0) * delta
	_flinch += _flinch_v * delta
	model.position = global_basis.inverse() * _flinch
	var airborne := state == State.AIR or (state == State.FLEE and species in ["bird", "moth"])
	var spd := linear_velocity.length() if not proxy else (6.0 if state == State.FLEE else 0.0)
	BeastModels.animate(model, _anim_t, airborne, spd)
	aura.global_position = global_position + Vector3(0, 0.05, 0)
	aura.rotation = Vector3(0, _anim_t * 1.4, 0)
	var ring := aura.get_node("Ring")
	ring.position.y = sin(_anim_t * 3.0) * 0.06
	var s: float = Data.AGES[age]["scale"]
	_hp_label.global_position = global_position + Vector3(0, 0.8 * s + (0.6 if species in ["rhino", "ape"] else 0.0), 0)
	var tag := ""
	if flags & FLAG_MARK:
		tag += " 易伤"
	if flags & FLAG_ROOT:
		tag += " 缠绕"
	if flags & FLAG_BURN:
		tag += " 灼烧"
	_hp_label.text = "%s · %s  %d%s" % [Data.age_name(age), Data.BEASTS[species]["name"], ceili(maxf(hp, 0.0)), tag]
	_update_status_fx()


func _update_status_fx() -> void:
	_status.global_position = global_position
	var want := flags
	if _status.get_meta("f", -1) == want:
		return
	_status.set_meta("f", want)
	for c in _status.get_children():
		c.queue_free()
	var s: float = Data.AGES[age]["scale"]
	if want & FLAG_ROOT:
		for k in 3:
			var r := U.part(_status, U.torus(0.5 * s, 0.56 * s, 24, 4), U.glow(Color(0.4, 0.8, 1.0), 2.0, true), Vector3(0, -0.2 + k * 0.25, 0), Vector3(randf() * 0.4, 0, randf() * 0.4), Vector3.ONE, false)
			r.name = "Root%d" % k
	if want & FLAG_MARK:
		var l := U.label3d("◆", 64, Color(0.85, 0.4, 1.0), 8)
		l.position = Vector3(0, 1.1 * s, 0)
		l.fixed_size = true
		l.pixel_size = 0.0012
		_status.add_child(l)
	if want & FLAG_BURN:
		var p := CPUParticles3D.new()
		p.amount = 16
		p.lifetime = 0.6
		p.mesh = U.sphere(0.06, 6, 3)
		p.material_override = U.glow(Color(1.0, 0.5, 0.15), 4.0, true)
		p.direction = Vector3.UP
		p.initial_velocity_min = 1.0
		p.initial_velocity_max = 2.5
		p.gravity = Vector3(0, 2, 0)
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.4 * s
		_status.add_child(p)


func flinch(impulse: Vector3) -> void:
	_flinch_v += impulse.limit_length(6.0) * 1.2


func _interpolate() -> void:
	if _snaps.is_empty():
		return
	var t := _now() - INTERP_DELAY
	var a: Array = _snaps[0]
	if t <= a[0] or _snaps.size() == 1:
		global_position = a[1]
		quaternion = a[2]
		return
	for i in range(_snaps.size() - 1):
		var s0: Array = _snaps[i]
		var s1: Array = _snaps[i + 1]
		if t >= s0[0] and t <= s1[0]:
			var k: float = (t - s0[0]) / maxf(s1[0] - s0[0], 0.0001)
			global_position = (s0[1] as Vector3).lerp(s1[1], k)
			quaternion = (s0[2] as Quaternion).slerp(s1[2], k)
			state = s1[3]
			return
	var last: Array = _snaps[-1]
	global_position = last[1]
	quaternion = last[2]
	state = last[3]


func set_hp_from_ratio(r: float) -> void:
	hp = max_hp * r
