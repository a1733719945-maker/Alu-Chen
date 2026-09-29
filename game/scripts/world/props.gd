class_name Props
extends RefCounted
## 公用的"像样"零件（2026-09-29 质感重做）：
##   rbox    倒角方块：边上有一道斜面，能接住高光（纯 BoxMesh 的直角边在光下就是一块平色，看着像积木）
##   lathe   旋转体：按一条轮廓线转一圈（灯笼、葫芦、柱础、香炉）
##   lantern 中式灯笼：带竹骨的纸灯身（透光）+ 上下漆木盖 + 金穗子 + 吊绳

static var _meshes := {}

## AI 生成的道具模型（混元，assets/models/props）
const BOAT_MODEL := "res://assets/models/props/boat.glb"
const LION_MODEL := "res://assets/models/props/stone_lion.glb"


## 摆一个模型：按 fit（"l" 长度 z / "h" 高度 y / "w" 宽度 x）缩到 size 米，水平居中、底面放在 base.y；yaw 转多少
static func place_model(parent: Node3D, path: String, size: float, fit := "h", base := Vector3.ZERO, yaw := 0.0) -> Node3D:
	var inst := (load(path) as PackedScene).instantiate() as Node3D
	var holder := Node3D.new()
	holder.name = "Model"
	parent.add_child(holder)
	holder.add_child(inst)
	inst.rotation.y = yaw
	var box := AABB()
	var first := true
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var t := Transform3D.IDENTITY
		var c: Node = n
		while c != null and c != holder:
			if c is Node3D:
				t = (c as Node3D).transform * t
			c = c.get_parent()
		var bb := t * (n as MeshInstance3D).get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	var dim: float = {"l": box.size.z, "h": box.size.y, "w": box.size.x}.get(fit, box.size.y)
	var k := size / maxf(dim, 0.001)
	inst.scale = Vector3.ONE * k
	var c0 := box.get_center()
	inst.position = Vector3(-c0.x * k, -box.position.y * k, -c0.z * k) + base
	for gi: GeometryInstance3D in inst.find_children("*", "GeometryInstance3D", true, false):
		gi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return holder


## 倒角方块。bevel：斜面宽（米），默认取最短边的 12%
static func rbox(size: Vector3, bevel := -1.0) -> ArrayMesh:
	var b := bevel if bevel >= 0.0 else minf(minf(size.x, size.y), size.z) * 0.12
	b = minf(b, minf(minf(size.x, size.y), size.z) * 0.45)
	var key := "rbox|%.4f|%.4f|%.4f|%.4f" % [size.x, size.y, size.z, b]
	if _meshes.has(key):
		return _meshes[key]
	var h := size * 0.5
	# 每个角三个点：沿 x / y / z 方向各缩进一点
	var pt := func(sx: float, sy: float, sz: float, axis: int) -> Vector3:
		var v := Vector3(sx * h.x, sy * h.y, sz * h.z)
		if axis != 0:
			v.x -= sx * b
		if axis != 1:
			v.y -= sy * b
		if axis != 2:
			v.z -= sz * b
		return v
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tri := func(a: Vector3, c: Vector3, d: Vector3, out: Vector3) -> void:
		var n := (c - a).cross(d - a)
		if n.length() < 1e-9:
			return
		# Godot 正面是顺时针：法线朝外时叉积应该朝里
		if n.dot(out) > 0.0:
			var t := c
			c = d
			d = t
		var nn := out.normalized()
		for v in [a, c, d]:
			st.set_normal(nn)
			st.set_uv(Vector2(v.x + v.z, v.y))
			st.add_vertex(v)
	var quad := func(a: Vector3, c: Vector3, d: Vector3, e: Vector3, out: Vector3) -> void:
		tri.call(a, c, d, out)
		tri.call(a, d, e, out)
	var S := [-1.0, 1.0]
	# 六个大面
	for s in S:
		quad.call(pt.call(s, -1, -1, 0), pt.call(s, 1, -1, 0), pt.call(s, 1, 1, 0), pt.call(s, -1, 1, 0), Vector3(s, 0, 0))
		quad.call(pt.call(-1, s, -1, 1), pt.call(1, s, -1, 1), pt.call(1, s, 1, 1), pt.call(-1, s, 1, 1), Vector3(0, s, 0))
		quad.call(pt.call(-1, -1, s, 2), pt.call(1, -1, s, 2), pt.call(1, 1, s, 2), pt.call(-1, 1, s, 2), Vector3(0, 0, s))
	# 十二条边的斜面
	for s1 in S:
		for s2 in S:
			# 沿 z 的边（x = s1, y = s2）
			quad.call(pt.call(s1, s2, -1, 0), pt.call(s1, s2, 1, 0), pt.call(s1, s2, 1, 1), pt.call(s1, s2, -1, 1), Vector3(s1, s2, 0))
			# 沿 x 的边（y = s1, z = s2）
			quad.call(pt.call(-1, s1, s2, 1), pt.call(1, s1, s2, 1), pt.call(1, s1, s2, 2), pt.call(-1, s1, s2, 2), Vector3(0, s1, s2))
			# 沿 y 的边（x = s1, z = s2）
			quad.call(pt.call(s1, -1, s2, 0), pt.call(s1, 1, s2, 0), pt.call(s1, 1, s2, 2), pt.call(s1, -1, s2, 2), Vector3(s1, 0, s2))
	# 八个角的小三角
	for sx in S:
		for sy in S:
			for sz in S:
				tri.call(pt.call(sx, sy, sz, 0), pt.call(sx, sy, sz, 1), pt.call(sx, sy, sz, 2), Vector3(sx, sy, sz))
	var m := st.commit()
	_meshes[key] = m
	return m


## 旋转体：prof 是 [半径, 高度] 一串点（从下往上），segs 圈分几段；ribs > 0 时表面按竹骨起伏（灯笼）
static func lathe(prof: PackedVector2Array, segs := 16, ribs := 0, rib_k := 0.05) -> ArrayMesh:
	var key := "lathe|%s|%d|%d|%.3f" % [str(prof), segs, ribs, rib_k]
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := prof.size()
	for i in rows:
		for k in segs + 1:
			var a := TAU * float(k) / segs
			var r := prof[i].x
			if ribs > 0:
				r *= 1.0 - rib_k * pow(absf(sin(a * ribs * 0.5)), 0.6)
			st.set_uv(Vector2(float(k) / segs, float(i) / maxf(rows - 1, 1)))
			st.add_vertex(Vector3(cos(a) * r, prof[i].y, sin(a) * r))
	for i in rows - 1:
		for k in segs:
			var a0 := i * (segs + 1) + k
			var b0 := a0 + segs + 1
			for idx in [a0, a0 + 1, b0, a0 + 1, b0 + 1, b0]:
				st.add_index(idx)
	st.generate_normals()
	var m := st.commit()
	_meshes[key] = m
	return m


## 中式灯笼。p 是灯身中心，s 是大小（1 = 灯身高约 0.5 米）
static func lantern(parent: Node3D, p: Vector3, c: Color, s := 1.0, cord := 0.25) -> Node3D:
	var n := Node3D.new()
	n.position = p
	n.scale = Vector3.ONE * s
	parent.add_child(n)
	var prof := PackedVector2Array()
	for i in 13:
		var t := float(i) / 12.0
		var y := lerpf(-0.24, 0.24, t)
		prof.append(Vector2(0.09 + 0.15 * sin(PI * t), y))
	var body := U.part(n, lathe(prof, 20, 10, 0.06), MatLib.paper_lamp(Color(c.r, c.g * 0.8, c.b * 0.7), 1.3), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
	body.name = "Body"
	var cap := MatLib.lacquer(Color(0.08, 0.05, 0.04), false)
	var gold := MatLib.gold()
	for dy in [0.25, -0.25]:
		U.part(n, U.cyl(0.1, 0.1, 0.05, 12), cap, Vector3(0, dy, 0))
		U.part(n, U.cyl(0.107, 0.107, 0.012, 12), gold, Vector3(0, dy + (0.02 if dy > 0 else -0.02), 0))
	# 金穗子：一根结 + 一束散开的穗
	U.part(n, U.sphere(0.022, 8, 6), gold, Vector3(0, -0.3, 0))
	U.part(n, U.cyl(0.012, 0.035, 0.22, 8), MatLib.canvas(Color(0.9, 0.62, 0.2)), Vector3(0, -0.43, 0))
	if cord > 0.0:
		U.part(n, U.cyl(0.006, 0.006, cord, 4), MatLib.rope(), Vector3(0, 0.27 + cord * 0.5, 0))
	return n
