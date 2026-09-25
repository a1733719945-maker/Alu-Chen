class_name Island
extends RefCounted
## 地图的地形数据：高度、魂兽栖息地、码头、暗器铺、祭坛、船的位置。
## 用固定种子生成，所以每个玩家电脑上的地图一模一样（联机时碰撞必须一致）。
##
## map_id："island" 第一章湖心岛 / "forest" 第二章落日森林

const SIZE := 321                 # 网格顶点数，间距 1 米，地图 320×320 米
const HALF := (SIZE - 1) / 2
const WATER_Y := 0.0

var map_id := "island"
var map_seed := 20260925
var heights := PackedFloat32Array()
var habitats: Array[Dictionary] = []   # {type, center: Vector2, radius, flat, points: Array[Vector3]}
var ponds: Array[Dictionary] = []      # 森林里的毒沼 {center, radius, depth}
var water_habitat := "water"
var spawn := Vector3.ZERO
var spawn_yaw := 0.0
var dock_start := Vector3.ZERO
var dock_end := Vector3.ZERO
var dock_y := 0.0
var shop_pos := Vector3.ZERO
var shop_yaw := 0.35
var altar_pos := Vector3.ZERO
var boss_pos := Vector3.ZERO           # Boss 出现的地方
var ancient_tree := Vector3.INF        # 森林中心的千年古树
var paths: Array[PackedVector2Array] = []   # 踩出来的小路：出生点通往各处
var hill := Vector2(-8, -78)
var base_radius := 104.0

var _noise := FastNoiseLite.new()
var _shore := FastNoiseLite.new()
var _detail := FastNoiseLite.new()


func _init(p_map := "island") -> void:
	map_id = p_map
	if map_id == "forest":
		map_seed = 20261001
		base_radius = 128.0
		water_habitat = "swamp"
		hill = Vector2(10, -60)
	_noise.seed = map_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.012
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 4
	_shore.seed = map_seed + 1
	_shore.frequency = 0.9
	_detail.seed = map_seed + 2
	_detail.frequency = 0.08
	_define_habitats()
	_generate()
	_place_landmarks()


func _define_habitats() -> void:
	if map_id == "forest":
		habitats = [
			{"type": "den", "center": Vector2(-62, -18), "radius": 16.0, "flat": 3.0, "points": []},
			{"type": "mud", "center": Vector2(58, 8), "radius": 15.0, "flat": 1.2, "points": []},
			{"type": "grove", "center": Vector2(6, -58), "radius": 20.0, "flat": 3.4, "points": []},
		]
		ponds = [
			{"center": Vector2(-22, 34), "radius": 17.0, "depth": 3.5},
			{"center": Vector2(40, -40), "radius": 13.0, "depth": 3.0},
			{"center": Vector2(-70, 50), "radius": 12.0, "depth": 3.0},
		]
	else:
		habitats = [
			{"type": "meadow", "center": Vector2(4, 6), "radius": 25.0, "flat": 2.2, "points": []},
			{"type": "burrow", "center": Vector2(52, -26), "radius": 16.0, "flat": 2.0, "points": []},
			{"type": "flowers", "center": Vector2(-50, -30), "radius": 13.0, "flat": 2.6, "points": []},
		]


## 岛的半径随方向变化，海岸线不是正圆
func _island_radius(angle: float) -> float:
	return base_radius + _shore.get_noise_2d(cos(angle) * 1.6, sin(angle) * 1.6) * 16.0 + sin(angle * 3.0 + 1.0) * 6.0


func _raw_height(x: float, z: float) -> float:
	var r := Vector2(x, z).length()
	var R := _island_radius(atan2(z, x))
	var amp := 5.5 if map_id == "island" else 7.5
	var land := 1.6 + (_noise.get_noise_2d(x, z) * 0.5 + 0.5) * amp + _detail.get_noise_2d(x, z) * 0.35
	var dh := Vector2(x, z).distance_to(hill)
	land += 11.0 * exp(-dh * dh / (2.0 * 22.0 * 22.0))
	# 森林：边缘隆起成山，中间低
	if map_id == "forest":
		land += smoothstep(R - 45.0, R - 10.0, r) * 9.0 * (1.0 if z < 60.0 else 0.2)
	for h in habitats:
		var d := Vector2(x, z).distance_to(h["center"])
		var k := smoothstep(h["radius"] + 10.0, h["radius"] - 2.0, d)
		land = lerpf(land, h["flat"] + _detail.get_noise_2d(x, z) * 0.25, k)
	for p in ponds:
		var d := Vector2(x, z).distance_to(p["center"])
		var k := smoothstep(p["radius"] + 6.0, p["radius"] - 4.0, d)
		land = lerpf(land, -p["depth"] + _detail.get_noise_2d(x, z) * 0.4, k)
	var t := smoothstep(R + 8.0, R - 16.0, r)
	var lake_floor := -6.5 - clampf((r - R) * 0.05, 0.0, 6.0)
	return lerpf(lake_floor, land, t)


func _generate() -> void:
	heights.resize(SIZE * SIZE)
	for j in SIZE:
		var z := float(j - HALF)
		for i in SIZE:
			var x := float(i - HALF)
			heights[i + j * SIZE] = _raw_height(x, z)


## 任意位置的地面高度（和碰撞体一致的双线性插值）
func height_at(x: float, z: float) -> float:
	var fx := clampf(x + HALF, 0.0, SIZE - 1.001)
	var fz := clampf(z + HALF, 0.0, SIZE - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var h00 := heights[i + j * SIZE]
	var h10 := heights[i + 1 + j * SIZE]
	var h01 := heights[i + (j + 1) * SIZE]
	var h11 := heights[i + 1 + (j + 1) * SIZE]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func slope_at(x: float, z: float) -> float:
	var dx := height_at(x + 0.5, z) - height_at(x - 0.5, z)
	var dz := height_at(x, z + 0.5) - height_at(x, z - 0.5)
	return Vector2(dx, dz).length()


func is_land(x: float, z: float) -> bool:
	return height_at(x, z) > WATER_Y + 0.25


func ground_point(x: float, z: float) -> Vector3:
	return Vector3(x, height_at(x, z), z)


func _place_landmarks() -> void:
	# 码头：从中心往南走，找到岸边
	var z := 40.0
	while z < 155.0 and is_land(0.0, z + 1.0):
		z += 1.0
	dock_start = Vector3(0.0, height_at(0.0, z - 3.0) + 0.35, z - 3.0)
	dock_end = Vector3(0.0, WATER_Y + 0.45, z + 16.0)
	dock_y = maxf(dock_start.y, 0.5) + 0.125
	spawn = Vector3(2.0, height_at(2.0, z - 12.0) + 0.1, z - 12.0)
	spawn_yaw = 0.0
	shop_pos = ground_point(-12.0, z - 16.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed + 7
	for h in habitats:
		var pts: Array = []
		if h["type"] in ["burrow", "den"]:
			var n := 8 if h["type"] == "burrow" else 5
			for k in n:
				var a := TAU * k / n + rng.randf_range(-0.3, 0.3)
				var d := rng.randf_range(4.0, h["radius"] - 3.0)
				var c: Vector2 = h["center"] + Vector2(cos(a), sin(a)) * d
				pts.append(ground_point(c.x, c.y))
		else:
			pts.append(ground_point(h["center"].x, h["center"].y))
		h["points"] = pts
	if map_id == "forest":
		var g := habitat("grove")
		ancient_tree = ground_point(g["center"].x, g["center"].y - 15.0)
		altar_pos = ground_point(g["center"].x + 1.0, g["center"].y - 6.5)
		boss_pos = ground_point(g["center"].x, g["center"].y + 3.0)
	else:
		# 祭坛在北边山坡上，面朝湖；湖主从祭坛正前方的湖里出来，站在祭坛边就能打
		altar_pos = ground_point(hill.x + 3.0, hill.y - 13.0)
		var bz := hill.y - 10.0
		while bz > -170.0 and is_land(hill.x, bz):
			bz -= 1.0
		boss_pos = Vector3(hill.x, WATER_Y, bz - 18.0)
	_make_paths()


## 小路：从出生点走到暗器铺、各个栖息地、祭坛。路线是折线，搭建场景时再加上弯曲
func _make_paths() -> void:
	var s := Vector2(spawn.x, spawn.z - 4.0)
	var shop := Vector2(shop_pos.x, shop_pos.z)
	var altar := Vector2(altar_pos.x, altar_pos.z + 3.0)
	paths.append(PackedVector2Array([Vector2(dock_start.x, dock_start.z), s, shop]))
	if map_id == "forest":
		var den: Vector2 = habitat("den")["center"]
		var mud: Vector2 = habitat("mud")["center"]
		var grove: Vector2 = habitat("grove")["center"]
		var fork := s + Vector2(0, -38)
		paths.append(PackedVector2Array([s, fork, grove + Vector2(0, 16), altar]))
		paths.append(PackedVector2Array([fork, Vector2(-30, -6), den + Vector2(14, 0)]))
		paths.append(PackedVector2Array([fork, Vector2(34, 18), mud + Vector2(-13, 0)]))
	else:
		var meadow: Vector2 = habitat("meadow")["center"]
		var burrow: Vector2 = habitat("burrow")["center"]
		var flowers: Vector2 = habitat("flowers")["center"]
		paths.append(PackedVector2Array([s, meadow + Vector2(0, 22)]))
		paths.append(PackedVector2Array([meadow + Vector2(20, -8), burrow + Vector2(-14, 4)]))
		paths.append(PackedVector2Array([meadow + Vector2(-18, -10), flowers + Vector2(12, 6)]))
		paths.append(PackedVector2Array([meadow + Vector2(0, -24), Vector2(hill.x + 10.0, hill.y + 36.0), altar]))


## 到最近一条小路的距离
func path_distance(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := INF
	for pl in paths:
		for i in pl.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(p, pl[i], pl[i + 1])
			best = minf(best, p.distance_to(q))
	return best


## 某个点属于哪个栖息地（"" 表示哪里都不是）
func habitat_at(p: Vector3) -> String:
	if p.y <= WATER_Y + 0.35 and height_at(p.x, p.z) < WATER_Y - 0.15:
		return water_habitat
	var p2 := Vector2(p.x, p.z)
	for h in habitats:
		if p2.distance_to(h["center"]) <= h["radius"]:
			if h["type"] in ["burrow", "den"]:
				var r := 3.5 if h["type"] == "burrow" else 4.5
				for b in h["points"]:
					if p2.distance_to(Vector2(b.x, b.z)) < r:
						return h["type"]
				return ""
			return h["type"]
	return ""


func habitat(type: String) -> Dictionary:
	for h in habitats:
		if h["type"] == type:
			return h
	return {}


## 魂兽落地后逃往的地方
func escape_point(type: String, from: Vector3) -> Vector3:
	if type == water_habitat:
		# 找最近的水：先看池塘，再往外找湖
		var best := Vector3.INF
		for p in ponds:
			var c := Vector3(p["center"].x, WATER_Y, p["center"].y)
			if from.distance_to(c) < from.distance_to(best):
				best = c
		var dir := Vector3(from.x, 0, from.z).normalized()
		if dir == Vector3.ZERO:
			dir = Vector3.FORWARD
		var q := from
		for i in 90:
			q += dir * 2.0
			if not is_land(q.x, q.z):
				if from.distance_to(q) < from.distance_to(best):
					best = Vector3(q.x, WATER_Y, q.z)
				break
		return best if best != Vector3.INF else from
	var h := habitat(type)
	if h.is_empty():
		return from
	var best: Vector3 = h["points"][0]
	for b in h["points"]:
		if b.distance_to(from) < best.distance_to(from):
			best = b
	return best
