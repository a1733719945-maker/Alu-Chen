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
			_plan = ["hunt:burrow,meadow,flowers,water,reel", "shop", "recoil", "sniper", "ring", "boss", "boat", "hunt:den,swamp,mud", "boss", "done"]
		"shots":
			_shots = true
			_shots_dir = str(args.get("out", "user://shots"))
			DirAccess.make_dir_recursive_absolute(_shots_dir)
			main._show_menu()
			_plan = ["menu", "tour1", "hunt:burrow", "shop", "recoil", "sniper", "ring", "boss", "boat", "tour2", "hunt:den", "done"]
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
	var limit := 300.0 if mode != "shots" else 900.0
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
		"tour1", "tour2":
			_run_tour()
		"host":
			_run_host()
		"vm":
			_run_vm()
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


# ------------------------------------------------------------------ 抓魂兽流程

func _habitat_spot(w: World, h: String) -> Dictionary:
	# 返回 {stand: 玩家站的位置, target: 引魂索落点, water: 是否落在水里}
	var isl := w.island
	match h:
		"water":
			return {"stand": Vector3(isl.dock_end.x, isl.dock_y - 0.4, isl.dock_end.z - 2), "target": isl.dock_end + Vector3(-4, 0, 10), "water": true}
		"swamp":
			var pd: Dictionary = isl.ponds[0]
			var c: Vector2 = pd["center"]
			var st := Vector3(c.x + float(pd["radius"]) + 4.0, 0, c.y)
			st.y = isl.height_at(st.x, st.z)
			return {"stand": st, "target": Vector3(c.x, Island.WATER_Y, c.y), "water": true}
		"burrow", "den":
			var hb := isl.habitat(h)
			var b: Vector3 = hb["points"][0]
			var c: Vector2 = hb["center"]
			var dir := Vector3(c.x - b.x, 0, c.y - b.z).normalized()
			var st := b + dir * 12.0
			st.y = isl.height_at(st.x, st.z)
			return {"stand": st, "target": b, "water": false}
		"reel":
			return _habitat_spot(w, "meadow")
		_:
			var c: Vector2 = isl.habitat(h)["center"]
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
			Profile.add_money(20000)
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
			_note("买了 4 把暗器和 2 个升级，花了 %d 金魂币" % (before - Profile.money))
			if not _check(p.guns.size() == 5, "暗器数量不对：%d" % p.guns.size()):
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
			if w.hud._choice != null:
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
				if not _check(w._cur_quest().get("type", "") in ["boat", "end"], "打完 Boss 任务没推进"):
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
			w.interact()
			_next(2)
		2:
			var nw := _ready_world()
			if nw and nw != _old_world:
				if not _check(nw.chapter == 2 and nw.island.map_id == "forest", "坐船后没到第二章"):
					return
				if not _check(Profile.chapter == 2, "存档章节没更新"):
					return
				_note("到了第二章 · 落日森林")
				_next_phase()
			elif _step_t > 20.0:
				_fail("坐船 20 秒还没到第二章")


# ------------------------------------------------------------------ 截图游览

func _tour_list(w: World) -> Array:
	var isl := w.island
	var out := []
	var gp := func(x: float, z: float, up: float) -> Vector3:
		return Vector3(x, isl.height_at(x, z) + up, z)
	if w.chapter == 1:
		out.append(["spawn", null, null])
		var m: Vector2 = isl.habitat("meadow")["center"]
		out.append(["meadow", gp.call(m.x + 22, m.y + 26, 1.7), gp.call(m.x, m.y, 3.0)])
		var h := isl.hill
		out.append(["hill_view", gp.call(h.x, h.y + 6, 1.7), gp.call(0, 50, 0.0)])
		out.append(["lake_view", gp.call(isl.dock_start.x + 8, isl.dock_start.z - 4, 1.7), Vector3(-120, 10, 260)])
		var f: Vector2 = isl.habitat("flowers")["center"]
		out.append(["flowers", gp.call(f.x + 14, f.y + 8, 1.7), gp.call(f.x, f.y, 0.5)])
		var b: Vector2 = isl.habitat("burrow")["center"]
		out.append(["burrow", gp.call(b.x - 16, b.y + 10, 1.7), gp.call(b.x, b.y, 0.5)])
		out.append(["forest_edge", gp.call(-60, 40, 1.7), gp.call(-90, 20, 4.0)])
	else:
		out.append(["forest_spawn", null, null])
		var g: Vector2 = isl.habitat("grove")["center"]
		out.append(["grove", gp.call(g.x + 4, g.y + 20, 1.7), isl.ancient_tree + Vector3(0, 9, 0)])
		out.append(["ancient_tree", gp.call(g.x - 8, g.y - 5, 1.7), isl.ancient_tree + Vector3(0, 4, 0)])
		var d: Vector2 = isl.habitat("den")["center"]
		out.append(["den", gp.call(d.x + 12, d.y + 12, 1.7), gp.call(d.x, d.y, 1.0)])
		var md: Vector2 = isl.habitat("mud")["center"]
		out.append(["mud", gp.call(md.x - 16, md.y + 10, 1.7), gp.call(md.x, md.y, 0.0)])
		var pd: Dictionary = isl.ponds[0]
		var pc: Vector2 = pd["center"]
		out.append(["swamp", gp.call(pc.x + float(pd["radius"]) + 6, pc.y + 6, 1.7), Vector3(pc.x, 0.5, pc.y)])
		out.append(["forest_path", gp.call(isl.spawn.x, isl.spawn.z - 30, 1.7), gp.call(isl.spawn.x, isl.spawn.z - 80, 3.0)])
		out.append(["forest_shop", gp.call(isl.shop_pos.x + 3, isl.shop_pos.z + 9, 1.7), isl.shop_pos + Vector3(0, 1.5, 0)])
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
