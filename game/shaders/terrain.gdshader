shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// 地形：四层真实贴图混合。顶点色 RGBA = 四层的权重（岛上：草/土/石/沙，森林：落叶/泥/石/苔藓）。
// 按贴图亮度做“高度混合”，交界处是石缝、草丛那样的自然过渡，不是糊在一起的渐变。
// 两种尺度采样同一张贴图，远处看不出重复。石头用三向投影，陡坡不会拉伸。

uniform sampler2D albedo0 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D albedo1 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D albedo2 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D albedo3 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal0 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal1 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal2 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal3 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// 每米重复几次
uniform vec4 scales = vec4(0.28, 0.3, 0.14, 0.3);
uniform vec3 tint0 : source_color = vec3(1.0);
uniform vec3 tint1 : source_color = vec3(1.0);
uniform vec3 tint2 : source_color = vec3(1.0);
uniform vec3 tint3 : source_color = vec3(1.0);
uniform vec4 roughs = vec4(0.95, 0.9, 0.8, 0.92);
uniform float blend_sharp = 0.22;
uniform float normal_depth = 1.0;
uniform float snow_height = 9999.0;
uniform float wet_level = 0.6;          // 这个高度以下的地面是湿的（水边）
uniform float macro_amount = 0.22;      // 大块的明暗变化，打破重复感

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	TANGENT = normalize(vec3(1.0, 0.0, 0.0) - NORMAL * NORMAL.x);
	BINORMAL = normalize(cross(TANGENT, NORMAL));
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float lum(vec3 c) {
	return dot(c, vec3(0.3, 0.59, 0.11));
}

// 同一张贴图，近处用正常尺度，再叠一层转了角度的大尺度，互相打散重复的图案
vec3 two_scale(sampler2D t, vec2 uv, float far) {
	vec3 a = texture(t, uv).rgb;
	vec2 uv2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * uv * 0.27 + vec2(0.37, 0.71);
	vec3 b = texture(t, uv2).rgb;
	return mix(a, b, 0.3 + far * 0.4);
}

void fragment() {
	vec2 uv = wpos.xz;
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float far = smoothstep(15.0, 90.0, dist);

	vec3 c0 = two_scale(albedo0, uv * scales.x, far) * tint0;
	vec3 c1 = two_scale(albedo1, uv * scales.y, far) * tint1;
	vec3 c3 = two_scale(albedo3, uv * scales.w, far) * tint3;
	// 石头：三向投影
	vec3 bw = pow(abs(wnrm), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);
	float s2 = scales.z;
	vec3 c2 = (texture(albedo2, wpos.zy * s2).rgb * bw.x + texture(albedo2, wpos.xz * s2).rgb * bw.y + texture(albedo2, wpos.xy * s2).rgb * bw.z) * tint2;

	vec4 w = COLOR;
	w /= max(w.r + w.g + w.b + w.a, 0.001);
	vec4 h = w + vec4(lum(c0), lum(c1), lum(c2), lum(c3)) * 0.45;
	float m = max(max(h.x, h.y), max(h.z, h.w)) - blend_sharp;
	vec4 b = max(h - m, vec4(0.0));
	b /= max(b.x + b.y + b.z + b.w, 0.0001);

	vec3 alb = c0 * b.x + c1 * b.y + c2 * b.z + c3 * b.w;
	float rough = dot(b, roughs);

	vec3 n0 = texture(normal0, uv * scales.x).rgb;
	vec3 n1 = texture(normal1, uv * scales.y).rgb;
	vec3 n2 = texture(normal2, uv * s2).rgb;
	vec3 n3 = texture(normal3, uv * scales.w).rgb;
	vec3 nm = n0 * b.x + n1 * b.y + n2 * b.z + n3 * b.w;

	// 大块明暗
	float mv = vnoise(uv * 0.018) * 0.6 + vnoise(uv * 0.07) * 0.4;
	alb *= mix(1.0 - macro_amount, 1.0 + macro_amount * 0.6, mv);

	// 水边湿润：更深、更亮滑
	float wet = 1.0 - smoothstep(wet_level - 0.8, wet_level + 0.3, wpos.y);
	alb *= mix(1.0, 0.62, wet);
	rough = mix(rough, 0.35, wet * 0.8);

	// 高山积雪
	float snow = smoothstep(snow_height, snow_height + 25.0, wpos.y + vnoise(uv * 0.05) * 18.0) * smoothstep(0.45, 0.75, wnrm.y);
	alb = mix(alb, vec3(0.86, 0.89, 0.93), snow);
	rough = mix(rough, 0.6, snow);

	ALBEDO = alb;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
	NORMAL_MAP = mix(nm, vec3(0.5, 0.5, 1.0), snow * 0.7 + far * 0.35);
	NORMAL_MAP_DEPTH = normal_depth;
}
