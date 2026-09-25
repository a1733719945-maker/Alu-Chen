class_name Fx
extends Node3D
## 一次性特效：弹道、命中火花、伤害数字、落水、魂兽死亡时魂环碎裂。
## 全部自己销毁。

var _spark_mesh: QuadMesh
var _dust_mat: StandardMaterial3D
var _cam: Camera3D


func _ready() -> void:
	_spark_mesh = QuadMesh.new()
	_spark_mesh.size = Vector2(0.14, 0.14)
	_dust_mat = _particle_mat(false)


func set_camera(c: Camera3D) -> void:
	_cam = c


func _particle_mat(glow: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m


func _burst(pos: Vector3, normal: Vector3, color: Color, amount: int, speed: float, life: float, size: float, glow: bool, gravity := -9.0, spread := 60.0) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = life
	p.mesh = _spark_mesh
	p.material_override = _particle_mat(glow)
	p.direction = normal if normal != Vector3.ZERO else Vector3.UP
	p.spread = spread
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, gravity, 0)
	p.damping_min = 1.0
	p.damping_max = 3.0
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size
	var g := Gradient.new()
	g.set_color(0, color)
	g.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = g
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0.2))
	p.scale_amount_curve = curve
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.2).timeout.connect(p.queue_free)


# ------------------------------------------------------------------ 弹道

## 一道飞过去的"箭影"。hitscan 瞬间命中，但画面上让它飞一下更有感觉。
func tracer(from: Vector3, to: Vector3, color: Color, width := 0.018, speed := 420.0, length := 3.5) -> void:
	var dist := from.distance_to(to)
	if dist < 0.5:
		return
	var seg := minf(length, dist)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, width, seg)
	mi.mesh = bm
	mi.material_override = U.glow(color, 4.0, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var dir := (to - from) / dist
	var start := from + dir * seg * 0.5
	var end := to - dir * seg * 0.5
	mi.look_at_from_position(start, start + dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
	var t := maxf(dist / speed, 0.03)
	var tw := create_tween()
	tw.tween_property(mi, "global_position", end, t)
	tw.tween_property(mi, "scale", Vector3(0.1, 0.1, 0.3), 0.05)
	tw.tween_callback(mi.queue_free)


func muzzle_flash(pos: Vector3, dir: Vector3, color: Color, big := false) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = U.sphere(0.05 if not big else 0.09, 8, 4)
	mi.material_override = U.glow(color, 6.0, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3(1, 1, 2.5)
	mi.look_at(pos + dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 2.5 if big else 1.2
	light.omni_range = 4.0
	add_child(light)
	light.global_position = pos
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3(0.2, 0.2, 0.2), 0.06)
	tw.parallel().tween_property(light, "light_energy", 0.0, 0.07)
	tw.tween_callback(func(): mi.queue_free(); light.queue_free())


# ------------------------------------------------------------------ 命中

func impact_world(pos: Vector3, normal: Vector3) -> void:
	_burst(pos, normal, Color(0.6, 0.55, 0.45, 0.9), 7, 3.0, 0.45, 1.0, false)


func impact_beast(pos: Vector3, normal: Vector3, color: Color, headshot: bool) -> void:
	var c := color
	c.a = 1.0
	_burst(pos, normal, c, 14 if headshot else 8, 5.5 if headshot else 4.0, 0.5, 1.2 if headshot else 0.9, true, -3.0, 70.0)


func splash(pos: Vector3, big := false) -> void:
	_burst(Vector3(pos.x, Island.WATER_Y + 0.05, pos.z), Vector3.UP, Color(0.85, 0.95, 1.0, 0.9), 26 if big else 10, 6.0 if big else 3.5, 0.8, 1.8 if big else 1.0, false, -14.0, 25.0)
	var ring := MeshInstance3D.new()
	ring.mesh = U.torus(0.3, 0.38, 32, 4)
	ring.material_override = U.glow(Color(0.8, 0.95, 1.0), 1.2, true)
	add_child(ring)
	ring.global_position = Vector3(pos.x, Island.WATER_Y + 0.08, pos.z)
	var tw := create_tween()
	tw.tween_property(ring, "scale", Vector3.ONE * (6.0 if big else 3.5), 0.7)
	tw.tween_callback(ring.queue_free)


func dirt_puff(pos: Vector3) -> void:
	_burst(pos, Vector3.UP, Color(0.55, 0.42, 0.28, 0.85), 14, 3.0, 0.7, 2.0, false, -6.0, 50.0)


## 魂兽死亡：一团魂力光点炸开，魂环扩散消失
func death_burst(pos: Vector3, color: Color, age: int) -> void:
	_burst(pos, Vector3.UP, color, 40 + age * 25, 8.0, 1.0, 2.6, true, -2.0, 180.0)
	_burst(pos, Vector3.UP, Color(1, 1, 1, 1), 16, 4.0, 0.5, 1.6, true, 0.0, 180.0)
	var ring := MeshInstance3D.new()
	ring.mesh = U.torus(0.5, 0.58, 48, 6)
	ring.material_override = U.glow(color, 4.0, true)
	add_child(ring)
	ring.global_position = pos
	var tw := create_tween()
	tw.tween_property(ring, "scale", Vector3.ONE * (4.0 + age * 1.5), 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_property(ring, "position:y", ring.position.y + 0.6, 0.45)
	tw.tween_callback(ring.queue_free)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 4.0
	light.omni_range = 8.0
	add_child(light)
	light.global_position = pos
	var tl := create_tween()
	tl.tween_property(light, "light_energy", 0.0, 0.5)
	tl.tween_callback(light.queue_free)


## 伤害数字：从命中点往上飘
func damage_number(pos: Vector3, amount: float, headshot: bool, kill := false) -> void:
	var l := U.label3d(str(roundi(amount)), 64 if headshot or kill else 48, Color(1, 0.86, 0.3) if headshot else Color(1, 1, 1), 12)
	if kill:
		l.modulate = Color(1.0, 0.4, 0.3)
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0011
	add_child(l)
	var side := Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4))
	l.global_position = pos + Vector3(0, 0.2, 0) + side * 0.5
	var tw := create_tween()
	tw.tween_property(l, "global_position", l.global_position + Vector3(0, 1.1, 0) + side, 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tw.tween_callback(l.queue_free)


## 逃走时一团烟
func poof(pos: Vector3) -> void:
	_burst(pos, Vector3.UP, Color(0.9, 0.9, 0.9, 0.7), 12, 2.0, 0.6, 2.2, false, 1.0, 180.0)


# ------------------------------------------------------------------ 箭插在树上 / 地上 / 魂兽身上

var _arrows: Array[Node3D] = []


func stick_arrow(pos: Vector3, dir: Vector3, on: Node3D) -> void:
	var a := Node3D.new()
	var shaft := U.part(a, U.cyl(0.006, 0.006, 0.34, 4), U.mat(Color(0.35, 0.24, 0.14)), Vector3(0, 0, 0.14), Vector3(PI / 2, 0, 0), Vector3.ONE, false)
	shaft.name = "Shaft"
	U.part(a, U.box(Vector3(0.03, 0.001, 0.06)), U.mat(Color(0.9, 0.9, 0.85)), Vector3(0, 0, 0.29), Vector3.ZERO, Vector3.ONE, false)
	U.part(a, U.box(Vector3(0.001, 0.03, 0.06)), U.mat(Color(0.9, 0.9, 0.85)), Vector3(0, 0, 0.29), Vector3.ZERO, Vector3.ONE, false)
	if on and is_instance_valid(on):
		on.add_child(a)
	else:
		add_child(a)
	a.global_position = pos - dir * 0.05
	a.look_at(pos + dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
	# look_at 让 -Z 朝前：箭杆在 +Z 那边，正好露在外面
	_arrows.append(a)
	if _arrows.size() > 70:
		var old: Node3D = _arrows.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	# 箭可能插在魂兽身上，魂兽先没了箭也跟着没了：用弱引用，别抓着已经释放的节点
	var wr: WeakRef = weakref(a)
	get_tree().create_timer(12.0).timeout.connect(func():
		var n: Node = wr.get_ref()
		if n:
			n.queue_free())


# ------------------------------------------------------------------ 魂环

func soul_ring(pos: Vector3, color: Color) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = pos
	U.part(n, U.torus(0.9, 1.02, 48, 6), U.glow(color, 4.0), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
	U.part(n, U.torus(0.6, 0.66, 40, 4), U.glow(color, 2.0, true), Vector3(0, 0.25, 0), Vector3.ZERO, Vector3.ONE, false)
	var beam := U.part(n, U.cyl(0.05, 0.4, 14.0, 12), U.glow(color, 0.6, true), Vector3(0, 7.0, 0), Vector3.ZERO, Vector3.ONE, false)
	beam.name = "Beam"
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 2.0
	light.omni_range = 8.0
	n.add_child(light)
	return n


## 吸收魂环：光柱罩住玩家，魂环从头顶落下
func absorb(target: Node3D, color: Color) -> void:
	var n := Node3D.new()
	add_child(n)
	n.global_position = target.global_position
	var pillar := U.part(n, U.cyl(1.2, 1.2, 30.0, 24), U.glow(color, 0.8, true), Vector3(0, 15, 0), Vector3.ZERO, Vector3.ONE, false)
	var ring := U.part(n, U.torus(1.0, 1.14, 48, 6), U.glow(color, 5.0), Vector3(0, 8, 0), Vector3.ZERO, Vector3.ONE, false)
	var tw := create_tween()
	tw.tween_property(ring, "position:y", 1.0, 2.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(ring, "scale", Vector3.ONE * 0.8, 2.6)
	tw.tween_property(pillar, "scale", Vector3(0.01, 1, 0.01), 0.4)
	tw.tween_callback(n.queue_free)
	_burst(target.global_position + Vector3.UP, Vector3.UP, color, 60, 6.0, 1.2, 2.0, true, -1.0, 180.0)


# ------------------------------------------------------------------ Boss 和魂兽的攻击

func hazard_ball(kind: String, color: Color) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	var r := 0.35 if kind != "rock" else 0.45
	var mat: Material = U.glow(color, 2.5) if kind != "rock" else U.mat(color)
	U.part(n, U.sphere(r, 10, 6), mat)
	if kind == "spit":
		var p := CPUParticles3D.new()
		p.amount = 20
		p.lifetime = 0.5
		p.mesh = U.sphere(0.08, 4, 2)
		p.material_override = U.glow(color, 2.0, true)
		p.gravity = Vector3(0, -4, 0)
		p.initial_velocity_max = 0.5
		n.add_child(p)
	return n


## 红圈预警：从中间长到外圈，满了就砸下来
func telegraph(center: Vector3, radius: float, delay: float) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = center + Vector3(0, 0.12, 0)
	U.part(n, U.torus(radius - 0.12, radius, 64, 4), U.glow(Color(1.0, 0.2, 0.15), 3.0), Vector3.ZERO, Vector3.ZERO, Vector3(1, 0.2, 1), false)
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 0.02
	cm.radial_segments = 48
	disc.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.15, 0.1, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = false
	disc.material_override = m
	disc.scale = Vector3(0.05, 1, 0.05)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(disc)
	var tw := create_tween()
	tw.tween_property(disc, "scale", Vector3.ONE, delay)
	return n


func slam(center: Vector3, radius: float) -> void:
	_burst(center + Vector3.UP * 0.2, Vector3.UP, Color(0.6, 0.5, 0.4, 0.9), 40, 9.0, 0.9, 3.0, false, -12.0, 70.0)
	shockwave(center, radius, Color(1.0, 0.5, 0.3))
	if not Engine.is_editor_hint() and center.y <= Island.WATER_Y + 0.3:
		splash(center, true)


func poison_pool(pos: Vector3, radius: float) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = pos + Vector3(0, 0.08, 0)
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 0.04
	cm.radial_segments = 32
	var disc := MeshInstance3D.new()
	disc.mesh = cm
	disc.material_override = U.glow(Color(0.45, 0.9, 0.2), 1.2, true)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(disc)
	var p := CPUParticles3D.new()
	p.amount = 24
	p.lifetime = 1.4
	p.mesh = U.sphere(0.1, 5, 3)
	p.material_override = U.glow(Color(0.5, 1.0, 0.3), 1.5, true)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * 0.8
	p.direction = Vector3.UP
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.2
	p.gravity = Vector3(0, 0.5, 0)
	n.add_child(p)
	return n


func web_burst(pos: Vector3) -> void:
	_burst(pos + Vector3.UP * 0.5, Vector3.UP, Color(0.95, 0.95, 1.0, 0.9), 30, 5.0, 0.8, 1.5, false, -3.0, 180.0)


# ------------------------------------------------------------------ 佛怒唐莲

func lotus() -> Node3D:
	var n := Node3D.new()
	add_child(n)
	var petal := U.glow(Color(1.0, 0.55, 0.75), 2.5)
	var core := U.glow(Color(1.0, 0.9, 0.5), 4.0)
	for k in 8:
		var a := TAU * k / 8.0
		U.part(n, U.sphere(0.09, 6, 4), petal, Vector3(cos(a) * 0.1, 0.03, sin(a) * 0.1), Vector3.ZERO, Vector3(1.6, 0.4, 0.8), false).rotation.y = -a
	U.part(n, U.sphere(0.07, 8, 6), core, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.7)
	light.light_energy = 1.5
	light.omni_range = 4.0
	n.add_child(light)
	return n


func lotus_explosion(pos: Vector3) -> void:
	explosion(pos, 7.0, Color(1.0, 0.55, 0.7))
	_burst(pos, Vector3.UP, Color(1.0, 0.7, 0.85), 60, 12.0, 1.2, 2.2, true, -6.0, 180.0)


# ------------------------------------------------------------------ 魂技

func explosion(pos: Vector3, radius: float, color: Color) -> void:
	var ball := MeshInstance3D.new()
	ball.mesh = U.sphere(1.0, 20, 12)
	ball.material_override = U.glow(color, 5.0, true)
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ball)
	ball.global_position = pos
	ball.scale = Vector3.ONE * 0.3
	var tw := create_tween()
	tw.tween_property(ball, "scale", Vector3.ONE * radius * 0.8, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_property(ball, "transparency", 1.0, 0.35)
	tw.tween_callback(ball.queue_free)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 8.0
	light.omni_range = radius * 3.0
	add_child(light)
	light.global_position = pos + Vector3.UP
	var tl := create_tween()
	tl.tween_property(light, "light_energy", 0.0, 0.5)
	tl.tween_callback(light.queue_free)
	_burst(pos, Vector3.UP, Color(color.r, color.g, color.b, 1.0), 50, radius * 2.0, 0.8, 2.0, true, -4.0, 180.0)
	shockwave(pos, radius, color)


## 冲击波：地面一圈光扩散开，加尘土
func shockwave(center: Vector3, radius: float, color: Color) -> void:
	var ring := MeshInstance3D.new()
	ring.mesh = U.torus(0.85, 1.0, 64, 6)
	ring.material_override = U.glow(color, 4.0, true)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.global_position = center + Vector3(0, 0.3, 0)
	ring.scale = Vector3(0.2, 0.6, 0.2)
	var tw := create_tween()
	tw.tween_property(ring, "scale", Vector3(radius, 1.0, radius), 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_property(ring, "transparency", 1.0, 0.45)
	tw.tween_callback(ring.queue_free)
	for k in 10:
		var a := TAU * k / 10.0
		var spike := MeshInstance3D.new()
		spike.mesh = U.cyl(0.0, 0.25, 1.8, 5)
		spike.material_override = U.glow(color, 2.5)
		add_child(spike)
		var p := center + Vector3(cos(a), 0, sin(a)) * radius * 0.6
		spike.global_position = p + Vector3(0, -1.0, 0)
		var ts := create_tween()
		ts.tween_property(spike, "global_position:y", p.y + 0.6, 0.12)
		ts.tween_interval(0.25)
		ts.tween_property(spike, "global_position:y", p.y - 1.5, 0.3)
		ts.tween_callback(spike.queue_free)
	_burst(center + Vector3.UP * 0.3, Vector3.UP, Color(0.7, 0.62, 0.5, 0.8), 24, 5.0, 0.7, 2.5, false, -8.0, 80.0)


func vines(center: Vector3, radius: float, color: Color) -> void:
	for k in 14:
		var a := randf() * TAU
		var d := sqrt(randf()) * radius
		var v := MeshInstance3D.new()
		v.mesh = U.cyl(0.03, 0.09, 3.2, 5)
		v.material_override = U.glow(color, 1.8)
		add_child(v)
		var p := center + Vector3(cos(a) * d, 0, sin(a) * d)
		v.global_position = p + Vector3(0, -1.6, 0)
		v.rotation = Vector3(randf_range(-0.4, 0.4), randf() * TAU, randf_range(-0.4, 0.4))
		var tw := create_tween()
		tw.tween_property(v, "global_position:y", p.y + 1.2, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_interval(2.5)
		tw.tween_property(v, "global_position:y", p.y - 2.0, 0.5)
		tw.tween_callback(v.queue_free)
	sigil(center, radius, color)


func sigil(center: Vector3, radius: float, color: Color) -> void:
	var n := Node3D.new()
	add_child(n)
	n.global_position = center + Vector3(0, 0.15, 0)
	U.part(n, U.torus(radius - 0.1, radius, 64, 4), U.glow(color, 3.0, true), Vector3.ZERO, Vector3.ZERO, Vector3(1, 0.2, 1), false)
	U.part(n, U.torus(radius * 0.6 - 0.08, radius * 0.6, 48, 4), U.glow(color, 2.0, true), Vector3.ZERO, Vector3.ZERO, Vector3(1, 0.2, 1), false)
	for k in 6:
		var a := TAU * k / 6.0
		U.part(n, U.box(Vector3(radius * 0.8, 0.02, 0.06)), U.glow(color, 2.0, true), Vector3(cos(a), 0, sin(a)) * radius * 0.4, Vector3(0, -a, 0), Vector3.ONE, false)
	var tw := create_tween()
	tw.tween_property(n, "rotation:y", PI, 1.5)
	tw.parallel().tween_property(n, "scale", Vector3.ONE * 1.05, 1.5)
	tw.tween_callback(n.queue_free)


func vortex(center: Vector3, radius: float, color: Color) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 80
	p.lifetime = 2.0
	p.explosiveness = 0.2
	p.mesh = _spark_mesh
	p.material_override = _particle_mat(true)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = radius
	p.emission_ring_inner_radius = radius * 0.8
	p.emission_ring_height = 0.5
	p.radial_accel_min = -12.0
	p.radial_accel_max = -8.0
	p.tangential_accel_min = 10.0
	p.tangential_accel_max = 14.0
	p.gravity = Vector3(0, 2, 0)
	p.scale_amount_min = 1.5
	p.scale_amount_max = 2.5
	p.color = color
	add_child(p)
	p.global_position = center + Vector3.UP
	p.emitting = true
	get_tree().create_timer(2.5).timeout.connect(p.queue_free)
	sigil(center, radius, color)


func beam(origin: Vector3, dir: Vector3, length: float, color: Color, width := 0.35) -> void:
	dir = dir.normalized()
	var mi := MeshInstance3D.new()
	mi.mesh = U.cyl(width, width, length, 16)
	mi.material_override = U.glow(color, 5.0, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var mid := origin + dir * length * 0.5
	mi.global_position = mid
	mi.global_basis = Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT) * Basis(Vector3.RIGHT, PI / 2)
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3(0.05, 1.0, 0.05), 0.35).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)
	var core := MeshInstance3D.new()
	core.mesh = U.cyl(width * 0.35, width * 0.35, length, 8)
	core.material_override = U.glow(Color(1, 1, 1), 6.0, true)
	add_child(core)
	core.global_transform = mi.global_transform
	var tc := create_tween()
	tc.tween_interval(0.12)
	tc.tween_callback(core.queue_free)


func aura_burst(pos: Vector3, color: Color, radius: float) -> void:
	var ring := MeshInstance3D.new()
	ring.mesh = U.torus(0.9, 1.0, 48, 4)
	ring.material_override = U.glow(color, 3.0, true)
	add_child(ring)
	ring.global_position = pos + Vector3(0, 0.2, 0)
	var tw := create_tween()
	tw.tween_property(ring, "global_position:y", pos.y + 2.4, 0.8)
	tw.parallel().tween_property(ring, "scale", Vector3.ONE * maxf(radius * 0.3, 1.2), 0.8)
	tw.parallel().tween_property(ring, "transparency", 1.0, 0.8)
	tw.tween_callback(ring.queue_free)
	_burst(pos + Vector3.UP, Vector3.UP, color, 30, 3.0, 1.0, 1.4, true, 2.0, 180.0)


func heal_burst(pos: Vector3) -> void:
	aura_burst(pos, Color(0.5, 1.0, 0.55), 2.0)


func trail(from: Vector3, to: Vector3, color: Color) -> void:
	_burst(to, (from - to).normalized(), Color(color.r, color.g, color.b, 0.8), 3, 1.0, 0.35, 1.2, true, 0.0, 20.0)
