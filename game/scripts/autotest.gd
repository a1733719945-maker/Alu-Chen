class_name AutoTest
extends Node
## 自动测试 / 截图。命令行：
##   godot --headless --path game -- --autotest=solo
##   godot --headless --path game -- --autotest=host --server=ws://127.0.0.1:18931 --room=TEST
##   godot --headless --path game -- --autotest=client --server=ws://127.0.0.1:18931 --room=TEST
##   godot --path game -- --autotest=shots --out=/tmp/shots
## 成功时退出码 0，失败 1。

var main: Node
var mode := "solo"
var args := {}
var _t := 0.0
var _step := 0
var _step_t := 0.0
var _log: Array[String] = []
var _queue: Array = []          # 要测的栖息地
var _target: Beast
var _kills_before := 0
var _wallet_before := 0
var _shots_dir := ""
var _shot_i := 0
var _done := false
var _lure_held := false
var _busy := false             # 截图等待中，别重入
var _press_lure_next := false


func _ready() -> void:
	print("[autotest] mode=", mode)
	match mode:
		"solo", "shots":
			if mode == "shots":
				_shots_dir = str(args.get("out", "user://shots"))
				DirAccess.make_dir_recursive_absolute(_shots_dir)
				main._show_menu()
				_step = -10
			else:
				main.start_solo()
			_queue = ["burrow", "meadow", "flowers", "water", "reel"]
		"host":
			Settings.server_url = str(args.get("server", "ws://127.0.0.1:18931"))
			main.start_host(str(args.get("room", "TEST")))
		"client":
			Settings.server_url = str(args.get("server", "ws://127.0.0.1:18931"))
			Settings.player_name = "客人"
			main.start_join(str(args.get("room", "TEST")))
			_queue = ["burrow", "meadow"]


func _fail(msg: String) -> void:
	if _done:
		return
	_done = true
	printerr("[autotest] FAIL: ", msg)
	for l in _log:
		printerr("   ", l)
	get_tree().quit(1)


func _pass(msg: String) -> void:
	if _done:
		return
	_done = true
	print("[autotest] PASS: ", msg)
	for l in _log:
		print("   ", l)
	get_tree().quit(0)


func _note(s: String) -> void:
	_log.append("%.1fs %s" % [_t, s])
	print("[autotest] ", s)


func _world() -> World:
	return main.world


func _aim(p: Player, target: Vector3) -> void:
	var d := target - p.cam.global_position
	p.yaw = atan2(-d.x, -d.z)
	p.pitch = atan2(d.y, Vector2(d.x, d.z).length())
	p.kick_pitch = 0.0
	p.kick_yaw = 0.0


func _shot(name: String) -> void:
	if _shots_dir == "" or DisplayServer.get_name() == "headless":
		return
	_busy = true
	await RenderingServer.frame_post_draw
	_busy = false
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%02d_%s.png" % [_shots_dir, _shot_i, name]
	_shot_i += 1
	img.save_png(path)
	print("[autotest] screenshot ", path)


func _next(step: int) -> void:
	_step = step
	_step_t = 0.0


func _process(dt: float) -> void:
	if _done:
		return
	_t += dt
	if _busy:
		return
	_step_t += dt
	if _press_lure_next:
		_press_lure_next = false
		Input.action_press("lure")
		_lure_held = true
	var limit := 120.0 if mode != "shots" else 200.0
	if _t > limit:
		_fail("超时（step %d）" % _step)
		return
	match mode:
		"solo":
			_run_hunt(dt, false)
		"shots":
			_run_shots(dt)
		"host":
			_run_host()
		"client":
			_run_hunt(dt, true)


# ------------------------------------------------------------------ 抓魂兽流程（单人和客人共用）

func _habitat_spot(w: World, h: String) -> Dictionary:
	# 返回 {stand: 玩家站的位置, target: 引魂索落点}
	var isl := w.island
	match h:
		"water":
			return {"stand": isl.dock_end + Vector3(0, 0.2, -2), "target": isl.dock_end + Vector3(4, 0, 10)}
		"burrow":
			var b: Vector3 = isl.habitat("burrow")["points"][0]
			var dir := Vector3(1, 0, 0.3).normalized()
			var st := b + dir * 12.0
			st.y = isl.height_at(st.x, st.z)
			return {"stand": st, "target": b}
		"meadow", "reel":
			var c: Vector2 = isl.habitat("meadow")["center"]
			var tp := Vector3(c.x, isl.height_at(c.x, c.y), c.y)
			var st := tp + Vector3(0, 0, 12)
			st.y = isl.height_at(st.x, st.z)
			return {"stand": st, "target": tp}
		"flowers":
			var c: Vector2 = isl.habitat("flowers")["center"]
			var tp := Vector3(c.x, isl.height_at(c.x, c.y), c.y)
			var st := tp + Vector3(12, 0, 0)
			st.y = isl.height_at(st.x, st.z)
			return {"stand": st, "target": tp}
	return {}


func _run_hunt(dt: float, online: bool) -> void:
	var w := _world()
	if not w or not is_instance_valid(w) or not w.is_node_ready():
		return
	var p := w.player
	match _step:
		0:
			if _step_t < 1.0:
				return
			if online and w.remotes.is_empty():
				if _step_t > 20.0:
					_fail("没看到房主")
				return
			if _queue.is_empty():
				_pass("全部栖息地测完，金魂币 %d" % w.wallet)
				return
			var h: String = _queue[0]
			var spot := _habitat_spot(w, h)
			p.teleport(spot["stand"] + Vector3(0, 0.5, 0))
			_note("测试 %s，站在 %s" % [h, spot["stand"]])
			p.lure.force_age = 2 if h == "reel" else 0
			_next(1)
		1:
			# 用 _land 直接让索头落在栖息地（抛物线投掷另外测）
			if _step_t < 0.4:
				return
			var h: String = _queue[0]
			var spot := _habitat_spot(w, h)
			_aim(p, spot["target"])
			p.lure.state = Lure.S.FLYING
			p.lure._set_visible(true)
			p.lure._land(spot["target"], h == "water")
			if p.lure.habitat == "":
				_fail("索头落在 %s 没识别出栖息地" % spot["target"])
				return
			_note("索头落在 %s（%s），等咬钩" % [p.lure.habitat, p.lure.species])
			_next(2)
		2:
			if p.lure.state == Lure.S.BITE:
				_note("咬钩了：%s %s" % [Data.age_name(p.lure.age), p.lure.species])
				_kills_before = int(w._stat(Net.my_id)["kills"])
				Input.action_press("lure")
				_lure_held = true
				_next(3)
			elif _step_t > 5.0:
				_fail("5 秒内没咬钩")
		3:
			if p.lure.state == Lure.S.REELING:
				# 千年：拉力高了就松
				if p.lure.reel_tension > 0.7 and _lure_held:
					Input.action_release("lure")
					_lure_held = false
				elif p.lure.reel_tension < 0.3 and not _lure_held:
					Input.action_press("lure")
					_lure_held = true
				return
			if _lure_held and _step_t > 0.05:
				Input.action_release("lure")
				_lure_held = false
			if p.lure.state == Lure.S.RETURNING or p.lure.state == Lure.S.IDLE:
				if _lure_held:
					Input.action_release("lure")
					_lure_held = false
				_next(4)
			elif _step_t > 8.0:
				_fail("拽不上来，state=%d" % p.lure.state)
		4:
			# 等魂兽出现
			for b: Beast in w.beasts.values():
				if b.alive() and b.owner_peer == Net.my_id:
					_target = b
					_note("魂兽出现了：%s，位置 %s" % [b.name, b.global_position])
					_next(5)
					return
			if _step_t > 3.0:
				_fail("拽了之后没出现魂兽")
		5:
			# 空中开火，打到死
			if not is_instance_valid(_target) or not _target.alive():
				_next(6)
				return
			if _step_t < 0.35:
				return
			var aim_pt := _target.global_position
			_aim(p, aim_pt)
			if p.ammo[p.weapon] <= 0 and not p.reloading:
				p.start_reload()
			Input.action_press("fire")
			get_tree().create_timer(0.02).timeout.connect(func(): Input.action_release("fire"))
			if _step_t > 12.0:
				_fail("12 秒没打死")
		6:
			var st: Dictionary = w._stat(Net.my_id)
			if int(st["kills"]) > _kills_before:
				_note("击杀成功，金魂币 %d，击杀数 %d" % [w.wallet, st["kills"]])
				if w.wallet <= 0:
					_fail("击杀了但金魂币没增加")
					return
				_queue.pop_front()
				_next(0)
			elif _step_t > 3.0:
				# 可能逃走了：重来一次
				_note("魂兽跑了，重试")
				_next(0)


# ------------------------------------------------------------------ 房主：等客人来抓

func _run_host() -> void:
	var w := _world()
	if not w or not is_instance_valid(w):
		return
	match _step:
		0:
			if not w.remotes.is_empty():
				_note("客人进来了：%s" % w.remotes.keys())
				_next(1)
			elif _t > 40.0:
				_fail("没有客人加入")
		1:
			for id in w.stats:
				if id != Net.my_id and int(w.stats[id]["kills"]) >= 2:
					_note("客人击杀 %d 只，全队金魂币 %d" % [w.stats[id]["kills"], w.wallet])
					_next(2)
					return
		2:
			if w.remotes.is_empty() or _step_t > 3.0:
				_pass("房主测试通过")


# ------------------------------------------------------------------ 截图

func _run_shots(dt: float) -> void:
	match _step:
		-10:
			if _step_t > 1.5:
				await _shot("menu")
				main.start_solo()
				_next(-9)
		-9:
			var w := _world()
			if w and _step_t > 3.0:
				await _shot("spawn")
				var isl := w.island
				var p := w.player
				var c: Vector2 = isl.habitat("meadow")["center"]
				var st := Vector3(c.x + 20, 0, c.y + 25)
				st.y = isl.height_at(st.x, st.z)
				p.teleport(st + Vector3(0, 0.5, 0))
				_aim(p, Vector3(c.x, isl.height_at(c.x, c.y) + 4, c.y))
				_next(-8)
		-8:
			if _step_t > 1.5:
				await _shot("meadow")
				var w := _world()
				var p := w.player
				var hill := w.island.hill
				p.teleport(Vector3(hill.x, w.island.height_at(hill.x, hill.y) + 0.5, hill.y))
				_aim(p, Vector3(0, 0, 40))
				_next(-7)
		-7:
			if _step_t > 1.5:
				await _shot("hill_view")
				_next(0)
		_:
			_run_hunt_shots(dt)


func _run_hunt_shots(dt: float) -> void:
	var w := _world()
	var p := w.player
	if _queue.is_empty():
		_pass("截图完成")
		return
	var h: String = _queue[0]
	match _step:
		0:
			var spot := _habitat_spot(w, h)
			p.teleport(spot["stand"] + Vector3(0, 0.5, 0))
			p.lure.force_age = [0, 1, 2, 0, 2][_shot_i % 5] if h != "reel" else 2
			_aim(p, spot["target"] + Vector3(0, 2, 0))
			_next(1)
		1:
			if _step_t < 0.5:
				return
			var spot := _habitat_spot(w, h)
			p.lure.state = Lure.S.FLYING
			p.lure._set_visible(true)
			p.lure._land(spot["target"], h == "water")
			_aim(p, spot["target"] + Vector3(0, 1.0, 0))
			_next(2)
		2:
			if p.lure.state == Lure.S.BITE:
				_press_lure_next = true
				_next(3)
				_shot(h + "_bite")
		3:
			if p.lure.state == Lure.S.REELING:
				if _step_t > 0.6 and not p.has_meta("reel_shot"):
					p.set_meta("reel_shot", true)
					_shot("reel")
				if p.lure.reel_tension > 0.7 and _lure_held:
					Input.action_release("lure")
					_lure_held = false
				elif p.lure.reel_tension < 0.3 and not _lure_held:
					Input.action_press("lure")
					_lure_held = true
				return
			if _lure_held:
				Input.action_release("lure")
				_lure_held = false
			for b: Beast in w.beasts.values():
				if b.alive():
					_target = b
					_next(4)
					return
		4:
			if not is_instance_valid(_target) or not _target.alive():
				_next(6)
				return
			_aim(p, _target.global_position)
			if _step_t > 0.9:
				_next(5)
				_shot(h + "_air")
		5:
			if not is_instance_valid(_target) or not _target.alive():
				_next(6)
				return
			_aim(p, _target.global_position)
			if p.fire_cd <= 0.0:
				if p.ammo[p.weapon] <= 0:
					p.start_reload()
				Input.action_press("fire")
				get_tree().create_timer(0.02).timeout.connect(func(): Input.action_release("fire"))
				if not p.has_meta("fire_shot_" + h):
					p.set_meta("fire_shot_" + h, true)
					get_tree().create_timer(0.03).timeout.connect(func(): _shot(h + "_fire"))
			if _step_t > 8.0:
				_next(6)
		6:
			if _step_t > 0.25 and not p.has_meta("kill_shot_" + h):
				p.set_meta("kill_shot_" + h, true)
				_shot(h + "_kill")
			if _step_t > 0.8:
				_queue.pop_front()
				if not _queue.is_empty() and _queue[0] == "meadow":
					p.switch_weapon(1)
				_next(0)
