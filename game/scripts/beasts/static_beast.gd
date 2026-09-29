class_name StaticBeast
extends RefCounted
## AI 生成的灵兽模型（混元，assets/models/beasts/beast_<物种>.glb）：**没有骨骼**，动作全靠顶点着色器按部位摆
## （2026-09-29，大号交接第 8 节："鱼蛇摆动、鸟扇翅、兔蟾跳、四条腿的腿前后摆"）：
##   quad 四条腿：下面四成是腿，按前后、左右分成四条，对角步（左前右后同步）绕髋 / 肩前后摆；空中前腿前伸后腿后蹬；
##                身子一起一伏、尾巴左右甩、头点一点；扑咬时前半身往前一冲
##   hop 跳的（兔、蟾）：耳朵晃、空中耳朵往后贴、后腿蹬直、身子拉长
##   swim 游的 / 爬的（鱼、蛇、藤）：整条身子从头到尾一道横波，越往尾巴摆得越大
##   flap 飞的（鸟、蛾、蝠、鳐）：两侧（翅膀）绕身体中线上下扇
## 模型本身的颜色 / 法线 / ORM 贴图照用；挨打闪红。
## 每只灵兽的动作参数是 instance uniform（步态相位、步幅、在不在空中、扑咬、挨打），一个物种共用一个材质。

const DIR := "res://assets/models/beasts/"
## 模型朝哪边（转多少让头朝 -Z）、用哪种动作
const FIT := {
	"wolf": {"yaw": PI / 2, "rig": "quad"},
	"rabbit": {"yaw": PI, "rig": "hop"},
}
const RIGS := {"quad": 0, "hop": 1, "swim": 2, "flap": 3}

const SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic;
uniform float has_normal = 0.0;
uniform float has_orm = 0.0;
uniform vec3 c0 = vec3(0.0);      // 身体中心（网格坐标）
uniform vec3 fwd = vec3(0.0, 0.0, -1.0);
uniform vec3 up = vec3(0.0, 1.0, 0.0);
uniform float half_len = 1.0;     // 头到尾的一半
uniform float hmin = -0.5;        // 最低点（沿 up，相对中心）
uniform float hgt = 1.0;          // 高度
uniform int rig = 0;
instance uniform float gait = 0.0;
instance uniform float amp = 0.0;
instance uniform float air = 0.0;
instance uniform float lunge = 0.0;
instance uniform float hurt = 0.0;
instance uniform float t = 0.0;

void vertex() {
	vec3 p = VERTEX;
	vec3 side = normalize(cross(up, fwd));
	vec3 r = p - c0;
	float along = dot(r, fwd) / half_len;
	float y = dot(r, up);
	float h = (y - hmin) / hgt;
	float lat = dot(r, side);
	if (rig == 0) {
		// 四条腿
		float legw = 1.0 - smoothstep(0.26, 0.46, h);
		float front = step(0.0, along);
		float ph = gait + front * PI + (lat > 0.0 ? PI : 0.0);
		float ang = sin(ph) * amp * 0.6;
		ang = mix(ang, mix(-0.6, 0.6, front), air);
		float dy = y - (hmin + hgt * 0.5);
		p += (fwd * (-dy * sin(ang)) + up * (dy * (cos(ang) - 1.0))) * legw;
		// 迈步时脚抬一点（往前摆的那半程）
		p += up * max(sin(ph + 1.57), 0.0) * amp * hgt * 0.06 * legw * (1.0 - air);
		p += up * abs(sin(gait)) * amp * hgt * 0.035;
		// 尾巴
		float tailw = (1.0 - smoothstep(-0.85, -0.5, along)) * smoothstep(0.3, 0.5, h);
		float td = max(-0.5 - along, 0.0) * half_len;
		p += side * sin(t * 6.0 + gait * 0.5) * td * 0.4 * tailw * (1.0 - amp * 0.4);
		p += up * td * 0.25 * tailw * (air - amp * 0.3);
		// 头：点头；扑咬时前半身往前一冲、头抬一下
		float headw = smoothstep(0.5, 0.85, along);
		p += up * sin(gait * 2.0) * amp * hgt * 0.035 * headw;
		p += up * sin(t * 1.3) * hgt * 0.012 * headw * (1.0 - amp);
		float lw = smoothstep(-0.4, 1.0, along);
		p += fwd * lunge * half_len * 0.35 * lw;
		p += up * lunge * hgt * 0.08 * headw;
	} else if (rig == 1) {
		// 跳的：耳朵（头上面）晃、空中往后贴
		float earw = smoothstep(0.6, 0.78, h) * smoothstep(-0.2, 0.2, along);
		float ed = max(y - (hmin + hgt * 0.6), 0.0);
		p += -fwd * ed * (0.18 * sin(t * 8.0) * (1.0 - air) + 0.8 * air) * earw;
		p += side * ed * 0.08 * sin(t * 5.0 + lat * 20.0) * earw;
		// 后腿：空中蹬直
		float hindw = (1.0 - smoothstep(0.15, 0.4, h)) * (1.0 - smoothstep(-0.25, 0.15, along));
		p += -fwd * air * half_len * 0.45 * hindw - up * air * hgt * 0.06 * hindw;
		// 前爪：空中往前伸
		float forew = (1.0 - smoothstep(0.1, 0.3, h)) * smoothstep(0.1, 0.4, along);
		p += fwd * air * half_len * 0.2 * forew;
		// 身子：空中拉长，快要落地时压扁；鼻子抽动
		p += fwd * along * half_len * 0.14 * air;
		p += up * (y - hmin) * (-0.08 * amp * (1.0 - air));
		p += fwd * sin(t * 18.0) * half_len * 0.006 * smoothstep(0.8, 1.0, along);
		p += fwd * lunge * half_len * 0.3 * smoothstep(-0.3, 1.0, along);
	} else if (rig == 2) {
		// 游 / 爬：头到尾一道横波
		float k = 0.5 - along * 0.5;
		p += side * sin(t * 6.0 - along * 5.0 + gait) * half_len * (0.04 + 0.12 * k * k) * (0.6 + amp * 0.6);
		p += fwd * lunge * half_len * 0.35 * smoothstep(-0.3, 1.0, along);
	} else {
		// 扇翅：离中线越远上下摆得越多
		float wing = abs(lat) / half_len;
		p += up * sin(t * 14.0 + gait) * wing * half_len * (0.2 + air * 0.35) * smoothstep(0.1, 0.4, wing);
		p += fwd * lunge * half_len * 0.3 * smoothstep(-0.3, 1.0, along);
	}
	VERTEX = p;
}

void fragment() {
	vec4 a = texture(albedo_tex, UV);
	ALBEDO = mix(a.rgb, vec3(1.0, 0.3, 0.25), hurt * 0.45);
	if (has_orm > 0.5) {
		vec3 o = texture(orm_tex, UV).rgb;
		AO = o.r;
		ROUGHNESS = o.g;
		METALLIC = o.b;
	} else {
		ROUGHNESS = 0.8;
	}
	if (has_normal > 0.5) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
	EMISSION = vec3(1.0, 0.25, 0.15) * hurt * 0.35;
}
"""

static var _shader: Shader
static var _mats := {}


static func path(species: String) -> String:
	var p := DIR + "beast_" + species + ".glb"
	return p if FIT.has(species) and ResourceLoader.exists(p) else ""


## 做一个灵兽模型：按 cfg 的 fit / size 缩放、居中（原点 = 身体中心，和 Quaternius 模型一样）、头朝 -Z
static func build(species: String, cfg: Dictionary) -> Node3D:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var fit: Dictionary = FIT[species]
	var inst := (load(path(species)) as PackedScene).instantiate() as Node3D
	var holder := Node3D.new()
	holder.name = "Static"
	holder.add_child(inst)
	inst.rotation.y = float(fit["yaw"])
	var box := AABB()
	var first := true
	var mis: Array = []
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		mis.append(mi)
		var bb := BeastModels._local_xform(holder, mi) * mi.mesh.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	var dim: float = {"w": box.size.x, "h": box.size.y, "l": box.size.z}.get(str(cfg.get("fit", "l")), box.size.z)
	var k := float(cfg.get("size", 1.0)) / maxf(dim, 0.001)
	inst.scale = Vector3.ONE * k
	inst.position = -box.get_center() * k
	# 每个网格：把"头朝哪、哪边朝上"换算到网格自己的坐标里
	var rig := int(RIGS[str(fit["rig"])])
	for i in mis.size():
		var mi: MeshInstance3D = mis[i]
		var xf := BeastModels._local_xform(holder, mi)
		var inv := xf.basis.inverse()
		var f := (inv * Vector3(0, 0, -1)).normalized()
		var u := (inv * Vector3.UP).normalized()
		var ab := mi.mesh.get_aabb()
		var c := ab.get_center()
		var hl := 0.0
		var lo := INF
		var hi := -INF
		for ci in 8:
			var corner := ab.get_endpoint(ci) - c
			hl = maxf(hl, absf(corner.dot(f)))
			lo = minf(lo, corner.dot(u))
			hi = maxf(hi, corner.dot(u))
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s) as BaseMaterial3D
			var key := "%s|%d|%d" % [species, i, s]
			var m: ShaderMaterial = _mats.get(key)
			if m == null:
				m = ShaderMaterial.new()
				m.shader = _shader
				if src:
					m.set_shader_parameter("albedo_tex", src.albedo_texture)
					if src.normal_texture:
						m.set_shader_parameter("normal_tex", src.normal_texture)
						m.set_shader_parameter("has_normal", 1.0)
					var orm: Texture2D = src.roughness_texture if src.roughness_texture else src.metallic_texture
					if orm:
						m.set_shader_parameter("orm_tex", orm)
						m.set_shader_parameter("has_orm", 1.0)
				m.set_shader_parameter("c0", c)
				m.set_shader_parameter("fwd", f)
				m.set_shader_parameter("up", u)
				m.set_shader_parameter("half_len", maxf(hl, 0.001))
				m.set_shader_parameter("hmin", lo)
				m.set_shader_parameter("hgt", maxf(hi - lo, 0.001))
				m.set_shader_parameter("rig", rig)
				_mats[key] = m
			mi.set_surface_override_material(s, m)
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	holder.set_meta("mis", mis)
	holder.set_meta("gait", randf() * TAU)
	holder.set_meta("last_t", -1.0)
	holder.set_meta("air", 0.0)
	return holder


## 每帧（BeastModels.animate 调）：步态相位按速度走，在不在空中平滑过渡，扑咬、挨打慢慢退
static func animate(holder: Node3D, t: float, airborne: bool, speed: float, rig: String) -> void:
	var last := float(holder.get_meta("last_t", -1.0))
	var dt := clampf(t - last, 0.0, 0.1) if last >= 0.0 else 0.0
	holder.set_meta("last_t", t)
	var freq := 2.2 if rig == "quad" else 1.6
	var gait := float(holder.get_meta("gait", 0.0)) + dt * (freq + speed * 1.7)
	holder.set_meta("gait", gait)
	var amp := clampf(speed / 5.0, 0.0, 1.2)
	var air := move_toward(float(holder.get_meta("air", 0.0)), 1.0 if airborne else 0.0, dt * 6.0)
	holder.set_meta("air", air)
	var now := Time.get_ticks_msec() / 1000.0
	var lunge := 0.0
	var ls := float(holder.get_meta("lunge_at", -9.0))
	if now - ls < 0.5:
		var k := (now - ls) / 0.5
		lunge = sin(k * PI) * (1.0 if k < 0.5 else 0.8)
	var hurt := clampf(1.0 - (now - float(holder.get_meta("hurt_at", -9.0))) / 0.18, 0.0, 1.0)
	for mi in holder.get_meta("mis", []):
		var gi := mi as GeometryInstance3D
		gi.set_instance_shader_parameter("gait", gait)
		gi.set_instance_shader_parameter("amp", amp)
		gi.set_instance_shader_parameter("air", air)
		gi.set_instance_shader_parameter("lunge", lunge)
		gi.set_instance_shader_parameter("hurt", hurt)
		gi.set_instance_shader_parameter("t", t)


static func attack(holder: Node3D) -> void:
	holder.set_meta("lunge_at", Time.get_ticks_msec() / 1000.0)


static func hurt(holder: Node3D) -> void:
	holder.set_meta("hurt_at", Time.get_ticks_msec() / 1000.0)
