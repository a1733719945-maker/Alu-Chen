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
			main.start_host(str(args.get("room", "TEST")))
			_plan = ["host"]
		"client":
			Settings.server_url = str(args.get("server", "ws://127.0.0.1:18931"))
			Settings.player_name = "客人"
			main.start_join(str(args.get("room", "TEST")))
			_plan = ["hunt:burrow,meadow", "done"]
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
		"tour", "tour1", "tour2":
			_run_tour()
		"host":
			_run_host()
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


func _free_later(n: Node) -> void:
	get_tree().create_timer(2.0).timeout.connect(n.queue_free)


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
