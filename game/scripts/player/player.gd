class_name Player
extends CharacterBody3D
## 本地玩家：第一人称移动、看、开枪、甩引魂索、放魂技、用道具。
##
## 手感：
##   移动 —— 地面加速度大、摩擦快，停得住；空中能小幅转向
##   视角 —— 读原始鼠标输入，不做平滑、不做加速；开镜按视野缩放灵敏度
##   后坐 —— 每把暗器有自己的后坐图案（见 Gun 和 data.gd），准星跟着跳，停火后回正
##   冲击 —— 每发镜头额外"顶"一下再弹回（只影响画面），加上屏幕震动和视野微缩
##   相机 —— 物理 120Hz，相机位置按帧插值，高刷新率显示器也顺滑

signal ammo_changed(gun: Gun)
signal weapon_changed(gun: Gun)
signal hurt(amount: float, from_dir: Vector3)
signal died

const EYE_HEIGHT := 1.62
const CROUCH_EYE := 1.12
const WALK_SPEED := 5.6
const SPRINT_SPEED := 8.6
const CROUCH_SPEED := 2.9
const GROUND_ACCEL := 75.0
const GROUND_DECEL := 55.0
const AIR_ACCEL := 16.0
const GRAVITY := 22.0
const JUMP_VELOCITY := 7.8
const COYOTE_TIME := 0.1
const JUMP_BUFFER := 0.12
const FIRE_BUFFER := 0.09
const REGEN_DELAY := 4.0
const REGEN_RATE := 8.0

var world: Node
var cam: Camera3D
var viewmodel: ViewModel
var lure: Lure
var input_enabled := true

var yaw := 0.0
var pitch := 0.0
var trauma := 0.0
var guns: Array[Gun] = []
var gun: Gun
var gun_idx := 0
var fire_buffer := 0.0
var switch_t := 0.0
var ads := 0.0
var scoped := false
var sprint_k := 0.0
var crouch_k := 0.0
var swimming := false

# 体力 / 护盾 / 魂力 / 增益
var hp := 100.0
var shield := 0.0
var shield_t := 0.0
var soul := 60.0
var dead := false
var busy_t := 0.0                # 吸收魂环时不能开枪
var buffs := {}                  # stat -> [amount, 剩余秒]
var _since_hurt := 99.0

var _coyote := 0.0
var _jump_buf := 0.0
var _prev_pos := Vector3.ZERO
var _cur_pos := Vector3.ZERO
var _was_on_floor := true
var _fall_speed := 0.0
var _land_dip := 0.0
var _step_t := 0.0
var _shake_t := 0.0
var _noise := FastNoiseLite.new()
var _hip_vfov := 70.0
var _punch := Vector3.ZERO       # 镜头冲击（度）：x 抬头，y 左右，z 翻滚
var _punch_v := Vector3.ZERO
var _fov_punch := 0.0
var _sway_t := 0.0
var _breath := 4.0               # 狙击屏息剩余秒数
var _breath_tired := 0.0
var _strafe := 0.0


func _ready() -> void:
	collision_layer = U.LAYER_PLAYER
	collision_mask = U.LAYER_WORLD
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.78
	cs.shape = cap
	cs.position.y = 0.89
	add_child(cs)

	cam = Camera3D.new()
	cam.top_level = true
	cam.near = 0.03
	cam.far = 1500.0
	cam.current = true
	add_child(cam)
	viewmodel = ViewModel.new()
	cam.add_child(viewmodel)
	lure = Lure.new()
	lure.world = world
	add_child(lure)
	lure.set_camera(cam)

	_noise.frequency = 2.0
	rebuild_guns()
	hp = Profile.max_hp()
	soul = Profile.max_soul()
	_prev_pos = global_position
	_cur_pos = global_position
	Settings.changed.connect(_on_settings)
	_on_settings()


func _on_settings() -> void:
	_hip_vfov = Settings.vertical_fov(Settings.fov)


## 根据存档里拥有的暗器和升级重建（买了新暗器、升级后调用）
func rebuild_guns() -> void:
	var old := {}
	for g in guns:
		old[g.id] = g
	var keep_id := gun.id if gun else ""
	guns.clear()
	for id in Profile.loadout:
		var stats := Profile.weapon_stats(id)
		if old.has(id):
			old[id].set_stats(stats)
			guns.append(old[id])
		else:
			guns.append(Gun.new(id, stats))
	gun_idx = 0
	for i in guns.size():
		if guns[i].id == keep_id:
			gun_idx = i
	gun = guns[gun_idx]
	viewmodel.set_weapon(gun.id, true)
	weapon_changed.emit(gun)
	ammo_changed.emit(gun)


func look_to(p_yaw: float, p_pitch: float) -> void:
	yaw = p_yaw
	pitch = p_pitch


func teleport(p: Vector3) -> void:
	global_position = p
	velocity = Vector3.ZERO
	_prev_pos = p
	_cur_pos = p


# ------------------------------------------------------------------ 增益

func add_buff(stat: String, amount: float, dur: float) -> void:
	var cur: Array = buffs.get(stat, [0.0, 0.0])
	buffs[stat] = [maxf(cur[0], amount), maxf(cur[1], dur)]


func buff(stat: String) -> float:
	var v := 0.0
	if buffs.has(stat):
		v += float(buffs[stat][0])
	if buffs.has("all") and stat in ["dmg", "speed"]:
		v += float(buffs["all"][0])
	return v


func damage_mult() -> float:
	return 1.0 + buff("dmg")


func crit_active() -> bool:
	return buffs.has("crit")


func add_shield(amount: float, dur: float) -> void:
	shield = maxf(shield, amount)
	shield_t = dur


func heal(amount: float) -> void:
	if dead:
		return
	hp = minf(hp + amount, Profile.max_hp())


func take_damage(amount: float, from_pos: Vector3) -> void:
	if dead or amount <= 0.0:
		return
	var left := amount
	if shield > 0.0:
		var s := minf(shield, left)
		shield -= s
		left -= s
	hp -= left
	_since_hurt = 0.0
	trauma = minf(trauma + 0.3 + amount * 0.01, 1.0)
	_punch_v += Vector3(-1.5, randf_range(-1.5, 1.5), randf_range(-2.0, 2.0)) * 20.0
	hurt.emit(amount, (from_pos - global_position).normalized())
	Sfx.play("hurt", -3.0, 0.08)
	if hp <= 0.0:
		hp = 0.0
		dead = true
		died.emit()


func revive() -> void:
	dead = false
	hp = Profile.max_hp()
	shield = 0.0
	soul = Profile.max_soul()
	for g in guns:
		g.ammo = int(g.d["mag"])
		g.cancel_reload()
	ammo_changed.emit(gun)


# ------------------------------------------------------------------ 视角

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or dead:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var d: Vector2 = event.screen_relative
		var sens := 0.022 * Settings.sensitivity * _ads_sens_factor()
		yaw -= deg_to_rad(d.x * sens)
		pitch -= deg_to_rad(d.y * sens) * (-1.0 if Settings.invert_y else 1.0)
		pitch = clampf(pitch, deg_to_rad(-89), deg_to_rad(89))
		viewmodel.add_sway(d)


func _ads_sens_factor() -> float:
	if ads <= 0.01:
		return 1.0
	# 开镜后按视野缩放，保证"屏幕上移动同样距离需要的鼠标距离"一致
	var cur := deg_to_rad(cam.fov) * 0.5
	var hip := deg_to_rad(_hip_vfov) * 0.5
	return tan(cur) / tan(hip) * lerpf(1.0, Settings.ads_sensitivity, ads)


## 狙击镜的晃动（度）：按住 Shift 屏息 4 秒会稳住
func _scope_sway() -> Vector2:
	if not scoped:
		return Vector2.ZERO
	var t := _sway_t
	var s := Vector2(sin(t * 0.9) * 0.55 + sin(t * 2.3) * 0.18, sin(t * 1.3) * 0.4 + sin(t * 3.1) * 0.12)
	var hold := input_enabled and Input.is_action_pressed("sprint") and _breath > 0.0 and _breath_tired <= 0.0
	var hv := Vector3(velocity.x, 0, velocity.z).length()
	var k := 0.12 if hold else (1.6 if _breath_tired > 0.0 else 1.0)
	return s * k * (1.0 + hv * 0.4)


func aim_basis() -> Basis:
	var r := gun.recoil
	var sw := _scope_sway()
	return Basis.from_euler(Vector3(pitch + deg_to_rad(r.y + sw.y), yaw - deg_to_rad(r.x + sw.x), 0), EULER_ORDER_YXZ)


func aim_dir() -> Vector3:
	return -aim_basis().z


func eye_position() -> Vector3:
	return _cur_pos + Vector3(0, lerpf(EYE_HEIGHT, CROUCH_EYE, crouch_k), 0)


# ------------------------------------------------------------------ 移动（物理帧）

func _physics_process(dt: float) -> void:
	_prev_pos = global_position
	var input := Vector2.ZERO
	var can_move := input_enabled and not dead
	if can_move:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	_strafe = input.x
	var crouching := can_move and Input.is_action_pressed("crouch")
	crouch_k = move_toward(crouch_k, 1.0 if crouching else 0.0, dt / 0.12)
	var sprinting := can_move and Input.is_action_pressed("sprint") and input.y < -0.3 and ads < 0.3 and not crouching and not gun.reloading
	sprint_k = move_toward(sprint_k, 1.0 if sprinting and is_on_floor() else 0.0, dt / 0.15)
	var max_speed := WALK_SPEED
	if sprinting:
		max_speed = SPRINT_SPEED
	elif crouching:
		max_speed = CROUCH_SPEED
	max_speed *= lerpf(1.0, float(gun.d["ads_move"]), ads)
	max_speed *= 1.0 + buff("speed")

	var wish := Basis(Vector3.UP, yaw) * Vector3(input.x, 0, input.y)
	if wish.length() > 1.0:
		wish = wish.normalized()
	var hv := Vector3(velocity.x, 0, velocity.z)

	if is_on_floor():
		_coyote = COYOTE_TIME
		if wish.length() > 0.01:
			hv = hv.move_toward(wish * max_speed, GROUND_ACCEL * dt)
		else:
			hv = hv.move_toward(Vector3.ZERO, GROUND_DECEL * dt)
	elif swimming:
		hv = hv.move_toward(wish * 3.2, GROUND_ACCEL * 0.4 * dt)
	else:
		_coyote -= dt
		# 空中：只能往想去的方向加速，不会凭空刹车
		if wish.length() > 0.01:
			var target := wish * maxf(max_speed, hv.length())
			hv = hv.move_toward(target, AIR_ACCEL * dt)
		velocity.y -= GRAVITY * dt
	# 下水：浅水走得慢；深水浮在水面上游，头露出水面，可以游回岸边
	var ground: float = world.island.height_at(global_position.x, global_position.z)
	var swim_y := Island.WATER_Y - 1.35
	swimming = ground < swim_y and global_position.y < swim_y + 0.15
	if swimming:
		velocity.y = (swim_y - global_position.y) * 6.0
		hv = hv.limit_length(3.2)
		_coyote = 0.0
	elif global_position.y < Island.WATER_Y + 0.1 and ground < Island.WATER_Y - 0.2:
		hv *= 1.0 - clampf((Island.WATER_Y - ground) * 0.25, 0.0, 0.5) * dt * 8.0
	# 地图边界
	var out := Vector3(global_position.x, 0, global_position.z)
	if out.length() > 150.0 and hv.dot(out.normalized()) > 0.0:
		hv -= out.normalized() * hv.dot(out.normalized())
	velocity.x = hv.x
	velocity.z = hv.z

	if can_move and Input.is_action_just_pressed("jump"):
		_jump_buf = JUMP_BUFFER
	_jump_buf -= dt
	if _jump_buf > 0.0 and _coyote > 0.0:
		velocity.y = JUMP_VELOCITY
		_jump_buf = 0.0
		_coyote = 0.0
		Sfx.play("jump", -10.0, 0.08)

	_fall_speed = -velocity.y
	move_and_slide()

	if is_on_floor() and not _was_on_floor and _fall_speed > 5.0:
		var k := clampf((_fall_speed - 5.0) / 12.0, 0.15, 1.0)
		_land_dip = k
		viewmodel.land(k)
		Sfx.play("land", lerpf(-12.0, -2.0, k), 0.08)
	_was_on_floor = is_on_floor()

	if global_position.y < -8.0:
		teleport(world.island.spawn + Vector3(0, 1, 0))

	var speed := hv.length()
	if is_on_floor() and speed > 1.0:
		_step_t += dt * speed / 2.2
		if _step_t >= 1.0:
			_step_t = 0.0
			Sfx.play("step", -16.0 + sprint_k * 3.0, 0.15)
	_cur_pos = global_position


# ------------------------------------------------------------------ 每帧：相机、开枪、引魂索、魂技

func _process(dt: float) -> void:
	_update_stats(dt)
	_update_weapons(dt)
	_update_camera(dt)
	var hv := Vector3(velocity.x, 0, velocity.z)
	viewmodel.scoped = scoped
	viewmodel.update(dt, ads, hv.length() / WALK_SPEED, is_on_floor(), gun.reload_progress(), sprint_k, _strafe,
		lure.state != Lure.S.IDLE, bool(gun.d["per_shell"]))
	lure.hand = viewmodel.hand_global()
	var active := input_enabled and not dead and busy_t <= 0.0
	var lp := active and Input.is_action_pressed("lure")
	var ljp := active and Input.is_action_just_pressed("lure")
	var ljr := active and Input.is_action_just_released("lure")
	var before := lure.state
	lure.update_local(dt, lp, ljp, ljr, aim_dir())
	if before == Lure.S.CHARGING and lure.state == Lure.S.FLYING:
		viewmodel.throw_anim()
	viewmodel.pull_anim(1.0 if lure.state == Lure.S.REELING and lp else 0.0)
	if active:
		for i in Data.SKILL_KEYS.size():
			if Input.is_action_just_pressed("skill_%d" % (i + 1)):
				world.skills.cast(i)
		if Input.is_action_just_pressed("grenade"):
			_throw_grenade()
		if Input.is_action_just_pressed("pill"):
			_use_pill()
	if input_enabled and not dead and Input.is_action_just_pressed("interact"):
		world.interact()


func _update_stats(dt: float) -> void:
	_since_hurt += dt
	busy_t = maxf(busy_t - dt, 0.0)
	for k in buffs.keys():
		buffs[k][1] -= dt
		if buffs[k][1] <= 0.0:
			buffs.erase(k)
	if shield_t > 0.0:
		shield_t -= dt
		if shield_t <= 0.0:
			shield = 0.0
	if dead:
		return
	var max_hp := Profile.max_hp()
	var regen := buff("regen") + (5.0 if buffs.has("all") else 0.0)
	if _since_hurt > REGEN_DELAY:
		regen += REGEN_RATE
	hp = minf(hp + regen * dt, max_hp)
	var soul_rate := 5.0 * (1.0 + buff("soul"))
	soul = minf(soul + soul_rate * dt, Profile.max_soul())
	# 屏息
	var holding := scoped and Input.is_action_pressed("sprint")
	if _breath_tired > 0.0:
		_breath_tired -= dt
		if _breath_tired <= 0.0:
			_breath = 4.0
	elif holding:
		_breath -= dt
		if _breath <= 0.0:
			_breath_tired = 2.0
			Sfx.play("exhale", -8.0)
	else:
		_breath = minf(_breath + dt * 1.5, 4.0)
	_sway_t += dt


func _update_camera(dt: float) -> void:
	var f := Engine.get_physics_interpolation_fraction()
	var body := _prev_pos.lerp(_cur_pos, f)
	# 镜头冲击：弹簧，顶上去再弹回来
	var left := minf(dt, 0.1)
	while left > 0.0:
		var h := minf(left, 1.0 / 240.0)
		var a := -_punch * 260.0 - _punch_v * 20.0
		_punch_v += a * h
		_punch += _punch_v * h
		left -= h
	_fov_punch = U.damp(_fov_punch, 0.0, 12.0, dt)
	trauma = maxf(trauma - dt * 1.8, 0.0)
	_shake_t += dt * 40.0
	var sh := trauma * trauma
	var shake_rot := Vector3(_noise.get_noise_2d(_shake_t, 0.0), _noise.get_noise_2d(0.0, _shake_t), _noise.get_noise_2d(_shake_t, _shake_t)) * sh * 0.05
	_land_dip = U.damp(_land_dip, 0.0, 7.0, dt)
	var hv := Vector3(velocity.x, 0, velocity.z)
	var bob := 0.0
	if is_on_floor() and hv.length() > 1.0:
		bob = sin(Time.get_ticks_msec() / 1000.0 * lerpf(9.0, 13.0, sprint_k)) * 0.022 * clampf(hv.length() / WALK_SPEED, 0.0, 1.4) * (1.0 - ads * 0.85)
	var eye := lerpf(EYE_HEIGHT, CROUCH_EYE, crouch_k)
	if dead:
		eye = 0.4
	cam.global_position = body + Vector3(0, eye + bob - _land_dip * 0.12, 0)
	var punch := Basis.from_euler(Vector3(deg_to_rad(_punch.x), deg_to_rad(_punch.y), deg_to_rad(_punch.z)))
	cam.global_basis = aim_basis() * punch * Basis.from_euler(shake_rot)
	# 视野：开镜缩小（狙击镜 4 倍）、冲刺略微放大、开火微缩
	var mult := lerpf(1.0, float(gun.d["ads_fov"]), ads)
	var target_fov := rad_to_deg(2.0 * atan(tan(deg_to_rad(_hip_vfov) * 0.5) * mult))
	target_fov += sprint_k * 4.0 - _fov_punch
	cam.fov = target_fov


# ------------------------------------------------------------------ 暗器

func _update_weapons(dt: float) -> void:
	var speed_k := 1.0 + buff("speed")
	for g in guns:
		var ev := g.update(dt, speed_k if g == gun else 1.0)
		if g == gun:
			for e in ev:
				match e:
					"shell":
						Sfx.play("reload_shell", -4.0, 0.06)
						ammo_changed.emit(gun)
					"reload_done":
						Sfx.play("mag_in", -3.0, 0.04)
						ammo_changed.emit(gun)
					"cycled":
						pass
	fire_buffer -= dt
	switch_t -= dt
	var active := input_enabled and not dead and busy_t <= 0.0
	var want_ads := active and Input.is_action_pressed("aim") and switch_t <= 0.0 and sprint_k < 0.5 and not gun.reloading
	ads = move_toward(ads, 1.0 if want_ads else 0.0, dt / float(gun.d["ads_time"]))
	scoped = bool(gun.d.get("scope", false)) and ads > 0.92

	if not active:
		return
	for i in 5:
		if Input.is_action_just_pressed("weapon_%d" % (i + 1)) and i < guns.size():
			switch_weapon(i)
	if Input.is_action_just_pressed("weapon_next"):
		switch_weapon((gun_idx + 1) % guns.size())
	elif Input.is_action_just_pressed("weapon_prev"):
		switch_weapon((gun_idx - 1 + guns.size()) % guns.size())

	if Input.is_action_just_pressed("reload"):
		start_reload()

	if Input.is_action_just_pressed("fire"):
		fire_buffer = FIRE_BUFFER
	var auto: bool = gun.d["mode"] == "auto"
	var trigger: bool = fire_buffer > 0.0 or (auto and Input.is_action_pressed("fire"))
	if trigger and switch_t <= 0.0 and sprint_k < 0.6:
		if gun.ammo <= 0 and not gun.reloading:
			if Input.is_action_just_pressed("fire"):
				Sfx.play("dry", -6.0)
			fire_buffer = 0.0
			start_reload()
		elif gun.ready_to_fire():
			_fire()


func switch_weapon(i: int) -> void:
	if i == gun_idx or i < 0 or i >= guns.size():
		return
	gun.cancel_reload()
	gun_idx = i
	gun = guns[i]
	switch_t = 0.3
	ads = 0.0
	viewmodel.set_weapon(gun.id)
	Sfx.play("switch", -8.0)
	weapon_changed.emit(gun)
	ammo_changed.emit(gun)


func start_reload() -> void:
	if gun.start_reload():
		Sfx.play("mag_out", -5.0, 0.04)


func current_spread() -> float:
	var hv := Vector3(velocity.x, 0, velocity.z)
	return gun.spread(ads, hv.length() / WALK_SPEED, not is_on_floor() and not swimming, crouch_k > 0.5, scoped)


func _fire() -> void:
	var d := gun.d
	fire_buffer = 0.0
	# 先按开火前的准星方向算弹道，再加这一发的后坐
	var spread := deg_to_rad(current_spread())
	var basis := aim_basis()
	var dirs: Array[Vector3] = []
	var n := int(d["pellets"])
	for i in n:
		# 圆锥内均匀分布；多根针时分层取样，不会全挤在一边
		var r := spread * sqrt((float(i) + randf()) / n)
		var a := randf() * TAU
		var local := Vector3(sin(r) * cos(a), sin(r) * sin(a), -cos(r))
		dirs.append((basis * local).normalized())
	var origin := cam.global_position
	var muzzle := viewmodel.muzzle_global() if not scoped else origin + aim_dir() * 0.6 + basis.y * -0.08
	world.local_fire(gun, origin, dirs, muzzle)
	gun.shoot(ads)
	ammo_changed.emit(gun)
	# 镜头冲击（不影响弹道）
	var vp := float(d["view_punch"]) * lerpf(1.0, 0.6, ads)
	_punch_v += Vector3(vp * 22.0, randf_range(-0.35, 0.35) * vp * 22.0, randf_range(-0.5, 0.5) * vp * 22.0)
	_fov_punch += vp * 0.35
	trauma = minf(trauma + float(d["shake"]), 1.0)
	var lever := 0.0
	match gun.id:
		"zhuge":
			lever = 0.055
		"zhuihun":
			lever = float(d.get("cycle", 1.0))
		"baoyu":
			lever = 0.35
	var back := 0.035 if n == 1 else 0.08
	if gun.id == "zhuihun":
		back = 0.1
	viewmodel.kick(back * (1.0 - ads * 0.4), deg_to_rad(float(d["view_punch"]) * 3.0) * (1.0 - ads * 0.5), lever)
	Sfx.play(d["sound"], -1.0, 0.05)
	if gun.id == "zhuihun":
		get_tree().create_timer(0.35).timeout.connect(func(): Sfx.play("bolt_cycle", -4.0))
	elif gun.id == "baoyu":
		get_tree().create_timer(0.3).timeout.connect(func(): Sfx.play("pump", -4.0))
	if gun.ammo <= 0:
		get_tree().create_timer(0.25).timeout.connect(start_reload)


func _throw_grenade() -> void:
	if not Profile.use_item("grenade"):
		world.hud.toast("没有佛怒唐莲了，去暗器铺买", Color(1, 0.7, 0.5))
		return
	viewmodel.throw_anim()
	var dir := aim_dir()
	world.throw_grenade(cam.global_position + dir * 0.6, dir * 19.0 + Vector3.UP * 4.0 + velocity * 0.5)
	Sfx.play("lure_throw", -2.0, 0.1, 0.8)


func _use_pill() -> void:
	if hp >= Profile.max_hp() - 1.0:
		return
	if not Profile.use_item("pill"):
		world.hud.toast("没有回血丹了，去暗器铺买", Color(1, 0.7, 0.5))
		return
	heal(60.0)
	Sfx.play("heal", -4.0)
	world.fx.heal_burst(global_position)


## 给联机同步用的状态
func net_state() -> Array:
	var flags := 0
	if is_on_floor():
		flags |= 1
	if sprint_k > 0.5:
		flags |= 2
	if ads > 0.5:
		flags |= 4
	if crouch_k > 0.5:
		flags |= 8
	if gun.reloading:
		flags |= 16
	if dead:
		flags |= 32
	return [global_position, yaw, pitch, gun.id, flags, int(lure.state), lure.pos, hp / Profile.max_hp()]
