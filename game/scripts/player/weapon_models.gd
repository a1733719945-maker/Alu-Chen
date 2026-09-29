class_name WeaponModels
extends RefCounted
## 第一人称暗器模型。每个模型里有几个特殊节点：
##   Muzzle    箭射出去的位置
##   Sight     开镜时眼睛对准的点（照门），开镜会把它移到屏幕正中
##   Mag       换弹时拆下来的部分
##   ArmL/ArmR 弩臂，开火时往前弹
##   Lever     机括（连机神弩的拉杆、穿云弩的栓），开火后动一下
##   LeftHand  托着暗器的左手（甩引魂索时藏起来）
## 朝向：-Z 向前，原点在右手握把。


## 默认的底色（皮肤的 pal 里没写的用这个）
const BASE_PAL := {"wood": Color(0.36, 0.2, 0.12), "lacquer": Color(0.32, 0.05, 0.05), "black": Color(0.07, 0.06, 0.06),
	"bronze": Color(0.55, 0.38, 0.2), "gold": Color(0.9, 0.7, 0.3), "iron": Color(0.28, 0.29, 0.31)}
const ROLES := ["wood", "lacquer", "black", "bronze", "gold", "iron"]
static var _no_arms := false       # 预览（暗器铺、画皮肤）不要手和袖子
static var _boxes := {}            # 暗器 -> 侧面范围 Rect2（画皮肤投影用）


## 材质。skin：暗器皮肤（Data.GUN_SKINS），outfit：装扮（袖子颜色）。空字符串 = 用自己存档里穿的
## weapon：哪把暗器（每把暗器可以穿不同的皮肤；自己画的皮肤要知道是哪把）
static func _mats(skin := "", outfit := "", weapon := "") -> Dictionary:
	if skin == "":
		skin = Profile.skin_for(weapon) if weapon != "" else Profile.skin
	if outfit == "":
		outfit = Profile.outfit
	var sk: Dictionary = Data.GUN_SKINS.get(skin, Data.GUN_SKINS["default"])
	var of: Dictionary = Data.OUTFITS.get(outfit, Data.OUTFITS["default"])
	var pal: Dictionary = sk.get("pal", {})
	var glow: Color = sk.get("glow", Color(0.35, 0.95, 0.8))
	var sleeve: Color = Color(0.1, 0.11, 0.17) if outfit == "default" else (of["robe"] as Color)
	var cuff: Color = of.get("accent", Color(0.85, 0.66, 0.3))
	var m := {
		# 手（2026-09-29 重做，用户说以前是"巧克力手"）：半指皮手套 + 露出来的手指是皮肤（带透光）
		"skin": _skin_mat(),
		"glove": MatLib.leather(Color(0.2, 0.13, 0.09)),
		"bracer": MatLib.leather(Color(0.13, 0.09, 0.07)),
		"trim": MatLib.bronze(),
		"sleeve": MatLib.cloth(sleeve, false, 9.0),
		"cuff": U.mat(cuff, 0.35, 0.0, 0.7),
		"inner": MatLib.cloth(Color(0.86, 0.84, 0.78), false, 9.0),
		"string": U.mat(Color(0.9, 0.88, 0.8), 0.8),
		"jade": U.glow(glow, 1.6 if skin == "default" else 2.4),
		# 翎羽：有明暗的发光材质（纯发光的看起来是一块平的色块）
		"feather": U.mat(Color(0.2, 0.75, 0.9) if skin == "default" else glow, 0.3, 0.6, 0.2),
		"lens": U.glow(Color(0.45, 0.75, 1.0), 2.5),
		# 瞄具、配件不跟皮肤（像 CS 一样，配件是另外装上去的黑色金属件）
		"optic": U.mat(Color(0.06, 0.06, 0.07), 0.4, 0.0, 0.35),
		"acc": U.mat(Color(0.2, 0.21, 0.22), 0.3, 0.0, 0.9),
	}
	for role in ROLES:
		m[role] = GunSkin.material(sk, role, pal.get(role, BASE_PAL[role]), weapon)
	return m


static func _marker(parent: Node3D, name: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = name
	n.position = pos
	parent.add_child(n)
	return n


static func _p(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := U.part(parent, mesh, mat, pos, rot, scl, false)
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# 皮肤的花纹按暗器根节点的坐标算：把这个零件相对根节点的位置告诉着色器
	if GunSkin.is_skin_mat(mat):
		GunSkin.bind_part(mi)
	return mi


static var _skin: StandardMaterial3D


## 皮肤：暖色、有一点透光（次表面散射）和边缘光，不再是一坨深棕色
static func _skin_mat() -> StandardMaterial3D:
	if _skin == null:
		_skin = StandardMaterial3D.new()
		_skin.albedo_color = Color(0.62, 0.43, 0.32)
		_skin.roughness = 0.6
		_skin.subsurf_scatter_enabled = true
		_skin.subsurf_scatter_strength = 0.2
		_skin.rim_enabled = true
		_skin.rim = 0.08
		_skin.rim_tint = 0.8
		_skin.normal_enabled = true
		_skin.normal_texture = MatLib.tex("leather_normal")
		_skin.normal_scale = 0.15
		_skin.uv1_triplanar = true
		_skin.uv1_scale = Vector3.ONE * 30.0
	return _skin


## 一节手指 / 指骨：从 a 到 b 的胶囊
static func _seg(parent: Node3D, a: Vector3, b: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var d := b - a
	var mi := _p(parent, U.capsule(r, d.length() + r * 2.0), mat, (a + b) * 0.5)
	mi.basis = Basis(Quaternion(Vector3.UP, d.normalized()))
	return mi


## 一只握拳的手（半指皮手套）：手背、四根三节的手指绕着握把弯过去、大拇指压在上面。side = 1 右手，-1 左手
## 手的本地坐标：-Z 朝前，握把是竖着的（Y 轴），手指从右往左（右手）包住握把
static func fist(parent: Node3D, m: Dictionary, pos: Vector3, rot: Vector3, side := 1.0) -> Node3D:
	var h := Node3D.new()
	h.position = pos
	h.rotation = rot
	parent.add_child(h)
	var gc := Vector3(-0.004 * side, 0, -0.004)      # 握把中心
	# 手背 + 手掌（手套）
	_p(h, U.sphere(0.03, 16, 12), m["glove"], Vector3(0.015 * side, -0.002, 0.012), Vector3.ZERO, Vector3(0.85, 1.4, 1.25))
	_p(h, U.sphere(0.026, 12, 8), m["glove"], Vector3(0.006 * side, 0.018, 0.018), Vector3.ZERO, Vector3(1.0, 0.8, 1.0))
	# 手指：每根三节，按角度绕着握把（右边 → 前面 → 左边 → 往回收）
	var ys := [0.026, 0.009, -0.008, -0.024]
	var rs := [0.0092, 0.0096, 0.009, 0.0079]
	var angs := [deg_to_rad(-12.0), deg_to_rad(-80.0), deg_to_rad(-148.0), deg_to_rad(-200.0)]
	for k in 4:
		var r: float = rs[k]
		var R := 0.017 + r
		var pts: Array[Vector3] = []
		for i in 4:
			var a: float = angs[i]
			var rr := R * (1.0 - 0.06 * i)
			pts.append(gc + Vector3(cos(a) * rr * side, float(ys[k]) - i * 0.0012, sin(a) * rr))
		_seg(h, pts[0], pts[1], r, m["glove"])            # 第一节在手套里
		_seg(h, pts[1], pts[2], r * 0.93, m["skin"])
		_seg(h, pts[2], pts[3], r * 0.85, m["skin"])
		# 指关节（手套上鼓起来的一圈）
		_p(h, U.sphere(r * 1.18, 10, 6), m["glove"], pts[0] + Vector3(0.002 * side, 0, 0.001))
	# 大拇指：根部在手套里，从手背上方压过握把，指尖朝前下
	var t0 := Vector3(0.012 * side, 0.036, 0.008)
	var t1 := Vector3(-0.004 * side, 0.04, -0.014)
	var t2 := Vector3(-0.015 * side, 0.034, -0.03)
	_seg(h, t0, t1, 0.0125, m["glove"])
	_seg(h, t1, t2, 0.0105, m["skin"])
	return h


## 袖子：千机阁长袍（布料贴图），手腕一圈皮护腕 + 两道青铜箍，里面露一点白色里衣，袖口一道彩边
## elbow：从手腕指向手肘的方向（前臂斜着往下、往外、往后伸出画面，像 CS 里的手臂）
static func sleeve(parent: Node3D, m: Dictionary, wrist: Vector3, elbow: Vector3) -> Node3D:
	var s := Node3D.new()
	s.position = wrist
	parent.add_child(s)
	# 让本地 +Z 指向手肘
	s.basis = Basis.looking_at(-elbow.normalized(), Vector3.UP if absf(elbow.normalized().y) < 0.95 else Vector3.FORWARD)
	var rx := Vector3(PI / 2, 0, 0)
	_p(s, U.cyl(0.023, 0.025, 0.03, 16), m["glove"], Vector3(0, 0, -0.008), rx)
	_p(s, U.cyl(0.029, 0.033, 0.07, 18), m["bracer"], Vector3(0, 0, 0.026), rx)
	for zz in [-0.004, 0.056]:
		_p(s, U.cyl(0.0335, 0.0335, 0.008, 18), m["trim"], Vector3(0, 0, zz), rx)
	_p(s, U.cyl(0.035, 0.036, 0.016, 18), m["inner"], Vector3(0, 0, 0.068), rx)
	_p(s, U.cyl(0.041, 0.04, 0.014, 20), m["cuff"], Vector3(0, 0, 0.08), rx)
	# 袖子往手肘方向越来越宽（Y 轴转到 +Z 后，cyl 的 top 在 -Z 端）
	_p(s, U.cyl(0.039, 0.055, 0.42, 20), m["sleeve"], Vector3(0, 0, 0.295), Vector3(-PI / 2, 0, 0))
	return s


static func _arm_right(root: Node3D, m: Dictionary, grip: Vector3) -> void:
	if _no_arms:
		return
	# 右手握把 + 袖子往右后方延伸出画面
	fist(root, m, grip, Vector3(0.15, 0, 0), 1.0)
	sleeve(root, m, grip + Vector3(0.014, -0.022, 0.045), Vector3(0.32, -0.55, 0.75))


static func _arm_left(root: Node3D, m: Dictionary, pos: Vector3) -> void:
	if _no_arms:
		return
	var lh := Node3D.new()
	lh.name = "LeftHand"
	lh.position = pos
	root.add_child(lh)
	# 左手从下面托着：手指从左边包上来
	fist(lh, m, Vector3(0, -0.012, 0), Vector3(0, 0, -0.9), -1.0)
	sleeve(lh, m, Vector3(-0.03, -0.038, 0.03), Vector3(-0.45, -0.6, 0.62))


static func _bow(root: Node3D, m: Dictionary, front: Vector3, span: float, thick: float, back: float) -> void:
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.name = "ArmL" if side < 0 else "ArmR"
		arm.position = front + Vector3(0.018 * side, 0, 0)
		arm.rotation.y = -0.32 * side
		root.add_child(arm)
		_p(arm, Props.rbox(Vector3(span, thick, thick * 1.6)), m["wood"], Vector3(span * 0.5 * side, 0, 0))
		_p(arm, Props.rbox(Vector3(span * 0.35, thick * 1.2, thick * 1.8)), m["gold"], Vector3(span * 0.18 * side, 0, 0))
		_p(arm, U.sphere(thick * 0.9, 8, 6), m["bronze"], Vector3(span * side, 0, 0))
	# 弓弦：从两边弩臂尖连到机括
	var tip := span * cos(0.32)
	var zback := span * sin(0.32)
	for side in [-1.0, 1.0]:
		var a := front + Vector3((0.018 + tip) * side, 0, zback)
		var b := front + Vector3(0, 0, back)
		var mid := (a + b) * 0.5
		var s := _p(root, U.cyl(0.0022, 0.0022, a.distance_to(b), 4), m["string"], mid)
		s.name = "String"
		# 圆柱的轴是 Y：先让 -Z 指向弦的方向，再绕 X 转 90° 把 Y 转过去
		s.basis = Basis.looking_at((b - a).normalized(), Vector3.UP) * Basis(Vector3.RIGHT, PI / 2)


## on：装着的配件 {"sight": "red", "muzzle": "brake", "under": "grip"}；null = 用自己存档里装的
## arms：要不要手和袖子（暗器铺预览不要）；charm：挂件 id（null = 存档里挂的，"" = 不挂）
static func build(id: String, skin := "", outfit := "", on: Variant = null, arms := true, charm: Variant = null) -> Node3D:
	_no_arms = not arms
	var root := _build(id, skin, outfit, on, charm)
	_no_arms = false
	# 画皮肤的投影范围：第一次搭这把暗器时按零件量出来（不算配件和手）
	if not _boxes.has(id) and id != "fist":
		_boxes[id] = _calc_box(root)
	var pb := GunSkin.box2to1(_boxes.get(id, Rect2(-0.4, -0.1, 0.8, 0.2)))
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mat := (mi as MeshInstance3D).material_override
		if GunSkin.is_skin_mat(mat):
			(mat as ShaderMaterial).set_shader_parameter("paint_box", pb)
	return root


## 暗器侧面的范围（Rect2：x 是 z 方向，y 是 y 方向），画皮肤用
static func side_box(id: String) -> Rect2:
	if not _boxes.has(id):
		var tmp := build(id, "default", "default", {}, false, "")
		tmp.free()
	return _boxes.get(id, Rect2(-0.4, -0.1, 0.8, 0.2))


static func _calc_box(root: Node3D) -> Rect2:
	var zmin := INF
	var zmax := -INF
	var ymin := INF
	var ymax := -INF
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not GunSkin.is_skin_mat(mi.material_override):
			continue
		var xf := Transform3D.IDENTITY
		var c: Node = mi
		while c != null and c != root and c is Node3D:
			xf = (c as Node3D).transform * xf
			c = c.get_parent()
		var bb := xf * mi.get_aabb()
		zmin = minf(zmin, bb.position.z)
		zmax = maxf(zmax, bb.end.z)
		ymin = minf(ymin, bb.position.y)
		ymax = maxf(ymax, bb.end.y)
	if zmin == INF:
		return Rect2(-0.4, -0.1, 0.8, 0.2)
	return Rect2(zmin, ymin, zmax - zmin, ymax - ymin)


static func _build(id: String, skin: String, outfit: String, on: Variant, charm: Variant) -> Node3D:
	var root := Node3D.new()
	root.name = id
	var m := _mats(skin, outfit, id)
	var att: Dictionary = (on as Dictionary) if on is Dictionary else (Profile.attach_on.get(id, {}) as Dictionary)
	var sight := str(att.get("sight", ""))
	match id:
		"fist":
			# 空手：两只拳头，出拳时往前打（ViewModel.punch）
			var r := Node3D.new()
			r.name = "FistR"
			r.position = Vector3(0.16, -0.17, -0.33)
			root.add_child(r)
			fist(r, m, Vector3.ZERO, Vector3(0.9, 0.15, -0.2), 1.0)
			sleeve(r, m, Vector3(0.014, -0.03, 0.045), Vector3(0.3, -0.55, 0.78))
			var l := Node3D.new()
			l.name = "LeftHand"
			l.position = Vector3(-0.16, -0.17, -0.33)
			root.add_child(l)
			fist(l, m, Vector3.ZERO, Vector3(0.9, -0.15, 0.2), -1.0)
			sleeve(l, m, Vector3(-0.014, -0.03, 0.045), Vector3(-0.3, -0.55, 0.78))
			_marker(root, "Muzzle", Vector3(0.16, -0.14, -0.4))
			_marker(root, "Sight", Vector3(0, 0, -0.3))
			return root
		"xiujian":
			_arm_right(root, m, Vector3(0, -0.035, -0.06))
			_p(root, U.cyl(0.014, 0.017, 0.26, 12), m["bronze"], Vector3(0.0, 0.025, -0.02), Vector3(PI / 2, 0, 0))
			_p(root, U.cyl(0.0, 0.009, 0.035, 6), m["iron"], Vector3(0.0, 0.025, -0.165), Vector3(-PI / 2, 0, 0))
			_p(root, U.cyl(0.019, 0.019, 0.025, 12), m["gold"], Vector3(0.0, 0.025, -0.14), Vector3(PI / 2, 0, 0))
			_p(root, U.cyl(0.019, 0.019, 0.02, 12), m["gold"], Vector3(0.0, 0.025, 0.09), Vector3(PI / 2, 0, 0))
			for zz in [0.0, 0.07]:
				_p(root, Props.rbox(Vector3(0.1, 0.012, 0.022)), m["black"], Vector3(0.0, -0.005, zz))
			var mag := _marker(root, "Mag", Vector3(0.0, 0.025, 0.12))
			_p(mag, U.cyl(0.012, 0.012, 0.05, 8), m["iron"], Vector3.ZERO, Vector3(PI / 2, 0, 0))
			_marker(root, "Muzzle", Vector3(0.0, 0.025, -0.19))
			if sight == "red":
				_reddot(root, m, Vector3(0, 0.068, 0.03), 0.04)
			else:
				_iron(root, m, Vector3(0, 0.047, -0.135), Vector3(0, 0.047, 0.085), 0.018)
			_marker(root, "Eject", Vector3(0.015, 0.035, 0.02))
		"zhuge":
			_arm_right(root, m, Vector3(0, -0.07, 0.1))
			_p(root, Props.rbox(Vector3(0.05, 0.055, 0.36)), m["wood"], Vector3(0, 0, 0.0))
			_p(root, Props.rbox(Vector3(0.036, 0.09, 0.05)), m["wood"], Vector3(0, -0.06, 0.1), Vector3(-0.35, 0, 0))
			_p(root, Props.rbox(Vector3(0.056, 0.012, 0.37)), m["gold"], Vector3(0, 0.028, 0.0))
			var mag := _marker(root, "Mag", Vector3(0, 0.065, -0.03))
			_p(mag, Props.rbox(Vector3(0.046, 0.07, 0.2)), m["black"])
			_p(mag, Props.rbox(Vector3(0.05, 0.008, 0.205)), m["gold"], Vector3(0, 0.036, 0))
			for k in 4:
				_p(mag, Props.rbox(Vector3(0.004, 0.004, 0.16)), m["jade"], Vector3(-0.012 + k * 0.008, 0.041, 0))
			var lever := _marker(root, "Lever", Vector3(0, 0.1, -0.12))
			_p(lever, Props.rbox(Vector3(0.012, 0.012, 0.24)), m["bronze"], Vector3(0, 0.0, 0.12), Vector3(0.12, 0, 0))
			_p(lever, U.cyl(0.012, 0.012, 0.06, 8), m["bronze"], Vector3(0, -0.01, 0.235), Vector3(0, 0, PI / 2))
			_bow(root, m, Vector3(0, 0.005, -0.17), 0.21, 0.016, 0.03)
			for k in 8:
				_p(root, Props.rbox(Vector3(0.05, 0.005, 0.008)), m["iron"], Vector3(0, 0.1, -0.06 + k * 0.016))
			_arm_left(root, m, Vector3(-0.005, -0.045, -0.11))
			_marker(root, "Muzzle", Vector3(0, 0.02, -0.26))
			_optic(root, m, sight, Vector3(0, 0.128, 0.02), 0.103)
			if sight == "":
				_iron(root, m, Vector3(0, 0.118, -0.125), Vector3(0, 0.118, 0.075), 0.022)
			_marker(root, "Eject", Vector3(0.03, 0.04, 0.0))
		"kongque":
			_arm_right(root, m, Vector3(0, -0.075, 0.14))
			_p(root, Props.rbox(Vector3(0.046, 0.06, 0.56)), m["lacquer"], Vector3(0, 0, 0.02))
			_p(root, Props.rbox(Vector3(0.05, 0.1, 0.12)), m["lacquer"], Vector3(0, -0.02, 0.26))
			_p(root, Props.rbox(Vector3(0.036, 0.09, 0.05)), m["wood"], Vector3(0, -0.07, 0.14), Vector3(-0.3, 0, 0))
			_p(root, Props.rbox(Vector3(0.05, 0.01, 0.57)), m["gold"], Vector3(0, 0.032, 0.02))
			_p(root, U.cyl(0.02, 0.022, 0.24, 12), m["bronze"], Vector3(0, 0.01, -0.34), Vector3(PI / 2, 0, 0))
			for k in 3:
				_p(root, U.cyl(0.024, 0.024, 0.012, 12), m["gold"], Vector3(0, 0.01, -0.26 - k * 0.07), Vector3(PI / 2, 0, 0))
			# 流光翎：一排发光的翎羽
			for k in 5:
				var a := (k - 2) * 0.28
				var f := _p(root, Props.rbox(Vector3(0.006, 0.07, 0.03)), m["feather"], Vector3(sin(a) * 0.03, 0.07, -0.12 + absf(k - 2) * 0.01), Vector3(0, 0, a))
				f.name = "Feather"
				_p(root, U.sphere(0.008, 6, 4), m["jade"], Vector3(sin(a) * 0.058, 0.1, -0.12))
			var mag := _marker(root, "Mag", Vector3(0, -0.07, -0.02))
			_p(mag, Props.rbox(Vector3(0.03, 0.1, 0.06)), m["jade"], Vector3(0, -0.02, 0), Vector3(0.15, 0, 0))
			_bow(root, m, Vector3(0, 0.0, -0.2), 0.14, 0.014, 0.1)
			_arm_left(root, m, Vector3(-0.005, -0.04, -0.2))
			_marker(root, "Muzzle", Vector3(0, 0.01, -0.51))
			_optic(root, m, sight, Vector3(0, 0.13, 0.06), 0.037)
			if sight == "":
				var ring := _p(root, U.torus(0.008, 0.013, 16, 6), m["gold"], Vector3(0, 0.058, 0.17), Vector3(PI / 2, 0, 0))
				ring.name = "Aperture"
				_p(root, Props.rbox(Vector3(0.004, 0.028, 0.004)), m["gold"], Vector3(0, 0.046, -0.44))
				_marker(root, "Sight", Vector3(0, 0.058, 0.17))
			# 枪管下战术手电
			_p(root, U.cyl(0.013, 0.013, 0.07, 12), m["black"], Vector3(0.028, -0.01, -0.3), Vector3(PI / 2, 0, 0))
			_p(root, U.cyl(0.011, 0.011, 0.002, 12), U.glow(Color(1.0, 0.97, 0.85), 3.0), Vector3(0.028, -0.01, -0.336), Vector3(PI / 2, 0, 0))
			_marker(root, "Eject", Vector3(0.03, 0.03, 0.05))
		"baoyu":
			_arm_right(root, m, Vector3(0, -0.06, 0.07))
			_p(root, Props.rbox(Vector3(0.1, 0.085, 0.22)), m["lacquer"], Vector3(0, 0, -0.03))
			for yy in [0.044, -0.044]:
				_p(root, Props.rbox(Vector3(0.106, 0.008, 0.226)), m["gold"], Vector3(0, yy, -0.03))
			_p(root, Props.rbox(Vector3(0.09, 0.075, 0.006)), m["black"], Vector3(0, 0, -0.142))
			for ix in 4:
				for iy in 3:
					_p(root, U.sphere(0.0055, 5, 3), m["gold"], Vector3(-0.03 + ix * 0.02, -0.02 + iy * 0.02, -0.146))
			var pump := _marker(root, "Lever", Vector3(0, -0.058, -0.06))
			_p(pump, Props.rbox(Vector3(0.07, 0.03, 0.1)), m["wood"])
			_p(root, Props.rbox(Vector3(0.02, 0.006, 0.12)), m["gold"], Vector3(0, 0.05, -0.05))
			var mag := _marker(root, "Mag", Vector3(0.0, 0.02, 0.09))
			_p(mag, Props.rbox(Vector3(0.05, 0.03, 0.03)), m["bronze"])
			_arm_left(root, m, Vector3(-0.06, -0.06, -0.07))
			_marker(root, "Muzzle", Vector3(0, 0, -0.16))
			_optic(root, m, sight, Vector3(0, 0.09, 0.0), 0.05)
			if sight == "":
				# 鬼环照门 + 夜光准星
				_p(root, U.torus(0.007, 0.011, 16, 6), m["iron"], Vector3(0, 0.062, 0.04), Vector3(PI / 2, 0, 0))
				_p(root, U.sphere(0.004, 6, 4), U.glow(Color(0.4, 1.0, 0.5), 3.0), Vector3(0, 0.062, -0.13))
				_marker(root, "Sight", Vector3(0, 0.062, 0.05))
			for k in 4:
				_p(root, U.cyl(0.008, 0.008, 0.03, 8), U.mat(Color(0.75, 0.12, 0.1), 0.5), Vector3(-0.058, 0.0, -0.08 + k * 0.022), Vector3(0, 0, PI / 2))
				_p(root, U.cyl(0.0085, 0.0085, 0.008, 8), m["gold"], Vector3(-0.07, 0.0, -0.08 + k * 0.022), Vector3(0, 0, PI / 2))
			_marker(root, "Eject", Vector3(0.05, 0.02, 0.0))
		"zhuihun":
			_arm_right(root, m, Vector3(0, -0.08, 0.16))
			_p(root, Props.rbox(Vector3(0.05, 0.065, 0.66)), m["wood"], Vector3(0, 0, 0.0))
			_p(root, Props.rbox(Vector3(0.055, 0.11, 0.14)), m["wood"], Vector3(0, -0.025, 0.3))
			_p(root, Props.rbox(Vector3(0.056, 0.01, 0.67)), m["iron"], Vector3(0, 0.035, 0.0))
			_p(root, Props.rbox(Vector3(0.036, 0.09, 0.05)), m["black"], Vector3(0, -0.07, 0.16), Vector3(-0.3, 0, 0))
			var lever := _marker(root, "Lever", Vector3(0.035, 0.02, 0.1))
			_p(lever, U.cyl(0.006, 0.006, 0.06, 6), m["iron"], Vector3(0.03, 0, 0), Vector3(0, 0, PI / 2))
			_p(lever, U.sphere(0.013, 8, 6), m["bronze"], Vector3(0.062, 0, 0))
			var mag := _marker(root, "Mag", Vector3(0, -0.06, -0.05))
			_p(mag, Props.rbox(Vector3(0.03, 0.06, 0.08)), m["iron"])
			_bow(root, m, Vector3(0, 0.0, -0.3), 0.3, 0.02, 0.12)
			_arm_left(root, m, Vector3(-0.005, -0.045, -0.2))
			_marker(root, "Muzzle", Vector3(0, 0.02, -0.34))
			if sight == "scope":
				for zz in [-0.04, 0.07]:
					_p(root, Props.rbox(Vector3(0.012, 0.04, 0.02)), m["iron"], Vector3(0, 0.055, zz))
				_scope(root, m, Vector3(0, 0.085, 0.0))
			else:
				_optic(root, m, sight, Vector3(0, 0.1, 0.0), 0.04)
				if sight == "":
					_iron(root, m, Vector3(0, 0.068, -0.3), Vector3(0, 0.068, 0.12), 0.03)
			# 两脚架（收起）
			for s in [-1.0, 1.0]:
				_p(root, U.cyl(0.005, 0.005, 0.16, 6), m["black"], Vector3(0.012 * s, -0.04, -0.2), Vector3(PI / 2, 0, 0))
			_marker(root, "Eject", Vector3(0.035, 0.03, 0.08))
		"meihua":
			# 寒梅袖箭：腕上的筒，前面五个箭孔排成一朵梅花，侧面一朵金梅
			_arm_right(root, m, Vector3(0, -0.035, -0.06))
			_p(root, U.cyl(0.021, 0.024, 0.22, 16), m["lacquer"], Vector3(0.0, 0.025, -0.03), Vector3(PI / 2, 0, 0))
			for zz in [-0.13, -0.07, 0.07]:
				_p(root, U.cyl(0.026, 0.026, 0.014, 16), m["gold"], Vector3(0.0, 0.025, zz), Vector3(PI / 2, 0, 0))
			_p(root, U.cyl(0.024, 0.024, 0.01, 16), m["bronze"], Vector3(0.0, 0.025, -0.142), Vector3(PI / 2, 0, 0))
			for k in 5:
				var a := k * TAU / 5.0 + PI / 2
				_p(root, U.cyl(0.0042, 0.0042, 0.012, 8), m["black"], Vector3(cos(a) * 0.012, 0.025 + sin(a) * 0.012, -0.149), Vector3(PI / 2, 0, 0))
			# 侧面（朝里、看得见的一面）的金梅花
			for k in 5:
				var a2 := k * TAU / 5.0
				_p(root, U.sphere(0.0065, 8, 6), m["gold"], Vector3(-0.024, 0.025 + sin(a2) * 0.011, -0.02 + cos(a2) * 0.011), Vector3.ZERO, Vector3(0.5, 1, 1))
			_p(root, U.sphere(0.005, 8, 6), m["jade"], Vector3(-0.026, 0.025, -0.02))
			for zz in [0.0, 0.07]:
				_p(root, Props.rbox(Vector3(0.1, 0.012, 0.022)), m["black"], Vector3(0.0, -0.005, zz))
			var mag := _marker(root, "Mag", Vector3(0.0, 0.025, 0.1))
			_p(mag, U.cyl(0.014, 0.014, 0.04, 10), m["iron"], Vector3.ZERO, Vector3(PI / 2, 0, 0))
			_marker(root, "Muzzle", Vector3(0.0, 0.025, -0.16))
			if sight in ["red", "holo"]:
				_optic(root, m, sight, Vector3(0, 0.072, 0.02), 0.045)
			else:
				_iron(root, m, Vector3(0, 0.049, -0.125), Vector3(0, 0.049, 0.075), 0.018)
			_marker(root, "Eject", Vector3(0.015, 0.035, 0.02))
		"longxu":
			# 追星针：细长的射手暗器，枪管前面一个金龙头，两根龙须顺着枪管往后飘
			_arm_right(root, m, Vector3(0, -0.075, 0.14))
			_p(root, Props.rbox(Vector3(0.042, 0.052, 0.5)), m["lacquer"], Vector3(0, 0, 0.0))
			_p(root, Props.rbox(Vector3(0.046, 0.1, 0.15)), m["wood"], Vector3(0, -0.022, 0.29))
			_p(root, Props.rbox(Vector3(0.048, 0.012, 0.16)), m["black"], Vector3(0, -0.075, 0.29))
			_p(root, Props.rbox(Vector3(0.034, 0.09, 0.05)), m["black"], Vector3(0, -0.07, 0.14), Vector3(-0.3, 0, 0))
			_p(root, Props.rbox(Vector3(0.046, 0.008, 0.51)), m["gold"], Vector3(0, 0.029, 0.0))
			_p(root, U.cyl(0.009, 0.011, 0.34, 12), m["iron"], Vector3(0, 0.012, -0.42), Vector3(PI / 2, 0, 0))
			# 龙头
			_p(root, U.sphere(0.022, 12, 8), m["gold"], Vector3(0, 0.012, -0.26), Vector3.ZERO, Vector3(0.9, 0.8, 1.4))
			for s in [-1.0, 1.0]:
				_p(root, U.cyl(0.0, 0.006, 0.03, 6), m["gold"], Vector3(0.01 * s, 0.03, -0.25), Vector3(-0.6, 0, 0.3 * s))
				_p(root, U.sphere(0.004, 6, 4), m["jade"], Vector3(0.016 * s, 0.02, -0.275))
				# 龙须：两根细金线斜着往后飘
				for j in 3:
					_p(root, U.cyl(0.0018, 0.0018, 0.05, 4), m["gold"], Vector3(0.018 * s + j * 0.004 * s, 0.004 - j * 0.005, -0.3 + j * 0.035), Vector3(PI / 2 + 0.3, 0, 0.35 * s))
			var mag := _marker(root, "Mag", Vector3(0, -0.055, -0.04))
			_p(mag, Props.rbox(Vector3(0.026, 0.07, 0.05)), m["iron"], Vector3(0, -0.01, 0), Vector3(0.12, 0, 0))
			_arm_left(root, m, Vector3(-0.005, -0.04, -0.2))
			_marker(root, "Muzzle", Vector3(0, 0.012, -0.6))
			_optic(root, m, sight, Vector3(0, 0.1, 0.05), 0.03)
			if sight == "":
				_iron(root, m, Vector3(0, 0.055, -0.22), Vector3(0, 0.055, 0.14), 0.022)
			_marker(root, "Eject", Vector3(0.03, 0.03, 0.05))
		"zimu":
			# 子母雷珠：前面一个鼓鼓的"胆"，三道金箍，旁边挂着三颗发光的子胆；泵动上膛
			_arm_right(root, m, Vector3(0, -0.07, 0.1))
			_p(root, Props.rbox(Vector3(0.07, 0.08, 0.2)), m["lacquer"], Vector3(0, 0, 0.06))
			_p(root, Props.rbox(Vector3(0.05, 0.1, 0.12)), m["wood"], Vector3(0, -0.02, 0.2))
			_p(root, Props.rbox(Vector3(0.036, 0.09, 0.05)), m["black"], Vector3(0, -0.07, 0.1), Vector3(-0.3, 0, 0))
			_p(root, U.sphere(0.062, 18, 12), m["wood"], Vector3(0, 0.01, -0.1), Vector3.ZERO, Vector3(1, 1, 1.3))
			for k in 3:
				_p(root, U.torus(0.058, 0.066, 24, 6), m["gold"], Vector3(0, 0.01, -0.15 + k * 0.05), Vector3(PI / 2, 0, 0), Vector3(1.0 - absf(k - 1) * 0.12, 1.0 - absf(k - 1) * 0.12, 1))
			_p(root, U.cyl(0.03, 0.034, 0.16, 16), m["iron"], Vector3(0, 0.01, -0.24), Vector3(PI / 2, 0, 0))
			_p(root, U.torus(0.03, 0.038, 20, 6), m["bronze"], Vector3(0, 0.01, -0.32), Vector3(PI / 2, 0, 0))
			_p(root, U.cyl(0.026, 0.026, 0.004, 16), m["black"], Vector3(0, 0.01, -0.318), Vector3(PI / 2, 0, 0))
			for k in 3:
				var a := k * TAU / 3.0 + 0.5
				_p(root, U.sphere(0.012, 10, 6), m["jade"], Vector3(cos(a) * 0.066, 0.01 + sin(a) * 0.066, -0.1))
			var pump := _marker(root, "Lever", Vector3(0, -0.045, -0.24))
			_p(pump, Props.rbox(Vector3(0.05, 0.03, 0.09)), m["black"])
			var mag := _marker(root, "Mag", Vector3(0.045, 0.0, 0.06))
			_p(mag, U.cyl(0.012, 0.012, 0.05, 10), m["bronze"], Vector3.ZERO, Vector3(PI / 2, 0, 0))
			_arm_left(root, m, Vector3(-0.03, -0.07, -0.24))
			_marker(root, "Muzzle", Vector3(0, 0.01, -0.34))
			_optic(root, m, sight, Vector3(0, 0.12, 0.05), 0.04)
			if sight == "":
				_iron(root, m, Vector3(0, 0.1, -0.1), Vector3(0, 0.07, 0.12), 0.02)
			_marker(root, "Eject", Vector3(0.04, 0.03, 0.05))
		"hansha":
			# 流沙机弩：粗重的机匣，左边一个大弹鼓，枪管外面一圈六根小管，开火时转起来（Rotor）
			_arm_right(root, m, Vector3(0, -0.085, 0.15))
			_p(root, Props.rbox(Vector3(0.07, 0.085, 0.3)), m["lacquer"], Vector3(0, 0, 0.06))
			_p(root, Props.rbox(Vector3(0.05, 0.1, 0.14)), m["wood"], Vector3(0, -0.02, 0.28))
			_p(root, Props.rbox(Vector3(0.036, 0.09, 0.05)), m["black"], Vector3(0, -0.075, 0.15), Vector3(-0.3, 0, 0))
			_p(root, Props.rbox(Vector3(0.074, 0.01, 0.31)), m["gold"], Vector3(0, 0.044, 0.06))
			# 提把
			_p(root, Props.rbox(Vector3(0.012, 0.012, 0.12)), m["iron"], Vector3(0, 0.085, 0.05))
			for zz in [-0.005, 0.105]:
				_p(root, Props.rbox(Vector3(0.012, 0.04, 0.012)), m["iron"], Vector3(0, 0.064, zz))
			_p(root, U.cyl(0.03, 0.03, 0.2, 16), m["black"], Vector3(0, 0.012, -0.18), Vector3(PI / 2, 0, 0))
			var rotor := _marker(root, "Rotor", Vector3(0, 0.012, -0.36))
			for k in 6:
				var a := k * TAU / 6.0
				_p(rotor, U.cyl(0.006, 0.006, 0.2, 8), m["iron"], Vector3(cos(a) * 0.018, sin(a) * 0.018, 0), Vector3(PI / 2, 0, 0))
			for zz in [-0.06, 0.06]:
				_p(rotor, U.cyl(0.027, 0.027, 0.012, 16), m["bronze"], Vector3(0, 0, zz), Vector3(PI / 2, 0, 0))
			var mag := _marker(root, "Mag", Vector3(-0.07, -0.03, 0.02))
			_p(mag, U.cyl(0.07, 0.07, 0.05, 24), m["iron"], Vector3.ZERO, Vector3(0, 0, PI / 2))
			_p(mag, U.torus(0.064, 0.072, 24, 6), m["gold"], Vector3(-0.026, 0, 0), Vector3(0, 0, PI / 2))
			_p(mag, U.sphere(0.012, 8, 6), m["jade"], Vector3(-0.028, 0, 0))
			_arm_left(root, m, Vector3(-0.005, -0.06, -0.14))
			_marker(root, "Muzzle", Vector3(0, 0.012, -0.47))
			_optic(root, m, sight, Vector3(0, 0.12, 0.08), 0.045)
			if sight == "":
				_iron(root, m, Vector3(0, 0.07, -0.08), Vector3(0, 0.07, 0.18), 0.024)
			_marker(root, "Eject", Vector3(0.04, 0.03, 0.08))
		"guanyin":
			# 天心泪：白玉金边的弩身，两片莲瓣做弩臂，最前面悬着一滴发光的泪（Tear，蓄力时越来越亮）
			_arm_right(root, m, Vector3(0, -0.075, 0.13))
			_p(root, Props.rbox(Vector3(0.042, 0.055, 0.46)), m["lacquer"], Vector3(0, 0, 0.02))
			_p(root, Props.rbox(Vector3(0.048, 0.1, 0.12)), m["wood"], Vector3(0, -0.022, 0.24))
			_p(root, Props.rbox(Vector3(0.034, 0.09, 0.05)), m["black"], Vector3(0, -0.07, 0.13), Vector3(-0.3, 0, 0))
			_p(root, Props.rbox(Vector3(0.046, 0.008, 0.47)), m["gold"], Vector3(0, 0.031, 0.02))
			# 莲瓣护手
			for s in [-1.0, 1.0]:
				_p(root, U.sphere(0.04, 12, 8), m["bronze"], Vector3(0.03 * s, 0.0, -0.12), Vector3(0, 0.4 * s, 0), Vector3(0.25, 0.7, 1.4))
			_bow(root, m, Vector3(0, 0.005, -0.2), 0.15, 0.012, 0.08)
			var tear := _marker(root, "Tear", Vector3(0, 0.02, -0.3))
			var tm := (U.glow(Color(0.75, 0.92, 1.0), 2.0) as StandardMaterial3D).duplicate() as StandardMaterial3D
			root.set_meta("tear_mat", tm)
			_p(tear, U.sphere(0.018, 16, 10), tm)
			_p(tear, U.cyl(0.0, 0.018, 0.035, 16), tm, Vector3(0, 0, -0.022), Vector3(-PI / 2, 0, 0))
			for k in 3:
				var a := k * TAU / 3.0
				_p(root, U.cyl(0.0022, 0.0022, 0.05, 4), m["gold"], Vector3(cos(a) * 0.026, 0.02 + sin(a) * 0.026, -0.27), Vector3(PI / 2, 0, 0))
			var mag := _marker(root, "Mag", Vector3(0, -0.055, -0.02))
			_p(mag, Props.rbox(Vector3(0.026, 0.06, 0.06)), m["jade"])
			_arm_left(root, m, Vector3(-0.005, -0.045, -0.13))
			_marker(root, "Muzzle", Vector3(0, 0.02, -0.33))
			_optic(root, m, sight, Vector3(0, 0.1, 0.03), 0.035)
			if sight == "":
				_iron(root, m, Vector3(0, 0.058, -0.18), Vector3(0, 0.058, 0.13), 0.022)
			_marker(root, "Eject", Vector3(0.03, 0.03, 0.05))
	_attachments(root, m, id, att)
	var ch := (Profile.charm_for(id) if charm == null else str(charm))
	if ch != "":
		_charm(root, id, ch)
	return root


## 机械照门：前面一根准星柱、后面一个缺口。Sight 在缺口
static func _iron(root: Node3D, m: Dictionary, front: Vector3, rear: Vector3, h: float) -> void:
	var tritium := U.glow(Color(0.4, 1.0, 0.5), 3.0)
	_p(root, Props.rbox(Vector3(0.005, h, 0.006)), m["black"], front - Vector3(0, h * 0.5, 0))
	_p(root, U.sphere(0.0026, 6, 4), tritium, front + Vector3(0, -0.002, 0.003))
	for s in [-1.0, 1.0]:
		_p(root, Props.rbox(Vector3(0.007, h, 0.008)), m["black"], rear + Vector3(0.0065 * s, -h * 0.5 + 0.002, 0))
		_p(root, U.sphere(0.0024, 6, 4), tritium, rear + Vector3(0.0065 * s, -0.003, 0.004))
	_p(root, Props.rbox(Vector3(0.02, 0.006, 0.01)), m["black"], rear + Vector3(0, -h + 0.003, 0))
	_marker(root, "Sight", rear + Vector3(0, 0, 0.004))


## 按装的瞄具放模型：red 红点、holo 全息、x2 2 倍镜、x4 4 倍镜、scope 狙击镜（开镜时是全屏瞄准镜）
static func _optic(root: Node3D, m: Dictionary, sight: String, c: Vector3, base_y: float) -> void:
	match sight:
		"red":
			_reddot(root, m, c, base_y)
		"holo":
			_holo(root, m, c)
		"x2":
			_acog(root, m, c)
		"x4":
			_x4(root, m, c, base_y)
		"scope":
			_scope(root, m, c)


## 瞄具、配件用的材质：黑件换成配件自己的黑色（不跟皮肤），铁件换成枪灰金属
static func _om(m: Dictionary) -> Dictionary:
	var o := m.duplicate()
	o["black"] = m["optic"]
	o["iron"] = m["acc"]
	return o


## 4 倍镜：短一点的镜筒 + 两个镜座，开镜是全屏瞄准镜
static func _x4(root: Node3D, m: Dictionary, c: Vector3, base_y: float) -> void:
	m = _om(m)
	for zz in [-0.035, 0.045]:
		_p(root, Props.rbox(Vector3(0.014, c.y - base_y, 0.016)), m["black"], Vector3(c.x, (c.y + base_y) * 0.5, c.z + zz))
	var tube := _dbl(m["black"])
	_p(root, _open_tube(0.018, 0.018, 0.14), tube, c, Vector3(PI / 2, 0, 0))
	_p(root, _open_tube(0.019, 0.026, 0.045), tube, c + Vector3(0, 0, -0.09), Vector3(PI / 2, 0, 0))
	_p(root, U.torus(0.024, 0.029, 28, 6), m["gold"], c + Vector3(0, 0, -0.113), Vector3(PI / 2, 0, 0))
	_p(root, U.cyl(0.01, 0.01, 0.018, 12), m["black"], c + Vector3(0, 0.026, 0.0))
	_quad(root, 0.048, _shader_mat(GLASS_SHADER, {}), c + Vector3(0, 0, -0.112))
	_quad(root, 0.034, U.mat(Color(0.03, 0.05, 0.08), 0.1), c + Vector3(0, 0, 0.07), "ScopeLens")
	_marker(root, "Sight", c + Vector3(0, 0, 0.072))

# ------------------------------------------------------------------ 配件：瞄具、枪口、激光、手电、弹壳

const RETICLE_SHADER := """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.12, 0.08, 1.0);
uniform int kind = 0;
void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = smoothstep(0.1, 0.035, r) * 1.6 + smoothstep(0.16, 0.04, r) * 0.25;
	if (kind == 1) {
		a += smoothstep(0.05, 0.0, abs(r - 0.72)) * 1.2;
	} else if (kind == 2) {
		vec2 q = vec2(abs(p.x), p.y);
		float line = smoothstep(0.06, 0.0, abs(q.y + q.x * 0.9)) * step(-0.42, p.y) * step(p.y, 0.0);
		float post = smoothstep(0.04, 0.0, abs(p.x)) * step(p.y, -0.5) * step(-0.95, p.y);
		a = line * 1.5 + post + smoothstep(0.08, 0.02, r) * 1.2;
	}
	ALBEDO = color.rgb * a * 1.8;
}
"""
const GLASS_SHADER := """shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// 镜片：几乎透明，只有一点反光；不要一圈发蓝的边（用户说像劣质镀膜）
uniform vec4 tint : source_color = vec4(0.8, 0.85, 0.9, 0.03);
void fragment() {
	float r = length(UV - 0.5) * 2.0;
	if (r > 1.0) {
		discard;
	}
	float glint = smoothstep(0.25, 0.0, abs(UV.x + UV.y - 0.62)) * 0.05;
	ALBEDO = tint.rgb;
	ALPHA = tint.a + glint;
}
"""


static func _shader_mat(code: String, params: Dictionary) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = code
	sm.shader = sh
	for k in params:
		sm.set_shader_parameter(k, params[k])
	return sm


static func _quad(parent: Node3D, size: float, mat: Material, pos: Vector3, name := "") -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var mi := _p(parent, q, mat, pos)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if name != "":
		mi.name = name
	return mi


## 全息瞄具：金属框 + 透明玻璃 + 红色"圈点"准星。Sight 在准星中心
static func _holo(root: Node3D, m: Dictionary, c: Vector3) -> void:
	m = _om(m)
	_p(root, Props.rbox(Vector3(0.05, 0.016, 0.075)), m["black"], c + Vector3(0, -0.028, 0.0))
	for s in [-1.0, 1.0]:
		_p(root, Props.rbox(Vector3(0.006, 0.05, 0.05)), m["black"], c + Vector3(0.025 * s, -0.002, -0.005))
	_p(root, Props.rbox(Vector3(0.056, 0.007, 0.05)), m["black"], c + Vector3(0, 0.026, -0.005))
	_p(root, Props.rbox(Vector3(0.02, 0.012, 0.02)), m["iron"], c + Vector3(0.02, -0.018, 0.03))
	_quad(root, 0.046, _shader_mat(GLASS_SHADER, {}), c + Vector3(0, 0, -0.02))
	_quad(root, 0.03, _shader_mat(RETICLE_SHADER, {"color": Color(1.0, 0.12, 0.08), "kind": 1}), c + Vector3(0, 0, -0.022), "Reticle")
	_marker(root, "Sight", c)


## 两头开口的镜筒（不挡视线），里外两面都画
static func _open_tube(r_rear: float, r_front: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_rear
	c.bottom_radius = r_front
	c.height = h
	c.radial_segments = 24
	c.rings = 1
	c.cap_top = false
	c.cap_bottom = false
	return c


static func _dbl(mat: Material) -> Material:
	var d := mat.duplicate() as BaseMaterial3D
	d.cull_mode = BaseMaterial3D.CULL_DISABLED
	return d


## 红点瞄具：增高座（从 bot 高度垫到镜筒下面）+ 一截开口短镜筒 + 透明玻璃，玻璃上一颗红点。Sight 在镜筒后口
static func _reddot(root: Node3D, m: Dictionary, c: Vector3, bot := 0.037) -> void:
	m = _om(m)
	var top := c.y - 0.017
	_p(root, Props.rbox(Vector3(0.03, top - bot, 0.045)), m["black"], Vector3(c.x, (bot + top) * 0.5, c.z))
	_p(root, _open_tube(0.019, 0.02, 0.05), _dbl(m["black"]), c, Vector3(PI / 2, 0, 0))
	_p(root, U.torus(0.019, 0.023, 24, 6), m["gold"], c + Vector3(0, 0, -0.025), Vector3(PI / 2, 0, 0))
	_p(root, U.cyl(0.006, 0.006, 0.012, 10), m["black"], c + Vector3(0.024, 0, 0.005), Vector3(0, 0, PI / 2))
	_quad(root, 0.036, _shader_mat(GLASS_SHADER, {}), c + Vector3(0, 0, -0.02))
	_quad(root, 0.018, _shader_mat(RETICLE_SHADER, {"color": Color(1.0, 0.1, 0.06), "kind": 0}), c + Vector3(0, 0, -0.021), "Reticle")
	_marker(root, "Sight", c + Vector3(0, 0, 0.025))


## 狙击镜：主镜筒 + 粗物镜 + 目镜 + 调节旋钮，全部开口。
## 开镜到底时画面换成全屏瞄准镜（HUD 的 ScopeOverlay），手里的模型藏起来
static func _scope(root: Node3D, m: Dictionary, c: Vector3) -> void:
	m = _om(m)
	var tube := _dbl(m["black"])
	_p(root, _open_tube(0.021, 0.021, 0.2), tube, c, Vector3(PI / 2, 0, 0))
	_p(root, _open_tube(0.022, 0.031, 0.06), tube, c + Vector3(0, 0, -0.13), Vector3(PI / 2, 0, 0))
	_p(root, _open_tube(0.024, 0.021, 0.04), tube, c + Vector3(0, 0, 0.12), Vector3(PI / 2, 0, 0))
	_p(root, U.torus(0.029, 0.034, 32, 6), m["bronze"], c + Vector3(0, 0, -0.16), Vector3(PI / 2, 0, 0))
	_p(root, U.torus(0.022, 0.027, 32, 6), m["bronze"], c + Vector3(0, 0, 0.14), Vector3(PI / 2, 0, 0))
	_p(root, U.cyl(0.011, 0.011, 0.022, 12), m["black"], c + Vector3(0, 0.03, 0.0))
	_p(root, U.cyl(0.012, 0.012, 0.004, 12), m["bronze"], c + Vector3(0, 0.042, 0.0))
	_p(root, U.cyl(0.011, 0.011, 0.022, 12), m["black"], c + Vector3(0.03, 0, 0.0), Vector3(0, 0, PI / 2))
	_p(root, U.cyl(0.013, 0.013, 0.02, 12), m["bronze"], c + Vector3(0, 0, 0.1), Vector3(PI / 2, 0, 0))
	_quad(root, 0.058, _shader_mat(GLASS_SHADER, {}), c + Vector3(0, 0, -0.159))
	_quad(root, 0.044, U.mat(Color(0.03, 0.05, 0.08), 0.1), c + Vector3(0, 0, 0.138), "ScopeLens")
	_marker(root, "Sight", c + Vector3(0, 0, 0.14))


## 光学瞄准镜（流光翎，类似 ACOG）：镜筒、前后镜片、金边，镜片里是琥珀色的箭头准星
static func _acog(root: Node3D, m: Dictionary, c: Vector3) -> void:
	m = _om(m)
	_p(root, Props.rbox(Vector3(0.036, 0.022, 0.12)), m["black"], c + Vector3(0, -0.03, 0))
	_p(root, Props.rbox(Vector3(0.028, c.y - 0.06, 0.05)), m["black"], Vector3(c.x, (c.y + 0.02) * 0.5, c.z))
	_p(root, U.cyl(0.02, 0.02, 0.13, 20), m["black"], c + Vector3(0, 0, -0.005), Vector3(PI / 2, 0, 0))
	_p(root, U.cyl(0.026, 0.021, 0.04, 20), m["black"], c + Vector3(0, 0, -0.085), Vector3(PI / 2, 0, 0))
	_p(root, U.cyl(0.023, 0.02, 0.03, 20), m["black"], c + Vector3(0, 0, 0.07), Vector3(PI / 2, 0, 0))
	_p(root, U.torus(0.019, 0.025, 24, 6), m["gold"], c + Vector3(0, 0, 0.086), Vector3(PI / 2, 0, 0))
	_p(root, U.torus(0.022, 0.028, 24, 6), m["gold"], c + Vector3(0, 0, -0.105), Vector3(PI / 2, 0, 0))
	_p(root, Props.rbox(Vector3(0.012, 0.014, 0.02)), m["gold"], c + Vector3(0, 0.024, -0.02))
	_quad(root, 0.05, _shader_mat(GLASS_SHADER, {}), c + Vector3(0, 0, -0.106))
	_quad(root, 0.04, _shader_mat(GLASS_SHADER, {}), c + Vector3(0, 0, 0.087))
	_quad(root, 0.03, _shader_mat(RETICLE_SHADER, {"color": Color(1.0, 0.6, 0.1), "kind": 2}), c + Vector3(0, 0, 0.08), "Reticle")
	_marker(root, "Sight", c + Vector3(0, 0, 0.087))


## 每把暗器枪管下 / 侧面能挂东西的位置
const UNDER := {"xiujian": Vector3(0, -0.002, -0.12), "meihua": Vector3(0, -0.002, -0.12), "zhuge": Vector3(0, -0.06, -0.15), "kongque": Vector3(0, -0.055, -0.3),
	"baoyu": Vector3(0, -0.09, -0.06), "zhuihun": Vector3(0, -0.05, -0.12), "longxu": Vector3(0, -0.04, -0.2), "zimu": Vector3(0, -0.07, -0.3),
	"hansha": Vector3(0, -0.06, -0.22), "guanyin": Vector3(0, -0.045, -0.22)}
## 枪托接在哪（枪身最后面）
const REAR := {"baoyu": Vector3(0, -0.01, 0.08), "zhuge": Vector3(0, -0.02, 0.18), "kongque": Vector3(0, -0.02, 0.32), "zhuihun": Vector3(0, -0.02, 0.37),
	"longxu": Vector3(0, -0.02, 0.365), "zimu": Vector3(0, -0.02, 0.26), "hansha": Vector3(0, -0.02, 0.35), "guanyin": Vector3(0, -0.02, 0.3)}
## 挂件挂在哪（暗器朝里的一面，自己看得见）
# 量不出大小时的后备位置（一般用 _charm 里按暗器大小算的位置）
const CHARM_AT := {"xiujian": Vector3(-0.022, 0.0, 0.1), "meihua": Vector3(-0.024, 0.0, 0.1), "baoyu": Vector3(-0.052, -0.03, 0.05),
	"zhuge": Vector3(-0.03, -0.02, 0.12), "longxu": Vector3(-0.024, -0.02, 0.1), "kongque": Vector3(-0.026, -0.03, 0.12),
	"zimu": Vector3(-0.038, -0.03, 0.1), "hansha": Vector3(-0.038, -0.035, 0.14), "zhuihun": Vector3(-0.028, -0.03, 0.14), "guanyin": Vector3(-0.024, -0.025, 0.1)}


## 买来的配件：枪口（制退器、补偿器、消音器）、枪管下（握把、斜握把、激光）、弹匣、枪托
static func _attachments(root: Node3D, m: Dictionary, id: String, att: Dictionary) -> void:
	m = _om(m)
	var mz := root.get_node_or_null("Muzzle") as Node3D
	var laser := U.glow(Color(1.0, 0.1, 0.08), 6.0)
	var under: Vector3 = UNDER.get(id, Vector3(0, -0.05, -0.1))
	var small := id in Data.SIDEARMS
	if mz:
		match str(att.get("muzzle", "")):
			"brake":
				_brake(root, m, mz.position + Vector3(0, 0, 0.03), 0.016 if small else 0.02)
				mz.position.z -= 0.035
			"comp":
				var r := 0.016 if small else 0.02
				var cp := mz.position + Vector3(0, 0, -0.015)
				_p(root, U.cyl(r, r * 1.1, 0.045, 12), m["black"], cp, Vector3(PI / 2, 0, 0))
				for k in 3:
					_p(root, Props.rbox(Vector3(r * 1.2, 0.004, 0.006)), m["iron"], cp + Vector3(0, r * 0.95, -0.015 + k * 0.014))
				mz.position.z -= 0.04
			"silencer":
				var r2 := 0.017 if small else 0.022
				var sp := mz.position + Vector3(0, 0, -0.07)
				_p(root, U.cyl(r2, r2, 0.14, 16), m["black"], sp, Vector3(PI / 2, 0, 0))
				for zz in [-0.065, 0.065]:
					_p(root, U.cyl(r2 * 1.06, r2 * 1.06, 0.01, 16), m["iron"], sp + Vector3(0, 0, zz), Vector3(PI / 2, 0, 0))
				mz.position.z -= 0.14
	match str(att.get("under", "")):
		"grip":
			_p(root, Props.rbox(Vector3(0.024, 0.07, 0.028)), m["black"], under + Vector3(0, -0.02, 0))
			_p(root, Props.rbox(Vector3(0.028, 0.008, 0.032)), m["iron"], under + Vector3(0, 0.016, 0))
		"angled":
			_p(root, Props.rbox(Vector3(0.024, 0.05, 0.05)), m["black"], under + Vector3(0, -0.012, 0.01), Vector3(0.7, 0, 0))
			_p(root, Props.rbox(Vector3(0.028, 0.008, 0.06)), m["iron"], under + Vector3(0, 0.016, 0))
		"laser":
			var side := Vector3(0.03, 0.0, 0.0) if not small else Vector3.ZERO
			_p(root, Props.rbox(Vector3(0.022, 0.018, 0.05)), m["black"], under + side + Vector3(0, 0.012, 0))
			_p(root, U.cyl(0.003, 0.003, 0.004, 8), laser, under + side + Vector3(0, 0.012, -0.027), Vector3(PI / 2, 0, 0))
	# 弹匣：在原来的弹匣上加东西（弹匣节点换弹时会拆下来，加的东西跟着走）
	var mag := root.get_node_or_null("Mag") as Node3D
	if mag:
		match str(att.get("mag", "")):
			"extmag":
				_p(mag, Props.rbox(Vector3(0.03, 0.05, 0.045)), m["black"], Vector3(0, -0.055, 0.0))
				_p(mag, Props.rbox(Vector3(0.032, 0.006, 0.048)), m["iron"], Vector3(0, -0.08, 0.0))
			"fastmag":
				_p(mag, U.torus(0.008, 0.012, 12, 4), U.mat(Color(0.8, 0.12, 0.08), 0.5), Vector3(0, -0.05, 0.0), Vector3(PI / 2, 0, 0))
				_p(mag, Props.rbox(Vector3(0.034, 0.008, 0.03)), U.mat(Color(0.8, 0.12, 0.08), 0.5), Vector3(0, -0.035, 0.0))
			"soulmag":
				_p(mag, Props.rbox(Vector3(0.034, 0.012, 0.05)), m["jade"], Vector3(0, -0.03, 0.0))
				_p(mag, U.sphere(0.01, 8, 6), m["jade"], Vector3(-0.02, -0.01, 0.0))
	# 枪托：接在最后面往后伸
	var rear: Vector3 = REAR.get(id, Vector3(0, -0.02, 0.25))
	match str(att.get("stock", "")):
		"lstock":
			for s in [-1.0, 1.0]:
				_p(root, U.cyl(0.004, 0.004, 0.13, 6), m["iron"], rear + Vector3(0.012 * s, 0.0, 0.065), Vector3(PI / 2, 0, 0))
			_p(root, Props.rbox(Vector3(0.036, 0.08, 0.012)), m["black"], rear + Vector3(0, -0.01, 0.13))
		"hstock":
			_p(root, Props.rbox(Vector3(0.042, 0.075, 0.13)), m["black"], rear + Vector3(0, -0.01, 0.065))
			_p(root, Props.rbox(Vector3(0.03, 0.02, 0.08)), m["iron"], rear + Vector3(0, 0.035, 0.06))
			_p(root, Props.rbox(Vector3(0.046, 0.085, 0.016)), U.mat(Color(0.12, 0.1, 0.09), 0.9), rear + Vector3(0, -0.01, 0.135))


## 挂件：一根短绳吊着一个小东西，节点叫 Charm（ViewModel 让它像摆一样晃）
static func _charm(root: Node3D, id: String, ch: String) -> void:
	# 用户：挂件检视的时候都看不到（以前挂在握把后面，第一人称正好在画面下面外头）。
	# 现在挂在暗器左侧、从枪口往后三分之一多一点的地方（第一人称看得见的那一面），大一半
	var at: Vector3 = CHARM_AT.get(id, Vector3(-0.03, -0.02, 0.1))
	var bx := _calc_box(root)
	if bx.size.x > 0.08:
		var side := 0.026 if id in Data.SIDEARMS else 0.034
		at = Vector3(-side, bx.position.y + bx.size.y * 0.6, bx.position.x + bx.size.x * 0.36)
	var pivot := _marker(root, "Charm", at)
	# 摆动会改 pivot 的 basis（会把缩放冲掉），缩放放在下面一层
	var hold := Node3D.new()
	hold.scale = Vector3.ONE * 1.5
	pivot.add_child(hold)
	var cord := U.mat(Color(0.75, 0.1, 0.08), 0.7)
	_p(hold, U.cyl(0.0012, 0.0012, 0.035, 4), cord, Vector3(0, -0.0175, 0))
	var p := Node3D.new()
	p.position = Vector3(0, -0.04, 0)
	hold.add_child(p)
	match ch:
		"tassel":
			_p(p, U.sphere(0.006, 8, 6), cord)
			for k in 7:
				var a := k * TAU / 7.0
				_p(p, U.cyl(0.0011, 0.0006, 0.045, 3), cord, Vector3(cos(a) * 0.003, -0.025, sin(a) * 0.003), Vector3(cos(a) * 0.08, 0, sin(a) * 0.08))
		"jade":
			var jm := U.mat(Color(0.3, 0.75, 0.5), 0.12, 0.25)
			_p(p, U.torus(0.004, 0.012, 20, 8), jm, Vector3(0, -0.006, 0), Vector3(0, 0, PI / 2))
			for k in 5:
				_p(p, U.cyl(0.001, 0.0006, 0.03, 3), cord, Vector3(0, -0.035, (k - 2) * 0.0015))
		"bell":
			var gm := U.mat(Color(1.0, 0.78, 0.3), 0.18, 0.0, 1.0)
			_p(p, U.torus(0.0015, 0.004, 10, 4), gm, Vector3(0, 0.004, 0), Vector3(0, 0, PI / 2))
			_p(p, U.sphere(0.011, 14, 10), gm, Vector3(0, -0.008, 0))
			_p(p, Props.rbox(Vector3(0.0225, 0.0015, 0.004)), U.mat(Color(0.1, 0.07, 0.03), 0.8), Vector3(0, -0.012, 0))
		"rabbit":
			var wm := U.mat(Color(0.97, 0.95, 0.93), 0.9)
			var pm := U.mat(Color(1.0, 0.55, 0.65), 0.7)
			_p(p, U.sphere(0.009, 12, 8), wm, Vector3(0, -0.012, 0), Vector3.ZERO, Vector3(1, 1.1, 1))
			_p(p, U.sphere(0.0065, 12, 8), wm, Vector3(0, 0.002, 0))
			for s in [-1.0, 1.0]:
				_p(p, U.capsule(0.0022, 0.014), wm, Vector3(0, 0.012, 0.003 * s), Vector3(0.25 * s, 0, 0))
				_p(p, U.sphere(0.0012, 6, 4), pm, Vector3(-0.0058, 0.003, 0.0025 * s))
		"ring":
			var age := 0
			for r in Profile.rings:
				age = maxi(age, int(r["age"]))
			var col: Color = Data.AGES[clampi(age, 0, Data.AGES.size() - 1)]["glow"]
			_p(p, U.torus(0.009, 0.013, 24, 6), U.glow(col, 2.2), Vector3(0, -0.008, 0), Vector3(0, 0, PI / 2))
		"lotus":
			var lm := U.glow(Color(1.0, 0.55, 0.75), 1.4)
			for k in 6:
				var a := k * TAU / 6.0
				_p(p, U.sphere(0.006, 8, 6), lm, Vector3(cos(a) * 0.006, -0.004, sin(a) * 0.006), Vector3(0.5, a, 0), Vector3(0.6, 0.35, 1.3))
			_p(p, U.sphere(0.004, 8, 6), U.glow(Color(1.0, 0.85, 0.35), 2.5), Vector3(0, -0.002, 0))


static func _brake(root: Node3D, m: Dictionary, pos: Vector3, r: float) -> void:
	_p(root, U.cyl(r, r, 0.06, 12), m["black"], pos, Vector3(PI / 2, 0, 0))
	for k in 3:
		for s in [-1.0, 1.0]:
			_p(root, Props.rbox(Vector3(0.004, r * 1.2, 0.008)), m["iron"], pos + Vector3(r * s, 0, -0.02 + k * 0.018))


## 别人手里的小号模型（第三人称）
static func build_small(id: String, skin := "default") -> Node3D:
	var root := Node3D.new()
	# 别人自己画的皮肤传不过来（图在他电脑上），看到的是原色
	var m := _mats("default" if skin == "paint" else skin, "default", "")
	match id:
		"meihua":
			_p(root, U.cyl(0.024, 0.028, 0.28, 10), m["lacquer"], Vector3.ZERO, Vector3(PI / 2, 0, 0))
			_p(root, U.cyl(0.03, 0.03, 0.02, 10), m["gold"], Vector3(0, 0, -0.12), Vector3(PI / 2, 0, 0))
		"longxu":
			_p(root, Props.rbox(Vector3(0.05, 0.06, 0.62)), m["lacquer"])
			_p(root, U.cyl(0.012, 0.012, 0.36, 8), m["iron"], Vector3(0, 0.01, -0.45), Vector3(PI / 2, 0, 0))
			_p(root, U.sphere(0.026, 8, 6), m["gold"], Vector3(0, 0.01, -0.3))
		"zimu":
			_p(root, Props.rbox(Vector3(0.08, 0.09, 0.26)), m["lacquer"], Vector3(0, 0, 0.08))
			_p(root, U.sphere(0.075, 10, 8), m["wood"], Vector3(0, 0.01, -0.1), Vector3.ZERO, Vector3(1, 1, 1.3))
			_p(root, U.cyl(0.035, 0.035, 0.16, 10), m["iron"], Vector3(0, 0.01, -0.25), Vector3(PI / 2, 0, 0))
		"hansha":
			_p(root, Props.rbox(Vector3(0.08, 0.1, 0.4)), m["lacquer"], Vector3(0, 0, 0.05))
			_p(root, U.cyl(0.035, 0.035, 0.4, 10), m["iron"], Vector3(0, 0.01, -0.35), Vector3(PI / 2, 0, 0))
			_p(root, U.cyl(0.08, 0.08, 0.06, 12), m["iron"], Vector3(-0.08, -0.03, 0.02), Vector3(0, 0, PI / 2))
		"guanyin":
			_p(root, Props.rbox(Vector3(0.05, 0.065, 0.55)), m["lacquer"])
			_p(root, Props.rbox(Vector3(0.45, 0.02, 0.03)), m["bronze"], Vector3(0, 0, -0.24))
			_p(root, U.sphere(0.025, 10, 8), U.glow(Color(0.75, 0.92, 1.0), 2.0), Vector3(0, 0.02, -0.34))
		"xiujian":
			_p(root, U.cyl(0.02, 0.024, 0.3, 8), m["bronze"], Vector3.ZERO, Vector3(PI / 2, 0, 0))
		"zhuge":
			_p(root, Props.rbox(Vector3(0.06, 0.07, 0.42)), m["wood"])
			_p(root, Props.rbox(Vector3(0.05, 0.08, 0.22)), m["black"], Vector3(0, 0.07, -0.03))
			_p(root, Props.rbox(Vector3(0.5, 0.02, 0.03)), m["wood"], Vector3(0, 0, -0.2))
		"kongque":
			_p(root, Props.rbox(Vector3(0.05, 0.07, 0.7)), m["lacquer"])
			_p(root, Props.rbox(Vector3(0.12, 0.06, 0.03)), m["feather"], Vector3(0, 0.07, -0.15))
		"baoyu":
			_p(root, Props.rbox(Vector3(0.12, 0.1, 0.26)), m["lacquer"])
		"zhuihun":
			_p(root, Props.rbox(Vector3(0.06, 0.08, 0.8)), m["wood"])
			_p(root, U.cyl(0.025, 0.025, 0.24, 8), m["bronze"], Vector3(0, 0.08, 0), Vector3(PI / 2, 0, 0))
			_p(root, Props.rbox(Vector3(0.7, 0.025, 0.03)), m["wood"], Vector3(0, 0, -0.36))
	return root
