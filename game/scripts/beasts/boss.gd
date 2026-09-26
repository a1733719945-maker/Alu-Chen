class_name Boss
extends Node3D
## Boss：房主算 AI 和血量，客人按快照插值显示。模型和数值在 Data.BOSSES 里。
##
## ai = water（千年曼陀罗蛇、深海魔鲸）：待在水里，头露出水面。
##   喷毒 —— 毒液落地变成毒池；尾巴砸 —— 地上先出红圈，1.3 秒后砸下；
##   潜水 —— 沉下去，从玩家附近的水里跃出；半血以下召唤小怪
## ai = land（人面魔蛛、泰坦巨猿）：在空地上绕着玩家走。
##   吐网 / 扔石头；跳砸 —— 红圈预警后跳过来；喷毒；半血以下更快
## ai = air（冰霜巨龙）：在天上盘旋。
##   冰息 —— 冻住的地方会减速；俯冲 —— 红圈预警后冲下来；半血以下召唤雪原狼
## 打头是弱点，伤害 ×1.7；打身体 ×0.6
##
## 受击体积：按模型真实的包围盒做一个身体盒子 + 头上一个弱点球（Data.BOSSES 的 weak 是头在包围盒里的位置）。
## 魂技按"离身体表面多远"算，不按中心算，不然大 Boss 根本打不到。
## 仇恨：只打附近 90 米内、没隐身、没刚复活的玩家；没人可打一段时间就慢慢回血。
## 外观：身上有流动的金色能量和边缘光、四个魂环、背后的圣光光轮、天上照下来的光柱、金色光点。

const INTERP_DELAY := 0.1

var world: Node
var kind := "mandala"
var cfg: Dictionary
var ai := "water"
var proxy := false
var max_hp := 3000.0
var hp := 3000.0
var state := "emerge"
var state_t := 0.0
var phase := 1
var damagers := {}
var dead := false

var head: Node3D                 # 整个 Boss 的位置（模型中心）
var model: Node3D
var parts: Array[StaticBody3D] = []
var size := Vector3(4, 4, 4)     # 缩放后的宽、高、长
var _upright := false
var _move_to := Vector3.ZERO
var _anchor := Vector3.ZERO
var _atk_cd := 3.0
var _dive_cd := 14.0
var _summon_cd := 10.0
var _yaw := 0.0
var _t := 0.0
var _snaps: Array = []
var _root_t := 0.0
var _orbit := 0.0
var _last_pos := Vector3.ZERO
var _speed := 0.0
var _dying := -1.0
var _fall_v := 0.0
var _box := AABB()               # 身体包围盒（Head 本地坐标）
var _weak_pos := Vector3.ZERO
var _weak_r := 1.0
var _mark_t := 0.0
var _mark_mult := 1.0
var _no_target_t := 0.0
var _halo: Node3D
var _sp_cd := 5.0                # 特殊招式（延迟重击 / 冲击环 / 连扫）冷却
var _combo_n := 0
var _combo_t := 0.0
var _combo_peer := 0
var _ult_cd := 0.0               # 二阶段全场大招
var _ult_ready := false
var _since_hit := 99.0
var _custom := false              # 用的是玩家自己放的模型（有真贴图，不压暗）            # 多久没挨打了：远处狙击也算在打它，不会回血
var _soul_rings: Array = []
var _pillar: MeshInstance3D

const HOLY_SHADER := """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;
uniform vec4 rim_color : source_color = vec4(1.0, 0.82, 0.45, 1.0);
uniform vec4 vein_color : source_color = vec4(0.7, 0.4, 1.0, 1.0);
uniform float rim_power = 2.2;
uniform float strength = 1.3;
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	float n = noise(wpos.xz * 0.7 + vec2(0.0, TIME * 0.5)) * noise(wpos.xy * 0.9 - vec2(TIME * 0.35, 0.0));
	float veins = smoothstep(0.3, 0.42, n) * (0.55 + 0.45 * sin(TIME * 3.0 + wpos.y));
	float pulse = 0.85 + 0.15 * sin(TIME * 1.7);
	ALBEDO = rim_color.rgb * fres * strength * pulse + vein_color.rgb * veins * 0.6;
}
"""
const PILLAR_SHADER := """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.85, 0.5, 1.0);
uniform float alpha = 0.18;
void fragment() {
	float fade = pow(1.0 - UV.y, 0.6) * smoothstep(0.0, 0.08, UV.y);
	float side = pow(clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float flow = 0.75 + 0.25 * sin(UV.y * 40.0 - TIME * 3.0);
	ALBEDO = color.rgb * alpha * fade * side * flow;
}
"""


func setup(p_world: Node, p_kind: String, p_hp: float, p_proxy: bool, anchor: Vector3) -> void:
	world = p_world
	kind = p_kind
	cfg = Data.BOSSES[kind]
	ai = str(cfg.get("ai", "land"))
	proxy = p_proxy
	max_hp = p_hp
	hp = p_hp
	_anchor = anchor
	name = "Boss"
	_build()


# ------------------------------------------------------------------ 模型和碰撞

func _part_body(shape: Shape3D, weak: bool, offset: Vector3) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = U.LAYER_BEAST
	b.collision_mask = 0
	b.set_meta("boss", true)
	b.set_meta("weak", weak)
	b.set_meta("offset", offset)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	b.add_child(cs)
	b.top_level = true
	add_child(b)
	parts.append(b)


## 模型所有网格合起来的包围盒（Head 本地坐标）
func _measure_box() -> AABB:
	var out := AABB()
	var first := true
	var inv := head.global_transform.affine_inverse()
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var bb := (inv * mi.global_transform) * mi.mesh.get_aabb()
		if first:
			out = bb
			first = false
		else:
			out = out.merge(bb)
	return out


func _build() -> void:
	head = Node3D.new()
	head.name = "Head"
	head.top_level = true
	add_child(head)
	# 有用户自己放的模型（assets/models/bosses/<kind>.glb）就用它
	var custom := BeastModels.custom_boss_path(kind)
	_custom = custom != ""
	model = BeastModels.instance_custom(custom, cfg) if _custom else BeastModels.instance_model(cfg)
	head.add_child(model)
	var d := BeastModels._dims(str(cfg["model"]))
	var k := BeastModels._model_scale(cfg)
	size = Vector3(float(d["w"]), float(d["h"]), float(d["l"])) * k
	_upright = size.y > size.z * 1.15
	_box = _measure_box()
	if _box.size.length() < 0.5:
		_box = AABB(-size * 0.5, size)
	size = _box.size
	# 年份光环
	var r := maxf(size.x, size.z) * 0.55
	var ring := U.part(head, U.torus(r, r + 0.25, 64, 6), U.glow(Data.age_color(2), 4.0), Vector3(0, _box.position.y + size.y * 0.15, 0), Vector3.ZERO, Vector3.ONE, false)
	ring.name = "Ring"
	# 碰撞：身体一个盒子（头那一截切掉），头是弱点球，露在外面
	var wn: Vector3 = cfg.get("weak", Vector3(0, 0.36, -0.2) if _upright else Vector3(0, 0.15, -0.42))
	_weak_pos = _box.get_center() + _box.size * wn
	var mn := minf(size.x, minf(size.y, size.z))
	var mx := maxf(size.x, maxf(size.y, size.z))
	_weak_r = clampf(maxf(mn * 0.4, mx * 0.13), 1.0, 4.0)
	var lo := _box.position + _box.size * 0.06
	var hi := _box.end - _box.size * 0.06
	if absf(wn.y) >= absf(wn.z):
		hi.y = minf(hi.y, _weak_pos.y - _weak_r * 0.5)
	else:
		lo.z = maxf(lo.z, _weak_pos.z + _weak_r * 0.5)
	var bs := BoxShape3D.new()
	bs.size = (hi - lo).abs().max(Vector3.ONE * 0.5)
	_part_body(bs, false, (lo + hi) * 0.5)
	var ws := SphereShape3D.new()
	ws.radius = _weak_r
	_part_body(ws, true, _weak_pos)
	_decorate()
	match ai:
		"water":
			head.global_position = _anchor + Vector3(0, -size.y, 0)
		"land":
			head.global_position = _anchor + Vector3(0, 14, 0)
		"air":
			head.global_position = _anchor + Vector3(0, 40, 0)


## 让 Boss 看起来威猛、有神圣感：
##   材质变暗、更有光泽，外面再叠一层流动的金色能量 + 边缘光（HOLY_SHADER）；
##   一个加粗发亮的年份魂环（魂兽只有一个魂环）；头后面一圈圣光光轮；天上照下来一道光柱；金色光点往上飘；眼睛发光
func _decorate() -> void:
	var holy := ShaderMaterial.new()
	holy.shader = Shader.new()
	holy.shader.code = HOLY_SHADER
	var theme: Color = cfg.get("holy", Color(1.0, 0.82, 0.45))
	holy.set_shader_parameter("rim_color", theme)
	var vein: Color = cfg.get("glow", Color(0.2, 0.1, 0.35))
	holy.set_shader_parameter("vein_color", Color(vein.r * 3.0 + 0.3, vein.g * 3.0 + 0.2, vein.b * 3.0 + 0.5))
	if _custom:
		# 自己的模型有真贴图：流光和边缘光淡一点，不要把贴图盖住
		holy.set_shader_parameter("strength", 0.6)
		holy.set_shader_parameter("vein_color", Color(vein.r * 0.8, vein.g * 0.8, vein.b * 0.8))
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var base := mi.get_active_material(i)
			if not base is BaseMaterial3D:
				continue
			var m := (base as BaseMaterial3D).duplicate() as BaseMaterial3D
			var a := m.albedo_color
			if not _custom:
				m.albedo_color = Color(a.r * 0.72, a.g * 0.7, a.b * 0.74, a.a)
				m.roughness = 0.42
			if not _custom:
				m.metallic_specular = 0.75
				m.rim_enabled = true
				m.rim = 0.7
				m.rim_tint = 0.4
			m.next_pass = holy
			mi.set_surface_override_material(i, m)
	var c := _box.get_center()
	var big := maxf(size.x, size.z)
	# 魂兽只有一个魂环（代表它的年份）：就是 _build 里那一圈，这里只把它加粗、加亮
	var ring0 := head.get_node("Ring") as MeshInstance3D
	var rr0 := big * 0.6
	ring0.mesh = U.torus(rr0 - 0.3, rr0 + 0.3, 96, 10)
	ring0.material_override = U.glow(Data.age_color(int(cfg.get("age", 2))), 6.0)
	var ages: Array = []
	for i in ages.size():
		var col := Data.age_color(ages[i])
		var rr := big * (0.62 + i * 0.05)
		var mat := U.glow(col if ages[i] < 3 else Color(0.9, 0.1, 0.15), 5.0 if ages[i] < 3 else 3.0)
		var sr := Node3D.new()
		head.add_child(sr)
		U.part(sr, U.torus(rr - 0.16, rr + 0.16, 96, 8), mat, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
		if ages[i] == 3:
			U.part(sr, U.torus(rr - 0.1, rr + 0.1, 96, 6), U.mat(Color(0.03, 0.02, 0.03), 0.3), Vector3(0, 0.02, 0), Vector3.ZERO, Vector3.ONE, false)
		_soul_rings.append(sr)
	# 圣光光轮：头后面竖着的一圈 + 放射状光芒
	_halo = Node3D.new()
	head.add_child(_halo)
	_halo.position = _weak_pos + Vector3(0, _weak_r * 0.6, _weak_r * 1.6)
	var hr := clampf(_weak_r * 2.4, 2.0, 7.0)
	var gold := U.glow(Color(1.0, 0.85, 0.45), 4.0, true)
	U.part(_halo, U.torus(hr - 0.12, hr + 0.12, 96, 6), gold, Vector3.ZERO, Vector3(PI / 2, 0, 0), Vector3.ONE, false)
	U.part(_halo, U.torus(hr * 0.72 - 0.05, hr * 0.72 + 0.05, 96, 4), gold, Vector3.ZERO, Vector3(PI / 2, 0, 0), Vector3.ONE, false)
	for k in 16:
		var a := TAU * k / 16.0
		var ln := hr * (0.5 if k % 2 == 0 else 0.3)
		U.part(_halo, U.box(Vector3(0.08, ln, 0.04)), gold, Vector3(cos(a), sin(a), 0) * (hr + ln * 0.5 + 0.2), Vector3(0, 0, a - PI / 2), Vector3.ONE, false)
	# 眼睛（只给自带的模型加；自己的模型眼睛位置不知道，别乱挂两个光球）
	for side in ([] if _custom else [-1.0, 1.0]):
		var e := U.part(head, U.sphere(_weak_r * 0.14, 8, 6), U.glow(Color(1.0, 0.9, 0.5), 10.0), _weak_pos + Vector3(side * _weak_r * 0.35, _weak_r * 0.15, -_weak_r * 0.75), Vector3.ZERO, Vector3.ONE, false)
		e.name = "Eye"
	var el := OmniLight3D.new()
	el.light_color = Color(1.0, 0.85, 0.5)
	el.light_energy = 3.0
	el.omni_range = _weak_r * 4.0
	el.position = _weak_pos + Vector3(0, 0, -_weak_r)
	head.add_child(el)
	var gl := OmniLight3D.new()
	gl.light_color = theme
	gl.light_energy = 2.5
	gl.omni_range = big * 2.2
	gl.position = c
	head.add_child(gl)
	# 金色光点
	var p := CPUParticles3D.new()
	p.amount = 90
	p.lifetime = 3.0
	p.mesh = U.sphere(0.08, 6, 3)
	p.material_override = U.glow(Color(1.0, 0.85, 0.45), 6.0, true)
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.2
	p.gravity = Vector3(0, 0.5, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = _box.size * 0.55
	p.position = c
	head.add_child(p)
	# 光柱：从天上照下来
	_pillar = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = big * 0.5
	cm.bottom_radius = big * 0.75
	cm.height = 60.0
	cm.cap_top = false
	cm.cap_bottom = false
	_pillar.mesh = cm
	var pm := ShaderMaterial.new()
	pm.shader = Shader.new()
	pm.shader.code = PILLAR_SHADER
	pm.set_shader_parameter("color", theme)
	pm.set_shader_parameter("alpha", 0.07 if _custom else 0.12)
	_pillar.material_override = pm
	_pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pillar.top_level = true
	add_child(_pillar)


## 露出水面 / 离地多高（模型中心）
func _hover() -> float:
	match ai:
		"water":
			# 只有底下一小截在水里，整个身子都露出来能打
			return -_box.position.y - size.y * 0.1
		"air":
			return 14.0
	return -_box.position.y


# ------------------------------------------------------------------ 房主：受伤

func take_hit(dmg: float, weak: bool, shooter: int) -> float:
	if dead:
		return 0.0
	var real := dmg * (1.7 if weak else 0.6) * (_mark_mult if _mark_t > 0.0 else 1.0)
	hp -= real
	_since_hit = 0.0
	damagers[shooter] = float(damagers.get(shooter, 0.0)) + real
	if hp <= max_hp * 0.5 and phase == 1:
		phase = 2
		_ult_ready = true
		world.boss_phase2()
	if hp <= 0.0:
		hp = 0.0
		dead = true
		world.boss_died(self)
	return real


func root(t: float) -> void:
	_root_t = maxf(_root_t, t * 0.5)


func mark(t: float, mult: float) -> void:
	_mark_t = maxf(_mark_t, t)
	_mark_mult = maxf(mult, 1.0)


## 点 p 离 Boss 身体表面多远（在身体里面是负数或 0）
func surface_dist(p: Vector3) -> float:
	var best := INF
	for b in parts:
		var cs := b.get_child(0) as CollisionShape3D
		if cs.shape is SphereShape3D:
			best = minf(best, b.global_position.distance_to(p) - (cs.shape as SphereShape3D).radius)
		elif cs.shape is BoxShape3D:
			var lp := b.global_transform.affine_inverse() * p
			var he := (cs.shape as BoxShape3D).size * 0.5
			var q := lp.abs() - he
			best = minf(best, q.max(Vector3.ZERO).length() + minf(maxf(q.x, maxf(q.y, q.z)), 0.0))
	return best


## 一条线段（光束、冲刺）有没有碰到 Boss
func segment_hit(origin: Vector3, dir: Vector3, length: float, width: float) -> bool:
	var steps := int(ceil(length / 0.8))
	for i in steps + 1:
		if surface_dist(origin + dir * (length * i / maxf(steps, 1))) < width:
			return true
	return false


func center() -> Vector3:
	return head.global_position


## 弱点（头）的位置
func weak_point() -> Vector3:
	for b in parts:
		if b.get_meta("weak"):
			return b.global_position
	return head.global_position


# ------------------------------------------------------------------ 房主：AI

func _set_state(s: String) -> void:
	state = s
	state_t = 0.0
	if s in ["leap", "dive_attack"]:
		BeastModels.play_role(model, "attack")


## 死了：不能再被打中，播死亡动画；飞的摔下来，水里的沉下去，最后炸成魂光
func die_visual() -> void:
	dead = true
	_dying = 0.0
	for b in parts:
		b.collision_layer = 0
	head.get_node("Ring").visible = false
	for sr in _soul_rings:
		(sr as Node3D).visible = false
	if _halo:
		_halo.visible = false
	if _pillar:
		_pillar.visible = false
	BeastModels.play_role(model, "death")


func _dying_tick(dt: float) -> void:
	_dying += dt
	var p := head.global_position
	if ai == "water":
		p.y -= dt * size.y * 0.35
	else:
		var rest := maxf(world.island.height_at(p.x, p.z), Island.WATER_Y - size.y * 0.3) + size.y * 0.5
		if p.y > rest:
			_fall_v += 9.8 * 1.6 * dt
			p.y = maxf(p.y - _fall_v * dt, rest)
			if p.y <= rest:
				world.fx.explosion(p + Vector3(0, -size.y * 0.4, 0), size.x * 0.6, Color(0.75, 0.7, 0.6))
				Sfx.play_at("slam", p, 2.0)
	head.global_position = p
	if _dying > 2.4:
		_dying = -100.0
		world.fx.death_burst(p, Data.age_color(2), 3)
		world.fx.explosion(p, 8.0, Color(0.8, 0.3, 1.0))
		queue_free()


func _process(dt: float) -> void:
	_t += dt
	if _dying >= 0.0:
		_dying_tick(dt)
		return
	if _dying < -1.0:
		return
	if proxy:
		_interpolate()
	elif not dead:
		_think(dt)
	_update_visual(dt)


## 能打的玩家：没倒地、没隐身、没在复活保护里，而且离 Boss 不太远（跑远了就脱战）
func _targets() -> Array:
	var c := head.global_position
	return world.alive_players().filter(func(p): return Vector2(p["pos"].x - c.x, p["pos"].z - c.z).length() < 90.0)


func _pick_target() -> Dictionary:
	var ps := _targets()
	if ps.is_empty():
		return {}
	return ps[randi() % ps.size()]


func _think(dt: float) -> void:
	state_t += dt
	_since_hit += dt
	_mark_t = maxf(_mark_t - dt, 0.0)
	if _targets().is_empty():
		# 没人可打：脱战，慢慢回血（打死人以后复活回来不会一直被追着打）。
		# 远处还有人在打它（狙击）就不算脱战，不回血
		_no_target_t += dt
		if _no_target_t > 8.0 and _since_hit > 15.0:
			hp = minf(hp + max_hp * 0.015 * dt, max_hp)
		if state in ["idle"]:
			_atk_cd = maxf(_atk_cd, 2.0)
			return
	else:
		_no_target_t = 0.0
		_moves(dt)
	var speed_k := 0.5 if _root_t > 0.0 else (1.35 if phase == 2 else 1.0)
	_root_t = maxf(_root_t - dt, 0.0)
	match ai:
		"water":
			_think_water(dt, speed_k)
		"air":
			_think_air(dt, speed_k)
		_:
			_think_land(dt, speed_k)


## 新招式（学黑神话 / 艾尔登法环）：看起手、踩节奏翻滚才能躲
##   延迟重击：起手时长不固定，红圈只在最后 0.35 秒出现
##   冲击环：脚下扩散的红墙，跳过去或者翻滚穿过去（二阶段连着两圈）
##   连扫：三～四下扇形横扫，每一下都重新对准人
##   全场大招（二阶段）：一大片都砸，只有几个绿圈安全
func _moves(dt: float) -> void:
	_sp_cd -= dt
	_ult_cd -= dt
	var h := head.global_position
	var o := Vector3(h.x, world.island.height_at(h.x, h.z), h.z)
	if _combo_n > 0:
		_combo_t -= dt
		if _combo_t <= 0.0:
			_combo_t = 0.75 if phase == 1 else 0.6
			_combo_n -= 1
			var tp := _target_by_peer(_combo_peer)
			if not tp.is_empty():
				world.boss_cone(o, (tp["pos"] as Vector3) - o, deg_to_rad(38.0), 12.0 + maxf(size.x, size.z) * 0.6, 0.5, 30.0)
				BeastModels.play_role(model, "attack")
		return
	if state != "idle" and state != "dive_attack":
		return
	if phase == 2 and (_ult_ready or _ult_cd <= 0.0):
		_ult_ready = false
		_ult_cd = 45.0
		_ultimate()
		return
	if _sp_cd > 0.0:
		return
	_sp_cd = randf_range(6.0, 9.0) if phase == 1 else randf_range(4.0, 6.0)
	_atk_cd = maxf(_atk_cd, 2.0)
	var tp2 := _pick_target()
	if tp2.is_empty():
		return
	var r := randf()
	if r < 0.35:
		world.boss_shockwave(o, 42.0, 11.0 if phase == 1 else 14.0, 26.0)
		BeastModels.play_role(model, "attack")
		if phase == 2:
			get_tree().create_timer(0.9).timeout.connect(func():
				if not dead:
					world.boss_shockwave(o, 42.0, 14.0, 26.0))
	elif r < 0.7:
		var delay := randf_range(1.0, 2.0)
		world.boss_telegraph(tp2["pos"], 5.5, delay, 42.0, "slam", h, true)
		get_tree().create_timer(delay - 0.2).timeout.connect(func():
			if not dead:
				BeastModels.play_role(model, "attack"))
	else:
		_combo_n = 3 if phase == 1 else 4
		_combo_t = 0.3
		_combo_peer = int(tp2["peer"])


func _target_by_peer(peer: int) -> Dictionary:
	for p in _targets():
		if int(p["peer"]) == peer:
			return p
	return _pick_target()


func _ultimate() -> void:
	var ps := _targets()
	if ps.is_empty():
		return
	var c := Vector3.ZERO
	for p in ps:
		c += p["pos"]
	c /= ps.size()
	c.y = world.island.height_at(c.x, c.z)
	var safes: Array = []
	for k in 3:
		for tries in 20:
			var a := randf() * TAU
			var rr := randf_range(7.0, 14.0)
			var q := c + Vector3(cos(a) * rr, 0, sin(a) * rr)
			if world.island.is_land(q.x, q.z):
				q.y = world.island.height_at(q.x, q.z)
				safes.append(q)
				break
	if safes.is_empty():
		safes.append(c)
	world.boss_ultimate(c, 32.0, safes, 4.0, 70.0)
	BeastModels.play_role(model, "attack")
	# 放大招的这几秒不出别的招：躲进绿圈就一定安全
	_sp_cd = 6.5
	_atk_cd = maxf(_atk_cd, 5.5)


func _summon_tick(dt: float) -> void:
	if phase != 2:
		return
	_summon_cd -= dt
	if _summon_cd <= 0.0:
		_summon_cd = 11.0
		world.boss_summon(self, str(cfg.get("summon", "wolf")), 2)


func _mouth() -> Vector3:
	return weak_point() - head.global_basis.z * size.z * 0.1


func _think_water(dt: float, speed_k: float) -> void:
	var h := head.global_position
	var surf := _anchor.y + _hover()
	match state:
		"emerge":
			var target := Vector3(_anchor.x, surf, _anchor.z)
			head.global_position = h.lerp(target, 1.0 - exp(-2.0 * dt))
			if state_t > 2.5:
				_set_state("idle")
				_move_to = _patrol_point()
		"idle":
			_atk_cd -= dt * speed_k
			_dive_cd -= dt * speed_k
			_summon_tick(dt)
			var to := _move_to - h
			to.y = 0
			if to.length() < 1.5:
				_move_to = _patrol_point()
			var np := h + to.limit_length(3.2 * speed_k * dt)
			np.y = surf + sin(_t * 1.3) * 0.8
			head.global_position = np
			_face_toward(world.nearest_player_pos(h), dt)
			if _dive_cd <= 0.0:
				_dive_cd = 16.0
				_set_state("dive")
			elif _atk_cd <= 0.0:
				var tp := _pick_target()
				if not tp.is_empty():
					var near: bool = Vector2(tp["pos"].x - h.x, tp["pos"].z - h.z).length() < 22.0 + size.z * 0.5
					if near and randf() < 0.55:
						_atk_cd = 3.2
						world.boss_telegraph(tp["pos"], 5.5, 1.3, 32.0, "slam", h)
						BeastModels.play_role(model, "attack")
					else:
						_atk_cd = 3.0 if phase == 1 else 2.2
						var n := 1 if phase == 1 else 3
						for i in n:
							var off := Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)) * (0 if i == 0 else 1)
							world.boss_projectile("spit", _mouth(), tp["pos"] + off, 1.2, 3.5, 14.0)
		"dive":
			head.global_position.y = move_toward(h.y, _anchor.y - size.y, 6.0 * dt)
			if state_t > 1.6:
				var tp := _pick_target()
				var pos := _anchor
				if not tp.is_empty():
					pos = world.water_point_near(tp["pos"])
				head.global_position = Vector3(pos.x, _anchor.y - size.y, pos.z)
				_move_to = pos
				world.boss_telegraph(Vector3(pos.x, 0.0, pos.z), 6.5 + size.z * 0.15, 1.3, 30.0, "leap", pos)
				_set_state("leap")
		"leap":
			if state_t > 1.2:
				head.global_position = head.global_position.lerp(Vector3(_move_to.x, surf + 1.5, _move_to.z), 1.0 - exp(-6.0 * dt))
			if state_t > 2.4:
				_anchor = Vector3(head.global_position.x, _anchor.y, head.global_position.z)
				_set_state("idle")
				_move_to = _patrol_point()


func _patrol_point() -> Vector3:
	return _anchor + Vector3(randf_range(-14, 14), 0, randf_range(-8, 8))


func _think_land(dt: float, speed_k: float) -> void:
	var h := head.global_position
	var ground: float = world.island.height_at(h.x, h.z)
	var off := _hover()
	match state:
		"emerge":
			# 从天上 / 树冠上落下来
			head.global_position.y = move_toward(h.y, ground + off, 14.0 * dt)
			if state_t > 1.5:
				_set_state("idle")
				world.boss_telegraph(Vector3(h.x, ground, h.z), size.x * 0.6 + 3.0, 0.1, 0.0, "slam", h)
		"idle":
			_atk_cd -= dt * speed_k
			_summon_tick(dt)
			var tp: Dictionary = world.nearest_player(h)
			if tp.is_empty():
				return
			var to: Vector3 = tp["pos"] - h
			to.y = 0
			var dist := to.length()
			var dir := to.normalized()
			var side := dir.cross(Vector3.UP)
			var keep := 11.0 + size.z * 0.4
			var want := dir * (1.0 if dist > keep + 4.0 else (-1.0 if dist < keep else 0.0)) + side * 0.6
			var np := h + want.normalized() * 4.5 * speed_k * dt
			var c := Vector3(_anchor.x, 0, _anchor.z)
			if Vector3(np.x, 0, np.z).distance_to(c) < 30.0:
				head.global_position = Vector3(np.x, world.island.height_at(np.x, np.z) + off, np.z)
			_face_toward(tp["pos"], dt)
			if _atk_cd <= 0.0:
				var r := randf()
				if r < 0.35:
					_atk_cd = 2.2 if phase == 1 else 1.6
					var n := 1 if phase == 1 else 3
					var kind2 := "rock" if cfg.get("throws", false) else "web"
					for i in n:
						var o := Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5)) * (0 if i == 0 else 1)
						world.boss_projectile(kind2, _mouth() + Vector3(0, 1, 0), tp["pos"] + o, 0.9 if kind2 == "web" else 1.1, 2.2 if kind2 == "web" else 2.8, 10.0 if kind2 == "web" else 22.0)
					BeastModels.play_role(model, "attack")
				elif r < 0.65:
					_atk_cd = 2.6
					world.boss_projectile("spit", _mouth(), tp["pos"], 1.1, 3.5, 14.0)
					BeastModels.play_role(model, "attack")
				else:
					_atk_cd = 3.4
					_move_to = tp["pos"]
					world.boss_telegraph(tp["pos"], 5.0 + size.x * 0.2, 1.3, 40.0, "leap", tp["pos"])
					_set_state("leap")
		"leap":
			if state_t < 1.3:
				head.global_position.y = ground + off - sin(state_t / 1.3 * PI) * 0.4
			elif state_t < 1.8:
				var k := (state_t - 1.3) / 0.5
				var p := h.lerp(Vector3(_move_to.x, h.y, _move_to.z), k)
				p.y = world.island.height_at(p.x, p.z) + off + sin(k * PI) * 6.0
				head.global_position = p
			else:
				_set_state("idle")


func _think_air(dt: float, speed_k: float) -> void:
	var h := head.global_position
	var c := _anchor
	var fly_y := _anchor.y + _hover() + 6.0
	match state:
		"emerge":
			head.global_position = h.lerp(Vector3(c.x, fly_y, c.z), 1.0 - exp(-1.5 * dt))
			_face_toward(world.nearest_player_pos(h), dt)
			if state_t > 3.0:
				_set_state("idle")
		"idle":
			_atk_cd -= dt * speed_k
			_summon_tick(dt)
			_orbit += dt * 0.28 * speed_k
			var tp: Vector3 = world.nearest_player_pos(h)
			var rad := 26.0
			var goal := Vector3(tp.x + cos(_orbit) * rad, fly_y + sin(_t * 0.7) * 3.0, tp.z + sin(_orbit) * rad)
			var np := h.lerp(goal, 1.0 - exp(-0.8 * dt))
			head.global_position = np
			var vel := np - h
			_face_toward(h + vel * 10.0 if vel.length() > 0.02 else tp, dt)
			if _atk_cd <= 0.0:
				var t2 := _pick_target()
				if t2.is_empty():
					return
				if randf() < 0.6:
					# 冰息：一串冰球，落地的地方结冰减速
					_atk_cd = 2.6 if phase == 1 else 1.8
					var n := 3 if phase == 1 else 5
					for i in n:
						var o := Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)) * (0 if i == 0 else 1)
						world.boss_projectile("web", _mouth(), t2["pos"] + o, 1.0 + i * 0.12, 3.0, 16.0)
					BeastModels.play_role(model, "attack")
				else:
					_atk_cd = 4.0
					_move_to = t2["pos"]
					world.boss_telegraph(t2["pos"], 7.0, 1.6, 45.0, "leap", t2["pos"])
					_set_state("dive_attack")
		"dive_attack":
			if state_t < 1.4:
				var to := _move_to - h
				to.y = 0
				_face_toward(_move_to, dt * 3.0)
				head.global_position = h.lerp(_move_to + Vector3(0, 3.0 + size.y * 0.3, 0) - to.normalized() * 6.0, 1.0 - exp(-2.5 * dt))
			elif state_t < 2.4:
				head.global_position = h.lerp(Vector3(h.x, fly_y, h.z), 1.0 - exp(-2.0 * dt))
			else:
				_set_state("idle")


func _face_toward(p: Vector3, dt: float) -> void:
	var to := p - head.global_position
	to.y = 0
	if to.length() < 0.1:
		return
	var target_yaw := atan2(-to.x, -to.z)
	_yaw = lerp_angle(_yaw, target_yaw, 1.0 - exp(-3.0 * dt))


# ------------------------------------------------------------------ 同步

func snapshot() -> Array:
	return [head.global_position, _yaw, hp / max_hp, state]


func push_snapshot(s: Array) -> void:
	_snaps.append([Time.get_ticks_msec() / 1000.0, s[0], float(s[1])])
	hp = float(s[2]) * max_hp
	var ns := str(s[3])
	if ns != state and ns in ["leap", "dive_attack"]:
		BeastModels.play_role(model, "attack")
	state = ns
	if _snaps.size() > 12:
		_snaps.pop_front()


func _interpolate() -> void:
	if _snaps.is_empty():
		return
	var t := Time.get_ticks_msec() / 1000.0 - INTERP_DELAY
	var s1: Array = _snaps[-1]
	var s0: Array = s1
	var k := 1.0
	for i in range(_snaps.size() - 1):
		if t >= _snaps[i][0] and t <= _snaps[i + 1][0]:
			s0 = _snaps[i]
			s1 = _snaps[i + 1]
			k = (t - s0[0]) / maxf(s1[0] - s0[0], 0.0001)
			break
	head.global_position = (s0[1] as Vector3).lerp(s1[1], k)
	_yaw = lerp_angle(float(s0[2]), float(s1[2]), k)


# ------------------------------------------------------------------ 画面（房主和客人都跑）

func _update_visual(dt: float) -> void:
	head.global_basis = Basis(Vector3.UP, _yaw)
	var ring := head.get_node("Ring")
	ring.rotation.y += dt * 0.8
	var p := head.global_position
	if dt > 0.0:
		_speed = lerpf(_speed, p.distance_to(_last_pos) / dt, 1.0 - exp(-5.0 * dt))
	_last_pos = p
	var airborne := ai == "air" or state == "leap"
	BeastModels._animate_model(model, airborne, _speed, "fly" if ai == "air" else "run")
	for b in parts:
		b.global_transform = head.global_transform * Transform3D(Basis(), b.get_meta("offset") as Vector3)
	# 魂环、光轮、光柱
	for i in _soul_rings.size():
		var sr: Node3D = _soul_rings[i]
		sr.rotation = Vector3(sin(_t * 0.6 + i) * 0.12, _t * (0.5 + i * 0.15) * (1.0 if i % 2 == 0 else -1.0), cos(_t * 0.5 + i) * 0.12)
		sr.position.y = _box.position.y + size.y * (0.12 + i * 0.22) + sin(_t * 1.2 + i * 1.7) * 0.25
	if _halo:
		_halo.rotation.z = _t * 0.25
		var s := 1.0 + sin(_t * 2.0) * 0.04
		_halo.scale = Vector3(s, s, s)
	if _pillar:
		_pillar.global_position = Vector3(p.x, p.y + 30.0, p.z)
