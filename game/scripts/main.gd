extends Node
## 入口：主菜单 ↔ 游戏。
##
## 单人 / 房主：直接用自己存档里的章节建地图。
## 客人：连上后先打招呼，等房主回 "init"（里面有当前章节），再建地图。
## 地图还没建好时收到的联机消息先存起来，建好后按顺序交给地图。

var menu: MainMenu
var world: World
var _waiting_init := false
var _queue: Array = []
var _sailing := false        # 正在播开船动画：这期间收到的联机消息先存着，新地图建好再给它



func _ready() -> void:
	# 输入框、滑条、勾选框、下拉框、滚动条的统一样式（合进引擎默认主题，CanvasLayer 下面的界面也能用上）
	ThemeDB.get_default_theme().merge_with(UiKit.make_theme())
	Net.connected.connect(_on_connected)
	Net.failed.connect(_on_failed)
	Net.disconnected.connect(_on_disconnected)
	Net.message.connect(_on_message)
	Net.status.connect(func(t): if menu: menu.set_status(t))
	var args := _args()
	if args.has("autotest"):
		Data.autotest = true
		var at := AutoTest.new()
		at.main = self
		at.mode = str(args["autotest"])
		at.args = args
		add_child(at)
		return
	_show_menu()


## 手机的返回键：游戏里等于 Esc（暂停 / 关面板），主菜单里退出游戏
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if world and is_instance_valid(world) and world.is_inside_tree():
			var ev := InputEventAction.new()
			ev.action = "pause"
			ev.pressed = true
			Input.parse_input_event(ev)
			var up := InputEventAction.new()
			up.action = "pause"
			up.pressed = false
			Input.parse_input_event.call_deferred(up)
		else:
			get_tree().quit()


func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out


func _show_menu(status := "", error := false) -> void:
	if menu:
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu = MainMenu.new()
	add_child(menu)
	menu.solo.connect(start_solo)

	menu.host_room.connect(start_host)
	menu.join_room.connect(start_join)
	menu.quit.connect(func(): get_tree().quit())
	menu.prologue.connect(func():
		menu.visible = false
		await play_prologue()
		if menu:
			menu.visible = true)
	if status != "":
		menu.set_status(status, error)


func start_solo() -> void:
	Net.start_offline()


func start_host(room := "") -> void:
	if menu:
		menu.set_busy(true)
		menu.set_status("正在连接服务器…")
	Net.host(Settings.server_url, Settings.display_name(), room)


func start_join(code: String) -> void:
	code = code.strip_edges().to_upper()
	if code.length() < 4:
		if menu:
			menu.set_status("请输入朋友给你的 4 位房间码", true)
		return
	if menu:
		menu.set_busy(true)
		menu.set_status("正在连接服务器…")
	Net.join(Settings.server_url, code, Settings.display_name())


func _on_connected(_code: String) -> void:
	if Net.is_host():
		# 这个存档第一次进游戏：先看序章（天倾、五大灵主、栖霞村、怎么玩）
		if int(Profile.stats.get("prologue", 0)) == 0 and not Data.autotest:
			Profile.stats["prologue"] = 1
			Profile.mark_dirty()
			await play_prologue()
		var layer: CanvasLayer = null
		if not Data.autotest:
			var ch: Dictionary = Data.CHAPTERS.get(Profile.chapter, {})
			layer = _loading_layer("正在进入%s……" % str(ch.get("name", "")))
			await get_tree().process_frame
			await get_tree().process_frame
		_start_world(Profile.chapter, false)
		if layer:
			layer.queue_free()
		if Net.is_online():
			world.hud.toast("已进入房间 %s。按 Esc 可以看到房间码，发给朋友就能加入" % Net.room_code, Color(1, 0.9, 0.6), 7.0)
	else:
		_waiting_init = true
		_queue.clear()
		if menu:
			menu.set_status("已连上，正在同步房主的进度…")
		Net.send(0, "hello", [Settings.display_name(), Settings.wuhun, true, Profile.level, _ring_summary()])


## 序章（Remotion 画的，48 秒）：主菜单"序章"也能重看
func play_prologue() -> void:
	var v := Voyage.new()
	v.video = "res://assets/cutscene/prologue.ogv"
	v.length = 50.0
	v.music = "event"
	add_child(v)
	await v.finished
	Sfx.play_music("explore")


func _ring_summary() -> Array:
	var out := []
	for r in Profile.rings:
		out.append(int(r["age"]))
	return out


## hunt：去这一章的猎场（空 = 岛上）
func _start_world(chapter: int, announce: bool, hunt := {}) -> void:
	if menu:
		menu.queue_free()
		menu = null
	if world:
		world.queue_free()
		world = null
	if not Data.CHAPTERS.has(chapter):
		chapter = 1
	world = World.new(chapter, hunt)
	world.name = "World"
	add_child(world)
	world.leave_requested.connect(leave)
	world.travel_requested.connect(_travel)
	world.map_requested.connect(_change_map)
	if announce and Net.is_online():
		Net.send(0, "hello", world.hello_payload(true))


## 换地图时盖在最上面的"正在前往……"（建地图时画面不动，至少让人知道在加载）
func _loading_layer(text: String) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.05, 0.94)
	UiKit.fill(bg)
	layer.add_child(bg)
	var l := UiKit.title(text, 40, UiKit.GOLD)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiKit.fill(l)
	layer.add_child(l)
	var sub := UiKit.label("手机 / 平板上要十几秒，别关游戏", 18, UiKit.MIST)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiKit.place(sub, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-400, 40, 400, 80))
	sub.visible = Settings.is_mobile()
	layer.add_child(sub)
	return layer


## 去猎场 / 从猎场回岛：同一章换一张图（不播开船动画）
func _change_map(chapter: int, hunt: Dictionary) -> void:
	if Data.autotest:
		_start_world(chapter, true, hunt)
		return
	# 建猎场要几秒：先盖一层"正在前往"，画出来了再建（不然画面停在旧图上像卡死了）
	_sailing = true
	_queue.clear()
	if world:
		world.process_mode = Node.PROCESS_MODE_DISABLED
	# 去猎场：先播一小段"猎场"过场（猎物的名字叠在上面），再盖"正在前往"建图
	if not hunt.is_empty():
		var sp := str(hunt.get("species", ""))
		var hv := Voyage.new()
		hv.video = "res://assets/cutscene/hunt.ogv"
		hv.length = 4.0
		hv.title = "猎场 · %s%s王" % [Data.age_name(int(hunt.get("age", 0))), Data.BEASTS[sp]["name"]] if Data.BEASTS.has(sp) else "猎场 · 灵兽王"
		add_child(hv)
		await hv.finished
	var layer := _loading_layer("正在前往猎场……" if not hunt.is_empty() else "正在回岛……")
	await get_tree().process_frame
	await get_tree().process_frame
	_start_world(chapter, true, hunt)
	layer.queue_free()
	_sailing = false
	var q := _queue.duplicate()
	_queue.clear()
	for m in q:
		world.on_message(m[0], m[1], m[2])


func _travel(chapter: int) -> void:
	# 坐船换章节：先播开船动画（Remotion 做的），所有人一起换地图，换完再互相打招呼
	if Data.autotest or not Data.CHAPTERS.has(chapter):
		_start_world(chapter, true)
		return
	_sailing = true
	_queue.clear()
	if world:
		world.process_mode = Node.PROCESS_MODE_DISABLED
		world.hud.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var v := Voyage.new()
	v.title = "前往 · %s" % Data.CHAPTERS[chapter]["name"]
	v.length = 8.0
	v.captions = [[1.4, 7.4, str(Data.CHAPTERS[chapter].get("story", ""))]]
	add_child(v)
	await v.finished
	# 建新岛要一会儿（平板上十几秒）：先盖"正在前往"，画出来了再建，不然画面停在最后一帧像黑屏卡死
	var layer := _loading_layer("正在前往%s……" % Data.CHAPTERS[chapter]["name"])
	await get_tree().process_frame
	await get_tree().process_frame
	_sailing = false
	_start_world(chapter, true)
	layer.queue_free()
	var q := _queue.duplicate()
	_queue.clear()
	for m in q:
		world.on_message(m[0], m[1], m[2])


func _on_message(from: int, type: String, data: Variant) -> void:
	if _sailing:
		_queue.append([from, type, data])
		return
	if _waiting_init:
		_queue.append([from, type, data])
		if type == "init":
			_waiting_init = false
			var d0: Array = data
			_start_world(int(d0[0]), false, d0[8] if d0.size() > 8 and d0[8] is Dictionary else {})
			var q := _queue.duplicate()
			_queue.clear()
			for m in q:
				world.on_message(m[0], m[1], m[2])
		return
	if world:
		world.on_message(from, type, data)


func _on_failed(reason: String) -> void:
	_waiting_init = false
	if menu:
		menu.set_busy(false)
		menu.set_status(reason, true)


func _on_disconnected(reason: String) -> void:
	_back_to_menu(reason, true)


func leave() -> void:
	Net.close()
	_back_to_menu("", false)


func _back_to_menu(status: String, error: bool) -> void:
	_waiting_init = false
	if world:
		world.queue_free()
		world = null
	_show_menu(status, error)
