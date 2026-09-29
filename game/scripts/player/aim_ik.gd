class_name AimIK
extends SkeletonModifier3D
## 队友模型（混元绑的人形骨骼）端暗器的姿势：动画照常放（跑、跳、蹲），两条胳膊在动画之后用两节 IK 改掉——
## 右手到握把、左手托着前面，手肘往下往外撇。目标点每帧由 RemotePlayer 按朝向 + 抬头低头算好（世界坐标）。
## 骨头名是混元 / Mixamo 那套：RightArm / RightForeArm / RightHand，左边同理。

## 开关用 SkeletonModifier3D 自带的 active（关着的时候引擎不调这个修改器）
var r_target := Vector3.ZERO
var l_target := Vector3.ZERO
var r_pole := Vector3.ZERO
var l_pole := Vector3.ZERO
var _bones := {}


func _ready() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for nm in ["RightArm", "RightForeArm", "RightHand", "LeftArm", "LeftForeArm", "LeftHand"]:
		_bones[nm] = sk.find_bone(nm)


func _process_modification_with_delta(_delta: float) -> void:
	_apply()


func _process_modification() -> void:
	_apply()


func _apply() -> void:
	if _bones.is_empty() or int(_bones.get("RightArm", -1)) < 0 or int(_bones.get("LeftArm", -1)) < 0:
		return
	var sk := get_skeleton()
	var inv := sk.global_transform.affine_inverse()
	_two_bone(sk, _bones["RightArm"], _bones["RightForeArm"], _bones["RightHand"], inv * r_target, inv * r_pole)
	_two_bone(sk, _bones["LeftArm"], _bones["LeftForeArm"], _bones["LeftHand"], inv * l_target, inv * l_pole)


## 两节 IK（骨架坐标）：上臂 a → 前臂 b → 手 c，手放到 t，手肘朝 pole 那边弯
func _two_bone(sk: Skeleton3D, a: int, b: int, c: int, t: Vector3, pole: Vector3) -> void:
	if a < 0 or b < 0 or c < 0:
		return
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
	pv = (pv - dir * pv.dot(dir))
	if pv.length() < 1e-5:
		pv = Vector3.DOWN - dir * Vector3.DOWN.dot(dir)
	pv = pv.normalized()
	var x := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - x * x, 0.0))
	var E := A + dir * x + pv * h
	var T := A + dir * d
	# 上臂转到指向手肘
	var q1 := Quaternion((gb.origin - A).normalized(), (E - A).normalized())
	sk.set_bone_global_pose(a, Transform3D(Basis(q1) * ga.basis, A))
	# 前臂转到指向手
	gb = sk.get_bone_global_pose(b)
	gc = sk.get_bone_global_pose(c)
	var q2 := Quaternion((gc.origin - gb.origin).normalized(), (T - gb.origin).normalized())
	sk.set_bone_global_pose(b, Transform3D(Basis(q2) * gb.basis, gb.origin))
