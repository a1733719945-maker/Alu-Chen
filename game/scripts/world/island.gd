class_name Island
extends RefCounted
## 小岛的地形数据：高度、魂兽栖息地位置。
## 用固定种子生成，所以每个玩家电脑上的岛一模一样（联机时碰撞必须一致）。

const SIZE := 321                 # 网格顶点数，间距 1 米，岛占 320×320 米
const HALF := (SIZE - 1) / 2
const WATER_Y := 0.0
const SEED := 20260925

var heights := PackedFloat32Array()
var habitats: Array[Dictionary] = []   # {type, center: Vector2, radius, points: Array[Vector3]}
var spawn := Vector3.ZERO
var spawn_yaw := 0.0
var dock_start := Vector3.ZERO         # 码头在岸上的一端
var dock_end := Vector3.ZERO           # 伸进湖里的一端
var shop_pos := Vector3.ZERO
var hill := Vector2(-8, -78)

var _noise := FastNoiseLite.new()
var _shore := FastNoiseLite.new()
var _detail := FastNoiseLite.new()


func _init() -> void:
	_noise.seed = SEED
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.012
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 4
	_shore.seed = SEED + 1
	_shore.frequency = 0.9
	_detail.seed = SEED + 2
	_detail.frequency = 0.08
	_define_habitats()
	_generate()
	_place_landmarks()


func _define_habitats() -> void:
	habitats = [
		{"type": "meadow", "center": Vector2(4, 6), "radius": 25.0, "flat": 2.2, "points": []},
		{"type": "burrow", "center": Vector2(52, -26), "radius": 16.0, "flat": 2.0, "points": []},
		{"type": "flowers", "center": Vector2(-50, -30), "radius": 13.0, "flat": 2.6, "points": []},
	]


## 岛的半径随方向变化，海岸线不是正圆
func _island_radius(angle: float) -> float:
	return 104.0 + _shore.get_noise_2d(cos(angle) * 1.6, sin(angle) * 1.6) * 16.0 + sin(angle * 3.0 + 1.0) * 6.0


func _raw_height(x: float, z: float) -> float:
	var r := Vector2(x, z).length()
	var R := _island_radius(atan2(z, x))
	var land := 1.6 + (_noise.get_noise_2d(x, z) * 0.5 + 0.5) * 5.5 + _detail.get_noise_2d(x, z) * 0.35
	# 北边一座小山，可以站上去俯瞰全岛
	var dh := Vector2(x, z).distance_to(hill)
	land += 11.0 * exp(-dh * dh / (2.0 * 22.0 * 22.0))
	# 栖息地压平，方便走动和抛索
	for h in habitats:
		var d := Vector2(x, z).distance_to(h["center"])
		var k := smoothstep(h["radius"] + 10.0, h["radius"] - 2.0, d)
		land = lerpf(land, h["flat"] + _detail.get_noise_2d(x, z) * 0.25, k)
	# 海岸：岛外是湖底
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


func _place_landmarks() -> void:
	# 码头：从岛中心往南走，找到岸边
	var z := 40.0
	while z < 150.0 and is_land(0.0, z + 1.0):
		z += 1.0
	dock_start = Vector3(0.0, height_at(0.0, z - 3.0) + 0.35, z - 3.0)
	dock_end = Vector3(0.0, WATER_Y + 0.45, z + 16.0)
	spawn = Vector3(2.0, height_at(2.0, z - 12.0) + 0.1, z - 12.0)
	spawn_yaw = 0.0  # 朝北（-Z）
	shop_pos = Vector3(-12.0, height_at(-12.0, z - 16.0), z - 16.0)
	# 兔子洞：田里散布几个洞
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 7
	for h in habitats:
		var pts: Array = []
		if h["type"] == "burrow":
			for k in 8:
				var a := TAU * k / 8.0 + rng.randf_range(-0.3, 0.3)
				var d := rng.randf_range(4.0, h["radius"] - 3.0)
				var c: Vector2 = h["center"] + Vector2(cos(a), sin(a)) * d
				pts.append(Vector3(c.x, height_at(c.x, c.y), c.y))
		else:
			pts.append(Vector3(h["center"].x, height_at(h["center"].x, h["center"].y), h["center"].y))
		h["points"] = pts


## 某个点属于哪个栖息地（"" 表示哪里都不是）
func habitat_at(p: Vector3) -> String:
	if p.y <= WATER_Y + 0.35 and height_at(p.x, p.z) < WATER_Y - 0.15:
		return "water"
	var p2 := Vector2(p.x, p.z)
	for h in habitats:
		if p2.distance_to(h["center"]) <= h["radius"]:
			if h["type"] == "burrow":
				# 要落在某个洞口附近
				for b in h["points"]:
					if p2.distance_to(Vector2(b.x, b.z)) < 3.5:
						return "burrow"
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
	if type == "water":
		# 往离岛中心更远的方向爬，直到找到水
		var dir := Vector3(from.x, 0, from.z).normalized()
		if dir == Vector3.ZERO:
			dir = Vector3.FORWARD
		var p := from
		for i in 80:
			p += dir * 2.0
			if not is_land(p.x, p.z):
				return Vector3(p.x, WATER_Y, p.z)
		return p
	var h := habitat(type)
	if h.is_empty():
		return from
	var best: Vector3 = h["points"][0]
	for b in h["points"]:
		if b.distance_to(from) < best.distance_to(from):
			best = b
	return best
