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
const WHEEL_HOLD := 0.2          # 按住 Q 超过这么久弹出魂技轮盘
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
const REGEN_DELAY := 6.0
const REGEN_RATE := 5.0
const BREATH := 10.0             # 水下憋气秒数（魂骨能加）
const SWIM_SPEED := 3.4
const DROWN_DPS := 12.0

var world: Node
var cam: Camera3D
var viewmodel: ViewModel
var lure: Lure
var input_enabled := true
var _q_t := -1.0                 # Q 按了多久（-1 没按）

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
# 魂兽招式带来的负面状态（Data.BEAST_SKILLS）
var root_t := 0.0                # 定身（连按空格挣脱）
var slow_t := 0.0
var slow_k := 0.0
var vuln_t := 0.0                # 受到伤害 +30%
var silence_t := 0.0             # 放不了魂技
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

# 水、倒地、魂技位移、魂骨
var under := false               # 眼睛在水下
var air := BREATH                # 剩余憋气
var invuln_t := 0.0              # 复活保护（魂兽和 Boss 不打）
var carried := false             # 被海鸥叼着
var giant_k := 0.0               # 变大了多少（0 = 正常，0.5 = 1.5 倍）
var _giant_target := 0.0
var _giant_t := 0.0
var fly_t := 0.0
var _grapple_to := Vector3.ZERO
var _grapple_t := 0.0
var _rope: MeshInstance3D
var _air_jumps := 0
var _drown_t := 0.0
var _was_wet := false
var _cs: CollisionShape3D
# 暗器：倒地掉在地上的（lost）、从地上捡来的队友的（borrowed：id -> 主人）
var lost_guns: Array = []
var borrowed := {}
# 物品栏（数字键）：1 主暗器（再按 1 换别的主暗器）/ 2 袖箭 / 3 佛怒唐莲 / 4 回血丹 / 5 没装上的魂骨
const SLOT_NAMES := ["主暗器", "袖箭", "佛怒唐莲", "回血丹 / 烤肉", "魂骨"]
var slot := 1
var _last_gun_slot := 1
var _spare_idx := 0
var _primary_pick := ""          # 上次拿的主暗器
var _slot4 := "pill"             # 4 号位现在拿的是回血丹还是烤肉
var _starve_t := 0.0
var _climb_t := 0.0
var _ctrl_t := -1.0              # Ctrl 按下多久（轻点 = 翻滚，按住 = 蹲）
var _roll_t := 0.0
var _roll_cd := 0.0
var _roll_dir := Vector3.ZERO
var _poison_t := 0.0
var _poison_dps := 0.0
var _poison_tick := 0.0
var _food_warn := 0


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
	_cs = cs
	_rope = MeshInstance3D.new()
	_rope.mesh = U.cyl(0.02, 0.02, 1.0, 6)
	_rope.material_override = U.glow(Color(0.45, 0.8, 1.0), 3.0)
	_rope.top_level = true
	_rope.visible = false
	_rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rope)

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
	# 暗器都是存档里真有的；没有袖箭就用空手（一把都没有也是空手）
	var ids: Array = Profile.loadout.duplicate()
	ids.append("fist")     # 空手一直都在：按 X 收起暗器，跑得快
	for id in ids:
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
	if slot >= 2 and slot_ready(slot):
		_show_slot_item()
	else:
		slot = 1 if gun.id in ["xiujian", "fist"] else 0
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
	return (1.0 + buff("dmg")) * (1.0 + giant_k * 0.2) * Data.level_damage(Profile.level) * Profile.rebirth_power()


## 魂兽和 Boss 不打你：刚复活、隐身、被海鸥叼着
func untargetable() -> bool:
	return invuln_t > 0.0 or buffs.has("invis") or carried


func crit_active() -> bool:
	return buffs.has("crit")


func add_shield(amount: float, dur: float) -> void:
	shield = maxf(shield, amount)
	shield_t = dur


func root(dur: float) -> void:
	root_t = maxf(root_t, dur)


func slow(k: float, dur: float) -> void:
	slow_k = maxf(slow_k if slow_t > 0.0 else 0.0, k)
	slow_t = maxf(slow_t, dur)


func _update_status(dt: float) -> void:
	root_t = maxf(root_t - dt, 0.0)
	slow_t = maxf(slow_t - dt, 0.0)
	vuln_t = maxf(vuln_t - dt, 0.0)
	silence_t = maxf(silence_t - dt, 0.0)


func heal(amount: float) -> void:
	if dead:
		return
	hp = minf(hp + amount, Profile.max_hp())


func take_damage(amount: float, from_pos: Vector3) -> void:
	if dead or amount <= 0.0 or invuln_t > 0.0:
		return
	# 减伤：魂技（金刚变、浴火、防御增幅）+ 魂骨，最多减 80%
	amount *= 1.0 - clampf(buff("dr") + Profile.bone_bonus("dr"), 0.0, 0.8)
	if vuln_t > 0.0:
		amount *= 1.3
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
	carried = false
	hp = Profile.max_hp()
	Profile.food = maxf(Profile.food, 40.0)
	shield = 0.0
	soul = Profile.max_soul()
	air = max_air()
	fly_t = 0.0
	_grapple_t = 0.0
	for g in guns:
		g.ammo = int(g.d["mag"])
		g.cancel_reload()
	ammo_changed.emit(gun)


## 被队友拉起来：原地站起来，体力回一部分，2 秒保护
func revive_here(frac: float) -> void:
	dead = false
	carried = false
	hp = Profile.max_hp() * frac
	air = max_air()
	invuln_t = 2.0
	velocity = Vector3.ZERO


## 被海鸥叼着飞（World 每帧给位置）
func carry_to(p: Vector3) -> void:
	global_position = p
	velocity = Vector3.ZERO
	_prev_pos = p
	_cur_pos = p


func max_air() -> float:
	return BREATH + Profile.bone_bonus("breath")


func on_bones_changed() -> void:
	rebuild_guns()
	hp = minf(hp, Profile.max_hp())


# ------------------------------------------------------------------ 暗器掉落 / 捡起

## 倒地时手里的暗器掉在地上（空手不掉）：这把就不是你的了，谁捡到归谁，也可以自己捡回来
func drop_guns_on_death() -> Array:
	var out: Array = []
	if gun.id != "fist" and slot < 2:
		out.append([gun.id, Net.my_id])
		_remove_gun(gun.id)
		rebuild_guns()
	return out


func _remove_gun(id: String) -> void:
	Profile.remove_weapon(id)


func can_pick_gun(id: String, _owner: int) -> bool:
	return not Profile.has_weapon(id)


func pick_gun(id: String, owner: int) -> void:
	Profile.add_weapon(id)
	if owner == Net.my_id:
		world.hud.toast("捡回了%s" % Data.WEAPONS[id]["name"], Color(0.6, 0.9, 1.0))
	else:
		world.hud.toast("捡到了%s（%s 的，按 T 可以丢还给他）" % [Data.WEAPONS[id]["name"], world.peer_name(owner)], Color(0.6, 0.9, 1.0), 4.0)
	rebuild_guns()
	for i in guns.size():
		if guns[i].id == id:
			switch_weapon(i)


# ------------------------------------------------------------------ 魂技位移

func start_giant(scale_to: float, dur: float) -> void:
	_giant_target = maxf(scale_to - 1.0, 0.0)
	_giant_t = dur
	Sfx.play("skill_buff", 0.0, 0.0, 0.6)


func blink(dir: Vector3, dist: float) -> void:
	var from := global_position + Vector3(0, 1.0, 0)
	var hit: Dictionary = world.raycast(from, from + dir * dist, U.LAYER_WORLD, [get_rid()])
	var to := from + dir * dist
	if not hit.is_empty():
		to = hit["position"] - dir * 0.6
	var g: float = world.island.height_at(to.x, to.z)
	to.y = maxf(to.y - 1.0, g + 0.05)
	world.fx.poof(global_position + Vector3(0, 1, 0))
	teleport(to)
	world.fx.poof(to + Vector3(0, 1, 0))
	invuln_t = maxf(invuln_t, 0.35)
	_fov_punch -= 8.0


func grapple_to(p: Vector3) -> void:
	_grapple_to = p
	_grapple_t = 1.4
	velocity = Vector3.ZERO
	Sfx.play("lure_throw", 0.0, 0.05, 1.3)


func start_fly(dur: float) -> void:
	fly_t = dur
	velocity.y = maxf(velocity.y, 5.0)


# ------------------------------------------------------------------ 视角

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var d: Vector2 = event.screen_relative
		if world.hud.wheel_open():
			# 魂技轮盘打开时鼠标用来选魂技，不转视角
			world.hud.wheel_mouse(d)
			return
		var sens := 0.022 * Settings.sensitivity * _ads_sens_factor()
		yaw -= deg_to_rad(d.x * sens)
		pitch -= deg_to_rad(d.y * sens) * (-1.0 if Settings.invert_y else 1.0)
		pitch = clampf(pitch, deg_to_rad(-89), deg_to_rad(89))
		viewmodel.add_sway(d)


## 开镜时视野缩成多少：全屏瞄准镜按倍率，其他按瞄具
func ads_zoom_mult() -> float:
	if bool(gun.d.get("scope", false)):
		var z := Settings.scope_zoom if bool(gun.d.get("variable", false)) else float(gun.d.get("zoom", 2.0))
		return 1.0 / maxf(z, 1.0)
	return float(gun.d["ads_fov"])


func hud_flash(c: Color) -> void:
	world.hud.flash(c)


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
	return s * k * 0.45 * (1.0 + hv * 0.4)


func aim_basis() -> Basis:
	var r := gun.recoil
	var sw := _scope_sway()
	return Basis.from_euler(Vector3(pitch + deg_to_rad(r.y + sw.y), yaw - deg_to_rad(r.x + sw.x), 0), EULER_ORDER_YXZ)


func aim_dir() -> Vector3:
	return -aim_basis().z


func eye_position() -> Vector3:
	return _cur_pos + Vector3(0, lerpf(EYE_HEIGHT, CROUCH_EYE, crouch_k) * (1.0 + giant_k), 0)


# ------------------------------------------------------------------ 移动（物理帧）

func _physics_process(dt: float) -> void:
	_prev_pos = global_position
	if carried:
		_cur_pos = global_position
		return
	var input := Vector2.ZERO
	var can_move := input_enabled and not dead
	if can_move:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	_strafe = input.x
	var crouching := can_move and Input.is_action_pressed("crouch")
	crouch_k = move_toward(crouch_k, 1.0 if crouching and fly_t <= 0.0 and not swimming else 0.0, dt / 0.12)
	# 跑的时候按左键 / 右键：马上停下来开枪 / 开镜
	var sprinting := can_move and Input.is_action_pressed("sprint") and input.y < -0.3 and ads < 0.3 and not crouching and not gun.reloading \
		and not Input.is_action_pressed("fire") and not Input.is_action_pressed("aim")
	sprint_k = move_toward(sprint_k, 1.0 if sprinting and is_on_floor() else 0.0, dt / 0.15)
	var max_speed := WALK_SPEED
	if sprinting:
		max_speed = SPRINT_SPEED
	elif crouching:
		max_speed = CROUCH_SPEED
	max_speed *= lerpf(1.0, float(gun.d["ads_move"]), ads)
	max_speed *= 1.0 + buff("speed") + Profile.bone_bonus("speed") + giant_k * 0.25
	if slot < 2:
		max_speed *= float(Data.MOVE_K.get(gun.id, 1.0))
	max_speed = maxf(max_speed, 1.0)
	_update_status(dt)
	if slow_t > 0.0:
		max_speed *= 1.0 - slow_k
	if root_t > 0.0:
		max_speed = 0.0
		if can_move and Input.is_action_just_pressed("jump"):
			root_t = maxf(root_t - 0.3, 0.0)
			trauma = minf(trauma + 0.1, 1.0)

	var wish := Basis(Vector3.UP, yaw) * Vector3(input.x, 0, input.y)
	if wish.length() > 1.0:
		wish = wish.normalized()
	var hv := Vector3(velocity.x, 0, velocity.z)
	var jump_held := can_move and Input.is_action_pressed("jump")
	var jump_pressed := can_move and Input.is_action_just_pressed("jump") and root_t <= 0.0
	# 翻滚：移动中轻点 Ctrl。翻滚的前 0.36 秒无敌（躲 Boss 的重击、横扫、冲击环）
	_roll_cd -= dt
	if can_move and Input.is_action_just_pressed("crouch"):
		_ctrl_t = 0.0
	if _ctrl_t >= 0.0:
		_ctrl_t += dt
		if not Input.is_action_pressed("crouch"):
			if _ctrl_t < 0.22 and wish.length() > 0.1 and _roll_cd <= 0.0 and is_on_floor() and fly_t <= 0.0:
				_roll_dir = wish.normalized()
				_roll_t = 0.42
				_roll_cd = 0.9
				invuln_t = maxf(invuln_t, 0.36)
				Sfx.play("jump", -4.0, 0.05, 0.7)
				viewmodel.land(0.5)
				_punch_v.z += 45.0 * (1.0 if _roll_dir.dot(Basis(Vector3.UP, yaw) * Vector3.RIGHT) > 0.0 else -1.0)
			_ctrl_t = -1.0

	# 水：脚下是深水，身子泡进去了就是在游泳（不会浮在水面上走）
	var ground: float = world.island.height_at(global_position.x, global_position.z)
	var deep := ground < Island.WATER_Y - 1.3
	var eye_h := lerpf(EYE_HEIGHT, CROUCH_EYE, crouch_k) * (1.0 + giant_k)
	swimming = deep and global_position.y < Island.WATER_Y - 0.55 and fly_t <= 0.0
	var wet := global_position.y < Island.WATER_Y - 0.1 and ground < Island.WATER_Y
	if wet and not _was_wet and velocity.y < -3.0:
		world.fx.splash(Vector3(global_position.x, Island.WATER_Y, global_position.z), velocity.y < -8.0)
		Sfx.play("splash_big" if velocity.y < -8.0 else "splash_small", -2.0, 0.1)
	_was_wet = wet

	_climb_t = maxf(_climb_t - dt, 0.0)
	if _grapple_t > 0.0:
		# 蓝银飞索：直线拉过去
		_grapple_t -= dt
		var to := _grapple_to - global_position - Vector3(0, 0.8, 0)
		velocity = to.normalized() * 26.0
		if to.length() < 1.6 or _grapple_t <= 0.0:
			_grapple_t = 0.0
			velocity = to.normalized() * 6.0 + Vector3.UP * 5.0
		_coyote = 0.0
	elif fly_t > 0.0 and not dead:
		# 飞行：空格上升，Ctrl 下降
		fly_t -= dt
		hv = hv.move_toward(wish * max_speed * 1.35, GROUND_ACCEL * 0.6 * dt)
		var vy := 0.0
		if jump_held:
			vy = 6.0
		elif can_move and Input.is_action_pressed("crouch"):
			vy = -6.0
		velocity.y = move_toward(velocity.y, vy, 30.0 * dt)
		_coyote = 0.0
	elif swimming:
		# 游泳：不按键就慢慢往下沉；空格往上游，Ctrl 往下潜，往前游时按视线方向上下
		var sw := SWIM_SPEED * (1.0 + Profile.bone_bonus("swim")) * (1.0 + buff("speed") * 0.5)
		hv = hv.move_toward(wish * sw, 18.0 * dt)
		var vy := -0.9
		if jump_held:
			vy = 3.2
		elif can_move and Input.is_action_pressed("crouch"):
			vy = -3.2
		if input.y < -0.3:
			vy += aim_dir().y * sw * 0.8
		# 头最多露出水面一点点（爬岸的时候不限）
		if global_position.y + eye_h > Island.WATER_Y + 0.35 and vy > 0.0 and _climb_t <= 0.0:
			vy = 0.0
		velocity.y = move_toward(velocity.y, vy, 10.0 * dt)
		# 靠岸：顶着岸往前游或者按空格，就能爬上去（岸再陡也能出来）
		var pushing := is_on_wall() and (jump_held or (wish.length() > 0.1 and wish.dot(get_wall_normal()) < -0.3))
		# 水里按空格：旁边 5 米内有岸就直接爬上去（沼泽、陡岸都能出来）
		if jump_pressed:
			var best := Vector3.INF
			for r in [1.5, 3.0, 4.5]:
				for k in 12:
					var a := TAU * k / 12.0
					var q := global_position + Vector3(cos(a) * r, 0, sin(a) * r)
					if world.island.is_land(q.x, q.z):
						var qy: float = world.island.height_at(q.x, q.z)
						if qy < global_position.y + 4.0 and (best == Vector3.INF or q.distance_to(global_position) < best.distance_to(global_position)):
							best = Vector3(q.x, qy + 0.3, q.z)
				if best != Vector3.INF:
					break
			if best != Vector3.INF:
				teleport(best)
				Sfx.play("splash_small", -4.0)
		if pushing:
			_climb_t = 0.7
			velocity.y = 5.5
			hv = hv.move_toward(-get_wall_normal() * 2.5, 30.0 * dt)
		_coyote = 0.0
	elif is_on_floor():
		_coyote = COYOTE_TIME
		_air_jumps = 1 if Profile.bone_bonus("djump") > 0.0 else 0
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
		velocity.y -= GRAVITY * dt * (0.8 if wet else 1.0)
		# 刚从水里爬上岸：还顶着岸就继续往上
		if _climb_t > 0.0 and is_on_wall() and wish.length() > 0.1 and wish.dot(get_wall_normal()) < -0.2:
			velocity.y = maxf(velocity.y, 5.0)
		# 魂骨：滑翔
		if jump_held and velocity.y < -2.0 and Profile.bone_bonus("glide") > 0.0:
			velocity.y = move_toward(velocity.y, -2.0, 60.0 * dt)
			hv = hv.move_toward(wish * max_speed * 1.25, AIR_ACCEL * 1.5 * dt)
	if _roll_t > 0.0:
		_roll_t -= dt
		hv = _roll_dir * lerpf(6.0, 12.5, _roll_t / 0.42)
	# 浅水：走得慢
	if not swimming and global_position.y < Island.WATER_Y + 0.1 and ground < Island.WATER_Y - 0.2:
		hv *= 1.0 - clampf((Island.WATER_Y - ground) * 0.25, 0.0, 0.5) * dt * 8.0
	# 地图边界
	var out := Vector3(global_position.x, 0, global_position.z)
	if out.length() > 150.0 and hv.dot(out.normalized()) > 0.0:
		hv -= out.normalized() * hv.dot(out.normalized())
	if _grapple_t <= 0.0:
		velocity.x = hv.x
		velocity.z = hv.z

	if jump_pressed:
		_jump_buf = JUMP_BUFFER
	_jump_buf -= dt
	var jv := JUMP_VELOCITY * sqrt(1.0 + Profile.bone_bonus("jump") + giant_k * 0.6)
	if _jump_buf > 0.0 and _coyote > 0.0 and not swimming:
		velocity.y = jv
		_jump_buf = 0.0
		_coyote = 0.0
		Sfx.play("jump", -10.0, 0.08)
	elif jump_pressed and _air_jumps > 0 and not is_on_floor() and not swimming and fly_t <= 0.0 and _coyote <= 0.0:
		# 魂骨：二段跳
		_air_jumps -= 1
		_jump_buf = 0.0
		velocity.y = jv * 0.9
		world.fx.poof(global_position)
		Sfx.play("jump", -6.0, 0.08, 1.25)

	_fall_speed = -velocity.y
	move_and_slide()

	if is_on_floor() and not _was_on_floor and _fall_speed > 5.0:
		var k := clampf((_fall_speed - 5.0) / 12.0, 0.15, 1.0)
		_land_dip = k
		viewmodel.land(k)
		Sfx.play("land", lerpf(-12.0, -2.0, k), 0.08)
	_was_on_floor = is_on_floor()

	if global_position.y < ground - 4.0 or global_position.y < -80.0:
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
		_skill_input(dt)
		if Input.is_action_just_pressed("pill"):
			_use_pill()
		if Input.is_action_just_pressed("throw"):
			_drop_current()
		if Input.is_action_just_pressed("bait"):
			cycle_bait()
	if input_enabled and not dead and Input.is_action_just_pressed("interact"):
		# F：旁边有真的能交互的（店、祭坛、渡船、能吸收的魂环、救人）就交互，没有就放第三个魂技
		var it: Dictionary = world.nearest_interactable()
		if bool(it.get("act", false)):
			world.interact()
		elif active:
			world.skills.cast_slot(2)
	if not active and world.hud.wheel_open():
		world.hud.close_wheel()
		_q_t = -1.0


## 魂技：Q / E / F 三个魂技槽（K 武魂面板里选装哪三个），按哪个放哪个，清清楚楚
func _skill_input(_dt: float) -> void:
	if Input.is_action_just_pressed("skill_1"):
		world.skills.cast_slot(0)
	if Input.is_action_just_pressed("skill_2"):
		world.skills.cast_slot(1)


func _update_stats(dt: float) -> void:
	_since_hurt += dt
	busy_t = maxf(busy_t - dt, 0.0)
	invuln_t = maxf(invuln_t - dt, 0.0)
	# 变大 / 变回来
	if _giant_t > 0.0:
		_giant_t -= dt
		if _giant_t <= 0.0:
			_giant_target = 0.0
	giant_k = move_toward(giant_k, _giant_target, dt * 2.5)
	_cs.scale = Vector3.ONE * (1.0 + giant_k)
	_cs.position.y = 0.89 * (1.0 + giant_k)
	# 飞索的绳子
	if _grapple_t > 0.0:
		var a := viewmodel.hand_global()
		var b := _grapple_to
		_rope.visible = true
		_rope.global_position = (a + b) * 0.5
		_rope.global_basis = Basis.looking_at((b - a).normalized(), Vector3.UP if absf((b - a).normalized().y) < 0.98 else Vector3.FORWARD) * Basis(Vector3.RIGHT, PI / 2)
		_rope.scale = Vector3(1, a.distance_to(b), 1)
	else:
		_rope.visible = false
	# 憋气：眼睛在水下就扣，憋不住了开始掉血
	var eye_y := global_position.y + lerpf(EYE_HEIGHT, CROUCH_EYE, crouch_k) * (1.0 + giant_k)
	var gy: float = world.island.height_at(global_position.x, global_position.z)
	var was_under := under
	under = eye_y < Island.WATER_Y - 0.05 and gy < Island.WATER_Y and not carried
	if under != was_under:
		Sfx.set_underwater(under)
		if not under and air < max_air() * 0.5:
			Sfx.play("gasp", -2.0, 0.05)
	if under and not dead:
		air -= dt
		if air <= 0.0:
			air = 0.0
			_drown_t -= dt
			if _drown_t <= 0.0:
				_drown_t = 0.5
				var inv := invuln_t
				invuln_t = 0.0
				take_damage(DROWN_DPS * 0.5, global_position + Vector3.UP)
				invuln_t = inv
	else:
		air = minf(air + dt * 4.0, max_air())
		_drown_t = 0.0
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
	var regen := buff("regen") + (5.0 if buffs.has("all") else 0.0) + Profile.bone_bonus("regen")
	_update_food(dt)
	_update_poison(dt)
	if _since_hurt > REGEN_DELAY and Profile.food > 25.0:
		regen += REGEN_RATE
	hp = minf(hp + regen * dt, max_hp)
	var soul_rate := 5.0 * (1.0 + buff("soul")) * (0.5 if Profile.food < 25.0 else 1.0)
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
	var eye := lerpf(EYE_HEIGHT, CROUCH_EYE, crouch_k) * (1.0 + giant_k)
	if dead and not carried:
		eye = 0.4
	cam.global_position = body + Vector3(0, eye + bob - _land_dip * 0.12, 0)
	var punch := Basis.from_euler(Vector3(deg_to_rad(_punch.x), deg_to_rad(_punch.y), deg_to_rad(_punch.z)))
	cam.global_basis = aim_basis() * punch * Basis.from_euler(shake_rot)
	# 视野：开镜缩小（瞄具、2 倍镜、狙击镜 4~12 倍）、冲刺略微放大、开火微缩
	var mult := lerpf(1.0, ads_zoom_mult(), ads)
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
	var want_ads: bool = active and Input.is_action_pressed("aim") and switch_t <= 0.0 and not gun.reloading and slot < 2 and gun.d["mode"] != "melee"
	if want_ads and ads <= 0.0:
		Sfx.play("ads_in", -6.0, 0.05)
	ads = move_toward(ads, 1.0 if want_ads else 0.0, dt / float(gun.d["ads_time"]))
	scoped = bool(gun.d.get("scope", false)) and ads > 0.6

	if not active:
		return
	for i in 5:
		if Input.is_action_just_pressed("weapon_%d" % (i + 1)):
			select_slot(i)
	if Input.is_action_just_pressed("holster"):
		# X：收起暗器空手跑（快），再按一下拿回刚才的暗器
		if gun.id == "fist":
			var back := _gun_index(_holster_from)
			switch_weapon(back if back >= 0 else 0)
		else:
			_holster_from = gun.id
			switch_weapon(_gun_index("fist"))
	if Input.is_action_just_pressed("inspect") and slot < 2 and gun.id != "fist":
		viewmodel.inspect()
	if scoped and bool(gun.d.get("variable", false)):
		# 狙击镜开着：滚轮调倍率（往上放大），松开右键再开镜还是这个倍率
		var z := Settings.scope_zoom
		if Input.is_action_just_pressed("weapon_prev"):
			z = minf(z * 1.25, 12.0)
		elif Input.is_action_just_pressed("weapon_next"):
			z = maxf(z / 1.25, 4.0)
		if not is_equal_approx(z, Settings.scope_zoom):
			Settings.scope_zoom = z
			Settings.save_settings()
			Sfx.play("ui_click", -8.0, 0.0, 1.4)
	elif Input.is_action_just_pressed("weapon_next"):
		_cycle_slot(1)
	elif Input.is_action_just_pressed("weapon_prev"):
		_cycle_slot(-1)

	if slot >= 2:
		# 手上拿的是道具：左键使用（扔唐莲 / 吃药 / 装魂骨）
		if not slot_ready(slot):
			select_slot(_last_gun_slot)
		elif Input.is_action_just_pressed("fire") and switch_t <= 0.0:
			_use_slot_item()
		return

	if gun.d["mode"] == "melee":
		# 空手：左键出拳（按住连着打）
		if Input.is_action_pressed("fire") and gun.fire_cd <= 0.0 and switch_t <= 0.0:
			sprint_k = 0.0
			_melee()
		return

	if Input.is_action_just_pressed("reload"):
		start_reload()

	if Input.is_action_just_pressed("fire"):
		fire_buffer = FIRE_BUFFER
	var auto: bool = gun.d["mode"] == "auto"
	var trigger: bool = fire_buffer > 0.0 or (auto and Input.is_action_pressed("fire"))
	if trigger:
		sprint_k = 0.0
	if trigger and switch_t <= 0.0:
		if gun.ammo <= 0 and not gun.reloading:
			if Input.is_action_just_pressed("fire"):
				Sfx.play("dry", -6.0)
			fire_buffer = 0.0
			start_reload()
		elif gun.ready_to_fire():
			_fire()


func switch_weapon(i: int) -> void:
	if i < 0 or i >= guns.size() or (i == gun_idx and slot < 2):
		return
	gun.cancel_reload()
	# 切枪取消拉栓（狙完马上切走再切回来，栓已经拉好了）
	if gun.cycling > 0.0:
		gun.cycling = 0.0
	gun_idx = i
	gun = guns[i]
	slot = 1 if gun.id in ["xiujian", "fist"] else 0
	_last_gun_slot = slot
	switch_t = 0.3
	ads = 0.0
	viewmodel.set_weapon(gun.id)
	Sfx.play("switch", -8.0)
	weapon_changed.emit(gun)
	ammo_changed.emit(gun)


# ------------------------------------------------------------------ 物品栏

## 主暗器（袖箭、空手以外的）
func primaries() -> Array:
	var out: Array = []
	for g in guns:
		if not g.id in ["xiujian", "fist"]:
			out.append(g.id)
	return out


## 出拳：左右手轮流，打中前面 3 米内的魂兽（能把小魂兽揍飞），伤害跟等级涨
var _punch_side := 1.0
var _holster_from := "xiujian"


func _melee() -> void:
	var d := gun.d
	gun.fire_cd = 60.0 / float(d["rpm"])
	_punch_side = -_punch_side
	viewmodel.punch(_punch_side)
	Sfx.play("skill_dash", -12.0, 0.1, 1.6)
	var origin := cam.global_position
	var dir := aim_dir()
	var hit: Dictionary = world.raycast(origin, origin + dir * float(d["range"]), U.LAYER_WORLD | U.LAYER_BEAST, [get_rid()])
	if hit.is_empty():
		# 没正中：看看前面一点有没有魂兽（拳头判定宽一点）
		for b: Beast in world.beasts.values():
			if b.alive() and b.global_position.distance_to(origin + dir * 1.8) < 1.6:
				hit = {"collider": b, "position": b.global_position, "normal": -dir, "shape": 0}
				break
	if hit.is_empty():
		return
	world.local_melee(gun, origin, dir, hit)
	_punch_v += Vector3(-6.0, _punch_side * 8.0, _punch_side * 10.0)
	trauma = minf(trauma + 0.15, 1.0)


func spare_bones() -> Array:
	return Profile.bones.filter(func(b): return not Profile.is_equipped(str(b)))


func spare_bone() -> String:
	var sp := spare_bones()
	if sp.is_empty():
		return ""
	return str(sp[clampi(_spare_idx, 0, sp.size() - 1)])


func slot_ready(i: int) -> bool:
	match i:
		0:
			return not primaries().is_empty()
		1:
			return true
		2:
			return Profile.item_count("grenade") > 0
		3:
			return Profile.item_count("pill") > 0 or Profile.item_count("meat") > 0
		4:
			return not spare_bones().is_empty()
	return false


func _gun_index(id: String) -> int:
	for i in guns.size():
		if guns[i].id == id:
			return i
	return -1


func select_slot(i: int) -> void:
	if not slot_ready(i):
		var why := ["还没有主暗器，去暗器铺买", "", "没有佛怒唐莲了", "没有回血丹了", "没有多余的魂骨（捡到的魂骨会先自动装上）"]
		if str(why[i]) != "":
			world.hud.toast(str(why[i]), Color(0.9, 0.9, 0.9), 1.6)
		return
	match i:
		0:
			# 已经拿着主暗器再按 1：换下一把主暗器
			var ps := primaries()
			if slot == 0 and ps.size() > 1:
				var cur := ps.find(gun.id)
				switch_weapon(_gun_index(str(ps[(cur + 1) % ps.size()])))
			elif slot != 0:
				var want := _primary_pick if _primary_pick in ps else str(ps[0])
				switch_weapon(_gun_index(want))
		1:
			switch_weapon(_gun_index("xiujian") if _gun_index("xiujian") >= 0 else _gun_index("fist"))
		_:
			if i == 4 and slot == 4:
				_spare_idx = (_spare_idx + 1) % maxi(spare_bones().size(), 1)
			elif i == 3 and slot == 3 and Profile.item_count("pill") > 0 and Profile.item_count("meat") > 0:
				_slot4 = "meat" if _slot4 == "pill" else "pill"
			elif slot == i:
				return
			if slot < 2:
				_last_gun_slot = slot
			gun.cancel_reload()
			slot = i
			ads = 0.0
			switch_t = 0.25
			_show_slot_item()
			Sfx.play("switch", -10.0, 0.05, 1.2)
	if slot == 0:
		_primary_pick = gun.id


func _show_slot_item() -> void:
	match slot:
		2:
			viewmodel.show_item("item", "grenade")
		3:
			if Profile.item_count(_slot4) <= 0:
				_slot4 = "meat" if _slot4 == "pill" else "pill"
			viewmodel.show_item("item", _slot4)
		4:
			viewmodel.show_item("bone", spare_bone())


func _cycle_slot(step: int) -> void:
	var i := slot
	for k in 5:
		i = (i + step + 5) % 5
		if slot_ready(i):
			if i == 0 and slot == 0:
				continue
			select_slot(i)
			return


## 饱食度：一直在掉（跑步掉得快）；低于 25 不自然回血、魂力回得慢；饿到 0 开始掉血
func _update_poison(dt: float) -> void:
	if _poison_t <= 0.0 or dead:
		return
	_poison_t -= dt
	_poison_tick -= dt
	if _poison_tick <= 0.0:
		_poison_tick = 0.5
		take_damage(_poison_dps * 0.5, global_position + Vector3.UP)
		world.fx.impact_beast(global_position + Vector3(0, 1.2, 0), Vector3.UP, Color(0.5, 1.0, 0.3), false)


func _update_food(dt: float) -> void:
	if Data.autotest:
		return
	Profile.food = maxf(Profile.food - Data.FOOD_DRAIN * dt * (1.6 if sprint_k > 0.5 else 1.0), 0.0)
	var lvl := 2 if Profile.food <= 0.0 else (1 if Profile.food < 25.0 else 0)
	if lvl > _food_warn:
		if lvl == 1:
			world.hud.toast("饿了：不会自己回血，魂力回得慢。按 4 拿出烤肉吃（打死魂兽常掉，暗器铺也有卖）", Color(1.0, 0.7, 0.35), 5.0)
		else:
			world.hud.toast("饿坏了，开始掉血！快吃东西", Color(1.0, 0.4, 0.3), 4.0)
	_food_warn = lvl
	if Profile.food <= 0.0:
		_starve_t -= dt
		if _starve_t <= 0.0:
			_starve_t = 1.0
			var inv := invuln_t
			invuln_t = 0.0
			take_damage(2.0, global_position + Vector3.UP)
			invuln_t = inv


## 中毒：一段时间内持续掉血（第二章落日森林的魂兽带毒）
func poison(dps: float, dur: float) -> void:
	if _poison_t <= 0.0:
		world.hud.toast("中毒了！持续掉血（回血丹能解）", Color(0.6, 1.0, 0.4), 2.0)
	_poison_dps = maxf(_poison_dps if _poison_t > 0.0 else 0.0, dps)
	_poison_t = maxf(_poison_t, dur)


func eat_meat() -> void:
	if Profile.food >= Data.FOOD_MAX - 1.0 and hp >= Profile.max_hp() - 1.0:
		world.hud.toast("吃不下了", Color(0.9, 0.9, 0.9), 1.2)
		return
	if not Profile.use_item("meat"):
		return
	Profile.food = minf(Profile.food + Data.MEAT_FOOD, Data.FOOD_MAX)
	heal(10.0)
	Sfx.play("pickup", -2.0, 0.05, 0.7)
	world.hud.toast("吃了烤魂兽肉  饱食 %d" % roundi(Profile.food), Color(1.0, 0.8, 0.5), 1.5)


## 鱼饵：B 换下一种（有的才换得到，青草饵不要钱）
func current_bait() -> String:
	var b := Profile.bait
	var item := str(Data.BAITS.get(b, Data.BAITS["grass"])["item"])
	if item != "" and Profile.item_count(item) <= 0:
		return "grass"
	return b


func cycle_bait() -> void:
	var order: Array = Data.BAIT_ORDER
	var i := order.find(Profile.bait)
	for k in order.size():
		i = (i + 1) % order.size()
		var id := str(order[i])
		var item := str(Data.BAITS[id]["item"])
		if item == "" or Profile.item_count(item) > 0:
			Profile.bait = id
			Profile.mark_dirty()
			world.hud.toast("鱼饵：%s" % bait_text(), Color(0.8, 1.0, 0.8), 1.8)
			Sfx.play("ui_click", -6.0)
			return
	world.hud.toast("只有青草饵。去暗器铺买血腥饵、魂晶饵、金骨饵", Color(0.9, 0.9, 0.9), 2.5)


func bait_text() -> String:
	var b := current_bait()
	var d: Dictionary = Data.BAITS[b]
	var item := str(d["item"])
	return "%s%s" % [d["name"], (" ×%d" % Profile.item_count(item)) if item != "" else "（免费）"]


## 左键使用手上的道具
func _use_slot_item() -> void:
	match slot:
		2:
			_throw_grenade()
		3:
			if _slot4 == "meat":
				eat_meat()
			else:
				_use_pill()
		4:
			var e := spare_bone()
			if e == "":
				return
			var sl := str(Data.bone_data(e)["slot"])
			var old := str(Profile.equipped.get(sl, ""))
			Profile.equip_bone(e)
			on_bones_changed()
			Sfx.play("level_up", -8.0)
			world.hud.toast("装上了【%s】%s%s" % [Data.bone_name(e), Data.bone_desc(e), ("，换下来的%s在 5 号位" % Data.bone_name(old)) if old != "" else ""], UiKit.GOLD, 4.0)
			_spare_idx = 0
	if slot_ready(slot):
		_show_slot_item()


## T：把手上的东西丢出去（丢给队友，或者丢进收购箱卖掉）
func _drop_current() -> void:
	var e := {}
	match slot:
		0, 1:
			# 暗器也能丢（丢给队友、丢进收购箱卖一半价钱）；丢了就不是你的了，想要再买
			var id := gun.id
			if id == "fist":
				world.hud.toast("手上什么都没拿", Color(0.9, 0.9, 0.9), 1.2)
				return
			e = {"kind": "gun", "key": id, "owner": Net.my_id}
			_remove_gun(id)
			rebuild_guns()
			var ps := primaries()
			switch_weapon(_gun_index(str(ps[0]) if not ps.is_empty() else ("xiujian" if Profile.has_weapon("xiujian") else "fist")))
		2, 3:
			var key := "grenade" if slot == 2 else _slot4
			if not Profile.use_item(key):
				return
			e = {"kind": "item", "key": key, "owner": Net.my_id}
		4:
			var b := spare_bone()
			if b == "" or not Profile.remove_bone(b):
				return
			e = {"kind": "bone", "key": b, "owner": Net.my_id}
	world.loot.throw_entry(e, cam.global_position, aim_dir(), velocity)
	viewmodel.throw_anim()
	if slot >= 2:
		if slot_ready(slot):
			_show_slot_item()
		else:
			select_slot(_last_gun_slot)


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
	var back := 0.05 if n == 1 else 0.1
	if gun.id == "zhuihun":
		back = 0.13
	# 手里的暗器往后顶、往上跳（开镜时小一些，但不会没有）
	viewmodel.kick(back * (1.0 - ads * 0.35), deg_to_rad(float(d["view_punch"]) * 4.2) * (1.0 - ads * 0.45), lever)
	Sfx.play(d["sound"], 0.0, 0.04, 1.0 + randf_range(-0.03, 0.03))
	# 低频的"咚"叠在枪声下面，让每一发更有分量
	Sfx.play("thud", -9.0 if n == 1 else -4.0, 0.05, 1.6 if gun.id in ["xiujian", "zhuge"] else 1.1)
	# 抛壳
	var ej := viewmodel.model().get_node_or_null("Eject") as Node3D
	if ej and not scoped:
		var cb := cam.global_basis
		world.fx.shell(ej.global_position, cb.x * randf_range(2.2, 3.2) + cb.y * randf_range(1.5, 2.4) + cb.z * 0.6 + velocity)
		if randf() < 0.5:
			get_tree().create_timer(0.45).timeout.connect(func(): Sfx.play("shell", -18.0, 0.2))
	# 弹匣快空了：每发多一声清脆的"咔"
	if gun.ammo > 0 and gun.ammo <= maxi(int(float(d["mag"]) * 0.25), 1):
		Sfx.play("low_ammo", -8.0, 0.05)
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
	_poison_t = 0.0
	root_t = 0.0
	slow_t = 0.0
	vuln_t = 0.0
	silence_t = 0.0
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
	if untargetable():
		flags |= 64
	if buffs.has("invis"):
		flags |= 128
	if fly_t > 0.0:
		flags |= 256
	if carried:
		flags |= 512
	if under:
		flags |= 1024
	return [global_position, yaw, pitch, gun.id, flags, int(lure.state), lure.pos, hp / Profile.max_hp(), 1.0 + giant_k]
