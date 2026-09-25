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
