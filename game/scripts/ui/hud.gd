class_name Hud
extends CanvasLayer
## 游戏内界面。
##   左上：金魂币、任务追踪          上中：Boss 血条、提示        右上：击杀信息
##   左下：体力 / 护盾 / 魂力 / 修为、道具
##   下中：魂技栏（Q C X）、引魂索提示、交互提示
##   右下：暗器、弹药、暗器栏
##   准星、命中标记、击杀奖励、任务目标标记、狙击镜、受伤红屏、倒地倒计时
##   面板：暂停、暗器铺、武魂（K）、魂技二选一、魂师榜（Tab）

var world: Node
var crosshair: Crosshair
var _root: Control
var _money: Label
var _room: Label
var _fps: Label
var _quest_title: Label
var _quest_text: Label
var _quest_prog: Label
var _weapon: Label
var _ammo: Label
var _reload: Label
var _slots: Label
var _prompt: Label
var _interact: Label
var _toast: Label
var _toast_t := 0.0
var _feed: VBoxContainer
var _popup: VBoxContainer
var _popup_t := 0.0
var _bar_box: VBoxContainer
var _bar_a: ProgressBar
var _bar_b: ProgressBar
var _bar_label: Label
var _hp: ProgressBar
var _shield: ProgressBar
var _hp_text: Label
var _soul: ProgressBar
var _xp: ProgressBar
var _level: Label
var _items: Label
var _skills_n := -1
var _skill_boxes: Array = []
var _boss_box: VBoxContainer
var _boss_name: Label
var _boss_bar: ProgressBar
var _banner: VBoxContainer
var _banner_t := 0.0
var _callout: Label
var _callout_t := 0.0
var _vignette: ColorRect
var _vig_t := 0.0
var _hurt_dirs: Array = []
var _hurt_layer: Control
var _death: ColorRect
var _death_text: Label
var _scope: Control
var _marker: Control
var _absorb: Label
var _absorb_t := 0.0
var _pause: Control
var _pause_menu: VBoxContainer
var _settings: SettingsPanel
var _scores: PanelContainer
var _scores_list: VBoxContainer
var _shop: ShopPanel
var _wuhun: WuhunPanel
var _choice: Control
var _money_shown := 0.0


func _ready() -> void:
	layer = 5
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	UiKit.fill(_root)

	_vignette = ColorRect.new()
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.material = _vignette_material()
	_root.add_child(_vignette)
	UiKit.fill(_vignette)

	_scope = ScopeOverlay.new()
	_scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scope.visible = false
	_root.add_child(_scope)
	UiKit.fill(_scope)

	crosshair = Crosshair.new()
	crosshair.player = world.player
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(crosshair)
	UiKit.fill(crosshair)

	_hurt_layer = Control.new()
	_hurt_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hurt_layer.draw.connect(_draw_hurt)
	_root.add_child(_hurt_layer)
	UiKit.fill(_hurt_layer)

	_marker = Control.new()
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.draw.connect(_draw_marker)
	_root.add_child(_marker)
	UiKit.fill(_marker)

	_build_top_left()
	_build_bottom_left()
	_build_bottom_right()
	_build_bottom_center()
	_build_top_center()

	_feed = VBoxContainer.new()
	UiKit.place(_feed, Vector4(1, 0, 1, 0), Vector4(-640, 24, -30, 320))
	_root.add_child(_feed)

	_popup = VBoxContainer.new()
	_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.place(_popup, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-320, 56, 320, 300))
	_root.add_child(_popup)

	_callout = UiKit.title("", 56, UiKit.GOLD)
	_callout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_callout.add_theme_constant_override("outline_size", 12)
	_callout.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	UiKit.place(_callout, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-500, -230, 500, -150))
	_root.add_child(_callout)

	_banner = VBoxContainer.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.place(_banner, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-600, -320, 600, -120))
	_root.add_child(_banner)

	_absorb = UiKit.title("", 44, Color.WHITE)
	_absorb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_absorb.add_theme_constant_override("outline_size", 12)
	_absorb.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	UiKit.place(_absorb, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-500, 120, 500, 200))
	_root.add_child(_absorb)

	_death = ColorRect.new()
	_death.color = Color(0.35, 0.0, 0.0, 0.55)
	_death.visible = false
	_death.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_death)
	UiKit.fill(_death)
	_death_text = UiKit.title("", 64, Color(1, 0.85, 0.8))
	_death_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_death.add_child(_death_text)
	UiKit.fill(_death_text)

	_build_scores()
	_build_pause()
	_shop = ShopPanel.new()
	_shop.world = world
	_shop.visible = false
	_shop.closed.connect(_close_shop)
	add_child(_shop)
	_wuhun = WuhunPanel.new()
	_wuhun.visible = false
	_wuhun.closed.connect(func(): _wuhun.visible = false; world.set_ui_open(false))
	add_child(_wuhun)
	_money_shown = Profile.money
	update_quest()
	_refresh_skills()


func _vignette_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float amount = 0.0;
uniform vec4 tint : source_color = vec4(0.8, 0.0, 0.0, 1.0);
void fragment() {
	vec2 d = UV - 0.5;
	float v = smoothstep(0.25, 0.75, length(d) * 1.3);
	COLOR = vec4(tint.rgb, v * amount);
}"""
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


func _bar(color: Color, w := 420.0, h := 14.0) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(w, h)
	b.show_percentage = false
	b.max_value = 1.0
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bg.set_corner_radius_all(int(h / 2))
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	fg.set_corner_radius_all(int(h / 2))
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	return b


func _build_top_left() -> void:
	var tl := VBoxContainer.new()
	tl.position = Vector2(28, 18)
	tl.add_theme_constant_override("separation", 2)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(tl)
	_money = UiKit.num("金魂币 0", 34, UiKit.GOLD, 6)
	tl.add_child(_money)
	_room = UiKit.label("", 16, UiKit.MIST, 6)
	tl.add_child(_room)
	_fps = UiKit.label("", 15, Color(0.8, 1, 0.8), 5)
	tl.add_child(_fps)
	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	tl.add_child(gap)
	_quest_title = UiKit.label("", 16, UiKit.JADE, 6)
	tl.add_child(_quest_title)
	_quest_text = UiKit.label("", 20, Color.WHITE, 7)
	_quest_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quest_text.custom_minimum_size.x = 440
	tl.add_child(_quest_text)
	_quest_prog = UiKit.label("", 17, UiKit.GOLD, 6)
	tl.add_child(_quest_prog)


func _build_bottom_left() -> void:
	var bl := VBoxContainer.new()
	UiKit.place(bl, Vector4(0, 1, 0, 1), Vector4(28, -190, 520, -24))
	bl.alignment = BoxContainer.ALIGNMENT_END
	bl.add_theme_constant_override("separation", 4)
	bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bl)
	_level = UiKit.label("", 20, UiKit.MOON, 7)
	bl.add_child(_level)
	var hpbox := Control.new()
	hpbox.custom_minimum_size = Vector2(420, 20)
	bl.add_child(hpbox)
	_hp = _bar(Color(0.86, 0.26, 0.22), 420, 20)
	hpbox.add_child(_hp)
	_shield = _bar(Color(0.8, 0.92, 1.0, 0.85), 420, 20)
	(_shield.get_theme_stylebox("background") as StyleBoxFlat).bg_color = Color(0, 0, 0, 0)
	hpbox.add_child(_shield)
	_hp_text = UiKit.label("", 14, Color.WHITE, 5)
	_hp_text.position = Vector2(10, 0)
	hpbox.add_child(_hp_text)
	_soul = _bar(Color(0.35, 0.6, 1.0), 420, 12)
	bl.add_child(_soul)
	_xp = _bar(UiKit.GOLD, 420, 6)
	bl.add_child(_xp)
	_items = UiKit.label("", 16, UiKit.MOON, 6)
	bl.add_child(_items)


func _build_bottom_right() -> void:
	var br := VBoxContainer.new()
	UiKit.place(br, Vector4(1, 1, 1, 1), Vector4(-620, -230, -40, -24))
	br.alignment = BoxContainer.ALIGNMENT_END
	br.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(br)
	_weapon = UiKit.bold("袖箭", 22, UiKit.MOON, 6)
	_weapon.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	br.add_child(_weapon)
	_ammo = UiKit.num("10 / 10", 64, Color.WHITE, 6)
	_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	br.add_child(_ammo)
	_reload = UiKit.label("", 18, UiKit.GOLD, 5)
	_reload.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	br.add_child(_reload)
	_slots = UiKit.label("", 15, UiKit.MIST, 5)
	_slots.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	br.add_child(_slots)


func _build_bottom_center() -> void:
	var bc := VBoxContainer.new()
	UiKit.place(bc, Vector4(0.5, 1, 0.5, 1), Vector4(-420, -330, 420, -20))
	bc.alignment = BoxContainer.ALIGNMENT_END
	bc.add_theme_constant_override("separation", 6)
	bc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bc)
	_interact = UiKit.label("", 24, Color(1, 0.95, 0.75), 8)
	_interact.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bc.add_child(_interact)
	_bar_box = VBoxContainer.new()
	_bar_box.visible = false
	bc.add_child(_bar_box)
	_bar_label = UiKit.label("", 18, UiKit.MOON, 6)
	_bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bar_box.add_child(_bar_label)
	_bar_a = _bar(Color(0.55, 0.85, 1.0))
	_bar_a.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bar_box.add_child(_bar_a)
	_bar_b = _bar(Color(1.0, 0.4, 0.3))
	_bar_b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bar_box.add_child(_bar_b)
	_prompt = UiKit.label("", 22, UiKit.MOON, 8)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bc.add_child(_prompt)
	var skills := HBoxContainer.new()
	skills.alignment = BoxContainer.ALIGNMENT_CENTER
	skills.add_theme_constant_override("separation", 10)
	bc.add_child(skills)
	for i in Data.SKILL_KEYS.size():
		var box := PanelContainer.new()
		box.custom_minimum_size = Vector2(136, 58)
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.03, 0.04, 0.06, 0.72)
		st.set_border_width_all(0)
		st.border_width_bottom = 3
		st.border_color = Color(1, 1, 1, 0.15)
		st.set_corner_radius_all(4)
		st.content_margin_left = 8
		st.content_margin_right = 8
		box.add_theme_stylebox_override("panel", st)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		box.add_child(v)
		var top := UiKit.label("", 14, UiKit.MIST, 4)
		v.add_child(top)
		var nm := UiKit.label("", 18, Color.WHITE, 5)
		v.add_child(nm)
		skills.add_child(box)
		_skill_boxes.append({"box": box, "style": st, "top": top, "name": nm})


func _build_top_center() -> void:
	_boss_box = VBoxContainer.new()
	_boss_box.visible = false
	UiKit.place(_boss_box, Vector4(0.5, 0, 0.5, 0), Vector4(-420, 18, 420, 80))
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_boss_box)
	_boss_name = UiKit.title("", 30, Color(1, 0.85, 0.9))
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_box.add_child(_boss_name)
	_boss_bar = _bar(Color(0.7, 0.2, 0.85), 840, 18)
	_boss_box.add_child(_boss_bar)
	_toast = UiKit.label("", 22, Color.WHITE, 8)
	UiKit.place(_toast, Vector4(0.5, 0, 0.5, 0), Vector4(-560, 100, 560, 170))
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(_toast)


func _build_scores() -> void:
	_scores = PanelContainer.new()
	_scores.add_theme_stylebox_override("panel", UiKit.panel_style())
	UiKit.place(_scores, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-320, -240, 320, 240))
	_scores.visible = false
	_root.add_child(_scores)
	_scores_list = VBoxContainer.new()
	_scores.add_child(_scores_list)


func _build_pause() -> void:
	_pause = ColorRect.new()
	(_pause as ColorRect).color = Color(0, 0, 0, 0.55)
	_pause.visible = false
	add_child(_pause)
	UiKit.fill(_pause)
	var center := CenterContainer.new()
	_pause.add_child(center)
	UiKit.fill(center)
	var stack := VBoxContainer.new()
	center.add_child(stack)
	_pause_menu = VBoxContainer.new()
	_pause_menu.add_theme_constant_override("separation", 12)
	_pause_menu.custom_minimum_size = Vector2(440, 0)
	stack.add_child(_pause_menu)
	_pause_menu.add_child(UiKit.title("暂停", 56))
	var code := UiKit.label("", 22, UiKit.GOLD)
	code.name = "Code"
	code.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pause_menu.add_child(code)
	var resume := UiKit.button("继续游戏", 24, true)
	resume.pressed.connect(func(): world.set_paused(false))
	_pause_menu.add_child(resume)
	var wh := UiKit.button("武魂与魂环（K）", 22)
	wh.pressed.connect(func(): world.set_paused(false); toggle_wuhun())
	_pause_menu.add_child(wh)
	var settings := UiKit.button("设置", 22)
	settings.pressed.connect(func(): _pause_menu.visible = false; _settings.visible = true)
	_pause_menu.add_child(settings)
	var quit := UiKit.button("返回主菜单", 22)
	quit.pressed.connect(func(): world.leave())
	_pause_menu.add_child(quit)
	var keys := UiKit.label("WASD 移动 · 空格 跳 · Shift 冲刺（开镜时屏息）· Ctrl 蹲\n左键 射击 · 右键 瞄准 · R 换弹 · 1-5 / 滚轮 换暗器\nE 引魂索 · Q C X 魂技 · G 佛怒唐莲 · H 回血丹 · F 交互 · K 武魂 · Tab 魂师榜", 15, UiKit.MIST)
	_pause_menu.add_child(keys)
	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.closed.connect(func(): _settings.visible = false; _pause_menu.visible = true)
	stack.add_child(_settings)


# ------------------------------------------------------------------ 面板

func show_pause(on: bool) -> void:
	_pause.visible = on
	_pause_menu.visible = true
	_settings.visible = false
	var code: Label = _pause_menu.get_node("Code")
	if Net.is_online():
		code.text = "房间码  %s\n发给朋友，在主菜单输入即可加入" % Net.room_code
	else:
		code.text = "单人模式"


func open_shop() -> void:
	_shop.open()
	world.set_ui_open(true)


func _close_shop() -> void:
	_shop.visible = false
	world.set_ui_open(false)


func toggle_wuhun() -> void:
	if _wuhun.visible:
		_wuhun.visible = false
		world.set_ui_open(false)
	elif not world.ui_open:
		_wuhun.open()
		world.set_ui_open(true)


func close_panels() -> void:
	if _choice and is_instance_valid(_choice):
		return   # 魂技必须选一个
	_shop.visible = false
	_wuhun.visible = false
	world.set_ui_open(false)


## 吸收完魂环：从两个魂技里选一个
func choose_skill(age: int, species: String) -> void:
	var slot := Profile.rings.size()
	var tree: Array = Data.SKILL_TREE[Data.wuhun_id(Settings.wuhun)]
	if slot >= tree.size():
		return
	var opts: Array = tree[slot]
	_absorb.text = ""
	_choice = ColorRect.new()
	(_choice as ColorRect).color = Color(0, 0, 0, 0.6)
	add_child(_choice)
	UiKit.fill(_choice)
	var center := CenterContainer.new()
	_choice.add_child(center)
	UiKit.fill(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	center.add_child(v)
	var t := UiKit.title("第%s魂环 · %s魂环（%s）" % [Data.RING_NAMES[slot], Data.age_name(age), Data.BEASTS.get(species, {"name": "魂兽"})["name"]], 44, Data.age_color(age))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var sub := UiKit.label("选一个魂技（选了就不能换，按 %s 释放）" % Data.SKILL_KEYS[slot], 20, UiKit.MIST)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	v.add_child(row)
	for sid in opts:
		var s: Dictionary = Data.SKILLS[sid]
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiKit.panel_style())
		card.custom_minimum_size = Vector2(380, 0)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 8)
		card.add_child(cv)
		cv.add_child(UiKit.title(str(s["name"]), 40, UiKit.GOLD))
		var d := UiKit.label(str(s["desc"]), 19)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(d)
		cv.add_child(UiKit.label("魂力 %d · 冷却 %d 秒" % [int(s["cost"]), int(s["cd"])], 16, UiKit.MIST))
		var b := UiKit.button("选这个", 22, true)
		b.pressed.connect(func():
			world.finish_absorb(age, species, sid)
			_choice.queue_free()
			_choice = null
			world.set_ui_open(false)
			_refresh_skills())
		cv.add_child(b)
		row.add_child(card)
	world.set_ui_open(true)


# ------------------------------------------------------------------ 外部调用

func on_ammo(g: Gun) -> void:
	_ammo.text = "%d / %d" % [g.ammo, int(g.d["mag"])]
	_ammo.add_theme_color_override("font_color", Color(1, 0.45, 0.35) if g.ammo == 0 else Color.WHITE)


func on_weapon(g: Gun) -> void:
	_weapon.text = "%s · %s" % [str(g.d["name"]), str(g.d["cat"])]
	on_ammo(g)
	var parts := []
	var p: Player = world.player
	for i in p.guns.size():
		var nm := str(p.guns[i].d["name"])
		parts.append(("[%d %s]" if p.guns[i] == g else "%d %s") % [i + 1, nm])
	_slots.text = "  ".join(parts)


func hitmarker(headshot: bool, kill: bool) -> void:
	crosshair.hit(headshot, kill)


func toast(text: String, color := Color.WHITE, time := 2.8) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	_toast_t = time


func feed(text: String, color := Color.WHITE) -> void:
	var l := UiKit.label(text, 18, color, 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_feed.add_child(l)
	while _feed.get_child_count() > 7:
		var c := _feed.get_child(0)
		_feed.remove_child(c)
		c.queue_free()
	var tw := l.create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


func kill_popup(money: int, xp: int, tags: Array, species: String, age: int) -> void:
	for c in _popup.get_children():
		c.queue_free()
	var big := UiKit.label("+%d 金魂币   +%d 修为" % [money, xp], 36, UiKit.GOLD, 10)
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


func _show_banner(title: String, sub: String, color: Color, time := 4.0) -> void:
	for c in _banner.get_children():
		c.queue_free()
	var t := UiKit.title(title, 60, color)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_constant_override("outline_size", 14)
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_banner.add_child(t)
	if sub != "":
		var s := UiKit.label(sub, 22, Color.WHITE, 8)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_banner.add_child(s)
	_banner_t = time


func chapter_banner(name: String, intro: String) -> void:
	_show_banner(name, intro, UiKit.MOON, 7.0)


func level_up(level: int) -> void:
	_show_banner("魂力提升 · %d 级%s" % [level, Data.titles(level)], "体力、魂力上限提升", UiKit.GOLD, 2.5)


func quest_done(text: String, reward: int) -> void:
	toast("任务完成：%s%s" % [text, ("   +%d 金魂币" % reward) if reward > 0 else ""], Color(0.6, 1.0, 0.7), 4.0)
	update_quest()


func boss_defeated(name: String, money: int, bone: String) -> void:
	var sub := "+%d 金魂币" % money
	if bone != "":
		sub += "   获得魂骨【%s】：%s" % [Data.BONES[bone]["name"], Data.BONES[bone]["desc"]]
	sub += "\n地上掉落了千年魂环"
	_show_banner("击败 %s！" % name, sub, Color(1.0, 0.85, 0.4), 7.0)


func skill_callout(slot: int, sid: String) -> void:
	_callout.text = "第%s魂技 · %s" % [Data.RING_NAMES[slot], Data.SKILLS[sid]["name"]]
	_callout_t = 1.4


func absorb_start(age: int, _species: String) -> void:
	_absorb.text = "正在吸收%s魂环……" % Data.age_name(age)
	_absorb.add_theme_color_override("font_color", Data.age_color(age) if age > 0 else Color.WHITE)
	_absorb_t = 3.0


func hurt(amount: float, dir: Vector3) -> void:
	_vig_t = clampf(_vig_t + 0.35 + amount * 0.02, 0.0, 1.0)
	_hurt_dirs.append({"dir": dir, "t": 1.0})


func death_countdown(t: float) -> void:
	_death.visible = t >= 0.0
	if t >= 0.0:
		_death_text.text = "你倒下了\n%d 秒后在码头复活" % ceili(t)


func boss_bar(name: String) -> void:
	_boss_box.visible = name != ""
	_boss_name.text = name


func update_quest() -> void:
	if not is_node_ready():
		return
	var ch: int = world.chapter
	var qs: Array = Data.CHAPTERS[ch]["quests"]
	var q: Dictionary = Data.quest(ch, world.quest_idx)
	_quest_title.text = "%s · 任务 %d/%d" % [Data.CHAPTERS[ch]["name"], mini(world.quest_idx + 1, qs.size()), qs.size()]
	if q.is_empty():
		_quest_text.text = "本章任务全部完成"
		_quest_prog.text = ""
		return
	_quest_text.text = str(q["text"])
	match str(q["type"]):
		"kill", "hunt":
			_quest_prog.text = "进度 %d / %d" % [world.quest_count, maxi(world.quest_target, int(q["n"]))]
		"level":
			_quest_prog.text = "你的等级 %d / %d" % [Profile.level, int(q["n"])]
		"rings":
			_quest_prog.text = "你的魂环 %d / %d" % [Profile.rings.size(), int(q["n"])]
		_:
			_quest_prog.text = ""


func _refresh_skills() -> void:
	_skills_n = Profile.rings.size()
	for i in Data.SKILL_KEYS.size():
		var sb: Dictionary = _skill_boxes[i]
		var sid: String = world.skills.slot_skill(i)
		var st: StyleBoxFlat = sb["style"]
		if sid == "":
			sb["top"].text = "%s · 第%s魂环" % [Data.SKILL_KEYS[i], Data.RING_NAMES[i]]
			sb["name"].text = "%d 级解锁" % ((i + 1) * 10)
			sb["name"].add_theme_color_override("font_color", UiKit.MIST)
			st.border_color = Color(1, 1, 1, 0.15)
		else:
			var age := int(Profile.rings[i]["age"])
			sb["name"].text = str(Data.SKILLS[sid]["name"])
			sb["name"].add_theme_color_override("font_color", Color.WHITE)
			st.border_color = Data.age_color(age)


# ------------------------------------------------------------------ 每帧

func _process(dt: float) -> void:
	var p: Player = world.player
	_money_shown = move_toward(_money_shown, Profile.money, maxf(absf(Profile.money - _money_shown) * dt * 6.0, dt * 20.0))
	_money.text = "金魂币  %d" % roundi(_money_shown)
	_room.text = ("房间 %s · %d 人" % [Net.room_code, Net.peers.size() + 1]) if Net.is_online() else "单人模式"
	_fps.text = ("%d FPS" % Engine.get_frames_per_second()) if Settings.show_fps else ""

	# 体力 / 魂力 / 修为
	var mhp := Profile.max_hp()
	_hp.value = p.hp / mhp
	_shield.value = clampf(p.shield / mhp, 0.0, 1.0)
	_hp_text.text = "%d / %d%s" % [ceili(p.hp), int(mhp), ("  +%d 护盾" % ceili(p.shield)) if p.shield > 0.0 else ""]
	_soul.value = p.soul / Profile.max_soul()
	var need := Data.xp_to_next(Profile.level)
	_xp.value = float(Profile.xp) / float(need)
	var cap := "  【瓶颈：吸收第%d魂环】" % (Profile.rings.size() + 1) if Profile.at_bottleneck() else ""
	_level.text = "%s · %s   修为 %d/%d%s" % [Settings.display_name(), Profile.title(), Profile.xp, need, cap]
	var gold := Profile.item_count("gold_bites")
	_items.text = "G 佛怒唐莲 ×%d    H 回血丹 ×%d%s" % [Profile.item_count("grenade"), Profile.item_count("pill"), ("    引兽香 %d 次" % gold) if gold > 0 else ""]

	# 魂技冷却
	for i in Data.SKILL_KEYS.size():
		var sb: Dictionary = _skill_boxes[i]
		var sid: String = world.skills.slot_skill(i)
		if sid == "":
			continue
		var cd: float = world.skills.cooldowns[i]
		var cost := int(Data.SKILLS[sid]["cost"])
		if cd > 0.0:
			sb["top"].text = "%s · 冷却 %.1f" % [Data.SKILL_KEYS[i], cd]
			sb["box"].modulate = Color(0.55, 0.55, 0.55)
		else:
			sb["top"].text = "%s · 魂力 %d" % [Data.SKILL_KEYS[i], cost]
			sb["box"].modulate = Color.WHITE if p.soul >= cost else Color(0.6, 0.7, 1.0)
	if Profile.rings.size() != _skills_n:
		_refresh_skills()

	var g := p.gun
	if g.reloading:
		_reload.text = "装针中…" if g.d["per_shell"] else "换弹中…"
	elif g.cycling > 0.0:
		_reload.text = "拉栓…"
	elif g.ammo == 0:
		_reload.text = "按 R 换弹"
	else:
		_reload.text = ""

	_toast_t -= dt
	_toast.modulate.a = clampf(_toast_t / 0.4, 0.0, 1.0)
	_popup_t -= dt
	_popup.modulate.a = clampf(_popup_t / 0.5, 0.0, 1.0)
	_banner_t -= dt
	_banner.modulate.a = clampf(_banner_t / 0.6, 0.0, 1.0)
	_callout_t -= dt
	_callout.modulate.a = clampf(_callout_t / 0.4, 0.0, 1.0)
	_absorb_t -= dt
	if _absorb_t <= 0.0 and _absorb.text != "" and not (_choice and is_instance_valid(_choice)):
		_absorb.text = ""
	_vig_t = maxf(_vig_t - dt * 0.8, 0.0)
	var low := clampf(1.0 - p.hp / mhp * 3.0, 0.0, 0.6) if not p.dead else 0.0
	(_vignette.material as ShaderMaterial).set_shader_parameter("amount", maxf(_vig_t, low))
	for h in _hurt_dirs.duplicate():
		h["t"] -= dt
		if h["t"] <= 0.0:
			_hurt_dirs.erase(h)
	_hurt_layer.queue_redraw()
	_marker.queue_redraw()

	if world.boss:
		_boss_bar.value = world.boss.hp / world.boss.max_hp
	_scope.visible = p.scoped
	crosshair.visible = not p.scoped

	var it: Dictionary = world.nearest_interactable() if not p.dead else {}
	_interact.text = str(it.get("text", ""))

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
			_prompt.add_theme_font_size_override("font_size", 17)
			_prompt.modulate = Color(1, 1, 1, 0.5)
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


# ------------------------------------------------------------------ 受伤方向、任务目标标记

func _draw_hurt() -> void:
	var p: Player = world.player
	var c := _hurt_layer.size * 0.5
	for h in _hurt_dirs:
		var d: Vector3 = h["dir"]
		var local := p.cam.global_basis.inverse() * d
		var a := atan2(local.x, -local.z)
		var dir2 := Vector2(sin(a), -cos(a))
		var r := 90.0
		var tip := c + dir2 * (r + 22)
		var side := Vector2(-dir2.y, dir2.x) * 16.0
		var base := c + dir2 * r
		_hurt_layer.draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), Color(1, 0.15, 0.1, float(h["t"]) * 0.85))


func _quest_target() -> Variant:
	var q: Dictionary = Data.quest(world.chapter, world.quest_idx)
	match str(q.get("target", "")):
		"shop":
			return world.builder.shop_door
		"altar":
			return world.island.altar_pos + Vector3(0, 2, 0)
		"boat":
			return world.builder.boat_pos + Vector3(0, 1.8, 0)
	if str(q.get("type", "")) == "boss" and world.boss:
		return world.boss.center() + Vector3(0, 3, 0)
	if str(q.get("type", "")) == "hunt":
		var hb := str(Data.BEASTS[q["species"]]["habitat"])
		var hc: Vector3 = world.island.habitat_center(hb)
		if hc.distance_to(world.player.global_position) > 12.0:
			return hc + Vector3(0, 2.5, 0)
	# 地上有能吸收的魂环：标出来
	var best: Variant = null
	for rid in world.rings:
		var r: Dictionary = world.rings[rid]
		if Profile.can_absorb(int(r["age"])) == "":
			if best == null or (r["pos"] as Vector3).distance_to(world.player.global_position) < (best as Vector3).distance_to(world.player.global_position):
				best = r["pos"]
	return best


func _draw_marker() -> void:
	var target: Variant = _quest_target()
	if target == null:
		return
	var p: Player = world.player
	var cam := p.cam
	var tp: Vector3 = target
	var size := _marker.size
	var behind := cam.is_position_behind(tp)
	var sp := cam.unproject_position(tp)
	if behind:
		sp = size - sp
	var margin := 60.0
	var clamped := Vector2(clampf(sp.x, margin, size.x - margin), clampf(sp.y, margin + 60, size.y - margin - 120))
	if behind:
		clamped.y = size.y - margin - 120
	var col := Color(1.0, 0.85, 0.35, 0.95)
	var s := 12.0
	_marker.draw_colored_polygon(PackedVector2Array([clamped + Vector2(0, -s), clamped + Vector2(s, 0), clamped + Vector2(0, s), clamped + Vector2(-s, 0)]), col)
	_marker.draw_polyline(PackedVector2Array([clamped + Vector2(0, -s - 3), clamped + Vector2(s + 3, 0), clamped + Vector2(0, s + 3), clamped + Vector2(-s - 3, 0), clamped + Vector2(0, -s - 3)]), Color(0, 0, 0, 0.6), 2.0)
	var dist := p.global_position.distance_to(tp)
	var font := Data.font_ui
	_marker.draw_string_outline(font, clamped + Vector2(-30, s + 22), "%d 米" % roundi(dist), HORIZONTAL_ALIGNMENT_CENTER, 60, 16, 5, Color(0, 0, 0, 0.8))
	_marker.draw_string(font, clamped + Vector2(-30, s + 22), "%d 米" % roundi(dist), HORIZONTAL_ALIGNMENT_CENTER, 60, 16, col)


func _fill_scores() -> void:
	for c in _scores_list.get_children():
		c.queue_free()
	_scores_list.add_child(UiKit.title("魂师榜", 40))
	var header := HBoxContainer.new()
	for t in [["魂师", 260], ["等级", 90], ["击杀", 90], ["赚取", 110]]:
		var l := UiKit.label(t[0], 18, UiKit.MIST)
		l.custom_minimum_size.x = t[1]
		header.add_child(l)
	_scores_list.add_child(header)
	var ids: Array = world.stats.keys()
	ids.sort_custom(func(a, b): return world.stats[a]["earned"] > world.stats[b]["earned"])
	for id in ids:
		var row := HBoxContainer.new()
		var s: Dictionary = world.stats[id]
		var info: Dictionary = world.peer_info.get(id, {})
		var nm: String = world.peer_name(id) + ("（你）" if id == Net.my_id else "") + ("  房主" if id == 1 and Net.is_online() else "")
		for t in [[nm, 260], [str(info.get("level", 1)), 90], [str(s["kills"]), 90], [str(s["earned"]), 110]]:
			var l := UiKit.label(t[0], 20)
			l.custom_minimum_size.x = t[1]
			row.add_child(l)
		_scores_list.add_child(row)
