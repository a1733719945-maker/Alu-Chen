class_name BeastModels
extends RefCounted
## 魂兽的模型：先用简单几何体拼。以后拿到 AI 生成的 .glb 模型，
## 放到 assets/models/<species>.glb 就会自动替换（见 build()）。
##
## 模型朝向：-Z 是头的方向。原点在身体中心（也是刚体的重心）。

const GLB_DIR := "res://assets/models/"


static func build(species: String, age: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	root.set_meta("species", species)
	var glb_path := GLB_DIR + species + ".glb"
	if ResourceLoader.exists(glb_path):
		var scene: PackedScene = load(glb_path)
		var inst := scene.instantiate()
		root.add_child(inst)
		root.set_meta("glb", true)
	else:
		match species:
			"rabbit":
				_rabbit(root)
			"vine":
				_vine(root)
			"bird":
				_bird(root)
			"moth":
				_moth(root)
			"wolf":
				_wolf(root)
			"rhino":
				_rhino(root)
			"ape":
				_ape(root)
			"snake":
				_snake(root)
	var s: float = Data.AGES[age]["scale"]
	root.scale = Vector3.ONE * s
	return root


## 碰撞形状：[{shape, xform, head}]，已经按年份缩放
static func shapes(species: String, age: int) -> Array:
	var s: float = Data.AGES[age]["scale"]
	var out := []
	match species:
		"rabbit":
			out.append({"shape": _sphere_shape(0.32 * s), "xform": Transform3D(), "head": false})
			out.append({"shape": _sphere_shape(0.22 * s), "xform": Transform3D(Basis(), Vector3(0, 0.2, -0.3) * s), "head": true})
		"vine":
			var cap := CapsuleShape3D.new()
			cap.radius = 0.2 * s
			cap.height = 1.5 * s
			out.append({"shape": cap, "xform": Transform3D(Basis.from_euler(Vector3(PI / 2, 0, 0)), Vector3(0, 0, 0.1) * s), "head": false})
			out.append({"shape": _sphere_shape(0.24 * s), "xform": Transform3D(Basis(), Vector3(0, 0.05, -0.78) * s), "head": true})
		"bird":
			out.append({"shape": _sphere_shape(0.22 * s), "xform": Transform3D(), "head": false})
			var wings := BoxShape3D.new()
			wings.size = Vector3(0.8, 0.08, 0.26) * s
			out.append({"shape": wings, "xform": Transform3D(Basis(), Vector3(0, 0.04, 0.02) * s), "head": false})
			out.append({"shape": _sphere_shape(0.15 * s), "xform": Transform3D(Basis(), Vector3(0, 0.13, -0.18) * s), "head": true})
		"wolf":
			var body := CapsuleShape3D.new()
			body.radius = 0.28 * s
			body.height = 1.2 * s
			out.append({"shape": body, "xform": Transform3D(Basis.from_euler(Vector3(PI / 2, 0, 0)), Vector3(0, 0, 0.05) * s), "head": false})
			out.append({"shape": _sphere_shape(0.22 * s), "xform": Transform3D(Basis(), Vector3(0, 0.22, -0.62) * s), "head": true})
		"rhino":
			var rb := BoxShape3D.new()
			rb.size = Vector3(0.9, 0.85, 1.6) * s
			out.append({"shape": rb, "xform": Transform3D(Basis(), Vector3(0, 0.05, 0.1) * s), "head": false})
			out.append({"shape": _sphere_shape(0.33 * s), "xform": Transform3D(Basis(), Vector3(0, 0.05, -0.95) * s), "head": true})
		"ape":
			var ab := CapsuleShape3D.new()
			ab.radius = 0.38 * s
			ab.height = 1.3 * s
			out.append({"shape": ab, "xform": Transform3D(Basis(), Vector3(0, 0.1, 0) * s), "head": false})
			out.append({"shape": _sphere_shape(0.26 * s), "xform": Transform3D(Basis(), Vector3(0, 0.85, -0.12) * s), "head": true})
		"snake":
			var sc := CapsuleShape3D.new()
			sc.radius = 0.2 * s
			sc.height = 1.7 * s
			out.append({"shape": sc, "xform": Transform3D(Basis.from_euler(Vector3(PI / 2, 0, 0)), Vector3(0, 0, 0.15) * s), "head": false})
			out.append({"shape": _sphere_shape(0.24 * s), "xform": Transform3D(Basis(), Vector3(0, 0.1, -0.85) * s), "head": true})
		"moth":
			var wb := BoxShape3D.new()
			wb.size = Vector3(0.95, 0.1, 0.5) * s
			out.append({"shape": wb, "xform": Transform3D(), "head": false})
			out.append({"shape": _sphere_shape(0.1 * s), "xform": Transform3D(Basis(), Vector3(0, 0.02, -0.2) * s), "head": true})
	return out


static func _sphere_shape(r: float) -> SphereShape3D:
	var sh := SphereShape3D.new()
	sh.radius = r
	return sh


## 魂环：水平漂在魂兽身上，颜色表示年份
static func aura(age: int, species: String) -> Node3D:
	var n := Node3D.new()
	n.name = "Aura"
	var s: float = Data.AGES[age]["scale"]
	var r := 0.55
	match species:
		"vine", "snake", "wolf":
			r = 0.85
		"rhino":
			r = 1.1
		"ape":
			r = 0.8
	var c: Color = Data.AGES[age]["color"]
	var energy := 1.6 if age == 0 else (2.6 if age == 1 else 3.6)
	var ring := U.part(n, U.torus(r * s - 0.03, r * s + 0.03, 48, 6), U.glow(c, energy), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
	ring.name = "Ring"
	if age >= 2:
		var light := OmniLight3D.new()
		light.light_color = c
		light.light_energy = 1.5
		light.omni_range = 5.0
		n.add_child(light)
	return n


# ------------------------------------------------------------------ 柔骨兔

static func _rabbit(root: Node3D) -> void:
	var white := U.mat(Color(0.97, 0.95, 0.93), 0.9)
	var pink := U.mat(Color(0.98, 0.7, 0.72), 0.8)
	var eye := U.mat(Color(0.85, 0.15, 0.2), 0.3)
	U.part(root, U.sphere(0.28, 14, 8), white, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.9, 1.25))
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.2, -0.3)
	root.add_child(head)
	U.part(head, U.sphere(0.2, 14, 8), white)
	U.part(head, U.sphere(0.035, 8, 4), eye, Vector3(0.1, 0.04, -0.14))
	U.part(head, U.sphere(0.035, 8, 4), eye, Vector3(-0.1, 0.04, -0.14))
	U.part(head, U.sphere(0.03, 6, 4), pink, Vector3(0, -0.03, -0.19))
	for side in [-1.0, 1.0]:
		var ear := Node3D.new()
		ear.name = "EarL" if side < 0 else "EarR"
		ear.position = Vector3(0.08 * side, 0.14, 0.02)
		ear.rotation = Vector3(0.35, 0, -0.18 * side)
		head.add_child(ear)
		U.part(ear, U.capsule(0.055, 0.38), white, Vector3(0, 0.19, 0), Vector3.ZERO, Vector3(1, 1, 0.55))
		U.part(ear, U.capsule(0.03, 0.28), pink, Vector3(0, 0.19, -0.02), Vector3.ZERO, Vector3(1, 1, 0.4))
	U.part(root, U.sphere(0.08, 8, 6), white, Vector3(0, 0.06, 0.34))
	for side in [-1.0, 1.0]:
		U.part(root, U.sphere(0.09, 8, 6), white, Vector3(0.14 * side, -0.2, 0.12), Vector3.ZERO, Vector3(0.8, 0.6, 1.4))
		U.part(root, U.sphere(0.06, 8, 6), white, Vector3(0.12 * side, -0.2, -0.2))
	# 小舞的粉色蝴蝶结
	U.part(head, U.sphere(0.05, 8, 4), pink, Vector3(0.12, 0.15, 0.02), Vector3.ZERO, Vector3(1.4, 0.8, 0.6))


# ------------------------------------------------------------------ 鬼藤

static func _vine(root: Node3D) -> void:
	var dark := U.mat(Color(0.12, 0.34, 0.17), 0.8)
	var mid := U.mat(Color(0.2, 0.48, 0.22), 0.8)
	var vein := U.glow(Color(0.45, 1.0, 0.45), 2.2)
	var eye := U.glow(Color(1.0, 0.85, 0.2), 3.0)
	var body := Node3D.new()
	body.name = "Segments"
	root.add_child(body)
	var n := 10
	for i in n:
		var t := float(i) / (n - 1)
		var seg := Node3D.new()
		seg.name = "S%d" % i
		seg.position = Vector3(0, 0, -0.6 + t * 1.45)
		body.add_child(seg)
		var r := lerpf(0.17, 0.06, t)
		U.part(seg, U.sphere(r, 10, 6), dark if i % 2 == 0 else mid)
		if i % 2 == 1:
			U.part(seg, U.sphere(r * 0.35, 6, 4), vein, Vector3(0, r * 0.8, 0))
		if i % 3 == 2:
			var leaf := U.part(seg, U.cyl(0.0, 0.07, 0.22, 4), mid, Vector3(r, 0.02, 0), Vector3(0, 0, -1.2), Vector3(1, 1, 0.3))
			leaf.name = "Leaf"
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.05, -0.78)
	root.add_child(head)
	U.part(head, U.sphere(0.22, 12, 8), dark, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.8, 1.3))
	U.part(head, U.sphere(0.045, 6, 4), eye, Vector3(0.11, 0.08, -0.18))
	U.part(head, U.sphere(0.045, 6, 4), eye, Vector3(-0.11, 0.08, -0.18))
	for side in [-1.0, 1.0]:
		U.part(head, U.cyl(0.0, 0.04, 0.22, 5), mid, Vector3(0.09 * side, 0.18, 0.05), Vector3(-0.6, 0, 0.3 * side))


# ------------------------------------------------------------------ 风铃鸟

static func _bird(root: Node3D) -> void:
	var teal := U.mat(Color(0.36, 0.82, 0.76), 0.7)
	var belly := U.mat(Color(0.96, 0.94, 0.78), 0.8)
	var beak := U.mat(Color(0.95, 0.62, 0.25), 0.6)
	var black := U.mat(Color(0.05, 0.05, 0.06), 0.3)
	var bell := U.glow(Color(1.0, 0.85, 0.35), 2.2)
	U.part(root, U.sphere(0.18, 12, 8), teal, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.95, 1.25))
	U.part(root, U.sphere(0.14, 10, 6), belly, Vector3(0, -0.05, -0.05), Vector3.ZERO, Vector3(0.9, 0.8, 1.1))
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.13, -0.18)
	root.add_child(head)
	U.part(head, U.sphere(0.13, 12, 8), teal)
	U.part(head, U.cyl(0.0, 0.035, 0.1, 6), beak, Vector3(0, -0.01, -0.15), Vector3(-PI / 2, 0, 0))
	U.part(head, U.sphere(0.022, 6, 4), black, Vector3(0.07, 0.03, -0.09))
	U.part(head, U.sphere(0.022, 6, 4), black, Vector3(-0.07, 0.03, -0.09))
	for side in [-1.0, 1.0]:
		var w := Node3D.new()
		w.name = "WingL" if side < 0 else "WingR"
		w.position = Vector3(0.14 * side, 0.05, 0.0)
		root.add_child(w)
		U.part(w, U.box(Vector3(0.34, 0.025, 0.2)), teal, Vector3(0.17 * side, 0, 0.02))
		U.part(w, U.box(Vector3(0.18, 0.02, 0.12)), belly, Vector3(0.3 * side, 0, 0.07))
	var tail := U.part(root, U.box(Vector3(0.16, 0.02, 0.26)), teal, Vector3(0, 0.03, 0.26), Vector3(0.25, 0, 0))
	tail.name = "Tail"
	U.part(root, U.sphere(0.045, 8, 6), bell, Vector3(0, -0.07, 0.3))


# ------------------------------------------------------------------ 月光蛾

static func _moth(root: Node3D) -> void:
	var body_m := U.mat(Color(0.85, 0.86, 0.92), 0.8)
	var wing_m := StandardMaterial3D.new()
	wing_m.albedo_color = Color(0.93, 0.95, 1.0, 0.85)
	wing_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wing_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	wing_m.emission_enabled = true
	wing_m.emission = Color(0.7, 0.75, 1.0)
	wing_m.emission_energy_multiplier = 0.8
	var edge := U.glow(Color(0.75, 0.8, 1.0), 2.0)
	U.part(root, U.capsule(0.05, 0.32), body_m, Vector3.ZERO, Vector3(PI / 2, 0, 0))
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.02, -0.2)
	root.add_child(head)
	U.part(head, U.sphere(0.06, 8, 6), body_m)
	for side in [-1.0, 1.0]:
		U.part(head, U.cyl(0.004, 0.006, 0.18, 4), body_m, Vector3(0.03 * side, 0.08, -0.05), Vector3(-0.7, 0, 0.4 * side))
	for side in [-1.0, 1.0]:
		var w := Node3D.new()
		w.name = "WingL" if side < 0 else "WingR"
		w.position = Vector3(0.03 * side, 0.02, 0.0)
		root.add_child(w)
		U.part(w, U.box(Vector3(0.44, 0.01, 0.3)), wing_m, Vector3(0.22 * side, 0, -0.06), Vector3(0, 0.25 * side, 0), Vector3.ONE, false)
		U.part(w, U.box(Vector3(0.3, 0.01, 0.22)), wing_m, Vector3(0.17 * side, 0, 0.16), Vector3(0, -0.3 * side, 0), Vector3.ONE, false)
		U.part(w, U.sphere(0.035, 6, 4), edge, Vector3(0.36 * side, 0.005, -0.08))


# ------------------------------------------------------------------ 疾风魔狼

static func _leg(parent: Node3D, name: String, pos: Vector3, mat: Material, r: float, length: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = name
	pivot.position = pos
	parent.add_child(pivot)
	U.part(pivot, U.capsule(r, length), mat, Vector3(0, -length * 0.45, 0))
	return pivot


static func _wolf(root: Node3D) -> void:
	var fur := U.mat(Color(0.32, 0.36, 0.44), 0.9)
	var belly := U.mat(Color(0.62, 0.64, 0.68), 0.9)
	var dark := U.mat(Color(0.12, 0.13, 0.16), 0.8)
	var eye := U.glow(Color(0.4, 0.95, 1.0), 3.5)
	var wind := U.glow(Color(0.55, 0.9, 1.0), 1.4, true)
	U.part(root, U.capsule(0.26, 1.05), fur, Vector3(0, 0, 0.05), Vector3(PI / 2, 0, 0), Vector3(1.0, 1.0, 0.95))
	U.part(root, U.capsule(0.2, 0.7), belly, Vector3(0, -0.08, 0.05), Vector3(PI / 2, 0, 0), Vector3(0.9, 1.0, 0.8))
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.22, -0.6)
	root.add_child(head)
	U.part(head, U.sphere(0.2, 12, 8), fur, Vector3.ZERO, Vector3.ZERO, Vector3(0.9, 0.9, 1.1))
	U.part(head, U.cyl(0.07, 0.1, 0.26, 8), dark, Vector3(0, -0.05, -0.2), Vector3(PI / 2, 0, 0))
	U.part(head, U.sphere(0.035, 6, 4), eye, Vector3(0.09, 0.06, -0.12))
	U.part(head, U.sphere(0.035, 6, 4), eye, Vector3(-0.09, 0.06, -0.12))
	for side in [-1.0, 1.0]:
		U.part(head, U.cyl(0.0, 0.06, 0.16, 4), fur, Vector3(0.09 * side, 0.2, 0.04), Vector3(0, 0, -0.15 * side))
	for k in 4:
		var side := -1.0 if k % 2 == 0 else 1.0
		var zz := -0.35 if k < 2 else 0.4
		_leg(root, "Leg%d" % k, Vector3(0.14 * side, -0.12, zz), fur, 0.07, 0.5)
	var tail := Node3D.new()
	tail.name = "Tail"
	tail.position = Vector3(0, 0.08, 0.62)
	root.add_child(tail)
	U.part(tail, U.capsule(0.07, 0.55), fur, Vector3(0, 0.05, 0.25), Vector3(1.1, 0, 0))
	# 疾风：身上一圈风纹
	U.part(root, U.torus(0.34, 0.37, 24, 4), wind, Vector3(0, 0, -0.1), Vector3(PI / 2, 0, 0), Vector3.ONE, false)


# ------------------------------------------------------------------ 铁甲犀

static func _rhino(root: Node3D) -> void:
	var hide := U.mat(Color(0.42, 0.4, 0.38), 0.95)
	var plate := U.mat(Color(0.35, 0.37, 0.4), 0.35, 0.0, 0.8)
	var horn := U.mat(Color(0.85, 0.8, 0.7), 0.5)
	var eye := U.glow(Color(1.0, 0.45, 0.2), 3.0)
	U.part(root, U.sphere(0.6, 14, 10), hide, Vector3(0, 0.05, 0.1), Vector3.ZERO, Vector3(0.8, 0.72, 1.35))
	# 铁甲：背上几块金属板
	for k in 4:
		U.part(root, U.box(Vector3(0.85, 0.12, 0.34)), plate, Vector3(0, 0.45 - absf(k - 1.5) * 0.04, -0.4 + k * 0.32), Vector3(0.1 * (k - 1.5), 0, 0))
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.02, -0.9)
	root.add_child(head)
	U.part(head, U.sphere(0.34, 12, 8), hide, Vector3.ZERO, Vector3.ZERO, Vector3(0.9, 0.85, 1.2))
	U.part(head, U.cyl(0.0, 0.1, 0.42, 8), horn, Vector3(0, 0.25, -0.28), Vector3(-0.5, 0, 0))
	U.part(head, U.cyl(0.0, 0.06, 0.2, 6), horn, Vector3(0, 0.25, -0.02), Vector3(-0.3, 0, 0))
	U.part(head, U.box(Vector3(0.62, 0.1, 0.3)), plate, Vector3(0, 0.26, 0.12))
	U.part(head, U.sphere(0.04, 6, 4), eye, Vector3(0.2, 0.1, -0.15))
	U.part(head, U.sphere(0.04, 6, 4), eye, Vector3(-0.2, 0.1, -0.15))
	for k in 4:
		var side := -1.0 if k % 2 == 0 else 1.0
		var zz := -0.45 if k < 2 else 0.6
		_leg(root, "Leg%d" % k, Vector3(0.32 * side, -0.3, zz), hide, 0.14, 0.55)


# ------------------------------------------------------------------ 金刚猿

static func _ape(root: Node3D) -> void:
	var fur := U.mat(Color(0.25, 0.17, 0.12), 0.95)
	var face := U.mat(Color(0.55, 0.42, 0.34), 0.8)
	var gold := U.glow(Color(1.0, 0.75, 0.3), 1.8)
	var eye := U.glow(Color(1.0, 0.85, 0.25), 3.0)
	U.part(root, U.sphere(0.45, 14, 10), fur, Vector3(0, 0.15, 0), Vector3.ZERO, Vector3(1.1, 1.2, 0.85))
	U.part(root, U.sphere(0.3, 12, 8), face, Vector3(0, 0.1, -0.26), Vector3.ZERO, Vector3(1.0, 1.1, 0.5))
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.85, -0.12)
	root.add_child(head)
	U.part(head, U.sphere(0.26, 12, 8), fur)
	U.part(head, U.sphere(0.18, 10, 6), face, Vector3(0, -0.03, -0.14), Vector3.ZERO, Vector3(1.0, 0.9, 0.7))
	U.part(head, U.sphere(0.035, 6, 4), eye, Vector3(0.08, 0.04, -0.24))
	U.part(head, U.sphere(0.035, 6, 4), eye, Vector3(-0.08, 0.04, -0.24))
	# 金刚：手臂上的金纹
	for side in [-1.0, 1.0]:
		var arm := _leg(root, "Arm" + ("L" if side < 0 else "R"), Vector3(0.5 * side, 0.5, -0.05), fur, 0.14, 0.9)
		U.part(arm, U.torus(0.13, 0.16, 16, 4), gold, Vector3(0, -0.35, 0), Vector3.ZERO, Vector3.ONE, false)
		U.part(arm, U.sphere(0.16, 10, 6), face, Vector3(0, -0.85, 0))
	for k in 2:
		var side := -1.0 if k == 0 else 1.0
		_leg(root, "Leg%d" % k, Vector3(0.22 * side, -0.35, 0.05), fur, 0.14, 0.5)


# ------------------------------------------------------------------ 曼陀罗蛇

static func _snake(root: Node3D) -> void:
	var skin := U.mat(Color(0.3, 0.12, 0.35), 0.5)
	var belly := U.mat(Color(0.75, 0.6, 0.35), 0.6)
	var mark := U.glow(Color(1.0, 0.35, 0.7), 2.0)
	var eye := U.glow(Color(0.9, 1.0, 0.3), 3.5)
	var body := Node3D.new()
	body.name = "Segments"
	root.add_child(body)
	var n := 12
	for i in n:
		var t := float(i) / (n - 1)
		var seg := Node3D.new()
		seg.name = "S%d" % i
		seg.position = Vector3(0, 0, -0.65 + t * 1.7)
		body.add_child(seg)
		var r := lerpf(0.19, 0.06, t)
		U.part(seg, U.sphere(r, 10, 6), skin)
		U.part(seg, U.sphere(r * 0.8, 8, 4), belly, Vector3(0, -r * 0.35, 0), Vector3.ZERO, Vector3(1.0, 0.6, 1.0))
		if i % 2 == 0:
			U.part(seg, U.sphere(r * 0.35, 6, 4), mark, Vector3(0, r * 0.8, 0))
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.1, -0.85)
	root.add_child(head)
	U.part(head, U.sphere(0.24, 12, 8), skin, Vector3.ZERO, Vector3.ZERO, Vector3(1.1, 0.7, 1.4))
	U.part(head, U.sphere(0.04, 6, 4), eye, Vector3(0.13, 0.08, -0.15))
	U.part(head, U.sphere(0.04, 6, 4), eye, Vector3(-0.13, 0.08, -0.15))
	# 曼陀罗花冠
	for k in 5:
		var a := TAU * k / 5.0
		U.part(head, U.cyl(0.0, 0.06, 0.18, 4), mark, Vector3(cos(a) * 0.14, 0.18, 0.08 + sin(a) * 0.1), Vector3(-0.6, a, 0))


# ------------------------------------------------------------------ 动画（不管是房主算的还是客人看到的，都用这个）

static func animate(model: Node3D, t: float, airborne: bool, speed := 0.0) -> void:
	if model.has_meta("glb"):
		return
	var species: String = model.get_meta("species", "")
	match species:
		"bird":
			var flap := sin(t * 16.0) * 0.9 if airborne else 0.15
			var wl := model.get_node_or_null("WingL")
			var wr := model.get_node_or_null("WingR")
			if wl:
				wl.rotation.z = -flap
			if wr:
				wr.rotation.z = flap
		"moth":
			var flap := sin(t * 9.0) * 0.75
			var wl := model.get_node_or_null("WingL")
			var wr := model.get_node_or_null("WingR")
			if wl:
				wl.rotation.z = -flap
			if wr:
				wr.rotation.z = flap
		"wolf", "rhino", "ape":
			var sp := clampf(speed / 6.0, 0.0, 1.5)
			var f := 11.0 if species == "wolf" else (7.0 if species == "rhino" else 8.0)
			for k in 4:
				var leg := model.get_node_or_null("Leg%d" % k)
				if leg:
					var ph := 0.0 if k in [0, 3] else PI
					leg.rotation.x = sin(t * f + ph) * 0.7 * sp if not airborne else (0.6 if k < 2 else -0.6)
			if species == "ape":
				for n in ["ArmL", "ArmR"]:
					var arm := model.get_node_or_null(n)
					if arm:
						arm.rotation.x = sin(t * 6.0 + (0.0 if n == "ArmL" else PI)) * 0.5 * sp + (-1.2 if airborne else 0.0)
			var tail := model.get_node_or_null("Tail")
			if tail:
				tail.rotation.y = sin(t * 9.0) * 0.4
		"vine", "snake":
			var segs := model.get_node_or_null("Segments")
			if segs:
				var amp := 0.06 + minf(speed, 4.0) * 0.03
				var i := 0
				for s in segs.get_children():
					s.position.x = sin(t * 7.0 + i * 0.9) * amp * (0.4 + i * 0.12)
					i += 1
		"rabbit":
			var head := model.get_node_or_null("Head")
			if head:
				var el := head.get_node_or_null("EarL")
				var er := head.get_node_or_null("EarR")
				var k := 0.5 if airborne else 0.0
				if el:
					el.rotation.x = 0.35 + sin(t * 11.0) * 0.12 + k
				if er:
					er.rotation.x = 0.35 + sin(t * 11.0 + 1.3) * 0.12 + k
