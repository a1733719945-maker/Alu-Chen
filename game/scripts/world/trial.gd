class_name Trial
extends Node
## 试炼（用户："每一关和秘境都是同一个玩法……多加入一些模式，类似 CF 打僵尸……在地上捡武器，然后守在什么地方；
## 还有割草模式，到处都是怪物，但是一打全死那种感觉"）。
##
## 码头边一块试炼碑（地图上「试」），按 F 选一种，队友从同一块碑随时加入：
##   尸潮守关 siege：一座围起来的古堡，中间是镇尸的阵眼。僵尸（Horde，清朝官服的跳尸）一波一波从四个尸门跳进来，
##     身边有人就扑人，没人就去砸阵眼——阵眼碎了就输。地上六个兵器架，每波换一批暗器（品质越高伤害越高），
##     谁都能捡（出了试炼就还回去）；每五波一只尸王（砸地，看红圈）。能撑几波记下来。
##   万兽割草 musou：一大片荒原，满地都是小尸，一打就死；三分钟看能斩多少。斩一只攒一格「灵爆」，
##     攒满按 Z：身边一圈全清。记最多斩数。
## 场地在地图外面的高空（跟秘境一样，Island.add_floor 让地面高度在这里也对）。同一时间只有一局。
##
## 联机：房主管一局；trst 同步状态，进 trenter / 传送 trin / 离开 trleave / 结束 trend（带结算），
##   兵器架 trrack，阵眼挨打 trcore，尸王砸地走 World.boss_telegraph；僵尸的出生 / 挨打走 Horde（hdsp / hdhit）。

const SIEGE := Vector3(-900.0, 420.0, 0.0)
const SIEGE_R := 36.0
const MUSOU := Vector3(0.0, 420.0, -900.0)
const MUSOU_R := 62.0
const MUSOU_TIME := 180.0
const CORE_HP := 1000.0
const CORE_R := 2.6
const PREP := 8.0
const BREAK := 10.0
const BURST_NEED := 60             # 割草：斩多少只攒满一次灵爆
const BURST_R := 15.0
const MODES := {
	"siege": {"name": "尸潮守关", "kick": "守住阵眼", "color": Color(0.45, 1.0, 0.55),
		"desc": "僵尸一波一波跳进古堡，守住中间的阵眼。地上兵器架每波换暗器，谁都能捡；每五波出一只尸王。"},
	"musou": {"name": "万兽割草", "kick": "三分钟", "color": Color(1.0, 0.7, 0.3),
		"desc": "满地都是小尸，一打就死。三分钟能斩多少？斩够 %d 只攒一次灵爆（Z），身边一圈全清。" % BURST_NEED},
}
## 兵器架的品质：名字、颜色、伤害倍数
const QUALITY := [["凡品", Color(0.85, 0.85, 0.85), 1.0], ["灵品", Color(0.4, 0.75, 1.0), 1.35], ["玄品", Color(0.75, 0.45, 1.0), 1.8], ["天品", Color(1.0, 0.75, 0.25), 2.5]]

var world: World
var horde: Horde
var stele := Vector3.INF           # 试炼碑
var run := {}                      # 大家都有：{"mode","phase","wave","t","left","core","kills"}
var inside := false
var racks: Array = []              # 守关：[{"pos": Vector3, "id": String, "q": int}]
var my_kills := 0
var burst := 0                     # 割草：灵爆充能
var _return := Vector3.ZERO
var _rack_nodes: Array = []
var _core: Node3D
var _core_mat: StandardMaterial3D
var _gates: Array = []             # 守关：四个尸门（出生点）
var _pending: Array = []           # 自己这一帧打中的 [[id, 伤害, peer]]
var _kill_snd_t := 0.0
var _mile := 0
# 房主
var _members := {}
var _queue: Array = []             # 这一波还没出的 [kind, hp]
var _spawn_t := 0.0
var _phase_t := 0.0
var _sync_t := 0.0
var _empty_t := 0.0
var _king_t := 0.0
var _stats := {}                   # peer -> 斩数（结算用）
# 界面
var _card: PanelContainer
var _c_kick: Label
var _c_state: Label
var _c_sub: Label
var _core_bar: ProgressBar
var _big: Label                    # 割草：中间上方的大斩数
var _big_sub: Label
var _burst_bar: ProgressBar
var _result: PanelContainer
var _result_t := 0.0


func _ready() -> void:
	horde = Horde.new()
	horde.name = "Horde"
	horde.world = world
	horde.trial = self
	add_child(horde)
	horde.killed.connect(_on_killed)
	_build_ui()
	if world.island.hunting:
		return
	_place_stele()
	_build_siege()
	_build_musou()


func mode() -> String:
	return str(run.get("mode", ""))


func center() -> Vector3:
	return SIEGE if mode() == "siege" else MUSOU


func arena_r() -> float:
	return SIEGE_R if mode() == "siege" else MUSOU_R


func _process(dt: float) -> void:
	if Net.is_host():
		_host(dt)
	elif not run.is_empty() and str(run["phase"]) in ["wave", "break", "run"]:
		run["t"] = float(run["t"]) + dt
	_local(dt)


# ------------------------------------------------------------------ 试炼碑（码头边，猎灵榜旁边）

func _place_stele() -> void:
	var isl := world.island
	var bp: Vector3 = world.builder.board_pos
	if bp == Vector3.ZERO:
		bp = isl.spawn
	for r in [6.0, 8.0, 10.0, 13.0]:
		for i in 16:
			var a := TAU * i / 16.0
			var q := bp + Vector3(cos(a), 0, sin(a)) * float(r)
			if not isl.is_land(q.x, q.z) or isl.height_at(q.x, q.z) < 0.9 or isl.slope_at(q.x, q.z) > 0.4:
				continue
			if Vector2(q.x - world.builder.shop_door.x, q.z - world.builder.shop_door.z).length() < 6.0:
				continue
			if Vector2(q.x - world.builder.boat_pos.x, q.z - world.builder.boat_pos.z).length() < 6.0:
				continue
			stele = isl.ground_point(q.x, q.z)
			break
		if stele != Vector3.INF:
			break
	if stele == Vector3.INF:
		stele = isl.ground_point(bp.x + 6.0, bp.z)
	var b := world.builder
	var n := Node3D.new()
	n.name = "TrialStele"
	world.add_child(n)
	n.global_position = stele
	var face := Vector3(isl.spawn.x - stele.x, 0, isl.spawn.z - stele.z)
	n.rotation.y = atan2(face.x, face.z) if face.length() > 0.5 else 0.0
	var stone := b._stone(Color(0.35, 0.33, 0.36))
	var dark := b._stone(Color(0.18, 0.17, 0.2))
	U.part(n, U.cyl(1.5, 1.8, 0.4, 10), dark, Vector3(0, 0.2, 0))
	# 碑身 + 碑帽（青石上刻着发绿光的"试"字）
	U.part(n, U.box(Vector3(1.4, 3.0, 0.45)), stone, Vector3(0, 1.9, 0))
	U.part(n, U.box(Vector3(1.8, 0.35, 0.7)), dark, Vector3(0, 3.55, 0))
	U.part(n, U.cyl(0.0, 1.1, 0.5, 4), dark, Vector3(0, 3.95, 0), Vector3(0, PI / 4, 0), Vector3(1, 1, 0.45))
	b._cyl_collider(stele + Vector3(0, 0.0, 0), 0.9, 3.8)
	var l := U.label3d("试", 180, Color(0.5, 1.0, 0.6), 0)
	l.position = Vector3(0, 2.2, 0.24)
	l.pixel_size = 0.005
	l.modulate = Color(0.55, 1.0, 0.65)
	n.add_child(l)
	var l2 := l.duplicate() as Label3D
	l2.position = Vector3(0, 2.2, -0.24)
	l2.rotation.y = PI
	n.add_child(l2)
	for s in [-1.0, 1.0]:
		U.part(n, U.box(Vector3(0.12, 0.9, 0.02)), U.glow(Color(0.95, 0.8, 0.25), 1.5), Vector3(s * 0.55, 2.9, 0.235), Vector3(0, 0, s * 0.1), Vector3.ONE, false)
	var gl := OmniLight3D.new()
	gl.light_color = Color(0.5, 1.0, 0.6)
	gl.light_energy = 1.6
	gl.omni_range = 7.0
	gl.position = Vector3(0, 2.2, 1.2)
	n.add_child(gl)
	b._motes(stele + Vector3(0, 2.0, 0), Vector3(1.5, 1.8, 1.5), 16, Color(0.5, 1.0, 0.6) * 0.8, 0.12)


func compass_marks() -> Array:
	if inside or stele == Vector3.INF:
		return []
	return [[stele, "试", Color(0.5, 1.0, 0.6)]]


# ------------------------------------------------------------------ 场地：尸潮守关（古堡）

func _build_siege() -> void:
	world.island.add_floor(SIEGE, SIEGE_R + 2.0)
	var b := world.builder
	var stone := b._stone(Color(0.46, 0.44, 0.42))
	var dark := b._stone(Color(0.24, 0.23, 0.25))
	var wood := b._wood(Color(0.45, 0.3, 0.2))
	var root := Node3D.new()
	root.name = "SiegeArena"
	world.add_child(root)
	root.global_position = SIEGE
	var rng := RandomNumberGenerator.new()
	rng.seed = 4400 + world.chapter
	U.part(root, U.cyl(SIEGE_R + 2.5, SIEGE_R + 3.5, 2.0, 64), dark, Vector3(0, -1.0, 0))
	b._cyl_collider(SIEGE + Vector3(0, -2.0, 0), SIEGE_R + 2.5, 2.0)
	for ring in 4:
		var rr := 6.0 + ring * 8.0
		U.part(root, U.cyl(rr + 3.8, rr + 3.8, 0.06, 64), stone if ring % 2 == 0 else dark, Vector3(0, 0.02 + ring * 0.001, 0), Vector3.ZERO, Vector3.ONE, false)
	# 外墙：一圈城墙，四个方向留尸门
	var n := 36
	for i in n:
		var a := TAU * i / n
		if _near_gate(a, 0.2):
			continue
		var h := rng.randf_range(7.0, 9.5)
		var w := TAU * (SIEGE_R + 2.0) / n + 0.8
		var c := Vector3(cos(a), 0, sin(a)) * (SIEGE_R + 2.0)
		var basis := Basis(Vector3.UP, -a + PI * 0.5)
		var slab := U.part(root, U.box(Vector3(w, h, 2.6)), stone if i % 4 != 0 else dark, c + Vector3(0, h * 0.5 - 0.5, 0), Vector3(0, -a + PI * 0.5, 0), Vector3.ONE, false)
		slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# 垛口
		for k in 2:
			U.part(root, U.box(Vector3(w * 0.3, 1.0, 2.8)), dark, c + Vector3(0, h + 0.0, 0) + basis * Vector3((k - 0.5) * w * 0.5, 0, 0), Vector3(0, -a + PI * 0.5, 0), Vector3.ONE, false)
		b._add_collider(_box_shape(Vector3(w, h, 2.6)), Transform3D(basis, SIEGE + c + Vector3(0, h * 0.5 - 0.5, 0)))
	# 四个尸门：黑洞洞的门洞 + 两边挂白灯笼 + 地上一滩绿雾
	for k in 4:
		var a := k * PI * 0.5
		var dir := Vector3(cos(a), 0, sin(a))
		var gp := dir * (SIEGE_R + 1.5)
		var gate := Node3D.new()
		root.add_child(gate)
		gate.position = gp
		gate.rotation.y = -a - PI * 0.5
		U.part(gate, U.box(Vector3(6.0, 7.5, 1.0)), U.mat(Color(0.02, 0.03, 0.02), 1.0), Vector3(0, 3.7, 0.5), Vector3.ZERO, Vector3.ONE, false)
		for s in [-1.0, 1.0]:
			U.part(gate, U.box(Vector3(1.2, 9.5, 3.0)), dark, Vector3(s * 3.6, 4.7, 0), Vector3.ZERO, Vector3.ONE, false)
			b._add_collider(_box_shape(Vector3(1.2, 9.5, 3.0)), Transform3D(Basis(Vector3.UP, -a - PI * 0.5), SIEGE + gp + Basis(Vector3.UP, -a - PI * 0.5) * Vector3(s * 3.6, 4.7, 0)))
			U.part(gate, U.sphere(0.35, 10, 8), U.glow(Color(0.9, 1.0, 0.9), 2.2), Vector3(s * 3.6, 6.8, 1.7), Vector3.ZERO, Vector3(1, 1.3, 1), false)
		U.part(gate, U.box(Vector3(8.4, 1.0, 3.2)), dark, Vector3(0, 9.0, 0), Vector3.ZERO, Vector3.ONE, false)
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(5.4, 7.0)
		q.mesh = qm
		q.material_override = FxLib.quad_mat("swirl", Color(0.35, 1.0, 0.45), 1.0, true)
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		q.position = Vector3(0, 3.6, 1.1)
		gate.add_child(q)
		var tw := q.create_tween().set_loops()
		tw.tween_property(q, "rotation:z", -TAU, 8.0).as_relative()
		var gl := OmniLight3D.new()
		gl.light_color = Color(0.4, 1.0, 0.5)
		gl.light_energy = 1.5
		gl.omni_range = 11.0
		gl.position = Vector3(0, 3.0, 3.0)
		gate.add_child(gl)
		_gates.append(SIEGE + dir * (SIEGE_R - 2.5))
	# 阵眼：石台 + 浮着的八卦晶石 + 两圈转的符环 + 一道光柱
	U.part(root, U.cyl(2.2, 2.7, 1.0, 8), dark, Vector3(0, 0.5, 0))
	U.part(root, U.cyl(2.8, 2.8, 0.15, 8), stone, Vector3(0, 0.08, 0))
	b._cyl_collider(SIEGE, 2.4, 1.0)
	_core = Node3D.new()
	root.add_child(_core)
	_core.position = Vector3(0, 2.6, 0)
	_core_mat = U.glow(Color(0.5, 1.0, 0.6), 3.5)
	U.part(_core, U.sphere(0.8, 8, 4), _core_mat, Vector3.ZERO, Vector3.ZERO, Vector3(1, 1.5, 1), false)
	for k in 2:
		var ring := U.part(_core, U.torus(1.3 + k * 0.4, 1.36 + k * 0.4, 48, 4), U.glow(Color(0.95, 0.8, 0.3), 2.5), Vector3.ZERO, Vector3(0.5 + k, 0, 0.3), Vector3.ONE, false)
		var rt := ring.create_tween().set_loops()
		rt.tween_property(ring, "rotation:y", TAU * (1.0 if k == 0 else -1.0), 5.0 + k * 3.0).as_relative()
	var cl := OmniLight3D.new()
	cl.light_color = Color(0.5, 1.0, 0.6)
	cl.light_energy = 3.0
	cl.omni_range = 16.0
	_core.add_child(cl)
	var pil := MeshInstance3D.new()
	var pcm := CylinderMesh.new()
	pcm.top_radius = 0.9
	pcm.bottom_radius = 0.9
	pcm.height = 40.0
	pcm.cap_top = false
	pcm.cap_bottom = false
	pil.mesh = pcm
	pil.material_override = FxLib.smat("pillar", {"color": Color(0.5, 1.0, 0.6), "hdr": 1.2, "half_h": 20.0, "speed": 0.8, "top": 0.5})
	pil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pil.position = Vector3(0, 21.0, 0)
	root.add_child(pil)
	var obst: Array = [[Vector2(SIEGE.x, SIEGE.z), 2.4]]
	# 内圈矮墙：八段，中间有缺口（能从墙后面打，僵尸会绕着缺口进来）
	for i in 8:
		var a := TAU * i / 8.0 + PI / 8.0
		var c := Vector3(cos(a), 0, sin(a)) * 11.0
		var yaw := -a + PI * 0.5
		U.part(root, U.box(Vector3(4.6, 1.2, 0.8)), stone, c + Vector3(0, 0.6, 0), Vector3(0, yaw, 0))
		U.part(root, U.box(Vector3(4.8, 0.15, 1.0)), dark, c + Vector3(0, 1.25, 0), Vector3(0, yaw, 0))
		b._add_collider(_box_shape(Vector3(4.6, 1.2, 0.8)), Transform3D(Basis(Vector3.UP, yaw), SIEGE + c + Vector3(0, 0.6, 0)))
		var side := Basis(Vector3.UP, yaw) * Vector3(1.4, 0, 0)
		for s in [-1.0, 0.0, 1.0]:
			var oc := c + side * float(s)
			obst.append([Vector2(SIEGE.x + oc.x, SIEGE.z + oc.z), 0.9])
	# 四座箭楼（斜对角）：石台子 + 斜坡，站上去居高临下
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0
		var c := Vector3(cos(a), 0, sin(a)) * 22.0
		var yaw := -a + PI * 0.5
		U.part(root, U.box(Vector3(4.0, 2.6, 4.0)), dark, c + Vector3(0, 1.3, 0), Vector3(0, yaw, 0))
		U.part(root, U.box(Vector3(4.4, 0.3, 4.4)), stone, c + Vector3(0, 2.75, 0), Vector3(0, yaw, 0))
		b._add_collider(_box_shape(Vector3(4.0, 2.6, 4.0)), Transform3D(Basis(Vector3.UP, yaw), SIEGE + c + Vector3(0, 1.3, 0)))
		for pi2 in 4:
			var pc := c + Basis(Vector3.UP, yaw) * Vector3((pi2 % 2 - 0.5) * 3.6, 0, (pi2 / 2 - 0.5) * 3.6)
			U.part(root, U.cyl(0.12, 0.12, 2.4, 6), wood, pc + Vector3(0, 4.0, 0))
		U.part(root, U.box(Vector3(4.8, 0.2, 4.8)), U.mat(Color(0.35, 0.08, 0.06), 0.8), c + Vector3(0, 5.25, 0), Vector3(0, yaw, 0))
		# 斜坡朝着中间
		var inward := -Vector3(cos(a), 0, sin(a))
		var rc := c + inward * 3.9
		var ry := atan2(inward.x, inward.z)
		var ramp_b := Basis(Vector3.UP, ry) * Basis(Vector3.RIGHT, 0.5)
		var ramp := MeshInstance3D.new()
		ramp.mesh = U.box(Vector3(2.2, 0.3, 5.2))
		ramp.material_override = stone
		ramp.transform = Transform3D(ramp_b, rc + Vector3(0, 1.25, 0))
		root.add_child(ramp)
		b._add_collider(_box_shape(Vector3(2.2, 0.3, 5.2)), Transform3D(ramp_b, SIEGE + rc + Vector3(0, 1.25, 0)))
		obst.append([Vector2(SIEGE.x + c.x, SIEGE.z + c.z), 2.9])
	# 白灯笼、纸钱、火盆：阴森一点
	for i in 12:
		var a := TAU * i / 12.0 + 0.13
		var c := Vector3(cos(a), 0, sin(a)) * (SIEGE_R - 1.8)
		U.part(root, U.cyl(0.06, 0.06, 3.2, 6), wood, c + Vector3(0, 1.6, 0))
		U.part(root, U.sphere(0.32, 10, 8), U.glow(Color(0.92, 0.98, 0.9), 1.6), c + Vector3(0, 3.3, 0), Vector3.ZERO, Vector3(1, 1.35, 1), false)
		if i % 3 == 0:
			var fl := OmniLight3D.new()
			fl.light_color = Color(0.7, 1.0, 0.75)
			fl.light_energy = 1.0
			fl.omni_range = 9.0
			fl.position = c + Vector3(0, 3.0, 0)
			root.add_child(fl)
	b._motes(SIEGE + Vector3(0, 3.0, 0), Vector3(SIEGE_R * 0.8, 3.0, SIEGE_R * 0.8), 80, Color(0.5, 1.0, 0.6) * 0.5, 0.14)
	_siege_obstacles = obst
	# 兵器架（六个，在内圈矮墙外面一点）
	for i in 6:
		var a := TAU * i / 6.0
		var c := Vector3(cos(a), 0, sin(a)) * 15.5
		racks.append({"pos": SIEGE + c, "id": "", "q": 0})
		var rn := Node3D.new()
		root.add_child(rn)
		rn.position = c
		U.part(rn, U.box(Vector3(1.6, 0.8, 0.8)), wood, Vector3(0, 0.4, 0))
		U.part(rn, U.box(Vector3(1.8, 0.08, 0.9)), dark, Vector3(0, 0.82, 0))
		var holder := Node3D.new()
		holder.name = "Holder"
		holder.position = Vector3(0, 1.45, 0)
		rn.add_child(holder)
		var beam := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.5
		cm.bottom_radius = 0.7
		cm.height = 6.0
		cm.cap_top = false
		cm.cap_bottom = false
		beam.mesh = cm
		beam.position = Vector3(0, 3.8, 0)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rn.add_child(beam)
		var lt := OmniLight3D.new()
		lt.omni_range = 5.0
		lt.light_energy = 1.5
		lt.position = Vector3(0, 1.8, 0)
		rn.add_child(lt)
		_rack_nodes.append([rn, holder, beam, lt])
		obst.append([Vector2(SIEGE.x + c.x, SIEGE.z + c.z), 1.0])


var _siege_obstacles: Array = []


func _near_gate(a: float, tol: float) -> bool:
	for k in 4:
		if absf(wrapf(a - k * PI * 0.5, -PI, PI)) < tol:
			return true
	return false


func _box_shape(size: Vector3) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = size
	return s


# ------------------------------------------------------------------ 场地：万兽割草（荒原乱葬岗）

func _build_musou() -> void:
	world.island.add_floor(MUSOU, MUSOU_R + 2.0)
	var b := world.builder
	var earth := b._stone(Color(0.3, 0.27, 0.22))
	var dark := b._stone(Color(0.17, 0.16, 0.15))
	var wood := b._wood(Color(0.3, 0.22, 0.16))
	var root := Node3D.new()
	root.name = "MusouArena"
	world.add_child(root)
	root.global_position = MUSOU
	var rng := RandomNumberGenerator.new()
	rng.seed = 5500 + world.chapter
	U.part(root, U.cyl(MUSOU_R + 2.5, MUSOU_R + 4.0, 2.0, 96), earth, Vector3(0, -1.0, 0))
	b._cyl_collider(MUSOU + Vector3(0, -2.0, 0), MUSOU_R + 2.5, 2.0)
	# 深浅不一的土、枯草
	for i in 40:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * (MUSOU_R - 4.0)
		var s := rng.randf_range(3.0, 9.0)
		U.part(root, U.cyl(s, s, 0.04, 16), dark if i % 2 == 0 else b._stone(Color(0.33, 0.32, 0.2)), Vector3(cos(a) * r, 0.02 + i * 0.0005, sin(a) * r), Vector3.ZERO, Vector3(1, 1, rng.randf_range(0.5, 1.0)), false)
	# 一圈断墙（挡着不让出去）
	var n := 48
	for i in n:
		var a := TAU * i / n
		var h := rng.randf_range(2.5, 5.5)
		var w := TAU * (MUSOU_R + 2.0) / n + 0.6
		var c := Vector3(cos(a), 0, sin(a)) * (MUSOU_R + 2.0)
		var basis := Basis(Vector3.UP, -a + PI * 0.5)
		var slab := U.part(root, U.box(Vector3(w, h, 2.0)), dark, c + Vector3(0, h * 0.5 - 0.3, 0), Vector3(rng.randf_range(-0.05, 0.05), -a + PI * 0.5, rng.randf_range(-0.06, 0.06)), Vector3.ONE, false)
		slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b._add_collider(_box_shape(Vector3(w, 12.0, 2.0)), Transform3D(basis, MUSOU + c + Vector3(0, 5.5, 0)))
	# 墓碑、枯树、歪着的招魂幡
	for i in 34:
		var a := rng.randf() * TAU
		var r := rng.randf_range(8.0, MUSOU_R - 5.0)
		var c := Vector3(cos(a), 0, sin(a)) * r
		match i % 3:
			0:
				U.part(root, U.box(Vector3(0.9, 1.3, 0.25)), b._stone(Color(0.45, 0.44, 0.42)), c + Vector3(0, 0.6, 0), Vector3(rng.randf_range(-0.2, 0.2), rng.randf() * TAU, rng.randf_range(-0.15, 0.15)))
			1:
				var t := Node3D.new()
				root.add_child(t)
				t.position = c
				t.rotation.y = rng.randf() * TAU
				var th := rng.randf_range(3.5, 6.0)
				U.part(t, U.cyl(0.1, 0.28, th, 7), wood, Vector3(0, th * 0.5, 0), Vector3(rng.randf_range(-0.1, 0.1), 0, rng.randf_range(-0.1, 0.1)))
				for k in 3:
					U.part(t, U.cyl(0.03, 0.09, 1.8, 5), wood, Vector3(0, th * (0.55 + k * 0.13), 0), Vector3(0, k * 2.1, 0.9 + k * 0.15))
			2:
				U.part(root, U.cyl(0.05, 0.05, 4.0, 6), wood, c + Vector3(0, 2.0, 0), Vector3(0, 0, rng.randf_range(-0.2, 0.2)))
				U.part(root, U.box(Vector3(0.6, 2.0, 0.02)), U.glow(Color(0.95, 0.95, 0.9), 0.6), c + Vector3(0.35, 2.8, 0), Vector3(0, rng.randf() * TAU, 0), Vector3.ONE, false)
	# 中间的出入台（一圈绿光）
	U.part(root, U.cyl(3.0, 3.2, 0.25, 24), dark, Vector3(0, 0.12, 0))
	U.part(root, U.torus(2.5, 2.7, 48, 4), U.glow(UiKit.JADE, 2.5), Vector3(0, 0.28, 0), Vector3.ZERO, Vector3(1, 0.1, 1), false)
	for i in 8:
		var a := TAU * i / 8.0
		var fl := OmniLight3D.new()
		fl.light_color = Color(1.0, 0.65, 0.35)
		fl.light_energy = 1.2
		fl.omni_range = 16.0
		fl.position = Vector3(cos(a) * 30.0, 4.0, sin(a) * 30.0)
		root.add_child(fl)
		U.part(root, U.cyl(0.5, 0.35, 1.0, 8), dark, Vector3(cos(a) * 30.0, 0.5, sin(a) * 30.0))
		U.part(root, U.sphere(0.4, 10, 8), U.glow(Color(1.0, 0.55, 0.2), 5.0), Vector3(cos(a) * 30.0, 1.3, sin(a) * 30.0), Vector3.ZERO, Vector3(1, 1.4, 1), false)
	b._motes(MUSOU + Vector3(0, 3.0, 0), Vector3(MUSOU_R * 0.8, 3.0, MUSOU_R * 0.8), 100, Color(1.0, 0.7, 0.4) * 0.5, 0.15)


func spawn_pad() -> Vector3:
	if mode() == "siege":
		return SIEGE + Vector3(0, 0.5, 5.0)
	return MUSOU + Vector3(0, 0.6, 0)


# ------------------------------------------------------------------ 进出

func interactables() -> Array:
	var out: Array = []
	if inside:
		if mode() == "siege":
			for i in racks.size():
				var r: Dictionary = racks[i]
				if str(r["id"]) == "":
					continue
				var q: Array = QUALITY[int(r["q"])]
				var w: Dictionary = Data.WEAPONS[str(r["id"])]
				var have := world.player.trial_gun == str(r["id"]) and is_equal_approx(world.player.trial_k, float(q[2]))
				out.append({"id": "trrack", "i": i, "pos": (r["pos"] as Vector3) + Vector3(0, 1.4, 0), "r": 2.6,
					"text": ("已经拿着【%s · %s】" % [q[0], w["name"]]) if have else ("按 F 捡起【%s · %s】（伤害 ×%.2f）" % [q[0], w["name"], float(q[2])]), "act": not have})
		out.append({"id": "trexit", "pos": spawn_pad() + Vector3(0, 1.0, 0), "r": 2.5,
			"text": "按 F 离开试炼" + ("（还在打，出去就算你放弃）" if str(run.get("phase", "")) != "done" else ""), "act": true})
		return out
	if stele != Vector3.INF:
		var txt := "按 F 打开试炼（尸潮守关 / 万兽割草）"
		if not run.is_empty():
			txt = "按 F 加入%s（队友在里面）" % MODES[mode()]["name"]
		out.append({"id": "trstele", "pos": stele + Vector3(0, 1.4, 0), "r": 3.2, "text": txt, "act": true})
	return out


func interact(it: Dictionary) -> void:
	match str(it["id"]):
		"trstele":
			if not run.is_empty():
				Net.send_host("trenter", [mode()])
			else:
				world.hud.open_trial_picker()
		"trexit":
			leave()
		"trrack":
			pick_rack(int(it["i"]))


## 选了一种（试炼面板里点的）
func request(m: String) -> void:
	Net.send_host("trenter", [m])


func best_key(m: String) -> String:
	return "%s_best_%d" % [m, world.chapter]


func best(m: String) -> int:
	return int(Profile.stats.get(best_key(m), 0))


## 被房主传送进来
func enter(m: String) -> void:
	if inside:
		return
	if run.is_empty():
		run = {"mode": m, "phase": "prep", "wave": 0, "t": 0.0, "left": 0, "core": CORE_HP, "kills": 0}
	inside = true
	my_kills = 0
	burst = 0
	_mile = 0
	_return = stele + Vector3(0, 0.6, 2.5) if stele != Vector3.INF else world.player.global_position
	_setup_horde()
	var pl := world.player
	pl.teleport(spawn_pad() + Vector3(randf_range(-1.5, 1.5), 0.2, randf_range(-1.0, 1.0)))
	pl.look_to(0.0, deg_to_rad(-2))
	var md: Dictionary = MODES[m]
	world.fx.aura_burst(pl.global_position, md["color"], 3.0)
	Sfx.play("absorb", -4.0, 0.0, 0.7)
	world.hud._show_banner(str(md["name"]), str(md["desc"]), md["color"], 5.0)
	world.hud.flash(Color(0.4, 1.0, 0.5, 0.35))


func _setup_horde() -> void:
	horde.clear()
	horde.center = center()
	horde.radius = arena_r()
	if mode() == "siege":
		horde.goal = SIEGE
		horde.goal_r = CORE_R
		horde.chase_r = 9.0
		horde.obstacles = _siege_obstacles
	else:
		horde.goal = Vector3.INF
		horde.chase_r = 1e9
		horde.obstacles = []
		horde.dmg_k = 0.6


## 自己走出去（或者倒下回了码头）
func leave(teleport := true) -> void:
	if not inside:
		return
	inside = false
	horde.clear()
	_drop_trial_gun()
	if teleport:
		world.player.teleport(_return)
		world.fx.aura_burst(_return, Color(0.5, 1.0, 0.6), 2.5)
		Sfx.play("absorb", -6.0, 0.0, 1.2)
	if Net.is_host():
		_members.erase(Net.my_id)
	else:
		Net.send_host("trleave", [])


func on_respawn() -> void:
	# 倒下了：还在打就在场地里复活（守关看阵眼，割草看时间；灵爆充能清零），打完了就回码头
	if inside and not run.is_empty():
		world.player.teleport(spawn_pad())
		burst = 0
		return
	leave(false)


func _drop_trial_gun() -> void:
	var p := world.player
	if p.trial_gun != "":
		p.trial_gun = ""
		p.trial_k = 1.0
		p.rebuild_guns()


## 捡兵器架上的暗器：换成它（出了试炼还回去）
func pick_rack(i: int) -> void:
	if i < 0 or i >= racks.size():
		return
	var r: Dictionary = racks[i]
	var id := str(r["id"])
	if id == "":
		return
	var q: Array = QUALITY[int(r["q"])]
	var p := world.player
	p.trial_gun = id
	p.trial_k = float(q[2])
	p.rebuild_guns()
	for gi in p.guns.size():
		if p.guns[gi].id == id:
			p.switch_weapon(gi)
			break
	world.hud.toast("捡起【%s · %s】" % [q[0], Data.WEAPONS[id]["name"]], q[1], 2.0)
	world.fx.aura_burst((r["pos"] as Vector3) + Vector3(0, 1.4, 0), q[1], 1.5)
	Sfx.play("pickup", -2.0)


# ------------------------------------------------------------------ 房主

func host_enter(from: int, m: String) -> void:
	if not MODES.has(m):
		return
	if not run.is_empty() and mode() != m:
		return
	if run.is_empty():
		run = {"mode": m, "phase": "prep", "wave": 0, "t": 0.0, "left": 0, "core": CORE_HP, "kills": 0}
		_members.clear()
		_queue.clear()
		_stats.clear()
		_phase_t = PREP if m == "siege" else 5.0
		_empty_t = 0.0
		horde.next_id = 1
		if m == "siege":
			_host_roll_racks(1)
	_members[from] = true
	_sync()
	if from == Net.my_id:
		enter(m)
	else:
		Net.send(from, "trin", [m])
		Net.send(from, "trrack", _rack_msg())
		# 中途加入：场上已经有的僵尸也告诉他
		var cur: Array = []
		for u in horde.units:
			cur.append([int(u["id"]), (u["p"] as Vector3).x, (u["p"] as Vector3).z, int(u["kind"]), float(u["hp"])])
		if not cur.is_empty():
			Net.send(from, "hdsp", cur)


func _sync() -> void:
	_sync_t = 1.0
	var st: Array = []
	if not run.is_empty():
		st = [mode(), str(run["phase"]), int(run["wave"]), float(run["t"]), int(run["left"]), float(run["core"]), int(run["kills"])]
	Net.send(0, "trst", st)


func _team() -> int:
	return maxi(_members.size(), 1)


func _host(dt: float) -> void:
	if run.is_empty():
		return
	var present := {}
	for p in world.all_players():
		present[int(p["peer"])] = true
	for k in _members.keys():
		if not present.has(int(k)):
			_members.erase(k)
	var phase := str(run["phase"])
	if _members.is_empty():
		_empty_t += dt
		if _empty_t > 4.0:
			_end_run()
		return
	_empty_t = 0.0
	if phase in ["wave", "break", "run"]:
		run["t"] = float(run["t"]) + dt
	match mode():
		"siege":
			_host_siege(dt, phase)
		"musou":
			_host_musou(dt, phase)
	_sync_t -= dt
	if _sync_t <= 0.0:
		_sync()


## 这一章的参照（奖励、血量都按它算）
func _ref() -> Array:
	var sp: Array = world._map_species()
	return [str(sp[0]) if not sp.is_empty() else "rabbit", int(Data.CH_AGE.get(world.chapter, 0))]


## 僵尸血量：按全队最强暗器一发的伤害算（跳尸 3 发、铁尸 9 发、尸王 60 发），越往后越厚
func _unit_hp(kind: int, wave: int) -> float:
	var o := world.team_output()
	var shot := maxf(o.x, 10.0)
	var k := 1.0 + 0.14 * (wave - 1)
	match kind:
		0:
			return 1.0
		1:
			return shot * 2.6 * k
		2:
			return shot * 8.0 * k
		_:
			return shot * 55.0 * k * (1.0 + 0.5 * (_team() - 1))


func _host_siege(dt: float, phase: String) -> void:
	match phase:
		"prep", "break":
			_phase_t -= dt
			if _phase_t <= 0.0:
				_start_wave(int(run["wave"]) + 1)
		"wave":
			_spawn_t -= dt
			var cap := 14 + 4 * (_team() - 1)
			if not _queue.is_empty() and _spawn_t <= 0.0 and horde.alive_count() < cap:
				_spawn_t = 0.35
				var batch: Array = []
				for i in mini(3, _queue.size()):
					var e: Array = _queue.pop_front()
					var g: Vector3 = _gates[randi() % _gates.size()]
					g += Vector3(randf_range(-2.0, 2.0), 0, randf_range(-2.0, 2.0))
					batch.append([0, g.x, g.z, int(e[0]), float(e[1])])
				horde.host_spawn(batch)
			run["left"] = horde.alive_count() + _queue.size()
			_host_kings(dt)
			if _queue.is_empty() and horde.alive_count() == 0:
				_wave_cleared()
			if float(run["core"]) <= 0.0:
				_end_run()


func _start_wave(n: int) -> void:
	run["wave"] = n
	run["phase"] = "wave"
	var count := 8 + 4 * n + 3 * (_team() - 1)
	for i in count:
		var kind := 1
		if n >= 3 and randf() < (0.15 if n < 6 else 0.28):
			kind = 2
		_queue.append([kind, _unit_hp(kind, n)])
	if n % 5 == 0:
		for i in (1 if _team() < 3 else 2):
			_queue.insert(randi() % maxi(_queue.size(), 1), [3, _unit_hp(3, n)])
	_queue.shuffle()
	horde.dmg_k = 1.0 + 0.06 * (n - 1)
	horde.core_dmg = 8.0 + 1.5 * n
	_spawn_t = 0.5
	Net.send(0, "trwave", [n, horde.dmg_k, horde.core_dmg])
	_on_wave([n, horde.dmg_k, horde.core_dmg])
	_sync()


func _wave_cleared() -> void:
	var n := int(run["wave"])
	run["phase"] = "break"
	_phase_t = BREAK
	# 阵眼回一点
	run["core"] = minf(float(run["core"]) + CORE_HP * 0.15, CORE_HP)
	var ref := _ref()
	var money := roundi(Data.kill_money(ref[0], ref[1]) * (1.5 + 0.6 * n) * Data.KILL_MONEY)
	var xp := roundi(Data.kill_xp(ref[0], ref[1]) * (1.5 + 0.6 * n))
	_host_roll_racks(n + 1)
	Net.send(0, "trclear", [n, money, xp])
	_on_wave_clear([n, money, xp])
	_sync()


## 兵器架：每波换一批。波数越高，好品质越多
func _host_roll_racks(wave: int) -> void:
	var pool: Array = []
	for id in Data.WEAPON_ORDER:
		if id in Data.SIDEARMS:
			continue
		pool.append(id)
	for r in racks:
		r["id"] = pool[randi() % pool.size()]
		var roll := randf() + wave * 0.045
		r["q"] = 3 if roll > 1.15 else (2 if roll > 0.85 else (1 if roll > 0.5 else 0))
	var m := _rack_msg()
	Net.send(0, "trrack", m)
	_on_racks(m)


func _rack_msg() -> Array:
	var m: Array = []
	for r in racks:
		m.append([str(r["id"]), int(r["q"])])
	return m


## 尸王：隔几秒砸一下离它最近的人（地上红圈，看到就跑）
func _host_kings(dt: float) -> void:
	_king_t -= dt
	if _king_t > 0.0:
		return
	_king_t = 3.2
	for u in horde.units:
		if int(u["kind"]) != 3:
			continue
		var p: Vector3 = u["p"]
		var tp := world.nearest_player(p)
		if tp.is_empty() or (tp["pos"] as Vector3).distance_to(p) > 14.0:
			continue
		var at: Vector3 = tp["pos"]
		at.y = SIEGE.y
		var dmg := Profile.max_hp() * 0.3 / float(Data.CH_POWER.get(world.chapter, 1.0))
		world.boss_telegraph(at, 5.0, 1.3, dmg, "slam", p)
		u["cd"] = 2.0
		var tw := create_tween()
		tw.tween_interval(1.25)
		tw.tween_callback(func():
			Net.send(0, "trslam", [at])
			_on_slam([at]))


## 阵眼挨打（Horde 调，只有房主）
func host_core_hit(dmg: float, from: Vector3) -> void:
	if run.is_empty() or mode() != "siege" or str(run["phase"]) != "wave":
		return
	run["core"] = maxf(float(run["core"]) - dmg, 0.0)
	Net.send(0, "trcore", [float(run["core"]), from])
	_on_core([float(run["core"]), from])


func _host_musou(dt: float, phase: String) -> void:
	match phase:
		"prep":
			_phase_t -= dt
			if _phase_t <= 0.0:
				run["phase"] = "run"
				run["t"] = 0.0
				_sync()
		"run":
			if float(run["t"]) >= MUSOU_TIME:
				_end_run()
				return
			# 维持满场：一直补到这么多只（人越多越多）；在人周围 18~40 米冒出来
			var want := mini(150 + 45 * (_team() - 1), Horde.MAX - 20)
			_spawn_t -= dt
			if horde.alive_count() < want and _spawn_t <= 0.0:
				_spawn_t = 0.12
				var pls := world.alive_players().filter(func(p): return Vector2((p["pos"] as Vector3).x - MUSOU.x, (p["pos"] as Vector3).z - MUSOU.z).length() < MUSOU_R + 5.0)
				if pls.is_empty():
					return
				var batch: Array = []
				for i in mini(12, want - horde.alive_count()):
					var c: Vector3 = pls[randi() % pls.size()]["pos"]
					var a := randf() * TAU
					var r := randf_range(18.0, 40.0)
					var q := Vector2(c.x + cos(a) * r - MUSOU.x, c.z + sin(a) * r - MUSOU.z)
					if q.length() > MUSOU_R - 3.0:
						q = q.normalized() * (MUSOU_R - 3.0)
					var kind := 2 if randf() < 0.04 else 0
					batch.append([0, MUSOU.x + q.x, MUSOU.z + q.y, kind, _unit_hp(kind, 1) * (0.35 if kind == 2 else 1.0)])
				horde.host_spawn(batch)


func _end_run() -> void:
	if run.is_empty():
		return
	var m := mode()
	var ref := _ref()
	var kills := int(run["kills"])
	var wave := int(run["wave"])
	var score := kills if m == "musou" else maxi(wave - (1 if str(run["phase"]) == "wave" else 0), 0)
	var money := 0
	var xp := 0
	if m == "musou":
		money = roundi(Data.kill_money(ref[0], ref[1]) * kills * 0.12 * Data.KILL_MONEY)
		xp = roundi(Data.kill_xp(ref[0], ref[1]) * kills * 0.12)
	else:
		money = roundi(Data.kill_money(ref[0], ref[1]) * score * 1.0 * Data.KILL_MONEY)
		xp = roundi(Data.kill_xp(ref[0], ref[1]) * score * 1.0)
	var msg := [m, score, int(float(run["t"])), money, xp, kills]
	run = {}
	_members.clear()
	_queue.clear()
	Net.send(0, "trend", msg)
	_on_end(msg)
	_sync()


# ------------------------------------------------------------------ 打中 / 打死

## 自己开枪：一条射线上的僵尸（World.local_fire 调）
func shot(origin: Vector3, end: Vector3, w: Dictionary, dmg_mult: float, pierce: int) -> void:
	if not inside:
		return
	var n := pierce + (2 if mode() == "musou" else 0)
	for h in horde.ray_hits(origin, end, n):
		var dist := float(h[1])
		var head := bool(h[2])
		var dmg := float(w["damage"]) * world._falloff(w, dist) * (float(w["headshot"]) if head else 1.0) * dmg_mult
		_pending.append([int(h[0]), dmg, Net.my_id])
		var p := horde.pos_of(int(h[0]))
		if p != Vector3.INF:
			world.fx.impact_beast(p + Vector3.UP * (1.65 if head else 1.1), (origin - p).normalized(), Color(0.5, 1.0, 0.6), head)
		world.hud.hitmarker(head, false)


## 爆炸（子母雷珠、雷莲）
func blast(at: Vector3, r: float, dmg: float) -> void:
	if not inside:
		return
	for id in horde.in_sphere(at, r):
		_pending.append([id, dmg, Net.my_id])


## 拳头：面前一小片
func melee(origin: Vector3, dir: Vector3, reach: float, dmg: float) -> void:
	if not inside:
		return
	var c := origin + dir * (reach * 0.6)
	for id in horde.in_sphere(Vector3(c.x, origin.y - 1.0, c.z), maxf(reach * 0.6, 1.4)):
		_pending.append([id, dmg, Net.my_id])
		world.hud.hitmarker(false, false)


## 房主：神通打到的（SkillSystem._launch / _beam 调）
func host_area(c: Vector3, r: float, dmg: float, caster: int) -> void:
	if run.is_empty() or horde.alive_count() == 0:
		return
	var list: Array = []
	for id in horde.in_sphere(c, r):
		list.append([id, dmg, caster])
	_send_hits(list)


func host_beam(o: Vector3, dir: Vector3, length: float, width: float, dmg: float, caster: int) -> void:
	if run.is_empty() or horde.alive_count() == 0:
		return
	var list: Array = []
	for id in horde.in_beam(o, dir, length, width):
		list.append([id, dmg, caster])
	_send_hits(list)


func _send_hits(list: Array) -> void:
	if list.is_empty():
		return
	Net.send(0, "hdhit", list)
	horde.apply_hits(list)


## 灵爆（割草，Z）：身边一圈全清
func _burst_now() -> void:
	if burst < BURST_NEED or not inside or mode() != "musou" or world.player.dead:
		return
	burst = 0
	var p := world.player.global_position
	var list: Array = []
	for id in horde.in_sphere(p, BURST_R):
		list.append([id, 1e6, Net.my_id])
	_send_hits(list)
	Net.send(0, "trburst", [p])
	_on_burst([p])


func _on_burst(d: Array) -> void:
	var p: Vector3 = d[0]
	if not inside:
		return
	world.fx.shockwave(p, BURST_R, Color(1.0, 0.75, 0.3))
	world.fx.ring_breakthrough(p, Color(1.0, 0.75, 0.3), 1)
	world.fx.explosion(p + Vector3.UP, 5.0, Color(1.0, 0.7, 0.3))
	world.fx._shake(p, 0.9, 40.0)
	Sfx.play_at("boom", p, 4.0, 0.05, 0.7)
	Sfx.play_at("kill_burst", p, 2.0)


func _on_killed(_id: int, peer: int, kind: int, pos: Vector3) -> void:
	if Net.is_host() and not run.is_empty():
		run["kills"] = int(run["kills"]) + 1
		_stats[peer] = int(_stats.get(peer, 0)) + 1
	if peer != Net.my_id:
		return
	my_kills += 1
	if mode() == "musou":
		burst = mini(burst + 1, BURST_NEED)
		if burst == BURST_NEED:
			world.hud.toast("灵爆攒满了——按 Z，身边一圈全清！", Color(1.0, 0.8, 0.35), 2.5)
			Sfx.play("rare", -4.0)
		# 里程碑：百人斩、五百、千人斩……
		var miles := [100, 300, 500, 1000, 2000, 3000]
		if _mile < miles.size() and my_kills >= int(miles[_mile]):
			var mk := int(miles[_mile])
			_mile += 1
			var nm := "千人斩" if mk >= 1000 else ("百人斩" if mk == 100 else "%d 斩" % mk)
			world.hud._show_banner(nm, "", Color(1.0, 0.75, 0.3), 1.6)
			world.hud.flash(Color(1.0, 0.8, 0.3, 0.3))
			Sfx.play("level_up", -4.0, 0.0, 1.2)
	elif kind >= 2:
		world.fx.damage_number(pos + Vector3.UP * 2.0, 0.0, false, true)
	# 击杀声不要太密（割草一次死十几只）
	if _kill_snd_t <= 0.0:
		_kill_snd_t = 0.06
		Sfx.play("kill", -6.0, 0.1, 1.0 + minf(my_kills % 20, 10) * 0.02)
		world.hud.hitmarker(false, true)


# ------------------------------------------------------------------ 消息

func on_message(from: int, type: String, data: Variant) -> void:
	match type:
		"trst":
			if not Net.is_host():
				_apply_state(data)
		"trenter":
			if Net.is_host():
				host_enter(from, str(data[0]))
		"trin":
			enter(str(data[0]))
		"trleave":
			if Net.is_host():
				_members.erase(from)
		"trrack":
			_on_racks(data)
		"trcore":
			_on_core(data)
		"trwave":
			_on_wave(data)
		"trclear":
			_on_wave_clear(data)
		"trslam":
			_on_slam(data)
		"trburst":
			_on_burst(data)
		"trend":
			_on_end(data)
		"hdsp":
			if inside:
				horde.spawn(data)
		"hdhit":
			horde.apply_hits(data)


func _apply_state(d: Array) -> void:
	if d.is_empty():
		run = {}
		return
	run = {"mode": str(d[0]), "phase": str(d[1]), "wave": int(d[2]), "t": float(d[3]), "left": int(d[4]), "core": float(d[5]), "kills": int(d[6])}


func _on_racks(d: Array) -> void:
	for i in mini(d.size(), racks.size()):
		racks[i]["id"] = str(d[i][0])
		racks[i]["q"] = int(d[i][1])
		var nodes: Array = _rack_nodes[i]
		var holder: Node3D = nodes[1]
		for c in holder.get_children():
			c.queue_free()
		var id := str(d[i][0])
		if id == "":
			continue
		var q: Array = QUALITY[int(d[i][1])]
		var wm := WeaponModels.build(id)
		wm.scale = Vector3.ONE * 2.2
		holder.add_child(wm)
		var tw := holder.create_tween().set_loops()
		tw.tween_property(holder, "rotation:y", TAU, 4.0).as_relative()
		var beam: MeshInstance3D = nodes[2]
		beam.material_override = FxLib.smat("pillar", {"color": q[1], "hdr": 1.2 + int(d[i][1]) * 0.6, "half_h": 3.0, "speed": 1.0, "top": 0.0, "rim_k": 0.7})
		(nodes[3] as OmniLight3D).light_color = q[1]


func _on_core(d: Array) -> void:
	if not inside:
		return
	var hp := float(d[0])
	run["core"] = hp
	var k := hp / CORE_HP
	_core_mat.albedo_color = Color(0.5, 1.0, 0.6).lerp(Color(1.0, 0.25, 0.2), 1.0 - k)
	_core_mat.emission = _core_mat.albedo_color
	world.fx._sparks(SIEGE + Vector3(0, 2.6, 0), Vector3.UP, Color(1.0, 0.4, 0.3), 5, 4.0, 0.4, 0.05, -6.0, 120.0)
	if k < 0.35 and randf() < 0.1:
		world.hud.toast("阵眼快碎了！", Color(1.0, 0.35, 0.3), 1.2)


func _on_wave(d: Array) -> void:
	horde.dmg_k = float(d[1])
	horde.core_dmg = float(d[2])
	if not inside:
		return
	var n := int(d[0])
	var sub := "尸王来了！看地上的红圈" if n % 5 == 0 else ""
	world.hud._show_banner("第 %d 波" % n, sub, Color(0.5, 1.0, 0.55), 1.8)
	Sfx.play("boss_roar", -4.0, 0.0, 1.4 if n % 5 != 0 else 0.8)


func _on_wave_clear(d: Array) -> void:
	if not inside:
		return
	var n := int(d[0])
	world._gain(int(d[1]), int(d[2]))
	world.hud._show_banner("第 %d 波 · 守住了" % n, "+%d 灵石 · 兵器架换了一批" % int(d[1]), UiKit.GOLD, 2.2)
	Sfx.play("quest_done", -2.0)
	world.fx.aura_burst(SIEGE + Vector3(0, 2.6, 0), Color(0.5, 1.0, 0.6), 4.0)


func _on_slam(d: Array) -> void:
	if inside:
		world.fx.slam(d[0], 5.0)
		Sfx.play_at("boom", d[0], 2.0, 0.1, 0.8)


func _on_end(d: Array) -> void:
	var m := str(d[0])
	var was := inside
	run = {}
	horde.clear()
	if not was:
		return
	var score := int(d[1])
	var t := int(d[2])
	var money := int(d[3])
	var xp := int(d[4])
	var kills := int(d[5])
	world._gain(money, xp)
	var key := best_key(m)
	var old := int(Profile.stats.get(key, 0))
	var record := score > old
	if record:
		Profile.stats[key] = score
		Profile.mark_dirty()
	Profile.count("trials")
	world.lock_music("victory", 25.0)
	Sfx.play("quest_done", 2.0)
	world.hud.flash(Color(1.0, 0.82, 0.35, 0.35))
	_show_result(m, score, t, money, xp, kills, record, old)


# ------------------------------------------------------------------ 自己这边：每帧

func _local(dt: float) -> void:
	_kill_snd_t -= dt
	if not _pending.is_empty():
		var list := _pending
		_pending = []
		# 同一只合在一起
		var merged := {}
		for e in list:
			var id := int(e[0])
			merged[id] = float(merged.get(id, 0.0)) + float(e[1])
		var out: Array = []
		for id in merged:
			out.append([id, merged[id], Net.my_id])
		_send_hits(out)
	_update_ui(dt)
	if _result:
		_result_t -= dt
		if _result_t <= 0.0:
			_result.visible = false
	if not inside:
		return
	if Input.is_action_just_pressed("true_body") and world.player.input_enabled:
		_burst_now()
	var p := world.player
	if not p.dead and (p.global_position.y < center().y - 6.0 or Vector2(p.global_position.x - center().x, p.global_position.z - center().z).length() > arena_r() + 4.0):
		p.teleport(spawn_pad())
	# 局结束了（房主那边结算过、或者出来了）：自己留在场地里就送回去
	if run.is_empty() and _result_t <= 0.0:
		leave()


# ------------------------------------------------------------------ 界面

func _build_ui() -> void:
	var hud: Hud = world.hud
	var q: Control = hud._quest_text.get_parent()
	var tl: Control = q.get_parent()
	_card = PanelContainer.new()
	var st := UiKit.glass_style(0.45, 12, 8)
	st.border_color = Color(0.45, 1.0, 0.55)
	st.border_width_left = 3
	_card.add_theme_stylebox_override("panel", st)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.visible = false
	tl.add_child(_card)
	tl.move_child(_card, q.get_index() + 1)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(v)
	_c_kick = UiKit.kicker("", Color(0.6, 1.0, 0.65), 13)
	UiKit._text_style(_c_kick, 3)
	v.add_child(_c_kick)
	_c_state = UiKit.bold("", 20, Color.WHITE, 3)
	v.add_child(_c_state)
	_c_sub = UiKit.label("", 14, UiKit.MIST, 3)
	v.add_child(_c_sub)
	_core_bar = UiKit.bar(Color(0.5, 1.0, 0.6), 240.0, 8.0)
	v.add_child(_core_bar)
	# 割草：上方正中的大斩数 + 灵爆条
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	UiKit.place(box, Vector4(0.5, 0.0, 0.5, 0.0), Vector4(-220, 118, 220, 250))
	layer.add_child(box)
	_big = UiKit.num("", 64, Color(1.0, 0.82, 0.4), 6)
	_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_big)
	_big_sub = UiKit.label("", 16, UiKit.MOON, 3)
	_big_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_big_sub)
	_burst_bar = UiKit.bar(Color(1.0, 0.75, 0.3), 260.0, 8.0)
	_burst_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_burst_bar)
	box.visible = false
	_big.set_meta("box", box)


var _big_scale := 1.0
var _last_kills := 0


func _update_ui(dt: float) -> void:
	var box: Control = _big.get_meta("box")
	_card.visible = inside and not run.is_empty()
	box.visible = inside and mode() == "musou"
	if not _card.visible:
		return
	var md: Dictionary = MODES.get(mode(), MODES["siege"])
	_c_kick.text = "试炼 · %s" % md["name"]
	var s := int(float(run["t"]))
	var phase := str(run["phase"])
	if mode() == "siege":
		_core_bar.visible = true
		_core_bar.value = float(run["core"]) / CORE_HP
		match phase:
			"prep":
				_c_state.text = "准备……去兵器架捡把好暗器"
			"wave":
				_c_state.text = "第 %d 波 · 还剩 %d 只" % [int(run["wave"]), int(run["left"])]
			"break":
				_c_state.text = "第 %d 波守住了 · 喘口气" % int(run["wave"])
			_:
				_c_state.text = ""
		_c_sub.text = "阵眼 %d / %d · 你斩了 %d 只 · 最高 %d 波" % [int(float(run["core"])), int(CORE_HP), my_kills, best("siege")]
	else:
		_core_bar.visible = false
		var left := maxi(int(MUSOU_TIME) - s, 0)
		_c_state.text = ("准备……" if phase == "prep" else "还剩 %d:%02d" % [left / 60, left % 60])
		_c_sub.text = "全队 %d 斩 · 最多 %d 斩" % [int(run["kills"]), best("musou")]
		if my_kills != _last_kills:
			_last_kills = my_kills
			_big_scale = 1.25
		_big_scale = lerpf(_big_scale, 1.0, 1.0 - exp(-10.0 * dt))
		_big.text = "%d 斩" % my_kills
		_big.pivot_offset = _big.size * 0.5
		_big.scale = Vector2.ONE * _big_scale
		_big_sub.text = "灵爆 %d / %d%s" % [burst, BURST_NEED, "  ·  按 Z" if burst >= BURST_NEED else ""]
		_burst_bar.value = float(burst) / BURST_NEED


func _show_result(m: String, score: int, t: int, money: int, xp: int, kills: int, record: bool, old: int) -> void:
	if not _result:
		var layer := CanvasLayer.new()
		layer.layer = 5
		add_child(layer)
		_result = PanelContainer.new()
		_result.add_theme_stylebox_override("panel", UiKit.glass_style(0.72, 28, 20))
		_result.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiKit.place(_result, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-300, -190, 300, 150))
		layer.add_child(_result)
	for c in _result.get_children():
		c.queue_free()
	var md: Dictionary = MODES[m]
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result.add_child(v)
	v.add_child(UiKit.kicker("试炼 · %s" % md["name"], md["color"], 15))
	var big := ("撑过 %d 波" % score) if m == "siege" else ("%d 斩" % score)
	v.add_child(UiKit.title(big, 48, UiKit.GOLD))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 28)
	g.add_theme_constant_override("v_separation", 4)
	v.add_child(g)
	var rec := "新纪录！" if record else ("最好 %d" % old)
	var rows := [["用时", "%d:%02d" % [t / 60, t % 60]], ["你斩了", "%d 只（全队 %d）" % [my_kills, kills]], ["纪录", rec], ["报酬", "+%d 灵石 · +%d 修为" % [money, xp]]]
	for row in rows:
		g.add_child(UiKit.label(str(row[0]), 16, UiKit.MIST))
		g.add_child(UiKit.bold(str(row[1]), 17, UiKit.MOON))
	v.add_child(UiKit.label("几秒后送回试炼碑", 14, UiKit.MIST))
	_result.visible = true
	_result.modulate.a = 0.0
	var tw := _result.create_tween()
	tw.tween_property(_result, "modulate:a", 1.0, 0.35)
	_result_t = 6.0
