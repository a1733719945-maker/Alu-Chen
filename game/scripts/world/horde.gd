class_name Horde
extends Node3D
## 僵尸群（试炼用：尸潮守关、万兽割草）。几百只的时候刚体灵兽会卡，这里自己算位置、一个 MultiMesh 画出来。
##
## 样子：清朝官服的跳尸——长袍、补子、马蹄袖伸得笔直、官帽、额头上贴一张黄符、眼睛冒绿光，一蹦一蹦往前跳。
## 种类 kind：0 小尸（割草：一打就死）、1 跳尸（守关：几枪）、2 铁尸（大一圈、血厚、慢）、3 尸王（很大，砸地）
##
## 联机：房主决定出哪些（hdsp：[[id, x, z, kind, hp], ...]），每台电脑自己算它们怎么跳
##   （目标都是"最近的人 / 阵眼"，大家看到的差不多）；谁打中了发 hdhit [[id, 伤害, 是谁打的], ...]，
##   每台电脑扣一样的血，扣到 0 就死；是自己那一下打死的，算自己的击杀。
##   咬人：每台电脑只算咬没咬到自己；砸阵眼：只有房主算。

signal killed(id: int, peer: int, kind: int, pos: Vector3)

const MAX := 360
const SCALE := [0.9, 1.0, 1.3, 2.6]
const STEP := [1.5, 1.25, 1.0, 1.7]        # 一跳多远
const HOP := [0.36, 0.46, 0.58, 0.8]       # 一跳多久
const REST := [0.05, 0.14, 0.2, 0.35]      # 落地歇多久
const HOP_H := [0.4, 0.45, 0.4, 0.9]
const TINT := [Color(0.34, 0.4, 0.36), Color(0.14, 0.2, 0.36), Color(0.36, 0.28, 0.18), Color(0.55, 0.08, 0.08)]
const ATK_CD := [0.9, 1.1, 1.4, 2.5]
const BITE_K := [0.035, 0.06, 0.09, 0.0]   # 咬一口掉最大体力的多少

var world: World
var trial: Node
var center := Vector3.ZERO                 # 场地中间（地面高度 center.y）
var radius := 30.0
var goal := Vector3.INF                    # 守关：阵眼（没人在身边就去砸它）
var goal_r := 2.6
var chase_r := 1e9                         # 多近的人会被追（守关 9 米；割草追最近的人）
var obstacles: Array = []                  # [[Vector2 中心, 半径], ...]
var dmg_k := 1.0                           # 咬人加成（守关后面几波）
var core_dmg := 10.0                       # 砸阵眼一下
var units: Array = []                      # 活着的：{"id","p","hp","max","kind","from","to","t","len","rest","cd","yaw","hurt"}
var by_id := {}
var next_id := 1
var _mm: MultiMesh
var _fx_budget := 0


func _ready() -> void:
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = _build_mesh()
	_mm.instance_count = MAX
	_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = SHADER
	mmi.material_override = m
	add_child(mmi)
	# 包围盒要大（MultiMesh 按整体剔除）
	mmi.custom_aabb = AABB(Vector3(-2000, -100, -2000), Vector3(4000, 1000, 4000))
	FxLib.no_decals(mmi)


func alive_count() -> int:
	return units.size()


func clear() -> void:
	units.clear()
	by_id.clear()
	_mm.visible_instance_count = 0


# ------------------------------------------------------------------ 出生 / 挨打 / 死

## 房主用：发 hdsp，大家一起出
func host_spawn(list: Array) -> void:
	for e in list:
		e[0] = next_id
		next_id += 1
	Net.send(0, "hdsp", list)
	spawn(list)


func spawn(list: Array) -> void:
	for e in list:
		var id := int(e[0])
		if by_id.has(id) or units.size() >= MAX:
			continue
		next_id = maxi(next_id, id + 1)
		var p := Vector3(float(e[1]), center.y, float(e[2]))
		var k := int(e[3])
		var u := {"id": id, "p": p, "hp": float(e[4]), "max": float(e[4]), "kind": k, "from": p, "to": p, "t": 0.0,
			"len": HOP[k], "rest": randf() * 0.4, "cd": 1.0, "yaw": randf() * TAU, "hurt": 0.0, "ph": randf()}
		units.append(u)
		by_id[id] = u
		if _fx_budget < 6 and world.player.global_position.distance_to(p) < 60.0:
			_fx_budget += 1
			world.fx._smoke(p + Vector3.UP * 0.3, Color(0.3, 0.45, 0.35, 0.55), 5, 1.5, 0.8, 1.2, 0.4)


## 大家都调：同样的伤害（hdhit）。自己那一下打死的算自己的
func apply_hits(list: Array) -> void:
	for e in list:
		var u: Dictionary = by_id.get(int(e[0]), {})
		if u.is_empty():
			continue
		u["hp"] = float(u["hp"]) - float(e[1])
		u["hurt"] = 1.0
		if float(u["hp"]) <= 0.0:
			_die(u, int(e[2]))


func _die(u: Dictionary, peer: int) -> void:
	units.erase(u)
	by_id.erase(int(u["id"]))
	var p: Vector3 = u["p"]
	var s: float = SCALE[int(u["kind"])]
	if _fx_budget < 10 and world.player.global_position.distance_to(p) < 70.0:
		_fx_budget += 1
		world.fx._flash(p + Vector3.UP * s, Color(0.5, 1.0, 0.6), 1.4 * s, 0.12)
		world.fx._smoke(p + Vector3.UP * 0.8 * s, Color(0.35, 0.5, 0.4, 0.6), 4, 2.0, 0.8, 1.1 * s, 0.6)
		world.fx._sparks(p + Vector3.UP * 1.6 * s, Vector3.UP, Color(1.0, 0.85, 0.3), 6, 4.0, 0.6, 0.05, -6.0, 90.0)
	killed.emit(int(u["id"]), peer, int(u["kind"]), p)


# ------------------------------------------------------------------ 打中了谁

## 一条射线（开枪）：从近到远打到的 [[id, 距离, 是不是打头], ...]
func ray_hits(from: Vector3, to: Vector3, max_n: int) -> Array:
	var out: Array = []
	var d := to - from
	var len := d.length()
	if len < 0.01:
		return out
	var dir := d / len
	for u in units:
		var s: float = SCALE[int(u["kind"])]
		var base: Vector3 = u["p"]
		var a := base + Vector3.UP * 0.25 * s
		var b := base + Vector3.UP * 1.75 * s
		var r := 0.42 * s
		# 射线和竖着的胶囊：先粗筛（离射线太远的跳过）
		var rel := base + Vector3.UP * s - from
		var along := rel.dot(dir)
		if along < -1.0 or along > len + 1.0:
			continue
		if (rel - dir * along).length() > 1.2 * s + r:
			continue
		var cp := _seg_closest(from, to, a, b)
		if cp[0] <= r:
			var hit_y: float = (cp[2] as Vector3).y
			out.append([int(u["id"]), float(cp[1]) * len, hit_y > base.y + 1.45 * s])
	out.sort_custom(func(x, y): return x[1] < y[1])
	if out.size() > max_n:
		out.resize(max_n)
	return out


## 两条线段最近的距离：[距离, 在第一条上的比例 0~1, 第二条上最近的点]
static func _seg_closest(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> Array:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	var c := d1.dot(r)
	var b := d1.dot(d2)
	var den := a * e - b * b
	if den > 1e-6:
		s = clampf((b * f - c * e) / den, 0.0, 1.0)
	t = (b * s + f) / e
	if t < 0.0:
		t = 0.0
		s = clampf(-c / a, 0.0, 1.0)
	elif t > 1.0:
		t = 1.0
		s = clampf((b - c) / a, 0.0, 1.0)
	var c1 := p1 + d1 * s
	var c2 := p2 + d2 * t
	return [c1.distance_to(c2), s, c2]


## 一个圈里的（爆炸、神通、灵爆）
func in_sphere(c: Vector3, r: float) -> Array:
	var out: Array = []
	for u in units:
		var p: Vector3 = u["p"]
		var s: float = SCALE[int(u["kind"])]
		if Vector2(p.x - c.x, p.z - c.z).length() < r + 0.4 * s and absf(p.y + s - c.y) < r + 2.0 * s:
			out.append(int(u["id"]))
	return out


## 一条带子里的（光束、冲刺）
func in_beam(o: Vector3, dir: Vector3, length: float, width: float) -> Array:
	var out: Array = []
	dir = Vector3(dir.x, 0, dir.z).normalized()
	for u in units:
		var rel: Vector3 = (u["p"] as Vector3) - o
		rel.y = 0.0
		var along := rel.dot(dir)
		if along < 0.0 or along > length:
			continue
		if (rel - dir * along).length() < width + 0.4 * SCALE[int(u["kind"])]:
			out.append(int(u["id"]))
	return out


func pos_of(id: int) -> Vector3:
	var u: Dictionary = by_id.get(id, {})
	return u["p"] if not u.is_empty() else Vector3.INF


# ------------------------------------------------------------------ 每帧：跳、咬、画

func _process(dt: float) -> void:
	_fx_budget = 0
	if units.is_empty():
		_mm.visible_instance_count = 0
		return
	var pls: Array = world.alive_players()
	var me: Vector3 = world.player.global_position
	var me_ok: bool = not world.player.dead and not world.player.untargetable()
	var host := Net.is_host()
	# 挤在一起的推开：按 2 米一格分桶
	var grid := {}
	for i in units.size():
		var p: Vector3 = units[i]["p"]
		var key := Vector2i(floori(p.x / 2.0), floori(p.z / 2.0))
		if not grid.has(key):
			grid[key] = []
		grid[key].append(i)
	var n := 0
	for i in units.size():
		var u: Dictionary = units[i]
		var k := int(u["kind"])
		var s: float = SCALE[k]
		u["cd"] = float(u["cd"]) - dt
		u["hurt"] = maxf(float(u["hurt"]) - dt * 4.0, 0.0)
		var p: Vector3 = u["p"]
		# 目标：身边有人追人，没有就去砸阵眼（割草：追最近的人）
		var tgt := goal
		var bd := chase_r
		for pl in pls:
			var q: Vector3 = pl["pos"]
			var dd := Vector2(q.x - p.x, q.z - p.z).length()
			if dd < bd:
				bd = dd
				tgt = q
		if tgt == Vector3.INF and not pls.is_empty():
			tgt = pls[0]["pos"]
		# 跳：落地歇一下 → 选下一个落点 → 抛物线跳过去
		var t := float(u["t"]) + dt
		if t >= float(u["len"]):
			var rest := float(u["rest"]) - dt
			u["rest"] = rest
			p = u["to"]
			if rest <= 0.0 and tgt != Vector3.INF:
				var to := Vector3(tgt.x - p.x, 0, tgt.z - p.z)
				var dist := to.length()
				var stop := (goal_r + 0.6 * s) if tgt == goal else (0.6 + 0.35 * s)
				var step := minf(float(STEP[k]) * randf_range(0.85, 1.15), maxf(dist - stop, 0.0))
				var dir := to / maxf(dist, 0.01)
				dir = dir.rotated(Vector3.UP, sin(float(u["ph"]) * 9.0 + t) * 0.25)
				var nxt := p + dir * step
				nxt = _push_out(nxt, s)
				u["from"] = p
				u["to"] = nxt
				u["t"] = 0.0
				u["len"] = float(HOP[k]) * randf_range(0.9, 1.1)
				u["rest"] = float(REST[k]) * randf_range(0.6, 1.4)
				if dist > 0.3:
					u["yaw"] = atan2(-to.x, -to.z)
				t = 0.0
			else:
				u["t"] = t
		else:
			u["t"] = t
		var kk := clampf(t / float(u["len"]), 0.0, 1.0)
		var from: Vector3 = u["from"]
		var to2: Vector3 = u["to"]
		p = from.lerp(to2, kk)
		# 分开：同一格和旁边格里的往外推一点
		var sep := Vector3.ZERO
		var key2 := Vector2i(floori(p.x / 2.0), floori(p.z / 2.0))
		for gx in 3:
			for gz in 3:
				var cell: Array = grid.get(key2 + Vector2i(gx - 1, gz - 1), [])
				for j in cell:
					if j == i:
						continue
					var o: Vector3 = units[j]["p"]
					var dv := Vector3(p.x - o.x, 0, p.z - o.z)
					var dl := dv.length()
					var want := 0.55 * (s + float(SCALE[int(units[j]["kind"])]))
					if dl < want and dl > 0.001:
						sep += dv / dl * (want - dl)
		if sep != Vector3.ZERO:
			var push := sep.limit_length(0.5) * minf(dt * 8.0, 1.0)
			u["from"] = from + push
			u["to"] = to2 + push
			p += push
		p.y = center.y
		u["p"] = p
		# 咬自己（每台电脑只算自己）
		if me_ok and float(u["cd"]) <= 0.0 and k < 3:
			var md := Vector2(me.x - p.x, me.z - p.z).length()
			if md < 0.75 + 0.45 * s and absf(me.y - p.y) < 2.2 * s:
				u["cd"] = float(ATK_CD[k])
				world.player.take_damage(Profile.max_hp() * float(BITE_K[k]) * dmg_k, p)
				Sfx.play_at("bite", p, -4.0, 0.15, 0.8)
		# 砸阵眼（房主算）
		if host and goal != Vector3.INF and float(u["cd"]) <= 0.0 and trial:
			if Vector2(goal.x - p.x, goal.z - p.z).length() < goal_r + 0.9 * s:
				u["cd"] = float(ATK_CD[k])
				trial.host_core_hit(core_dmg * (1.0 + k * 0.8), p)
		# 画：跳起来的高度、往前倾、落地压扁
		var hop := sin(kk * PI)
		var y := p.y + hop * float(HOP_H[k]) * s
		var squash := 0.0
		if float(u["t"]) >= float(u["len"]):
			squash = 0.12
		var bs := Basis(Vector3.UP, float(u["yaw"])) * Basis(Vector3.RIGHT, -0.12 * hop)
		bs = bs.scaled(Vector3(s * (1.0 + squash), s * (1.0 - squash + 0.06 * hop), s * (1.0 + squash)))
		_mm.set_instance_transform(n, Transform3D(bs, Vector3(p.x, y, p.z)))
		_mm.set_instance_color(n, TINT[k])
		_mm.set_instance_custom_data(n, Color(float(u["ph"]), hop, float(u["hurt"]), float(k)))
		n += 1
	_mm.visible_instance_count = n


## 推出障碍物、留在场地里
func _push_out(p: Vector3, s: float) -> Vector3:
	for o in obstacles:
		var c: Vector2 = o[0]
		var r := float(o[1]) + 0.35 * s
		var d := Vector2(p.x - c.x, p.z - c.y)
		if d.length() < r:
			var v := d.normalized() * r if d.length() > 0.01 else Vector2(r, 0)
			p = Vector3(c.x + v.x, p.y, c.y + v.y)
	var off := Vector2(p.x - center.x, p.z - center.z)
	if off.length() > radius - 1.0:
		off = off.normalized() * (radius - 1.0)
		p = Vector3(center.x + off.x, p.y, center.z + off.y)
	return p


# ------------------------------------------------------------------ 模型（程序拼的一只跳尸，UV.x 记是哪个部件）

const PART_ROBE := 0.0
const PART_SKIN := 1.0
const PART_TALISMAN := 2.0
const PART_EYE := 3.0
const PART_HAT := 4.0
const PART_GOLD := 5.0

const SHADER := """shader_type spatial;
varying vec3 tint;
varying vec4 cd;
varying float part;
void vertex() {
	tint = COLOR.rgb;
	cd = INSTANCE_CUSTOM;
	part = UV.x;
	// 两只手随着跳上下晃一点；袍子下摆往后飘
	if (part < 0.5 && VERTEX.y < 0.4) { VERTEX.z += cd.y * 0.08; }
	if (VERTEX.z < -0.35 && VERTEX.y > 1.2) { VERTEX.y += sin(TIME * 6.0 + cd.x * 30.0) * 0.03 - cd.y * 0.06; }
}
void fragment() {
	vec3 c = tint;
	float rough = 0.85;
	float metal = 0.0;
	vec3 em = vec3(0.0);
	if (part > 0.5 && part < 1.5) { c = vec3(0.5, 0.6, 0.5); rough = 0.7; }
	else if (part > 1.5 && part < 2.5) {
		c = vec3(0.95, 0.78, 0.22);
		// 黄符上的朱砂字：几道横竖
		float s1 = step(0.45, fract(UV.y * 5.0)) * step(fract(UV.y * 5.0), 0.6);
		c = mix(c, vec3(0.75, 0.08, 0.05), s1 * 0.8);
		em = vec3(0.35, 0.25, 0.02);
	}
	else if (part > 2.5 && part < 3.5) { c = vec3(0.05); em = vec3(0.4, 1.0, 0.45) * 4.0; }
	else if (part > 3.5 && part < 4.5) { c = vec3(0.04, 0.04, 0.05); rough = 0.5; }
	else if (part > 4.5) { c = vec3(0.85, 0.62, 0.22); rough = 0.35; metal = 0.8; }
	// 袍子：上身亮一点、下摆暗一点（光从上面来）
	if (part < 0.5) { c *= 0.8 + 0.25 * (1.0 - UV.y); }
	ALBEDO = c;
	ROUGHNESS = rough;
	METALLIC = metal;
	// 挨打：红光一闪；尸王身上一层暗红
	EMISSION = em + vec3(1.0, 0.35, 0.2) * cd.z * 1.6 + (cd.w > 2.5 && part < 0.5 ? vec3(0.25, 0.02, 0.02) : vec3(0.0));
}
"""


func _build_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 长袍（下宽上窄）+ 下摆金边 + 上身 + 胸前补子
	_add(st, U.cyl(0.25, 0.36, 1.05, 12), Transform3D(Basis(), Vector3(0, 0.53, 0)), PART_ROBE)
	_add(st, U.cyl(0.365, 0.37, 0.06, 12), Transform3D(Basis(), Vector3(0, 0.05, 0)), PART_GOLD)
	_add(st, U.cyl(0.24, 0.27, 0.45, 12), Transform3D(Basis(), Vector3(0, 1.26, 0)), PART_ROBE)
	_add(st, U.box(Vector3(0.26, 0.26, 0.02)), Transform3D(Basis(), Vector3(0, 1.2, -0.255)), PART_GOLD)
	_add(st, U.box(Vector3(0.2, 0.2, 0.025)), Transform3D(Basis(), Vector3(0, 1.2, -0.26)), PART_ROBE)
	# 宽肩、立领、前襟一道金边（从领口一直到下摆）
	_add(st, U.sphere(0.3, 12, 8), Transform3D(Basis().scaled(Vector3(1.25, 0.42, 0.85)), Vector3(0, 1.45, 0)), PART_ROBE)
	_add(st, U.cyl(0.12, 0.14, 0.09, 12), Transform3D(Basis(), Vector3(0, 1.53, 0)), PART_GOLD)
	_add(st, U.box(Vector3(0.05, 1.05, 0.02)), Transform3D(Basis(Vector3.RIGHT, -0.1), Vector3(0, 0.55, -0.31)), PART_GOLD)
	# 两只手伸得笔直（马蹄袖）+ 发青的手
	for sx in [-0.17, 0.17]:
		var arm := Basis(Vector3.RIGHT, PI * 0.5)
		_add(st, U.cyl(0.075, 0.1, 0.62, 8), Transform3D(arm, Vector3(sx, 1.38, -0.3)), PART_ROBE)
		_add(st, U.cyl(0.1, 0.1, 0.05, 8), Transform3D(arm, Vector3(sx, 1.38, -0.6)), PART_GOLD)
		_add(st, U.box(Vector3(0.09, 0.05, 0.16)), Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(sx, 1.36, -0.7)), PART_SKIN)
	# 头、官帽（帽檐 + 帽身 + 顶珠）、黄符、绿眼睛
	_add(st, U.sphere(0.155, 12, 8), Transform3D(Basis().scaled(Vector3(0.95, 1.1, 0.95)), Vector3(0, 1.63, 0)), PART_SKIN)
	_add(st, U.cyl(0.25, 0.25, 0.03, 16), Transform3D(Basis(), Vector3(0, 1.76, 0)), PART_HAT)
	_add(st, U.cyl(0.17, 0.2, 0.13, 16), Transform3D(Basis(), Vector3(0, 1.83, 0)), PART_HAT)
	_add(st, U.sphere(0.045, 8, 6), Transform3D(Basis(), Vector3(0, 1.92, 0)), PART_GOLD)
	_add(st, U.box(Vector3(0.14, 0.32, 0.006)), Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(0, 1.6, -0.172)), PART_TALISMAN)
	for sx in [-0.055, 0.055]:
		_add(st, U.sphere(0.022, 6, 4), Transform3D(Basis(), Vector3(sx, 1.66, -0.135)), PART_EYE)
	# 一条辫子垂在背后
	_add(st, U.cyl(0.02, 0.035, 0.5, 6), Transform3D(Basis(Vector3.RIGHT, -0.15), Vector3(0, 1.38, 0.17)), PART_HAT)
	return st.commit()


## 把一个基本网格按 xf 摆好加进来；UV.x = 部件，UV.y 保留原来的 v（符纸上的字、袍子暗纹用）
func _add(st: SurfaceTool, mesh: Mesh, xf: Transform3D, part: float) -> void:
	var arr := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var nb := xf.basis.inverse().transposed()
	var order: PackedInt32Array = idx
	if order.is_empty():
		order = PackedInt32Array(range(verts.size()))
	for i in order:
		st.set_uv(Vector2(part, uvs[i].y if i < uvs.size() else 0.0))
		if i < norms.size():
			st.set_normal((nb * norms[i]).normalized())
		st.add_vertex(xf * verts[i])
