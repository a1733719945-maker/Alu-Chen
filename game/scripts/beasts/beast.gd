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
##
## 性格（temper，房主拽出来时随机，见 Data.TEMPERS）：
##   flee 胆小：按上面的方式逃；fierce 凶暴：一直追着最近的玩家打，不逃；
##   sly 狡猾：落地装死，你走近或者过几秒突然窜回去；bone 魂骨兽：金光闪闪跑得快，打死必掉魂骨

enum State { AIR, GROUND, FLEE, GONE }

const ESCAPE_AFTER := 24.0
const FIERCE_GIVE_UP := 90.0     # 凶暴的魂兽最多缠人这么久
const INTERP_DELAY := 0.1
const FLAG_MARK := 1
const FLAG_ROOT := 2
const FLAG_BURN := 4

# 空中重力（倍数）：往上飞时正常重力，到最高点附近短暂“停一下”给玩家打，往下掉时更快。
const G_RISE := 1.0
const G_APEX := 0.45
const G_FALL := 1.6
const APEX_BAND := 1.2     # 竖直速度在 ±这个值（米/秒）以内算“最高点附近”
const G_DEAD := 1.6
const LIFT_FADE := 0.35    # 空中每多挨一枪，往上推的力就小一截
const MAX_GUN_UP := 3.0    # 枪最多把魂兽往上推到这个速度（米/秒），技能不受限
const DEAD_MAX := 2.6      # 尸体最多留这么久

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
var temper := "flee"
var _atk_cd := 0.8
var _charge_t := 0.0
var _charge_dir := Vector3.ZERO
var _swoop_t := 0.0
var _water_t := 0.0
var _no_target_t := 0.0
var _play_dead := 0.0
var _temper_fx: Node3D

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
var _dead_t := -1.0
var _dead_ground := 0.0


func setup(p_world: Node, p_id: int, p_species: String, p_age: int, p_owner: int, p_proxy: bool, p_temper := "flee") -> void:
	world = p_world
	temper = p_temper if Data.TEMPERS.has(p_temper) else "flee"
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
	mass = Data.AGES[age]["mass"] * (2.0 if Data.BEASTS[species].get("heavy", false) else 1.0)
	gravity_scale = G_RISE
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
	_build_temper_fx()
	if temper == "sly":
		_play_dead = randf_range(2.5, 4.5)


## 性格的样子：凶暴的眼睛发红光，魂骨兽全身金光、往上飘金色光点
func _build_temper_fx() -> void:
	if temper == "flee" or temper == "sly":
		return
	var s: float = Data.AGES[age]["scale"]
	var bs := BeastModels.body_size(species) * s
	_temper_fx = Node3D.new()
	add_child(_temper_fx)
	var col: Color = Data.TEMPERS[temper]["color"]
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 1.4 if temper == "fierce" else 2.6
	light.omni_range = maxf(bs.length() * 1.2, 3.0)
	light.position = Vector3(0, bs.y * 0.3, -bs.z * 0.3)
	_temper_fx.add_child(light)
	if temper == "bone":
		var p := CPUParticles3D.new()
		p.amount = 24
		p.lifetime = 1.2
		p.mesh = U.sphere(0.05, 6, 3)
		p.material_override = U.glow(Color(1.0, 0.85, 0.35), 5.0, true)
		p.direction = Vector3.UP
		p.spread = 20.0
		p.initial_velocity_min = 0.6
		p.initial_velocity_max = 1.6
		p.gravity = Vector3(0, 1.0, 0)
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = bs * 0.5
		_temper_fx.add_child(p)
	else:
		# 两只红眼
		for side in [-1.0, 1.0]:
			var e := U.part(_temper_fx, U.sphere(0.05 * s + 0.03, 6, 4), U.glow(Color(1.0, 0.15, 0.1), 8.0), Vector3(side * bs.x * 0.12, bs.y * 0.25, -bs.z * 0.45), Vector3.ZERO, Vector3.ONE, false)
			e.name = "Eye"


func launch(pos: Vector3, vel: Vector3) -> void:
	global_position = pos
	spawn_pos = pos
	linear_velocity = vel
	angular_velocity = Vector3(randf_range(-4, 4), randf_range(-6, 6), randf_range(-4, 4))
	if motion() in ["slither", "charge"]:
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
## launch = true 是技能把魂兽挑上天，不受“越打越推不动”的限制
func take_hit(dmg: float, impulse: Vector3, local_point: Vector3, headshot: bool, shooter: int, dist: float, launch := false) -> float:
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
		var imp := impulse / (2.0 if Data.BEASTS[species].get("heavy", false) else 1.0)
		if imp.y > 0.0 and not launch:
			# 空中连击：每一枪往上推的力越来越小，而且最多推到 MAX_GUN_UP，魂兽最后一定会掉下来
			imp.y /= 1.0 + air_hits * LIFT_FADE
			imp.y = minf(imp.y, maxf(MAX_GUN_UP - linear_velocity.y, 0.0) * mass)
		apply_impulse(imp, global_basis * local_point)
		if state == State.FLEE or state == State.GROUND:
			if impulse.y > 1.0:
				state = State.AIR
	if motion() == "fly":
		fly_dir = Vector3.ZERO
	return real


## 魂技：炸上天
func skill_launch(dmg: float, up: float, from: Vector3, shooter: int) -> float:
	var away := global_position - from
	away.y = 0
	var imp := away.normalized() * up * 0.25 + Vector3.UP * up
	root_t = 0.0
	return take_hit(dmg, imp * mass, Vector3.ZERO, false, shooter, 0.0, true)


# ------------------------------------------------------------------ 物理（房主）

func _physics_process(delta: float) -> void:
	if state == State.GONE:
		_dead_tick(delta)
		return
	if proxy:
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
			if temper == "fierce" and state != State.AIR:
				_swim(delta)
				return
			world.beast_escaped(self, "splash")
			return
	_water_t = 0.0

	if temper == "fierce":
		if life > FIERCE_GIVE_UP:
			world.beast_escaped(self, "timeout")
			return
	elif life > ESCAPE_AFTER + (8.0 if temper == "sly" else 0.0):
		world.beast_escaped(self, "timeout")
		return

	match state:
		State.AIR:
			gravity_scale = air_gravity(linear_velocity.y)
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
			gravity_scale = G_RISE
			ground_time += delta
			if temper == "sly" and _play_dead > 0.0:
				# 装死：躺着不动，有人走近就突然跑
				_play_dead -= delta
				var np: Vector3 = world.nearest_player_pos(global_position)
				if np.distance_to(global_position) < 4.0:
					_play_dead = 0.0
				if _play_dead > 0.0:
					return
				linear_velocity += Vector3.UP * 3.0
			if ground_time > 0.35:
				state = State.FLEE
		State.FLEE:
			if not m in ["fly", "flutter"]:
				gravity_scale = G_RISE
			if temper == "fierce":
				_fierce(delta, m, touching)
			else:
				_flee(delta, m, touching)


## 空中的重力倍数（按竖直速度分三段）
static func air_gravity(vy: float) -> float:
	if vy > APEX_BAND:
		return G_RISE
	if vy > -APEX_BAND:
		return G_APEX
	return G_FALL


## 从 y 方向速度 vy 抛出去，落到比起点低 drop 米的地方要多久（按上面的分段重力算）
static func flight_time(vy: float, drop: float) -> float:
	var y := 0.0
	var t := 0.0
	var dt := 1.0 / 120.0
	while t < 8.0:
		vy -= 9.8 * air_gravity(vy) * dt
		y += vy * dt
		t += dt
		if vy < 0.0 and y <= -drop:
			break
	return t


## 要抛到 height 米高，初速度的 y 分量
static func launch_vy(height: float) -> float:
	var g := 9.8 * G_RISE
	var ga := 9.8 * G_APEX
	var band_h := APEX_BAND * APEX_BAND / (2.0 * ga)
	return sqrt(2.0 * g * maxf(height - band_h, 0.1) + APEX_BAND * APEX_BAND)


# ------------------------------------------------------------------ 死亡：摔到地上再消失

## 被打死：不再能被打中，身体按真实重力摔下去，播死亡动画，落地后化成魂光消失
func die() -> void:
	if state == State.GONE:
		return
	var vel := linear_velocity
	if proxy and _snaps.size() >= 2:
		var a: Array = _snaps[-2]
		var b: Array = _snaps[-1]
		vel = ((b[1] as Vector3) - (a[1] as Vector3)) / maxf(float(b[0]) - float(a[0]), 0.03)
	state = State.GONE
	_dead_t = 0.0
	collision_layer = 0
	collision_mask = U.LAYER_WORLD
	root_t = 0.0
	pull_t = 0.0
	if proxy:
		freeze = false
		contact_monitor = true
		max_contacts_reported = 4
	gravity_scale = G_DEAD
	linear_damp = 0.2
	vel.y = minf(vel.y, 2.0)
	linear_velocity = vel.limit_length(14.0)
	aura.visible = false
	if _temper_fx:
		_temper_fx.visible = false
	_hp_label.visible = false
	_status.visible = false
	model.position = Vector3.ZERO
	if model.has_meta("holder") and BeastModels.has_death(model.get_meta("holder")):
		# 有死亡动画：身体保持直立，动画自己倒下
		lock_rotation = true
		angular_velocity = Vector3.ZERO
		var fwd := -global_basis.z
		fwd.y = 0.0
		_face(fwd.normalized(), 1.0)
		BeastModels.play_role(model.get_meta("holder"), "death")
	else:
		angular_velocity = Vector3(randf_range(-5, 5), randf_range(-3, 3), randf_range(-5, 5))
		var tw := create_tween()
		tw.tween_property(model, "rotation:z", PI * 0.5 * (1.0 if randf() < 0.5 else -1.0), 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _dead_tick(delta: float) -> void:
	if _dead_t < 0.0:
		return
	_dead_t += delta
	var in_water: bool = global_position.y < Island.WATER_Y - 0.1 and not world.island.is_land(global_position.x, global_position.z)
	if in_water:
		# 掉进水里：慢慢沉下去
		linear_velocity = linear_velocity.lerp(Vector3(0, -0.8, 0), 1.0 - exp(-4.0 * delta))
	if _dead_t > 0.15 and (get_contact_count() > 0 or in_water):
		_dead_ground += delta
	if _dead_ground > 0.75 or _dead_t > DEAD_MAX:
		_vanish()


func _vanish() -> void:
	_dead_t = -1.0
	var pos := global_position + Vector3(0, 0.4 * float(Data.AGES[age]["scale"]), 0)
	world.fx.death_burst(pos, Data.age_color(age), age)
	Sfx.play_at("kill_burst", pos, -8.0, 0.05)
	queue_free()


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
			gravity_scale = G_RISE
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
	if temper == "bone" or temper == "sly":
		# 魂骨兽、狡猾的：不打人，直接用最快速度跑
		if m in ["run", "charge", "throw"]:
			_run_to_escape(delta, touching, 10.5 if temper == "bone" else 9.0, Data.BEASTS[species]["habitat"])
			return
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
				linear_velocity = dir * (6.0 if temper == "bone" else 4.2) + Vector3.UP * 3.6
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
				var sp := 5.0 if temper == "bone" else 3.4
				linear_velocity = Vector3(dir.x * sp, minf(linear_velocity.y, 0.5), dir.z * sp)
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
						BeastModels.play_attack(model)
			else:
				_run_to_escape(delta, touching, 6.5, Data.BEASTS[species]["habitat"])


## 凶暴：追着最近的玩家打，打完退一下再上，不逃
func _fierce(delta: float, m: String, touching: bool) -> void:
	_atk_cd -= delta
	var tp: Dictionary = world.nearest_player(global_position)
	if tp.is_empty():
		# 没人可打（都死了 / 隐身）：原地转悠，太久就走了
		_no_target_t += delta
		if m in ["fly", "flutter"]:
			gravity_scale = 0.0
			linear_velocity = linear_velocity.lerp(Vector3(sin(life) * 3.0, 0.3, cos(life) * 3.0), 1.0 - exp(-2.0 * delta))
		if _no_target_t > 12.0:
			temper = "flee"
		return
	_no_target_t = 0.0
	var tpos: Vector3 = tp["pos"]
	var to := tpos - global_position
	var flat := Vector3(to.x, 0, to.z)
	var dist := flat.length()
	var dir := flat.normalized() if dist > 0.01 else -global_basis.z
	var s: float = Data.AGES[age]["scale"]
	var reach: float = 1.3 + BeastModels.body_size(species).z * s * 0.45
	var dmg: float = float(Data.BEASTS[species].get("hurt", 8.0)) * (1.0 + age * 0.5)
	match m:
		"fly", "flutter":
			# 在头顶盘旋，冷却好了俯冲下来啄一口，再拉起来
			gravity_scale = 0.0
			angular_velocity = angular_velocity.lerp(Vector3.ZERO, 1.0 - exp(-6.0 * delta))
			if _swoop_t > 0.0:
				_swoop_t -= delta
				var aim := tpos + Vector3(0, 1.1, 0) - global_position
				linear_velocity = linear_velocity.lerp(aim.normalized() * 13.0, 1.0 - exp(-6.0 * delta))
				_face(aim.normalized(), 0.3)
				if aim.length() < reach + 0.4:
					_swoop_t = 0.0
					_atk_cd = randf_range(1.8, 2.8)
					world.beast_bite(self, int(tp["peer"]), dmg)
					BeastModels.play_attack(model)
					linear_velocity = -dir * 6.0 + Vector3.UP * 7.0
			else:
				var orbit := life * 1.3 + id
				var goal := tpos + Vector3(cos(orbit) * 6.0, 4.5 + sin(life * 2.0), sin(orbit) * 6.0)
				linear_velocity = linear_velocity.lerp((goal - global_position).limit_length(8.0) * 1.2, 1.0 - exp(-2.5 * delta))
				_face(Vector3(linear_velocity.x, 0, linear_velocity.z).normalized(), 0.15)
				if _atk_cd <= 0.0:
					_swoop_t = 1.4
		"throw":
			# 保持距离扔石头，太近了就一巴掌
			_face(dir, 0.25)
			if dist < reach + 0.6 and _atk_cd <= 0.0:
				_atk_cd = 1.6
				world.beast_bite(self, int(tp["peer"]), dmg * 0.8)
				BeastModels.play_attack(model)
			elif _atk_cd <= 0.0 and touching:
				_atk_cd = randf_range(2.2, 3.2)
				world.beast_throw_rock(self, tpos)
				BeastModels.play_attack(model)
			elif touching:
				var want := 1.0 if dist > 13.0 else (-0.6 if dist < 6.0 else 0.0)
				var side := dir.cross(Vector3.UP) * sin(life * 0.8) * 0.6
				var v := (dir * want + side) * 5.5
				linear_velocity = Vector3(v.x, minf(linear_velocity.y, 0.5), v.z)
				angular_velocity = Vector3.ZERO
		"charge":
			# 刨地 → 冲锋 → 冲过头停下 → 再来
			if _charge_t > 0.0:
				_charge_t -= delta
				if touching:
					linear_velocity = Vector3(_charge_dir.x * 12.5, minf(linear_velocity.y, 0.5), _charge_dir.z * 12.5)
				angular_velocity = Vector3.ZERO
				_face(_charge_dir, 0.4)
				if dist < reach and _atk_cd <= 0.0:
					_atk_cd = 1.2
					world.beast_bite(self, int(tp["peer"]), dmg)
					BeastModels.play_attack(model)
			elif _atk_cd <= 0.0:
				_face(dir, 0.3)
				if touching:
					linear_velocity = Vector3(0, minf(linear_velocity.y, 0.5), 0)
				attack_t += delta
				if attack_t > 0.7:
					attack_t = 0.0
					_charge_dir = dir
					_charge_t = clampf(dist / 12.5 + 0.5, 0.6, 2.0)
					_atk_cd = 0.0
					Sfx.play_at("bite_attack", global_position, -4.0, 0.1, 0.7)
			else:
				_face(dir, 0.2)
		_:
			# 跑、跳、爬过来咬
			var speed := 8.0
			if m == "hop":
				speed = 5.5
			elif m == "slither":
				speed = 4.8
			_face(dir, 0.35)
			if dist > reach * 0.8:
				if touching:
					if m == "hop":
						hop_timer -= delta
						if hop_timer <= 0.0:
							hop_timer = 0.38
							linear_velocity = dir * speed + Vector3.UP * 3.8
					else:
						linear_velocity = Vector3(dir.x * speed, minf(linear_velocity.y, 0.5), dir.z * speed)
						if m == "run" and dist < 5.0 and dist > reach and _atk_cd <= 0.0:
							linear_velocity.y = 4.5   # 扑
				angular_velocity = Vector3.ZERO
			if dist < reach and absf(to.y) < 2.5 and _atk_cd <= 0.0:
				_atk_cd = randf_range(1.1, 1.6)
				world.beast_bite(self, int(tp["peer"]), dmg)
				BeastModels.play_attack(model)
				if touching:
					linear_velocity = -dir * 3.5 + Vector3.UP * 2.5


## 凶暴的魂兽掉进水里：浮到水面，朝玩家游；泡太久就放弃逃走
func _swim(delta: float) -> void:
	_water_t += delta
	if _water_t > 12.0:
		world.beast_escaped(self, "splash")
		return
	gravity_scale = 0.2
	var tp: Dictionary = world.nearest_player(global_position)
	var dir := Vector3.ZERO
	if not tp.is_empty():
		dir = Vector3(tp["pos"].x - global_position.x, 0, tp["pos"].z - global_position.z).normalized()
	var v := dir * 3.2
	v.y = (Island.WATER_Y - 0.25 - global_position.y) * 3.0
	linear_velocity = linear_velocity.lerp(v, 1.0 - exp(-4.0 * delta))
	angular_velocity = Vector3.ZERO
	if dir != Vector3.ZERO:
		_face(dir, 0.2)


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
			BeastModels.play_attack(model)
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
	var airborne := state == State.AIR or (state == State.FLEE and motion() in ["fly", "flutter"])
	var spd := linear_velocity.length() if not proxy else (6.0 if state == State.FLEE else 0.0)
	BeastModels.animate(model, _anim_t, airborne, spd)
	aura.global_position = global_position + Vector3(0, 0.05, 0)
	aura.rotation = Vector3(0, _anim_t * 1.4, 0)
	var ring := aura.get_node("Ring")
	ring.position.y = sin(_anim_t * 3.0) * 0.06
	var s: float = Data.AGES[age]["scale"]
	_hp_label.global_position = global_position + Vector3(0, BeastModels.label_height(species) * s, 0)
	var tag := ""
	var tn: String = Data.TEMPERS[temper]["name"]
	if tn != "":
		tag += " [%s]" % tn
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
