extends Node
## 玩家设置：灵敏度、视野、音量、服务器地址等。保存在 user://settings.cfg。
## 按键在这里注册（不写在 project.godot 里，方便以后做改键）。

signal changed

const PATH := "user://settings.cfg"
const DEFAULT_SERVER := "wss://douluo-relay.onrender.com"

var player_name := ""
var wuhun := 0                     # Data.WUHUN 的下标
var sensitivity := 2.0             # 每个鼠标计数转 0.022°×sensitivity，和 CS/Apex 的数值习惯一样
var ads_sensitivity := 1.0         # 开镜时额外乘的系数（已经按视野自动缩放过）
var fov := 95.0                    # 16:9 下的水平视野
var invert_y := false
var master_volume := 0.8
var sfx_volume := 1.0
var fullscreen := false
var vsync := false
var max_fps := 0                   # 0 = 不限
var server_url := DEFAULT_SERVER
var show_fps := false
var quality := 2                   # 画质：0 低 / 1 中 / 2 高（草和植被密度下次进地图生效）


func _ready() -> void:
	# 不把一帧里的鼠标移动合成一个事件，每个原始移动都能收到
	Input.use_accumulated_input = false
	_register_inputs()
	load_settings()
	apply()


func _register_inputs() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE],
		"sprint": [KEY_SHIFT],
		"crouch": [KEY_CTRL],
		"lure": [KEY_E],
		"interact": [KEY_F],
		"reload": [KEY_R],
		"skill": [KEY_Q],
		"grenade": [KEY_G],
		"pill": [KEY_H],
		"wuhun_panel": [KEY_K],
		"weapon_1": [KEY_1],
		"weapon_2": [KEY_2],
		"weapon_3": [KEY_3],
		"weapon_4": [KEY_4],
		"weapon_5": [KEY_5],
		"scoreboard": [KEY_TAB],
		"pause": [KEY_ESCAPE],
		"fullscreen": [KEY_F11],
		"toggle_fps": [KEY_F3],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	var mouse := {
		"fire": MOUSE_BUTTON_LEFT,
		"aim": MOUSE_BUTTON_RIGHT,
		"weapon_next": MOUSE_BUTTON_WHEEL_DOWN,
		"weapon_prev": MOUSE_BUTTON_WHEEL_UP,
	}
	for action in mouse:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		var mb := InputEventMouseButton.new()
		mb.button_index = mouse[action]
		InputMap.action_add_event(action, mb)
	# 鼠标侧键也能甩引魂索
	var side := InputEventMouseButton.new()
	side.button_index = MOUSE_BUTTON_XBUTTON1
	InputMap.action_add_event("lure", side)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	player_name = cfg.get_value("player", "name", player_name)
	wuhun = int(cfg.get_value("player", "wuhun", wuhun))
	sensitivity = float(cfg.get_value("input", "sensitivity", sensitivity))
	ads_sensitivity = float(cfg.get_value("input", "ads_sensitivity", ads_sensitivity))
	invert_y = bool(cfg.get_value("input", "invert_y", invert_y))
	fov = float(cfg.get_value("video", "fov", fov))
	fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))
	vsync = bool(cfg.get_value("video", "vsync", vsync))
	max_fps = int(cfg.get_value("video", "max_fps", max_fps))
	show_fps = bool(cfg.get_value("video", "show_fps", show_fps))
	quality = clampi(int(cfg.get_value("video", "quality", quality)), 0, 2)
	master_volume = float(cfg.get_value("audio", "master", master_volume))
	sfx_volume = float(cfg.get_value("audio", "sfx", sfx_volume))
	server_url = str(cfg.get_value("net", "server", server_url))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "wuhun", wuhun)
	cfg.set_value("input", "sensitivity", sensitivity)
	cfg.set_value("input", "ads_sensitivity", ads_sensitivity)
	cfg.set_value("input", "invert_y", invert_y)
	cfg.set_value("video", "fov", fov)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "max_fps", max_fps)
	cfg.set_value("video", "show_fps", show_fps)
	cfg.set_value("video", "quality", quality)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("net", "server", server_url)
	cfg.save(PATH)


func apply() -> void:
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = max_fps
	var vp := get_viewport()
	if vp:
		vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][quality]
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if quality == 0 else Viewport.SCREEN_SPACE_AA_DISABLED
		RenderingServer.directional_shadow_atlas_set_size([2048, 4096, 4096][quality], true)
	var master := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master, linear_to_db(maxf(master_volume, 0.0001)))
	changed.emit()


func toggle_fullscreen() -> void:
	fullscreen = not fullscreen
	apply()
	save_settings()


## 16:9 下的水平视野换算成 Godot 相机用的垂直视野
func vertical_fov(hfov_deg: float) -> float:
	var h := deg_to_rad(hfov_deg)
	return rad_to_deg(2.0 * atan(tan(h * 0.5) / (16.0 / 9.0)))


func display_name() -> String:
	return player_name if player_name.strip_edges() != "" else "魂师"
