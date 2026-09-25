shader_type spatial;
// 地形：顶点色决定草地/沙滩/岩石，法线用屏幕导数算成平面，得到低多边形的切面感

varying vec3 world_pos;

uniform float facet_strength = 0.85;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec3 flat_n = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	NORMAL = normalize(mix(NORMAL, flat_n, facet_strength));
	// 每块地面颜色有一点点随机深浅，不会显得太平
	float v = hash(floor(world_pos.xz * 0.5)) * 0.08 - 0.04;
	// 顶点色按 sRGB 写的，转成线性空间
	vec3 base = pow(COLOR.rgb, vec3(2.2));
	ALBEDO = base * (1.0 + v);
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
