class_name ViewModel
extends Node3D
## 第一人称手里的东西：右手暗器、左手引魂索。
## 负责枪口位置、晃动、后坐、换弹、切枪、开镜的动作。

var weapons: Array[Node3D] = []
var muzzles: Array[Node3D] = []
var left_arm: Node3D
var left_hand: Node3D
var coil: MeshInstance3D
var current := 0

var _sway := Vector2.ZERO          # 鼠标带动的滞后
var _sway_target := Vector2.ZERO
var _kick := 0.0                   # 开火往后顶
var _kick_rot := 0.0
var _switch := 0.0                 # 1 = 放下，0 = 举起
var _reload := 0.0
var _bob_t := 0.0
var _bob_amt := 0.0
var _land := 0.0
var _left_throw := 0.0
var _left_pull := 0.0

const HIP_POS := [Vector3(0.21, -0.2, -0.42), Vector3(0.2, -0.2, -0.44)]
const ADS_POS := [Vector3(0.0, -0.1, -0.34), Vector3(0.0, -0.1, -0.38)]


func _ready() -> void:
	var skin := U.mat(Color(0.93, 0.78, 0.66), 0.8)
	var sleeve := U.mat(Color(0.86, 0.82, 0.74), 0.9)
	var bronze := U.mat(Color(0.35, 0.28, 0.2), 0.45, 0.0, 0.6)
	var gold := U.mat(Color(0.85, 0.66, 0.28), 0.35, 0.0, 0.8)
	var lacquer := U.mat(Color(0.35, 0.07, 0.06), 0.35)
	var strap := U.mat(Color(0.3, 0.2, 0.14), 0.8)

	# 袖箭：绑在右手腕上的铜管
	var xj := Node3D.new()
	xj.name = "Xiujian"
	add_child(xj)
	U.part(xj, U.capsule(0.045, 0.42), sleeve, Vector3(0.02, -0.03, 0.14), Vector3(PI / 2, 0, 0), Vector3.ONE, false)
	U.part(xj, U.sphere(0.05, 10, 6), skin, Vector3(0.0, -0.035, -0.08), Vector3.ZERO, Vector3(0.9, 0.7, 1.2), false)
	U.part(xj, U.cyl(0.014, 0.017, 0.26, 10), bronze, Vector3(0.0, 0.025, -0.02), Vector3(PI / 2, 0, 0), Vector3.ONE, false)
	U.part(xj, U.cyl(0.0, 0.009, 0.035, 6), U.mat(Color(0.85, 0.88, 0.9), 0.3, 0.0, 0.9), Vector3(0.0, 0.025, -0.165), Vector3(-PI / 2, 0, 0), Vector3.ONE, false)
	U.part(xj, U.cyl(0.019, 0.019, 0.025, 10), gold, Vector3(0.0, 0.025, -0.14), Vector3(PI / 2, 0, 0), Vector3.ONE, false)
	U.part(xj, U.cyl(0.019, 0.019, 0.02, 10), gold, Vector3(0.0, 0.025, 0.09), Vector3(PI / 2, 0, 0), Vector3.ONE, false)
	for zz in [0.0, 0.08]:
		U.part(xj, U.box(Vector3(0.1, 0.012, 0.022)), strap, Vector3(0.0, 0.0, zz), Vector3.ZERO, Vector3.ONE, false)
	var m0 := Node3D.new()
	m0.position = Vector3(0.0, 0.025, -0.18)
	xj.add_child(m0)
	weapons.append(xj)
	muzzles.append(m0)

	# 暴雨梨花针：一个小漆盒，正面一排排针孔
	var by := Node3D.new()
	by.name = "Baoyu"
	add_child(by)
	U.part(by, U.capsule(0.042, 0.4), sleeve, Vector3(0.02, -0.06, 0.2), Vector3(PI / 2, 0, 0), Vector3.ONE, false)
	U.part(by, U.sphere(0.048, 10, 6), skin, Vector3(0.0, -0.05, 0.04), Vector3.ZERO, Vector3(1.1, 0.8, 1.2), false)
	U.part(by, U.box(Vector3(0.085, 0.07, 0.15)), lacquer, Vector3(0.0, 0.0, -0.03), Vector3.ZERO, Vector3.ONE, false)
	U.part(by, U.box(Vector3(0.092, 0.008, 0.155)), gold, Vector3(0.0, 0.037, -0.03), Vector3.ZERO, Vector3.ONE, false)
	U.part(by, U.box(Vector3(0.092, 0.008, 0.155)), gold, Vector3(0.0, -0.037, -0.03), Vector3.ZERO, Vector3.ONE, false)
	var face := U.part(by, U.box(Vector3(0.078, 0.064, 0.006)), U.mat(Color(0.12, 0.1, 0.08)), Vector3(0.0, 0.0, -0.106), Vector3.ZERO, Vector3.ONE, false)
	face.name = "Face"
	for ix in 4:
		for iy in 3:
			U.part(by, U.sphere(0.005, 5, 3), gold, Vector3(-0.027 + ix * 0.018, -0.018 + iy * 0.018, -0.11), Vector3.ZERO, Vector3.ONE, false)
	U.part(by, U.sphere(0.013, 8, 4), U.glow(Color(0.5, 0.8, 1.0), 2.0), Vector3(0.0, 0.045, 0.0), Vector3.ZERO, Vector3.ONE, false)
	var m1 := Node3D.new()
	m1.position = Vector3(0.0, 0.0, -0.12)
	by.add_child(m1)
	weapons.append(by)
	muzzles.append(m1)

	# 左手：手腕上缠着发光的引魂索
	left_arm = Node3D.new()
	left_arm.name = "LeftArm"
	add_child(left_arm)
	U.part(left_arm, U.capsule(0.045, 0.42), sleeve, Vector3(0.0, -0.02, 0.16), Vector3(PI / 2, 0, 0), Vector3.ONE, false)
	U.part(left_arm, U.sphere(0.05, 10, 6), skin, Vector3(0.0, -0.02, -0.06), Vector3.ZERO, Vector3(0.9, 0.75, 1.2), false)
	coil = U.part(left_arm, U.torus(0.045, 0.062, 24, 6), U.glow(Color(0.45, 0.8, 1.0), 2.5), Vector3(0.0, -0.02, 0.04), Vector3(PI / 2, 0, 0), Vector3.ONE, false)
	left_hand = Node3D.new()
	left_hand.position = Vector3(0.0, 0.0, -0.1)
	left_arm.add_child(left_hand)

	set_weapon(0, true)


func set_weapon(i: int, instant := false) -> void:
	current = i
	for k in weapons.size():
		weapons[k].visible = k == i
	if instant:
		_switch = 0.0
	else:
		_switch = 1.0


func muzzle_global() -> Vector3:
	return muzzles[current].global_position


func hand_global() -> Vector3:
	return left_hand.global_position


func add_sway(mouse_delta: Vector2) -> void:
	_sway_target += mouse_delta * 0.00022


func kick(strength: float) -> void:
	_kick += 0.045 * strength
	_kick_rot += 0.09 * strength


func land(amount: float) -> void:
	_land = clampf(amount, 0.0, 1.0)


func throw_anim() -> void:
	_left_throw = 1.0


func pull_anim(v: float) -> void:
	_left_pull = v


## reload_k：0..1 换弹进度（0 表示没在换弹）
func update(dt: float, ads: float, speed_ratio: float, grounded: bool, reload_k: float, sprint: float) -> void:
	# 鼠标拖拽的滞后感
	_sway_target = _sway_target.lerp(Vector2.ZERO, 1.0 - exp(-9.0 * dt))
	_sway = _sway.lerp(_sway_target, 1.0 - exp(-14.0 * dt))
	_kick = U.damp(_kick, 0.0, 18.0, dt)
	_kick_rot = U.damp(_kick_rot, 0.0, 14.0, dt)
	_switch = move_toward(_switch, 0.0, dt / 0.22)
	_land = U.damp(_land, 0.0, 8.0, dt)
	_left_throw = move_toward(_left_throw, 0.0, dt / 0.3)
	_reload = reload_k
	if grounded and speed_ratio > 0.1:
		_bob_t += dt * lerpf(7.0, 11.0, sprint) * clampf(speed_ratio, 0.4, 1.3)
		_bob_amt = U.damp(_bob_amt, clampf(speed_ratio, 0.0, 1.3), 8.0, dt)
	else:
		_bob_amt = U.damp(_bob_amt, 0.0, 6.0, dt)

	var ads_k := ads * ads
	var hip: Vector3 = HIP_POS[current]
	var aim: Vector3 = ADS_POS[current]
	var p := hip.lerp(aim, ads_k)
	var bob_scale := lerpf(1.0, 0.15, ads_k)
	p += Vector3(sin(_bob_t) * 0.012, -absf(cos(_bob_t)) * 0.014, 0) * _bob_amt * bob_scale
	p += Vector3(-_sway.x, _sway.y, 0) * lerpf(1.0, 0.3, ads_k)
	p.z += _kick
	p.y -= _land * 0.05
	p.y -= _switch * 0.35
	p.y -= sin(_reload * PI) * 0.12
	# 冲刺时枪往下斜
	p += Vector3(-0.04, -0.05, 0.03) * sprint * (1.0 - ads_k)
	var w := weapons[current]
	w.position = p
	var rs := sin(_reload * PI)
	w.rotation = Vector3(
		_kick_rot + rs * 0.6 - sprint * 0.3 * (1.0 - ads_k),
		-_sway.x * 1.5 + sprint * 0.5 * (1.0 - ads_k),
		-_sway.x * 2.0 + rs * 0.5)

	# 左手：平时在左下角，抛索时往前一甩，拉扯时往回拽
	var lp := Vector3(-0.27, -0.23, -0.44)
	lp += Vector3(sin(_bob_t + PI) * 0.01, -absf(cos(_bob_t)) * 0.012, 0) * _bob_amt
	lp += Vector3(0.08, 0.12, -0.14) * sin(_left_throw * PI)
	lp += Vector3(0.02, 0.03, 0.1) * _left_pull
	lp.y -= ads_k * 0.12
	lp.y -= _land * 0.05
	left_arm.position = lp
	left_arm.rotation = Vector3(0.15 + 0.2 * sin(_left_throw * PI) - _left_pull * 0.3, -0.2, 0.25)
	coil.rotation.y += dt * 2.0
