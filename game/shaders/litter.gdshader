shader_type spatial;
render_mode cull_disabled;
// 地上的小零碎（落叶、松针、枯枝、碎石）：平铺在地上的贴片，图集 4×4 格（tools/make_litter.py）。
// 实例颜色的 a 是第几格（0~15），rgb 是色调。远处慢慢缩没，跟草一样不会"啪"一下消失

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float fade_start = 20.0;
uniform float fade_end = 32.0;

varying vec2 cell_off;
varying vec3 tint;

void vertex() {
	float c = floor(COLOR.a * 15.0 + 0.5);
	cell_off = vec2(mod(c, 4.0), floor(c / 4.0)) * 0.25;
	tint = COLOR.rgb;
	vec3 wp = MODEL_MATRIX[3].xyz;
	float d = length(wp - CAMERA_POSITION_WORLD);
	VERTEX *= 1.0 - smoothstep(fade_start, fade_end, d);
}

void fragment() {
	vec4 c = texture(atlas, cell_off + clamp(UV, 0.02, 0.98) * 0.25);
	ALBEDO = c.rgb * tint;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.88;
	SPECULAR = 0.3;
	// 背面朝上时法线翻过来（双面贴片），光照跟地面一致
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
