class_name ViewModel
extends Node3D
## 第一人称手里的东西：右手暗器、左手引魂索。
## 所有动作都是程序动画：弹簧后坐、鼠标拖拽的滞后、走路晃动、冲刺姿势、
## 换弹（拆弹匣）、拉杆 / 拉栓 / 泵动、弩臂回弹、开镜把照门对准屏幕中心。

const HIP := {
	"xiujian": Vector3(0.2, -0.19, -0.4),
	"zhuge": Vector3(0.16, -0.17, -0.36),
	"kongque": Vector3(0.15, -0.165, -0.36),
	"baoyu": Vector3(0.17, -0.17, -0.37),
	"zhuihun": Vector3(0.15, -0.175, -0.36),
}
# 开镜时照门离眼睛多远
const ADS_DIST := {"xiujian": 0.22, "zhuge": 0.16, "kongque": 0.13, "baoyu": 0.2, "zhuihun": 0.12}
const SPRING_K := 300.0
const SPRING_C := 22.0

var models := {}
var cur := "xiujian"
var left_arm: Node3D
var left_hand: Node3D
var coil: MeshInstance3D
var scoped := false

var _kp := Vector3.ZERO      # 后坐：位置弹簧
var _kpv := Vector3.ZERO
var _kr := Vector3.ZERO      # 后坐：旋转弹簧（x 抬头，y 左右，z 翻滚）
var _krv := Vector3.ZERO
var _sway := Vector2.ZERO
var _sway_target := Vector2.ZERO
var _move_tilt := 0.0
var _switch := 0.0
var _bob_t := 0.0
var _bob_amt := 0.0
var _land := 0.0
var _left_throw := 0.0
var _left_pull := 0.0
var _left_show := 0.0
var _arm_flex := 0.0
var _lever_t := 0.0
var _lever_len := 0.0
var _idle_t := 0.0


func _ready() -> void:
	for id in Data.WEAPON_ORDER:
		var m := WeaponModels.build(id)
		m.visible = false
		add_child(m)
		models[id] = m
	var mats := WeaponModels._mats()
	# 左手：手腕上缠着发光的引魂索
	left_arm = Node3D.new()
	left_arm.name = "LeftArm"
	add_child(left_arm)
	WeaponModels.fist(left_arm, mats, Vector3(0.0, -0.02, -0.06), Vector3(0.2, 0, -0.25), -1.0)
	WeaponModels.sleeve(left_arm, mats, Vector3(0.0, -0.022, -0.02), Vector3(-0.2, -0.4, 0.9))
	for n in left_arm.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	coil = U.part(left_arm, U.torus(0.043, 0.06, 24, 6), U.glow(Color(0.45, 0.8, 1.0), 2.5), Vector3(0.0, -0.022, 0.0), Vector3(PI / 2, 0, 0), Vector3.ONE, false)
	left_hand = Node3D.new()
	left_hand.position = Vector3(0.0, 0.0, -0.1)
	left_arm.add_child(left_hand)
	set_weapon("xiujian", true)


func set_weapon(id: String, instant := false) -> void:
	cur = id
	for k in models:
		models[k].visible = k == id
	_switch = 0.0 if instant else 1.0
	_kp = Vector3.ZERO
	_kr = Vector3.ZERO


func model() -> Node3D:
	return models[cur]


func muzzle_global() -> Vector3:
	var n := model().get_node_or_null("Muzzle")
	return n.global_position if n else global_position


func hand_global() -> Vector3:
	return left_hand.global_position


func two_handed() -> bool:
	return cur != "xiujian"


func add_sway(mouse_delta: Vector2) -> void:
	_sway_target += mouse_delta * 0.00018


## 开火：往后顶、往上抬、随机翻滚一点；弩臂往前弹；机括动一下
func kick(back: float, up: float, lever_time := 0.0) -> void:
	_kpv += Vector3(randf_range(-0.2, 0.2), 0.12, 1.0) * back
	_krv += Vector3(up, randf_range(-0.25, 0.25) * up, randf_range(-0.6, 0.6) * up)
	_arm_flex = 1.0
	if lever_time > 0.0:
		_lever_t = lever_time
		_lever_len = lever_time


func land(amount: float) -> void:
	_land = clampf(amount, 0.0, 1.0)


func throw_anim() -> void:
	_left_throw = 1.0


func pull_anim(v: float) -> void:
	_left_pull = v


func _ads_pos(id: String) -> Vector3:
	var s := models[id].get_node_or_null("Sight") as Node3D
	var sp := s.position if s else Vector3.ZERO
	return Vector3(0, 0, -float(ADS_DIST.get(id, 0.2))) - sp


## 每帧：ads 开镜进度，speed_k 速度/走路速度，reload_k 换弹进度，strafe 左右输入
func update(dt: float, ads: float, speed_k: float, grounded: bool, reload_k: float, sprint: float, strafe: float, lure_busy: bool, per_shell: bool) -> void:
	_idle_t += dt
	# 弹簧：固定小步长积分，某一帧卡了很久（加载、切出窗口）也不会发散
	var left := minf(dt, 0.1)
	while left > 0.0:
		var h := minf(left, 1.0 / 240.0)
		var a := -_kp * SPRING_K - _kpv * SPRING_C
		_kpv += a * h
		_kp += _kpv * h
		var ar := -_kr * SPRING_K * 0.8 - _krv * SPRING_C * 0.9
		_krv += ar * h
		_kr += _krv * h
		left -= h
	# 鼠标拖拽的滞后
	_sway_target = _sway_target.lerp(Vector2.ZERO, 1.0 - exp(-10.0 * dt))
	_sway = _sway.lerp(_sway_target, 1.0 - exp(-16.0 * dt))
	_move_tilt = U.damp(_move_tilt, -strafe * 0.06, 8.0, dt)
	_switch = move_toward(_switch, 0.0, dt / 0.28)
	_land = U.damp(_land, 0.0, 8.0, dt)
	_left_throw = move_toward(_left_throw, 0.0, dt / 0.3)
	_arm_flex = move_toward(_arm_flex, 0.0, dt / 0.12)
	if _lever_t > 0.0:
		_lever_t = maxf(_lever_t - dt, 0.0)
	if grounded and speed_k > 0.1:
		_bob_t += dt * lerpf(7.5, 11.5, sprint) * clampf(speed_k, 0.4, 1.3)
		_bob_amt = U.damp(_bob_amt, clampf(speed_k, 0.0, 1.3), 8.0, dt)
	else:
		_bob_amt = U.damp(_bob_amt, 0.0, 6.0, dt)

	var m := model()
	m.visible = not scoped
	var ads_k := ads * ads * (3.0 - 2.0 * ads)
	var p: Vector3 = (HIP[cur] as Vector3).lerp(_ads_pos(cur), ads_k)
	var calm := lerpf(1.0, 0.12, ads_k)
	# 走路晃动（8 字形）、呼吸
	p += Vector3(sin(_bob_t) * 0.011, -absf(cos(_bob_t)) * 0.013, 0) * _bob_amt * calm
	p += Vector3(sin(_idle_t * 1.1) * 0.0015, sin(_idle_t * 1.7) * 0.002, 0) * calm
	p += Vector3(-_sway.x, _sway.y, 0) * lerpf(1.0, 0.25, ads_k)
	p += _kp * Vector3(0.3, 0.3, 1.0) * lerpf(1.0, 0.55, ads_k)
	p.y -= _land * 0.045 * calm
	p.y -= _switch * 0.32
	# 换弹：放低、侧过来
	var rs := sin(reload_k * PI)
	if per_shell:
		rs = minf(reload_k * 6.0, 1.0) if reload_k > 0.0 else 0.0
	p += Vector3(-0.02, -0.07, 0.03) * rs
	# 冲刺：暗器斜着放低
	p += Vector3(-0.03, -0.05, 0.04) * sprint * (1.0 - ads_k)
	m.position = p
	m.rotation = Vector3(
		_kr.x + rs * 0.35 - sprint * 0.35 * (1.0 - ads_k) + _switch * 0.5,
		-_sway.x * 1.4 + _kr.y + sprint * 0.55 * (1.0 - ads_k),
		-_sway.x * 1.8 + _kr.z + rs * 0.55 + _move_tilt * calm)

	_animate_parts(m, reload_k, per_shell)

	# 左手：单手暗器时一直在左下角；双手暗器平时托着暗器，甩引魂索时才伸出来
	var show_left := (not two_handed()) or lure_busy or _left_throw > 0.0
	_left_show = move_toward(_left_show, 1.0 if show_left else 0.0, dt / 0.15)
	var lh := m.get_node_or_null("LeftHand")
	if lh:
		lh.visible = _left_show < 0.5
	var lp := Vector3(-0.26, -0.22, -0.42)
	lp += Vector3(sin(_bob_t + PI) * 0.01, -absf(cos(_bob_t)) * 0.012, 0) * _bob_amt
	lp += Vector3(0.08, 0.12, -0.14) * sin(_left_throw * PI)
	lp += Vector3(0.02, 0.03, 0.1) * _left_pull
	lp.y -= ads_k * 0.14
	lp.y -= _land * 0.05
	lp.y -= (1.0 - _left_show) * 0.35
	left_arm.position = lp
	left_arm.rotation = Vector3(0.15 + 0.2 * sin(_left_throw * PI) - _left_pull * 0.3, -0.2, 0.25)
	left_arm.visible = _left_show > 0.02 and not scoped
	coil.rotation.y += dt * 2.0


func _animate_parts(m: Node3D, reload_k: float, per_shell: bool) -> void:
	# 弩臂开火往前弹
	for n in ["ArmL", "ArmR"]:
		var arm := m.get_node_or_null(n) as Node3D
		if arm:
			if not arm.has_meta("ry"):
				arm.set_meta("ry", arm.rotation.y)
			var side := -1.0 if n == "ArmL" else 1.0
			arm.rotation.y = float(arm.get_meta("ry")) + side * 0.22 * _arm_flex
	# 弹匣：前 30% 往下拆掉，中间看不见，后 30% 装回来
	var mag := m.get_node_or_null("Mag") as Node3D
	if mag:
		if not mag.has_meta("y"):
			mag.set_meta("y", mag.position.y)
			mag.set_meta("z", mag.position.z)
		var off := 0.0
		if reload_k > 0.0 and not per_shell:
			if reload_k < 0.3:
				off = reload_k / 0.3
			elif reload_k < 0.65:
				off = 1.0
			else:
				off = 1.0 - (reload_k - 0.65) / 0.35
		elif per_shell and reload_k > 0.0:
			off = sin(fmod(reload_k * 6.0, 1.0) * PI) * 0.4
		mag.position.y = float(mag.get_meta("y")) - off * 0.14
		mag.position.z = float(mag.get_meta("z")) + off * 0.05
		mag.visible = off < 0.95
	# 机括：诸葛神弩的拉杆、追魂弩的栓、梨花针的泵
	var lever := m.get_node_or_null("Lever") as Node3D
	if lever:
		if not lever.has_meta("rest"):
			lever.set_meta("rest", lever.transform)
		var rest: Transform3D = lever.get_meta("rest")
		var k := 0.0
		if _lever_len > 0.0:
			k = 1.0 - _lever_t / _lever_len
		var t := rest
		match cur:
			"zhuge":
				t = rest.rotated_local(Vector3.RIGHT, sin(k * PI) * 0.55) if _lever_t > 0.0 else rest
			"zhuihun":
				if _lever_t > 0.0:
					var up := smoothstep(0.0, 0.25, k) - smoothstep(0.75, 1.0, k)
					var back := smoothstep(0.25, 0.5, k) - smoothstep(0.5, 0.75, k)
					t = rest.rotated_local(Vector3.FORWARD, up * 1.2)
					t.origin += Vector3(0, 0, back * 0.07)
			"baoyu":
				if _lever_t > 0.0:
					t.origin += Vector3(0, 0, sin(k * PI) * 0.07)
		lever.transform = t
