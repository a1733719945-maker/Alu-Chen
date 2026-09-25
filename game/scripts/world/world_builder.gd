class_name WorldBuilder
extends RefCounted
## 把 Island 的数据搭成看得见、碰得到的场景：地形、湖水、树、草、兔子洞、花丛、码头。

const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")
const WATER_SHADER := preload("res://shaders/water.gdshader")
const GRASS_SHADER := preload("res://shaders/grass.gdshader")

var island: Island
var root: Node3D
var rng := RandomNumberGenerator.new()
var colliders: StaticBody3D
var ambient_birds: Array[Node3D] = []
var ambient_moths: Array[Node3D] = []


func _init(p_island: Island, p_root: Node3D) -> void:
	island = p_island
	root = p_root
	rng.seed = Island.SEED + 100


func build() -> void:
	colliders = StaticBody3D.new()
	colliders.name = "Props"
	colliders.collision_layer = U.LAYER_WORLD
	colliders.collision_mask = 0
	root.add_child(colliders)
	_environment()
	_terrain()
	_water()
	_mountains()
	_trees()
	_rocks()
	_grass()
	_burrows()
	_flowers()
	_reeds()
	_dock_and_shop()
	_signs()
	_ambient_life()


# ------------------------------------------------------------------ 天空与光照

func _environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.28, 0.52, 0.82)
	sky_mat.sky_horizon_color = Color(0.78, 0.84, 0.86)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_bottom_color = Color(0.16, 0.22, 0.26)
	sky_mat.ground_horizon_color = Color(0.72, 0.8, 0.82)
	sky_mat.sun_angle_max = 24.0
	sky_mat.sun_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 0.9
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.8, 0.88)
	env.fog_density = 0.0022
	env.fog_aerial_perspective = 0.55
	env.fog_sky_affect = 0.15
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-36, -38, 0)
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 140.0
	root.add_child(sun)


# ------------------------------------------------------------------ 地形

func _terrain_color(x: float, z: float, h: float, slope: float) -> Color:
	var n := sin(x * 0.07 + z * 0.05) * 0.5 + sin(x * 0.19 - z * 0.13) * 0.5
	var grass := Color(0.33, 0.55, 0.22).lerp(Color(0.44, 0.62, 0.25), n * 0.5 + 0.5)
	var c := grass
	if h < -0.3:
		c = Color(0.55, 0.52, 0.4)
	elif h < 1.0:
		c = Color(0.86, 0.79, 0.58).lerp(grass, smoothstep(0.55, 1.0, h))
	var p2 := Vector2(x, z)
	for hb in island.habitats:
		var d := p2.distance_to(hb["center"])
		var k := smoothstep(hb["radius"] + 4.0, hb["radius"] - 4.0, d)
		if k <= 0.0:
			continue
		match hb["type"]:
			"meadow":
				c = c.lerp(Color(0.56, 0.66, 0.28), k * 0.8)
			"flowers":
				c = c.lerp(Color(0.34, 0.5, 0.36), k * 0.8)
			"burrow":
				c = c.lerp(Color(0.46, 0.5, 0.24), k * 0.6)
				for b in hb["points"]:
					var db := p2.distance_to(Vector2(b.x, b.z))
					c = c.lerp(Color(0.44, 0.33, 0.2), smoothstep(3.2, 1.2, db))
	if slope > 0.55:
		c = c.lerp(Color(0.5, 0.49, 0.45), smoothstep(0.55, 0.95, slope))
	if h > 9.0:
		c = c.lerp(Color(0.55, 0.54, 0.5), smoothstep(9.0, 13.0, h) * 0.7)
	return c


func _terrain() -> void:
	var S := Island.SIZE
	var H := Island.HALF
	var hts := island.heights
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(S * S)
	norms.resize(S * S)
	cols.resize(S * S)
	for j in S:
		for i in S:
			var idx := i + j * S
			var h := hts[idx]
			var x := float(i - H)
			var z := float(j - H)
			var hl := hts[idx - 1] if i > 0 else h
			var hr := hts[idx + 1] if i < S - 1 else h
			var hu := hts[idx - S] if j > 0 else h
			var hd := hts[idx + S] if j < S - 1 else h
			verts[idx] = Vector3(x, h, z)
			norms[idx] = Vector3(hl - hr, 2.0, hu - hd).normalized()
			cols[idx] = _terrain_color(x, z, h, Vector2(hr - hl, hd - hu).length() * 0.5)
	var idxs := PackedInt32Array()
	idxs.resize((S - 1) * (S - 1) * 6)
	var k := 0
	for j in S - 1:
		for i in S - 1:
			var a := i + j * S
			var b := a + 1
			var c := a + S
			var d := c + 1
			# 交替切分方向，切面不会全朝一个方向
			if (i + j) % 2 == 0:
				idxs[k] = a; idxs[k + 1] = b; idxs[k + 2] = d
				idxs[k + 3] = a; idxs[k + 4] = d; idxs[k + 5] = c
			else:
				idxs[k] = a; idxs[k + 1] = b; idxs[k + 2] = c
				idxs[k + 3] = b; idxs[k + 4] = d; idxs[k + 5] = c
			k += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idxs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var sm := ShaderMaterial.new()
	sm.shader = TERRAIN_SHADER
	var mi := MeshInstance3D.new()
	mi.name = "TerrainMesh"
	mi.mesh = mesh
	mi.material_override = sm
	root.add_child(mi)

	var body := StaticBody3D.new()
	body.name = "Terrain"
	body.collision_layer = U.LAYER_WORLD
	body.collision_mask = 0
	var shape := HeightMapShape3D.new()
	shape.map_width = S
	shape.map_depth = S
	shape.map_data = hts
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	root.add_child(body)


func _water() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(1600, 1600)
	pm.subdivide_width = 180
	pm.subdivide_depth = 180
	var sm := ShaderMaterial.new()
	sm.shader = WATER_SHADER
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = pm
	mi.material_override = sm
	mi.position.y = Island.WATER_Y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	# 岛外的湖底，免得透过水看到空
	var floor_mi := MeshInstance3D.new()
	var fp := PlaneMesh.new()
	fp.size = Vector2(1600, 1600)
	floor_mi.mesh = fp
	floor_mi.material_override = U.mat(Color(0.3, 0.33, 0.26))
	floor_mi.position.y = -12.5
	root.add_child(floor_mi)


func _mountains() -> void:
	var mat := U.mat(Color(0.3, 0.42, 0.36))
	var snow := U.mat(Color(0.86, 0.9, 0.92))
	for i in 34:
		var a := TAU * i / 34.0 + rng.randf_range(-0.08, 0.08)
		var d := rng.randf_range(430.0, 640.0)
		var h := rng.randf_range(55.0, 170.0)
		var r := h * rng.randf_range(0.9, 1.4)
		var m := U.part(root, U.cyl(0.0, r, h, rng.randi_range(5, 8)), mat,
			Vector3(cos(a) * d, h * 0.5 - 12.0, sin(a) * d), Vector3(0, rng.randf() * TAU, 0), Vector3.ONE, false)
		if h > 120.0:
			U.part(m, U.cyl(0.0, r * 0.28, h * 0.28, 6), snow, Vector3(0, h * 0.36 + 0.5, 0), Vector3.ZERO, Vector3.ONE, false)


# ------------------------------------------------------------------ 植被

func _avoid(x: float, z: float, margin: float) -> bool:
	var p := Vector2(x, z)
	for hb in island.habitats:
		if p.distance_to(hb["center"]) < hb["radius"] + margin:
			return true
	if p.distance_to(Vector2(island.spawn.x, island.spawn.z)) < 16.0:
		return true
	if p.distance_to(Vector2(island.shop_pos.x, island.shop_pos.z)) < 10.0:
		return true
	if absf(x - island.dock_start.x) < 5.0 and z > island.dock_start.z - 14.0:
		return true
	return false


func _multimesh(mesh: Mesh, material: Material, xforms: Array, colors := [], shadows := true) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors.size() > 0
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)
	return mmi


func _trees() -> void:
	var trunks := []
	var pines := []
	var pine2 := []
	var rounds := []
	var round_cols := []
	var tries := 0
	while trunks.size() < 230 and tries < 6000:
		tries += 1
		var x := rng.randf_range(-130, 130)
		var z := rng.randf_range(-130, 130)
		var h := island.height_at(x, z)
		if h < 1.3 or island.slope_at(x, z) > 0.8 or _avoid(x, z, 5.0):
			continue
		var s := rng.randf_range(0.8, 1.5)
		var base := Vector3(x, h - 0.2, z)
		var yaw := rng.randf() * TAU
		trunks.append(Transform3D(Basis.from_euler(Vector3(0, yaw, 0)).scaled(Vector3(s, s, s)), base + Vector3(0, 1.6 * s, 0)))
		if rng.randf() < 0.55:
			pines.append(Transform3D(Basis.from_euler(Vector3(0, yaw, 0)).scaled(Vector3(s, s, s)), base + Vector3(0, 4.2 * s, 0)))
			pine2.append(Transform3D(Basis.from_euler(Vector3(0, yaw + 0.5, 0)).scaled(Vector3(s * 0.75, s * 0.8, s * 0.75)), base + Vector3(0, 6.2 * s, 0)))
		else:
			rounds.append(Transform3D(Basis.from_euler(Vector3(rng.randf() * 0.3, yaw, 0)).scaled(Vector3(s, s * 0.9, s)), base + Vector3(0, 4.6 * s, 0)))
			round_cols.append(Color(0.3, 0.52, 0.2).lerp(Color(0.5, 0.64, 0.22), rng.randf()))
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 0.32 * s
		shape.height = 5.0 * s
		cs.shape = shape
		cs.position = base + Vector3(0, 2.5 * s, 0)
		colliders.add_child(cs)
	_multimesh(U.cyl(0.18, 0.3, 3.2, 6), U.mat(Color(0.42, 0.3, 0.2)), trunks)
	_multimesh(U.cyl(0.0, 2.1, 4.2, 7), U.mat(Color(0.2, 0.42, 0.26)), pines)
	_multimesh(U.cyl(0.0, 1.5, 3.2, 7), U.mat(Color(0.24, 0.48, 0.28)), pine2)
	var leaf := StandardMaterial3D.new()
	leaf.vertex_color_use_as_albedo = true
	leaf.vertex_color_is_srgb = true
	leaf.roughness = 0.9
	_multimesh(U.sphere(2.3, 7, 5), leaf, rounds, round_cols)


func _rocks() -> void:
	var xs := []
	var cols := []
	for i in 70:
		var x := rng.randf_range(-125, 125)
		var z := rng.randf_range(-125, 125)
		var h := island.height_at(x, z)
		if h < -1.5 or _avoid(x, z, 2.0):
			continue
		var s := rng.randf_range(0.4, 1.8)
		var b := Basis.from_euler(Vector3(rng.randf() * 0.6, rng.randf() * TAU, rng.randf() * 0.6)).scaled(Vector3(s * rng.randf_range(1.0, 1.8), s * rng.randf_range(0.6, 1.1), s))
		xs.append(Transform3D(b, Vector3(x, h, z)))
		cols.append(Color(0.52, 0.52, 0.5).lerp(Color(0.62, 0.6, 0.55), rng.randf()))
		if s > 1.0:
			var cs := CollisionShape3D.new()
			var sh := SphereShape3D.new()
			sh.radius = s * 0.9
			cs.shape = sh
			cs.position = Vector3(x, h, z)
			colliders.add_child(cs)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.95
	_multimesh(U.sphere(1.0, 6, 4), m, xs, cols)


func _blade_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var a := k * PI / 3.0
		var side := Vector3(cos(a), 0, sin(a)) * 0.045
		var off := Vector3(-sin(a), 0, cos(a)) * 0.04 * (k - 1)
		st.set_normal(Vector3.UP)
		st.add_vertex(-side + off)
		st.add_vertex(side + off)
		st.add_vertex(Vector3(0, 0.42, 0) + off * 2.0)
	return st.commit()


func _grass() -> void:
	var xs := []
	var cols := []
	var mesh := _blade_mesh()
	var tries := 0
	while xs.size() < 70000 and tries < 200000:
		tries += 1
		var x := rng.randf_range(-128, 128)
		var z := rng.randf_range(-128, 128)
		var h := island.height_at(x, z)
		if h < 1.05 or island.slope_at(x, z) > 0.7:
			continue
		var s := rng.randf_range(0.55, 1.15)
		var in_meadow: bool = Vector2(x, z).distance_to(island.habitat("meadow")["center"]) < island.habitat("meadow")["radius"]
		if in_meadow:
			s *= 1.45
		xs.append(Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.2, 0.2), rng.randf() * TAU, 0)).scaled(Vector3(s, s, s)), Vector3(x, h - 0.03, z)))
		var c := Color(1, 1, 1).lerp(Color(0.8, 0.95, 0.7), rng.randf())
		if in_meadow:
			c = Color(1.1, 1.05, 0.7)
		cols.append(c)
	var sm := ShaderMaterial.new()
	sm.shader = GRASS_SHADER
	_multimesh(mesh, sm, xs, cols, false)


func _burrows() -> void:
	var dirt := U.mat(Color(0.45, 0.33, 0.2))
	var hole := U.mat(Color(0.05, 0.03, 0.02))
	var hb := island.habitat("burrow")
	for b in hb["points"]:
		var base: Vector3 = b
		U.part(root, U.sphere(1.0, 10, 6), dirt, base + Vector3(0, -0.15, 0), Vector3.ZERO, Vector3(1.5, 0.55, 1.5))
		U.part(root, U.cyl(0.45, 0.45, 0.06, 12), hole, base + Vector3(0, 0.39, 0))


func _flowers() -> void:
	var hb := island.habitat("flowers")
	var c: Vector2 = hb["center"]
	var xs := []
	var cols := []
	var stems := []
	for i in 700:
		var a := rng.randf() * TAU
		var d: float = sqrt(rng.randf()) * hb["radius"]
		var x: float = c.x + cos(a) * d
		var z: float = c.y + sin(a) * d
		var h := island.height_at(x, z)
		var s := rng.randf_range(0.7, 1.3)
		stems.append(Transform3D(Basis().scaled(Vector3(s, s, s)), Vector3(x, h + 0.2 * s, z)))
		xs.append(Transform3D(Basis().scaled(Vector3(s, s * 0.6, s)), Vector3(x, h + 0.42 * s, z)))
		var pal := [Color(0.95, 0.95, 1.0), Color(0.8, 0.75, 1.0), Color(0.7, 0.88, 1.0), Color(1.0, 0.9, 0.97)]
		cols.append(pal[rng.randi() % pal.size()])
	_multimesh(U.cyl(0.012, 0.012, 0.4, 4), U.mat(Color(0.25, 0.45, 0.2)), stems, [], false)
	var fm := StandardMaterial3D.new()
	fm.vertex_color_use_as_albedo = true
	fm.vertex_color_is_srgb = true
	fm.emission_enabled = true
	fm.emission = Color(0.55, 0.55, 0.8)
	fm.emission_energy_multiplier = 0.35
	_multimesh(U.sphere(0.09, 6, 3), fm, xs, cols, false)


func _reeds() -> void:
	var xs := []
	var tries := 0
	while xs.size() < 900 and tries < 30000:
		tries += 1
		var a := rng.randf() * TAU
		var r := rng.randf_range(80, 130)
		var x := cos(a) * r
		var z := sin(a) * r
		var h := island.height_at(x, z)
		if h > 0.5 or h < -0.9:
			continue
		if absf(x - island.dock_start.x) < 6.0 and z > 0:
			continue
		for k in 4:
			var o := Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))
			var s := rng.randf_range(0.7, 1.4)
			xs.append(Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15))).scaled(Vector3(1, s, 1)), Vector3(x, h + 0.8 * s, z) + o))
	_multimesh(U.cyl(0.02, 0.035, 1.6, 4), U.mat(Color(0.5, 0.58, 0.3)), xs, [], false)


# ------------------------------------------------------------------ 码头、暗器铺、路牌

func _dock_and_shop() -> void:
	var wood := U.mat(Color(0.52, 0.38, 0.24))
	var dark := U.mat(Color(0.36, 0.25, 0.16))
	var a := island.dock_start
	var b := island.dock_end
	var len := a.distance_to(Vector3(b.x, a.y, b.z))
	var mid := (a + Vector3(b.x, b.y, b.z)) * 0.5
	mid.y = maxf(a.y, 0.5)
	var dock := U.part(root, U.box(Vector3(3.2, 0.25, len)), wood, mid)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(3.2, 0.25, len)
	cs.shape = sh
	cs.position = mid
	colliders.add_child(cs)
	for k in int(len / 3.0) + 1:
		for side in [-1.4, 1.4]:
			var p := Vector3(a.x + side, mid.y - 1.5, a.z + k * 3.0)
			U.part(root, U.cyl(0.13, 0.13, 3.4, 6), dark, p)
	dock.name = "Dock"

	# 暗器铺（下个版本开张）
	var s := island.shop_pos
	var hut := Node3D.new()
	hut.position = s
	hut.rotation.y = 0.35
	root.add_child(hut)
	U.part(hut, U.box(Vector3(6.0, 3.0, 4.6)), U.mat(Color(0.72, 0.6, 0.44)), Vector3(0, 1.5, 0))
	var roof := PrismMesh.new()
	roof.size = Vector3(7.0, 1.8, 5.6)
	U.part(hut, roof, U.mat(Color(0.55, 0.2, 0.16)), Vector3(0, 3.9, 0))
	U.part(hut, U.box(Vector3(1.2, 2.0, 0.1)), dark, Vector3(0, 1.0, 2.31))
	var sign := U.label3d("唐门 · 暗器铺", 72, Color(1.0, 0.86, 0.5))
	sign.position = Vector3(0, 3.3, 2.7)
	sign.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sign.pixel_size = 0.006
	hut.add_child(sign)
	var sub := U.label3d("下个版本开张", 40, Color(0.9, 0.9, 0.85))
	sub.position = Vector3(0, 2.75, 2.7)
	sub.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	hut.add_child(sub)
	var hcs := CollisionShape3D.new()
	var hsh := BoxShape3D.new()
	hsh.size = Vector3(6.0, 4.5, 4.6)
	hcs.shape = hsh
	hcs.transform = hut.transform * Transform3D(Basis(), Vector3(0, 2.2, 0))
	colliders.add_child(hcs)
	# 灯笼
	for side in [-2.4, 2.4]:
		var lp := hut.transform * Vector3(side, 2.6, 2.5)
		U.part(root, U.sphere(0.22, 8, 6), U.glow(Color(1.0, 0.55, 0.25), 3.0), lp)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.6, 0.3)
		light.light_energy = 1.2
		light.omni_range = 7.0
		light.position = lp
		root.add_child(light)


func _sign(pos: Vector2, title: String, sub: String, color: Color) -> void:
	var h := island.height_at(pos.x, pos.y)
	var wood := U.mat(Color(0.5, 0.36, 0.22))
	U.part(root, U.cyl(0.07, 0.07, 2.2, 6), wood, Vector3(pos.x, h + 1.1, pos.y))
	var t := U.label3d(title, 64, color)
	t.pixel_size = 0.012
	t.position = Vector3(pos.x, h + 3.2, pos.y)
	root.add_child(t)
	var s := U.label3d(sub, 36, Color(0.92, 0.92, 0.88))
	s.pixel_size = 0.01
	s.position = Vector3(pos.x, h + 2.45, pos.y)
	root.add_child(s)


func _signs() -> void:
	var m := island.habitat("meadow")
	var b := island.habitat("burrow")
	var f := island.habitat("flowers")
	_sign(m["center"] + Vector2(0, m["radius"] + 2.0), "风铃草原", "把引魂索抛到草原上 · 风铃鸟", Color(0.6, 0.95, 0.85))
	_sign(b["center"] + Vector2(-b["radius"] - 1.0, 4.0), "兔子洞", "抛到洞口附近 · 柔骨兔", Color(1.0, 0.8, 0.85))
	_sign(f["center"] + Vector2(f["radius"] + 1.5, 3.0), "月光花丛", "抛进花丛 · 月光蛾", Color(0.85, 0.85, 1.0))
	_sign(Vector2(island.dock_start.x - 3.5, island.dock_start.z - 2.0), "湖水", "抛进水里 · 鬼藤", Color(0.55, 0.85, 1.0))


# ------------------------------------------------------------------ 装饰用的鸟和蛾子（不能打，只是让草原热闹点）

func _ambient_life() -> void:
	var m := island.habitat("meadow")
	for i in 4:
		var bird := BeastModels.build("bird", 0)
		bird.scale = Vector3.ONE * 0.8
		bird.set_meta("orbit", Vector4(m["center"].x, m["center"].y, rng.randf_range(10, 20), rng.randf_range(0.25, 0.45)))
		bird.set_meta("phase", rng.randf() * TAU)
		bird.set_meta("height", island.height_at(m["center"].x, m["center"].y) + rng.randf_range(14, 22))
		root.add_child(bird)
		ambient_birds.append(bird)
	var f := island.habitat("flowers")
	for i in 3:
		var moth := BeastModels.build("moth", 0)
		moth.scale = Vector3.ONE * 0.6
		moth.set_meta("orbit", Vector4(f["center"].x, f["center"].y, rng.randf_range(3, 8), rng.randf_range(0.3, 0.6)))
		moth.set_meta("phase", rng.randf() * TAU)
		moth.set_meta("height", island.height_at(f["center"].x, f["center"].y) + rng.randf_range(1.5, 3.5))
		root.add_child(moth)
		ambient_moths.append(moth)


func animate(t: float) -> void:
	for n in ambient_birds + ambient_moths:
		var o: Vector4 = n.get_meta("orbit")
		var ph: float = n.get_meta("phase")
		var a := t * o.w + ph
		var p := Vector3(o.x + cos(a) * o.z, n.get_meta("height") + sin(t * 0.7 + ph) * 1.2, o.y + sin(a) * o.z)
		n.look_at_from_position(p, p + Vector3(-sin(a), 0, cos(a)), Vector3.UP)
		BeastModels.animate(n, t + ph, true)
