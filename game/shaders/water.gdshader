shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;
// 湖水：顶点波浪 + 深浅变色 + 岸边白沫 + 菲涅尔反光

uniform vec3 shallow_color : source_color = vec3(0.30, 0.68, 0.66);
uniform vec3 deep_color : source_color = vec3(0.04, 0.22, 0.32);
uniform vec3 foam_color : source_color = vec3(0.92, 0.97, 0.95);
uniform float depth_fade = 4.5;
uniform float foam_width = 0.7;
uniform float wave_height = 0.12;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

varying vec3 world_pos;

float wave(vec2 p, float t) {
	float w = sin(p.x * 0.35 + t * 1.1) * 0.5;
	w += sin(p.y * 0.28 - t * 0.9 + p.x * 0.1) * 0.35;
	w += sin((p.x + p.y) * 0.6 + t * 1.7) * 0.15;
	return w;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	float h = wave(world_pos.xz, t) * wave_height;
	VERTEX.y += h;
	// 用差分求波浪法线
	float e = 0.5;
	float hx = wave(world_pos.xz + vec2(e, 0.0), t) * wave_height;
	float hz = wave(world_pos.xz + vec2(0.0, e), t) * wave_height;
	NORMAL = normalize(vec3(h - hx, e, h - hz));
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	// 水下地面有多深
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	float floor_dist = -view.z;
	float surf_dist = -VERTEX.z;
	float water_depth = max(floor_dist - surf_dist, 0.0);

	float k = clamp(water_depth / depth_fade, 0.0, 1.0);
	vec3 col = mix(shallow_color, deep_color, k);

	// 轻微折射：透过浅水能看到水底
	vec2 ofs = NORMAL.xz * 0.02;
	vec3 below = texture(screen_texture, SCREEN_UV + ofs).rgb;
	col = mix(below * shallow_color * 1.6, col, clamp(k * 1.4 + 0.25, 0.0, 1.0));

	// 岸边白沫
	float n = noise(world_pos.xz * 1.5 + TIME * 0.4);
	float foam = 1.0 - smoothstep(0.0, foam_width * (0.6 + n * 0.8), water_depth);
	col = mix(col, foam_color, foam * 0.85);

	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = col;
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ALPHA = clamp(0.82 + fres * 0.18 + foam * 0.2, 0.0, 1.0);
}
