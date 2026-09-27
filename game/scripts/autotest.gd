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
##   → 到 10 级瓶颈、吸收魂环、选魂技、放魂技 → 祭坛召唤湖主、用暗器打它、打死、拿魂骨
##   → 坐船去第二章 → 落日森林里抓狼、蛇、犀牛
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
	match mode:
		"solo":
			main.start_solo()
			_plan = ["phys", "hunt:burrow,meadow,flowers,water,reel", "shop", "recoil", "sniper", "ring", "boss", "boat", "hunt:den,swamp,mud", "boss", "boat",
				"hunt:glade,roost,thicket,nest,bog", "boss", "boat",
				"hunt:snowden,frostgrove,icefield,icecave,icelake", "boss", "boat",
				"hunt:beach,cliff,reef,deep,abyss", "boss", "done"]
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
			# --exp=1：房主直接开猎魂远征，测远征的联机
			main._expedition = args.has("exp")
			main.start_host(str(args.get("room", "TEST")))
			_plan = ["exphost"] if args.has("exp") else ["host"]
		"client":
			Settings.server_url = str(args.get("server", "ws://127.0.0.1:18931"))
			Settings.player_name = "客人"
			main.start_join(str(args.get("room", "TEST")))
			_plan = ["expclient", "done"] if args.has("exp") else ["hunt:burrow,meadow", "done"]
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
		"expedition":
			_run_expedition()
		"expshot":
			_run_expshot()
		"comboshot":
			_run_comboshot()
		"tour", "tour1", "tour2":
			_run_tour()
		"host":
			_run_host()
		"exphost":
			_run_exphost()
		"expclient":
			_run_expclient()
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
			_pass("全部流程通过：等级 %d，魂环 %d，金魂币 %d，章节 %d" % [Profile.level, Profile.rings.size(), Profile.money, Profile.chapter])


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


# ------------------------------------------------------------------ 界面截图：魂技栏和魂技轮盘

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

## 1) 拽出来的魂兽：飞多高、多久落地
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
				_fail("物理测试：魂兽不见了（case %d）" % case)
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
				_fail("物理测试：魂兽 12 秒还没落地（case %d，状态 %d，位置 %s）" % [case, b.state, b.global_position])


# ------------------------------------------------------------------ 抓魂兽流程

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
				_note("击杀成功，金魂币 %d → %d，等级 %d，击杀数 %d" % [_money_before, Profile.money, Profile.level, st["kills"]])
				if Profile.money <= _money_before:
					_fail("击杀了但金魂币没增加")
					return
				_queue.pop_front()
				_next(0)
			elif _step_t > 3.0:
				# 可能逃走了：重来一次
				_note("魂兽跑了，重试")
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
			if not _check(Profile.sell_weapon("baoyu") and Profile.money > sold and not Profile.has_weapon("baoyu"), "卖不了暴雨梨花针"):
				return
			w.on_sold_weapon("baoyu")
			if not _check(Profile.buy_weapon("baoyu"), "卖掉的暗器买不回来"):
				return
			w.on_bought_weapon("baoyu")
			w.hud._shop._tab = "attach"
			w.hud._shop.refresh()
			_note("买了 4 把暗器和 2 个升级，花了 %d 金魂币" % (before - Profile.money))
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
			if not _check(p.gun.id == "zhuge", "切不到诸葛神弩"):
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


# ------------------------------------------------------------------ 魂环：瓶颈、掉环、吸收、选魂技、放魂技

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
			# 刚从暗器铺出来：先走开一点，别让魂环掉在铺子门口（按 F 会开铺子）
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
			var dbg := "玩家 %s，魂环 %s" % [p.global_position, w.rings.values().map(func(r): return r["pos"])]
			if not _check(it.get("id", "") == "ring" and it.get("ok", false), "站在魂环旁边却不能吸收：%s（%s）" % [it, dbg]):
				return
			w.interact()
			_next(3)
		3:
			if w.hud._choice == null and Profile.rings.size() >= 1:
				# 新版：魂技吸收完自动揭晓，不用选
				_note("吸收了百年魂环，魂技【%s】" % Data.SKILLS[Profile.rings[0]["skill"]]["name"])
				Profile.add_xp(100000)
				w._broadcast_prog()
				if not _check(Profile.level == 20, "吸收魂环后没有突破瓶颈（%d 级）" % Profile.level):
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
				if not _check(Profile.rings.size() == 1, "吸收后魂环数不对"):
					return
				_note("吸收了百年魂环，魂技【%s】" % Data.SKILLS[sid]["name"])
				Profile.add_xp(100000)
				w._broadcast_prog()
				if not _check(Profile.level == 20, "吸收魂环后没有突破瓶颈（%d 级）" % Profile.level):
					return
				_next(4)
			elif _step_t > 5.0:
				_fail("吸收魂环 5 秒后没弹出魂技选择")
		4:
			if _step_t < 0.5:
				return
			p.soul = Profile.max_soul()
			# 魂技现在由魂兽决定：测试固定换成第一环的攻击魂技，结果稳定
			Profile.rings[0]["skill"] = Data.SKILL_TREE[Data.wuhun_id(Settings.wuhun)][0][0]
			var s0 := p.soul
			var m := w.island.habitat("meadow")
			var c: Vector2 = m["center"]
			_aim(p, Vector3(c.x, w.island.height_at(c.x, c.y), c.y))
			w.skills.cast(0)
			if not _check(w.skills.cooldowns[0] > 0.0 and p.soul < s0, "放魂技没生效"):
				return
			_note("放出魂技，冷却 %.1f 秒" % w.skills.cooldowns[0])
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
				if not _check(not Profile.bones.is_empty(), "打死 Boss 没拿到魂骨"):
					return
				_note("Boss 死了，拿到魂骨 %s，任务：%s" % [Profile.bones, w._cur_quest().get("text", "")])
				if not _check(w._cur_quest().get("type", "") in ["boat", "end", "god"], "打完 Boss 任务没推进"):
					return
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


## 魂兽王：捆魂、暴怒、逃跑、击杀掉王魂和魂环，再拿王魂附魔
func _run_kings() -> void:
	var w := _ready_world()
	if not w:
		return
	var p := w.player
	match _step:
		0:
			w._init_elites()
			if not _check(not w.elites.is_empty(), "这张图没有魂兽王的位置"):
				return
			var key: String = w.elites.keys()[0]
			w._host_spawn_elite(key)
			var k: Beast = w.beasts.get(int(w.elites[key]["id"]))
			if not _check(k != null and k.temper == "elite", "魂兽王没刷出来"):
				return
			_mem["king"] = k.id
			_note("魂兽王：%s，血量 %d" % [k.display_name(), int(k.max_hp)])
			p.teleport(k.global_position + Vector3(0, 0.5, 14))
			_next(1)
		1:
			if _step_t < 1.5:
				return
			var k: Beast = w.beasts.get(int(_mem["king"]))
			w.host_hook(k.id, Net.my_id)
			if not _check(k.root_t > 0.0, "单人用引魂索钩魂兽王没捆住"):
				return
			_note("捆魂成功，按住 %.1f 秒" % k.root_t)
			k.root_t = 0.0
			k.take_hit(k.max_hp * 0.55, Vector3.ZERO, Vector3.ZERO, false, Net.my_id, 10.0)
			_next(2)
		2:
			if _step_t < 0.5:
				return
			var k: Beast = w.beasts.get(int(_mem["king"]))
			if not _check(k._phase2, "魂兽王半血没暴怒"):
				return
			k.root_t = 0.0
			k.take_hit(k.hp - k.max_hp * 0.2, Vector3.ZERO, Vector3.ZERO, false, Net.my_id, 10.0)
			_next(3)
		3:
			if _step_t < 0.6:
				return
			var k: Beast = w.beasts.get(int(_mem["king"]))
			if not _check(k._retreat, "魂兽王残血没逃跑"):
				return
			_note("魂兽王暴怒、逃跑都正常")
			_mem["mats"] = int(Profile.materials.get(k.species, 0))
			_mem["sp"] = k.species
			k.take_hit(k.hp + 10.0, Vector3.ZERO, Vector3.ZERO, false, Net.my_id, 10.0)
			w._host_kill(k)
			_next(4)
		4:
			if _step_t < 1.0:
				return
			if not _check(int(Profile.materials.get(str(_mem["sp"]), 0)) > int(_mem["mats"]), "打死魂兽王没拿到王魂"):
				return
			if not _check(not w.rings.is_empty(), "打死魂兽王没掉魂环"):
				return
			Profile.add_material("rabbit", 2)
			Profile.add_money(1000)
			if not _check(Profile.do_enchant("xiujian", "bind") and Profile.enchant.get("xiujian", "") == "bind", "附魔失败"):
				return
			_note("王魂、魂环、附魔都正常")
			_next_phase()


## 界面截图：HUD、暗器铺、武魂、暂停、成就、地图、魂技二选一、倒地、Boss 出场、魂师榜
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
			h.feed("你 击杀了 百年 · 魔狼", Color.WHITE)
			h.feed("客人 击杀了 十年 · 柔骨兔", Color.WHITE)
			h.kill_popup(186, 42, ["爆头 +50%", "空中击杀"], "wolf", 1)
			h.toast("✔ 悬赏完成：风铃鸟 · 十年    +70 金魂币", Color(0.6, 1.0, 0.7), 5.0)
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
			h.boss_intro("千年魂兽 · 曼陀罗蛇")
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


## 天上飞的鸟：用真的射线打它，要掉下来变成一只魂兽；魂兽王任务要能计数
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
			if not _check(w.beasts.size() > int(_mem["nb"]), "打中鸟以后没有掉下来变成魂兽"):
				return
			if not _check(not (w.builder._critters[0] as Node3D).visible, "打下来的鸟还在天上飞"):
				return
			_note("天上的鸟打下来变成了魂兽")
			# 魂兽王任务：计数
			w.quest_idx = _quest_index(w.chapter, "kings")
			w.quest_count = 0
			w._host_check_quest()
			w._host_quest_event("kings", 1)
			if not _check(w.quest_count == 1, "打死魂兽王任务没计数"):
				return
			_note("魂兽王任务计数正常（目标 %d）" % w.quest_target)
			_next_phase()


## 猎魂连击：空中命中涨评级、奖励倍数、3 秒不打就断；武魂真身：充满后变身、加伤害、子弹不耗、到时间结束
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
				_check(c.meter == 0.0, "武魂真身关掉了还在充能")
				_next_phase()
				return
			c.meter = 1.0
			var before := p.damage_mult()
			c.activate()
			if not _check(c.active() and p.damage_mult() > before * 1.8, "武魂真身没加伤害"):
				return
			p.gun.ammo = 0
			_mem["dm"] = before
			_next(2)
		2:
			if _step_t < 0.3:
				return
			if not _check(p.gun.ammo == int(p.gun.d["mag"]), "武魂真身期间子弹还在消耗"):
				return
			c.tb_t = 0.05
			_next(3)
		3:
			if _step_t < 0.4:
				return
			if not _check(not c.active() and c.meter == 0.0, "武魂真身到时间没结束"):
				return
			_note("武魂真身：加伤害、子弹不耗、到时间结束都正常")
			_next_phase()


## 截图：连击评级 S、武魂真身
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


func _free_later(n: Node) -> void:
	get_tree().create_timer(2.0).timeout.connect(n.queue_free)


## 仇恨范围：60 米外的凶暴魂兽不过来，走到 14 米它就来咬；90 级魂力护体减伤 36%
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
			if not _check(spot != Vector3.INF, "60 米外找不到陆地放魂兽"):
				return
			_target = w._host_spawn_wild(spot, "wolf", 1, "fierce")
			_next(1)
		1:
			if _step_t < 5.0:
				return
			var b := _target
			if not _check(b != null and is_instance_valid(b) and b.alive(), "凶暴魂兽不见了"):
				return
			var d := b.global_position.distance_to(p.global_position)
			if not _check(d > 45.0, "60 米外的凶暴魂兽还是追过来了（现在 %.0f 米）" % d):
				return
			_note("60 米外的凶暴魂兽不追人（%.0f 米）" % d)
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
				_note("90 级魂力护体：挨 100 掉 %.0f" % lost)
				_next_phase()
			elif _step_t > 8.0:
				_fail("走到 14 米凶暴魂兽也不过来（%.1f 米；魂兽 %s %s state=%d，玩家 %s dead=%s 能打=%s）" % [d, b.global_position, b.temper, b.state, p.global_position, p.dead, not p.untargetable()])


## 猎魂远征：坐船去 → 猎物出现、有踪迹、罗盘不标成普通的王 → 打死：钱和王魂进背包 → 护法吸收魂环（一波波只冲吸收的人）
## → 再吸收一次时倒下：打断、魂环掉回地上、背包掉在原地 → 走回去捡回来 → 血月夜猎者：营地外追人、营地里不追
## → 船边存战利品 ×1.8 → 坐船回原来的章节
func _run_expedition() -> void:
	var w := _world()
	match _step:
		0:
			w = _ready_world()
			if not w or _step_t < 1.0:
				return
			_mem["home"] = Profile.chapter
			Profile.level = 10
			Profile.rings = []
			w._broadcast_prog()
			if not _check((Data.EXP_CODE + Data.EXP_CHAPTER) in w.boat_destinations(), "渡船没有猎魂远征"):
				return
			_old_world = w
			w.board(Data.EXP_CODE + Data.EXP_CHAPTER)
			_next(1)
		1:
			var nw := _ready_world()
			if nw and nw != _old_world and nw.expedition:
				if not _check(nw.chapter == Data.EXP_CHAPTER and nw.island.map_id == str(Data.CHAPTERS[Data.EXP_CHAPTER]["map"]), "远征没到星斗大森林"):
					return
				if not _check(Profile.chapter == int(_mem["home"]), "去远征把存档章节改了"):
					return
				if not _check(not nw.hud._quest_text.get_parent().visible, "远征里还显示章节任务"):
					return
				_note("到了猎魂远征（存档章节还是 %d）" % Profile.chapter)
				nw.player.invuln_t = 9999.0
				nw.expedition.next_t = 0.0
				_next(2)
			elif _step_t > 20.0:
				_fail("坐船 20 秒还没到远征")
		2:
			var e := w.expedition
			if e.target_id == 0 or not w.beasts.has(e.target_id):
				if _step_t > 5.0:
					_fail("猎物没出现")
				return
			var b: Beast = w.beasts[e.target_id]
			if not _check(b.temper == "elite" and b.exp_role == "target", "猎物不是王"):
				return
			var marks: Array = w.hud._compass_marks()
			var prey := false
			for m in marks:
				if str(m[1]) == "王":
					_fail("猎物被当成普通的王标在罗盘上")
					return
				if str(m[1]) == "猎":
					prey = true
			if not _check(prey, "罗盘上没有猎物"):
				return
			_note("猎物：%s，%d 米外" % [b.display_name(), int(b.global_position.distance_to(w.player.global_position))])
			# 走到它 30 米外（踪迹只在 170 米内显示），再让它挪一挪
			for i in 16:
				var a := TAU * i / 16.0
				var q := b.global_position + Vector3(cos(a) * 30.0, 0, sin(a) * 30.0)
				if w.island.is_land(q.x, q.z):
					w.player.teleport(Vector3(q.x, w.island.height_at(q.x, q.z) + 0.3, q.z))
					break
			b.global_position += Vector3(4.0, 0.5, 0.0)
			_target = b
			_next(3)
		3:
			var e := w.expedition
			if e._prints.is_empty():
				if _step_t > 3.0:
					_fail("猎物走动了没有踪迹")
				return
			_note("猎物走动留下了踪迹（%d 个脚印）" % e._prints.size())
			_mem["money"] = Profile.money
			_mem["ach"] = Profile.achieved.keys()
			var b := _target
			b.last_hitter = Net.my_id
			b.damagers[Net.my_id] = 1.0
			b.hp = 0.0
			w._host_kill(b)
			_next(4)
		4:
			if _step_t < 0.5:
				return
			var e := w.expedition
			if not _check(e.target_id == 0 and e.next_t > 0.0, "打死猎物后没排下一只"):
				return
			# 成就奖励直接到手（不算战利品），其他的钱都该在背包里
			var ach := 0
			for a in Data.ACHIEVEMENTS:
				if Profile.achieved.has(str(a["id"])) and not str(a["id"]) in (_mem["ach"] as Array):
					ach += int(a["reward"])
			if not _check(e.bag_money > 0 and Profile.money - int(_mem["money"]) == ach, "远征的钱没进背包（背包 %d，金魂币 %d → %d，成就 %d）" % [e.bag_money, int(_mem["money"]), Profile.money, ach]):
				return
			if not _check(e._mat_n(e.bag_mats) >= 1, "王魂没进背包"):
				return
			var rid := -1
			for k in w.rings:
				rid = int(k)
			if not _check(rid >= 0, "猎物没掉魂环"):
				return
			_note("背包：%d 金魂币、王魂 ×%d；地上掉了魂环" % [e.bag_money, e._mat_n(e.bag_mats)])
			var rp: Vector3 = w.rings[rid]["pos"]
			w.player.teleport(Vector3(rp.x, w.island.height_at(rp.x, rp.z) + 0.2, rp.z))
			Net.send_host("absorb", [rid])
			_next(5)
		5:
			var e := w.expedition
			if e.channel.is_empty():
				if _step_t > 2.0:
					_fail("吸收魂环没开始护法")
				return
			if not _check(w.player.channeling and int(e.channel["peer"]) == Net.my_id, "吸收的人没被定住"):
				return
			e.channel["dur"] = 8.0
			e._wave_t = 0.0
			_next(6)
		6:
			var e := w.expedition
			if not e.channel.is_empty():
				if _step_t > 1.0 and not _mem.has("wave"):
					var n := 0
					for b: Beast in w.beasts.values():
						if b.alive() and b.focus_peer == Net.my_id:
							n += 1
					if not _check(n >= 2, "护法没来魂兽（%d）" % n):
						return
					_mem["wave"] = n
					_note("护法：来了 %d 只魂兽，都冲着吸收的人" % n)
				if _step_t > 15.0:
					_fail("护法 15 秒还没结束")
				return
			if not _check(Profile.rings.size() == 1 and not w.player.channeling, "护法结束没吸收到魂环（%d）" % Profile.rings.size()):
				return
			for b: Beast in w.beasts.values():
				if b.focus_peer != 0:
					_fail("护法结束了魂兽还只盯着吸收的人")
					return
			_note("护法完成，吸收了第一魂环")
			Profile.level = 20
			w._broadcast_prog()
			w._host_drop_ring(w.player.global_position + Vector3(0, 1.0, 0), 1, "stag", 90.0)
			_next(7)
		7:
			if _step_t < 0.3:
				return
			var rid := -1
			for k in w.rings:
				rid = int(k)
			if not _check(rid >= 0, "第二个魂环没掉"):
				return
			w.expedition.add_bag(500)
			Net.send_host("absorb", [rid])
			_next(8)
		8:
			var e := w.expedition
			if e.channel.is_empty():
				if _step_t > 2.0:
					_fail("第二次护法没开始")
				return
			var p := w.player
			p.invuln_t = 0.0
			p.take_damage(999999.0, p.global_position + Vector3.FORWARD)
			_next(9)
		9:
			if _step_t < 0.5:
				return
			var e := w.expedition
			if not _check(e.channel.is_empty() and not w.rings.is_empty(), "倒下了吸收没被打断 / 魂环没掉回地上"):
				return
			if not _check(not e.dropped.is_empty() and e.bag_money == 0, "倒下了背包没掉"):
				return
			_mem["drop"] = int(e.dropped["money"])
			_note("倒下：吸收被打断，魂环掉回地上；背包掉在原地（%d）" % int(e.dropped["money"]))
			w._respawn_at_dock()
			_next(10)
		10:
			if _step_t < 0.5:
				return
			var p := w.player
			p.invuln_t = 9999.0
			var dp: Vector3 = w.expedition.dropped["pos"]
			p.teleport(dp + Vector3(0.5, 0.3, 0))
			_next(11)
		11:
			if _step_t < 0.3:
				return
			var e := w.expedition
			var it := w.nearest_interactable()
			if not _check(str(it.get("id", "")) == "expbag", "站在背包旁边没有提示（%s）" % str(it.get("id", ""))):
				return
			w.interact()
			if not _check(e.dropped.is_empty() and e.bag_money == int(_mem["drop"]), "背包没捡回来"):
				return
			_note("走回去捡回了背包")
			e._host_phase("blood")
			e._hunter_wait = 0.0
			_next(12)
		12:
			var e := w.expedition
			if e.hunter_id == 0 or not w.beasts.has(e.hunter_id):
				if _step_t > 3.0:
					_fail("血月没出夜猎者")
				return
			var h: Beast = w.beasts[e.hunter_id]
			if not _check(h.exp_role == "hunter" and h.speed_cap > 0.0 and h.speed_cap < Player.SPRINT_SPEED, "夜猎者设置不对"):
				return
			var spot := Vector3.INF
			for i in 24:
				var a := TAU * i / 24.0
				var q := h.global_position + Vector3(cos(a) * 30.0, 0, sin(a) * 30.0)
				if w.island.is_land(q.x, q.z) and e._camp_dist(q) > Data.EXP_CAMP_R + 5.0:
					spot = Vector3(q.x, w.island.height_at(q.x, q.z) + 0.3, q.z)
					break
			if not _check(spot != Vector3.INF, "夜猎者旁边找不到地方站"):
				return
			var p := w.player
			p.invuln_t = 0.0
			p.hp = 1000000.0
			p.teleport(spot)
			_target = h
			_next(13)
		13:
			if _step_t < 1.5:
				return
			var h := _target
			if not _check(is_instance_valid(h) and h.focus_peer == Net.my_id, "夜猎者没盯上营地外 30 米的人"):
				return
			_note("夜猎者盯上了营地外 30 米的人")
			w.player.teleport(w.island.spawn + Vector3(0, 0.5, 0))
			_next(14)
		14:
			if _step_t < 1.5:
				return
			var h := _target
			var e := w.expedition
			if not _check(h.focus_peer == 0 and e._camp_dist(h.spawn_pos) >= Data.EXP_CAMP_R, "人进了营地夜猎者还在追"):
				return
			_note("进了船边营地，夜猎者不追了")
			var p := w.player
			p.hp = Profile.max_hp()
			p.invuln_t = 9999.0
			var bp := w.builder.boat_pos
			p.teleport(Vector3(w.island.dock_end.x + 0.6, w.island.dock_y + 0.2, bp.z))
			_mem["money"] = Profile.money
			_mem["bag"] = e.bag_money
			_next(15)
		15:
			if _step_t < 0.5:
				return
			var e := w.expedition
			var it := w.nearest_interactable()
			if not _check(str(it.get("id", "")) == "boat", "船边没有提示（%s）" % str(it.get("id", ""))):
				return
			w.interact()
			var want := roundi(int(_mem["bag"]) * 1.8)
			if not _check(Profile.money - int(_mem["money"]) == want and not e.has_bag(), "存战利品不对（多了 %d，应该 %d）" % [Profile.money - int(_mem["money"]), want]):
				return
			_note("血月存战利品 ×1.8：+%d 金魂币" % want)
			_old_world = w
			w.board(int(_mem["home"]))
			_next(16)
		16:
			var nw := _ready_world()
			if nw and nw != _old_world:
				if not _check(nw.expedition == null and nw.chapter == int(_mem["home"]), "没回到原来的章节"):
					return
				_note("坐船回到了%s" % Data.CHAPTERS[nw.chapter]["name"])
				_next_phase()
			elif _step_t > 20.0:
				_fail("回程 20 秒还没到")


## 截图：远征的黄昏、踪迹、护法、血月和夜猎者
func _run_expshot() -> void:
	var w := _world()
	match _step:
		0:
			w = _ready_world()
			if not w or _step_t < 1.0:
				return
			if w.expedition == null:
				_old_world = w
				w.board(Data.EXP_CODE + Data.EXP_CHAPTER)
			_next(1)
		1:
			w = _ready_world()
			if not w or not w.expedition or _step_t < 3.0:
				return
			var p := w.player
			p.invuln_t = 9999.0
			var e := w.expedition
			# 前面一串发光的脚印
			var fwd := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
			var side := fwd.cross(Vector3.UP)
			for i in 10:
				var q := p.global_position + fwd * (4.0 + i * 2.2) + side * sin(i * 0.7) * 1.5
				q.y = w.island.height_at(q.x, q.z)
				e._on_fp([q, side])
			e.next_t = 0.0
			_next(2)
		2:
			if _step_t < 2.0:
				return
			_next(3)
			await _shot("exp_dusk_tracks")
		3:
			var e := w.expedition
			var p := w.player
			var fwd := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
			# 队友视角：别人在吸收（光柱 + 两圈魂环），左上角护法条
			e.hold = true
			e.channel = {"peer": 999, "age": 2, "species": "stag", "pos": p.global_position + fwd * 6.0, "t": 12.0, "dur": 40.0}
			e._on_channel_start()
			_next(4)
		4:
			if _step_t < 1.5:
				return
			_next(5)
			await _shot("exp_channel")
		5:
			var e := w.expedition
			e._channel_visual(false)
			e.channel = {}
			e.hold = false
			e._host_phase("blood")
			e._hunter_wait = 999.0
			_next(6)
		6:
			if _step_t < 9.5:
				return
			var e := w.expedition
			e._spawn_hunter()
			var h: Beast = w.beasts[e.hunter_id]
			var p := w.player
			var fwd := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
			var q := p.global_position + fwd * 22.0
			h.global_position = Vector3(q.x, w.island.height_at(q.x, q.z) + 1.0, q.z)
			h.spawn_pos = h.global_position
			_next(7)
		7:
			if _step_t < 2.5:
				return
			_next(8)
			await _shot("exp_bloodmoon")
		8:
			_next_phase()


func _fx_impact(fx: Fx, o: Vector3, fwd: Vector3, side: Vector3) -> void:
	for k in 4:
		fx.impact_beast(o + Vector3(randf_range(-1, 1), 1.2 + randf(), randf_range(-1, 1)), -fwd, Color(1.0, 0.3, 0.25), k == 0)
		fx.impact_world(o + side * (k - 1.5) * 1.5, Vector3.UP)


func _fx_burn_bleed(fx: Fx, o: Vector3, side: Vector3, c: Color) -> void:
	fx.empower_hit("burn", o + Vector3.UP * 1.5 + side, c)
	fx.empower_hit("bleed", o + Vector3.UP * 1.5 - side, c)


## 魂兽巢穴：放出来、打掉、爆掉给奖励
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
			_note("巢打爆了，金魂币 %d → %d" % [int(_mem["money_n"]), Profile.money])
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


## 新魂技：召唤、连锁、黑洞、领域、环绕、附体、神技，每个放一次（周围放几只魂兽当靶子）
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
			_note("新魂技都放过了")
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


## 奇遇 + 海鸥群 + 魂兽独门招式（平时自动测试里关着，这里专门跑一遍）
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
			# 一只凶暴的魂兽放独门招式
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
			_note("奇遇、王、海鸥群、魂兽招式都跑过了，没有报错")
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
					_note("客人击杀 %d 只，房主金魂币 %d、修为 %d" % [w.stats[id]["kills"], Profile.money, Profile.xp])
					if not _check(Profile.xp > 0 or Profile.level > 1, "队友击杀，房主没分到修为"):
						return
					_next(2)
					return
		2:
			if w.remotes.is_empty() or _step_t > 3.0:
				_pass("房主测试通过")


## 远征联机（房主）：客人进来 → 出猎物 → 算客人打死的（魂环归他）→ 客人吸收时房主开护法、缩短时间 → 客人吸收完
func _run_exphost() -> void:
	var w := _ready_world()
	if not w:
		return
	var e := w.expedition
	if not _check(e != null, "房主没进远征"):
		return
	match _step:
		0:
			if not w.remotes.is_empty():
				_note("客人进来了：%s" % w.remotes.keys())
				w.player.invuln_t = 9999.0
				e.next_t = 0.0
				_next(1)
			elif _t > 40.0:
				_fail("没有客人加入")
		1:
			var guest := int(w.remotes.keys()[0])
			var lv := int(w.peer_info.get(guest, {}).get("level", 1))
			if e.target_id == 0 or not w.beasts.has(e.target_id) or lv < 10 or _step_t < 3.0:
				if _step_t > 20.0:
					_fail("猎物没出现 / 客人等级没同步（%d）" % lv)
				return
			var b: Beast = w.beasts[e.target_id]
			b.last_hitter = guest
			b.damagers[guest] = 1.0
			b.hp = 0.0
			w._host_kill(b)
			_note("猎物（%s）算客人打死的" % b.display_name())
			_next(2)
		2:
			if not e.channel.is_empty():
				if not _mem.has("short"):
					_mem["short"] = true
					if not _check(int(e.channel["peer"]) != Net.my_id, "护法的不是客人"):
						return
					e.channel["dur"] = 6.0
					_note("客人开始吸收，房主开始刷护法的魂兽")
				return
			if _mem.has("short"):
				_note("护法结束")
				_next(3)
			elif _step_t > 30.0:
				_fail("客人 30 秒没开始吸收")
		3:
			if w.remotes.is_empty() or _step_t > 6.0:
				_pass("远征房主测试通过")


## 远征联机（客人）：跟着房主进远征 → 收到天色和猎物 → 猎物打死后钱进自己背包、地上有自己的魂环 → 吸收（护法）→ 学会魂技
func _run_expclient() -> void:
	var w := _ready_world()
	if not w:
		return
	match _step:
		0:
			if not _check(w._exp_mode and w.expedition != null and w.chapter == Data.EXP_CHAPTER, "客人没跟着进远征（章节 %d）" % w.chapter):
				return
			Profile.level = 10
			Profile.rings = []
			w._broadcast_prog()
			w.player.invuln_t = 9999.0
			_note("客人进了远征")
			_next(1)
		1:
			var e := w.expedition
			var tb: Beast = w.beasts.get(e.target_id) if e.target_id != 0 else null
			if e._got_state and tb != null and tb.exp_role == "target":
				_note("客人收到了天色（%s）和猎物（%s）" % [Data.EXP_PHASE[e.phase]["name"], tb.display_name()])
				_next(2)
			elif _step_t > 25.0:
				_fail("客人没收到远征状态 / 猎物")
		2:
			var e := w.expedition
			if w.rings.is_empty():
				if _step_t > 25.0:
					_fail("客人没看到魂环")
				return
			if not _check(e.bag_money > 0, "客人打死猎物，钱没进背包"):
				return
			var rid := int(w.rings.keys()[0])
			var rp: Vector3 = w.rings[rid]["pos"]
			w.player.teleport(Vector3(rp.x, w.island.height_at(rp.x, rp.z) + 0.2, rp.z))
			_note("客人背包 %d 金魂币，去吸收魂环" % e.bag_money)
			Net.send_host("absorb", [rid])
			_next(3)
		3:
			var e := w.expedition
			if w.player.channeling and not e.channel.is_empty():
				_note("客人被定住了，在护法")
				_next(4)
			elif _step_t > 8.0:
				_fail("客人吸收没开始护法")
		4:
			if Profile.rings.size() == 1 and not w.player.channeling:
				_note("客人吸收完了：%s" % Data.SKILLS[str(Profile.rings[0]["skill"])]["name"])
				_next_phase()
			elif _step_t > 30.0:
				_fail("客人护法 30 秒没结束")


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


# ------------------------------------------------------------------ 把所有魂兽模型摆成一排看朝向和大小

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
