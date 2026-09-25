class_name WorldBuilder
extends RefCounted
## 把 Island 的数据搭成看得见、碰得到的场景。
##
## 第一章 湖心岛：晴天、草地、松树和阔叶树、兔子洞、月光花丛、码头、暗器铺小屋、北坡祭坛、乌篷船。
## 第二章 落日森林：黄昏、秋天的落叶林、狼穴、泥潭、毒沼、古树林和千年古树、商人帐篷。
## 第三章 星斗大森林：月夜、巨树、发光的蓝银草和蘑菇、魔蛛巢、蝠巢枯林、星斗古树。
## 第四章 极北之地：雪天、雪松、冰晶、冰湖浮冰、雪狼洞和冰窟、飘雪。
## 第五章 海神岛：正午、椰子树、金沙滩、浅海珊瑚、海崖。
##
## 素材全是 CC0 免费素材：天空 HDR 和植物、石头模型来自 Poly Haven，地面和树皮贴图来自 ambientCG。
## 树是程序生成的：树皮圆管做树干树枝，再插上几十张“一簇树叶”的贴片（tools/prepare_assets.py 生成）。
## 同一种东西用 MultiMesh 批量画，按 32~64 米分块，看不见的块整块跳过。

const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")
const WATER_SHADER := preload("res://shaders/water.gdshader")
const GRASS_SHADER := preload("res://shaders/grass.gdshader")
const FOLIAGE_SHADER := preload("res://shaders/foliage.gdshader")
const SNOW_OVERLAY := preload("res://shaders/snow_overlay.gdshader")
const GROUND := "res://assets/textures/ground/"
const FOLIAGE := "res://assets/textures/foliage/"
const MODELS := "res://assets/models/env/"

# 每张地图的天空和光。sky：天空 HDR；u / elev：HDR 里太阳（月亮）的位置（tools 里量出来的）；
# heading：把太阳转到哪个方向（999 = 不转）；light_elev：灯光的高度角（太阳贴地平线时抬高一点）
const ENV := {
	"island": {"sky": "sky_day", "u": 0.595, "elev": 48.0, "heading": 999.0, "light_elev": 48.0, "sun": Color(1.0, 0.95, 0.86), "energy": 1.25,
		"ambient": 0.7, "exposure": 0.95, "white": 6.0, "glow": 0.5, "bloom": 0.03, "fog": Color(0.68, 0.76, 0.86), "fog_d": 0.00095,
		"scatter": 0.12, "aerial": 0.45, "fog_sky": 0.1, "sat": 1.08, "contrast": 1.04},
	"forest": {"sky": "sky_dusk", "u": 0.613, "elev": 4.7, "heading": -70.0, "light_elev": 17.0, "sun": Color(1.0, 0.72, 0.45), "energy": 1.55,
		"ambient": 0.75, "exposure": 1.05, "white": 5.0, "glow": 0.7, "bloom": 0.08, "fog": Color(0.86, 0.66, 0.5), "fog_d": 0.006,
		"scatter": 0.35, "aerial": 0.5, "fog_sky": 0.25, "vol": 0.012, "vol_albedo": Color(1.0, 0.85, 0.7), "sat": 1.12, "contrast": 1.06},
	# 月夜：月光别太亮（用户反馈太亮、月亮从山前面透出来）——月光、曝光、辉光、月晕都压低，天空多被雾盖住
	"deepforest": {"sky": "sky_night", "u": 0.600, "elev": 13.8, "heading": -40.0, "light_elev": 28.0, "sun": Color(0.6, 0.72, 1.0), "energy": 0.42,
		"ambient": 0.6, "exposure": 1.0, "white": 4.0, "glow": 0.5, "bloom": 0.03, "fog": Color(0.08, 0.12, 0.2), "fog_d": 0.0045,
		"scatter": 0.04, "aerial": 0.3, "fog_sky": 0.85, "vol": 0.01, "vol_albedo": Color(0.6, 0.72, 1.0), "vol_e": 0.6, "sky_e": 0.55, "sat": 1.05, "contrast": 1.08},
	"snow": {"sky": "sky_snow", "u": 0.62, "elev": 16.6, "heading": 999.0, "light_elev": 32.0, "sun": Color(0.95, 0.97, 1.0), "energy": 1.0,
		"ambient": 0.95, "exposure": 0.85, "white": 6.0, "glow": 0.4, "bloom": 0.03, "fog": Color(0.82, 0.86, 0.92), "fog_d": 0.003,
		"scatter": 0.1, "aerial": 0.6, "fog_sky": 0.4, "sat": 1.0, "contrast": 1.05},
	"sea": {"sky": "sky_sea", "u": 0.600, "elev": 49.8, "heading": 999.0, "light_elev": 49.8, "sun": Color(1.0, 0.96, 0.88), "energy": 1.35,
		"ambient": 0.75, "exposure": 0.95, "white": 6.0, "glow": 0.5, "bloom": 0.03, "fog": Color(0.7, 0.82, 0.92), "fog_d": 0.0007,
		"scatter": 0.12, "aerial": 0.5, "fog_sky": 0.1, "sat": 1.12, "contrast": 1.04},
}

var island: Island
var root: Node3D
var chapter := 1
var forest := false                    # 森林类地图（四周环山）
var biome := "island"                  # 地图 id，决定天空、地面、树
var quality := 2
var rng := RandomNumberGenerator.new()
var colliders: StaticBody3D
var env: Environment
var sun: DirectionalLight3D
var shop_door := Vector3.ZERO
var boat_pos := Vector3.ZERO
var boat: Node3D

var _path := PackedFloat32Array()      # 每个地形格子到最近小路的距离
var _patch := FastNoiseLite.new()      # 地面斑块
var _warp := FastNoiseLite.new()       # 让小路弯弯曲曲
var _tex_cache := {}
var _prop_cache := {}
var _trunks: Array = []                # [Vector2 位置, 半径]：放灌木、石头时避开树干
var _trunk_grid := {}                  # 8 米一格，查附近的树干
var _birds: Array[Node3D] = []
var _moths: Array[Node3D] = []
var _bubbles: Array[MeshInstance3D] = []
var _altar_flame: Node3D
var _snowfall: GPUParticles3D
var _ice_floes: Array[Node3D] = []


func _init(p_island: Island, p_root: Node3D, p_chapter := 1) -> void:
	island = p_island
	root = p_root
	chapter = p_chapter
	biome = island.map_id
	forest = island.style == "forest"
	rng.seed = island.map_seed + 100
	quality = Settings.quality
	_patch.seed = island.map_seed + 11
	_patch.frequency = 0.035
	_patch.fractal_octaves = 3
	_warp.seed = island.map_seed + 12
	_warp.frequency = 0.02


func build() -> void:
	colliders = StaticBody3D.new()
	colliders.name = "Props"
	colliders.collision_layer = U.LAYER_WORLD
	colliders.collision_mask = 0
	root.add_child(colliders)
	_path_field()
	_environment()
	_terrain()
	_water()
	_mountains()
	if forest:
		_grove()
	_trees()
	_props()
	_grass()
	match biome:
		"island":
			_burrows()
			_moon_flowers("flowers")
			_reeds()
		"forest":
			_dens_for("den", 1.0, false)
			_mud()
			_swamp_plants()
		"deepforest":
			_dens_for("nest", 0.9, false)
			_webs("nest")
			_dens_for("roost", 1.2, false)
			_moon_flowers("glade")
			_blue_silver_grass()
			_swamp_plants()
		"snow":
			_dens_for("snowden", 1.0, true)
			_dens_for("icecave", 1.5, true)
			_ice_crystals("icefield", 70, 1.0)
			_ice_crystals("frostgrove", 50, 0.6)
			_ice_floes_build()
			_snowfall_build()
		"sea":
			_corals()
			_beach()
	_dock()
	_boat()
	_shop()
	_altar()
	_signs()
	_ambient_life()
	apply_quality()


## 画质设置改了以后调用：只改光影效果（植被密度要重新进地图）
func apply_quality() -> void:
	var q := Settings.quality
	env.ssao_enabled = q >= 1
	env.ssil_enabled = q >= 2
	env.volumetric_fog_enabled = (ENV[biome] as Dictionary).has("vol") and q >= 2
	sun.directional_shadow_max_distance = [70.0, 120.0, 170.0][q]
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if q == 0 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS


func _density() -> float:
	return [0.35, 0.65, 1.0][quality]


# ------------------------------------------------------------------ 天空与光照

func _environment() -> void:
	var e: Dictionary = ENV[biome]
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = load("res://assets/sky/%s.hdr" % e["sky"])
	pano.energy_multiplier = float(e.get("sky_e", 1.0))
	var sky := Sky.new()
	sky.sky_material = pano
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_threshold = 1.0
	env.fog_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.8
	env.ssil_radius = 4.0
	env.adjustment_enabled = true

	# 太阳方向：跟天空图里的太阳对上。太阳贴着地平线时，灯光抬高一点，不然全被山挡住
	var dir := _sky_dir(float(e["u"]), float(e["elev"]))
	var heading := atan2(dir.x, -dir.z)
	var want := heading if float(e["heading"]) > 900.0 else deg_to_rad(float(e["heading"]))
	var rot := heading - want
	dir = Basis(Vector3.UP, rot) * dir
	env.sky_rotation = Vector3(0, rot, 0)
	var light_elev := deg_to_rad(float(e["light_elev"]))
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	var light_dir := (flat * cos(light_elev) + Vector3.UP * sin(light_elev)).normalized()

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.transform = Transform3D(Basis.looking_at(-light_dir, Vector3.UP), Vector3.ZERO)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.0
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.85
	sun.light_color = e["sun"]
	sun.light_energy = e["energy"]
	env.ambient_light_energy = e["ambient"]
	env.tonemap_exposure = e["exposure"]
	env.tonemap_white = e["white"]
	env.glow_intensity = e["glow"]
	env.glow_bloom = e["bloom"]
	env.fog_light_color = e["fog"]
	env.fog_density = e["fog_d"]
	env.fog_sun_scatter = e["scatter"]
	env.fog_aerial_perspective = e["aerial"]
	env.fog_sky_affect = e["fog_sky"]
	env.adjustment_saturation = e["sat"]
	env.adjustment_contrast = e["contrast"]
	if e.has("vol"):
		sun.light_volumetric_fog_energy = float(e.get("vol_e", 2.2))
		env.volumetric_fog_density = e["vol"]
		env.volumetric_fog_albedo = e["vol_albedo"]
		env.volumetric_fog_anisotropy = 0.6
		env.volumetric_fog_length = 80.0
		env.volumetric_fog_ambient_inject = 0.35
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	root.add_child(sun)


## 全景图坐标 → 世界方向（Godot 的全景天空：u=0 在 -Z，往 +X 转）
func _sky_dir(u: float, elev_deg: float) -> Vector3:
	var phi := TAU * u
	var el := deg_to_rad(elev_deg)
	return Vector3(sin(phi) * cos(el), sin(el), -cos(phi) * cos(el)).normalized()


# ------------------------------------------------------------------ 贴图、材质

func _tex(name: String) -> Texture2D:
	if not _tex_cache.has(name):
		var path := name if name.begins_with("res://") else GROUND + name + ".jpg"
		_tex_cache[name] = load(path)
	return _tex_cache[name]


## 带真实贴图的材质，用世界坐标三向投影，箱子、圆柱都不用管 UV
func _surface(key: String, tint := Color.WHITE, scale := 0.5, rough := 0.9) -> StandardMaterial3D:
	var ck := "%s|%s|%.2f|%.2f" % [key, tint.to_html(), scale, rough]
	if _tex_cache.has(ck):
		return _tex_cache[ck]
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex(key + "_albedo")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = _tex(key + "_normal")
	m.roughness = rough
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_tex_cache[ck] = m
	return m


func _wood(tint := Color(1.25, 1.05, 0.85)) -> StandardMaterial3D:
	return _surface("bark", tint, 0.9, 0.85)


func _stone(tint := Color(1.1, 1.08, 1.02)) -> StandardMaterial3D:
	return _surface("rock", tint, 0.6, 0.85)


func _cloth(color: Color) -> StandardMaterial3D:
	var m := U.mat(color, 0.95)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


# ------------------------------------------------------------------ 小路

func _path_field() -> void:
	var S := Island.SIZE
	var H := Island.HALF
	_path.resize(S * S)
	_path.fill(99.0)
	for pl in island.paths:
		for i in pl.size() - 1:
			var a: Vector2 = pl[i]
			var b: Vector2 = pl[i + 1]
			var x0 := clampi(int(minf(a.x, b.x)) - 8 + H, 0, S - 1)
			var x1 := clampi(int(maxf(a.x, b.x)) + 8 + H, 0, S - 1)
			var z0 := clampi(int(minf(a.y, b.y)) - 8 + H, 0, S - 1)
			var z1 := clampi(int(maxf(a.y, b.y)) + 8 + H, 0, S - 1)
			for j in range(z0, z1 + 1):
				for ii in range(x0, x1 + 1):
					var p := Vector2(ii - H, j - H)
					# 扭一下坐标，路就弯弯曲曲的
					p += Vector2(_warp.get_noise_2d(p.x, p.y), _warp.get_noise_2d(p.y + 50.0, p.x)) * 3.5
					var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
					var idx := ii + j * S
					if d < _path[idx]:
						_path[idx] = d


func path_d(x: float, z: float) -> float:
	var i := clampi(roundi(x) + Island.HALF, 0, Island.SIZE - 1)
	var j := clampi(roundi(z) + Island.HALF, 0, Island.SIZE - 1)
	return _path[i + j * Island.SIZE]


# ------------------------------------------------------------------ 地形

static func _one(i: int) -> Color:
	match i:
		0:
			return Color(1, 0, 0, 0)
		1:
			return Color(0, 1, 0, 0)
		2:
			return Color(0, 0, 1, 0)
	return Color(0, 0, 0, 1)


## 地形每个点四层贴图的权重（四层是什么见 _ground_material）
func _weights(x: float, z: float, h: float, slope: float) -> Color:
	var n := _patch.get_noise_2d(x, z) * 0.5 + 0.5
	var p2 := Vector2(x, z)
	var w := _one(0)
	var pd := path_d(x, z)
	match biome:
		"forest", "deepforest":
			# 0 落叶 / 1 泥 / 2 石 / 3 苔藓
			w = w.lerp(_one(3), smoothstep(0.56, 0.74, n) * 0.85)
			for p in island.ponds:
				var d := p2.distance_to(p["center"])
				w = w.lerp(_one(1), smoothstep(p["radius"] + 7.0, p["radius"] + 1.0, d) * 0.9)
				w = w.lerp(_one(3), smoothstep(p["radius"] + 9.0, p["radius"] + 6.0, d) * (1.0 - smoothstep(p["radius"] + 6.0, p["radius"] + 3.0, d)) * 0.7)
			for hb in island.habitats:
				var d := p2.distance_to(hb["center"])
				var k := smoothstep(hb["radius"] + 5.0, hb["radius"] - 3.0, d)
				if k <= 0.0:
					continue
				match hb["type"]:
					"mud":
						w = w.lerp(_one(1), k)
					"grove", "clearing", "glade":
						w = w.lerp(_one(3), k * 0.75)
					"roost":
						w = w.lerp(_one(2), k * 0.4 * n)
					"den", "nest":
						w = w.lerp(_one(2), k * 0.35 * n)
						for b in hb["points"]:
							w = w.lerp(_one(1), smoothstep(4.5, 1.5, p2.distance_to(Vector2(b.x, b.z))) * 0.8)
			w = w.lerp(_one(1), smoothstep(2.4, 0.9, pd) * 0.75)
			w = w.lerp(_one(1), 1.0 - smoothstep(0.4, 1.4, h))
		"snow":
			# 0 雪 / 1 岩石 / 2 冻土 / 3 冰
			w = w.lerp(_one(2), smoothstep(2.2, 0.8, pd) * 0.7)
			w = w.lerp(_one(3), 1.0 - smoothstep(0.3, 1.2, h + (n - 0.5) * 0.6))
			for hb in island.habitats:
				var d := p2.distance_to(hb["center"])
				var k := smoothstep(hb["radius"] + 4.0, hb["radius"] - 3.0, d)
				if k <= 0.0:
					continue
				match hb["type"]:
					"icefield":
						w = w.lerp(_one(3), k * clampf(0.5 + n, 0.0, 1.0))
					"snowden", "icecave":
						for b in hb["points"]:
							w = w.lerp(_one(1), smoothstep(4.5, 1.8, p2.distance_to(Vector2(b.x, b.z))) * 0.8)
			w = w.lerp(_one(1), smoothstep(12.0, 18.0, h) * 0.4 * n)
		"sea":
			# 0 沙 / 1 草 / 2 石 / 3 土
			w = w.lerp(_one(1), smoothstep(2.0, 3.2, h + (n - 0.5) * 1.6))
			for hb in island.habitats:
				var d := p2.distance_to(hb["center"])
				var k := smoothstep(hb["radius"] + 5.0, hb["radius"] - 3.0, d)
				if k <= 0.0:
					continue
				match hb["type"]:
					"beach":
						w = w.lerp(_one(0), k)
					"cliff":
						w = w.lerp(_one(2), k * 0.5 * n)
			w = w.lerp(_one(3), smoothstep(2.2, 0.8, pd) * 0.8 * smoothstep(2.0, 3.0, h))
		_:
			# 岛：0 草 / 1 土 / 2 石 / 3 沙
			w = w.lerp(_one(1), smoothstep(0.64, 0.82, n) * 0.6)
			w = w.lerp(_one(3), 1.0 - smoothstep(0.55, 1.5, h + (n - 0.5) * 0.8))
			w = w.lerp(Color(0, 0.4, 0, 0.6), smoothstep(-0.4, -1.8, h))
			for hb in island.habitats:
				if hb["type"] == "burrow":
					for b in hb["points"]:
						w = w.lerp(_one(1), smoothstep(3.6, 1.3, p2.distance_to(Vector2(b.x, b.z))))
			w = w.lerp(_one(1), smoothstep(2.2, 0.8, pd) * 0.85)
			w = w.lerp(_one(2), smoothstep(9.0, 15.0, h) * 0.45 * n)
	if not forest:
		var altar := Vector2(island.altar_pos.x, island.altar_pos.z)
		w = w.lerp(_one(2 if biome != "snow" else 1), smoothstep(7.5, 5.0, p2.distance_to(altar)) * 0.6)
	var shop := Vector2(island.shop_pos.x, island.shop_pos.z)
	var dirt := 2 if biome == "snow" else (3 if biome == "sea" else 1)
	w = w.lerp(_one(dirt), smoothstep(7.0, 4.0, p2.distance_to(shop)) * 0.8)
	w = w.lerp(_one(2 if biome != "snow" else 1), smoothstep(0.5, 0.95, slope))
	return w


func _terrain_material(layers: Array, tints: Array, scales: Vector4, roughs: Vector4) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = TERRAIN_SHADER
	for i in 4:
		sm.set_shader_parameter("albedo%d" % i, _tex(str(layers[i]) + "_albedo"))
		sm.set_shader_parameter("normal%d" % i, _tex(str(layers[i]) + "_normal"))
		sm.set_shader_parameter("tint%d" % i, tints[i])
	sm.set_shader_parameter("scales", scales)
	sm.set_shader_parameter("roughs", roughs)
	return sm


func _ground_material() -> ShaderMaterial:
	match biome:
		"forest":
			return _terrain_material(["forest", "mud", "rock", "moss"],
				[Color(0.95, 0.88, 0.8), Color(0.8, 0.74, 0.66), Color(0.95, 0.93, 0.88), Color(0.8, 0.86, 0.62)],
				Vector4(0.3, 0.26, 0.16, 0.22), Vector4(0.92, 0.38, 0.8, 0.9))
		"deepforest":
			return _terrain_material(["forest", "mud", "rock", "moss"],
				[Color(0.5, 0.55, 0.62), Color(0.55, 0.55, 0.6), Color(0.75, 0.78, 0.85), Color(0.45, 0.68, 0.62)],
				Vector4(0.3, 0.26, 0.16, 0.22), Vector4(0.92, 0.35, 0.8, 0.9))
		"snow":
			var sm := _terrain_material(["snow", "rock", "dirt", "ice"],
				[Color(1.0, 1.0, 1.0), Color(0.82, 0.84, 0.9), Color(0.78, 0.76, 0.76), Color(0.85, 0.95, 1.05)],
				Vector4(0.2, 0.16, 0.24, 0.12), Vector4(0.75, 0.8, 0.9, 0.12))
			sm.set_shader_parameter("wet_level", -3.0)
			return sm
		"sea":
			var sm := _terrain_material(["sand", "grass", "rock", "dirt"],
				[Color(1.08, 1.02, 0.9), Color(0.95, 1.05, 0.8), Color(1.0, 0.98, 0.95), Color(0.95, 0.9, 0.8)],
				Vector4(0.2, 0.3, 0.16, 0.24), Vector4(0.9, 0.95, 0.8, 0.92))
			sm.set_shader_parameter("wet_level", 0.9)
			return sm
	return _terrain_material(["grass", "dirt", "rock", "sand"],
		[Color(0.95, 1.0, 0.9), Color(0.95, 0.92, 0.85), Color(1.05, 1.03, 1.0), Color(1.0, 0.97, 0.92)],
		Vector4(0.3, 0.24, 0.16, 0.22), Vector4(0.95, 0.92, 0.8, 0.9))


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
			cols[idx] = _weights(x, z, h, Vector2(hr - hl, hd - hu).length() * 0.5)
	var idxs := PackedInt32Array()
	idxs.resize((S - 1) * (S - 1) * 6)
	var k := 0
	for j in S - 1:
		for i in S - 1:
			var a := i + j * S
			var b := a + 1
			var c := a + S
			var d := c + 1
			idxs[k] = a; idxs[k + 1] = b; idxs[k + 2] = d
			idxs[k + 3] = a; idxs[k + 4] = d; idxs[k + 5] = c
			k += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idxs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "TerrainMesh"
	mi.mesh = mesh
	mi.material_override = _ground_material()
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
	pm.size = Vector2(2400, 2400)
	pm.subdivide_width = 200
	pm.subdivide_depth = 200
	var sm := ShaderMaterial.new()
	sm.shader = WATER_SHADER
	var img := Image.create_from_data(Island.SIZE, Island.SIZE, false, Image.FORMAT_RF, island.heights.to_byte_array())
	sm.set_shader_parameter("height_tex", ImageTexture.create_from_image(img))
	sm.set_shader_parameter("terrain_half", float(Island.HALF))
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 6.0
	var fn := FastNoiseLite.new()
	fn.frequency = 0.03
	fn.fractal_octaves = 3
	nt.noise = fn
	sm.set_shader_parameter("ripple_tex", nt)
	match biome:
		"forest":
			sm.set_shader_parameter("shallow_color", Color(0.36, 0.42, 0.26))
			sm.set_shader_parameter("deep_color", Color(0.07, 0.12, 0.08))
			sm.set_shader_parameter("foam_color", Color(0.75, 0.72, 0.6))
			sm.set_shader_parameter("depth_fade", 2.5)
			sm.set_shader_parameter("murk", 0.8)
			sm.set_shader_parameter("foam_width", 0.35)
		"deepforest":
			sm.set_shader_parameter("shallow_color", Color(0.14, 0.3, 0.3))
			sm.set_shader_parameter("deep_color", Color(0.02, 0.06, 0.1))
			sm.set_shader_parameter("foam_color", Color(0.5, 0.75, 0.8))
			sm.set_shader_parameter("depth_fade", 2.5)
			sm.set_shader_parameter("murk", 0.7)
			sm.set_shader_parameter("foam_width", 0.3)
		"snow":
			sm.set_shader_parameter("shallow_color", Color(0.55, 0.78, 0.85))
			sm.set_shader_parameter("deep_color", Color(0.08, 0.22, 0.34))
			sm.set_shader_parameter("foam_color", Color(0.95, 0.98, 1.0))
			sm.set_shader_parameter("foam_width", 1.0)
		"sea":
			sm.set_shader_parameter("shallow_color", Color(0.2, 0.85, 0.8))
			sm.set_shader_parameter("deep_color", Color(0.02, 0.2, 0.42))
			sm.set_shader_parameter("depth_fade", 8.0)
			sm.set_shader_parameter("foam_width", 1.0)
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = pm
	mi.material_override = sm
	mi.position.y = Island.WATER_Y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	# 地形外面的湖底
	var floor_mi := MeshInstance3D.new()
	var fp := PlaneMesh.new()
	fp.size = Vector2(2400, 2400)
	floor_mi.mesh = fp
	floor_mi.material_override = _surface("mud" if forest else "sand", Color(0.55, 0.55, 0.5), 0.1, 0.9)
	if biome == "sea":
		floor_mi.position.y = -24.0
	floor_mi.position.y = -13.0
	floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(floor_mi)


## 湖对岸一圈连绵的山（山脊噪声），远处被雾淡化
func _mountains() -> void:
	var nz := FastNoiseLite.new()
	nz.seed = island.map_seed + 77
	nz.frequency = 0.0032
	nz.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	nz.fractal_octaves = 5
	var A := 256
	var r0 := 290.0 if forest else (560.0 if biome == "sea" else 340.0)
	var radii: Array[float] = []
	for i in 30:
		radii.append(r0 + pow(i / 29.0, 1.5) * 1000.0)
	var peak: float = {"island": 220.0, "forest": 150.0, "deepforest": 170.0, "snow": 280.0, "sea": 70.0}[biome]
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var grid := []
	for i in radii.size():
		var row: Array[float] = []
		for k in A:
			var a := TAU * k / A
			var r := radii[i]
			var x := cos(a) * r
			var z := sin(a) * r
			var rise := smoothstep(r0, r0 + 260.0, r)
			var nv := clampf(nz.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
			var hgt := -18.0 + rise * (25.0 + nv * nv * peak) + (1.0 - rise) * nv * 10.0
			row.append(hgt)
		grid.append(row)
	var norms := PackedVector3Array()
	for i in radii.size():
		for k in A:
			var a := TAU * k / A
			var r := radii[i]
			var hgt: float = grid[i][k]
			var hl: float = grid[i][(k + A - 1) % A]
			var hr: float = grid[i][(k + 1) % A]
			var hi: float = grid[maxi(i - 1, 0)][k]
			var ho: float = grid[mini(i + 1, radii.size() - 1)][k]
			var arc := TAU * r / A
			var dr := (radii[mini(i + 1, radii.size() - 1)] - radii[maxi(i - 1, 0)])
			var radial := Vector3(cos(a), 0, sin(a))
			var tang := Vector3(-sin(a), 0, cos(a))
			var n := (Vector3.UP * 2.0 - radial * (ho - hi) / dr * 2.0 - tang * (hr - hl) / (arc * 2.0) * 2.0).normalized()
			verts.append(Vector3(cos(a) * r, hgt, sin(a) * r))
			norms.append(n)
			var slope := 1.0 - n.y
			var w := _one(0)
			w = w.lerp(_one(1), smoothstep(40.0, 110.0, hgt) * 0.6)
			w = w.lerp(_one(2), clampf(smoothstep(0.12, 0.35, slope) + smoothstep(90.0, 160.0, hgt), 0.0, 1.0))
			w = w.lerp(_one(3), 1.0 - smoothstep(-2.0, 4.0, hgt))
			cols.append(w)
	var idxs := PackedInt32Array()
	for i in radii.size() - 1:
		for k in A:
			var a0 := i * A + k
			var a1 := i * A + (k + 1) % A
			var b0 := (i + 1) * A + k
			var b1 := (i + 1) * A + (k + 1) % A
			idxs.append_array(PackedInt32Array([a0, b0, b1, a0, b1, a1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idxs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var sm: ShaderMaterial
	if biome == "deepforest":
		sm = _terrain_material(["moss", "forest", "rock", "mud"],
			[Color(0.25, 0.38, 0.4), Color(0.3, 0.35, 0.42), Color(0.55, 0.6, 0.7), Color(0.3, 0.32, 0.35)],
			Vector4(0.05, 0.05, 0.03, 0.05), Vector4(0.95, 0.95, 0.85, 0.9))
	elif biome == "snow":
		sm = _terrain_material(["snow", "snow", "rock", "ice"],
			[Color(0.95, 0.97, 1.0), Color(0.9, 0.93, 0.98), Color(0.7, 0.74, 0.8), Color(0.8, 0.9, 1.0)],
			Vector4(0.05, 0.05, 0.03, 0.05), Vector4(0.8, 0.8, 0.85, 0.2))
		sm.set_shader_parameter("snow_height", 40.0)
	elif forest:
		sm = _terrain_material(["forest", "moss", "rock", "mud"],
			[Color(0.75, 0.5, 0.32), Color(0.55, 0.45, 0.3), Color(0.8, 0.78, 0.75), Color(0.6, 0.55, 0.45)],
			Vector4(0.05, 0.05, 0.03, 0.05), Vector4(0.95, 0.95, 0.85, 0.9))
	else:
		sm = _terrain_material(["grass", "moss", "rock", "sand"],
			[Color(0.42, 0.55, 0.36), Color(0.5, 0.6, 0.4), Color(0.95, 0.95, 0.95), Color(0.9, 0.88, 0.8)],
			Vector4(0.05, 0.05, 0.03, 0.05), Vector4(0.95, 0.95, 0.85, 0.9))
		sm.set_shader_parameter("snow_height", 150.0)
	sm.set_shader_parameter("macro_amount", 0.35)
	sm.set_shader_parameter("wet_level", -2.0)
	var mi := MeshInstance3D.new()
	mi.name = "Mountains"
	mi.mesh = mesh
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


# ------------------------------------------------------------------ 批量绘制

## 盖在东西上面的一层雪（极北之地）
func _snow_overlay() -> ShaderMaterial:
	if not _tex_cache.has("snow_overlay"):
		var m := ShaderMaterial.new()
		m.shader = SNOW_OVERLAY
		_tex_cache["snow_overlay"] = m
	return _tex_cache["snow_overlay"]


func _multimesh(mesh: Mesh, xforms: Array, colors: Array = [], shadows := true, material: Material = null, overlay: Material = null) -> MultiMeshInstance3D:
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
	if material:
		mmi.material_override = material
	if overlay:
		mmi.material_overlay = overlay
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)
	return mmi


## 按区块分组画，每块单独做视锥剔除；vis_end > 0 时远处整块隐藏
func _scatter(mesh: Mesh, xforms: Array, colors: Array = [], vis_end := 0.0, shadows := true, chunk := 48.0, material: Material = null, overlay: Material = null) -> void:
	if xforms.is_empty():
		return
	var buckets := {}
	for i in xforms.size():
		var t: Transform3D = xforms[i]
		var key := Vector2i(floori(t.origin.x / chunk), floori(t.origin.z / chunk))
		if not buckets.has(key):
			buckets[key] = [[], []]
		buckets[key][0].append(t)
		if colors.size() > 0:
			buckets[key][1].append(colors[i])
	for key in buckets:
		var mmi := _multimesh(mesh, buckets[key][0], buckets[key][1], shadows, material, overlay)
		if vis_end > 0.0:
			mmi.visibility_range_end = vis_end
			mmi.visibility_range_end_margin = vis_end * 0.12
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


# ------------------------------------------------------------------ 放东西的规则

## 这里能不能种树 / 放石头（避开栖息地、路、出生点、房子、码头、祭坛）
func _free(x: float, z: float, margin: float) -> bool:
	var p := Vector2(x, z)
	for hb in island.habitats:
		var r: float = hb["radius"]
		if hb["type"] in ["grove", "clearing"]:
			r -= 2.0
		if p.distance_to(hb["center"]) < r + margin:
			return false
	for pd in island.ponds:
		if p.distance_to(pd["center"]) < pd["radius"] + margin + 1.0:
			return false
	if path_d(x, z) < 1.6 + margin:
		return false
	if p.distance_to(Vector2(island.spawn.x, island.spawn.z)) < 12.0 + margin:
		return false
	if p.distance_to(Vector2(island.shop_pos.x, island.shop_pos.z)) < 9.0 + margin:
		return false
	if p.distance_to(Vector2(island.altar_pos.x, island.altar_pos.z)) < 8.0 + margin:
		return false
	if absf(x - island.dock_start.x) < 4.0 + margin and z > island.dock_start.z - 10.0:
		return false
	if island.ancient_tree != Vector3.INF and p.distance_to(Vector2(island.ancient_tree.x, island.ancient_tree.z)) < 9.0 + margin:
		return false
	return true


func _add_trunk(p: Vector2, radius: float) -> void:
	var t := [p, radius]
	_trunks.append(t)
	var key := Vector2i(floori(p.x / 8.0), floori(p.y / 8.0))
	if not _trunk_grid.has(key):
		_trunk_grid[key] = []
	_trunk_grid[key].append(t)


func _near_trunk(x: float, z: float, r: float) -> bool:
	var p := Vector2(x, z)
	var cx := floori(x / 8.0)
	var cz := floori(z / 8.0)
	for i in range(cx - 1, cx + 2):
		for j in range(cz - 1, cz + 2):
			for t in _trunk_grid.get(Vector2i(i, j), []):
				if p.distance_to(t[0]) < r + float(t[1]):
					return true
	return false


func _add_collider(shape: Shape3D, xf: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xf
	colliders.add_child(cs)


func _cyl_collider(pos: Vector3, radius: float, height: float) -> void:
	var sh := CylinderShape3D.new()
	sh.radius = radius
	sh.height = height
	_add_collider(sh, Transform3D(Basis(), pos + Vector3(0, height * 0.5, 0)))


# ------------------------------------------------------------------ 程序生成的树

## 沿折线生成一段圆管（树干、树枝）。cnt[0] 是这个 SurfaceTool 里已有的顶点数
func _tube(st: SurfaceTool, cnt: Array, pts: Array, radii: Array, sides: int, sway0: float, sway1: float) -> void:
	var n := pts.size()
	var side := Vector3.ZERO
	var v := 0.0
	var start: int = cnt[0]
	for i in n:
		var p: Vector3 = pts[i]
		var t: Vector3
		if i == 0:
			t = (pts[1] - pts[0]).normalized()
		elif i == n - 1:
			t = (pts[i] - pts[i - 1]).normalized()
		else:
			t = (pts[i + 1] - pts[i - 1]).normalized()
		if i == 0:
			side = t.cross(Vector3.FORWARD if absf(t.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		else:
			side = (side - t * side.dot(t)).normalized()
			v += (pts[i] - pts[i - 1]).length()
		var up := t.cross(side).normalized()
		var r: float = radii[i]
		var around := maxf(0.5, roundf(TAU * r / 1.2))
		var sw := lerpf(sway0, sway1, float(i) / (n - 1))
		for k in sides + 1:
			var a := TAU * k / sides
			var d := side * cos(a) + up * sin(a)
			st.set_normal(d)
			st.set_uv(Vector2(float(k) / sides * around, v * 0.5))
			st.set_uv2(Vector2(sw, 0))
			st.add_vertex(p + d * r)
	for i in n - 1:
		for k in sides:
			var a0 := start + i * (sides + 1) + k
			var b0 := a0 + sides + 1
			st.add_index(a0)
			st.add_index(b0)
			st.add_index(a0 + 1)
			st.add_index(a0 + 1)
			st.add_index(b0)
			st.add_index(b0 + 1)
	cnt[0] = start + n * (sides + 1)


## 一张树叶贴片：底边中点在 base，沿 up_dir 长 h，宽 w。法线指向 nc 外侧（整棵树像一团蓬松的球）
## v0 / v1：贴图底边和顶边的 V 坐标（棕榈叶分两段弯折时用半张贴图）
func _card(st: SurfaceTool, cnt: Array, base: Vector3, up_dir: Vector3, right: Vector3, w: float, h: float, nc: Vector3, sway: float, col: Color, v0 := 1.0, v1 := 0.0) -> void:
	var r := right * (w * 0.5)
	var u := up_dir * h
	var pts := [base - r, base + r, base + r + u, base - r + u]
	var uvs := [Vector2(0, v0), Vector2(1, v0), Vector2(1, v1), Vector2(0, v1)]
	var start: int = cnt[0]
	for i in 4:
		var p: Vector3 = pts[i]
		var nrm := (p - nc)
		nrm = (nrm.normalized() if nrm.length() > 0.01 else Vector3.UP).lerp(Vector3.UP, 0.25).normalized()
		st.set_normal(nrm)
		st.set_uv(uvs[i])
		st.set_uv2(Vector2(sway * (0.7 + 0.3 * float(i >= 2)), 0))
		st.set_color(col)
		st.add_vertex(p)
	for i in [0, 1, 2, 0, 2, 3]:
		st.add_index(start + i)
	cnt[0] = start + 4


## 一簇树叶：三张贴片交叉，朝树冠外侧
func _cluster(st: SurfaceTool, cnt: Array, r: RandomNumberGenerator, p: Vector3, crown: Vector3, R: float, size: float) -> void:
	var out := p - crown
	out = (out.normalized() if out.length() > 0.05 else Vector3.UP).lerp(Vector3.UP, 0.35).normalized()
	var perp := out.cross(Vector3.UP if absf(out.y) < 0.95 else Vector3.RIGHT).normalized()
	var k := clampf((p - crown).length() / R, 0.0, 1.0)
	var shade := lerpf(0.55, 1.05, k) * r.randf_range(0.88, 1.08) * lerpf(0.85, 1.05, clampf((p.y - crown.y) / R * 0.5 + 0.5, 0.0, 1.0))
	var col := Color(shade, shade, shade)
	var base := p - out * size * 0.45
	var roll := r.randf() * PI
	for i in 3:
		var right := perp.rotated(out, roll + i * PI / 3.0)
		_card(st, cnt, base, out, right, size, size, crown, 1.0, col)


func _along(pts: Array, t: float) -> Vector3:
	var f := clampf(t, 0.0, 1.0) * (pts.size() - 1)
	var i := mini(int(f), pts.size() - 2)
	return (pts[i] as Vector3).lerp(pts[i + 1], f - i)


## 阔叶树：弯一点的树干 + 5~7 根斜向上的树枝 + 二三十簇树叶
func _broad_tree(r: RandomNumberGenerator, H: float, spread: float, bark: Material, leaves: Material) -> Dictionary:
	var sb := SurfaceTool.new()
	sb.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sl := SurfaceTool.new()
	sl.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cb := [0]
	var cl := [0]
	var r0 := H * 0.03 + 0.12
	var trunk_h := H * r.randf_range(0.52, 0.62)
	var lean := Vector3(r.randf_range(-0.5, 0.5), 0, r.randf_range(-0.5, 0.5))
	var pts := []
	var rad := []
	for i in 7:
		var t := i / 6.0
		var jitter := Vector3(r.randf_range(-0.1, 0.1), 0, r.randf_range(-0.1, 0.1)) if i > 0 else Vector3.ZERO
		pts.append(Vector3(0, t * trunk_h - 0.3, 0) + lean * t * t + jitter)
		rad.append(r0 * (1.0 - t * 0.5) * (1.0 + 0.6 * pow(1.0 - t, 8.0)))
	_tube(sb, cb, pts, rad, 10, 0.0, 0.25)
	var top: Vector3 = pts[pts.size() - 1]
	var crown := top + Vector3(0, H * 0.14, 0)
	var R := H * 0.3 * spread
	var clusters: Array[Vector3] = []
	var nb := r.randi_range(5, 7)
	for b in nb:
		var t0 := r.randf_range(0.5, 1.0)
		var s := _along(pts, t0)
		var az := TAU * b / nb + r.randf_range(-0.4, 0.4)
		var el := deg_to_rad(r.randf_range(22.0, 52.0))
		var dir := Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el))
		var L := R * r.randf_range(0.85, 1.2)
		var bp := [s, s + dir * L * 0.35, s + dir * L * 0.7 + Vector3(0, 0.12, 0) * L, s + dir * L + Vector3(0, 0.2, 0) * L]
		var br := r0 * 0.5 * (1.0 - t0 * 0.35)
		_tube(sb, cb, bp, [br, br * 0.72, br * 0.45, br * 0.18], 6, 0.2, 0.75)
		clusters.append(bp[3])
		clusters.append(bp[2])
		if r.randf() < 0.7:
			clusters.append((bp[1] as Vector3).lerp(bp[2], 0.5) + Vector3(0, R * 0.2, 0))
	for i in 14:
		var d := Vector3(r.randf_range(-1, 1), r.randf_range(-0.5, 1), r.randf_range(-1, 1)).normalized() * R * r.randf_range(0.45, 0.95)
		clusters.append(crown + Vector3(d.x, d.y * 0.8, d.z))
	var mesh := ArrayMesh.new()
	sb.generate_tangents()
	sb.commit(mesh)
	mesh.surface_set_material(0, bark)
	if leaves:
		for c in clusters:
			_cluster(sl, cl, r, c, crown, R, R * r.randf_range(0.62, 0.85))
		sl.commit(mesh)
		mesh.surface_set_material(1, leaves)
	return {"mesh": mesh, "radius": r0}


## 松树：笔直的树干，一层层向四周伸出、稍微下垂的松枝
func _pine_tree(r: RandomNumberGenerator, H: float, bark: Material, needles: Material) -> Dictionary:
	var sb := SurfaceTool.new()
	sb.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sl := SurfaceTool.new()
	sl.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cb := [0]
	var cl := [0]
	var r0 := H * 0.022 + 0.12
	var pts := []
	var rad := []
	for i in 6:
		var t := i / 5.0
		pts.append(Vector3(0, t * H - 0.3, 0))
		rad.append(lerpf(r0, 0.03, t) * (1.0 + 0.5 * pow(1.0 - t, 10.0)))
	_tube(sb, cb, pts, rad, 9, 0.0, 0.5)
	var y := H * r.randf_range(0.2, 0.3)
	while y < H * 0.95:
		var t := y / H
		var L := (1.0 - t) * H * 0.3 + 0.5
		var n := r.randi_range(5, 7)
		var off := r.randf() * TAU
		var shade := lerpf(0.6, 1.05, t)
		for k in n:
			var az := off + TAU * k / n + r.randf_range(-0.25, 0.25)
			var droop := deg_to_rad(r.randf_range(5.0, 24.0))
			var d := Vector3(cos(az) * cos(droop), -sin(droop), sin(az) * cos(droop))
			var side := Vector3(-sin(az), 0, cos(az))
			var base := Vector3(0, y, 0) - d * 0.15
			var col := Color(1, 1, 1) * shade * r.randf_range(0.9, 1.06)
			col.a = 1.0
			var nc := Vector3(0, y - L * 0.6, 0)
			_card(sl, cl, base, d, side.rotated(d, r.randf_range(-0.4, 0.4)), L * 1.05, L, nc, 0.3 + t * 0.7, col)
			_card(sl, cl, base, d, side.rotated(d, PI * 0.5), L * 0.55, L, nc, 0.3 + t * 0.7, col * 0.92)
		y += r.randf_range(0.45, 0.75) * (1.0 + (1.0 - t) * 0.4)
	for k in 2:
		var right := Vector3(cos(k * PI * 0.5), 0, sin(k * PI * 0.5))
		_card(sl, cl, Vector3(0, H * 0.9, 0), Vector3.UP, right, 1.1, 1.3, Vector3(0, H * 0.8, 0), 1.0, Color(1.05, 1.05, 1.05))
	var mesh := ArrayMesh.new()
	sb.generate_tangents()
	sb.commit(mesh)
	sl.commit(mesh)
	mesh.surface_set_material(0, bark)
	mesh.surface_set_material(1, needles)
	return {"mesh": mesh, "radius": r0}


## 椰子树：弯弯的树干，顶上一圈往下垂的大叶子（每片叶子两段，先往上再往下弯）
func _palm_tree(r: RandomNumberGenerator, H: float, bark: Material, fronds: Material) -> Dictionary:
	var sb := SurfaceTool.new()
	sb.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sl := SurfaceTool.new()
	sl.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cb := [0]
	var cl := [0]
	var lean_dir := Vector3(r.randf_range(-1, 1), 0, r.randf_range(-1, 1)).normalized()
	var lean := r.randf_range(0.8, 2.6)
	var pts := []
	var rad := []
	for i in 9:
		var t := i / 8.0
		pts.append(Vector3(0, t * H - 0.3, 0) + lean_dir * lean * t * t)
		rad.append(lerpf(0.26, 0.15, t) * (1.0 + 0.4 * pow(1.0 - t, 8.0)))
	_tube(sb, cb, pts, rad, 8, 0.0, 0.5)
	var top: Vector3 = pts[8]
	var nc := top - Vector3(0, 2.0, 0)
	var n := r.randi_range(10, 13)
	for k in n:
		var az := TAU * k / n + r.randf_range(-0.2, 0.2)
		var out := Vector3(cos(az), 0, sin(az))
		var side := out.cross(Vector3.UP).normalized()
		var L := r.randf_range(3.2, 4.4)
		var el1 := deg_to_rad(r.randf_range(15.0, 40.0))
		var d1 := (out * cos(el1) + Vector3.UP * sin(el1)).normalized()
		var p1 := top + d1 * L * 0.5
		var el2 := deg_to_rad(r.randf_range(-45.0, -20.0))
		var d2 := (out * cos(el2) + Vector3.UP * sin(el2)).normalized()
		var sh := r.randf_range(0.85, 1.05)
		var col := Color(sh, sh, sh)
		_card(sl, cl, top, d1, side.rotated(d1, r.randf_range(-0.3, 0.3)), 1.5, L * 0.5, nc, 0.8, col, 1.0, 0.5)
		_card(sl, cl, p1, d2, side.rotated(d2, r.randf_range(-0.3, 0.3)), 1.5, L * 0.5, nc, 1.0, col, 0.5, 0.0)
	var mesh := ArrayMesh.new()
	sb.generate_tangents()
	sb.commit(mesh)
	sl.commit(mesh)
	mesh.surface_set_material(0, bark)
	mesh.surface_set_material(1, fronds)
	return {"mesh": mesh, "radius": 0.26}


func _bark(tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex("bark_albedo")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = _tex("bark_normal")
	m.normal_scale = 1.3
	m.roughness = 0.95
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _leaves(tex: String, tint: Color, backlight: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FOLIAGE_SHADER
	m.set_shader_parameter("leaf_tex", load(FOLIAGE + tex + ".png"))
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("backlight", backlight)
	return m


## 每张地图有哪几种树：[{mesh, radius, kind}]
func _tree_kinds(r: RandomNumberGenerator) -> Array:
	var kinds: Array = []
	match biome:
		"forest":
			var bark := _bark(Color(0.72, 0.62, 0.55))
			var autumn := _leaves("leaf_autumn", Color(1.0, 0.92, 0.85), Color(0.7, 0.35, 0.1))
			var dark := _leaves("leaf_dark", Color(0.95, 0.9, 0.7), Color(0.4, 0.4, 0.12))
			var gold := _leaves("leaf_green", Color(1.15, 0.95, 0.45), Color(0.6, 0.45, 0.1))
			var pine := _leaves("leaf_pine", Color(0.8, 0.85, 0.7), Color(0.25, 0.35, 0.12))
			for i in 3:
				kinds.append(_broad_tree(r, r.randf_range(14, 18), 1.0, bark, autumn).merged({"kind": "broad"}))
			for i in 2:
				kinds.append(_broad_tree(r, r.randf_range(13, 17), 0.95, bark, dark).merged({"kind": "broad"}))
			kinds.append(_broad_tree(r, r.randf_range(12, 15), 1.05, bark, gold).merged({"kind": "broad"}))
			for i in 2:
				kinds.append(_pine_tree(r, r.randf_range(16, 21), _bark(Color(0.6, 0.5, 0.45)), pine).merged({"kind": "pine"}))
		"deepforest":
			var bark := _bark(Color(0.42, 0.4, 0.46))
			var dark := _leaves("leaf_dark", Color(0.55, 0.8, 0.85), Color(0.1, 0.3, 0.45))
			var blue := _leaves("leaf_green", Color(0.45, 0.7, 0.9), Color(0.1, 0.35, 0.6))
			var pine := _leaves("leaf_pine", Color(0.55, 0.72, 0.75), Color(0.1, 0.2, 0.28))
			for i in 3:
				kinds.append(_broad_tree(r, r.randf_range(18, 25), 1.1, bark, dark).merged({"kind": "broad"}))
			for i in 2:
				kinds.append(_broad_tree(r, r.randf_range(16, 22), 1.0, bark, blue).merged({"kind": "broad"}))
			for i in 2:
				kinds.append(_pine_tree(r, r.randf_range(20, 27), bark, pine).merged({"kind": "pine"}))
		"snow":
			var bark := _bark(Color(0.6, 0.55, 0.52))
			var snowpine := _leaves("leaf_pine_snow", Color(0.95, 1.0, 1.0), Color(0.2, 0.25, 0.3))
			for i in 4:
				kinds.append(_pine_tree(r, r.randf_range(11, 19), bark, snowpine).merged({"kind": "pine"}))
			for i in 2:
				kinds.append(_broad_tree(r, r.randf_range(7, 10), 0.9, _bark(Color(0.55, 0.52, 0.5)), null).merged({"kind": "dead"}))
		"sea":
			var bark := _bark(Color(0.9, 0.78, 0.62))
			var frond := _leaves("palm_frond", Color(1.0, 1.02, 0.95), Color(0.4, 0.5, 0.15))
			for i in 4:
				kinds.append(_palm_tree(r, r.randf_range(7, 11), bark, frond).merged({"kind": "palm"}))
			var green := _leaves("leaf_green", Color(1.05, 1.05, 0.95), Color(0.45, 0.55, 0.15))
			for i in 2:
				kinds.append(_broad_tree(r, r.randf_range(8, 11), 1.1, _bark(Color(0.85, 0.78, 0.72)), green).merged({"kind": "broad"}))
		_:
			var bark := _bark(Color(0.85, 0.78, 0.72))
			var green := _leaves("leaf_green", Color(1.0, 1.0, 1.0), Color(0.45, 0.55, 0.15))
			var dark := _leaves("leaf_dark", Color(1.05, 1.08, 1.0), Color(0.3, 0.4, 0.12))
			var pine := _leaves("leaf_pine", Color(1.0, 1.0, 1.0), Color(0.25, 0.35, 0.12))
			for i in 2:
				kinds.append(_broad_tree(r, r.randf_range(8, 11), 1.0, bark, green).merged({"kind": "broad"}))
			kinds.append(_broad_tree(r, r.randf_range(9, 12), 1.1, bark, dark).merged({"kind": "broad"}))
			for i in 3:
				kinds.append(_pine_tree(r, r.randf_range(11, 16), _bark(Color(0.9, 0.8, 0.72)), pine).merged({"kind": "pine"}))
	return kinds


## 这个位置长哪种树
func _tree_kind_at(r: RandomNumberGenerator, h: float) -> String:
	match biome:
		"forest":
			return "pine" if r.randf() < 0.25 else "broad"
		"deepforest":
			return "pine" if r.randf() < 0.3 else "broad"
		"snow":
			return "dead" if r.randf() < 0.15 else "pine"
		"sea":
			return "palm" if h < 5.5 or r.randf() < 0.5 else "broad"
	return "pine" if r.randf() < clampf(0.35 + (h - 5.0) * 0.08, 0.2, 0.85) else "broad"


func _trees() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = island.map_seed + 300
	var kinds := _tree_kinds(r)
	var xforms := []
	for k in kinds:
		xforms.append([])
	var target: int = {"island": 240, "forest": 700, "deepforest": 850, "snow": 380, "sea": 230}[biome]
	var min_h := 0.9 if biome == "sea" else 1.2
	var tree_noise := FastNoiseLite.new()
	tree_noise.seed = island.map_seed + 301
	tree_noise.frequency = 0.02
	var tries := 0
	var placed := 0
	while placed < target and tries < target * 40:
		tries += 1
		var x := r.randf_range(-158, 158)
		var z := r.randf_range(-158, 158)
		var h := island.height_at(x, z)
		if h < min_h or island.slope_at(x, z) > 0.85 or not _free(x, z, 2.5):
			continue
		# 树成片长：噪声低的地方是空地
		var dens := tree_noise.get_noise_2d(x, z) * 0.5 + 0.5
		if r.randf() > smoothstep(0.3, 0.6, dens) + (0.25 if forest else 0.0):
			continue
		if _near_trunk(x, z, 2.2 if forest else 3.0):
			continue
		var want := _tree_kind_at(r, h)
		var choices := []
		for i in kinds.size():
			if str(kinds[i]["kind"]) == want:
				choices.append(i)
		if choices.is_empty():
			continue
		var ki: int = choices[r.randi() % choices.size()]
		var s := r.randf_range(0.8, 1.25)
		var b := Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(s, s * r.randf_range(0.92, 1.08), s))
		xforms[ki].append(Transform3D(b, Vector3(x, h, z)))
		var rad: float = kinds[ki]["radius"] * s
		_add_trunk(Vector2(x, z), rad)
		_cyl_collider(Vector3(x, h - 0.5, z), rad * 1.1, 7.0)
		placed += 1
	for i in kinds.size():
		_scatter(kinds[i]["mesh"], xforms[i], [], 0.0, true, 64.0)


# ------------------------------------------------------------------ Poly Haven 模型

## 读一个模型文件，返回里面每个网格（同一个文件里常有 a/b/c 几个变体）
func _prop(name: String) -> Array:
	if _prop_cache.has(name):
		return _prop_cache[name]
	var out := []
	var path := MODELS + name + "/" + name + "_1k.gltf"
	if ResourceLoader.exists(path):
		var ps: PackedScene = load(path)
		var inst := ps.instantiate()
		_collect(inst, Transform3D.IDENTITY, out)
		inst.free()
	_prop_cache[name] = out
	return out


func _collect(n: Node, parent_xf: Transform3D, out: Array) -> void:
	var xf := parent_xf
	if n is Node3D:
		xf = parent_xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mesh: Mesh = (n as MeshInstance3D).mesh
		var b := xf.basis
		var aabb: AABB = Transform3D(b, Vector3.ZERO) * mesh.get_aabb()
		var mid := aabb.get_center()
		out.append({"mesh": mesh, "basis": b, "offset": Vector3(-mid.x, -aabb.position.y, -mid.z), "size": aabb.size})
	for child in n.get_children():
		_collect(child, xf, out)


## 在地图上撒一种模型。where(rng) 返回位置（Vector3.INF 表示这次不放）
func _scatter_prop(name: String, count: int, where: Callable, smin: float, smax: float, vis_end := 0.0, shadows := true, collide := 0.0, sink := 0.05, overlay: Material = null) -> void:
	var variants := _prop(name)
	if variants.is_empty():
		return
	var per := []
	for v in variants:
		per.append([])
	var r := RandomNumberGenerator.new()
	r.seed = island.map_seed + name.hash()
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 30:
		tries += 1
		var p: Vector3 = where.call(r)
		if p == Vector3.INF:
			continue
		var vi := r.randi() % variants.size()
		var v: Dictionary = variants[vi]
		var s := r.randf_range(smin, smax)
		var yaw := Basis(Vector3.UP, r.randf() * TAU)
		var b := yaw.scaled(Vector3(s, s, s)) * (v["basis"] as Basis)
		var off: Vector3 = yaw * ((v["offset"] as Vector3) * s)
		var origin := p + off - Vector3(0, sink * s, 0)
		per[vi].append(Transform3D(b, origin))
		if collide > 0.0:
			var size: Vector3 = v["size"] * s
			var foot := minf(size.x, size.z) * 0.5 * collide
			if foot > 0.35:
				var sh := SphereShape3D.new()
				sh.radius = foot
				_add_collider(sh, Transform3D(Basis(), p + Vector3(0, size.y * 0.5 - foot * 0.35, 0)))
		placed += 1
	for i in variants.size():
		_scatter(variants[i]["mesh"], per[i], [], vis_end, shadows, 40.0, null, overlay)


## 常用的放置规则
func _spot_land(min_h := 1.0, max_slope := 0.8, margin := 1.0, avoid_trunk := 1.0) -> Callable:
	return func(r: RandomNumberGenerator) -> Vector3:
		var x := r.randf_range(-150, 150)
		var z := r.randf_range(-150, 150)
		var h := island.height_at(x, z)
		if h < min_h or island.slope_at(x, z) > max_slope or not _free(x, z, margin):
			return Vector3.INF
		if avoid_trunk > 0.0 and _near_trunk(x, z, avoid_trunk):
			return Vector3.INF
		return Vector3(x, h, z)


## 靠近树的地方（蕨类、灌木喜欢树荫）
func _spot_under_trees(spread: float) -> Callable:
	return func(r: RandomNumberGenerator) -> Vector3:
		if _trunks.is_empty():
			return Vector3.INF
		var t: Array = _trunks[r.randi() % _trunks.size()]
		var a := r.randf() * TAU
		var d := r.randf_range(1.2, spread)
		var c: Vector2 = t[0]
		var x := c.x + cos(a) * d
		var z := c.y + sin(a) * d
		var h := island.height_at(x, z)
		if h < 0.8 or not _free(x, z, 0.0) or _near_trunk(x, z, 0.6):
			return Vector3.INF
		return Vector3(x, h, z)


func _spot_in(center: Vector2, radius: float, min_h := 0.6) -> Callable:
	return func(r: RandomNumberGenerator) -> Vector3:
		var a := r.randf() * TAU
		var d := sqrt(r.randf()) * radius
		var x := center.x + cos(a) * d
		var z := center.y + sin(a) * d
		var h := island.height_at(x, z)
		if h < min_h or path_d(x, z) < 1.4:
			return Vector3.INF
		return Vector3(x, h, z)


func _props() -> void:
	var dn := _density()
	match biome:
		"forest", "deepforest":
			var k := 1.2 if biome == "deepforest" else 1.0
			_scatter_prop("rock_moss_set_01", 70, _spot_land(0.5, 1.2, 0.5), 0.6, 2.2, 0.0, true, 0.8)
			_scatter_prop("rock_moss_set_02", 70, _spot_land(0.5, 1.2, 0.5), 0.6, 2.2, 0.0, true, 0.8)
			_scatter_prop("boulder_01", 20, _spot_land(1.0, 1.0, 2.0), 2.0, 4.0, 0.0, true, 0.9)
			_scatter_prop("fern_02", int(700 * dn * k), _spot_under_trees(6.0), 1.0, 1.8, 55.0, false)
			_scatter_prop("shrub_02", int(140 * dn * k), _spot_under_trees(7.0), 0.9, 1.5, 90.0, true)
			_scatter_prop("nettle_plant", int(400 * dn), _spot_under_trees(8.0), 2.5, 4.5, 45.0, false)
			_scatter_prop("shrub_sorrel_01", int(500 * dn), _spot_land(0.8, 0.8, 0.0, 0.5), 4.0, 7.0, 35.0, false)
			_scatter_prop("tree_stump_01", 28, _spot_land(1.0, 0.7, 1.0), 1.0, 1.6, 0.0, true, 0.8)
			_scatter_prop("dead_tree_trunk", 14, _spot_land(1.0, 0.5, 2.0, 2.5), 1.3, 2.0, 0.0, true)
			_scatter_prop("dead_tree_trunk_02", 12, _spot_land(1.0, 0.5, 2.0, 2.5), 1.0, 1.5, 0.0, true)
			if biome == "deepforest":
				var t := island.habitat("thicket")
				_scatter_prop("shrub_02", int(90 * dn) + 20, _spot_in(t["center"], t["radius"] + 4.0, 1.0), 1.2, 2.0, 90.0, true)
				_scatter_prop("fern_02", int(200 * dn) + 40, _spot_in(t["center"], t["radius"] + 4.0, 1.0), 1.6, 2.4, 60.0, false)
		"snow":
			var snow := _snow_overlay()
			_scatter_prop("rock_moss_set_01", 60, _spot_land(0.3, 1.2, 0.5), 0.6, 2.2, 0.0, true, 0.8, 0.05, snow)
			_scatter_prop("rock_moss_set_02", 60, _spot_land(0.3, 1.2, 0.5), 0.6, 2.2, 0.0, true, 0.8, 0.05, snow)
			_scatter_prop("boulder_01", 26, _spot_land(0.5, 1.2, 1.5), 2.0, 4.5, 0.0, true, 0.9, 0.05, snow)
			_scatter_prop("tree_stump_01", 20, _spot_land(1.0, 0.7, 1.0), 1.0, 1.5, 0.0, true, 0.8, 0.05, snow)
			_scatter_prop("dead_tree_trunk", 12, _spot_land(1.0, 0.5, 2.0, 2.5), 1.3, 2.0, 0.0, true, 0.0, 0.05, snow)
			_scatter_prop("shrub_04", int(120 * dn), _spot_land(1.0, 0.8, 0.0, 0.5), 2.5, 4.0, 40.0, false)
		"sea":
			var inland := func(rr: RandomNumberGenerator) -> Vector3:
				var q: Vector3 = _spot_land(3.0, 0.8, 0.5).call(rr)
				return q
			var shore := func(rr: RandomNumberGenerator) -> Vector3:
				var q: Vector3 = _spot_land(0.5, 0.8, 1.0).call(rr)
				return q if q != Vector3.INF and q.y < 2.2 else Vector3.INF
			_scatter_prop("rock_moss_set_01", 45, _spot_land(-0.8, 1.2, 0.5), 0.6, 2.2, 0.0, true, 0.8)
			_scatter_prop("rock_moss_set_02", 45, _spot_land(-0.8, 1.2, 0.5), 0.6, 2.2, 0.0, true, 0.8)
			var c := island.habitat("cliff")
			_scatter_prop("boulder_01", 16, _spot_in(c["center"], c["radius"] + 6.0, 1.0), 2.0, 4.0, 0.0, true, 0.9)
			_scatter_prop("shrub_02", int(80 * dn), inland, 0.8, 1.3, 90.0, true)
			_scatter_prop("shrub_sorrel_01", int(300 * dn), inland, 4.0, 7.0, 35.0, false)
			_scatter_prop("dead_tree_trunk", 10, shore, 1.0, 1.6, 0.0, true)
			_scatter_prop("dead_tree_trunk_02", 8, shore, 0.8, 1.2, 0.0, true)
		_:
			_scatter_prop("rock_moss_set_01", 45, _spot_land(-0.5, 1.2, 0.5), 0.6, 2.0, 0.0, true, 0.8)
			_scatter_prop("rock_moss_set_02", 45, _spot_land(-0.5, 1.2, 0.5), 0.6, 2.0, 0.0, true, 0.8)
			var hill := func(r: RandomNumberGenerator) -> Vector3:
				var p: Vector3 = _spot_land(3.0, 1.2, 1.5).call(r)
				return p if p != Vector3.INF and Vector2(p.x, p.z).distance_to(island.hill) < 45.0 else Vector3.INF
			_scatter_prop("boulder_01", 14, hill, 2.0, 3.6, 0.0, true, 0.9)
			_scatter_prop("boulder_01", 6, _spot_land(0.2, 1.0, 1.0), 1.5, 2.5, 0.0, true, 0.9)
			_scatter_prop("shrub_02", int(90 * dn), _spot_under_trees(6.0), 0.8, 1.3, 90.0, true)
			_scatter_prop("fern_02", int(300 * dn), _spot_under_trees(5.0), 0.9, 1.5, 50.0, false)
			_scatter_prop("shrub_03", int(250 * dn), _spot_land(1.0, 0.8, 0.0, 0.5), 2.0, 3.5, 40.0, false)
			_scatter_prop("shrub_sorrel_01", int(400 * dn), _spot_land(1.0, 0.8, 0.0, 0.5), 4.0, 7.0, 35.0, false)
			var m := island.habitat("meadow")
			_scatter_prop("dandelion_01", int(450 * dn), _spot_in(m["center"], m["radius"], 1.0), 2.5, 4.0, 45.0, false)
			_scatter_prop("flower_ursinia", int(350 * dn), _spot_in(m["center"], m["radius"] + 6.0, 1.0), 2.0, 3.2, 45.0, false)
			var b := island.habitat("burrow")
			_scatter_prop("nettle_plant", int(160 * dn), _spot_in(b["center"], b["radius"] + 4.0, 1.0), 2.5, 4.0, 45.0, false)
			_scatter_prop("tree_stump_01", 10, _spot_land(1.2, 0.6, 1.0), 1.0, 1.4, 0.0, true, 0.8)
			_scatter_prop("dead_tree_trunk", 6, _spot_land(1.2, 0.5, 2.0, 2.5), 1.2, 1.8, 0.0, true)


# ------------------------------------------------------------------ 草

func _tuft_mesh(w: float, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cnt := [0]
	for k in 3:
		var a := k * PI / 3.0
		var right := Vector3(cos(a), 0, sin(a))
		var base := Vector3(-sin(a), 0, cos(a)) * 0.04 * (k - 1)
		_card(st, cnt, base, Vector3.UP, right, w, h, Vector3(0, -10, 0), 1.0, Color.WHITE)
	return st.commit()


func _grass_mat(tex: String, sway: float, fade: float, glow := Color.BLACK) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = GRASS_SHADER
	sm.set_shader_parameter("glow", glow)
	sm.set_shader_parameter("grass_tex", load(FOLIAGE + tex + ".png"))
	sm.set_shader_parameter("sway", sway)
	sm.set_shader_parameter("fade_start", fade * 0.65)
	sm.set_shader_parameter("fade_end", fade)
	return sm


func _grass() -> void:
	var fade: float = [32.0, 45.0, 60.0][quality]
	var r := RandomNumberGenerator.new()
	r.seed = island.map_seed + 400
	var xs := []
	var cols := []
	var base_count: int = {"island": 50000, "forest": 22000, "deepforest": 20000, "snow": 7000, "sea": 32000}[biome]
	var target := int(base_count * _density())
	var tries := 0
	var meadow := island.habitat("meadow")
	var grove := island.habitat("grove")
	while xs.size() < target and tries < target * 5:
		tries += 1
		var x := r.randf_range(-150, 150)
		var z := r.randf_range(-150, 150)
		var h := island.height_at(x, z)
		if h < 1.0 or island.slope_at(x, z) > 0.7:
			continue
		var pd := path_d(x, z)
		if pd < 0.9 or (pd < 1.8 and r.randf() < 0.7):
			continue
		var s := r.randf_range(0.7, 1.25)
		var c := Color(1, 1, 1).lerp(Color(0.82, 0.92, 0.7), r.randf())
		var p2 := Vector2(x, z)
		if biome == "snow":
			# 雪地：只有几丛枯黄的草从雪里冒出来，冰原上没有
			if h < 1.4 or _patch.get_noise_2d(x * 2.0, z * 2.0) < 0.1 or island.habitat_at(Vector3(x, h, z)) == "icefield":
				continue
			s *= 0.75
			c = Color(1.75, 1.0, 1.3).lerp(Color(1.55, 1.05, 1.15), r.randf())
		elif biome == "sea":
			if h < 2.6:
				continue
			c = Color(1.05, 1.05, 0.8).lerp(Color(0.85, 1.0, 0.7), r.randf())
		elif forest:
			# 森林里草只长在有光的地方：古树林空地、水边、小路两旁
			var near := island.arena != Vector2.INF and p2.distance_to(island.arena) < 26.0
			for pd2 in island.ponds:
				if p2.distance_to(pd2["center"]) < float(pd2["radius"]) + 9.0:
					near = true
			if pd < 5.0:
				near = true
			if not near and r.randf() > 0.12:
				continue
			c = Color(1.0, 0.92, 0.78).lerp(Color(0.85, 0.95, 0.65), r.randf())
			if biome == "deepforest":
				c = Color(0.5, 0.75, 0.75).lerp(Color(0.4, 0.62, 0.7), r.randf())
		else:
			if meadow.size() > 0 and p2.distance_to(meadow["center"]) < float(meadow["radius"]):
				s *= 1.5
				c = Color(1.08, 1.05, 0.82)
			if h < 1.6:
				c = c * Color(1.05, 1.0, 0.85)
		var b := Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(s, s * r.randf_range(0.8, 1.2), s))
		xs.append(Transform3D(b, Vector3(x, h - 0.04, z)))
		cols.append(c)
	var mat := _grass_mat("grass_tuft_dry" if (biome in ["forest", "snow"]) else "grass_tuft", 0.22, fade)
	_scatter(_tuft_mesh(0.95, 0.62), xs, cols, fade + 6.0, false, 32.0, mat)


# ------------------------------------------------------------------ 第一章：兔子洞、月光花丛、芦苇

func _burrows() -> void:
	var dirt := _surface("dirt", Color(0.9, 0.8, 0.7), 0.6)
	var hole := U.mat(Color(0.03, 0.02, 0.015), 1.0)
	var hb := island.habitat("burrow")
	for b in hb["points"]:
		var base: Vector3 = b
		U.part(root, U.sphere(1.0, 14, 8), dirt, base + Vector3(0, -0.2, 0), Vector3.ZERO, Vector3(1.7, 0.6, 1.7))
		U.part(root, U.cyl(0.5, 0.42, 0.08, 16), hole, base + Vector3(0, 0.37, 0), Vector3.ZERO, Vector3.ONE, false)
		for k in 3:
			var a := rng.randf() * TAU
			var rp := base + Vector3(cos(a) * 1.9, 0.0, sin(a) * 1.9)
			U.part(root, U.sphere(0.25, 8, 5), _stone(), rp, Vector3(rng.randf(), rng.randf(), 0), Vector3(1.3, 0.7, 1.0))


func _moon_flowers(type: String) -> void:
	var hb := island.habitat(type)
	var c: Vector2 = hb["center"]
	var rad: float = hb["radius"]
	_scatter_prop("periwinkle_plant", int(260 * _density()) + 60, _spot_in(c, rad, 0.8), 2.0, 3.2, 60.0, false)
	# 会发光的月光花：细茎 + 发光花苞
	var xs := []
	var stems := []
	var cols := []
	for i in 260:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * rad
		var x := c.x + cos(a) * d
		var z := c.y + sin(a) * d
		var h := island.height_at(x, z)
		var s := rng.randf_range(0.7, 1.3)
		stems.append(Transform3D(Basis().scaled(Vector3(s, s, s)), Vector3(x, h + 0.25 * s, z)))
		xs.append(Transform3D(Basis().scaled(Vector3(s, s * 0.7, s)), Vector3(x, h + 0.52 * s, z)))
		var pal := [Color(0.85, 0.9, 1.0), Color(0.75, 0.7, 1.0), Color(0.65, 0.85, 1.0), Color(1.0, 0.85, 0.97)]
		cols.append(pal[rng.randi() % pal.size()])
	_multimesh(U.cyl(0.01, 0.014, 0.5, 4), stems, [], false, U.mat(Color(0.25, 0.42, 0.2)))
	var fm := StandardMaterial3D.new()
	fm.vertex_color_use_as_albedo = true
	fm.vertex_color_is_srgb = true
	fm.emission_enabled = true
	fm.emission = Color(0.55, 0.6, 1.0)
	fm.emission_energy_multiplier = 1.6
	_multimesh(U.sphere(0.07, 8, 4), xs, cols, false, fm)
	_motes(island.ground_point(c.x, c.y) + Vector3(0, 1.5, 0), Vector3(rad, 1.5, rad), 70, Color(0.7, 0.8, 1.6), 0.07)


func _reeds() -> void:
	var xs := []
	var cols := []
	var tries := 0
	while xs.size() < int(2600 * _density()) and tries < 60000:
		tries += 1
		var a := rng.randf() * TAU
		var rr := rng.randf_range(70, 150)
		var x := cos(a) * rr
		var z := sin(a) * rr
		var h := island.height_at(x, z)
		if h > 0.7 or h < -0.8:
			continue
		if absf(x - island.dock_start.x) < 6.0 and z > 0:
			continue
		var s := rng.randf_range(0.9, 1.4)
		xs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * 0.8, s * 2.4, s * 0.8)), Vector3(x, h - 0.05, z)))
		cols.append(Color(0.8, 0.85, 0.6).lerp(Color(1.0, 0.95, 0.7), rng.randf()))
	_scatter(_tuft_mesh(0.8, 0.62), xs, cols, 70.0, false, 40.0, _grass_mat("grass_tuft_dry", 0.12, 70.0))


# ------------------------------------------------------------------ 第二章：狼穴、泥潭、古树林、毒沼

## 一片“洞口”栖息地：每个洞口背后堆三块大石头围成半圆，中间一个黑洞
func _dens_for(type: String, scale: float, snowy: bool) -> void:
	var hb := island.habitat(type)
	if hb.is_empty():
		return
	var hc: Vector2 = hb["center"]
	var rocks := _prop("boulder_01")
	var hole := U.mat(Color(0.02, 0.015, 0.01), 1.0)
	var snow := _snow_overlay() if snowy else null
	for b in hb["points"]:
		var p: Vector3 = b
		var out := Vector2(p.x, p.z) - hc
		out = out.normalized() if out.length() > 0.5 else Vector2(1, 0)
		var back := Vector3(out.x, 0, out.y)
		var yaw := atan2(back.x, back.z)
		for k in 3:
			var a := yaw + (k - 1) * 0.9
			var q := p + Vector3(sin(a), 0, cos(a)) * 2.6 * scale
			q.y = island.height_at(q.x, q.z)
			var s := rng.randf_range(2.6, 3.4) * scale
			if rocks.size() > 0:
				var v: Dictionary = rocks[0]
				var ry := Basis(Vector3.UP, rng.randf() * TAU)
				var sc := Vector3(s, s * 1.2, s)
				var mi := MeshInstance3D.new()
				mi.mesh = v["mesh"]
				mi.transform = Transform3D(ry.scaled(sc) * (v["basis"] as Basis), q + ry * ((v["offset"] as Vector3) * sc) - Vector3(0, 0.3, 0))
				if snow:
					mi.material_overlay = snow
				root.add_child(mi)
			var sh := SphereShape3D.new()
			sh.radius = 1.3 * s * 0.5
			_add_collider(sh, Transform3D(Basis(), q + Vector3(0, 0.6, 0)))
		var hm := U.part(root, U.sphere(1.0, 16, 8), hole, p + back * 1.2 * scale + Vector3(0, 0.3, 0), Vector3(0, yaw, 0), Vector3(1.2, 0.9, 0.5) * scale, false)
		hm.name = "DenHole"
		if type in ["den", "nest", "snowden"]:
			for k in 2:
				var bp := p + Vector3(rng.randf_range(-1.5, 1.5), 0.05, rng.randf_range(-1.5, 1.5))
				U.part(root, U.cyl(0.03, 0.03, 0.5, 5), U.mat(Color(0.85, 0.82, 0.72)), bp, Vector3(PI * 0.5, rng.randf() * TAU, 0), Vector3.ONE, false)


func _mud() -> void:
	var hb := island.habitat("mud")
	var c: Vector2 = hb["center"]
	var mud_mat := U.mat(Color(0.25, 0.2, 0.15), 0.2)
	for i in 14:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * (float(hb["radius"]) - 3.0)
		var p := island.ground_point(c.x + cos(a) * d, c.y + sin(a) * d)
		var mi := U.part(root, U.sphere(0.18, 10, 6), mud_mat, p, Vector3.ZERO, Vector3.ONE, false)
		mi.set_meta("phase", rng.randf() * 4.0)
		mi.set_meta("base", p)
		_bubbles.append(mi)
	# 泥潭边插几根枯枝
	for i in 8:
		var a := rng.randf() * TAU
		var d := float(hb["radius"]) + rng.randf_range(-2, 2)
		var p := island.ground_point(c.x + cos(a) * d, c.y + sin(a) * d)
		U.part(root, U.cyl(0.03, 0.08, rng.randf_range(1.2, 2.4), 5), _wood(Color(0.6, 0.5, 0.4)), p + Vector3(0, 0.6, 0), Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4)))


func _grove() -> void:
	if island.ancient_tree == Vector3.INF:
		return
	var t := island.ancient_tree
	var r := RandomNumberGenerator.new()
	r.seed = island.map_seed + 500
	var star := biome == "deepforest"
	var bark := _bark(Color(0.62, 0.55, 0.5) if not star else Color(0.4, 0.42, 0.5))
	var leaves := _leaves("leaf_autumn", Color(1.05, 0.95, 0.8), Color(0.8, 0.4, 0.1))
	if star:
		leaves = _leaves("leaf_dark", Color(0.5, 0.85, 1.1), Color(0.2, 0.5, 1.0))
	var tree: Dictionary = _broad_tree(r, 40.0 if star else 34.0, 1.3 if star else 1.25, bark, leaves)
	var mi := MeshInstance3D.new()
	mi.name = "AncientTree"
	mi.mesh = tree["mesh"]
	mi.position = t
	mi.scale = Vector3(1.6, 1.0, 1.6)
	root.add_child(mi)
	_add_trunk(Vector2(t.x, t.z), 3.0)
	_cyl_collider(t + Vector3(0, -0.5, 0), 2.6, 16.0)
	# 盘根错节的树根
	var roots := _prop("root_cluster_01")
	if roots.size() > 0:
		var v: Dictionary = roots[0]
		for k in 3:
			var yaw := Basis(Vector3.UP, TAU * k / 3.0 + 0.3)
			var s := 2.2
			var rm := MeshInstance3D.new()
			rm.mesh = v["mesh"]
			var off := yaw * Vector3(0, 0, 2.2)
			rm.transform = Transform3D(yaw.scaled(Vector3(s, s, s)) * (v["basis"] as Basis), t + off + yaw * ((v["offset"] as Vector3) * s) - Vector3(0, 0.25, 0))
			root.add_child(rm)
	# 古树林里一圈发光的蘑菇
	var g := {"center": island.arena, "radius": 20.0}
	var caps := []
	var stems := []
	var cols := []
	for i in (90 if not star else 240):
		var a := r.randf() * TAU
		var d := r.randf_range(4.0, float(g["radius"]) + (6.0 if not star else 60.0))
		var p := island.ground_point(g["center"].x + cos(a) * d, g["center"].y + sin(a) * d)
		if r.randf() < 0.5:
			var a2 := r.randf() * TAU
			p = island.ground_point(t.x + cos(a2) * r.randf_range(3.5, 7.0), t.z + sin(a2) * r.randf_range(3.5, 7.0))
		var s := r.randf_range(0.6, 1.6)
		stems.append(Transform3D(Basis().scaled(Vector3(s, s, s)), p + Vector3(0, 0.1 * s, 0)))
		caps.append(Transform3D(Basis().scaled(Vector3(s, s * 0.45, s)), p + Vector3(0, 0.2 * s, 0)))
		cols.append(Color(0.4, 0.9, 1.0).lerp(Color(0.7, 0.5, 1.0), r.randf()))
	_multimesh(U.cyl(0.025, 0.035, 0.2, 5), stems, [], false, U.mat(Color(0.85, 0.82, 0.75)))
	var cm := StandardMaterial3D.new()
	cm.vertex_color_use_as_albedo = true
	cm.emission_enabled = true
	cm.emission = Color(0.35, 0.8, 1.0)
	cm.emission_energy_multiplier = 2.2
	_multimesh(U.sphere(0.12, 10, 5), caps, cols, false, cm)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.5, 0.8, 1.0)
	glow.light_energy = 1.5
	glow.omni_range = 14.0
	glow.position = t + Vector3(0, 2.0, 5.0)
	root.add_child(glow)
	_motes(Vector3(g["center"].x, t.y + 3.0, g["center"].y - 5.0), Vector3(16, 3, 16), 90, Color(1.6, 1.3, 0.6), 0.06)


func _swamp_plants() -> void:
	var lily := U.mat(Color(0.28, 0.45, 0.2), 0.6)
	var xs := []
	for p in island.ponds:
		var c: Vector2 = p["center"]
		for i in 40:
			var a := rng.randf() * TAU
			var d := sqrt(rng.randf()) * (float(p["radius"]) - 1.0)
			var x := c.x + cos(a) * d
			var z := c.y + sin(a) * d
			if island.height_at(x, z) > -0.3:
				continue
			var s := rng.randf_range(0.6, 1.3)
			xs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, 1, s)), Vector3(x, Island.WATER_Y + 0.03, z)))
		_motes(Vector3(c.x, 1.5, c.y), Vector3(p["radius"], 1.2, p["radius"]), 40, Color(1.5, 1.6, 0.5), 0.06)
	_multimesh(U.cyl(0.35, 0.35, 0.02, 10), xs, [], false, lily)
	# 水边的枯草（芦苇）
	var reeds := []
	var cols := []
	for p in island.ponds:
		var c: Vector2 = p["center"]
		for i in int(160 * _density()):
			var a := rng.randf() * TAU
			var d := float(p["radius"]) + rng.randf_range(-3.0, 2.0)
			var x := c.x + cos(a) * d
			var z := c.y + sin(a) * d
			var h := island.height_at(x, z)
			if h > 0.8 or h < -0.8:
				continue
			var s := rng.randf_range(0.9, 1.4)
			reeds.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * 0.8, s * 2.4, s * 0.8)), Vector3(x, h - 0.05, z)))
			cols.append(Color(0.9, 0.85, 0.6))
	_scatter(_tuft_mesh(0.8, 0.62), reeds, cols, 70.0, false, 40.0, _grass_mat("grass_tuft_dry", 0.12, 70.0))


## 魔蛛巢：洞口拉满白色蛛丝，地上有卵囊
func _webs(type: String) -> void:
	var hb := island.habitat(type)
	if hb.is_empty():
		return
	var silk := U.mat(Color(0.9, 0.9, 0.95, 1.0), 0.6)
	var egg := U.mat(Color(0.9, 0.88, 0.8), 0.4, 0.3)
	for b in hb["points"]:
		var p: Vector3 = b
		for k in 7:
			var a := TAU * k / 7.0 + rng.randf_range(-0.2, 0.2)
			var top := p + Vector3(cos(a) * 2.4, rng.randf_range(1.8, 3.2), sin(a) * 2.4)
			var mid := (p + Vector3(0, 0.3, 0) + top) * 0.5
			var len := (top - p).length()
			var strand := U.part(root, U.cyl(0.012, 0.012, len, 4), silk, mid, Vector3.ZERO, Vector3.ONE, false)
			strand.basis = Basis.looking_at((top - p).normalized(), Vector3.UP if absf((top - p).normalized().y) < 0.95 else Vector3.RIGHT) * Basis(Vector3.RIGHT, PI / 2)
		for k in 3:
			var ep := p + Vector3(rng.randf_range(-1.8, 1.8), 0.2, rng.randf_range(-1.8, 1.8))
			ep.y = island.height_at(ep.x, ep.z) + 0.2
			U.part(root, U.sphere(0.28, 10, 6), egg, ep, Vector3.ZERO, Vector3(1, 1.3, 1), false)


## 星斗大森林：一片片会发光的蓝银草（唐三的武魂）
func _blue_silver_grass() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = island.map_seed + 700
	var xs := []
	var cols := []
	var centers: Array[Vector2] = []
	for i in 40:
		var c := Vector2(r.randf_range(-130, 130), r.randf_range(-130, 130))
		if island.height_at(c.x, c.y) > 1.2:
			centers.append(c)
	var g := island.habitat("glade")
	if not g.is_empty():
		for i in 6:
			centers.append(g["center"] + Vector2(r.randf_range(-12, 12), r.randf_range(-12, 12)))
	for c in centers:
		for k in int(160 * _density()) + 30:
			var a := r.randf() * TAU
			var d := sqrt(r.randf()) * r.randf_range(3.0, 7.0)
			var x := c.x + cos(a) * d
			var z := c.y + sin(a) * d
			var h := island.height_at(x, z)
			if h < 1.0 or path_d(x, z) < 1.0:
				continue
			var s := r.randf_range(0.7, 1.2)
			xs.append(Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(s * 0.8, s * 1.3, s * 0.8)), Vector3(x, h - 0.04, z)))
			cols.append(Color(0.45, 0.75, 1.3).lerp(Color(0.6, 0.9, 1.4), r.randf()))
	var fade: float = [32.0, 45.0, 60.0][quality]
	_scatter(_tuft_mesh(0.8, 0.62), xs, cols, fade + 20.0, false, 32.0, _grass_mat("grass_tuft", 0.25, fade + 14.0, Color(0.15, 0.4, 1.0)))
	for c in centers.slice(0, 12):
		_motes(island.ground_point(c.x, c.y) + Vector3(0, 1.2, 0), Vector3(6, 1.2, 6), 20, Color(0.5, 0.8, 1.6), 0.06)


## 冰晶：六棱柱，淡蓝色，会微微发光
func _ice_crystals(type: String, count: int, scale: float) -> void:
	var hb := island.habitat(type)
	if hb.is_empty():
		return
	var c: Vector2 = hb["center"]
	var xs := []
	for i in count:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * (float(hb["radius"]) + 6.0)
		var x := c.x + cos(a) * d
		var z := c.y + sin(a) * d
		if path_d(x, z) < 1.5:
			continue
		var h := island.height_at(x, z)
		for k in rng.randi_range(2, 4):
			var s := rng.randf_range(0.6, 1.6) * scale
			var tilt := Basis.from_euler(Vector3(rng.randf_range(-0.5, 0.5), rng.randf() * TAU, rng.randf_range(-0.5, 0.5)))
			xs.append(Transform3D(tilt.scaled(Vector3(s, s * rng.randf_range(1.2, 2.4), s)), Vector3(x + rng.randf_range(-0.5, 0.5), h + 0.3 * s, z + rng.randf_range(-0.5, 0.5))))
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.7, 0.9, 1.0, 0.75)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic_specular = 0.9
	m.emission_enabled = true
	m.emission = Color(0.3, 0.65, 1.0)
	m.emission_energy_multiplier = 0.8
	m.rim_enabled = true
	m.rim = 0.6
	_multimesh(U.cyl(0.05, 0.3, 1.0, 6), xs, [], true, m)
	_motes(island.ground_point(c.x, c.y) + Vector3(0, 2.0, 0), Vector3(hb["radius"], 2.0, hb["radius"]), 50, Color(0.8, 0.95, 1.6), 0.06)


## 冰湖：岸边漂着一块块浮冰
func _ice_floes_build() -> void:
	var xs := []
	var tries := 0
	while xs.size() < 160 and tries < 20000:
		tries += 1
		var a := rng.randf() * TAU
		var rr := rng.randf_range(80, 170)
		var x := cos(a) * rr
		var z := sin(a) * rr
		var h := island.height_at(x, z)
		if h > -0.4 or h < -5.0:
			continue
		if absf(x - island.dock_start.x) < 8.0 and z > 0:
			continue
		var s := rng.randf_range(1.2, 4.0)
		xs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, 1.0, s * rng.randf_range(0.6, 1.0))), Vector3(x, Island.WATER_Y + 0.05, z)))
	var m := _surface("snow", Color(0.95, 0.98, 1.0), 0.3, 0.6)
	_multimesh(U.cyl(1.0, 1.05, 0.3, 7), xs, [], false, m)


## 飘雪：跟着镜头走的一团雪花
func _snowfall_build() -> void:
	var p := GPUParticles3D.new()
	p.amount = [1200, 2200, 3500][quality]
	p.lifetime = 8.0
	p.preprocess = 8.0
	p.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 50, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(35, 4, 35)
	pm.direction = Vector3(0.2, -1, 0.1)
	pm.spread = 15.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 2.2
	pm.gravity = Vector3(0, -0.4, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 6.0
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, 0.85)
	var dot := GradientTexture2D.new()
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(0.5, 0.0)
	var dg := Gradient.new()
	dg.set_color(0, Color(1, 1, 1, 1))
	dg.set_color(1, Color(1, 1, 1, 0))
	dot.gradient = dg
	dot.width = 16
	dot.height = 16
	m.albedo_texture = dot
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	_snowfall = p


## 海神岛：浅海里一丛丛珊瑚（透过海水能看到）
func _corals() -> void:
	var branches := []
	var bcols := []
	var brains := []
	var rcols := []
	var tries := 0
	var pal := [Color(1.0, 0.45, 0.55), Color(1.0, 0.65, 0.3), Color(0.75, 0.45, 1.0), Color(1.0, 0.9, 0.4), Color(0.35, 0.9, 0.85)]
	while branches.size() < 1400 and tries < 40000:
		tries += 1
		var x := rng.randf_range(-165, 165)
		var z := rng.randf_range(-165, 165)
		var h := island.height_at(x, z)
		if h > -0.8 or h < -3.2:
			continue
		var col: Color = pal[rng.randi() % pal.size()]
		for k in rng.randi_range(3, 7):
			var s := rng.randf_range(0.5, 1.2)
			var tilt := Basis.from_euler(Vector3(rng.randf_range(-0.6, 0.6), rng.randf() * TAU, rng.randf_range(-0.6, 0.6)))
			branches.append(Transform3D(tilt.scaled(Vector3(s, s, s)), Vector3(x + rng.randf_range(-0.6, 0.6), h + 0.3 * s, z + rng.randf_range(-0.6, 0.6))))
			bcols.append(col)
		if rng.randf() < 0.5:
			var bs := rng.randf_range(0.4, 0.9)
			brains.append(Transform3D(Basis().scaled(Vector3(bs, bs * 0.6, bs)), Vector3(x + 0.8, h + 0.1, z - 0.5)))
			rcols.append(pal[rng.randi() % pal.size()])
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.7
	m.emission_enabled = true
	m.emission = Color(0.15, 0.1, 0.1)
	_multimesh(U.cyl(0.03, 0.08, 0.7, 5), branches, bcols, false, m)
	_multimesh(U.sphere(0.5, 10, 6), brains, rcols, false, m)


## 海神岛：沙滩上的贝壳和海星
func _beach() -> void:
	var xs := []
	var cols := []
	var tries := 0
	while xs.size() < 500 and tries < 20000:
		tries += 1
		var x := rng.randf_range(-160, 160)
		var z := rng.randf_range(-160, 160)
		var h := island.height_at(x, z)
		if h < 0.3 or h > 1.6:
			continue
		var s := rng.randf_range(0.08, 0.16)
		xs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * 0.35, s * 1.3)), Vector3(x, h + 0.02, z)))
		cols.append([Color(1.0, 0.95, 0.9), Color(1.0, 0.75, 0.7), Color(1.0, 0.55, 0.3)][rng.randi() % 3])
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.5
	_scatter(U.sphere(1.0, 8, 4), xs, cols, 50.0, false, 40.0, m)


## 萤火虫 / 花粉：慢慢飘的小光点
func _motes(center: Vector3, extents: Vector3, count: int, color: Color, size: float) -> void:
	var p := GPUParticles3D.new()
	p.amount = count
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.position = center
	p.visibility_aabb = AABB(-extents - Vector3.ONE * 3.0, (extents + Vector3.ONE * 3.0) * 2.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.gravity = Vector3(0, 0.03, 0)
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.35
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.2
	pm.turbulence_noise_scale = 4.0
	pm.turbulence_influence_min = 0.03
	pm.turbulence_influence_max = 0.1
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0))
	grad.set_color(1, Color(1, 1, 1, 0))
	grad.add_point(0.2, Color(1, 1, 1, 1))
	grad.add_point(0.5, Color(1, 1, 1, 0.3))
	grad.add_point(0.8, Color(1, 1, 1, 1))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	var dot := GradientTexture2D.new()
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(0.5, 0.0)
	var dg := Gradient.new()
	dg.set_color(0, Color(1, 1, 1, 1))
	dg.set_color(1, Color(1, 1, 1, 0))
	dot.gradient = dg
	dot.width = 32
	dot.height = 32
	m.albedo_texture = dot
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)


# ------------------------------------------------------------------ 码头、船

func _dock() -> void:
	var wood := _wood()
	var dark := _wood(Color(0.7, 0.58, 0.45))
	var a := island.dock_start
	var b := island.dock_end
	var len := a.distance_to(Vector3(b.x, a.y, b.z))
	var mid := (a + Vector3(b.x, b.y, b.z)) * 0.5
	mid.y = island.dock_y - 0.125
	# 一块块木板，中间有缝
	var n := int(len / 0.55)
	for k in n:
		var z := a.z + (k + 0.5) * len / n
		var plank := U.part(root, U.box(Vector3(3.2, 0.12, len / n - 0.06)), wood, Vector3(a.x, island.dock_y - 0.06 + rng.randf_range(-0.015, 0.015), z), Vector3(0, rng.randf_range(-0.01, 0.01), 0))
		plank.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for side in [-1.5, 1.5]:
		U.part(root, U.box(Vector3(0.18, 0.2, len)), dark, Vector3(a.x + side, island.dock_y - 0.22, mid.z))
	var sh := BoxShape3D.new()
	sh.size = Vector3(3.2, 0.25, len)
	_add_collider(sh, Transform3D(Basis(), mid))
	for k in int(len / 3.0) + 1:
		for side in [-1.5, 1.5]:
			var p := Vector3(a.x + side, mid.y - 1.2, a.z + k * 3.0)
			U.part(root, U.cyl(0.14, 0.14, 3.2, 8), dark, p)
			# 桩子上的缆绳
			if k % 2 == 1:
				U.part(root, U.torus(0.12, 0.2, 12, 6), U.mat(Color(0.7, 0.62, 0.45)), p + Vector3(0, 1.25, 0), Vector3(PI * 0.5, 0, 0))
	# 码头上的灯笼杆
	for k in 2:
		var lp := Vector3(a.x - 1.4, island.dock_y, a.z + len * (0.35 + k * 0.5))
		U.part(root, U.cyl(0.05, 0.06, 2.4, 6), dark, lp + Vector3(0, 1.2, 0))
		_lantern(lp + Vector3(0, 2.3, 0), Color(1.0, 0.45, 0.2))


func _lantern(p: Vector3, color: Color) -> void:
	U.part(root, U.sphere(0.2, 10, 8), U.glow(color, 3.0), p, Vector3.ZERO, Vector3(1, 1.25, 1), false)
	U.part(root, U.cyl(0.08, 0.08, 0.06, 8), U.mat(Color(0.15, 0.1, 0.05)), p + Vector3(0, 0.27, 0))
	var l := OmniLight3D.new()
	l.light_color = color.lerp(Color(1, 0.8, 0.6), 0.4)
	l.light_energy = 1.4
	l.omni_range = 7.0
	l.position = p
	root.add_child(l)


## 乌篷船：拴在码头尽头旁边，坐上去就能去下一章
func _boat() -> void:
	var e := island.dock_end
	boat_pos = Vector3(e.x + 3.1, Island.WATER_Y, e.z - 2.5)
	boat = Node3D.new()
	boat.name = "Boat"
	boat.position = boat_pos
	root.add_child(boat)
	var hull_mat := _wood(Color(0.75, 0.55, 0.38)).duplicate() as StandardMaterial3D
	hull_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var L := 7.0
	var W := 1.9
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var secs := 12
	var ring := 7
	for i in secs + 1:
		var t := float(i) / secs
		var z := (t - 0.5) * L
		var wk := pow(sin(PI * clampf(t * 0.94 + 0.03, 0.0, 1.0)), 0.55)
		var rise := pow(absf(t - 0.5) * 2.0, 3.0) * 0.45
		for k in ring:
			var a := PI * float(k) / (ring - 1)
			var x := cos(a) * W * 0.5 * wk
			var y := -sin(a) * 0.62 * (0.35 + 0.65 * wk) + 0.35 + rise
			st.set_uv(Vector2(float(k) / (ring - 1), t * 3.0))
			st.add_vertex(Vector3(x, y, z))
	for i in secs:
		for k in ring - 1:
			var a0 := i * ring + k
			var b0 := a0 + ring
			for idx in [a0, b0, a0 + 1, a0 + 1, b0, b0 + 1]:
				st.add_index(idx)
	st.generate_normals()
	U.part(boat, st.commit(), hull_mat, Vector3.ZERO)
	# 船篷：竹篾编的黑色半圆篷
	var sp := SurfaceTool.new()
	sp.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 10
	for s in 2:
		for k in seg + 1:
			var a := PI * float(k) / seg
			sp.set_uv(Vector2(float(k) / seg * 2.0, s * 1.5))
			sp.add_vertex(Vector3(cos(a) * 0.85, 0.45 + sin(a) * 0.95, (s - 0.5) * 2.8))
	for k in seg:
		for idx in [k, k + seg + 1, k + 1, k + 1, k + seg + 1, k + seg + 2]:
			sp.add_index(idx)
	sp.generate_normals()
	var canopy := _surface("bark", Color(0.35, 0.3, 0.26), 2.0, 0.9).duplicate() as StandardMaterial3D
	canopy.cull_mode = BaseMaterial3D.CULL_DISABLED
	U.part(boat, sp.commit(), canopy, Vector3(0, 0, -0.3))
	# 座板、船桨、船头灯笼
	U.part(boat, U.box(Vector3(W * 0.8, 0.08, 0.4)), hull_mat, Vector3(0, 0.5, 2.0))
	U.part(boat, U.box(Vector3(W * 0.8, 0.08, 0.4)), hull_mat, Vector3(0, 0.5, -2.4))
	U.part(boat, U.cyl(0.03, 0.03, 3.2, 5), hull_mat, Vector3(0.7, 0.9, 2.6), Vector3(0.9, 0, 0.3))
	U.part(boat, U.cyl(0.03, 0.03, 1.4, 5), hull_mat, Vector3(0, 1.2, -L * 0.45))
	var lamp := U.part(boat, U.sphere(0.18, 10, 8), U.glow(Color(1.0, 0.45, 0.2), 3.0), Vector3(0, 1.95, -L * 0.45), Vector3.ZERO, Vector3(1, 1.2, 1), false)
	lamp.name = "Lamp"
	var sh := BoxShape3D.new()
	sh.size = Vector3(W, 0.6, L)
	_add_collider(sh, Transform3D(Basis(), boat_pos + Vector3(0, 0.3, 0)))


# ------------------------------------------------------------------ 暗器铺

func _shop() -> void:
	var s := island.shop_pos
	var hut := Node3D.new()
	hut.name = "Shop"
	hut.position = s
	hut.rotation.y = island.shop_yaw
	root.add_child(hut)
	var wood := _wood()
	var dark := _wood(Color(0.65, 0.5, 0.38))
	var red := U.mat(Color(0.62, 0.14, 0.1), 0.7)
	var gold := U.mat(Color(0.95, 0.75, 0.35), 0.4, 0.0, 0.6)
	if forest or biome == "snow":
		# 商人帐篷：四根杆子 + 布顶 + 货箱
		var cloth := _cloth(Color(0.62, 0.2, 0.12))
		for p in [Vector3(-2.6, 0, -2.0), Vector3(2.6, 0, -2.0), Vector3(-2.6, 0, 2.0), Vector3(2.6, 0, 2.0)]:
			U.part(hut, U.cyl(0.08, 0.09, 3.0, 6), dark, p + Vector3(0, 1.5, 0))
		var roof := U.cyl(0.0, 4.3, 1.8, 4)
		U.part(hut, roof, cloth, Vector3(0, 3.8, 0), Vector3(0, PI * 0.25, 0), Vector3(1.0, 1.0, 0.8))
		U.part(hut, U.box(Vector3(5.4, 2.2, 0.05)), cloth, Vector3(0, 2.0, -2.05))
		for p in [Vector3(-1.8, 0.4, -1.2), Vector3(-1.1, 0.4, -1.5), Vector3(1.9, 0.35, -1.3), Vector3(-1.5, 1.1, -1.35)]:
			U.part(hut, U.box(Vector3(0.8, 0.8, 0.8) * (0.9 if p.y > 1.0 else 1.0)), dark, p, Vector3(0, rng.randf_range(-0.3, 0.3), 0))
		U.part(hut, U.box(Vector3(3.6, 0.95, 0.9)), wood, Vector3(0, 0.48, 1.3))
		var sh := BoxShape3D.new()
		sh.size = Vector3(5.4, 3.0, 4.2)
		_add_collider(sh, hut.transform * Transform3D(Basis(), Vector3(0, 1.5, -0.2)))
		shop_door = hut.transform * Vector3(0, 1.0, 2.6)
		_lantern(hut.transform * Vector3(-2.6, 2.6, 2.1), Color(1.0, 0.5, 0.2))
		_lantern(hut.transform * Vector3(2.6, 2.6, 2.1), Color(1.0, 0.5, 0.2))
	else:
		# 唐门小屋：木墙、红柱、灰瓦翘檐，门前一张柜台
		U.part(hut, U.box(Vector3(6.0, 3.0, 4.6)), wood, Vector3(0, 1.5, 0))
		U.part(hut, U.box(Vector3(6.4, 0.3, 5.0)), _stone(), Vector3(0, 0.1, 0))
		for x in [-3.0, 3.0]:
			for z in [-2.3, 2.3]:
				U.part(hut, U.cyl(0.16, 0.16, 3.2, 8), red, Vector3(x, 1.6, z))
		var roof := PrismMesh.new()
		roof.size = Vector3(7.6, 1.9, 6.0)
		var tiles := _surface("rock", Color(0.42, 0.42, 0.45), 1.6, 0.7)
		U.part(hut, roof, tiles, Vector3(0, 4.05, 0))
		# 翘起来的屋檐角
		for x in [-3.7, 3.7]:
			for z in [-2.9, 2.9]:
				U.part(hut, U.cyl(0.02, 0.1, 0.9, 5), tiles, Vector3(x, 3.35, z), Vector3(0.6 * signf(z), 0, -0.6 * signf(x)))
		U.part(hut, U.box(Vector3(1.3, 2.1, 0.12)), dark, Vector3(-1.6, 1.05, 2.31))
		# 柜台和陈列的暗器
		U.part(hut, U.box(Vector3(3.2, 1.0, 0.8)), dark, Vector3(1.0, 0.5, 2.9))
		U.part(hut, U.box(Vector3(3.3, 0.06, 0.9)), red, Vector3(1.0, 1.03, 2.9))
		var shown := ["zhuge", "kongque", "baoyu"]
		for i in shown.size():
			var w := WeaponModels.build_small(shown[i])
			w.position = Vector3(0.1 + i * 0.9, 1.12, 2.9)
			w.rotation = Vector3(0, PI * 0.5 + 0.2, PI * 0.5)
			w.scale = Vector3.ONE * 1.3
			hut.add_child(w)
		# 牌匾
		U.part(hut, U.box(Vector3(3.2, 0.8, 0.1)), dark, Vector3(0, 3.35, 2.42))
		U.part(hut, U.box(Vector3(3.0, 0.62, 0.02)), gold, Vector3(0, 3.35, 2.48))
		var hcs := BoxShape3D.new()
		hcs.size = Vector3(6.0, 4.5, 4.6)
		_add_collider(hcs, hut.transform * Transform3D(Basis(), Vector3(0, 2.2, 0)))
		var counter := BoxShape3D.new()
		counter.size = Vector3(3.2, 1.0, 0.8)
		_add_collider(counter, hut.transform * Transform3D(Basis(), Vector3(1.0, 0.5, 2.9)))
		shop_door = hut.transform * Vector3(1.0, 1.0, 4.0)
		_lantern(hut.transform * Vector3(-3.0, 2.7, 2.7), Color(1.0, 0.35, 0.18))
		_lantern(hut.transform * Vector3(3.0, 2.7, 2.7), Color(1.0, 0.35, 0.18))
	var tent := forest or biome == "snow"
	var sign := U.label3d("唐门 · 暗器铺", 72, Color(0.35, 0.12, 0.05) if not tent else Color(1.0, 0.86, 0.5), 6)
	sign.position = Vector3(0, 3.35, 2.53) if not tent else Vector3(0, 3.1, 2.3)
	sign.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sign.pixel_size = 0.0065
	sign.outline_modulate = Color(1.0, 0.85, 0.5, 0.5) if not tent else Color(0, 0, 0, 0.8)
	hut.add_child(sign)
	var sub := U.label3d("买暗器 · 升级 · 道具（按 F）", 40, Color(1.0, 0.95, 0.85))
	sub.position = Vector3(1.0, 2.1, 3.4) if not tent else Vector3(0, 2.4, 2.4)
	sub.pixel_size = 0.006
	hut.add_child(sub)


# ------------------------------------------------------------------ 祭坛

func _altar() -> void:
	var p := island.altar_pos
	var stone := _stone(Color(0.95, 0.93, 0.88))
	var dark := _stone(Color(0.6, 0.58, 0.55))
	var node := Node3D.new()
	node.name = "Altar"
	node.position = p
	root.add_child(node)
	U.part(node, U.cyl(3.4, 3.7, 0.6, 8), dark, Vector3(0, 0.0, 0))
	U.part(node, U.cyl(2.4, 2.6, 0.45, 8), stone, Vector3(0, 0.5, 0))
	var sh := CylinderShape3D.new()
	sh.radius = 3.5
	sh.height = 0.6
	_add_collider(sh, Transform3D(Basis(), p))
	var sh2 := CylinderShape3D.new()
	sh2.radius = 2.5
	sh2.height = 0.45
	_add_collider(sh2, Transform3D(Basis(), p + Vector3(0, 0.5, 0)))
	# 四根石柱，顶上有发光的符
	var rune_col := Color(0.55, 1.0, 0.7) if not forest else Color(1.0, 0.55, 0.3)
	for k in 4:
		var a := TAU * k / 4.0 + PI * 0.25
		var q := Vector3(cos(a) * 3.0, 0, sin(a) * 3.0)
		U.part(node, U.box(Vector3(0.45, 2.6, 0.45)), stone, q + Vector3(0, 1.4, 0))
		U.part(node, U.box(Vector3(0.6, 0.2, 0.6)), dark, q + Vector3(0, 2.75, 0))
		U.part(node, U.sphere(0.16, 10, 8), U.glow(rune_col, 3.5), q + Vector3(0, 3.05, 0), Vector3.ZERO, Vector3.ONE, false)
		_cyl_collider(p + q, 0.35, 2.8)
	# 香炉（鼎）
	var bronze := U.mat(Color(0.45, 0.35, 0.2), 0.45, 0.0, 0.7)
	U.part(node, U.cyl(0.55, 0.42, 0.55, 12), bronze, Vector3(0, 1.0, 0))
	for k in 3:
		var a := TAU * k / 3.0
		U.part(node, U.cyl(0.05, 0.07, 0.35, 6), bronze, Vector3(cos(a) * 0.35, 0.72, sin(a) * 0.35))
	for x in [-0.5, 0.5]:
		U.part(node, U.torus(0.08, 0.14, 12, 6), bronze, Vector3(x, 1.35, 0), Vector3(0, 0, PI * 0.5))
	# 地上的法阵
	var ring := U.part(node, U.torus(2.0, 2.12, 48, 4), U.glow(rune_col, 1.6), Vector3(0, 0.74, 0), Vector3.ZERO, Vector3(1, 0.1, 1), false)
	ring.name = "Ring"
	_altar_flame = Node3D.new()
	_altar_flame.position = Vector3(0, 1.3, 0)
	node.add_child(_altar_flame)
	U.part(_altar_flame, U.sphere(0.14, 8, 6), U.glow(Color(1.0, 0.6, 0.25), 3.0), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
	var l := OmniLight3D.new()
	l.light_color = rune_col.lerp(Color(1, 0.7, 0.4), 0.5)
	l.light_energy = 1.2
	l.omni_range = 9.0
	l.position = Vector3(0, 2.0, 0)
	node.add_child(l)
	_motes(p + Vector3(0, 2.5, 0), Vector3(0.4, 1.5, 0.4), 24, Color(1.2, 1.1, 1.0) * 0.5, 0.35)


# ------------------------------------------------------------------ 路牌

func _sign(pos: Vector2, title: String, sub: String, color: Color) -> void:
	var h := island.height_at(pos.x, pos.y)
	var wood := _wood(Color(0.9, 0.75, 0.6))
	U.part(root, U.cyl(0.07, 0.08, 2.4, 6), wood, Vector3(pos.x, h + 1.2, pos.y))
	U.part(root, U.box(Vector3(1.4, 0.35, 0.06)), wood, Vector3(pos.x, h + 2.0, pos.y), Vector3(0, rng.randf() * TAU, 0.05))
	var t := U.label3d(title, 64, color)
	t.pixel_size = 0.012
	t.position = Vector3(pos.x, h + 3.2, pos.y)
	root.add_child(t)
	var s := U.label3d(sub, 36, Color(0.95, 0.95, 0.9))
	s.pixel_size = 0.01
	s.position = Vector3(pos.x, h + 2.55, pos.y)
	root.add_child(s)


func _signs() -> void:
	var hub := Vector2(island.spawn.x, island.spawn.z - 38.0)
	var pal := [Color(0.6, 0.95, 0.85), Color(1.0, 0.8, 0.85), Color(0.85, 0.85, 1.0), Color(1.0, 0.75, 0.55), Color(0.75, 1.0, 0.7)]
	var i := 0
	for hb in island.habitats:
		var t := str(hb["type"])
		if not Data.HABITATS.has(t):
			continue
		var info: Dictionary = Data.HABITATS[t]
		var sp: Dictionary = Data.BEASTS[info["beast"]]
		var sub := "抛到这里 · %s%s" % [sp["name"], "（会反击）" if sp.has("hurt") else ""]
		var c: Vector2 = hb["center"]
		var dir := (hub - c).normalized()
		_sign(c + dir * (float(hb["radius"]) + 2.5) + Vector2(-dir.y, dir.x) * 3.0, str(info["name"]), sub, pal[i % pal.size()])
		i += 1
	# 水边
	var wsub := ""
	if island.water_types.size() > 1:
		var names := []
		for w in island.water_types:
			names.append("%s（%s）" % [Data.HABITATS[w]["name"], Data.BEASTS[Data.HABITATS[w]["beast"]]["name"]])
		wsub = "越往外越深：" + " → ".join(names)
	else:
		wsub = "抛进水里 · %s" % Data.BEASTS[Data.HABITATS[island.water_habitat]["beast"]]["name"]
	_sign(Vector2(island.dock_start.x - 3.5, island.dock_start.z - 2.0), str(Data.HABITATS[island.water_habitat]["name"]) if island.water_types.size() == 1 else "海", wsub, Color(0.55, 0.85, 1.0))
	for p in island.ponds.slice(0, 1):
		_sign(p["center"] + Vector2(p["radius"] + 3.0, -2.0), str(Data.HABITATS[island.water_habitat]["name"]), wsub, Color(0.6, 1.0, 0.8))
	if forest or biome == "snow":
		_sign(Vector2(island.shop_pos.x + 5.0, island.shop_pos.z + 3.0), "行脚商人", "唐门的暗器也能在这儿买", Color(1.0, 0.85, 0.5))
	_sign(Vector2(island.altar_pos.x + 4.5, island.altar_pos.z + 4.5), "祭坛", "按 F 召唤 Boss（要先完成前面的任务）", Color(1.0, 0.75, 0.45))


# ------------------------------------------------------------------ 装饰用的鸟和蛾子（不能打，只是让地图热闹点）

func _ambient_life() -> void:
	var centers: Array = []
	match biome:
		"island":
			var m := island.habitat("meadow")
			var f := island.habitat("flowers")
			centers = [[m["center"], "bird", 4, 14.0, 22.0, 10.0, 20.0], [f["center"], "moth", 3, 1.5, 3.5, 3.0, 8.0]]
		"forest":
			centers = [[island.arena, "bird", 3, 26.0, 36.0, 12.0, 20.0]]
		"deepforest":
			var ro := island.habitat("roost")
			centers = [[ro["center"], "bat", 5, 10.0, 18.0, 6.0, 14.0]]
		"sea":
			var c := island.habitat("cliff")
			centers = [[c["center"], "gull", 5, 16.0, 26.0, 12.0, 24.0], [Vector2(0, 60), "gull", 3, 12.0, 20.0, 20.0, 40.0]]
	for c in centers:
		var cc: Vector2 = c[0]
		for i in int(c[2]):
			var n := BeastModels.build(str(c[1]), 0)
			n.scale = Vector3.ONE * (0.6 if c[1] == "moth" else 0.8)
			n.set_meta("orbit", Vector4(cc.x, cc.y, rng.randf_range(c[5], c[6]), rng.randf_range(0.25, 0.5)))
			n.set_meta("phase", rng.randf() * TAU)
			n.set_meta("height", island.height_at(cc.x, cc.y) + rng.randf_range(c[3], c[4]))
			root.add_child(n)
			if c[1] == "moth":
				_moths.append(n)
			else:
				_birds.append(n)


func animate(t: float) -> void:
	for n in _birds + _moths:
		var o: Vector4 = n.get_meta("orbit")
		var ph: float = n.get_meta("phase")
		var a := t * o.w + ph
		var p := Vector3(o.x + cos(a) * o.z, n.get_meta("height") + sin(t * 0.7 + ph) * 1.2, o.y + sin(a) * o.z)
		n.look_at_from_position(p, p + Vector3(-sin(a), 0, cos(a)), Vector3.UP)
		BeastModels.animate(n, t + ph, true)
	if boat:
		boat.position.y = boat_pos.y + sin(t * 1.3) * 0.06
		boat.rotation = Vector3(sin(t * 0.9) * 0.02, 0, sin(t * 1.1 + 1.0) * 0.03)
	for b in _bubbles:
		var ph: float = b.get_meta("phase")
		var k := fmod(t * 0.5 + ph, 2.0)
		var s := smoothstep(0.0, 1.6, k) * (1.0 if k < 1.7 else 0.0)
		b.scale = Vector3(s, s * 0.7, s) * 1.4
		b.position = (b.get_meta("base") as Vector3) + Vector3(0, s * 0.08 - 0.02, 0)
	if _altar_flame:
		_altar_flame.scale = Vector3.ONE * (1.0 + sin(t * 9.0) * 0.12 + sin(t * 13.0) * 0.08)
	if _snowfall:
		var cam := root.get_viewport().get_camera_3d()
		if cam:
			_snowfall.global_position = cam.global_position + Vector3(0, 10, 0)
