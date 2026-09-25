extends Node
## 入口：主菜单 ↔ 游戏。

var menu: MainMenu
var world: World


func _ready() -> void:
	Net.connected.connect(_on_connected)
	Net.failed.connect(_on_failed)
	Net.disconnected.connect(_on_disconnected)
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
	if menu:
		menu.queue_free()
		menu = null
	if world:
		world.queue_free()
	world = World.new()
	world.name = "World"
	add_child(world)
	world.leave_requested.connect(leave)
	if Net.is_online():
		world.hud.toast("已进入房间 %s。按 Esc 可以看到房间码，发给朋友就能加入" % Net.room_code, Color(1, 0.9, 0.6), 7.0)


func _on_failed(reason: String) -> void:
	if menu:
		menu.set_busy(false)
		menu.set_status(reason, true)


func _on_disconnected(reason: String) -> void:
	_back_to_menu(reason, true)


func leave() -> void:
	Net.close()
	_back_to_menu("", false)


func _back_to_menu(status: String, error: bool) -> void:
	if world:
		world.queue_free()
		world = null
	_show_menu(status, error)
