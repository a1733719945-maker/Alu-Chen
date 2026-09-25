class_name WeaponModels
extends RefCounted
## 第一人称暗器模型。每个模型里有几个特殊节点：
##   Muzzle    箭射出去的位置
##   Sight     开镜时眼睛对准的点（照门），开镜会把它移到屏幕正中
##   Mag       换弹时拆下来的部分
##   ArmL/ArmR 弩臂，开火时往前弹
##   Lever     机括（诸葛神弩的拉杆、追魂弩的栓），开火后动一下
##   LeftHand  托着暗器的左手（甩引魂索时藏起来）
## 朝向：-Z 向前，原点在右手握把。


static func _mats() -> Dictionary:
	return {
		"skin": U.mat(Color(0.84, 0.64, 0.52), 0.6),
		"sleeve": U.mat(Color(0.1, 0.11, 0.17), 0.85),
		"cuff": U.mat(Color(0.85, 0.66, 0.3), 0.35, 0.0, 0.7),
		"inner": U.mat(Color(0.86, 0.84, 0.78), 0.8),
		"wood": U.mat(Color(0.36, 0.2, 0.12), 0.6),
		"lacquer": U.mat(Color(0.32, 0.05, 0.05), 0.3),
		"black": U.mat(Color(0.07, 0.06, 0.06), 0.35),
		"bronze": U.mat(Color(0.55, 0.38, 0.2), 0.35, 0.0, 0.8),
		"gold": U.mat(Color(0.9, 0.7, 0.3), 0.3, 0.0, 0.9),
		"iron": U.mat(Color(0.28, 0.29, 0.31), 0.4, 0.0, 0.85),
		"string": U.mat(Color(0.9, 0.88, 0.8), 0.8),
		"jade": U.glow(Color(0.35, 0.95, 0.8), 1.6),
		"feather": U.glow(Color(0.2, 0.75, 0.9), 1.2),
		"lens": U.glow(Color(0.45, 0.75, 1.0), 2.5),
	}


static func _marker(parent: Node3D, name: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = name
	n.position = pos
	parent.add_child(n)
	return n


static func _p(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := U.part(parent, mesh, mat, pos, rot, scl, false)
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return mi


## 一只握拳的手：手掌 + 四根弯着的手指 + 大拇指。side = 1 右手，-1 左手
## 手的本地坐标：-Z 朝前，手指从右往左（右手）包住握把
static func fist(parent: Node3D, m: Dictionary, pos: Vector3, rot: Vector3, side := 1.0) -> Node3D:
	var h := Node3D.new()
	h.position = pos
	h.rotation = rot
	parent.add_child(h)
	# 手掌（稍扁的圆角块）
	_p(h, U.sphere(0.03, 12, 8), m["skin"], Vector3(0.012 * side, 0, 0.012), Vector3.ZERO, Vector3(0.95, 1.35, 1.35))
	# 四根手指：横着包在握把前面，上粗下细
	for k in 4:
		var y := 0.024 - k * 0.0165
		var r := 0.0105 - k * 0.0008
		_p(h, U.capsule(r, 0.05), m["skin"], Vector3(-0.004 * side, y, -0.024), Vector3(0, 0, PI / 2), Vector3.ONE)
		# 指关节
		_p(h, U.sphere(r * 1.08, 8, 6), m["skin"], Vector3(0.02 * side, y, -0.018))
		# 指尖弯回来贴在另一边
		_p(h, U.sphere(r * 0.95, 8, 6), m["skin"], Vector3(-0.026 * side, y, -0.008))
	# 大拇指：从手掌左上方伸向前
	_p(h, U.capsule(0.011, 0.05), m["skin"], Vector3(-0.018 * side, 0.034, -0.012), Vector3(PI / 2 - 0.35, 0, 0.5 * side))
	return h


## 袖子：深色唐门长袍，手腕一圈金边，里面露一点白色里衣
## elbow：从手腕指向手肘的方向（前臂斜着往下、往外、往后伸出画面，像 CS 里的手臂）
static func sleeve(parent: Node3D, m: Dictionary, wrist: Vector3, elbow: Vector3) -> Node3D:
	var s := Node3D.new()
	s.position = wrist
	parent.add_child(s)
	# 让本地 +Z 指向手肘
	s.basis = Basis.looking_at(-elbow.normalized(), Vector3.UP if absf(elbow.normalized().y) < 0.95 else Vector3.FORWARD)
	_p(s, U.cyl(0.024, 0.026, 0.03, 12), m["skin"], Vector3(0, 0, -0.005), Vector3(PI / 2, 0, 0))
	_p(s, U.cyl(0.031, 0.031, 0.02, 14), m["inner"], Vector3(0, 0, 0.016), Vector3(PI / 2, 0, 0))
	_p(s, U.cyl(0.04, 0.038, 0.026, 16), m["cuff"], Vector3(0, 0, 0.036), Vector3(PI / 2, 0, 0))
	# 袖子往手肘方向越来越宽（Y 轴转到 +Z 后，cyl 的 top 在 -Z 端）
	_p(s, U.cyl(0.037, 0.05, 0.42, 16), m["sleeve"], Vector3(0, 0, 0.26), Vector3(-PI / 2, 0, 0))
	return s


static func _arm_right(root: Node3D, m: Dictionary, grip: Vector3) -> void:
	# 右手握把 + 袖子往右后方延伸出画面
	fist(root, m, grip, Vector3(0.15, 0, 0), 1.0)
	sleeve(root, m, grip + Vector3(0.014, -0.022, 0.045), Vector3(0.32, -0.55, 0.75))


static func _arm_left(root: Node3D, m: Dictionary, pos: Vector3) -> void:
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
		_p(arm, U.box(Vector3(span, thick, thick * 1.6)), m["wood"], Vector3(span * 0.5 * side, 0, 0))
		_p(arm, U.box(Vector3(span * 0.35, thick * 1.2, thick * 1.8)), m["gold"], Vector3(span * 0.18 * side, 0, 0))
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


static func build(id: String) -> Node3D:
	var root := Node3D.new()
	root.name = id
	var m := _mats()
	match id:
		"xiujian":
			_arm_right(root, m, Vector3(0, -0.035, -0.06))
			_p(root, U.cyl(0.014, 0.017, 0.26, 12), m["bronze"], Vector3(0.0, 0.025, -0.02), Vector3(PI / 2, 0, 0))
			_p(root, U.cyl(0.0, 0.009, 0.035, 6), m["iron"], Vector3(0.0, 0.025, -0.165), Vector3(-PI / 2, 0, 0))
			_p(root, U.cyl(0.019, 0.019, 0.025, 12), m["gold"], Vector3(0.0, 0.025, -0.14), Vector3(PI / 2, 0, 0))
			_p(root, U.cyl(0.019, 0.019, 0.02, 12), m["gold"], Vector3(0.0, 0.025, 0.09), Vector3(PI / 2, 0, 0))
			for zz in [0.0, 0.07]:
				_p(root, U.box(Vector3(0.1, 0.012, 0.022)), m["black"], Vector3(0.0, -0.005, zz))
			_p(root, U.box(Vector3(0.006, 0.012, 0.006)), m["gold"], Vector3(0.0, 0.047, -0.135))
			var notch := _p(root, U.box(Vector3(0.02, 0.008, 0.006)), m["gold"], Vector3(0.0, 0.045, 0.085))
			notch.name = "Notch"
			var mag := _marker(root, "Mag", Vector3(0.0, 0.025, 0.12))
			_p(mag, U.cyl(0.012, 0.012, 0.05, 8), m["iron"], Vector3.ZERO, Vector3(PI / 2, 0, 0))
			_marker(root, "Muzzle", Vector3(0.0, 0.025, -0.19))
			_marker(root, "Sight", Vector3(0.0, 0.047, 0.09))
		"zhuge":
			_arm_right(root, m, Vector3(0, -0.07, 0.1))
			_p(root, U.box(Vector3(0.05, 0.055, 0.36)), m["wood"], Vector3(0, 0, 0.0))
			_p(root, U.box(Vector3(0.036, 0.09, 0.05)), m["wood"], Vector3(0, -0.06, 0.1), Vector3(-0.35, 0, 0))
			_p(root, U.box(Vector3(0.056, 0.012, 0.37)), m["gold"], Vector3(0, 0.028, 0.0))
			var mag := _marker(root, "Mag", Vector3(0, 0.065, -0.03))
			_p(mag, U.box(Vector3(0.046, 0.07, 0.2)), m["black"])
			_p(mag, U.box(Vector3(0.05, 0.008, 0.205)), m["gold"], Vector3(0, 0.036, 0))
			for k in 4:
				_p(mag, U.box(Vector3(0.004, 0.004, 0.16)), m["jade"], Vector3(-0.012 + k * 0.008, 0.041, 0))
			var lever := _marker(root, "Lever", Vector3(0, 0.1, -0.12))
			_p(lever, U.box(Vector3(0.012, 0.012, 0.24)), m["bronze"], Vector3(0, 0.0, 0.12), Vector3(0.12, 0, 0))
			_p(lever, U.cyl(0.012, 0.012, 0.06, 8), m["bronze"], Vector3(0, -0.01, 0.235), Vector3(0, 0, PI / 2))
			_bow(root, m, Vector3(0, 0.005, -0.17), 0.21, 0.016, 0.03)
			_p(root, U.box(Vector3(0.006, 0.02, 0.006)), m["gold"], Vector3(0, 0.11, -0.125))
			_p(root, U.box(Vector3(0.024, 0.012, 0.006)), m["gold"], Vector3(0, 0.106, 0.07))
			_arm_left(root, m, Vector3(-0.005, -0.045, -0.11))
			_marker(root, "Muzzle", Vector3(0, 0.02, -0.26))
			_holo(root, m, Vector3(0, 0.128, 0.02))
		"kongque":
			_arm_right(root, m, Vector3(0, -0.075, 0.14))
			_p(root, U.box(Vector3(0.046, 0.06, 0.56)), m["lacquer"], Vector3(0, 0, 0.02))
			_p(root, U.box(Vector3(0.05, 0.1, 0.12)), m["lacquer"], Vector3(0, -0.02, 0.26))
			_p(root, U.box(Vector3(0.036, 0.09, 0.05)), m["wood"], Vector3(0, -0.07, 0.14), Vector3(-0.3, 0, 0))
			_p(root, U.box(Vector3(0.05, 0.01, 0.57)), m["gold"], Vector3(0, 0.032, 0.02))
			_p(root, U.cyl(0.02, 0.022, 0.24, 12), m["bronze"], Vector3(0, 0.01, -0.34), Vector3(PI / 2, 0, 0))
			for k in 3:
				_p(root, U.cyl(0.024, 0.024, 0.012, 12), m["gold"], Vector3(0, 0.01, -0.26 - k * 0.07), Vector3(PI / 2, 0, 0))
			# 孔雀翎：一排发光的翎羽
			for k in 5:
				var a := (k - 2) * 0.28
				var f := _p(root, U.box(Vector3(0.006, 0.07, 0.03)), m["feather"], Vector3(sin(a) * 0.03, 0.07, -0.12 + absf(k - 2) * 0.01), Vector3(0, 0, a))
				f.name = "Feather"
				_p(root, U.sphere(0.008, 6, 4), m["jade"], Vector3(sin(a) * 0.058, 0.1, -0.12))
			var mag := _marker(root, "Mag", Vector3(0, -0.07, -0.02))
			_p(mag, U.box(Vector3(0.03, 0.1, 0.06)), m["jade"], Vector3(0, -0.02, 0), Vector3(0.15, 0, 0))
			_bow(root, m, Vector3(0, 0.0, -0.2), 0.14, 0.014, 0.1)
			var ring := _p(root, U.torus(0.008, 0.013, 16, 6), m["gold"], Vector3(0, 0.058, 0.17), Vector3(PI / 2, 0, 0))
			ring.name = "Aperture"
			_p(root, U.box(Vector3(0.004, 0.028, 0.004)), m["gold"], Vector3(0, 0.046, -0.44))
			_arm_left(root, m, Vector3(-0.005, -0.04, -0.2))
			_marker(root, "Muzzle", Vector3(0, 0.01, -0.51))
			_acog(root, m, Vector3(0, 0.125, 0.03))
		"baoyu":
			_arm_right(root, m, Vector3(0, -0.06, 0.07))
			_p(root, U.box(Vector3(0.1, 0.085, 0.22)), m["lacquer"], Vector3(0, 0, -0.03))
			for yy in [0.044, -0.044]:
				_p(root, U.box(Vector3(0.106, 0.008, 0.226)), m["gold"], Vector3(0, yy, -0.03))
			_p(root, U.box(Vector3(0.09, 0.075, 0.006)), m["black"], Vector3(0, 0, -0.142))
			for ix in 4:
				for iy in 3:
					_p(root, U.sphere(0.0055, 5, 3), m["gold"], Vector3(-0.03 + ix * 0.02, -0.02 + iy * 0.02, -0.146))
			var pump := _marker(root, "Lever", Vector3(0, -0.058, -0.06))
			_p(pump, U.box(Vector3(0.07, 0.03, 0.1)), m["wood"])
			_p(root, U.sphere(0.014, 8, 6), m["jade"], Vector3(0, 0.05, 0.03))
			_p(root, U.box(Vector3(0.02, 0.006, 0.12)), m["gold"], Vector3(0, 0.05, -0.05))
			var mag := _marker(root, "Mag", Vector3(0.0, 0.02, 0.09))
			_p(mag, U.box(Vector3(0.05, 0.03, 0.03)), m["bronze"])
			_arm_left(root, m, Vector3(-0.06, -0.06, -0.07))
			_marker(root, "Muzzle", Vector3(0, 0, -0.16))
			_marker(root, "Sight", Vector3(0, 0.056, 0.05))
		"zhuihun":
			_arm_right(root, m, Vector3(0, -0.08, 0.16))
			_p(root, U.box(Vector3(0.05, 0.065, 0.66)), m["wood"], Vector3(0, 0, 0.0))
			_p(root, U.box(Vector3(0.055, 0.11, 0.14)), m["wood"], Vector3(0, -0.025, 0.3))
			_p(root, U.box(Vector3(0.056, 0.01, 0.67)), m["iron"], Vector3(0, 0.035, 0.0))
			_p(root, U.box(Vector3(0.036, 0.09, 0.05)), m["black"], Vector3(0, -0.07, 0.16), Vector3(-0.3, 0, 0))
			# 铜瞄镜
			_p(root, U.cyl(0.02, 0.02, 0.2, 16), m["bronze"], Vector3(0, 0.08, 0.02), Vector3(PI / 2, 0, 0))
			_p(root, U.cyl(0.026, 0.02, 0.04, 16), m["bronze"], Vector3(0, 0.08, -0.1), Vector3(PI / 2, 0, 0))
			_p(root, U.cyl(0.023, 0.02, 0.03, 16), m["bronze"], Vector3(0, 0.08, 0.13), Vector3(PI / 2, 0, 0))
			_p(root, U.cyl(0.022, 0.022, 0.004, 16), m["lens"], Vector3(0, 0.08, -0.121), Vector3(PI / 2, 0, 0))
			for zz in [-0.04, 0.07]:
				_p(root, U.box(Vector3(0.012, 0.04, 0.02)), m["iron"], Vector3(0, 0.055, zz))
			var lever := _marker(root, "Lever", Vector3(0.035, 0.02, 0.1))
			_p(lever, U.cyl(0.006, 0.006, 0.06, 6), m["iron"], Vector3(0.03, 0, 0), Vector3(0, 0, PI / 2))
			_p(lever, U.sphere(0.013, 8, 6), m["bronze"], Vector3(0.062, 0, 0))
			var mag := _marker(root, "Mag", Vector3(0, -0.06, -0.05))
			_p(mag, U.box(Vector3(0.03, 0.06, 0.08)), m["iron"])
			_bow(root, m, Vector3(0, 0.0, -0.3), 0.3, 0.02, 0.12)
			_arm_left(root, m, Vector3(-0.005, -0.045, -0.2))
			_marker(root, "Muzzle", Vector3(0, 0.02, -0.34))
			_marker(root, "Sight", Vector3(0, 0.08, 0.14))
	_attachments(root, m, id)
	return root


# ------------------------------------------------------------------ 配件：瞄具、枪口、激光、手电、弹壳

const RETICLE_SHADER := """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.12, 0.08, 1.0);
uniform int kind = 0;
void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = smoothstep(0.1, 0.035, r) * 1.6 + smoothstep(0.4, 0.0, r) * 0.18;
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
uniform vec4 tint : source_color = vec4(0.45, 0.75, 0.9, 0.12);
void fragment() {
	float edge = smoothstep(0.35, 0.5, length(UV - 0.5));
	ALBEDO = tint.rgb;
	ALPHA = tint.a + edge * 0.25;
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


## 全息瞄具（诸葛神弩）：金属框 + 蓝色镀膜玻璃 + 红色"圈点"准星。Sight 在准星中心
static func _holo(root: Node3D, m: Dictionary, c: Vector3) -> void:
	_p(root, U.box(Vector3(0.05, 0.016, 0.075)), m["black"], c + Vector3(0, -0.028, 0.0))
	for s in [-1.0, 1.0]:
		_p(root, U.box(Vector3(0.006, 0.05, 0.05)), m["black"], c + Vector3(0.025 * s, -0.002, -0.005))
	_p(root, U.box(Vector3(0.056, 0.007, 0.05)), m["black"], c + Vector3(0, 0.026, -0.005))
	_p(root, U.box(Vector3(0.02, 0.012, 0.02)), m["iron"], c + Vector3(0.02, -0.018, 0.03))
	_quad(root, 0.046, _shader_mat(GLASS_SHADER, {"tint": Color(0.4, 0.7, 0.85, 0.1)}), c + Vector3(0, 0, -0.02))
	_quad(root, 0.03, _shader_mat(RETICLE_SHADER, {"color": Color(1.0, 0.12, 0.08), "kind": 1}), c + Vector3(0, 0, -0.022), "Reticle")
	_marker(root, "Sight", c)


## 光学瞄准镜（孔雀翎，类似 ACOG）：镜筒、前后镜片、金边，镜片里是琥珀色的箭头准星
static func _acog(root: Node3D, m: Dictionary, c: Vector3) -> void:
	_p(root, U.box(Vector3(0.036, 0.022, 0.12)), m["black"], c + Vector3(0, -0.03, 0))
	_p(root, U.box(Vector3(0.028, c.y - 0.06, 0.05)), m["black"], Vector3(c.x, (c.y + 0.02) * 0.5, c.z))
	_p(root, U.cyl(0.02, 0.02, 0.13, 20), m["black"], c + Vector3(0, 0, -0.005), Vector3(PI / 2, 0, 0))
	_p(root, U.cyl(0.026, 0.021, 0.04, 20), m["black"], c + Vector3(0, 0, -0.085), Vector3(PI / 2, 0, 0))
	_p(root, U.cyl(0.023, 0.02, 0.03, 20), m["black"], c + Vector3(0, 0, 0.07), Vector3(PI / 2, 0, 0))
	_p(root, U.torus(0.019, 0.025, 24, 6), m["gold"], c + Vector3(0, 0, 0.086), Vector3(PI / 2, 0, 0))
	_p(root, U.torus(0.022, 0.028, 24, 6), m["gold"], c + Vector3(0, 0, -0.105), Vector3(PI / 2, 0, 0))
	_p(root, U.box(Vector3(0.012, 0.014, 0.02)), m["gold"], c + Vector3(0, 0.024, -0.02))
	_quad(root, 0.05, _shader_mat(GLASS_SHADER, {"tint": Color(0.6, 0.45, 0.2, 0.08)}), c + Vector3(0, 0, -0.106))
	_quad(root, 0.04, _shader_mat(GLASS_SHADER, {"tint": Color(0.3, 0.5, 0.7, 0.06)}), c + Vector3(0, 0, 0.087))
	_quad(root, 0.03, _shader_mat(RETICLE_SHADER, {"color": Color(1.0, 0.6, 0.1), "kind": 2}), c + Vector3(0, 0, 0.08), "Reticle")
	_marker(root, "Sight", c + Vector3(0, 0, 0.087))


## 其余配件：枪口制退器、夜光照门、激光、手电、抛壳口
static func _attachments(root: Node3D, m: Dictionary, id: String) -> void:
	var mz := root.get_node_or_null("Muzzle") as Node3D
	var tritium := U.glow(Color(0.4, 1.0, 0.5), 3.0)
	var laser := U.glow(Color(1.0, 0.1, 0.08), 6.0)
	match id:
		"xiujian":
			# 夜光三点照门 + 枪管下激光 + 补偿器
			_p(root, U.sphere(0.0028, 6, 4), tritium, Vector3(0.0, 0.054, -0.135))
			for s in [-1.0, 1.0]:
				_p(root, U.sphere(0.0028, 6, 4), tritium, Vector3(0.007 * s, 0.05, 0.085))
			_p(root, U.box(Vector3(0.022, 0.018, 0.05)), m["black"], Vector3(0, 0.0, -0.13))
			_p(root, U.cyl(0.003, 0.003, 0.004, 8), laser, Vector3(0.0, 0.0, -0.157), Vector3(PI / 2, 0, 0))
			_p(root, U.cyl(0.017, 0.017, 0.03, 10), m["black"], Vector3(0.0, 0.025, -0.175), Vector3(PI / 2, 0, 0))
			for k in 2:
				_p(root, U.box(Vector3(0.036, 0.004, 0.005)), m["gold"], Vector3(0.0, 0.03, -0.168 - k * 0.012))
			_marker(root, "Eject", Vector3(0.015, 0.035, 0.02))
		"zhuge":
			# 枪口制退器 + 竖握把 + 皮卡汀尼导轨
			if mz:
				_brake(root, m, mz.position + Vector3(0, 0, 0.03), 0.018)
			_p(root, U.box(Vector3(0.024, 0.06, 0.026)), m["black"], Vector3(0, -0.06, -0.15))
			for k in 8:
				_p(root, U.box(Vector3(0.05, 0.005, 0.008)), m["iron"], Vector3(0, 0.1, -0.06 + k * 0.016))
			_marker(root, "Eject", Vector3(0.03, 0.04, 0.0))
		"kongque":
			if mz:
				_brake(root, m, mz.position + Vector3(0, 0, 0.035), 0.02)
			# 枪管下战术手电
			_p(root, U.cyl(0.013, 0.013, 0.07, 12), m["black"], Vector3(0.028, -0.01, -0.3), Vector3(PI / 2, 0, 0))
			_p(root, U.cyl(0.011, 0.011, 0.002, 12), U.glow(Color(1.0, 0.97, 0.85), 3.0), Vector3(0.028, -0.01, -0.336), Vector3(PI / 2, 0, 0))
			_marker(root, "Eject", Vector3(0.03, 0.03, 0.05))
		"baoyu":
			# 鬼环照门 + 夜光准星 + 侧挂弹壳
			_p(root, U.torus(0.007, 0.011, 16, 6), m["iron"], Vector3(0, 0.062, 0.04), Vector3(PI / 2, 0, 0))
			_p(root, U.sphere(0.004, 6, 4), tritium, Vector3(0, 0.058, -0.13))
			for k in 4:
				_p(root, U.cyl(0.008, 0.008, 0.03, 8), U.mat(Color(0.75, 0.12, 0.1), 0.5), Vector3(-0.058, 0.0, -0.08 + k * 0.022), Vector3(0, 0, PI / 2))
				_p(root, U.cyl(0.0085, 0.0085, 0.008, 8), m["gold"], Vector3(-0.07, 0.0, -0.08 + k * 0.022), Vector3(0, 0, PI / 2))
			_marker(root, "Eject", Vector3(0.05, 0.02, 0.0))
		"zhuihun":
			if mz:
				_brake(root, m, mz.position + Vector3(0, 0, 0.04), 0.024)
			# 两脚架（收起）
			for s in [-1.0, 1.0]:
				_p(root, U.cyl(0.005, 0.005, 0.16, 6), m["black"], Vector3(0.012 * s, -0.04, -0.2), Vector3(PI / 2, 0, 0))
			_marker(root, "Eject", Vector3(0.035, 0.03, 0.08))


static func _brake(root: Node3D, m: Dictionary, pos: Vector3, r: float) -> void:
	_p(root, U.cyl(r, r, 0.06, 12), m["black"], pos, Vector3(PI / 2, 0, 0))
	for k in 3:
		for s in [-1.0, 1.0]:
			_p(root, U.box(Vector3(0.004, r * 1.2, 0.008)), m["iron"], pos + Vector3(r * s, 0, -0.02 + k * 0.018))


## 别人手里的小号模型（第三人称）
static func build_small(id: String) -> Node3D:
	var root := Node3D.new()
	var m := _mats()
	match id:
		"xiujian":
			_p(root, U.cyl(0.02, 0.024, 0.3, 8), m["bronze"], Vector3.ZERO, Vector3(PI / 2, 0, 0))
		"zhuge":
			_p(root, U.box(Vector3(0.06, 0.07, 0.42)), m["wood"])
			_p(root, U.box(Vector3(0.05, 0.08, 0.22)), m["black"], Vector3(0, 0.07, -0.03))
			_p(root, U.box(Vector3(0.5, 0.02, 0.03)), m["wood"], Vector3(0, 0, -0.2))
		"kongque":
			_p(root, U.box(Vector3(0.05, 0.07, 0.7)), m["lacquer"])
			_p(root, U.box(Vector3(0.12, 0.06, 0.03)), m["feather"], Vector3(0, 0.07, -0.15))
		"baoyu":
			_p(root, U.box(Vector3(0.12, 0.1, 0.26)), m["lacquer"])
		"zhuihun":
			_p(root, U.box(Vector3(0.06, 0.08, 0.8)), m["wood"])
			_p(root, U.cyl(0.025, 0.025, 0.24, 8), m["bronze"], Vector3(0, 0.08, 0), Vector3(PI / 2, 0, 0))
			_p(root, U.box(Vector3(0.7, 0.025, 0.03)), m["wood"], Vector3(0, 0, -0.36))
	return root
