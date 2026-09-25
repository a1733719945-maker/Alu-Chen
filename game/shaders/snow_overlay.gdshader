shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;
// 叠在石头、树桩上的一层雪：朝上的面盖白，侧面和底下不盖

uniform float amount = 0.85;

varying vec3 wn;
varying vec3 wp;

void vertex() {
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = fract(sin(dot(floor(wp.xz * 6.0), vec2(12.9898, 78.233))) * 43758.5453);
	float k = smoothstep(0.3, 0.7, wn.y + (n - 0.5) * 0.15) * amount;
	ALBEDO = vec3(0.92, 0.95, 1.0);
	ROUGHNESS = 0.75;
	ALPHA = k;
}
