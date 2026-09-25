class_name RemotePlayer
extends Node3D
## 其他玩家在我这边的样子：一个小人 + 名字 + 手里的暗器 + 引魂索。
## 位置按对方发来的快照插值（落后 100ms，动作顺）。

const INTERP_DELAY := 0.1

var peer_id := 0
var world: Node
var _snaps: Array = []   # [time, pos, yaw, pitch, weapon, flags, lure_state, lure_pos]
var body: Node3D
var head: Node3D
var arm_r: Node3D
var arm_l: Node3D
var leg_l: Node3D
var leg_r: Node3D
var weapons: Array[Node3D] = []
var label: Label3D
var lure: Lure
var _walk_t := 0.0
var _last_pos := Vector3.ZERO
var weapon := 0
var pitch := 0.0


func setup(p_world: Node, id: int, display_name: String, wuhun_idx: int) -> void:
	world = p_world
	peer_id = id
	name = "P%d" % id
	var robe := U.mat(Color(0.92, 0.92, 0.88), 0.9)
	var accent := U.mat(Data.wuhun_color(wuhun_idx), 0.6)
	var skin := U.mat(Color(0.93, 0.78, 0.66), 0.8)
	var hair := U.mat(Color(0.12, 0.1, 0.1), 0.7)
	var dark := U.mat(Color(0.2, 0.18, 0.18), 0.8)
	body = Node3D.new()
	add_child(body)
	U.part(body, U.capsule(0.27, 0.9), robe, Vector3(0, 1.08, 0))
	U.part(body, U.cyl(0.29, 0.29, 0.1, 12), accent, Vector3(0, 0.98, 0))
	head = Node3D.new()
	head.position = Vector3(0, 1.62, 0)
	body.add_child(head)
	U.part(head, U.sphere(0.2, 14, 10), skin)
	U.part(head, U.sphere(0.21, 14, 10), hair, Vector3(0, 0.05, 0.03), Vector3.ZERO, Vector3(1.0, 0.85, 1.0))
	U.part(head, U.sphere(0.03, 6, 4), dark, Vector3(0.07, 0.02, -0.18))
	U.part(head, U.sphere(0.03, 6, 4), dark, Vector3(-0.07, 0.02, -0.18))
	leg_l = _limb(body, Vector3(-0.12, 0.62, 0), robe, 0.09, 0.62)
	leg_r = _limb(body, Vector3(0.12, 0.62, 0), robe, 0.09, 0.62)
	arm_l = _limb(body, Vector3(-0.33, 1.38, 0), robe, 0.07, 0.56)
	arm_r = _limb(body, Vector3(0.33, 1.38, 0), robe, 0.07, 0.56)
	# 手里的暗器
	var xj := Node3D.new()
	U.part(xj, U.cyl(0.03, 0.035, 0.32, 8), U.mat(Color(0.35, 0.28, 0.2), 0.45, 0.0, 0.6), Vector3(0, -0.5, -0.1), Vector3(PI / 2, 0, 0))
	arm_r.add_child(xj)
	var by := Node3D.new()
	U.part(by, U.box(Vector3(0.16, 0.14, 0.24)), U.mat(Color(0.35, 0.07, 0.06), 0.35), Vector3(0, -0.52, -0.1))
	arm_r.add_child(by)
	weapons = [xj, by]
	var coil := U.part(arm_l, U.torus(0.07, 0.09, 20, 6), U.glow(Color(0.45, 0.8, 1.0), 2.5), Vector3(0, -0.4, 0))
	coil.rotation.x = PI / 2
	# 魂环光圈（按武魂颜色）
	var ring := U.part(self, U.torus(0.55, 0.6, 40, 6), U.glow(Data.wuhun_color(wuhun_idx), 1.4), Vector3(0, 0.05, 0), Vector3.ZERO, Vector3.ONE, false)
	ring.name = "Ring"
	label = U.label3d(display_name, 44, Color(1, 1, 1), 10)
	label.position = Vector3(0, 2.15, 0)
	label.fixed_size = true
	label.pixel_size = 0.0012
	add_child(label)
	lure = Lure.new()
	lure.world = world
	lure.remote = true
	add_child(lure)


func _limb(parent: Node3D, pos: Vector3, m: Material, r: float, length: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	parent.add_child(pivot)
	U.part(pivot, U.capsule(r, length), m, Vector3(0, -length * 0.5, 0))
	return pivot


func set_camera(c: Camera3D) -> void:
	lure.set_camera(c)


func push_snapshot(s: Array) -> void:
	var entry := [Time.get_ticks_msec() / 1000.0]
	entry.append_array(s)
	_snaps.append(entry)
	if _snaps.size() > 20:
		_snaps.pop_front()


## 当前位置（给房主判断魂兽往哪飞等用）
func current_pos() -> Vector3:
	return global_position


func muzzle_global() -> Vector3:
	return arm_r.global_transform * Vector3(0, -0.52, -0.3)


func _process(dt: float) -> void:
	if _snaps.is_empty():
		return
	var t := Time.get_ticks_msec() / 1000.0 - INTERP_DELAY
	var s0: Array = _snaps[0]
	var s1: Array = _snaps[-1]
	var k := 1.0
	for i in range(_snaps.size() - 1):
		if t >= _snaps[i][0] and t <= _snaps[i + 1][0]:
			s0 = _snaps[i]
			s1 = _snaps[i + 1]
			k = (t - s0[0]) / maxf(s1[0] - s0[0], 0.0001)
			break
	if t < _snaps[0][0]:
		s1 = _snaps[0]
		s0 = s1
	var pos: Vector3 = (s0[1] as Vector3).lerp(s1[1], k)
	var yaw := lerp_angle(float(s0[2]), float(s1[2]), k)
	pitch = lerpf(float(s0[3]), float(s1[3]), k)
	global_position = pos
	body.rotation.y = yaw
	head.rotation.x = pitch * 0.6
	weapon = int(s1[4])
	var flags := int(s1[5])
	for i in weapons.size():
		weapons[i].visible = i == weapon
	# 走路摆腿
	var hv := (pos - _last_pos) / maxf(dt, 0.0001)
	hv.y = 0
	_last_pos = pos
	var speed := minf(hv.length(), 10.0)
	_walk_t += dt * speed * 1.6
	var swing := sin(_walk_t) * clampf(speed / 6.0, 0.0, 1.0) * 0.7
	if not (flags & 1):
		swing = 0.4
	leg_l.rotation.x = swing
	leg_r.rotation.x = -swing
	arm_l.rotation.x = -swing * 0.6
	# 右手举着暗器，跟着视角上下
	arm_r.rotation.x = PI / 2 * 0.85 + pitch
	if flags & 8:
		body.position.y = -0.35
	else:
		body.position.y = 0.0
	get_node("Ring").rotation.y += dt * 1.2
	lure.hand = arm_l.global_transform * Vector3(0, -0.5, 0)
	lure.apply_remote(int(s1[6]), s1[7], dt)
