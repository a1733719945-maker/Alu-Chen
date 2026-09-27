class_name Gun
extends RefCounted
## 一把暗器的状态：弹匣、射速、后坐、散布、换弹、拉栓。
##
## 手感原理（参考 CS / COD）：
##   1. 后坐 recoil：每发按固定图案往上/左右跳（加一点随机），准星和弹道一起跳。
##      停火一小会儿后按 recover_speed 回正。连射越久跳得越高，所以要往下拉鼠标"压枪"。
##   2. 镜头冲击 view punch：每发让镜头额外顶一下再弹回，只影响画面不影响弹道。
##   3. 散布 spread：第一发最准；每发增加一点（bloom），停火后恢复；移动、跳跃时变大，开镜、蹲下时变小。

var id: String
var d: Dictionary
var ammo := 0
var fire_cd := 0.0
var spray := 0.0                 # 连射计数（停火后回落）
var recoil := Vector2.ZERO       # 累积后坐（度）
var bloom := 0.0
var since_shot := 99.0
var reloading := false
var reload_t := 0.0
var reload_total := 0.0
var cycling := 0.0               # 拉栓剩余时间
var burst_left := 0
var _pattern: Array = []


func _init(p_id: String, stats: Dictionary) -> void:
	id = p_id
	set_stats(stats)
	ammo = int(d["mag"])


func set_stats(stats: Dictionary) -> void:
	d = stats
	_pattern = Data.pattern(d)
	ammo = mini(ammo, int(d["mag"]))


func interval() -> float:
	return 60.0 / float(d["rpm"])


## 每帧更新。speed_k 是换弹速度加成（增幅魂技）。返回事件列表（给音效、动画用）
func update(dt: float, speed_k := 1.0) -> Array:
	var ev: Array = []
	fire_cd -= dt
	since_shot += dt
	if cycling > 0.0:
		cycling -= dt
		if cycling <= 0.0:
			ev.append("cycled")
	if since_shot > 0.08:
		bloom = move_toward(bloom, 0.0, float(d["bloom_recover"]) * dt)
	if since_shot > float(d["recover_delay"]):
		recoil = recoil.move_toward(Vector2.ZERO, float(d["recover_speed"]) * dt)
		# 回正得差不多了，连射计数也清零
		spray = move_toward(spray, 0.0, dt * float(d["recover_speed"]) * 0.8)
	if reloading:
		reload_t += dt * speed_k
		if d["per_shell"]:
			if reload_t >= reload_total:
				reload_t = 0.0
				ammo += 1
				ev.append("shell")
				if ammo >= int(d["mag"]):
					reloading = false
					ev.append("reload_done")
		elif reload_t >= reload_total:
			reloading = false
			ammo = int(d["mag"])
			ev.append("reload_done")
	return ev


func ready_to_fire() -> bool:
	return fire_cd <= 0.0 and cycling <= 0.0 and ammo > 0 and (not reloading or (d["per_shell"] and ammo > 0))


func start_reload() -> bool:
	if reloading or ammo >= int(d["mag"]):
		return false
	reloading = true
	reload_t = 0.0
	reload_total = float(d["reload"]) if (ammo > 0 or d["per_shell"]) else float(d["reload_empty"])
	return true


func cancel_reload() -> void:
	reloading = false
	reload_t = 0.0


func reload_progress() -> float:
	if not reloading:
		return 0.0
	return clampf(reload_t / maxf(reload_total, 0.01), 0.0, 1.0)


## 开一枪：更新弹药、射速、后坐、散布。返回这一发新增的后坐（度）
func shoot(ads: float) -> Vector2:
	if reloading and d["per_shell"]:
		cancel_reload()
	ammo -= 1
	fire_cd = interval()
	since_shot = 0.0
	var idx := mini(int(spray), _pattern.size() - 1)
	var step: Vector2 = _pattern[idx]
	var k: float = float(d.get("recoil_mult", 1.0)) * lerpf(1.0, float(d["ads_recoil"]), ads)
	var j: float = float(d["jitter"])
	step = step * k + Vector2(randf_range(-j, j), randf_range(-j * 0.3, j)) * k
	# 连射放大（冲锋、步枪），配件：制退器压上跳、握把压左右
	step *= float(d.get("recoil_scale", 1.0))
	step.x *= float(d.get("recoil_h", 1.0))
	step.y *= float(d.get("recoil_v", 1.0))
	recoil += step
	spray += 1.0
	bloom = minf(bloom + float(d["bloom"]), float(d["bloom_max"]))
	if d["mode"] == "bolt":
		cycling = float(d.get("cycle", 1.0))
	return step


## 当前散布（度）。speed_k：当前水平速度 / 走路速度
func spread(ads: float, speed_k: float, airborne: bool, crouching: bool, scoped: bool) -> float:
	var base := lerpf(float(d["hip"]), float(d["ads"]), ads)
	if d.get("scope", false):
		# 瞬狙：镜子一开（开到六成）就是准的，不用等完全开镜
		base = float(d["hip"]) if ads < 0.55 else float(d["ads"])
	var s := base + bloom + float(d["move"]) * clampf(speed_k, 0.0, 1.5) * lerpf(1.0, 0.6, ads)
	if airborne:
		s += float(d["air"])
	if crouching:
		s *= float(d["crouch"])
	return s
