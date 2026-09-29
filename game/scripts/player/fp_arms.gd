class_name FPArms
extends Node3D
## 第一人称的手（2026-09-29，用户："持枪的手还是非常简陋，用人物模型的手"）：
## 用混元生成的玩家人物（assets/models/player/player.glb，和队友同一个模型）——
##   只留两条胳膊的三角形（袖子、金护腕、半指皮手套），身子、头、箭囊都删掉；
##   模型没有手指骨头：加载时把手指按"弯曲变形"卷成握拳（绕指根的横轴，越往指尖弯得越多）；
##   整副骨架摆成头在镜头上、面朝前，每帧两节 IK 把手腕放到暗器上的握把标记（GripR / GripL，WeaponModels 放的），
##   手掌朝向按标记上写的 a（手腕 → 指根）、n（手心朝哪）摆。
## 没有标记的那只手垂到画面下面去。

const MODEL := "res://assets/models/player/player.glb"
const ARM_BONES := ["LeftArm", "LeftForeArm", "LeftHand", "LeftHand_end", "RightArm", "RightForeArm", "RightHand", "RightHand_end"]
const EYE := Vector3(0.0, -0.1, 0.07)     # 头骨（Head）相对镜头的位置：眼睛比头骨高一点、靠前一点
const CURL := 2.5                         # 手指卷多少（弧度，指尖处）：9 厘米的手指卷成半径约 3.6 厘米的圈
const KNUCKLE := 0.63                     # 指根在手上的位置（手腕到指尖的比例；按手的宽度 / 厚度截面量的：16 / 25 厘米）

static var _cache := {}                   # "mesh" / "frames"（每只手的 H、a0、n0、tmax）

var skel: Skeleton3D
var ik: FPIK
var right: Node3D                         # 右手的目标（带 meta a / n 的标记），null = 垂下去
var left: Node3D


static func available() -> bool:
	return ResourceLoader.exists(MODEL)


## 镜头的朝向（ViewModel 挂在镜头下面、不转；FPArms 自己转了 180°）
func cam_basis() -> Basis:
	var p := get_parent() as Node3D
	return p.global_basis if p else global_basis


func _ready() -> void:
	name = "FPArms"
	var inst := (load(MODEL) as PackedScene).instantiate() as Node3D
	add_child(inst)
	rotation.y = PI                       # 模型面朝 +Z，镜头看 -Z
	for ap in inst.find_children("*", "AnimationPlayer", true, false):
		(ap as AnimationPlayer).active = false
	var sks := inst.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		queue_free()
		return
	skel = sks[0]
	skel.reset_bone_poses()
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.skin == null or not (mi.mesh is ArrayMesh):
			mi.visible = false
			continue
		var frames := {}
		mi.mesh = _arm_mesh(mi.mesh as ArrayMesh, mi.skin, frames)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		if ik == null:
			ik = FPIK.new()
			ik.fp = self
			ik.skin = mi.skin
			ik.frames = frames
			skel.add_child(ik)
	# 头骨放到镜头下面一点（在树里才算得出世界坐标）
	var hb := skel.find_bone("Head")
	if hb >= 0:
		var head: Vector3 = global_transform.affine_inverse() * (skel.global_transform * skel.get_bone_global_rest(hb).origin)
		position = EYE - basis * head


# ------------------------------------------------------------------ 只留胳膊 + 卷手指

## 返回新网格；frames 里填每只手的 {"bind": 绑定索引, "H", "a0", "n0", "tmax"}（网格空间，绑定姿势）
func _arm_mesh(src: ArrayMesh, skin: Skin, frames: Dictionary) -> ArrayMesh:
	var bind_name := {}
	for i in skin.get_bind_count():
		var bn := String(skin.get_bind_name(i))
		if bn == "" and skin.get_bind_bone(i) >= 0:
			bn = skel.get_bone_name(skin.get_bind_bone(i))
		bind_name[i] = bn
	# 两只手的框架：在骨架空间里算（混元的 FBX 是 Z 朝上的，网格空间和骨架空间差 90°，不能混用），
	# 卷手指时换到网格空间（S = 骨架静止姿势 × 绑定：网格空间 → 骨架空间）
	var lat := Vector3.RIGHT
	var up := Vector3.UP
	var la := skel.find_bone("LeftArm")
	var ra := skel.find_bone("RightArm")
	if la >= 0 and ra >= 0:
		lat = (skel.get_bone_global_rest(ra).origin - skel.get_bone_global_rest(la).origin).normalized()
	var hips := skel.find_bone("Hips")
	var head := skel.find_bone("Head")
	if hips >= 0 and head >= 0:
		up = (skel.get_bone_global_rest(head).origin - skel.get_bone_global_rest(hips).origin).normalized()
	for side in ["Left", "Right"]:
		var hi := -1
		for i in bind_name:
			if bind_name[i] == side + "Hand":
				hi = i
		var hb := skel.find_bone(side + "Hand")
		var eb := skel.find_bone(side + "Hand_end")
		if hi < 0 or hb < 0:
			continue
		var rest := skel.get_bone_global_rest(hb)
		var S := rest * skin.get_bind_pose(hi)
		var H := rest.origin
		var a0: Vector3
		if eb >= 0:
			a0 = (skel.get_bone_global_rest(eb).origin - H).normalized()
		else:
			a0 = (rest.basis * Vector3.UP).normalized()
		# 手心朝向：A 字站姿手垂在身侧，手心朝身体中线
		var inward := -lat if side == "Right" else lat
		var n0 := (inward - a0 * inward.dot(a0)).normalized()
		var Si := S.affine_inverse()
		frames[side] = {"bind": hi, "rest": rest, "H": H, "a0": a0, "n0": n0, "tmax": 0.0,
			"Hm": Si * H, "a0m": (Si.basis * a0).normalized(), "n0m": (Si.basis * n0).normalized()}
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var arr: Array = src.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var tans: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT] if arr[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var n := verts.size()
		var per := bones.size() / maxi(n, 1)
		# 每个顶点主要跟着哪根骨头
		var main := PackedStringArray()
		main.resize(n)
		for v in n:
			var best := 0.0
			var bn := ""
			for c in per:
				var w := weights[v * per + c]
				if w > best:
					best = w
					bn = str(bind_name.get(bones[v * per + c], ""))
			main[v] = bn
		# 手指弯曲
		for side in frames:
			var f: Dictionary = frames[side]
			var H: Vector3 = f["Hm"]
			var a0: Vector3 = f["a0m"]
			var tmax := 0.0
			for v in n:
				if main[v].begins_with(side + "Hand"):
					tmax = maxf(tmax, (verts[v] - H).dot(a0))
			# IK 用骨架空间的长度（网格空间可能是厘米）
			var sk_k: float = ((f["rest"] as Transform3D) * skin.get_bind_pose(int(f["bind"]))).basis.get_scale().x
			f["tmax"] = maxf(tmax * sk_k, float(f["tmax"]))
			if tmax <= 1e-4:
				continue
			var n0: Vector3 = f["n0m"]
			var c0 := a0.cross(n0).normalized()
			var t0 := tmax * KNUCKLE
			var R := (tmax - t0) / CURL
			# 大拇指不动（它在指根以前）：静止姿势里朝手心那边伸着。所以握的时候让手心朝着暗器，拇指就藏在暗器里
			for v in n:
				if not main[v].begins_with(side + "Hand"):
					continue
				var rel := verts[v] - H
				var sx := rel.dot(a0) - t0
				if sx <= 0.0:
					continue
				var d := rel.dot(n0)
				var l := rel.dot(c0)
				var phi := sx / R
				var r := R - d
				var np := H + a0 * (t0 + sin(phi) * r) + n0 * (R - cos(phi) * r) + c0 * l
				verts[v] = np
				var rot := Basis(c0, phi)
				if not norms.is_empty():
					norms[v] = rot * norms[v]
				if not tans.is_empty():
					var t3 := rot * Vector3(tans[v * 4], tans[v * 4 + 1], tans[v * 4 + 2])
					tans[v * 4] = t3.x
					tans[v * 4 + 1] = t3.y
					tans[v * 4 + 2] = t3.z
		# 只留胳膊的三角形
		var keep := PackedInt32Array()
		for t in range(0, idx.size(), 3):
			if main[idx[t]] in ARM_BONES and main[idx[t + 1]] in ARM_BONES and main[idx[t + 2]] in ARM_BONES:
				keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
		arr[Mesh.ARRAY_VERTEX] = verts
		if not norms.is_empty():
			arr[Mesh.ARRAY_NORMAL] = norms
		if not tans.is_empty():
			arr[Mesh.ARRAY_TANGENT] = tans
		arr[Mesh.ARRAY_INDEX] = keep
		if keep.is_empty():
			continue
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, src.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
		var mat := src.surface_get_material(s)
		if mat is BaseMaterial3D:
			# 袖口被切开的地方能看到里面：双面画
			var m2 := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
			m2.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat = m2
		out.surface_set_material(out.get_surface_count() - 1, mat)
	return out


# ------------------------------------------------------------------ IK：手腕到握把、手掌按标记朝向

class FPIK extends SkeletonModifier3D:
	var fp: FPArms
	var skin: Skin
	var frames := {}

	func _process_modification_with_delta(_delta: float) -> void:
		_apply()

	func _process_modification() -> void:
		_apply()

	func _apply() -> void:
		var sk := get_skeleton()
		if sk == null or fp == null:
			return
		_side(sk, "Right", fp.right)
		_side(sk, "Left", fp.left)

	func _side(sk: Skeleton3D, side: String, target: Node3D) -> void:
		if not frames.has(side):
			return
		var f: Dictionary = frames[side]
		var ua := sk.find_bone(side + "Arm")
		var fa := sk.find_bone(side + "ForeArm")
		var hb := sk.find_bone(side + "Hand")
		if ua < 0 or fa < 0 or hb < 0:
			return
		var inv := sk.global_transform.affine_inverse()
		var sh := sk.get_bone_global_pose(ua).origin
		var sgn := -1.0 if side == "Left" else 1.0
		var a: Vector3
		var n: Vector3
		var g: Vector3
		if target != null and target.is_inside_tree() and target.is_visible_in_tree():
			var tb := inv.basis * target.global_basis
			a = (tb * (target.get_meta("a", Vector3(0, 0, -1)) as Vector3)).normalized()
			n = (tb * (target.get_meta("n", Vector3(-1, 0, 0)) as Vector3)).normalized()
			g = inv * target.global_position
		else:
			# 没事干：垂到画面下面
			var cam_down := (inv.basis * fp.cam_basis() * Vector3.DOWN).normalized()
			a = cam_down
			n = (inv.basis * fp.cam_basis() * Vector3(-sgn, 0, 0)).normalized()
			g = sh + cam_down * 0.62
		n = (n - a * n.dot(a)).normalized()
		var c := a.cross(n)
		var a0: Vector3 = f["a0"]
		var n0: Vector3 = f["n0"]
		var c0 := a0.cross(n0)
		var R := Basis(a, n, c) * Basis(a0, n0, c0).transposed()
		var tmax := float(f["tmax"])
		# 手指卷成的圈的圆心对准握把中心：圆心在指根往手心方向 R 处
		var curl_r := tmax * (1.0 - KNUCKLE) / CURL
		var w := g - a * (tmax * KNUCKLE) - n * (curl_r * 0.8)
		# 两节 IK：上臂 → 前臂，手肘往外、往下
		var pole := sh + (inv.basis * fp.cam_basis() * Vector3(sgn * 0.5, -0.6, 0.15))
		_two_bone(sk, ua, fa, hb, w, pole)
		# 骨架空间里：把静止姿势的手整个转 R、挪到手腕目标
		var H: Vector3 = f["H"]
		var M := Transform3D(R, w - R * H)
		sk.set_bone_global_pose(hb, M * (f["rest"] as Transform3D))

	func _two_bone(sk: Skeleton3D, a: int, b: int, c: int, t: Vector3, pole: Vector3) -> void:
		var ga := sk.get_bone_global_pose(a)
		var gb := sk.get_bone_global_pose(b)
		var gc := sk.get_bone_global_pose(c)
		var A := ga.origin
		var l1 := A.distance_to(gb.origin)
		var l2 := gb.origin.distance_to(gc.origin)
		if l1 < 1e-4 or l2 < 1e-4:
			return
		var to_t := t - A
		var d := clampf(to_t.length(), absf(l1 - l2) + 1e-3, (l1 + l2) * 0.999)
		var dir := to_t.normalized()
		var pv := pole - A
		pv = pv - dir * pv.dot(dir)
		if pv.length() < 1e-5:
			pv = Vector3.DOWN - dir * Vector3.DOWN.dot(dir)
		pv = pv.normalized()
		var x := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
		var h := sqrt(maxf(l1 * l1 - x * x, 0.0))
		var E := A + dir * x + pv * h
		var T := A + dir * d
		var q1 := Quaternion((gb.origin - A).normalized(), (E - A).normalized())
		sk.set_bone_global_pose(a, Transform3D(Basis(q1) * ga.basis, A))
		gb = sk.get_bone_global_pose(b)
		gc = sk.get_bone_global_pose(c)
		var q2 := Quaternion((gc.origin - gb.origin).normalized(), (T - gb.origin).normalized())
		sk.set_bone_global_pose(b, Transform3D(Basis(q2) * gb.basis, gb.origin))
