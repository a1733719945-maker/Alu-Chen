shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, depth_prepass_alpha;
// 树叶贴片：透明镂空 + 随风摆动 + 透光（逆光时叶子发亮）。
// 法线在生成网格时指向树冠中心的外侧，整棵树的明暗像一个蓬松的球，而不是一片片纸。
// UV2.x = 摆动权重（树干根部 0，枝梢 1）

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float alpha_cut = 0.45;
uniform float wind = 1.0;
uniform vec3 backlight : source_color = vec3(0.45, 0.5, 0.2);
uniform float tex_size = 512.0;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	float sway = UV2.x;
	float t = TIME * 1.1 + root.x * 0.07 + root.z * 0.05;
	// 整棵树缓慢摇 + 叶子快速抖
	vec3 big = vec3(sin(t) * 0.6 + sin(t * 0.37) * 0.4, 0.0, cos(t * 0.8) * 0.4) * 0.12 * sway * sway;
	float f = TIME * 5.0 + VERTEX.x * 2.1 + VERTEX.y * 1.7 + VERTEX.z * 1.3;
	vec3 small = vec3(sin(f), sin(f * 1.3) * 0.6, cos(f * 0.9)) * 0.035 * sway;
	VERTEX += (big + small) * wind;
}

void fragment() {
	vec4 c = texture(leaf_tex, UV);
	// 远处贴图缩小后透明部分会“吃掉”叶子，按缩小程度把不透明度补回来
	vec2 dx = dFdx(UV * tex_size);
	vec2 dy = dFdy(UV * tex_size);
	float mip = 0.5 * log2(max(dot(dx, dx), dot(dy, dy)));
	float a = c.a * (1.0 + max(mip, 0.0) * 0.3);
	ALBEDO = c.rgb * tint * COLOR.rgb;
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	ALPHA_TEXTURE_COORDINATE = UV * tex_size;
	ROUGHNESS = 0.75;
	SPECULAR = 0.3;
	BACKLIGHT = backlight * c.rgb * 2.0;
}
