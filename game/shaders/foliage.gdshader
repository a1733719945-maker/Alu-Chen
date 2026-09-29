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

uniform float bump = 0.8;          // 叶子自己的起伏（按贴图明暗凹凸），近看一片片叶子有明暗，不再是一块平涂的绿（太大会一粒粒闪）
uniform float hue_jitter = 0.08;   // 每一簇的颜色稍微不一样

float lum(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

void fragment() {
	vec4 c = texture(leaf_tex, UV);
	// 远处贴图缩小后透明部分会“吃掉”叶子，按缩小程度把不透明度补回来
	vec2 dx = dFdx(UV * tex_size);
	vec2 dy = dFdy(UV * tex_size);
	float mip = 0.5 * log2(max(dot(dx, dx), dot(dy, dy)));
	float a = c.a * (1.0 + max(mip, 0.0) * 0.3);
	// 屏幕空间凹凸（不需要切线）：贴图亮的地方凸出来。近处（mip 小）才加，远处本来就是一团
	float h = lum(c.rgb) + c.a * 0.4;
	vec3 dpx = dFdx(VERTEX);
	vec3 dpy = dFdy(VERTEX);
	vec3 n0 = normalize(NORMAL);
	vec3 r1 = cross(dpy, n0);
	vec3 r2 = cross(n0, dpx);
	float det = dot(dpx, r1);
	vec3 grad = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
	float near_k = 1.0 - smoothstep(-0.5, 1.2, mip);
	NORMAL = normalize(abs(det) * n0 - grad * bump * near_k);
	// 每簇颜色：按世界位置取一点偏黄 / 偏蓝
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float j = fract(sin(dot(floor(wp * 0.6), vec3(12.9898, 78.233, 37.719))) * 43758.5453) - 0.5;
	vec3 col = c.rgb * (1.0 + vec3(j, j * 0.4, -j) * hue_jitter * 2.0);
	// 叶子暗的部分（叶脉、叶缝）再压一点，层次更深
	col *= mix(0.78, 1.0, smoothstep(0.08, 0.5, lum(c.rgb)));
	ALBEDO = col * tint * COLOR.rgb;
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	ALPHA_TEXTURE_COORDINATE = UV * tex_size;
	ROUGHNESS = 0.75;
	SPECULAR = 0.3;
	BACKLIGHT = backlight * c.rgb * 2.0;
}
