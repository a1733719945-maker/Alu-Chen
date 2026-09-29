class_name AutoTest
extends Node
## 自动测试 / 截图。命令行：
##   godot --headless --path game -- --autotest=solo
##   godot --headless --path game -- --autotest=host --server=ws://127.0.0.1:18931 --room=TEST
##   godot --headless --path game -- --autotest=client --server=ws://127.0.0.1:18931 --room=TEST
##   godot --path game -- --autotest=shots --out=/tmp/shots
## 成功时退出码 0，失败 1。
##
## 单人测试把整个流程走一遍：
##   第一章四种栖息地 + 千年拉扯 → 暗器铺买暗器、升级 → 全自动压枪（后坐和回正）→ 狙击开镜、拉栓
##   → 到 10 级瓶颈、吸收灵环、选神通、放神通 → 祭坛召唤镜湖之主、用暗器打它、打死、拿灵骨
##   → 坐船去第二章 → 落霞林里抓狼、蛇、犀牛
## 测试用单独的存档文件，不会动玩家自己的存档。

var main: Node
var mode := "solo"
var args := {}
var _t := 0.0
var _phase := ""
var _step := 0
var _step_t := 0.0
var _log: Array[String] = []
var _plan: Array = []
var _queue: Array = []          # 要测的栖息地
var _target: Beast
var _kills_before := 0
var _money_before := 0
var _shots_dir := ""
var _shot_i := 0
var _shots := false
var _done := false
var _lure_held := false
var _busy := false              # 截图等待中，别重入
var _press_lure_next := false
var _old_world: World
var _tour: Array = []
var _mem := {}


func _ready() -> void:
	print("[autotest] mode=", mode)
	Profile.path = "user://profile_test_%s.json" % mode
	Profile.reset()
	# --from_save=profile.json：拿玩家真存档的一份拷贝来测（原存档只读，不会被改）
	if args.has("from_save"):
		var src := "user://" + str(args["from_save"])
		if FileAccess.file_exists(src):
			var f := FileAccess.open(Profile.path, FileAccess.WRITE)
			f.store_string(FileAccess.get_file_as_string(src))
			f.close()
			Profile._defaults()
			Profile.load_profile()
	match mode:
		"solo":
			main.start_solo()
			_plan = ["phys", "hunt:burrow,meadow,flowers,water,reel", "shop", "recoil", "sniper", "ring", "boss", "boat", "hunt:den,swamp,mud", "boss", "boat",
				"hunt:glade,roost,thicket,nest,bog", "boss", "boat",
				"hunt:snowden,frostgrove,icefield,icecave,icelake", "boss", "boat",
				"hunt:beach,cliff,reef,deep,abyss", "boss", "dungeon", "chase", "musou", "huntrun", "huntfail", "touch", "feel", "done"]
			# 新暗器测试放在第一章买完暗器后面（要第一章的草地摆靶子；第五章归墟没有草地）
			_plan.insert(_plan.find("shop") + 1, "guns2")
			_plan.insert(_plan.find("guns2") + 1, "pills")
			_plan.insert(_plan.find("pills") + 1, "stars")
			_plan.insert(_plan.find("stars") + 1, "decor")
			_plan.insert(_plan.find("decor") + 1, "selfpreview")
		"shots":
			_shots = true
			_shots_dir = str(args.get("out", "user://shots"))
			DirAccess.make_dir_recursive_absolute(_shots_dir)
			main._show_menu()
			_plan = ["menu", "tour1", "hunt:burrow", "shop", "recoil", "sniper", "ring", "boss", "boat", "tour2", "hunt:den", "done"]
		"measure":
			_shots = true
			_shots_dir = str(args.get("out", "user://shots"))
			DirAccess.make_dir_recursive_absolute(_shots_dir)
			_setup_measure()
			_plan = ["measure"]
		"zoo":
			_shots = true
			_shots_dir = str(args.get("out", "user://shots"))
			DirAccess.make_dir_recursive_absolute(_shots_dir)
			_setup_zoo()
			_plan = ["zoo"]
		"vm":
			_shots = true
			_shots_dir = str(args.get("out", "user://shots"))
			DirAccess.make_dir_recursive_absolute(_shots_dir)
			_setup_vm()
			_plan = ["vm"]
		"host":
			Settings.server_url = str(args.get("server", "ws://127.0.0.1:18931"))
			# --dg=1：测猎灵榜和秘境的联机（配 --autotest=client --dg=1）

			main.start_host(str(args.get("room", "TEST")))
			_plan = ["dghost"] if args.has("dg") else ["host"]
		"client":
			Settings.server_url = str(args.get("server", "ws://127.0.0.1:18931"))
			Settings.player_name = "客人"
			main.start_join(str(args.get("room", "TEST")))
			_plan = ["dgclient", "done"] if args.has("dg") else ["hunt:burrow,meadow", "done"]
	# 只跑其中几段：--chapter=2 --plan=tour2,hunt:den+mud,boss,done
	if args.has("plan") and mode in ["solo", "shots"]:
		if args.has("chapter"):
			Profile.chapter = int(args["chapter"])
			Profile.save_profile()
		_plan.clear()
		for e in str(args["plan"]).split(","):
			_plan.append(e.replace("+", ","))
		if _plan[0] != "menu":
			if main.world:
				main.world.queue_free()
				main.world = null
			if main.menu:
				main.menu.queue_free()
				main.menu = null
			main.start_solo()
	_next_phase()


func _next_phase() -> void:
	if _plan.is_empty():
		return
	var p: String = _plan.pop_front()
	if p.begins_with("hunt:"):
		_phase = "hunt"
		_queue = Array(p.substr(5).split(","))
		for k in ["bite_shot", "air_shot", "fire_shot", "kill_shot"]:
			_mem.erase(k)
	else:
		_phase = p
	_step = 0
	_step_t = 0.0
	_note("—— %s" % p)


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


func _check(ok: bool, msg: String) -> bool:
	if not ok:
		_fail(msg)
	return ok


func _world() -> World:
	return main.world


func _aim(p: Player, target: Vector3) -> void:
	var d := target - p.cam.global_position
	p.yaw = atan2(-d.x, -d.z)
	p.pitch = atan2(d.y, Vector2(d.x, d.z).length())
	# 测试直接瞄准，把后坐清零（后坐单独测）
	p.gun.recoil = Vector2.ZERO


func _shot(name: String) -> void:
	if not _shots or DisplayServer.get_name() == "headless":
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
	var limit := 900.0 if mode != "shots" else 1500.0
	if _t > limit:
		_fail("超时（%s step %d）" % [_phase, _step])
		return
	match _phase:
		"menu":
			if _step_t > 1.5:
				await _shot("menu")
				main.start_solo()
				_next_phase()
		"hunt":
			_run_hunt()
		"phys":
			_run_phys()
		"touch":
			_run_touch()
		"view":
			if _step == 0 and _step_t > 4.0 and _ready_world():
				_next(1)
				await _shot("view")
				_next_phase()
		"hudshot":
			_run_hudshot()
		"shop":
			_run_shop()
		"recoil":
			_run_recoil()
		"sniper":
			_run_sniper()
		"ring":
			_run_ring()
		"boss":
			_run_boss()
		"boat":
			_run_boat()
		"events":
			_run_events()
		"bossshot":
			_run_bossshot()
		"skills2":
			_run_skills2()
		"down":
			_run_down()
		"nests":
			_run_nests()
		"kings":
			_run_kings()
		"uishots":
			_run_uishots()
		"fxshots":
			_run_fxshots()
		"critters":
			_run_critters()
		"combo":
			_run_combo()
		"aggro":
			_run_aggro()
		"huntrun":
			_run_huntrun()
		"huntfail":
			_run_huntfail()
		"migrate":
			_run_migrate()
		"bot":
			_run_bot()
		"guns2":
			_run_guns2()
		"pills":
			_run_pills()
		"bossarts":
			_run_bossarts()
		"mateshot":
			_run_mateshot()
		"cineshot":
			_run_cineshot()
		"gunshots":
			_run_gunshots()
		"dgwatch":
			_run_dgwatch()
		"dungeon":
			_run_dungeon()
		"stars":
			_run_stars()
		"bosscine":
			_run_bosscine()
		"selfpreview":
			_run_selfpreview()
		"decor":
			_run_decor()
		"decorshot":
			_run_decorshot()
		"chase":
			_run_chase()
		"chaseshot":
			_run_chaseshot()
		"kbshot":
			_run_kbshot()
		"feel":
			_run_feel()
		"fpshot":
			_run_fpshot()
		"gripshot":
			_run_gripshot()
		"musou":
			_run_musou()
		"dgshot":
			_run_dgshot()
		"comboshot":
			_run_comboshot()
		"tour", "tour1", "tour2":
			_run_tour()
		"sceneshot":
			_run_sceneshot()
		"host":
			_run_host()
		"dghost":
			_run_dghost()
		"dgclient":
			_run_dgclient()
		"vm":
			_run_vm()
		"measure":
			_run_measure()
		"zoo":
			if _step_t > 1.5 and _step == 0:
				_next(1)
				await _shot("zoo")
				_pass("模型预览完成")
		"done":
			_pass("全部流程通过：等级 %d，灵环 %d，灵石 %d，章节 %d" % [Profile.level, Profile.rings.size(), Profile.money, Profile.chapter])


func _ready_world() -> World:
	var w := _world()
	if not w or not is_instance_valid(w) or not w.is_node_ready() or not w.is_inside_tree():
		return null
	return w


func _switch_to(p: Player, id: String) -> void:
	for i in p.guns.size():
		if p.guns[i].id == id:
			p.switch_weapon(i)
			return


# ------------------------------------------------------------------ 界面截图：神通栏和神通轮盘

# ------------------------------------------------------------------ 手机触屏：模拟手指

func _tp(logical: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * logical


func _finger(idx: int, logical: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = idx
	ev.pressed = pressed
	ev.position = _tp(logical)
	Input.parse_input_event(ev)


func _slide(idx: int, logical: Vector2, rel: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = idx
	ev.position = _tp(logical)
	ev.relative = get_viewport().get_final_transform().basis_xform(rel)
	ev.screen_relative = ev.relative
	Input.parse_input_event(ev)


## 触屏操作：摇杆走路 + 冲刺、滑屏转视角、开火键、引魂索键（按住蓄力松开甩）、菜单 → 灵相面板 → 返回
func _run_touch() -> void:
	var w := _ready_world()
	if not w:
		return
	var p := w.player
	var tc: TouchControls = w.touch
	var sz: Vector2 = tc._canvas.size
	match _step:
		0:
			if _step_t < 2.0:
				return
			Settings._force_touch = true
			Settings.apply()
			p.select_slot(1)
			# 给三个神通，看神通键
			if Profile.rings.is_empty():
				var tree: Array = Data.SKILL_TREE[Data.wuhun_id(Settings.wuhun)]
				for i in 3:
					Profile.add_ring(mini(i, 2), str(tree[i][0]), "wolf")
				w.skills.cooldowns[1] = 5.0
			_next(1)
		1:
			if _step_t < 1.0:
				return
			if not _check(tc._canvas.visible, "触屏：按钮没显示出来"):
				return
			await _shot("touch_hud")
			_mem["t_pos"] = p.global_position
			_finger(0, Vector2(200, sz.y - 170), true)
			_next(2)
		2:
			if _step_t < 0.1:
				return
			# 往前推出圈外：走 + 冲刺
			_slide(0, Vector2(200, sz.y - 300), Vector2(0, -130))
			_next(3)
		3:
			if _step_t < 1.2:
				return
			var moved: float = (p.global_position - (_mem["t_pos"] as Vector3)).length()
			_note("触屏：摇杆推 1.2 秒走了 %.1f 米，冲刺 %s" % [moved, tc._sprinting])
			if not _check(moved > 3.0 and tc._sprinting, "触屏：摇杆推了走不动或没冲刺"):
				return
			await _shot("touch_move")
			_finger(0, Vector2(200, sz.y - 300), false)
			_mem["t_yaw"] = p.yaw
			_finger(1, Vector2(sz.x * 0.6, sz.y * 0.3), true)
			_next(4)
		4:
			if _step_t < 0.1:
				return
			_slide(1, Vector2(sz.x * 0.6 + 150, sz.y * 0.3), Vector2(150, 0))
			_next(5)
		5:
			if _step_t < 0.2:
				return
			var dy := rad_to_deg(angle_difference(float(_mem["t_yaw"]), p.yaw))
			_note("触屏：往右滑 150 像素，视角转了 %.1f°" % dy)
			if not _check(dy < -8.0 and dy > -30.0, "触屏：滑屏转视角不对（%.1f°）" % dy):
				return
			_finger(1, Vector2(sz.x * 0.6 + 150, sz.y * 0.3), false)
			_mem["t_ammo"] = p.gun.ammo
			_finger(2, tc._center(tc._find("fire")), true)
			_next(6)
		6:
			if _step_t < 0.2 and not _mem.has("t_dbg"):
				_mem["t_dbg"] = true
				var fb := tc._find("fire")
				_note("调试：开火键中心 %s 按下=%s 动作=%s slot=%d gun=%s switch=%.2f cd=%.2f 忙=%.2f 冲刺=%s 手指=%s" % [tc._center(fb), fb["down"], Input.is_action_pressed("fire"), p.slot, p.gun.id, p.switch_t, p.gun.fire_cd, p.busy_t, Input.is_action_pressed("sprint"), tc._fingers])
			if _step_t < 0.5:
				return
			_finger(2, tc._center(tc._find("fire")), false)
			_note("触屏：按开火键，弹药 %d → %d" % [_mem["t_ammo"], p.gun.ammo])
			if not _check(p.gun.ammo < int(_mem["t_ammo"]), "触屏：按开火键没开枪"):
				return
			_finger(3, tc._center(tc._find("lure")), true)
			_next(7)
		7:
			if _step_t < 0.6:
				return
			if not _check(p.lure.state == Lure.S.CHARGING, "触屏：按住引魂索键没在蓄力（%d）" % p.lure.state):
				return
			_finger(3, tc._center(tc._find("lure")), false)
			_next(8)
		8:
			if _step_t < 0.3:
				return
			_note("触屏：引魂索松手后状态 %d（不是 0 就是甩出去了）" % p.lure.state)
			if not _check(p.lure.state != Lure.S.IDLE and p.lure.state != Lure.S.CHARGING, "触屏：松开引魂索键没甩出去"):
				return
			_finger(4, tc._center(tc._find("menu")), true)
			_next(9)
		9:
			if _step_t < 0.15:
				return
			_finger(4, tc._center(tc._find("menu")), false)
			if not _check(tc._menu_open, "触屏：菜单没展开"):
				return
			_finger(4, tc._center(tc._find("wuhun")), true)
			_next(10)
		10:
			if _step_t < 0.15:
				return
			_finger(4, tc._center(tc._find("wuhun")), false)
			_next(11)
		11:
			if _step_t < 0.6:
				return
			if not _check(w.ui_open and tc._close.visible, "触屏：点菜单里的灵相没打开面板 / 没有返回键"):
				return
			await _shot("touch_panel")
			tc._close.pressed.emit()
			_next(12)
		12:
			if _step_t < 0.5:
				return
			if not _check(not w.ui_open and tc._canvas.visible, "触屏：点返回没关掉面板"):
				return
			_note("触屏：菜单 → 灵相面板 → 返回 正常")
			Settings._force_touch = false
			Settings.apply()
			_next_phase()


func _run_hudshot() -> void:
	var w := _ready_world()
	if not w:
		return
	match _step:
		0:
			if _step_t < 2.0:
				return
			var tree: Array = Data.SKILL_TREE[Data.wuhun_id(Settings.wuhun)]
			for i in 4:
				Profile.add_ring(mini(i, 2), str(tree[i][i % 2]), "wolf")
			Profile.level = 41
			Profile.add_item("grenade", 2) if Profile.has_method("add_item") else null
			w.skills.current = 1
			w.skills.cooldowns[2] = 6.0
			_next(1)
		1:
			if _step_t < 1.0:
				return
			await _shot("hud")
			w.hud.open_wheel(1)
			w.hud.wheel_mouse(Vector2(90, 30))
			_next(2)
		2:
			if _step_t < 0.5:
				return
			_next(3)
			await _shot("wheel")
			w.hud.close_wheel()
			_next_phase()


# ------------------------------------------------------------------ 物理：抛起来、空中连击、死了摔下来

## 1) 拽出来的灵兽：飞多高、多久落地
## 2) 空中一直用全自动打（只推不扣血）：最后一定会掉下来
## 3) 在最高点打死：尸体摔到地上再消失
func _run_phys() -> void:
	var w := _ready_world()
	if not w:
		return
	var p := w.player
	match _step:
		0:
			var spot := _habitat_spot(w, "meadow")
			p.teleport(spot["stand"] + Vector3(0, 0.5, 0))
			_mem["phys_from"] = spot["target"]
			_mem["phys_case"] = 0
			_next(1)
		1:
			if _step_t < 0.3:
				return
			var from: Vector3 = _mem["phys_from"]
			_target = w._host_spawn(Net.my_id, from, "rabbit", 0, p.global_position)
			_mem["phys_y0"] = _target.global_position.y
			_mem["phys_top"] = _target.global_position.y
			_mem["phys_hits"] = 0
			_mem["phys_hit_t"] = 0.0
			_next(2)
		2:
			var case: int = _mem["phys_case"]
			var b := _target
			if not is_instance_valid(b):
				if case == 2 and _mem.has("phys_kill_t"):
					var last: Vector3 = _mem.get("phys_last", Vector3.ZERO)
					var ground := w.island.height_at(last.x, last.z)
					var fall_t := _step_t - float(_mem["phys_kill_t"])
					_note("物理：在 %.1f 米高打死，尸体摔到 %.1f 米（地面 %.1f），%.2f 秒后消失" % [_mem["phys_kill_y"], last.y, ground, fall_t])
					if _check(last.y - ground < 1.5 and fall_t > 0.5, "物理测试：尸体没掉到地上"):
						_next_phase()
					return
				_fail("物理测试：灵兽不见了（case %d）" % case)
				return
			if b.alive():
				_mem["phys_top"] = maxf(float(_mem["phys_top"]), b.global_position.y)
			if case == 1 and b.state == Beast.State.AIR and _step_t > 0.4:
				# 全自动一直打：每 0.1 秒一枪，和真枪一样的冲量
				_mem["phys_hit_t"] = float(_mem["phys_hit_t"]) + get_process_delta_time()
				while float(_mem["phys_hit_t"]) > 0.1:
					_mem["phys_hit_t"] = float(_mem["phys_hit_t"]) - 0.1
					var d := (b.global_position - p.global_position).normalized()
					b.take_hit(0.0, d * 1.35 + Vector3.UP * 1.35 * 0.65, Vector3.ZERO, false, Net.my_id, 10.0)
					_mem["phys_hits"] = int(_mem["phys_hits"]) + 1
			if case == 2 and b.alive() and b.state == Beast.State.AIR and _step_t > 0.6 and b.linear_velocity.y < 0.5:
				_mem["phys_kill_y"] = b.global_position.y
				_mem["phys_kill_t"] = _step_t
				b.last_hitter = Net.my_id
				b.take_hit(99999.0, Vector3.ZERO, Vector3.ZERO, false, Net.my_id, 10.0)
				w._host_kill(b)
				return
			if case == 2 and not b.alive():
				_mem["phys_last"] = b.global_position
				if b.linear_velocity.y > 3.5:
					_fail("物理测试：尸体往上飞了 %.1f" % b.linear_velocity.y)
				return
			if b.alive() and b.state != Beast.State.AIR:
				var top := float(_mem["phys_top"]) - float(_mem["phys_y0"])
				if case == 0:
					_note("物理：拽出来飞了 %.1f 米高，%.2f 秒落地" % [top, _step_t])
					if not _check(top > 4.0 and top < 11.0 and _step_t > 1.4 and _step_t < 4.5, "物理测试：抛物线不对"):
						return
				else:
					_note("物理：空中连打 %d 枪，%.2f 秒后还是掉到了地上（最高 %.1f 米）" % [_mem["phys_hits"], _step_t, top])
					if not _check(_step_t < 7.0, "物理测试：空中连击一直掉不下来"):
						return
				w._remove_beast(b)
				_mem["phys_case"] = case + 1
				_next(1)
				return
			if _step_t > 12.0:
				_fail("物理测试：灵兽 12 秒还没落地（case %d，状态 %d，位置 %s）" % [case, b.state, b.global_position])


# ------------------------------------------------------------------ 抓灵兽流程

func _habitat_spot(w: World, h: String) -> Dictionary:
	# 返回 {stand: 玩家站的位置, target: 引魂索落点, water: 是否落在水里}
	var isl := w.island
	if h == "reel":
		return _habitat_spot(w, "meadow")
	if h == "water":
		return {"stand": Vector3(isl.dock_end.x, isl.dock_y - 0.4, isl.dock_end.z - 2), "target": isl.dock_end + Vector3(-4, 0, 10), "water": true}
	if isl.is_water_habitat(h):
		var tp: Vector3 = isl.habitat_center(h)
		if not isl.ponds.is_empty():
			var pd: Dictionary = isl.ponds[0]
			var c: Vector2 = pd["center"]
			var st := Vector3(c.x + float(pd["radius"]) + 4.0, 0, c.y)
			st.y = isl.height_at(st.x, st.z)
			return {"stand": st, "target": Vector3(c.x, Island.WATER_Y, c.y), "water": true}
		# 从水面往岛中心走，走到岸上再往里 2 米
		var dir := Vector3(-tp.x, 0, -tp.z).normalized()
		var st := tp
		for i in 250:
			st += dir
			if isl.is_land(st.x, st.z):
				break
		st += dir * 2.0
		st.y = isl.height_at(st.x, st.z)
		return {"stand": st, "target": Vector3(tp.x, Island.WATER_Y, tp.z), "water": true}
	var hb := isl.habitat(h)
	var c: Vector2 = hb["center"]
	if h in Island.POINT_HABITATS:
		var b: Vector3 = hb["points"][0]
		var dir := Vector3(c.x - b.x, 0, c.y - b.z).normalized()
		var st := b + dir * 12.0
		st.y = isl.height_at(st.x, st.z)
		return {"stand": st, "target": b, "water": false}
	var tp := Vector3(c.x, isl.height_at(c.x, c.y), c.y)
	var st := tp + Vector3(0, 0, 12)
	st.y = isl.height_at(st.x, st.z)
	return {"stand": st, "target": tp, "water": false}


func _run_hunt() -> void:
	var w := _ready_world()
	if not w:
		return
	var p := w.player
	if _queue.is_empty():
		_next_phase()
		return
	var h: String = _queue[0]
	match _step:
		0:
			if _step_t < 1.0:
				return
			if mode == "client" and w.remotes.is_empty():
				if _step_t > 20.0:
					_fail("没看到房主")
				return
			var spot := _habitat_spot(w, h)
			p.teleport(spot["stand"] + Vector3(0, 0.5, 0))
			p.hp = Profile.max_hp()
			_note("测试 %s，站在 %s" % [h, spot["stand"]])
			p.lure.force_age = 2 if h == "reel" else 0
			_money_before = Profile.money
			# 用全自动暗器打（有的话）
			_switch_to(p, "zhuge")
			_next(1)
		1:
			# 用 _land 直接让索头落在栖息地（抛物线投掷另外测）
			if _step_t < 0.4:
				return
			var spot := _habitat_spot(w, h)
			_aim(p, spot["target"] + Vector3(0, 1.0, 0))
			p.lure.state = Lure.S.FLYING
			p.lure._set_visible(true)
			p.lure._land(spot["target"], bool(spot["water"]))
			if p.lure.habitat == "":
				_fail("索头落在 %s 没识别出栖息地" % spot["target"])
				return
			_note("索头落在 %s（%s），等咬钩" % [p.lure.habitat, p.lure.species])
			_next(2)
		2:
			if p.lure.state == Lure.S.BITE:
				_note("咬钩了：%s %s" % [Data.age_name(p.lure.age), p.lure.species])
				_kills_before = int(w._stat(Net.my_id)["kills"])
				if _shots and not _mem.has("bite_shot"):
					_mem["bite_shot"] = true
					_press_lure_next = true
					_next(3)
					_shot(h + "_bite")
					return
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
			# 等灵兽出现
			for b: Beast in w.beasts.values():
				if b.alive() and b.owner_peer == Net.my_id:
					_target = b
					_note("灵兽出现了：%s，位置 %s" % [b.name, b.global_position])
					_next(5)
					return
			if _step_t > 3.0:
				_fail("拽了之后没出现灵兽")
		5:
			# 空中开火，打到死
			if not is_instance_valid(_target) or not _target.alive():
				_next(6)
				return
			if _step_t < 0.35:
				return
			_aim(p, _target.global_position + Vector3(0, 0.2, 0))
			p.hp = Profile.max_hp()
			if _shots and _step_t > 0.5 and not _mem.has("air_shot"):
				_mem["air_shot"] = true
				_shot(h + "_air")
				return
			if p.gun.ammo <= 0 and not p.gun.reloading:
				p.start_reload()
			Input.action_press("fire")
			get_tree().create_timer(0.02).timeout.connect(func(): Input.action_release("fire"))
			if _shots and _step_t > 0.8 and not _mem.has("fire_shot"):
				_mem["fire_shot"] = true
				get_tree().create_timer(0.03).timeout.connect(func(): _shot(h + "_fire"))
			if _step_t > 12.0:
				_fail("12 秒没打死")
		6:
			Input.action_release("fire")
			var st: Dictionary = w._stat(Net.my_id)
			if int(st["kills"]) > _kills_before:
				if _shots and not _mem.has("kill_shot"):
					_mem["kill_shot"] = true
					_shot(h + "_kill")
					return
				_note("击杀成功，灵石 %d → %d，等级 %d，击杀数 %d" % [_money_before, Profile.money, Profile.level, st["kills"]])
				if Profile.money <= _money_before:
					_fail("击杀了但灵石没增加")
					return
				_queue.pop_front()
				_next(0)
			elif _step_t > 3.0:
				# 可能逃走了：重来一次
				_note("灵兽跑了，重试")
				_next(0)


# ------------------------------------------------------------------ 暗器铺

func _run_shop() -> void:
	var w := _ready_world()
	if not w:
		return
	var p := w.player
	match _step:
		0:
			var door := w.builder.shop_door
			var away := (door - w.island.shop_pos)
			away.y = 0
			var st := door + away.normalized() * (5.0 if _shots and not _mem.has("shop_ext") else 1.5)
			st.y = w.island.height_at(st.x, st.z)
			p.teleport(st + Vector3(0, 0.3, 0))
			_aim(p, w.island.shop_pos + Vector3(0, 1.8, 0))
			_next(1)
		1:
			if _step_t < 1.0:
				return
			if _shots and not _mem.has("shop_ext"):
				_mem["shop_ext"] = true
				await _shot("shop_outside")
				_next(0)
				return
			var it := w.nearest_interactable()
			if not _check(it.get("id", "") == "shop", "站在暗器铺门口，却没有“按 F”提示：%s" % it):
				return
			w.interact()
			if not _check(w.hud._shop != null and w.hud._shop.visible, "按 F 没打开暗器铺"):
				return
			Profile.add_money(300000)
			w.hud._shop.refresh()
			_next(2)
		2:
			if _step_t < 0.6:
				return
			if _shots and not _mem.has("shop_ui"):
				_mem["shop_ui"] = true
				_shot("shop_panel")
				return
			var before := Profile.money
			for id in ["zhuge", "zhuihun", "kongque", "baoyu"]:
				if not _check(Profile.buy_weapon(id), "买不了 %s" % id):
					return
				w.on_bought_weapon(id)
			if not _check(Profile.buy_upgrade("zhuge", "dmg") and Profile.buy_upgrade("zhuge", "stab"), "升级失败"):
				return
			w.on_upgraded("zhuge")
			# 配件：狙击镜要买（默认只有机械照门），买了自动装上
			if not _check(Profile.buy_attach("zhuihun", "scope") and Profile.buy_attach("kongque", "red"), "买不了配件"):
				return
			w.on_attach_changed()
			if not _check(bool(Profile.weapon_stats("zhuihun").get("scope", false)), "装了狙击镜却没有瞄准镜"):
				return
			# 卖掉再买回来：不能显示"已拥有"，升级和配件还在
			var sold := Profile.money
			if not _check(Profile.sell_weapon("baoyu") and Profile.money > sold and not Profile.has_weapon("baoyu"), "卖不了千丝雨针"):
				return
			w.on_sold_weapon("baoyu")
			if not _check(Profile.buy_weapon("baoyu"), "卖掉的暗器买不回来"):
				return
			w.on_bought_weapon("baoyu")
			w.hud._shop._tab = "attach"
			w.hud._shop.refresh()
			_note("买了 4 把暗器和 2 个升级，花了 %d 灵石" % (before - Profile.money))
			if not _check(p.guns.size() == 6, "暗器数量不对（5 把 + 空手）：%d" % p.guns.size()):
				return
			var dmg := float(Profile.weapon_stats("zhuge")["damage"])
			if not _check(dmg > float(Data.WEAPONS["zhuge"]["damage"]), "伤害升级没生效"):
				return
			w.hud._shop._tab = "upgrades"
			w.hud._shop.refresh()
			_next(3)
		3:
			if _step_t < 0.5:
				return
			if _shots and not _mem.has("shop_up"):
				_mem["shop_up"] = true
				_shot("shop_upgrades")
				return
			w.hud.close_panels()
			if not _check(not w.ui_open, "关不掉暗器铺"):
				return
			_next_phase()


# ------------------------------------------------------------------ 压枪：全自动连射，后坐往上爬，松开后回正

func _run_recoil() -> void:
	var w := _ready_world()
	if not w:
		return
	var p := w.player
	match _step:
		0:
			_switch_to(p, "zhuge")
			var m := w.island.habitat("meadow")
			var c: Vector2 = m["center"]
			p.teleport(Vector3(c.x, w.island.height_at(c.x, c.y) + 0.5, c.y + 8.0))
			p.look_to(0.0, deg_to_rad(4))
			_next(1)
		1:
			if _step_t < 1.2:
				return
			if not _check(p.gun.id == "zhuge", "切不到连机神弩"):
				return
			_mem["ammo0"] = p.gun.ammo
			_mem["pitch0"] = p.pitch
			Input.action_press("fire")
			_next(2)
		2:
			if _shots and _step_t > 0.35 and not _mem.has("spray_shot"):
				_mem["spray_shot"] = true
				_shot("spray")
				return
			if _step_t < 0.6:
				return
			var rec: Vector2 = p.gun.recoil
			var fired: int = int(_mem["ammo0"]) - p.gun.ammo
			Input.action_release("fire")
			_note("连射 %d 发，后坐 上 %.2f° 左右 %.2f°，扩散 %.2f°" % [fired, rec.y, rec.x, p.current_spread()])
			if not _check(fired >= 6, "0.6 秒只打出 %d 发" % fired):
				return
			if not _check(rec.y > 1.0, "连射后准星没有上跳（后坐 %.2f°）" % rec.y):
				return
			_mem["rec"] = rec
			_next(3)
		3:
			if _step_t < 1.0:
				return
			var rec: Vector2 = p.gun.recoil
			_note("停火 1 秒后后坐回到 %.2f°" % rec.length())
			if not _check(rec.length() < 0.35, "停火后准星没有回正（%.2f°）" % rec.length()):
				return
			_next_phase()


func _run_sniper() -> void:
	var w := _ready_world()
	if not w:
		return
	var p := w.player
	match _step:
		0:
			_switch_to(p, "zhuihun")
			_next(1)
		1:
			if _step_t < 1.0:
				return
			Input.action_press("aim")
			_next(2)
		2:
			if _step_t < 0.7:
				return
			if not _check(p.scoped, "狙击开镜后没有进入瞄准镜"):
				return
			if _shots and not _mem.has("scope"):
				_mem["scope"] = true
				_shot("scope")
				return
			var a := p.gun.ammo
			Input.action_press("fire")
			get_tree().create_timer(0.05).timeout.connect(func(): Input.action_release("fire"))
			_mem["sn_ammo"] = a
			_next(3)
		3:
			if _step_t < 0.15:
				return
			if not _check(p.gun.ammo == int(_mem["sn_ammo"]) - 1, "狙击没开火"):
				return
			if not _check(p.gun.cycling > 0.0, "狙击开火后没有拉栓"):
				return
			_note("狙击开镜、开火、拉栓正常")
			Input.action_release("aim")
			_next(4)
		4:
			if _step_t > 1.5:
				_switch_to(p, "zhuge")
				_next_phase()


# ------------------------------------------------------------------ 灵环：瓶颈、掉环、吸收、选神通、放神通

func _run_ring() -> void:
	var w := _ready_world()
	if not w:
		return
	var p := w.player
	match _step:
		0:
			Profile.add_xp(100000)
			w._broadcast_prog()
			if not _check(Profile.level == 10 and Profile.at_bottleneck(), "经验很多时应该卡在 10 级瓶颈，实际 %d 级" % Profile.level):
				return
			_note("卡在 10 级瓶颈")
			# 刚从暗器铺出来：先走开一点，别让灵环掉在铺子门口（按 F 会开铺子）
			var away := p.global_position - w.builder.shop_door
			away.y = 0.0
			if away.length() < 12.0:
				for i in 12:
					var dir := (away.normalized() if away.length() > 0.5 else Vector3.RIGHT).rotated(Vector3.UP, i * TAU / 12.0)
					var q := w.builder.shop_door + dir * 14.0
					if w.island.is_land(q.x, q.z):
						p.teleport(Vector3(q.x, w.island.height_at(q.x, q.z) + 0.3, q.z))
						break
			var fwd := -p.global_transform.basis.z
			fwd.y = 0
			var rp := p.global_position + fwd.normalized() * 3.0
			w._host_drop_ring(rp, 1, "rabbit")
			_next(1)
		1:
			if _step_t < 0.4:
				return
			var rid: int = w.rings.keys()[w.rings.size() - 1]
			var rp: Vector3 = w.rings[rid]["pos"]
			var g := w.island.height_at(rp.x, rp.z)
			p.teleport(Vector3(rp.x, g + 0.3, rp.z + 1.2))
			_aim(p, rp)
			_next(2)
		2:
			if _step_t < 0.5:
				return
			if _shots and not _mem.has("ring_shot"):
				_mem["ring_shot"] = true
				_shot("ring_drop")
				return
			var it := w.nearest_interactable()
			var dbg := "玩家 %s，灵环 %s" % [p.global_position, w.rings.values().map(func(r): return r["pos"])]
			if not _check(it.get("id", "") == "ring" and it.get("ok", false), "站在灵环旁边却不能吸收：%s（%s）" % [it, dbg]):
				return
			# 第十一版：吸收要站着 10 秒，会来一小波灵兽；测试里别让人被咬死
			p.invuln_t = 20.0
			w.interact()
			_next(3)
		3:
			if w.hud._choice == null and Profile.rings.size() >= 1:
				# 新版：神通吸收完自动揭晓，不用选
				_note("吸收了百年灵环，神通【%s】" % Data.SKILLS[Profile.rings[0]["skill"]]["name"])
				Profile.add_xp(100000)
				w._broadcast_prog()
				if not _check(Profile.level == 20, "吸收灵环后没有突破瓶颈（%d 级）" % Profile.level):
					return
				_next(4)
			elif w.hud._choice != null:
				if _shots and not _mem.has("choice_shot"):
					_mem["choice_shot"] = true
					_shot("skill_choice")
					return
				var sid: String = Data.SKILL_TREE[Data.wuhun_id(Settings.wuhun)][0][0]
				w.finish_absorb(1, "rabbit", sid)
				w.hud._choice.queue_free()
				w.hud._choice = null
				w.set_ui_open(false)
				w.hud._refresh_skills()
				if not _check(Profile.rings.size() == 1, "吸收后灵环数不对"):
					return
				_note("吸收了百年灵环，神通【%s】" % Data.SKILLS[sid]["name"])
				Profile.add_xp(100000)
				w._broadcast_prog()
				if not _check(Profile.level == 20, "吸收灵环后没有突破瓶颈（%d 级）" % Profile.level):
					return
				_next(4)
			elif _step_t > 15.0:
				_fail("吸收灵环 15 秒后还没学到神通")
		4:
			if _step_t < 0.5:
				return
			p.soul = Profile.max_soul()
			# 神通现在由灵兽决定：测试固定换成第一环的攻击神通，结果稳定
			Profile.rings[0]["skill"] = Data.SKILL_TREE[Data.wuhun_id(Settings.wuhun)][0][0]
			var s0 := p.soul
			var m := w.island.habitat("meadow")
			var c: Vector2 = m["center"]
			_aim(p, Vector3(c.x, w.island.height_at(c.x, c.y), c.y))
			w.skills.cast(0)
			if not _check(w.skills.cooldowns[0] > 0.0 and p.soul < s0, "放神通没生效"):
				return
			_note("放出神通，冷却 %.1f 秒" % w.skills.cooldowns[0])
			_next(5)
		5:
			if _step_t < 0.4:
				return
			if _shots and not _mem.has("skill_shot"):
				_mem["skill_shot"] = true
				_shot("skill_cast")
				return
			if _step_t < 1.2:
				return
			if _shots and not _mem.has("wuhun_shot"):
				_mem["wuhun_shot"] = true
				w.hud.toggle_wuhun()
				_next(6)
				return
			_next_phase()
		6:
			if _step_t < 0.6:
				return
			await _shot("wuhun_panel")
			w.hud.close_panels()
			_next_phase()


# ------------------------------------------------------------------ Boss

func _quest_index(chapter: int, type: String) -> int:
	var qs: Array = Data.CHAPTERS[chapter]["quests"]
	for i in qs.size():
		if qs[i]["type"] == type:
			return i
	return -1


func _run_boss() -> void:
	var w := _ready_world()
	if not w:
		return
	var p := w.player
	match _step:
		0:
			w.quest_idx = _quest_index(w.chapter, "altar")
			w.quest_count = 0
			w._host_sync_quest()
			_mem.erase("boss_dbg")
			var a := w.island.altar_pos
			p.teleport(a + Vector3(0, 1.2, 2.0))
			_aim(p, a + Vector3(0, 1.2, 0))
			_next(1)
		1:
			if _step_t < 0.8:
				return
			if _shots and not _mem.has("altar_shot"):
				_mem["altar_shot"] = true
				var a := w.island.altar_pos
				p.teleport(a + Vector3(6.0, 0.5, 8.0))
				_aim(p, a + Vector3(0, 1.5, 0))
				_step_t = 0.0
				get_tree().create_timer(0.8).timeout.connect(func():
					await _shot("altar")
					p.teleport(a + Vector3(0, 1.2, 2.0)))
				return
			var it := w.nearest_interactable()
			if not _check(it.get("id", "") == "altar", "站在祭坛上却没有提示：%s" % it):
				return
			w.interact()
			_next(2)
		2:
			if w.boss:
				_note("Boss 出现了：%s，血量 %d" % [w.boss.kind, int(w.boss.hp)])
				if not _check(w._cur_quest().get("type", "") == "boss", "召唤 Boss 后任务没推进"):
					return
				_mem["boss_hp"] = w.boss.hp
				_next(3)
			elif _step_t > 2.0:
				_fail("按了祭坛，Boss 没出现")
		3:
			# 等它出场，然后用暗器打（真实命中判定）
			if _step_t < 3.0:
				return
			var b := w.boss
			if not b:
				_fail("Boss 不见了")
				return
			# 湖里的 Boss：从它往岛中心走，走到岸上再往里 2 米；陆地上的 Boss：站在 14 米外
			var c := b.center()
			var dir := Vector3(-c.x, 0, -c.z).normalized()
			var st := Vector3(c.x, 0, c.z)
			if w.island.is_land(c.x, c.z):
				st += dir * 14.0
			else:
				for i in 200:
					st += dir
					if w.island.is_land(st.x, st.z):
						break
				st += dir * 2.0
			st.y = w.island.height_at(st.x, st.z) + 0.3
			p.teleport(st)
			p.hp = Profile.max_hp()
			_next(4)
		4:
			var b := w.boss
			if not b:
				_next(5)
				return
			p.hp = Profile.max_hp()
			_aim(p, b.center())
			if p.gun.ammo <= 0 and not p.gun.reloading:
				p.start_reload()
			Input.action_press("fire")
			if _shots and _step_t > 1.0 and not _mem.has("boss_shot"):
				_mem["boss_shot"] = true
				_shot("boss_fight")
				return
			if not _mem.has("boss_dbg") and _step_t > 1.0:
				_mem["boss_dbg"] = true
				var hit := w.raycast(p.cam.global_position, b.center(), U.LAYER_WORLD | U.LAYER_BEAST, [p.get_rid()])
				_note("调试：Boss 状态 %s 位置 %s，玩家 %s，射线打到 %s，弹药 %d，dead=%s input=%s" % [b.state, b.center(), p.cam.global_position, hit.get("collider"), p.gun.ammo, p.dead, p.input_enabled])
			if _step_t > 3.0:
				Input.action_release("fire")
				var lost: float = float(_mem["boss_hp"]) - b.hp
				_note("用暗器打了 Boss %d 血" % int(lost))
				if not _check(lost > 0.0, "打 Boss 没掉血"):
					return
				w.host_boss_damage(b.hp + 10.0, true, Net.my_id)
				_next(5)
		5:
			if w.boss == null:
				if not _check(not Profile.bones.is_empty(), "打死 Boss 没拿到灵骨"):
					return
				_note("Boss 死了，拿到灵骨 %s，任务：%s" % [Profile.bones, w._cur_quest().get("text", "")])
				if not _check(w._cur_quest().get("type", "") in ["boat", "end", "god"], "打完 Boss 任务没推进"):
					return
				# 剧情：灵主临死说一句、第一次打倒记下（接着播天枢记忆、青崖子说话）
				var lk := str(Data.CHAPTERS[w.chapter]["boss"])
				if not _check(int(Profile.stats.get("story_" + lk, 0)) == 1 and (w.hud._say_t > 0.0 or not w.hud._say_queue.is_empty()), "打倒灵主没有触发剧情（临死台词 / 天枢记忆）"):
					return
				_note("灵主临死：「%s」" % Story.lord(lk, "death"))
				# 青崖子站在天坛边，按 F 说的是打完以后的话
				if not _check(w.sage != null and w.sage.lines_now().has(Story.lord(lk, "after")), "天坛边没有青崖子 / 他说的话没跟着主线走"):
					return
				w.sage.talk()
				_note("青崖子：「%s」" % w.hud._say_queue[0][1] if not w.hud._say_queue.is_empty() else "青崖子说话了")
				_next(6)
			elif _step_t > 4.0:
				_fail("Boss 血打光了却没死")
		6:
			if _step_t > 1.0:
				if _shots and not _mem.has("boss_dead_shot"):
					_mem["boss_dead_shot"] = true
					_shot("boss_defeated")
					return
				_next_phase()


## 灵兽王：捆魂、暴怒、逃跑、击杀掉王魄和灵环，再拿王魄附魔
func _run_kings() -> void:
	var w := _ready_world()
	if not w:
		return
	var p := w.player
	match _step:
		0:
			w._init_elites()
			if not _check(not w.elites.is_empty(), "这张图没有灵兽王的位置"):
				return
			var key: String = w.elites.keys()[0]
			w._host_spawn_elite(key)
			var k: Beast = w.beasts.get(int(w.elites[key]["id"]))
			if not _check(k != null and k.temper == "elite", "灵兽王没刷出来"):
				return
			_mem["king"] = k.id
			_note("灵兽王：%s，血量 %d" % [k.display_name(), int(k.max_hp)])
			p.teleport(k.global_position + Vector3(0, 0.5, 14))
			_next(1)
		1:
			if _step_t < 1.5:
				return
			var k: Beast = w.beasts.get(int(_mem["king"]))
			w.host_hook(k.id, Net.my_id)
			if not _check(k.root_t > 0.0, "单人用引魂索钩灵兽王没捆住"):
				return
			_note("捆魂成功，按住 %.1f 秒" % k.root_t)
			k.root_t = 0.0
			# 随机词条"坚甲"会让打身子的伤害减半，测不到半血
			k.affixes.clear()
			k.take_hit(k.max_hp * 0.55, Vector3.ZERO, Vector3.ZERO, false, Net.my_id, 10.0)
			_next(2)
		2:
			if _step_t < 0.5:
				return
			var k: Beast = w.beasts.get(int(_mem["king"]))
			if not _check(k._phase2, "灵兽王半血没暴怒"):
				return
			k.root_t = 0.0
			k.take_hit(k.hp - k.max_hp * 0.2, Vector3.ZERO, Vector3.ZERO, false, Net.my_id, 10.0)
			_next(3)
		3:
			if _step_t < 0.6:
				return
			var k: Beast = w.beasts.get(int(_mem["king"]))
			if not _check(k._retreat, "灵兽王残血没逃跑"):
				return
			_note("灵兽王暴怒、逃跑都正常")
			_mem["mats"] = int(Profile.materials.get(k.species, 0))
			_mem["sp"] = k.species
			k.take_hit(k.hp + 10.0, Vector3.ZERO, Vector3.ZERO, false, Net.my_id, 10.0)
			w._host_kill(k)
			_next(4)
		4:
			if _step_t < 1.0:
				return
			if not _check(int(Profile.materials.get(str(_mem["sp"]), 0)) > int(_mem["mats"]), "打死灵兽王没拿到王魄"):
				return
			if not _check(not w.rings.is_empty(), "打死灵兽王没掉灵环"):
				return
			Profile.add_material("rabbit", 2)
			Profile.add_money(1000)
			if not _check(Profile.do_enchant("xiujian", "bind") and Profile.enchant.get("xiujian", "") == "bind", "附魔失败"):
				return
			_note("王魄、灵环、附魔都正常")
			_next_phase()


## 界面截图：HUD、暗器铺、灵相、暂停、成就、地图、神通二选一、倒地、Boss 出场、修士榜
##   godot --path game --resolution 1920x1080 -- --autotest=shots --plan=menu,uishots,done --out=目录
func _run_uishots() -> void:
	var w := _ready_world()
	if not w:
		return
	var p := w.player
	var h: Hud = w.hud
	match _step:
		0:
			if _step_t < 2.0:
				return
			var tree: Array = Data.SKILL_TREE[Data.wuhun_id(Settings.wuhun)]
			for i in 3:
				Profile.add_ring([1, 1, 2][i], str(tree[i][i % 2]), ["wolf", "rabbit", "snake"][i])
			Profile.level = 34
			Profile.xp = Data.xp_to_next(34) / 3
			Profile.add_money(12840)
			Profile.items["grenade"] = 3
			Profile.items["pill"] = 2
			Profile.add_weapon("zhuge")
			Profile.add_material("wolf", 2)
			w.skills.cooldowns[1] = 7.0
			h._refresh_skills()
			w._init_elites()
			var key: String = w.elites.keys()[0]
			w._host_spawn_elite(key)
			var k: Beast = w.beasts.get(int(w.elites[key]["id"]))
			_mem["king"] = k.id
			p.teleport(k.global_position + Vector3(0, 0.5, 13))
			_next(1)
		1:
			if _step_t < 1.2:
				return
			var k: Beast = w.beasts.get(int(_mem["king"]))
			if k:
				k.hp = k.max_hp * 0.62
				k.root_t = 30.0
				_aim(p, k.global_position + Vector3(0, 1.5, 0))
			p.hp = Profile.max_hp() * 0.7
			p.soul = Profile.max_soul() * 0.55
			h.feed("你 击杀了 百年 · 恶狼", Color.WHITE)
			h.feed("客人 击杀了 十年 · 玉兔", Color.WHITE)
			h.kill_popup(186, 42, ["爆头 +50%", "空中击杀"], "wolf", 1)
			h.toast("✔ 悬赏完成：青鸾 · 十年    +70 灵石", Color(0.6, 1.0, 0.7), 5.0)
			_next(2)
		2:
			if _step_t < 0.6:
				return
			_next(3)
			await _shot("ui_hud")
			h.open_shop()
		3:
			if _step_t < 0.5:
				return
			_next(4)
			await _shot("ui_shop")
			h._shop._tab = "enchant"
			h._shop.refresh()
		4:
			if _step_t < 0.5:
				return
			_next(5)
			await _shot("ui_shop_enchant")
			h._shop._tab = "attach"
			h._shop.refresh()
		5:
			if _step_t < 0.5:
				return
			_next(6)
			await _shot("ui_shop_attach")
			h.close_panels()
			h.toggle_wuhun()
		6:
			if _step_t < 0.5:
				return
			_next(7)
			await _shot("ui_wuhun")
			h.close_panels()
			w.set_paused(true)
		7:
			if _step_t < 0.5:
				return
			_next(70)
			await _shot("ui_pause")
			h._pause_menu.visible = false
			h._settings.visible = true
		70:
			if _step_t < 0.5:
				return
			_next(8)
			await _shot("ui_settings")
			w.set_paused(false)
			h.toggle_achievements()
		8:
			if _step_t < 0.5:
				return
			_next(9)
			await _shot("ui_achievements")
			h.toggle_achievements()
			h._bigmap.visible = true
		9:
			if _step_t < 0.5:
				return
			_next(10)
			await _shot("ui_map")
			h._bigmap.visible = false
			h.choose_skill(2, "snake")
		10:
			if _step_t < 0.5:
				return
			_next(11)
			await _shot("ui_choice")
			h._choice.queue_free()
			h._choice = null
			w.set_ui_open(false)
			h.death_countdown(8.0, true)
		11:
			if _step_t < 0.5:
				return
			_next(12)
			await _shot("ui_down")
			h.death_countdown(-1.0)
			h.boss_intro("千年灵兽 · 碧鳞蛇")
		12:
			if _step_t < 1.4:
				return
			_next(13)
			await _shot("ui_intro")
			Input.action_press("scoreboard")
			h.level_up(35)
		13:
			if _step_t < 0.5:
				return
			_next(14)
			await _shot("ui_scores")
			Input.action_release("scoreboard")
			h.open_boat_picker([1, 2])
		14:
			if _step_t < 0.5:
				return
			_next(15)
			await _shot("ui_boat")
			h._close_boat_picker()
			_next_phase()


## 特效截图：在正前方 12 米一个接一个放特效，每个在最好看的那一刻截一张
##   godot --path game --resolution 1920x1080 -- --autotest=shots --plan=fxshots,done --out=目录 [--only=explosion,beam]
var _fxq: Array = []


func _run_fxshots() -> void:
	var w := _ready_world()
	if not w:
		return
	var p := w.player
	var fx: Fx = w.fx
	match _step:
		0:
			if _step_t < 2.5:
				return
			w.hud.visible = false
			var fwd := -p.cam.global_basis.z
			fwd.y = 0.0
			fwd = fwd.normalized()
			var c := p.global_position + fwd * 12.0
			c.y = maxf(w.island.height_at(c.x, c.z), Island.WATER_Y)
			_mem["c"] = c
			_mem["fwd"] = fwd
			var gold := Color(1.0, 0.8, 0.35)
			var purple := Color(0.68, 0.36, 1.0)
			var cyan := Color(0.35, 0.8, 1.0)
			var orange := Color(1.0, 0.5, 0.2)
			var green := Color(0.4, 1.0, 0.5)
			var holder := Node3D.new()
			fx.add_child(holder)
			holder.global_position = c
			_mem["holder"] = holder
			var eye := p.cam.global_position
			var side := fwd.cross(Vector3.UP)
			_fxq = [
				["explosion", func(o: Vector3): fx.explosion(o + Vector3.UP, 5.0, orange), 0.12],
				["explosion_smoke", func(o: Vector3): fx.explosion(o + Vector3.UP, 5.0, orange), 0.55],
				["shockwave", func(o: Vector3): fx.shockwave(o, 8.0, cyan), 0.14],
				["sigil", func(o: Vector3): fx.sigil(o, 5.0, purple), 0.3, 0.0],
				["vines", func(o: Vector3): fx.vines(o, 4.0, green), 0.5],
				["vortex", func(o: Vector3): fx.vortex(o, 5.0, cyan), 0.7, 0.0],
				["beam", func(o: Vector3): fx.beam(eye + side * 1.5 - Vector3.UP * 0.4, (o + Vector3.UP * 1.5) - (eye + side * 1.5), 30.0, gold, 0.4), 0.08],
				["chain", func(o: Vector3): fx.chain_fx([o + side * 5.0 + Vector3.UP * 2.0, o + Vector3.UP * 1.5 + fwd * 2.0, o - side * 4.0 + Vector3.UP * 2.2, o - side * 7.0 + fwd * 4.0 + Vector3.UP * 1.2], cyan), 0.04],
				["pillar", func(o: Vector3): fx._pillar(o, gold, 1.5, 40.0, 0.8), 0.35, 4.0],
				["level_up", func(o: Vector3): fx.level_up_burst(o, 4), 0.4],
				["breakthrough", func(o: Vector3): fx.ring_breakthrough(o, purple, 3), 0.75, 3.0],
				["aura", func(o: Vector3): fx.aura_burst(o, green, 4.0), 0.3],
				["death", func(o: Vector3): fx.death_burst(o + Vector3.UP, purple, 2), 0.1],
				["impact", func(o: Vector3): _fx_impact(fx, o, fwd, side), 0.06],
				["telegraph", func(o: Vector3): _free_later(fx.telegraph(o, 6.0, 1.5)), 0.9, 0.0],
				["cone", func(o: Vector3): w._on_cone([o - fwd * 4.0, fwd, 0.6, 12.0, 1.5, 0.0]), 0.9, 0.0],
				["boss_wave", func(o: Vector3): w._on_shockwave([o, 9.0, 8.0, 0.0]), 0.6, 0.5],
				["blackhole", func(o: Vector3): fx.blackhole_fx(o, 6.0, 2.0, purple), 1.0, 2.5],
				["domain", func(o: Vector3): fx.domain_fx(o, 7.0, 3.0, gold), 0.9, 1.0],
				["meteor", func(o: Vector3): fx.meteor_strike(o, 6.0, orange), 0.13, 5.0],
				["meteor_hit", func(o: Vector3): fx.meteor_strike(o, 6.0, orange), 0.36],
				["summon_phoenix", func(o: Vector3): fx.summon_visual("phoenix", orange, 3.0, o + Vector3.UP * 2.0), 0.9, 2.0],
				["summon_tiger", func(o: Vector3): fx.summon_visual("tiger", cyan, 3.0, o), 0.9],
				["orbit", func(o: Vector3): fx.orbit_visual(holder, "scythe", 5, 3.0, 3.0, cyan), 0.6],
				["shield", func(o: Vector3): fx.shield_bubble(holder, 3.0, cyan), 0.5],
				["soul_ring", func(o: Vector3): _free_later(fx.soul_ring(o + Vector3.UP * 0.3, purple)), 0.5, 1.0],
				["absorb", func(o: Vector3): fx.absorb(holder, gold), 1.2, 3.0],
				["poison", func(o: Vector3): _free_later(fx.poison_pool(o, 4.0)), 0.8, 0.0],
				["lotus", func(o: Vector3): fx.lotus_explosion(o + Vector3.UP), 0.2],
				["muzzle", func(o: Vector3): fx.muzzle_flash(eye + fwd * 1.3 + side * 0.25 - Vector3.UP * 0.25, fwd, orange, true), 0.02],
				["slam", func(o: Vector3): fx.slam(o, 7.0), 0.25, 0.0],
				["burn_bleed", func(o: Vector3): _fx_burn_bleed(fx, o, side, orange), 0.15],
				["shen", func(o: Vector3): fx.shen_manifest(o, 2, gold), 1.6, 14.0],
				["poof", func(o: Vector3): fx.poof(o + Vector3.UP), 0.3],
			]
			if args.has("only"):
				var only := str(args["only"]).split(",")
				_fxq = _fxq.filter(func(e): return str(e[0]) in only)
			_next(1)
		1:
			if _fxq.is_empty():
				w.hud.visible = true
				_next_phase()
				return
			if _step_t < 2.2:
				return
			var e: Array = _fxq.pop_front()
			var c: Vector3 = _mem["c"]
			_aim(p, c + Vector3(0, float(e[3]) if e.size() > 3 else 1.5, 0))
			(e[1] as Callable).call(c)
			_mem["shot"] = e[0]
			_mem["sd"] = e[2]
			_next(2)
		2:
			if _step_t < float(_mem["sd"]):
				return
			_next(1)
			await _shot("fx_" + str(_mem["shot"]))


## 天上飞的鸟：用真的射线打它，要掉下来变成一只灵兽；灵兽王任务要能计数
func _run_critters() -> void:
	var w := _ready_world()
	if not w:
		return
	var p := w.player
	match _step:
		0:
			if _step_t < 1.0:
				return
			if not _check(not w.builder._critters.is_empty(), "这张图天上没有能打的鸟"):
				return
			var n: Node3D = w.builder._critters[0]
			var body := n.get_node_or_null("Hit") as StaticBody3D
			if not _check(body != null, "天上的鸟没有碰撞体"):
				return
			# 站到鸟的正下方偏一点，朝它开一枪（真的射线）
			p.teleport(Vector3(n.global_position.x + 6.0, w.island.height_at(n.global_position.x + 6.0, n.global_position.z) + 0.5, n.global_position.z))
			_mem["nb"] = w.beasts.size()
			_next(1)
		1:
			if _step_t < 0.5:
				return
			var n: Node3D = w.builder._critters[0]
			var hit: Dictionary = w.raycast(p.cam.global_position, n.global_position, U.LAYER_WORLD | U.LAYER_BEAST, [p.get_rid()])
			if not _check(not hit.is_empty() and (hit["collider"] as Node).has_meta("critter"), "射线打不到天上的鸟"):
				return
			w.critter_hit(int((hit["collider"] as Node).get_meta("critter")), hit["position"])
			_next(2)
		2:
			if _step_t < 0.5:
				return
			if not _check(w.beasts.size() > int(_mem["nb"]), "打中鸟以后没有掉下来变成灵兽"):
				return
			if not _check(not (w.builder._critters[0] as Node3D).visible, "打下来的鸟还在天上飞"):
				return
			_note("天上的鸟打下来变成了灵兽")
			# 秘境任务：通关一次就算
			w.quest_idx = _quest_index(w.chapter, "dungeon")
			w.quest_count = 0
			w._host_check_quest()
			var before := w.quest_idx
			w._host_quest_event("dungeon", 1)
			if not _check(w.quest_idx > before, "通关秘境任务没推进"):
				return
			_note("秘境任务推进正常")
			_next_phase()


## 猎灵连击：空中命中涨评级、奖励倍数、3 秒不打就断；灵相真身：充满后变身、加伤害、子弹不耗、到时间结束
func _run_combo() -> void:
	var w := _ready_world()
	if not w:
		return
	var c: Combo = w.combo
	var p := w.player
	match _step:
		0:
			if _step_t < 1.0:
				return
			for i in 45:
				c.hit(true, i % 3 == 0)
			c.kill(true)
			if not _check(c.rank() >= 3, "空中连击 45 下评级还不到 A（%d 分）" % int(c.points)):
				return
			if not _check(c.mult() > 1.5, "连击奖励倍数没涨"):
				return
			_note("连击 %d · 评级 %s · 奖励 ×%.2f · 充能 %d%%" % [c.hits, Combo.RANKS[c.rank()][0], c.mult(), int(c.meter * 100)])
			_next(1)
		1:
			if _step_t < Combo.DECAY + 0.4:
				return
			if not _check(c.hits == 0 and c.rank() == 0, "3 秒不打连击没断"):
				return
			_note("连击 3 秒不打就断了")
			if not Combo.TRUE_BODY:
				_check(c.meter == 0.0, "灵相真身关掉了还在充能")
				_next_phase()
				return
			c.meter = 1.0
			var before := p.damage_mult()
			c.activate()
			if not _check(c.active() and p.damage_mult() > before * 1.8, "灵相真身没加伤害"):
				return
			p.gun.ammo = 0
			_mem["dm"] = before
			_next(2)
		2:
			if _step_t < 0.3:
				return
			if not _check(p.gun.ammo == int(p.gun.d["mag"]), "灵相真身期间子弹还在消耗"):
				return
			c.tb_t = 0.05
			_next(3)
		3:
			if _step_t < 0.4:
				return
			if not _check(not c.active() and c.meter == 0.0, "灵相真身到时间没结束"):
				return
			_note("灵相真身：加伤害、子弹不耗、到时间结束都正常")
			_next_phase()


## 截图：连击评级 S、灵相真身
func _run_comboshot() -> void:
	var w := _ready_world()
	if not w:
		return
	var c: Combo = w.combo
	match _step:
		0:
			if _step_t < 2.0:
				return
			for i in 75:
				c.hit(true, i % 3 == 0)
			_next(1)
		1:
			c.since = 0.0
			if _step_t < 0.6:
				return
			_next(2)
			await _shot("combo")
			c.meter = 1.0
			c.activate()
		2:
			c.since = 0.0
			if _step_t < 1.2:
				return
			_next(3)
			await _shot("true_body")
		3:
			if _step_t < 0.5:
				return
			_next_phase()


## 机器人打一局秘境（配 --from_save=profile.json --tier=0，用真存档的等级、暗器、灵骨；存档只读不写）：
## 站在进出台上，自动瞄最近的灵兽开枪，记掉了多少血、最低剩多少、多久通关——用来调单人难度
func _run_bot() -> void:
	var w := _ready_world()
	if not w:
		return
	var d := w.dungeon
	var p := w.player
	match _step:
		0:
			if _step_t < 2.0:
				return
			var tier := int(args.get("tier", "0"))
			# 用真实数值（自动测试默认不乘章节血量）
			Data.autotest = false
			# 拿存档里每秒伤害最高的暗器
			var bi := 0
			var bdps := -1.0
			for i in p.guns.size():
				var gd: Dictionary = p.guns[i].d
				var dps := float(gd["damage"]) * float(gd["pellets"]) * float(gd["rpm"])
				if dps > bdps:
					bdps = dps
					bi = i
			p.switch_weapon(bi)
			var o := Profile.output()
			var fl := []
			for a in 4:
				fl.append(int(Data.hp_floor(w.chapter, a, o)))
			_note("输出：一发 %d · 每秒 %d · 这一章标准 %s · 血量下限（十年/百年/千年/万年）%s" % [int(o.x), int(o.y), Data.ref_output(w.chapter), fl])
			_note("机器人：%d 级 · %d 环 · 第 %d 章 · 暗器 %s · 体力 %d · 护体 %d%% · 进%s" % [Profile.level, Profile.rings.size(), w.chapter, p.gun.id, int(Profile.max_hp()), roundi(p.defense() * 100.0), d.tier_name(tier)])
			_mem["hurt"] = 0.0
			_mem["minhp"] = 1.0
			Net.send_host("dgenter", [tier])
			_next(1)
		1:
			if not d.inside:
				if _step_t > 3.0:
					_fail("没进秘境")
				return
			_mem["hp_last"] = p.hp
			_mem["wave"] = 0
			_next(2)
		2:
			var last := float(_mem["hp_last"])
			if p.hp < last:
				_mem["hurt"] = float(_mem["hurt"]) + (last - p.hp)
			_mem["hp_last"] = p.hp
			_mem["minhp"] = minf(float(_mem["minhp"]), p.hp / Profile.max_hp())
			if not d.run.is_empty() and int(d.run["wave"]) != int(_mem["wave"]):
				_mem["wave"] = int(d.run["wave"])
				_note("  %d 秒：第 %d 波，体力 %d%%" % [int(_step_t), int(d.run["wave"]), roundi(p.hp / Profile.max_hp() * 100.0)])
			if p.dead:
				_note("  %d 秒倒下了（%s）· 一共挨了 %d 点伤害" % [int(_step_t), str(d.run.get("phase", "")), int(float(_mem["hurt"]))])
				_next_phase()
				return
			if not d.run.is_empty() and str(d.run["phase"]) == "clear":
				_note("  通关：%d 秒 · 一共挨了 %d 点伤害（体力上限的 %d%%）· 最低剩 %d%%" % [int(_step_t), int(float(_mem["hurt"])), roundi(float(_mem["hurt"]) / Profile.max_hp() * 100.0), roundi(float(_mem["minhp"]) * 100.0)])
				Input.action_release("fire")
				_next_phase()
				return
			if _step_t > 300.0:
				_note("  300 秒没打完（%s）" % str(d.run))
				_next_phase()
				return
			var best: Beast = null
			var bd := INF
			for b: Beast in w.beasts.values():
				if b.alive() and b.hunt_role in ["dg", "dgboss"]:
					var dd := b.global_position.distance_to(p.global_position)
					if dd < bd:
						bd = dd
						best = b
			if best:
				_aim(p, best.global_position + Vector3(0, 0.5 * float(Data.AGES[best.age]["scale"]) * best.size_k, 0))
				if p.gun.ammo <= 0 and not p.gun.reloading:
					p.start_reload()
				# 血少了吃回血丹（真人也会吃）
				if p.hp < Profile.max_hp() * 0.4 and int(Profile.items.get("pill", 0)) > 0:
					p._use_pill()
				# 装着的神通好了就放（真人也会放）
				if bool(args.get("skills", "1") == "1"):
					for i in 3:
						if int(Profile.skill_slots[i]) >= 0 and float(w.skills.cooldowns[i]) <= 0.0:
							w.skills.cast(i)
				Input.action_press("fire")
				get_tree().create_timer(0.02).timeout.connect(func(): Input.action_release("fire"))


## 观察秘境（调试用，配 --from_save）：人站着不打，每 2 秒记一次每只灵兽在干什么、谁咬到人了；人来回走，看会不会卡住
func _run_dgwatch() -> void:
	var w := _ready_world()
	if not w:
		return
	var d := w.dungeon
	var p := w.player
	match _step:
		0:
			if _step_t < 2.0:
				return
			Data.autotest = false
			_mem["bites"] = {}
			p.hurt.connect(func(amount, _dir): _mem["hurt_n"] = int(_mem.get("hurt_n", 0)) + 1)
			Net.send_host("dgenter", [int(args.get("tier", "0"))])
			_next(1)
		1:
			if not d.inside:
				return
			_mem["last"] = p.global_position
			_mem["tick"] = 0
			for off in [Vector3(0, 0, 20), Vector3(0, 0, 0), Vector3(10, 0, -10)]:
				var from: Vector3 = Dungeon.ARENA + off + Vector3(0, 5, 0)
				var hit := w.raycast(from, from + Vector3(0, -20, 0), U.LAYER_WORLD)
				print("[watch] 地面探测 %s → %s" % [off, (hit["position"] - Dungeon.ARENA) if not hit.is_empty() else "没打中"])
			_next(2)
		2:
			p.hp = Profile.max_hp()
			# 来回走：往前走、转圈
			p.yaw += 0.6 * get_process_delta_time()
			Input.action_press("move_forward")
			var tick := int(_step_t / 2.0)
			if tick != int(_mem["tick"]):
				_mem["tick"] = tick
				var moved := (p.global_position - (_mem["last"] as Vector3)).length()
				_mem["last"] = p.global_position
				var line := "t=%d 人 %s 走了 %.1f 米 挨打 %d 次 | " % [int(_step_t), _fmt(p.global_position - Dungeon.ARENA), moved, int(_mem.get("hurt_n", 0))]
				for b: Beast in w.beasts.values():
					if b.alive() and b.hunt_role in ["dg", "dgboss"]:
						line += "%s st%d d%.0f v%.1f cd%.1f ch%.1f %s; " % [b.species, b.state, b.global_position.distance_to(p.global_position), b.linear_velocity.length(), b._atk_cd, b._charge_t, _fmt(b.global_position - Dungeon.ARENA)]
				print("[watch] ", line)
			if _step_t > 50.0:
				Input.action_release("move_forward")
				_next_phase()


func _fmt(v: Vector3) -> String:
	return "(%.0f,%.1f,%.0f)" % [v.x, v.y, v.z]


## 旧存档（版本 3）升级：任务往后挪一格，第一章在"坐船"的还在"坐船"
func _run_migrate() -> void:
	var old := Profile.path
	Profile.path = "user://profile_test_migrate.json"
	var cases := [[3, 4, "boat"], [1, 2, "altar"], [0, 0, "dungeon"]]
	for c in cases:
		var f := FileAccess.open(Profile.path, FileAccess.WRITE)
		f.store_string(JSON.stringify({"version": 3, "level": 30, "chapter": 1, "quest": c[0], "quest_count": 2}))
		f.close()
		Profile._defaults()
		Profile.load_profile()
		var q := Data.quest(1, Profile.quest)
		if not _check(Profile.quest == int(c[1]) and str(q.get("type", "")) == str(c[2]), "旧存档任务 %d 升级后是 %d（%s），应该是 %d（%s）" % [c[0], Profile.quest, q.get("type", ""), c[1], c[2]]):
			return
	_note("旧存档升级：任务位置都对（坐船还是坐船、祭坛还是祭坛、第一个任务变成秘境）")
	Profile.path = old
	Profile._defaults()
	Profile.load_profile()
	_next_phase()


func _free_later(n: Node) -> void:
	get_tree().create_timer(2.0).timeout.connect(n.queue_free)


## 仇恨范围：60 米外的凶暴灵兽不过来，走到 14 米它就来咬；90 级灵力护体减伤 36%
func _run_aggro() -> void:
	var w := _ready_world()
	if not w:
		return
	var p := w.player
	match _step:
		0:
			if _step_t < 1.0:
				return
			var base := p.global_position
			var spot := Vector3.INF
			for i in 36:
				var a := TAU * i / 36.0
				var q := base + Vector3(cos(a) * 60.0, 0, sin(a) * 60.0)
				var gy := w._solid_y(q.x, q.z)
				# 地面要是真的地形（不是石头、树这些道具的顶上）
				if w.island.is_land(q.x, q.z) and gy != -INF and absf(gy - base.y) < 6.0 and absf(gy - w.island.height_at(q.x, q.z)) < 0.5:
					spot = Vector3(q.x, gy + 0.4, q.z)
					break
			if not _check(spot != Vector3.INF, "60 米外找不到陆地放灵兽"):
				return
			_target = w._host_spawn_wild(spot, "wolf", 1, "fierce")
			_next(1)
		1:
			if _step_t < 5.0:
				return
			var b := _target
			if not _check(b != null and is_instance_valid(b) and b.alive(), "凶暴灵兽不见了"):
				return
			var d := b.global_position.distance_to(p.global_position)
			if not _check(d > 45.0, "60 米外的凶暴灵兽还是追过来了（现在 %.0f 米）" % d):
				return
			_note("60 米外的凶暴灵兽不追人（%.0f 米）" % d)
			var to := p.global_position - b.global_position
			to.y = 0.0
			var q := b.global_position + to.normalized() * 14.0
			var qy := w._solid_y(q.x, q.z)
			p.teleport(Vector3(q.x, (qy if qy != -INF else w.island.height_at(q.x, q.z)) + 0.3, q.z))
			p.invuln_t = 0.0
			_mem["hp0"] = p.hp
			_next(2)
		2:
			var b := _target
			var d := b.global_position.distance_to(p.global_position)
			if d < 8.0 or p.hp < float(_mem["hp0"]):
				_note("走到 14 米它就追上来了（%.1f 秒，%.1f 米）" % [_step_t, d])
				w.beast_escaped(b, "despawn")
				var lv := Profile.level
				Profile.level = 90
				p.shield = 0.0
				p.hp = 5000.0
				p.take_damage(100.0, p.global_position + Vector3.FORWARD)
				var lost := 5000.0 - p.hp
				Profile.level = lv
				p.hp = Profile.max_hp()
				if not _check(absf(lost - 64.0) < 1.0, "90 级挨 100 点伤害掉了 %.1f（应该 64）" % lost):
					return
				_note("90 级灵力护体：挨 100 掉 %.0f" % lost)
				_next_phase()
			elif _step_t > 8.0:
				_fail("走到 14 米凶暴灵兽也不过来（%.1f 米；灵兽 %s %s state=%d，玩家 %s dead=%s 能打=%s）" % [d, b.global_position, b.temper, b.state, p.global_position, p.dead, not p.untargetable()])


## 猎灵：卡瓶颈 → 猎灵榜挑一只（记下卡片上写的神通）→ 猎物出现、有踪迹、罗盘不标成普通的王
## → 打死掉灵环 → 吸收（单人 10 秒、来一小波只冲吸收的人）→ 学到的就是卡片上写的神通
## → 再吸收一次时倒下：打断、灵环掉回地上
func _run_huntrun() -> void:
	var w := _world()
	match _step:
		0:
			w = _ready_world()
			if not w or _step_t < 1.0:
				return
			Profile.level = 10
			Profile.rings = []
			w._broadcast_prog()
			var h := w.hunt
			w.hud.open_board()
			if not _check(w.hud._board != null and is_instance_valid(w.hud._board), "猎灵榜打不开"):
				return
			w.hud._close_board()
			var list := h.species_list()
			if not _check(not list.is_empty(), "猎灵榜上没有灵兽"):
				return
			var sp := str(list[0])
			var age := h.base_age()
			_mem["sp"] = sp
			_mem["sid"] = h.skill_preview(sp, age)
			_note("猎灵榜：%d 种灵兽；挑了%s%s，卡片上写的神通【%s】" % [list.size(), Data.age_name(age), Data.BEASTS[sp]["name"], Data.SKILLS[str(_mem["sid"])]["name"]])
			w.player.invuln_t = 9999.0
			h.request(sp, age)
			_mem["old_wid"] = w.get_instance_id()
			_next(10)
		10:
			# 全队去猎场：换了一张大地图
			w = _ready_world()
			if not w or w.get_instance_id() == int(_mem["old_wid"]) or not w.island.hunting:
				if _step_t > 15.0:
					_fail("挑了猎物没去猎场")
				return
			var isl := w.island
			_note("到了猎场：%d×%d 米，%d 片区域（老窝「%s」离营地 %d 米，巢穴「%s」），%d 处宝藏" % [isl.size - 1, isl.size - 1, isl.habitats.size(), isl.zone_name(isl.home), int(isl.home.distance_to(isl.spawn)), isl.zone_name(isl.nest), isl.treasures.size()])
			if not _check(isl.habitats.size() >= 5 and isl.home.distance_to(isl.spawn) > 100.0 and isl.treasures.size() >= 8, "猎场太小 / 区域太少"):
				return
			w.player.invuln_t = 9999.0
			_next(1)
		1:
			var h := w.hunt
			# 猎物刚出现的那一帧，自己这边还没换过来（下一帧会把追踪进度清零），等它换好再看爪痕
			if h.target_id == 0 or not w.beasts.has(h.target_id) or h._clue_target != h.target_id:
				if _step_t > 5.0:
					_fail("挑了猎物没出现")
				return
			var b: Beast = w.beasts[h.target_id]
			if not _check(b.temper == "elite" and b.hunt_role == "target" and b.species == str(_mem["sp"]), "猎物不对"):
				return
			for m in w.hud._compass_marks():
				if str(m[1]) == "王" or str(m[1]) == "猎":
					_fail("还没追踪，猎物就标在罗盘上了（%s）" % m[1])
					return
			var h2 := w.hunt
			if not _check(h2.clues.size() >= 2 and h2.region != "", "猎物没有出没地 / 爪痕（%d）" % h2.clues.size()):
				return
			_note("猎物：%s，%d 米外，在「%s」一带，地上 %d 处爪痕" % [b.display_name(), int(b.global_position.distance_to(w.player.global_position)), h2.region, h2.clues.size()])
			# 走到每处爪痕按 F 看：看满 3 处锁定
			var read := 0
			for c in h2.clues:
				w.player.teleport((c[1] as Vector3) + Vector3(0.5, 0.4, 0))
				var it := w.nearest_interactable()
				if str(it.get("id", "")) == "hclue":
					w.interact()
					read += 1
			if h2._lock_t <= 0.0 and read < 3:
				# 爪痕不够 3 处：让它走一走再留几处
				b.spawn_pos = b.global_position + Vector3(40, 0, 0)
				_mem["need_more"] = true
			if not _check(read >= 2, "站在爪痕旁边没有「查看痕迹」（看了 %d 处）" % read):
				return
			_note("看了 %d 处爪痕：%s" % [read, h2._last_read])
			for i in 16:
				var a := TAU * i / 16.0
				var q := b.global_position + Vector3(cos(a) * 30.0, 0, sin(a) * 30.0)
				if w.island.is_land(q.x, q.z):
					w.player.teleport(Vector3(q.x, w.island.height_at(q.x, q.z) + 0.3, q.z))
					break
			b.global_position += Vector3(4.0, 0.5, 0.0)
			_target = b
			_next(2)
		2:
			var h := w.hunt
			if h._prints.is_empty():
				if _step_t > 3.0:
					_fail("猎物走动了没有踪迹")
				return
			_note("猎物走动留下了踪迹（%d 个脚印）" % h._prints.size())
			# 还没锁定：它走动留下的新爪痕再看几处
			var tries := 0
			while h._lock_t <= 0.0 and tries < 10:
				tries += 1
				var found := false
				for id in h._clue_nodes:
					if not bool(h._clue_nodes[id]["read"]):
						h.read_clue(int(id))
						found = true
						break
				if not found:
					break
			if not _check(h._lock_t > 0.0 and h.located(), "看了爪痕没锁定猎物"):
				return
			var locked_mark := false
			for m in w.hud._compass_marks():
				if str(m[1]) == "猎":
					locked_mark = true
			if not _check(locked_mark, "锁定了罗盘上却没有猎物"):
				return
			_note("锁定猎物：罗盘上标出来了（%.0f 秒）" % h._lock_t)
			# 打到三成血：它逃往巢穴（测试里把它挪到巢穴旁边，不用等它走过去）
			var b := _target
			b.affixes.clear()
			b.hp = b.max_hp * 0.28
			b._aggro_t = 0.0
			_next(11)
		11:
			var b := _target
			if not b._retreat:
				if _step_t > 3.0:
					_fail("三成血了猎物没逃跑")
				return
			if not _mem.has("moved"):
				_mem["moved"] = true
				var nest: Vector3 = w.island.nest
				_note("猎物逃往巢穴「%s」（离它 %d 米）" % [w.island.zone_name(nest), int(b.global_position.distance_to(nest))])
				b.global_position = nest + Vector3(6.0, 1.5, 0.0)
				b.linear_velocity = Vector3.ZERO
				return
			if not b.napping:
				if _step_t > 10.0:
					_fail("猎物回到巢穴没睡着")
				return
			if not _check(b.has_node("Zzz"), "睡着了头上没有 Zzz"):
				return
			var real := b.take_hit(100.0, Vector3.ZERO, Vector3.ZERO, true, Net.my_id, 10.0)
			if not _check(real >= 240.0 and not b.napping, "偷袭伤害不对（%.0f，应该是 250）" % real):
				return
			_note("猎物在巢穴睡着了；偷袭一下 %.0f 伤害（×2.5），它醒了" % real)
			b.hp = b.max_hp * 0.15
			_next(12)
		12:
			var h := w.hunt
			if not h.weak:
				if _step_t > 3.0:
					_fail("两成血以下没有虚弱")
				return
			if not _mem.has("hooked"):
				_mem["hooked"] = true
				_note("猎物虚弱了（一瘸一拐）：用引魂索捆住活捉")
				_target.bind_cd = 0.0
				w.host_hook(_target.id, Net.my_id)
				return
			if w.trip.phase != "done":
				if _step_t > 6.0:
					_fail("捆住虚弱的猎物没活捉（cap %d，phase %s）" % [h._cap_id, w.trip.phase])
				return
			var r: Dictionary = w.trip.result
			if not _check(bool(r["captured"]) and int(r["money"]) > 0, "活捉结算不对：%s" % str(r)):
				return
			_note("活捉成功：评级 %s，用时 %d 秒，报酬 %d 灵石 + %d 修为" % [r["rating"], int(r["time"]), int(r["money"]), int(r["xp"])])
			_next(3)
		3:
			if _step_t < 0.5:
				return
			if not _check(w.hunt.target_id == 0, "猎物死了还挂着"):
				return
			var rid := -1
			for k in w.rings:
				rid = int(k)
			if not _check(rid >= 0, "猎物没掉灵环"):
				return
			var rp: Vector3 = w.rings[rid]["pos"]
			w.player.teleport(Vector3(rp.x, w.island.height_at(rp.x, rp.z) + 0.2, rp.z))
			_next(4)
		4:
			if _step_t < 0.3:
				return
			var it := w.nearest_interactable()
			if not _check(str(it.get("id", "")) == "ring" and bool(it.get("ok", false)), "站在灵环旁边不能吸收（%s）" % str(it.get("text", ""))):
				return
			_note("提示：%s" % str(it["text"]))
			w.interact()
			_next(5)
		5:
			var h := w.hunt
			if h.channel.is_empty():
				if _step_t > 2.0:
					_fail("吸收灵环没开始")
				return
			if not _check(w.player.channeling and absf(float(h.channel["dur"]) - Data.HUNT_CHANNEL_SOLO) < 0.1, "单人吸收时间不对（%.0f 秒）" % float(h.channel["dur"])):
				return
			_next(6)
		6:
			var h := w.hunt
			if not h.channel.is_empty():
				if _step_t > 3.0 and not _mem.has("wave"):
					var n := 0
					for b: Beast in w.beasts.values():
						if b.alive() and b.focus_peer == Net.my_id:
							n += 1
					if not _check(n >= 1, "吸收时没来灵兽"):
						return
					_mem["wave"] = n
					_note("吸收中：来了 %d 只灵兽冲着吸收的人" % n)
				if _step_t > 14.0:
					_fail("单人吸收 14 秒还没结束")
				return
			if not _check(Profile.rings.size() == 1 and not w.player.channeling, "吸收结束没学到神通"):
				return
			if not _check(str(Profile.rings[0]["skill"]) == str(_mem["sid"]), "学到的神通和猎灵榜上写的不一样（%s ≠ %s）" % [Profile.rings[0]["skill"], _mem["sid"]]):
				return
			_note("吸收完：学到的就是猎灵榜上写的【%s】（%.1f 秒）" % [Data.SKILLS[str(_mem["sid"])]["name"], _step_t])
			Profile.level = 20
			w._broadcast_prog()
			w._host_drop_ring(w.player.global_position + Vector3(0, 1.0, 0), 1, str(_mem["sp"]), 90.0)
			_next(7)
		7:
			if _step_t < 0.3:
				return
			var rid := -1
			for k in w.rings:
				rid = int(k)
			if not _check(rid >= 0, "第二个灵环没掉"):
				return
			Net.send_host("absorb", [rid])
			_next(8)
		8:
			if w.hunt.channel.is_empty():
				if _step_t > 2.0:
					_fail("第二次吸收没开始")
				return
			var p := w.player
			p.invuln_t = 0.0
			p.take_damage(999999.0, p.global_position + Vector3.FORWARD)
			_next(9)
		9:
			if _step_t < 0.5:
				return
			if not _check(w.hunt.channel.is_empty() and not w.rings.is_empty() and not w.player.channeling, "倒下了吸收没被打断 / 灵环没掉回地上"):
				return
			_note("吸收时倒下：打断，灵环掉回地上")
			w._respawn_at_dock()
			w.player.invuln_t = 3.0
			# 打开一处宝藏，然后回岛
			var tp: Vector3 = w.island.treasures[0]
			w.player.teleport(tp + Vector3(1.0, 0.4, 0))
			_next(13)
		13:
			if _step_t < 0.4:
				return
			if not _mem.has("chest"):
				_mem["chest"] = true
				var money0 := Profile.money
				var it := w.nearest_interactable()
				if not _check(str(it.get("id", "")) == "htreasure", "站在宝藏旁边没有「打开宝藏」（%s）" % str(it.get("text", ""))):
					return
				w.interact()
				if not _check(Profile.money > money0 and w.trip.found_list().size() == 1, "打开宝藏没拿到东西"):
					return
				_note("打开了一处宝藏：+%d 灵石" % (Profile.money - money0))
				# 灵兽群：走到一处 60 米外，应该刷出来一群（年份不超过猎物）
				if not _check(w.trip._packs.size() >= 8, "猎场里灵兽群太少（%d 处）" % w.trip._packs.size()):
					return
				w.trip.wilds_on = true
				var pk: Dictionary = w.trip._packs[0]
				var pp: Vector3 = pk["pos"]
				var away := (w.island.spawn - pp)
				away.y = 0.0
				var at := pp + away.normalized() * 60.0
				w.player.teleport(Vector3(at.x, w.island.height_at(at.x, at.z) + 0.5, at.z))
				w.player.invuln_t = 60.0
				_mem["pk"] = pk
				_next(14)
				return
		14:
			if _step_t < 2.5:
				return
			var ids: Array = (_mem["pk"] as Dictionary)["ids"]
			if not _check(ids.size() >= 2, "走近了灵兽群没刷出来（%d 只）" % ids.size()):
				return
			var top := int(w.trip.info.get("age", 0))
			for id in ids:
				var b: Beast = w.beasts.get(int(id))
				if b and not _check(b.age <= top, "灵兽群的年份（%d）比猎物（%d）还高" % [b.age, top]):
					return
			_note("灵兽群：%d 处，走近刷出 %d 只%s（%s）" % [w.trip._packs.size(), ids.size(), Data.BEASTS[str((_mem["pk"] as Dictionary)["sp"])]["name"], w.beasts[int(ids[0])].temper])
			for id in ids.duplicate():
				var b2: Beast = w.beasts.get(int(id))
				if b2:
					# 铁钳蟹这种带甲的会减伤（第五章跑出来过没打死），给足
					w.host_skill_damage(b2, b2.hp * 4.0 + 100.0, Vector3.ZERO, Net.my_id)
			w.trip.wilds_on = false
			if w.island.guard_spots.is_empty():
				_note("这张猎场没有守宝点")
				_next(16)
				return
			if not _check(int((_mem["pk"] as Dictionary)["killed"]) >= 2, "灵兽群打死了没记上"):
				return
			var gp: Vector3 = w.island.guard_spots[0]["pos"]
			w.player.teleport(gp + Vector3(0, 0.5, 1.8))
			w.player.invuln_t = 60.0
			var it0 := w.nearest_interactable()
			if not _check(str(it0.get("id", "")) == "htchest" and not bool(it0.get("act", true)), "王还没打倒，大宝箱就能开（%s）" % str(it0.get("text", ""))):
				return
			var g := w.trip.host_spawn_guard(0)
			if not _check(g != null and g.temper == "elite" and g.hunt_role == "guard" and g.age <= top, "守宝的王不对"):
				return
			_note("守宝的王：%s（血 %d）" % [w.trip.guard_name(0), int(g.max_hp)])
			_mem["gid"] = g.id
			_mem["rings0"] = w.rings.size()
			w.host_skill_damage(g, g.hp + 10.0, Vector3.ZERO, Net.my_id)
			_next(15)
		15:
			if _step_t < 0.6:
				return
			if not _check(w.trip.guard_dead[0], "守宝的王死了，宝箱没解锁"):
				return
			if not _check(w.rings.size() <= int(_mem["rings0"]), "守宝的王掉了灵环（灵环只该从猎物身上来）"):
				return
			var gp2: Vector3 = w.island.guard_spots[0]["pos"]
			w.player.teleport(gp2 + Vector3(0, 0.5, 1.8))
			_next(16)
		16:
			if not _mem.has("opened"):
				if _step_t < 0.4:
					return
				_mem["opened"] = true
				if not w.island.guard_spots.is_empty():
					var money1 := Profile.money
					var it := w.nearest_interactable()
					if not _check(str(it.get("id", "")) == "htchest" and bool(it.get("act", false)), "站在大宝箱旁边打不开（%s）" % str(it.get("text", ""))):
						return
					w.interact()
					if not _check(Profile.money > money1 and w.trip.guard_marks().size() == w.island.guard_spots.size() - 1, "大宝箱没拿到东西 / 地图标记没变"):
						return
					_note("大宝箱：+%d 灵石" % (Profile.money - money1))
				# L 键回岛（F 是神通键）：地上有灵环时要按两次
				_mem["old_wid"] = w.get_instance_id()
				w.trip.key_return()
				if not w.rings.is_empty():
					if not _check(w.trip.back_t < 9000.0, "地上有灵环，按一次 L 就回岛了"):
						return
					w.trip.key_return()
				return
			w = _ready_world()
			if not w or w.get_instance_id() == int(_mem["old_wid"]) or w.island.hunting:
				if _step_t > 15.0:
					_fail("猎灵完了按 L 回不了岛")
				return
			_note("按 L 回到了岛上")
			w.player.invuln_t = 3.0
			_next_phase()


## 猎场失败：全队倒下 3 次 → 猎灵失败 → 回岛
func _run_huntfail() -> void:
	var w := _world()
	match _step:
		0:
			w = _ready_world()
			if not w or _step_t < 1.0:
				return
			var list := w.hunt.species_list()
			w.hunt.request(str(list[0]), w.hunt.base_age())
			_mem["old_wid"] = w.get_instance_id()
			_next(1)
		1:
			w = _ready_world()
			if not w or w.get_instance_id() == int(_mem["old_wid"]) or not w.island.hunting:
				if _step_t > 15.0:
					_fail("没去猎场")
				return
			if _step_t < 2.5:
				return
			for i in 3:
				w.trip.on_my_faint()
			if not _check(w.trip.phase == "fail" and w.trip.faints == 3, "倒下 3 次没失败（%d 次，%s）" % [w.trip.faints, w.trip.phase]):
				return
			_note("全队倒下 3 次：猎灵失败")
			_mem["old_wid"] = w.get_instance_id()
			w.trip.host_return()
			_next(2)
		2:
			w = _ready_world()
			if not w or w.get_instance_id() == int(_mem["old_wid"]) or w.island.hunting:
				if _step_t > 15.0:
					_fail("失败了回不了岛")
				return
			_note("失败后回到了岛上")
			_next_phase()


## 秘境：三个入口 → 进一层 → 三波（测试里自动打死）→ 秘境之主 → 通关：钱、修为、宝箱、纪录、任务 → 从台子离开
## → 再进一次、倒下 → 秘境失败、人回到码头
func _run_dungeon() -> void:
	var w := _ready_world()
	if not w:
		return
	var d := w.dungeon
	var p := w.player
	match _step:
		0:
			if _step_t < 1.0:
				return
			if not _check(d.portals.size() == 3, "秘境入口不是 3 个（%d）" % d.portals.size()):
				return
			var pp: Vector3 = d.portals[0]["pos"]
			var fwd := Basis(Vector3.UP, float(d.portals[0]["yaw"])) * Vector3(0, 0, 3.0)
			# 前一段打灵主时可能被打倒、被海鸥叼走了（看招式随机）：先回码头站起来，不然传送过去马上又被叼回天上
			if p.dead or p.carried:
				_note("上一段被打倒了（dead=%s，被海鸥叼着=%s），先回码头复活" % [p.dead, p.carried])
				w._respawn_at_dock()
			p.teleport(pp + fwd + Vector3(0, 0.4, 0))
			p.invuln_t = 9999.0
			_note("秘境入口：%s" % ", ".join(d.portals.map(func(e): return "%s（%d, %d）" % [d.tier_name(int(e["tier"])), int(e["pos"].x), int(e["pos"].z)])))
			_next(1)
		1:
			if _step_t < 0.4:
				return
			var it := w.nearest_interactable()
			if str(it.get("id", "")) != "dgportal":
				# 诊断：人在哪、什么状态、附近能交互的东西离多远
				var near: Array = []
				for e in w.interactables():
					var dd: float = (e["pos"] as Vector3).distance_to(p.global_position + Vector3(0, 1, 0))
					if dd < 30.0:
						near.append("%s %.1f/%.1f" % [e["id"], dd, float(e["r"])])
				_note("诊断：玩家 %s dead=%s carried=%s 入口 %s 附近 %s" % [p.global_position, p.dead, p.carried, d.portals[0]["pos"], near])
			if not _check(str(it.get("id", "")) == "dgportal", "站在秘境入口没有提示（%s）" % str(it.get("id", ""))):
				return
			_mem["money"] = Profile.money
			_mem["xp"] = Profile.xp + Profile.level * 100000
			_mem["quest"] = w.quest_idx
			_mem["qtype"] = str(w._cur_quest().get("type", ""))
			w.interact()
			_next(2)
		2:
			if not d.inside:
				if _step_t > 3.0:
					_fail("按 F 没进秘境")
				return
			if not _check(d._in_arena(p.global_position) and not d.run.is_empty(), "进秘境后不在场地里"):
				return
			_note("进了%s · 词条 %s" % [d.tier_name(int(d.run["tier"])), Data.DG_MODS[str(d.run["mod"])]["name"]])
			_mem["waves"] = 0
			_mem["walk"] = 0
			_next(20)
		20:
			# 秘境里往东南西北各走 0.7 秒，都要走得动（用户：秘境往右走卡脚——场地在地图外 900 米，被地图边界挡住了）
			var dirs := [["东", -PI / 2], ["北", 0.0], ["西", PI / 2], ["南", PI]]
			var k := int(_mem["walk"])
			if k >= dirs.size():
				Input.action_release("move_forward")
				_note("秘境里东南西北都走得动")
				_next(3)
				return
			if not _mem.has("walk_from"):
				p.look_to(float(dirs[k][1]), 0.0)
				_mem["walk_from"] = p.global_position
				_mem["walk_t"] = _step_t
				Input.action_press("move_forward")
				return
			if _step_t - float(_mem["walk_t"]) < 0.7:
				return
			Input.action_release("move_forward")
			var fwd := Basis(Vector3.UP, float(dirs[k][1])) * Vector3.FORWARD
			var moved := (p.global_position - (_mem["walk_from"] as Vector3)).dot(fwd)
			if not _check(moved > 1.5, "秘境里往%s走不动（只走了 %.1f 米）" % [dirs[k][0], moved]):
				return
			_mem.erase("walk_from")
			_mem["walk"] = k + 1
		3:
			# 测试：场地里出来的灵兽一律秒掉
			for b: Beast in w.beasts.values():
				if b.alive() and b.hunt_role in ["dg", "dgboss"] and b.state != Beast.State.AIR:
					b.last_hitter = Net.my_id
					b.damagers[Net.my_id] = 1.0
					b.hp = 0.0
					w._host_kill(b)
			if not d.run.is_empty() and int(d.run["wave"]) > int(_mem["waves"]):
				_mem["waves"] = int(d.run["wave"])
				_note("第 %d 波" % int(d.run["wave"]))
			if not d.run.is_empty() and str(d.run["phase"]) == "boss" and not _mem.has("boss"):
				_mem["boss"] = true
				var bb: Beast = w.beasts.get(int(d.run["boss"]))
				if not _check(bb != null and bb.hunt_role == "dgboss", "秘境之主没出来"):
					return
				_note("秘境之主：%s，血量 %d" % [bb.display_name(), int(bb.max_hp)])
			if not d.run.is_empty() and str(d.run["phase"]) == "clear":
				_next(4)
			elif _step_t > 90.0:
				_fail("秘境 90 秒没打完（%s）" % str(d.run))
		4:
			if _step_t < 1.0:
				return
			if not _check(Profile.money > int(_mem["money"]) and (Profile.at_bottleneck() or Profile.xp + Profile.level * 100000 > int(_mem["xp"])), "通关没给钱和修为"):
				return
			if not _check(d._chest.visible, "通关没有宝箱"):
				return
			if not _check(d._result != null and d._result.visible, "通关没有结算面板"):
				return
			if not _check(d.best_time(0) > 0, "没记下通关时间"):
				return
			if not _check(str(_mem["qtype"]) != "dungeon" or w.quest_idx > int(_mem["quest"]), "通关秘境没完成任务"):
				return
			_note("通关：+%d 灵石，用时 %d 秒，任务推进到「%s」" % [Profile.money - int(_mem["money"]), d.best_time(0), str(w._cur_quest().get("text", ""))])
			p.teleport(d.spawn_pad() + Vector3(0.5, 0.2, 0))
			_next(5)
		5:
			if _step_t < 0.4:
				return
			var it := w.nearest_interactable()
			if not _check(str(it.get("id", "")) == "dgexit", "进出台没有离开的提示（%s）" % str(it.get("id", ""))):
				return
			w.interact()
			if not _check(not d.inside and not d._in_arena(p.global_position, 10.0), "离开秘境后还在场地里"):
				return
			_note("从台子离开，回到了入口")
			_next(6)
		6:
			if _step_t < 3.5:
				return
			if not _check(d.run.is_empty(), "人都走了秘境还没结束"):
				return
			if not _check(not d._card.visible and not d._result.visible, "出了秘境，左上角 / 中间还挂着秘境的信息"):
				return
			# 三层秘境之主和秘境同年份（以前高一档：千年秘境掉万年灵环）
			d.run = {"tier": 2, "age": d.tier_age(2), "mod": "armor", "phase": "wave", "wave": 3, "t": 0.0, "left": 0, "boss": 0}
			d._start_boss()
			var b3: Beast = w.beasts.get(int(d.run["boss"]))
			if not _check(b3 != null and b3.age == d.tier_age(2), "三层秘境之主年份不对（%d，秘境 %d）" % [b3.age if b3 else -1, d.tier_age(2)]):
				return
			_note("三层秘境之主：%s（和秘境同年份）" % b3.display_name())
			w._remove_beast(b3)
			d.run = {}
			d._sync()
			# 再进一次，然后倒下
			Net.send_host("dgenter", [1])
			_next(7)
		7:
			if not d.inside:
				if _step_t > 3.0:
					_fail("第二次没进去")
				return
			p.invuln_t = 0.0
			p.take_damage(999999.0, p.global_position + Vector3.FORWARD)
			w._respawn_at_dock()
			_next(8)
		8:
			if _step_t < 7.5:
				return
			if not _check(not d.inside and d.run.is_empty() and not d._in_arena(p.global_position, 10.0), "倒下后秘境没结束 / 人还在场地里"):
				return
			_note("在秘境里倒下：回到码头，没人了秘境就失败")
			p.invuln_t = 3.0
			_next_phase()


## 截图：猎灵榜、踪迹、吸收灵环（队友视角）、秘境入口、秘境场地、秘境之主
func _run_dgshot() -> void:
	var w := _ready_world()
	if not w:
		return
	var p := w.player
	var d := w.dungeon
	match _step:
		0:
			if _step_t < 2.0:
				return
			p.invuln_t = 9999.0
			w.hud.open_board()
			_next(1)
		1:
			if _step_t < 1.0:
				return
			_next(2)
			await _shot("hunt_board")
			w.hud._close_board()
		2:
			var fwd := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
			var side := fwd.cross(Vector3.UP)
			for i in 10:
				var q := p.global_position + fwd * (4.0 + i * 2.2) + side * sin(i * 0.7) * 1.5
				q.y = w.island.height_at(q.x, q.z)
				w.hunt._on_fp([q, side])
			_next(3)
		3:
			if _step_t < 1.5:
				return
			_next(4)
			await _shot("hunt_tracks")
		4:
			var fwd := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
			var h := w.hunt
			h.hold = true
			h.channel = {"peer": 999, "age": 1, "species": "rabbit", "pos": p.global_position + fwd * 6.0, "t": 12.0, "dur": 25.0}
			h._on_channel_start()
			_next(5)
		5:
			if _step_t < 1.5:
				return
			_next(6)
			await _shot("hunt_channel")
			w.hunt._channel_visual(false)
			w.hunt.channel = {}
			w.hunt.hold = false
		6:
			var pp: Vector3 = d.portals[0]["pos"]
			var fwd := Basis(Vector3.UP, float(d.portals[0]["yaw"])) * Vector3(0, 0, 9.0)
			p.teleport(pp + fwd + Vector3(0, 0.4, 0))
			_aim(p, pp + Vector3(0, 2.8, 0))
			_next(7)
		7:
			if _step_t < 1.5:
				return
			_next(8)
			await _shot("dungeon_portal")
			Net.send_host("dgenter", [0])
		8:
			if not d.inside or _step_t < 2.0:
				return
			_aim(p, Dungeon.ARENA + Vector3(0, 3.0, -20.0))
			_next(9)
		9:
			if _step_t < 1.5:
				return
			_next(10)
			await _shot("dungeon_arena")
		10:
			# 第一波出来以后拍一张
			if d.run.is_empty() or str(d.run["phase"]) != "wave" or _step_t < 4.0:
				return
			_aim(p, Dungeon.ARENA + Vector3(0, 1.5, -24.0))
			_next(11)
		11:
			if _step_t < 1.0:
				return
			_next(12)
			await _shot("dungeon_wave")
			d._host_start_boss_now()
		12:
			if d.run.is_empty() or str(d.run["phase"]) != "boss" or _step_t < 2.5:
				return
			var bb: Beast = w.beasts.get(int(d.run["boss"]))
			if bb:
				_aim(p, bb.global_position + Vector3(0, 1.5, 0))
			_next(13)
		13:
			if _step_t < 0.8:
				return
			_next(14)
			await _shot("dungeon_boss")
		14:
			_next_phase()




func _fx_impact(fx: Fx, o: Vector3, fwd: Vector3, side: Vector3) -> void:
	for k in 4:
		fx.impact_beast(o + Vector3(randf_range(-1, 1), 1.2 + randf(), randf_range(-1, 1)), -fwd, Color(1.0, 0.3, 0.25), k == 0)
		fx.impact_world(o + side * (k - 1.5) * 1.5, Vector3.UP)


func _fx_burn_bleed(fx: Fx, o: Vector3, side: Vector3, c: Color) -> void:
	fx.empower_hit("burn", o + Vector3.UP * 1.5 + side, c)
	fx.empower_hit("bleed", o + Vector3.UP * 1.5 - side, c)


## 灵兽巢穴：放出来、打掉、爆掉给奖励
func _run_nests() -> void:
	var w := _ready_world()
	if not w:
		return
	match _step:
		0:
			w.nests.setup(w, true)
			if not _check(w.nests.nests.size() > 0, "这张图一个巢都放不下"):
				return
			_note("放了 %d 个巢" % w.nests.nests.size())
			var n: Dictionary = w.nests.nests[0]
			w.player.teleport((n["pos"] as Vector3) + Vector3(0, 0.5, 14))
			_aim(w.player, (n["pos"] as Vector3) + Vector3(0, 2.0, 0))
			_mem["money_n"] = Profile.money
			_next(1)
		1:
			if _step_t < 1.0:
				return
			# 真的开枪打一下（检查碰撞体、命中判定）；传送后镜头位置更新了再瞄
			var n0: Dictionary = w.nests.nests[0]
			_aim(w.player, (n0["pos"] as Vector3) + Vector3(0, 2.0, 0))
			Input.action_press("fire")
			get_tree().create_timer(0.05).timeout.connect(func(): Input.action_release("fire"))
			_next(2)
		2:
			if _step_t < 0.6:
				return
			var n: Dictionary = w.nests.nests[0]
			if not _check(float(n["hp"]) < float(n["max"]), "开枪打巢没掉血"):
				return
			w.nests.host_damage(0, 99999999.0, Net.my_id)
			_next(3)
		3:
			if _step_t < 1.0:
				return
			if not _check(not w.nests.nests[0]["alive"] and Profile.money > int(_mem["money_n"]), "巢打爆了没奖励"):
				return
			_note("巢打爆了，灵石 %d → %d" % [int(_mem["money_n"]), Profile.money])
			_next_phase()


## 倒下：海鸥叼到天上 → 海鸥被打下来 → 掉到地上站起来；再倒一次按空格回码头
func _run_down() -> void:
	var w := _ready_world()
	if not w:
		return
	var p := w.player
	match _step:
		0:
			p.invuln_t = 0.0
			p.take_damage(999999.0, p.global_position + Vector3.FORWARD)
			if not _check(p.dead and p.carried, "倒下后没有被海鸥叼走"):
				return
			_next(1)
		1:
			if _step_t < 5.0:
				return
			var gy: float = w.island.height_at(p.global_position.x, p.global_position.z)
			_note("被叼到离地 %.1f 米" % (p.global_position.y - gy))
			if not _check(p.global_position.y - gy > 10.0, "海鸥没把人叼到天上"):
				return
			w.loot._host_gull_hit(-Net.my_id, Net.my_id)
			_next(2)
		2:
			if not p.dead:
				_note("海鸥被打下来，%.1f 秒后落地站起来了" % _step_t)
				_next(3)
			elif _step_t > 8.0:
				_fail("海鸥被打下来以后人一直没落地复活（还在 %s）" % p.global_position)
		3:
			if _step_t < 1.0:
				return
			p.invuln_t = 0.0
			p.take_damage(999999.0, p.global_position + Vector3.FORWARD)
			w._carry_t = 2.0
			Input.action_press("jump")
			get_tree().create_timer(0.1).timeout.connect(func(): Input.action_release("jump"))
			_next(4)
		4:
			if not p.dead:
				if not _check(p.global_position.distance_to(w.island.spawn) < 8.0, "按空格没有回码头"):
					return
				_note("按空格回码头复活了")
				_next_phase()
			elif _step_t > 4.0:
				_fail("按空格没有回码头复活")


## 新神通：召唤、连锁、黑洞、领域、环绕、附体、神技，每个放一次（周围放几只灵兽当靶子）
const SK2_ALL := ["lyc_dance", "lyc_storm", "lyc_king", "lyc_wall", "lyc_net", "bh_rage", "hf_meteor", "qb_wall", "ls_true", "bh_shen"]
var SK2: Array = SK2_ALL


func _run_skills2() -> void:
	var w := _ready_world()
	if not w:
		return
	var p := w.player
	match _step:
		0:
			var m := w.island.habitat("meadow")
			var c: Vector2 = m["center"]
			p.teleport(Vector3(c.x, w.island.height_at(c.x, c.y) + 0.5, c.y + 10.0))
			p.look_to(0.0, deg_to_rad(-12))
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--skills="):
					SK2 = a.substr(9).split(",")
			Profile.rings = []
			for sid in SK2:
				Profile.rings.append({"age": 3, "skill": sid, "beast": "rabbit"})
			Profile.level = 90
			_mem["sk_i"] = 0
			_next(1)
		1:
			if _step_t < 1.0:
				return
			var i := int(_mem["sk_i"])
			if i >= SK2.size():
				_next(2)
				return
			for k in 5:
				var a := randf() * TAU
				w._host_spawn(1, p.global_position + Vector3(cos(a) * 8.0, 0.5, sin(a) * 8.0 - 6.0), "rabbit", 1, p.global_position, "fierce", "grass", false)
			p.soul = 999.0
			p.hp = 99999.0
			w.skills.cooldowns[i] = 0.0
			w.skills.cast(i)
			_note("放了 %s" % Data.SKILLS[SK2[i]]["name"])
			_mem["sk_i"] = i + 1
			if _shots:
				var nm: String = SK2[i]
				get_tree().create_timer(1.2).timeout.connect(func(): _shot("sk_" + nm))
			if str(Data.SKILLS[SK2[i]]["type"]) == "empower":
				Input.action_press("fire")
				get_tree().create_timer(0.6).timeout.connect(func(): Input.action_release("fire"))
			_step_t = -2.5
		2:
			if _step_t < 3.0:
				return
			_note("新神通都放过了")
			_next_phase()


## 只看 Boss 长什么样（换了自定义模型以后用）：召唤出来，站在岸边看着它拍几张
func _run_bossshot() -> void:
	var w := _ready_world()
	if not w:
		return
	var p := w.player
	match _step:
		0:
			w._host_spawn_boss()
			_next(1)
		1:
			if _step_t < 4.0 or not w.boss:
				return
			var c := w.boss.center()
			var dir := Vector3(-c.x, 0, -c.z).normalized()
			var st := Vector3(c.x, 0, c.z)
			for i in 200:
				st += dir
				if w.island.is_land(st.x, st.z):
					break
			st += dir * 3.0
			# 大个子（朱厌二十多米高）站远一点才拍得全
			var far := maxf(w.boss.size.x, maxf(w.boss.size.y, w.boss.size.z)) * 1.3 + 8.0
			if Vector3(st.x - c.x, 0, st.z - c.z).length() < far:
				st = Vector3(c.x, 0, c.z) + dir * far
			st.y = w.island.height_at(st.x, st.z) + 0.3
			p.teleport(st)
			p.hp = 99999.0
			_aim(p, c)
			_next(2)
		2:
			p.hp = 99999.0
			if w.boss:
				_aim(p, w.boss.center())
			if _step_t > 1.5 and not _mem.has("b1"):
				_mem["b1"] = true
				await _shot("boss_a")
			elif _step_t > 4.0 and not _mem.has("b2"):
				_mem["b2"] = true
				await _shot("boss_b")
			elif _step_t > 7.0 and not _mem.has("b3"):
				_mem["b3"] = true
				await _shot("boss_c")
			elif _step_t > 8.0:
				_next_phase()


## 奇遇 + 海鸥群 + 灵兽独门招式（平时自动测试里关着，这里专门跑一遍）
func _run_events() -> void:
	var w := _ready_world()
	if not w:
		return
	var p := w.player
	match _step:
		0:
			for k in 3:
				w.loot._add_flock_gull([900 + k, Vector3.ZERO, 30.0 + k * 10.0, 28.0, k * 2.0, 0.25, 0.0])
			w._on_tide([w.chapter])
			var ev: Dictionary = Data.CH_EVENTS[w.chapter]
			w._host_tide_spawn(ev)
			w._host_tide_king(ev)
			# 一只凶暴的灵兽放独门招式
			var b := w._host_spawn(1, p.global_position + Vector3(4, 0.5, 0), "bird", 0, p.global_position, "fierce", "grass")
			if b:
				b._sk_cd = 0.0
			_next(1)
		1:
			if _step_t < 4.0:
				return
			w.loot._host_flock_hit(900, Net.my_id)
			_next(2)
		2:
			if _step_t < 1.0:
				return
			if not _check(not w.loot._flock.has(900) or w.loot._flock[900]["dead"], "海鸥打不下来"):
				return
			_note("奇遇、王、海鸥群、灵兽招式都跑过了，没有报错")
			_next_phase()


func _run_boat() -> void:
	var w := _world()
	match _step:
		0:
			w = _ready_world()
			if not w:
				return
			var p := w.player
			var bp := w.builder.boat_pos
			var st := Vector3(w.island.dock_end.x + 0.6, w.island.dock_y + 0.2, bp.z)
			p.teleport(st)
			_aim(p, bp + Vector3(0, 1.0, 0))
			_next(1)
		1:
			if _step_t < 1.0:
				return
			if _shots and not _mem.has("boat_shot"):
				_mem["boat_shot"] = true
				var p := w.player
				p.teleport(Vector3(w.island.dock_end.x - 1.0, w.island.dock_y + 0.2, w.builder.boat_pos.z - 9.0))
				_aim(p, w.builder.boat_pos + Vector3(0, 0.8, 0))
				_step_t = 0.0
				get_tree().create_timer(0.8).timeout.connect(func(): _shot("boat"))
				_step = 0
				return
			var it := w.nearest_interactable()
			if not _check(it.get("id", "") == "boat", "站在船边却没有提示：%s" % it):
				return
			_old_world = w
			_mem["old_chapter"] = w.chapter
			w.interact()
			# 按 F 弹出目的地选择：选下一章
			if not _check(w.hud._boat_picker != null and is_instance_valid(w.hud._boat_picker), "按 F 没弹出目的地选择"):
				return
			w.hud._close_boat_picker()
			w.board(int(Data.CHAPTERS[w.chapter]["next"]))
			_next(2)
		2:
			var nw := _ready_world()
			if nw and nw != _old_world:
				var want := int(Data.CHAPTERS[int(_mem["old_chapter"])]["next"])
				if not _check(nw.chapter == want and nw.island.map_id == str(Data.CHAPTERS[want]["map"]), "坐船后没到第 %d 章" % want):
					return
				if not _check(Profile.chapter == want, "存档章节没更新"):
					return
				_note("到了%s" % Data.CHAPTERS[want]["name"])
				_next_phase()
			elif _step_t > 20.0:
				_fail("坐船 20 秒还没到第二章")


# ------------------------------------------------------------------ 截图游览

func _tour_list(w: World) -> Array:
	var isl := w.island
	var out := []
	var gp := func(x: float, z: float, up: float) -> Vector3:
		return Vector3(x, isl.height_at(x, z) + up, z)
	var tag := isl.map_id
	out.append([tag + "_spawn", null, null])
	var hub := Vector2(isl.spawn.x, isl.spawn.z - 38.0)
	for hb in isl.habitats:
		var c: Vector2 = hb["center"]
		var dir := (hub - c).normalized()
		var st: Vector2 = c + dir * (float(hb["radius"]) + 6.0)
		out.append([tag + "_" + str(hb["type"]), gp.call(st.x, st.y, 1.7), gp.call(c.x, c.y, 1.0)])
	if isl.ancient_tree != Vector3.INF:
		var a := isl.arena
		out.append([tag + "_arena", gp.call(a.x + 4, a.y + 20, 1.7), isl.ancient_tree + Vector3(0, 9, 0)])
	else:
		var h := isl.hill
		out.append([tag + "_altar", gp.call(isl.altar_pos.x + 7, isl.altar_pos.z + 9, 1.7), isl.altar_pos + Vector3(0, 1.5, 0)])
		out.append([tag + "_hill_view", gp.call(h.x, h.y + 6, 1.7), gp.call(0, 50, 0.0)])
	for pd in isl.ponds.slice(0, 1):
		var pc: Vector2 = pd["center"]
		out.append([tag + "_pond", gp.call(pc.x + float(pd["radius"]) + 6, pc.y + 6, 1.7), Vector3(pc.x, 0.5, pc.y)])
	out.append([tag + "_dock", gp.call(isl.dock_start.x + 8, isl.dock_start.z - 4, 1.7), w.builder.boat_pos + Vector3(0, 1, 0)])
	out.append([tag + "_shop", gp.call(isl.shop_pos.x + 3, isl.shop_pos.z + 9, 1.7), isl.shop_pos + Vector3(0, 1.5, 0)])
	return out


## 场景质感对比：同样 4 个机位（出生点、山顶远眺、第一片栖息地、水塘），关掉 HUD
func _run_sceneshot() -> void:
	var w := _ready_world()
	if not w:
		return
	var p := w.player
	match _step:
		0:
			if _step_t < 3.0:
				return
			w.hud.visible = false
			var keep := []
			for e in _tour_list(w):
				var nm := str(e[0])
				if nm.ends_with("_spawn") or nm.ends_with("_hill_view") or nm.ends_with("_pond") or (keep.size() == 1 and e[1] != null):
					keep.append(e)
			_tour = keep
			_next(1)
		1:
			if _tour.is_empty():
				w.hud.visible = true
				p.cam.cull_mask = p.cam.cull_mask | 2
				_next_phase()
				return
			var e: Array = _tour[0]
			if e[1] != null:
				p.teleport((e[1] as Vector3) - Vector3(0, 1.6, 0))
				_aim(p, e[2])
			# 手在第 2 渲染层（灵兽、队友也在这层），拍风景时镜头不画这层
			p.cam.cull_mask = p.cam.cull_mask & ~2
			_next(2)
		2:
			p.hp = 99999.0
			if _step_t < 2.5:
				return
			var e: Array = _tour.pop_front()
			await _shot("scene_" + str(e[0]))
			_next(1)


func _run_tour() -> void:
	var w := _ready_world()
	if not w:
		return
	var p := w.player
	match _step:
		0:
			if _step_t < 3.0:
				return
			_tour = _tour_list(w)
			_next(1)
		1:
			if _tour.is_empty():
				_next_phase()
				return
			var e: Array = _tour[0]
			if e[1] != null:
				p.teleport((e[1] as Vector3) - Vector3(0, 1.6, 0))
				_aim(p, e[2])
			_next(2)
		2:
			if _step_t < 1.8:
				return
			var e: Array = _tour.pop_front()
			await _shot(str(e[0]))
			_next(1)


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
					_note("客人击杀 %d 只，房主灵石 %d、修为 %d" % [w.stats[id]["kills"], Profile.money, Profile.xp])
					if not _check(Profile.xp > 0 or Profile.level > 1, "队友击杀，房主没分到修为"):
						return
					_next(2)
					return
		2:
			if w.remotes.is_empty() or _step_t > 3.0:
				_pass("房主测试通过")


## 联机（房主，--dg=1）：客人进来 → 进一层秘境（客人跟进来）→ 自动秒掉灵兽直到通关
## → 猎灵榜挑一只 → 两个人一起到猎场 → 打倒猎物、结算 → 一起回岛
func _run_dghost() -> void:
	var w := _ready_world()
	if not w:
		return
	var d := w.dungeon
	match _step:
		0:
			if not w.remotes.is_empty():
				_note("客人进来了：%s" % w.remotes.keys())
				w.player.invuln_t = 9999.0
				_next(1)
			elif _t > 40.0:
				_fail("没有客人加入")
		1:
			if _step_t < 2.0:
				return
			Net.send_host("dgenter", [0])
			_next(2)
		2:
			if d.inside and d._members.size() >= 2:
				_note("客人也进了秘境（%d 人）" % d._members.size())
				_next(3)
			elif _step_t > 25.0:
				_fail("客人 25 秒没跟进秘境")
		3:
			for b: Beast in w.beasts.values():
				if b.alive() and b.hunt_role in ["dg", "dgboss"] and b.state != Beast.State.AIR:
					b.last_hitter = Net.my_id if randf() < 0.5 else int(w.remotes.keys()[0])
					b.damagers[b.last_hitter] = 1.0
					b.hp = 0.0
					w._host_kill(b)
			if not d.run.is_empty() and str(d.run["phase"]) == "clear":
				_note("两个人通关了秘境")
				d.leave()
				_next(4)
			elif _step_t > 90.0:
				_fail("两个人 90 秒没打完秘境")
		4:
			# 等两个人都出了秘境，挑猎物去猎场
			if _step_t < 4.0:
				return
			if d.inside or d._members.size() > 0:
				if _step_t > 30.0:
					_fail("出不了秘境（还有 %d 人在里面）" % d._members.size())
				return
			var list := w.hunt.species_list()
			w.hunt.request(str(list[0]), w.hunt.base_age())
			_mem["old_wid"] = w.get_instance_id()
			_next(5)
		5:
			if w.get_instance_id() == int(_mem["old_wid"]) or not w.island.hunting or w.remotes.is_empty() or w.hunt.target_id == 0:
				if _step_t > 40.0:
					_fail("两个人没一起到猎场（猎场 %s，客人 %d）" % [w.island.hunting, w.remotes.size()])
				return
			w.player.invuln_t = 9999.0
			if _step_t < 4.0:
				return
			_note("两个人都到了猎场，猎物出现了")
			var b: Beast = w.beasts[w.hunt.target_id]
			b.last_hitter = int(w.remotes.keys()[0])
			b.damagers[b.last_hitter] = 1.0
			b.damagers[Net.my_id] = 1.0
			b.hp = 0.0
			w._host_kill(b)
			_next(6)
		6:
			if w.trip.phase != "done":
				if _step_t > 5.0:
					_fail("打倒猎物没结算")
				return
			if _step_t < 4.0:
				return
			_note("猎灵结算：评级 %s" % str(w.trip.result["rating"]))
			_mem["old_wid"] = w.get_instance_id()
			w.trip.host_return()
			_next(7)
		7:
			if w.get_instance_id() == int(_mem["old_wid"]) or w.island.hunting:
				if _step_t > 30.0:
					_fail("回不了岛")
				return
			if w.remotes.is_empty():
				if _step_t > 30.0:
					_fail("回岛以后客人没回来")
				return
			_note("两个人一起回到了岛上")
			_next(8)
		8:
			if w.remotes.is_empty() or _step_t > 10.0:
				_pass("联机房主测试通过")


## 联机（客人，--dg=1）：房主开了秘境，从入口跟进去 → 通关拿到奖励 → 离开
## → 房主挑了猎物，自己也被带到猎场、看得到猎物 → 结算拿到报酬 → 跟着回岛
func _run_dgclient() -> void:
	var w := _ready_world()
	if not w:
		return
	var d := w.dungeon
	match _step:
		0:
			w.player.invuln_t = 9999.0
			_next(1)
		1:
			if d.run.is_empty():
				if _step_t > 40.0:
					_fail("客人没看到房主开的秘境")
				return
			var tier := int(d.run["tier"])
			var pp: Vector3 = d.portals[tier]["pos"]
			w.player.teleport(pp + Basis(Vector3.UP, float(d.portals[tier]["yaw"])) * Vector3(0, 0, 3.0) + Vector3(0, 0.4, 0))
			_next(2)
		2:
			if _step_t < 0.5:
				return
			var it := w.nearest_interactable()
			if not _check(str(it.get("id", "")) == "dgportal" and bool(it.get("act", false)), "客人在入口不能进（%s）" % str(it.get("text", ""))):
				return
			_mem["money"] = Profile.money
			w.interact()
			_next(3)
		3:
			if d.inside:
				_note("客人进了秘境：%s" % d.tier_name(int(d.run["tier"])))
				_next(4)
			elif _step_t > 8.0:
				_fail("客人按 F 没进秘境")
		4:
			if not d.run.is_empty() and str(d.run["phase"]) == "clear" and Profile.money > int(_mem["money"]):
				_note("客人拿到了通关奖励：+%d 灵石" % (Profile.money - int(_mem["money"])))
				d.leave()
				_next(5)
			elif _step_t > 100.0:
				_fail("客人 100 秒没等到通关")
		5:
			var tb: Beast = w.beasts.get(w.hunt.target_id) if w.hunt.target_id != 0 else null
			if not w.island.hunting or tb == null:
				if _step_t > 60.0:
					_fail("客人没跟着到猎场 / 没看到猎物")
				return
			w.player.invuln_t = 9999.0
			_note("客人也到了猎场，看到了猎物：%s" % tb.display_name())
			_mem["money"] = Profile.money
			_next(6)
		6:
			if w.trip == null or w.trip.phase != "done":
				if _step_t > 40.0:
					_fail("客人没收到猎灵结算")
				return
			if not _check(Profile.money > int(_mem["money"]), "客人没拿到猎灵报酬"):
				return
			_note("客人拿到了猎灵报酬：+%d 灵石（评级 %s）" % [Profile.money - int(_mem["money"]), str(w.trip.result["rating"])])
			_next(7)
		7:
			if w.island.hunting:
				if _step_t > 40.0:
					_fail("客人没跟着回岛")
				return
			_note("客人跟着回到了岛上")
			_next_phase()



# ------------------------------------------------------------------ 第十二版：新暗器、配件、熟练度、皮肤、自己画

## 一只不会动、打不死的靶子
func _dummy(w: World, pos: Vector3) -> Beast:
	pos.y = w.island.height_at(pos.x, pos.z) + 0.9
	# 山魈：个子大、身上没有甲（铁甲兕打身子只吃一成多伤害，测出来的数不准）
	var b: Beast = w._host_spawn_wild(pos, "ape", 1, "flee")
	if b:
		b.affixes.clear()
		b.max_hp = 1000000.0
		b.hp = b.max_hp
		b.freeze = true
		b.global_position = pos
	return b


func _dummy_center(b: Beast) -> Vector3:
	return b.global_position + Vector3(0, 0.35, 0)


## 队友的样子（截图）：在面前放一个假的队友，站着、走、跑、蹲各拍一张
## 过场动画在游戏里播出来的样子（视频 + 标题 / 字幕叠层），每段截几张
const CINES := [["prologue", "", [4.0, 16.0, 30.0, 44.0]], ["voyage_2", "", [2.0, 6.0]], ["voyage_5", "", [6.0]], ["dungeon", "洞天秘境 · 千年 · 二层", [2.5]],
	["hunt", "猎场 · 万年铁钳蟹王", [2.5]], ["ascend", "", [6.0, 14.0, 22.0]]]


func _run_cineshot() -> void:
	match _step:
		0:
			_mem["ci"] = 0
			_next(1)
		1:
			var ci := int(_mem["ci"])
			if ci >= CINES.size():
				_next_phase()
				return
			var c: Array = CINES[ci]
			var v := Voyage.new()
			v.video = "res://assets/cutscene/%s.ogv" % c[0]
			v.title = str(c[1])
			v.length = 60.0
			main.add_child(v)
			_mem["v"] = v
			_mem["si"] = 0
			_next(2)
		2:
			var c2: Array = CINES[int(_mem["ci"])]
			var times: Array = c2[2]
			var si := int(_mem["si"])
			if si >= times.size():
				var v2: Voyage = _mem["v"]
				if is_instance_valid(v2):
					v2._finish()
				_mem["ci"] = int(_mem["ci"]) + 1
				_next(1)
				return
			if _step_t >= float(times[si]):
				_mem["si"] = si + 1
				_shot("cine_%s_%d" % [c2[0], si])


func _run_mateshot() -> void:
	var w := _ready_world()
	if not w:
		return
	var p := w.player
	match _step:
		0:
			var m := RemotePlayer.new()
			w.add_child(m)
			m.setup(w, 99, {"name": "青崖", "wuhun": 5, "level": 42, "rings": [0, 1, 1, 2], "outfit": "default", "skin": "default"})
			_mem["mate"] = m
			_mem["base"] = p.global_position + Vector3(0, 0, -4.0)
			_mem["k"] = 0
			_next(1)
		1:
			var m: RemotePlayer = _mem["mate"]
			var base: Vector3 = _mem["base"]
			var k := int(_mem["k"])
			var poses := [["idle", 0.0, 1], ["walk", 2.5, 1], ["run", 7.0, 3], ["crouch", 0.0, 9], ["side", 5.0, 3]]
			if k >= poses.size():
				m.queue_free()
				_next_phase()
				return
			var pose: Array = poses[k]
			var spd := float(pose[1])
			# 在人面前绕圈走（能看到侧面和正面）
			var a := _step_t * spd * 0.35
			var pos: Vector3 = base + Vector3(sin(a) * 1.5 if spd > 0.0 else 0.0, 0, 0)
			pos.y = w.island.height_at(pos.x, pos.z)
			var yaw := PI * 0.5 if spd > 0.0 else PI + 0.5
			if str(pose[0]) == "side":
				yaw = PI * 0.5
			m.push_snapshot([pos, yaw, 0.0, "zhuge", int(pose[2]), 0, Vector3.ZERO, 100.0, 1.0, 1.0])
			_aim(p, base + Vector3(0, 1.1, 0))
			if _step_t > 1.6 and not _mem.has("shot%d" % k):
				_mem["shot%d" % k] = true
				_shot("mate_" + str(pose[0]))
			if _step_t > 2.0:
				_mem["k"] = k + 1
				_step_t = 0.0


## 第十三版 Boss 招式：五个 Boss 轮流出来，每一招都放一遍（不报错、招式真的出来）；
## 圈砸到人会掉血、翻滚躲过去算极限闪避；破绽时打头伤害翻倍
const ARTS := {"mandala": ["sweep", "spit", "coil", "dive", "sweep2", "swamp"], "spider": ["web", "lunge", "drop", "brood", "lunge2", "cage"],
	"titan": ["rocks", "charge", "quake", "fists", "rockrain", "charge2", "stomp", "stomp2"], "icedragon": ["breath", "spiral", "swoop", "shards"],
	"whale": ["tsunami", "vortex", "breach", "geyser", "gaze", "storm"]}


func _run_bossarts() -> void:
	var w := _ready_world()
	if not w:
		return
	var p := w.player
	var kinds: Array = ARTS.keys()
	match _step:
		0:
			_mem["ki"] = 0
			_next(1)
		1:
			# 出下一个 Boss
			var ki := int(_mem["ki"])
			if ki >= kinds.size():
				_next(9)
				return
			var kind := str(kinds[ki])
			if w.boss:
				w.boss.queue_free()
				w.boss = null
			w._on_boss_spawn([kind, 9.0e7, w.island.boss_pos, 0])
			_mem["ai"] = 0
			_mem["tel"] = 0
			_next(2)
		2:
			var b := w.boss
			if _step_t < 3.5:
				return
			# 上一个 Boss 把人打倒了、还被海鸥叼在天上：先回码头复活（不然站位后马上又被叼走）
			if p.dead or p.carried or w._carry_t >= 0.0:
				w._respawn_at_dock()
			# 人站在 Boss 旁边 16 米（水里的 Boss：岸上）
			var c := b.center()
			var dir := Vector3(-c.x, 0, -c.z).normalized()
			# 大个子的 Boss 离远一点（不然人会被放到它身上）
			var want := 16.0 + maxf(b.size.x, b.size.z) * 0.7
			var st := Vector3(c.x, 0, c.z) + dir * want
			# 在 Boss 周围一圈圈找最近的陆地（Boss 大了以后，只朝一个方向找会走到 90 米仇恨范围外面去）
			var found := false
			for ring in 12:
				for k in 24:
					var ang := atan2(dir.z, dir.x) + TAU * k / 24.0
					var q := Vector3(c.x, 0, c.z) + Vector3(cos(ang), 0, sin(ang)) * (want + ring * 5.0)
					if w.island.is_land(q.x, q.z):
						st = q
						found = true
						break
				if found:
					break
			st.y = w.island.height_at(st.x, st.z) + 0.3
			p.teleport(st)
			_mem["stand"] = st
			_mem["bpos"] = b.head.global_position
			p.hp = Profile.max_hp()
			p.invuln_t = 0.0
			_next(3)
		3:
			# 一招一招放
			var b := w.boss
			var list: Array = ARTS[b.kind]
			var ai := int(_mem["ai"])
			# 被打倒过：走正规的回码头复活（只 revive 的话倒地计时还在走，过几秒会被自动送回码头）
			if p.dead or p.carried or w._carry_t >= 0.0:
				w._respawn_at_dock()
				p.teleport(_mem["stand"])
				p.invuln_t = 0.0
			p.hp = Profile.max_hp()
			if not b._act.is_empty() or b.stun_t > 0.0 or b.state != "idle":
				if _step_t > 12.0:
					_fail("%s 的招 %s 卡住了（state=%s act=%s stun=%.1f）" % [b.kind, str(list[maxi(ai - 1, 0)]), b.state, str(b._act), b.stun_t])
				b.stun_t = minf(b.stun_t, 0.3)
				return
			if _step_t < 0.6 and ai > 0:
				return
			if ai >= list.size():
				_note("%s：%s 都放出来了（预警 %d 个）" % [Data.BOSSES[b.kind]["name"], "、".join(list), int(_mem["tel"])])
				_next(4)
				return
			var n0 := w.arts._lanes.size() + w.arts._sweeps.size() + w.arts._circles.size() + w.arts._walls.size() + w.arts._vortexes.size() + w._hazards.size() + w._waves.size()
			b.phase = 2 if ai >= 4 else 1
			b.force_art = str(list[ai])
			b._busy = 0.0
			b._sp_cd = 0.0
			b._ult_cd = 99.0
			b._ult_ready = false
			b._moves(0.016)
			_mem["ai"] = ai + 1
			_mem["n0"] = n0
			_step_t = 0.0
			_next(5)
		5:
			# 等这一招真的出来（预警 / 冲锋 / 潜水 / 召唤）
			var b := w.boss
			var n := w.arts._lanes.size() + w.arts._sweeps.size() + w.arts._circles.size() + w.arts._walls.size() + w.arts._vortexes.size() + w._hazards.size() + w._waves.size()
			var ok := n > int(_mem["n0"]) or not b._act.is_empty() or b.state != "idle" or b.stun_t > 0.0
			if ok:
				_mem["tel"] = int(_mem["tel"]) + maxi(n - int(_mem["n0"]), 0)
				if _shots:
					# 截图：看着 Boss，等招式出来一点再拍
					_aim(p, b.center())
					var nm := "art_%s_%s" % [b.kind, str(ARTS[b.kind][int(_mem["ai"]) - 1])]
					get_tree().create_timer(0.9).timeout.connect(func(): _shot(nm))
				_next(3)
				_step_t = 0.0
			elif _step_t > 1.5:
				_fail("%s 的招 %s 没放出来（人离 Boss %.0f 米，能打的人 %d 个，state=%s）" % [b.kind, str(ARTS[b.kind][int(_mem["ai"]) - 1]), p.global_position.distance_to(b.head.global_position), b._targets().size(), b.state])
		4:
			# 砸到人掉血；翻滚躲过算极限闪避；破绽打头 ×2
			var b := w.boss
			b._busy = 99.0
			if not _mem.has("hurt") and not _mem.has("hurt_wait"):
				w.arts.clear_all()
				if p.dead or p.carried or w._carry_t >= 0.0:
					w._respawn_at_dock()
				# 砸人、闪避这两下在出生点测（Boss 冲锋、落石会把人推到奇怪的地方）
				b.head.global_position = _mem["bpos"]
				p.teleport(w.island.spawn + Vector3(0, 0.5, 0))
				p.velocity = Vector3.ZERO
				p.hp = Profile.max_hp()
				p.invuln_t = 0.0
				_mem["hp0"] = p.hp
				_mem["hurt_wait"] = true
				_step_t = 0.0
				return
			if _mem.has("hurt_wait"):
				if _step_t < 0.5:
					return
				_mem.erase("hurt_wait")
				p.invuln_t = 0.0
				p.hp = Profile.max_hp()
				_mem["hp0"] = p.hp
				w.arts.circle(p.global_position, 4.0, 0.4, 40.0, "rock")
				_mem["hurt"] = true
				_step_t = 0.0
				return
			if not _mem.has("dodge") and _step_t < 1.2:
				return
			if not _mem.has("dodge"):
				# 前面招式的余波（推飞、倒地被海鸥叼走）偶尔让这一下落空：重来两次
				if p.hp >= float(_mem["hp0"]) and int(_mem.get("retry", 0)) < 2:
					_mem["retry"] = int(_mem.get("retry", 0)) + 1
					_mem.erase("hurt")
					return
				if not _check(p.hp < float(_mem["hp0"]), "%s：圈砸到人没掉血（hp %.0f，dead=%s，invuln %.2f，位置 %s）" % [b.kind, p.hp, p.dead, p.invuln_t, p.global_position]):
					return
				_mem.erase("retry")
				p.hp = Profile.max_hp()
				p.velocity = Vector3.ZERO
				_mem["pd0"] = int(Profile.stats.get("perfect_dodges", 0))
				_mem["dc"] = p.global_position
				_mem["dodge"] = true
				if p.dead or p.carried or w._carry_t >= 0.0:
					w._respawn_at_dock()
					p.teleport(_mem["dc"])
				p.hp = Profile.max_hp()
				# 翻滚中挨一下（和圈砸到人走的是同一条路）
				p._roll_t = 0.42
				p.invuln_t = 0.36
				p._pd_cd = 0.0
				var hp1 := p.hp
				w.arts._hurt(40.0, p.global_position + Vector3(2, 0, 0), Vector3.ZERO)
				if not _check(p.hp >= hp1, "%s：翻滚的无敌时间里还掉血了" % b.kind):
					return
				_step_t = 0.0
				return
			if _step_t < 0.3:
				return
			if not _check(int(Profile.stats.get("perfect_dodges", 0)) > int(_mem["pd0"]) and p.buff("dmg") >= 0.3, "%s：翻滚躲过去没有极限闪避（次数 %d→%d，buff %.2f，hp %.0f/%.0f，圈 %d，圈心 %s 人 %s 地面 %.1f）" % [b.kind, int(_mem["pd0"]), int(Profile.stats.get("perfect_dodges", 0)), p.buff("dmg"), p.hp, Profile.max_hp(), w.arts._circles.size(), _mem["dc"], p.global_position, w.island.height_at(p.global_position.x, p.global_position.z)]):
				return
			var h0 := b.hp
			b.stun_t = 0.0
			var d1 := b.take_hit(100.0, true, Net.my_id)
			w.arts.stun(b, 2.0)
			var d2 := b.take_hit(100.0, true, Net.my_id)
			if not _check(d2 > d1 * 1.9, "%s：破绽时打头没有翻倍（%.0f → %.0f）" % [b.kind, d1, d2]):
				return
			b.hp = h0
			b.stun_t = 0.0
			b._busy = 0.0
			for k in ["hurt", "dodge", "rolled"]:
				_mem.erase(k)
			p.buffs.erase("dmg")
			_mem["ki"] = int(_mem["ki"]) + 1
			_next(1)
		9:
			if w.boss:
				w.boss.queue_free()
				w.boss = null
			w.arts.clear_all()
			w.hud.boss_bar("")
			_note("五个 Boss 的招式、破绽、极限闪避都没问题")
			_next_phase()


## 丹药（代替烤肉 / 饱食度）和散魂丹：4 号位轮换、每种丹药的效果、散掉一个灵环再补上同一个位置
func _run_pills() -> void:
	var w := _ready_world()
	if not w:
		return
	var p := w.player
	match _step:
		0:
			if not _check(bool(Data.ITEMS["meat"].get("hidden", false)), "烤肉还在卖"):
				return
			for id in Data.PILL_ORDER:
				Profile.items[id] = 2
			p.select_slot(3)
			var first := p.cur_pill()
			p.select_slot(3)
			if not _check(p.cur_pill() != first, "再按 4 没换丹药（%s）" % first):
				return
			p.soul = 1.0
			p.eat_pill("soul_pill")
			if not _check(p.soul > Profile.max_soul() * 0.5, "回魂丹没回灵力（%.0f）" % p.soul):
				return
			p.eat_pill("haste_pill")
			p.eat_pill("guard_pill")
			p.eat_pill("rage_pill")
			p.eat_pill("giant_pill")
			if not _check(p.buff("speed") >= 0.35 and p.buff("dr") >= 0.4 and p.buff("dmg") >= 0.4 and p._giant_t > 0.0, "丹药的效果不对（%s，巨灵 %.1f）" % [str(p.buffs), p._giant_t]):
				return
			if not _check(Profile.item_count("rage_pill") == 1, "吃了丹药没扣"):
				return
			_note("丹药：4 号位轮换，回魂 / 疾风 / 金刚 / 破境 / 巨灵 都生效（%s）" % str(p.buffs.keys()))
			# 散魂丹：三个假灵环，散掉第二个，再补上
			_mem["saved"] = [Profile.rings.duplicate(true), Profile.skill_slots.duplicate(), Profile.level, Profile.ring_hole]
			Profile.rings = [{"age": 0, "skill": "lyc_root", "beast": "rabbit"}, {"age": 1, "skill": "lyc_mark", "beast": "bird"}, {"age": 1, "skill": "lyc_pull", "beast": "moth"}]
			Profile.skill_slots = [0, 1, 2]
			Profile.level = 35
			Profile.ring_hole = -1
			Profile.items["scatter_pill"] = 0
			if not _check(Profile.remove_ring(1) != "", "没有散魂丹也能散灵环"):
				return
			Profile.items["scatter_pill"] = 1
			if not _check(Profile.remove_ring(1) == "" and Profile.rings.size() == 2 and Profile.ring_hole == 1, "散灵环不对（%d 个，洞 %d）" % [Profile.rings.size(), Profile.ring_hole]):
				return
			if not _check(Profile.skill_slots == [0, -1, 1], "散掉以后神通槽不对（%s）" % str(Profile.skill_slots)):
				return
			if not _check(Profile.next_ring_index() == 1 and Profile.can_absorb(1) == "", "散掉的位置补不上（%s）" % Profile.can_absorb(1)):
				return
			w.rings_changed()
			Profile.add_ring(1, "lyc_spike", "wolf")
			if not _check(Profile.rings.size() == 3 and str(Profile.rings[1]["skill"]) == "lyc_spike" and Profile.ring_hole == -1 and Profile.skill_slots == [0, 1, 2], "补上的灵环位置不对（%s，%s）" % [str(Profile.rings), str(Profile.skill_slots)]):
				return
			_note("散魂丹：散掉第二灵环，猎一只补回第二灵环的位置，神通槽跟着对上")
			var sv: Array = _mem["saved"]
			Profile.rings = sv[0]
			Profile.skill_slots = sv[1]
			Profile.level = int(sv[2])
			Profile.ring_hole = int(sv[3])
			w.rings_changed()
			p.select_slot(1)
			_next_phase()


func _run_guns2() -> void:
	var w := _ready_world()
	if not w:
		return
	var p := w.player
	match _step:
		0:
			Profile.add_money(900000)
			for id in ["meihua", "longxu", "zimu", "hansha", "guanyin"]:
				if not _check(Profile.buy_weapon(id), "买不了 %s" % id):
					return
				w.on_bought_weapon(id)
			# 在草地上摆靶子（别的地图没有草地就在码头边）
			var m := w.island.habitat("meadow")
			var c: Vector2 = m.get("center", Vector2(w.island.spawn.x, w.island.spawn.z))
			var base := Vector3(c.x, 0, c.y)
			p.teleport(Vector3(base.x, w.island.height_at(base.x, base.z) + 0.5, base.z))
			p.look_to(0.0, 0.0)
			var dm := {}
			dm["A"] = _dummy(w, base + Vector3(0, 0, -12))
			for i in 3:
				dm["B%d" % i] = _dummy(w, base + Vector3(-7.0 + (i - 1) * 1.6, 0, -18))
			dm["C0"] = _dummy(w, base + Vector3(5, 0, -9))
			dm["C1"] = _dummy(w, base + Vector3(9, 0, -16.2))
			for k in dm:
				if not _check(dm[k] != null, "靶子 %s 没刷出来" % k):
					return
			_mem["dm"] = dm
			_note("买了五把新暗器，一共 %d 把（含空手）" % p.guns.size())
			_switch_to(p, "meihua")
			_next(1)
		1:
			# 寒梅袖箭：扣一下出三箭
			if _step_t < 0.6:
				return
			var a: Beast = _mem["dm"]["A"]
			_aim(p, _dummy_center(a))
			if not _mem.has("mh0"):
				_mem["mh0"] = p.gun.ammo
				_mem["hp0"] = a.hp
				p.fire_buffer = 0.2
				return
			if _step_t < 1.2:
				return
			var shots: int = int(_mem["mh0"]) - p.gun.ammo
			_note("寒梅袖箭扣一下出了 %d 箭，靶子掉血 %d" % [shots, int(float(_mem["hp0"]) - a.hp)])
			if not _check(shots == 3, "寒梅袖箭一次应该出 3 箭，出了 %d" % shots):
				return
			if not _check(a.hp < float(_mem["hp0"]), "寒梅袖箭没打中靶子"):
				return
			_switch_to(p, "hansha")
			_next(2)
		2:
			# 流沙机弩：按住越打越快
			if _step_t < 0.6:
				return
			var a2: Beast = _mem["dm"]["A"]
			_aim(p, _dummy_center(a2))
			if not _mem.has("hs_iv0"):
				_mem["hs_iv0"] = p.gun.interval()
				Input.action_press("fire")
				_mem["hs_t"] = _step_t
				return
			if _step_t - float(_mem["hs_t"]) < 1.8:
				return
			var iv1: float = p.gun.interval()
			Input.action_release("fire")
			_note("流沙机弩：刚开火每发 %.3f 秒，转起来 %.3f 秒（转速 %.2f）" % [float(_mem["hs_iv0"]), iv1, p.gun.heat])
			if not _check(p.gun.heat > 0.85 and iv1 < float(_mem["hs_iv0"]) * 0.6, "流沙机弩没有越打越快"):
				return
			_switch_to(p, "guanyin")
			_next(3)
		3:
			# 天心泪：轻点一下 vs 蓄满
			if _step_t < 0.6:
				return
			var a3: Beast = _mem["dm"]["A"]
			_aim(p, _dummy_center(a3))
			if not _mem.has("gy_tap"):
				# 开着镜打，两发都落在身子上（不然一发爆头一发打身子，比不出蓄力的倍数）
				if not _mem.has("gy_ads"):
					_mem["gy_ads"] = true
					Input.action_press("aim")
					_mem["gy_t0"] = _step_t
					return
				if _step_t - float(_mem["gy_t0"]) < 0.5:
					return
				_mem["gy_tap"] = true
				_mem["gy_hp"] = a3.hp
				Input.action_press("fire")
				get_tree().create_timer(0.05).timeout.connect(func(): Input.action_release("fire"))
				_mem["gy_t"] = _step_t
				return
			if not _mem.has("gy_d1"):
				if _step_t - float(_mem["gy_t"]) < 0.8:
					return
				_mem["gy_d1"] = float(_mem["gy_hp"]) - a3.hp
				_mem["gy_hp"] = a3.hp
				Input.action_press("fire")
				_mem["gy_t"] = _step_t
				return
			if not _mem.has("gy_full"):
				if _step_t - float(_mem["gy_t"]) < 1.3:
					return
				_mem["gy_full"] = p.gun.charge
				Input.action_release("fire")
				_mem["gy_t"] = _step_t
				return
			if _step_t - float(_mem["gy_t"]) < 0.6:
				return
			Input.action_release("aim")
			var d2 := float(_mem["gy_hp"]) - a3.hp
			_note("天心泪：轻点 %d，蓄满（%.2f）%d" % [int(float(_mem["gy_d1"])), float(_mem["gy_full"]), int(d2)])
			if not _check(float(_mem["gy_full"]) >= 0.99, "天心泪按住 1.3 秒没蓄满"):
				return
			if not _check(float(_mem["gy_d1"]) > 0.0 and d2 > float(_mem["gy_d1"]) * 3.5, "天心泪蓄满的伤害不够（轻点 %d，蓄满 %d）" % [int(float(_mem["gy_d1"])), int(d2)]):
				return
			_switch_to(p, "zimu")
			_next(4)
		4:
			# 子母雷珠：打中间那只，三只都挨炸，子胆也炸
			if _step_t < 0.6:
				return
			var dm2: Dictionary = _mem["dm"]
			var mid: Beast = dm2["B1"]
			_aim(p, mid.global_position - Vector3(0, 0.3, 0))
			if not _mem.has("zm"):
				_mem["zm"] = [(dm2["B0"] as Beast).hp, mid.hp, (dm2["B2"] as Beast).hp]
				p.fire_buffer = 0.2
				_mem["zm_t"] = _step_t
				return
			if _step_t - float(_mem["zm_t"]) < 1.4:
				return
			var hs: Array = _mem["zm"]
			var lost: Array = []
			for i in 3:
				lost.append(int(float(hs[i]) - (dm2["B%d" % i] as Beast).hp))
			_note("子母雷珠：三只靶子各掉 %s" % str(lost))
			for i in 3:
				if not _check(int(lost[i]) > 0, "爆炸没炸到第 %d 只（%s）" % [i + 1, str(lost)]):
					return
			_switch_to(p, "longxu")
			_next(5)
		5:
			# 追星针：一针穿两只
			if _step_t < 0.6:
				return
			var dm3: Dictionary = _mem["dm"]
			var c0: Beast = dm3["C0"]
			var c1: Beast = dm3["C1"]
			var eye := p.cam.global_position
			_aim(p, _dummy_center(c0))
			if not _mem.has("lx_fired"):
				# 两只靶子排在一条线上：开枪前每帧把后面那只按住在线上（以前放下去就往下掉，偶尔打空）
				var want := eye + (_dummy_center(c0) - eye) * 1.8
				c1.global_position += want - _dummy_center(c1)
				c1.linear_velocity = Vector3.ZERO
			if not _mem.has("lx"):
				# 开镜打（腰射有散布，远的那只偶尔打不到）
				Input.action_press("aim")
				_mem["lx"] = [c0.hp, c1.hp]
				_mem["lx_t"] = _step_t
				return
			if not _mem.has("lx_fired"):
				if _step_t - float(_mem["lx_t"]) < 0.5:
					return
				_mem["lx_fired"] = true
				p.fire_buffer = 0.2
				return
			if _step_t - float(_mem["lx_t"]) < 1.1:
				return
			Input.action_release("aim")
			var l0 := float(_mem["lx"][0]) - c0.hp
			var l1 := float(_mem["lx"][1]) - c1.hp
			_note("追星针穿透：第一只掉 %d，后面那只掉 %d" % [int(l0), int(l1)])
			if not _check(l0 > 0.0 and l1 > 0.0, "追星针没有穿透两只"):
				return
			_next(6)
		6:
			# 熟练度、配件
			var r0 := float(Profile.weapon_stats("kongque")["reload"])
			var lv := Profile.add_mastery("kongque", 400)
			var r1 := float(Profile.weapon_stats("kongque")["reload"])
			_note("流光翎熟练度 → %d 级，换弹 %.2f → %.2f 秒" % [Profile.mastery_level("kongque"), r0, r1])
			if not _check(lv >= 3 and r1 < r0, "熟练度升级没有加成"):
				return
			if not _check(Profile.owns_skin("kongque", "steel") and not Profile.owns_skin("zhuge", "steel"), "熟练度皮肤应该只给练到的那把"):
				return
			var base := Data.weapon_stats("kongque", {})
			for a in ["extmag", "lstock", "silencer"]:
				if not _check(Profile.buy_attach("kongque", a), "买不了配件 %s" % a):
					return
			var st := Profile.weapon_stats("kongque")
			_note("流光翎装扩容弹匣 + 轻型枪托 + 消音器：弹匣 %d，开镜 %.2f 秒，消音 %s" % [int(st["mag"]), float(st["ads_time"]), str(st.get("quiet", false))])
			if not _check(int(st["mag"]) == int(round(float(base["mag"]) * 1.5)) and float(st["ads_time"]) < float(base["ads_time"]) and bool(st.get("quiet", false)), "新配件数值不对"):
				return
			w.on_attach_changed()
			_next(7)
		7:
			# 每把暗器 × 每款皮肤都能搭出来；自己画的皮肤；挂件
			var n := 0
			for id in Data.WEAPON_ORDER:
				for sid in Data.GUN_SKIN_ORDER:
					var mdl := WeaponModels.build(str(id), str(sid), "default", {}, false, "")
					var sm := 0
					for mi in mdl.find_children("*", "MeshInstance3D", true, false):
						if GunSkin.is_skin_mat((mi as MeshInstance3D).material_override):
							sm += 1
					mdl.free()
					if not _check(sm > 3, "%s 穿 %s 没有质感材质" % [id, sid]):
						return
					n += 1
			var img := Image.create_empty(GunSkin.PAINT_W, GunSkin.PAINT_H, false, Image.FORMAT_RGBA8)
			img.fill_rect(Rect2i(100, 60, 200, 80), Color(1, 0.2, 0.1, 1))
			GunSkin.save_paint("kongque", img)
			Profile.wear_skin("kongque", "paint")
			var painted := WeaponModels.build("kongque", "", "default", {}, false, "")
			var on := false
			for mi in painted.find_children("*", "MeshInstance3D", true, false):
				var mat := (mi as MeshInstance3D).material_override
				if GunSkin.is_skin_mat(mat) and float((mat as ShaderMaterial).get_shader_parameter("paint_on")) > 0.5:
					on = true
			painted.free()
			if not _check(Profile.skin_for("kongque") == "paint" and on, "自己画的皮肤没穿上"):
				return
			if not _check(Profile.buy_charm("tassel"), "买不了挂件"):
				return
			Profile.set_charm("kongque", "tassel")
			var ch := WeaponModels.build("kongque")
			var has_charm := ch.get_node_or_null("Charm") != null
			ch.free()
			if not _check(has_charm, "挂件没挂上"):
				return
			_note("%d 个暗器 × 皮肤组合都搭得出来；自己画的皮肤、挂件都在" % n)
			w.on_look_changed()
			_switch_to(p, "kongque")
			_next(8)
		8:
			# 暗器铺外观页：3D 预览、打开画板画一笔、保存
			if _step_t < 0.4:
				return
			if not _mem.has("shop_open"):
				_mem["shop_open"] = true
				w.hud.open_shop()
				var sp: ShopPanel = w.hud._shop
				sp._tab = "looks"
				sp._pick_weapon = "kongque"
				sp.refresh()
				return
			var sp2: ShopPanel = w.hud._shop
			if not _mem.has("paint_open"):
				if not _check(sp2._preview != null and sp2._preview.model != null, "外观页没有 3D 预览"):
					return
				_mem["paint_open"] = true
				sp2._open_paint("kongque")
				return
			if _step_t < 1.5:
				return
			if not _check(sp2._paint != null and sp2._paint.visible, "画板没打开"):
				return
			var pp: PaintPanel = sp2._paint
			pp._push_undo()
			pp._stroke(Vector2(50, 50), Vector2(400, 180))
			pp._stamp_at(Vector2(256, 128))
			pp._commit()
			pp._save()
			if not _check(not pp.visible and GunSkin.has_paint("kongque"), "画完保存不了"):
				return
			w.hud.close_panels()
			_note("外观页 3D 预览、画板画一笔、保存都没问题")
			# 靶子收掉（后面的测试还在这张图上）
			for k in _mem["dm"]:
				var db: Beast = _mem["dm"][k]
				if is_instance_valid(db) and db.alive():
					w.beast_escaped(db, "despawn")
			_mem.erase("dm")
			Input.action_release("fire")
			Input.action_release("aim")
			_next_phase()


## 截图：新暗器第一人称（检视姿势，看得到侧面的质感）、几款皮肤、外观页、画板
var _gs_list: Array = []


func _run_gunshots() -> void:
	var w := _ready_world()
	if not w:
		return
	var p := w.player
	match _step:
		0:
			Profile.add_money(900000)
			for id in Data.WEAPON_ORDER:
				if not Profile.has_weapon(str(id)):
					Profile.buy_weapon(str(id))
			for sid in Data.GUN_SKIN_ORDER:
				if Data.GUN_SKINS[sid].has("price") and int(Data.GUN_SKINS[sid]["price"]) > 0:
					Profile.buy_look("skin", str(sid))
			Profile.mastery["kongque"] = 5000
			p.rebuild_guns()
			var m := w.island.habitat("meadow")
			var c: Vector2 = m["center"]
			p.teleport(Vector3(c.x, w.island.height_at(c.x, c.y) + 0.5, c.y))
			p.look_to(0.6, deg_to_rad(8))
			_gs_list = [["meihua", "default"], ["longxu", "dragon"], ["zimu", "magma"], ["hansha", "circuit"], ["guanyin", "pearl"],
				["kongque", "chrome"], ["kongque", "damascus"], ["kongque", "fade"], ["kongque", "star"], ["kongque", "master"],
				["zhuge", "carbon"], ["zhuihun", "jade"], ["xiujian", "ice"], ["baoyu", "shadow"]]
			_next(1)
		1:
			if _gs_list.is_empty():
				_next(3)
				return
			var e: Array = _gs_list[0]
			Profile.wear_skin(str(e[0]), str(e[1]))
			w.on_look_changed()
			_switch_to(p, str(e[0]))
			_next(2)
		2:
			if _step_t < 0.9:
				return
			if not _mem.has("insp"):
				_mem["insp"] = true
				p.viewmodel.inspect()
				return
			if _step_t < 1.9:
				return
			_mem.erase("insp")
			var e2: Array = _gs_list.pop_front()
			await _shot("gun_%s_%s" % [e2[0], e2[1]])
			_next(1)
		3:
			if not _mem.has("shop"):
				_mem["shop"] = true
				w.hud.open_shop()
				var sp: ShopPanel = w.hud._shop
				sp._tab = "looks"
				sp._pick_weapon = "kongque"
				sp._look_skin = "fade"
				sp.refresh()
				return
			if _step_t < 1.5:
				return
			await _shot("shop_looks")
			var sp2: ShopPanel = w.hud._shop
			sp2._tab = "weapons"
			sp2.refresh()
			_next(4)
		4:
			if _step_t < 0.8:
				return
			await _shot("shop_weapons")
			var sp3: ShopPanel = w.hud._shop
			sp3._tab = "attach"
			sp3._pick_weapon = "kongque"
			sp3.refresh()
			_next(5)
		5:
			if _step_t < 0.8:
				return
			await _shot("shop_attach")
			var sp4: ShopPanel = w.hud._shop
			sp4._tab = "looks"
			sp4.refresh()
			sp4._open_paint("zhuge")
			var pp: PaintPanel = sp4._paint
			pp._push_undo()
			pp.pcol = Color(0.1, 0.6, 1.0)
			pp.brush = 30.0
			pp._stroke(Vector2(20, 60), Vector2(500, 90))
			pp.pcol = Color(1.0, 0.8, 0.2)
			pp.stamp = "star"
			pp._stamp_at(Vector2(300, 120))
			pp._commit()
			_next(6)
		6:
			if _step_t < 1.5:
				return
			await _shot("paint_panel")
			var sp5: ShopPanel = w.hud._shop
			sp5._paint._save()
			w.hud.close_panels()
			_switch_to(p, "zhuge")
			_next(7)
		7:
			if _step_t < 0.9:
				return
			if not _mem.has("insp2"):
				_mem["insp2"] = true
				p.viewmodel.inspect()
				return
			if _step_t < 1.9:
				return
			await _shot("gun_zhuge_painted")
			_next_phase()


# ------------------------------------------------------------------ 只看第一人称手和暗器（渲染很快）

var _vm: ViewModel
var _vm_list: Array = []


func _setup_vm() -> void:
	var root := Node3D.new()
	add_child(root)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.6, 0.5)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.7)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -140, 0)
	sun.light_energy = 1.3
	root.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = Settings.vertical_fov(Settings.fov)
	cam.near = 0.01
	root.add_child(cam)
	cam.make_current()
	_vm = ViewModel.new()
	cam.add_child(_vm)
	_vm_list = Array(Data.WEAPON_ORDER).duplicate()


func _run_vm() -> void:
	match _step:
		0:
			if _vm_list.is_empty():
				_pass("暗器模型截图完成")
				return
			_vm.set_weapon(str(_vm_list[0]), true)
			_next(1)
		1:
			_vm.update(0.016, 0.0, 0.0, true, -1.0, 0.0, 0.0, false, false)
			if _step_t > 0.5:
				var id: String = _vm_list.pop_front()
				await _shot("vm_" + id)
				_next(0)


# ------------------------------------------------------------------ 把所有灵兽模型摆成一排看朝向和大小

func _setup_zoo() -> void:
	var root := Node3D.new()
	add_child(root)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.62, 0.7)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.75)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 60)
	ground.mesh = pm
	ground.material_override = U.mat(Color(0.35, 0.45, 0.3))
	root.add_child(ground)
	var files: Array = []
	for f in DirAccess.get_files_at("res://assets/models/creatures"):
		if f.ends_with(".gltf") or f.ends_with(".fbx"):
			files.append(f)
	files.sort()
	var cols := 7
	for i in files.size():
		var f: String = files[i]
		var ps: PackedScene = load("res://assets/models/creatures/" + f)
		var inst: Node3D = ps.instantiate()
		var holder := Node3D.new()
		holder.position = Vector3((i % cols) * 6.0 - 18.0, 0, (i / cols) * 7.0 - 10.0)
		root.add_child(holder)
		holder.add_child(inst)
		# 缩放到大约 2.5 米大小
		var acc := [null]
		_zoo_aabb(inst, Transform3D.IDENTITY, acc)
		var a: AABB = acc[0]
		var k := 2.5 / maxf(a.size.x, maxf(a.size.y, a.size.z))
		inst.scale = Vector3.ONE * k
		inst.position = -Vector3(a.get_center().x, a.position.y, a.get_center().z) * k
		var aps := inst.find_children("*", "AnimationPlayer", true, false)
		if aps.size() > 0:
			var ap: AnimationPlayer = aps[0]
			var names := ap.get_animation_list()
			for n in names:
				if "Idle" in n or "Swim" in n or "Flying" in n:
					ap.play(n)
					break
		# 红色箭头指向 -Z（游戏里的“前方”）
		var arrow := U.part(holder, U.box(Vector3(0.15, 0.15, 1.6)), U.glow(Color(1, 0.1, 0.1), 2.0), Vector3(0, 0.05, -2.0))
		arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var l := U.label3d(f.get_basename(), 64, Color.WHITE)
		l.position = Vector3(0, 3.2, 0)
		l.pixel_size = 0.01
		holder.add_child(l)
	var cam := Camera3D.new()
	cam.fov = 60
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 34, 22), Vector3(0, 0, -1), Vector3.UP)
	cam.make_current()


func _zoo_aabb(n: Node, xf: Transform3D, acc: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var a: AABB = t * (n as MeshInstance3D).mesh.get_aabb()
		acc[0] = a if acc[0] == null else (acc[0] as AABB).merge(a)
	for c in n.get_children():
		_zoo_aabb(c, t, acc)


# ------------------------------------------------------------------ 量模型：正交相机从侧面和上面拍，数像素

var _m_files: Array = []
var _m_cam: Camera3D
var _m_holder: Node3D
var _m_info := {}


func _setup_measure() -> void:
	var root := Node3D.new()
	add_child(root)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(1, 0, 1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.8)
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 40, 0)
	root.add_child(sun)
	_m_cam = Camera3D.new()
	_m_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	root.add_child(_m_cam)
	_m_cam.make_current()
	_m_holder = Node3D.new()
	root.add_child(_m_holder)
	for f in DirAccess.get_files_at("res://assets/models/creatures"):
		if f.ends_with(".gltf") or f.ends_with(".fbx"):
			_m_files.append(f)
	_m_files.sort()


func _run_measure() -> void:
	match _step:
		0:
			if _m_files.is_empty():
				var fa := FileAccess.open(_shots_dir + "/frames.json", FileAccess.WRITE)
				fa.store_string(JSON.stringify(_m_info))
				_pass("量完了")
				return
			for c in _m_holder.get_children():
				c.free()
			var f: String = _m_files[0]
			var inst: Node3D = (load("res://assets/models/creatures/" + f) as PackedScene).instantiate()
			_m_holder.add_child(inst)
			var acc := [null]
			_zoo_aabb(inst, Transform3D.IDENTITY, acc)
			var a: AABB = acc[0]
			var ext := maxf(a.size.x, maxf(a.size.y, a.size.z)) * 3.0
			_m_info[f.get_basename()] = {"size": ext, "cx": a.get_center().x, "cy": a.get_center().y, "cz": a.get_center().z}
			_m_cam.size = ext
			_m_cam.far = ext * 10.0
			_m_cam.look_at_from_position(a.get_center() + Vector3(ext * 2.0, 0, 0), a.get_center(), Vector3.UP)
			_next(1)
		1:
			if _step_t > 0.3:
				await _shot("side_" + str(_m_files[0]).get_basename())
				var c: Vector3 = Vector3(_m_info[str(_m_files[0]).get_basename()]["cx"], _m_info[str(_m_files[0]).get_basename()]["cy"], _m_info[str(_m_files[0]).get_basename()]["cz"])
				var ext: float = _m_cam.size
				_m_cam.look_at_from_position(c + Vector3(0, ext * 2.0, 0), c, Vector3.FORWARD)
				_next(2)
		2:
			if _step_t > 0.3:
				await _shot("top_" + str(_m_files[0]).get_basename())
				_m_files.pop_front()
				_next(0)

# ------------------------------------------------------------------ 试炼：尸潮守关 / 万兽割草

## 最近的僵尸的胸口（瞄准用）
func _horde_target(T: Trial, from: Vector3) -> Vector3:
	var best := Vector3.INF
	var bd := INF
	for u in T.horde.units:
		var q: Vector3 = u["p"]
		var d := q.distance_to(from)
		if d < bd:
			bd = d
			best = q + Vector3.UP * 1.1 * float(Horde.SCALE[int(u["kind"])])
	return best


## 瞄着最近的僵尸开一枪（走真的开枪流程：World.local_fire → Trial.shot）
func _horde_shoot(p: Player, T: Trial) -> void:
	var tg := _horde_target(T, p.global_position)
	if tg == Vector3.INF:
		return
	_aim(p, tg)
	p.gun.ammo = maxi(p.gun.ammo, 5)
	p.gun.reloading = false
	if p.gun.fire_cd <= 0.0 and p.switch_t <= 0.0:
		p._fire()


func _trial_enter(w: World, T: Trial, m: String) -> bool:
	var p := w.player
	if p.dead or p.carried:
		w._respawn_at_dock()
	match _step:
		0:
			if not _check(T.stele != Vector3.INF, "岛上没有试炼碑"):
				return false
			p.teleport(T.stele + Vector3(0, 0.6, 2.2))
			p.invuln_t = 9999.0
			_next(1)
		1:
			if _step_t < 0.5:
				return false
			var it := w.nearest_interactable()
			if not _check(str(it.get("id", "")) == "trstele", "站在试炼碑前没有「按 F 打开试炼」（最近的是 %s）" % str(it.get("id", ""))):
				return false
			w.interact()
			if not _check(w.hud._trial_picker != null and is_instance_valid(w.hud._trial_picker), "按 F 没打开试炼面板"):
				return false
			w.hud._close_trial_picker()
			T.request(m)
			_next(2)
		2:
			if not T.inside:
				if _step_t > 3.0:
					_fail("点了%s没进去" % Trial.MODES[m]["name"])
				return false
			var c := T.center()
			if not _check(Vector2(p.global_position.x - c.x, p.global_position.z - c.z).length() < 12.0, "没传送到%s的场地" % Trial.MODES[m]["name"]):
				return false
			_note("进了试炼 · %s" % Trial.MODES[m]["name"])
			return true
	return false


## 握把标定：每把暗器从右侧正交看（z 横着、y 竖着），画 5 厘米的格子和坐标，红点 = 右手 GripR，蓝点 = 左手 GripL
func _run_gripshot() -> void:
	var w := _ready_world()
	if not w:
		return
	match _step:
		0:
			if _step_t < 1.0:
				return
			var cam := Camera3D.new()
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = 0.95
			cam.near = 0.01
			cam.far = 20.0
			w.add_child(cam)
			var base := w.player.global_position + Vector3(0, 60.0, 0)
			cam.global_position = base + Vector3(3.0, 0, 0)
			cam.look_at(base, Vector3.UP)
			cam.current = true
			var holder := Node3D.new()
			w.add_child(holder)
			holder.global_position = base
			# 背景板 + 格子
			var bg := U.part(holder, U.box(Vector3(0.01, 3, 3)), U.mat(Color(0.3, 0.32, 0.36), 1.0), Vector3(-0.8, 0, 0))
			bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for k in range(-10, 11):
				var v := k * 0.05
				var col := Color(0.55, 0.58, 0.62) if k % 2 != 0 else Color(0.8, 0.82, 0.85)
				U.part(holder, U.box(Vector3(0.002, 0.002 if k != 0 else 0.004, 1.0)), U.glow(col, 0.6), Vector3(-0.7, v, 0))
				U.part(holder, U.box(Vector3(0.002, 1.0, 0.002 if k != 0 else 0.004)), U.glow(col, 0.6), Vector3(-0.7, 0, v))
				if k % 2 == 0:
					var lz := U.label3d("%.1f" % v, 22, Color.WHITE, 0)
					lz.billboard = BaseMaterial3D.BILLBOARD_ENABLED
					lz.pixel_size = 0.0012
					lz.position = Vector3(-0.6, -0.44, v)
					holder.add_child(lz)
					var ly := U.label3d("%.1f" % v, 22, Color.WHITE, 0)
					ly.billboard = BaseMaterial3D.BILLBOARD_ENABLED
					ly.pixel_size = 0.0012
					ly.position = Vector3(-0.6, v, 0.44)
					holder.add_child(ly)
			_mem["gs_cam"] = cam
			_mem["gs_holder"] = holder
			_mem["gs_list"] = Array(Data.WEAPON_ORDER).duplicate()
			_next(1)
		1:
			var lst: Array = _mem["gs_list"]
			var holder: Node3D = _mem["gs_holder"]
			if _mem.has("gs_gun"):
				(_mem["gs_gun"] as Node).queue_free()
				_mem.erase("gs_gun")
			if lst.is_empty():
				(_mem["gs_cam"] as Node).queue_free()
				holder.queue_free()
				w.player.cam.current = true
				_next_phase()
				return
			var id := str(lst[0])
			var g := WeaponModels.build(id, "default", "default", {}, true, "")
			holder.add_child(g)
			for mk in g.find_children("Grip*", "", true, false):
				var col := Color(1, 0.2, 0.2) if mk.name == "GripR" else Color(0.2, 0.5, 1)
				U.part(mk as Node3D, U.sphere(0.012, 10, 8), U.glow(col, 3.0), Vector3.ZERO)
				# 手指方向 a（短棍）
				var a: Vector3 = (mk as Node3D).get_meta("a", Vector3.FORWARD)
				var st := U.part(mk as Node3D, U.cyl(0.003, 0.003, 0.06, 6), U.glow(col, 2.0), a.normalized() * 0.03)
				st.basis = Basis(Quaternion(Vector3.UP, a.normalized()))
				st.position = a.normalized() * 0.03
			_mem["gs_gun"] = g
			_next(2)
		2:
			if _step_t < 0.4:
				return
			var id := str((_mem["gs_list"] as Array).pop_front())
			_next(1)
			await _shot("grip_%s" % id)


## 第一人称的手（FPArms）：几把暗器各截三张——正常第一人称、从右边看手、从前面看手（另放一个镜头，看手指有没有握住）
func _run_fpshot() -> void:
	var w := _ready_world()
	if not w:
		return
	var p := w.player
	match _step:
		0:
			if _step_t < 1.5:
				return
			Profile.add_money(900000)
			for id in ["zhuge", "kongque", "hansha"]:
				if not Profile.has_weapon(id):
					Profile.buy_weapon(id)
			p.rebuild_guns()
			var m := w.island.habitat("meadow")
			var c: Vector2 = m["center"]
			p.teleport(Vector3(c.x, w.island.height_at(c.x, c.y) + 0.5, c.y))
			p.look_to(0.6, deg_to_rad(4))
			_mem["fp_list"] = ["xiujian", "zhuge", "kongque", "fist"]
			_next(1)
		1:
			var lst: Array = _mem["fp_list"]
			if lst.is_empty():
				if _mem.has("fp_cam"):
					(_mem["fp_cam"] as Node).queue_free()
				p.cam.current = true
				_next_phase()
				return
			_switch_to(p, str(lst[0]))
			_next(2)
		2:
			if _step_t < 1.3:
				return
			var id := str((_mem["fp_list"] as Array)[0])
			p.cam.current = true
			_next(3)
			await _shot("fp_%s_view" % id)
		3:
			var cam: Camera3D = _mem.get("fp_cam")
			if cam == null:
				cam = Camera3D.new()
				cam.fov = 40.0
				cam.near = 0.01
				w.add_child(cam)
				_mem["fp_cam"] = cam
			var ct := p.cam.global_transform
			var look := ct * Vector3(0.1, -0.2, -0.32)
			cam.global_position = ct * Vector3(0.75, -0.05, -0.3)
			cam.look_at(look, ct.basis.y)
			cam.current = true
			_next(4)
		4:
			if _step_t < 0.1:
				return
			var id := str((_mem["fp_list"] as Array)[0])
			_next(5)
			await _shot("fp_%s_side" % id)
		5:
			var cam: Camera3D = _mem["fp_cam"]
			var ct := p.cam.global_transform
			cam.global_position = ct * Vector3(0.05, -0.12, -1.05)
			cam.look_at(ct * Vector3(0.08, -0.22, -0.3), ct.basis.y)
			_next(6)
		6:
			if _step_t < 0.1:
				return
			var id := str((_mem["fp_list"] as Array)[0])
			_next(7)
			await _shot("fp_%s_front" % id)
			(_mem["fp_list"] as Array).pop_front()
			p.cam.current = true
			_next(1)


## 样板狩猎（KingFeel）：去猎场 → 按住猎物 → 打尾巴直到断（模型上那截没了、地上掉一截、摔一跤、拿到部位材料）
## → 打头攒晕值直到倒地 5 秒 → 怒气满了暴怒 → 暴怒完了累（变慢、不放大招、血少能活捉）。shots 模式下每一步截图
func _run_feel() -> void:
	var w := _world()
	match _step:
		0:
			w = _ready_world()
			if not w or _step_t < 1.0:
				return
			Profile.level = 10
			var h := w.hunt
			var list := h.species_list()
			if not _check(not list.is_empty(), "猎灵榜上没有灵兽"):
				return
			var sp := str(list[0])
			for s in list:
				if str(s) in ["wolf", "deer", "rhino", "ape"]:
					sp = str(s)
					break
			_mem["sp"] = sp
			w.player.invuln_t = 9999.0
			h.request(sp, h.base_age())
			_mem["old_wid"] = w.get_instance_id()
			_next(1)
		1:
			w = _ready_world()
			if not w or w.get_instance_id() == int(_mem["old_wid"]) or not w.island.hunting:
				if _step_t > 15.0:
					_fail("挑了猎物没去猎场")
				return
			var h := w.hunt
			if h.target_id == 0 or not w.beasts.has(h.target_id):
				if _step_t > 20.0:
					_fail("猎物没出现")
				return
			var b: Beast = w.beasts[h.target_id]
			if not _check(b.feel != null and b.feel.parts.size() == 3, "猎物身上没有 KingFeel / 部位不是 3 个"):
				return
			_mem["bid"] = b.id
			w.player.invuln_t = 9999.0
			w.player.hp = 99999.0
			# 按住它（root_t）：站着挨打；侧面 11 米看
			b.root_t = 9999.0
			b.root_pos = b.global_position
			var side := b.global_basis * b.feel._front.cross(Vector3.UP)
			var at := b.global_position + side.normalized() * 11.0
			at.y = w.island.height_at(at.x, at.z) + 0.4
			w.player.teleport(at)
			_aim(w.player, b.global_position + Vector3.UP * 0.8)
			_note("猎物 %s：部位 %s，头朝 %s，晕值上限 %.0f" % [b.display_name(), str(b.feel.parts.keys()), str(b.feel._front), b.feel.stun_max])
			_next(2)
		2:
			if _step_t < 1.5:
				return
			var b: Beast = w.beasts.get(int(_mem["bid"]))
			var f: KingFeel = b.feel
			# 传送以后镜头才到位：这时候再瞄
			_aim(w.player, b.global_position + Vector3.UP * 0.4)
			# 打尾巴：一枪两成血（尾巴只有一成六）
			var lp := f._center - f._front * f._half * 0.9
			var before := int(Profile.parts.get("%s|tail" % b.species, 0))
			b.take_hit(b.max_hp * 0.2, Vector3.ZERO, lp, false, Net.my_id, 10.0)
			if not _check(f.broken("tail") and f.down_t > 2.0, "尾巴打了两成血没断 / 没摔倒（%s）" % str(f.parts["tail"])):
				return
			if not _check(int(Profile.parts.get("%s|tail" % b.species, 0)) == before + 1, "断尾没拿到部位材料"):
				return
			if not _check(not f.allows("slam"), "断了尾巴还能放震地"):
				return
			_note("断尾：摔倒 %.1f 秒，部位材料 +1，震地没了" % f.down_t)
			_next(3)
		3:
			if _step_t < 0.35:
				return
			_next(4)
			await _shot("feel_tail_break")
		4:
			if _step_t < 1.2:
				return
			_next(5)
			await _shot("feel_toppled")
		5:
			var b: Beast = w.beasts.get(int(_mem["bid"]))
			var f: KingFeel = b.feel
			f.down_t = 0.0
			f.host_tick(0.01)
			# 打头攒晕值：一次打一成的三分之一，最多 6 下一定晕
			var hp0 := b.hp
			var n := 0
			while f.down_t <= 0.0 and n < 6:
				b.take_hit(f.stun_max * 0.4, Vector3.ZERO, f._center + f._front * f._half, true, Net.my_id, 10.0)
				n += 1
			if not _check(f.down_t > 4.0 and f.stuns == 1, "打头 %d 下没晕（晕值 %.0f / %.0f）" % [n, f.stun, f.stun_max]):
				return
			# 倒地时打头更痛
			var h1 := b.hp
			b.take_hit(10.0, Vector3.ZERO, f._center + f._front * f._half, true, Net.my_id, 10.0)
			var dealt := h1 - b.hp
			if not _check(dealt > 20.0, "倒地时打头没有加伤（10 → %.1f）" % dealt):
				return
			_note("打头 %d 下晕倒 %.1f 秒（掉了 %.0f 血）；倒地时打头 10 → %.1f" % [n, f.down_t, hp0 - b.hp, dealt])
			_next(6)
		6:
			if _step_t < 0.8:
				return
			_next(7)
			await _shot("feel_stunned")
		7:
			var b: Beast = w.beasts.get(int(_mem["bid"]))
			var f: KingFeel = b.feel
			f.down_t = 0.0
			b._aggro_t = 10.0
			f.rage = 99.9
			f.host_tick(0.2)
			if not _check(f.mood == "rage" and b.enrage_t > 20.0, "怒气满了没暴怒（%s）" % f.mood):
				return
			f.host_tick(KingFeel.RAGE_TIME + 0.1)
			if not _check(f.mood == "tired" and f.speed_k() < 0.7 and not f.allows("pounce"), "暴怒完了没累 / 累了还放大招"):
				return
			b.hp = b.max_hp * 0.3
			if not _check(f.capturable(), "累了、三成血还不能活捉"):
				return
			_note("怒气满了暴怒 %d 秒，完了累 %d 秒：速度 ×%.2f，不放大招，三成血能活捉" % [int(KingFeel.RAGE_TIME), int(KingFeel.TIRED_TIME), f.speed_k()])
			_next(8)
		8:
			if _step_t < 1.5:
				return
			_next(9)
			await _shot("feel_tired")
			var b: Beast = w.beasts.get(int(_mem["bid"]))
			if b:
				b.root_t = 0.0
			_next_phase()


## 僵尸受击反馈截图：一排 5 只跳尸，轻打 / 重打 / 打死两只，命中后 0.12 秒（后仰、后退）和 0.47 秒（尸体倒下）各一张
func _run_kbshot() -> void:
	var w := _ready_world()
	if not w:
		return
	var T := w.trial
	var p := w.player
	p.hp = 99999.0
	p.invuln_t = 9999.0
	match _step:
		0:
			T.request("chase")
			_next(1)
		1:
			if not T.inside:
				if _step_t > 4.0:
					_fail("进不了尸潮追击")
				return
			T._phase_t = 999.0
			T.horde.clear()
			p.teleport(Trial.CHASE + Vector3(0, 0.5, -2.0))
			var list: Array = []
			for i in 5:
				list.append([0, Trial.CHASE.x - 4.0 + i * 2.0, Trial.CHASE.z - 9.0, 1, 100.0])
			T.horde.host_spawn(list)
			_aim(p, Trial.CHASE + Vector3(0, 1.2, -9.0))
			_next(2)
		2:
			if _step_t < 1.2:
				return
			var us: Array = T.horde.units
			if us.size() < 5:
				_fail("僵尸没出来")
				return
			var ids := []
			for u in us:
				ids.append(int(u["id"]))
			var hp0 := float(us[1]["hp"])
			T.horde.apply_hits([[ids[0], 15.0, Net.my_id], [ids[1], 45.0, Net.my_id], [ids[3], 150.0, Net.my_id], [ids[4], 150.0, Net.my_id]])
			if not _check(T.horde.units.size() == 3 and (T.horde.by_id[ids[1]] as Dictionary).get("kb", Vector3.ZERO).length() > 1.0, "挨打没有后退速度 / 没打死"):
				return
			_note("受击：重打那只 hp %.0f → %.0f，后退初速 %.1f" % [hp0, float(T.horde.by_id[ids[1]]["hp"]), (T.horde.by_id[ids[1]]["kb"] as Vector3).length()])
			_next(3)
		3:
			if _step_t < 0.12:
				return
			_next(4)
			await _shot("kb_hit")
		4:
			if _step_t < 0.35:
				return
			_next(5)
			await _shot("kb_fall")
			T.leave()
			_next_phase()


func _run_chase() -> void:
	var w := _ready_world()
	if not w:
		return
	var T := w.trial
	var p := w.player
	if _step < 3:
		if _trial_enter(w, T, "chase"):
			_next(3)
		return
	if _step != 5 and _step < 12:
		p.hp = 99999.0
	match _step:
		3:
			if T.racks.is_empty() or str(T.racks[0]["id"]) == "":
				if _step_t > 3.0:
					_fail("兵器架上没有暗器")
				return
			if not _check(T.racks.size() == 3 + 2 * (Trial.GATES.size() + 1), "兵器架数量不对（%d）" % T.racks.size()):
				return
			# 每个架子的暗器都带瞄具；后面守点的品质更高、配件更多
			for r in T.racks:
				var on: Dictionary = r["on"]
				if not _check(on.has("sight"), "兵器架上的 %s 没有瞄具（%s）" % [str(r["id"]), str(on)]):
					return
			var last: Dictionary = T.racks[T.racks.size() - 1]
			if not _check(int(last["q"]) >= 2 and (last["on"] as Dictionary).size() >= 2, "渡口的兵器架品质 / 配件太少（%s）" % str(last)):
				return
			var id := str(T.racks[0]["id"])
			T.pick_rack(0)
			if not _check(p.trial_gun == id and p.gun.id == id, "捡了兵器架上的 %s，手里没有它" % id):
				return
			if not _check(p.trial_attach == T.racks[0]["on"] and p.viewmodel.attach_override.has(id), "捡的暗器没带上配件（%s）" % str(p.trial_attach)):
				return
			_note("捡起%s%s" % [T.rack_name(0), T.rack_attach_text(0)])
			_note("渡口兵器架：%s%s" % [T.rack_name(T.racks.size() - 1), T.rack_attach_text(T.racks.size() - 1)])
			T._phase_t = 0.0
			p.invuln_t = 0.0     # 无敌（进场时测试开的）的人不算"能打的人"，不刷僵尸
			_next(4)
		4:
			if str(T.run.get("phase", "")) != "run" or T.horde.alive_count() == 0:
				if _step_t > 12.0:
					_fail("僵尸没出来（%s）" % str(T.run))
				return
			_note("开跑：%d 只僵尸冒出来了" % T.horde.alive_count())
			p.hp = Profile.max_hp()
			p.invuln_t = 0.0
			_mem["hp"] = p.hp
			_next(5)
		5:
			# 站着不动：僵尸会跳过来咬人
			if p.hp < float(_mem["hp"]) - 0.5 or p.dead:
				_note("僵尸扑过来咬人了：体力 %d → %d" % [int(_mem["hp"]), int(p.hp)])
				p.hp = 99999.0
				_next(6)
			elif _step_t > 30.0:
				_fail("30 秒没有僵尸咬到人（场上 %d 只）" % T.horde.alive_count())
		6:
			# 开枪：挨打的僵尸飘伤害数字、头上有血条（hit_t 归零）
			var labels := w.fx.get_children().filter(func(c): return c is Label3D).size()
			_mem["lab"] = labels
			_horde_shoot(p, T)
			var hit := false
			for u in T.horde.units:
				if float(u["hit_t"]) < 0.5 and float(u["hp"]) < float(u["max"]):
					hit = true
			var labels2 := w.fx.get_children().filter(func(c): return c is Label3D).size()
			if hit or T.my_kills > 0:
				if not _check(labels2 > 0, "打中僵尸没飘伤害数字"):
					return
				_note("打中僵尸：飘了伤害数字，血条出来了（斩 %d）" % T.my_kills)
				_next(7)
			elif _step_t > 20.0:
				_fail("打了 20 秒没打中僵尸")
		7:
			# 走进第一关守点：开始守
			p.teleport(T.zone_center(0) + Vector3(0, 0.5, 0))
			if str(T.run.get("phase", "")) == "hold":
				_note("到了第一道城门前：开始守（要守 %d 秒）" % int(Trial.HOLD[0]))
				_next(8)
			elif _step_t > 5.0:
				_fail("走进守点没开始守（%s）" % str(T.run))
		8:
			var cp := int(T.run.get("cp", 0))
			if not T.run.is_empty() and str(T.run.get("phase", "")) == "hold":
				T.run["hold"] = maxf(float(T.run["hold"]), float(Trial.HOLD[mini(cp, 3)]) - 0.3)
			if cp >= 1:
				var sb: StaticBody3D = T._gate_nodes[0][2]
				if not _check((sb.get_child(0) as CollisionShape3D).disabled, "守住了城门没打开（碰撞还在）"):
					return
				if not _check(T.horde.bounds.position.y < Trial.GATES[1] + 1.0, "开了门，僵尸的活动范围没往前挪（%s）" % str(T.horde.bounds)):
					return
				_note("第一道城门开了：现在第 %d 关" % (cp + 1))
				_next(9)
			elif _step_t > 8.0:
				_fail("守够时间城门没开（%s）" % str(T.run))
		9:
			# 第二关：有尸王
			var cp2 := int(T.run.get("cp", 0))
			p.teleport(T.zone_center(cp2) + Vector3(0, 0.5, 0))
			if str(T.run.get("phase", "")) == "hold":
				var kings := T.horde.units.filter(func(u): return int(u["kind"]) == 3).size()
				if not _check(kings >= 1, "第二关守点没有尸王"):
					return
				_note("第二关：尸王来了（%d 只）" % kings)
				_next(10)
			elif _step_t > 5.0:
				_fail("第二关守点没开始守（%s）" % str(T.run))
		10:
			# 一路守到渡口
			var cp3 := int(T.run.get("cp", 0))
			if T.run.is_empty():
				if not _check(T._result != null and T._result.visible and T.best("chase") == Trial.GATES.size() + 1, "逃出去了没结算 / 纪录（%d）" % T.best("chase")):
					return
				_note("守到渡船靠岸：逃出生天！纪录「%s」" % T.best_text("chase"))
				_next(11)
				return
			p.teleport(T.zone_center(cp3) + Vector3(0, 0.5, 0))
			if str(T.run.get("phase", "")) == "hold":
				T.run["hold"] = maxf(float(T.run["hold"]), float(Trial.HOLD[mini(cp3, 3)]) - 0.3)
			if _step_t > 25.0:
				_fail("25 秒没守到渡口（%s）" % str(T.run))
		11:
			if T.inside:
				if _step_t > 9.0:
					_fail("结算完没送回岛上")
				return
			if not _check(p.trial_gun == "" and p.viewmodel.attach_override.is_empty(), "出了试炼，捡的暗器没还回去"):
				return
			_note("送回试炼碑，捡的暗器还回去了")
			T.request("chase")
			_next(12)
		12:
			# 再来一局：续命用完就失败
			if not T.inside or str(T.run.get("phase", "")) == "":
				if _step_t > 4.0:
					_fail("第二局没进去")
				return
			T._phase_t = 0.0
			# 准备阶段倒下不扣续命：等开跑了再倒
			if str(T.run.get("phase", "")) != "run":
				return
			T.run["lives"] = 0
			p.invuln_t = 0.0
			p.hp = 1.0
			p.take_damage(1e6, p.global_position + Vector3(0, 0, -2))
			_next(13)
		13:
			if T.run.is_empty():
				if not _check(T._result != null and T._result.visible, "续命用完没结算"):
					return
				_note("续命用完：失败结算（倒在第一关）")
				_next(14)
			elif _step_t > 10.0:
				_fail("续命用完没结束（%s，倒下 %s）" % [str(T.run), str(p.dead)])
		14:
			if p.dead or p.carried:
				w._respawn_at_dock()
			if T.inside:
				if _step_t > 12.0:
					_fail("失败以后没送回岛上")
				return
			_next_phase()


func _run_musou() -> void:
	var w := _ready_world()
	if not w:
		return
	var T := w.trial
	var p := w.player
	if _step < 3:
		if _trial_enter(w, T, "musou"):
			_next(3)
		return
	p.hp = 99999.0
	p.invuln_t = 0.0     # 无敌（复活保护）的时候不算"能打的人"，小尸不会在身边冒出来
	match _step:
		3:
			if str(T.run.get("phase", "")) != "run" or T.horde.alive_count() < 100:
				if _step_t > 20.0:
					_fail("割草场上的小尸不够（%d 只，%s）" % [T.horde.alive_count(), str(T.run)])
				return
			_note("万兽割草：场上 %d 只小尸" % T.horde.alive_count())
			_next(4)
		4:
			_horde_shoot(p, T)
			if T.my_kills >= 6:
				_note("开枪斩了 %d 只（子弹能穿好几只）" % T.my_kills)
				_next(5)
			elif _step_t > 20.0:
				_fail("打了 20 秒只斩了 %d 只" % T.my_kills)
		5:
			# 灵爆：等小尸围上来（身边至少 5 只），一圈全清
			var near := T.horde.in_sphere(p.global_position, Trial.BURST_R).size()
			if near < 5 and _step_t < 15.0:
				return
			var before := T.my_kills
			T.burst = Trial.BURST_NEED
			T._burst_now()
			_note("灵爆：身边 %d 只 → 斩数 %d → %d" % [near, before, T.my_kills])
			if not _check(T.my_kills - before >= near and T.burst < Trial.BURST_NEED, "灵爆没清掉身边的"):
				return
			# 神通（房主算）：打一片
			var c: Vector3 = T.horde.units[0]["p"] if not T.horde.units.is_empty() else p.global_position
			var n2 := T.horde.in_sphere(c, 6.0).size()
			var k2 := int(T.run.get("kills", 0))
			T.host_area(c, 6.0, 1e6, Net.my_id)
			if not _check(int(T.run.get("kills", 0)) - k2 == n2, "神通打到的小尸没死（%d 只里死了 %d）" % [n2, int(T.run.get("kills", 0)) - k2]):
				return
			_next(6)
		6:
			if not T.run.is_empty():
				T.run["t"] = Trial.MUSOU_TIME + 1.0
			if T.run.is_empty():
				if not _check(T.best("musou") >= T.my_kills and T._result.visible, "三分钟到了没结算"):
					return
				_note("时间到：%d 斩（纪录 %d）" % [T.my_kills, T.best("musou")])
				_next(7)
			elif _step_t > 3.0:
				_fail("时间到了没结束")
		7:
			if T.inside:
				if _step_t > 9.0:
					_fail("结算完没送回岛上")
				return
			_next_phase()


# ------------------------------------------------------------------ 暗器升星（赌一把）

func _run_stars() -> void:
	var w := _ready_world()
	if not w:
		return
	var id := "xiujian"
	match _step:
		0:
			if not id in Profile.weapons:
				Profile.weapons.append(id)
			Profile.stars.erase(id)
			Profile.star_bless.erase(id)
			Profile.money += 2000000
			Profile.materials["rabbit"] = int(Profile.materials.get("rabbit", 0)) + 10
			var d0 := float(Profile.weapon_stats(id)["damage"])
			# 必成功升到 5 星（3 星突破扣一个王魄）
			var m0 := Profile.all_mats()
			for i in 5:
				var r := Profile.star_try(id, false, 0.0)
				if not _check(bool(r.get("ok", false)), "升星 %d → %d 应该成功" % [i, i + 1]):
					return
			if not _check(Profile.star_of(id) == 5 and Profile.all_mats() == m0 - 1, "升到 5 星不对（%d 星，王魄 %d → %d）" % [Profile.star_of(id), m0, Profile.all_mats()]):
				return
			var d5 := float(Profile.weapon_stats(id)["damage"])
			if not _check(is_equal_approx(d5 / d0, Data.star_mult(5)), "5 星伤害倍数不对（%.3f，应该 %.3f）" % [d5 / d0, Data.star_mult(5)]):
				return
			# 失败：贴护星符不掉星、攒祝福
			var info0 := Profile.star_try_info(id, true)
			var r2 := Profile.star_try(id, true, 0.999)
			if not _check(not bool(r2["ok"]) and Profile.star_of(id) == 5 and float(Profile.star_bless.get(id, 0.0)) > 0.0, "贴护星符失败了不该掉星、要攒祝福"):
				return
			var info1 := Profile.star_try_info(id, true)
			if not _check(float(info1["rate"]) > float(info0["rate"]), "祝福没加到成功率上"):
				return
			# 不贴符失败很多次：最多掉到突破线（3 星）
			for i in 12:
				Profile.star_try(id, false, 0.999)
			if not _check(Profile.star_of(id) >= 3, "掉星掉穿了突破线（%d）" % Profile.star_of(id)):
				return
			_note("升星：5 星伤害 ×%.2f；护星符不掉星、祝福 +%d%%；连败 12 次停在 ★%d（突破保底）" % [Data.star_mult(5), roundi(Data.STAR_BLESS * 100.0), Profile.star_of(id)])
			# 界面：暗器铺升星页点一下
			w.hud.open_shop()
			var sp: ShopPanel = w.hud._shop
			sp._tab = "stars"
			sp._pick_weapon = id
			sp.refresh()
			_mem["s0"] = Profile.star_of(id)
			sp._do_star(id)
			_next(1)
		1:
			var sp2: ShopPanel = w.hud._shop
			if sp2._star_busy:
				if _step_t > 6.0:
					_fail("升星动画卡住了")
				return
			if not _check(Profile.star_of(id) != int(_mem["s0"]) or float(Profile.star_bless.get(id, 0.0)) > 0.0, "点了升星没反应"):
				return
			_note("暗器铺点升星：★%d → ★%d" % [int(_mem["s0"]), Profile.star_of(id)])
			w.hud.close_panels()
			_next_phase()


# ------------------------------------------------------------------ 装饰

func _run_decor() -> void:
	var w := _ready_world()
	if not w:
		return
	match _step:
		0:
			Profile.money += 100000
			var n0 := w.decor.get_child_count()
			for id in Data.DECOR_ORDER:
				if not Profile.decor.has(id) and not _check(Profile.buy_decor(id), "买不了装饰 %s" % id):
					return
			w.decor.refresh()
			var live: Node3D = w.decor._live
			if not _check(live != null and live.get_child_count() > 20, "买了装饰没摆出来（%d 个零件）" % (live.get_child_count() if live else 0)):
				return
			_mem["n"] = live.get_child_count()
			# 收起一样：少掉一些零件
			Profile.toggle_decor("paifang")
			w.decor.refresh()
			_next(1)
		1:
			var live2: Node3D = w.decor._live
			if not _check(live2.get_child_count() < int(_mem["n"]), "收起牌坊没少东西"):
				return
			Profile.toggle_decor("paifang")
			w.decor.refresh()
			# 暗器铺装饰页能打开
			w.hud.open_shop()
			var sp: ShopPanel = w.hud._shop
			sp._tab = "decor"
			sp.refresh()
			_note("装饰：%d 样都摆上了（%d 个零件），收起 / 摆上都行" % [Data.DECOR.size(), int(_mem["n"])])
			var pag := w.decor.find_children("Pagoda", "", false, false).size()
			var pav := w.decor.find_children("Pavilion", "", false, false).size()
			_note("国风地标：宝塔 %d、亭子 %d、全部 %d 个" % [pag, pav, w.decor.get_child_count()])
			if not _check(pag == 1 and pav >= 1, "岛上没摆宝塔 / 亭子"):
				return
			_next(2)
		2:
			if _step_t < 0.3:
				return
			w.hud.close_panels()
			_next_phase()


## 截图：码头装饰（要开窗口）
func _run_decorshot() -> void:
	var w := _ready_world()
	if not w:
		return
	var p := w.player
	match _step:
		0:
			Profile.money += 100000
			for id in Data.DECOR_ORDER:
				if not Profile.decor.has(id):
					Profile.buy_decor(id)
			w.decor.refresh()
			var isl := w.island
			var a: Vector3 = isl.dock_start
			var e: Vector3 = isl.dock_end
			var dir := Vector3(e.x - a.x, 0, e.z - a.z).normalized()
			var st := a - dir * 16.0
			st.y = isl.height_at(st.x, st.z) + 0.3
			p.teleport(st)
			_aim(p, a + dir * 6.0 + Vector3(0, 2.5, 0))
			_next(1)
		1:
			p.hp = 99999.0
			if _step_t > 2.0 and not _mem.has("d1"):
				_mem["d1"] = true
				await _shot("decor_dock")
			elif _step_t > 2.5 and not _mem.has("d2"):
				_mem["d2"] = true
				var bp: Vector3 = w.builder.boat_pos
				var e2: Vector3 = w.island.dock_end
				p.teleport(Vector3(e2.x - 1.0, w.island.dock_y + 0.3, e2.z - 6.0))
				_aim(p, bp + Vector3(0, 2.0, 0))
			elif _step_t > 4.5 and not _mem.has("d3"):
				_mem["d3"] = true
				await _shot("decor_boat")
			elif _step_t > 5.0 and not _mem.has("d4"):
				_mem["d4"] = true
				var xf := Transform3D(Basis(Vector3.UP, w.island.shop_yaw), w.island.shop_pos)
				var sp := xf * Vector3(0, 0, 12.0)
				sp.y = w.island.height_at(sp.x, sp.z) + 0.3
				p.teleport(sp)
				_aim(p, xf * Vector3(0, 2.0, 0))
			elif _step_t > 7.0 and not _mem.has("d5"):
				_mem["d5"] = true
				await _shot("decor_shop")
			elif _step_t > 7.5 and not _mem.has("d6"):
				_mem["d6"] = true
				# 青崖子近看
				if w.sage:
					var sp2: Vector3 = w.sage.global_position + w.sage.global_transform.basis.z * -3.2
					sp2.y = w.island.height_at(sp2.x, sp2.z) + 0.3
					p.teleport(sp2)
					_aim(p, w.sage.global_position + Vector3(0, 1.3, 0))
			elif _step_t > 9.5 and not _mem.has("d7"):
				_mem["d7"] = true
				if w.sage:
					await _shot("decor_sage")
			elif _step_t > 10.0:
				_next_phase()


# ------------------------------------------------------------------ 尸潮追击截图：长街、跳尸模型近看、挨打的血条和数字

func _run_chaseshot() -> void:
	var w := _ready_world()
	if not w:
		return
	var T := w.trial
	var p := w.player
	p.hp = 99999.0
	p.invuln_t = 9999.0
	match _step:
		0:
			T.request("chase")
			_next(1)
		1:
			if not T.inside:
				if _step_t > 4.0:
					_fail("进不了尸潮追击")
				return
			T._phase_t = 999.0     # 一直停在准备阶段，只看自己摆的僵尸
			T.horde.clear()
			p.teleport(Trial.CHASE + Vector3(0, 0.5, -2.0))
			# 近处一排：跳尸、疾尸、铁尸、小尸，远一点一只尸王
			var list: Array = []
			var kinds := [1, 4, 2, 1, 0, 1, 4, 1, 2, 1, 1, 4]
			for i in kinds.size():
				var x := -7.0 + (i % 6) * 2.8 + randf_range(-0.4, 0.4)
				var z := -9.0 - (i / 6) * 4.0 - randf_range(0.0, 1.5)
				list.append([0, Trial.CHASE.x + x, Trial.CHASE.z + z, kinds[i], 100.0])
			list.append([0, Trial.CHASE.x + 1.5, Trial.CHASE.z - 24.0, 3, 1000.0])
			T.horde.host_spawn(list)
			_aim(p, Trial.CHASE + Vector3(0, 1.3, -14.0))
			_next(2)
		2:
			if _step_t > 0.6 and not _mem.has("c1"):
				_mem["c1"] = true
				await _shot("chase_close")
			elif _step_t > 0.8 and not _mem.has("c2"):
				_mem["c2"] = true
				# 打其中两只：血条、伤害数字
				for u in T.horde.units.slice(0, 3):
					T._pending.append([int(u["id"]), float(u["max"]) * 0.4, Net.my_id])
					w.fx.damage_number((u["p"] as Vector3) + Vector3.UP * 1.9, float(u["max"]) * 0.4, false, false, true)
			elif _step_t > 1.1 and not _mem.has("c3"):
				_mem["c3"] = true
				await _shot("chase_hit")
			elif _step_t > 1.3 and not _mem.has("c4"):
				_mem["c4"] = true
				# 长街：从起点往北看到第一道城门
				T.horde.clear()
				var list2: Array = []
				for i in 30:
					list2.append([0, Trial.CHASE.x + randf_range(-11.0, 11.0), Trial.CHASE.z - randf_range(20.0, 90.0), [1, 1, 4, 2][i % 4], 100.0])
				T.horde.host_spawn(list2)
				p.teleport(Trial.CHASE + Vector3(0, 0.5, 4.0))
				_aim(p, Trial.CHASE + Vector3(0, 4.0, -110.0))
			elif _step_t > 2.2 and not _mem.has("c5"):
				_mem["c5"] = true
				await _shot("chase_street")
			elif _step_t > 2.5:
				T.leave()
				_next_phase()


# ------------------------------------------------------------------ 灵主出场镜头（BossCine；平时自动测试关着，这里直接放一遍）

func _run_bosscine() -> void:
	var w := _ready_world()
	if not w:
		return
	var p := w.player
	match _step:
		0:
			if not w.boss:
				w._host_spawn_boss()
			_mem["cine"] = BossCine.play(w, w.boss, "测试 · 出场", str(Data.BOSSES[w.boss.kind]["name"]), "来历", "台词")
			if not _check(not p.cam.current and not p.input_enabled and not w.hud.visible, "出场镜头没接管镜头 / 没关 HUD"):
				return
			_next(1)
		1:
			var c: BossCine = _mem["cine"]
			if is_instance_valid(c) and not c._done:
				if _step_t > BossCine.DUR + 2.0:
					_fail("出场镜头没结束")
				return
			if not _check(p.cam.current and w.hud.visible and p.input_enabled, "出场镜头结束后没还回镜头 / HUD / 操作"):
				return
			_note("灵主出场镜头：%.1f 秒，结束后镜头、HUD、操作都还回来了" % _step_t)
			w.boss.queue_free()
			w.boss = null
			w.hud.boss_bar("")
			_next_phase()


# ------------------------------------------------------------------ 灵相面板里自己的 3D 人物

func _run_selfpreview() -> void:
	var w := _ready_world()
	if not w:
		return
	match _step:
		0:
			w.hud._wuhun.open()
			w.hud._wuhun.visible = true
			_next(1)
		1:
			if _step_t < 1.0:
				return
			var sp := w.hud._wuhun.find_children("*", "SelfPreview", true, false)
			if not _check(sp.size() == 1 and (sp[0] as SelfPreview).mate != null and (sp[0] as SelfPreview).mate.body != null, "灵相面板里没有自己的 3D 人物"):
				return
			_note("灵相面板：自己的 3D 人物（队友看到的样子）")
			w.hud.close_panels()
			_next_phase()
