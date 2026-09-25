class_name Player
extends CharacterBody3D
## 本地玩家：第一人称移动、看、开枪、甩引魂索。
##
## 手感相关的数值：
##   移动 —— 地面加速度大、摩擦快，停得住；空中能小幅转向
##   视角 —— 读原始鼠标输入，不做平滑、不做加速
##   后坐 —— 开枪瞬间准星上跳，之后自动回到原位（不用手动压枪）
##   相机 —— 物理 120Hz，相机位置按帧插值，高刷新率显示器也顺滑

signal ammo_changed(weapon: int, ammo: int, mag: int)
signal weapon_changed(weapon: int)

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

var world: Node
var cam: Camera3D
var viewmodel: ViewModel
var lure: Lure
var input_enabled := true

var yaw := 0.0
var pitch := 0.0
var kick_pitch := 0.0      # 后坐造成的偏移（度），会自动回正
var kick_yaw := 0.0
var trauma := 0.0          # 屏幕震动
var weapon := 0
var ammo: Array[int] = []
var fire_cd := 0.0
var fire_buffer := 0.0
var reload_t := 0.0
var reloading := false
var switch_t := 0.0
var ads := 0.0
var bloom := 0.0
var sprint_k := 0.0
var crouch_k := 0.0

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
	for w in Data.WEAPONS:
		ammo.append(w["mag"])
	_prev_pos = global_position
	_cur_pos = global_position
	Settings.changed.connect(_on_settings)
	_on_settings()


func _on_settings() -> void:
	_hip_vfov = Settings.vertical_fov(Settings.fov)


func look_to(p_yaw: float, p_pitch: float) -> void:
	yaw = p_yaw
	pitch = p_pitch


func teleport(p: Vector3) -> void:
	global_position = p
	velocity = Vector3.ZERO
	_prev_pos = p
	_cur_pos = p


# ------------------------------------------------------------------ 视角

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
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


func aim_basis() -> Basis:
	return Basis.from_euler(Vector3(pitch + deg_to_rad(kick_pitch), yaw + deg_to_rad(kick_yaw), 0), EULER_ORDER_YXZ)


func aim_dir() -> Vector3:
	return -aim_basis().z


func eye_position() -> Vector3:
	return _cur_pos + Vector3(0, lerpf(EYE_HEIGHT, CROUCH_EYE, crouch_k), 0)


# ------------------------------------------------------------------ 移动（物理帧）

func _physics_process(dt: float) -> void:
	_prev_pos = global_position
	var input := Vector2.ZERO
	if input_enabled:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var crouching := input_enabled and Input.is_action_pressed("crouch")
	crouch_k = move_toward(crouch_k, 1.0 if crouching else 0.0, dt / 0.12)
	var sprinting := input_enabled and Input.is_action_pressed("sprint") and input.y < -0.3 and ads < 0.3 and not crouching and not reloading
	sprint_k = move_toward(sprint_k, 1.0 if sprinting and is_on_floor() else 0.0, dt / 0.15)
	var max_speed := WALK_SPEED
	if sprinting:
		max_speed = SPRINT_SPEED
	elif crouching:
		max_speed = CROUCH_SPEED
	max_speed *= lerpf(1.0, 0.72, ads)

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
	else:
		_coyote -= dt
		# 空中：只能往想去的方向加速，不会凭空刹车
		if wish.length() > 0.01:
			var target := wish * maxf(max_speed, hv.length())
			hv = hv.move_toward(target, AIR_ACCEL * dt)
		velocity.y -= GRAVITY * dt
	# 湖边：水深过膝就走不动了，不能一直走进深水
	var depth: float = Island.WATER_Y - world.island.height_at(global_position.x, global_position.z)
	if depth > 0.2 and global_position.y < Island.WATER_Y + 0.1:  # 站在码头上不算
		hv *= 1.0 - clampf(depth * 0.25, 0.0, 0.5) * dt * 8.0
		var out := Vector3(global_position.x, 0, global_position.z).normalized()
		if depth > 0.9 and hv.dot(out) > 0.0:
			hv -= out * hv.dot(out)
	velocity.x = hv.x
	velocity.z = hv.z

	if input_enabled and Input.is_action_just_pressed("jump"):
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

	# 掉进湖里太深：拉回岸上
	if global_position.y < -8.0:
		teleport(world.island.spawn + Vector3(0, 1, 0))

	# 脚步声
	var speed := hv.length()
	if is_on_floor() and speed > 1.0:
		_step_t += dt * speed / 2.2
		if _step_t >= 1.0:
			_step_t = 0.0
			Sfx.play("step", -16.0 + sprint_k * 3.0, 0.15)
	_cur_pos = global_position


# ------------------------------------------------------------------ 每帧：相机、开枪、引魂索

func _process(dt: float) -> void:
	_update_weapons(dt)
	_update_camera(dt)
	var hv := Vector3(velocity.x, 0, velocity.z)
	var reload_k := 0.0
	if reloading:
		var w: Dictionary = Data.WEAPONS[weapon]
		reload_k = clampf(reload_t / w["reload"], 0.0, 1.0)
	viewmodel.update(dt, ads, hv.length() / WALK_SPEED, is_on_floor(), reload_k, sprint_k)
	lure.hand = viewmodel.hand_global()
	var lp := input_enabled and Input.is_action_pressed("lure")
	var ljp := input_enabled and Input.is_action_just_pressed("lure")
	var ljr := input_enabled and Input.is_action_just_released("lure")
	var before := lure.state
	lure.update_local(dt, lp, ljp, ljr, aim_dir())
	if before == Lure.S.CHARGING and lure.state == Lure.S.FLYING:
		viewmodel.throw_anim()
	viewmodel.pull_anim(1.0 if lure.state == Lure.S.REELING and lp else 0.0)


func _update_camera(dt: float) -> void:
	var f := Engine.get_physics_interpolation_fraction()
	var body := _prev_pos.lerp(_cur_pos, f)
	# 后坐自动回正
	var w: Dictionary = Data.WEAPONS[weapon]
	kick_pitch = U.damp(kick_pitch, 0.0, w["recoil_recover"], dt)
	kick_yaw = U.damp(kick_yaw, 0.0, w["recoil_recover"], dt)
	# 屏幕震动（trauma 的平方，轻的几乎感觉不到，重的很明显）
	trauma = maxf(trauma - dt * 1.8, 0.0)
	_shake_t += dt * 40.0
	var sh := trauma * trauma
	var shake_rot := Vector3(_noise.get_noise_2d(_shake_t, 0.0), _noise.get_noise_2d(0.0, _shake_t), _noise.get_noise_2d(_shake_t, _shake_t)) * sh * 0.05
	_land_dip = U.damp(_land_dip, 0.0, 7.0, dt)
	var hv := Vector3(velocity.x, 0, velocity.z)
	var bob := 0.0
	if is_on_floor() and hv.length() > 1.0:
		bob = sin(Time.get_ticks_msec() / 1000.0 * lerpf(9.0, 13.0, sprint_k)) * 0.025 * clampf(hv.length() / WALK_SPEED, 0.0, 1.4) * (1.0 - ads * 0.8)
	var eye := lerpf(EYE_HEIGHT, CROUCH_EYE, crouch_k)
	cam.global_position = body + Vector3(0, eye + bob - _land_dip * 0.12, 0)
	cam.global_basis = aim_basis() * Basis.from_euler(shake_rot)
	# 视野：开镜缩小、冲刺略微放大
	var ads_mult: float = w["ads_fov"]
	var target_fov := _hip_vfov
	target_fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(_hip_vfov) * 0.5) * lerpf(1.0, ads_mult, ads)))
	target_fov += sprint_k * 4.0
	cam.fov = target_fov


# ------------------------------------------------------------------ 暗器

func _update_weapons(dt: float) -> void:
	var w: Dictionary = Data.WEAPONS[weapon]
	fire_cd -= dt
	fire_buffer -= dt
	switch_t -= dt
	bloom = U.damp(bloom, 0.0, 6.0, dt)
	var want_ads := input_enabled and Input.is_action_pressed("aim") and switch_t <= 0.0 and sprint_k < 0.5
	ads = move_toward(ads, 1.0 if want_ads else 0.0, dt / w["ads_time"])

	if not input_enabled:
		return
	if Input.is_action_just_pressed("weapon_1"):
		switch_weapon(0)
	elif Input.is_action_just_pressed("weapon_2"):
		switch_weapon(1)
	elif Input.is_action_just_pressed("weapon_next"):
		switch_weapon((weapon + 1) % Data.WEAPONS.size())
	elif Input.is_action_just_pressed("weapon_prev"):
		switch_weapon((weapon - 1 + Data.WEAPONS.size()) % Data.WEAPONS.size())

	if Input.is_action_just_pressed("reload"):
		start_reload()

	if reloading:
		reload_t += dt
		if w["reload_per_shell"]:
			if reload_t >= w["reload"]:
				reload_t = 0.0
				ammo[weapon] += 1
				Sfx.play("reload_shell", -4.0, 0.06)
				ammo_changed.emit(weapon, ammo[weapon], w["mag"])
				if ammo[weapon] >= w["mag"]:
					reloading = false
					Sfx.play("reload_end", -4.0)
			# 装针中途按开火可以打断
			if Input.is_action_just_pressed("fire") and ammo[weapon] > 0:
				reloading = false
				fire_buffer = FIRE_BUFFER
		elif reload_t >= w["reload"]:
			reloading = false
			ammo[weapon] = w["mag"]
			Sfx.play("reload_end", -3.0)
			ammo_changed.emit(weapon, ammo[weapon], w["mag"])

	if Input.is_action_just_pressed("fire"):
		fire_buffer = FIRE_BUFFER
	var trigger: bool = fire_buffer > 0.0 or (w["auto"] and Input.is_action_pressed("fire"))
	if trigger and fire_cd <= 0.0 and switch_t <= 0.0 and not reloading and sprint_k < 0.6:
		if ammo[weapon] <= 0:
			Sfx.play("dry", -6.0)
			fire_buffer = 0.0
			start_reload()
		else:
			_fire()


func switch_weapon(i: int) -> void:
	if i == weapon:
		return
	weapon = i
	reloading = false
	switch_t = 0.22
	ads = 0.0
	viewmodel.set_weapon(i)
	Sfx.play("switch", -8.0)
	weapon_changed.emit(i)
	ammo_changed.emit(i, ammo[i], Data.WEAPONS[i]["mag"])


func start_reload() -> void:
	var w: Dictionary = Data.WEAPONS[weapon]
	if reloading or ammo[weapon] >= w["mag"]:
		return
	reloading = true
	reload_t = 0.0
	Sfx.play("reload_start", -5.0)


func current_spread() -> float:
	var w: Dictionary = Data.WEAPONS[weapon]
	var base := lerpf(w["spread"], w["ads_spread"], ads)
	var hv := Vector3(velocity.x, 0, velocity.z)
	var move_pen := clampf(hv.length() / WALK_SPEED, 0.0, 1.5) * 0.9 * (1.0 - ads * 0.7)
	var air_pen := 0.0 if is_on_floor() else 1.6
	return base + bloom + move_pen + air_pen


func _fire() -> void:
	var w: Dictionary = Data.WEAPONS[weapon]
	fire_buffer = 0.0
	fire_cd = w["interval"]
	ammo[weapon] -= 1
	ammo_changed.emit(weapon, ammo[weapon], w["mag"])
	var spread := deg_to_rad(current_spread())
	var basis := aim_basis()
	var dirs: Array[Vector3] = []
	var n := int(w["pellets"])
	for i in n:
		# 圆锥内均匀分布；多根针时分层取样，不会全挤在一边
		var r := spread * sqrt((float(i) + randf()) / n)
		var a := randf() * TAU
		var local := Vector3(sin(r) * cos(a), sin(r) * sin(a), -cos(r))
		dirs.append((basis * local).normalized())
	var origin := cam.global_position
	world.local_fire(weapon, origin, dirs, viewmodel.muzzle_global())
	# 后坐：准星往上跳，左右随机一点
	var ads_red := lerpf(1.0, 0.65, ads)
	kick_pitch += w["recoil_pitch"] * ads_red
	kick_yaw += randf_range(-1.0, 1.0) * w["recoil_yaw"] * ads_red
	trauma = minf(trauma + w["shake"], 1.0)
	bloom += 0.35 if w["pellets"] == 1 else 0.0
	viewmodel.kick(1.0 if w["pellets"] == 1 else 2.2)
	Sfx.play(w["sound"], -1.0, 0.06)
	if ammo[weapon] <= 0:
		get_tree().create_timer(0.25).timeout.connect(start_reload)


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
	if reloading:
		flags |= 16
	return [global_position, yaw, pitch, weapon, flags, int(lure.state), lure.pos]
