class_name RemotePlayer
extends Node3D
## 其他玩家在我这边的样子：小人 + 名字等级 + 手里的暗器 + 身上的魂环 + 引魂索。
## 位置按对方发来的快照插值（落后 100ms，动作顺）。

const INTERP_DELAY := 0.1

var peer_id := 0
var world: Node
var info := {}
var _snaps: Array = []   # [time, pos, yaw, pitch, gun_id, flags, lure_state, lure_pos, hp]
var body: Node3D
var head: Node3D
var arm_r: Node3D
var arm_l: Node3D
var leg_l: Node3D
var leg_r: Node3D
var weapons := {}
var label: Label3D
var lure: Lure
var ring_root: Node3D
var _walk_t := 0.0
var _last_pos := Vector3.ZERO
var pitch := 0.0
var _dead := false
var _flags := 0
var _scale := 1.0
var _flash := [0.0, 0.0, 0.0]


func setup(p_world: Node, id: int, p_info: Dictionary) -> void:
	world = p_world
	peer_id = id
	name = "P%d" % id
	var wuhun_idx := int(p_info.get("wuhun", 0))
	var robe := U.mat(Color(0.92, 0.92, 0.88), 0.9)
	var accent := U.mat(Data.wuhun_color(wuhun_idx), 0.6)
	var skin := U.mat(Color(0.93, 0.78, 0.66), 0.8)
	var hair := U.mat(Color(0.12, 0.1, 0.1), 0.7)
	var dark := U.mat(Color(0.2, 0.18, 0.18), 0.8)
	body = Node3D.new()
	add_child(body)
	U.part(body, U.capsule(0.27, 0.9), robe, Vector3(0, 1.08, 0))
	U.part(body, U.cyl(0.29, 0.29, 0.1, 12), accent, Vector3(0, 0.98, 0))
	U.part(body, U.cyl(0.3, 0.36, 0.5, 12), robe, Vector3(0, 0.62, 0))
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
	for id2 in Data.WEAPON_ORDER:
		var w := WeaponModels.build_small(id2)
		w.position = Vector3(0, -0.52, -0.15)
		w.visible = false
		arm_r.add_child(w)
		weapons[id2] = w
	var coil := U.part(arm_l, U.torus(0.07, 0.09, 20, 6), U.glow(Color(0.45, 0.8, 1.0), 2.5), Vector3(0, -0.4, 0))
	coil.rotation.x = PI / 2
	ring_root = Node3D.new()
	add_child(ring_root)
	label = U.label3d("", 40, Color(1, 1, 1), 10)
	label.position = Vector3(0, 2.25, 0)
	label.fixed_size = true
	label.pixel_size = 0.0011
	add_child(label)
	lure = Lure.new()
	lure.world = world
	lure.remote = true
	add_child(lure)
	set_info(p_info)


func set_info(p_info: Dictionary) -> void:
	info = p_info
	label.text = "%s\n%d 级%s" % [str(info.get("name", "魂师")), int(info.get("level", 1)), Data.titles(int(info.get("level", 1)))]
	for c in ring_root.get_children():
		c.queue_free()
	var rs: Array = info.get("rings", [])
	# 魂环：从脚下往上一圈一圈，颜色按年份
	for i in rs.size():
		var col := Data.age_color(int(rs[i]))
		var r := U.part(ring_root, U.torus(0.55, 0.62, 40, 6), U.glow(col, 2.0), Vector3(0, 0.25 + i * 0.35, 0), Vector3.ZERO, Vector3.ONE, false)
		r.name = "R%d" % i


func flash_ring(slot: int) -> void:
	if slot < _flash.size():
		_flash[slot] = 1.0


func _limb(parent: Node3D, pos: Vector3, m: Material, r: float, length: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	parent.add_child(pivot)
	U.part(pivot, U.capsule(r, length), m, Vector3(0, -length * 0.5, 0))
	return pivot


func set_camera(c: Camera3D) -> void:
	lure.set_camera(c)


func is_dead() -> bool:
	return _dead


## 隐身、刚复活、被海鸥叼着：魂兽和 Boss 不打他
func untargetable() -> bool:
	return (_flags & 64) != 0


func push_snapshot(s: Array) -> void:
	var entry := [Time.get_ticks_msec() / 1000.0]
	entry.append_array(s)
	_snaps.append(entry)
	if _snaps.size() > 20:
		_snaps.pop_front()


func muzzle_global() -> Vector3:
	return arm_r.global_transform * Vector3(0, -0.52, -0.5)


func _process(dt: float) -> void:
	for i in _flash.size():
		_flash[i] = maxf(_flash[i] - dt, 0.0)
	var k := 0
	for r in ring_root.get_children():
		r.rotation.y += dt * (1.0 + k * 0.3)
		r.scale = Vector3.ONE * (1.0 + (_flash[k] if k < _flash.size() else 0.0) * 0.8)
		k += 1
	if _snaps.is_empty():
		return
	var t := Time.get_ticks_msec() / 1000.0 - INTERP_DELAY
	var s0: Array = _snaps[0]
	var s1: Array = _snaps[-1]
	var f := 1.0
	for i in range(_snaps.size() - 1):
		if t >= _snaps[i][0] and t <= _snaps[i + 1][0]:
			s0 = _snaps[i]
			s1 = _snaps[i + 1]
			f = (t - s0[0]) / maxf(s1[0] - s0[0], 0.0001)
			break
	if t < _snaps[0][0]:
		s1 = _snaps[0]
		s0 = s1
	var pos: Vector3 = (s0[1] as Vector3).lerp(s1[1], f)
	var yaw := lerp_angle(float(s0[2]), float(s1[2]), f)
	pitch = lerpf(float(s0[3]), float(s1[3]), f)
	global_position = pos
	body.rotation.y = yaw
	head.rotation.x = pitch * 0.6
	var gid := str(s1[4])
	for id2 in weapons:
		weapons[id2].visible = id2 == gid
	var flags := int(s1[5])
	_flags = flags
	_dead = (flags & 32) != 0
	# 变大、隐身
	var want := float(s1[9]) if s1.size() > 9 else 1.0
	_scale = lerpf(_scale, want, 1.0 - exp(-8.0 * dt))
	body.scale = Vector3.ONE * _scale
	label.position.y = 2.25 * _scale
	body.visible = (flags & 128) == 0
	var nm := "%s\n%d 级%s" % [str(info.get("name", "魂师")), int(info.get("level", 1)), Data.titles(int(info.get("level", 1)))]
	if flags & 128:
		nm += "\n（隐身中）"
	elif _dead and not (flags & 512):
		nm += "\n倒地！按住 F 救他"
	if label.text != nm:
		label.text = nm
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
	arm_r.rotation.x = PI / 2 * 0.85 + pitch
	body.position.y = -0.35 if flags & 8 else 0.0
	if _dead:
		body.rotation.x = -PI / 2
		body.position.y = 0.3
	else:
		body.rotation.x = 0.0
	lure.hand = arm_l.global_transform * Vector3(0, -0.5, 0)
	lure.apply_remote(int(s1[6]), s1[7], dt)
