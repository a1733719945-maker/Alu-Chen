extends SceneTree
## 模型预览：GLB / FBX 从正面、侧面、斜后方三个角度渲染，拼成一张 PNG（检查朝向、大小、贴图、面数）
##   godot --path game --position 2500,0 --script ../tools/preview_model.gd -- 模型.glb 输出.png [动作名]
## 要开窗口渲染（不能 --headless）；窗口放到屏幕外，不打扰用户。动作名给了就停在那段动作的中间一帧

const W := 640
const H := 720


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 2:
		print("用法：-- model.glb out.png [anim]")
		quit(1)
		return
	var model := _load(a[0])
	if model == null:
		quit(1)
		return
	var anim := a[2] if a.size() > 2 else ""
	_run.call_deferred(model, a[1], anim)


func _load(path: String) -> Node3D:
	var n: Node
	if path.get_extension().to_lower() == "fbx":
		var d := FBXDocument.new()
		var s := FBXState.new()
		if d.append_from_file(path, s) != OK:
			print("读不了 ", path)
			return null
		n = d.generate_scene(s)
	else:
		var d2 := GLTFDocument.new()
		var s2 := GLTFState.new()
		if d2.append_from_file(path, s2) != OK:
			print("读不了 ", path)
			return null
		n = d2.generate_scene(s2)
	var holder := Node3D.new()
	holder.add_child(n)
	return holder


func _run(model: Node3D, out: String, anim: String) -> void:
	var tris := 0
	var box := AABB()
	var first := true
	for mi: Node in model.find_children("*", "", true, false):
		var mesh: Mesh = null
		if mi is MeshInstance3D:
			mesh = (mi as MeshInstance3D).mesh
		elif mi is ImporterMeshInstance3D:
			mesh = (mi as ImporterMeshInstance3D).mesh.get_mesh()
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(i)
			tris += ((arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() if arr[Mesh.ARRAY_INDEX] != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		var bb := _xf(model, mi as Node3D) * mesh.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	var anims := PackedStringArray()
	for ap: AnimationPlayer in model.find_children("*", "AnimationPlayer", true, false):
		anims = ap.get_animation_list()
		if anim != "" and ap.has_animation(anim):
			ap.play(anim)
			ap.seek(ap.get_animation(anim).length * 0.5, true)
			ap.pause()
	var skels := model.find_children("*", "Skeleton3D", true, false)
	var bones := PackedStringArray()
	if skels.size() > 0:
		var sk := skels[0] as Skeleton3D
		for b in sk.get_bone_count():
			bones.append(sk.get_bone_name(b))
	print("面数 ", tris, "  尺寸 ", box.size, "  中心 ", box.get_center())
	print("动作 ", anims)
	print("骨头 ", bones.size(), " 根：", ", ".join(bones.slice(0, 60)))
	var sheet := Image.create(W * 3, H, false, Image.FORMAT_RGB8)
	var angles := [0.0, 90.0, 215.0]
	for i in 3:
		var vp := SubViewport.new()
		vp.size = Vector2i(W, H)
		vp.own_world_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.msaa_3d = Viewport.MSAA_4X
		root.add_child(vp)
		var env := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.32, 0.34, 0.38)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.75, 0.75, 0.8)
		e.ambient_light_energy = 0.6
		e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.environment = e
		vp.add_child(env)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-40, 30, 0)
		sun.light_energy = 1.6
		vp.add_child(sun)
		var fill := DirectionalLight3D.new()
		fill.rotation_degrees = Vector3(-20, 200, 0)
		fill.light_energy = 0.5
		vp.add_child(fill)
		var m: Node3D = model if i == 0 else model.duplicate()
		vp.add_child(m)
		var cam := Camera3D.new()
		vp.add_child(cam)
		var c := box.get_center()
		var r := box.size.length() * 0.5
		var ang := deg_to_rad(float(angles[i]))
		var dist := r / tan(deg_to_rad(25.0)) * 1.05
		cam.fov = 50.0
		cam.near = maxf(dist * 0.01, 0.01)
		cam.far = dist * 10.0
		cam.position = c + Vector3(sin(ang), 0.25, cos(ang)).normalized() * dist
		cam.look_at(c, Vector3.UP)
	for f in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var k := 0
	for vp: SubViewport in root.find_children("*", "SubViewport", false, false):
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(img, Rect2i(0, 0, W, H), Vector2i(k * W, 0))
		k += 1
	sheet.save_png(out)
	print("写好了 ", out)
	quit(0)


func _xf(root: Node, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
