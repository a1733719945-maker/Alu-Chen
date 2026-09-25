class_name Hud
extends CanvasLayer
## 游戏内界面：准星、弹药、金魂币、引魂索提示、击杀奖励、暂停菜单、计分板。

var world: Node
var crosshair: Crosshair
var _root: Control
var _wallet: Label
var _room: Label
var _weapon: Label
var _ammo: Label
var _reload: Label
var _prompt: Label
var _toast: Label
var _toast_t := 0.0
var _feed: VBoxContainer
var _popup: VBoxContainer
var _popup_t := 0.0
var _bar_box: VBoxContainer
var _bar_a: ProgressBar
var _bar_b: ProgressBar
var _bar_label: Label
var _fps: Label
var _pause: Control
var _pause_menu: VBoxContainer
var _settings: SettingsPanel
var _scores: PanelContainer
var _scores_list: VBoxContainer
var _wallet_shown := 0.0
var _wallet_target := 0


func _ready() -> void:
	layer = 5
	_root = Control.new()
	UiKit.fill(_root)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	crosshair = Crosshair.new()
	crosshair.player = world.player
	UiKit.fill(crosshair)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(crosshair)

	# 左上：金魂币、房间
	var tl := VBoxContainer.new()
	tl.position = Vector2(28, 22)
	_root.add_child(tl)
	_wallet = UiKit.label("金魂币 0", 30, UiKit.GOLD, 8)
	tl.add_child(_wallet)
	_room = UiKit.label("", 18, UiKit.MOON, 6)
	tl.add_child(_room)
	_fps = UiKit.label("", 16, Color(0.8, 1, 0.8), 5)
	tl.add_child(_fps)

	# 右下：暗器与弹药
	var br := VBoxContainer.new()
	UiKit.place(br, Vector4(1, 1, 1, 1), Vector4(-620, -220, -40, -30))
	br.alignment = BoxContainer.ALIGNMENT_END
	_root.add_child(br)
	_weapon = UiKit.label("袖箭", 24, UiKit.MOON, 6)
	_weapon.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	br.add_child(_weapon)
	_ammo = UiKit.label("10 / 10", 44, Color.WHITE, 8)
	_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	br.add_child(_ammo)
	_reload = UiKit.label("", 18, UiKit.GOLD, 5)
	_reload.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	br.add_child(_reload)
	var keys := UiKit.label("1 袖箭  2 暴雨梨花针  R 换弹  E 引魂索", 15, UiKit.MIST, 5)
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	br.add_child(keys)

	# 下方中间：引魂索提示和拉力条
	var bc := VBoxContainer.new()
	UiKit.place(bc, Vector4(0.5, 1, 0.5, 1), Vector4(-420, -250, 420, -120))
	bc.alignment = BoxContainer.ALIGNMENT_END
	_root.add_child(bc)
	_bar_box = VBoxContainer.new()
	_bar_box.visible = false
	bc.add_child(_bar_box)
	_bar_label = UiKit.label("", 18, UiKit.MOON, 6)
	_bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bar_box.add_child(_bar_label)
	_bar_a = _bar(Color(0.55, 0.85, 1.0))
	_bar_box.add_child(_bar_a)
	_bar_b = _bar(Color(1.0, 0.4, 0.3))
	_bar_box.add_child(_bar_b)
	_prompt = UiKit.label("", 24, UiKit.MOON, 8)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bc.add_child(_prompt)

	# 上方中间：提示
	_toast = UiKit.label("", 22, Color.WHITE, 8)
	UiKit.place(_toast, Vector4(0.5, 0, 0.5, 0), Vector4(-560, 96, 560, 170))
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(_toast)

	# 右上：击杀信息
	_feed = VBoxContainer.new()
	UiKit.place(_feed, Vector4(1, 0, 1, 0), Vector4(-640, 24, -30, 320))
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	_root.add_child(_feed)

	# 准星下方：击杀奖励
	_popup = VBoxContainer.new()
	UiKit.place(_popup, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-320, 56, 320, 300))
	_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_popup)

	_build_scores()
	_build_pause()
	set_wallet(world.wallet)


func _bar(color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(420, 14)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.show_percentage = false
	b.max_value = 1.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bg.set_corner_radius_all(7)
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	fg.set_corner_radius_all(7)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	return b


func _build_scores() -> void:
	_scores = PanelContainer.new()
	_scores.add_theme_stylebox_override("panel", UiKit.panel_style(Color(0.05, 0.14, 0.12, 0.88)))
	UiKit.place(_scores, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-300, -240, 300, 240))
	_scores.visible = false
	_root.add_child(_scores)
	_scores_list = VBoxContainer.new()
	_scores.add_child(_scores_list)


func _build_pause() -> void:
	_pause = ColorRect.new()
	(_pause as ColorRect).color = Color(0, 0, 0, 0.55)
	UiKit.fill(_pause)
	_pause.visible = false
	add_child(_pause)
	var center := CenterContainer.new()
	_pause.add_child(center)
	UiKit.fill(center)
	var stack := VBoxContainer.new()
	center.add_child(stack)
	_pause_menu = VBoxContainer.new()
	_pause_menu.add_theme_constant_override("separation", 12)
	_pause_menu.custom_minimum_size = Vector2(420, 0)
	stack.add_child(_pause_menu)
	_pause_menu.add_child(UiKit.title("暂停", 56))
	var code := UiKit.label("", 22, UiKit.GOLD)
	code.name = "Code"
	_pause_menu.add_child(code)
	var resume := UiKit.button("继续游戏", 24, true)
	resume.pressed.connect(func(): world.set_paused(false))
	_pause_menu.add_child(resume)
	var settings := UiKit.button("设置", 22)
	settings.pressed.connect(func(): _pause_menu.visible = false; _settings.visible = true)
	_pause_menu.add_child(settings)
	var quit := UiKit.button("返回主菜单", 22)
	quit.pressed.connect(func(): world.leave())
	_pause_menu.add_child(quit)
	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.closed.connect(func(): _settings.visible = false; _pause_menu.visible = true)
	stack.add_child(_settings)


func show_pause(on: bool) -> void:
	_pause.visible = on
	_pause_menu.visible = true
	_settings.visible = false
	var code: Label = _pause_menu.get_node("Code")
	if Net.is_online():
		code.text = "房间码  %s  （发给朋友，在主菜单输入即可加入）" % Net.room_code
	else:
		code.text = "单人模式"


# ------------------------------------------------------------------ 外部调用

func on_ammo(_w: int, ammo: int, mag: int) -> void:
	_ammo.text = "%d / %d" % [ammo, mag]
	_ammo.add_theme_color_override("font_color", Color(1, 0.45, 0.35) if ammo == 0 else Color.WHITE)


func on_weapon(w: int) -> void:
	var d: Dictionary = Data.WEAPONS[w]
	_weapon.text = d["name"]
	on_ammo(w, world.player.ammo[w], d["mag"])


func set_wallet(v: int) -> void:
	_wallet_target = v


func hitmarker(headshot: bool, kill: bool) -> void:
	crosshair.hit(headshot, kill)


func toast(text: String, color := Color.WHITE, time := 2.6) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	_toast_t = time


func feed(text: String, color := Color.WHITE) -> void:
	var l := UiKit.label(text, 18, color, 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_feed.add_child(l)
	while _feed.get_child_count() > 6:
		_feed.get_child(0).queue_free()
		_feed.remove_child(_feed.get_child(0))
	var tw := l.create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


func kill_popup(reward: int, tags: Array, species: String, age: int) -> void:
	for c in _popup.get_children():
		c.queue_free()
	var big := UiKit.label("+%d 金魂币" % reward, 40, UiKit.GOLD, 10)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_popup.add_child(big)
	var who := UiKit.label("%s · %s" % [Data.age_name(age), Data.BEASTS[species]["name"]], 20, Data.age_color(age), 6)
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_popup.add_child(who)
	for t in tags:
		var l := UiKit.label(str(t), 18, Color(1, 0.95, 0.8), 6)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_popup.add_child(l)
	_popup.modulate.a = 1.0
	_popup.scale = Vector2.ONE * 1.25
	_popup.pivot_offset = Vector2(320, 20)
	var tw := _popup.create_tween()
	tw.tween_property(_popup, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_popup_t = 2.2


# ------------------------------------------------------------------ 每帧

func _process(dt: float) -> void:
	var p: Player = world.player
	# 金魂币数字滚动
	_wallet_shown = move_toward(_wallet_shown, _wallet_target, maxf(absf(_wallet_target - _wallet_shown) * dt * 6.0, dt * 20.0))
	_wallet.text = "金魂币  %d" % roundi(_wallet_shown)
	if Net.is_online():
		_room.text = "房间 %s · %d 人" % [Net.room_code, Net.peers.size() + 1]
	else:
		_room.text = "单人模式"
	_fps.text = ("%d FPS" % Engine.get_frames_per_second()) if Settings.show_fps else ""

	var w: Dictionary = Data.WEAPONS[p.weapon]
	if p.reloading:
		_reload.text = "装针中…" if w["reload_per_shell"] else "换弹中…"
	elif p.ammo[p.weapon] == 0:
		_reload.text = "按 R 换弹"
	else:
		_reload.text = ""

	_toast_t -= dt
	_toast.modulate.a = clampf(_toast_t / 0.4, 0.0, 1.0)
	_popup_t -= dt
	_popup.modulate.a = clampf(_popup_t / 0.5, 0.0, 1.0)

	_update_lure_ui(p)

	var show_scores: bool = Input.is_action_pressed("scoreboard") and not world.paused
	if show_scores != _scores.visible:
		_scores.visible = show_scores
		if show_scores:
			_fill_scores()


func _update_lure_ui(p: Player) -> void:
	var lure := p.lure
	_bar_box.visible = false
	var t := Time.get_ticks_msec() / 1000.0
	match lure.state:
		Lure.S.IDLE:
			_prompt.text = "按住 E 蓄力 · 松开甩出引魂索"
			_prompt.add_theme_font_size_override("font_size", 18)
			_prompt.modulate = Color(1, 1, 1, 0.55)
		Lure.S.CHARGING:
			_prompt.text = "松开 E 甩出去"
			_prompt.add_theme_font_size_override("font_size", 20)
			_prompt.modulate = Color(1, 1, 1, 0.85)
		Lure.S.FLYING:
			_prompt.text = ""
		Lure.S.WAITING:
			_prompt.add_theme_font_size_override("font_size", 20)
			_prompt.modulate = Color(1, 1, 1, 0.8)
			if lure.habitat == "":
				_prompt.text = "这里没有魂兽 · 按 E 收回"
			else:
				_prompt.text = "等魂兽咬住…（%s）· 按 E 收回" % Data.HABITATS[lure.habitat]["name"]
		Lure.S.BITE:
			_prompt.text = "咬住了！按 E 拽！"
			_prompt.add_theme_font_size_override("font_size", 34)
			var flash := 0.75 + 0.25 * sin(t * 25.0)
			var c := Data.age_color(lure.age) if lure.age > 0 else Color(1.0, 0.9, 0.35)
			_prompt.modulate = Color(c.r, c.g, c.b, flash)
		Lure.S.REELING:
			_prompt.text = "按住 E 拉！拉力变红就松开"
			_prompt.add_theme_font_size_override("font_size", 26)
			_prompt.modulate = Color(0.85, 0.65, 1.0)
			_bar_box.visible = true
			_bar_label.text = "千年%s · 拉上来的进度 / 拉力" % Data.BEASTS[lure.species]["name"]
			_bar_a.value = lure.reel_progress
			_bar_b.value = lure.reel_tension
			var fill: StyleBoxFlat = _bar_b.get_theme_stylebox("fill")
			fill.bg_color = Color(0.5, 0.9, 0.5).lerp(Color(1.0, 0.25, 0.2), smoothstep(0.4, 0.9, lure.reel_tension))
		Lure.S.RETURNING:
			_prompt.text = ""


func _fill_scores() -> void:
	for c in _scores_list.get_children():
		c.queue_free()
	_scores_list.add_child(UiKit.title("魂师榜", 40))
	_scores_list.add_child(UiKit.label("全队金魂币  %d" % world.wallet, 22, UiKit.GOLD))
	var header := HBoxContainer.new()
	for t in [["魂师", 260], ["击杀", 110], ["赚取", 110]]:
		var l := UiKit.label(t[0], 18, UiKit.MIST)
		l.custom_minimum_size.x = t[1]
		header.add_child(l)
	_scores_list.add_child(header)
	var ids: Array = world.stats.keys()
	ids.sort_custom(func(a, b): return world.stats[a]["earned"] > world.stats[b]["earned"])
	for id in ids:
		var row := HBoxContainer.new()
		var s: Dictionary = world.stats[id]
		var nm := Net.peer_name(id) + ("（你）" if id == Net.my_id else "") + ("  房主" if id == 1 and Net.is_online() else "")
		for t in [[nm, 260], [str(s["kills"]), 110], [str(s["earned"]), 110]]:
			var l := UiKit.label(t[0], 20)
			l.custom_minimum_size.x = t[1]
			row.add_child(l)
		_scores_list.add_child(row)
