extends SceneTree
## 混元 3D Studio 绑好骨骼的 FBX → 游戏用的 GLB（Boss：assets/models/bosses/<kind>.glb）
##
## 混元每导出一次只带一个动作（每个文件都是整个模型 + 一段动作），这里把几个文件的动作合进一个 GLB：
##   godot --headless --path <空项目> --script fbx_to_glb.gd -- 输出.glb 贴图边长 动作名=文件.fbx [动作名=文件.fbx ...]
##   第一个文件当底（模型、骨骼、贴图都用它的），其他文件只取动作。
##   动作名用 Boss 认得的：idle / walk / run / attack（attack2…）/ roar / jump / hit / death
##
## 顺便做三件事：
##   1. 立起来：混元的 FBX 是 Z 朝上的，读进来是躺着的 → 外面包一层转 -90°
##   2. 修尾巴：人形骨架没有尾巴骨头，尾巴被绑到了腿上，一动就拉成长带子 → 尾巴上的点全部改绑到胯（Hips），跟着身子走
##   3. 贴图缩到指定边长（原来 4K PNG 几十 MB）

const LOOP := ["idle", "walk", "run"]


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 3:
		print("用法：-- out.glb 贴图边长 名字=文件.fbx ...")
		quit(1)
		return
	# --notail：不修尾巴（人形角色：长衫后摆会被当成尾巴改绑到胯上，跑起来脚边拉出长条）
	var notail := a.has("--notail")
	if notail:
		a.erase("--notail")
	var out_path := a[0]
	var tex := int(a[1])
	var pairs: Array = []
	for i in range(2, a.size()):
		var kv := a[i].split("=", true, 1)
		pairs.append([kv[0], kv[1]])
	var base := _load(pairs[0][1])
	if base == null:
		quit(1)
		return
	var ap: AnimationPlayer = base.find_children("*", "AnimationPlayer", true, false)[0]
	# 动作：每个文件取它的第一段，按给的名字放进底模的动作库
	var lib := AnimationLibrary.new()
	for pr in pairs:
		var src: Node = base if pr[1] == pairs[0][1] else _load(pr[1])
		var sap: AnimationPlayer = src.find_children("*", "AnimationPlayer", true, false)[0]
		var an: Animation = sap.get_animation(sap.get_animation_list()[0]).duplicate(true)
		# 名字后面带 @角度：整段动作绕竖轴转这么多度（混元有的动作整个人是侧着的，比如快拳）
		var nm: String = pr[0]
		var yaw := 0.0
		if "@" in nm:
			yaw = float(nm.get_slice("@", 1))
			nm = nm.get_slice("@", 0)
		if yaw != 0.0:
			_turn(an, src, deg_to_rad(yaw))
		an.loop_mode = Animation.LOOP_LINEAR if nm in LOOP else Animation.LOOP_NONE
		lib.add_animation(nm, an)
		print("动作 ", nm, " ← ", pr[1].get_file(), "（", snappedf(an.length, 0.01), " 秒", ("，转 %d°" % int(yaw)) if yaw != 0.0 else "", "）")
		if src != base:
			src.free()
	for ln in ap.get_animation_library_list():
		ap.remove_animation_library(ln)
	ap.add_animation_library("", lib)
	# 立起来
	var root := Node3D.new()
	root.name = "Model"
	root.add_child(base)
	base.owner = null
	var box := _aabb(base)
	if box.size.z > box.size.y * 1.3:
		base.rotation.x = -PI * 0.5
		print("高度在 Z 轴上：转 -90° 立起来")
	_set_owner(base, root)
	# 修尾巴 + 缩贴图
	for n in base.find_children("*", "", true, false):
		if n is ImporterMeshInstance3D:
			var imi := n as ImporterMeshInstance3D
			var sk := imi.get_node_or_null(imi.skeleton_path) as Skeleton3D
			if imi.skin and sk and not notail:
				imi.mesh = _fix_tail(imi.mesh, imi.skin, sk)
			for i in imi.mesh.get_surface_count():
				_shrink_textures(imi.mesh.get_surface_material(i), tex)
		elif n is MeshInstance3D and (n as MeshInstance3D).mesh is ArrayMesh:
			# FBXDocument.generate_scene 出来的是普通 MeshInstance3D：转成 ImporterMesh 修完再转回来
			var mi := n as MeshInstance3D
			var am := mi.mesh as ArrayMesh
			var im := ImporterMesh.new()
			for i in am.get_surface_count():
				im.add_surface(am.surface_get_primitive_type(i), am.surface_get_arrays(i), [], {}, am.surface_get_material(i), am.surface_get_name(i), am.surface_get_format(i) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
			var sk2 := mi.get_node_or_null(mi.skeleton) as Skeleton3D
			if mi.skin and sk2 and not notail:
				im = _fix_tail(im, mi.skin, sk2)
			for i in im.get_surface_count():
				_shrink_textures(im.get_surface_material(i), tex)
			mi.mesh = im.get_mesh()
	var doc := GLTFDocument.new()
	doc.image_format = "JPEG"
	doc.lossy_quality = 0.88
	var st := GLTFState.new()
	if doc.append_from_scene(root, st) != OK or doc.write_to_filesystem(st, out_path) != OK:
		print("写不出 ", out_path)
		quit(1)
		return
	print("写好了 ", out_path)
	quit(0)


## 整段动作绕竖轴转 ang：只改 Hips（根）的旋转和位置轨道，在 Hips 父骨头的空间里转
func _turn(an: Animation, scene: Node, ang: float) -> void:
	var sk: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
	var hip := sk.find_bone("Hips")
	var par := sk.get_bone_parent(hip)
	var pb := _xf(scene, sk).basis * (sk.get_bone_global_rest(par).basis if par >= 0 else Basis())
	var up := (pb.inverse() * Vector3.UP).normalized()
	var r := Quaternion(up, ang)
	for t in an.get_track_count():
		var path := String(an.track_get_path(t))
		if not path.ends_with(":Hips"):
			continue
		for k in an.track_get_key_count(t):
			var v: Variant = an.track_get_key_value(t, k)
			if an.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				an.track_set_key_value(t, k, (r * (v as Quaternion)).normalized())
			elif an.track_get_type(t) == Animation.TYPE_POSITION_3D:
				an.track_set_key_value(t, k, r * (v as Vector3))


func _load(path: String) -> Node:
	var d := FBXDocument.new()
	var s := FBXState.new()
	if d.append_from_file(path, s) != OK:
		print("读不了 ", path)
		return null
	return d.generate_scene(s)


func _set_owner(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		c.owner = owner_node
		_set_owner(c, owner_node)
	if n != owner_node:
		n.owner = owner_node


func _aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for m in n.find_children("*", "", true, false):
		var bb: AABB
		if m is ImporterMeshInstance3D:
			bb = _xf(n, m) * (m as ImporterMeshInstance3D).mesh.get_mesh().get_aabb()
		elif m is MeshInstance3D and (m as MeshInstance3D).mesh:
			bb = _xf(n, m) * (m as MeshInstance3D).mesh.get_aabb()
		else:
			continue
		box = bb if first else box.merge(bb)
		first = false
	return box


func _xf(root: Node, n: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


## 尾巴：在身子后面、胯以下、离两条腿都远的点做种子，顺着三角形往外长，碰到身体表面就停；全部改绑到 Hips
func _fix_tail(mesh: ImporterMesh, skin: Skin, sk: Skeleton3D) -> ImporterMesh:
	# 骨头在网格空间里的位置（绑定姿势的逆）
	var pos := {}
	var bind_of := {}
	for i in skin.get_bind_count():
		var bn := String(skin.get_bind_name(i))
		if bn == "" and skin.get_bind_bone(i) >= 0:
			bn = sk.get_bone_name(skin.get_bind_bone(i))
		pos[bn] = skin.get_bind_pose(i).affine_inverse().origin
		bind_of[bn] = i
	for need in ["Hips", "Head", "LeftUpLeg", "RightUpLeg", "LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase", "LeftLeg", "RightLeg"]:
		if not pos.has(need):
			print("骨骼里没有 ", need, "，不修尾巴")
			return mesh
	var hips: Vector3 = pos["Hips"]
	var up: Vector3 = (pos["Head"] - hips).normalized()
	var H: float = (pos["Head"] - (pos["LeftFoot"] + pos["RightFoot"]) * 0.5).length() * 1.1
	var fwd: Vector3 = ((pos["LeftToeBase"] + pos["RightToeBase"]) - (pos["LeftFoot"] + pos["RightFoot"])) * 0.5
	fwd = (fwd - up * fwd.dot(up)).normalized()
	var back := -fwd
	var legs := []
	for s in ["Left", "Right"]:
		legs.append([pos[s + "UpLeg"], pos[s + "Leg"]])
		legs.append([pos[s + "Leg"], pos[s + "Foot"]])
		legs.append([pos[s + "Foot"], pos[s + "ToeBase"]])
	var hips_bind: int = bind_of["Hips"]
	var out := ImporterMesh.new()
	for si in mesh.get_surface_count():
		var arr: Array = mesh.get_surface_arrays(si)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		if bones.is_empty():
			out.add_surface(mesh.get_surface_primitive_type(si), arr, [], {}, mesh.get_surface_material(si), mesh.get_surface_name(si), mesh.get_surface_format(si))
			continue
		var per := bones.size() / verts.size()
		var n := verts.size()
		var bdist := PackedFloat32Array()
		var ldist := PackedFloat32Array()
		var hgt := PackedFloat32Array()
		bdist.resize(n)
		ldist.resize(n)
		hgt.resize(n)
		for i in n:
			var d := verts[i] - hips
			bdist[i] = d.dot(back) / H
			hgt[i] = d.dot(up) / H
			var m := INF
			for seg in legs:
				m = minf(m, _seg_dist(verts[i], seg[0], seg[1]))
			ldist[i] = m / H
		# 贴图颜色：朱厌的尾巴是白毛、手脚是红的——红的点不算尾巴（不然脚爪会被改绑到胯上、拉成长条）
		var red := PackedByteArray()
		red.resize(n)
		var mat := mesh.get_surface_material(si) as BaseMaterial3D
		var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		if mat and mat.albedo_texture and uvs.size() == n:
			var img := mat.albedo_texture.get_image()
			if img.is_compressed():
				img.decompress()
			var W := img.get_width()
			var Hh := img.get_height()
			for i in n:
				var c := img.get_pixel(clampi(int(fposmod(uvs[i].x, 1.0) * W), 0, W - 1), clampi(int(fposmod(uvs[i].y, 1.0) * Hh), 0, Hh - 1))
				red[i] = 1 if c.r > 0.25 and c.r > c.g * 1.5 and c.r > c.b * 1.5 else 0
		# 相邻关系
		var nb := {}
		for t in range(0, idx.size(), 3):
			for k in 3:
				var v0 := idx[t + k]
				for k2 in 3:
					if k2 != k:
						if not nb.has(v0):
							nb[v0] = []
						nb[v0].append(idx[t + k2])
		var tail := {}
		var q: Array = []
		for i in n:
			if bdist[i] > 0.1 and hgt[i] < 0.05 and ldist[i] > 0.06 and red[i] == 0:
				tail[i] = true
				q.append(i)
		while not q.is_empty():
			var v: int = q.pop_back()
			for w in nb.get(v, []):
				if tail.has(w):
					continue
				if bdist[w] > 0.035 and ldist[w] > 0.035 and hgt[w] < 0.1 and red[w] == 0:
					tail[w] = true
					q.append(w)
		for i in tail:
			for c in per:
				bones[i * per + c] = hips_bind if c == 0 else 0
				weights[i * per + c] = 1.0 if c == 0 else 0.0
		print("尾巴改绑到胯：", tail.size(), " / ", n, " 个点")
		arr[Mesh.ARRAY_BONES] = bones
		arr[Mesh.ARRAY_WEIGHTS] = weights
		out.add_surface(mesh.get_surface_primitive_type(si), arr, [], {}, mesh.get_surface_material(si), mesh.get_surface_name(si), mesh.get_surface_format(si))
	return out


func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
	return p.distance_to(a + ab * t)


var _done_tex := {}


func _shrink_textures(mat: Material, tex: int) -> void:
	if not mat is BaseMaterial3D:
		return
	var m := mat as BaseMaterial3D
	for p in ["albedo_texture", "normal_texture", "roughness_texture", "metallic_texture", "ao_texture", "emission_texture", "orm_texture"]:
		if not p in m:
			continue
		var t: Texture2D = m.get(p)
		if t == null:
			continue
		if _done_tex.has(t):
			m.set(p, _done_tex[t])
			continue
		var img := t.get_image()
		if img == null:
			continue
		if img.is_compressed():
			img.decompress()
		if maxi(img.get_width(), img.get_height()) > tex:
			var k := float(tex) / maxi(img.get_width(), img.get_height())
			img.resize(int(img.get_width() * k), int(img.get_height() * k), Image.INTERPOLATE_LANCZOS)
		var nt := ImageTexture.create_from_image(img)
		_done_tex[t] = nt
		m.set(p, nt)
