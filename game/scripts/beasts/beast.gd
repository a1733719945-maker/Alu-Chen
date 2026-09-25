class_name Beast
extends RigidBody3D
## 一只被引魂索拽出来的魂兽。
##
## 房主电脑上：真正的物理刚体，被打中会被推飞（空中连击就靠这个）。
## 客人电脑上：proxy = true，冻结成运动学刚体，按房主发来的位置插值移动，
##             只用来显示和让射线打中。

enum State { AIR, GROUND, FLEE, GONE }

const ESCAPE_AFTER := 16.0      # 活太久就逃掉
const INTERP_DELAY := 0.1       # 客人那边落后 100ms 插值，动作更顺

var id := 0
var species := "rabbit"
var age := 0
var hp := 30.0
var max_hp := 30.0
var owner_peer := 1             # 谁拽出来的
var proxy := false
var state: State = State.AIR
var world: Node                 # World

var air_hits := 0
var last_hitter := 0
var last_headshot := false
var last_dist := 0.0
var last_hit_air := false       # 最后一击时是不是在空中
var life := 0.0
var ground_time := 0.0
var hop_timer := 0.0
var escape_target := Vector3.ZERO
var fly_dir := Vector3.ZERO
var spawn_pos := Vector3.ZERO

var model: Node3D
var aura: Node3D
var head_shapes := {}           # shape 下标 -> true
var _anim_t := 0.0
var _flinch := Vector3.ZERO
var _flinch_v := Vector3.ZERO
var _snaps: Array = []          # 客人：[time, pos, quat, state]
var _hp_label: Label3D


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
	mass = Data.AGES[age]["mass"]
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
	_hp_label = U.label3d("%s · %s" % [Data.age_name(age), Data.BEASTS[species]["name"]], 34, Data.age_color(age), 8)
	_hp_label.top_level = true
	_hp_label.no_depth_test = true
	_hp_label.fixed_size = true
	_hp_label.pixel_size = 0.0009
	add_child(_hp_label)
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
	if species == "vine":
		angular_velocity *= 0.5
	# 头朝飞行方向
	var flat := Vector3(vel.x, 0, vel.z)
	if flat.length() > 0.1:
		look_at_from_position(pos, pos + flat, Vector3.UP)
	if proxy:
		_snaps = [[_now(), pos, quaternion, State.AIR]]


func is_head(shape_idx: int) -> bool:
	return head_shapes.has(shape_idx)


func alive() -> bool:
	return state != State.GONE


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# ------------------------------------------------------------------ 房主：被打中

## impulse 是世界坐标下的冲量，local_point 是命中点相对魂兽的位置（魂兽本地坐标）
func take_hit(dmg: float, impulse: Vector3, local_point: Vector3, headshot: bool, shooter: int, dist: float) -> bool:
	if state == State.GONE:
		return false
	var motion: String = Data.BEASTS[species]["motion"]
	last_hit_air = state == State.AIR or (state == State.FLEE and motion in ["fly", "flutter"])
	if last_hit_air:
		air_hits += 1
	last_hitter = shooter
	last_headshot = headshot
	last_dist = dist
	hp -= dmg
	# 被打中就往上挑，脱离地面，重新进入空中状态
	apply_impulse(impulse, global_basis * local_point)
	if state == State.FLEE or state == State.GROUND:
		if impulse.y > 1.0:
			state = State.AIR
	if species == "bird":
		fly_dir = Vector3.ZERO  # 被打乱了飞行方向，重新选
	return hp <= 0.0


# ------------------------------------------------------------------ 物理（房主）

func _physics_process(delta: float) -> void:
	if proxy or state == State.GONE:
		return
	life += delta
	var touching := get_contact_count() > 0
	var motion: String = Data.BEASTS[species]["motion"]

	# 掉进水里：除了鸟（会飞走）都算逃走
	if global_position.y < Island.WATER_Y - 0.2 and not world.island.is_land(global_position.x, global_position.z):
		if motion != "fly" or state != State.AIR:
			world.beast_escaped(self, "splash")
			return

	if life > ESCAPE_AFTER:
		world.beast_escaped(self, "timeout")
		return

	match state:
		State.AIR:
			if motion == "fly" and life > 1.1 and linear_velocity.y < 1.0:
				state = State.FLEE
			elif motion == "flutter" and life > 1.4 and linear_velocity.y < 0.5:
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
			_flee(delta, motion, touching)


func _flee(delta: float, motion: String, touching: bool) -> void:
	match motion:
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
			# 鸟：飞离玩家，越飞越快
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
			# 蛾子：忽左忽右地往上飘
			gravity_scale = 0.0
			var wob := Vector3(sin(life * 3.1) * 1.8, 1.1 + sin(life * 5.0) * 0.6, cos(life * 2.3) * 1.8)
			linear_velocity = linear_velocity.lerp(wob, 1.0 - exp(-3.0 * delta))
			angular_velocity = angular_velocity.lerp(Vector3.ZERO, 1.0 - exp(-6.0 * delta))
			if global_position.y > spawn_pos.y + 22.0:
				world.beast_escaped(self, "fly")


func _face(dir: Vector3, strength: float) -> void:
	if dir.length() < 0.01:
		return
	var target := Basis.looking_at(dir, Vector3.UP)
	global_basis = global_basis.slerp(target, clampf(strength, 0.0, 1.0)).orthonormalized()


# ------------------------------------------------------------------ 客人：插值

func push_snapshot(pos: Vector3, rot: Quaternion, st: int) -> void:
	_snaps.append([_now(), pos, rot, st])
	if _snaps.size() > 12:
		_snaps.pop_front()


func _process(delta: float) -> void:
	if state == State.GONE:
		return
	_anim_t += delta
	if proxy:
		_interpolate()
	# 被打中时模型抖一下（客人那边房主的物理反应要晚一点才到，先抖一下让手感跟上）
	_flinch_v += (-_flinch * 180.0 - _flinch_v * 16.0) * delta
	_flinch += _flinch_v * delta
	model.position = global_basis.inverse() * _flinch
	var airborne := state == State.AIR or (state == State.FLEE and species in ["bird", "moth"])
	BeastModels.animate(model, _anim_t, airborne, linear_velocity.length())
	aura.global_position = global_position + Vector3(0, 0.05, 0)
	aura.rotation = Vector3(0, _anim_t * 1.4, 0)
	var ring := aura.get_node("Ring")
	ring.position.y = sin(_anim_t * 3.0) * 0.06
	_hp_label.global_position = global_position + Vector3(0, 0.75 * Data.AGES[age]["scale"], 0)
	_hp_label.text = "%s · %s  %d" % [Data.age_name(age), Data.BEASTS[species]["name"], ceili(maxf(hp, 0.0))]


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
	# 超出最新快照：短暂外推
	var last: Array = _snaps[-1]
	global_position = last[1]
	quaternion = last[2]
	state = last[3]


func set_hp_from_ratio(r: float) -> void:
	hp = max_hp * r
