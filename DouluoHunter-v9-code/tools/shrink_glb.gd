extends SceneTree
## 把 AI 生成的大 GLB（几十万面、2K/4K 贴图）压小，方便 GitHub 网页上传、游戏里也不卡。
## 减面用 Godot 自带的 LOD 生成（ImporterMesh.generate_lods），贴图缩到指定尺寸、存成 JPEG。
## 用法：godot --headless --path <任意空项目> --script shrink_glb.gd -- 输入.glb 输出.glb [目标三角面数=100000] [贴图边长=1024]


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 2:
		print("用法：-- in.glb out.glb [tris] [tex]")
		quit(1)
		return
	var target := int(a[2]) if a.size() > 2 else 100000
	var tex := int(a[3]) if a.size() > 3 else 1024
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(a[0], st) != OK:
		print("读不了 ", a[0])
		quit(1)
		return
	var root := doc.generate_scene(st)
	var total := 0
	for n in root.find_children("*", "", true, false):
		if n is ImporterMeshInstance3D:
			total += _tris_importer((n as ImporterMeshInstance3D).mesh)
		elif n is MeshInstance3D and (n as MeshInstance3D).mesh:
			total += _tris_array((n as MeshInstance3D).mesh)
	var ratio := clampf(float(target) / maxf(total, 1.0), 0.02, 1.0)
	print("原来 ", total, " 面，目标 ", target, "（", snappedf(ratio, 0.001), "）")
	var after := 0
	for n in root.find_children("*", "", true, false):
		if n is ImporterMeshInstance3D:
			var imi := n as ImporterMeshInstance3D
			imi.mesh = _simplify(imi.mesh, ratio, tex)
			after += _tris_importer(imi.mesh)
		elif n is MeshInstance3D and (n as MeshInstance3D).mesh:
			var mi := n as MeshInstance3D
			var im := ImporterMesh.new()
			var am := mi.mesh as ArrayMesh
			for i in am.get_surface_count():
				im.add_surface(am.surface_get_primitive_type(i), am.surface_get_arrays(i), [], {}, am.surface_get_material(i), am.surface_get_name(i), am.surface_get_format(i))
			im = _simplify(im, ratio, tex)
			mi.mesh = im.get_mesh()
			after += _tris_importer(im)
	print("减到 ", after, " 面")
	var out := GLTFDocument.new()
	out.image_format = "JPEG"
	out.lossy_quality = 0.85
	var st2 := GLTFState.new()
	if out.append_from_scene(root, st2) != OK or out.write_to_filesystem(st2, a[1]) != OK:
		print("写不出 ", a[1])
		quit(1)
		return
	print("写好了 ", a[1])
	quit(0)


func _tris_importer(m: ImporterMesh) -> int:
	var t := 0
	for i in m.get_surface_count():
		var arr: Array = m.get_surface_arrays(i)
		var idx: Variant = arr[Mesh.ARRAY_INDEX]
		t += (idx.size() if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return t


func _tris_array(m: Mesh) -> int:
	var t := 0
	for i in m.get_surface_count():
		var arr: Array = m.surface_get_arrays(i)
		var idx: Variant = arr[Mesh.ARRAY_INDEX]
		t += (idx.size() if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return t


## 用 LOD 生成器算出一套更少的三角形，再把没用到的顶点删掉（不然文件还是一样大）
func _simplify(src: ImporterMesh, ratio: float, tex: int) -> ImporterMesh:
	var dst := ImporterMesh.new()
	src.generate_lods(25.0, 60.0, [])
	for i in src.get_surface_count():
		var arr: Array = src.get_surface_arrays(i)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()))
		var want := int(idx.size() * ratio)
		var best := idx
		for l in src.get_surface_lod_count(i):
			var li := src.get_surface_lod_indices(i, l)
			best = li
			if li.size() <= want:
				break
		var mat := src.get_surface_material(i)
		_shrink_textures(mat, tex)
		dst.add_surface(src.get_surface_primitive_type(i), _compact(arr, best), [], {}, mat, src.get_surface_name(i), src.get_surface_format(i))
	return dst


func _compact(arr: Array, idx: PackedInt32Array) -> Array:
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n := verts.size()
	var remap := PackedInt32Array()
	remap.resize(n)
	remap.fill(-1)
	var order := PackedInt32Array()
	var new_idx := PackedInt32Array()
	new_idx.resize(idx.size())
	for k in idx.size():
		var v := idx[k]
		if remap[v] < 0:
			remap[v] = order.size()
			order.append(v)
		new_idx[k] = remap[v]
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for t in Mesh.ARRAY_MAX:
		var src: Variant = arr[t]
		if src == null or t == Mesh.ARRAY_INDEX:
			continue
		var per := 1
		var s: int = src.size()
		if s != n and n > 0 and s % n == 0:
			per = s / n
		var dst: Variant = src.duplicate()
		dst.resize(order.size() * per)
		for j in order.size():
			for c in per:
				dst[j * per + c] = src[order[j] * per + c]
		out[t] = dst
	out[Mesh.ARRAY_INDEX] = new_idx
	return out


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
		if img.get_width() > tex or img.get_height() > tex:
			var k := float(tex) / maxf(img.get_width(), img.get_height())
			img.resize(maxi(int(img.get_width() * k), 1), maxi(int(img.get_height() * k), 1), Image.INTERPOLATE_LANCZOS)
		var nt := ImageTexture.create_from_image(img)
		_done_tex[t] = nt
		m.set(p, nt)
