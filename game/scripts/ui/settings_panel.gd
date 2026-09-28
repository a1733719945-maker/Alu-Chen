class_name SettingsPanel
extends PanelContainer
## 设置面板：主菜单和游戏里暂停时共用。分成 操作 / 画面 / 声音 / 联机 四段，左边名字右边控件。

signal closed

var _server: LineEdit


func _ready() -> void:
	add_theme_stylebox_override("panel", UiKit.panel_style(Color(0.04, 0.05, 0.07, 0.94)))
	custom_minimum_size = Vector2(680, 0)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	add_child(outer)
	outer.add_child(UiKit.panel_head("选项", "设置", "Esc", func(): closed.emit()))
	# 选项多，放进可以滚动的区域，小屏幕也看得到底下的按钮
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(640, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	v.add_child(UiKit.section("操作", UiKit.GOLD))
	_slider(v, "鼠标灵敏度", 0.2, 8.0, 0.05, Settings.sensitivity, func(x): Settings.sensitivity = x)
	_slider(v, "开镜灵敏度倍率", 0.3, 2.0, 0.05, Settings.ads_sensitivity, func(x): Settings.ads_sensitivity = x)
	_check(v, "鼠标 Y 轴反转", Settings.invert_y, func(b): Settings.invert_y = b)
	v.add_child(UiKit.section("手机 · 触屏", UiKit.GOLD))
	# 选项顺序：自动 / 关 / 开 ↔ Settings.touch = -1 / 0 / 1
	_option(v, "触屏按钮", ["自动（手机上开）", "关", "开"], [-1, 0, 1].find(Settings.touch), func(i): Settings.touch = [-1, 0, 1][i])
	_slider(v, "滑屏转视角灵敏度", 0.3, 3.0, 0.05, Settings.touch_sens, func(x): Settings.touch_sens = x)
	_slider(v, "按钮大小", 0.7, 1.4, 0.05, Settings.touch_size, func(x): Settings.touch_size = x)
	_check(v, "辅助瞄准（准星附近的灵兽轻轻吸过去）", Settings.aim_assist, func(b): Settings.aim_assist = b)
	_slider(v, "界面大小", 0.8, 1.4, 0.05, Settings.ui_scale, func(x): Settings.ui_scale = x)
	v.add_child(UiKit.section("画面", UiKit.GOLD))
	_slider(v, "视野 FOV", 70.0, 120.0, 1.0, Settings.fov, func(x): Settings.fov = x)
	_option(v, "画质", ["低（老电脑 / 手机）", "中", "高"], Settings.quality, func(i): Settings.quality = i)
	_slider(v, "渲染分辨率（手机调低更流畅）", 0.5, 1.0, 0.05, Settings.render_scale, func(x): Settings.render_scale = x)
	_check(v, "全屏（F11）", Settings.fullscreen, func(b): Settings.fullscreen = b)
	_check(v, "垂直同步（更稳，但多一点延迟）", Settings.vsync, func(b): Settings.vsync = b)
	_check(v, "显示帧数（F3）", Settings.show_fps, func(b): Settings.show_fps = b)
	v.add_child(UiKit.section("声音", UiKit.GOLD))
	_slider(v, "总音量", 0.0, 1.0, 0.01, Settings.master_volume, func(x): Settings.master_volume = x)
	_slider(v, "音效", 0.0, 1.0, 0.01, Settings.sfx_volume, func(x): Settings.sfx_volume = x)
	_slider(v, "音乐", 0.0, 1.0, 0.01, Settings.music_volume, func(x): Settings.music_volume = x; Sfx.refresh_music_volume())
	v.add_child(UiKit.section("联机", UiKit.GOLD))
	var srow := _row(v, "服务器")
	_server = LineEdit.new()
	_server.text = Settings.server_url
	_server.add_theme_font_size_override("font_size", 16)
	_server.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_server.text_changed.connect(func(t): Settings.server_url = t.strip_edges(); Settings.save_settings())
	srow.add_child(_server)
	var reset := UiKit.button("恢复默认", 15)
	reset.pressed.connect(func(): _server.text = Settings.DEFAULT_SERVER; Settings.server_url = Settings.DEFAULT_SERVER; Settings.save_settings())
	srow.add_child(reset)
	var ok := UiKit.button("完成", 20, true)
	ok.pressed.connect(func(): closed.emit())
	outer.add_child(ok)


func _input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("pause"):
		closed.emit()
		get_viewport().set_input_as_handled()


## 一行：左边名字（固定宽），右边放控件
func _row(parent: Control, text: String) -> HBoxContainer:
	var p := PanelContainer.new()
	var st := UiKit.row_style()
	st.content_margin_top = 6
	st.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", st)
	parent.add_child(p)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	p.add_child(row)
	var l := UiKit.label(text, 17, UiKit.MOON)
	l.custom_minimum_size.x = 190
	row.add_child(l)
	return row


func _slider(parent: Control, text: String, lo: float, hi: float, step: float, value: float, setter: Callable) -> void:
	var row := _row(parent, text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size.y = 24
	var val := UiKit.num(_fmt(value, step), 20, UiKit.GOLD, 0)
	val.custom_minimum_size.x = 56
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.value_changed.connect(func(x):
		setter.call(x)
		val.text = _fmt(x, step)
		Settings.apply()
		Settings.save_settings())
	row.add_child(s)
	row.add_child(val)


func _fmt(x: float, step: float) -> String:
	return str(roundi(x)) if step >= 1.0 else ("%.2f" % x)


func _option(parent: Control, text: String, items: Array, value: int, setter: Callable) -> void:
	var row := _row(parent, text)
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.selected = value
	o.add_theme_font_size_override("font_size", 17)
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.item_selected.connect(func(i):
		setter.call(i)
		Settings.apply()
		Settings.save_settings())
	row.add_child(o)


func _check(parent: Control, text: String, value: bool, setter: Callable) -> void:
	var row := _row(parent, text)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	var c := CheckBox.new()
	c.button_pressed = value
	c.text = "开" if value else "关"
	c.add_theme_font_size_override("font_size", 16)
	c.toggled.connect(func(b):
		c.text = "开" if b else "关"
		setter.call(b)
		Settings.apply()
		Settings.save_settings())
	row.add_child(c)
