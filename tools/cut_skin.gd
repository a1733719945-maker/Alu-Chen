extends SceneTree
## 把 AI 模型里"皮肤颜色"的三角形删掉（寒梅袖箭的模型带了一截光胳膊，第一人称里和我们的手套、袖子叠在一起很怪）。
## 按三角形三个顶点 UV 在颜色贴图上取色：像皮肤（偏暖、不太饱和、够亮）的就删。金色（蓝很少）、皮带（暗）不会被当成皮肤。
##   godot --headless --path game --script ../tools/cut_skin.gd -- 输入.glb 输出.glb


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 2:
		print("用法：-- in.glb out.glb")
		quit(1)
		return
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(a[0], st) != OK:
		print("读不了 ", a[0])
		quit(1)
		return
	var root := doc.generate_scene(st)
	var cut := 0
	var total := 0
	for n in root.find_children("*", "", true, false):
		var im: ImporterMesh = null
		if n is ImporterMeshInstance3D:
			im = (n as ImporterMeshInstance3D).mesh
		elif n is MeshInstance3D and (n as MeshInstance3D).mesh is ArrayMesh:
			# generate_scene 出来的是普通 MeshInstance3D：转成 ImporterMesh 处理完再转回去
			var am := (n as MeshInstance3D).mesh as ArrayMesh
			im = ImporterMesh.new()
			for i in am.get_surface_count():
				im.add_surface(am.surface_get_primitive_type(i), am.surface_get_arrays(i), [], {}, am.surface_get_material(i), am.surface_get_name(i), am.surface_get_format(i))
		if im == null:
			continue
		var out := ImporterMesh.new()
		for s in im.get_surface_count():
			var arr: Array = im.get_surface_arrays(s)
			var mat := im.get_surface_material(s) as BaseMaterial3D
			var img: Image = null
			if mat and mat.albedo_texture:
				img = mat.albedo_texture.get_image()
				if img and img.is_compressed():
					img.decompress()
			var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var keep := PackedInt32Array()
			for t in range(0, idx.size(), 3):
				total += 1
				var skin := 0
				if img and not uvs.is_empty():
					for k in 3:
						if _is_skin(_px(img, uvs[idx[t + k]])):
							skin += 1
				if skin >= 2:
					cut += 1
					continue
				keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
			arr[Mesh.ARRAY_INDEX] = keep
			out.add_surface(im.get_surface_primitive_type(s), arr, [], {}, im.get_surface_material(s), im.get_surface_name(s), im.get_surface_format(s))
		if n is ImporterMeshInstance3D:
			(n as ImporterMeshInstance3D).mesh = out
		else:
			(n as MeshInstance3D).mesh = out.get_mesh()
	print("删掉 ", cut, " / ", total, " 个三角形（皮肤）")
	var d2 := GLTFDocument.new()
	d2.image_format = "JPEG"
	d2.lossy_quality = 0.88
	var st2 := GLTFState.new()
	if d2.append_from_scene(root, st2) != OK or d2.write_to_filesystem(st2, a[1]) != OK:
		print("写不出 ", a[1])
		quit(1)
		return
	print("写好了 ", a[1])
	quit(0)


func _px(img: Image, uv: Vector2) -> Color:
	var w := img.get_width()
	var h := img.get_height()
	return img.get_pixel(clampi(int(fposmod(uv.x, 1.0) * w), 0, w - 1), clampi(int(fposmod(uv.y, 1.0) * h), 0, h - 1))


## 皮肤：色相在橙色一带、饱和度中等（金色更饱和）、够亮（皮带更暗）；背光的皮肤色相不变，所以按色相判断
func _is_skin(c: Color) -> bool:
	return c.h > 0.015 and c.h < 0.11 and c.s > 0.12 and c.s < 0.5 and c.v > 0.42
