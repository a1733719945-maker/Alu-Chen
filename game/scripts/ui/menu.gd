class_name MainMenu
extends Control
## 主菜单：取名、选武魂、单人 / 建房间 / 加入房间。

signal solo
signal host_room
signal join_room(code: String)
signal quit

var _name: LineEdit
var _code: LineEdit
var _status: Label
var _wuhun_btns: Array[Button] = []
var _wuhun_name: Label
var _wuhun_pic: TextureRect
var _main: HBoxContainer
var _settings: SettingsPanel
var _buttons: Array[Button] = []


func _ready() -> void:
	UiKit.fill(self)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.15, 0.13)
	add_child(bg)
	UiKit.fill(bg)
	# 一点点光晕
	var glow := TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.25, 0.45, 0.4, 0.55))
	g.set_color(1, Color(0.06, 0.15, 0.13, 0.0))
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 0.9)
	glow.texture = gt
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(glow)
	UiKit.fill(glow)

	var center := CenterContainer.new()
	add_child(center)
	UiKit.fill(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	center.add_child(col)

	var title := UiKit.title("斗罗大陆 · 猎魂", 84, UiKit.MOON)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub := UiKit.label("用引魂索把魂兽拽上天，用唐门暗器在空中击杀 · 最多 8 人联机", 20, UiKit.MIST)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	_main = HBoxContainer.new()
	_main.add_theme_constant_override("separation", 26)
	col.add_child(_main)

	# 左：名字与武魂
	var left := PanelContainer.new()
	left.add_theme_stylebox_override("panel", UiKit.panel_style())
	_main.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 10)
	left.add_child(lv)
	lv.add_child(UiKit.label("你的名字", 18, UiKit.MIST))
	_name = LineEdit.new()
	_name.max_length = 10
	_name.placeholder_text = "输入名字"
	_name.text = Settings.player_name
	_name.add_theme_font_size_override("font_size", 22)
	_name.custom_minimum_size = Vector2(420, 44)
	_name.text_changed.connect(func(t): Settings.player_name = t.strip_edges(); Settings.save_settings())
	lv.add_child(_name)
	lv.add_child(UiKit.label("武魂（这一版只决定你的魂环颜色，魂技下个版本加入）", 16, UiKit.MIST))
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 14)
	lv.add_child(wrow)
	_wuhun_pic = TextureRect.new()
	_wuhun_pic.custom_minimum_size = Vector2(150, 150)
	_wuhun_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_wuhun_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	wrow.add_child(_wuhun_pic)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	wrow.add_child(grid)
	for i in Data.WUHUN.size():
		var b := UiKit.button(Data.WUHUN[i]["name"], 16)
		b.custom_minimum_size = Vector2(84, 40)
		b.pressed.connect(_pick_wuhun.bind(i))
		grid.add_child(b)
		_wuhun_btns.append(b)
	_wuhun_name = UiKit.label("", 20, UiKit.GOLD)
	lv.add_child(_wuhun_name)

	# 右：开始
	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", UiKit.panel_style())
	_main.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 12)
	rv.custom_minimum_size = Vector2(380, 0)
	right.add_child(rv)
	var b_solo := UiKit.button("单人游戏", 26, true)
	b_solo.pressed.connect(func(): solo.emit())
	rv.add_child(b_solo)
	var b_host := UiKit.button("创建联机房间", 24)
	b_host.pressed.connect(func(): host_room.emit())
	rv.add_child(b_host)
	var jrow := HBoxContainer.new()
	jrow.add_theme_constant_override("separation", 8)
	_code = LineEdit.new()
	_code.placeholder_text = "房间码"
	_code.max_length = 8
	_code.add_theme_font_size_override("font_size", 24)
	_code.custom_minimum_size = Vector2(150, 50)
	_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code.text_submitted.connect(func(t): join_room.emit(t))
	jrow.add_child(_code)
	var b_join := UiKit.button("加入房间", 22)
	b_join.pressed.connect(func(): join_room.emit(_code.text))
	jrow.add_child(b_join)
	rv.add_child(jrow)
	var b_set := UiKit.button("设置", 20)
	b_set.pressed.connect(func(): _main.visible = false; _settings.visible = true)
	rv.add_child(b_set)
	var b_quit := UiKit.button("退出", 20)
	b_quit.pressed.connect(func(): quit.emit())
	rv.add_child(b_quit)
	_buttons = [b_solo, b_host, b_join]

	_status = UiKit.label("", 20, UiKit.GOLD)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(900, 0)
	col.add_child(_status)

	var help := UiKit.label("WASD 移动 · 空格 跳 · Shift 冲刺 · Ctrl 蹲 · 左键 射击 · 右键 瞄准 · R 换弹 · 1/2 切换暗器 · E 引魂索 · Tab 魂师榜 · Esc 暂停", 16, UiKit.MIST)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(help)
	var ver := UiKit.label("版本 %s · 第一版（手感测试）" % ProjectSettings.get_setting("application/config/version", "0"), 14, Color(0.5, 0.6, 0.57))
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(ver)

	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.closed.connect(func(): _settings.visible = false; _main.visible = true)
	col.add_child(_settings)

	_pick_wuhun(Settings.wuhun, true)


func _pick_wuhun(i: int, silent := false) -> void:
	Settings.wuhun = i
	if not silent:
		Settings.save_settings()
	var w: Dictionary = Data.WUHUN[i]
	_wuhun_pic.texture = load(w["img"])
	_wuhun_name.text = "%s · %s" % [w["name"], w["kind"]]
	for k in _wuhun_btns.size():
		_wuhun_btns[k].modulate = Color(1, 1, 1) if k == i else Color(0.75, 0.8, 0.78)
		_wuhun_btns[k].add_theme_color_override("font_color", UiKit.GOLD if k == i else UiKit.MOON)


func set_status(text: String, error := false) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", Color(1, 0.55, 0.45) if error else UiKit.GOLD)


func set_busy(busy: bool) -> void:
	for b in _buttons:
		b.disabled = busy
