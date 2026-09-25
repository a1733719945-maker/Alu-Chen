class_name U
extends RefCounted
## 小工具：材质缓存、常用网格。

const LAYER_WORLD := 1        # 地形、树、石头
const LAYER_BEAST := 2        # 魂兽
const LAYER_PLAYER := 4       # 本地玩家

static var _mats := {}


## 纯色材质（按颜色缓存，同色共用一个）
static func mat(color: Color, rough := 0.85, emission := 0.0, metallic := 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%.2f" % [color.to_html(), rough, emission, metallic]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metallic
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	_mats[key] = m
	return m


## 发光且不受光照的材质（弹道、魂环、特效）
static func glow(color: Color, energy := 2.0, transparent := false) -> StandardMaterial3D:
	var key := "glow|%s|%.2f|%s" % [color.to_html(), energy, transparent]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


## 加一个网格节点
static func part(parent: Node3D, mesh: Mesh, material: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func sphere(r := 0.5, segs := 12, rings := 8) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = segs
	m.rings = rings
	return m


static func box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func cyl(r_top: float, r_bottom: float, h: float, segs := 10) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bottom
	m.height = h
	m.radial_segments = segs
	m.rings = 1
	return m


static func capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 12
	m.rings = 4
	return m


static func torus(inner: float, outer: float, ring_segs := 48, segs := 8) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = ring_segs
	m.ring_segments = segs
	return m


static func label3d(text: String, size := 48, color := Color.WHITE, outline := 10) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = Data.font_ui
	l.font_size = size
	l.outline_size = outline
	l.modulate = color
	l.outline_modulate = Color(0, 0, 0, 0.75)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.pixel_size = 0.004
	l.double_sided = true
	return l


## 帧率无关的平滑：rate 越大越快追上
static func damp(from: float, to: float, rate: float, dt: float) -> float:
	return lerpf(from, to, 1.0 - exp(-rate * dt))


static func damp_v3(from: Vector3, to: Vector3, rate: float, dt: float) -> Vector3:
	return from.lerp(to, 1.0 - exp(-rate * dt))
