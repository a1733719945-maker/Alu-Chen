class_name Island
extends RefCounted
## 地图的地形数据：高度、灵兽栖息地、码头、暗器铺、祭坛、船的位置。
## 用固定种子生成，所以每个玩家电脑上的地图一模一样（联机时碰撞必须一致）。
##
## 五张地图（map_id）：
##   island     第一章 镜湖：湖中间一个岛，北边小山上有祭坛，镜湖之主从北边湖里出来
##   forest     第二章 落霞林：四周是山，中间有沼泽，古树林里召唤 Boss
##   deepforest 第三章 苍梧林海：更大更密的夜晚森林
##   snow       第四章 朔北冰原：湖中间的雪岛，冰湖
##   sea        第五章 归墟：大海中间的岛，海水越深灵兽越强

const SIZE := 321                 # 岛的网格顶点数，间距 1 米，地图 320×320 米（猎场更大，见 size）
const HALF := (SIZE - 1) / 2
const HUNT_SIZE := 641            # 猎场 640×640 米（岛的四倍面积）
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
## 这些栖息地由几个“洞口”组成（兔子洞、狼穴……），抛到洞口附近才有灵兽
const POINT_HABITATS := ["burrow", "den", "nest", "snowden", "icecave", "roost"]

var map_id := "island"
var size := SIZE                       # 网格顶点数（岛 321，猎场 641）
var half := HALF
# 猎场（第十二版补丁：用户说岛太小、没有探索感）：猎灵榜挑了灵兽，全队去一张专门的大地图猎它
var hunting := false
var hunt_species := ""
var hills: Array = []                  # 猎场的山头 [中心 Vector2, 高, 宽]
var ridges: Array = []                 # 猎场的山脊 [起点, 终点, 高, 宽]
var treasures: Array = []              # 猎场里藏着的宝藏（山顶、水边、角落）Vector3
var guard_spots: Array = []            # 猎场里灵兽王守着的大宝箱 {"pos": Vector3, "type": 栖息地}
var nest := Vector3.ZERO               # 猎物的巢穴（受重伤逃回这里睡觉）
var home := Vector3.ZERO               # 猎物一开始在哪一带
var rim_r := 270.0                     # 猎场外圈山脚的半径
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


## hunt_seed != 0：这一章的猎场（地形、植被跟这一章一样，但大得多），hunt_species 是要猎的灵兽
func _init(p_map := "island", hunt_seed := 0, p_hunt_species := "") -> void:
	map_id = p_map if MAPS.has(p_map) else "island"
	cfg = MAPS[map_id]
	map_seed = int(cfg["seed"])
	if hunt_seed != 0:
		hunting = true
		hunt_species = p_hunt_species
		map_seed = hunt_seed
		size = HUNT_SIZE
		half = (size - 1) / 2
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
	if hunting:
		_define_hunt()
		_generate()
		_place_hunt_landmarks()
		return
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
	# 归墟：靠海的一圈地势低，是大片沙滩
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
		# 水塘（碧眼沼、毒沼）：岸边是一大片缓坡浅滩，走着就能上岸，不会掉进去爬不出来
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
	heights.resize(size * size)
	for j in size:
		var z := float(j - half)
		for i in size:
			var x := float(i - half)
			heights[i + j * size] = _hunt_height(x, z) if hunting else _raw_height(x, z)


# ------------------------------------------------------------------ 猎场

## 猎场的布局：几片栖息地（猎物的老窝、巢穴、这一章别的灵兽的地盘）、山头、山脊、水塘、营地
func _define_hunt() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed
	rim_r = 262.0
	# 这一章陆地上的栖息地类型（猎物自己的那种一定有，还有它的巢穴）
	var types: Array = []
	var flats := {}
	for h in cfg["habitats"]:
		var t := str(h[0])
		if t != "clearing" and not t in types:
			types.append(t)
			flats[t] = float(h[3])
	var own := str(Data.BEASTS.get(hunt_species, {"habitat": ""})["habitat"])
	if own == "" or not Data.HABITATS.has(own) or is_water_habitat(own):
		own = str(types[0]) if not types.is_empty() else "meadow"
	var plan: Array = [[own, "home"], [own, "nest"]]
	for t in types:
		if t != own:
			plan.append([t, ""])
	# 多出来的区域：再来一片自己的地盘和一片别的，地图才不空
	plan.append([own, ""])
	if types.size() > 1:
		plan.append([types[rng.randi() % types.size()], ""])
	# 营地在南边；老窝在北边远处，巢穴在另一头（受伤了要跑很远，追着打）
	var camp := Vector2(0, rim_r - 30.0)
	var placed: Array = []
	for e in plan:
		var best := Vector2.ZERO
		var bs := -INF
		for tries in 40:
			var a := rng.randf() * TAU
			var r := rng.randf_range(80.0, rim_r - 55.0)
			var c := Vector2(cos(a), sin(a)) * r
			var s := 0.0
			var md := INF
			for q in placed:
				md = minf(md, c.distance_to(q))
			md = minf(md, c.distance_to(camp) * 0.9)
			s = minf(md, 120.0)
			if e[1] == "home":
				s += -c.y * 0.4 + c.distance_to(camp) * 0.3
			elif e[1] == "nest" and not placed.is_empty():
				s += c.distance_to(placed[0]) * 0.5
			s += rng.randf() * 10.0
			if s > bs:
				bs = s
				best = c
		placed.append(best)
		var radius := rng.randf_range(24.0, 32.0)
		var nm := str(Data.HABITATS[e[0]]["name"]) if Data.HABITATS.has(e[0]) else "荒野"
		if e[1] == "nest":
			nm = "%s巢穴" % str(Data.BEASTS.get(hunt_species, {"name": "灵兽"})["name"])
		# 海崖这种台地保持原来的高度，别的区域高低随机一点
		var flat: float = float(flats[e[0]]) if str(e[0]) == "cliff" else rng.randf_range(2.2, 4.5)
		habitats.append({"type": e[0], "center": best, "radius": radius, "flat": flat, "points": [], "label": nm, "role": e[1]})
	# 山头、山脊：地势起伏，站到高处才看得远
	for k in rng.randi_range(7, 10):
		var c2 := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(40.0, rim_r - 40.0)
		var ok := c2.distance_to(camp) > 60.0
		for h in habitats:
			if c2.distance_to(h["center"]) < float(h["radius"]) + 30.0:
				ok = false
		if ok:
			hills.append([c2, rng.randf_range(8.0, 24.0), rng.randf_range(22.0, 40.0)])
	for k in 3:
		var a0 := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(60.0, 200.0)
		var a1 := a0 + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(70.0, 140.0)
		ridges.append([a0, a1, rng.randf_range(6.0, 12.0), rng.randf_range(10.0, 16.0)])
	# 水塘
	var pond_n := 4 if map_id == "sea" else 3
	for k in pond_n:
		for tries in 20:
			var c3 := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(50.0, rim_r - 60.0)
			var ok2 := c3.distance_to(camp) > 50.0
			for h in habitats:
				if c3.distance_to(h["center"]) < float(h["radius"]) + 25.0:
					ok2 = false
			if ok2:
				ponds.append({"center": c3, "radius": rng.randf_range(14.0, 24.0), "depth": rng.randf_range(2.5, 4.0)})
				break


## 猎场的高度：起伏的地面 + 山头 + 山脊 + 压平的栖息地 + 水塘，外面一圈高山围住
func _hunt_height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var r := p.length()
	var amp: float = float(cfg["amp"]) + 3.0
	var land := 2.0 + (_noise.get_noise_2d(x, z) * 0.5 + 0.5) * amp + _detail.get_noise_2d(x, z) * 0.4
	for h in hills:
		var d := p.distance_to(h[0])
		land += float(h[1]) * exp(-d * d / (2.0 * float(h[2]) * float(h[2])))
	for g in ridges:
		var q := Geometry2D.get_closest_point_to_segment(p, g[0], g[1])
		var d2 := p.distance_to(q)
		land += float(g[2]) * exp(-d2 * d2 / (2.0 * float(g[3]) * float(g[3]))) * (0.7 + 0.3 * _detail.get_noise_2d(x * 0.5, z * 0.5))
	for h in habitats:
		var d3 := p.distance_to(h["center"])
		var k := smoothstep(float(h["radius"]) + 14.0, float(h["radius"]) - 2.0, d3)
		land = lerpf(land, float(h["flat"]) + _detail.get_noise_2d(x, z) * 0.3, k)
	# 营地一小块平地
	land = lerpf(land, 2.4, smoothstep(26.0, 12.0, p.distance_to(Vector2(0, rim_r - 30.0))))
	for pd in ponds:
		var d4 := p.distance_to(pd["center"])
		var kk := smoothstep(float(pd["radius"]) + 9.0, float(pd["radius"]) - 5.0, d4)
		var bed := -float(pd["depth"]) * smoothstep(float(pd["radius"]) + 1.0, float(pd["radius"]) - 7.0, d4)
		land = lerpf(land, bed + _detail.get_noise_2d(x, z) * 0.3, kk)
	# 外圈的山：走到边上是山壁，爬不出去
	var edge := rim_r + _shore.get_noise_2d(cos(atan2(z, x)) * 1.6, sin(atan2(z, x)) * 1.6) * 14.0
	land += smoothstep(edge - 20.0, edge + 30.0, r) * (38.0 + _noise.get_noise_2d(x * 0.6, z * 0.6) * 14.0)
	return land


func _place_hunt_landmarks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed + 7
	var camp := Vector2(0, rim_r - 30.0)
	spawn = Vector3(camp.x, height_at(camp.x, camp.y) + 0.1, camp.y)
	spawn_yaw = 0.0
	# 岛上才有的东西（码头、暗器铺、祭坛、Boss）放到营地 / 很远的地方，不会用到
	dock_start = spawn + Vector3(0, 0, 8)
	dock_end = dock_start
	dock_y = spawn.y
	shop_pos = spawn + Vector3(-8, 0, 3)
	altar_pos = Vector3(9999, 0, 9999)
	boss_pos = Vector3(9999, 0, 9999)
	for h in habitats:
		var pts: Array = []
		if h["type"] in POINT_HABITATS:
			var n := 7
			for k in n:
				var a := TAU * k / n + rng.randf_range(-0.3, 0.3)
				var d := rng.randf_range(5.0, h["radius"] - 4.0)
				var c: Vector2 = h["center"] + Vector2(cos(a), sin(a)) * d
				pts.append(ground_point(c.x, c.y))
		else:
			pts.append(ground_point(h["center"].x, h["center"].y))
		h["points"] = pts
		match str(h.get("role", "")):
			"home":
				home = ground_point(h["center"].x, h["center"].y)
			"nest":
				nest = ground_point(h["center"].x, h["center"].y)
	# 宝藏：山顶、水塘边、山脊上、区域边上
	for hl in hills:
		if treasures.size() >= 6:
			break
		var c: Vector2 = hl[0]
		treasures.append(ground_point(c.x, c.y))
	for pd in ponds:
		var c2: Vector2 = pd["center"] + Vector2.from_angle(rng.randf() * TAU) * (float(pd["radius"]) + 6.0)
		if is_land(c2.x, c2.y):
			treasures.append(ground_point(c2.x, c2.y))
	for g in ridges:
		var c3: Vector2 = (g[0] as Vector2).lerp(g[1], 0.5)
		if c3.length() < rim_r - 30.0:
			treasures.append(ground_point(c3.x, c3.y))
	while treasures.size() < 14:
		var c4 := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(60.0, rim_r - 35.0)
		if is_land(c4.x, c4.y) and c4.distance_to(camp) > 50.0:
			treasures.append(ground_point(c4.x, c4.y))
	# 灵兽王守着的大宝箱：别的灵兽的地盘里（不在猎物的老窝和巢穴），离营地远的先挑，最多 3 个
	# （和猎物同一种的地盘不要，免得守宝的王和猎物长得一样）
	var zs: Array = habitats.filter(func(h): return str(h.get("role", "")) == "" and not is_water_habitat(str(h["type"])) and Data.HABITATS.has(str(h["type"])) \
		and str(Data.HABITATS[str(h["type"])]["beast"]) != hunt_species)
	zs.sort_custom(func(a, b): return (a["center"] as Vector2).distance_to(camp) > (b["center"] as Vector2).distance_to(camp))
	for h in zs:
		if guard_spots.size() >= 3:
			break
		var c6: Vector2 = h["center"]
		if is_land(c6.x, c6.y):
			guard_spots.append({"pos": ground_point(c6.x, c6.y), "type": str(h["type"])})
	# 小路：营地通往各个区域（中间一个路口），路弯弯曲曲
	var hub := camp + Vector2(0, -60)
	paths.append(PackedVector2Array([camp, hub]))
	for h in habitats:
		var c5: Vector2 = h["center"]
		var to := (hub - c5).normalized()
		var mid := hub.lerp(c5, 0.5) + Vector2(-to.y, to.x) * 18.0
		paths.append(PackedVector2Array([hub, mid, c5 + to * (float(h["radius"]) * 0.6)]))


## 一片区域的名字（猎场地图上、罗盘上用）
func zone_name(p: Vector3) -> String:
	var best := ""
	var bd := INF
	for h in habitats:
		var d := Vector2(p.x, p.z).distance_to(h["center"])
		if d < bd:
			bd = d
			best = str(h.get("label", Data.HABITATS.get(str(h["type"]), {"name": "荒野"})["name"]))
	return best if bd < 90.0 else "荒野"


## 地图外面另搭的平台（秘境的场地）：[{"c": Vector2, "r2": 半径平方, "y": 高度}]。在里面 height_at 直接返回平台高度，
## 所以灵兽、红圈、脚印、落地这些用到地面高度的东西在秘境里照常用
var floors: Array = []


func add_floor(center: Vector3, radius: float) -> void:
	floors.append({"c": Vector2(center.x, center.z), "r2": radius * radius, "y": center.y})


## 长方形的平台（试炼 · 尸潮追击的长街）：half = 半宽（x）、半长（z）
func add_floor_rect(center: Vector3, half: Vector2) -> void:
	floors.append({"c": Vector2(center.x, center.z), "r2": -1.0, "h": half, "y": center.y})


func _in_floor(f: Dictionary, x: float, z: float, pad := 0.0) -> bool:
	var c: Vector2 = f["c"]
	if float(f["r2"]) < 0.0:
		var h: Vector2 = f["h"]
		return absf(x - c.x) < h.x + pad and absf(z - c.y) < h.y + pad
	var r := sqrt(float(f["r2"])) + pad
	return (x - c.x) * (x - c.x) + (z - c.y) * (z - c.y) < r * r


## 任意位置的地面高度（和碰撞体一致的双线性插值）
func height_at(x: float, z: float) -> float:
	for f in floors:
		if _in_floor(f, x, z):
			return float(f["y"])
	var fx := clampf(x + half, 0.0, size - 1.001)
	var fz := clampf(z + half, 0.0, size - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var h00 := heights[i + j * size]
	var h10 := heights[i + 1 + j * size]
	var h01 := heights[i + (j + 1) * size]
	var h11 := heights[i + 1 + (j + 1) * size]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func slope_at(x: float, z: float) -> float:
	var dx := height_at(x + 0.5, z) - height_at(x - 0.5, z)
	var dz := height_at(x, z + 0.5) - height_at(x, z - 0.5)
	return Vector2(dx, dz).length()


func is_land(x: float, z: float) -> bool:
	return height_at(x, z) > WATER_Y + 0.25


## 这个点在不在额外加的平台上（秘境场地）——野外刷怪、摆东西要避开
func on_floor(x: float, z: float) -> bool:
	for f in floors:
		if _in_floor(f, x, z, 20.0):
			return true
	return false


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


## 水里某一点属于哪种水域（归墟按深浅分）
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


## 灵兽落地后逃往的地方
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
