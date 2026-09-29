class_name RemotePlayer
extends Node3D
## 其他玩家在我这边的样子：小人 + 名字等级 + 手里的暗器 + 身上的灵环 + 引魂索。
## 位置按对方发来的快照插值（落后 100ms，动作顺）。

const INTERP_DELAY := 0.1
const CUSTOM_MODELS := ["res://assets/models/player/player.glb", "res://assets/models/player/player.gltf"]

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
var _robe_parts: Array = []
var _accent_parts: Array = []
var _hat: Node3D
var _look := ""
var _flash := [0.0, 0.0, 0.0]
# 关节和会飘的东西
var _knee_l: Node3D
var _knee_r: Node3D
var _elbow_l: Node3D
var _elbow_r: Node3D
var _skirt: Array = []           # 长衣下摆：前左、前右、后
var _cape: Node3D
var _ribbon: Node3D
var _tassel: Node3D
var _skin_mat: Material
var _t := 0.0
var _custom: Node3D               # 自定义模型（没有就是 null）
var _custom_role := ""
# 混元人物（assets/models/player/player.glb，带骨骼和六段动作）：胳膊用 IK 端着暗器，暗器挂在 _gun_root 上每帧摆到右手
var _skel: Skeleton3D
var _ik: AimIK
var _chest_bone := -1
var _gun_root: Node3D


func setup(p_world: Node, id: int, p_info: Dictionary) -> void:
	world = p_world
	peer_id = id
	name = "P%d" % id
	var wuhun_idx := int(p_info.get("wuhun", 0))
	# 第十三版：用户说队友模型"很敷衍"（以前是一个胶囊身子 + 球头 + 四根棍）。
	# 现在是一个猎灵人：长衣（前两片后一片会跟着走路摆）、腰带和穗子、围巾、短披风（跑起来往后飘）、
	# 束发和飘带、护腕、靴子、背后的箭囊；腿和胳膊都有关节。长衣和披风用装扮的颜色，腰带、围巾用灵相的颜色
	var robe := U.mat(Color(0.92, 0.92, 0.88), 0.9)
	var accent := U.mat(Data.wuhun_color(wuhun_idx), 0.6)
	var skin := U.mat(Color(0.93, 0.78, 0.66), 0.8)
	var hair := U.mat(Color(0.1, 0.08, 0.08), 0.6)
	var dark := U.mat(Color(0.2, 0.18, 0.18), 0.8)
	var leather := U.mat(Color(0.26, 0.17, 0.11), 0.65)
	var cloth := U.mat(Color(0.14, 0.14, 0.17), 0.9)
	var metal := U.mat(Color(0.75, 0.62, 0.38), 0.35, 0.0, 0.8)
	_skin_mat = skin
	body = Node3D.new()
	add_child(body)
	FxLib.no_decals(body)
	# 躯干：里衣 + 胸口（长衣的上半截）+ 肩
	U.part(body, U.capsule(0.2, 0.62), cloth, Vector3(0, 1.3, 0), Vector3.ZERO, Vector3(1.05, 1.0, 0.72))
	U.part(body, U.capsule(0.23, 0.58), robe, Vector3(0, 1.32, 0.02), Vector3.ZERO, Vector3(1.0, 1.0, 0.78))
	U.part(body, U.box(Vector3(0.1, 0.5, 0.02)), cloth, Vector3(0, 1.3, -0.17))
	U.part(body, U.sphere(0.12, 10, 8), robe, Vector3(-0.24, 1.55, 0), Vector3.ZERO, Vector3(1.1, 0.8, 1.0))
	U.part(body, U.sphere(0.12, 10, 8), robe, Vector3(0.24, 1.55, 0), Vector3.ZERO, Vector3(1.1, 0.8, 1.0))
	# 左肩护甲
	U.part(body, U.sphere(0.14, 10, 8), leather, Vector3(-0.27, 1.58, 0), Vector3(0, 0, 0.4), Vector3(1.0, 0.55, 1.1))
	U.part(body, U.torus(0.1, 0.14, 16, 4), metal, Vector3(-0.27, 1.6, 0), Vector3(0, 0, 0.4), Vector3(1.0, 1.0, 1.0))
	# 腰带（灵相的颜色）+ 带扣 + 垂下来的穗子
	U.part(body, U.cyl(0.215, 0.215, 0.09, 16), accent, Vector3(0, 1.02, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.8))
	U.part(body, U.box(Vector3(0.08, 0.07, 0.03)), metal, Vector3(0, 1.02, -0.18))
	_tassel = Node3D.new()
	_tassel.position = Vector3(0.12, 0.98, -0.16)
	body.add_child(_tassel)
	U.part(_tassel, U.cyl(0.012, 0.012, 0.22, 4), accent, Vector3(0, -0.11, 0))
	U.part(_tassel, U.cyl(0.03, 0.005, 0.1, 8), accent, Vector3(0, -0.26, 0))
	# 长衣的下摆：前面左右两片、后面一片（挂在腰上，走路会摆）
	for spec in [["front_l", Vector3(-0.1, 1.0, -0.1), Vector3(0.2, 0.62, 0.03)], ["front_r", Vector3(0.1, 1.0, -0.1), Vector3(0.2, 0.62, 0.03)], ["back", Vector3(0, 1.0, 0.13), Vector3(0.44, 0.7, 0.03)]]:
		var pv := Node3D.new()
		pv.position = spec[1]
		body.add_child(pv)
		var sz: Vector3 = spec[2]
		U.part(pv, U.box(sz), robe, Vector3(0, -sz.y * 0.5, 0))
		U.part(pv, U.box(Vector3(sz.x, 0.03, sz.z + 0.005)), accent, Vector3(0, -sz.y + 0.02, 0))
		_skirt.append(pv)
	# 围巾（灵相的颜色）+ 脖子
	U.part(body, U.cyl(0.06, 0.07, 0.1, 10), skin, Vector3(0, 1.66, 0))
	U.part(body, U.torus(0.07, 0.13, 20, 8), accent, Vector3(0, 1.64, 0), Vector3(0.15, 0, 0), Vector3(1.0, 1.4, 1.0))
	# 短披风：挂在肩后面，跑起来往后飘
	_cape = Node3D.new()
	_cape.position = Vector3(0, 1.6, 0.14)
	body.add_child(_cape)
	U.part(_cape, U.box(Vector3(0.52, 0.66, 0.02)), robe, Vector3(0, -0.33, 0.01))
	U.part(_cape, U.box(Vector3(0.52, 0.03, 0.025)), accent, Vector3(0, -0.65, 0.01))
	# 背后的箭囊（斜挎）
	U.part(body, U.cyl(0.06, 0.07, 0.5, 10), leather, Vector3(-0.12, 1.38, 0.2), Vector3(0, 0, 0.45))
	for k in 3:
		U.part(body, U.cyl(0.008, 0.008, 0.2, 4), dark, Vector3(-0.22 + k * 0.025, 1.66 + k * 0.01, 0.2), Vector3(0, 0, 0.45))
	U.part(body, U.box(Vector3(0.04, 0.62, 0.02)), leather, Vector3(0.0, 1.34, -0.17), Vector3(0, 0, -0.62))
	# 头：脸、眼睛、头发（束发 + 发髻 + 飘带）
	head = Node3D.new()
	head.position = Vector3(0, 1.8, 0)
	body.add_child(head)
	U.part(head, U.sphere(0.13, 16, 12), skin, Vector3.ZERO, Vector3.ZERO, Vector3(0.92, 1.05, 0.95))
	U.part(head, U.sphere(0.138, 16, 12), hair, Vector3(0, 0.035, 0.022), Vector3.ZERO, Vector3(0.95, 0.9, 0.98))
	U.part(head, U.sphere(0.06, 10, 8), hair, Vector3(0, 0.15, 0.06))
	U.part(head, U.torus(0.03, 0.05, 12, 4), accent, Vector3(0, 0.15, 0.06), Vector3(PI / 2, 0, 0))
	U.part(head, U.sphere(0.018, 6, 4), dark, Vector3(0.045, 0.01, -0.118))
	U.part(head, U.sphere(0.018, 6, 4), dark, Vector3(-0.045, 0.01, -0.118))
	U.part(head, U.box(Vector3(0.05, 0.008, 0.01)), hair, Vector3(0.045, 0.045, -0.12))
	U.part(head, U.box(Vector3(0.05, 0.008, 0.01)), hair, Vector3(-0.045, 0.045, -0.12))
	_ribbon = Node3D.new()
	_ribbon.position = Vector3(0, 0.15, 0.1)
	head.add_child(_ribbon)
	U.part(_ribbon, U.box(Vector3(0.03, 0.3, 0.005)), accent, Vector3(0.02, -0.15, 0.02))
	U.part(_ribbon, U.box(Vector3(0.03, 0.26, 0.005)), accent, Vector3(-0.02, -0.13, 0.03))
	# 腿：大腿（裤子）→ 膝盖 → 小腿（靴子）
	var lg := _limb2(body, Vector3(-0.1, 0.98, 0), cloth, leather, 0.075, 0.46, 0.45, true)
	leg_l = lg[0]
	_knee_l = lg[1]
	var rg := _limb2(body, Vector3(0.1, 0.98, 0), cloth, leather, 0.075, 0.46, 0.45, true)
	leg_r = rg[0]
	_knee_r = rg[1]
	# 胳膊：上臂（长衣）→ 手肘 → 小臂（护腕）→ 手
	var la := _limb2(body, Vector3(-0.28, 1.52, 0), robe, leather, 0.055, 0.29, 0.27, false)
	arm_l = la[0]
	_elbow_l = la[1]
	var ra := _limb2(body, Vector3(0.28, 1.52, 0), robe, leather, 0.055, 0.29, 0.27, false)
	arm_r = ra[0]
	_elbow_r = ra[1]
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).material_override == robe:
			_robe_parts.append(mi)
		elif (mi as MeshInstance3D).material_override == accent:
			_accent_parts.append(mi)
	# 有人自己做了模型（assets/models/player/player.glb，Tripo / Meshy 生成的也行）就用它：
	# 程序做的身子藏起来，模型按高度缩到 1.85 米、脚踩地；动画按名字找 idle / walk|run / jump
	var cpath := _custom_path()
	if cpath != "":
		for mi in body.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).visible = false
		_custom = BeastModels.instance_custom(cpath, {"fit": "h", "size": 1.85})
		_custom.position.y = 0.925
		body.add_child(_custom)
		FxLib.no_decals(_custom)
		var sks := _custom.find_children("*", "Skeleton3D", true, false)
		if sks.size() > 0:
			_skel = sks[0]
			_chest_bone = _skel.find_bone("Spine2")
			if _skel.find_bone("RightArm") >= 0 and _skel.find_bone("LeftArm") >= 0:
				_ik = AimIK.new()
				_skel.add_child(_ik)
				_gun_root = Node3D.new()
				_gun_root.name = "GunRoot"
				add_child(_gun_root)
		if _custom.has_meta("ap"):
			var ap0: AnimationPlayer = _custom.get_meta("ap")
			if ap0.has_animation("sprint"):
				ap0.get_animation("sprint").loop_mode = Animation.LOOP_LINEAR
	_hat = Node3D.new()
	head.add_child(_hat)
	var coil := U.part(_elbow_l, U.torus(0.06, 0.08, 20, 6), U.glow(Color(0.45, 0.8, 1.0), 2.5), Vector3(0, -0.14, 0))
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


static func _custom_path() -> String:
	for p in CUSTOM_MODELS:
		if ResourceLoader.exists(p):
			return p
	return ""


func set_info(p_info: Dictionary) -> void:
	info = p_info
	_apply_look(str(info.get("outfit", "default")), str(info.get("skin", "default")), info.get("skins", {}) as Dictionary)
	label.text = "%s\n%d 级%s" % [str(info.get("name", "修士")), int(info.get("level", 1)), Data.titles(int(info.get("level", 1)))]
	for c in ring_root.get_children():
		c.queue_free()
	var rs: Array = info.get("rings", [])
	# 灵环：从脚下往上一圈一圈，颜色按年份
	for i in rs.size():
		var col := Data.age_color(int(rs[i]))
		var r := U.part(ring_root, U.torus(0.55, 0.62, 40, 6), U.glow(col, 2.0), Vector3(0, 0.25 + i * 0.35, 0), Vector3.ZERO, Vector3.ONE, false)
		r.name = "R%d" % i


## 装扮（长袍颜色、点缀、帽子）和手里暗器的皮肤（skins：每把暗器单独穿的皮肤）
func _apply_look(outfit: String, skin: String, skins := {}) -> void:
	var key := outfit + "|" + skin + "|" + JSON.stringify(skins)
	if key == _look:
		return
	_look = key
	var of: Dictionary = Data.OUTFITS.get(outfit, Data.OUTFITS["default"])
	var robe := U.mat(of["robe"], 0.8, 0.0, 0.5 if outfit == "gold" else 0.0)
	for mi in _robe_parts:
		(mi as MeshInstance3D).material_override = robe
	if of.has("accent"):
		var acc := U.mat(of["accent"], 0.5, 0.6 if outfit == "flame" else 0.0, 0.6)
		for mi in _accent_parts:
			(mi as MeshInstance3D).material_override = acc
	for c in _hat.get_children():
		c.queue_free()
	match "" if _custom else str(of.get("hat", "")):
		"douli":
			U.part(_hat, U.cyl(0.02, 0.32, 0.14, 20), U.mat(Color(0.72, 0.6, 0.38), 0.9), Vector3(0, 0.15, 0))
		"hood":
			U.part(_hat, U.sphere(0.16, 14, 10), robe, Vector3(0, 0.03, 0.035), Vector3.ZERO, Vector3(1.05, 1.0, 1.12))
		"crown":
			var gold := U.mat(Color(1.0, 0.82, 0.35), 0.25, 0.4, 0.9)
			U.part(_hat, U.torus(0.1, 0.13, 20, 6), gold, Vector3(0, 0.13, 0))
			for k in 6:
				var a := TAU * k / 6.0
				U.part(_hat, U.cyl(0.0, 0.022, 0.07, 6), gold, Vector3(cos(a) * 0.115, 0.18, sin(a) * 0.115))
	for id2 in weapons:
		(weapons[id2] as Node).queue_free()
	weapons.clear()
	for id2 in Data.WEAPON_ORDER:
		var w := WeaponModels.build_small(id2, str(skins.get(id2, skin)))
		w.visible = false
		if _gun_root:
			_gun_root.add_child(w)
		else:
			w.position = Vector3(0, -0.52, -0.15)
			arm_r.add_child(w)
		weapons[id2] = w


func flash_ring(slot: int) -> void:
	if slot < _flash.size():
		_flash[slot] = 1.0


## 两节的胳膊 / 腿：上半截挂在 pivot 上，下半截挂在关节上（膝盖 / 手肘）。腿的末端是靴子，胳膊的末端是手。返回 [pivot, 关节]
func _limb2(parent: Node3D, pos: Vector3, m1: Material, m2: Material, r: float, l1: float, l2: float, leg: bool) -> Array:
	var pivot := Node3D.new()
	pivot.position = pos
	parent.add_child(pivot)
	U.part(pivot, U.capsule(r, l1 + r), m1, Vector3(0, -l1 * 0.5, 0))
	var j := Node3D.new()
	j.position = Vector3(0, -l1, 0)
	pivot.add_child(j)
	U.part(j, U.capsule(r * 0.88, l2 + r), m2, Vector3(0, -l2 * 0.5, 0))
	if leg:
		U.part(j, U.box(Vector3(r * 2.0, 0.07, r * 3.6)), m2, Vector3(0, -l2 - 0.01, -r * 0.9))
		U.part(j, U.cyl(r * 1.08, r * 1.08, 0.06, 10), m2, Vector3(0, -l2 * 0.35, 0))
	else:
		U.part(j, U.cyl(r * 1.05, r * 1.1, l2 * 0.5, 10), m2, Vector3(0, -l2 * 0.6, 0))
		U.part(j, U.sphere(r * 0.95, 10, 8), _skin_mat, Vector3(0, -l2 - 0.03, 0))
	return [pivot, j]


func set_camera(c: Camera3D) -> void:
	lure.set_camera(c)


func is_dead() -> bool:
	return _dead


## 隐身、刚复活、被海鸥叼着：灵兽和 Boss 不打他
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
	var nm := "%s\n%d 级%s" % [str(info.get("name", "修士")), int(info.get("level", 1)), Data.titles(int(info.get("level", 1)))]
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
	_t += dt
	_walk_t += dt * speed * 1.6
	var run_k := clampf(speed / 6.0, 0.0, 1.0)
	var air := not (flags & 1)
	var crouch := (flags & 8) != 0
	var swing := sin(_walk_t) * run_k * 0.75
	if air:
		swing = 0.35
	# 腿：往前迈的时候大腿抬，往后的时候膝盖弯
	leg_l.rotation.x = swing
	leg_r.rotation.x = -swing
	_knee_l.rotation.x = -(maxf(-sin(_walk_t), 0.0) * run_k * 1.1 + (0.7 if air else 0.0))
	_knee_r.rotation.x = -(maxf(sin(_walk_t), 0.0) * run_k * 1.1 + (0.2 if air else 0.0))
	if crouch:
		leg_l.rotation.x = 0.9
		leg_r.rotation.x = 0.7
		_knee_l.rotation.x = -1.6
		_knee_r.rotation.x = -1.4
	# 胳膊：左手跟着摆、手肘微弯；右手端着暗器
	arm_l.rotation.x = -swing * 0.6
	_elbow_l.rotation.x = 0.35 + run_k * 0.4
	arm_r.rotation.x = PI / 2 * 0.85 + pitch
	_elbow_r.rotation.x = 0.0
	# 长衣下摆跟着腿摆，后片、披风、飘带跑起来往后飘
	(_skirt[0] as Node3D).rotation.x = maxf(swing, 0.0) * 0.9 + 0.04
	(_skirt[1] as Node3D).rotation.x = maxf(-swing, 0.0) * 0.9 + 0.04
	(_skirt[2] as Node3D).rotation.x = -(0.08 + run_k * 0.4 + sin(_t * 7.0) * 0.04 * run_k)
	_cape.rotation.x = -(0.06 + run_k * 0.7 + sin(_t * 6.0) * 0.06 * (0.3 + run_k)) - (0.4 if air else 0.0)
	_ribbon.rotation.x = -(0.25 + run_k * 0.9) + sin(_t * 9.0) * 0.12
	_tassel.rotation.x = sin(_walk_t * 2.0) * 0.35 * run_k
	# 混元人物自己有蹲、冲刺的动作，不用再压低 / 前倾
	var own_anim := _skel != null
	body.position.y = (-0.3 if crouch and not own_anim else 0.0) + (0.0 if own_anim else absf(sin(_walk_t)) * 0.03 * run_k)
	if _dead:
		body.rotation.x = -PI / 2
		body.position.y = 0.3
	else:
		# 冲刺时身子往前倾
		body.rotation.x = lerp_angle(body.rotation.x, -0.18 if (flags & 2) and not own_anim else 0.0, 1.0 - exp(-8.0 * dt))
	lure.hand = _elbow_l.global_transform * Vector3(0, -0.3, 0)
	lure.apply_remote(int(s1[6]), s1[7], dt)
	if _custom and _custom.has_meta("ap"):
		var ap: AnimationPlayer = _custom.get_meta("ap")
		var roles: Dictionary = _custom.get_meta("roles")
		var role := "idle"
		var anim := ""
		if air and str(roles.get("air", "")) != "":
			role = "air"
		elif crouch and ap.has_animation("crouch"):
			role = "crouch"
			anim = "crouch"
		elif speed > 0.6 and (flags & 2) and ap.has_animation("sprint"):
			role = "sprint"
			anim = "sprint"
		elif speed > 0.6 and speed < 2.6 and str(roles.get("walk", "")) != "":
			role = "walk"
		elif speed > 0.6 and str(roles.get("run", "")) != "":
			role = "run"
		if anim == "":
			anim = str(roles.get(role, ""))
		match role:
			"run":
				ap.speed_scale = clampf(speed / 5.0, 0.7, 1.6)
			"sprint":
				ap.speed_scale = clampf(speed / 7.5, 0.8, 1.5)
			"walk":
				ap.speed_scale = clampf(speed / 1.6, 0.7, 1.6)
			_:
				ap.speed_scale = 1.0
		if role != _custom_role and anim != "":
			_custom_role = role
			ap.play(anim, 0.2)
	_update_aim()


## 混元人物端暗器：按朝向和抬头低头算两只手的位置（相对胸口），交给 AimIK；暗器摆到右手
func _update_aim() -> void:
	if _ik == null:
		return
	var holding := not _dead and (_flags & 128) == 0 and _gun_root != null
	_ik.active = holding
	_gun_root.visible = holding
	if not holding:
		return
	var bx := body.global_transform
	var yb := bx.basis.orthonormalized()
	var f := yb * Vector3(0, sin(pitch), -cos(pitch))
	var up := yb * Vector3(0, cos(pitch), sin(pitch))
	var right := yb * Vector3.RIGHT
	var chest := bx * Vector3(0, 1.38, 0)
	if _chest_bone >= 0:
		chest = _skel.global_transform * _skel.get_bone_global_pose(_chest_bone).origin
	var s := _scale
	var r := chest + (right * 0.12 + f * 0.3 + up * 0.06) * s
	_ik.r_target = r
	_ik.l_target = r + (f * 0.3 - right * 0.07 - up * 0.03) * s
	_ik.r_pole = chest + (right * 0.5 - yb.y * 0.6 - f * 0.2) * s
	_ik.l_pole = chest + (-right * 0.5 - yb.y * 0.6) * s
	_gun_root.global_transform = Transform3D(Basis(yb.x, up, -f).orthonormalized().scaled(Vector3.ONE * s), r + f * 0.08 * s)
