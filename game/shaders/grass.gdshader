shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap;
// 草叶：随风摆动，根部深、尖端浅

uniform vec3 base_color : source_color = vec3(0.18, 0.40, 0.14);
uniform vec3 tip_color : source_color = vec3(0.55, 0.78, 0.32);
uniform float sway = 0.18;

varying float tip;

void vertex() {
	tip = clamp(VERTEX.y / 0.42, 0.0, 1.0);
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float t = TIME * 1.6 + wp.x * 0.15 + wp.z * 0.11;
	float bend = (sin(t) * 0.6 + sin(t * 2.3 + wp.x) * 0.25) * sway * tip * tip;
	VERTEX.x += bend;
	VERTEX.z += bend * 0.5;
}

void fragment() {
	vec3 c = mix(base_color, tip_color, tip) * COLOR.rgb;
	ALBEDO = c;
	ROUGHNESS = 0.9;
	BACKLIGHT = vec3(0.25, 0.35, 0.15);
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz, 0.6));
}
