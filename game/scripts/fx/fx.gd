class_name Fx
extends Node3D
## 一次性特效：弹道、枪口火光、命中、爆炸、冲击波、法阵、光柱、光束、魂灵……全部自己销毁。
## 第七版重做（用户说特效劣质）。做法和一般游戏一样，一个特效叠好几层：
##   闪光（星芒贴图，0.1 秒）→ 主体（火球 / 光柱 / 光束着色器）→ 火花（按速度拉长的光条）→ 烟尘（软粒子，慢慢散）
##   → 地面（贴花：法阵、焦痕、裂纹、冲击环，贴着地形）→ 灯光一闪 → 热浪扭曲 → 镜头震动。
## 贴图、材质、着色器在 FxLib（fx_lib.gd），贴图由 tools/make_fx_textures.gd 生成。

var _cam: Camera3D
var _player: Node               # 用来震镜头（Player.trauma）
var _shells: Array = []
var _quad: QuadMesh             # 粒子和闪光用的 1×1 方片
var _plane: PlaneMesh           # 躺平的 1×1 方片（冲击环、魂环）
var _ball: SphereMesh           # 火球、热浪
var _c_shrink: Curve
var _c_grow: Curve
var _c_pop: Curve
# 旧接口还在用
var _spark_mesh: QuadMesh
var _soft_tex: Texture2D


func _ready() -> void:
	_quad = QuadMesh.new()
	_quad.size = Vector2(1, 1)
	_plane = PlaneMesh.new()
	_plane.size = Vector2(1, 1)
	_ball = SphereMesh.new()
	_ball.radius = 1.0
	_ball.height = 2.0
	_ball.radial_segments = 32
	_ball.rings = 16
	_spark_mesh = QuadMesh.new()
	_spark_mesh.size = Vector2(0.14, 0.14)
	_soft_tex = FxLib.tex("glow")
	_c_shrink = _curve([Vector2(0, 1), Vector2(1, 0.15)])
	_c_grow = _curve([Vector2(0, 0.35), Vector2(1, 1)])
	_c_pop = _curve([Vector2(0, 0.2), Vector2(0.12, 1), Vector2(1, 0.6)])


func _curve(pts: Array) -> Curve:
	var c := Curve.new()
	for p in pts:
		c.add_point(p)
	return c


func set_camera(c: Camera3D) -> void:
	_cam = c
	var n: Node = c
	while n and not n is Player:
		n = n.get_parent()
	_player = n


# ------------------------------------------------------------------ 基础零件

func _free_after(n: Node, t: float) -> void:
	get_tree().create_timer(t).timeout.connect(func():
		if is_instance_valid(n):
			n.queue_free())


func _near_cam(pos: Vector3, d: float) -> bool:
	return _cam != null and is_instance_valid(_cam) and _cam.global_position.distance_to(pos) < d


func _on_water(pos: Vector3) -> bool:
	return pos.y <= Island.WATER_Y + 0.35


## 颜色渐变：开头 a、结尾透明（fade_in：开头也是透明，淡入）
func _ramp(c: Color, fade_in := false, mid := Color(0, 0, 0, 0)) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(c.r, c.g, c.b, 0.0 if fade_in else c.a))
	g.set_color(1, Color(c.r, c.g, c.b, 0.0))
	if fade_in:
		g.add_point(0.12, c)
	if mid.a > 0.0:
		g.add_point(0.4, mid)
	return g


func _cp(pos: Vector3, amount: int, life: float, explosive := 0.95) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = explosive
	p.amount = maxi(amount, 1)
	p.lifetime = life
	p.mesh = _quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.global_position = pos
	_free_after(p, life + 0.4)
	return p


## 发光的光点（加法混合）
func _glows(pos: Vector3, dir: Vector3, color: Color, n: int, speed: float, life: float, size: float, gravity := -2.0, spread := 180.0, hdr := 1.6) -> CPUParticles3D:
	var p := _cp(pos, n, life)
	p.material_override = FxLib.pmat("glow", true, hdr, 1, 0.3)
	p.direction = dir if dir != Vector3.ZERO else Vector3.UP
	p.spread = spread
	p.initial_velocity_min = speed * 0.3
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, gravity, 0)
	p.damping_min = 1.0
	p.damping_max = 3.0
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size
	p.scale_amount_curve = _c_shrink
	p.color_ramp = _ramp(Color(color.r, color.g, color.b, 1.0))
	p.emitting = true
	return p


## 火花：按速度拉长的光条，开头白热，后面变成 color
func _sparks(pos: Vector3, dir: Vector3, color: Color, n: int, speed: float, life: float, size := 0.07, gravity := -9.0, spread := 60.0, stretch := 5.0) -> CPUParticles3D:
	var p := _cp(pos, n, life)
	p.material_override = FxLib.spark_mat(2.2, stretch)
	p.particle_flag_align_y = true
	p.direction = dir if dir != Vector3.ZERO else Vector3.UP
	p.spread = spread
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, gravity, 0)
	p.damping_min = 0.5
	p.damping_max = 2.0
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	p.scale_amount_curve = _c_shrink
	var g := Gradient.new()
	g.set_color(0, Color(1, 0.97, 0.9, 1))
	g.set_color(1, Color(color.r, color.g, color.b, 0))
	g.add_point(0.25, Color(color.r, color.g, color.b, 1))
	p.color_ramp = g
	p.emitting = true
	return p


## 烟 / 尘 / 水雾：普通混合的烟团，慢慢变大、转着散掉（软粒子，碰到地面不会一刀切）
func _smoke(pos: Vector3, color: Color, n: int, speed: float, life: float, size: float, rise := 0.6, spread := 180.0, dir := Vector3.UP, radius := 0.0) -> CPUParticles3D:
	var p := _cp(pos, n, life, 0.85)
	p.material_override = FxLib.pmat("smoke", false, 1.0, 2, 0.8)
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = speed * 0.3
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, rise, 0)
	p.damping_min = 2.0
	p.damping_max = 4.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -40.0
	p.angular_velocity_max = 40.0
	p.anim_offset_min = 0.0
	p.anim_offset_max = 1.0
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	p.scale_amount_curve = _c_grow
	p.color_ramp = _ramp(color, true)
	if radius > 0.0:
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = radius
	p.emitting = true
	return p


## 碎屑：小块往外飞、落下（普通混合）
func _bits(pos: Vector3, dir: Vector3, color: Color, n: int, speed: float, size := 0.08) -> void:
	var p := _cp(pos, n, 0.9)
	p.material_override = FxLib.pmat("glow", false, 1.0, 1, 0.0)
	p.direction = dir
	p.spread = 70.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -14.0, 0)
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size
	p.color_ramp = _ramp(Color(color.r * 0.6, color.g * 0.6, color.b * 0.6, 1.0))
	p.emitting = true


## 一闪：朝镜头的星芒 / 光晕，很快变大消失
func _flash(pos: Vector3, color: Color, size: float, dur := 0.12, tex_name := "flare", hdr := 2.4) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _quad
	mi.material_override = FxLib.bill_mat(tex_name, color, hdr)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * size
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * size * 1.35, dur).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mi, "transparency", 1.0, dur).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)


func _light(pos: Vector3, color: Color, energy: float, rng: float, dur: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, dur).set_ease(Tween.EASE_IN)
	tw.tween_callback(l.queue_free)


func _shake(pos: Vector3, amount: float, radius := 30.0) -> void:
	if _player == null or not is_instance_valid(_player) or not _cam:
		return
	var d := _cam.global_position.distance_to(pos)
	if d < radius:
		_player.trauma = minf(float(_player.trauma) + amount * (1.0 - d / radius), 1.0)


## 热浪：一个看不见的球把背后的画面往外推（爆炸、冲击波），画质低时不做
func _distort(pos: Vector3, radius: float, dur: float, strength := 0.035) -> void:
	# 3D 里读屏幕在带 MSAA 时会把背后画暗（第七版试过），先不做
	if true or Settings.quality == 0 or not _near_cam(pos, 90.0):
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _ball
	var m := FxLib.smat("distort", {"strength": strength, "fade": 1.0})
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.2
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * radius, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_method(func(v: float): m.set_shader_parameter("fade", v), 1.0, 0.0, dur)
	tw.tween_callback(mi.queue_free)


## 贴在地上的图（法阵、预警圈、焦痕、裂纹）：陆地上用贴花（跟着地形起伏，不会穿进坡里），水面上用躺平的方片。
## hold < 0 表示不自动消失（返回的节点交给调用的人管）。spin：每秒转多少弧度
func _ground(pos: Vector3, tex_name: String, color: Color, size: float, hold: float, fade: float, emission := 0.0, spin := 0.0, albedo_mix := 1.0) -> Node3D:
	var n: Node3D
	if _on_water(pos):
		var mi := MeshInstance3D.new()
		mi.mesh = _plane
		mi.material_override = FxLib.quad_mat(tex_name, color, maxf(emission * 0.6, 1.0), emission > 0.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.scale = Vector3(size, 1, size)
		add_child(mi)
		mi.global_position = Vector3(pos.x, Island.WATER_Y + 0.06, pos.z)
		n = mi
	else:
		var d := Decal.new()
		d.texture_albedo = FxLib.tex(tex_name)
		if emission > 0.0:
			d.texture_emission = FxLib.tex(tex_name)
			d.emission_energy = emission
		d.modulate = color
		d.albedo_mix = albedo_mix
		d.size = Vector3(size, 8.0, size)
		d.upper_fade = 0.15
		d.lower_fade = 0.4
		d.cull_mask = 1
		add_child(d)
		d.global_position = pos
		n = d
	n.rotation.y = randf() * TAU
	if spin != 0.0:
		var ts := n.create_tween().set_loops()
		ts.tween_property(n, "rotation:y", TAU * signf(spin), TAU / absf(spin)).as_relative()
	if hold >= 0.0:
		var tw := n.create_tween()
		tw.tween_interval(hold)
		if n is Decal:
			tw.tween_property(n, "modulate:a", 0.0, fade)
		else:
			tw.tween_property(n, "transparency", 1.0, fade)
		tw.tween_callback(n.queue_free)
	return n


## 改地面图的大小（贴花改 size，水面方片改 scale）
func _ground_size(n: Node3D, size: float) -> void:
	if not is_instance_valid(n):
		return
	if n is Decal:
		(n as Decal).size = Vector3(size, 8.0, size)
	else:
		n.scale = Vector3(size, 1, size)


## 地上一圈亮环往外扩（冲击波的地面部分）
func _ground_ring(pos: Vector3, color: Color, radius: float, dur: float, emission := 4.0) -> void:
	var n := _ground(pos, "ring", color, 0.5, -1.0, 0.0, emission * 0.6, 0.0, 0.6)
	var tw := n.create_tween()
	tw.tween_method(func(s: float): _ground_size(n, s), 0.5, radius * 2.2, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	if n is Decal:
		tw.parallel().tween_property(n, "modulate:a", 0.0, dur * 1.2).set_ease(Tween.EASE_IN)
	else:
		tw.parallel().tween_property(n, "transparency", 1.0, dur * 1.2).set_ease(Tween.EASE_IN)
	tw.tween_callback(n.queue_free)


## 躺平的一圈光（halo / ring 贴图），在空中变大、升高、变淡
func _air_ring(pos: Vector3, color: Color, r0: float, r1: float, dur: float, rise := 0.0, tex_name := "halo", hdr := 2.0, delay := 0.0) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _plane
	mi.material_override = FxLib.quad_mat(tex_name, color, hdr, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3(r0 * 2.5, 1, r0 * 2.5)
	mi.visible = delay <= 0.0
	var tw := mi.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
		tw.tween_callback(func(): mi.visible = true)
	tw.tween_property(mi, "scale", Vector3(r1 * 2.5, 1, r1 * 2.5), dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_property(mi, "global_position:y", pos.y + rise, dur).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mi, "transparency", 1.0, dur).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)


## 旧接口：粒子材质、发光材质
func _particle_mat(glow: bool) -> StandardMaterial3D:
	return FxLib.pmat("glow", glow, 2.5 if glow else 1.0, 1, 0.3)


func _soft_glow(color: Color) -> StandardMaterial3D:
	return FxLib.quad_mat("glow", color, 2.5, true)


## 旧接口：一团粒子。glow = 发光的光点 + 火花；不发光 = 烟尘
func _burst(pos: Vector3, normal: Vector3, color: Color, amount: int, speed: float, life: float, size: float, glow: bool, gravity := -9.0, spread := 60.0) -> void:
	if glow:
		_glows(pos, normal, color, maxi(amount / 2, 1), speed * 0.7, life, size * 0.12, gravity * 0.5, spread)
		_sparks(pos, normal, color, maxi(amount / 2, 1), speed, life * 0.8, 0.05 + size * 0.02, gravity, spread)
	else:
		_smoke(pos, color, maxi(amount / 3, 2), speed * 0.35, life * 1.6, size * 0.35, 0.4, spread, normal if normal != Vector3.ZERO else Vector3.UP)


# ------------------------------------------------------------------ 弹道

## 弹道：一道朝着镜头的辉光光迹（中间亮白、两边带颜色的光晕、尾巴渐隐），弩类暗器前面还有一支真的弩箭在飞。
## 伤害是开枪瞬间就算好的，画面上让箭飞一下更有感觉。
const TRACER_SHADER := """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, world_vertex_coords, fog_disabled;
uniform vec4 color : source_color = vec4(1.0);
uniform float width = 0.05;
uniform float intensity = 2.6;
void vertex() {
	vec3 ax = (MODEL_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz;
	float len = length(ax);
	vec3 axis = ax / max(len, 0.0001);
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 side = normalize(cross(axis, INV_VIEW_MATRIX[3].xyz - center));
	VERTEX = center + axis * (UV.y - 0.5) * len + side * (UV.x - 0.5) * width;
}
void fragment() {
	float across = abs(UV.x - 0.5) * 2.0;
	float core = exp(-across * across * 40.0);
	float halo = exp(-across * across * 5.0) * 0.5;
	float tail = pow(clamp(1.0 - UV.y, 0.0, 1.0), 1.4);
	ALBEDO = (color.rgb * (halo + core) + vec3(1.0) * core * 0.9) * tail * intensity;
}
"""
var _tracer_mesh: PlaneMesh
var _tracer_mats := {}


func _tracer_mat(color: Color, width: float) -> ShaderMaterial:
	var key := "%s|%.3f" % [color.to_html(), width]
	if _tracer_mats.has(key):
		return _tracer_mats[key]
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = TRACER_SHADER
	m.shader = sh
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("width", width)
	_tracer_mats[key] = m
	return m


## 一支弩箭：深色箭杆、发光的箭头、三片尾羽
func bolt_model(color: Color, glow := true) -> Node3D:
	var n := Node3D.new()
	U.part(n, U.cyl(0.0065, 0.0065, 0.46, 6), U.mat(Color(0.28, 0.18, 0.1), 0.55), Vector3(0, 0, 0.23), Vector3(PI / 2, 0, 0), Vector3.ONE, false)
	U.part(n, U.cyl(0.0, 0.014, 0.06, 8), U.glow(color, 6.0) if glow else U.mat(Color(0.55, 0.57, 0.6), 0.3, 0.0, 0.9), Vector3(0, 0, -0.025), Vector3(-PI / 2, 0, 0), Vector3.ONE, false)
	U.part(n, U.cyl(0.009, 0.009, 0.015, 8), U.mat(Color(0.8, 0.62, 0.28), 0.3, 0.0, 0.9), Vector3(0, 0, 0.01), Vector3(PI / 2, 0, 0), Vector3.ONE, false)
	var feather := U.mat(Color(0.75, 0.18, 0.12), 0.8)
	for k in 3:
		var fl := U.part(n, U.box(Vector3(0.0015, 0.024, 0.075)), feather, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
		fl.rotation.z = TAU * k / 3.0
		fl.position = Vector3(sin(TAU * k / 3.0) * -0.012, cos(TAU * k / 3.0) * 0.012, 0.42)
	if glow:
		var h := MeshInstance3D.new()
		h.mesh = _quad
		h.material_override = FxLib.bill_mat("glow", color, 3.0)
		h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		h.scale = Vector3.ONE * 0.14
		h.position = Vector3(0, 0, -0.03)
		n.add_child(h)
	return n


func tracer(from: Vector3, to: Vector3, color: Color, width := 0.05, speed := 260.0, length := 4.0, bolt := false) -> void:
	var dist := from.distance_to(to)
	if dist < 0.5:
		return
	if _tracer_mesh == null:
		_tracer_mesh = PlaneMesh.new()
		_tracer_mesh.size = Vector2(1, 1)
	var dir := (to - from) / dist
	var mi := MeshInstance3D.new()
	mi.mesh = _tracer_mesh
	mi.material_override = _tracer_mat(color, width)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4.0
	add_child(mi)
	var b: Node3D = null
	if bolt:
		b = bolt_model(color)
		add_child(b)
	_place_tracer(mi, b, from, dir, dist, length, 0.02)
	var t := maxf(dist / speed, 0.04)
	var tw := create_tween()
	tw.tween_method(func(k: float): _place_tracer(mi, b, from, dir, dist, length, k), 0.02, 1.0, t)
	tw.tween_method(func(k: float): _place_tracer(mi, null, from, dir, dist, length * (1.0 - k), 1.0), 0.0, 1.0, 0.07)
	tw.tween_callback(func():
		mi.queue_free()
		if is_instance_valid(b):
			b.queue_free())


func _place_tracer(mi: MeshInstance3D, b: Node3D, from: Vector3, dir: Vector3, dist: float, length: float, k: float) -> void:
	if not is_instance_valid(mi):
		return
	var head := from + dir * dist * k
	var tail := clampf(minf(length, dist * k), 0.01, 1000.0)
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	var basis := Basis.looking_at(dir, up)
	mi.global_transform = Transform3D(basis * Basis.from_scale(Vector3(1, 1, tail)), head - dir * tail * 0.5)
	if is_instance_valid(b):
		b.global_transform = Transform3D(basis, head)
		b.visible = k < 0.999


## 枪口火光：星芒一闪 + 往前喷的两片火舌 + 一点灯光 + 一小团枪口烟
func muzzle_flash(pos: Vector3, dir: Vector3, color: Color, big := false) -> void:
	var warm := color.lerp(Color(1.0, 0.85, 0.55), 0.5)
	_flash(pos, warm, 0.34 if big else 0.2, 0.05, "flare", 5.0)
	var star := Node3D.new()
	add_child(star)
	star.global_position = pos
	star.look_at(pos + dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
	star.rotate_object_local(Vector3.FORWARD, randf() * TAU)
	var L := 0.42 if big else 0.24
	for k in 2:
		var q := MeshInstance3D.new()
		q.mesh = _quad
		q.material_override = FxLib.quad_mat("spark", warm, 5.0, true)
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		star.add_child(q)
		# 方片的长边（Y）朝枪口前方（-Z）
		q.rotation = Vector3(-PI / 2, 0, 0)
		q.rotate_object_local(Vector3.UP, PI * 0.5 * k)
		q.scale = Vector3(L * 0.35, L, 1)
		q.position = Vector3(0, 0, -L * 0.45)
	var tw := star.create_tween()
	tw.tween_property(star, "scale", Vector3(0.3, 0.3, 1.3), 0.05)
	tw.tween_callback(star.queue_free)
	_light(pos, warm, 2.8 if big else 1.4, 4.5, 0.07)
	_smoke(pos + dir * 0.08, Color(0.8, 0.8, 0.78, 0.22), 2 if not big else 5, 0.8, 0.7, 0.35 if not big else 0.6, 0.4, 25.0, dir)
	if big:
		_sparks(pos, dir, warm, 6, 9.0, 0.25, 0.04, -4.0, 18.0, 6.0)


## 抛壳：一枚铜壳从抛壳口飞出去，转着落下
func shell(pos: Vector3, vel: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = U.cyl(0.006, 0.006, 0.024, 6)
	mi.material_override = U.mat(Color(0.85, 0.62, 0.25), 0.3, 0.0, 0.9)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	_shells.append({"mi": mi, "v": vel, "t": 0.0, "spin": Vector3(randf_range(10, 25), randf_range(-8, 8), randf_range(10, 25))})


func _process(dt: float) -> void:
	_update_summon_visuals(dt)
	_update_orbit_visuals(dt)
	for s in _shells.duplicate():
		s["t"] += dt
		var mi: MeshInstance3D = s["mi"]
		if s["t"] > 0.9 or not is_instance_valid(mi):
			_shells.erase(s)
			if is_instance_valid(mi):
				mi.queue_free()
			continue
		s["v"] = (s["v"] as Vector3) + Vector3(0, -9.8 * dt, 0)
		mi.global_position += (s["v"] as Vector3) * dt
		mi.rotation += (s["spin"] as Vector3) * dt


# ------------------------------------------------------------------ 命中

## 打到地面 / 树 / 石头：一小团尘、几粒碎屑、一点火星
func impact_world(pos: Vector3, normal: Vector3) -> void:
	_smoke(pos + normal * 0.1, Color(0.62, 0.56, 0.47, 0.55), 3, 1.2, 0.8, 0.45, 0.3, 40.0, normal)
	_bits(pos, normal, Color(0.5, 0.42, 0.32), 5, 3.5, 0.05)
	_sparks(pos, normal, Color(1.0, 0.75, 0.4), 3, 4.0, 0.18, 0.03, -9.0, 50.0, 4.0)


## 打到魂兽：颜色的星芒一闪 + 拉长的火花 + 几颗光点；爆头更大，还有一圈光
func impact_beast(pos: Vector3, normal: Vector3, color: Color, headshot: bool) -> void:
	var c := Color(color.r, color.g, color.b, 1.0)
	_flash(pos, c.lerp(Color.WHITE, 0.35), 0.8 if headshot else 0.45, 0.08)
	_sparks(pos, normal, c, 12 if headshot else 7, 7.0 if headshot else 5.0, 0.35, 0.06, -6.0, 65.0)
	_glows(pos, normal, c, 5 if headshot else 3, 2.0, 0.4, 0.18, -1.0, 90.0)
	if headshot:
		_flash(pos, Color(1.0, 0.9, 0.5), 1.4, 0.16, "halo", 3.0)


## 落水：水花（往上溅、落下的水滴）+ 水雾 + 水面一圈白沫往外扩
func splash(pos: Vector3, big := false) -> void:
	var at := Vector3(pos.x, Island.WATER_Y + 0.05, pos.z)
	_sparks(at, Vector3.UP, Color(0.8, 0.92, 1.0), 34 if big else 12, 8.0 if big else 4.5, 0.9, 0.09 if big else 0.06, -16.0, 22.0, 3.5)
	_smoke(at + Vector3.UP * 0.3, Color(0.9, 0.95, 1.0, 0.45), 8 if big else 3, 2.0, 1.2, 1.6 if big else 0.8, 0.2, 60.0)
	_air_ring(at + Vector3.UP * 0.03, Color(0.85, 0.95, 1.0), 0.3, 3.0 if big else 1.6, 0.8, 0.0, "ring", 1.4)
	if big:
		_air_ring(at + Vector3.UP * 0.03, Color(0.85, 0.95, 1.0), 0.2, 1.8, 1.1, 0.0, "ring", 1.0, 0.15)


func dirt_puff(pos: Vector3) -> void:
	_smoke(pos, Color(0.55, 0.44, 0.32, 0.75), 6, 2.5, 1.1, 1.2, 0.2, 60.0)
	_bits(pos, Vector3.UP, Color(0.45, 0.35, 0.25), 8, 4.0, 0.07)


## 魂兽死亡：星芒一闪、魂力碎片炸开、光点慢慢往上飘，脚下的魂环扩散消失；年份越高越大
func death_burst(pos: Vector3, color: Color, age: int) -> void:
	var c := Color(color.r, color.g, color.b, 1.0)
	if c.get_luminance() < 0.2:
		c = Color(0.8, 0.1, 0.12)
	_flash(pos, c.lerp(Color.WHITE, 0.3), 2.2 + age * 0.8, 0.18)
	_sparks(pos, Vector3.UP, c, 26 + age * 14, 9.0 + age, 0.7, 0.08, -5.0, 180.0, 5.0)
	_glows(pos, Vector3.UP, c, 18 + age * 10, 2.5, 1.6, 0.35, 1.2, 180.0)
	_air_ring(pos - Vector3.UP * 0.3, c, 0.6, 3.5 + age * 1.5, 0.55, 0.5)
	_light(pos, c, 5.0 + age, 9.0, 0.5)
	if age >= 2:
		_distort(pos, 3.0 + age, 0.4, 0.03)
		_air_ring(pos, c, 0.5, 2.5 + age, 0.7, 2.0, "ring", 2.0, 0.08)
	if age >= 3:
		_smoke(pos, Color(0.12, 0.05, 0.08, 0.6), 8, 3.0, 1.8, 2.0, 1.0)


## 伤害数字：从命中点往上飘，出来时弹一下
func damage_number(pos: Vector3, amount: float, headshot: bool, kill := false) -> void:
	var l := U.label3d(str(roundi(amount)), 72 if headshot or kill else 56, Color(1, 0.86, 0.3) if headshot else Color(1, 1, 1), 12)
	l.font = Data.font_num
	if kill:
		l.modulate = Color(1.0, 0.4, 0.3)
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0011
	add_child(l)
	var side := Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4))
	l.global_position = pos + Vector3(0, 0.2, 0) + side * 0.5
	l.scale = Vector3.ONE * 1.6
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "global_position", l.global_position + Vector3(0, 1.1, 0) + side, 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.45).set_delay(0.3)
	tw.tween_callback(l.queue_free)


## 逃走、消失时一团烟
func poof(pos: Vector3) -> void:
	_smoke(pos, Color(0.92, 0.92, 0.95, 0.7), 9, 2.2, 1.2, 1.5, 0.6, 180.0, Vector3.UP, 0.4)
	_glows(pos, Vector3.UP, Color(1, 1, 1), 6, 2.0, 0.6, 0.2, 0.5)


# ------------------------------------------------------------------ 箭插在树上 / 地上 / 魂兽身上

var _arrows: Array = []


func stick_arrow(pos: Vector3, dir: Vector3, on: Node3D) -> void:
	var a := bolt_model(Color(0.6, 0.6, 0.6), false)
	if on and is_instance_valid(on):
		on.add_child(a)
	else:
		add_child(a)
	a.global_position = pos - dir * 0.05
	a.look_at(pos + dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
	# look_at 让 -Z 朝前：箭杆在 +Z 那边，正好露在外面
	_arrows.append(a)
	if _arrows.size() > 70:
		var old: Variant = _arrows.pop_front()
		if is_instance_valid(old):
			(old as Node).queue_free()
	# 箭可能插在魂兽身上，魂兽先没了箭也跟着没了：用弱引用，别抓着已经释放的节点
	var wr: WeakRef = weakref(a)
	get_tree().create_timer(12.0).timeout.connect(func():
		var n: Node = wr.get_ref()
		if n:
			n.queue_free())


# ------------------------------------------------------------------ 魂环

func _ring_glow(color: Color) -> Color:
	return Color(0.8, 0.08, 0.12) if color.get_luminance() < 0.2 else color


## 地上掉落的魂环：两圈转着的魂环（大的贴地、小的在上面反着转）+ 冲天的光柱 + 往上飘的光点 + 灯
func soul_ring(pos: Vector3, color: Color) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = pos
	var glow := _ring_glow(color)
	var r1 := FxLib.soul_ring(color, glow, 1.0, 2.6)
	n.add_child(r1)
	var r2 := FxLib.soul_ring(color, glow, 0.62, 2.0)
	r2.position = Vector3(0, 0.3, 0)
	n.add_child(r2)
	for pair in [[r1, 1.0], [r2, -1.6]]:
		var rn: Node3D = pair[0]
		var tw := rn.create_tween().set_loops()
		tw.tween_property(rn, "rotation:y", TAU * signf(pair[1]), TAU / absf(pair[1])).as_relative()
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.45
	cm.bottom_radius = 0.3
	cm.height = 16.0
	cm.cap_top = false
	cm.cap_bottom = false
	cm.radial_segments = 20
	beam.mesh = cm
	beam.material_override = FxLib.smat("pillar", {"color": glow, "hdr": 1.8, "half_h": 8.0, "speed": 0.5, "top": 0.2})
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position = Vector3(0, 8.0, 0)
	n.add_child(beam)
	var p := CPUParticles3D.new()
	p.amount = 18
	p.lifetime = 1.8
	p.mesh = _quad
	p.material_override = FxLib.pmat("glow", true, 1.7, 1, 0.0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 0.95
	p.emission_ring_inner_radius = 0.7
	p.emission_ring_height = 0.05
	p.direction = Vector3.UP
	p.spread = 8.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.4
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.08
	p.scale_amount_max = 0.16
	p.scale_amount_curve = _c_shrink
	p.color_ramp = _ramp(Color(glow.r, glow.g, glow.b, 1.0))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(p)
	var light := OmniLight3D.new()
	light.light_color = glow
	light.light_energy = 2.0
	light.omni_range = 8.0
	light.position = Vector3(0, 0.6, 0)
	n.add_child(light)
	return n


## 吸收魂环：脚下法阵、光柱罩住玩家、魂环从头顶慢慢落下、光点往身上聚
func absorb(target: Node3D, color: Color) -> void:
	var pos := target.global_position
	var glow := _ring_glow(color)
	_ground(pos, "magic", glow, 5.0, 2.6, 0.5, 1.8, 0.8, 0.5)
	var n := Node3D.new()
	add_child(n)
	n.global_position = pos
	var cm := CylinderMesh.new()
	cm.top_radius = 1.6
	cm.bottom_radius = 1.6
	cm.height = 30.0
	cm.cap_top = false
	cm.cap_bottom = false
	cm.radial_segments = 32
	var pillar := MeshInstance3D.new()
	pillar.mesh = cm
	var pm := FxLib.smat("pillar", {"color": glow, "hdr": 1.1, "half_h": 15.0, "speed": 0.9, "top": 0.35})
	pillar.material_override = pm
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pillar.position = Vector3(0, 15, 0)
	n.add_child(pillar)
	var ring := FxLib.soul_ring(color, glow, 1.1, 3.0)
	ring.position = Vector3(0, 8, 0)
	n.add_child(ring)
	var tw := n.create_tween()
	tw.tween_property(ring, "position:y", 1.0, 2.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(ring, "rotation:y", TAU * 2.0, 2.6)
	tw.parallel().tween_property(ring, "scale", Vector3.ONE * 0.8, 2.6)
	tw.tween_method(func(v: float): pm.set_shader_parameter("fade", v), 1.0, 0.0, 0.4)
	tw.tween_callback(n.queue_free)
	# 光点从四周往身上聚
	var p := _cp(pos + Vector3.UP, 70, 1.4, 0.3)
	p.material_override = FxLib.pmat("glow", true, 1.7, 1, 0.0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 4.0
	p.emission_ring_inner_radius = 3.0
	p.emission_ring_height = 2.0
	p.radial_accel_min = -9.0
	p.radial_accel_max = -6.0
	p.tangential_accel_min = 4.0
	p.tangential_accel_max = 7.0
	p.gravity = Vector3(0, 0.8, 0)
	p.scale_amount_min = 0.12
	p.scale_amount_max = 0.3
	p.color_ramp = _ramp(Color(glow.r, glow.g, glow.b, 1.0), true)
	p.emitting = true
	_light(pos + Vector3.UP, glow, 4.0, 10.0, 2.6)


# ------------------------------------------------------------------ Boss 和魂兽的攻击

## 飞过来的东西：毒液（绿色火球 + 滴下来的毒）、蛛网团、石头（带尘土拖尾）
func hazard_ball(kind: String, color: Color) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	if kind == "rock":
		U.part(n, U.sphere(0.45, 10, 6), U.mat(color), Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.85, 1.1))
		n.add_child(_trail_particles(Color(0.55, 0.47, 0.38, 0.5), false, 0.5, 0.6))
		return n
	var ball := MeshInstance3D.new()
	ball.mesh = _ball
	ball.material_override = FxLib.smat("fire", {"color": color, "hdr": 2.0, "speed": 2.0})
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ball.scale = Vector3.ONE * 0.38
	n.add_child(ball)
	var h := MeshInstance3D.new()
	h.mesh = _quad
	h.material_override = FxLib.bill_mat("glow", color, 2.0)
	h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	h.scale = Vector3.ONE * 1.6
	n.add_child(h)
	n.add_child(_trail_particles(color, true, 0.25, 0.4))
	if kind == "spit":
		var p := CPUParticles3D.new()
		p.amount = 14
		p.lifetime = 0.6
		p.mesh = _quad
		p.material_override = FxLib.pmat("glow", true, 1.4, 1, 0.0)
		p.gravity = Vector3(0, -9, 0)
		p.initial_velocity_max = 0.6
		p.scale_amount_min = 0.06
		p.scale_amount_max = 0.12
		p.color = color
		n.add_child(p)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.5
	light.omni_range = 4.0
	n.add_child(light)
	return n


## 跟着飞行物的拖尾（粒子留在世界里）
func _trail_particles(color: Color, glow: bool, size: float, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 30
	p.lifetime = life
	p.mesh = _quad
	p.local_coords = false
	p.material_override = FxLib.pmat("glow", true, 1.5, 1, 0.0) if glow else FxLib.pmat("smoke", false, 1.0, 2, 0.5)
	p.gravity = Vector3(0, 0.5, 0)
	p.initial_velocity_max = 0.3
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	p.scale_amount_curve = _c_shrink if glow else _c_grow
	p.anim_offset_max = 1.0
	p.angle_max = 360.0
	p.color_ramp = _ramp(Color(color.r, color.g, color.b, color.a if not glow else 1.0), not glow)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## 红圈预警：地上外圈一直亮着，里面一圈从中间长到外圈，长满了就砸下来
func telegraph(center: Vector3, radius: float, delay: float, color := Color(1.0, 0.2, 0.15)) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = center
	var outer := _ground(center, "warn", color, radius * 2.0, -1.0, 0.0, 1.4, 0.0, 0.85)
	outer.reparent(n)
	var inner := _ground(center, "warn", color.lerp(Color(1, 0.6, 0.3), 0.3), 0.3, -1.0, 0.0, 1.8, 0.0, 0.6)
	inner.reparent(n)
	var tw := n.create_tween()
	tw.tween_method(func(s: float): _ground_size(inner, s), 0.3, radius * 2.0, maxf(delay, 0.05)).set_ease(Tween.EASE_IN)
	# 外圈一闪一闪
	if outer is Decal:
		var tp := outer.create_tween().set_loops()
		tp.tween_property(outer, "emission_energy", 2.6, 0.18)
		tp.tween_property(outer, "emission_energy", 1.2, 0.18)
	return n


## Boss 砸地：地面裂开（发红光的裂纹慢慢熄灭）、尘土往外翻、碎石飞、冲击波、镜头震
func slam(center: Vector3, radius: float) -> void:
	if _on_water(center):
		splash(center, true)
	else:
		_ground(center, "crack", Color(0.1, 0.07, 0.05, 0.9), radius * 1.3, 4.0, 2.0, 0.0, 0.0, 1.0)
		_ground(center, "crack", Color(1.0, 0.45, 0.15, 1.0), radius * 1.3, 0.2, 1.2, 2.5, 0.0, 0.0)
		_bits(center + Vector3.UP * 0.3, Vector3.UP, Color(0.5, 0.42, 0.33), 22, 9.0, 0.16)
	var dust := _smoke(center + Vector3.UP * 0.4, Color(0.62, 0.54, 0.44, 0.75), 18, 7.0, 1.8, 2.6, 0.3, 80.0)
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	dust.emission_ring_axis = Vector3.UP
	dust.emission_ring_radius = radius * 0.4
	dust.emission_ring_inner_radius = 0.2
	dust.emission_ring_height = 0.2
	dust.radial_accel_min = 6.0
	dust.radial_accel_max = 10.0
	shockwave(center, radius, Color(1.0, 0.5, 0.3))
	_shake(center, 0.5, 30.0)


## 毒池：地上一滩发光的绿、冒泡、飘毒雾
func poison_pool(pos: Vector3, radius: float) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = pos + Vector3(0, 0.08, 0)
	var g := _ground(pos, "scorch", Color(0.35, 0.95, 0.2, 0.95), radius * 2.3, -1.0, 0.0, 1.0, 0.15, 0.7)
	g.reparent(n)
	var p := CPUParticles3D.new()
	p.amount = 26
	p.lifetime = 1.3
	p.mesh = _quad
	p.material_override = FxLib.pmat("glow", true, 1.4, 1, 0.0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * 0.8
	p.direction = Vector3.UP
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.1
	p.gravity = Vector3(0, 0.6, 0)
	p.scale_amount_min = 0.08
	p.scale_amount_max = 0.2
	p.scale_amount_curve = _c_pop
	p.color_ramp = _ramp(Color(0.55, 1.0, 0.3, 1.0))
	n.add_child(p)
	var mist := CPUParticles3D.new()
	mist.amount = 10
	mist.lifetime = 2.6
	mist.mesh = _quad
	mist.material_override = FxLib.pmat("smoke", false, 1.0, 2, 0.8)
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	mist.emission_sphere_radius = radius * 0.7
	mist.gravity = Vector3(0, 0.25, 0)
	mist.initial_velocity_max = 0.2
	mist.scale_amount_min = radius * 0.5
	mist.scale_amount_max = radius * 0.9
	mist.scale_amount_curve = _c_grow
	mist.anim_offset_max = 1.0
	mist.angle_max = 360.0
	mist.color_ramp = _ramp(Color(0.45, 0.8, 0.25, 0.35), true)
	n.add_child(mist)
	return n


func web_burst(pos: Vector3) -> void:
	_sparks(pos + Vector3.UP * 0.5, Vector3.UP, Color(0.95, 0.95, 1.0), 26, 6.0, 0.8, 0.07, -3.0, 180.0, 7.0)
	_smoke(pos + Vector3.UP * 0.5, Color(0.95, 0.95, 1.0, 0.5), 6, 2.0, 1.0, 1.2, 0.0)


# ------------------------------------------------------------------ 佛怒唐莲

func lotus() -> Node3D:
	var n := Node3D.new()
	add_child(n)
	var pink := Color(1.0, 0.55, 0.75)
	var petal := FxLib.smat("spirit", {"color": pink, "hdr": 3.0})
	for k in 8:
		var a := TAU * k / 8.0
		U.part(n, U.sphere(0.09, 8, 6), petal, Vector3(cos(a) * 0.1, 0.03, sin(a) * 0.1), Vector3.ZERO, Vector3(1.6, 0.4, 0.8), false).rotation.y = -a
	var core := MeshInstance3D.new()
	core.mesh = _quad
	core.material_override = FxLib.bill_mat("flare", Color(1.0, 0.85, 0.6), 4.0)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core.scale = Vector3.ONE * 0.7
	n.add_child(core)
	n.add_child(_trail_particles(pink, true, 0.18, 0.35))
	var light := OmniLight3D.new()
	light.light_color = pink
	light.light_energy = 1.8
	light.omni_range = 4.0
	n.add_child(light)
	return n


func lotus_explosion(pos: Vector3) -> void:
	var pink := Color(1.0, 0.55, 0.72)
	explosion(pos, 7.0, pink)
	# 花瓣：粉色的光片慢慢飘落
	var p := _cp(pos, 36, 2.4)
	p.material_override = FxLib.pmat("glow", true, 1.2, 1, 0.0)
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 11.0
	p.gravity = Vector3(0, -2.5, 0)
	p.damping_min = 2.0
	p.damping_max = 4.0
	p.scale_amount_min = 0.15
	p.scale_amount_max = 0.35
	p.scale_amount_curve = _c_shrink
	p.color_ramp = _ramp(Color(1.0, 0.72, 0.85, 1.0))
	p.emitting = true


# ------------------------------------------------------------------ 爆炸、冲击波

## 爆炸：星芒一闪 → 火球翻滚着烧散 → 火花四溅 → 黑烟升起 → 地上焦痕 → 冲击波 → 灯光 → 热浪 → 镜头震
func explosion(pos: Vector3, radius: float, color: Color) -> void:
	var c := Color(color.r, color.g, color.b, 1.0)
	_flash(pos, c.lerp(Color.WHITE, 0.5), radius * 0.9, 0.12)
	# 火球核心：表面鼓包、翻滚，边上烧散
	var ball := MeshInstance3D.new()
	ball.mesh = _ball
	var fm := FxLib.smat("fire", {"color": c, "hdr": 2.2, "progress": 0.0, "lumpy": 0.35})
	ball.material_override = fm
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ball)
	ball.global_position = pos
	ball.scale = Vector3.ONE * 0.3
	var tw := ball.create_tween()
	tw.tween_property(ball, "scale", Vector3.ONE * radius * 0.38, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_method(func(v: float): fm.set_shader_parameter("progress", v), 0.0, 1.0, 0.5).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(ball, "global_position:y", pos.y + radius * 0.2, 0.5)
	tw.tween_callback(ball.queue_free)
	# 一团团往外翻的火（烟团贴图、加法），从白热 → 颜色 → 暗红 → 没了
	_fire(pos, c, 12 + int(radius * 2.0), radius)
	_sparks(pos, Vector3.UP, c, 22 + int(radius * 3.0), radius * 3.0 + 4.0, 0.9, 0.09, -9.0, 180.0, 5.0)
	_glows(pos, Vector3.UP, c, 10, radius * 1.2, 1.2, 0.22, 1.5, 180.0)
	_smoke(pos + Vector3.UP * 0.3, Color(c.r * 0.18 + 0.08, c.g * 0.15 + 0.07, c.b * 0.15 + 0.07, 0.75), 10, radius * 0.9, 2.2, radius * 0.7, 1.4, 180.0, Vector3.UP, radius * 0.25)
	if not _on_water(pos) and pos.y - _ground_y(pos) < 2.0:
		_ground(Vector3(pos.x, _ground_y(pos), pos.z), "scorch", Color(0, 0, 0, 0.85), radius * 1.5, 6.0, 3.0)
	shockwave(pos, radius, c)
	_light(pos + Vector3.UP, c.lerp(Color(1, 0.8, 0.5), 0.3), 9.0, radius * 3.0, 0.55)
	_distort(pos, radius * 1.2, 0.4, 0.04)
	_shake(pos, clampf(radius * 0.08, 0.15, 0.6), radius * 5.0)


## 火团：加法混合的烟团贴图，冲出去以后停住、变大、颜色从白热变暗
func _fire(pos: Vector3, color: Color, n: int, radius: float) -> void:
	var p := _cp(pos, n, 0.85, 0.95)
	p.material_override = FxLib.pmat("smoke", true, 1.5, 2, 0.4)
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = radius * 1.2
	p.initial_velocity_max = radius * 2.8
	p.damping_min = radius * 2.5
	p.damping_max = radius * 4.0
	p.gravity = Vector3(0, 2.5, 0)
	p.angle_max = 360.0
	p.angular_velocity_min = -70.0
	p.angular_velocity_max = 70.0
	p.anim_offset_max = 1.0
	p.scale_amount_min = radius * 0.35
	p.scale_amount_max = radius * 0.65
	p.scale_amount_curve = _c_grow
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.82, 1.0))
	g.set_color(1, Color(color.r * 0.3, color.g * 0.1, color.b * 0.05, 0.0))
	g.add_point(0.2, Color(color.r, color.g * 0.9, color.b * 0.8, 1.0))
	g.add_point(0.55, Color(color.r * 0.7, color.g * 0.35, color.b * 0.2, 0.55))
	p.color_ramp = g
	p.emitting = true


## 地面高度（有岛就问岛，没有就当成 pos 本身）
func _ground_y(pos: Vector3) -> float:
	var w := get_parent()
	var isl: Variant = w.get("island") if w else null
	if isl != null:
		return maxf(isl.height_at(pos.x, pos.z), Island.WATER_Y)
	return pos.y


## 冲击波：地上一圈亮环往外扩 + 一圈矮矮的光墙跟着扩（带热浪）+ 尘土往外翻
func shockwave(center: Vector3, radius: float, color: Color) -> void:
	var c := Color(color.r, color.g, color.b, 1.0)
	var gy := _ground_y(center)
	var g := Vector3(center.x, gy, center.z)
	_ground_ring(g, c, radius, 0.45)
	var wall := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 1.4
	cm.cap_top = false
	cm.cap_bottom = false
	cm.radial_segments = 64
	wall.mesh = cm
	var wm := FxLib.smat("pillar", {"color": c, "hdr": 1.6, "half_h": 0.7, "speed": 2.0, "top": 0.0, "rim_k": 0.6})
	wall.material_override = wm
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wall)
	wall.global_position = g + Vector3(0, 0.6, 0)
	wall.scale = Vector3(0.1, 0.5, 0.1)
	var tw := wall.create_tween()
	tw.tween_property(wall, "scale", Vector3(radius, 1.0, radius), 0.38).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_method(func(v: float): wm.set_shader_parameter("fade", v), 1.0, 0.0, 0.45).set_ease(Tween.EASE_IN)
	tw.tween_callback(wall.queue_free)
	if not _on_water(g):
		var dust := _smoke(g + Vector3.UP * 0.3, Color(0.66, 0.6, 0.5, 0.55), 12, 1.0, 1.2, 1.4, 0.2, 30.0)
		dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		dust.emission_ring_axis = Vector3.UP
		dust.emission_ring_radius = maxf(radius * 0.3, 0.5)
		dust.emission_ring_inner_radius = 0.1
		dust.emission_ring_height = 0.1
		dust.radial_accel_min = radius * 3.0
		dust.radial_accel_max = radius * 4.5
	_distort(g + Vector3.UP * 0.5, radius, 0.35, 0.025)


# ------------------------------------------------------------------ 魂技：藤蔓、法阵、漩涡、光束、光环

## 藤蔓：从地里钻出来的弯曲藤条（四节越来越细、带刺），脚下法阵，飘叶子
func vines(center: Vector3, radius: float, color: Color, count := 14) -> void:
	var vc := color.lerp(Color(0.15, 0.5, 0.3), 0.55)
	var vm := U.mat(vc, 0.6, 0.6)
	var thorn := U.mat(vc.lightened(0.3), 0.5, 1.2)
	var gy := _ground_y(center)
	for k in count:
		var a := randf() * TAU
		var d := sqrt(randf()) * radius
		var root := Node3D.new()
		add_child(root)
		var p := Vector3(center.x + cos(a) * d, gy, center.z + sin(a) * d)
		root.global_position = p + Vector3(0, -2.4, 0)
		root.rotation = Vector3(0, randf() * TAU, 0)
		# 四节，每节往一边再弯一点
		var parent: Node3D = root
		var bend := randf_range(0.18, 0.35) * (1.0 if randf() < 0.5 else -1.0)
		var w0 := randf_range(0.06, 0.09)
		for s in 4:
			var seg := Node3D.new()
			seg.position = Vector3(0, 0.75 if s > 0 else 0.0, 0)
			seg.rotation = Vector3(bend, 0, bend * 0.4)
			parent.add_child(seg)
			var r0 := w0 * (1.0 - s * 0.22)
			U.part(seg, U.cyl(r0 * 0.78, r0, 0.8, 7), vm, Vector3(0, 0.4, 0), Vector3.ZERO, Vector3.ONE, false)
			if s > 0:
				U.part(seg, U.cyl(0.0, r0 * 0.6, 0.18, 4), thorn, Vector3(r0, 0.35, 0), Vector3(0, 0, -1.2), Vector3.ONE, false)
			parent = seg
		var tw := root.create_tween()
		tw.tween_property(root, "global_position:y", p.y - 0.2, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_interval(2.4)
		tw.tween_property(root, "global_position:y", p.y - 3.2, 0.5).set_ease(Tween.EASE_IN)
		tw.tween_callback(root.queue_free)
	_bits(Vector3(center.x, gy + 0.2, center.z), Vector3.UP, Color(0.4, 0.32, 0.22), 14, 5.0, 0.1)
	_glows(Vector3(center.x, gy + 0.5, center.z), Vector3.UP, color.lerp(Color(0.5, 1.0, 0.5), 0.5), 20, 2.0, 1.6, 0.18, 0.5)
	sigil(center, radius, color)


## 法阵：地上一个转着的魂力法阵，亮一下慢慢淡掉，外圈往上飘光点
func sigil(center: Vector3, radius: float, color: Color) -> void:
	var c := Color(color.r, color.g, color.b, 1.0)
	var gy := _ground_y(center)
	var g := Vector3(center.x, gy, center.z)
	var n := _ground(g, "magic", c, radius * 2.2, 1.0, 0.6, 2.0, 1.2, 0.6)
	if n is Decal:
		(n as Decal).emission_energy = 4.0
		var tw := n.create_tween()
		tw.tween_property(n, "emission_energy", 2.0, 0.35)
	var p := _cp(g + Vector3.UP * 0.1, 30, 1.2, 0.5)
	p.material_override = FxLib.pmat("glow", true, 1.7, 1, 0.0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = radius
	p.emission_ring_inner_radius = radius * 0.85
	p.emission_ring_height = 0.1
	p.direction = Vector3.UP
	p.spread = 5.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.5
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.1
	p.scale_amount_max = 0.22
	p.scale_amount_curve = _c_shrink
	p.color_ramp = _ramp(c)
	p.emitting = true
	_light(g + Vector3.UP, c, 3.0, radius * 2.0 + 4.0, 1.2)


## 漩涡（牵引）：地上一个转得很快的旋涡，光点往中间卷
func vortex(center: Vector3, radius: float, color: Color) -> void:
	var c := Color(color.r, color.g, color.b, 1.0)
	var gy := _ground_y(center)
	var g := Vector3(center.x, gy, center.z)
	_ground(g, "swirl", c, radius * 2.4, 1.4, 0.6, 2.0, -5.0, 0.5)
	var p := _cp(g + Vector3.UP, 90, 1.8, 0.25)
	p.material_override = FxLib.pmat("glow", true, 1.7, 1, 0.0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = radius
	p.emission_ring_inner_radius = radius * 0.8
	p.emission_ring_height = 0.6
	p.radial_accel_min = -14.0
	p.radial_accel_max = -9.0
	p.tangential_accel_min = 10.0
	p.tangential_accel_max = 15.0
	p.gravity = Vector3(0, 2, 0)
	p.scale_amount_min = 0.15
	p.scale_amount_max = 0.3
	p.scale_amount_curve = _c_shrink
	p.color_ramp = _ramp(c, true)
	p.emitting = true
	var dust := _smoke(g + Vector3.UP * 0.4, Color(0.6, 0.55, 0.5, 0.4), 10, 0.5, 1.6, radius * 0.4, 0.8, 30.0)
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	dust.emission_ring_axis = Vector3.UP
	dust.emission_ring_radius = radius
	dust.emission_ring_inner_radius = radius * 0.7
	dust.emission_ring_height = 0.2
	dust.radial_accel_min = -8.0
	dust.radial_accel_max = -5.0
	dust.tangential_accel_min = 6.0
	dust.tangential_accel_max = 9.0
	sigil(center, radius, color)


## 光束：朝镜头的光带（噪声往前流、白芯），起点和终点各一闪，沿途散落光点，粗的还有灯光
func beam(origin: Vector3, dir: Vector3, length: float, color: Color, width := 0.35) -> void:
	dir = dir.normalized()
	if length < 0.3:
		return
	var c := Color(color.r, color.g, color.b, 1.0)
	var w := maxf(width * 2.2, 0.1)
	var mi := MeshInstance3D.new()
	mi.mesh = _plane
	var bm := FxLib.smat("beam", {"color": c, "width": w, "hdr": 2.3, "len_m": length})
	mi.material_override = bm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = length
	add_child(mi)
	var basis := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
	mi.global_transform = Transform3D(basis * Basis.from_scale(Vector3(1, 1, length)), origin + dir * length * 0.5)
	var tw := mi.create_tween()
	tw.tween_method(func(v: float): bm.set_shader_parameter("width", v), w * 1.4, w, 0.06)
	tw.tween_interval(0.12)
	tw.tween_method(func(v: float): bm.set_shader_parameter("width", v), w, 0.0, 0.28).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)
	_flash(origin + dir * 1.2, c.lerp(Color.WHITE, 0.4), w * 1.4, 0.15)
	if width >= 0.3:
		var end := origin + dir * length
		_flash(end, c, w * 2.5, 0.2)
		_sparks(end, -dir, c, 24, 9.0, 0.6, 0.09, -4.0, 80.0)
		var p := _cp(origin + dir * length * 0.5, int(clampf(length * 2.5, 16, 120)), 0.9, 0.9)
		p.material_override = FxLib.pmat("glow", true, 1.7, 1, 0.0)
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(width, width, length * 0.5)
		p.rotation = basis.get_euler()
		p.direction = Vector3(1, 0, 0)
		p.spread = 180.0
		p.initial_velocity_min = 0.6
		p.initial_velocity_max = 2.5
		p.gravity = Vector3.ZERO
		p.scale_amount_min = 0.1
		p.scale_amount_max = 0.25
		p.scale_amount_curve = _c_shrink
		p.color_ramp = _ramp(c)
		p.emitting = true
		_light(origin + dir * minf(length, 12.0), c, 5.0, 12.0, 0.35)


## 光环（增益、治疗、护盾）：脚下一圈光往外扩、一圈光往上升、光点往上飘
func aura_burst(pos: Vector3, color: Color, radius: float) -> void:
	var c := Color(color.r, color.g, color.b, 1.0)
	var gy := _ground_y(pos)
	_air_ring(Vector3(pos.x, gy + 0.08, pos.z), c, 0.5, maxf(radius * 0.7, 1.6), 0.6, 0.0, "halo", 3.0)
	_air_ring(Vector3(pos.x, gy + 0.2, pos.z), c, 0.9, 1.3, 0.8, 2.4, "halo", 2.5, 0.05)
	_glows(pos + Vector3.UP * 0.6, Vector3.UP, c, 22, 3.0, 1.1, 0.22, 1.5, 60.0)
	_sparks(pos + Vector3.UP * 0.3, Vector3.UP, c, 10, 5.0, 0.6, 0.05, 0.0, 25.0, 6.0)
	_light(pos + Vector3.UP, c, 3.0, 6.0, 0.6)


func heal_burst(pos: Vector3) -> void:
	aura_burst(pos, Color(0.5, 1.0, 0.55), 2.0)


func trail(from: Vector3, to: Vector3, color: Color) -> void:
	_glows(to, (from - to).normalized(), color, 4, 1.0, 0.35, 0.2, 0.0, 20.0)


# ------------------------------------------------------------------ 成长的"爽感"：升级、魂环突破、高阶魂技的额外层次

## 从地面往上飘的光点（环形发射）+ 几道往上的光条
func _rise(pos: Vector3, color: Color, amount: int, radius: float, speed: float, life: float, size := 1.6) -> void:
	var c := Color(color.r, color.g, color.b, 1.0)
	var p := _cp(pos, amount, life, 0.6)
	p.material_override = FxLib.pmat("glow", true, 1.8, 1, 0.0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = radius
	p.emission_ring_inner_radius = radius * 0.3
	p.emission_ring_height = 0.2
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.tangential_accel_min = 2.0
	p.tangential_accel_max = 5.0
	p.gravity = Vector3.ZERO
	p.damping_min = 0.5
	p.damping_max = 1.5
	p.scale_amount_min = size * 0.06
	p.scale_amount_max = size * 0.14
	p.scale_amount_curve = _c_shrink
	p.color_ramp = _ramp(c)
	p.emitting = true
	var s := _sparks(pos, Vector3.UP, c, maxi(amount / 4, 3), speed * 1.5, life * 0.6, 0.05, 0.0, 8.0, 8.0)
	s.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	s.emission_ring_axis = Vector3.UP
	s.emission_ring_radius = radius
	s.emission_ring_inner_radius = radius * 0.2
	s.emission_ring_height = 0.2


## 一根从天上打下来的光柱：先细后粗，再收成一条线消失。里面一根白芯，脚下一闪。
## 镜头在光柱里面的话（自己身上的魂环突破、魂技）：光柱从头顶上方开始，不然整个屏幕都是白的
func _pillar(pos: Vector3, color: Color, radius: float, height: float, dur: float) -> void:
	var c := Color(color.r, color.g, color.b, 1.0)
	var base := pos
	if _cam and is_instance_valid(_cam):
		var cp := _cam.global_position
		if Vector2(cp.x - pos.x, cp.z - pos.z).length() < radius + 1.0:
			var lift := maxf(cp.y - pos.y + 3.0, 0.0)
			pos.y += lift
			height = maxf(height - lift, 10.0)
			radius = minf(radius, 1.2)
	var n := Node3D.new()
	add_child(n)
	n.global_position = pos
	var meshes: Array = []
	for layer in [[radius, c, 1.5, 0.9], [radius * 0.28, c.lerp(Color.WHITE, 0.6), 2.2, 1.6]]:
		var cm := CylinderMesh.new()
		cm.top_radius = layer[0]
		cm.bottom_radius = layer[0]
		cm.height = height
		cm.cap_top = false
		cm.cap_bottom = false
		cm.radial_segments = 28
		var m := FxLib.smat("pillar", {"color": layer[1], "hdr": layer[2], "half_h": height * 0.5, "speed": layer[3], "top": 0.5})
		meshes.append(U.part(n, cm, m, Vector3(0, height * 0.5, 0), Vector3.ZERO, Vector3(0.05, 1, 0.05), false))
	_flash(base + Vector3.UP * 0.5, c.lerp(Color.WHITE, 0.4), radius * 2.5, 0.3, "glow", 1.5)
	var light := OmniLight3D.new()
	light.light_color = c
	light.light_energy = 0.0
	light.omni_range = radius * 6.0 + 6.0
	light.position = Vector3(0, 2, 0)
	n.add_child(light)
	# 先一起变粗，停 dur 秒，再一起收成一条线
	var tw := n.create_tween().set_parallel(true)
	for mi in meshes:
		tw.tween_property(mi, "scale", Vector3.ONE, 0.12).set_ease(Tween.EASE_OUT)
	tw.tween_property(light, "light_energy", 3.0, 0.1)
	tw.chain().tween_interval(dur)
	tw.chain().tween_property(light, "light_energy", 0.0, 0.35)
	for mi in meshes:
		tw.tween_property(mi, "scale", Vector3(0.01, 1, 0.01), 0.35).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(n.queue_free)


## 一圈光环从 from 高度升到 to 高度，同时变大变淡
func _ring_rise(pos: Vector3, color: Color, r: float, from: float, to: float, dur: float, delay := 0.0) -> void:
	_air_ring(pos + Vector3(0, from, 0), Color(color.r, color.g, color.b, 1.0), r * 0.6, r * 1.4, dur, to - from, "halo", 3.0, delay)


## 升级（小爽）：脚下金色法阵一闪、金色光点螺旋上升、两圈光环往上升
func level_up_burst(pos: Vector3, rings: int) -> void:
	var gold := Color(1.0, 0.82, 0.35)
	_ground(Vector3(pos.x, _ground_y(pos), pos.z), "magic", gold, 4.5, 0.6, 0.6, 2.2, 1.5, 0.4)
	_rise(pos, gold, 40 + rings * 8, 1.2, 5.0 + rings * 0.4, 1.4, 1.4)
	_ring_rise(pos, gold, 1.3, 0.1, 2.6, 0.9)
	_ring_rise(pos, Color(1.0, 0.95, 0.8), 0.9, 0.1, 3.2, 1.1, 0.15)
	_ground_ring(Vector3(pos.x, _ground_y(pos), pos.z), gold, 5.0 + rings * 0.4, 0.6, 3.0)


## 魂环突破（大爽）：天上打下光柱，脚下大法阵，身上所有魂环一个接一个升起来，最后一圈冲击波把附近照亮
func ring_breakthrough(pos: Vector3, color: Color, rings: int) -> void:
	var c := _ring_glow(color)
	var g := Vector3(pos.x, _ground_y(pos), pos.z)
	_pillar(pos, c, 1.8, 60.0, 1.6)
	_ground(g, "magic", c, 9.0, 2.0, 1.0, 2.4, 0.9, 0.5)
	_rise(pos, c, 160, 3.0, 9.0, 2.2, 2.2)
	_rise(pos, Color(1, 1, 1), 60, 1.0, 12.0, 1.6, 1.2)
	for i in rings:
		var rc: Color = Data.AGES[int(Profile.rings[i]["age"])]["glow"] if i < Profile.rings.size() else c
		_ring_rise(pos, rc, 1.1 + i * 0.12, 0.2, 1.0 + i * 0.35, 1.8, 0.12 * i)
	get_tree().create_timer(0.6).timeout.connect(func():
		shockwave(pos, 14.0, c)
		_sparks(pos + Vector3.UP, Vector3.UP, c, 70, 16.0, 1.2, 0.12, -3.0, 180.0, 6.0)
		_glows(pos + Vector3.UP, Vector3.UP, c, 40, 6.0, 1.6, 0.35, 0.5, 180.0)
		_shake(pos, 0.4, 20.0))


## 高阶魂技的额外层次：tier 0~1 普通，2~3 加法阵和光点，4 加光柱，5（万年）黑红魂火，6（神技）金色神光
func skill_flourish(center: Vector3, color: Color, tier: int, radius: float) -> void:
	if tier >= 2:
		sigil(center, maxf(radius, 3.0), color)
		_rise(center, color, 30 + tier * 15, maxf(radius * 0.6, 1.5), 4.0 + tier, 1.2, 1.6)
	if tier >= 4:
		_pillar(center, color, maxf(radius * 0.25, 1.0), 40.0, 0.5)
		_distort(center + Vector3.UP, maxf(radius, 4.0), 0.5, 0.03)
	if tier == 5:
		var dark := Color(0.6, 0.03, 0.06)
		_rise(center, dark, 90, maxf(radius, 3.0), 7.0, 1.6, 2.6)
		_smoke(center + Vector3.UP * 0.5, Color(0.06, 0.0, 0.02, 0.85), 16, 3.0, 2.0, 2.4, 1.2, 180.0, Vector3.UP, 1.0)
		shockwave(center, maxf(radius, 4.0) * 1.3, dark)
	if tier >= 6:
		var holy := Color(1.0, 0.86, 0.45)
		for k in 6:
			var a := TAU * k / 6.0
			var p := center + Vector3(cos(a), 0, sin(a)) * maxf(radius, 4.0) * 0.8
			get_tree().create_timer(0.07 * k).timeout.connect(func(): _pillar(p, holy, 0.6, 50.0, 0.4))
		_ring_rise(center, holy, maxf(radius, 4.0), 12.0, 16.0, 1.6)
		_rise(center, holy, 110, maxf(radius, 4.0), 12.0, 2.0, 2.0)
		get_tree().create_timer(0.45).timeout.connect(func(): shockwave(center, maxf(radius, 5.0) * 1.6, holy))


# ------------------------------------------------------------------ 新魂技的特效：召唤魂灵、环绕、连锁、黑洞、领域、陨石、神技法相

## 魂灵的材质：轮廓亮、里面流光的半透明光体
func _spirit_mat(color: Color, energy := 2.2) -> Material:
	return FxLib.smat("spirit", {"color": color, "hdr": energy * 0.9})


## 魂灵的身体：按 kind 用几何体拼一个发光的形象。返回的节点自带光、粒子
func spirit_body(kind: String, color: Color) -> Node3D:
	var n := Node3D.new()
	var m := _spirit_mat(color)
	var core := _spirit_mat(color.lightened(0.4), 4.0)
	match kind:
		"tiger", "cat":
			# 借一只狼的动画模型，染成半透明的魂灵
			var body := BeastModels.instance_model({"model": "wolf", "fit": "l", "size": 3.4 if kind == "tiger" else 1.8})
			for gi: GeometryInstance3D in body.find_children("*", "GeometryInstance3D", true, false):
				gi.material_override = m
				gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			BeastModels.play_role(body, "run")
			body.name = "Body"
			n.add_child(body)
		"phoenix":
			U.part(n, U.sphere(0.6, 16, 10), core, Vector3.ZERO, Vector3.ZERO, Vector3(1, 0.8, 1.6), false)
			for s in [-1.0, 1.0]:
				var w := Node3D.new()
				w.name = "WingL" if s < 0 else "WingR"
				n.add_child(w)
				U.part(w, U.box(Vector3(2.8, 0.05, 1.2)), m, Vector3(1.5 * s, 0, 0.2), Vector3.ZERO, Vector3.ONE, false)
				U.part(w, U.box(Vector3(1.6, 0.05, 0.8)), m, Vector3(3.2 * s, 0, 0.6), Vector3(0, 0.3 * s, 0), Vector3.ONE, false)
				# 翅膀上带火
				var fp := CPUParticles3D.new()
				fp.amount = 24
				fp.lifetime = 0.5
				fp.mesh = _quad
				fp.local_coords = false
				fp.material_override = FxLib.pmat("glow", true, 1.7, 1, 0.0)
				fp.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
				fp.emission_box_extents = Vector3(2.0, 0.05, 0.5)
				fp.position = Vector3(2.0 * s, 0, 0.3)
				fp.gravity = Vector3(0, 2.0, 0)
				fp.scale_amount_min = 0.2
				fp.scale_amount_max = 0.4
				fp.scale_amount_curve = _c_shrink
				fp.color_ramp = _ramp(Color(color.r, color.g, color.b, 1.0))
				w.add_child(fp)
			U.part(n, U.cyl(0.0, 0.5, 2.4, 10), m, Vector3(0, 0, 1.6), Vector3(PI / 2, 0, 0), Vector3.ONE, false)
		"angel":
			U.part(n, U.capsule(0.35, 1.8), core, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
			U.part(n, U.sphere(0.28, 12, 8), core, Vector3(0, 1.2, 0), Vector3.ZERO, Vector3.ONE, false)
			var halo := MeshInstance3D.new()
			halo.mesh = _plane
			halo.material_override = FxLib.quad_mat("halo", Color(1, 0.9, 0.5), 3.0, true)
			halo.scale = Vector3(1.0, 1, 1.0)
			halo.position = Vector3(0, 1.62, 0)
			halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			n.add_child(halo)
			for k in 3:
				for s in [-1.0, 1.0]:
					var w2 := U.part(n, U.box(Vector3(1.9 - k * 0.3, 0.04, 0.5)), m, Vector3(1.0 * s, 0.7 - k * 0.45, 0.2), Vector3(0, 0, s * (0.5 - k * 0.35)), Vector3.ONE, false)
					w2.name = "Wing"
		"tower":
			for k in 7:
				var r := 0.9 - k * 0.1
				U.part(n, U.cyl(r * 0.8, r, 0.45, 10), m, Vector3(0, k * 0.52, 0), Vector3.ZERO, Vector3.ONE, false)
				var tr := MeshInstance3D.new()
				tr.mesh = _plane
				tr.material_override = FxLib.quad_mat("halo", color.lightened(0.3), 2.5, true)
				tr.scale = Vector3(r * 2.6, 1, r * 2.6)
				tr.position = Vector3(0, k * 0.52 + 0.24, 0)
				tr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				n.add_child(tr)
			U.part(n, U.sphere(0.35, 12, 8), core, Vector3(0, 3.9, 0), Vector3.ZERO, Vector3.ONE, false)
		"hammer":
			var h := Node3D.new()
			h.name = "Head"
			n.add_child(h)
			U.part(h, U.cyl(0.14, 0.14, 2.6, 10), m, Vector3(0, -0.4, 0), Vector3.ZERO, Vector3.ONE, false)
			U.part(h, U.box(Vector3(1.6, 0.9, 0.9)), m, Vector3(0, 1.0, 0), Vector3.ZERO, Vector3.ONE, false)
			U.part(h, U.box(Vector3(1.7, 0.2, 1.0)), core, Vector3(0, 1.0, 0), Vector3.ZERO, Vector3.ONE, false)
		"scythe":
			var sc := Node3D.new()
			sc.name = "Head"
			n.add_child(sc)
			U.part(sc, U.cyl(0.08, 0.08, 3.0, 8), m, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
			# 刀刃：一片月牙光
			var blade := MeshInstance3D.new()
			blade.mesh = _quad
			blade.material_override = FxLib.quad_mat("slash", color.lightened(0.3), 3.5, true)
			blade.scale = Vector3(2.6, 2.6, 1)
			blade.position = Vector3(-0.6, 1.2, 0)
			blade.rotation = Vector3(0, 0, PI)
			blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			sc.add_child(blade)
		"vine":
			for k in 9:
				var a := k * 0.8
				U.part(n, U.cyl(0.12 - k * 0.01, 0.18 - k * 0.01, 0.9, 8), m, Vector3(cos(a) * 0.25, k * 0.55, sin(a) * 0.25), Vector3(sin(a) * 0.3, 0, cos(a) * 0.3), Vector3.ONE, false)
				U.part(n, U.box(Vector3(0.6, 0.03, 0.2)), core, Vector3(cos(a) * 0.5, k * 0.55 + 0.2, sin(a) * 0.5), Vector3(0, -a, 0.4), Vector3.ONE, false)
		"sausage":
			U.part(n, U.capsule(0.55, 2.6), m, Vector3(0, 1.3, 0), Vector3.ZERO, Vector3.ONE, false)
			var sr := MeshInstance3D.new()
			sr.mesh = _plane
			sr.material_override = FxLib.quad_mat("halo", color.lightened(0.3), 2.5, true)
			sr.scale = Vector3(1.9, 1, 1.9)
			sr.position = Vector3(0, 1.3, 0)
			sr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			n.add_child(sr)
		_:
			U.part(n, U.sphere(0.7, 16, 10), core)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 2.0
	light.omni_range = 7.0
	light.position = Vector3(0, 1, 0)
	n.add_child(light)
	var p := CPUParticles3D.new()
	p.amount = 36
	p.lifetime = 1.4
	p.mesh = _quad
	p.local_coords = false
	p.material_override = FxLib.pmat("glow", true, 1.7, 1, 0.0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.2
	p.direction = Vector3.UP
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0, 1.0, 0)
	p.scale_amount_min = 0.1
	p.scale_amount_max = 0.22
	p.scale_amount_curve = _c_shrink
	p.color_ramp = _ramp(Color(color.r, color.g, color.b, 0.9))
	p.position = Vector3(0, 0.8, 0)
	n.add_child(p)
	return n


## 召唤出来的魂灵：出现时脚下法阵 + 一道光升起来，dur 秒后散掉。follow 不为空就跟着那个节点飘
func summon_visual(kind: String, color: Color, dur: float, pos: Vector3, follow: Node3D = null) -> Node3D:
	var n := spirit_body(kind, color)
	add_child(n)
	n.global_position = pos
	n.set_meta("kind", kind)
	n.set_meta("follow", follow)
	n.set_meta("t", 0.0)
	n.set_meta("dur", dur)
	n.set_meta("side", 1.0 if randf() < 0.5 else -1.0)
	n.scale = Vector3.ONE * 0.05
	var tw := create_tween()
	tw.tween_property(n, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	sigil(pos, 2.5, color)
	_pillar(pos, color, 0.7, 20.0, 0.25)
	_rise(pos, color, 50, 1.5, 6.0, 1.0, 1.6)
	_summons.append(n)
	return n


var _summons: Array = []


func _update_summon_visuals(dt: float) -> void:
	for n in _summons.duplicate():
		if not is_instance_valid(n):
			_summons.erase(n)
			continue
		var t := float(n.get_meta("t")) + dt
		n.set_meta("t", t)
		var kind := str(n.get_meta("kind"))
		var follow: Variant = n.get_meta("follow") if n.has_meta("follow") else null    # 设成 null 的 meta 会被删掉
		if follow != null and is_instance_valid(follow):
			var fp: Vector3 = (follow as Node3D).global_position
			var side := float(n.get_meta("side"))
			var goal: Vector3 = fp + Vector3(2.2 * side + sin(t * 1.3) * 0.5, 0.2, 1.4)
			if kind in ["phoenix", "angel"]:
				goal = fp + Vector3(cos(t * 0.9) * 3.0, 4.0 + sin(t * 1.7) * 0.4, sin(t * 0.9) * 3.0)
			elif kind in ["hammer", "scythe"]:
				goal = fp + Vector3(2.0 * side, 2.2 + sin(t * 2.0) * 0.3, 0.8)
			if n.has_meta("lunge") and float(n.get_meta("lunge")) > 0.0:
				var l := float(n.get_meta("lunge")) - dt
				n.set_meta("lunge", l)
				goal = goal.lerp(n.get_meta("lunge_to") as Vector3, sin(clampf(l / 0.4, 0.0, 1.0) * PI))
			var vel: Vector3 = goal - n.global_position
			n.global_position = n.global_position.lerp(goal, 1.0 - exp(-6.0 * dt))
			if Vector3(vel.x, 0, vel.z).length() > 0.05:
				n.look_at(n.global_position - Vector3(vel.x, 0, vel.z), Vector3.UP)
		match kind:
			"phoenix":
				for w in ["WingL", "WingR"]:
					var wn := n.get_node_or_null(w) as Node3D
					if wn:
						wn.rotation.z = sin(t * 9.0) * 0.5 * (1.0 if w == "WingL" else -1.0)
			"tower", "vine", "sausage":
				n.rotation.y += dt * 0.6
			"hammer", "scythe":
				var hd := n.get_node_or_null("Head") as Node3D
				if hd:
					hd.rotation.z = sin(t * 1.5) * 0.2
		if t > float(n.get_meta("dur")):
			_summons.erase(n)
			poof(n.global_position + Vector3.UP)
			_rise(n.global_position, Color(1, 1, 1), 30, 1.0, 4.0, 0.8, 1.2)
			n.queue_free()


## 魂灵出手：扑过去（爪痕）/ 吐火球 / 射光 / 抽打 / 砸下去
func summon_attack(kind: String, from: Vector3, to: Vector3, color: Color, _caster_node: Node3D = null) -> void:
	for n in _summons:
		if is_instance_valid(n) and str(n.get_meta("kind")) == kind and n.global_position.distance_to(from) < 6.0:
			n.set_meta("lunge", 0.4)
			n.set_meta("lunge_to", to + Vector3(0, 0.5, 0))
	match kind:
		"phoenix":
			tracer(from, to, color, 0.35, 70.0, 6.0)
			get_tree().create_timer(0.15).timeout.connect(func(): explosion(to, 3.0, color))
		"angel", "tower":
			beam(from, to - from, from.distance_to(to), color, 0.18)
			_sparks(to, Vector3.UP, color, 20, 7.0, 0.5, 0.07, -3.0, 180.0)
			_flash(to, color, 2.0, 0.15)
		"hammer":
			get_tree().create_timer(0.2).timeout.connect(func():
				explosion(to, 5.0, color)
				slam(to, 5.0))
		"vine":
			vines(to, 1.2, color, 4)
			trail(from, to, color)
		_:
			trail(from, to, color)
			_claw(to + Vector3.UP * 0.8, from, color)
			impact_beast(to + Vector3.UP * 0.5, Vector3.UP, color, true)


## 爪痕：三道月牙光斩过去
func _claw(at: Vector3, from: Vector3, color: Color) -> void:
	var dir := at - from
	dir.y = 0.0
	if dir.length() < 0.1:
		dir = Vector3.FORWARD
	var root := Node3D.new()
	add_child(root)
	root.global_position = at
	root.look_at(at + dir.normalized(), Vector3.UP)
	root.rotate_object_local(Vector3.FORWARD, randf_range(-0.6, 0.6))
	for k in 3:
		var q := MeshInstance3D.new()
		q.mesh = _quad
		q.material_override = FxLib.quad_mat("slash", color.lightened(0.3), 4.0, true)
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		q.scale = Vector3(2.2, 2.2, 1)
		q.position = Vector3((k - 1) * 0.35, 0, 0)
		root.add_child(q)
	var tw := root.create_tween()
	tw.tween_property(root, "scale", Vector3(1.3, 1.3, 1.3), 0.2).from(Vector3(0.5, 0.5, 0.5)).set_ease(Tween.EASE_OUT)
	for q in root.get_children():
		tw.parallel().tween_property(q, "transparency", 1.0, 0.25).set_ease(Tween.EASE_IN)
	tw.tween_callback(root.queue_free)


## 环绕：n 个刀刃 / 宝珠 / 火团绕着 target 转 dur 秒，每个都拖着光尾
func orbit_visual(target: Node3D, kind: String, n: int, radius: float, dur: float, color: Color) -> void:
	var root := Node3D.new()
	add_child(root)
	var m := _spirit_mat(color, 3.0)
	var core := _spirit_mat(color.lightened(0.3), 4.5)
	for k in n:
		var a := TAU * k / n
		var piece := Node3D.new()
		root.add_child(piece)
		piece.position = Vector3(cos(a) * radius, 1.0, sin(a) * radius)
		piece.rotation.y = -a
		match kind:
			"scythe", "claw", "feather":
				var q := MeshInstance3D.new()
				q.mesh = _quad
				q.material_override = FxLib.quad_mat("slash", color.lightened(0.2), 3.5, true)
				q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				q.scale = Vector3(1.4, 1.4, 1)
				q.rotation = Vector3(-PI / 2, 0, 0)
				piece.add_child(q)
			"hammer":
				U.part(piece, U.box(Vector3(0.7, 0.45, 0.45)), m)
				U.part(piece, U.cyl(0.06, 0.06, 1.0, 6), core, Vector3(0, -0.6, 0))
			"sausage":
				U.part(piece, U.capsule(0.22, 1.0), m, Vector3.ZERO, Vector3(0, 0, PI / 2), Vector3.ONE, false)
			"thorn":
				U.part(piece, U.cyl(0.0, 0.16, 1.4, 8), core, Vector3.ZERO, Vector3(PI / 2, 0, 0), Vector3.ONE, false)
			_:
				U.part(piece, U.sphere(0.3, 12, 8), core)
				var hq := MeshInstance3D.new()
				hq.mesh = _quad
				hq.material_override = FxLib.bill_mat("glow", color, 2.5)
				hq.scale = Vector3.ONE * 1.4
				hq.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				piece.add_child(hq)
		var tp := _trail_particles(color, true, 0.25, 0.35)
		tp.amount = 20
		piece.add_child(tp)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.5
	light.omni_range = radius * 2.5
	light.position = Vector3(0, 1, 0)
	root.add_child(light)
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	ring.mesh = _plane
	ring.material_override = FxLib.quad_mat("halo", color, 1.4, true)
	ring.scale = Vector3(radius * 2.5, 1, radius * 2.5)
	ring.position = Vector3(0, 0.15, 0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	root.set_meta("target", target)
	root.set_meta("t", 0.0)
	root.set_meta("dur", dur)
	_orbits.append(root)


var _orbits: Array = []


func _update_orbit_visuals(dt: float) -> void:
	for r in _orbits.duplicate():
		if not is_instance_valid(r):
			_orbits.erase(r)
			continue
		var t := float(r.get_meta("t")) + dt
		r.set_meta("t", t)
		var target: Variant = r.get_meta("target") if r.has_meta("target") else null
		if target == null or not is_instance_valid(target) or t > float(r.get_meta("dur")):
			_orbits.erase(r)
			poof(r.global_position + Vector3.UP)
			r.queue_free()
			continue
		r.global_position = (target as Node3D).global_position
		r.rotation.y += dt * 4.5
		for c in r.get_children():
			if c is Node3D and c.name != "Ring" and not c is Light3D:
				(c as Node3D).rotation.x += dt * 8.0


## 连锁闪电：每段是一串折线（朝镜头的光带），主干亮、旁边两三根细分叉，闪两下；命中点星芒 + 火花
func chain_fx(points: Array, color: Color) -> void:
	var c := Color(color.r, color.g, color.b, 1.0)
	var m := FxLib.smat("beam", {"color": c, "width": 0.35, "hdr": 4.5, "len_m": 1.2})
	var thin := FxLib.smat("beam", {"color": c, "width": 0.14, "hdr": 3.5, "len_m": 1.0})
	var root := Node3D.new()
	add_child(root)
	for i in range(points.size() - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var pts := _bolt_points(a, b, 0.55)
		_bolt_mesh(root, pts, m)
		# 分叉
		for k in 2:
			var j := randi_range(1, maxi(pts.size() - 2, 1))
			var s: Vector3 = pts[j]
			var e := s + Vector3(randf_range(-1.5, 1.5), randf_range(-1.2, 0.8), randf_range(-1.5, 1.5))
			_bolt_mesh(root, _bolt_points(s, e, 0.3), thin)
		_flash(b, c.lerp(Color.WHITE, 0.4), 1.6, 0.15)
		_sparks(b, Vector3.UP, c, 16, 7.0, 0.35, 0.06, -4.0, 180.0)
	# 闪两下：暗一下再亮回来，然后淡掉
	var tw := root.create_tween()
	tw.tween_interval(0.07)
	tw.tween_method(_fade_mats.bind([m, thin]), 1.0, 0.3, 0.04)
	tw.tween_method(_fade_mats.bind([m, thin]), 0.3, 1.0, 0.03)
	tw.tween_method(_fade_mats.bind([m, thin]), 1.0, 0.0, 0.35)
	tw.tween_callback(root.queue_free)
	if points.size() > 0:
		_light(points[0], c, 6.0, 18.0, 0.4)


func _fade_mats(v: float, mats: Array) -> void:
	for mm in mats:
		(mm as ShaderMaterial).set_shader_parameter("fade", v)


func _bolt_points(a: Vector3, b: Vector3, jitter: float) -> Array:
	var segs := maxi(int(a.distance_to(b) / 0.9), 2)
	var out: Array = [a]
	for k in range(1, segs):
		out.append(a.lerp(b, float(k) / segs) + Vector3(randf_range(-jitter, jitter), randf_range(-jitter, jitter), randf_range(-jitter, jitter)))
	out.append(b)
	return out


func _bolt_mesh(root: Node3D, pts: Array, m: Material) -> void:
	for k in range(pts.size() - 1):
		var p0: Vector3 = pts[k]
		var p1: Vector3 = pts[k + 1]
		var d := p1 - p0
		var l := d.length()
		if l < 0.01:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = _plane
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 2.0
		root.add_child(mi)
		var dir := d / l
		var basis := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
		# 每段稍微长一点，接缝处不断开
		mi.global_transform = Transform3D(basis * Basis.from_scale(Vector3(1, 1, l * 1.08)), p0 + d * 0.5)


## 黑洞：一颗黑球（轮廓一圈亮光）、两层吸积盘转着、周围的画面被扭曲，光点往里卷，dur 秒后炸开
func blackhole_fx(center: Vector3, radius: float, dur: float, color: Color) -> void:
	var c := Color(color.r, color.g, color.b, 1.0)
	var n := Node3D.new()
	add_child(n)
	n.global_position = center + Vector3(0, 2.0, 0)
	var dark := StandardMaterial3D.new()
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dark.albedo_color = Color(0.01, 0.0, 0.02)
	var ball := U.part(n, U.sphere(1.0, 32, 16), dark, Vector3.ZERO, Vector3.ZERO, Vector3.ONE * 0.1, false)
	var rim := U.part(n, U.sphere(1.18, 32, 16), FxLib.smat("spirit", {"color": c, "hdr": 3.5}), Vector3.ZERO, Vector3.ZERO, Vector3.ONE * 0.1, false)
	for k in 2:
		var disk := MeshInstance3D.new()
		disk.mesh = _plane
		disk.material_override = FxLib.quad_mat("swirl", c if k == 0 else c.lerp(Color.WHITE, 0.3), 1.8 - k * 0.5, true)
		disk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		disk.scale = Vector3.ONE * 0.1
		disk.rotation = Vector3(0.35 if k == 0 else -0.5, 0, 0.2 if k == 0 else -0.3)
		n.add_child(disk)
		var ts := disk.create_tween().set_loops()
		ts.tween_property(disk, "rotation:y", -TAU, 0.9 + k * 0.6).as_relative()
		disk.create_tween().tween_property(disk, "scale", Vector3.ONE * (6.5 + k * 2.5), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var tw := ball.create_tween()
	tw.tween_property(ball, "scale", Vector3.ONE * 1.6, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	rim.create_tween().tween_property(rim, "scale", Vector3.ONE * 1.6, 0.4)
	# 周围的画面被吸进去（扭曲）
	if false:
		var lens := MeshInstance3D.new()
		lens.mesh = _ball
		lens.material_override = FxLib.smat("distort", {"strength": -0.08, "fade": 1.0})
		lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lens.scale = Vector3.ONE * 4.5
		n.add_child(lens)
	vortex(center, radius, color)
	var p := CPUParticles3D.new()
	p.amount = 120
	p.lifetime = 1.0
	p.mesh = _quad
	p.material_override = FxLib.pmat("glow", true, 1.7, 1, 0.0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * 0.8
	p.radial_accel_min = -30.0
	p.radial_accel_max = -20.0
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.12
	p.scale_amount_max = 0.25
	p.color_ramp = _ramp(c, true)
	n.add_child(p)
	get_tree().create_timer(dur).timeout.connect(func():
		if is_instance_valid(n):
			n.queue_free()
		explosion(center + Vector3.UP, radius, color)
		_pillar(center, color, radius * 0.25, 40.0, 0.3)
		_smoke(center + Vector3.UP, Color(0.08, 0.0, 0.12, 0.8), 14, radius, 2.0, radius * 0.6, 1.0, 180.0, Vector3.UP, 1.0))


## 领域：地上一个大法阵（外圈、里圈反着转）、一圈往上流动的光壁、光点从地上飘起来，持续 dur 秒
func domain_fx(center: Vector3, radius: float, dur: float, color: Color) -> void:
	var c := Color(color.r, color.g, color.b, 1.0)
	var gy := _ground_y(center)
	var g := Vector3(center.x, gy, center.z)
	var outer := _ground(g, "magic", c, radius * 2.15, -1.0, 0.0, 1.6, 0.35, 0.5)
	var inner := _ground(g, "magic", c.lerp(Color.WHITE, 0.25), radius * 1.1, -1.0, 0.0, 2.0, -0.7, 0.4)
	var n := Node3D.new()
	add_child(n)
	n.global_position = g + Vector3(0, 0.05, 0)
	var wall := MeshInstance3D.new()
	var wc := CylinderMesh.new()
	wc.top_radius = radius
	wc.bottom_radius = radius
	wc.height = 4.0
	wc.radial_segments = 72
	wc.cap_top = false
	wc.cap_bottom = false
	wall.mesh = wc
	var wm := FxLib.smat("pillar", {"color": c, "hdr": 0.9, "half_h": 2.0, "speed": 0.6, "top": 0.0, "rim_k": 0.5})
	wall.material_override = wm
	wall.position = Vector3(0, 2.0, 0)
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(wall)
	var p := CPUParticles3D.new()
	p.amount = int(clampf(radius * 8.0, 40, 180))
	p.lifetime = 2.0
	p.mesh = _quad
	p.material_override = FxLib.pmat("glow", true, 1.7, 1, 0.0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = radius
	p.emission_ring_inner_radius = 0.0
	p.emission_ring_height = 0.1
	p.direction = Vector3.UP
	p.spread = 5.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.0
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.1
	p.scale_amount_max = 0.2
	p.scale_amount_curve = _c_shrink
	p.color_ramp = _ramp(c, true)
	n.add_child(p)
	var light := OmniLight3D.new()
	light.light_color = c
	light.light_energy = 1.5
	light.omni_range = radius * 1.5
	light.position = Vector3(0, 2, 0)
	n.add_child(light)
	wall.scale = Vector3(0.05, 1, 0.05)
	var tw := wall.create_tween()
	tw.tween_property(wall, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for gnode in [outer, inner]:
		_ground_grow(gnode, 0.4)
	get_tree().create_timer(dur).timeout.connect(func():
		for gnode in [outer, inner]:
			if is_instance_valid(gnode):
				var tg: Tween = gnode.create_tween()
				if gnode is Decal:
					tg.tween_property(gnode, "modulate:a", 0.0, 0.5)
				else:
					tg.tween_property(gnode, "transparency", 1.0, 0.5)
				tg.tween_callback(gnode.queue_free)
		if not is_instance_valid(n):
			return
		p.emitting = false
		var te := n.create_tween()
		te.tween_method(func(v: float): wm.set_shader_parameter("fade", v), 1.0, 0.0, 0.5)
		te.parallel().tween_property(light, "light_energy", 0.0, 0.5)
		te.tween_callback(n.queue_free))
	shockwave(center, radius, color)


## 地面图从小长到原来的大小
func _ground_grow(n: Node3D, dur: float) -> void:
	if not is_instance_valid(n):
		return
	var full: float = (n as Decal).size.x if n is Decal else n.scale.x
	var tw := n.create_tween()
	tw.tween_method(func(s: float): _ground_size(n, s), full * 0.1, full, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 雨类魂技的每一波：一颗火流星拖着火尾和烟从天上砸下来
func meteor_strike(center: Vector3, radius: float, color: Color) -> void:
	var c := Color(color.r, color.g, color.b, 1.0)
	var from := center + Vector3(randf_range(-6, 6), 30.0, randf_range(-6, 6))
	var head := Node3D.new()
	add_child(head)
	head.global_position = from
	var ball := MeshInstance3D.new()
	ball.mesh = _ball
	ball.material_override = FxLib.smat("fire", {"color": c, "hdr": 2.6, "speed": 3.0})
	ball.scale = Vector3.ONE * (0.6 + radius * 0.06)
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.add_child(ball)
	var h := MeshInstance3D.new()
	h.mesh = _quad
	h.material_override = FxLib.bill_mat("flare", c.lerp(Color.WHITE, 0.3), 2.0)
	h.scale = Vector3.ONE * (2.0 + radius * 0.1)
	h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.add_child(h)
	var tail := _trail_particles(c, true, 1.2, 0.35)
	tail.amount = 50
	head.add_child(tail)
	var smoke := _trail_particles(Color(0.2, 0.18, 0.2, 0.5), false, 1.4, 0.8)
	head.add_child(smoke)
	var tw := create_tween()
	tw.tween_property(head, "global_position", center + Vector3.UP * 0.3, 0.22).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		# 拖尾留一会儿再删，不然烟一下子没了
		ball.queue_free()
		h.queue_free()
		tail.emitting = false
		smoke.emitting = false
		_free_after(head, 1.0)
		explosion(center + Vector3.UP * 0.5, radius * 0.6, color))


## 神技：天上显现巨大的武魂法相（武魂原画做成圆形光盘），四周光柱冲天
const SHEN_SHADER := """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform sampler2D art : source_color, filter_linear;
uniform vec4 color : source_color = vec4(1.0, 0.85, 0.5, 1.0);
uniform float fade = 1.0;
void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;
	float mask = smoothstep(1.0, 0.7, r);
	vec3 c = texture(art, UV).rgb * mask;
	float ring = smoothstep(0.03, 0.0, abs(r - 0.94)) + smoothstep(0.02, 0.0, abs(r - 0.82)) * 0.6;
	float rays = pow(max(0.0, sin(atan(p.y, p.x) * 12.0 + TIME * 0.8)), 8.0) * smoothstep(1.0, 0.85, r) * smoothstep(0.6, 0.9, r);
	ALBEDO = (c * 0.8 + color.rgb * (ring * 2.5 + rays * 0.9)) * fade;
}
"""


func shen_manifest(pos: Vector3, wuhun: int, color: Color) -> void:
	var img: Texture2D = load(str(Data.WUHUN[clampi(wuhun, 0, Data.WUHUN.size() - 1)]["img"]))
	var q := QuadMesh.new()
	q.size = Vector2(28, 28)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	var sm := ShaderMaterial.new()
	sm.shader = Shader.new()
	sm.shader.code = SHEN_SHADER
	sm.set_shader_parameter("art", img)
	sm.set_shader_parameter("color", color)
	sm.set_shader_parameter("fade", 0.0)
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# 法相出现在看得到的地方：自己放的就在正前方天上，别人放的在他头顶上
	var at := pos + Vector3(0, 20, 0)
	if _cam and is_instance_valid(_cam) and _cam.global_position.distance_to(pos) < 4.0:
		var fwd := -_cam.global_basis.z
		fwd.y = 0.0
		at = pos + fwd.normalized() * 55.0 + Vector3(0, 17, 0)
	mi.global_position = at
	if _cam and is_instance_valid(_cam):
		var to := _cam.global_position - mi.global_position
		if to.length() > 0.1:
			mi.look_at(mi.global_position - to, Vector3.UP)
	pos = Vector3(at.x, pos.y, at.z) if _cam and _cam.global_position.distance_to(pos) < 4.0 else pos
	var tw := create_tween()
	tw.tween_method(func(v: float): sm.set_shader_parameter("fade", v), 0.0, 1.0, 0.6)
	tw.parallel().tween_property(mi, "global_position:y", at.y - 4.0, 3.2).from(at.y + 6.0)
	tw.tween_interval(1.8)
	tw.tween_method(func(v: float): sm.set_shader_parameter("fade", v), 1.0, 0.0, 0.9)
	tw.tween_callback(mi.queue_free)
	for k in 8:
		var a := TAU * k / 8.0
		var pp := pos + Vector3(cos(a), 0, sin(a)) * 12.0
		get_tree().create_timer(0.05 * k).timeout.connect(func(): _pillar(pp, color, 0.8, 60.0, 1.2))
	_pillar(pos, Color(1, 0.95, 0.8), 2.0, 80.0, 1.6)
	_ground(Vector3(pos.x, _ground_y(pos), pos.z), "magic", color, 26.0, 3.0, 1.0, 2.0, 0.4, 0.4)
	_rise(pos, color, 120, 10.0, 12.0, 2.4, 2.2)
	_ring_rise(pos, color, 14.0, 0.2, 10.0, 2.0)


## 武魂附体 / 附魔时每一发命中的小特效
func empower_hit(kind: String, pos: Vector3, color: Color) -> void:
	match kind:
		"explode":
			explosion(pos, 3.5, color)
		"quake":
			shockwave(pos - Vector3.UP * 0.4, 4.5, color)
			_bits(pos, Vector3.UP, Color(0.5, 0.42, 0.33), 12, 6.0, 0.1)
			_smoke(pos, Color(0.62, 0.55, 0.45, 0.6), 6, 3.0, 1.0, 1.4, 0.2)
		"root":
			vines(pos - Vector3.UP * 0.4, 1.4, color)
		"bleed":
			_sparks(pos, Vector3.UP, Color(0.8, 0.02, 0.05), 20, 5.0, 0.6, 0.07, -12.0, 110.0, 3.0)
			_smoke(pos, Color(0.5, 0.0, 0.03, 0.6), 4, 1.0, 0.8, 0.6, -0.5)
		"burn":
			_glows(pos, Vector3.UP, Color(1.0, 0.55, 0.15), 14, 3.0, 0.8, 0.35, 3.0, 60.0)
			_sparks(pos, Vector3.UP, Color(1.0, 0.45, 0.1), 12, 5.0, 0.6, 0.06, 2.0, 70.0)
			_smoke(pos + Vector3.UP * 0.3, Color(0.15, 0.12, 0.1, 0.5), 4, 1.0, 1.2, 0.8, 1.2)
		_:
			_flash(pos, color, 1.2, 0.1)
			_sparks(pos, Vector3.UP, color, 14, 5.0, 0.5, 0.06, 0.0, 180.0)


## 护盾：六边形格子的光罩跟着人 dur 秒
func shield_bubble(target: Node3D, dur: float, color: Color) -> void:
	if target == null or not is_instance_valid(target):
		return
	var b := MeshInstance3D.new()
	b.mesh = U.sphere(1.4, 32, 16)
	var sm := FxLib.smat("shield", {"color": color, "hdr": 1.8})
	b.material_override = sm
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	target.add_child(b)
	b.position = Vector3(0, 1.0, 0)
	b.scale = Vector3.ONE * 0.2
	var tw := b.create_tween()
	tw.tween_property(b, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(maxf(dur - 0.5, 0.1))
	tw.tween_property(b, "scale", Vector3.ONE * 1.3, 0.25)
	tw.parallel().tween_method(func(v: float): sm.set_shader_parameter("fade", v), 1.0, 0.0, 0.25)
	tw.tween_callback(b.queue_free)
