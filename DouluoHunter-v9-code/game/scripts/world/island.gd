class_name Island
extends RefCounted
## 地图的地形数据：高度、魂兽栖息地、码头、暗器铺、祭坛、船的位置。
## 用固定种子生成，所以每个玩家电脑上的地图一模一样（联机时碰撞必须一致）。
##
## 五张地图（map_id）：
##   island     第一章 湖心岛：湖中间一个岛，北边小山上有祭坛，湖主从北边湖里出来
##   forest     第二章 落日森林：四周是山，中间有沼泽，古树林里召唤 Boss
##   deepforest 第三章 星斗大森林：更大更密的夜晚森林
##   snow       第四章 极北之地：湖中间的雪岛，冰湖
##   sea        第五章 海神岛：大海中间的岛，海水越深魂兽越强

const SIZE := 321                 # 网格顶点数，间距 1 米，地图 320×320 米
const HALF := (SIZE - 1) / 2
const WATER_Y := 0.0

## style：island（岛，Boss 在北边水里）/ forest（四周环山，Boss 在中间空地）
## habitats：[类型, 中心, 半径, 压平到的高度]
const MAPS := {
	"island": {"seed": 20260925, "style": "island", "radius": 104.0, "amp": 5.5, "hill": Vector2(-8, -78), "hill_h": 11.0, "rim": 0.0,
		"water": "water",
		"habitats": [["meadow", Vector2(4, 6), 25.0, 2.2], ["burrow", Vector2(52, -26), 16.0, 2.0], ["flowers", Vector2(-50, -30), 13.0, 2.6]]},
	"forest": {"seed": 20261001, "style": "forest", "radius": 128.0, "amp": 7.5, "hill": Vector2(10, -60), "hill_h": 11.0, "rim": 9.0,
		"water": "swamp", "arena": Vector2(6, -58),
		"habitats": [["den", Vector2(-62, -18), 16.0, 3.0], ["mud", Vector2(58, 8), 15.0, 1.2], ["grove", Vector2(6, -58), 20.0, 3.4]],
		"ponds": [[Vector2(-22, 34), 17.0, 3.5], [Vector2(40, -40), 13.0, 3.0], [Vector2(-70, 50), 12.0, 3.0]]},
	"deepforest": {"seed": 20261013, "style": "forest", "radius": 134.0, "amp": 8.5, "hill": Vector2(-30, 10), "hill_h": 9.0, "rim": 12.0,
		"water": "bog", "arena": Vector2(4, -56),
		"habitats": [["glade", Vector2(-62, -40), 18.0, 3.2], ["roost", Vector2(62, -30), 15.0, 3.6], ["thicket", Vector2(60, 34), 16.0, 2.8],
			["nest", Vector2(-58, 38), 15.0, 3.0], ["clearing", Vector2(4, -56), 22.0, 3.6]],
		"ponds": [[Vector2(-6, 20), 16.0, 3.5], [Vector2(26, -86), 11.0, 3.0], [Vector2(-92, -2), 12.0, 3.0]]},
	"snow": {"seed": 20261027, "style": "island", "radius": 118.0, "amp": 7.0, "hill": Vector2(0, -74), "hill_h": 16.0, "rim": 0.0,
		"water": "icelake",
		"habitats": [["snowden", Vector2(-58, -18), 16.0, 3.4], ["icefield", Vector2(52, -26), 20.0, 2.0], ["frostgrove", Vector2(-44, 42), 16.0, 3.0],
			["icecave", Vector2(52, 40), 15.0, 3.8]]},
	"sea": {"seed": 20261109, "style": "island", "radius": 116.0, "amp": 6.0, "hill": Vector2(-10, -70), "hill_h": 14.0, "rim": 0.0,
		"water": "reef", "depths": [[3.0, "reef"], [7.0, "deep"], [999.0, "abyss"]],
		"habitats": [["beach", Vector2(60, 58), 20.0, 1.3], ["cliff", Vector2(-62, -44), 16.0, 9.0]]},
}
## 这些栖息地由几个“洞口”组成（兔子洞、狼穴……），抛到洞口附近才有魂兽
const POINT_HABITATS := ["burrow", "den", "nest", "snowden", "icecave", "roost"]

var map_id := "island"
var map_seed := 20260925
var style := "island"
var cfg: Dictionary
var heights := PackedFloat32Array()
var habitats: Array[Dictionary] = []   # {type, center: Vector2, radius, flat, points: Array[Vector3]}
var ponds: Array[Dictionary] = []      # 森林里的水塘 {center, radius, depth}
var water_habitat := "water"
var water_types: Array = []            # 所有水里的栖息地
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
var arena := Vector2.INF               # 森林地图召唤 Boss 的空地
var paths: Array[PackedVector2Array] = []   # 踩出来的小路：出生点通往各处
var hill := Vector2(-8, -78)
var base_radius := 104.0

var _noise := FastNoiseLite.new()
var _shore := FastNoiseLite.new()
var _detail := FastNoiseLite.new()


func _init(p_map := "island") -> void:
	map_id = p_map if MAPS.has(p_map) else "island"
	cfg = MAPS[map_id]
	map_seed = int(cfg["seed"])
	style = str(cfg["style"])
	base_radius = float(cfg["radius"])
	hill = cfg["hill"]
	water_habitat = str(cfg["water"])
	water_types = [water_habitat]
	if cfg.has("depths"):
		water_types = []
		for d in cfg["depths"]:
			water_types.append(d[1])
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
	for h in cfg["habitats"]:
		habitats.append({"type": h[0], "center": h[1], "radius": h[2], "flat": h[3], "points": []})
	for p in cfg.get("ponds", []):
		ponds.append({"center": p[0], "radius": p[1], "depth": p[2]})
	if cfg.has("arena"):
		arena = cfg["arena"]


## 岛的半径随方向变化，海岸线不是正圆
func _island_radius(angle: float) -> float:
	return base_radius + _shore.get_noise_2d(cos(angle) * 1.6, sin(angle) * 1.6) * 16.0 + sin(angle * 3.0 + 1.0) * 6.0


func _raw_height(x: float, z: float) -> float:
	var r := Vector2(x, z).length()
	var R := _island_radius(atan2(z, x))
	var amp: float = cfg["amp"]
	var land := 1.6 + (_noise.get_noise_2d(x, z) * 0.5 + 0.5) * amp + _detail.get_noise_2d(x, z) * 0.35
	var dh := Vector2(x, z).distance_to(hill)
	land += float(cfg["hill_h"]) * exp(-dh * dh / (2.0 * 22.0 * 22.0))
	# 森林：边缘隆起成山，南边留出口（码头）
	var rim: float = cfg["rim"]
	if rim > 0.0:
		land += smoothstep(R - 45.0, R - 10.0, r) * rim * (1.0 if z < 60.0 else 0.2)
	# 海神岛：靠海的一圈地势低，是大片沙滩
	if map_id == "sea":
		land = lerpf(land * 0.4 + 0.7, land, smoothstep(R - 30.0, R - 70.0, r))
	for h in habitats:
		var d := Vector2(x, z).distance_to(h["center"])
		if h["type"] == "cliff":
			# 海崖：高出一截的台地
			land = lerpf(land, h["flat"] + _detail.get_noise_2d(x, z) * 0.6, smoothstep(h["radius"] + 4.0, h["radius"] - 1.0, d))
			continue
		var k := smoothstep(h["radius"] + 10.0, h["radius"] - 2.0, d)
		land = lerpf(land, h["flat"] + _detail.get_noise_2d(x, z) * 0.25, k)
	for p in ponds:
		# 水塘（碧磷沼、毒沼）：岸边是一大片缓坡浅滩，走着就能上岸，不会掉进去爬不出来
		var d := Vector2(x, z).distance_to(p["center"])
		var k := smoothstep(p["radius"] + 9.0, p["radius"] - 5.0, d)
		var bed := -float(p["depth"]) * smoothstep(p["radius"] + 1.0, p["radius"] - 7.0, d)
		land = lerpf(land, bed + _detail.get_noise_2d(x, z) * 0.3, k)
	var t := smoothstep(R + 8.0, R - 16.0, r)
	var deep := 9.0 if map_id == "sea" else 6.0
	var lake_floor := -6.5 - clampf((r - R) * 0.05, 0.0, deep)
	if map_id == "sea":
		# 近海是一段缓坡浅滩，再往外才突然变深
		lake_floor = lerpf(-1.2, -14.0, smoothstep(R - 4.0, R + 40.0, r))
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


func is_water_habitat(type: String) -> bool:
	return type in water_types


func _place_landmarks() -> void:
	# 码头：从中心往南走，找到岸边
	var z := 40.0
	while z < 155.0 and is_land(0.0, z + 1.0):
		z += 1.0
	# 码头桥面离水面 1 米；从岸上地面正好到这个高度的地方开始搭
	var deck := 1.0
	var zs := z
	while zs > z - 30.0 and height_at(0.0, zs) < deck:
		zs -= 1.0
	dock_start = Vector3(0.0, deck, zs)
	dock_end = Vector3(0.0, WATER_Y + 0.45, z + 16.0)
	dock_y = deck + 0.125
	spawn = Vector3(2.0, height_at(2.0, z - 12.0) + 0.1, z - 12.0)
	spawn_yaw = 0.0
	shop_pos = ground_point(-12.0, z - 16.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed + 7
	for h in habitats:
		var pts: Array = []
		if h["type"] in POINT_HABITATS:
			var n := 8 if h["type"] == "burrow" else 5
			for k in n:
				var a := TAU * k / n + rng.randf_range(-0.3, 0.3)
				var d := rng.randf_range(4.0, h["radius"] - 3.0)
				var c: Vector2 = h["center"] + Vector2(cos(a), sin(a)) * d
				pts.append(ground_point(c.x, c.y))
		else:
			pts.append(ground_point(h["center"].x, h["center"].y))
		h["points"] = pts
	if style == "forest":
		var c := arena
		ancient_tree = ground_point(c.x, c.y - 15.0)
		altar_pos = ground_point(c.x + 1.0, c.y - 6.5)
		boss_pos = ground_point(c.x, c.y + 3.0)
	else:
		# 祭坛在北边山坡上，面朝湖；Boss 从祭坛正前方的湖里出来，站在祭坛边就能打
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
	var hub := s + Vector2(0, -34)
	paths.append(PackedVector2Array([s, hub]))
	for h in habitats:
		var c: Vector2 = h["center"]
		if h["type"] == "clearing" or c == arena:
			continue
		var r: float = h["radius"]
		var to := (hub - c).normalized()
		var mid := hub.lerp(c, 0.5) + Vector2(-to.y, to.x) * 8.0
		paths.append(PackedVector2Array([hub, mid, c + to * (r * 0.6)]))
	if style == "forest":
		paths.append(PackedVector2Array([hub, arena + Vector2(0, 18), altar]))
	else:
		paths.append(PackedVector2Array([hub, Vector2(hill.x + 12.0, hill.y + 34.0), altar]))


## 到最近一条小路的距离
func path_distance(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := INF
	for pl in paths:
		for i in pl.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(p, pl[i], pl[i + 1])
			best = minf(best, p.distance_to(q))
	return best


## 水里某一点属于哪种水域（海神岛按深浅分）
func water_type_at(x: float, z: float) -> String:
	if not cfg.has("depths"):
		return water_habitat
	var depth := WATER_Y - height_at(x, z)
	for d in cfg["depths"]:
		if depth < float(d[0]):
			return d[1]
	return water_habitat


## 某个点属于哪个栖息地（"" 表示哪里都不是）
func habitat_at(p: Vector3) -> String:
	if p.y <= WATER_Y + 0.35 and height_at(p.x, p.z) < WATER_Y - 0.15:
		return water_type_at(p.x, p.z)
	var p2 := Vector2(p.x, p.z)
	for h in habitats:
		if h["type"] == "clearing":
			continue
		if p2.distance_to(h["center"]) <= h["radius"]:
			if h["type"] in POINT_HABITATS:
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


## 某种栖息地大概在哪（任务指路用）
func habitat_center(type: String) -> Vector3:
	var h := habitat(type)
	if not h.is_empty():
		return ground_point(h["center"].x, h["center"].y)
	if is_water_habitat(type):
		# 水：以码头为中心一圈圈往外找，找到离码头最近的这种水域
		for r in range(6, 200, 3):
			var n := maxi(12, r)
			for k in n:
				var a := TAU * k / n
				var q := Vector3(dock_end.x + cos(a) * r, WATER_Y, dock_end.z + sin(a) * r)
				if not is_land(q.x, q.z) and water_type_at(q.x, q.z) == type:
					return q
		for p in ponds:
			return Vector3(p["center"].x, WATER_Y, p["center"].y)
		return dock_end
	return spawn


## 魂兽落地后逃往的地方
func escape_point(type: String, from: Vector3) -> Vector3:
	if is_water_habitat(type):
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
