class_name MatLib
extends RefCounted
## PBR 材质库（2026-09-29，用户："无法接受低质感"）：以前建筑、码头、船、装饰都是纯色 U.mat，木头用的是树皮贴图、瓦用的是悬崖岩石。
## 贴图在 assets/textures/mat（tools/fetch_materials.py 从 ambientCG 下的 CC0）：每种 <名字>_albedo / _normal / _rough。
## 全部三向投影（不用 UV）：world = true 按世界坐标（建筑、码头：零件之间纹理连着、不随缩放拉伸），
## false 按模型自己的坐标（船、暗器、手、会动的东西，纹理跟着走不打滑）。
## 去色的贴图（NEUTRAL：瓦、漆、布、皮、纸、灰泥）靠 tint 上色——传进来的就是想要的颜色；其他的 tint 乘在原色上。

const DIR := "res://assets/textures/mat/"
const NEUTRAL := ["roof", "lacquer", "cloth", "canvas", "leather", "paper", "plaster"]
const NEUTRAL_K := 1.0 / 0.72      # 去色贴图的平均亮度是 0.72（fetch_materials.py 的 NEUTRAL_MEAN）

static var _tex := {}
static var _cache := {}


static func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		var path := DIR + name + ".jpg"
		_tex[name] = load(path) if ResourceLoader.exists(path) else null
	return _tex[name]


## key：材质名；tint：颜色；scale：每米重复几次；metal：金属度；rough：粗糙度（乘在粗糙度贴图上）；nk：法线强度
static func surf(key: String, tint := Color.WHITE, scale := 1.0, world := true, metal := 0.0, rough := 1.0, nk := 1.0) -> StandardMaterial3D:
	var ck := "%s|%s|%.3f|%s|%.2f|%.2f|%.2f" % [key, tint.to_html(), scale, world, metal, rough, nk]
	if _cache.has(ck):
		return _cache[ck]
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex(key + "_albedo")
	var c := tint
	if key in NEUTRAL:
		c = Color(tint.r * NEUTRAL_K, tint.g * NEUTRAL_K, tint.b * NEUTRAL_K, tint.a)
	m.albedo_color = c
	var n := tex(key + "_normal")
	if n:
		m.normal_enabled = true
		m.normal_texture = n
		m.normal_scale = nk
	var r := tex(key + "_rough")
	if r:
		m.roughness_texture = r
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.roughness = rough
	m.metallic = metal
	m.metallic_specular = 0.5
	m.uv1_triplanar = true
	m.uv1_world_triplanar = world
	m.uv1_triplanar_sharpness = 3.0
	m.uv1_scale = Vector3.ONE * scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[ck] = m
	return m


## 同一个材质改一下再用（双面、发光）时先复制，别改到缓存里的
static func variant(m: StandardMaterial3D, double_sided := false) -> StandardMaterial3D:
	var d := m.duplicate() as StandardMaterial3D
	if double_sided:
		d.cull_mode = BaseMaterial3D.CULL_DISABLED
	return d


# ------------------------------------------------------------------ 常用的几种

## 漆木：朱漆柱子、牌坊、船舷。带一层清漆（有光泽但不像塑料）
static func lacquer(c := Color(0.56, 0.07, 0.05), world := true) -> StandardMaterial3D:
	var ck := "lacq|%s|%s" % [c.to_html(), world]
	if _cache.has(ck):
		return _cache[ck]
	var m := surf("lacquer", c, 0.8, world, 0.0, 0.75, 0.6).duplicate() as StandardMaterial3D
	# 旧的朱漆太亮（粗糙度贴图 × 0.75 + 厚清漆）：反着淡蓝的天，红柱子、额枋远看发紫发灰。粗一点、清漆薄一点
	m.roughness_texture = null
	m.roughness = 0.62
	# 漆面是平的；法线贴图在合并过的细零件（窗棂、额枋）上算歪了，整面泛白发粉。去掉
	m.normal_enabled = false
	m.metallic_specular = 0.35
	m.clearcoat_enabled = true
	m.clearcoat = 0.25
	m.clearcoat_roughness = 0.4
	_cache[ck] = m
	return m


## 青瓦（筒瓦）屋顶
static func roof(c := Color(0.3, 0.31, 0.34), world := true) -> StandardMaterial3D:
	return surf("roof", c, 0.9, world, 0.0, 0.95, 1.4)


## 木头。tint 是相对原色的明暗（1 = 原色）
static func wood(tint := Color.WHITE, world := true) -> StandardMaterial3D:
	return surf("wood_light", tint, 1.4, world, 0.0, 1.0)


## 暗红硬木（紫檀）：暗器木件、柜台、家具
static func hardwood(tint := Color.WHITE, world := false) -> StandardMaterial3D:
	return surf("wood", tint, 2.2, world, 0.0, 0.9)


## 旧木板：码头、甲板、船身
static func planks(tint := Color.WHITE, world := true) -> StandardMaterial3D:
	return surf("planks", tint, 0.55, world, 0.0, 1.0)


static func gold(world := false) -> StandardMaterial3D:
	return surf("gold", Color(1.0, 0.92, 0.75), 2.0, world, 1.0, 0.9)


static func bronze(tint := Color.WHITE, world := false) -> StandardMaterial3D:
	return surf("bronze", tint, 1.6, world, 1.0, 1.0)


static func brass(world := false) -> StandardMaterial3D:
	return surf("brass", Color.WHITE, 2.0, world, 1.0, 0.9)


static func iron(tint := Color.WHITE, world := false) -> StandardMaterial3D:
	return surf("iron", tint, 2.0, world, 1.0, 1.0)


## 细布（袖子、袍子、帐篷）：双面
static func cloth(c: Color, world := false, scale := 3.0) -> StandardMaterial3D:
	var ck := "cloth|%s|%s|%.2f" % [c.to_html(), world, scale]
	if not _cache.has(ck):
		_cache[ck] = variant(surf("cloth", c, scale, world, 0.0, 1.0, 0.8), true)
	return _cache[ck]


## 粗布（帆、旗、幌子）：双面
static func canvas(c: Color, world := false) -> StandardMaterial3D:
	var ck := "canvas|%s|%s" % [c.to_html(), world]
	if not _cache.has(ck):
		_cache[ck] = variant(surf("canvas", c, 1.5, world, 0.0, 1.0, 1.0), true)
	return _cache[ck]


static func leather(c := Color(0.16, 0.11, 0.08), world := false) -> StandardMaterial3D:
	return surf("leather", c, 4.0, world, 0.0, 0.85, 0.8)


## 石雕（石狮子、石灯笼、台基）。tint 相对原色的明暗
static func stone(tint := Color.WHITE, world := true) -> StandardMaterial3D:
	return surf("granite", tint, 0.9, world, 0.0, 1.0, 1.2)


static func cobble(tint := Color.WHITE) -> StandardMaterial3D:
	return surf("cobble", tint, 0.35, true, 0.0, 1.0, 1.2)


static func brick(tint := Color.WHITE) -> StandardMaterial3D:
	return surf("brick", tint, 0.45, true, 0.0, 1.0, 1.2)


static func marble(tint := Color.WHITE) -> StandardMaterial3D:
	return surf("marble", tint, 0.5, true, 0.0, 0.8)


static func plaster(c := Color(0.86, 0.84, 0.8)) -> StandardMaterial3D:
	return surf("plaster", c, 0.6, true, 0.0, 1.0, 0.8)


static func rope(world := false) -> StandardMaterial3D:
	return surf("rope", Color.WHITE, 6.0, world, 0.0, 1.0)


static func bamboo(tint := Color.WHITE, world := false) -> StandardMaterial3D:
	return surf("bamboo", tint, 1.2, world, 0.0, 0.9)


static func thatch(tint := Color.WHITE, world := true) -> StandardMaterial3D:
	return surf("thatch", tint, 0.6, world, 0.0, 1.0)


## 灯笼纸：里面点着灯（纸纹透光）
static func paper_lamp(c: Color, energy := 2.2) -> StandardMaterial3D:
	var ck := "lamp|%s|%.2f" % [c.to_html(), energy]
	if _cache.has(ck):
		return _cache[ck]
	var m := surf("paper", c, 3.0, false, 0.0, 1.0, 0.5).duplicate() as StandardMaterial3D
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.emission_texture = tex("paper_albedo")
	m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	m.rim_enabled = true
	m.rim = 0.4
	_cache[ck] = m
	return m
