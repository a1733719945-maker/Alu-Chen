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
var music_volume := 0.6
var fullscreen := false
var vsync := false
var max_fps := 0                   # 0 = 不限
var server_url := DEFAULT_SERVER
var show_fps := false
var quality := 2                   # 画质：0 低 / 1 中 / 2 高 / 3 极高（草和植被密度下次进地图生效）
const QUALITY_MAX := 3
var save_slot := 1                # 用哪个存档位（1~3）
var scope_zoom := 6.0              # 狙击镜倍率（开镜时滚轮调，4~12 倍，记住上次的）
# 手机 / 触屏
var touch := -1                    # 触屏操作：-1 自动（手机上开）/ 0 关 / 1 开
var touch_sens := 1.0              # 触屏滑动转视角的灵敏度
var touch_size := 1.0              # 触屏按钮大小
var aim_assist := true             # 触屏辅助瞄准（准星附近有灵兽时轻轻吸过去）
var ui_scale := 1.0                # 界面大小（手机上在按屏幕尺寸自动放大的基础上再乘）
var render_scale := 1.0            # 3D 画面渲染分辨率（手机默认 0.75：省电、不烫、不卡）
var _force_touch := false          # 命令行 --touch：电脑上也用触屏操作（测试用）


func _ready() -> void:
	# 不把一帧里的鼠标移动合成一个事件，每个原始移动都能收到
	Input.use_accumulated_input = false
	_force_touch = "--touch" in OS.get_cmdline_user_args()
	if is_mobile():
		# 手机默认：低画质、渲染分辨率 75%、60 帧
		quality = 0
		render_scale = 0.75
		max_fps = 60
	elif is_mac():
		# Mac：Retina 屏像素是普通屏的 2~4 倍，默认中画质，3D 画面按屏幕降到约 1920×1200 再放大
		quality = 1
		render_scale = mac_render_scale()
	_register_inputs()
	load_settings()
	apply()
	_fit_window.call_deferred()


## 是不是手机 / 平板（导出的安卓、苹果版）
func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")


func is_mac() -> bool:
	return OS.get_name() == "macOS"


## Mac 默认的 3D 渲染比例：3D 画面大约 230 万像素（Retina 笔记本约 0.65，外接 1080p 屏是 1）
func mac_render_scale() -> float:
	if DisplayServer.get_name() == "headless":
		return 1.0
	var sz := DisplayServer.screen_get_size()
	return snappedf(clampf(sqrt(2.3e6 / maxf(float(sz.x * sz.y), 1.0)), 0.5, 1.0), 0.05)


## 窗口比屏幕大（13 寸 MacBook 放不下 1600×900 的窗口）：缩到屏幕可用区域的九成，居中
func _fit_window() -> void:
	if DisplayServer.get_name() == "headless" or fullscreen:
		return
	var area := DisplayServer.screen_get_usable_rect()
	var sz := DisplayServer.window_get_size()
	if area.size.x <= 0 or (sz.x <= area.size.x and sz.y <= area.size.y):
		return
	var k := minf(area.size.x * 0.92 / sz.x, area.size.y * 0.88 / sz.y)
	var ns := Vector2i(int(sz.x * k), int(sz.y * k))
	DisplayServer.window_set_size(ns)
	DisplayServer.window_set_position(area.position + (area.size - ns) / 2)


## 现在用不用触屏操作
func touch_active() -> bool:
	return touch == 1 or (touch == -1 and (is_mobile() or _force_touch))


## 触屏模式：鼠标按键不再触发开枪 / 开镜 / 切枪（手机上第一根手指会被当成鼠标左键）
func _strip_mouse_bindings() -> void:
	for action in ["fire", "aim", "weapon_next", "weapon_prev", "lure", "skill_1"]:
		for ev in InputMap.action_get_events(action):
			if ev is InputEventMouseButton:
				InputMap.action_erase_event(action, ev)


func _register_inputs() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE],
		"sprint": [KEY_SHIFT],
		"crouch": [KEY_CTRL, KEY_C],   # Mac 上按住 Ctrl 点鼠标会变成右键，所以 C 也能蹲
		"lure": [KEY_G],
		"interact": [KEY_F],
		"reload": [KEY_R],
		"skill_1": [KEY_Q],
		"skill_2": [KEY_E],
		"pill": [KEY_H],
		"throw": [KEY_T],
		"bait": [KEY_B],
		"map": [KEY_M],
		"wuhun_panel": [KEY_K],
		"holster": [KEY_X],
		"inspect": [KEY_V],
		"true_body": [KEY_Z],
		"achievements": [KEY_J],
		"hunt_board": [KEY_L],
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
	# 引魂索：G、鼠标中键、鼠标侧键都行（按住蓄力，松开甩出去）
	for b in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_XBUTTON1]:
		var side := InputEventMouseButton.new()
		side.button_index = b
		InputMap.action_add_event("lure", side)
	# 另一个侧键放第一个神通
	var side2 := InputEventMouseButton.new()
	side2.button_index = MOUSE_BUTTON_XBUTTON2
	InputMap.action_add_event("skill_1", side2)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	player_name = cfg.get_value("player", "name", player_name)
	wuhun = int(cfg.get_value("player", "wuhun", wuhun))
	save_slot = clampi(int(cfg.get_value("player", "slot", save_slot)), 1, 3)
	sensitivity = float(cfg.get_value("input", "sensitivity", sensitivity))
	scope_zoom = clampf(float(cfg.get_value("input", "scope_zoom", scope_zoom)), 4.0, 12.0)
	ads_sensitivity = float(cfg.get_value("input", "ads_sensitivity", ads_sensitivity))
	invert_y = bool(cfg.get_value("input", "invert_y", invert_y))
	fov = float(cfg.get_value("video", "fov", fov))
	fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))
	vsync = bool(cfg.get_value("video", "vsync", vsync))
	max_fps = int(cfg.get_value("video", "max_fps", max_fps))
	show_fps = bool(cfg.get_value("video", "show_fps", show_fps))
	quality = clampi(int(cfg.get_value("video", "quality", quality)), 0, QUALITY_MAX)
	master_volume = float(cfg.get_value("audio", "master", master_volume))
	sfx_volume = float(cfg.get_value("audio", "sfx", sfx_volume))
	music_volume = float(cfg.get_value("audio", "music", music_volume))
	server_url = str(cfg.get_value("net", "server", server_url))
	touch = clampi(int(cfg.get_value("touch", "mode", touch)), -1, 1)
	touch_sens = clampf(float(cfg.get_value("touch", "sens", touch_sens)), 0.2, 4.0)
	touch_size = clampf(float(cfg.get_value("touch", "size", touch_size)), 0.6, 1.6)
	aim_assist = bool(cfg.get_value("touch", "aim_assist", aim_assist))
	ui_scale = clampf(float(cfg.get_value("video", "ui_scale", ui_scale)), 0.7, 1.6)
	render_scale = clampf(float(cfg.get_value("video", "render_scale", render_scale)), 0.5, 1.0)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "wuhun", wuhun)
	cfg.set_value("player", "slot", save_slot)
	cfg.set_value("input", "sensitivity", sensitivity)
	cfg.set_value("input", "scope_zoom", scope_zoom)
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
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("net", "server", server_url)
	cfg.set_value("touch", "mode", touch)
	cfg.set_value("touch", "sens", touch_sens)
	cfg.set_value("touch", "size", touch_size)
	cfg.set_value("touch", "aim_assist", aim_assist)
	cfg.set_value("video", "ui_scale", ui_scale)
	cfg.set_value("video", "render_scale", render_scale)
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
		# 2026-09-30 量过（笔记本 RTX 4060，1080p，第一 / 二章）：以前的"高"（MSAA 4x、SSIL、影子四层 170 米）只有 11~12 帧——
		# 满地镂空的树叶草叶，MSAA 4x 每一层都要多算好几倍。现在低 / 中 / 高都用 FXAA、影子两层，高 28~33 帧；
		# 以前的"高"挪到"极高"（好显卡用）
		var q := clampi(quality, 0, QUALITY_MAX)
		vp.msaa_3d = Viewport.MSAA_4X if q >= 3 else Viewport.MSAA_DISABLED
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if q >= 3 else Viewport.SCREEN_SPACE_AA_FXAA
		RenderingServer.directional_shadow_atlas_set_size(4096 if q >= 3 else 2048, true)
		# 影子边缘柔化：每个有光照的像素（地面、水、树叶）都要多采样几次，项目设置里是"中等"，按画质分档
		RenderingServer.directional_soft_shadow_filter_set_quality([RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
			RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH][q])
		# 3D 画面按比例渲染再放大（手机上省很多），界面还是原分辨率
		# 电脑上降分辨率用 FSR（放大后更清楚），手机用最省的双线性
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR if is_mobile() or render_scale > 0.99 else Viewport.SCALING_3D_MODE_FSR
		vp.scaling_3d_scale = render_scale
		if is_mobile():
			vp.msaa_3d = Viewport.MSAA_DISABLED
			RenderingServer.directional_shadow_atlas_set_size(2048 if quality > 0 else 1024, true)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW)
	# 触屏：去掉鼠标按键绑定；关掉触屏时重新注册（action_add_event 不会重复加）
	if touch_active():
		_strip_mouse_bindings()
	else:
		_register_inputs()
	var master := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master, linear_to_db(maxf(master_volume, 0.0001)))
	changed.emit()


## 游戏画面（HUD）的界面缩放。只在玩的时候放大（TouchControls 里设）；
## 打开面板、暂停、主菜单时是 1（面板按 900 高设计，放大了会超出屏幕）
func hud_ui_scale() -> float:
	return auto_ui_scale() * ui_scale


## 手机上界面要放大多少：按屏幕的实际高度（英寸）算。电脑上是 1
func auto_ui_scale() -> float:
	if not is_mobile() and not _force_touch:
		return 1.0
	if _force_touch and not is_mobile():
		return 1.5                 # 电脑上模拟手机：按 6 寸手机横屏算
	var dpi := maxf(float(DisplayServer.screen_get_dpi()), 100.0)
	var sz := DisplayServer.screen_get_size()
	var h_in := minf(sz.x, sz.y) / dpi
	# 手机横屏高度大约 2.7 英寸 → 放大约 1.6 倍；7 寸以上的平板基本不用放大
	return clampf(4.4 / maxf(h_in, 1.0), 1.0, 1.7)


func toggle_fullscreen() -> void:
	fullscreen = not fullscreen
	apply()
	save_settings()


## 16:9 下的水平视野换算成 Godot 相机用的垂直视野
func vertical_fov(hfov_deg: float) -> float:
	var h := deg_to_rad(hfov_deg)
	return rad_to_deg(2.0 * atan(tan(h * 0.5) / (16.0 / 9.0)))


func display_name() -> String:
	return player_name if player_name.strip_edges() != "" else "修士"
