class_name Decor
extends Node3D
## 码头、船、暗器铺、猎场营地的装饰（用户："船和帐篷、补给站可以弄得更豪华，然后玩家可以再花钱增加装饰"）。
##   基础（人人都有）：船舷一道朱漆金边、船尾两盏灯、船头小旗；暗器铺前一根「暗器」幌子、石阶；营地兵器架、火把。
##   能买的（Data.DECOR，暗器铺「装饰」页）：红灯笼长廊、夜明珠灯柱、五色旌旗、锦鲤、苍墟牌坊、锦帆、龙首船头、镇门石狮、青铜香炉、虎皮大帐。
## 联机：每个人摆上的装饰写在 hello / prog 里（peer_info["decor"]），大家看到的是所有人装饰的合集。

var world: World
var _built: Array = []
var _live: Node3D                  # 能买的装饰都挂在这下面（换的时候整个重建）
var _koi: Array = []               # [鱼, 绕着的中心, 半径, 角速度, 相位]
var _flags: Array = []             # 飘的旗子


func _ready() -> void:
	name = "Decor"
	_base()
	refresh()


func _process(_dt: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for k in _koi:
		var f: Variant = k[0]
		if not is_instance_valid(f):
			continue
		var c: Vector3 = k[1]
		var a := float(k[4]) + t * float(k[3])
		f.position = c + Vector3(cos(a), 0, sin(a)) * float(k[2]) + Vector3(0, sin(t * 1.3 + float(k[4])) * 0.05, 0)
		f.rotation.y = -a - (PI * 0.5 if float(k[3]) > 0.0 else -PI * 0.5)
	for i in _flags.size():
		var fl: Variant = _flags[i]
		if is_instance_valid(fl):
			fl.rotation.y = sin(t * 1.7 + i * 0.9) * 0.25
			fl.rotation.z = sin(t * 2.3 + i) * 0.04


## 现在该摆哪些：自己摆上的 + 队友摆上的
func refresh() -> void:
	if not is_inside_tree():
		return
	var want := {}
	for id in Profile.decor_on():
		want[id] = true
	for peer in world.peer_info:
		if int(peer) == Net.my_id:
			continue
		for id in world.peer_info[peer].get("decor", []):
			if Data.DECOR.has(str(id)):
				want[str(id)] = true
	var ids: Array = want.keys()
	ids.sort()
	if ids == _built and _live != null:
		return
	_built = ids
	if _live:
		_live.queue_free()
	_live = Node3D.new()
	_live.name = "Bought"
	add_child(_live)
	_koi.clear()
	_flags = _flags.filter(func(f): return is_instance_valid(f) and not f.is_queued_for_deletion())
	var hunting := world.island.hunting
	for id in ids:
		var where := str(Data.DECOR[id]["where"])
		if hunting and where in ["dock", "boat"]:
			continue
		if not hunting and where == "camp":
			continue
		if hunting and where == "shop" and id != "censer":
			continue
		call("_d_" + str(id))


# ------------------------------------------------------------------ 零件

func _b() -> WorldBuilder:
	return world.builder


func _col(parent: Node, shape: Shape3D, xf: Transform3D) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = U.LAYER_WORLD
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	sb.add_child(cs)
	parent.add_child(sb)
	sb.global_transform = xf


func _boxs(size: Vector3) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = size
	return s


func _light(parent: Node3D, pos: Vector3, c: Color, energy := 1.4, rng := 7.0) -> void:
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = energy
	l.omni_range = rng
	l.position = pos
	parent.add_child(l)


## 一盏红灯笼：竹骨纸灯身 + 上下漆木盖 + 金穗子（Props.lantern）
func _lamp(parent: Node3D, p: Vector3, c: Color, s := 1.0) -> void:
	Props.lantern(parent, p, c, s * 1.1)


## 码头的方向（岸 → 海）、右手边、岸上那一头、海上那一头
func _dock_frame() -> Array:
	var isl := world.island
	var a: Vector3 = isl.dock_start
	var e: Vector3 = isl.dock_end
	var dir := Vector3(e.x - a.x, 0, e.z - a.z)
	var len := dir.length()
	dir = dir / maxf(len, 0.01)
	return [Vector3(a.x, isl.dock_y, a.z), dir, dir.cross(Vector3.UP), len]


func _shop_xf() -> Transform3D:
	var isl := world.island
	return Transform3D(Basis(Vector3.UP, isl.shop_yaw), isl.shop_pos)


# ------------------------------------------------------------------ 基础的样子（人人都有）

func _base() -> void:
	var b := _b()
	var isl := world.island
	if not isl.hunting and b.boat and not b.boat.has_meta("model"):
		# 船：两舷一道朱漆 + 金边，船尾两盏灯，船头一面小三角旗（混元的船模型自己有灯笼，不加）
		var red := MatLib.lacquer(Color(0.55, 0.08, 0.06), false)
		var gold := MatLib.gold()
		for sx in [-1.0, 1.0]:
			U.part(b.boat, Props.rbox(Vector3(0.05, 0.14, 5.6)), red, Vector3(sx * 0.93, 0.72, 0))
			U.part(b.boat, Props.rbox(Vector3(0.055, 0.03, 5.6)), gold, Vector3(sx * 0.935, 0.8, 0))
			U.part(b.boat, U.cyl(0.03, 0.03, 1.1, 5), b._wood(Color(0.4, 0.28, 0.18)), Vector3(sx * 0.6, 1.1, 3.1))
			_lamp(b.boat, Vector3(sx * 0.6, 1.75, 3.1), Color(1.0, 0.4, 0.2), 0.8)
		var flag := Node3D.new()
		flag.position = Vector3(0, 2.05, -3.15)
		b.boat.add_child(flag)
		U.part(flag, U.cyl(0.0, 0.35, 0.02, 3), MatLib.canvas(Color(0.75, 0.1, 0.08)), Vector3(0, 0, 0.3), Vector3(PI * 0.5, 0, PI * 0.5), Vector3(1, 1, 1.6))
		_flags.append(flag)
		_light(b.boat, Vector3(0, 1.8, 3.1), Color(1.0, 0.55, 0.3), 1.0, 6.0)
	if not isl.hunting and isl.shop_pos != Vector3.ZERO:
		# 暗器铺：门口一根高高的幌子（红布白字"暗器"），几级石阶
		var xf := _shop_xf()
		var n := Node3D.new()
		add_child(n)
		n.global_transform = xf
		var pole := b._wood(Color(0.35, 0.24, 0.15))
		U.part(n, U.cyl(0.07, 0.09, 6.0, 6), pole, Vector3(-3.9, 3.0, 3.3))
		U.part(n, U.cyl(0.04, 0.04, 1.3, 5), pole, Vector3(-3.35, 5.7, 3.3), Vector3(0, 0, PI * 0.5))
		var flag2 := Node3D.new()
		flag2.position = Vector3(-3.35, 5.65, 3.3)
		n.add_child(flag2)
		U.part(flag2, U.box(Vector3(0.9, 2.6, 0.03)), MatLib.canvas(Color(0.6, 0.09, 0.07)), Vector3(0, -1.3, 0))
		U.part(flag2, Props.rbox(Vector3(0.95, 0.12, 0.05)), MatLib.lacquer(Color(0.08, 0.06, 0.05), false), Vector3(0, -2.62, 0))
		var tx := U.label3d("暗\n器", 90, Color(1.0, 0.95, 0.85), 0)
		tx.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		tx.pixel_size = 0.006
		tx.position = Vector3(0, -1.25, 0.03)
		flag2.add_child(tx)
		_flags.append(flag2)
		_col(n, _boxs(Vector3(0.2, 6.0, 0.2)), xf * Transform3D(Basis(), Vector3(-3.9, 3.0, 3.3)))
	if not isl.hunting:
		_landmarks()
	if isl.hunting:
		# 营地：兵器架（插着三根长矛）+ 两支火把
		var c := isl.spawn
		var rack := Vector3(c.x - 1.0, isl.height_at(c.x - 1.0, c.z - 7.5), c.z - 7.5)
		var wood := b._wood(Color(0.45, 0.3, 0.2))
		var n2 := Node3D.new()
		add_child(n2)
		n2.global_position = rack
		U.part(n2, U.box(Vector3(2.0, 0.12, 0.4)), wood, Vector3(0, 0.3, 0))
		U.part(n2, U.box(Vector3(2.0, 0.12, 0.4)), wood, Vector3(0, 1.3, 0))
		for sx in [-0.95, 0.95]:
			U.part(n2, U.cyl(0.06, 0.06, 1.6, 6), wood, Vector3(sx, 0.8, 0))
		for k in 3:
			U.part(n2, U.cyl(0.025, 0.025, 2.6, 5), wood, Vector3(-0.5 + k * 0.5, 1.3, 0.05), Vector3(0.12, 0, 0))
			U.part(n2, U.cyl(0.0, 0.06, 0.3, 5), MatLib.iron(Color(1.6, 1.6, 1.6)), Vector3(-0.5 + k * 0.5 , 2.72, 0.2), Vector3(0.12, 0, 0))
		for sx in [-4.0, 4.0]:
			var tp := Vector3(c.x + sx, isl.height_at(c.x + sx, c.z - 4.0), c.z - 4.0)
			U.part(self, U.cyl(0.05, 0.07, 2.2, 6), wood, tp + Vector3(0, 1.1, 0))
			U.part(self, U.sphere(0.2, 8, 6), U.glow(Color(1.0, 0.55, 0.2), 5.0), tp + Vector3(0, 2.35, 0), Vector3.ZERO, Vector3(1, 1.5, 1), false)
			_light(self, tp + Vector3(0, 2.5, 0), Color(1.0, 0.6, 0.3), 1.4, 9.0)


# ------------------------------------------------------------------ 能买的

func _d_lanterns() -> void:
	var f := _dock_frame()
	var a: Vector3 = f[0]
	var dir: Vector3 = f[1]
	var right: Vector3 = f[2]
	var len := float(f[3])
	var pole := _b()._wood(Color(0.3, 0.2, 0.12))
	var n := int(len / 3.0)
	for k in n + 1:
		for s in [-1.0, 1.0]:
			var p: Vector3 = a + dir * (k * len / maxf(n, 1)) + right * 1.72 * s
			# 杆子立在码头边上，灯笼往外挑出去挂着（不挡走道、不挡视线）
			U.part(_live, U.cyl(0.04, 0.05, 2.9, 6), pole, p + Vector3(0, 1.45, 0))
			U.part(_live, U.cyl(0.025, 0.025, 0.6, 5), pole, p + Vector3(0, 2.85, 0) + right * 0.28 * s, Vector3(0, 0, PI * 0.5))
			_lamp(_live, p + Vector3(0, 2.45, 0) + right * 0.52 * s, Color(1.0, 0.25, 0.15), 0.85)
		if k % 2 == 0:
			_light(_live, a + dir * (k * len / maxf(n, 1)) + Vector3(0, 2.0, 0), Color(1.0, 0.45, 0.25), 1.6, 8.0)


func _d_pearls() -> void:
	var f := _dock_frame()
	var a: Vector3 = f[0]
	var dir: Vector3 = f[1]
	var right: Vector3 = f[2]
	var stone := _b()._stone(Color(0.75, 0.74, 0.72))
	for s in [-1.0, 1.0]:
		var p: Vector3 = a - dir * 1.2 + right * 2.3 * s
		p.y = world.island.height_at(p.x, p.z)
		U.part(_live, U.box(Vector3(0.7, 0.3, 0.7)), stone, p + Vector3(0, 0.15, 0))
		U.part(_live, U.box(Vector3(0.45, 2.4, 0.45)), stone, p + Vector3(0, 1.5, 0))
		U.part(_live, U.cyl(0.35, 0.2, 0.3, 8), stone, p + Vector3(0, 2.85, 0))
		U.part(_live, U.sphere(0.28, 16, 12), U.glow(Color(0.7, 0.92, 1.0), 4.5), p + Vector3(0, 3.25, 0), Vector3.ZERO, Vector3.ONE, false)
		U.part(_live, U.torus(0.3, 0.34, 24, 4), U.glow(Color(1.0, 0.85, 0.4), 2.0), p + Vector3(0, 3.25, 0), Vector3(PI * 0.5, 0, 0), Vector3.ONE, false)
		_light(_live, p + Vector3(0, 3.3, 0), Color(0.7, 0.9, 1.0), 2.0, 10.0)
		_col(_live, _boxs(Vector3(0.5, 3.0, 0.5)), Transform3D(Basis(), p + Vector3(0, 1.5, 0)))


func _d_banners() -> void:
	var f := _dock_frame()
	var a: Vector3 = f[0]
	var dir: Vector3 = f[1]
	var right: Vector3 = f[2]
	var cols := [Color(0.8, 0.12, 0.1), Color(0.95, 0.75, 0.2), Color(0.15, 0.35, 0.8), Color(0.15, 0.6, 0.3), Color(0.92, 0.92, 0.88), Color(0.1, 0.1, 0.12)]
	var pole := _b()._wood(Color(0.3, 0.2, 0.12))
	var i := 0
	for s in [-1.0, 1.0]:
		for k in 3:
			# 牌坊（离岸 7 米、宽 11 米）两边外侧，一边三根，往岸上排
			var p: Vector3 = a - dir * (2.0 + k * 2.6) + right * (7.2 + k * 0.4) * s
			p.y = world.island.height_at(p.x, p.z)
			U.part(_live, U.cyl(0.05, 0.07, 5.5, 6), pole, p + Vector3(0, 2.75, 0))
			U.part(_live, U.sphere(0.09, 8, 6), MatLib.gold(), p + Vector3(0, 5.55, 0))
			var fl := Node3D.new()
			fl.position = p + Vector3(0, 5.3, 0)
			_live.add_child(fl)
			U.part(fl, U.box(Vector3(0.8, 3.0, 0.03)), MatLib.canvas(cols[i % cols.size()]), Vector3(0.45, -1.5, 0))
			U.part(fl, Props.rbox(Vector3(0.85, 0.1, 0.04)), MatLib.gold(), Vector3(0.45, -3.0, 0))
			_flags.append(fl)
			_col(_live, _boxs(Vector3(0.15, 5.5, 0.15)), Transform3D(Basis(), p + Vector3(0, 2.75, 0)))
			i += 1


func _d_koi() -> void:
	var f := _dock_frame()
	var a: Vector3 = f[0]
	var dir: Vector3 = f[1]
	var right: Vector3 = f[2]
	var len := float(f[3])
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 10:
		var fish := Node3D.new()
		_live.add_child(fish)
		var body := Color(1.0, 0.45, 0.15) if i % 3 != 0 else Color(0.98, 0.95, 0.9)
		U.part(fish, U.sphere(0.16, 10, 6), U.glow(body, 1.2), Vector3.ZERO, Vector3.ZERO, Vector3(0.6, 0.45, 1.4), false)
		U.part(fish, U.sphere(0.06, 6, 4), U.glow(Color(1.0, 0.2, 0.1), 1.5), Vector3(0, 0.05, -0.08), Vector3.ZERO, Vector3(1.2, 0.5, 1.4), false)
		U.part(fish, U.cyl(0.0, 0.14, 0.2, 3), U.glow(body, 1.0), Vector3(0, 0, 0.28), Vector3(PI * 0.5, 0, 0), Vector3(1, 1, 0.25), false)
		var side := 1.0 if i % 2 == 0 else -1.0
		var c := a + dir * rng.randf_range(len * 0.3, len * 0.9) + right * (3.2 + rng.randf_range(0, 2.0)) * side
		c.y = Island.WATER_Y - 0.25
		_koi.append([fish, c, rng.randf_range(0.8, 2.2), rng.randf_range(0.4, 0.9) * (1.0 if i % 3 else -1.0), rng.randf() * TAU])
	_light(_live, a + dir * len * 0.6 + Vector3(0, 0.2, 0), Color(1.0, 0.6, 0.3), 0.8, 9.0)


func _d_paifang() -> void:
	var f := _dock_frame()
	var a: Vector3 = f[0]
	var dir: Vector3 = f[1]
	var right: Vector3 = f[2]
	var c := a - dir * 7.0
	c.y = world.island.height_at(c.x, c.z)
	var yaw := atan2(dir.x, dir.z)
	var n := Node3D.new()
	_live.add_child(n)
	n.global_transform = Transform3D(Basis(Vector3.UP, yaw), c)
	var red := MatLib.lacquer(Color(0.58, 0.07, 0.05))
	var dark := _b()._stone(Color(0.25, 0.24, 0.26))
	var gold := MatLib.gold(true)
	var green := MatLib.lacquer(Color(0.08, 0.3, 0.26))
	var blue := MatLib.lacquer(Color(0.07, 0.16, 0.34))
	var tiles := _b()._tiles(Color(0.26, 0.27, 0.3))
	for x in [-5.2, -2.4, 2.4, 5.2]:
		var h := 6.4 if absf(x) < 3.0 else 4.8
		var gy := world.island.height_at((n.global_transform * Vector3(x, 0, 0)).x, (n.global_transform * Vector3(x, 0, 0)).z) - c.y
		# 柱础：方座 + 鼓形石墩；柱子上下各一道金箍
		U.part(n, Props.rbox(Vector3(0.9, 0.5, 0.9), 0.06), dark, Vector3(x, gy + 0.25, 0))
		U.part(n, U.cyl(0.34, 0.38, 0.35, 16), dark, Vector3(x, gy + 0.65, 0))
		U.part(n, U.cyl(0.24, 0.26, h - gy, 16), red, Vector3(x, gy + (h - gy) * 0.5, 0))
		for yy in [gy + 0.9, h - 1.25]:
			U.part(n, U.cyl(0.27, 0.27, 0.08, 16), gold, Vector3(x, yy, 0))
		_col(_live, _boxs(Vector3(0.6, h, 0.6)), n.global_transform * Transform3D(Basis(), Vector3(x, h * 0.5, 0)))
	# 横梁：中间高、两边低，青绿彩画（青、绿两道 + 金线）+ 斗拱 + 瓦顶
	for bay in [[0.0, 4.8, 6.2], [-3.8, 2.8, 4.6], [3.8, 2.8, 4.6]]:
		var bx := float(bay[0])
		var bw := float(bay[1]) + 0.8
		var by := float(bay[2])
		U.part(n, Props.rbox(Vector3(bw, 0.35, 0.5)), green, Vector3(bx, by - 0.9, 0))
		U.part(n, Props.rbox(Vector3(bw - 0.3, 0.12, 0.54)), blue, Vector3(bx, by - 0.9, 0))
		U.part(n, Props.rbox(Vector3(bw, 0.5, 0.55)), red, Vector3(bx, by - 0.3, 0))
		for yy in [by - 0.72, by - 1.08, by - 0.05]:
			U.part(n, Props.rbox(Vector3(bw + 0.05, 0.04, 0.58), 0.01), gold, Vector3(bx, yy, 0))
		# 斗拱：一排小木托，把屋檐撑出去
		var nb := int(bw / 0.55)
		for k in nb:
			var kx := bx - bw * 0.5 + (k + 0.5) * bw / nb
			for zz in [-0.34, 0.34]:
				U.part(n, Props.rbox(Vector3(0.22, 0.14, 0.26), 0.02), red, Vector3(kx, by + 0.05, zz))
				U.part(n, Props.rbox(Vector3(0.3, 0.08, 0.32), 0.015), green, Vector3(kx, by + 0.15, zz * 1.1))
		var roof := PrismMesh.new()
		roof.size = Vector3(bw + 1.4, 1.0, 1.9)
		U.part(n, roof, tiles, Vector3(bx, by + 0.7, 0))
		# 屋脊 + 两头的鸱吻
		U.part(n, Props.rbox(Vector3(bw + 1.3, 0.18, 0.24), 0.04), dark, Vector3(bx, by + 1.22, 0))
		for sx in [-1.0, 1.0]:
			U.part(n, U.cyl(0.02, 0.12, 0.7, 6), tiles, Vector3(bx + sx * (bw * 0.5 + 0.7), by + 0.35, 0), Vector3(0, 0, -0.9 * sx))
			U.part(n, Props.rbox(Vector3(0.18, 0.4, 0.2), 0.04), dark, Vector3(bx + sx * (bw * 0.5 + 0.55), by + 1.4, 0), Vector3(0, 0, 0.25 * sx))
	# 匾：金字「苍墟」
	U.part(n, Props.rbox(Vector3(2.2, 1.0, 0.12), 0.03), MatLib.lacquer(Color(0.05, 0.1, 0.18)), Vector3(0, 5.2, 0.32))
	U.part(n, Props.rbox(Vector3(2.35, 1.12, 0.08), 0.03), gold, Vector3(0, 5.2, 0.28))
	for side in [1.0, -1.0]:
		var l := U.label3d("苍 墟", 120, Color(1.0, 0.82, 0.4), 0)
		l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		l.pixel_size = 0.006
		l.position = Vector3(0, 5.2, 0.39 * side)
		l.rotation.y = 0.0 if side > 0.0 else PI
		n.add_child(l)
	_light(n, Vector3(0, 4.5, 1.5), Color(1.0, 0.7, 0.4), 1.2, 9.0)
	_light(n, Vector3(0, 4.5, -1.5), Color(1.0, 0.7, 0.4), 1.2, 9.0)


func _d_sail() -> void:
	var boat: Node3D = _b().boat
	if boat == null:
		return
	var n := Node3D.new()
	boat.add_child(n)
	# 模型船中间是乌篷，桅杆挪到船头那段
	if boat.has_meta("model"):
		n.position.z = -3.0
	var wood := _b()._wood(Color(0.35, 0.24, 0.15))
	var cloth := MatLib.canvas(Color(0.66, 0.1, 0.07))
	var gold := MatLib.gold()
	U.part(n, U.cyl(0.06, 0.08, 6.0, 8), wood, Vector3(0, 3.4, 0.9))
	U.part(n, U.cyl(0.04, 0.04, 2.8, 6), wood, Vector3(0, 5.6, 0.95), Vector3(0, 0, PI * 0.5))
	U.part(n, U.cyl(0.04, 0.04, 2.6, 6), wood, Vector3(0, 2.3, 0.95), Vector3(0, 0, PI * 0.5))
	U.part(n, U.box(Vector3(2.5, 3.2, 0.03)), cloth, Vector3(0, 3.95, 1.0))
	for yy in [2.4, 5.5]:
		U.part(n, U.box(Vector3(2.55, 0.08, 0.04)), gold, Vector3(0, yy, 1.0))
	for xx in [-1.25, 1.25]:
		U.part(n, U.box(Vector3(0.08, 3.2, 0.04)), gold, Vector3(xx, 3.95, 1.0))
	# 帆上几道竹撑
	for k in 3:
		U.part(n, U.cyl(0.015, 0.015, 2.5, 4), wood, Vector3(0, 3.2 + k * 0.8, 1.02), Vector3(0, 0, PI * 0.5))
	var flag := Node3D.new()
	flag.position = Vector3(0, 6.35, 0.9)
	n.add_child(flag)
	U.part(flag, U.box(Vector3(0.9, 0.35, 0.02)), MatLib.canvas(Color(0.92, 0.7, 0.22)), Vector3(0.45, 0, 0))
	_flags.append(flag)
	# 船是基础场景里的，重建装饰时这一套也要跟着删
	_live.tree_exiting.connect(func():
		if is_instance_valid(n):
			n.queue_free())


func _d_dragon() -> void:
	var boat: Node3D = _b().boat
	if boat == null:
		return
	var n := Node3D.new()
	n.position = Vector3(0, 0.75, -3.45)
	boat.add_child(n)
	var gold := MatLib.gold()
	var red := MatLib.lacquer(Color(0.7, 0.1, 0.06), false)
	# 脖子往上往前弯，头朝前（-z）
	for k in 4:
		var t := float(k) / 3.0
		U.part(n, U.sphere(0.24 - t * 0.04, 12, 8), gold, Vector3(0, t * 0.9, -t * 0.35 - t * t * 0.2))
	var head := Node3D.new()
	head.position = Vector3(0, 1.05, -0.75)
	n.add_child(head)
	U.part(head, U.box(Vector3(0.36, 0.3, 0.55)), gold, Vector3.ZERO)
	U.part(head, U.box(Vector3(0.3, 0.16, 0.4)), gold, Vector3(0, -0.12, -0.35))
	U.part(head, U.box(Vector3(0.28, 0.06, 0.35)), red, Vector3(0, -0.22, -0.32))
	for sx in [-1.0, 1.0]:
		U.part(head, U.cyl(0.01, 0.05, 0.55, 5), gold, Vector3(sx * 0.12, 0.3, 0.1), Vector3(-0.6, 0, sx * 0.3))
		U.part(head, U.sphere(0.045, 8, 6), U.glow(Color(1.0, 0.3, 0.1), 5.0), Vector3(sx * 0.14, 0.08, -0.2), Vector3.ZERO, Vector3.ONE, false)
		U.part(head, U.cyl(0.008, 0.008, 0.6, 4), gold, Vector3(sx * 0.14, -0.15, -0.5), Vector3(0.3, 0, sx * 1.2))
	U.part(head, U.sphere(0.07, 8, 6), U.glow(Color(1.0, 0.85, 0.4), 4.0), Vector3(0, 0.02, -0.62), Vector3.ZERO, Vector3.ONE, false)
	_light(n, Vector3(0, 1.2, -1.2), Color(1.0, 0.7, 0.35), 1.2, 6.0)
	_live.tree_exiting.connect(func():
		if is_instance_valid(n):
			n.queue_free())


func _d_lions() -> void:
	var xf := _shop_xf()
	var stone := _b()._stone(Color(0.7, 0.68, 0.64))
	var dark := _b()._stone(Color(0.42, 0.4, 0.4))
	for sx in [-1.0, 1.0]:
		var n := Node3D.new()
		_live.add_child(n)
		var lp := xf * Vector3(sx * 3.4, 0, 4.4)
		lp.y = world.island.height_at(lp.x, lp.z)
		n.global_transform = Transform3D(xf.basis, lp)
		# 混元生成的石狮子（带雕花石座），脸朝铺子外面（+z）。不做镜像：缩放取负会让法线贴图的光照反过来（发暗发红）
		if ResourceLoader.exists(Props.LION_MODEL):
			Props.place_model(n, Props.LION_MODEL, 2.3, "h", Vector3(0, -0.05, 0), -0.12 * sx)
			_col(_live, _boxs(Vector3(1.0, 2.2, 1.3)), Transform3D(xf.basis, lp + Vector3(0, 1.1, 0)))
			continue
		U.part(n, U.box(Vector3(1.0, 0.7, 1.3)), dark, Vector3(0, 0.35, 0))
		U.part(n, U.box(Vector3(1.1, 0.1, 1.4)), stone, Vector3(0, 0.72, 0))
		# 蹲着的狮子：后身、前胸、头、鬃毛卷、前腿、绣球
		U.part(n, U.sphere(0.4, 12, 8), stone, Vector3(0, 1.05, -0.25), Vector3.ZERO, Vector3(1.0, 0.9, 1.1))
		U.part(n, U.sphere(0.36, 12, 8), stone, Vector3(0, 1.35, 0.15), Vector3.ZERO, Vector3(1.0, 1.2, 0.9))
		U.part(n, U.sphere(0.3, 12, 8), stone, Vector3(0, 1.85, 0.3))
		for k in 7:
			var a := TAU * k / 7.0
			U.part(n, U.sphere(0.12, 8, 6), stone, Vector3(cos(a) * 0.3, 1.85 + sin(a) * 0.3, 0.2))
		U.part(n, U.box(Vector3(0.22, 0.14, 0.2)), stone, Vector3(0, 1.8, 0.58))
		for lx in [-0.18, 0.18]:
			U.part(n, U.cyl(0.08, 0.1, 0.6, 8), stone, Vector3(lx, 1.0, 0.35))
			U.part(n, U.sphere(0.04, 6, 4), dark, Vector3(lx * 0.6, 1.95, 0.55))
		U.part(n, U.sphere(0.2, 12, 8), stone, Vector3(0.28 * sx, 0.95, 0.5))
		_col(_live, _boxs(Vector3(1.0, 2.2, 1.3)), Transform3D(xf.basis, lp + Vector3(0, 1.1, 0)))


func _d_censer() -> void:
	var p: Vector3
	if world.island.hunting:
		p = _b().camp_pos + Vector3(2.2, 0, 0.8)
	else:
		# 暗器铺前面找一块空地（避开收购箱和门口）
		var box: Vector3 = world.loot.box_pos if world.loot else Vector3.INF
		p = _shop_xf() * Vector3(-3.0, 0, 7.0)
		for off in [Vector3(-3.0, 0, 7.0), Vector3(3.2, 0, 7.0), Vector3(-5.0, 0, 5.5), Vector3(5.2, 0, 5.5)]:
			var q: Vector3 = _shop_xf() * off
			if box == Vector3.INF or Vector2(q.x - box.x, q.z - box.z).length() > 3.0:
				p = q
				break
	p.y = world.island.height_at(p.x, p.z)
	var bronze := MatLib.bronze(Color(0.7, 0.95, 0.8))
	var n := Node3D.new()
	_live.add_child(n)
	n.global_position = p
	U.part(n, U.cyl(0.55, 0.42, 0.55, 14), bronze, Vector3(0, 0.75, 0))
	U.part(n, U.cyl(0.6, 0.6, 0.08, 14), bronze, Vector3(0, 1.04, 0))
	for k in 3:
		var a := TAU * k / 3.0
		U.part(n, U.cyl(0.05, 0.08, 0.55, 6), bronze, Vector3(cos(a) * 0.36, 0.26, sin(a) * 0.36))
	for sx in [-1.0, 1.0]:
		U.part(n, U.torus(0.1, 0.14, 12, 5), bronze, Vector3(sx * 0.5, 1.22, 0), Vector3(0, 0, PI * 0.5))
	U.part(n, U.sphere(0.2, 10, 6), U.glow(Color(1.0, 0.5, 0.2), 2.0), Vector3(0, 1.02, 0), Vector3.ZERO, Vector3(1.6, 0.3, 1.6), false)
	var smoke := CPUParticles3D.new()
	smoke.amount = 18
	smoke.lifetime = 4.0
	smoke.mesh = U.sphere(0.12, 6, 4)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.8, 0.85, 0.8, 0.25)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke.material_override = sm
	smoke.direction = Vector3.UP
	smoke.spread = 12.0
	smoke.initial_velocity_min = 0.3
	smoke.initial_velocity_max = 0.6
	smoke.gravity = Vector3(0.05, 0.1, 0)
	smoke.scale_amount_min = 1.0
	smoke.scale_amount_max = 3.0
	smoke.position = Vector3(0, 1.1, 0)
	n.add_child(smoke)
	_col(_live, _boxs(Vector3(1.1, 1.2, 1.1)), Transform3D(Basis(), p + Vector3(0, 0.6, 0)))


func _d_tiger() -> void:
	var c := world.island.spawn
	var p := Vector3(c.x - 13.0, 0, c.z + 7.0)
	p.y = world.island.height_at(p.x, p.z)
	var n := Node3D.new()
	_live.add_child(n)
	n.global_position = p
	var orange := MatLib.canvas(Color(0.82, 0.48, 0.14))
	var black := MatLib.canvas(Color(0.08, 0.06, 0.05))
	var cream := MatLib.canvas(Color(0.88, 0.83, 0.68))
	var wood := _b()._wood(Color(0.35, 0.24, 0.15))
	# 十二面的帐墙（虎纹：橙黑相间）+ 尖顶 + 门帘
	for k in 12:
		var a := TAU * k / 12.0
		var w := U.part(n, U.box(Vector3(1.6, 2.4, 0.06)), orange if k % 2 == 0 else black, Vector3(cos(a) * 3.0, 1.2, sin(a) * 3.0), Vector3(0, -a + PI * 0.5, 0))
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	U.part(n, U.cyl(0.1, 3.5, 2.4, 12), orange, Vector3(0, 3.6, 0))
	for k in 6:
		U.part(n, U.cyl(0.02, 0.02, 3.0, 4), black, Vector3(cos(TAU * k / 6.0) * 1.7, 3.6, sin(TAU * k / 6.0) * 1.7), Vector3(0, -TAU * k / 6.0, 0.95))
	U.part(n, U.box(Vector3(1.2, 2.0, 0.08)), cream, Vector3(0, 1.0, 3.05))
	U.part(n, U.cyl(0.05, 0.06, 3.0, 6), wood, Vector3(0, 6.2, 0))
	var fl := Node3D.new()
	fl.position = Vector3(0, 7.3, 0)
	n.add_child(fl)
	U.part(fl, U.box(Vector3(1.4, 0.8, 0.03)), MatLib.canvas(Color(0.72, 0.1, 0.07)), Vector3(0.7, 0, 0))
	_flags.append(fl)
	for sx in [-1.8, 1.8]:
		U.part(n, U.cyl(0.35, 0.25, 0.9, 12), MatLib.iron(), Vector3(sx, 0.45, 4.2))
		U.part(n, U.sphere(0.3, 8, 6), U.glow(Color(1.0, 0.55, 0.2), 5.0), Vector3(sx, 1.0, 4.2), Vector3.ZERO, Vector3(1, 1.6, 1), false)
		_light(n, Vector3(sx, 1.6, 4.4), Color(1.0, 0.6, 0.3), 1.4, 9.0)
	var cyl := CylinderShape3D.new()
	cyl.radius = 3.0
	cyl.height = 2.4
	_col(_live, cyl, Transform3D(Basis(), p + Vector3(0, 1.2, 0)))


# ------------------------------------------------------------------ 国风地标（用户："地图往国风去改"）：
#   最高的山头一座七层宝塔（远处就看得见，认路用），海边两座红柱亭子，小路两边一对对石灯笼

func _landmarks() -> void:
	var isl := world.island
	var rng := RandomNumberGenerator.new()
	rng.seed = 8800 + world.chapter
	var avoid: Array = [Vector2(isl.spawn.x, isl.spawn.z), Vector2(isl.altar_pos.x, isl.altar_pos.z), Vector2(isl.shop_pos.x, isl.shop_pos.z)]
	if world.dungeon:
		for pt in world.dungeon.portals:
			avoid.append(Vector2((pt["pos"] as Vector3).x, (pt["pos"] as Vector3).z))
	if world.trial and world.trial.stele != Vector3.INF:
		avoid.append(Vector2(world.trial.stele.x, world.trial.stele.z))
	var ok := func(q: Vector2, clear: float) -> bool:
		if not isl.is_land(q.x, q.y) or isl.slope_at(q.x, q.y) > 0.35:
			return false
		for av in avoid:
			if q.distance_to(av) < clear:
				return false
		for h in isl.habitats:
			if q.distance_to(h["center"]) < float(h["radius"]) + 4.0:
				return false
		for pd in isl.ponds:
			if q.distance_to(pd["center"]) < float(pd["radius"]) + 4.0:
				return false
		return true
	# 宝塔：最高的空地
	var best := Vector2.INF
	var bh := -INF
	for i in 400:
		var q := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * isl.base_radius * 0.9
		if not ok.call(q, 28.0):
			continue
		var h := isl.height_at(q.x, q.y)
		if h > bh:
			bh = h
			best = q
	if best != Vector2.INF:
		_pagoda(isl.ground_point(best.x, best.y))
		avoid.append(best)
	# 亭子：靠海（离水 6~14 米）的两处空地，互相离得远
	var placed := 0
	for i in 600:
		if placed >= 2:
			break
		var a := rng.randf() * TAU
		var q := Vector2(cos(a), sin(a)) * isl.base_radius * rng.randf_range(0.55, 0.95)
		if not ok.call(q, 35.0) or isl.height_at(q.x, q.y) < 1.5:
			continue
		var near_water := false
		for k in 8:
			var d := Vector2(cos(TAU * k / 8.0), sin(TAU * k / 8.0)) * 10.0
			if not isl.is_land(q.x + d.x, q.y + d.y):
				near_water = true
		if not near_water:
			continue
		var face := Vector2.ZERO
		for k in 16:
			var d := Vector2(cos(TAU * k / 16.0), sin(TAU * k / 16.0))
			if not isl.is_land(q.x + d.x * 14.0, q.y + d.y * 14.0):
				face += d
		_pavilion(isl.ground_point(q.x, q.y), atan2(face.x, face.y) if face.length() > 0.1 else 0.0)
		avoid.append(q)
		placed += 1
	# 石灯笼：小路两边，每 26 米一对
	var stone := _b()._stone(Color(0.62, 0.6, 0.56))
	var n := 0
	for path in isl.paths:
		var acc := 0.0
		for k in range(1, path.size()):
			acc += path[k].distance_to(path[k - 1])
			if acc < 26.0:
				continue
			acc = 0.0
			var dir := (path[k] - path[k - 1]).normalized()
			var side := Vector2(-dir.y, dir.x)
			for sgn in [-1.0, 1.0]:
				var q: Vector2 = path[k] + side * 2.4 * sgn
				if not ok.call(q, 8.0):
					continue
				_stone_lantern(isl.ground_point(q.x, q.y), stone, n % 3 == 0)
				n += 1
			if n > 40:
				break


## 七层八角宝塔：一层比一层小，每层一圈飞檐，顶上金葫芦；檐角挂灯
func _pagoda(p: Vector3) -> void:
	var n := Node3D.new()
	n.name = "Pagoda"
	add_child(n)
	n.global_position = p
	var wall := MatLib.plaster(Color(0.84, 0.8, 0.72))
	var red := MatLib.lacquer(Color(0.55, 0.1, 0.07))
	var tiles := _b()._tiles(Color(0.25, 0.26, 0.29))
	var gold := MatLib.gold(true)
	U.part(n, U.cyl(4.2, 4.6, 1.2, 8), _b()._stone(Color(0.55, 0.53, 0.5)), Vector3(0, 0.4, 0))
	var y := 1.0
	var r := 3.2
	for f in 7:
		var h := 3.2 - f * 0.18
		U.part(n, U.cyl(r, r, h, 8), wall, Vector3(0, y + h * 0.5, 0))
		# 每层四面开一个红门洞
		for k in 4:
			var a := TAU * k / 4.0 + PI / 8.0
			U.part(n, U.box(Vector3(0.9, h * 0.6, 0.1)), red, Vector3(cos(a) * (r - 0.02), y + h * 0.42, sin(a) * (r - 0.02)), Vector3(0, -a + PI * 0.5, 0))
		y += h
		# 飞檐：扁的八角锥 + 一圈檐口
		U.part(n, U.cyl(r * 0.7, r + 1.3, 0.7, 8), tiles, Vector3(0, y + 0.3, 0))
		U.part(n, U.cyl(r + 1.32, r + 1.32, 0.1, 8), red, Vector3(0, y - 0.03, 0))
		for k in 8:
			var a := TAU * k / 8.0
			var tip := Vector3(cos(a), 0, sin(a)) * (r + 1.45)
			U.part(n, U.cyl(0.03, 0.14, 0.9, 5), tiles, tip + Vector3(0, y + 0.1, 0), Vector3(sin(a) * 0.7, 0, -cos(a) * 0.7))
			if f % 2 == 0:
				Props.lantern(n, tip + Vector3(0, y - 0.45, 0), Color(1.0, 0.5, 0.22), 0.5, 0.15)
		y += 0.6
		r *= 0.86
	U.part(n, U.cyl(0.08, 0.12, 3.0, 8), gold, Vector3(0, y + 1.5, 0))
	for k in 3:
		U.part(n, U.sphere(0.35 - k * 0.08, 12, 8), gold, Vector3(0, y + 0.6 + k * 0.8, 0))
	_light(n, Vector3(0, y + 2.0, 0), Color(1.0, 0.75, 0.4), 1.5, 14.0)
	var cs := CylinderShape3D.new()
	cs.radius = 3.3
	cs.height = y
	_col(n, cs, Transform3D(Basis(), p + Vector3(0, y * 0.5, 0)))


## 六角红柱亭子：石台 + 六根红柱 + 攒尖顶 + 美人靠
func _pavilion(p: Vector3, yaw: float) -> void:
	var n := Node3D.new()
	n.name = "Pavilion"
	add_child(n)
	n.global_transform = Transform3D(Basis(Vector3.UP, yaw), p)
	var stone := _b()._stone(Color(0.7, 0.68, 0.64))
	var red := MatLib.lacquer(Color(0.58, 0.09, 0.06))
	var tiles := _b()._tiles(Color(0.24, 0.28, 0.28))
	var gold := MatLib.gold(true)
	U.part(n, U.cyl(3.4, 3.7, 0.6, 6), stone, Vector3(0, 0.1, 0))
	for k in 6:
		var a := TAU * k / 6.0
		var c := Vector3(cos(a), 0, sin(a)) * 2.9
		U.part(n, U.cyl(0.15, 0.17, 3.2, 10), red, c + Vector3(0, 2.0, 0))
		_col(n, _boxs(Vector3(0.35, 3.2, 0.35)), n.global_transform * Transform3D(Basis(), c + Vector3(0, 2.0, 0)))
		# 美人靠（一圈矮栏杆，前面留口）
		if k != 0:
			var c2 := Vector3(cos(a + TAU / 12.0), 0, sin(a + TAU / 12.0)) * 2.5
			U.part(n, U.box(Vector3(2.7, 0.12, 0.35)), red, c2 + Vector3(0, 0.95, 0), Vector3(0, -(a + TAU / 12.0) + PI * 0.5, 0))
	U.part(n, U.cyl(3.3, 3.3, 0.35, 6), red, Vector3(0, 3.7, 0))
	U.part(n, U.cyl(0.25, 4.3, 1.8, 6), tiles, Vector3(0, 4.7, 0))
	for k in 6:
		var a := TAU * k / 6.0
		var tip := Vector3(cos(a), 0, sin(a)) * 4.35
		U.part(n, U.cyl(0.03, 0.14, 1.0, 5), tiles, tip + Vector3(0, 3.95, 0), Vector3(sin(a) * 0.75, 0, -cos(a) * 0.75))
	U.part(n, U.sphere(0.3, 10, 8), gold, Vector3(0, 5.75, 0))
	U.part(n, U.cyl(0.02, 0.1, 0.6, 6), gold, Vector3(0, 6.2, 0))
	_lamp(n, Vector3(0, 3.1, 0), Color(1.0, 0.4, 0.2), 1.1)
	_light(n, Vector3(0, 2.8, 0), Color(1.0, 0.6, 0.35), 1.2, 9.0)


## 石灯笼：底座 + 柱 + 灯室（里面一点暖光）+ 顶盖
func _stone_lantern(p: Vector3, stone: Material, lit: bool) -> void:
	var n := Node3D.new()
	add_child(n)
	n.global_position = p
	U.part(n, U.cyl(0.35, 0.42, 0.25, 6), stone, Vector3(0, 0.12, 0))
	U.part(n, U.cyl(0.13, 0.16, 0.9, 6), stone, Vector3(0, 0.7, 0))
	U.part(n, U.cyl(0.32, 0.3, 0.12, 6), stone, Vector3(0, 1.2, 0))
	U.part(n, U.box(Vector3(0.36, 0.34, 0.36)), stone, Vector3(0, 1.43, 0))
	U.part(n, U.box(Vector3(0.38, 0.2, 0.2)), U.glow(Color(1.0, 0.7, 0.35), 2.2), Vector3(0, 1.43, 0), Vector3.ZERO, Vector3.ONE, false)
	U.part(n, U.cyl(0.05, 0.45, 0.3, 6), stone, Vector3(0, 1.75, 0))
	U.part(n, U.sphere(0.08, 6, 4), stone, Vector3(0, 1.95, 0))
	if lit:
		_light(n, Vector3(0, 1.45, 0), Color(1.0, 0.7, 0.4), 0.9, 6.0)
	_col(n, _boxs(Vector3(0.5, 1.9, 0.5)), Transform3D(Basis(), p + Vector3(0, 0.95, 0)))
