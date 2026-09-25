class_name Lure
extends Node3D
## 引魂索：按住 E 蓄力、松开甩出去；魂兽咬住时再按 E 把它拽上天。
## 千年魂兽要按住 E 拉扯几秒，拉力太大（红色）要松一下，不然索会断。
##
## 本地玩家：自己算状态。其他玩家：只按同步过来的 state/pos 显示。

enum S { IDLE, CHARGING, FLYING, WAITING, BITE, REELING, RETURNING }

signal hint(text: String, color: Color)

var world: Node
var remote := false
var state: S = S.IDLE
var pos := Vector3.ZERO
var vel := Vector3.ZERO
var habitat := ""
var charge := 0.0
var bite_timer := 0.0
var bite_window := 0.0
var species := ""
var age := 0
var misses := 0
var force_age := -1               # 测试用：固定年份
var bait := "grass"               # 这一竿用的鱼饵
var reel_progress := 0.0
var reel_tension := 0.0
var _struggle := 0.0
var _struggle_timer := 0.0
var _flight_time := 0.0
var _return_t := 0.0
var _return_from := Vector3.ZERO
var _cooldown := 0.0
var _t := 0.0
var rng := RandomNumberGenerator.new()

var hand := Vector3.ZERO           # 每帧由玩家设置：手的位置
var orb: MeshInstance3D
var cord: MeshInstance3D
var _cord_mesh: ImmediateMesh
var bang: Label3D
var _cam: Camera3D


func _ready() -> void:
	rng.randomize()
	top_level = true
	orb = U.part(self, U.sphere(0.11, 12, 8), U.glow(Color(0.55, 0.85, 1.0), 3.5), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
	orb.top_level = true
	var inner := U.part(orb, U.sphere(0.06, 8, 6), U.glow(Color(1, 1, 1), 5.0), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
	inner.name = "Core"
	_cord_mesh = ImmediateMesh.new()
	cord = MeshInstance3D.new()
	cord.mesh = _cord_mesh
	cord.material_override = U.glow(Color(0.5, 0.82, 1.0), 2.2, true)
	cord.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cord.top_level = true
	add_child(cord)
	bang = U.label3d("!", 72, Color(1.0, 0.85, 0.2), 14)
	bang.top_level = true
	bang.no_depth_test = true
	bang.fixed_size = true
	bang.pixel_size = 0.0011
	bang.visible = false
	add_child(bang)
	_set_visible(false)


func set_camera(c: Camera3D) -> void:
	_cam = c


func _set_visible(v: bool) -> void:
	orb.visible = v
	cord.visible = v


func busy() -> bool:
	return state != S.IDLE


# ------------------------------------------------------------------ 本地输入

func update_local(dt: float, pressed: bool, just_pressed: bool, just_released: bool, aim_dir: Vector3) -> void:
	_t += dt
	_cooldown -= dt
	match state:
		S.IDLE:
			if just_pressed and _cooldown <= 0.0:
				state = S.CHARGING
				charge = 0.0
		S.CHARGING:
			charge += dt
			if just_released or not pressed:
				_throw(aim_dir)
		S.FLYING:
			if just_pressed:
				_start_return()
			else:
				_fly(dt)
		S.WAITING:
			if just_pressed:
				_start_return()
			elif habitat != "":
				bite_timer -= dt
				if bite_timer <= 0.0:
					_bite()
		S.BITE:
			bite_window -= dt
			if just_pressed:
				if age >= 2:
					state = S.REELING
					reel_progress = 0.0
					reel_tension = 0.25
					_struggle_timer = 0.5
					hint.emit("千年魂兽！按住 E 拉，拉力变红就松一下", Color(0.75, 0.5, 1.0))
					Sfx.play("yank", -4.0, 0.05, 0.8)
				else:
					_yank()
			elif bite_window <= 0.0:
				misses += 1
				hint.emit("跑了！再等等下一只", Color(1, 0.7, 0.5))
				_schedule_bite()
				state = S.WAITING
		S.REELING:
			_reel(dt, pressed)
		S.RETURNING:
			_return_t += dt / 0.22
			pos = _return_from.lerp(hand, clampf(_return_t, 0.0, 1.0))
			if _return_t >= 1.0:
				state = S.IDLE
				_set_visible(false)
	_update_visuals(dt)


func _throw(aim_dir: Vector3) -> void:
	var L: Dictionary = Data.LURE
	var k := clampf(charge / L["charge_time"], 0.0, 1.0)
	var speed := lerpf(L["min_speed"], L["max_speed"], k)
	vel = aim_dir * speed + Vector3.UP * speed * L["up"]
	pos = hand
	state = S.FLYING
	_flight_time = 0.0
	habitat = ""
	_set_visible(true)
	Sfx.play("lure_throw", -2.0, 0.08)


func _fly(dt: float) -> void:
	_flight_time += dt
	var g: float = Data.LURE["gravity"]
	var steps := 3
	var h := dt / steps
	for i in steps:
		var next := pos + vel * h
		vel.y -= g * h
		# 落水
		if next.y <= Island.WATER_Y and not world.island.is_land(next.x, next.z):
			var t := (pos.y - Island.WATER_Y) / maxf(pos.y - next.y, 0.0001)
			_land(pos.lerp(next, clampf(t, 0.0, 1.0)), true)
			return
		var hit: Dictionary = world.raycast(pos, next, U.LAYER_WORLD)
		if not hit.is_empty():
			_land(hit["position"], false)
			return
		pos = next
	if _flight_time > 4.0:
		_start_return()


func _land(p: Vector3, water: bool) -> void:
	pos = p + Vector3(0, 0.08, 0)
	vel = Vector3.ZERO
	state = S.WAITING
	habitat = world.island.habitat_at(Vector3(p.x, Island.WATER_Y if water else p.y, p.z))
	if water:
		if not world.island.is_water_habitat(habitat):
			habitat = world.island.water_type_at(p.x, p.z)
		world.fx.splash(p)
		Sfx.play_at("splash_small", p, -2.0)
	else:
		world.fx.dirt_puff(p)
		Sfx.play_at("thud", p, -6.0)
	if habitat == "":
		hint.emit("这里没有魂兽。看路牌，抛到水里或魂兽的窝附近（按 E 收回）", Color(0.9, 0.9, 0.9))
	else:
		_schedule_bite()


func _schedule_bite() -> void:
	var L: Dictionary = Data.LURE
	bite_timer = rng.randf_range(L["bite_min"], L["bite_max"])
	if misses >= L["hurry_after"]:
		bite_timer = 0.4
	species = Data.HABITATS[habitat]["beast"]
	bait = "grass"
	if force_age >= 0:
		age = force_age
		bait = "test"
	elif Profile.item_count("gold_bites") > 0:
		# 引兽香：必定百年以上
		age = Data.roll_age(rng, 1, world.chapter)
		Profile.items["gold_bites"] = Profile.item_count("gold_bites") - 1
		Profile.mark_dirty()
	else:
		# 鱼饵决定钓上来什么：青草饵基本只有十年，魂晶饵千年多……
		bait = world.player.current_bait() if not remote else "grass"
		age = Data.roll_age_bait(rng, world.chapter, bait)


func _bite() -> void:
	state = S.BITE
	# 咬钩才扣鱼饵
	var item := str(Data.BAITS.get(bait, Data.BAITS["grass"])["item"])
	if item != "" and not remote:
		Profile.use_item(item)
		if Profile.item_count(item) <= 0:
			hint.emit("%s用完了，换回青草饵（B 切换，暗器铺有卖）" % Data.BAITS[bait]["name"], Color(1, 0.8, 0.5))
	bite_window = Data.LURE["bite_window"] * (1.2 if age >= 2 else 1.0)
	Sfx.play("bite", 0.0, 0.03, 1.0 if age == 0 else (0.85 if age == 1 else 0.7))
	if _in_water():
		world.fx.splash(pos)
	var c := Data.age_color(age)
	bang.modulate = c if age > 0 else Color(1.0, 0.85, 0.2)
	bang.text = "！" if age == 0 else ("百年！" if age == 1 else "千年！！")


func _reel(dt: float, pressed: bool) -> void:
	var L: Dictionary = Data.LURE
	_struggle_timer -= dt
	if _struggle_timer <= 0.0:
		_struggle = 1.0
		_struggle_timer = rng.randf_range(0.55, 0.95)
		Sfx.play("struggle", -6.0, 0.1)
	_struggle = move_toward(_struggle, 0.0, dt / 0.35)
	if pressed:
		reel_progress += dt / L["reel_time"]
		reel_tension += dt * (0.35 + _struggle * 1.9)
	else:
		reel_progress -= dt * 0.12
		reel_tension -= dt * 1.4
	reel_progress = clampf(reel_progress, 0.0, 1.0)
	reel_tension = clampf(reel_tension, 0.0, 1.0)
	if reel_tension >= 1.0:
		misses += 1
		hint.emit("索断了！拉力变红的时候要松开 E", Color(1, 0.5, 0.4))
		Sfx.play("snap", 0.0)
		_start_return()
		return
	if reel_progress >= 1.0:
		_yank()


func _yank() -> void:
	misses = 0
	world.request_yank(pos, habitat, species, age, bait)
	Sfx.play("yank", 0.0, 0.05)
	_cooldown = 0.2
	_start_return()


func _start_return() -> void:
	state = S.RETURNING
	_return_t = 0.0
	_return_from = pos


# ------------------------------------------------------------------ 远程玩家的引魂索（只显示）

func apply_remote(p_state: int, p_pos: Vector3, dt: float) -> void:
	_t += dt
	state = p_state as S
	if state == S.IDLE or state == S.CHARGING:
		_set_visible(false)
	else:
		_set_visible(true)
		pos = pos.lerp(p_pos, 1.0 - exp(-20.0 * dt)) if pos.distance_to(p_pos) < 8.0 else p_pos
	_update_visuals(dt)


# ------------------------------------------------------------------ 画面

func _update_visuals(dt: float) -> void:
	if state == S.IDLE or state == S.CHARGING:
		bang.visible = false
		_cord_mesh.clear_surfaces()
		return
	var p := pos
	if state == S.WAITING and _in_water():
		p.y = Island.WATER_Y + 0.08 + sin(_t * 3.0) * 0.04
	if state == S.BITE:
		p += Vector3(sin(_t * 47.0), sin(_t * 31.0), cos(_t * 41.0)) * 0.06
		if _in_water():
			p.y = Island.WATER_Y - 0.05 + sin(_t * 20.0) * 0.08
	if state == S.REELING:
		p += Vector3(sin(_t * 55.0), 0, cos(_t * 49.0)) * (0.05 + _struggle * 0.12)
	orb.global_position = p
	var pulse := 1.0 + sin(_t * 8.0) * 0.1
	orb.scale = Vector3.ONE * pulse * (1.4 if state == S.BITE else 1.0)
	bang.visible = state == S.BITE or state == S.REELING
	bang.global_position = p + Vector3(0, 1.3 + sin(_t * 12.0) * 0.08, 0)
	if state == S.REELING:
		bang.modulate = Color(1.0, 0.3, 0.25).lerp(Color(0.7, 0.4, 1.0), 1.0 - reel_tension)
	_draw_cord(hand, p)


## 从手到索头画一条发光的带子，松的时候往下垂，拉紧时绷直
func _draw_cord(a: Vector3, b: Vector3) -> void:
	_cord_mesh.clear_surfaces()
	var d := a.distance_to(b)
	if d < 0.05:
		return
	var sag := 0.0
	match state:
		S.FLYING:
			sag = d * 0.04
		S.WAITING:
			sag = d * 0.12
		S.RETURNING:
			sag = d * 0.02
	var cam_pos := _cam.global_position if _cam else a + Vector3(0, 1, 0)
	var segs := 24
	var width := 0.018 if state != S.REELING else 0.026
	_cord_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in segs + 1:
		var t := float(i) / segs
		var p := a.lerp(b, t)
		p.y -= sag * 4.0 * t * (1.0 - t)
		if state == S.BITE or state == S.REELING:
			p += Vector3(0, sin(t * PI * 6.0 + _t * 60.0) * 0.02 * sin(t * PI), 0)
		var tangent := (b - a).normalized()
		var to_cam := (cam_pos - p).normalized()
		var side := tangent.cross(to_cam).normalized() * width * (1.0 + t * 0.5)
		_cord_mesh.surface_add_vertex(p - side)
		_cord_mesh.surface_add_vertex(p + side)
	_cord_mesh.surface_end()


func _in_water() -> bool:
	return world != null and world.island.is_water_habitat(habitat)
