class_name GunSkin
extends RefCounted
## 暗器皮肤的材质（第十二版）：不再只是换颜色。
##
## 一个着色器画全部花纹：木纹、大马士革钢、碳纤维、玉石纹、流光、熔岩裂纹、星河、龙鳞、珠光、符阵回路、冰晶、暗影烟、水波、极光、拉丝金属、蛛网。
## 花纹按"暗器根节点坐标"算（每个零件把自己相对根节点的位置写进 instance uniform），所以一把暗器上的花纹是连着的，不会每个零件各算各的。
## 金属反光靠天空的反射（world_builder 里环境的反射来源是天空），皮肤里 metal / rough 决定有多亮。
##
## 自己画的皮肤（Data.GUN_SKINS["paint"]）：一张 512×256 的图，从暗器右侧面投影上去（左边是枪尾，右边是枪口），
## 存在 user://paint/<存档文件名>_<暗器>.png（PaintPanel 画），paint_box 是这把暗器侧面的范围。

const PAT := {"plain": 0, "wood": 1, "fade": 2, "damascus": 3, "carbon": 4, "marble": 5, "flow": 6, "lava": 7, "galaxy": 8,
	"scales": 9, "pearl": 10, "circuit": 11, "ice": 12, "smoke": 13, "caustic": 14, "aurora": 15, "brushed": 16, "web": 17}
const PAINT_W := 512
const PAINT_H := 256
## 每种表面用哪张真实贴图（MatLib）：[贴图名, 贴图平均亮度, 每米重复, 明暗强度, 法线强度]
const DETAIL := {
	"wood": ["wood", 0.264, 3.0, 0.9, 1.2],
	"lacquer": ["lacquer", 0.72, 4.0, 0.45, 0.6],
	"black": ["leather", 0.72, 7.0, 0.6, 1.0],
	"bronze": ["bronze", 0.548, 4.0, 0.7, 0.9],
	"gold": ["gold", 0.887, 5.0, 0.5, 0.7],
	"iron": ["iron", 0.379, 4.0, 0.7, 0.9],
}

const SHADER := """shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 base_col : source_color = vec3(0.5);
uniform vec3 col2 : source_color = vec3(0.2);
uniform vec3 col3 : source_color = vec3(1.0);
uniform float metal = 0.0;
uniform float rough = 0.5;
uniform float coat = 0.0;
uniform int pattern = 0;
uniform float pscale = 30.0;
uniform float glow = 0.0;
uniform float speed = 1.0;
uniform sampler2D paint_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float paint_on = 0.0;
uniform vec4 paint_box = vec4(-0.4, -0.15, 0.4, 0.15);
uniform float paint_metal = 0.0;
uniform float paint_rough = 0.45;
uniform float paint_coat = 0.0;
// 真实材质细节（2026-09-29）：木纹 / 漆面 / 皮革 / 青铜 / 金 / 乌铁贴图，只取明暗 + 法线 + 粗糙度，颜色还是皮肤的
uniform sampler2D d_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D d_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D d_rgh : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float d_on = 0.0;
uniform float d_scale = 4.0;
uniform float d_mean = 0.5;
uniform float d_alb_k = 0.8;
uniform float d_nrm_k = 1.0;
uniform float d_rgh_k = 0.8;

instance uniform vec3 rp_x = vec3(1.0, 0.0, 0.0);
instance uniform vec3 rp_y = vec3(0.0, 1.0, 0.0);
instance uniform vec3 rp_z = vec3(0.0, 0.0, 1.0);
instance uniform vec3 rp_o = vec3(0.0);

varying vec3 rp;
varying vec3 rn;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash13(i), hash13(i + vec3(1.0, 0.0, 0.0)), f.x), mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), f.x), f.y);
	float b = mix(mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), f.x), mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), f.x), f.y);
	return mix(a, b, f.z);
}

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec3(17.1, 5.3, 11.7);
		a *= 0.5;
	}
	return s;
}

vec2 voro(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 o = vec3(hash13(i + g), hash13(i + g + 11.7), hash13(i + g + 23.3));
				float d = length(g + o - f);
				if (d < d1) {
					d2 = d1;
					d1 = d;
				} else if (d < d2) {
					d2 = d;
				}
			}
		}
	}
	return vec2(d1, d2);
}

// 零件表面主要朝哪边：取对应的平面坐标（碳纤维、回路这种平面花纹用）
vec2 plane_uv(vec3 p, vec3 n) {
	vec3 an = abs(n);
	if (an.x > an.y && an.x > an.z) {
		return p.zy;
	} else if (an.y > an.z) {
		return p.zx;
	}
	return p.xy;
}

void vertex() {
	rp = rp_o + rp_x * VERTEX.x + rp_y * VERTEX.y + rp_z * VERTEX.z;
	rn = normalize(rp_x * NORMAL.x + rp_y * NORMAL.y + rp_z * NORMAL.z);
}

void fragment() {
	vec3 p = rp * pscale;
	vec3 alb = base_col;
	float m = metal;
	float r = rough;
	float cc = coat;
	vec3 em = vec3(0.0);
	float t = TIME * speed;
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	if (pattern == 1) {
		// 木纹：沿着枪身的年轮 + 细纹
		float g = fbm(vec3(p.x * 2.0, p.y * 2.0, p.z * 0.25));
		float rings = fract(length(rp.xy) * 90.0 + g * 3.0);
		float fine = vnoise(vec3(p.x * 20.0, p.y * 20.0, p.z * 0.6));
		alb = base_col * mix(0.72, 1.18, smoothstep(0.15, 0.85, rings)) * (0.9 + fine * 0.2);
		r = rough + (rings - 0.5) * 0.12;
	} else if (pattern == 2) {
		// 渐变镭射：枪尾一个颜色，中间第二个，枪口第三个
		float k = clamp(0.5 - rp.z * 1.5 + (fbm(p * 0.5) - 0.5) * 0.2 + rp.y * 0.8, 0.0, 1.0);
		alb = k < 0.5 ? mix(base_col, col2, k * 2.0) : mix(col2, col3, k * 2.0 - 1.0);
	} else if (pattern == 3) {
		// 大马士革钢：一层层细细的、弯曲的钢纹
		float w = sin(rp.z * 420.0 + rp.y * 210.0 + fbm(p * 0.6) * 18.0 + fbm(p * 2.5) * 3.0);
		float band = smoothstep(-0.7, 0.7, w);
		alb = mix(col2, base_col, 0.3 + 0.7 * band);
		r = mix(0.34, rough, band);
	} else if (pattern == 4) {
		// 碳纤维：斜纹编织 + 清漆
		vec2 uv = plane_uv(rp, rn) * 190.0;
		vec2 c = floor(uv);
		vec2 f = fract(uv);
		float s = mod(c.x + floor(c.y * 0.5), 2.0) < 0.5 ? f.x : f.y;
		float sh = 0.45 + 0.55 * sin(s * 3.14159);
		alb = mix(col2, base_col, sh);
		r = 0.4;
		cc = 1.0;
	} else if (pattern == 5) {
		// 玉石 / 大理石：发光的细脉
		float v = fbm(p * 0.9);
		float vein = 1.0 - smoothstep(0.0, 0.07, abs(sin(p.z * 0.5 + p.y * 0.3 + v * 7.0)));
		alb = mix(base_col, col2, smoothstep(0.3, 0.75, v)) + col3 * vein * 0.35;
		em = col3 * vein * glow;
	} else if (pattern == 6) {
		// 流光：沿着枪身流动的能量线
		float lines = pow(abs(sin(rp.y * 140.0 + rp.x * 90.0 + fbm(p * 0.4) * 4.0)), 24.0);
		float flow = smoothstep(0.55, 1.0, sin(rp.z * 28.0 + t * 4.0 + fbm(p) * 3.0) * 0.5 + 0.5);
		em = col3 * lines * (0.25 + flow * 2.2) * glow + col2 * flow * 0.15 * glow;
	} else if (pattern == 7) {
		// 熔岩：黑色岩壳，裂缝里透出一明一暗的光
		vec2 v = voro(p * 0.9);
		float crack = 1.0 - smoothstep(0.0, 0.09, v.y - v.x);
		float pulse = 0.65 + 0.35 * sin(t * 2.0 + v.x * 6.0 + p.z * 0.1);
		alb = mix(base_col, base_col * 0.35, v.x) + col2 * crack * 0.3;
		em = col3 * crack * pulse * glow;
		r = 0.85;
		m = 0.0;
	} else if (pattern == 8) {
		// 星河：深色的星云，一闪一闪的星星
		float neb = fbm(p * 0.35 + vec3(0.0, 0.0, t * 0.05));
		alb = mix(base_col, col2, smoothstep(0.3, 0.75, neb));
		vec3 cell = floor(p * 1.6);
		float st = hash13(cell);
		float star = step(0.82, st) * smoothstep(0.3, 0.0, length(fract(p * 1.6) - 0.5)) * (0.4 + 0.6 * sin(t * 3.0 + st * 40.0));
		em = col3 * star * glow * 6.0 + col2 * smoothstep(0.45, 0.85, neb) * glow * 0.6;
	} else if (pattern == 9) {
		// 龙鳞：一片片的鳞，边缘刻进去
		vec2 v = voro(vec3(p.x * 1.4, p.y * 1.4, p.z * 0.9));
		float edge = smoothstep(0.02, 0.14, v.y - v.x);
		alb = mix(col2, base_col, edge) * (0.85 + 0.3 * v.x);
		r = mix(0.55, rough, edge);
	} else if (pattern == 10) {
		// 幻彩珠光：换个角度看颜色就变
		float h = fract((1.0 - ndv) * 1.3 + fbm(p * 0.4) * 0.5 + rp.z * 0.8);
		vec3 rainbow = 0.5 + 0.5 * cos(6.2831 * (h + vec3(0.0, 0.33, 0.67)));
		alb = mix(base_col, rainbow, 0.7);
		cc = 1.0;
	} else if (pattern == 11) {
		// 符阵回路：发光的线路，一道扫描光从枪尾扫到枪口
		vec2 uv = plane_uv(rp, rn) * 55.0;
		vec2 g = abs(fract(uv) - 0.5);
		float line = 1.0 - smoothstep(0.0, 0.07, min(g.x, g.y));
		float keep = step(0.42, hash13(vec3(floor(uv), 1.0)));
		float node = smoothstep(0.16, 0.08, length(fract(uv) - 0.5)) * step(0.8, hash13(vec3(floor(uv), 7.0)));
		float scan = smoothstep(0.85, 1.0, sin(rp.z * 18.0 + t * 5.0) * 0.5 + 0.5);
		em = col3 * (line * keep + node) * (0.35 + scan * 3.0) * glow;
		alb = base_col + col2 * line * keep * 0.3;
	} else if (pattern == 12) {
		// 冰晶：边缘发亮，里面有闪烁的冰屑
		float fr = pow(1.0 - ndv, 3.0);
		vec3 cell = floor(p * 6.0);
		float sp = step(0.975, hash13(cell)) * (0.5 + 0.5 * sin(t * 6.0 + hash13(cell + 3.1) * 30.0));
		alb = mix(base_col, col2, fbm(p * 0.6));
		em = col3 * (fr * 0.9 + sp * 2.5) * glow;
	} else if (pattern == 13) {
		// 暗影：哑光黑，表面飘着一缕缕发光的烟
		float s = fbm(p * 0.6 + vec3(0.0, t * 0.3, -t * 0.5));
		em = col3 * smoothstep(0.48, 0.82, s) * glow;
		alb = mix(base_col, col2, s * 0.5);
	} else if (pattern == 14) {
		// 水波：水底的光纹在流动
		vec2 v = voro(p * 0.8 + vec3(t * 0.3, t * 0.2, t * 0.25));
		float c = pow(1.0 - smoothstep(0.0, 0.3, v.y - v.x), 3.0);
		alb = mix(base_col, col2, fbm(p * 0.4));
		em = col3 * c * glow;
	} else if (pattern == 15) {
		// 极光：一条条飘动的光带
		float b = sin(rp.z * 18.0 + fbm(p * 0.4 + vec3(t * 0.2)) * 5.0 + t);
		em = mix(col2, col3, 0.5 + 0.5 * b) * smoothstep(0.2, 1.0, b) * glow;
	} else if (pattern == 16) {
		// 拉丝金属：顺着枪身的细纹
		float s = vnoise(vec3(rp.x * 500.0, rp.y * 500.0, rp.z * 6.0));
		alb = base_col * (0.86 + s * 0.24);
		r = rough + (s - 0.5) * 0.1;
	} else if (pattern == 17) {
		// 蛛网：黑底上发光的网线
		vec2 v = voro(p * 0.7);
		float web = 1.0 - smoothstep(0.0, 0.035, v.y - v.x);
		float pulse = 0.6 + 0.4 * sin(t * 1.5 + p.z * 0.2);
		alb = base_col + col2 * web * 0.4;
		em = col3 * web * pulse * glow;
	}
	if (d_on > 0.5) {
		// 三向投影（暗器根节点坐标，零件之间纹理连着）+ Whiteout 法线混合
		vec3 bw = pow(abs(rn), vec3(4.0));
		bw /= (bw.x + bw.y + bw.z);
		vec2 ux = rp.zy * d_scale;
		vec2 uy = rp.xz * d_scale;
		vec2 uz = rp.xy * d_scale;
		vec3 dal = texture(d_alb, ux).rgb * bw.x + texture(d_alb, uy).rgb * bw.y + texture(d_alb, uz).rgb * bw.z;
		float lum = dot(dal, vec3(0.299, 0.587, 0.114)) / max(d_mean, 0.01);
		alb *= mix(1.0, lum, d_alb_k);
		float drg = texture(d_rgh, ux).r * bw.x + texture(d_rgh, uy).r * bw.y + texture(d_rgh, uz).r * bw.z;
		r = mix(r, r * (0.45 + drg * 1.1), d_rgh_k);
		vec3 tx = texture(d_nrm, ux).xyz * 2.0 - 1.0;
		vec3 ty = texture(d_nrm, uy).xyz * 2.0 - 1.0;
		vec3 tz = texture(d_nrm, uz).xyz * 2.0 - 1.0;
		tx.xy *= d_nrm_k;
		ty.xy *= d_nrm_k;
		tz.xy *= d_nrm_k;
		tx = vec3(tx.xy + rn.zy, abs(tx.z) * rn.x);
		ty = vec3(ty.xy + rn.xz, abs(ty.z) * rn.y);
		tz = vec3(tz.xy + rn.xy, abs(tz.z) * rn.z);
		vec3 nr = normalize(tx.zyx * bw.x + ty.xzy * bw.y + tz.xyz * bw.z);
		// 根节点坐标 → 零件自己的坐标 → 视图坐标
		vec3 ln = inverse(mat3(rp_x, rp_y, rp_z)) * nr;
		NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(ln, 0.0)).xyz);
	}
	if (paint_on > 0.5) {
		vec2 puv = vec2((paint_box.z - rp.z) / (paint_box.z - paint_box.x), (paint_box.w - rp.y) / (paint_box.w - paint_box.y));
		vec4 pc = texture(paint_tex, clamp(puv, vec2(0.001), vec2(0.999)));
		alb = mix(alb, pc.rgb, pc.a);
		m = mix(m, paint_metal, pc.a);
		r = mix(r, paint_rough, pc.a);
		cc = mix(cc, paint_coat, pc.a);
		em *= 1.0 - pc.a;
	}
	ALBEDO = alb;
	METALLIC = clamp(m, 0.0, 1.0);
	ROUGHNESS = clamp(r, 0.03, 1.0);
	EMISSION = em;
	CLEARCOAT = cc;
	CLEARCOAT_ROUGHNESS = 0.08;
}
"""

static var _shader: Shader
static var _paint_cache := {}      # "存档位_暗器" -> ImageTexture


static func shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	return _shader


## 一种表面（wood / lacquer / black / bronze / gold / iron）的材质
## sk：Data.GUN_SKINS 里的一项；role：表面；weapon：画的皮肤要知道是哪把暗器
static func material(sk: Dictionary, role: String, base: Color, weapon := "") -> ShaderMaterial:
	var trim := role in ["bronze", "gold", "iron"]
	var m := ShaderMaterial.new()
	m.shader = shader()
	var metal := float(sk.get("metal", 0.0))
	# 身子（木头、漆、黑件）：皮肤的花纹；包边（青铜、金、铁）：抛光 / 拉丝金属
	var pat := str(sk.get("trim_pat", "brushed")) if trim else str(sk.get("pat", "plain"))
	var bm := float(sk.get("trim_metal", 0.9)) if trim else float(sk.get("body_metal", metal * 0.6))
	var br := float(sk.get("trim_rough", 0.28)) if trim else float(sk.get("body_rough", lerpf(0.55, 0.2, metal)))
	# 黑件比主体暗一点、粗一点
	if role == "black" and not trim:
		br = minf(br + 0.1, 1.0)
	m.set_shader_parameter("base_col", base)
	m.set_shader_parameter("col2", sk.get("c2", base.darkened(0.5)))
	m.set_shader_parameter("col3", sk.get("c3", sk.get("glow", Color(0.35, 0.95, 0.8))))
	m.set_shader_parameter("metal", bm)
	m.set_shader_parameter("rough", br)
	m.set_shader_parameter("coat", float(sk.get("coat", 0.0)) if not trim else 0.0)
	m.set_shader_parameter("pattern", int(PAT.get(pat, 0)))
	m.set_shader_parameter("pscale", float(sk.get("scale", 30.0)))
	m.set_shader_parameter("glow", float(sk.get("glow_k", 1.0)) * (0.5 if trim else 1.0))
	m.set_shader_parameter("speed", float(sk.get("speed", 1.0)))
	var det: Array = DETAIL.get(role, [])
	if not det.is_empty() and MatLib.tex(str(det[0]) + "_albedo"):
		m.set_shader_parameter("d_on", 1.0)
		m.set_shader_parameter("d_alb", MatLib.tex(str(det[0]) + "_albedo"))
		m.set_shader_parameter("d_nrm", MatLib.tex(str(det[0]) + "_normal"))
		m.set_shader_parameter("d_rgh", MatLib.tex(str(det[0]) + "_rough"))
		m.set_shader_parameter("d_mean", float(det[1]))
		m.set_shader_parameter("d_scale", float(det[2]))
		# 花纹皮肤（发光、星河、熔岩……）细节淡一点，别把花纹盖掉
		var k := 1.0 if pat in ["plain", "wood", "brushed", "damascus", "scales"] else 0.45
		m.set_shader_parameter("d_alb_k", float(det[3]) * k)
		m.set_shader_parameter("d_nrm_k", float(det[4]))
	if bool(sk.get("paint", false)) and weapon != "":
		var tex := paint_texture(weapon)
		if tex:
			var fin: Dictionary = Data.PAINT_FINISH.get(str(Profile.paint.get(weapon, {}).get("finish", "gloss")), Data.PAINT_FINISH["gloss"])
			# paint_box 等模型搭好了再设（WeaponModels.build 最后按零件算这把暗器的侧面范围）
			m.set_shader_parameter("paint_tex", tex)
			m.set_shader_parameter("paint_on", 1.0)
			m.set_shader_parameter("paint_metal", float(fin["metal"]))
			m.set_shader_parameter("paint_rough", float(fin["rough"]))
			m.set_shader_parameter("paint_coat", float(fin["coat"]))
	return m


## 零件相对暗器根节点的变换写进 instance uniform（花纹、画的图都按根节点坐标算）
static func bind_part(mi: GeometryInstance3D) -> void:
	var xf := Transform3D.IDENTITY
	var n: Node = mi
	while n != null and n is Node3D and n.get_parent() != null:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	mi.set_instance_shader_parameter("rp_x", xf.basis.x)
	mi.set_instance_shader_parameter("rp_y", xf.basis.y)
	mi.set_instance_shader_parameter("rp_z", xf.basis.z)
	mi.set_instance_shader_parameter("rp_o", xf.origin)


static func is_skin_mat(mat: Material) -> bool:
	return mat is ShaderMaterial and (mat as ShaderMaterial).shader == _shader and _shader != null


# ------------------------------------------------------------------ 自己画的皮肤

static func paint_path(weapon: String) -> String:
	return "user://paint/%s.png" % _key(weapon)


## 按存档文件分开（三个存档位、自动测试各画各的）
static func _key(weapon: String) -> String:
	return "%s_%s" % [Profile.path.get_file().get_basename(), weapon]


static func has_paint(weapon: String) -> bool:
	return FileAccess.file_exists(paint_path(weapon))


static func paint_texture(weapon: String) -> ImageTexture:
	var key := _key(weapon)
	if _paint_cache.has(key):
		return _paint_cache[key]
	if not has_paint(weapon):
		return null
	var img := Image.load_from_file(ProjectSettings.globalize_path(paint_path(weapon)))
	if img == null or img.is_empty():
		return null
	img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_paint_cache[key] = tex
	return tex


## 画好了：存盘，并让下次建模型时用新图
static func save_paint(weapon: String, img: Image) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://paint"))
	img.save_png(ProjectSettings.globalize_path(paint_path(weapon)))
	_paint_cache.erase(_key(weapon))


## 编辑时实时更新（不存盘）
static func set_live_paint(weapon: String, tex: ImageTexture) -> void:
	_paint_cache[_key(weapon)] = tex


## 不保存：扔掉编辑中的图（下次从存盘的读）
static func forget_live(weapon: String) -> void:
	_paint_cache.erase(_key(weapon))


## 暗器侧面的范围（Rect2：x = z，y = y）撑成 2:1（和画布一样）：返回 z 最小、y 最小、z 最大、y 最大
static func box2to1(r: Rect2) -> Vector4:
	var cz := r.position.x + r.size.x * 0.5
	var cy := r.position.y + r.size.y * 0.5
	var w := maxf(r.size.x, r.size.y * 2.0) * 1.04
	var h := w * 0.5
	return Vector4(cz - w * 0.5, cy - h * 0.5, cz + w * 0.5, cy + h * 0.5)
