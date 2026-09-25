shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;
// 草丛贴片：真实草叶贴图，根部暗、尖端亮，随风成片摆动（风像波浪一样扫过草地）。
// 远处慢慢缩小消失，不会“啪”一下不见。实例颜色（COLOR）让草色跟地面一致。

uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float sway = 0.22;
uniform float fade_start = 35.0;
uniform float fade_end = 55.0;
uniform vec3 root_dark : source_color = vec3(0.45, 0.5, 0.4);
uniform vec3 backlight : source_color = vec3(0.35, 0.42, 0.15);
uniform vec3 glow : source_color = vec3(0.0);      // 蓝银草：自己发光

varying float tip;

void vertex() {
	tip = clamp(1.0 - UV.y, 0.0, 1.0);
	vec3 wp = MODEL_MATRIX[3].xyz;
	float d = length(wp - CAMERA_POSITION_WORLD);
	float shrink = 1.0 - smoothstep(fade_start, fade_end, d);
	VERTEX *= shrink;
	// 一阵阵的风：沿一个方向推进的波
	float gust = sin(dot(wp.xz, vec2(0.11, 0.07)) - TIME * 1.7) * 0.5 + 0.5;
	float t = TIME * 2.3 + wp.x * 0.3 + wp.z * 0.23;
	float bend = (sin(t) * 0.35 + gust * 0.9) * sway * tip * tip;
	VERTEX += (inverse(mat3(MODEL_MATRIX)) * vec3(bend, -bend * 0.25, bend * 0.4));
}

void fragment() {
	vec4 c = texture(grass_tex, UV);
	vec2 dx = dFdx(UV * 256.0);
	vec2 dy = dFdy(UV * 256.0);
	float mip = 0.5 * log2(max(dot(dx, dx), dot(dy, dy)));
	ALBEDO = c.rgb * COLOR.rgb * mix(root_dark, vec3(1.0), smoothstep(0.0, 0.6, tip));
	ALPHA = c.a * (1.0 + max(mip, 0.0) * 0.35);
	ALPHA_SCISSOR_THRESHOLD = 0.4;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	ALPHA_TEXTURE_COORDINATE = UV * 256.0;
	ROUGHNESS = 0.85;
	BACKLIGHT = backlight;
	EMISSION = glow * c.rgb * (0.4 + tip * 1.2);
	// 法线大部分朝上，草地整体明暗跟地面接近，不会一片黑一片白
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz, 0.7));
}
