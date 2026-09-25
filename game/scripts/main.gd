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


func _ready() -> void:
	Net.connected.connect(_on_connected)
	Net.failed.connect(_on_failed)
	Net.disconnected.connect(_on_disconnected)
	Net.message.connect(_on_message)
	Net.status.connect(func(t): if menu: menu.set_status(t))
	var args := _args()
	if args.has("autotest"):
		var at := AutoTest.new()
		at.main = self
		at.mode = str(args["autotest"])
		at.args = args
		add_child(at)
		return
	_show_menu()


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
		_start_world(Profile.chapter, false)
		if Net.is_online():
			world.hud.toast("已进入房间 %s。按 Esc 可以看到房间码，发给朋友就能加入" % Net.room_code, Color(1, 0.9, 0.6), 7.0)
	else:
		_waiting_init = true
		_queue.clear()
		if menu:
			menu.set_status("已连上，正在同步房主的进度…")
		Net.send(0, "hello", [Settings.display_name(), Settings.wuhun, true, Profile.level, _ring_summary()])


func _ring_summary() -> Array:
	var out := []
	for r in Profile.rings:
		out.append(int(r["age"]))
	return out


func _start_world(chapter: int, announce: bool) -> void:
	if menu:
		menu.queue_free()
		menu = null
	if world:
		world.queue_free()
		world = null
	if not Data.CHAPTERS.has(chapter):
		chapter = 1
	world = World.new(chapter)
	world.name = "World"
	add_child(world)
	world.leave_requested.connect(leave)
	world.travel_requested.connect(_travel)
	if announce and Net.is_online():
		Net.send(0, "hello", world.hello_payload(true))


func _travel(chapter: int) -> void:
	# 坐船换章节：所有人一起换地图，换完再互相打招呼
	_start_world(chapter, true)


func _on_message(from: int, type: String, data: Variant) -> void:
	if _waiting_init:
		_queue.append([from, type, data])
		if type == "init":
			_waiting_init = false
			_start_world(int(data[0]), false)
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
