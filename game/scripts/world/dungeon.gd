class_name Dungeon
extends Node
## 秘境（第十一版）：刷修为、灵石、灵骨的地方。野外不再刷怪。
##
## 每座岛三个入口（地图上的「秘」，一层 / 二层 / 三层，年份一层比一层高）。走过去按 F 进去：
##   一块四面石墙围起来的场地（在地图外面的高空，`ARENA`；Island.add_floor 让地面高度在这里也对）。
##   准备 5 秒 → 三波灵兽从三个兽门冲出来（打完一波歇 4 秒）→ 秘境之主（灵兽王，放大招、半血暴怒叫小弟，场地上不时出红圈）
##   → 打死：宝箱（灵骨、回血丹）、灵环（卡瓶颈的人）、王魄、一大笔灵石和修为；记最快通关时间。
## 每次随机一个词条（兽潮 / 坚甲 / 陨星 / 疾风 / 狂暴），奖励跟着涨。单人和联机的数量、血量分开算。
## 同一时间只有一个秘境在打；队友可以随时从同一个入口进来帮忙。全死了（回码头复活）秘境就失败。
##
## 联机：房主管一局，每秒发 "dgst"；进 dgenter / 传送 dgin / 离开 dgleave / 兽门 dggate / 出 Boss dgboss / 通关 dgclear / 结束 dgend。

const ARENA := Vector3(900.0, 420.0, 0.0)     # 比远处的山顶（最高约 300 米）还高，墙外面只看得到天
const R := 30.0
const PREP := 5.0
const REST := 4.0
const CLEAR_STAY := 90.0

var world: World
var portals: Array = []            # [{"pos": Vector3, "tier": int, "yaw": float}]
var run := {}                      # 大家都有：{"tier", "age", "mod", "phase", "wave", "t", "left", "boss"}
var inside := false                # 自己在秘境里
var _return := Vector3.ZERO
var _gates: Array = []             # 三个兽门（地上的出生点）
var _gate_fx: Array = []
var _chest: Node3D
var _exit_fx: Node3D
# 房主
var _members := {}                 # 在里面的人 peer -> true
var _queue: Array = []             # 这一波还没出场的 [species, age]
var _spawn_t := 0.0
var _phase_t := 0.0
var _hazard_t := 0.0
var _sync_t := 0.0
var _empty_t := 0.0
var _gate_i := 0
# 界面
var _card: PanelContainer
var _c_kick: Label
var _c_mod: Label
var _c_state: Label
var _c_time: Label
var _result: PanelContainer        # 通关结算面板（屏幕中间）
var _result_t := 0.0
var _boss_name := ""


func _ready() -> void:
	_build_ui()
	# 猎场里没有秘境
	if world.island.hunting:
		return
	_place_portals()
	_build_portals()
	_build_arena()


func _process(dt: float) -> void:
	if Net.is_host():
		_host(dt)
	elif not run.is_empty() and str(run["phase"]) != "clear":
		run["t"] = float(run["t"]) + dt
	_local(dt)


# ------------------------------------------------------------------ 入口（每台电脑按同样的规则算，位置一样）

func _place_portals() -> void:
	var isl := world.island
	var sp := Vector2(isl.spawn.x, isl.spawn.z)
	var cands: Array = []
	for i in 48:
		var a := TAU * i / 48.0 + 0.2
		for k in [0.6, 0.48, 0.72, 0.38]:
			var q: Vector2 = Vector2(cos(a), sin(a)) * isl.base_radius * float(k)
			if not isl.is_land(q.x, q.y) or isl.height_at(q.x, q.y) < 1.4 or isl.slope_at(q.x, q.y) > 0.45:
				continue
			if q.distance_to(sp) < 40.0 or q.distance_to(Vector2(isl.altar_pos.x, isl.altar_pos.z)) < 22.0 or q.distance_to(Vector2(isl.shop_pos.x, isl.shop_pos.z)) < 15.0:
				continue
			var bad := false
			for h in isl.habitats:
				if q.distance_to(h["center"]) < float(h["radius"]) + 5.0:
					bad = true
			for p in isl.ponds:
				if q.distance_to(p["center"]) < float(p["radius"]) + 8.0:
					bad = true
			if isl.arena != Vector2.INF and q.distance_to(isl.arena) < 26.0:
				bad = true
			if not bad:
				cands.append(q)
				break
	if cands.is_empty():
		cands = [sp + Vector2(30, -30), sp + Vector2(-30, -40), sp + Vector2(0, -70)]
	# 挑三个互相离得远的
	var chosen: Array = []
	var first: Vector2 = cands[0]
	for c in cands:
		if (c as Vector2).distance_to(sp) < first.distance_to(sp):
			first = c
	chosen.append(first)
	while chosen.size() < 3 and chosen.size() < cands.size():
		var best: Vector2 = cands[0]
		var bd := -1.0
		for c in cands:
			var md := INF
			for o in chosen:
				md = minf(md, (c as Vector2).distance_to(o))
			if md > bd:
				bd = md
				best = c
		chosen.append(best)
	# 离码头近的是一层，远的是三层
	chosen.sort_custom(func(a, b): return (a as Vector2).distance_to(sp) < (b as Vector2).distance_to(sp))
	for t in chosen.size():
		var c: Vector2 = chosen[t]
		var to := sp - c
		portals.append({"pos": isl.ground_point(c.x, c.y), "tier": t, "yaw": atan2(to.x, to.y)})


func tier_age(tier: int) -> int:
	return Data.dg_age(world.chapter, tier)


func tier_name(tier: int) -> String:
	return "%s秘境·%s" % [Data.age_name(tier_age(tier)), Data.DG_TIERS[tier]["name"]]


func _best_key(tier: int) -> String:
	return "dg_best_%d_%d" % [world.chapter, tier]


func best_time(tier: int) -> int:
	return int(Profile.stats.get(_best_key(tier), 0))


## 入口：石头拱门 + 转着的漩涡 + 一盏灯 + 飘着的光点
func _build_portals() -> void:
	var b := world.builder
	var stone := b._stone(Color(0.8, 0.77, 0.82))
	var dark := b._stone(Color(0.45, 0.43, 0.5))
	for p in portals:
		var col: Color = Data.AGES[tier_age(int(p["tier"]))]["glow"]
		var pos: Vector3 = p["pos"]
		var n := Node3D.new()
		n.name = "Portal%d" % int(p["tier"])
		world.add_child(n)
		n.global_position = pos
		n.rotation.y = float(p["yaw"])
		U.part(n, U.cyl(2.8, 3.2, 0.5, 10), dark, Vector3(0, 0.1, 0))
		b._cyl_collider(pos + Vector3(0, -0.15, 0), 3.0, 0.5)
		for s in [-1.0, 1.0]:
			U.part(n, U.box(Vector3(0.8, 5.2, 0.8)), stone, Vector3(s * 2.2, 2.9, 0))
			U.part(n, U.box(Vector3(1.0, 0.3, 1.0)), dark, Vector3(s * 2.2, 0.5, 0))
			b._add_collider(_box_shape(Vector3(0.8, 5.2, 0.8)), Transform3D(Basis(Vector3.UP, float(p["yaw"])), pos + Basis(Vector3.UP, float(p["yaw"])) * Vector3(s * 2.2, 2.9, 0)))
		U.part(n, U.box(Vector3(5.6, 0.7, 1.0)), stone, Vector3(0, 5.75, 0))
		U.part(n, U.box(Vector3(6.2, 0.25, 1.2)), dark, Vector3(0, 6.2, 0))
		# 年份宝石
		U.part(n, U.sphere(0.28, 12, 8), U.glow(col, 4.0), Vector3(0, 5.75, 0.55), Vector3.ZERO, Vector3.ONE, false)
		# 漩涡两层，一层慢转一层快转
		for k in 2:
			var q := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = Vector2(3.6, 4.6) if k == 0 else Vector2(3.0, 3.8)
			q.mesh = qm
			q.material_override = FxLib.quad_mat("swirl" if k == 0 else "magic", col, 1.6 if k == 0 else 1.0, true)
			q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			q.position = Vector3(0, 2.75, 0.02 * k)
			n.add_child(q)
			var tw := q.create_tween().set_loops()
			tw.tween_property(q, "rotation:z", TAU * (1.0 if k == 0 else -1.0), 6.0 if k == 0 else 3.5).as_relative()
		var l := OmniLight3D.new()
		l.light_color = col
		l.light_energy = 2.2
		l.omni_range = 11.0
		l.position = Vector3(0, 2.6, 1.0)
		n.add_child(l)
		b._motes(pos + Vector3(0, 2.5, 0), Vector3(2.0, 2.0, 1.0), 20, Color(col.r, col.g, col.b) * 0.8, 0.14)


func _box_shape(size: Vector3) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = size
	return s


# ------------------------------------------------------------------ 场地（石墙围起来的圆形平台，只有天空在头顶）

func _build_arena() -> void:
	world.island.add_floor(ARENA, R + 2.0)
	var b := world.builder
	var stone := b._stone(Color(0.66, 0.63, 0.7))
	var dark := b._stone(Color(0.38, 0.36, 0.43))
	var root := Node3D.new()
	root.name = "DungeonArena"
	world.add_child(root)
	root.global_position = ARENA
	var rng := RandomNumberGenerator.new()
	rng.seed = 7700 + world.chapter
	# 地面
	U.part(root, U.cyl(R + 2.5, R + 3.5, 2.0, 64), dark, Vector3(0, -1.0, 0))
	# 注意：_cyl_collider 的位置是圆柱的底，不是中心（以前传成中心，地面碰撞高出 1 米，人和灵兽出生在碰撞里面卡住）
	b._cyl_collider(ARENA + Vector3(0, -2.0, 0), R + 2.5, 2.0)
	# 石板地砖：一圈圈深浅不一
	for ring in 3:
		var rr := 8.0 + ring * 8.5
		U.part(root, U.cyl(rr + 3.6, rr + 3.6, 0.06, 64), stone if ring % 2 == 0 else dark, Vector3(0, 0.02 + ring * 0.001, 0), Vector3.ZERO, Vector3.ONE, false)
	var magic := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	magic.mesh = pm
	magic.material_override = FxLib.quad_mat("magic", Color(0.6, 0.45, 1.0), 1.2, true)
	magic.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	magic.position = Vector3(0, 0.08, 0)
	root.add_child(magic)
	var mt := magic.create_tween().set_loops()
	mt.tween_property(magic, "rotation:y", TAU, 40.0).as_relative()
	for rr in [11.9, 23.9]:
		U.part(root, U.torus(rr, rr + 0.2, 96, 4), U.glow(Color(0.65, 0.5, 1.0), 2.2), Vector3(0, 0.08, 0), Vector3.ZERO, Vector3(1, 0.05, 1), false)
	# 围墙：高低不齐的石板（不投影子，不然太阳低的地图整个场地都是黑的）
	var n := 30
	for i in n:
		var a := TAU * i / n
		var h := rng.randf_range(11.0, 17.0)
		var w := TAU * (R + 2.0) / n + 0.9
		var c := Vector3(cos(a), 0, sin(a)) * (R + 2.0)
		var basis := Basis(Vector3.UP, -a + PI * 0.5)
		var slab := U.part(root, U.box(Vector3(w, h, 3.0)), stone if i % 3 != 0 else dark, c + Vector3(0, h * 0.5 - 0.5, 0), Vector3(0, -a + PI * 0.5, rng.randf_range(-0.03, 0.03)), Vector3.ONE, false)
		slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# 碰撞和看得见的墙一样高（以前高出一截，灵兽落在看不见的墙顶上）
		b._add_collider(_box_shape(Vector3(w, h, 3.0)), Transform3D(basis, ARENA + c + Vector3(0, h * 0.5 - 0.5, 0)))
		if i % 5 == 2:
			U.part(root, U.box(Vector3(0.5, 2.2, 0.1)), U.glow(Color(0.65, 0.5, 1.0), 2.5), c + Vector3(0, h * 0.55, 0) - Vector3(cos(a), 0, sin(a)) * 1.55, Vector3(0, -a + PI * 0.5, 0), Vector3.ONE, false)
	# 柱子：可以绕着躲
	for i in 6:
		var a := TAU * i / 6.0
		var c := Vector3(cos(a), 0, sin(a)) * 17.0
		U.part(root, U.cyl(1.1, 1.35, 8.0, 12), stone, c + Vector3(0, 4.0, 0))
		U.part(root, U.cyl(1.6, 1.6, 0.5, 12), dark, c + Vector3(0, 0.25, 0))
		U.part(root, U.cyl(1.5, 1.5, 0.4, 12), dark, c + Vector3(0, 8.1, 0))
		U.part(root, U.sphere(0.35, 12, 8), U.glow(Color(0.7, 0.55, 1.0), 4.0), c + Vector3(0, 8.7, 0), Vector3.ZERO, Vector3.ONE, false)
		b._cyl_collider(ARENA + c, 1.25, 8.4)
	# 矮石台：能跳上去、能躲
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0
		var c := Vector3(cos(a), 0, sin(a)) * 9.0
		var yaw := -a
		U.part(root, U.box(Vector3(3.4, 1.2, 2.0)), dark, c + Vector3(0, 0.6, 0), Vector3(0, yaw, 0))
		b._add_collider(_box_shape(Vector3(3.4, 1.2, 2.0)), Transform3D(Basis(Vector3.UP, yaw), ARENA + c + Vector3(0, 0.6, 0)))
	# 三个兽门（北边一个，两边斜前方各一个）：灵兽从这里冲出来
	for k in 3:
		var a := -PI * 0.5 + (k - 1) * 1.15
		var dir := Vector3(cos(a), 0, sin(a))
		var g := dir * (R + 0.4)
		var gate := Node3D.new()
		root.add_child(gate)
		gate.position = g
		gate.rotation.y = -a - PI * 0.5
		U.part(gate, U.box(Vector3(5.0, 7.0, 1.0)), U.mat(Color(0.03, 0.02, 0.04), 1.0), Vector3(0, 3.5, 0.2), Vector3.ZERO, Vector3.ONE, false)
		for s in [-1.0, 1.0]:
			U.part(gate, U.box(Vector3(0.9, 8.0, 1.6)), dark, Vector3(s * 2.9, 4.0, 0), Vector3.ZERO, Vector3.ONE, false)
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(4.6, 6.6)
		q.mesh = qm
		q.material_override = FxLib.quad_mat("swirl", Color(1.0, 0.35, 0.2), 1.3, true)
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		q.position = Vector3(0, 3.4, 0.9)   # 本地 +z 朝场地中间
		gate.add_child(q)
		var qt := q.create_tween().set_loops()
		qt.tween_property(q, "rotation:z", -TAU, 7.0).as_relative()
		var gl := OmniLight3D.new()
		gl.light_color = Color(1.0, 0.4, 0.25)
		gl.light_energy = 1.2
		gl.omni_range = 10.0
		gl.position = Vector3(0, 3.0, 2.5)
		gate.add_child(gl)
		_gate_fx.append([q, gl])
		_gates.append(ARENA - dir * 0.0 + dir * (R - 4.0))
	# 火盆：一圈暖光
	for i in 8:
		var a := TAU * i / 8.0 + PI / 8.0
		var c := Vector3(cos(a), 0, sin(a)) * (R - 2.0)
		U.part(root, U.cyl(0.5, 0.3, 1.2, 8), dark, c + Vector3(0, 0.6, 0))
		U.part(root, U.sphere(0.35, 10, 8), U.glow(Color(1.0, 0.55, 0.2), 5.0), c + Vector3(0, 1.35, 0), Vector3.ZERO, Vector3(1, 1.3, 1), false)
		var fl := OmniLight3D.new()
		fl.light_color = Color(1.0, 0.6, 0.3)
		fl.light_energy = 1.4
		fl.omni_range = 9.0
		fl.position = c + Vector3(0, 2.0, 0)
		root.add_child(fl)
	# 墙根：发光的灵晶簇 + 长苔的大石头
	var crystal := U.glow(Color(0.62, 0.45, 1.0), 1.8)
	for i in 10:
		var a := TAU * i / 10.0 + 0.31
		var c := Vector3(cos(a), 0, sin(a)) * (R - 2.6)
		for k in 3:
			var h := rng.randf_range(1.2, 3.2)
			var off := Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8))
			var tilt := Vector3(rng.randf_range(-0.35, 0.35), rng.randf() * TAU, rng.randf_range(-0.35, 0.35))
			U.part(root, U.cyl(0.04, 0.32, h, 5), crystal, c + off + Vector3(0, h * 0.45, 0), tilt, Vector3.ONE, false)
		if i % 2 == 0:
			var cl := OmniLight3D.new()
			cl.light_color = Color(0.65, 0.5, 1.0)
			cl.light_energy = 1.0
			cl.omni_range = 7.0
			cl.position = c + Vector3(0, 1.5, 0)
			root.add_child(cl)
	var rocks := b._prop("boulder_01")
	if not rocks.is_empty():
		for i in 9:
			var a := TAU * i / 9.0 + 0.62
			var v: Dictionary = rocks[i % rocks.size()]
			var s := rng.randf_range(2.2, 3.6)
			var yaw := Basis(Vector3.UP, rng.randf() * TAU)
			var mi := MeshInstance3D.new()
			mi.mesh = v["mesh"]
			var p := Vector3(cos(a), 0, sin(a)) * (R - 1.2)
			mi.transform = Transform3D(yaw.scaled(Vector3(s, s, s)) * (v["basis"] as Basis), p + yaw * ((v["offset"] as Vector3) * s) - Vector3(0, 0.2 * s, 0))
			root.add_child(mi)
	b._motes(ARENA + Vector3(0, 4.0, 0), Vector3(R * 0.8, 3.5, R * 0.8), 90, Color(0.8, 0.65, 1.0) * 0.7, 0.16)
	# 进出的台子（南边）
	U.part(root, U.cyl(2.4, 2.6, 0.2, 24), stone, Vector3(0, 0.1, R - 5.0))
	_exit_fx = Node3D.new()
	root.add_child(_exit_fx)
	_exit_fx.position = Vector3(0, 0.25, R - 5.0)
	U.part(_exit_fx, U.torus(2.0, 2.2, 48, 4), U.glow(UiKit.JADE, 3.0), Vector3.ZERO, Vector3.ZERO, Vector3(1, 0.1, 1), false)
	# 宝箱（通关才出现）
	_chest = Node3D.new()
	root.add_child(_chest)
	_chest.visible = false
	var gold := U.mat(Color(0.85, 0.62, 0.22), 0.35, 0.8, 0.5)
	var wood := b._wood(Color(0.7, 0.45, 0.3))
	U.part(_chest, U.box(Vector3(1.6, 0.9, 1.0)), wood, Vector3(0, 0.45, 0))
	for s in [-0.7, 0.0, 0.7]:
		U.part(_chest, U.box(Vector3(0.12, 0.95, 1.05)), gold, Vector3(s, 0.47, 0))
	var lid := Node3D.new()
	lid.name = "Lid"
	lid.position = Vector3(0, 0.9, -0.5)
	_chest.add_child(lid)
	U.part(lid, U.box(Vector3(1.6, 0.35, 1.0)), wood, Vector3(0, 0.17, 0.5))
	var cl := OmniLight3D.new()
	cl.light_color = UiKit.GOLD
	cl.light_energy = 3.0
	cl.omni_range = 8.0
	cl.position = Vector3(0, 1.6, 0)
	_chest.add_child(cl)


func spawn_pad() -> Vector3:
	return ARENA + Vector3(0, 0.4, R - 5.0)


# ------------------------------------------------------------------ 进出（自己）

func interactables() -> Array:
	var out: Array = []
	if inside:
		var cleared := not run.is_empty() and str(run["phase"]) == "clear"
		out.append({"id": "dgexit", "pos": spawn_pad() + Vector3(0, 1.0, 0), "r": 3.0,
			"text": "按 F 离开秘境" if cleared else "按 F 离开秘境（还没通关，出去就算放弃）", "act": true})
		return out
	for p in portals:
		var t := int(p["tier"])
		var txt := "按 F 进入%s（推荐 %d 级）" % [tier_name(t), Data.dg_level(world.chapter, t)]
		var bt := best_time(t)
		if bt > 0:
			txt += " · 最快 %d:%02d" % [bt / 60, bt % 60]
		var act := true
		if not run.is_empty():
			if int(run["tier"]) == t:
				txt = "按 F 进入%s（队友在里面打）" % tier_name(t)
			else:
				txt = "%s里有人在打，等打完" % tier_name(int(run["tier"]))
				act = false
		out.append({"id": "dgportal", "tier": t, "pos": (p["pos"] as Vector3) + Vector3(0, 1.5, 0), "r": 3.6, "text": txt, "act": act})
	return out


func interact(it: Dictionary) -> void:
	match str(it["id"]):
		"dgportal":
			Net.send_host("dgenter", [int(it["tier"])])
		"dgexit":
			leave()


## 被房主传送进来
func enter(tier: int) -> void:
	if inside:
		return
	inside = true
	_return = world.player.global_position
	for p in portals:
		if int(p["tier"]) == tier:
			var fwd := Basis(Vector3.UP, float(p["yaw"])) * Vector3(0, 0, 4.5)
			_return = (p["pos"] as Vector3) + fwd + Vector3(0, 0.5, 0)
	var pl := world.player
	pl.teleport(spawn_pad() + Vector3(randf_range(-1.5, 1.5), 0.2, 0))
	pl.look_to(0.0, deg_to_rad(-3))
	world.fx.aura_burst(pl.global_position, Data.AGES[tier_age(tier)]["glow"], 3.0)
	Sfx.play("absorb", -4.0, 0.0, 0.7)
	var mod: Dictionary = Data.DG_MODS.get(str(run.get("mod", "")), {})
	var show_banner := func():
		if is_instance_valid(world) and inside:
			world.hud._show_banner(tier_name(tier), ("词条 · %s：%s" % [mod["name"], mod["desc"]]) if not mod.is_empty() else "", Data.AGES[tier_age(tier)]["glow"], 4.0)
			world.hud.flash(Color(0.6, 0.45, 1.0, 0.4))
	# 进洞天：一小段过场（洞天裂开、把人吸进去），秘境名字叠在上面；准备时间 5 秒，播完正好开打
	if Data.autotest:
		show_banner.call()
	else:
		var v := Voyage.new()
		v.video = "res://assets/cutscene/dungeon.ogv"
		v.length = 5.0
		v.title = "洞天 · %s" % tier_name(tier)
		world.add_child(v)
		v.finished.connect(show_banner)


## 自己走出去（或者倒下回了码头）
func leave(teleport := true) -> void:
	if not inside:
		return
	inside = false
	if teleport:
		world.player.teleport(_return)
		world.fx.aura_burst(_return, Color(0.7, 0.55, 1.0), 2.5)
		Sfx.play("absorb", -6.0, 0.0, 1.2)
	if Net.is_host():
		_host_leave(Net.my_id)
	else:
		Net.send_host("dgleave", [])


# ------------------------------------------------------------------ 房主

func host_enter(from: int, tier: int) -> void:
	if tier < 0 or tier >= portals.size():
		return
	if not run.is_empty() and int(run["tier"]) != tier:
		return
	if run.is_empty():
		var mods: Array = Data.DG_MODS.keys()
		run = {"tier": tier, "age": tier_age(tier), "mod": str(mods[randi() % mods.size()]), "phase": "prep", "wave": 0, "t": 0.0, "left": 0, "boss": 0}
		_members.clear()
		_queue.clear()
		_phase_t = PREP
		_hazard_t = 6.0
		_empty_t = 0.0
	_members[from] = true
	_sync()
	if from == Net.my_id:
		enter(tier)
	else:
		Net.send(from, "dgin", [tier])


func _host_leave(peer: int) -> void:
	_members.erase(peer)


func _sync() -> void:
	_sync_t = 1.0
	var st: Array = []
	if not run.is_empty():
		st = [int(run["tier"]), int(run["age"]), str(run["mod"]), str(run["phase"]), int(run["wave"]), float(run["t"]), int(run["left"]), int(run["boss"])]
	Net.send(0, "dgst", st)


func _team_inside() -> int:
	return maxi(_members.size(), 1)


func _host(dt: float) -> void:
	if run.is_empty():
		return
	# 在里面的人：走了的、掉线的去掉
	var present := {}
	for p in world.all_players():
		present[int(p["peer"])] = true
	for k in _members.keys():
		if not present.has(int(k)):
			_members.erase(k)
	var phase := str(run["phase"])
	if _members.is_empty():
		_empty_t += dt
		if _empty_t > (2.0 if phase == "clear" else 6.0):
			_end_run(phase == "clear")
		return
	_empty_t = 0.0
	if phase != "clear":
		run["t"] = float(run["t"]) + dt
	_keep_inside()
	match phase:
		"prep", "rest":
			_phase_t -= dt
			if _phase_t <= 0.0:
				_start_wave(int(run["wave"]) + 1)
		"wave":
			# 场上同时最多几只（单人 3 只，每多一个人 +1）：打掉一只才补一只，不会一下子被围死
			_spawn_t -= dt
			var alive := _alive_mobs()
			if not _queue.is_empty() and _spawn_t <= 0.0 and alive < 2 + _team_inside():
				_spawn_t = 1.1
				var e: Array = _queue.pop_front()
				_spawn_mob(str(e[0]), int(e[1]))
				alive += 1
			run["left"] = alive + _queue.size()
			if _queue.is_empty() and alive == 0:
				if int(run["wave"]) >= 3:
					_start_boss()
				else:
					run["phase"] = "rest"
					_phase_t = REST
					_sync()
			_hazards(dt, false)
		"boss":
			run["left"] = 1
			_hazards(dt, true)
		"clear":
			_phase_t -= dt
			if _phase_t <= 0.0:
				_end_run(true)
	_sync_t -= dt
	if _sync_t <= 0.0:
		_sync()


func _in_arena(p: Vector3, extra := 0.0) -> bool:
	return Vector2(p.x - ARENA.x, p.z - ARENA.z).length() < R + extra and p.y > ARENA.y - 20.0


func _alive_mobs() -> int:
	var n := 0
	for b: Beast in world.beasts.values():
		if b.alive() and b.hunt_role == "dg" and _in_arena(b.global_position, 8.0):
			n += 1
	return n


## 被打飞出墙、掉下平台、卡在柱子 / 石台里的灵兽拉回场地里
var _stuck := {}                   # 灵兽 id -> [上次的位置, 多久没动了]


func _keep_inside() -> void:
	var dt := get_process_delta_time()
	for b: Beast in world.beasts.values():
		if not b.alive():
			continue
		if not (b.hunt_role in ["dg", "dgboss"]):
			# 不是秘境的灵兽跑进了场地（野外刷的、别处跟过来的）：收掉
			if _in_arena(b.global_position, 2.0):
				world.beast_escaped(b, "despawn")
			continue
		var p := b.global_position
		var far := Vector2(p.x - ARENA.x, p.z - ARENA.z).length() > R + 1.0
		# 卡住：3 秒没挪过半米，又没在咬人（离人 4 米外）；扔石头的猿猴会站在 6~13 米外不动，16 米内的不算
		var s: Array = _stuck.get(b.id, [p, 0.0])
		if p.distance_to(s[0]) > 0.5:
			s = [p, 0.0]
		else:
			s[1] = float(s[1]) + dt
		_stuck[b.id] = s
		var near_d := world.nearest_player_pos(p).distance_to(p)
		var thrower := str(Data.BEASTS[b.species]["motion"]) == "throw"
		var stuck := float(s[1]) > 3.0 and (near_d > 16.0 or (near_d > 4.5 and not thrower)) and b.root_t <= 0.0 and b._king_wind <= 0.0
		if far or p.y < ARENA.y - 4.0 or stuck:
			var a := randf() * TAU
			b.global_position = ARENA + Vector3(cos(a) * 13.0, 2.0, sin(a) * 13.0)
			b.linear_velocity = Vector3.ZERO
			_stuck[b.id] = [b.global_position, 0.0]


func _pool() -> Array:
	var out: Array = []
	for sp in world._map_species():
		if not world.island.is_water_habitat(str(Data.BEASTS[sp]["habitat"])):
			out.append(sp)
	if out.is_empty():
		out = ["rabbit"]
	return out


func _start_wave(n: int) -> void:
	run["wave"] = n
	run["phase"] = "wave"
	var tier: Dictionary = Data.DG_TIERS[int(run["tier"])]
	var count := int((tier["waves"] as Array)[n - 1]) + 2 * (_team_inside() - 1) + (2 if str(run["mod"]) == "swarm" else 0)
	var pool := _pool()
	var age := int(run["age"])
	# 第一波小一档，但不低于这一章的年份（第五章的秘境里不出千年的）
	var low := maxi(age - 1, int(Data.CH_AGE.get(world.chapter, 0)))
	for i in count:
		var a := mini(low, age) if n == 1 else age
		_queue.append([pool[randi() % pool.size()], a])
	_spawn_t = 0.8
	_sync()


func _spawn_mob(species: String, age: int) -> void:
	_gate_i = (_gate_i + 1) % _gates.size()
	var g: Vector3 = _gates[_gate_i]
	var q := g + Vector3(randf_range(-2.0, 2.0), 0.6, randf_range(-2.0, 2.0))
	var b: Beast = world._host_spawn_wild(q, species, age, "fierce")
	if b == null:
		return
	b.hunt_role = "dg"
	b.aggro_k = 3.0
	b.spawn_pos = ARENA
	# 秘境里的灵兽是一波波来的，血比野外的薄一点（单人也打得完）
	b.max_hp *= Data.DG_MOB_HP * float(Data.DG_MOB_HP_CH.get(world.chapter, 1.0))
	b.dmg_mult = Data.DG_MOB_DMG * float(Data.DG_MOB_DMG_CH.get(world.chapter, 1.0))
	var mod := str(run["mod"])
	if mod == "armor":
		b.max_hp *= 1.5
	elif mod == "swift" and not "swift" in b.affixes:
		b.affixes.append("swift")
	elif mod == "frenzy" and not "frenzy" in b.affixes:
		b.affixes.append("frenzy")
	b.hp = b.max_hp
	var m := [_gate_i]
	Net.send(0, "dggate", m)
	_on_gate(m)


func _start_boss() -> void:
	run["phase"] = "boss"
	var pool := _pool().filter(func(s): return not str(Data.BEASTS[s]["motion"]) in ["fly", "flutter"])
	if pool.is_empty():
		pool = _pool()
	var species: String = pool[randi() % pool.size()]
	# 秘境之主和秘境同一个年份（以前三层会高一档：千年秘境出万年之主、掉万年灵环，用户说不合理）
	var age := int(run["age"])
	var id := world.next_beast_id
	world.next_beast_id += 1
	var pos := ARENA + Vector3(0, 0.8, -6.0)
	var affixes: Array = []
	if str(run["mod"]) in ["swift", "frenzy"]:
		affixes.append(str(run["mod"]))
	var b := world._spawn_beast(id, species, age, pos, Vector3.ZERO, 1, false, "elite", affixes)
	Net.send(0, "bsp", [id, species, age, pos, Vector3.ZERO, 1, "elite", affixes])
	b.max_hp *= (Data.DG_BOSS_HP_SOLO + Data.DG_BOSS_HP_PER * float(_team_inside() - 1)) * (1.5 if str(run["mod"]) == "armor" else 1.0)
	b.hp = b.max_hp
	b.hunt_role = "dgboss"
	b.aggro_k = 3.0
	b.dmg_mult = 0.85
	b._rested = true
	b.spawn_pos = ARENA
	run["boss"] = id
	_hazard_t = 7.0
	var m := [id]
	Net.send(0, "dgboss", m)
	_on_boss(m)
	_sync()


## 自动截图用：小怪清掉，直接出秘境之主
func _host_start_boss_now() -> void:
	if run.is_empty():
		return
	_queue.clear()
	for b: Beast in world.beasts.values():
		if b.alive() and b.hunt_role == "dg":
			world.beast_escaped(b, "despawn")
	run["wave"] = 3
	_start_boss()


## 场地上的红圈：Boss 战一直有；陨星词条打小怪时也有
func _hazards(dt: float, boss: bool) -> void:
	if not boss and str(run["mod"]) != "meteor":
		return
	_hazard_t -= dt
	if _hazard_t > 0.0:
		return
	_hazard_t = randf_range(5.5, 8.0) if boss else randf_range(6.0, 9.0)
	var pl: Array = world.alive_players().filter(func(p): return _in_arena(p["pos"], 2.0))
	if pl.is_empty():
		return
	# 伤害：按这一章的灵兽大概咬一口的 1.5 倍（红圈能躲）
	var base: float = 12.0 * (1.0 + int(run["age"]) * 0.5) * Data.BEAST_DMG * Profile.rebirth_hard()
	var n := 3 if boss else 2
	for i in n:
		var t: Vector3 = pl[randi() % pl.size()]["pos"]
		var c := t + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
		if not _in_arena(c, -2.0):
			c = ARENA + (c - ARENA).limit_length(R - 3.0)
		c.y = ARENA.y
		world.boss_telegraph(c, 3.2, 1.3, base, "slam", c)
		var m := [c]
		var tw := create_tween()
		tw.tween_interval(1.1)
		tw.tween_callback(func():
			Net.send(0, "dgmet", m)
			_on_meteor(m))


## 陨石砸下来（红圈到时间前一点）
func _on_meteor(d: Array) -> void:
	if inside:
		world.fx.meteor_strike(d[0], 3.2, Color(1.0, 0.45, 0.2))


## 房主：有灵兽死了（World._host_kill 调）
func host_on_kill(b: Beast) -> void:
	if run.is_empty() or b.id != int(run["boss"]):
		return
	run["phase"] = "clear"
	_phase_t = CLEAR_STAY
	var tier: Dictionary = Data.DG_TIERS[int(run["tier"])]
	var mod: Dictionary = Data.DG_MODS.get(str(run["mod"]), {"reward": 1.0})
	var k := float(tier["reward"]) * float(mod["reward"])
	var money := roundi(Data.kill_money(b.species, b.age) * 4.0 * k * Data.KILL_MONEY)
	var xp := roundi(Data.kill_xp(b.species, b.age) * 5.0 * k)
	# 剩下的小怪（Boss 叫来的）散掉
	for o: Beast in world.beasts.values():
		if o.alive() and o != b and _in_arena(o.global_position, 6.0):
			world.beast_escaped(o, "despawn")
	# 宝箱里的东西：回血丹、雷莲，二层以上多一块灵骨
	var at := ARENA + Vector3(0, 1.2, 0)
	world.loot.spawn("item", "pill", 1 + int(run["tier"]), 0, at, Vector3(randf_range(-2, 2), 6.0, randf_range(-2, 2)))
	world.loot.spawn("item", "grenade", 1, 0, at, Vector3(randf_range(-2, 2), 6.0, randf_range(-2, 2)))
	if int(run["tier"]) >= 1:
		var pool := _pool()
		var bid: String = Data.BONE_BY_BEAST.get(pool[randi() % pool.size()], "")
		if bid != "":
			world.loot.spawn("bone", "%s@%d" % [bid, int(run["age"])], 1, 0, at, Vector3(randf_range(-1.5, 1.5), 7.0, randf_range(-1.5, 1.5)))
	world._host_quest_event("dungeon", 1)
	var msg := [int(run["tier"]), int(float(run["t"])), money, xp]
	for peer in _members:
		if int(peer) == Net.my_id:
			_on_clear(msg)
		else:
			Net.send(int(peer), "dgclear", msg)
	_sync()


func _end_run(cleared: bool) -> void:
	for b: Beast in world.beasts.values():
		if b.alive() and _in_arena(b.global_position, 8.0):
			world.beast_escaped(b, "despawn")
	# 场地里没人吸收的灵环也收掉（所有秘境共用一块场地，以前会留到下一个秘境里）
	for rid in world.rings.keys():
		if _in_arena(world.rings[rid]["pos"], 4.0):
			Net.send(0, "ringgone", [rid, 0])
			world._on_ring_gone([rid, 0])
	var m := [int(run["tier"]), cleared]
	run = {}
	_members.clear()
	_queue.clear()
	Net.send(0, "dgend", m)
	_on_end(m)
	_sync()


# ------------------------------------------------------------------ 消息

func on_message(from: int, type: String, data: Variant) -> void:
	match type:
		"dgst":
			if not Net.is_host():
				_apply_state(data)
		"dgenter":
			if Net.is_host():
				host_enter(from, int(data[0]))
		"dgin":
			enter(int(data[0]))
		"dgleave":
			if Net.is_host():
				_host_leave(from)
		"dggate":
			_on_gate(data)
		"dgboss":
			_on_boss(data)
		"dgmet":
			_on_meteor(data)
		"dgclear":
			_on_clear(data)
		"dgend":
			_on_end(data)


func _apply_state(d: Array) -> void:
	if d.is_empty():
		run = {}
		return
	var old_phase := str(run.get("phase", ""))
	var old_wave := int(run.get("wave", 0))
	run = {"tier": int(d[0]), "age": int(d[1]), "mod": str(d[2]), "phase": str(d[3]), "wave": int(d[4]), "t": float(d[5]), "left": int(d[6]), "boss": int(d[7])}
	if inside and (str(run["phase"]) != old_phase or int(run["wave"]) != old_wave):
		_phase_changed()


func _phase_changed() -> void:
	match str(run["phase"]):
		"wave":
			world.hud._show_banner("第 %d 波" % int(run["wave"]), "", Color(1.0, 0.6, 0.4), 1.6)
			Sfx.play("boss_roar", -6.0, 0.0, 1.3)
		"clear":
			_chest_open()


func _on_gate(d: Array) -> void:
	var i := int(d[0])
	if i < 0 or i >= _gate_fx.size() or not inside:
		return
	var l: OmniLight3D = _gate_fx[i][1]
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 6.0, 0.08)
	tw.tween_property(l, "light_energy", 1.2, 0.6)
	world.fx.aura_burst(_gates[i], Color(1.0, 0.4, 0.2), 2.0)


func _on_boss(d: Array) -> void:
	if not inside:
		return
	var b: Beast = world.beasts.get(int(d[0]))
	var nm := b.display_name() if b else "秘境之主"
	_boss_name = nm.replace("秘境之主 · ", "")
	world.hud._show_banner("秘境之主", nm, Color(1.0, 0.45, 0.3), 3.0)
	world.fx.shockwave(ARENA + Vector3(0, 0.2, -6.0), 12.0, Color(1.0, 0.4, 0.25))
	world.fx.aura_burst(ARENA + Vector3(0, 1.0, -6.0), Color(1.0, 0.35, 0.2), 5.0)
	Sfx.play("boss_roar", 2.0, 0.0, 0.75)
	world.player.trauma = minf(world.player.trauma + 0.6, 1.0)


func _on_clear(d: Array) -> void:
	var tier := int(d[0])
	var t := int(d[1])
	var money := int(d[2])
	var xp := int(d[3])
	world._gain(money, xp)
	var key := _best_key(tier)
	var old := int(Profile.stats.get(key, 0))
	var record := old == 0 or t < old
	if record:
		Profile.stats[key] = t
		Profile.mark_dirty()
	Profile.count("dungeons")
	# 庆祝（用户：打完没有庆祝的感觉）：金光一闪、镜头一震、场地上空一串烟花、宝箱弹开，再弹结算面板
	Sfx.play("quest_done", 2.0)
	Sfx.play("level_up", -3.0, 0.0, 0.9)
	Sfx.play("coin", -2.0)
	world.hud.flash(Color(1.0, 0.82, 0.35, 0.45))
	world.player.trauma = minf(world.player.trauma + 0.45, 1.0)
	world.fx.ring_breakthrough(ARENA, UiKit.GOLD, 0)
	world.fx.level_up_burst(world.player.global_position, Profile.rings.size())
	_chest_open()
	_fireworks(Data.AGES[tier_age(tier)]["glow"])
	_show_result(tier, t, money, xp, record, old)


## 场地上空一串烟花（金色 + 这一层的年份颜色）
func _fireworks(col: Color) -> void:
	var tw := create_tween()
	for i in 9:
		tw.tween_interval(0.22 if i > 0 else 0.35)
		tw.tween_callback(func():
			if not inside:
				return
			var a := randf() * TAU
			var p := ARENA + Vector3(cos(a) * randf_range(6.0, 20.0), randf_range(9.0, 16.0), sin(a) * randf_range(6.0, 20.0))
			var c: Color = UiKit.GOLD if i % 2 == 0 else col
			world.fx._sparks(p, Vector3.UP, c, 70, 11.0, 1.3, 0.09, -6.0, 180.0, 4.0)
			world.fx._glows(p, Vector3.UP, c.lightened(0.3), 24, 5.0, 1.6, 0.25, -2.5, 180.0, 2.2)
			world.fx.aura_burst(p, c, 2.5)
			Sfx.play_at("boom", p, -16.0, 0.2, 1.6))


## 通关结算：打倒了谁、用时（纪录）、报酬、宝箱里有什么
func _show_result(tier: int, t: int, money: int, xp: int, record: bool, old: int) -> void:
	world.lock_music("victory", 30.0)
	if not _result:
		var layer := CanvasLayer.new()
		layer.layer = 5
		add_child(layer)
		_result = PanelContainer.new()
		_result.add_theme_stylebox_override("panel", UiKit.glass_style(0.72, 28, 20))
		_result.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiKit.place(_result, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-300, -200, 300, 160))
		layer.add_child(_result)
	for c in _result.get_children():
		c.queue_free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result.add_child(v)
	v.add_child(UiKit.kicker(tier_name(tier), Data.AGES[tier_age(tier)]["glow"], 15))
	v.add_child(UiKit.title("秘境通关", 48, UiKit.GOLD))
	if _boss_name != "":
		v.add_child(UiKit.label("打倒了秘境之主 · %s" % _boss_name, 19, UiKit.MOON))
	# 秘境是天宫坠下的碎片：墙上刻着天上那边的记录
	var ins := Story.inscription(world.chapter, tier)
	if ins != "":
		var il := UiKit.label("残壁上刻着：「%s」" % ins, 17, Color(0.95, 0.85, 0.6))
		il.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(il)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 28)
	g.add_theme_constant_override("v_separation", 4)
	v.add_child(g)
	var tt := "%d:%02d" % [t / 60, t % 60]
	if record and old > 0:
		tt += "（新纪录！）"
	elif old > 0:
		tt += "（最快 %d:%02d）" % [old / 60, old % 60]
	var chest := "回血丹 ×%d · 九转雷莲 ×1" % (1 + tier)
	if tier >= 1:
		chest += " · 灵骨"
	var rows := [["用时", tt], ["报酬", "+%d 灵石 · +%d 修为" % [money, xp]], ["宝箱", chest + "（地上捡）"]]
	for row in rows:
		g.add_child(UiKit.label(str(row[0]), 16, UiKit.MIST))
		g.add_child(UiKit.bold(str(row[1]), 17, UiKit.MOON))
	v.add_child(UiKit.label("卡在瓶颈的人会掉灵环 · 从南边的台子按 F 离开", 14, UiKit.MIST))
	_result.visible = true
	_result.modulate.a = 0.0
	_result.scale = Vector2.ONE
	var tw := _result.create_tween()
	tw.tween_interval(0.6)
	tw.tween_property(_result, "modulate:a", 1.0, 0.35)
	_result_t = 10.0


func _chest_open() -> void:
	if not _chest or _chest.visible:
		return
	_chest.visible = true
	_chest.scale = Vector3.ONE * 0.2
	var tw := _chest.create_tween()
	tw.tween_property(_chest, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var lid: Node3D = _chest.get_node("Lid")
	tw.tween_property(lid, "rotation:x", -1.9, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	world.fx._pillar(ARENA, UiKit.GOLD, 1.2, 25.0, 0.6)


func _on_end(d: Array) -> void:
	var cleared := bool(d[1])
	if _chest:
		_chest.visible = false
		(_chest.get_node("Lid") as Node3D).rotation = Vector3.ZERO
	if inside:
		if not cleared:
			world.hud._show_banner("秘境失败", "所有人都倒下了", Color(0.9, 0.5, 0.45), 3.0)
		leave()
	run = {}


## 自己倒下、回码头复活（World._respawn_at_dock 调）：人已经不在秘境了
func on_respawn() -> void:
	leave(false)


# ------------------------------------------------------------------ 自己这边：每帧

func _local(_dt: float) -> void:
	# 出了秘境也要刷新一次（以前只在里面刷新，出来以后左上角的秘境卡片一直挂着）
	_update_ui()
	if _result:
		_result_t -= _dt
		if _result_t <= 0.0 or not inside:
			_result.visible = false
	if not inside:
		return
	var p := world.player
	# 掉出场地：拉回进出台
	if not p.dead and (p.global_position.y < ARENA.y - 6.0 or Vector2(p.global_position.x - ARENA.x, p.global_position.z - ARENA.z).length() > R + 4.0):
		p.teleport(spawn_pad())


func compass_marks() -> Array:
	var out: Array = []
	if inside:
		return out
	for p in portals:
		out.append([p["pos"], "秘", Data.AGES[tier_age(int(p["tier"]))]["glow"]])
	return out


## 界面：进了秘境才显示（左上角）
func _build_ui() -> void:
	var hud: Hud = world.hud
	var q: Control = hud._quest_text.get_parent()
	var tl: Control = q.get_parent()
	_card = PanelContainer.new()
	var st := UiKit.glass_style(0.45, 12, 8)
	st.border_color = Color(0.7, 0.55, 1.0)
	st.border_width_left = 3
	_card.add_theme_stylebox_override("panel", st)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.visible = false
	tl.add_child(_card)
	tl.move_child(_card, q.get_index() + 1)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(v)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(h)
	_c_kick = UiKit.kicker("", Color(0.8, 0.7, 1.0), 13)
	UiKit._text_style(_c_kick, 3)
	h.add_child(_c_kick)
	_c_time = UiKit.num("", 16, UiKit.MOON, 3)
	h.add_child(_c_time)
	_c_state = UiKit.bold("", 20, Color.WHITE, 3)
	v.add_child(_c_state)
	_c_mod = UiKit.label("", 14, UiKit.MIST, 3)
	v.add_child(_c_mod)


func _update_ui() -> void:
	_card.visible = inside and not run.is_empty()
	if not _card.visible:
		return
	var tier := int(run["tier"])
	_c_kick.text = tier_name(tier)
	var s := int(float(run["t"]))
	_c_time.text = "%d:%02d" % [s / 60, s % 60]
	match str(run["phase"]):
		"prep":
			_c_state.text = "准备……"
		"wave":
			_c_state.text = "第 %d / 3 波 · 还剩 %d 只" % [int(run["wave"]), int(run["left"])]
		"rest":
			_c_state.text = "第 %d 波清完了，喘口气" % int(run["wave"])
		"boss":
			_c_state.text = "秘境之主"
		"clear":
			_c_state.text = "通关 · 拿东西，从南边的台子离开"
	var mod: Dictionary = Data.DG_MODS.get(str(run["mod"]), {})
	if not mod.is_empty():
		_c_mod.text = "词条 · %s：%s" % [mod["name"], mod["desc"]]
		_c_mod.add_theme_color_override("font_color", mod["color"])
