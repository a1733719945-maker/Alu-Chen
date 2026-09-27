class_name FxLib
extends RefCounted
## 特效用的贴图、材质、着色器（全局缓存，Fx 和魂兽的魂环都用）。
## 贴图是 tools/make_fx_textures.gd 程序生成的（assets/fx）：白色 + 透明度，材质里上色；
## 加法混合的颜色乘了 hdr（大于 1），配合环境的泛光（glow）才会"发光"，不再是一块纯色塑料。

const DIR := "res://assets/fx/"

static var _tex := {}
static var _mats := {}
static var _shaders := {}
static var _fallback: GradientTexture2D


static func tex(name: String) -> Texture2D:
	if _tex.has(name):
		return _tex[name]
	var t: Texture2D = null
	if ResourceLoader.exists(DIR + name + ".png"):
		t = load(DIR + name + ".png")
	if t == null:
		if _fallback == null:
			_fallback = GradientTexture2D.new()
			_fallback.fill = GradientTexture2D.FILL_RADIAL
			_fallback.fill_from = Vector2(0.5, 0.5)
			_fallback.fill_to = Vector2(0.5, 0.0)
			var g := Gradient.new()
			g.set_color(0, Color(1, 1, 1, 1))
			g.set_color(1, Color(1, 1, 1, 0))
			_fallback.gradient = g
		t = _fallback
	_tex[name] = t
	return t


## 粒子材质：朝镜头的方片，贴图 + 顶点颜色（粒子颜色渐变），加法（发光）或普通混合（烟、尘）。
## soft：贴近地面、墙时渐隐（软粒子），不会一刀切在地面上
static func pmat(tex_name: String, add: bool, hdr := 1.0, atlas := 1, soft := 0.6) -> StandardMaterial3D:
	var key := "p|%s|%s|%.2f|%d|%.2f" % [tex_name, add, hdr, atlas, soft]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = tex(tex_name)
	m.albedo_color = Color(hdr, hdr, hdr, 1.0)
	m.disable_fog = add
	if add:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if atlas > 1:
		m.particles_anim_h_frames = atlas
		m.particles_anim_v_frames = atlas
		m.particles_anim_loop = false
	# 软粒子（proximity_fade）要读深度图，项目开了 MSAA 以后读出来不对，烟会整团淡没（第七版截图发现），先不开
	if soft > 0.0 and false:
		m.proximity_fade_enabled = true
		m.proximity_fade_distance = soft
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


## 平面上的贴图（冲击环、魂环、水花圈）：不朝镜头，躺在地上或者竖着。颜色乘 hdr
static func quad_mat(tex_name: String, color: Color, hdr := 2.0, add := true) -> StandardMaterial3D:
	var key := "q|%s|%s|%.2f|%s" % [tex_name, color.to_html(), hdr, add]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = tex(tex_name)
	m.albedo_color = Color(color.r * hdr, color.g * hdr, color.b * hdr, color.a) if add else color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_fog = add
	if add:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.no_depth_test = false
	_mats[key] = m
	return m


## 朝镜头的单张贴图（星芒闪光、光晕）
static func bill_mat(tex_name: String, color: Color, hdr := 3.0) -> StandardMaterial3D:
	var key := "b|%s|%s|%.2f" % [tex_name, color.to_html(), hdr]
	if _mats.has(key):
		return _mats[key]
	var m := quad_mat(tex_name, color, hdr, true).duplicate() as StandardMaterial3D
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	_mats[key] = m
	return m


# ------------------------------------------------------------------ 着色器

## 火花：按速度方向拉长、始终朝着镜头的光条（粒子要开 particle_flag_align_y）
const SPARK := """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float stretch = 4.0;
uniform float hdr = 3.0;
void vertex() {
	vec3 axis = MODEL_MATRIX[1].xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	float al = length(axis);
	axis = al > 0.0001 ? axis / al : vec3(0.0, 1.0, 0.0);
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - center);
	vec3 side = cross(axis, to_cam);
	float sl = length(side);
	side = sl > 0.0001 ? side / sl : vec3(1.0, 0.0, 0.0);
	vec3 wp = center + side * VERTEX.x * s + axis * VERTEX.y * s * stretch;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(wp, 1.0));
}
void fragment() {
	ALBEDO = COLOR.rgb * hdr;
	ALPHA = COLOR.a * texture(tex, UV).a;
}
"""

## 火球：噪声翻滚的球，中间白热，progress 0→1 从边上烧散
const FIRE := """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 color : source_color = vec4(1.0, 0.5, 0.15, 1.0);
uniform float progress = 0.0;
uniform float hdr = 2.4;
uniform float speed = 1.0;
uniform float lumpy = 0.3;
void vertex() {
	// 表面按噪声鼓包，不是一个光滑的圆球
	float n = textureLod(noise_tex, UV * vec2(3.0, 1.5) + vec2(TIME * 0.05 * speed, -TIME * 0.25 * speed), 0.0).r;
	VERTEX += NORMAL * (n - 0.45) * lumpy * 2.0;
}
void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec2 uv = UV * vec2(3.0, 1.5);
	float t = TIME * speed;
	float n = texture(noise_tex, uv + vec2(t * 0.1, -t * 0.45)).r * 0.65 + texture(noise_tex, uv * 2.1 + vec2(-t * 0.2, -t * 0.7)).r * 0.35;
	float thr = progress * 1.05;
	float body = smoothstep(thr, thr + 0.22, n * (0.45 + facing * 0.7));
	vec3 hot = mix(color.rgb, vec3(1.0, 0.93, 0.78), pow(facing, 3.0) * (1.0 - progress));
	ALBEDO = hot * hdr * body * (0.3 + facing * 0.9);
}
"""

## 光柱 / 光壁：开口圆柱，边缘亮（菲涅尔）、往上流动的光纹、上端淡出
const PILLAR := """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 color : source_color = vec4(1.0);
uniform float hdr = 2.5;
uniform float fade = 1.0;
uniform float speed = 0.6;
uniform float half_h = 10.0;
uniform float top = 0.45;
uniform float rim_k = 1.0;
varying float hy;
void vertex() {
	hy = VERTEX.y;
}
void fragment() {
	float t = clamp(hy / (2.0 * half_h) + 0.5, 0.0, 1.0);
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	float n = texture(noise_tex, vec2(UV.x * 2.0, t * 1.5 - TIME * speed)).r;
	float n2 = texture(noise_tex, vec2(UV.x * 5.0 + 0.37, t * 3.0 - TIME * speed * 1.8)).r;
	float streak = pow(n * 0.6 + n2 * 0.4, 2.5) * 2.2;
	float vert = smoothstep(1.0, top, t) * smoothstep(0.0, 0.03, t);
	float body = pow(rim, 2.0) * rim_k + streak * 0.55 + 0.1;
	ALBEDO = color.rgb * hdr * body * vert * fade;
}
"""

## 光束：朝镜头的光带（和弹道一样的做法），里面噪声往前流，中间一道白芯
const BEAM := """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, world_vertex_coords, fog_disabled;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 color : source_color = vec4(1.0);
uniform float width = 0.5;
uniform float hdr = 3.0;
uniform float fade = 1.0;
uniform float len_m = 10.0;
void vertex() {
	vec3 ax = (MODEL_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz;
	float len = length(ax);
	vec3 axis = ax / max(len, 0.0001);
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 side = normalize(cross(axis, INV_VIEW_MATRIX[3].xyz - center));
	VERTEX = center + axis * (UV.y - 0.5) * len + side * (UV.x - 0.5) * width;
}
void fragment() {
	float across = abs(UV.x - 0.5) * 2.0;
	float n = texture(noise_tex, vec2(UV.x * 0.7 + TIME * 0.2, UV.y * len_m / (width * 3.0) + TIME * 4.0)).r;
	float core = exp(-across * across * 24.0);
	float body = exp(-across * across * 3.0) * (0.65 + n * 0.6);
	float ends = smoothstep(0.0, 0.02, UV.y) * smoothstep(1.0, 0.98, UV.y);
	ALBEDO = (color.rgb * body + vec3(1.0) * core * 0.9) * hdr * ends * fade;
}
"""

## 魂灵：半透明的光体，轮廓亮、里面有流动的光
const SPIRIT := """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 color : source_color = vec4(1.0);
uniform float hdr = 2.0;
uniform float fade = 1.0;
void fragment() {
	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float n = texture(noise_tex, UV * vec2(2.0, 1.0) + vec2(0.0, -TIME * 0.35)).r;
	ALBEDO = color.rgb * hdr * fade * (pow(f, 2.2) * 1.5 + n * n * 0.4 + 0.07);
}
"""

## 护盾：六边形格子 + 轮廓亮
const SHIELD := """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(0.5, 0.8, 1.0, 1.0);
uniform float hdr = 1.6;
uniform float fade = 1.0;
float hex(vec2 p) {
	p.x *= 1.1547;
	p.y += mod(floor(p.x), 2.0) * 0.5;
	p = abs(fract(p) - 0.5);
	return abs(max(p.x * 1.5 + p.y, p.y * 2.0) - 1.0);
}
void fragment() {
	float f = 1.0 - abs(dot(NORMAL, VIEW));
	float h = smoothstep(0.12, 0.0, hex(UV * vec2(24.0, 12.0)));
	float wave = 0.5 + 0.5 * sin(UV.y * 20.0 - TIME * 3.0);
	ALBEDO = color.rgb * hdr * fade * (pow(f, 2.5) * 1.2 + h * (0.12 + wave * 0.15));
}
"""

## 画面扭曲（爆炸、冲击波的热浪）：球面按法线方向错开背后的画面
const DISTORT := """shader_type spatial;
render_mode unshaded, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.035;
uniform float fade = 1.0;
void fragment() {
	float d = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float band = sin(d * 3.14159) * (1.0 - d * 0.5);
	vec2 off = NORMAL.xy * band * strength * fade;
	ALBEDO = textureLod(screen_tex, SCREEN_UV - off, 0.0).rgb;
}
"""


static func shader(name: String) -> Shader:
	if _shaders.has(name):
		return _shaders[name]
	var s := Shader.new()
	s.code = {"spark": SPARK, "fire": FIRE, "pillar": PILLAR, "beam": BEAM, "spirit": SPIRIT, "shield": SHIELD, "distort": DISTORT}[name]
	_shaders[name] = s
	return s


## 新的着色器材质（每个特效一份，好单独调 fade / progress）
static func smat(name: String, params := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader(name)
	if name in ["fire", "pillar", "beam", "spirit"]:
		m.set_shader_parameter("noise_tex", tex("noise"))
	if name == "spark":
		m.set_shader_parameter("tex", tex("spark"))
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m


## 共用的火花材质（按 hdr 缓存）
static func spark_mat(hdr := 3.0, stretch := 4.0) -> ShaderMaterial:
	var key := "s|%.2f|%.2f" % [hdr, stretch]
	if _mats.has(key):
		return _mats[key]
	var m := smat("spark", {"hdr": hdr, "stretch": stretch})
	_mats[key] = m
	return m


## 地上的贴花（法阵、焦痕、预警圈）只投到第 1 层（地形、树、石头）。魂兽、Boss、人、手里的暗器放到第 2 层，就不会被贴花染色
static func no_decals(n: Node) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = 2
	for c in n.find_children("*", "VisualInstance3D", true, false):
		(c as VisualInstance3D).layers = 2


# ------------------------------------------------------------------ 魂环（魂兽脚下、掉在地上）

## 一圈魂环：躺平的贴图，亮环 + 柔光。万年的环是黑的：黑环（普通混合）+ 外面一圈暗红光
static func soul_ring(color: Color, glow: Color, radius: float, hdr := 2.2) -> Node3D:
	var n := Node3D.new()
	var dark := color.get_luminance() < 0.2
	var q := PlaneMesh.new()
	q.size = Vector2(radius * 2.5, radius * 2.5)
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	ring.mesh = q
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.material_override = quad_mat("halo", glow if dark else color, hdr * (1.3 if dark else 1.0), true)
	n.add_child(ring)
	if dark:
		var core := MeshInstance3D.new()
		var q2 := PlaneMesh.new()
		q2.size = Vector2(radius * 2.5, radius * 2.5)
		core.mesh = q2
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		core.material_override = quad_mat("halo", Color(0.02, 0.0, 0.02, 0.95), 1.0, false)
		core.position.y = 0.01
		ring.add_child(core)
	return n
