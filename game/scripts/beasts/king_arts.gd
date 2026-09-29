class_name KingArts
extends Node
## 样板狩猎第二步（2026-09-29 大号）：猎场猎物的一整套招 + 三段战斗的节奏。
## 用户："我们说的狩猎一次 15 分钟紧张的那个东西，我感觉没有"——小号做了断部位 / 打晕 / 暴怒疲劳（KingFeel），
## 但猎物单人一直开火 10~20 秒就打死了，招也还是所有灵兽王共用的三招（震地 / 扑杀 / 咆哮）。这里：
##   招：按体型一套。走的：扑咬（暴怒连咬）、甩尾横扫（扫身后一大圈，站在头前面反而安全）、冲锋（打空了刹不住，露破绽）、
##       跃击（跳起来砸你站的地方，落地露破绽）、地裂（一串圈朝你炸过来，第二回合起）；
##       飞的：俯冲（沿一条线冲下来，落地歇一下露破绽）、风刃（前方扇形）、羽雨（一片小圈）、旋风（把人往中间吸，第二回合起）、翅击（贴身一圈）。
##       每招有起手（身子压低 / 仰起来，地上出预警），翻滚能躲；暴怒起手快三成、会连招；累了只放轻招、起手慢
##   破绽：KingFeel.open（受伤 ×1.3、打头再 ×1.5，头上「破绽」）
##   节奏：七成血负伤换地方（吼一声，跑去另一片区域，一路滴血，追过去再打）→ 三成五逃回巢穴睡觉（KingFeel 之前就有）→ 巢穴决战（招更密）
##   伤害按这一章参考等级的血量算（Data.bite_cap 反推）：轻招一成、中招一成五、重招两成半左右
## 只在房主上跑；招的样子和打没打到用 BossArts（ba 消息，每台电脑自己判断），起手的姿势 / 破绽用 KingFeel 的事件同步

const STYLE_CH := {1: "water", 2: "fire", 3: "rock", 4: "ice", 5: "poison"}
const RELOCATE_AT := 0.7
const RELOCATE_MIN := 110.0
const RELOCATE_MAX := 280.0
const RELOCATE_SPEED := 9.5      # 比人冲刺（8.6）快一点：跟不上，要循着血迹和爪痕找
const CD := {"calm": [1.4, 2.4], "rage": [0.55, 1.1], "tired": [2.8, 4.0]}
## 轻招（累了也放）
const LIGHT := ["bite", "buffet", "gust"]
## 各招伤害（占这一章参考血量）
const DMG := {"bite": 0.1, "sweep": 0.16, "charge": 0.24, "leap": 0.28, "quake": 0.12, "roar": 0.06,
	"dive": 0.22, "gust": 0.14, "feathers": 0.1, "vortex": 0.06, "buffet": 0.14}

var world: Node
var b: Beast
var act := 1                     # 第几回合：1 老窝 / 2 负伤换了地方 / 3 巢穴
var cur := {}                    # 正在放的招
var cd := 2.5
var relocated := false
var _relocating := false
var _reloc_to := Vector3.ZERO
var _reloc_t := 0.0
var _last := ""
var _strafe := 1.0
var _strafe_t := 0.0
var _u := 100.0                  # 这一章参考血量（护体前）
var moves_done := {}             # 放过的招（自动测试看）
var _stuck_p := Vector3.INF      # 卡住检测：一秒前在哪
var _stuck_t := 0.0
var _detour := 0.0               # 绕路还剩几秒
var _detour_dir := Vector3.ZERO


static func attach(p_world: Node, beast: Beast) -> KingArts:
	if beast.arts:
		return beast.arts
	var a := KingArts.new()
	a.world = p_world
	a.b = beast
	a.name = "KingArts"
	beast.arts = a
	beast.add_child(a)
	a._u = Data.bite_cap(int(p_world.chapter), true) / Data.BITE_CAP_KING * Profile.rebirth_hard()
	return a


func _style() -> String:
	return str(STYLE_CH.get(int(world.chapter), "rock"))


## 这一招的伤害（BossArts 会再乘 Boss 的章节倍数，这里先除掉）
func _d(move: String) -> float:
	var k := 1.2 if b.enrage_t > 0.0 else 1.0
	return _u * float(DMG.get(move, 0.1)) * k / maxf(world.arts._k(), 0.01)


## 起手时间倍数：暴怒快、累了慢、巢穴决战也快一点
func _tk() -> float:
	var k := 1.0
	if b.feel.mood == "rage":
		k *= 0.72
	elif b.feel.mood == "tired":
		k *= 1.35
	if act >= 3:
		k *= 0.9
	return k


func _bs() -> Vector3:
	return BeastModels.body_size(b.species) * float(Data.AGES[b.age]["scale"]) * b.size_k


func _reach() -> float:
	return (1.3 + _bs().z * 0.45) * 1.0


## 往 dir 走：一秒走不到 2.5 米就是被树 / 石头挡住了——往左或往右斜着绕 1.6 秒，顺便跳一下（以前换地方时顶着一棵树原地跑了 50 秒）
func _steer(dir: Vector3, delta: float, touching: bool) -> Vector3:
	_stuck_t += delta
	if _stuck_t > 1.0:
		if _stuck_p != Vector3.INF and _detour <= 0.0 and Vector2(b.global_position.x - _stuck_p.x, b.global_position.z - _stuck_p.z).length() < 2.5:
			_detour = 1.6
			_detour_dir = dir.rotated(Vector3.UP, deg_to_rad(75.0) * (1.0 if randf() < 0.5 else -1.0))
			if touching:
				b.linear_velocity.y = 4.5
		_stuck_p = b.global_position
		_stuck_t = 0.0
	if _detour > 0.0:
		_detour -= delta
		return _detour_dir
	return dir


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, maxf(world.island.height_at(p.x, p.z), Island.WATER_Y), p.z)


func busy() -> bool:
	return not cur.is_empty() or _relocating


func relocating() -> bool:
	return _relocating


## 被打晕 / 断部位摔倒 / 被捆住：手上的招不放了（已经出了预警的照样砸下来）
func cancel() -> void:
	cur.clear()
	cd = maxf(cd, 1.2)


# ------------------------------------------------------------------ 打架（Beast._elite 调）

var _ticked := 0.0


## 保险：Beast._elite 有一阵没调我（掉进水里在游、被打飞到空中），手上的招就作废，别卡在半截
func _physics_process(_dt: float) -> void:
	# 在巢穴里醒了（偷袭 / 回够了血）：第三回合，巢穴决战
	if b._rested and act < 3:
		act = 3
		cd = 1.0
	if not cur.is_empty() and Time.get_ticks_msec() / 1000.0 - _ticked > 1.0 / maxf(Engine.time_scale, 0.1):
		cancel()


func host_tick(delta: float, tp: Dictionary, m: String, touching: bool) -> void:
	_ticked = Time.get_ticks_msec() / 1000.0
	# 普通的扑咬 / 冲锋不放了：所有攻击都走这里（有起手、有预警、能躲）
	b._atk_cd = 99.0
	var tpos: Vector3 = tp["pos"]
	var fly := m in ["fly", "flutter"]
	var to := tpos - b.global_position
	var flat := Vector3(to.x, 0, to.z)
	var dist := flat.length()
	if not cur.is_empty():
		_run(delta, tpos, touching, fly)
		return
	cd -= delta
	if b._special_tick(delta, tpos, dist, touching):
		return
	if cd <= 0.0:
		_target_dry = world.island.is_land(tpos.x, tpos.z)
		var mv := _pick(dist, fly)
		if mv != "":
			_start(mv, tpos, int(tp.get("peer", 0)), fly)
			return
	_position(delta, tpos, flat, dist, touching, fly, m)


var _target_dry := true


## 从 g 往 dir 走 L 米，到水边就停（陆地的冲锋不冲进水里）
func _land_len(g: Vector3, dir: Vector3, L: float) -> float:
	var d := 0.0
	while d < L:
		var q := g + dir * (d + 2.0)
		if not world.island.is_land(q.x, q.z):
			break
		d += 2.0
	return maxf(d, 6.0)


func _pick(dist: float, fly: bool) -> String:
	var r := _reach()
	var w := {}
	if fly:
		w["buffet"] = 3.0 if dist < r + 4.5 else 0.0
		w["gust"] = 2.2 if dist < 15.0 else 0.0
		w["dive"] = 2.6 if dist > 6.0 and dist < 34.0 else 0.0
		w["feathers"] = 2.0 if dist < 26.0 else 0.0
		w["vortex"] = 1.4 if act >= 2 and dist < 20.0 else 0.0
	else:
		w["bite"] = 3.0 if dist < r + 4.0 else 0.0
		w["sweep"] = 2.6 if dist < r + 3.0 and not b.feel.broken("tail") else 0.0
		w["charge"] = 2.4 if dist > 8.0 and dist < 32.0 else 0.0
		w["leap"] = 2.0 if dist > 6.0 and dist < 24.0 and _target_dry else 0.0
		w["quake"] = 1.8 if act >= 2 and dist < 22.0 else 0.0
	if b.feel.mood == "tired":
		for k in w.keys():
			if not k in LIGHT:
				w[k] = 0.0
	if w.has(_last):
		w[_last] = float(w[_last]) * 0.3
	var tot := 0.0
	for k in w:
		tot += float(w[k])
	if tot <= 0.0:
		return ""
	var x := randf() * tot
	for k in w:
		x -= float(w[k])
		if x <= 0.0:
			return str(k)
	return ""


## 没在放招：陆地的追上来 / 贴身时左右绕；飞的在人头顶盘旋
func _position(delta: float, tpos: Vector3, flat: Vector3, dist: float, touching: bool, fly: bool, m: String) -> void:
	var dir := flat.normalized() if dist > 0.01 else -b.global_basis.z
	if fly:
		b.gravity_scale = 0.0
		var orbit := b.life * 0.7 + b.id
		var goal := tpos + Vector3(cos(orbit) * 9.0, 5.0 + sin(b.life * 1.7) * 0.8, sin(orbit) * 9.0)
		b.linear_velocity = b.linear_velocity.lerp((goal - b.global_position).limit_length(9.0 * b._spd()) * 1.2, 1.0 - exp(-2.5 * delta))
		b.angular_velocity = b.angular_velocity.lerp(Vector3.ZERO, 1.0 - exp(-6.0 * delta))
		b._face(dir, 0.2)
		return
	if not touching:
		return
	var r := _reach()
	var want := 0.0
	if dist > r + 6.0:
		want = 1.0
	elif dist < r + 0.5:
		want = -0.4
	_strafe_t -= delta
	if _strafe_t <= 0.0:
		_strafe_t = randf_range(1.5, 3.0)
		_strafe = -_strafe
	var side := dir.cross(Vector3.UP) * _strafe * (0.6 if want == 0.0 else 0.15)
	var sp := (7.8 if want > 0.0 else 2.8) * b._spd()
	if b.speed_cap > 0.0:
		sp = minf(sp, b.speed_cap)
	var v := (dir * want + side)
	v = v.normalized() * sp if v.length() > 0.05 else Vector3.ZERO
	if want > 0.0:
		v = _steer(v.normalized(), delta, touching) * sp
	if m == "hop":
		b.hop_timer -= delta
		if b.hop_timer <= 0.0 and v != Vector3.ZERO:
			b.hop_timer = 0.42
			b.linear_velocity = v + Vector3.UP * 3.6
	else:
		b.linear_velocity = Vector3(v.x, minf(b.linear_velocity.y, 0.5), v.z)
	b.angular_velocity = Vector3.ZERO
	b._face(dir, 0.3)


# ------------------------------------------------------------------ 出招

func _start(mv: String, tpos: Vector3, peer: int, fly: bool, wind_k := 1.0) -> void:
	var A: BossArts = world.arts
	var st := _style()
	var p := b.global_position
	var g := _ground(p)
	var to := Vector3(tpos.x - p.x, 0, tpos.z - p.z)
	var dir := to.normalized() if to.length() > 0.05 else -b.global_basis.z
	var dist := to.length()
	var r := _reach()
	var bs := _bs()
	var tk := _tk() * wind_k
	var rage := b.feel.mood == "rage"
	cur = {"move": mv, "t": 0.0, "dir": dir, "at": tpos, "fired": false, "peer": peer}
	_last = mv
	moves_done[mv] = int(moves_done.get(mv, 0)) + 1
	match mv:
		"bite":
			var w := 0.55 * tk
			cur["wind"] = w
			cur["end"] = w + 0.45
			cur["combo"] = 2 if rage else (1 if act >= 3 else 0)
			A.lane(g, dir, r + 4.5, bs.x * 1.1 + 1.2, w, _d(mv), st)
			b.feel.pose("crouch", w)
		"sweep":
			var w := 0.8 * tk
			var f := -b.global_basis.z
			var af := atan2(f.x, f.z)
			cur["wind"] = w
			cur["end"] = w + 0.55
			A.sweep(g, af + PI * 0.3, af + PI * 1.7, r + 3.5, 0.45, w, 0.5, _d(mv), st)
			b.feel.pose("crouch", w)
		"charge":
			var w := 1.0 * tk
			var L := _land_len(g, dir, clampf(dist + 8.0, 14.0, 30.0))
			cur["wind"] = w
			cur["len"] = L
			cur["end"] = w + L / 16.0
			cur["again"] = rage and not bool(cur.get("second", false))
			A.lane(g, dir, L, bs.x + 1.6, w, _d(mv), st, 16.0)
			b.feel.pose("crouch", w)
		"leap":
			var w := 0.9 * tk
			var T := 1.3
			cur["wind"] = w
			cur["air"] = T
			cur["end"] = w + T + 0.1
			A.circle(tpos, 3.2 + bs.x * 0.6, w + T, _d(mv), st)
			b.feel.pose("crouch", w)
		"quake":
			var w := 0.9 * tk
			cur["wind"] = w
			cur["end"] = w + 0.8
			var pts: Array = []
			for i in 6:
				pts.append([g + dir * (2.5 + i * 3.2), w + 0.12 * i])
			A.rain(pts, 2.3, _d(mv), st)
			if act >= 3 and peer != 0:
				A.chase(peer, 3, 0.6, 2.6, 0.8, _d(mv), st)
			b.feel.pose("rear", w)
		"roar":
			var w := 0.7
			cur["wind"] = w
			cur["end"] = w + 0.6
			A.circle(g, r + 6.0, w, _d(mv), st)
			b.feel.pose("rear", w)
		"dive":
			var w := 0.9 * tk
			cur["wind"] = w
			cur["end"] = w + 28.0 / 20.0
			cur["start"] = g
			A.lane(g, dir, 28.0, bs.x + 1.4, w, _d(mv), st, 20.0)
			b.feel.pose("rear", w)
		"gust":
			var w := 0.7 * tk
			var af := atan2(dir.x, dir.z)
			cur["wind"] = w
			cur["end"] = w + 0.4
			A.sweep(g, af - 0.9, af + 0.9, 15.0, 0.5, w, 0.35, _d(mv), st)
			b.feel.pose("rear", w)
		"feathers":
			var w := 0.6 * tk
			cur["wind"] = w
			cur["end"] = w + 0.5
			var pts: Array = [[tpos, w + 0.25]]
			for i in 6:
				var a := randf() * TAU
				pts.append([tpos + Vector3(cos(a), 0, sin(a)) * randf_range(2.5, 6.5), w + 0.37 + 0.12 * i])
			A.rain(pts, 2.2, _d(mv), st)
			b.feel.pose("rear", w)
		"vortex":
			var w := 0.8 * tk
			cur["wind"] = w
			cur["end"] = w + 1.2
			A.vortex(tpos, 9.0, 3.2, 5.5, 2.6, _d(mv), st)
			b.feel.pose("rear", w)
		"buffet":
			var w := 0.6 * tk
			cur["wind"] = w
			cur["end"] = w + 0.5
			A.circle(g, r + 3.5, w, _d(mv), st)
			b.feel.pose("rear", w)


func _run(delta: float, tpos: Vector3, touching: bool, fly: bool) -> void:
	cur["t"] = float(cur["t"]) + delta
	var t := float(cur["t"])
	var mv := str(cur["move"])
	var wind := float(cur.get("wind", 0.5))
	var dir: Vector3 = cur["dir"]
	if mv == "rest":
		# 破绽：站着 / 落在地上歇一下
		if fly:
			b.gravity_scale = 1.0
		if touching:
			b.linear_velocity = Vector3(0, minf(b.linear_velocity.y, 0.5), 0)
			b.angular_velocity = Vector3.ZERO
		if t >= float(cur["end"]):
			_finish()
		return
	if t < wind:
		# 起手：站住、对着瞄的方向（锁定了，翻滚往旁边躲就躲得开）
		if fly:
			b.gravity_scale = 0.0
			var up := 2.5 if mv == "dive" else 0.0
			b.linear_velocity = b.linear_velocity.lerp(Vector3(0, up, 0), 1.0 - exp(-5.0 * delta))
		elif touching:
			b.linear_velocity = Vector3(0, minf(b.linear_velocity.y, 0.5), 0)
		if mv != "sweep":
			b.angular_velocity = Vector3.ZERO
			b._face(dir, 0.4)
		else:
			# 甩尾前先往反方向拧一下身子
			b.angular_velocity = Vector3(0, -1.2, 0)
		return
	var first := not bool(cur["fired"])
	cur["fired"] = true
	if first:
		BeastModels.play_attack(b.model)
		Sfx.play_at("boss_roar", b.global_position, -6.0, 0.1, 1.5)
	match mv:
		"bite":
			if first:
				b.linear_velocity = dir * 11.0 + Vector3.UP * 1.5
		"sweep":
			b.angular_velocity = Vector3(0, TAU / 0.5, 0)
			if touching:
				b.linear_velocity = Vector3(0, minf(b.linear_velocity.y, 0.5), 0)
		"charge":
			if touching or t - wind < 0.2:
				b.linear_velocity = Vector3(dir.x * 16.0, minf(b.linear_velocity.y, 0.5), dir.z * 16.0)
			b.angular_velocity = Vector3.ZERO
			b._face(dir, 0.5)
		"leap":
			if first:
				var at: Vector3 = cur["at"]
				var d := Vector3(at.x - b.global_position.x, 0, at.z - b.global_position.z)
				var T := float(cur["air"])
				var drop: float = b.global_position.y - float(world.island.height_at(at.x, at.z))
				b.linear_velocity = d / T + Vector3.UP * (9.8 * T * 0.5 - drop / T)
				b.angular_velocity = Vector3.ZERO
		"dive":
			var s: Vector3 = cur["start"]
			var k := clampf((t - wind) * 20.0 / 28.0, 0.0, 1.0)
			var goal := s + dir * 28.0 * k + Vector3.UP * 1.6
			b.gravity_scale = 0.0
			b.linear_velocity = (goal - b.global_position) * 10.0
			b._face(dir, 0.5)
		"buffet":
			if first and fly:
				b.linear_velocity = Vector3(0, -3.0, 0)
	if t >= float(cur["end"]):
		_after(mv, fly)


## 一招放完：连招 / 露破绽 / 回到走位
func _after(mv: String, fly: bool) -> void:
	var combo := int(cur.get("combo", 0))
	var again := bool(cur.get("again", false))
	var peer := int(cur.get("peer", 0))
	if mv == "bite" and combo > 0:
		var tp := _peer_pos(peer)
		cur.clear()
		# 连咬：第二口起手更快
		_start("bite", tp if tp != Vector3.INF else b.global_position - b.global_basis.z * 3.0, peer, fly, 0.7)
		cur["combo"] = combo - 1
		return
	if mv == "charge" and again:
		var tp2 := _peer_pos(peer)
		cur.clear()
		if tp2 != Vector3.INF:
			_start("charge", tp2, peer, fly)
			cur["second"] = true
			cur["again"] = false
			return
	match mv:
		"charge":
			_rest(2.2 if bool(cur.get("second", false)) else 1.6)
			return
		"leap":
			_rest(1.8)
			return
		"dive":
			_rest(1.8)
			return
	_finish()


## 露破绽：站着（飞的落到地上）几秒，挨打 ×1.3、打头再 ×1.5
func _rest(t: float) -> void:
	cur = {"move": "rest", "t": 0.0, "end": t, "dir": -b.global_basis.z, "fired": true}
	b.feel.open(t)


func _finish() -> void:
	cur.clear()
	var r: Array = CD[b.feel.mood] if CD.has(b.feel.mood) else CD["calm"]
	cd = randf_range(float(r[0]), float(r[1])) * (0.8 if act >= 3 else 1.0)


func _peer_pos(peer: int) -> Vector3:
	return world.arts._peer_pos(peer) if peer != 0 else Vector3.INF


# ------------------------------------------------------------------ 负伤换地方（七成血）

func want_relocate() -> bool:
	return not relocated and not _relocating and b.hp < b.max_hp * RELOCATE_AT and b.hp > b.max_hp * 0.4


func start_relocate() -> void:
	relocated = true
	_relocating = true
	cur.clear()
	_reloc_to = _pick_zone()
	# 老家改到新地方：路上掉进水里泡久了，送回的也是新地方
	b.spawn_pos = _reloc_to
	_reloc_t = -1.0
	# 先吼一声把人震开，再跑
	_start("roar", b.global_position, 0, false)
	cur.clear()
	var m := ["%s 负伤逃走了！跟着地上的血迹和爪痕追过去——它在别处等着你" % b.display_name(), 3]
	Net.send(0, "hev", m)
	world.hunt._on_ev(m)


## Beast._elite 调：返回 true 表示还在跑
func relocate_tick(delta: float, m: String, touching: bool) -> bool:
	_reloc_t += delta
	if _reloc_t < 0.0:
		if touching:
			b.linear_velocity = Vector3(0, minf(b.linear_velocity.y, 0.5), 0)
			b.angular_velocity = Vector3.ZERO
		return true
	var to := _reloc_to - b.global_position
	var flat := Vector3(to.x, 0, to.z)
	if flat.length() < 6.0 or _reloc_t > 50.0:
		_relocating = false
		act = 2
		b.spawn_pos = b.global_position if _reloc_t > 50.0 else _reloc_to
		b._aggro_t = 0.0
		cd = 1.5
		return false
	var dir := flat.normalized()
	if m in ["fly", "flutter"]:
		b.gravity_scale = 0.0
		b.linear_velocity = b.linear_velocity.lerp((to + Vector3.UP * 6.0).limit_length(RELOCATE_SPEED + 1.5), 1.0 - exp(-2.5 * delta))
	else:
		dir = _steer(dir, delta, touching)
		if touching:
			b.linear_velocity = Vector3(dir.x * RELOCATE_SPEED, minf(b.linear_velocity.y, 0.5) if b.linear_velocity.y < 1.0 else b.linear_velocity.y, dir.z * RELOCATE_SPEED)
			b.angular_velocity = Vector3.ZERO
	b._face(dir, 0.3)
	return true


## 换去哪：猎场里另一片区域（不是巢穴、不是现在这片），离得够远，离人越远越好
func _pick_zone() -> Vector3:
	var p := b.global_position
	var best := Vector3.INF
	var bs := -INF
	for h in world.island.habitats:
		if str(h.get("role", "")) == "nest":
			continue
		var type := str(h["type"])
		if world.island.is_water_habitat(type):
			continue
		var c: Vector2 = h["center"]
		var q := Vector3(c.x, 0, c.y)
		var d := Vector2(q.x - p.x, q.z - p.z).length()
		if d < RELOCATE_MIN or d > RELOCATE_MAX or not world.island.is_land(q.x, q.z):
			continue
		var np: Vector3 = world.nearest_player_pos(q)
		var s := minf(Vector2(np.x - q.x, np.z - q.z).length(), 200.0) + randf() * 40.0
		# 一路上有水就不好（陆地灵兽掉进水里泡久了会被送回老家）：每 8 米看一下
		var wet := 0
		var n := int(d / 8.0)
		for i in range(1, n):
			var k := float(i) / n
			if not world.island.is_land(lerpf(p.x, q.x, k), lerpf(p.z, q.z, k)):
				wet += 1
		s -= wet * 60.0
		if nest_far(q):
			s += 30.0
		if s > bs:
			bs = s
			best = q
	if best == Vector3.INF:
		best = world.hunt._wander_point(p)
	best.y = world.island.height_at(best.x, best.z) + 0.6
	return best


func nest_far(q: Vector3) -> bool:
	return b.nest_pos == Vector3.INF or Vector2(q.x - b.nest_pos.x, q.z - b.nest_pos.z).length() > 80.0
