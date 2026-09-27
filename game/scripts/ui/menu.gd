class_name MainMenu
extends Control
## 主菜单：取名、选武魂、单人 / 建房间 / 加入房间、存档位。
## 样子（参考 Valorant / Apex 的主界面）：左边一列大字菜单，右边是选中武魂的立绘和九个武魂头像，底下三个存档位。

signal solo
signal expedition
signal host_room
signal join_room(code: String)
signal quit

var _name: LineEdit
var _code: LineEdit
var _status: Label
var _wuhun_btns: Array[Button] = []
var _wuhun_name: Label
var _wuhun_kind: Label
var _wuhun_art: TextureRect
var _main: Control
var _settings: SettingsPanel
var _buttons: Array[Button] = []
var _skills_hint: Label
var _save_info: Label
var _reset_btn: Button
var _reset_armed := false
var _slot_btns: Array = []
var _rebirth_btn: Button
var _rebirth_armed := false


func _ready() -> void:
	UiKit.fill(self)
	var bg := ColorRect.new()
	bg.color = Color(0.025, 0.03, 0.05)
	add_child(bg)
	UiKit.fill(bg)
	# 右边：选中武魂的立绘，往左、往下渐渐融进背景
	_wuhun_art = TextureRect.new()
	_wuhun_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_wuhun_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_wuhun_art.modulate = Color(1, 1, 1, 0.5)
	add_child(_wuhun_art)
	UiKit.place(_wuhun_art, Vector4(0.36, 0, 1, 1), Vector4.ZERO)
	for dir in [[Vector2(0, 0.5), Vector2(0.75, 0.5)], [Vector2(0.5, 1.0), Vector2(0.5, 0.45)]]:
		var fade := TextureRect.new()
		var gt := GradientTexture2D.new()
		var g := Gradient.new()
		g.set_color(0, Color(0.025, 0.03, 0.05, 1.0))
		g.set_color(1, Color(0.025, 0.03, 0.05, 0.0))
		gt.gradient = g
		gt.fill_from = dir[0]
		gt.fill_to = dir[1]
		fade.texture = gt
		fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fade.stretch_mode = TextureRect.STRETCH_SCALE
		add_child(fade)
		UiKit.place(fade, Vector4(0.36, 0, 1, 1), Vector4.ZERO)
	# 左上一点冷光
	var glow := TextureRect.new()
	var gt2 := GradientTexture2D.new()
	var g2 := Gradient.new()
	g2.set_color(0, Color(0.2, 0.3, 0.55, 0.35))
	g2.set_color(1, Color(0.02, 0.03, 0.05, 0.0))
	gt2.gradient = g2
	gt2.fill = GradientTexture2D.FILL_RADIAL
	gt2.fill_from = Vector2(0.15, 0.1)
	gt2.fill_to = Vector2(0.75, 0.9)
	glow.texture = gt2
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(glow)
	UiKit.fill(glow)

	_main = Control.new()
	_main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_main)
	UiKit.fill(_main)

	# ---- 左：标题和菜单
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	UiKit.place(left, Vector4(0, 0, 0, 1), Vector4(84, 70, 600, -230))
	_main.add_child(left)
	left.add_child(UiKit.kicker("斗罗大陆", UiKit.GOLD, 18))
	left.add_child(UiKit.title("猎魂", 96, Color.WHITE))
	var sub := UiKit.label("用引魂索把魂兽拽上天，用唐门暗器在空中击杀 · 最多 8 人联机", 16, UiKit.MIST)
	left.add_child(sub)
	var sp := Control.new()
	sp.custom_minimum_size.y = 30
	left.add_child(sp)
	var b_solo := UiKit.menu_item("单人游戏", true, 32)
	b_solo.pressed.connect(func(): solo.emit())
	left.add_child(b_solo)
	# 第十版：猎魂远征试玩（单人直接进；联机从任何一张图的渡船去）
	var b_exp := UiKit.menu_item("猎魂远征（试玩）", false, 32)
	b_exp.pressed.connect(func(): expedition.emit())
	left.add_child(b_exp)
	var b_host := UiKit.menu_item("创建联机房间", false, 32)
	b_host.pressed.connect(func(): host_room.emit())
	left.add_child(b_host)
	var jrow := HBoxContainer.new()
	jrow.add_theme_constant_override("separation", 10)
	left.add_child(jrow)
	var b_join := UiKit.menu_item("加入房间", false, 32)
	b_join.pressed.connect(func(): join_room.emit(_code.text))
	jrow.add_child(b_join)
	_code = LineEdit.new()
	_code.placeholder_text = "房间码"
	_code.max_length = 8
	_code.add_theme_font_size_override("font_size", 24)
	_code.custom_minimum_size = Vector2(170, 48)
	_code.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_code.text_submitted.connect(func(t): join_room.emit(t))
	jrow.add_child(_code)
	var b_set := UiKit.menu_item("设置", false, 32)
	b_set.pressed.connect(func(): _main.visible = false; _settings.visible = true)
	left.add_child(b_set)
	var b_quit := UiKit.menu_item("退出", false, 32)
	b_quit.pressed.connect(func(): quit.emit())
	left.add_child(b_quit)
	_buttons = [b_solo, b_exp, b_host, b_join]
	var sp2 := Control.new()
	sp2.custom_minimum_size.y = 10
	left.add_child(sp2)
	_status = UiKit.bold("", 18, UiKit.GOLD)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(500, 0)
	left.add_child(_status)

	# ---- 左下：存档位
	var saves := VBoxContainer.new()
	saves.add_theme_constant_override("separation", 8)
	UiKit.place(saves, Vector4(0, 1, 0, 1), Vector4(84, -210, 700, -56))
	_main.add_child(saves)
	saves.add_child(UiKit.section("存档", UiKit.MIST))
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 8)
	saves.add_child(srow)
	for n in [1, 2, 3]:
		var sb := Button.new()
		sb.custom_minimum_size = Vector2(196, 64)
		sb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		sb.add_theme_font_size_override("font_size", 14)
		sb.add_theme_font_override("font", Data.font_bold)
		sb.pressed.connect(func():
			Sfx.play("ui_click", -8.0)
			Settings.save_slot = n
			Settings.save_settings()
			Profile.use_slot(n)
			_refresh_save()
			_pick_wuhun(Settings.wuhun, true))
		srow.add_child(sb)
		_slot_btns.append(sb)
	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", 10)
	saves.add_child(info)
	_save_info = UiKit.label("", 14, UiKit.MIST)
	_save_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_save_info)
	_reset_btn = UiKit.button("清空这个存档", 13)
	_reset_btn.pressed.connect(_on_reset)
	info.add_child(_reset_btn)
	# 成神以后：转生（换武魂从 1 级再来，永久变强，魂兽也更凶）
	_rebirth_btn = UiKit.button("", 15, true)
	_rebirth_btn.pressed.connect(_on_rebirth)
	saves.add_child(_rebirth_btn)

	# ---- 右：名字和武魂
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	UiKit.place(right, Vector4(1, 0, 1, 1), Vector4(-560, 84, -84, -150))
	_main.add_child(right)
	right.add_child(UiKit.section("你的名字", UiKit.MIST))
	_name = LineEdit.new()
	_name.max_length = 10
	_name.placeholder_text = "输入名字"
	_name.text = Settings.player_name
	_name.add_theme_font_size_override("font_size", 22)
	_name.custom_minimum_size = Vector2(0, 46)
	_name.text_changed.connect(func(t): Settings.player_name = t.strip_edges(); Settings.save_settings())
	right.add_child(_name)
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	right.add_child(gap)
	right.add_child(UiKit.section("武魂", UiKit.MIST))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	right.add_child(grid)
	for i in Data.WUHUN.size():
		var b := _wuhun_tile(i)
		grid.add_child(b)
		_wuhun_btns.append(b)
	var nm := HBoxContainer.new()
	nm.add_theme_constant_override("separation", 12)
	right.add_child(nm)
	_wuhun_name = UiKit.title("", 34, UiKit.GOLD)
	nm.add_child(_wuhun_name)
	_wuhun_kind = UiKit.bold("", 15, UiKit.MIST)
	_wuhun_kind.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nm.add_child(_wuhun_kind)
	_skills_hint = UiKit.label("", 14, Color(0.8, 0.84, 0.9))
	_skills_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_skills_hint)

	# ---- 底：按键说明和版本
	var help := UiKit.label("WASD 移动 · 空格 跳 · 左键 射击 · 右键 瞄准 · G 引魂索 · Q / E / F 魂技 · F 交互 · 1-5 物品栏 · M 地图 · K 武魂 · Esc 暂停（里面有全部按键）", 13, UiKit.DIM)
	UiKit.place(help, Vector4(0, 1, 1, 1), Vector4(84, -38, -300, -14))
	_main.add_child(help)
	var ver := UiKit.label("版本 %s · 第六版" % ProjectSettings.get_setting("application/config/version", "0"), 13, UiKit.DIM)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiKit.place(ver, Vector4(1, 1, 1, 1), Vector4(-400, -38, -84, -14))
	_main.add_child(ver)

	var sc := CenterContainer.new()
	sc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sc)
	UiKit.fill(sc)
	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.closed.connect(func(): _settings.visible = false; _main.visible = true)
	sc.add_child(_settings)

	_refresh_save()
	_pick_wuhun(Settings.wuhun, true)


## 武魂头像：图 + 底下名字，选中的金边
func _wuhun_tile(i: int) -> Button:
	var w: Dictionary = Data.WUHUN[i]
	var b := Button.new()
	b.custom_minimum_size = Vector2(152, 96)
	b.clip_contents = true
	var pic := TextureRect.new()
	pic.texture = load(w["img"])
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(pic)
	UiKit.place(pic, Vector4(0, 0, 1, 1), Vector4(2, 2, -2, -2))
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(shade)
	UiKit.place(shade, Vector4(0, 1, 1, 1), Vector4(2, -30, -2, -2))
	var l := UiKit.bold(str(w["name"]), 15, Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_child(l)
	UiKit.place(l, Vector4(0, 1, 1, 1), Vector4(0, -30, 0, -4))
	b.pressed.connect(func():
		Sfx.play("ui_click", -8.0)
		_pick_wuhun(i))
	return b


func _tile_style(b: Button, on: bool) -> void:
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0, 0, 0, 0.4)
	n.border_color = UiKit.GOLD if on else Color(1, 1, 1, 0.12)
	n.set_border_width_all(2 if on else 1)
	var h := n.duplicate() as StyleBoxFlat
	h.border_color = UiKit.GOLD if on else Color(1, 1, 1, 0.55)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.modulate = Color.WHITE if on else Color(0.72, 0.74, 0.78)


func _enter_tree() -> void:
	if not Data.autotest and Settings.save_slot != Profile.slot:
		Profile.use_slot(Settings.save_slot)


func _pick_wuhun(i: int, silent := false) -> void:
	Settings.wuhun = i
	if not silent:
		Settings.save_settings()
	var w: Dictionary = Data.WUHUN[i]
	_wuhun_art.texture = load(w["img"])
	_wuhun_name.text = str(w["name"])
	_wuhun_name.add_theme_color_override("font_color", Data.wuhun_color(i))
	_wuhun_kind.text = str(w["kind"])
	for k in _wuhun_btns.size():
		_tile_style(_wuhun_btns[k], k == i)
	var lines := ["魂技不固定：吸收哪种魂兽的魂环，就领悟哪种魂技，吸收了才知道。", "同一种魂兽总给同一个魂技；魂兽年份越高，魂技越强。", "Q / E / F 三个键各放一个魂技，在 K 武魂面板里自己选装哪个。"]
	if not Profile.rings.is_empty():
		lines.append("（已经有的魂技不会因为换武魂而改变）")
	_skills_hint.text = "\n".join(lines)


func _on_rebirth() -> void:
	if not _rebirth_armed:
		_rebirth_armed = true
		_rebirth_btn.text = "确定转生？再点一次（等级、魂环、暗器、魂骨清零）"
		return
	_rebirth_armed = false
	if Profile.do_rebirth():
		set_status("转生成功！第%d世：伤害、体力 +%d%%，魂兽也凶了 %d%%。可以换一个武魂，领悟全新的魂技" % [Profile.rebirth + 1, Profile.rebirth * 25, Profile.rebirth * 30])
	_refresh_save()
	_pick_wuhun(Settings.wuhun, true)


func _refresh_save() -> void:
	if _rebirth_btn:
		_rebirth_btn.visible = Profile.god
		_rebirth_btn.text = "转生 · 开始第 %d 世（永久更强，魂兽更凶）" % (Profile.rebirth + 2)
	for i in _slot_btns.size():
		var b: Button = _slot_btns[i]
		var on := Profile.slot == i + 1
		b.text = "存档 %d\n%s" % [i + 1, Profile.slot_summary(i + 1)]
		var n := StyleBoxFlat.new()
		n.bg_color = Color(1, 1, 1, 0.08) if on else Color(1, 1, 1, 0.035)
		n.border_color = UiKit.GOLD if on else Color(1, 1, 1, 0.1)
		n.set_border_width_all(1)
		n.border_width_top = 3 if on else 1
		n.content_margin_left = 14
		n.content_margin_right = 14
		var h := n.duplicate() as StyleBoxFlat
		h.bg_color = Color(1, 1, 1, 0.1)
		b.add_theme_stylebox_override("normal", n)
		b.add_theme_stylebox_override("hover", h)
		b.add_theme_stylebox_override("pressed", h)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_theme_color_override("font_color", UiKit.GOLD if on else UiKit.MIST)
		b.add_theme_color_override("font_hover_color", UiKit.GOLD if on else Color.WHITE)
	if Profile.level <= 1 and Profile.money == 0 and Profile.rings.is_empty() and Profile.chapter == 1:
		_save_info.text = "新存档：从第一章 · 湖心岛开始"
		_reset_btn.visible = false
		return
	_reset_btn.visible = true
	var ch: String = Data.CHAPTERS[Profile.chapter]["name"] if Data.CHAPTERS.has(Profile.chapter) else ""
	_save_info.text = "%s · %s · %d 个魂环 · 金魂币 %d" % [ch, Profile.title(), Profile.rings.size(), Profile.money]


func _on_reset() -> void:
	if not _reset_armed:
		_reset_armed = true
		_reset_btn.text = "真的要清空吗？再点一次"
		return
	_reset_armed = false
	_reset_btn.text = "清空这个存档"
	Profile.reset()
	_refresh_save()
	_pick_wuhun(Settings.wuhun, true)


func set_status(text: String, error := false) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", UiKit.RED if error else UiKit.GOLD)


func set_busy(busy: bool) -> void:
	for b in _buttons:
		b.disabled = busy
