class_name Boss
extends Node3D
## Boss：房主算 AI 和血量，客人按快照插值显示。模型和数值在 Data.BOSSES 里。
##
## ai = water（千年碧鳞蛇、玄鲲）：待在水里，头露出水面。
##   喷毒 —— 毒液落地变成毒池；尾巴砸 —— 地上先出红圈，1.3 秒后砸下；
##   潜水 —— 沉下去，从玩家附近的水里跃出；半血以下召唤小怪
## ai = land（千目蛛母、朱厌）：在空地上绕着玩家走。
##   吐网 / 扔石头；跳砸 —— 红圈预警后跳过来；喷毒；半血以下更快
## ai = air（冰螭）：在天上盘旋。
##   冰息 —— 冻住的地方会减速；俯冲 —— 红圈预警后冲下来；半血以下召唤雪原狼
## 打头是弱点，伤害 ×1.7；打身体 ×0.6
##
## 受击体积：按模型真实的包围盒做一个身体盒子 + 头上一个弱点球（Data.BOSSES 的 weak 是头在包围盒里的位置）。
## 神通按"离身体表面多远"算，不按中心算，不然大 Boss 根本打不到。
## 仇恨：只打附近 90 米内、没隐身、没刚复活的玩家；没人可打一段时间就慢慢回血。
## 外观：身上有流动的金色能量和边缘光、四个灵环、背后的圣光光轮、天上照下来的光柱、金色光点。

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
# 第十三版：每个 Boss 自己一套招式（零件在 world.arts，BossArts）
var stun_t := 0.0                # 露出破绽还剩几秒（房主）：不动不出招，打头伤害翻倍
var stun_vis := 0.0              # 大家都有：画破绽用
var _act := {}                   # 正在做的大动作：冲锋 / 爬高落下 / 俯冲
var _busy := 0.0                 # 这一招还要多久才出下一招
var _stun_after := 0.0           # 潜水扑出来落地以后露破绽几秒
var _gk := 1.0                   # 大个子：招式范围跟着体型放大（朱厌约 2）
var _step_d := 0.0               # 巨兽走路：攒够一步的距离就震一下地
var _leap_hint := false          # 跃击的提示只弹一次
var _pose_t := 0.0               # 起手：还有几秒砸下来（身子往后仰、抬起来）
var _pose_dur := 0.0
var _slam_t := 0.0               # 砸下去那一下往前一顿
var _model_y0 := 0.0
var _static_model := false        # 没有骨骼动画的模型（程序步态，见 _update_visual）
var _was_air := false              # 上一帧在不在空中（跃击起跳那一下放 jump 动作）
var _gait := 0.0                   # 步态相位（一步 = PI）
var _gait_k := 0.0                 # 走起来的程度 0~1（平滑过渡）

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
## 自己放的模型里没有贴图（只有形状，用户的 spider.glb / whale.glb 就是这样）：以前显示成一整块白。
## 这里用 3D 噪声在模型本地坐标上画一层皮：底色 → 斑块 → 发光的纹路（蛛母的红斑、玄鲲的荧光点），法线没有就按面算
const SKIN_SHADER := """shader_type spatial;
uniform vec4 base : source_color = vec4(0.08, 0.06, 0.09, 1.0);
uniform vec4 mid : source_color = vec4(0.25, 0.14, 0.2, 1.0);
uniform vec4 mark : source_color = vec4(0.9, 0.12, 0.18, 1.0);
uniform float scale = 6.0;
uniform float glow = 1.5;
uniform bool flat_normals = false;
varying vec3 lp;
void vertex() { lp = VERTEX * scale; }
float hash(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float noise(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 p) { float a = 0.5; float s = 0.0; for (int i = 0; i < 5; i++) { s += a * noise(p); p *= 2.03; a *= 0.5; } return s; }
void fragment() {
	if (flat_normals) { NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX))); }
	float n = fbm(lp);
	float fine = noise(lp * 9.0);
	vec3 col = mix(base.rgb, mid.rgb, smoothstep(0.3, 0.72, n));
	col *= 0.75 + 0.35 * fine;
	// 发光纹路：大尺度噪声的等高线 + 零星的斑点
	float m1 = 1.0 - smoothstep(0.0, 0.035, abs(fbm(lp * 0.45 + 11.0) - 0.5));
	float m2 = smoothstep(0.78, 0.84, noise(lp * 1.7 + 3.0));
	float m = max(m1 * 0.9, m2);
	col = mix(col, mark.rgb * 0.6, m);
	ALBEDO = col;
	ROUGHNESS = mix(0.32, 0.8, n) - m * 0.2;
	METALLIC = 0.08;
	SPECULAR = 0.55;
	EMISSION = mark.rgb * m * glow * (0.75 + 0.25 * sin(TIME * 2.0 + lp.x * 0.3));
}
"""
const SKIN_OF := {
	"spider": [Color(0.05, 0.035, 0.06), Color(0.22, 0.1, 0.18), Color(1.0, 0.12, 0.2), 1.8],
	"whale": [Color(0.025, 0.05, 0.09), Color(0.1, 0.2, 0.3), Color(0.3, 0.85, 1.0), 1.6],
	"mandala": [Color(0.03, 0.08, 0.05), Color(0.12, 0.3, 0.16), Color(0.5, 1.0, 0.35), 1.2],
	"titan": [Color(0.09, 0.06, 0.05), Color(0.3, 0.2, 0.14), Color(1.0, 0.45, 0.15), 1.4],
	"icedragon": [Color(0.08, 0.14, 0.22), Color(0.4, 0.6, 0.8), Color(0.55, 0.95, 1.0), 1.2],
}
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
	# 以前各种 Boss 共用的普通攻击（吐口水、跳砸、定时潜水）不用了，出招全在 _moves 里按 Boss 分
	_atk_cd = 1e9
	_dive_cd = 1e9
	_sp_cd = 3.0
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
	_model_y0 = model.position.y
	# AI 生成的模型大多没有骨骼动画：用代码让整个身子动（走路一步一沉、左右晃、跑起来前倾、站着喘气）
	# 有骨骼但没有走 / 跑动作的（比如只导出了死亡动作）也用程序步态
	_static_model = not model.has_meta("ap") or str((model.get_meta("roles") as Dictionary).get("run", "")) == ""
	if _custom and not _static_model:
		# 巨兽的动作按体型放慢：一个走路循环大概走 0.35 个身高
		model.set_meta("walk_max", size.y * 0.5)
		model.set_meta("gait_len", size.y * 0.35)
	FxLib.no_decals(model)
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
	_weak_r = clampf(maxf(mn * 0.4, mx * 0.13), 1.0, 6.0)
	_gk = clampf(maxf(size.x, size.y) / 12.0, 1.0, 2.2)
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
			# 从天上砸下来（大个子从更高的地方）
			head.global_position = _anchor + Vector3(0, 14.0 + size.y, 0)
		"air":
			head.global_position = _anchor + Vector3(0, 40, 0)


static var _skin: Shader


static func _skin_shader() -> Shader:
	if _skin == null:
		_skin = Shader.new()
		_skin.code = SKIN_SHADER
	return _skin


## 让 Boss 看起来威猛、有神圣感：
##   材质变暗、更有光泽，外面再叠一层流动的金色能量 + 边缘光（HOLY_SHADER）；
##   一个加粗发亮的年份灵环（灵兽只有一个灵环）；头后面一圈圣光光轮；天上照下来一道光柱；金色光点往上飘；眼睛发光
func _decorate() -> void:
	var holy := ShaderMaterial.new()
	holy.shader = Shader.new()
	holy.shader.code = HOLY_SHADER
	var theme: Color = cfg.get("holy", Color(1.0, 0.82, 0.45))
	holy.set_shader_parameter("rim_color", theme)
	var vein: Color = cfg.get("glow", Color(0.2, 0.1, 0.35))
	holy.set_shader_parameter("vein_color", Color(vein.r * 3.0 + 0.3, vein.g * 3.0 + 0.2, vein.b * 3.0 + 0.5))
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var base := mi.get_active_material(i)
			if _custom and (base == null or (base is BaseMaterial3D and (base as BaseMaterial3D).albedo_texture == null)):
				# 没有贴图的模型：画一层程序生成的皮（不是一整块白）
				var sk := ShaderMaterial.new()
				sk.shader = _skin_shader()
				var so: Array = SKIN_OF.get(kind, SKIN_OF["titan"])
				sk.set_shader_parameter("base", so[0])
				sk.set_shader_parameter("mid", so[1])
				sk.set_shader_parameter("mark", so[2])
				sk.set_shader_parameter("glow", so[3])
				var ab := mi.mesh.get_aabb()
				sk.set_shader_parameter("scale", 7.0 / maxf(maxf(ab.size.x, ab.size.y), maxf(ab.size.z, 0.001)))
				var fmt := 0
				if mi.mesh is ArrayMesh:
					fmt = (mi.mesh as ArrayMesh).surface_get_format(i)
				sk.set_shader_parameter("flat_normals", (fmt & Mesh.ARRAY_FORMAT_NORMAL) == 0)
				mi.set_surface_override_material(i, sk)
				continue
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
			# 自己的模型保持原样（用户："我辛辛苦苦生成的 Boss，你全部涂成白色"）：不叠流光和边缘光
			if not _custom:
				m.next_pass = holy
			mi.set_surface_override_material(i, m)
	var c := _box.get_center()
	var big := maxf(size.x, size.z)
	# 灵兽只有一个灵环（代表它的年份）：就是 _build 里那一圈，这里只把它加粗、加亮
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
	# 露出破绽：打头 ×2，打身子 ×1.3
	if stun_t > 0.0:
		real *= 2.0 if weak else 1.3
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
	# 露出破绽：趴着 / 浮着不动，不出招
	if stun_t > 0.0:
		stun_t -= dt
		if stun_t <= 0.0:
			_sp_cd = maxf(_sp_cd, 1.2)
			BeastModels.play_role(model, "attack")
		return
	# 冲锋、爬高落下、俯冲这些大动作自己管位置
	if not _act.is_empty():
		_act_tick(dt)
		return
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


## 第十三版：每个 Boss 自己一套招式（用户："最后的 Boss 和第一个用的技能一样、特效也没变，完全就是数值；借鉴鬼泣"）。
## 招式零件在 world.arts（BossArts）；这里决定什么时候出哪一招。一招出完 _busy 秒内不出下一招；
## 二阶段（半血）多几招、出得更快。大动作（冲锋、潜水突袭、从天而降、俯冲）结束会露出破绽：打头伤害翻倍。
##   碧鳞蛇（毒）：毒雾横扫、三连毒液、缠绕、潜水突袭（落地破绽）｜二阶段：来回横扫、毒沼
##   千目蛛母（蛛丝）：蛛丝弹幕、毒牙扑咬、从天而降（破绽）、子蛛｜二阶段：连扑、蛛网牢笼（只有中间安全）
##   朱厌（岩石）：巨岩连投、蛮牛冲锋（撞完破绽 3 秒）、震地三连、左右双拳｜二阶段：落石雨、连冲两次
##   冰螭（冰）：冰息扫射、冰锥螺旋、贴地俯冲（破绽）、冰晶追身｜二阶段：寒潮（躲进绿圈）
##   玄鲲（水）：海啸（找缺口）、漩涡、跃海冲击（破绽）、水柱追身｜二阶段：深渊凝视（扫射）、海啸加水柱一起来
const STYLE_OF := {"mandala": "poison", "spider": "silk", "titan": "rock", "icedragon": "ice", "whale": "water"}


func _style() -> String:
	return str(STYLE_OF.get(kind, "fire"))


func _moves(dt: float) -> void:
	_sp_cd -= dt
	_ult_cd -= dt
	_busy = maxf(_busy - dt, 0.0)
	if _busy > 0.0 or state != "idle":
		return
	if phase == 2 and kind in ["icedragon", "whale"] and (_ult_ready or _ult_cd <= 0.0):
		_ult_ready = false
		_ult_cd = 50.0
		_ultimate()
		_busy = 5.5
		return
	if _sp_cd > 0.0:
		return
	var tp := _pick_target()
	if tp.is_empty():
		return
	var h := head.global_position
	var o := Vector3(h.x, world.island.height_at(h.x, h.z), h.z)
	var t: Vector3 = tp["pos"]
	var peer := int(tp["peer"])
	BeastModels.play_role(model, "attack")
	var near := _nearest_dist(o)
	if near < _body_r() + 6.0 and randf() < 0.5 and force_art == "":
		_swat(o)
		_sp_cd = randf_range(0.3, 0.7)
		return
	match kind:
		"spider":
			_art_spider(o, t, peer)
		"titan":
			_art_titan(o, t, peer)
		"icedragon":
			_art_dragon(o, t, peer)
		"whale":
			_art_whale(o, t, peer)
		_:
			_art_mandala(o, t, peer)
	# 两招之间喘口气（二阶段短一点）。用户："攻击频率太低、打完了都只砸了一下"：以前 1~2 秒，现在 0.4~0.9 秒
	_sp_cd = randf_range(0.4, 0.9) * (1.0 if phase == 1 else 0.65)


var force_art := ""              # 自动测试：指定下一招


## 身子多宽（水平半径）
func _body_r() -> float:
	return maxf(size.x, size.z) * 0.5


func _nearest_dist(o: Vector3) -> float:
	var best := INF
	for p in _targets():
		best = minf(best, Vector2(p["pos"].x - o.x, p["pos"].z - o.z).length())
	return best


## 拍地：贴在身边的人挨一下（0.9 秒起手，身子一仰——看到就往外翻滚）
func _swat(o: Vector3) -> void:
	var c := Vector3(head.global_position.x, o.y, head.global_position.z)
	world.arts.circle(c, _body_r() + 5.5, 0.9, 30.0, _style())
	Sfx.play_at("boss_roar", c, 2.0, 0.05, 0.9)
	_busy = 1.3


## 起手动作（每台电脑自己演：BossArts 收到招式的时候调）：身子往后仰、抬起来，到点砸下去往前一顿
func windup(sec: float) -> void:
	if dead or sec < 0.35 or _pose_t > 0.0:
		return
	_pose_t = sec
	_pose_dur = sec


## 按权重挑一招：opts = [[名字, 权重], ...]
func _pick(opts: Array) -> String:
	if force_art != "":
		var f := force_art
		force_art = ""
		for e in opts:
			if str(e[0]) == f:
				return f
	var total := 0.0
	for e in opts:
		total += float(e[1])
	var r := randf() * total
	for e in opts:
		r -= float(e[1])
		if r <= 0.0:
			return str(e[0])
	return str(opts[0][0])


## 过一会儿再做（Boss 死了就不做）
func _later(sec: float, f: Callable) -> void:
	var tw := create_tween()
	tw.tween_interval(maxf(sec, 0.01))
	tw.tween_callback(func():
		if not dead and is_instance_valid(world):
			f.call())


## 这个人现在在哪（走了就用 fallback）
func _peer_pos_or(peer: int, fallback: Vector3) -> Vector3:
	for p in _targets():
		if int(p["peer"]) == peer:
			return p["pos"]
	return fallback


func _yaw_to(o: Vector3, p: Vector3) -> float:
	return atan2(p.x - o.x, p.z - o.z)


## 冲过去：地上先出一条直线预警，delay 秒后 Boss 沿着冲（冲击跟着走）；stun > 0 冲完露破绽；again = 冲完马上再冲一次
func _lunge(o: Vector3, t: Vector3, delay: float, speed: float, dmg: float, width: float, stun: float, again := false) -> void:
	var dir := Vector3(t.x - o.x, 0, t.z - o.z)
	var dist := dir.length()
	dir = dir.normalized() if dist > 0.5 else -head.global_basis.z
	var length := clampf(dist + 9.0, 14.0, 42.0)
	# 别冲出场地太远（地上的 Boss 在老窝 34 米内活动）
	var end := o + dir * length
	var an := Vector3(_anchor.x, 0, _anchor.z)
	var ec := Vector3(end.x, 0, end.z)
	if ai == "land" and ec.distance_to(an) > 34.0:
		ec = an + (ec - an).limit_length(34.0)
		length = maxf(Vector3(ec.x - o.x, 0, ec.z - o.z).length(), 10.0)
	world.arts.lane(o, dir, length, width, delay, dmg, _style(), speed)
	_act = {"type": "charge", "t": 0.0, "from": head.global_position, "dir": dir, "len": maxf(length - 2.0, 4.0), "delay": delay,
		"speed": speed, "dmg": dmg, "width": width, "stun": stun, "again": again}
	_busy = 0.6


## 大动作：冲锋 / 俯冲（charge）、爬到高处再砸下来（climb）
func _act_tick(dt: float) -> void:
	_act["t"] = float(_act["t"]) + dt
	var t := float(_act["t"])
	match str(_act["type"]):
		"charge":
			var from: Vector3 = _act["from"]
			var dir: Vector3 = _act["dir"]
			var delay := float(_act["delay"])
			if t < delay:
				# 蓄力：往后缩一点，盯着冲的方向
				_face_toward(head.global_position + dir * 10.0, dt * 4.0)
				var back := from - dir * sin(t / delay * PI * 0.5) * 1.5
				head.global_position = Vector3(back.x, head.global_position.y, back.z)
				return
			var k := clampf((t - delay) * float(_act["speed"]) / float(_act["len"]), 0.0, 1.0)
			var p := from + dir * float(_act["len"]) * k
			var g := maxf(world.island.height_at(p.x, p.z), Island.WATER_Y)
			match ai:
				"air":
					p.y = g + size.y * 0.45 + 1.0
				"water":
					p.y = head.global_position.y
				_:
					p.y = world.island.height_at(p.x, p.z) + _hover()
			head.global_position = head.global_position.lerp(p, 1.0 - exp(-18.0 * dt))
			_face_toward(p + dir * 10.0, dt * 4.0)
			if k >= 1.0:
				var st := float(_act["stun"])
				var again := bool(_act["again"])
				var a := _act
				_act = {}
				if again:
					var tp := _pick_target()
					if not tp.is_empty():
						var h := head.global_position
						_lunge(Vector3(h.x, world.island.height_at(h.x, h.z), h.z), tp["pos"], 0.55, float(a["speed"]), float(a["dmg"]), float(a["width"]), maxf(st, 2.5), false)
						return
				if st > 0.0:
					world.arts.stun(self, st)
					world.fx.slam(Vector3(head.global_position.x, g, head.global_position.z), 6.0)
				_busy = 0.8
		"leap":
			_leap_tick(t, dt)
		"climb":
			# 千目蛛母：爬到高处（1 秒）→ 地上出圈跟着人（圈定了就不动）→ 砸下来 → 腿陷进蛛网里露破绽
			var at: Vector3 = _act["at"]
			var gy: float = world.island.height_at(at.x, at.z)
			if t < 1.0:
				var h0 := head.global_position
				head.global_position = Vector3(h0.x, lerpf(h0.y, gy + 36.0, 1.0 - exp(-4.0 * dt)), h0.z)
				return
			if not _act.has("marked"):
				_act["marked"] = true
				at = _peer_pos_or(int(_act["peer"]), at)
				_act["at"] = at
				world.arts.circle(at, 7.0, 1.7, 45.0, "silk")
				return
			if t < 2.45:
				var hp2 := head.global_position
				head.global_position = hp2.lerp(Vector3(at.x, gy + 36.0, at.z), 1.0 - exp(-5.0 * dt))
				return
			if t < 2.7:
				var k2 := (t - 2.45) / 0.25
				head.global_position = Vector3(at.x, lerpf(gy + 36.0, gy + _hover(), k2 * k2), at.z)
				return
			head.global_position = Vector3(at.x, gy + _hover(), at.z)
			_act = {}
			world.arts.stun(self, float(2.5))
			_busy = 0.8


func _leap_tick(t: float, dt: float) -> void:
	var from: Vector3 = _act["from"]
	var gy_from: float = world.island.height_at(from.x, from.z) + _hover()
	var peak := 26.0 + size.y * 0.6
	if t < LEAP_CROUCH:
		# 蹲下去，盯着人
		head.global_position = Vector3(from.x, gy_from - sin(t / LEAP_CROUCH * PI * 0.5) * size.y * 0.08, from.z)
		_face_toward(_peer_pos_or(int(_act["peer"]), _act["at"]), dt * 3.0)
		return
	var at: Vector3 = _act["at"]
	if t < LEAP_LOCK:
		# 起跳：往人头顶上方飞（一次最多跳 60 米）
		if not _act.has("off"):
			_act["off"] = true
			var g0 := Vector3(from.x, world.island.height_at(from.x, from.z), from.z)
			world.fx.slam(g0, size.x * 0.5)
			Sfx.play_at("slam", g0, 6.0, 0.05, 0.6)
		at = _peer_pos_or(int(_act["peer"]), at)
		at = from + Vector3(at.x - from.x, 0, at.z - from.z).limit_length(60.0)
		_act["at"] = at
		var k := (t - LEAP_CROUCH) / (LEAP_LOCK - LEAP_CROUCH)
		var e := 1.0 - pow(1.0 - k, 2.0)
		var p := from.lerp(Vector3(at.x, from.y, at.z), e * 0.7)
		p.y = gy_from + peak * e
		head.global_position = head.global_position.lerp(p, 1.0 - exp(-10.0 * dt))
		_face_toward(at, dt * 3.0)
		return
	if not _act.has("top"):
		# 锁定落点：地上出红圈（1.3 秒后砸下来）
		at = _peer_pos_or(int(_act["peer"]), at)
		at = from + Vector3(at.x - from.x, 0, at.z - from.z).limit_length(60.0)
		at.y = world.island.height_at(at.x, at.z)
		_act["at"] = at
		_act["top"] = head.global_position
		world.arts.circle(at, clampf(size.y * 0.42, 8.0, 11.0), LEAP_LAND - LEAP_LOCK, LEAP_DMG, "rock")
		return
	var top: Vector3 = _act["top"]
	var gy: float = world.island.height_at(at.x, at.z) + _hover()
	if t < LEAP_LAND:
		# 先在空中顿一下（往上飘一点、挪到落点正上方），再猛地砸下来
		var k2 := (t - LEAP_LOCK) / (LEAP_LAND - LEAP_LOCK)
		var hold := clampf(k2 / 0.4, 0.0, 1.0)
		var fall := clampf((k2 - 0.4) / 0.6, 0.0, 1.0)
		var xz := top.lerp(Vector3(at.x, top.y, at.z), 1.0 - pow(1.0 - hold, 2.0))
		var y := top.y + sin(hold * PI * 0.5) * 4.0
		y = lerpf(y, gy, fall * fall)
		head.global_position = Vector3(xz.x, y, xz.z)
		return
	# 落地：圈里的伤害由红圈算；外面再推出去一圈冲击波（跳起来能躲）
	head.global_position = Vector3(at.x, gy, at.z)
	var g := Vector3(at.x, world.island.height_at(at.x, at.z), at.z)
	world.boss_shockwave(g, 34.0, 16.0, 18.0 * world.boss_mult())
	world.fx.slam(g, clampf(size.y * 0.42, 8.0, 11.0) * 1.4)
	world.fx._shake(g, 1.0, 60.0)
	Sfx.play_at("boom", g, 8.0, 0.05, 0.6)
	var again := bool(_act["again"])
	_act = {}
	if again:
		var tp := _pick_target()
		if not tp.is_empty():
			_leap(int(tp["peer"]), tp["pos"], false)
			return
	world.arts.stun(self, 3.0)
	_busy = 1.0


# ------------------------------------------------------------------ 五个 Boss 的招式

func _art_mandala(o: Vector3, t: Vector3, peer: int) -> void:
	var A: BossArts = world.arts
	var yaw := _yaw_to(o, t)
	var opts: Array = [["sweep", 3.0], ["spit", 2.0], ["coil", 2.0], ["dive", 1.5]]
	if phase == 2:
		opts.append_array([["sweep2", 2.5], ["swamp", 2.0]])
	match _pick(opts):
		"sweep":
			var s := 1.0 if randf() < 0.5 else -1.0
			A.sweep(o, yaw - 1.05 * s, yaw + 1.05 * s, 26.0, 0.12, 1.1, 1.0, 28.0, "poison")
			_busy = 2.4
		"sweep2":
			A.sweep(o, yaw - 1.1, yaw + 1.1, 26.0, 0.12, 1.0, 0.9, 28.0, "poison")
			_later(1.6, func(): A.sweep(o, yaw + 1.1, yaw - 1.1, 26.0, 0.12, 0.45, 0.9, 28.0, "poison"))
			_busy = 3.4
		"spit":
			for i in 3:
				_later(i * 0.35 + 0.05, func():
					var q := _peer_pos_or(peer, t) + Vector3(randf_range(-2.0, 2.0), 0, randf_range(-2.0, 2.0))
					world.boss_projectile("spit", _mouth(), q, 1.1, 3.2, 14.0 * world.boss_mult()))
			_busy = 1.8
		"coil":
			# 缠绕：一大圈藤蔓，1.5 秒内冲出去
			A.circle(t, 6.5, 1.5, 30.0, "poison")
			_later(1.45, func(): world.fx.vines(t, 6.5, BossArts.col("poison"), 16))
			_busy = 1.8
		"dive":
			_stun_after = 2.5
			_set_state("dive")
			_busy = 0.5
		"swamp":
			var pts: Array = []
			for i in 6:
				var a := randf() * TAU
				pts.append([t + Vector3(cos(a), 0, sin(a)) * randf_range(0.0, 8.0), 1.0 + i * 0.22])
			A.rain(pts, 3.6, 26.0, "poison")
			_busy = 2.6


func _art_spider(o: Vector3, t: Vector3, peer: int) -> void:
	var A: BossArts = world.arts
	var opts: Array = [["web", 2.5], ["lunge", 3.0], ["drop", 1.6], ["brood", 1.0]]
	if phase == 2:
		opts.append_array([["lunge2", 2.0], ["cage", 1.6]])
	match _pick(opts):
		"web":
			var pts: Array = []
			for i in 7:
				var a := randf() * TAU
				pts.append([t + Vector3(cos(a), 0, sin(a)) * randf_range(0.0, 9.0), 0.8 + i * 0.14])
			A.rain(pts, 2.8, 22.0, "silk")
			_busy = 2.0
		"lunge":
			_lunge(o, t, 0.8, 30.0, 34.0, 5.0, 0.0)
		"lunge2":
			_lunge(o, t, 0.7, 32.0, 34.0, 5.0, 2.0, true)
		"drop":
			_act = {"type": "climb", "t": 0.0, "peer": peer, "at": t}
			_busy = 0.5
		"brood":
			world.boss_summon(self, "spiderling", 2 if phase == 1 else 3)
			A.circle(t, 4.0, 1.2, 22.0, "silk")
			_busy = 1.5
		"cage":
			# 蛛网牢笼：一圈蛛丝砸在身边，只有正中间安全——站着别动
			var pts2: Array = []
			var a0 := randf() * TAU
			for i in 12:
				var a2 := a0 + TAU * i / 12.0
				pts2.append([t + Vector3(cos(a2), 0, sin(a2)) * randf_range(5.5, 8.5), 1.3 + (i % 3) * 0.12])
			A.rain(pts2, 3.4, 30.0, "silk")
			if peer == Net.my_id:
				world.hud.toast("蛛网牢笼——站在正中间别动！", Color(0.95, 0.95, 1.0), 2.0)
			else:
				Net.send(peer, "hint", ["蛛网牢笼——站在正中间别动！"])
			_busy = 2.6


func _art_titan(o: Vector3, t: Vector3, peer: int) -> void:
	var A: BossArts = world.arts
	var opts: Array = [["rocks", 2.5], ["charge", 2.5], ["quake", 2.0], ["fists", 2.5], ["stomp", 2.5]]
	if phase == 2:
		opts.append_array([["rockrain", 2.0], ["charge2", 2.0], ["stomp2", 2.0]])
	var gk := sqrt(_gk)
	match _pick(opts):
		"rocks":
			# 三块石头，节奏不一样：躲完第一块别松劲
			for d in [0.05, 0.6, 1.35]:
				_later(float(d), func():
					var q := _peer_pos_or(peer, t) + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
					world.boss_projectile("rock", _mouth() + Vector3(0, 1, 0), q, 1.1, 3.0, 26.0 * world.boss_mult()))
			_busy = 2.0
		"charge":
			_lunge(o, t, 1.3, 26.0, 45.0, 7.0 * gk, 3.0)
		"charge2":
			_lunge(o, t, 1.1, 30.0, 45.0, 7.0 * gk, 3.0, true)
		"stomp":
			_leap(peer, t, false)
		"stomp2":
			_leap(peer, t, true)
		"quake":
			for i in 3:
				_later(i * 0.8 + 0.05, func(): world.boss_shockwave(o, 36.0, 12.0, 24.0 * world.boss_mult()))
			_busy = 2.8
		"fists":
			# 左右两拳：圈最后 0.4 秒才出来，看它抬手
			var side := Vector3(t.z - o.z, 0, -(t.x - o.x)).normalized()
			A.circle(t + side * 2.5 * gk, 5.0 * gk, 1.2, 40.0, "rock", true)
			A.circle(t - side * 2.5 * gk, 5.0 * gk, 1.75, 40.0, "rock", true)
			_busy = 2.1
		"rockrain":
			var pts: Array = []
			for i in 14:
				var a := randf() * TAU
				pts.append([t + Vector3(cos(a), 0, sin(a)) * randf_range(0.0, 16.0), 0.8 + randf() * 2.2])
			A.rain(pts, 3.0, 30.0, "rock")
			_busy = 3.2


func _art_dragon(o: Vector3, t: Vector3, peer: int) -> void:
	var A: BossArts = world.arts
	var yaw := _yaw_to(o, t)
	var opts: Array = [["breath", 3.0], ["spiral", 2.5], ["swoop", 2.0], ["shards", 2.0]]
	match _pick(opts):
		"breath":
			var s := 1.0 if randf() < 0.5 else -1.0
			A.sweep(o, yaw - 1.2 * s, yaw + 1.2 * s, 38.0, 0.1, 1.3, 1.5, 36.0, "ice")
			_busy = 3.0
		"spiral":
			# 冰锥螺旋：从人脚下往外一圈圈扎出来
			var pts: Array = []
			var a0 := randf() * TAU
			var sgn := 1.0 if randf() < 0.5 else -1.0
			for i in 16:
				var a := a0 + i * 0.75 * sgn
				var rr := 1.5 + i * 0.75
				pts.append([t + Vector3(cos(a), 0, sin(a)) * rr, 0.8 + i * 0.12])
			A.rain(pts, 2.6, 26.0, "ice")
			_busy = 2.8
		"swoop":
			_lunge(o, t, 1.4, 38.0, 48.0, 8.0, 2.5)
		"shards":
			A.chase(peer, 5, 0.45, 3.2, 0.8, 24.0, "ice")
			_busy = 2.8


func _art_whale(o: Vector3, t: Vector3, peer: int) -> void:
	var A: BossArts = world.arts
	var yaw := _yaw_to(o, t)
	var dir := Vector3(t.x - o.x, 0, t.z - o.z).normalized()
	var opts: Array = [["tsunami", 2.0], ["vortex", 1.6], ["breach", 1.6], ["geyser", 2.5]]
	if phase == 2:
		opts.append_array([["gaze", 2.5], ["storm", 1.6]])
	match _pick(opts):
		"tsunami":
			A.wall(t - dir * 38.0, dir, 42.0, 12.0, 70.0, randf_range(-18.0, 18.0), 7.5, 55.0, "water", 1.6)
			_busy = 4.0
		"vortex":
			A.vortex(t.lerp(o, 0.25), 16.0, 6.0, 16.0, 4.5, 30.0, "water")
			A.chase(peer, 3, 0.8, 3.2, 0.9, 28.0, "water")
			_busy = 3.2
		"breach":
			_stun_after = 2.0
			_set_state("dive")
			_busy = 0.5
		"geyser":
			A.chase(peer, 6, 0.4, 3.4, 0.75, 30.0, "water")
			_busy = 2.8
		"gaze":
			var s := 1.0 if randf() < 0.5 else -1.0
			A.sweep(o, yaw - 1.4 * s, yaw + 1.4 * s, 50.0, 0.08, 1.4, 1.8, 50.0, "water")
			_busy = 3.6
		"storm":
			A.wall(t - dir * 38.0, dir, 42.0, 11.0, 70.0, randf_range(-18.0, 18.0), 8.0, 55.0, "water", 1.8)
			_later(1.0, func(): A.chase(peer, 5, 0.5, 3.2, 0.8, 28.0, "water"))
			_busy = 4.5


## 巨猿跃击（朱厌，用户："超级大，跳起来踩到我一脚就掉很多血"）：
## 蹲下蓄力 → 跳上高空、跟着人飘 → 地上出红圈锁定落点 → 砸下来：圈里掉一大半血，外面一圈冲击波（跳起来能躲）→ 露破绽。
## 躲法：看它起跳就往外跑，或者落地那一瞬间翻滚（极限闪避）。again：二阶段落地马上再跳一次，第二次落地才露破绽
const LEAP_CROUCH := 0.8         # 蹲下蓄力
const LEAP_LOCK := 1.9           # 这时锁定落点、出红圈
const LEAP_LAND := 3.2           # 这时砸到地上（红圈给 1.3 秒跑出去）
const LEAP_DMG := 95.0           # 圈里挨一下（招式数，乘章节系数；第三章 55 级大约掉一半血）


## 咆哮动作（出场镜头、暴怒）：没有 roar 动作的模型什么都不做
func roar_anim() -> void:
	if model:
		BeastModels.play_role(model, "roar")


func _leap(peer: int, t: Vector3, again: bool) -> void:
	_act = {"type": "leap", "t": 0.0, "peer": peer, "at": t, "from": head.global_position, "again": again}
	_busy = 0.5
	Sfx.play_at("boss_roar", head.global_position, 6.0, 0.05, 0.7)
	if not _leap_hint:
		_leap_hint = true
		var msg := "它要跳起来踩人了——看地上的红圈跑出去，或者落地那一下翻滚！"
		if peer == Net.my_id:
			world.hud.toast(msg, Color(1.0, 0.75, 0.5), 3.0)
		else:
			Net.send(peer, "hint", [msg])


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
	world.boss_ultimate(c, 32.0, safes, 4.0, 70.0 * world.boss_mult())
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
				# 水面先冒泡（圈），1.3 秒后从水里扑出来
				world.arts.circle(Vector3(pos.x, 0.0, pos.z), 6.5 + size.z * 0.15, 1.3, 30.0 if kind == "mandala" else 52.0, _style())
				_set_state("leap")
		"leap":
			if state_t > 1.2:
				head.global_position = head.global_position.lerp(Vector3(_move_to.x, surf + 1.5, _move_to.z), 1.0 - exp(-6.0 * dt))
			if state_t > 2.4:
				_anchor = Vector3(head.global_position.x, _anchor.y, head.global_position.z)
				_set_state("idle")
				_move_to = _patrol_point()
				# 玄鲲落回水里：两圈浪
				if kind == "whale":
					var hp3 := head.global_position
					world.boss_shockwave(Vector3(hp3.x, 0.0, hp3.z), 40.0, 13.0, 30.0 * world.boss_mult())
					_later(0.7, func(): world.boss_shockwave(Vector3(hp3.x, 0.0, hp3.z), 40.0, 15.0, 30.0 * world.boss_mult()))
				# 扑出来以后搁浅：露破绽
				if _stun_after > 0.0:
					world.arts.stun(self, _stun_after)
					_stun_after = 0.0


func _patrol_point() -> Vector3:
	return _anchor + Vector3(randf_range(-14, 14), 0, randf_range(-8, 8))


func _think_land(dt: float, speed_k: float) -> void:
	var h := head.global_position
	var ground: float = world.island.height_at(h.x, h.z)
	var off := _hover()
	match state:
		"emerge":
			# 从天上 / 树冠上落下来
			head.global_position.y = move_toward(h.y, ground + off, 30.0 * dt)
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
			# 在老窝 30 米内活动；冲锋冲出去了也能走回来
			var nd := Vector3(np.x, 0, np.z).distance_to(c)
			if nd < 30.0 or nd < Vector3(h.x, 0, h.z).distance_to(c):
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
	var airborne := ai == "air" or state == "leap" or str(_act.get("type", "")) == "leap"
	# 跃击：有"起跳砸地"动作的（朱厌）一开始就放，放慢到落地那一下对上砸下来的时间
	if airborne and not _was_air and ai != "air" and model.has_meta("roles") and str((model.get_meta("roles") as Dictionary).get("jump", "")) != "":
		BeastModels.play_role(model, "jump")
		var jap: AnimationPlayer = model.get_meta("ap")
		jap.speed_scale = 0.7
		model.set_meta("busy_until", Time.get_ticks_msec() / 1000.0 + jap.current_animation_length / 0.7 * 0.95)
	_was_air = airborne
	BeastModels._animate_model(model, airborne, _speed, "fly" if ai == "air" else "run")
	# 起手：往后仰、抬起来（前 60% 的时间抬到顶、停住），到点往前一顿
	var lift := 0.0
	if _pose_t > 0.0:
		_pose_t -= dt
		lift = sin(clampf((1.0 - _pose_t / maxf(_pose_dur, 0.01)) * 1.6, 0.0, 1.0) * PI * 0.5)
		if _pose_t <= 0.0:
			_slam_t = 0.3
	elif _slam_t > 0.0:
		_slam_t -= dt
	var fwd := maxf(_slam_t, 0.0) / 0.3
	model.rotation.x = 0.2 * lift - 0.12 * fwd
	# 侧倾每帧从零算：下面踉跄是往上加的，以前带骨骼动作的朱厌不走程序步态、没人归零，
	# 一次破绽累加到几十弧度，之后一直歪着（2026-09-30 用户："朱厌一直是歪着倒着的"）
	model.rotation.z = 0.0
	model.position.y = _model_y0 + size.y * 0.05 * lift
	if _static_model and ai == "land" and dt > 0.0:
		# 程序步态：一步一沉（和下面震地的步子同一个步长）、身子左右晃、跑起来前倾；站着的时候慢慢喘气
		var moving := 0.0 if airborne else clampf(_speed / 6.0, 0.0, 1.0)
		_gait_k = lerpf(_gait_k, moving, 1.0 - exp(-4.0 * dt))
		_gait += _speed * dt / maxf(size.y * 0.3, 0.5) * PI
		var run_k := clampf((_speed - 8.0) / 10.0, 0.0, 1.0)
		var bob := absf(sin(_gait))
		model.position.y += size.y * (0.028 + 0.02 * run_k) * (1.0 - bob) * -_gait_k
		model.rotation.z = sin(_gait) * (0.06 + 0.03 * run_k) * _gait_k
		model.rotation.x += -(0.05 + 0.12 * run_k) * _gait_k
		var breathe := sin(_t * 1.7) * 0.015 * (1.0 - _gait_k)
		model.scale = Vector3(1.0 - breathe * 0.4, 1.0 + breathe, 1.0 - breathe * 0.4)
		model.rotation.y = sin(_t * 0.45) * 0.06 * (1.0 - _gait_k)
	# 破绽（BossArts.stun）：踉跄——往一边歪、低头、慢慢晃、身子沉下去（以前是头上飘"破绽"两个字）
	if stun_vis > 0.0:
		stun_vis = maxf(stun_vis - dt, 0.0)
		var sk := clampf(stun_vis / 0.4, 0.0, 1.0)
		model.rotation.x -= 0.12 * sk
		model.rotation.z += (0.08 + sin(_t * 2.4) * 0.06) * sk
		model.position.y -= size.y * 0.04 * sk
	# 巨兽（朱厌）走路、冲锋：每一步地面一震，近处镜头跟着晃
	if ai == "land" and size.y > 12.0 and not airborne and _speed > 1.0:
		_step_d += _speed * dt
		if _step_d > size.y * 0.3:
			_step_d = 0.0
			var gp := Vector3(p.x, world.island.height_at(p.x, p.z), p.z)
			var run := _speed > 12.0
			world.fx._shake(gp, 0.3 if run else 0.16, 60.0 if run else 50.0)
			Sfx.play_at("thud", gp, 6.0 if run else 4.0, 0.1, 0.45)
			if run:
				world.fx.slam(gp, 4.0)
	for b in parts:
		b.global_transform = head.global_transform * Transform3D(Basis(), b.get_meta("offset") as Vector3)
	# 灵环、光轮、光柱
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
