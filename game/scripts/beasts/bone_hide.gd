class_name BoneHide
extends SkeletonModifier3D
## 部位破坏用（2026-09-29 样板狩猎）：在动画之后改骨头——
##   hide：这些骨头（连同子骨头）缩成一个点：灵兽王的尾巴、角、翅膀尖"断掉了"
##   keep：反过来用在掉下来的那一截上：整棵骨架缩成一点，只把这几根骨头（和子骨头）放回原来的大小和位置——
##         同一个模型、同一张贴图，只剩断下来的那截尾巴 / 角 / 翅膀

var hide: Array[int] = []
var keep: Array[int] = []


func _process_modification_with_delta(_delta: float) -> void:
	_apply()


func _process_modification() -> void:
	_apply()


func _apply() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for b in hide:
		if b >= 0:
			sk.set_bone_pose_scale(b, Vector3.ONE * 0.001)
	if keep.is_empty():
		return
	var saved := {}
	for b in keep:
		if b >= 0:
			saved[b] = sk.get_bone_global_pose(b)
	for r in sk.get_parentless_bones():
		sk.set_bone_pose_scale(r, Vector3.ONE * 0.001)
	for b in saved:
		sk.set_bone_global_pose(b, saved[b])
