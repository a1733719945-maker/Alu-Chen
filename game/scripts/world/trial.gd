class_name Trial
extends Node
## 试炼（用户："每一关和秘境都是同一个玩法……多加入一些模式，类似 CF 打僵尸……在地上捡武器，然后守在什么地方；
## 还有割草模式，到处都是怪物，但是一打全死"；后来又说守关的图太小、僵尸应该过来打人——"直接参考 CF 的生化追击"）。
##
## 码头边一块试炼碑（地图上「试」），按 F 选一种，队友从同一块碑随时加入：
##   尸潮追击 chase（学 CF 生化追击）：一条近五百米长的古城长街，尸群从后面追、从两边巷子里扑出来，只追人、只咬人。
##     全队边打边往北推：到城门前的守点要守住一段时间（城门慢慢升起来），僵尸一波比一波多，二关、三关还有尸王；
##     过了三道城门，最后在古渡口守到渡船靠岸，就算逃出去了。倒下会在最近的关口站起来，但全队只有几次续命，用完就失败。
##     地上的兵器架（起点三个、每个守点两个）放着带配件的暗器（瞄具、枪口、握把、弹匣……品质越高配件越全、伤害越高），
##     谁都能捡（出了试炼就还回去）。僵尸挨打飘伤害数字、头上有血条，尸王在屏幕上方有大血条。
##   万兽割草 musou：一大片荒原，满地都是小尸，一打就死；三分钟看能斩多少。斩一只攒一格「灵爆」，
##     攒满按 Z：身边一圈全清。记最多斩数。
## 场地在地图外面的高空（跟秘境一样，Island.add_floor / add_floor_rect 让地面高度在这里也对）。同一时间只有一局。
##
## 联机：房主管一局；trst 同步状态，进 trenter / 传送 trin / 离开 trleave / 结束 trend（带结算），
##   兵器架 trrack、开城门 trgate、开始守 trhold、续命 trlife、回血 trheal，尸王砸地走 World.boss_telegraph；
##   僵尸的出生 / 挨打走 Horde（hdsp / hdhit）。

const CHASE := Vector3(-900.0, 420.0, 0.0)   # 长街南头（起点），往北（-z）走
const CHASE_W := 14.0                         # 街的半宽
const CHASE_N := -470.0                       # 北头（渡口）的 z
const GATES := [-110.0, -220.0, -330.0]       # 三道城门的 z
const ESCAPE_Z := -452.0                      # 渡口守点
const HOLD := [30.0, 35.0, 40.0, 45.0]        # 每个守点守多久（最后一个是等船）
const ZONE_HALF := 9.0                        # 守点南北各多长
const MUSOU := Vector3(0.0, 420.0, -900.0)
const MUSOU_R := 62.0
const MUSOU_TIME := 180.0
const PREP := 10.0
const BURST_NEED := 60             # 割草：斩多少只攒满一次灵爆
const BURST_R := 15.0
const MODES := {
	"chase": {"name": "尸潮追击", "kick": "逃出古城", "color": Color(0.45, 1.0, 0.55),
		"desc": "尸群从后面追、从巷子里扑出来。边打边往前推，在三道城门前守住，最后守到渡船靠岸。地上兵器架的暗器带配件，谁都能捡。"},
	"musou": {"name": "万兽割草", "kick": "三分钟", "color": Color(1.0, 0.7, 0.3),
		"desc": "满地都是小尸，一打就死。三分钟能斩多少？斩够 %d 只攒一次灵爆（Z），身边一圈全清。" % BURST_NEED},
}
## 兵器架的品质：名字、颜色、伤害倍数
const QUALITY := [["凡品", Color(0.85, 0.85, 0.85), 1.0], ["灵品", Color(0.4, 0.75, 1.0), 1.35], ["玄品", Color(0.75, 0.45, 1.0), 1.8], ["天品", Color(1.0, 0.75, 0.25), 2.5]]

var world: World
var horde: Horde
var stele := Vector3.INF           # 试炼碑
var run := {}                      # 大家都有：{"mode","phase","cp","hold","t","lives","kills"}
var inside := false
var racks: Array = []              # 追击：[{"pos": Vector3, "id": String, "q": int, "on": {部位: 配件}}]
var my_kills := 0
var burst := 0                     # 割草：灵爆充能
var _return := Vector3.ZERO
var _rack_nodes: Array = []
var _gate_nodes: Array = []        # [[左门, 右门, 门的碰撞]]
var _boat: Node3D
var _chase_obst: Array = []
var _pending: Array = []           # 自己这一帧打中的 [[id, 伤害, peer]]
var _kill_snd_t := 0.0
var _mile := 0
var _gates_open := 0
# 房主
var _members := {}
var _spawn_t := 0.0
var _phase_t := 0.0
var _sync_t := 0.0
var _empty_t := 0.0
var _king_t := 0.0
var _was_dead := {}
var _stats := {}                   # peer -> 斩数（结算用）
# 界面
var _card: PanelContainer
var _c_kick: Label
var _c_state: Label
var _c_sub: Label
var _bar: ProgressBar
var _big: Label                    # 割草：中间上方的大斩数
var _big_sub: Label
var _burst_bar: ProgressBar
var _result: PanelContainer
var _result_t := 0.0
var _plates: Control               # 僵尸头上的血条（Control 画）


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
	_build_chase()
	_build_musou()


func mode() -> String:
	return str(run.get("mode", ""))


func center() -> Vector3:
	return CHASE if mode() == "chase" else MUSOU


func _process(dt: float) -> void:
	if Net.is_host():
		_host(dt)
	elif not run.is_empty() and str(run["phase"]) in ["run", "hold"]:
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
	if inside:
		# 追击：罗盘上标下一个守点
		if mode() == "chase" and not run.is_empty():
			var cp := int(run.get("cp", 0))
			return [[zone_center(cp), "渡" if cp >= GATES.size() else "守", Color(0.5, 1.0, 0.6)]]
		return []
	if stele == Vector3.INF:
		return []
	return [[stele, "试", Color(0.5, 1.0, 0.6)]]


# ------------------------------------------------------------------ 场地：尸潮追击（古城长街）

## 第 i 个守点（0~2 城门前，3 渡口）的中心
func zone_center(i: int) -> Vector3:
	var z: float = ESCAPE_Z if i >= GATES.size() else float(GATES[i]) + ZONE_HALF + 2.0
	return Vector3(CHASE.x, CHASE.y, z)


func in_zone(p: Vector3, i: int) -> bool:
	var c := zone_center(i)
	return absf(p.x - c.x) < CHASE_W + 1.0 and absf(p.z - c.z) < ZONE_HALF and absf(p.y - c.y) < 6.0


## 倒下以后在哪站起来：过了几道门就在最后那道门后面
func cp_spawn(cp: int) -> Vector3:
	if cp <= 0:
		return CHASE + Vector3(randf_range(-3.0, 3.0), 0.5, -2.0)
	return Vector3(CHASE.x + randf_range(-3.0, 3.0), CHASE.y + 0.5, float(GATES[cp - 1]) - 5.0)


func _build_chase() -> void:
	var len := -CHASE_N + 14.0
	var mid := CHASE + Vector3(0, 0, (CHASE_N - 12.0) * 0.5 + 6.0)
	world.island.add_floor_rect(mid, Vector2(CHASE_W + 3.0, len * 0.5 + 2.0))
	var b := world.builder
	# 质感（2026-09-29）：石板路、白墙木框铺面、青砖城墙、钉铜钉的木城门、纸灯笼（MatLib / Props）
	var stone := MatLib.brick(Color(0.95, 0.93, 0.9))
	var dark := MatLib.brick(Color(0.5, 0.49, 0.5))
	var wood := MatLib.planks(Color(1.4, 1.2, 1.05))
	var beam := MatLib.hardwood(Color(0.55, 0.5, 0.48), true)
	var red := MatLib.lacquer(Color(0.5, 0.09, 0.06))
	var ink := MatLib.lacquer(Color(0.05, 0.04, 0.035))
	var tiles := b._tiles(Color(0.24, 0.24, 0.27))
	var walls := [MatLib.plaster(Color(0.82, 0.79, 0.73)), MatLib.plaster(Color(0.72, 0.7, 0.66)), MatLib.plaster(Color(0.78, 0.72, 0.64))]
	var root := Node3D.new()
	root.name = "ChaseArena"
	world.add_child(root)
	root.global_position = CHASE
	var rng := RandomNumberGenerator.new()
	rng.seed = 4400 + world.chapter
	# 路面：一块长石板地（中间一条车辙色的深色带）
	U.part(root, U.box(Vector3(CHASE_W * 2.0 + 6.0, 2.0, len)), dark, Vector3(0, -1.0, (CHASE_N - 12.0) * 0.5 + 6.0))
	b._add_collider(_box_shape(Vector3(CHASE_W * 2.0 + 6.0, 2.0, len)), Transform3D(Basis(), mid + Vector3(0, -1.0, 0)))
	U.part(root, U.box(Vector3(CHASE_W * 2.0, 0.05, len - 4.0)), MatLib.cobble(Color(0.85, 0.84, 0.82)), Vector3(0, 0.02, (CHASE_N - 12.0) * 0.5 + 6.0), Vector3.ZERO, Vector3.ONE, false)
	U.part(root, U.box(Vector3(5.0, 0.06, len - 4.0)), MatLib.cobble(Color(0.6, 0.58, 0.55)), Vector3(0, 0.035, (CHASE_N - 12.0) * 0.5 + 6.0), Vector3.ZERO, Vector3.ONE, false)
	# 两边的房子：一栋栋铺面，飞檐、灯笼、黑洞洞的窗；隔一段有条巷子（尸群从这里扑出来）
	for side: float in [-1.0, 1.0]:
		var z := 8.0
		while z > CHASE_N + 4.0:
			var w := rng.randf_range(8.0, 13.0)
			var h := rng.randf_range(6.0, 9.5)
			var cz := z - w * 0.5
			var x := side * (CHASE_W + 2.0)
			var alley := rng.randf() < 0.22
			if alley:
				# 巷口：暗的，两边一对白灯笼
				U.part(root, U.box(Vector3(4.0, 7.0, w * 0.6)), U.mat(Color(0.02, 0.025, 0.02), 1.0), Vector3(x + side * 1.5, 3.5, cz), Vector3.ZERO, Vector3.ONE, false)
				for s2: float in [-1.0, 1.0]:
					Props.lantern(root, Vector3(x - side * 0.3, 3.2, cz + s2 * w * 0.32), Color(0.85, 1.0, 0.85), 0.9, 0.2)
			else:
				# 铺面：白墙 + 木框（转角柱、楼板梁、檐下梁），一楼是木板门脸
				var fx := x - side * 1.52      # 临街那一面
				U.part(root, U.box(Vector3(4.0, h, w - 0.3)), walls[rng.randi() % walls.size()], Vector3(x + side * 0.5, h * 0.5, cz))
				U.part(root, Props.rbox(Vector3(0.14, 3.0, w - 1.0), 0.03), wood, Vector3(fx, 1.5, cz))
				for yy in [3.05, h - 0.15]:
					U.part(root, Props.rbox(Vector3(0.24, 0.26, w - 0.2), 0.05), beam, Vector3(fx - side * 0.06, yy, cz))
				for s2: float in [-1.0, 1.0]:
					U.part(root, Props.rbox(Vector3(0.3, h, 0.3), 0.05), beam, Vector3(fx - side * 0.05, h * 0.5, cz + s2 * (w * 0.5 - 0.3)))
				var roof := PrismMesh.new()
				roof.size = Vector3(w + 0.6, 1.6, 5.4)
				U.part(root, roof, tiles, Vector3(x + side * 0.4, h + 0.8, cz), Vector3(0, PI * 0.5, 0))
				U.part(root, Props.rbox(Vector3(0.3, 0.2, w + 0.8), 0.05), dark, Vector3(x - side * 2.2, h + 0.05, cz))
				# 门和窗：门是深色漆木 + 门框；楼上的窗是木格子
				U.part(root, Props.rbox(Vector3(0.12, 2.6, 1.6), 0.03), ink, Vector3(fx - side * 0.04, 1.3, cz))
				U.part(root, Props.rbox(Vector3(0.1, 2.8, 1.85), 0.03), beam, Vector3(fx - side * 0.01, 1.4, cz))
				for k in 2:
					var wz := cz + (k - 0.5) * w * 0.5
					U.part(root, Props.rbox(Vector3(0.1, 1.0, 1.3), 0.02), ink, Vector3(fx - side * 0.02, h * 0.62, wz))
					for gx in 3:
						U.part(root, U.box(Vector3(0.06, 1.0, 0.05)), beam, Vector3(fx - side * 0.08, h * 0.62, wz - 0.4 + gx * 0.4))
					U.part(root, U.box(Vector3(0.06, 0.05, 1.3)), beam, Vector3(fx - side * 0.08, h * 0.62, wz))
				# 招牌 + 红灯笼
				U.part(root, Props.rbox(Vector3(0.12, 1.8, 0.7), 0.03), red, Vector3(x - side * 1.7, 3.6, cz + w * 0.3))
				if rng.randf() < 0.6:
					Props.lantern(root, Vector3(x - side * 2.3, 3.0, cz - w * 0.3), Color(1.0, 0.35, 0.2), 1.1, 0.3)
			z -= w
		# 整条街一面墙的碰撞（房子和巷子都挡着，人和僵尸都出不去）
		b._add_collider(_box_shape(Vector3(4.0, 14.0, len)), Transform3D(Basis(), mid + Vector3(side * (CHASE_W + 2.0), 7.0, 0)))
	# 南头：一堵城墙（起点背后）
	U.part(root, U.box(Vector3(CHASE_W * 2.0 + 8.0, 9.0, 3.0)), stone, Vector3(0, 4.5, 11.0))
	b._add_collider(_box_shape(Vector3(CHASE_W * 2.0 + 8.0, 12.0, 3.0)), Transform3D(Basis(), CHASE + Vector3(0, 6.0, 11.0)))
	# 路上的掩体：翻倒的板车、货箱、碎石堆（人能躲、僵尸会绕）
	var z2 := -14.0
	while z2 > CHASE_N + 20.0:
		z2 -= rng.randf_range(9.0, 16.0)
		var near_gate := false
		for g in GATES:
			if absf(z2 - float(g)) < 6.0 or absf(z2 - (float(g) + ZONE_HALF + 2.0)) < ZONE_HALF - 2.0:
				near_gate = true
		if near_gate or absf(z2 - ESCAPE_Z) < 16.0:
			continue
		var x2 := rng.randf_range(-CHASE_W + 3.0, CHASE_W - 3.0)
		var c := Vector3(x2, 0, z2)
		match rng.randi() % 3:
			0:
				var yaw := rng.randf() * TAU
				U.part(root, U.box(Vector3(2.4, 0.9, 1.4)), wood, c + Vector3(0, 0.75, 0), Vector3(0, yaw, 0.35))
				U.part(root, U.cyl(0.5, 0.5, 0.12, 12), wood, c + Vector3(1.0, 0.5, 0.7), Vector3(PI * 0.5, yaw, 0))
				b._add_collider(_box_shape(Vector3(2.4, 1.3, 1.4)), Transform3D(Basis(Vector3.UP, yaw), CHASE + c + Vector3(0, 0.65, 0)))
				_chase_obst.append([Vector2(CHASE.x + c.x, CHASE.z + c.z), 1.4])
			1:
				for k in 3:
					U.part(root, U.box(Vector3(1.0, 1.0, 1.0)), wood, c + Vector3((k % 2) * 1.05, 0.5 + (k / 2) * 1.0, 0), Vector3(0, rng.randf_range(-0.2, 0.2), 0))
				b._add_collider(_box_shape(Vector3(2.1, 2.0, 1.1)), Transform3D(Basis(), CHASE + c + Vector3(0.5, 1.0, 0)))
				_chase_obst.append([Vector2(CHASE.x + c.x + 0.5, CHASE.z + c.z), 1.3])
			_:
				U.part(root, U.sphere(1.3, 8, 6), dark, c + Vector3(0, 0.3, 0), Vector3.ZERO, Vector3(1.4, 0.7, 1.1))
				U.part(root, U.box(Vector3(1.2, 0.8, 0.9)), stone, c + Vector3(0.6, 0.5, 0.3), Vector3(0.3, 0.4, 0.2))
				b._add_collider(_box_shape(Vector3(2.6, 1.2, 2.0)), Transform3D(Basis(), CHASE + c + Vector3(0, 0.6, 0)))
				_chase_obst.append([Vector2(CHASE.x + c.x, CHASE.z + c.z), 1.6])
	# 三道城门：城墙 + 城楼 + 两扇大木门（守住以后门打开）
	for gi in GATES.size():
		var gz := float(GATES[gi])
		var g := Node3D.new()
		root.add_child(g)
		g.position = Vector3(0, 0, gz)
		for s3: float in [-1.0, 1.0]:
			U.part(g, U.box(Vector3(CHASE_W - 4.5, 9.0, 3.2)), stone, Vector3(s3 * (4.5 + (CHASE_W - 4.5) * 0.5), 4.5, 0))
			b._add_collider(_box_shape(Vector3(CHASE_W - 4.5, 12.0, 3.2)), Transform3D(Basis(), CHASE + Vector3(s3 * (4.5 + (CHASE_W - 4.5) * 0.5), 6.0, gz)))
			U.part(g, U.box(Vector3(1.2, 7.0, 3.4)), dark, Vector3(s3 * 4.9, 3.5, 0))
		U.part(g, U.box(Vector3(10.4, 2.0, 3.2)), stone, Vector3(0, 8.0, 0))
		# 城楼：红柱、飞檐
		U.part(g, U.box(Vector3(12.0, 0.4, 5.0)), dark, Vector3(0, 9.2, 0))
		for px: float in [-5.0, -1.7, 1.7, 5.0]:
			U.part(g, U.cyl(0.18, 0.2, 2.8, 8), red, Vector3(px, 10.8, 1.8))
		var roof2 := PrismMesh.new()
		roof2.size = Vector3(14.0, 2.0, 6.5)
		U.part(g, roof2, tiles, Vector3(0, 13.1, 0))
		var plaque := U.label3d("第%s关" % ["一", "二", "三"][gi], 100, Color(1.0, 0.85, 0.45), 0)
		plaque.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		plaque.pixel_size = 0.008
		plaque.position = Vector3(0, 8.0, 1.65)
		g.add_child(plaque)
		var doors: Array = []
		for s4: float in [-1.0, 1.0]:
			var hinge := Node3D.new()
			hinge.position = Vector3(s4 * 4.3, 0, 0.6)
			g.add_child(hinge)
			U.part(hinge, Props.rbox(Vector3(4.2, 7.0, 0.4), 0.05), red, Vector3(-s4 * 2.1, 3.5, 0))
			# 城门钉：九路门钉（一扇 5 × 7）+ 一对铺首衔环
			var stud := MatLib.brass()
			for row in 7:
				for col in 5:
					U.part(hinge, U.sphere(0.075, 8, 6), stud, Vector3(-s4 * (0.45 + col * 0.8), 0.7 + row * 0.95, 0.22), Vector3.ZERO, Vector3(1, 1, 0.6))
			U.part(hinge, U.torus(0.16, 0.22, 16, 6), stud, Vector3(-s4 * 0.35, 3.2, 0.26), Vector3(PI * 0.5, 0, 0))
			doors.append(hinge)
		var sb := StaticBody3D.new()
		sb.collision_layer = U.LAYER_WORLD
		var cs := CollisionShape3D.new()
		cs.shape = _box_shape(Vector3(8.6, 9.0, 1.0))
		sb.add_child(cs)
		root.add_child(sb)
		sb.global_position = CHASE + Vector3(0, 4.5, gz + 0.6)
		doors.append(sb)
		_gate_nodes.append(doors)
		# 守点：地上一个发绿光的符阵，两边火盆
		var zc := zone_center(gi) - CHASE
		_ward(root, zc)
	# 渡口：北头一段木码头伸进水里，守到渡船靠岸
	var pier := Vector3(0, 0, ESCAPE_Z)
	for k in 12:
		U.part(root, U.box(Vector3(10.0, 0.14, 1.0)), wood, pier + Vector3(0, 0.08, -8.0 - k * 1.05))
	b._add_collider(_box_shape(Vector3(10.0, 0.4, 13.0)), Transform3D(Basis(), CHASE + pier + Vector3(0, -0.1, -14.0)))
	var water := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(160.0, 90.0)
	water.mesh = pm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.05, 0.12, 0.14, 0.92)
	wm.roughness = 0.08
	wm.metallic = 0.3
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.material_override = wm
	water.position = Vector3(0, -1.2, CHASE_N - 40.0)
	root.add_child(water)
	# 水边一道看不见的墙（掉不下去）
	b._add_collider(_box_shape(Vector3(CHASE_W * 2.0 + 8.0, 12.0, 1.0)), Transform3D(Basis(), CHASE + Vector3(0, 6.0, CHASE_N - 12.0)))
	_ward(root, zone_center(GATES.size()) - CHASE)
	# 渡船：守的时候从西边慢慢划过来
	_boat = Node3D.new()
	root.add_child(_boat)
	_boat.position = Vector3(-70.0, -1.0, CHASE_N - 16.0)
	var hull := U.part(_boat, U.box(Vector3(12.0, 1.6, 4.0)), wood, Vector3(0, 0.6, 0))
	hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	U.part(_boat, U.box(Vector3(6.0, 2.2, 3.4)), red, Vector3(0.5, 2.4, 0))
	var broof := PrismMesh.new()
	broof.size = Vector3(7.0, 1.2, 4.2)
	U.part(_boat, broof, tiles, Vector3(0.5, 4.1, 0))
	U.part(_boat, U.cyl(0.1, 0.12, 8.0, 8), wood, Vector3(-3.5, 5.0, 0))
	U.part(_boat, U.box(Vector3(0.05, 4.0, 3.0)), MatLib.canvas(Color(0.7, 0.14, 0.09)), Vector3(-3.4, 6.0, 0))
	for s5: float in [-1.0, 1.0]:
		Props.lantern(_boat, Vector3(s5 * 5.5, 2.6, 1.6), Color(1.0, 0.45, 0.2), 1.2, 0.3)
	b._motes(CHASE + Vector3(0, 3.0, -230.0), Vector3(CHASE_W, 3.0, 230.0), 160, Color(0.5, 1.0, 0.6) * 0.4, 0.14)
	# 兵器架：起点三个，每个守点两个（越往后品质越好）
	for x3: float in [-6.0, 0.0, 6.0]:
		_add_rack(root, Vector3(x3, 0, -9.0))
	for zi in GATES.size() + 1:
		var zc2 := zone_center(zi) - CHASE
		for x4: float in [-9.0, 9.0]:
			_add_rack(root, zc2 + Vector3(x4, 0, 2.0))
	# 小零件（窗格、灯笼、门钉、木框）70 米外不画：长街几千个零件，全画会掉帧
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var gi := mi as MeshInstance3D
		if gi.mesh and gi.visibility_range_end == 0.0 and gi.mesh.get_aabb().size.length() * gi.global_transform.basis.get_scale().length() < 5.0:
			gi.visibility_range_end = 70.0


## 守点的符阵：地上一个绿光法阵 + 两个火盆
func _ward(root: Node3D, c: Vector3) -> void:
	var m := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12.0, 12.0)
	m.mesh = pm
	m.material_override = FxLib.quad_mat("magic", Color(0.45, 1.0, 0.55), 1.1, true)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.position = c + Vector3(0, 0.07, 0)
	root.add_child(m)
	var tw := m.create_tween().set_loops()
	tw.tween_property(m, "rotation:y", TAU, 30.0).as_relative()
	for sx: float in [-1.0, 1.0]:
		U.part(root, U.cyl(0.5, 0.35, 1.0, 8), world.builder._stone(Color(0.3, 0.3, 0.32)), c + Vector3(sx * 6.0, 0.5, -4.0))
		U.part(root, U.sphere(0.35, 10, 8), U.glow(Color(1.0, 0.55, 0.2), 5.0), c + Vector3(sx * 6.0, 1.3, -4.0), Vector3.ZERO, Vector3(1, 1.4, 1), false)
		var fl := OmniLight3D.new()
		fl.light_color = Color(1.0, 0.6, 0.3)
		fl.light_energy = 1.6
		fl.omni_range = 12.0
		fl.position = c + Vector3(sx * 6.0, 2.2, -4.0)
		root.add_child(fl)


func _add_rack(root: Node3D, c: Vector3) -> void:
	var wood := world.builder._wood(Color(0.45, 0.3, 0.2))
	var dark := world.builder._stone(Color(0.22, 0.21, 0.22))
	racks.append({"pos": CHASE + c, "id": "", "q": 0, "on": {}})
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
	cm.top_radius = 0.05
	cm.bottom_radius = 0.16      # 细细一道光（以前半径 0.7，一排三根挡住整条街）
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
	if mode() == "chase":
		return CHASE + Vector3(0, 0.5, -2.0)
	return MUSOU + Vector3(0, 0.6, 0)


# ------------------------------------------------------------------ 进出

func interactables() -> Array:
	var out: Array = []
	if inside:
		if mode() == "chase":
			var me: Vector3 = world.player.global_position
			for i in racks.size():
				var r: Dictionary = racks[i]
				if str(r["id"]) == "" or (r["pos"] as Vector3).distance_to(me) > 6.0:
					continue
				var q: Array = QUALITY[int(r["q"])]
				var have: bool = world.player.trial_gun == str(r["id"]) and world.player.trial_attach == r["on"] and is_equal_approx(world.player.trial_k, float(q[2]))
				out.append({"id": "trrack", "i": i, "pos": (r["pos"] as Vector3) + Vector3(0, 1.4, 0), "r": 2.6,
					"text": ("已经拿着【%s】" % rack_name(i)) if have else ("按 F 捡起【%s】%s" % [rack_name(i), rack_attach_text(i)]), "act": not have})
		out.append({"id": "trexit", "pos": spawn_pad() + Vector3(0, 1.0, 0), "r": 2.5,
			"text": "按 F 离开试炼" + ("（还在打，出去就算你放弃）" if not run.is_empty() else ""), "act": true})
		return out
	if stele != Vector3.INF:
		var txt := "按 F 打开试炼（尸潮追击 / 万兽割草）"
		if not run.is_empty():
			txt = "按 F 加入%s（队友在里面）" % MODES[mode()]["name"]
		out.append({"id": "trstele", "pos": stele + Vector3(0, 1.4, 0), "r": 3.2, "text": txt, "act": true})
	return out


func rack_name(i: int) -> String:
	var r: Dictionary = racks[i]
	return "%s · %s" % [QUALITY[int(r["q"])][0], Data.WEAPONS[str(r["id"])]["name"]]


## "（全息瞄具 · 制退器 · 扩容弹匣，伤害 ×1.8）"
func rack_attach_text(i: int) -> String:
	var r: Dictionary = racks[i]
	var names: Array = []
	for s in Data.ATTACH_SLOTS:
		var a := str((r["on"] as Dictionary).get(s[0], ""))
		if a != "" and Data.ATTACH.has(a):
			names.append(Data.ATTACH[a]["name"])
	var k := float(QUALITY[int(r["q"])][2])
	return "（%s%s）" % [" · ".join(names), ("，伤害 ×%.2f" % k) if k > 1.0 else ""]


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


## 追击的纪录写成字："逃出生天" / "过了 2 道城门"
func best_text(m: String) -> String:
	var b := best(m)
	if m == "musou":
		return "最多 %d 斩" % b
	if b > GATES.size():
		var t := int(Profile.stats.get("chase_time_%d" % world.chapter, 0))
		return "逃出生天 · 最快 %d:%02d" % [t / 60, t % 60]
	return "最远过了 %d 道城门" % b


func _new_run(m: String) -> Dictionary:
	return {"mode": m, "phase": "prep", "cp": 0, "hold": 0.0, "t": 0.0, "lives": 2 + _team(), "kills": 0}


## 被房主传送进来
func enter(m: String) -> void:
	if inside:
		return
	if run.is_empty():
		run = _new_run(m)
	inside = true
	my_kills = 0
	burst = 0
	_mile = 0
	_return = stele + Vector3(0, 0.6, 2.5) if stele != Vector3.INF else world.player.global_position
	_setup_horde()
	_apply_gates(int(run.get("cp", 0)), true)
	var pl := world.player
	pl.teleport((cp_spawn(int(run.get("cp", 0))) if m == "chase" else spawn_pad()) + Vector3(randf_range(-1.5, 1.5), 0.2, randf_range(-1.0, 1.0)))
	pl.look_to(0.0, deg_to_rad(-2))
	var md: Dictionary = MODES[m]
	world.fx.aura_burst(pl.global_position, md["color"], 3.0)
	Sfx.play("absorb", -4.0, 0.0, 0.7)
	world.hud._show_banner(str(md["name"]), str(md["desc"]), md["color"], 5.0)
	world.hud.flash(Color(0.4, 1.0, 0.5, 0.35))


func _setup_horde() -> void:
	horde.clear()
	horde.center = center()
	horde.goal = Vector3.INF
	horde.chase_r = 1e9
	if mode() == "chase":
		horde.radius = 1e6
		horde.obstacles = _chase_obst
		_update_bounds()
		horde.dmg_k = 1.0
	else:
		horde.radius = MUSOU_R
		horde.bounds = Rect2()
		horde.obstacles = []
		horde.dmg_k = 0.6


## 僵尸能跑的地方：南头到下一道还关着的城门
func _update_bounds() -> void:
	var cp := int(run.get("cp", 0))
	var north: float = (float(GATES[cp]) + 0.8) if cp < GATES.size() else CHASE_N - 2.0
	horde.bounds = Rect2(CHASE.x - CHASE_W, north, CHASE_W * 2.0, 10.0 - north)


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
	# 倒下了：还在打就在最近的关口 / 场地里站起来（续命房主扣；割草灵爆充能清零），打完了就回码头
	if inside and not run.is_empty():
		world.player.teleport(cp_spawn(int(run.get("cp", 0))) if mode() == "chase" else spawn_pad())
		burst = 0
		return
	leave(false)


func _drop_trial_gun() -> void:
	var p := world.player
	if p.trial_gun != "":
		p.trial_gun = ""
		p.trial_k = 1.0
		p.trial_attach = {}
		p.viewmodel.attach_override = {}
		p.viewmodel.apply_look()
		p.rebuild_guns()


## 捡兵器架上的暗器：换成它（带它自己的配件；出了试炼还回去）
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
	p.trial_attach = (r["on"] as Dictionary).duplicate()
	p.viewmodel.attach_override = {id: p.trial_attach}
	p.viewmodel.apply_look()
	p.rebuild_guns()
	for gi in p.guns.size():
		if p.guns[gi].id == id:
			p.switch_weapon(gi)
			break
	world.hud.toast("捡起【%s】%s" % [rack_name(i), rack_attach_text(i)], q[1], 2.5)
	world.fx.aura_burst((r["pos"] as Vector3) + Vector3(0, 1.4, 0), q[1], 1.5)
	Sfx.play("pickup", -2.0)
	Sfx.play("rack", -4.0)


# ------------------------------------------------------------------ 房主

func host_enter(from: int, m: String) -> void:
	if not MODES.has(m):
		return
	if not run.is_empty() and mode() != m:
		return
	if run.is_empty():
		_members.clear()
		_stats.clear()
		_was_dead.clear()
		_members[from] = true
		run = _new_run(m)
		_phase_t = PREP if m == "chase" else 5.0
		_empty_t = 0.0
		horde.next_id = 1
		if m == "chase":
			_host_roll_racks()
			_apply_gates(0, true)
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
		st = [mode(), str(run["phase"]), int(run["cp"]), float(run["hold"]), float(run["t"]), int(run["lives"]), int(run["kills"])]
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
	if _members.is_empty():
		_empty_t += dt
		if _empty_t > 4.0:
			_end_run(false)
		return
	_empty_t = 0.0
	var phase := str(run["phase"])
	if phase in ["run", "hold"]:
		run["t"] = float(run["t"]) + dt
	match mode():
		"chase":
			_host_chase(dt, phase)
		"musou":
			_host_musou(dt, phase)
	_sync_t -= dt
	if _sync_t <= 0.0:
		_sync()


## 这一章的参照（奖励、血量都按它算）
func _ref() -> Array:
	var sp: Array = world._map_species()
	return [str(sp[0]) if not sp.is_empty() else "rabbit", int(Data.CH_AGE.get(world.chapter, 0))]


## 僵尸血量：按全队最强暗器一发的伤害算（跳尸 3 发、疾尸 2 发、铁尸 9 发、尸王 60 发），越往后越厚
func _unit_hp(kind: int, lvl: int) -> float:
	var o := world.team_output()
	var shot := maxf(o.x, 10.0)
	var k := 1.0 + 0.16 * (lvl - 1)
	match kind:
		0:
			return 1.0
		1:
			return shot * 2.6 * k
		4:
			return shot * 1.8 * k
		2:
			return shot * 8.0 * k
		_:
			return shot * 55.0 * k * (1.0 + 0.5 * (_team() - 1))


## 在场的（进了试炼、没倒下）人的位置
func _alive_inside() -> Array:
	return world.alive_players().filter(func(p): return _members.has(int(p["peer"])) and absf((p["pos"] as Vector3).x - CHASE.x) < CHASE_W + 6.0 and (p["pos"] as Vector3).z < 20.0 and (p["pos"] as Vector3).z > CHASE_N - 20.0)


func _host_chase(dt: float, phase: String) -> void:
	# 续命：谁新倒下了，扣一次；扣完了还有人倒下就失败
	for pl in world.all_players():
		var peer := int(pl["peer"])
		if not _members.has(peer):
			continue
		var dead := not bool(pl["alive"])
		if dead and not bool(_was_dead.get(peer, false)) and phase in ["run", "hold"]:
			run["lives"] = int(run["lives"]) - 1
			Net.send(0, "trlife", [int(run["lives"]), peer])
			_on_life([int(run["lives"]), peer])
			if int(run["lives"]) < 0:
				_end_run(false)
				return
		_was_dead[peer] = dead
	var cp := int(run["cp"])
	match phase:
		"prep":
			_phase_t -= dt
			if _phase_t <= 0.0:
				run["phase"] = "run"
				_sync()
		"run":
			_host_chase_spawn(dt, false)
			# 有人走进守点：开始守
			for p in _alive_inside():
				if in_zone(p["pos"], cp):
					run["phase"] = "hold"
					run["hold"] = 0.0
					_king_t = 2.0
					var kings := 0
					if cp == 1 or cp == GATES.size():
						kings = 1 if _team() < 3 else 2
					var msg := [cp, kings]
					Net.send(0, "trhold", msg)
					_on_hold(msg)
					if kings > 0:
						var batch: Array = []
						for i in kings:
							var sp := _spawn_point(false)
							batch.append([0, sp.x, sp.z, 3, _unit_hp(3, 1 + cp * 2)])
						horde.host_spawn(batch)
					_sync()
					break
		"hold":
			_host_chase_spawn(dt, true)
			_host_kings(dt)
			# 守点里有活人才算时间（人都跑开了就停下）
			var any := false
			for p in _alive_inside():
				if in_zone(p["pos"], cp):
					any = true
					break
			if any:
				run["hold"] = float(run["hold"]) + dt
			if float(run["hold"]) >= float(HOLD[mini(cp, HOLD.size() - 1)]):
				if cp >= GATES.size():
					_end_run(true)
				else:
					_open_gate(cp)


## 出僵尸：身后追上来的 + 前面巷子里扑出来的（守的时候更多）
func _host_chase_spawn(dt: float, hold: bool) -> void:
	var cp := int(run["cp"])
	var team := _team()
	var want := (22 + 6 * cp + 7 * (team - 1)) if hold else (12 + 4 * cp + 5 * (team - 1))
	_spawn_t -= dt
	if _spawn_t > 0.0 or horde.alive_count() >= mini(want, Horde.MAX - 10):
		return
	_spawn_t = 0.45 if hold else 0.7
	if _alive_inside().is_empty():
		return
	var batch: Array = []
	for i in (3 if hold else 2):
		var sp := _spawn_point(randf() < (0.35 if hold else 0.5))
		var r := randf()
		var kind := 1
		if r < 0.08 + 0.05 * cp:
			kind = 2
		elif r < 0.22 + 0.1 * cp:
			kind = 4
		batch.append([0, sp.x, sp.z, kind, _unit_hp(kind, 1 + cp * 2)])
	horde.host_spawn(batch)


## ahead = true：前面的巷子口；false：后面追上来
func _spawn_point(ahead: bool) -> Vector3:
	var pls := _alive_inside()
	var front := 20.0
	var rear := -1e9
	for p in pls:
		front = minf(front, (p["pos"] as Vector3).z)
		rear = maxf(rear, (p["pos"] as Vector3).z)
	var cp := int(run["cp"])
	var north: float = (float(GATES[cp]) + 1.5) if cp < GATES.size() else CHASE_N - 1.0
	var z: float
	var x: float
	if ahead:
		z = clampf(front - randf_range(14.0, 34.0), north, 8.0)
		x = CHASE.x + (CHASE_W - 1.2) * (1.0 if randf() < 0.5 else -1.0)
	else:
		z = clampf(rear + randf_range(20.0, 32.0), north, 8.0)
		x = CHASE.x + randf_range(-CHASE_W + 2.0, CHASE_W - 2.0)
	return Vector3(x, CHASE.y, z)


func _open_gate(cp: int) -> void:
	run["cp"] = cp + 1
	run["phase"] = "run"
	run["hold"] = 0.0
	var ref := _ref()
	var money := roundi(Data.kill_money(ref[0], ref[1]) * (3.0 + 2.0 * cp) * Data.KILL_MONEY)
	var xp := roundi(Data.kill_xp(ref[0], ref[1]) * (3.0 + 2.0 * cp))
	var msg := [cp + 1, money, xp]
	Net.send(0, "trgate", msg)
	_on_gate(msg)
	_sync()


## 兵器架：起点凡品 / 灵品，越往后越好；每把按品质配上配件
func _host_roll_racks() -> void:
	var pool: Array = []
	for id in Data.WEAPON_ORDER:
		if id in Data.SIDEARMS:
			continue
		pool.append(id)
	for i in racks.size():
		var r: Dictionary = racks[i]
		var tier := 0 if i < 3 else 1 + (i - 3) / 2
		var q := 0
		match tier:
			0:
				q = 0 if randf() < 0.6 else 1
			1:
				q = 1
			2:
				q = 1 if randf() < 0.5 else 2
			3:
				q = 2
			_:
				q = 2 if randf() < 0.5 else 3
		var id := str(pool[randi() % pool.size()])
		r["id"] = id
		r["q"] = q
		r["on"] = roll_attach(id, q)
	var m := _rack_msg()
	Net.send(0, "trrack", m)
	_on_racks(m)


## 按品质给一把暗器配配件：凡品一个瞄具；灵品 + 枪口；玄品 + 枪管下、弹匣；天品全套
static func roll_attach(id: String, q: int) -> Dictionary:
	var ok: Array = Data.ATTACH_OK.get(id, [])
	var by_slot := {}
	for a in ok:
		var slot := str(Data.ATTACH[a]["slot"])
		if not by_slot.has(slot):
			by_slot[slot] = []
		by_slot[slot].append(a)
	var want := ["sight"]
	if q >= 1:
		want.append("muzzle")
	if q >= 2:
		want.append_array(["under", "mag"])
	if q >= 3:
		want.append("stock")
	var on := {}
	for slot in want:
		var opts: Array = by_slot.get(slot, [])
		if opts.is_empty():
			continue
		if slot == "sight":
			# 狙击 / 射手优先高倍镜，别的优先红点、全息
			var pref: Array = ["scope", "x4"] if id in ["zhuihun", "longxu", "kongque"] else ["holo", "red", "x2"]
			var pick := ""
			for pa in pref:
				if pa in opts:
					pick = pa
					break
			on[slot] = pick if pick != "" and randf() < 0.8 else opts[randi() % opts.size()]
		elif slot == "muzzle" and "silencer" in opts and opts.size() > 1:
			# 消音器会没有枪口火光，打僵尸不爽：少出
			var o2: Array = opts.filter(func(a): return a != "silencer")
			on[slot] = o2[randi() % o2.size()]
		else:
			on[slot] = opts[randi() % opts.size()]
	return on


func _rack_msg() -> Array:
	var m: Array = []
	for r in racks:
		m.append([str(r["id"]), int(r["q"]), r["on"]])
	return m


## 尸王：隔几秒砸一下离它最近的人（地上红圈，看到就跑）
func _host_kings(dt: float) -> void:
	_king_t -= dt
	if _king_t > 0.0:
		return
	_king_t = 3.0
	for u in horde.units:
		if int(u["kind"]) != 3:
			continue
		var p: Vector3 = u["p"]
		var tp := world.nearest_player(p)
		if tp.is_empty() or (tp["pos"] as Vector3).distance_to(p) > 16.0:
			continue
		var at: Vector3 = tp["pos"]
		at.y = CHASE.y
		var dmg := Profile.max_hp() * 0.3 / float(Data.CH_POWER.get(world.chapter, 1.0))
		world.boss_telegraph(at, 5.0, 1.3, dmg, "slam", p)
		u["cd"] = 2.0
		var tw := create_tween()
		tw.tween_interval(1.25)
		tw.tween_callback(func():
			Net.send(0, "trslam", [at])
			_on_slam([at]))


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
				_end_run(true)
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


## 结束：追击 won = 逃出去了；割草时间到（won 没用）
func _end_run(won: bool) -> void:
	if run.is_empty():
		return
	var m := mode()
	var ref := _ref()
	var kills := int(run["kills"])
	var score := kills
	var money := 0
	var xp := 0
	if m == "musou":
		money = roundi(Data.kill_money(ref[0], ref[1]) * kills * 0.12 * Data.KILL_MONEY)
		xp = roundi(Data.kill_xp(ref[0], ref[1]) * kills * 0.12)
	else:
		# 追击的成绩：过了几道城门，逃出去算 4
		score = GATES.size() + 1 if won else int(run["cp"])
		var k := 2.0 + score * 2.5 + (8.0 if won else 0.0)
		money = roundi(Data.kill_money(ref[0], ref[1]) * k * Data.KILL_MONEY)
		xp = roundi(Data.kill_xp(ref[0], ref[1]) * k)
	var msg := [m, score, int(float(run["t"])), money, xp, kills, won]
	run = {}
	_members.clear()
	Net.send(0, "trend", msg)
	_on_end(msg)
	_sync()


# ------------------------------------------------------------------ 打中 / 打死

## 自己开枪：一条射线上的僵尸（World.local_fire 调）。每一下都飘伤害数字
func shot(origin: Vector3, end: Vector3, w: Dictionary, dmg_mult: float, pierce: int) -> void:
	if not inside:
		return
	var n := pierce + (2 if mode() == "musou" else 0)
	for h in horde.ray_hits(origin, end, n):
		var id := int(h[0])
		var dist := float(h[1])
		var head := bool(h[2])
		var dmg := float(w["damage"]) * world._falloff(w, dist) * (float(w["headshot"]) if head else 1.0) * dmg_mult
		_pending.append([id, dmg, Net.my_id])
		var u: Dictionary = horde.by_id.get(id, {})
		if u.is_empty():
			continue
		var p: Vector3 = u["p"]
		var s: float = Horde.SCALE[int(u["kind"])]
		world.fx.impact_beast(p + Vector3.UP * (1.65 if head else 1.1) * s, (origin - p).normalized(), Color(0.5, 1.0, 0.6), head)
		var kill := float(u["hp"]) - dmg <= 0.0
		# 割草里小尸一打就死，满屏数字太乱：只飘铁尸和爆头
		if mode() == "chase" or int(u["kind"]) >= 2 or head:
			world.fx.damage_number(p + Vector3.UP * 1.9 * s, dmg, head, kill, true)
		world.hud.hitmarker(head, kill)
		Sfx.play("hit_head" if head else "hit", -8.0, 0.08)


## 爆炸（子母雷珠、雷莲）
func blast(at: Vector3, r: float, dmg: float) -> void:
	if not inside:
		return
	for id in horde.in_sphere(at, r):
		_pending.append([id, dmg, Net.my_id])
		var u: Dictionary = horde.by_id.get(id, {})
		if not u.is_empty() and mode() == "chase":
			world.fx.damage_number((u["p"] as Vector3) + Vector3.UP * 1.9, dmg, false, float(u["hp"]) - dmg <= 0.0, true)


## 拳头：面前一小片
func melee(origin: Vector3, dir: Vector3, reach: float, dmg: float) -> void:
	if not inside:
		return
	var c := origin + dir * (reach * 0.6)
	for id in horde.in_sphere(Vector3(c.x, origin.y - 1.0, c.z), maxf(reach * 0.6, 1.4)):
		_pending.append([id, dmg, Net.my_id])
		world.hud.hitmarker(false, false)
		var u: Dictionary = horde.by_id.get(id, {})
		if not u.is_empty():
			world.fx.damage_number((u["p"] as Vector3) + Vector3.UP * 1.9, dmg, false, float(u["hp"]) - dmg <= 0.0, true)


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
	if kind == 3:
		world.hud._show_banner("尸王倒下了", "", Color(1.0, 0.75, 0.3), 1.8)
		Sfx.play("level_up", -3.0, 0.0, 0.9)
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
		"trgate":
			_on_gate(data)
		"trhold":
			_on_hold(data)
		"trlife":
			_on_life(data)
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
	var old_cp := int(run.get("cp", 0))
	run = {"mode": str(d[0]), "phase": str(d[1]), "cp": int(d[2]), "hold": float(d[3]), "t": float(d[4]), "lives": int(d[5]), "kills": int(d[6])}
	if int(run["cp"]) != old_cp or _gates_open != int(run["cp"]):
		_apply_gates(int(run["cp"]), true)


func _on_racks(d: Array) -> void:
	for i in mini(d.size(), racks.size()):
		racks[i]["id"] = str(d[i][0])
		racks[i]["q"] = int(d[i][1])
		racks[i]["on"] = (d[i][2] as Dictionary) if d[i].size() > 2 and d[i][2] is Dictionary else {}
		var nodes: Array = _rack_nodes[i]
		var holder: Node3D = nodes[1]
		for c in holder.get_children():
			c.queue_free()
		var id := str(d[i][0])
		if id == "":
			continue
		var q: Array = QUALITY[int(d[i][1])]
		var wm := WeaponModels.build(id, "", "", racks[i]["on"], false)
		wm.scale = Vector3.ONE * 2.2
		holder.add_child(wm)
		if not holder.has_meta("spin"):
			holder.set_meta("spin", true)
			var tw := holder.create_tween().set_loops()
			tw.tween_property(holder, "rotation:y", TAU, 4.0).as_relative()
		var beam: MeshInstance3D = nodes[2]
		beam.material_override = FxLib.smat("pillar", {"color": q[1], "hdr": 0.9 + int(d[i][1]) * 0.45, "half_h": 3.0, "speed": 1.0, "top": 0.0, "rim_k": 0.7})
		(nodes[3] as OmniLight3D).light_color = q[1]


## 城门开到第 n 道（instant：进来 / 同步时直接摆好，不播动画）
func _apply_gates(n: int, instant: bool) -> void:
	for i in _gate_nodes.size():
		var open := i < n
		var nodes: Array = _gate_nodes[i]
		var sb: StaticBody3D = nodes[2]
		sb.process_mode = Node.PROCESS_MODE_DISABLED if open else Node.PROCESS_MODE_INHERIT
		(sb.get_child(0) as CollisionShape3D).disabled = open
		for k in 2:
			var hinge: Node3D = nodes[k]
			var s := -1.0 if k == 0 else 1.0
			var want := s * 1.7 if open else 0.0
			if instant or i < _gates_open:
				hinge.rotation.y = want
			else:
				var tw := hinge.create_tween()
				tw.tween_property(hinge, "rotation:y", want, 2.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_gates_open = n
	if inside and mode() == "chase":
		_update_bounds()


func _on_gate(d: Array) -> void:
	var n := int(d[0])
	if not run.is_empty():
		run["cp"] = n
		run["phase"] = "run"
	_apply_gates(n, false)
	if not inside:
		return
	world._gain(int(d[1]), int(d[2]))
	# 过关：全队回四成血
	var p := world.player
	if not p.dead:
		p.hp = minf(p.hp + Profile.max_hp() * 0.4, Profile.max_hp())
	world.hud._show_banner("第%s关 · 城门开了" % ["一", "二", "三"][clampi(n - 1, 0, 2)], "往前冲！+%d 灵石 · 回了四成血" % int(d[1]), UiKit.GOLD, 2.4)
	Sfx.play("quest_done", -2.0)
	Sfx.play("boom", -6.0, 0.0, 0.5)
	var gz := float(GATES[n - 1])
	world.fx.aura_burst(Vector3(CHASE.x, CHASE.y + 2.0, gz), Color(0.5, 1.0, 0.6), 6.0)
	world.fx._shake(Vector3(CHASE.x, CHASE.y, gz), 0.5, 40.0)


func _on_hold(d: Array) -> void:
	var cp := int(d[0])
	if not run.is_empty():
		run["phase"] = "hold"
		run["hold"] = 0.0
	if not inside:
		return
	var final := cp >= GATES.size()
	world.hud._show_banner("守住渡口！" if final else "守住！", ("渡船 %d 秒后靠岸" if final else "城门 %d 秒后打开") % int(HOLD[mini(cp, HOLD.size() - 1)]) + ("  ·  尸王来了！" if int(d[1]) > 0 else ""), Color(1.0, 0.45, 0.3), 2.4)
	Sfx.play("boss_roar", -2.0, 0.0, 1.1 if int(d[1]) == 0 else 0.8)
	if final and _boat:
		_boat.position = Vector3(-70.0, -1.0, CHASE_N - 16.0)
		var tw := _boat.create_tween()
		tw.tween_property(_boat, "position:x", 0.0, float(HOLD[HOLD.size() - 1])).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _on_life(d: Array) -> void:
	if not run.is_empty():
		run["lives"] = int(d[0])
	if not inside:
		return
	var nm := world.peer_name(int(d[1])) if int(d[1]) != Net.my_id else "你"
	var left := int(d[0])
	world.hud.toast("%s倒下了 · %s" % [nm, ("还剩 %d 次续命" % left) if left >= 0 else "续命用完了"], Color(1.0, 0.45, 0.35), 2.5)


func _on_slam(d: Array) -> void:
	if inside:
		world.fx.slam(d[0], 5.0)
		Sfx.play_at("boom", d[0], 2.0, 0.1, 0.8)


func _on_end(d: Array) -> void:
	var m := str(d[0])
	var was := inside
	run = {}
	horde.clear()
	_apply_gates(0, true)
	if _boat:
		_boat.position = Vector3(-70.0, -1.0, CHASE_N - 16.0)
	if not was:
		return
	var score := int(d[1])
	var t := int(d[2])
	var money := int(d[3])
	var xp := int(d[4])
	var kills := int(d[5])
	var won: bool = d.size() > 6 and bool(d[6])
	world._gain(money, xp)
	var key := best_key(m)
	var old := int(Profile.stats.get(key, 0))
	var record := score > old
	if record:
		Profile.stats[key] = score
	if m == "chase" and won:
		var tk := "chase_time_%d" % world.chapter
		var ot := int(Profile.stats.get(tk, 0))
		if ot == 0 or t < ot:
			Profile.stats[tk] = t
			record = true
	Profile.mark_dirty()
	Profile.count("trials")
	if m == "musou" or won:
		world.lock_music("victory", 25.0)
		Sfx.play("quest_done", 2.0)
		world.hud.flash(Color(1.0, 0.82, 0.35, 0.35))
	else:
		Sfx.play("boss_roar", 0.0, 0.0, 0.7)
	_show_result(m, score, t, money, xp, kills, record, old, won)


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
	if _plates:
		_plates.queue_redraw()
	if _result:
		_result_t -= dt
		if _result_t <= 0.0:
			_result.visible = false
	if not inside:
		return
	if Input.is_action_just_pressed("true_body") and world.player.input_enabled:
		_burst_now()
	var p := world.player
	var pp := p.global_position
	var out_of := false
	if mode() == "chase":
		out_of = pp.y < CHASE.y - 6.0 or absf(pp.x - CHASE.x) > CHASE_W + 6.0 or pp.z > 16.0 or pp.z < CHASE_N - 14.0
	else:
		out_of = pp.y < MUSOU.y - 6.0 or Vector2(pp.x - MUSOU.x, pp.z - MUSOU.z).length() > MUSOU_R + 4.0
	if not p.dead and out_of:
		p.teleport(cp_spawn(int(run.get("cp", 0))) if mode() == "chase" else spawn_pad())
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
	_bar = UiKit.bar(Color(0.5, 1.0, 0.6), 240.0, 8.0)
	v.add_child(_bar)
	# 割草：上方正中的大斩数 + 灵爆条
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	# 僵尸头上的血条（在 HUD 下面一层）
	_plates = Control.new()
	_plates.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_plates)
	UiKit.fill(_plates)
	_plates.draw.connect(_draw_plates)
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


## 僵尸头上的血条：最近 4 秒挨过打的、铁尸（一直显示），40 米内、在镜头前面；尸王在屏幕上方一条大血条
func _draw_plates() -> void:
	if not inside or horde.units.is_empty():
		return
	var cam := world.get_viewport().get_camera_3d()
	if cam == null:
		return
	var me := cam.global_position
	var fwd := -cam.global_basis.z
	var vs := _plates.size
	var king: Dictionary = {}
	for u in horde.units:
		var k := int(u["kind"])
		if k == 0:
			continue
		if k == 3 and (king.is_empty() or float(u["hp"]) < float(king["hp"])):
			king = u
		var p: Vector3 = u["p"]
		var s: float = Horde.SCALE[k]
		var top := p + Vector3.UP * (2.15 * s)
		var d := top.distance_to(me)
		if d > 40.0 or (top - me).dot(fwd) < 0.5:
			continue
		if float(u["hit_t"]) > 4.0 and k != 2:
			continue
		var sp := cam.unproject_position(top)
		var w := clampf(70.0 * (1.0 + (s - 1.0) * 0.6) * clampf(14.0 / d, 0.45, 1.2), 26.0, 110.0)
		var h := 5.0 if k != 3 else 7.0
		var frac := clampf(float(u["hp"]) / maxf(float(u["max"]), 1.0), 0.0, 1.0)
		var r := Rect2(sp - Vector2(w * 0.5, h), Vector2(w, h))
		_plates.draw_rect(r.grow(1.0), Color(0, 0, 0, 0.65))
		var col := Color(0.95, 0.3, 0.25) if k != 4 else Color(1.0, 0.55, 0.2)
		_plates.draw_rect(Rect2(r.position, Vector2(w * frac, h)), col)
		if d < 22.0:
			_plates.draw_string(Data.font_bold, sp + Vector2(-w * 0.5, -h - 3.0), Horde.NAMES[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.8))
	# 尸王：上方正中的大血条
	if not king.is_empty():
		var bw := minf(vs.x * 0.42, 620.0)
		var bx := (vs.x - bw) * 0.5
		var by := 92.0
		var fk := clampf(float(king["hp"]) / maxf(float(king["max"]), 1.0), 0.0, 1.0)
		_plates.draw_string(Data.font_title, Vector2(bx, by - 8.0), "尸王", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1.0, 0.85, 0.6))
		_plates.draw_rect(Rect2(bx - 2, by - 2, bw + 4, 14), Color(0, 0, 0, 0.7))
		_plates.draw_rect(Rect2(bx, by, bw * fk, 10), Color(0.85, 0.15, 0.1))
		_plates.draw_rect(Rect2(bx, by, bw, 10), Color(1.0, 0.8, 0.5, 0.5), false, 1.0)


var _big_scale := 1.0
var _last_kills := 0


func _update_ui(dt: float) -> void:
	var box: Control = _big.get_meta("box")
	_card.visible = inside and not run.is_empty()
	box.visible = inside and mode() == "musou"
	if not _card.visible:
		return
	var md: Dictionary = MODES.get(mode(), MODES["chase"])
	_c_kick.text = "试炼 · %s" % md["name"]
	var s := int(float(run["t"]))
	var phase := str(run["phase"])
	if mode() == "chase":
		var cp := int(run.get("cp", 0))
		var final := cp >= GATES.size()
		_bar.visible = phase == "hold"
		match phase:
			"prep":
				_c_state.text = "准备……去兵器架捡把好暗器"
			"run":
				_c_state.text = ("往北冲，到渡口！" if final else "往北冲，到第%s道城门前守住" % ["一", "二", "三"][cp])
			"hold":
				var need := float(HOLD[mini(cp, HOLD.size() - 1)])
				var left := maxi(int(ceil(need - float(run.get("hold", 0.0)))), 0)
				_c_state.text = ("守住！渡船 %d 秒后靠岸" if final else "守住！城门 %d 秒后打开") % left
				_bar.value = float(run.get("hold", 0.0)) / need
		_c_sub.text = "续命 %d · 你斩了 %d · %d:%02d · %s" % [maxi(int(run.get("lives", 0)), 0), my_kills, s / 60, s % 60, best_text("chase")]
	else:
		_bar.visible = false
		var left2 := maxi(int(MUSOU_TIME) - s, 0)
		_c_state.text = ("准备……" if phase == "prep" else "还剩 %d:%02d" % [left2 / 60, left2 % 60])
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


func _show_result(m: String, score: int, t: int, money: int, xp: int, kills: int, record: bool, old: int, won: bool) -> void:
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
	var big := "%d 斩" % score
	if m == "chase":
		big = "逃出生天" if won else ("倒在第%s关" % ["一", "二", "三", "四"][clampi(score, 0, 3)])
	v.add_child(UiKit.title(big, 48, UiKit.GOLD if (won or m == "musou") else UiKit.RED))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 28)
	g.add_theme_constant_override("v_separation", 4)
	v.add_child(g)
	var rec := "新纪录！" if record else (best_text(m))
	var rows := [["用时", "%d:%02d" % [t / 60, t % 60]], ["你斩了", "%d 只（全队 %d）" % [my_kills, kills]], ["纪录", rec], ["报酬", "+%d 灵石 · +%d 修为" % [money, xp]]]
	if m == "chase":
		rows.insert(0, ["过了城门", "%d / %d" % [mini(score, GATES.size()), GATES.size()]])
	for row in rows:
		g.add_child(UiKit.label(str(row[0]), 16, UiKit.MIST))
		g.add_child(UiKit.bold(str(row[1]), 17, UiKit.MOON))
	v.add_child(UiKit.label("几秒后送回试炼碑", 14, UiKit.MIST))
	_result.visible = true
	_result.modulate.a = 0.0
	var tw := _result.create_tween()
	tw.tween_property(_result, "modulate:a", 1.0, 0.35)
	_result_t = 6.0
