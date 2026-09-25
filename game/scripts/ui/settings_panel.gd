class_name SettingsPanel
extends PanelContainer
## 设置面板：主菜单和游戏里暂停时共用。

signal closed

var _server: LineEdit


func _ready() -> void:
	add_theme_stylebox_override("panel", UiKit.panel_style())
	custom_minimum_size = Vector2(560, 0)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	add_child(outer)
	# 标题栏：左边标题，右边返回（Esc 也能返回）
	var head := HBoxContainer.new()
	outer.add_child(head)
	var tt := UiKit.title("设置", 36)
	tt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tt)
	var back := UiKit.button("返回（Esc）", 18)
	back.pressed.connect(func(): closed.emit())
	head.add_child(back)
	# 选项多，放进可以滚动的区域，小屏幕也看得到底下的按钮
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(540, 460)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	_slider(v, "鼠标灵敏度", 0.2, 8.0, 0.05, Settings.sensitivity, func(x): Settings.sensitivity = x)
	_slider(v, "开镜灵敏度倍率", 0.3, 2.0, 0.05, Settings.ads_sensitivity, func(x): Settings.ads_sensitivity = x)
	_slider(v, "视野 FOV", 70.0, 120.0, 1.0, Settings.fov, func(x): Settings.fov = x)
	_slider(v, "总音量", 0.0, 1.0, 0.01, Settings.master_volume, func(x): Settings.master_volume = x)
	_slider(v, "音效音量", 0.0, 1.0, 0.01, Settings.sfx_volume, func(x): Settings.sfx_volume = x)
	_option(v, "画质", ["低（老电脑）", "中", "高"], Settings.quality, func(i): Settings.quality = i)
	_check(v, "鼠标 Y 轴反转", Settings.invert_y, func(b): Settings.invert_y = b)
	_check(v, "全屏（F11）", Settings.fullscreen, func(b): Settings.fullscreen = b)
	_check(v, "垂直同步（开了更稳，但会多一点延迟）", Settings.vsync, func(b): Settings.vsync = b)
	_check(v, "显示帧数（F3）", Settings.show_fps, func(b): Settings.show_fps = b)
	var srow := HBoxContainer.new()
	srow.add_child(UiKit.label("联机服务器", 18))
	_server = LineEdit.new()
	_server.text = Settings.server_url
	_server.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_server.text_changed.connect(func(t): Settings.server_url = t.strip_edges(); Settings.save_settings())
	srow.add_child(_server)
	v.add_child(srow)
	var reset := UiKit.button("恢复默认服务器", 16)
	reset.pressed.connect(func(): _server.text = Settings.DEFAULT_SERVER; Settings.server_url = Settings.DEFAULT_SERVER; Settings.save_settings())
	v.add_child(reset)
	var ok := UiKit.button("完成", 22, true)
	ok.pressed.connect(func(): closed.emit())
	outer.add_child(ok)


func _input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("pause"):
		closed.emit()
		get_viewport().set_input_as_handled()


func _slider(parent: Control, text: String, lo: float, hi: float, step: float, value: float, setter: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := UiKit.label(text, 18)
	l.custom_minimum_size.x = 170
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size.y = 28
	var val := UiKit.label(_fmt(value, step), 18)
	val.custom_minimum_size.x = 60
	s.value_changed.connect(func(x):
		setter.call(x)
		val.text = _fmt(x, step)
		Settings.apply()
		Settings.save_settings())
	row.add_child(s)
	row.add_child(val)
	parent.add_child(row)


func _fmt(x: float, step: float) -> String:
	return str(roundi(x)) if step >= 1.0 else ("%.2f" % x)


func _option(parent: Control, text: String, items: Array, value: int, setter: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := UiKit.label(text, 18)
	l.custom_minimum_size.x = 170
	row.add_child(l)
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.selected = value
	o.add_theme_font_size_override("font_size", 18)
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.item_selected.connect(func(i):
		setter.call(i)
		Settings.apply()
		Settings.save_settings())
	row.add_child(o)
	parent.add_child(row)


func _check(parent: Control, text: String, value: bool, setter: Callable) -> void:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = value
	c.add_theme_font_size_override("font_size", 18)
	c.toggled.connect(func(b):
		setter.call(b)
		Settings.apply()
		Settings.save_settings())
	parent.add_child(c)
