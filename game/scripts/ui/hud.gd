class_name Hud
extends CanvasLayer
## 游戏内界面（参考 Apex / 命运2：紧凑、少字、信息贴着屏幕边，中间留给画面）。
##   左上：章节目标、猎灵目标（灵兽王：方向箭头、距离、血量）、悬赏
##   上中：罗盘（方位 + 地点标记）、Boss / 灵兽王血条、提示
##   右上：小地图、灵石、击杀信息、成就
##   左下：状态、等级、体力 / 护盾、灵力、修为、饱食
##   下中：交互提示、引魂索提示、三个神通（Q / E / F，冷却转圈）
##   右下：暗器、弹药、物品栏 1-5
##   画面上：准星、灵兽头顶的名字和血条、任务目标标记、受伤方向、击杀奖励
##   面板（全屏毛玻璃）：暂停、暗器铺、灵相（K）、成就（J）、神通二选一、渡船；地图（M）、修士榜（Tab）

var world: Node
var crosshair: Crosshair
var _root: Control
# 左上
var _quest_title: Label
var _quest_text: Label
var _quest_hint: Label
var _quest_bar: ProgressBar
var _quest_prog: Label
var _kings: VBoxContainer
var _king_rows: Array = []
var _kings_sig := ""
var _kings_t := 0.0
var _bounty: VBoxContainer
# 上中
var _compass: Control
var _boss_box: VBoxContainer
var _boss_kick: Label
var _boss_name: Label
var _boss_state: Label
var _boss_draw: Control
var _boss_k := 1.0
var _boss_trail := 1.0
var _toast_box: PanelContainer
var _toast: Label
var _toast_t := 0.0
# 右上
var _minimap: MapView
var _bigmap: MapView
var _money: Label
var _money_shown := 0.0
var _room: Label
var _fps: Label
var _feed: VBoxContainer
# 左下
var _status: HBoxContainer
var _status_sig := ""
var _badge: Control
var _title: Label
var _hp: ProgressBar
var _shield: ProgressBar
var _hp_text: Label
var _soul: ProgressBar
var _soul_text: Label
var _xp: ProgressBar
var _food: ProgressBar
var _food_row: HBoxContainer
# 下中
var _interact: CenterContainer
# 剧情：人物说话的字幕（一句一句排队）、天枢记忆
var _say_box: PanelContainer
var _say_who: Label
var _say_text: Label
var _say_queue: Array = []
var _say_t := 0.0
var _say_dur := 0.0
var _interact_sig := ""
var _prompt: Label
var _bar_box: VBoxContainer
var _bar_a: ProgressBar
var _bar_b: ProgressBar
var _bar_label: Label
var _sk_boxes: Array = []
var _skills_n := -1
var _callout: Label
var _callout_t := 0.0
# 右下
var _weapon: Label
var _ench: Label
var _ammo: Label
var _ammo_max: Label
var _reload: Label
var _hotbar: HBoxContainer
# 触屏布局要挪动的几块
var _tl_box: Control
var _bc_box: Control
var _br_box: Control
var _sk_row: Control
var _money_row: Control
var _touch_on := false
var _hot_sig := ""
# 画面中间
var _plates: Control
var _popup: VBoxContainer
var _popup_t := 0.0
var _banner: VBoxContainer
var _banner_t := 0.0
var _absorb: Label
var _absorb_t := 0.0
var _vignette: ColorRect
var _vig_t := 0.0
var _hurt_dirs: Array = []
var _hurt_layer: Control
var _marker: Control
var _scope: ScopeOverlay
var _water: ColorRect
var _breath: ProgressBar
var _breath_box: HBoxContainer
var _revive: ProgressBar
var _revive_box: VBoxContainer
var _death: Control
var _death_title: Label
var _death_text: Label
var _death_bar: ProgressBar
var _death_key: Control
var _intro: Control
var _intro_title: Label
var _intro_sub: Label
# 面板
var _pause: Control
var _pause_menu: Control
var _pause_code: Label
var _settings: SettingsPanel
var _scores: PanelContainer
var _scores_list: VBoxContainer
var _shop: ShopPanel
var _wuhun: WuhunPanel
var _choice: Control
var _ach_panel: Control
var _boat_picker: Control


func _ready() -> void:
	layer = 5
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	UiKit.fill(_root)

	_water = ColorRect.new()
	_water.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wm := ShaderMaterial.new()
	wm.shader = Shader.new()
	wm.shader.code = """shader_type canvas_item;
uniform float t = 0.0;
void fragment() {
	vec2 d = UV - 0.5;
	float v = smoothstep(0.2, 0.8, length(d) * 1.2);
	float caustic = sin(UV.x * 30.0 + t * 2.0) * sin(UV.y * 24.0 - t * 1.6) * 0.03;
	COLOR = vec4(0.03, 0.22 + caustic, 0.3 + caustic, 0.42 + v * 0.4);
}"""
	_water.material = wm
	_water.visible = false
	_root.add_child(_water)
	UiKit.fill(_water)

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

	_plates = _layer(_draw_plates)
	crosshair = Crosshair.new()
	crosshair.player = world.player
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(crosshair)
	UiKit.fill(crosshair)
	_hurt_layer = _layer(_draw_hurt)
	_marker = _layer(_draw_marker)

	_build_top_left()
	_build_top_center()
	_build_top_right()
	_build_bottom_left()
	_build_bottom_center()
	_build_bottom_right()
	_build_center()
	_build_combo()
	_build_death()
	_build_intro()

	_bigmap = MapView.new()
	_bigmap.world = world
	_bigmap.big = true
	_bigmap.visible = false
	_bigmap.clip_contents = true
	UiKit.place(_bigmap, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-400, -410, 400, 410))
	_root.add_child(_bigmap)
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
	touch_layout(Settings.touch_active())
	Settings.changed.connect(_on_settings_changed)


func _on_settings_changed() -> void:
	touch_layout(Settings.touch_active())


# ------------------------------------------------------------------ 手机触屏布局

## 触屏时右下角是一圈按钮：弹药改由触屏层画在开火键上面，物品栏挪到下中（替掉神通格子，神通在按钮上），
## 左上让出暂停键的位置，金币挪到小地图左边，击杀消息挪到左边，大地图按屏幕高度缩小
func touch_layout(on: bool) -> void:
	_touch_on = on
	if not _tl_box:
		return
	UiKit.place(_tl_box, Vector4(0, 0, 0, 0), Vector4(96 if on else 26, 22, 466 if on else 396, 640))
	_sk_row.visible = not on
	_br_box.visible = not on
	var want: Node = _bc_box if on else _br_box
	if _hotbar.get_parent() != want:
		_hotbar.reparent(want, false)
	_hotbar.alignment = BoxContainer.ALIGNMENT_CENTER if on else BoxContainer.ALIGNMENT_END
	if on:
		# 小地图缩小一点，下面要放神通键
		UiKit.place(_minimap, Vector4(1, 0, 1, 0), Vector4(-190, 14, -22, 182))
		UiKit.place(_money_row, Vector4(1, 0, 1, 0), Vector4(-520, 14, -206, 48))
		UiKit.place(_fps, Vector4(1, 0, 1, 0), Vector4(-520, 48, -206, 66))
		UiKit.place(_feed, Vector4(0, 0, 0, 0), Vector4(96, 190, 560, 420))
	else:
		UiKit.place(_minimap, Vector4(1, 0, 1, 0), Vector4(-236, 18, -22, 232))
		UiKit.place(_money_row, Vector4(1, 0, 1, 0), Vector4(-300, 238, -22, 272))
		UiKit.place(_fps, Vector4(1, 0, 1, 0), Vector4(-300, 272, -22, 290))
		UiKit.place(_feed, Vector4(1, 0, 1, 0), Vector4(-560, 378, -22, 620))
	_fit_bigmap()


## 刘海屏：整个 HUD 左右往里收（TouchControls 算好传进来）
func set_safe_insets(l: float, r: float) -> void:
	_root.offset_left = l
	_root.offset_right = -r


## 大地图：按屏幕高度缩放（手机屏幕矮，固定 820 高会超出去）
func _fit_bigmap() -> void:
	if not _bigmap:
		return
	var h := 410.0
	if _touch_on:
		h = minf(410.0, get_viewport().get_visible_rect().size.y * 0.45)
	UiKit.place(_bigmap, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-h * 400.0 / 410.0, -h, h * 400.0 / 410.0, h))


## 触屏层用：物品栏第 i 格、小地图、大地图在屏幕上的位置
func hotbar_rect(i: int) -> Rect2:
	if not _hotbar or i >= _hotbar.get_child_count():
		return Rect2()
	var c := _hotbar.get_child(i) as Control
	return c.get_global_rect() if c and not c.is_queued_for_deletion() else Rect2()


func minimap_rect() -> Rect2:
	return _minimap.get_global_rect() if _minimap and _minimap.visible else Rect2()


func bigmap_open() -> bool:
	return _bigmap != null and _bigmap.visible


func bigmap_rect() -> Rect2:
	return _bigmap.get_global_rect() if bigmap_open() else Rect2()


## 触屏层画在开火键上面的：暗器名、弹药、换弹提示
func ammo_info() -> Array:
	return [_weapon.text if _weapon else "", _ammo.text if _ammo else "", _ammo_max.text if _ammo_max else "", _reload.text if _reload else ""]


func _layer(fn: Callable) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(fn)
	_root.add_child(c)
	UiKit.fill(c)
	return c


## 一个自己画的小控件（菱形、等级徽章、箭头）
func _painter(size: Vector2, fn: Callable) -> Control:
	var c := Control.new()
	c.custom_minimum_size = size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.draw.connect(fn.bind(c))
	return c


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


## 斜切的条（体力、灵力）
func _bar(color: Color, w := 420.0, h := 14.0, slant := false) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(w, h)
	b.show_percentage = false
	b.max_value = 1.0
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.4)
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	if slant:
		bg.skew = Vector2(0.3, 0)
		fg.skew = Vector2(0.3, 0)
		bg.border_color = Color(1, 1, 1, 0.1)
		bg.set_border_width_all(1)
	else:
		bg.set_corner_radius_all(1)
		fg.set_corner_radius_all(1)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	return b


# ------------------------------------------------------------------ 左上：目标、猎灵、悬赏

func _build_top_left() -> void:
	var tl := VBoxContainer.new()
	_tl_box = tl
	UiKit.place(tl, Vector4(0, 0, 0, 0), Vector4(26, 22, 396, 640))
	tl.add_theme_constant_override("separation", 16)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(tl)
	var q := VBoxContainer.new()
	q.add_theme_constant_override("separation", 2)
	q.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.add_child(q)
	var qh := HBoxContainer.new()
	qh.add_theme_constant_override("separation", 8)
	qh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	q.add_child(qh)
	qh.add_child(_painter(Vector2(10, 10), func(c: Control):
		c.draw_colored_polygon(PackedVector2Array([Vector2(5, 0), Vector2(10, 5), Vector2(5, 10), Vector2(0, 5)]), UiKit.GOLD)))
	_quest_title = UiKit.kicker("", UiKit.GOLD, 13)
	UiKit._text_style(_quest_title, 3)
	qh.add_child(_quest_title)
	_quest_text = UiKit.bold("", 19, Color.WHITE, 3)
	_quest_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quest_text.custom_minimum_size.x = 360
	q.add_child(_quest_text)
	_quest_hint = UiKit.label("", 14, Color(0.8, 0.84, 0.9), 3)
	_quest_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quest_hint.custom_minimum_size.x = 360
	q.add_child(_quest_hint)
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 10)
	pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	q.add_child(pr)
	_quest_bar = UiKit.bar(UiKit.GOLD, 200, 3)
	_quest_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pr.add_child(_quest_bar)
	_quest_prog = UiKit.num("", 17, UiKit.GOLD, 3)
	pr.add_child(_quest_prog)
	_kings = VBoxContainer.new()
	_kings.add_theme_constant_override("separation", 5)
	_kings.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.add_child(_kings)
	# 悬赏不常驻在 HUD 上（字太多），按住 Tab 在修士榜里看
	_bounty = VBoxContainer.new()
	_bounty.add_theme_constant_override("separation", 3)
	_bounty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bounty.visible = false
	tl.add_child(_bounty)


func update_quest() -> void:
	if not is_node_ready():
		return
	var ch: int = world.chapter
	var qs: Array = Data.CHAPTERS[ch]["quests"]
	var q: Dictionary = Data.quest(ch, world.quest_idx)
	_quest_title.text = str(Data.CHAPTERS[ch]["name"])
	if q.is_empty() or qs.is_empty():
		_quest_text.text = "这张图的 Boss 已经打赢了"
		_quest_hint.text = "可以去渡船去下一章，或者继续猎灵兽王"
		_quest_prog.text = ""
		_quest_bar.visible = false
		return
	# "修炼到 15 级（猎灵兽王最快：…）"：括号里的放到下面一行小字
	var t := str(q["text"])
	var cut := t.find("（")
	_quest_text.text = t.substr(0, cut) if cut > 0 else t
	_quest_hint.text = t.substr(cut + 1).trim_suffix("）") if cut > 0 else ""
	_quest_hint.visible = false   # 用户嫌字多：只留一句目标
	var a := 0
	var b := 0
	match str(q["type"]):
		"kill", "hunt":
			a = world.quest_count
			b = maxi(world.quest_target, int(q["n"]))
		"kings":
			a = world.quest_count
			b = maxi(world.quest_target, 1)
		"level":
			a = Profile.level
			b = int(q["n"])
		"rings":
			a = Profile.rings.size()
			b = int(q["n"])
		"god":
			a = Profile.level
			b = 100
	_quest_bar.visible = b > 0
	if b > 0:
		_quest_bar.value = clampf(float(a) / float(b), 0.0, 1.0)
		_quest_prog.text = "%d / %d" % [mini(a, b) if str(q["type"]) != "god" else a, b]
	else:
		_quest_prog.text = ""


## 灵兽王：房主知道全部（包括打死了在等重生的），客人只知道活着的
func _king_data() -> Array:
	var out: Array = []
	# 猎场：猎物有自己的卡，守宝的王标在地图和罗盘上，不再列卡片
	if world.island.hunting:
		return out
	if Net.is_host():
		for key in world.elites:
			var e: Dictionary = world.elites[key]
			var nm := "%s%s王" % [Data.age_name(int(e["age"])), Data.BEASTS[e["species"]]["name"]]
			var b: Beast = world.beasts.get(int(e["id"])) if int(e["id"]) != 0 else null
			if b and b.alive():
				out.append({"key": str(key), "name": nm, "b": b, "age": int(e["age"])})
			else:
				out.append({"key": str(key), "name": nm, "b": null, "t": float(e["t"]), "age": int(e["age"])})
	else:
		for b: Beast in world.beasts.values():
			if b.alive() and b.temper == "elite" and b.hunt_role == "":
				out.append({"key": str(b.id), "name": b.display_name(), "b": b, "age": b.age})
	return out


## 左上的猎灵目标：一只王一张卡（怪物猎人那样）。活着的：方向箭头、距离、血条、状态；死了的：重生倒计时
func _update_kings(dt: float) -> void:
	_kings_t -= dt
	_kings.visible = not (world.away())
	# 只列活着的（打死了在等重生的不占地方）
	var data := _king_data().filter(func(e): return e["b"] != null)
	var sig := ""
	for d in data:
		sig += "%s%s|" % [d["key"], d["b"] != null]
	if sig != _kings_sig:
		_kings_sig = sig
		_king_rows.clear()
		for c in _kings.get_children():
			c.queue_free()
		if not data.is_empty():
			_kings.add_child(UiKit.section("灵兽王", Color(1.0, 0.62, 0.3), 3))
		for d in data:
			_king_rows.append(_king_row(d))
	var me: Vector3 = world.player.global_position
	for i in mini(data.size(), _king_rows.size()):
		var d: Dictionary = data[i]
		var r: Dictionary = _king_rows[i]
		var b: Beast = d["b"]
		if b == null:
			var t := int(d.get("t", 0.0))
			(r["dist"] as Label).text = "%d:%02d 后重生" % [t / 60, t % 60]
			continue
		var to := b.global_position - me
		(r["dist"] as Label).text = "%d 米" % int(Vector2(to.x, to.z).length())
		(r["hp"] as ProgressBar).value = b.hp / b.max_hp
		var st := ""
		var sc := UiKit.MIST
		if b._retreat:
			st = "逃回巢穴"
			sc = UiKit.JADE
		elif b.root_t > 0.0:
			st = "捆住了"
			sc = UiKit.GREEN
		elif b._phase2:
			st = "暴怒"
			sc = UiKit.RED
		(r["state"] as Label).text = st
		(r["state"] as Label).add_theme_color_override("font_color", sc)
		r["arrow"].set_meta("a", _rel_angle(b.global_position))
		(r["arrow"] as Control).queue_redraw()


func _king_row(d: Dictionary) -> Dictionary:
	var alive: bool = d["b"] != null
	var p := PanelContainer.new()
	var st := UiKit.glass_style(0.42 if alive else 0.25, 10, 6)
	st.border_color = Color(1.0, 0.55, 0.2) if alive else Color(1, 1, 1, 0.15)
	st.border_width_left = 3
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kings.add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var arrow := _painter(Vector2(26, 26), func(c: Control):
		var a := float(c.get_meta("a", 0.0))
		var ctr := Vector2(13, 13)
		c.draw_circle(ctr, 12.0, Color(0, 0, 0, 0.35))
		if not c.get_meta("alive", true):
			c.draw_arc(ctr, 11.0, 0.0, TAU, 24, Color(1, 1, 1, 0.25), 1.5, true)
			return
		var tip := ctr + Vector2(0, -9).rotated(a)
		var l := ctr + Vector2(-6, 6).rotated(a)
		var rr := ctr + Vector2(6, 6).rotated(a)
		var m := ctr + Vector2(0, 2).rotated(a)
		c.draw_colored_polygon(PackedVector2Array([tip, rr, m, l]), Color(1.0, 0.7, 0.35)))
	arrow.set_meta("alive", alive)
	h.add_child(arrow)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	var nm := UiKit.bold(str(d["name"]), 16, Color(1.0, 0.8, 0.55) if alive else UiKit.DIM, 3)
	top.add_child(nm)
	var dist := UiKit.label("", 14, UiKit.MOON if alive else UiKit.DIM, 3)
	top.add_child(dist)
	var state := UiKit.bold("", 13, UiKit.MIST, 3)
	top.add_child(state)
	var hp := UiKit.bar(Color(1.0, 0.42, 0.28), 230, 3)
	hp.visible = alive
	v.add_child(hp)
	return {"dist": dist, "hp": hp, "state": state, "arrow": arrow}


## 目标在自己的哪个方向（0 = 正前方，顺时针为正），用来转箭头
func _rel_angle(target: Vector3) -> float:
	var p: Player = world.player
	var d := Vector2(target.x - p.global_position.x, target.z - p.global_position.z)
	var fwd := Vector2(-sin(p.yaw), -cos(p.yaw))
	var right := Vector2(cos(p.yaw), -sin(p.yaw))
	return atan2(d.dot(right), d.dot(fwd))


func update_bounties() -> void:
	if not _bounty:
		return
	for c in _bounty.get_children():
		c.queue_free()
	if Profile.bounties.is_empty():
		return
	_bounty.add_child(UiKit.section("悬赏", Color(0.85, 0.88, 0.94), 3))
	for b in Profile.bounties:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var age := int(b["age"])
		var a := str(b.get("affix", ""))
		var t := "%s · %s%s" % [Data.BEASTS[b["species"]]["name"], Data.age_name(age), "以上" if age > 0 else ""]
		if a != "":
			t += " · " + str(Data.AFFIXES[a]["name"])
		var l := UiKit.label(t, 14, Color(0.86, 0.89, 0.94), 3)
		l.custom_minimum_size.x = 230
		h.add_child(l)
		h.add_child(UiKit.icon("coin", 14, UiKit.GOLD))
		h.add_child(UiKit.num(str(int(b["reward"])), 16, UiKit.GOLD, 3))
		_bounty.add_child(h)


# ------------------------------------------------------------------ 上中：罗盘、Boss 血条、提示

func _build_top_center() -> void:
	_compass = Control.new()
	_compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.place(_compass, Vector4(0.5, 0, 0.5, 0), Vector4(-320, 14, 320, 58))
	_compass.draw.connect(_draw_compass)
	_root.add_child(_compass)
	_boss_box = VBoxContainer.new()
	_boss_box.visible = false
	_boss_box.add_theme_constant_override("separation", 4)
	UiKit.place(_boss_box, Vector4(0.5, 0, 0.5, 0), Vector4(-360, 66, 360, 130))
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_boss_box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_box.add_child(row)
	_boss_kick = UiKit.kicker("", Color(1.0, 0.62, 0.4), 13)
	UiKit._text_style(_boss_kick, 3)
	_boss_kick.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(_boss_kick)
	_boss_name = UiKit.title("", 24, Color.WHITE)
	UiKit._text_style(_boss_name, 3)
	row.add_child(_boss_name)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	_boss_state = UiKit.bold("", 15, UiKit.RED, 3)
	_boss_state.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(_boss_state)
	_boss_draw = Control.new()
	_boss_draw.custom_minimum_size = Vector2(720, 12)
	_boss_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_draw.draw.connect(_draw_boss_bar)
	_boss_box.add_child(_boss_draw)
	# 提示：罗盘下面一条半透明的
	var tc := CenterContainer.new()
	tc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.place(tc, Vector4(0.5, 0, 0.5, 0), Vector4(-600, 140, 600, 190))
	_root.add_child(tc)
	_toast_box = PanelContainer.new()
	_toast_box.add_theme_stylebox_override("panel", UiKit.glass_style(0.55, 18, 7))
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.modulate.a = 0.0
	tc.add_child(_toast_box)
	_toast = UiKit.label("", 18, Color.WHITE, 2)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.custom_minimum_size.x = 0
	_toast_box.add_child(_toast)


## Boss 血条：掉的血先变白、慢慢缩回去（魂类游戏的做法），25% / 50% / 75% 有刻度
func _draw_boss_bar() -> void:
	var s := _boss_draw.size
	_boss_draw.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.5))
	_boss_draw.draw_rect(Rect2(Vector2(1, 1), Vector2((s.x - 2) * clampf(_boss_trail, 0.0, 1.0), s.y - 2)), Color(1, 0.95, 0.85, 0.75))
	var col := Color(0.85, 0.2, 0.25)
	_boss_draw.draw_rect(Rect2(Vector2(1, 1), Vector2((s.x - 2) * clampf(_boss_k, 0.0, 1.0), s.y - 2)), col)
	_boss_draw.draw_rect(Rect2(Vector2(1, 1), Vector2((s.x - 2) * clampf(_boss_k, 0.0, 1.0), 3)), Color(1, 0.6, 0.55, 0.6))
	for k in [0.25, 0.5, 0.75]:
		_boss_draw.draw_line(Vector2(s.x * k, 0), Vector2(s.x * k, s.y), Color(0, 0, 0, 0.6), 2.0)
	_boss_draw.draw_rect(Rect2(Vector2.ZERO, s), Color(1, 1, 1, 0.25), false, 1.0)


func boss_bar(name: String) -> void:
	_boss_box.visible = name != ""
	var parts := name.split(" · ")
	_boss_name.text = parts[parts.size() - 1]
	_boss_kick.text = parts[0] if parts.size() > 1 else ""
	_boss_state.text = ""
	_boss_k = 1.0
	_boss_trail = 1.0


## 罗盘：一条横尺，东南西北 + 地点标记（铺、坛、船、王、Boss、任务目标、队友）
const COMPASS_SPAN := 150.0     # 罗盘上能看到的角度


func _draw_compass() -> void:
	var p: Player = world.player
	if not p:
		return
	var s := _compass.size
	var cx := s.x * 0.5
	var ppd := s.x / COMPASS_SPAN
	var heading := rad_to_deg(-p.yaw)
	var font: Font = Data.font_bold
	# 底：中间深、两头淡（每个顶点一个颜色，渐变过去）
	var dark := Color(0.02, 0.03, 0.05, 0.42)
	var clear := Color(0.02, 0.03, 0.05, 0.0)
	for half in [[0.0, cx, clear, dark], [cx, s.x, dark, clear]]:
		var x0: float = half[0]
		var x1: float = half[1]
		_compass.draw_polygon(PackedVector2Array([Vector2(x0, 8), Vector2(x1, 8), Vector2(x1, 27), Vector2(x0, 27)]), PackedColorArray([half[2], half[3], half[3], half[2]]))
	var names := {0: "北", 45: "东北", 90: "东", 135: "东南", 180: "南", 225: "西南", 270: "西", 315: "西北"}
	for deg in range(0, 360, 15):
		var rel := wrapf(float(deg) - heading, -180.0, 180.0)
		if absf(rel) > COMPASS_SPAN * 0.5:
			continue
		var x := cx + rel * ppd
		var fade := 1.0 - pow(absf(rel) / (COMPASS_SPAN * 0.5), 2.0)
		if names.has(deg):
			var main := deg % 90 == 0
			var txt: String = names[deg]
			var fs := 17 if main else 13
			var col := (UiKit.GOLD if deg == 0 else Color.WHITE) if main else UiKit.MIST
			var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			_compass.draw_string_outline(font, Vector2(x - w * 0.5, 23), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.4 * fade))
			_compass.draw_string(font, Vector2(x - w * 0.5, 23), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col.r, col.g, col.b, fade))
		else:
			_compass.draw_line(Vector2(x, 12), Vector2(x, 20), Color(1, 1, 1, 0.5 * fade), 1.5)
	# 中间的指针
	_compass.draw_colored_polygon(PackedVector2Array([Vector2(cx - 6, 0), Vector2(cx + 6, 0), Vector2(cx, 7)]), UiKit.GOLD)
	# 地点：挨得太近的往下错开一排
	var used: Array = []
	for m in _compass_marks():
		var pos: Vector3 = m[0]
		var d := Vector2(pos.x - p.global_position.x, pos.z - p.global_position.z)
		if d.length() < 2.0:
			continue
		var bearing := rad_to_deg(atan2(d.x, -d.y))
		var rel := wrapf(bearing - heading, -180.0, 180.0)
		var edge := absf(rel) > COMPASS_SPAN * 0.5
		var x := cx + clampf(rel, -COMPASS_SPAN * 0.5, COMPASS_SPAN * 0.5) * ppd
		var col: Color = m[2]
		if edge:
			col.a = 0.45
		var y := 38.0
		for ux in used:
			if absf(float(ux) - x) < 17.0:
				y = 58.0
		used.append(x)
		var glyph: String = m[1]
		if glyph == "◆":
			_compass.draw_colored_polygon(PackedVector2Array([Vector2(x, y - 8), Vector2(x + 7, y), Vector2(x, y + 8), Vector2(x - 7, y)]), col)
			if not edge:
				var dt := "%d米" % int(d.length())
				var dw := font.get_string_size(dt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
				_compass.draw_string_outline(font, Vector2(x - dw * 0.5, y + 22), dt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color(0, 0, 0, 0.5))
				_compass.draw_string(font, Vector2(x - dw * 0.5, y + 22), dt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiKit.GOLD)
		elif glyph == "·":
			_compass.draw_circle(Vector2(x, y), 5.0, Color(0, 0, 0, 0.5))
			_compass.draw_circle(Vector2(x, y), 3.5, col)
		else:
			_compass.draw_circle(Vector2(x, y), 9.5, Color(0, 0, 0, 0.55 * col.a))
			_compass.draw_circle(Vector2(x, y), 8.0, Color(col.r * 0.6, col.g * 0.6, col.b * 0.6, col.a))
			var gw := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			_compass.draw_string(font, Vector2(x - gw * 0.5, y + 4), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, col.a))


func _compass_marks() -> Array:
	var out: Array = []
	# 在秘境里：岛上的东西都不标，只标队友
	if world.away():
		for id in world.remotes:
			if world.remotes[id].global_position.distance_to(world.player.global_position) < 120.0:
				out.append([world.remotes[id].global_position, "·", Color(0.45, 0.8, 1.0)])
		return out
	# 猎场：营地、猎物（锁定了才标）、队友
	if world.island.hunting:
		out.append([world.builder.camp_pos, "营", UiKit.GOLD])
		if world.trip:
			out.append_array(world.trip.guard_marks())
		if world.hunt:
			out.append_array(world.hunt.compass_marks())
		for id in world.remotes:
			out.append([world.remotes[id].global_position, "·", Color(0.45, 0.8, 1.0)])
		var qt0: Variant = _quest_target()
		if qt0 != null:
			out.append([qt0, "◆", UiKit.GOLD])
		return out
	out.append([world.builder.shop_door, "铺", UiKit.GOLD])
	out.append([world.island.altar_pos, "坛", Color(1.0, 0.45, 0.4)])
	if int(Data.CHAPTERS[world.chapter].get("next", 0)) > 0:
		out.append([world.builder.boat_pos, "船", UiKit.JADE])
	for b: Beast in world.beasts.values():
		if b.alive() and b.temper == "elite" and b.hunt_role == "":
			out.append([b.global_position, "王", Color(1.0, 0.6, 0.25)])
	if world.hunt:
		out.append_array(world.hunt.compass_marks())
	if world.dungeon:
		out.append_array(world.dungeon.compass_marks())
		out.append_array(world.trial.compass_marks())
	if world.builder.board_pos != Vector3.ZERO and not (world.away()):
		out.append([world.builder.board_pos, "榜", Color(1.0, 0.78, 0.5)])
	if world.boss and not world.boss.dead:
		out.append([world.boss.center(), "主", Color(1.0, 0.3, 0.35)])
	for id in world.remotes:
		out.append([world.remotes[id].global_position, "·", Color(0.45, 0.8, 1.0)])
	var qt: Variant = _quest_target()
	if qt != null:
		out.append([qt, "◆", UiKit.GOLD])
	return out


# ------------------------------------------------------------------ 右上：小地图、灵石、击杀信息

func _build_top_right() -> void:
	_minimap = MapView.new()
	_minimap.world = world
	_minimap.clip_contents = true
	UiKit.place(_minimap, Vector4(1, 0, 1, 0), Vector4(-236, 18, -22, 232))
	_root.add_child(_minimap)
	var mr := HBoxContainer.new()
	mr.alignment = BoxContainer.ALIGNMENT_END
	mr.add_theme_constant_override("separation", 8)
	mr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.place(mr, Vector4(1, 0, 1, 0), Vector4(-300, 238, -22, 272))
	_root.add_child(mr)
	_money_row = mr
	_room = UiKit.label("", 13, UiKit.MIST, 3)
	_room.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mr.add_child(_room)
	mr.add_child(UiKit.icon("coin", 22, UiKit.GOLD))
	_money = UiKit.num("0", 28, UiKit.GOLD, 3)
	mr.add_child(_money)
	_fps = UiKit.label("", 12, Color(0.75, 1, 0.75), 3)
	_fps.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiKit.place(_fps, Vector4(1, 0, 1, 0), Vector4(-300, 272, -22, 290))
	_root.add_child(_fps)
	_feed = VBoxContainer.new()
	_feed.add_theme_constant_override("separation", 4)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.place(_feed, Vector4(1, 0, 1, 0), Vector4(-560, 378, -22, 620))
	_root.add_child(_feed)


func feed(text: String, color := Color.WHITE) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.glass_style(0.42, 10, 3))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_END
	var l := UiKit.label(text, 15, color, 2)
	p.add_child(l)
	_feed.add_child(p)
	while _feed.get_child_count() > 6:
		var c := _feed.get_child(0)
		_feed.remove_child(c)
		c.queue_free()
	var tw := p.create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)


## 成就解锁：小地图左边滑进来一张卡
func achievement(title: String, desc: String, reward: int) -> void:
	var p := PanelContainer.new()
	var st := UiKit._flat(Color(0.06, 0.05, 0.02, 0.88), 16, 10, 2)
	st.border_color = UiKit.GOLD
	st.border_width_left = 3
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	p.add_child(h)
	h.add_child(UiKit.icon("quest", 30, UiKit.GOLD))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	h.add_child(v)
	v.add_child(UiKit.kicker("成就解锁", UiKit.GOLD, 12))
	v.add_child(UiKit.bold(title, 19, Color.WHITE))
	v.add_child(UiKit.label("%s  ·  +%d 灵石" % [desc, reward], 13, UiKit.MIST))
	# 同时解锁好几个：往下排
	var n := 0
	for c in _root.get_children():
		if c.has_meta("ach"):
			n += 1
	p.set_meta("ach", true)
	if _touch_on:
		# 触屏：右边是一圈按钮，改在上面正中弹出
		UiKit.place(p, Vector4(0.5, 0, 0.5, 0), Vector4(-210, 72 + n * 76, 210, 142 + n * 76))
	else:
		UiKit.place(p, Vector4(1, 0, 1, 0), Vector4(-420, 296 + n * 80, -22, 366 + n * 80))
	_root.add_child(p)
	p.modulate.a = 0.0
	var x0 := p.position.x
	p.position.x = x0 + 60.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.25)
	tw.parallel().tween_property(p, "position:x", x0, 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_interval(3.8)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)


# ------------------------------------------------------------------ 左下：等级、体力、灵力

func _build_bottom_left() -> void:
	var holder := VBoxContainer.new()
	UiKit.place(holder, Vector4(0, 1, 0, 1), Vector4(26, -230, 420, -22))
	holder.alignment = BoxContainer.ALIGNMENT_END
	holder.add_theme_constant_override("separation", 6)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(holder)
	# 状态（定身、减速、瓶颈……）
	_status = HBoxContainer.new()
	_status.add_theme_constant_override("separation", 6)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_status)
	# 等级徽章 + 称号
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(top)
	_badge = _painter(Vector2(40, 40), func(c: Control):
		var ctr := Vector2(20, 20)
		var pts := PackedVector2Array()
		for i in 6:
			pts.append(ctr + Vector2.from_angle(PI / 6.0 + TAU * i / 6.0) * 19.0)
		c.draw_colored_polygon(pts, Color(0.03, 0.04, 0.06, 0.75))
		pts.append(pts[0])
		c.draw_polyline(pts, UiKit.GOLD, 2.0, true)
		var t := str(Profile.level)
		var f: Font = Data.font_num
		var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		c.draw_string(f, Vector2(20 - w * 0.5, 28), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE))
	top.add_child(_badge)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 3)
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(tv)
	_title = UiKit.bold("", 15, Color.WHITE, 3)
	_title.visible = false
	tv.add_child(_title)
	_xp = UiKit.bar(UiKit.GOLD, 250, 3)
	tv.add_child(_xp)
	# 体力（护盾叠在上面）
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 10)
	hrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(hrow)
	hrow.add_child(UiKit.icon("heart", 18, Color(1.0, 0.42, 0.38)))
	var hpbox := Control.new()
	hpbox.custom_minimum_size = Vector2(300, 18)
	hpbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hrow.add_child(hpbox)
	_hp = _bar(Color(0.95, 0.95, 0.95), 300, 18, true)
	hpbox.add_child(_hp)
	_shield = _bar(Color(0.45, 0.75, 1.0, 0.9), 300, 18, true)
	(_shield.get_theme_stylebox("background") as StyleBoxFlat).bg_color = Color(0, 0, 0, 0)
	(_shield.get_theme_stylebox("background") as StyleBoxFlat).set_border_width_all(0)
	hpbox.add_child(_shield)
	_hp_text = UiKit.num("", 22, Color.WHITE, 3)
	_hp_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hrow.add_child(_hp_text)
	# 灵力
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 10)
	srow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(srow)
	srow.add_child(UiKit.icon("soul", 18, Color(0.5, 0.72, 1.0)))
	_soul = _bar(Color(0.4, 0.62, 1.0), 300, 7, true)
	_soul.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	srow.add_child(_soul)
	_soul_text = UiKit.num("", 17, Color(0.7, 0.82, 1.0), 3)
	_soul_text.visible = false
	srow.add_child(_soul_text)
	# 饱食度
	_food_row = HBoxContainer.new()
	_food_row.add_theme_constant_override("separation", 10)
	_food_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_food_row)
	var fl := UiKit.bold("饱", 13, Color(1.0, 0.68, 0.3), 3)
	fl.custom_minimum_size.x = 18
	fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_food_row.add_child(fl)
	_food = _bar(Color(1.0, 0.62, 0.25), 140, 4, true)
	_food.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_food_row.add_child(_food)
	# 饱食度去掉了（换成了丹药），这一行不显示
	_food_row.visible = false


## 状态小标签：灵相附体、定身、减速、封神通、易伤、瓶颈、引兽香
func _update_status(p: Player) -> void:
	var st: Array = []
	if Profile.at_bottleneck():
		st.append(["瓶颈 · 吸收第%s灵环才能升级" % Data.RING_NAMES[mini(Profile.next_ring_index(), Data.RING_NAMES.size() - 1)], UiKit.GOLD])
	if not p.empower.is_empty():
		st.append(["%s %d" % [Data.SKILLS[p.empower["sid"]]["name"], ceili(float(p.empower["t"]))], UiKit.GOLD])
	if p.root_t > 0.0:
		st.append(["定身 %.1f · 连按空格" % p.root_t, UiKit.RED])
	if p.slow_t > 0.0:
		st.append(["减速 %.1f" % p.slow_t, UiKit.JADE])
	if p.silence_t > 0.0:
		st.append(["封神通 %.1f" % p.silence_t, Color(0.75, 0.55, 1.0)])
	if p.vuln_t > 0.0:
		st.append(["易伤 %.1f" % p.vuln_t, UiKit.RED])
	var gold := Profile.item_count("gold_bites")
	if gold > 0:
		st.append(["引兽香 %d" % gold, UiKit.GREEN])
	# 丹药 / 神通的增益（剩几秒）
	var bn := {"dmg": ["破境 · 伤害", Color(1.0, 0.3, 0.8)], "speed": ["疾风", Color(0.45, 1.0, 0.6)], "dr": ["金刚 · 减伤", Color(1.0, 0.8, 0.3)]}
	for k in bn:
		if p.buffs.has(k):
			st.append(["%s %d" % [bn[k][0], ceili(float(p.buffs[k][1]))], bn[k][1]])
	if p._giant_t > 0.0:
		st.append(["巨灵 %d" % ceili(p._giant_t), Color(1.0, 0.55, 0.2)])
	var sig := str(st)
	if sig == _status_sig:
		return
	_status_sig = sig
	for c in _status.get_children():
		c.queue_free()
	for s in st:
		_status.add_child(UiKit.chip(str(s[0]), s[1], 13))


# ------------------------------------------------------------------ 下中：交互、引魂索、神通

func _build_bottom_center() -> void:
	var bc := VBoxContainer.new()
	_bc_box = bc
	UiKit.place(bc, Vector4(0.5, 1, 0.5, 1), Vector4(-420, -330, 420, -22))
	bc.alignment = BoxContainer.ALIGNMENT_END
	bc.add_theme_constant_override("separation", 8)
	bc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bc)
	_interact = CenterContainer.new()
	_interact.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bc.add_child(_interact)
	_bar_box = VBoxContainer.new()
	_bar_box.visible = false
	_bar_box.add_theme_constant_override("separation", 4)
	_bar_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bc.add_child(_bar_box)
	_bar_label = UiKit.bold("", 16, UiKit.MOON, 3)
	_bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bar_box.add_child(_bar_label)
	_bar_a = _bar(Color(0.55, 0.85, 1.0), 380, 10, true)
	_bar_a.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bar_box.add_child(_bar_a)
	_bar_b = _bar(Color(1.0, 0.4, 0.3), 380, 10, true)
	_bar_b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bar_box.add_child(_bar_b)
	_prompt = UiKit.label("", 15, UiKit.MOON, 3)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bc.add_child(_prompt)
	# 神通：三个方块，冷却时从上往下转一圈变亮
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bc.add_child(row)
	_sk_row = row
	for k in 3:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(v)
		var box := {"frame": Color(1, 1, 1, 0.2), "cd": 0.0, "shown": "", "ready_t": 0.0}
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(62, 62)
		slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.draw.connect(func():
			var s := slot.size
			slot.draw_rect(Rect2(Vector2.ZERO, s), Color(0.02, 0.03, 0.05, 0.62)))
		v.add_child(slot)
		var icon := UiKit.icon("lock", 40, UiKit.MIST)
		slot.add_child(icon)
		UiKit.place(icon, Vector4(0, 0, 1, 1), Vector4(11, 11, -11, -11))
		var over := Control.new()
		over.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(over)
		UiKit.fill(over)
		over.draw.connect(_draw_skill_over.bind(over, box))
		var cd := UiKit.num("", 26, Color.WHITE, 3)
		cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot.add_child(cd)
		UiKit.fill(cd)
		var key := UiKit.keycap(["Q", "E", "F"][k], 12)
		key.position = Vector2(-8, -8)
		slot.add_child(key)
		var nm := UiKit.bold("", 13, Color.WHITE, 3)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.custom_minimum_size.x = 110
		nm.visible = false   # 字少一点：神通名放的时候上面会喊出来
		v.add_child(nm)
		box["icon"] = icon
		box["over"] = over
		box["cdl"] = cd
		box["name"] = nm
		_sk_boxes.append(box)
	_callout = UiKit.title("", 26, UiKit.GOLD)
	_callout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiKit._text_style(_callout, 4)
	UiKit.place(_callout, Vector4(0.5, 1, 0.5, 1), Vector4(-500, -236, 500, -198))
	_root.add_child(_callout)


## 神通格子上层：冷却的暗色扇形（顺时针退掉）、边框（灵环颜色）、刚好冷却完闪一下
func _draw_skill_over(c: Control, box: Dictionary) -> void:
	var s := c.size
	var ctr := s * 0.5
	var k: float = box["cd"]
	if k > 0.0:
		var pts := PackedVector2Array([ctr])
		var n := 32
		var r := s.length()
		for i in n + 1:
			var a := -PI * 0.5 + TAU * (1.0 - k) + TAU * k * float(i) / n
			var q := ctr + Vector2.from_angle(a) * r
			pts.append(Vector2(clampf(q.x, 0.0, s.x), clampf(q.y, 0.0, s.y)))
		c.draw_colored_polygon(pts, Color(0, 0, 0, 0.62))
	var fc: Color = box["frame"]
	c.draw_rect(Rect2(Vector2(1, 1), s - Vector2(2, 2)), fc, false, 2.0)
	var rt: float = box["ready_t"]
	if rt > 0.0:
		c.draw_rect(Rect2(Vector2(-3, -3), s + Vector2(6, 6)), Color(fc.r, fc.g, fc.b, rt), false, 3.0)


func _refresh_skills() -> void:
	_skills_n = Profile.rings.size()
	for b in _sk_boxes:
		b["shown"] = ""


func _update_skill_slot(p: Player, dt: float) -> void:
	for k in _sk_boxes.size():
		var box: Dictionary = _sk_boxes[k]
		var r: int = world.skills.slot_ring(k)
		var icon: TextureRect = box["icon"]
		var cdl: Label = box["cdl"]
		var nm: Label = box["name"]
		if r < 0:
			var nr := Profile.rings.size()
			var spare := false
			for i in nr:
				if not i in Profile.skill_slots:
					spare = true
			var key := "-%d%s" % [nr, spare]
			if box["shown"] != key:
				box["shown"] = key
				icon.texture = load(UiKit.ICONS + "lock.svg")
				icon.modulate = Color(1, 1, 1, 0.3)
				box["frame"] = Color(1, 1, 1, 0.14)
				box["cd"] = 0.0
				cdl.text = ""
				if spare:
					nm.text = "按 K 装神通"
				elif nr < Data.MAX_RINGS:
					nm.text = "%d 级 · 第%s灵环" % [(nr + 1) * 10, Data.RING_NAMES[nr]]
				else:
					nm.text = ""
				nm.add_theme_color_override("font_color", UiKit.DIM)
				(box["over"] as Control).queue_redraw()
			continue
		var sid: String = world.skills.slot_skill(r)
		var s: Dictionary = Data.SKILLS[sid]
		var age := int(Profile.rings[r]["age"])
		if box["shown"] != sid:
			box["shown"] = sid
			icon.texture = load(UiKit.ICONS + UiKit.skill_icon(sid) + ".svg")
			nm.text = str(s["name"])
			nm.add_theme_color_override("font_color", Color.WHITE)
			box["frame"] = Data.AGES[age]["glow"]
		var cd: float = world.skills.cooldowns[r]
		var cost := int(s["cost"])
		var full := maxf(float(s.get("cd", 1.0)), 0.1)
		var was: float = box["cd"]
		if cd > 0.0:
			box["cd"] = clampf(cd / full, 0.0, 1.0)
			cdl.text = "%d" % ceili(cd)
			icon.modulate = Color(0.6, 0.6, 0.6)
		else:
			box["cd"] = 0.0
			cdl.text = ""
			if was > 0.0:
				box["ready_t"] = 1.0
			icon.modulate = Color.WHITE if p.soul >= cost else Color(0.4, 0.55, 1.0, 0.8)
		box["ready_t"] = maxf(float(box["ready_t"]) - dt * 2.5, 0.0)
		(box["over"] as Control).queue_redraw()


func _set_interact(text: String) -> void:
	text = UiKit.keys(text)
	if text == _interact_sig:
		return
	_interact_sig = text
	for c in _interact.get_children():
		c.queue_free()
	if text == "":
		return
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.glass_style(0.62, 14, 7))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interact.add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	# "按 F 打开千机阁暗器铺" → [F] 打开千机阁暗器铺
	var rx := RegEx.create_from_string("^按(住)? ?([A-Z0-9]) (.*)$")
	var m := rx.search(text)
	if m:
		if m.get_string(1) != "":
			h.add_child(UiKit.label("按住", 18, UiKit.MIST))
		h.add_child(UiKit.keycap(m.get_string(2), 16))
		h.add_child(UiKit.bold(m.get_string(3), 18, Color(1, 0.96, 0.85)))
	else:
		var l := UiKit.bold(text, 18, Color(1, 0.96, 0.85))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = mini(text.length() * 18, 760)
		h.add_child(l)


func _update_lure_ui(p: Player) -> void:
	var lure := p.lure
	_bar_box.visible = false
	var t := Time.get_ticks_msec() / 1000.0
	_prompt.add_theme_color_override("font_color", UiKit.MOON)
	match lure.state:
		Lure.S.IDLE:
			_prompt.text = ""   # 闲着的时候不常驻提示（按键在暂停菜单里）
		Lure.S.CHARGING:
			_prompt.text = "松开 G 甩出去"
			_prompt.add_theme_font_size_override("font_size", 18)
			_prompt.modulate = Color(1, 1, 1, 0.9)
		Lure.S.FLYING, Lure.S.RETURNING:
			_prompt.text = ""
		Lure.S.WAITING:
			_prompt.add_theme_font_size_override("font_size", 17)
			_prompt.modulate = Color(1, 1, 1, 0.85)
			if lure.habitat == "":
				_prompt.text = "这里没有灵兽 · G 收回"
			else:
				_prompt.text = "等灵兽咬住…（%s）· G 收回" % Data.HABITATS[lure.habitat]["name"]
		Lure.S.BITE:
			_prompt.text = "咬住了！按 G 拽！"
			_prompt.add_theme_font_size_override("font_size", 30)
			var flash := 0.75 + 0.25 * sin(t * 25.0)
			var c := Data.age_color(lure.age) if lure.age > 0 else Color(1.0, 0.9, 0.35)
			_prompt.modulate = Color(1, 1, 1, flash)
			_prompt.add_theme_color_override("font_color", c)
		Lure.S.REELING:
			_prompt.text = "按住 G 拉！拉力变红就松开"
			_prompt.add_theme_font_size_override("font_size", 22)
			_prompt.modulate = Color(0.85, 0.7, 1.0)
			_bar_box.visible = true
			_bar_label.text = "千年%s · 上面是进度，下面是拉力" % Data.BEASTS[lure.species]["name"]
			_bar_a.value = lure.reel_progress
			_bar_b.value = lure.reel_tension
			var fill: StyleBoxFlat = _bar_b.get_theme_stylebox("fill")
			fill.bg_color = Color(0.5, 0.9, 0.5).lerp(Color(1.0, 0.25, 0.2), smoothstep(0.4, 0.9, lure.reel_tension))

	if _touch_on:
		_prompt.text = UiKit.keys(_prompt.text)


# ------------------------------------------------------------------ 右下：暗器、弹药、物品栏

func _build_bottom_right() -> void:
	var br := VBoxContainer.new()
	_br_box = br
	UiKit.place(br, Vector4(1, 1, 1, 1), Vector4(-520, -230, -26, -22))
	br.alignment = BoxContainer.ALIGNMENT_END
	br.add_theme_constant_override("separation", 2)
	br.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(br)
	var wr := HBoxContainer.new()
	wr.alignment = BoxContainer.ALIGNMENT_END
	wr.add_theme_constant_override("separation", 8)
	wr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	br.add_child(wr)
	_ench = UiKit.bold("", 13, UiKit.JADE, 3)
	_ench.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wr.add_child(_ench)
	_weapon = UiKit.bold("袖箭", 18, Color.WHITE, 3)
	wr.add_child(_weapon)
	var ar := HBoxContainer.new()
	ar.alignment = BoxContainer.ALIGNMENT_END
	ar.add_theme_constant_override("separation", 6)
	ar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	br.add_child(ar)
	_ammo = UiKit.num("10", 62, Color.WHITE, 3)
	ar.add_child(_ammo)
	_ammo_max = UiKit.num("/ 10", 26, UiKit.MIST, 3)
	_ammo_max.size_flags_vertical = Control.SIZE_SHRINK_END
	_ammo_max.custom_minimum_size.y = 58
	_ammo_max.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	ar.add_child(_ammo_max)
	_reload = UiKit.bold("", 15, UiKit.GOLD, 3)
	_reload.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_reload.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	br.add_child(_reload)
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	br.add_child(gap)
	_hotbar = HBoxContainer.new()
	_hotbar.alignment = BoxContainer.ALIGNMENT_END
	_hotbar.add_theme_constant_override("separation", 4)
	_hotbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	br.add_child(_hotbar)


## 物品栏：1 主暗器 2 袖箭 3 九转雷莲 4 回血丹 5 灵骨，当前的高亮
func _update_hotbar(p: Player) -> void:
	var slots: Array = []
	for i in 5:
		var nm := ""
		match i:
			0:
				nm = str(p.gun.d["name"]) if p.slot == 0 else (str(Data.WEAPONS[p.primaries()[0]]["name"]) if not p.primaries().is_empty() else "")
				if p.primaries().size() > 1:
					nm += "…"
			1:
				# 副手：拿着的那把；没拿着就显示上次用的（按 2 在袖箭和寒梅袖箭之间换）
				var ss: Array = p.sidearms()
				if ss.is_empty():
					nm = "空手"
				else:
					var sid := p.gun.id if (p.slot == 1 and p.gun.id in ss) else (p._side_pick if p._side_pick in ss else str(ss[0]))
					nm = str(Data.WEAPONS[sid]["name"]) + ("…" if ss.size() > 1 else "")
			2:
				nm = "雷莲 %d" % Profile.item_count("grenade") if Profile.item_count("grenade") > 0 else ""
			3:
				# 4 号位：现在拿的丹药和个数（有好几种就加个"…"，再按 4 换）
				var k4 := p.cur_pill()
				nm = ("%s %d%s" % [Data.ITEMS[k4]["name"], Profile.item_count(k4), "…" if p.owned_pills().size() > 1 else ""]) if Profile.item_count(k4) > 0 else ""
			4:
				nm = "灵骨 %d" % p.spare_bones().size() if not p.spare_bones().is_empty() else ""
		slots.append(nm)
	var sig := "%d|%s" % [p.slot, "|".join(slots)]
	if sig != _hot_sig:
		_hot_sig = sig
		for c in _hotbar.get_children():
			c.queue_free()
		for i in 5:
			var on := i == p.slot
			var empty: bool = slots[i] == ""
			var box := PanelContainer.new()
			var st := UiKit._flat(Color(0.03, 0.04, 0.06, 0.88 if on else 0.72), 8, 4, 2)
			st.border_color = UiKit.GOLD if on else Color(1, 1, 1, 0.1)
			st.set_border_width_all(1)
			st.border_width_bottom = 2 if on else 1
			box.add_theme_stylebox_override("panel", st)
			box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.custom_minimum_size = Vector2(78 if on else 64, 40)
			var v := VBoxContainer.new()
			v.add_theme_constant_override("separation", -3)
			v.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(v)
			v.add_child(UiKit.num(str(i + 1), 14, UiKit.GOLD if on else UiKit.DIM, 0))
			var l := UiKit.bold("—" if empty else str(slots[i]), 13, Color.WHITE if on else (UiKit.DIM if empty else UiKit.MIST), 0)
			l.clip_text = true
			v.add_child(l)
			_hotbar.add_child(box)
	# 手上拿的是道具：弹药那里显示数量和用法
	if p.slot >= 2:
		_ench.text = ""
		_ammo_max.text = ""
		match p.slot:
			2:
				_weapon.text = "九转雷莲"
				_ammo.text = "×%d" % Profile.item_count("grenade")
				_reload.text = "左键扔出去炸 · T 丢给队友"
			3:
				_weapon.text = "回血丹"
				_ammo.text = "×%d" % Profile.item_count("pill")
				_reload.text = "左键吃掉回血 · T 丢给队友"
			4:
				var e := p.spare_bone()
				_weapon.text = Data.bone_name(e)
				_ammo.text = ""
				_ammo_max.text = Data.BONE_SLOT_NAMES.get(str(Data.bone_data(e).get("slot", "")), "")
				_reload.text = "%s\n左键装上 · T 丢出 · 再按 5 换一块" % Data.bone_desc(e)
		_ammo.add_theme_color_override("font_color", UiKit.GOLD)
	elif _weapon.text != str(p.gun.d["name"]):
		on_weapon(p.gun)


func on_ammo(g: Gun) -> void:
	var mag := int(g.d["mag"])
	_ammo.text = "%d" % g.ammo
	_ammo_max.text = "/ %d" % mag
	var low := g.ammo <= maxi(1, mag / 4)
	_ammo.add_theme_color_override("font_color", UiKit.RED if g.ammo == 0 else (Color(1, 0.8, 0.5) if low else Color.WHITE))


func on_weapon(g: Gun) -> void:
	var ench := str(Profile.enchant.get(g.id, ""))
	var st := Profile.star_of(g.id)
	_weapon.text = str(g.d["name"]) + ((" ★%d" % st) if st > 0 else "")
	_ench.text = ("◆ " + str(Data.ENCHANTS[ench]["name"])) if Data.ENCHANTS.has(ench) else ""
	if Data.ENCHANTS.has(ench):
		_ench.add_theme_color_override("font_color", Data.ENCHANTS[ench]["color"])
	on_ammo(g)


# ------------------------------------------------------------------ 画面中间：击杀奖励、横幅、吸收

func _build_center() -> void:
	_popup = VBoxContainer.new()
	_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup.add_theme_constant_override("separation", 2)
	UiKit.place(_popup, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-300, 64, 300, 240))
	_root.add_child(_popup)
	_banner = VBoxContainer.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_theme_constant_override("separation", 6)
	UiKit.place(_banner, Vector4(0.5, 0, 0.5, 0), Vector4(-400, 200, 400, 400))
	_root.add_child(_banner)
	_build_say()
	_absorb = UiKit.title("", 34, Color.WHITE)
	_absorb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiKit._text_style(_absorb, 4)
	UiKit.place(_absorb, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-500, 120, 500, 180))
	_root.add_child(_absorb)
	# 憋气条：准星下面
	_breath_box = HBoxContainer.new()
	_breath_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_breath_box.add_theme_constant_override("separation", 8)
	UiKit.place(_breath_box, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-120, 70, 120, 92))
	_root.add_child(_breath_box)
	_breath_box.add_child(UiKit.bold("憋气", 14, Color(0.7, 0.95, 1.0), 3))
	_breath = _bar(Color(0.55, 0.9, 1.0), 180, 6, true)
	_breath.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_breath_box.add_child(_breath)
	_breath_box.visible = false
	# 救人进度
	_revive_box = VBoxContainer.new()
	_revive_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_revive_box.add_theme_constant_override("separation", 4)
	UiKit.place(_revive_box, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-150, 34, 150, 70))
	_root.add_child(_revive_box)
	var rl := UiKit.bold("救起队友", 14, UiKit.GREEN, 3)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_revive_box.add_child(rl)
	_revive = _bar(UiKit.GREEN, 300, 6, true)
	_revive_box.add_child(_revive)
	_revive_box.visible = false


func revive_progress(k: float) -> void:
	_revive_box.visible = k >= 0.0
	if k >= 0.0:
		_revive.value = clampf(k, 0.0, 1.0)


## 击杀奖励：准星下方，一个大数字 + 几个小标签（使命召唤那样），往上一弹
func kill_popup(money: int, xp: int, tags: Array, _species: String, _age: int) -> void:
	for c in _popup.get_children():
		c.queue_free()
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup.add_child(row)
	row.add_child(UiKit.num("+%d" % money, 36, UiKit.GOLD, 3))
	var cr: int = world.combo.rank() if world.combo else 0
	if cr >= 1:
		var rl := UiKit.title(str(Combo.RANKS[cr][0]), 26, Combo.RANKS[cr][3])
		UiKit._text_style(rl, 3)
		rl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(rl)
	var xl := UiKit.bold("+%d 修为" % xp, 16, Color(0.85, 0.9, 1.0), 3)
	xl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(xl)

	# 字少一点：灵兽名字、爆头 / 空中击杀这些标签都不写了，只有连杀才提一句
	for t in tags:
		var ts := str(t)
		if "连杀" in ts or ts.begins_with("双杀"):
			var ch := UiKit.chip(ts.split("  ")[0], Color(1, 0.9, 0.6), 13)
			ch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			_popup.add_child(ch)
	_popup.modulate.a = 1.0
	_popup.position.y = _popup.get_parent_area_size().y * 0.5 + 84.0
	var tw := _popup.create_tween()
	tw.tween_property(_popup, "position:y", _popup.get_parent_area_size().y * 0.5 + 64.0, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_popup_t = 2.2


## 大横幅（章节、升级、Boss 打赢）：命运2 进入新区域那样，标题两边一条细线
func _show_banner(title: String, sub: String, color: Color, time := 4.0) -> void:
	for c in _banner.get_children():
		c.queue_free()
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(row)
	for side in 2:
		var line := ColorRect.new()
		line.color = Color(color.r, color.g, color.b, 0.7)
		line.custom_minimum_size = Vector2(90, 2)
		line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(line)
		if side == 0:
			var t := UiKit.title(title, 44, color)
			t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			UiKit._text_style(t, 4)
			row.add_child(t)
	if sub != "":
		var s := UiKit.label(sub, 18, Color(0.93, 0.95, 0.98), 3)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_banner.add_child(s)
	_banner_t = time
	_banner.modulate.a = 0.0


# ------------------------------------------------------------------ 剧情：人物说话、天枢记忆

## 人物说话的字幕：底部那一列（神通、交互提示）正上方，毛玻璃底；一句说完再出下一句
func _build_say() -> void:
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.place(cc, Vector4(0.5, 1, 0.5, 1), Vector4(-700, -420, 700, -338))
	_root.add_child(cc)
	_say_box = PanelContainer.new()
	_say_box.add_theme_stylebox_override("panel", UiKit.glass_style(0.5, 22, 10))
	_say_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_say_box.modulate.a = 0.0
	cc.add_child(_say_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_say_box.add_child(v)
	_say_who = UiKit.kicker("", UiKit.GOLD, 14)
	_say_who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_say_who)
	_say_text = UiKit.label("", 24, Color(0.97, 0.95, 0.9), 3)
	_say_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_say_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_say_text)


## who 说 text（灵主、青崖子、灵环记忆、秘境刻字……）。dur = 0：按字数算停多久
func say(who: String, text: String, color := UiKit.GOLD, dur := 0.0) -> void:
	if text == "":
		return
	if dur <= 0.0:
		dur = clampf(2.4 + text.length() * 0.13, 3.2, 7.5)
	_say_queue.append([who, text, color, dur])


## 清掉还没说的（和人说话时按 F 换下一句，不排长队）
func say_clear() -> void:
	_say_queue.clear()
	_say_t = minf(_say_t, 0.25)


func _update_say(dt: float) -> void:
	if _say_t > 0.0:
		_say_t -= dt
		_say_box.modulate.a = minf(clampf(_say_t / 0.5, 0.0, 1.0), clampf((_say_dur - _say_t) / 0.3, 0.0, 1.0))
		return
	_say_box.modulate.a = 0.0
	if _say_queue.is_empty():
		return
	var e: Array = _say_queue.pop_front()
	_say_who.text = str(e[0])
	_say_who.add_theme_color_override("font_color", e[2])
	_say_text.text = str(e[1])
	_say_text.custom_minimum_size.x = minf(Data.font_ui.get_string_size(_say_text.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x + 6.0, 1100.0)
	_say_dur = float(e[3])
	_say_t = _say_dur


## 天枢记忆（灵主碎片里封着的三万年前那一夜）：压暗画面，三句一句一句浮出来；不挡操作，十几秒自己散掉。
## 以后有了 AI 画的图，换成过场视频
func memory(title: String, lines: Array) -> void:
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(layer)
	UiKit.fill(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.015, 0.02, 0.035, 0.74)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bg)
	UiKit.fill(bg)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 22)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.place(v, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-640, -200, 640, 200))
	layer.add_child(v)
	var k := UiKit.kicker(title, UiKit.GOLD, 16)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(k)
	var ls: Array = []
	for line in lines:
		var l := UiKit.label(str(line), 26, Color(0.96, 0.94, 0.88), 3)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.modulate.a = 0.0
		v.add_child(l)
		ls.append(l)
	layer.modulate.a = 0.0
	var tw := layer.create_tween()
	tw.tween_property(layer, "modulate:a", 1.0, 0.8)
	for l in ls:
		tw.tween_property(l, "modulate:a", 1.0, 0.9)
		tw.tween_interval(3.0)
	tw.tween_interval(1.2)
	tw.tween_property(layer, "modulate:a", 0.0, 1.2)
	tw.tween_callback(layer.queue_free)


func chapter_banner(name: String, intro: String) -> void:
	# 介绍只留第一句
	var first := intro.split("。")[0]
	_show_banner(name, first, UiKit.MOON, 5.0)


func level_up(level: int) -> void:
	_show_banner("%d 级" % level, "", UiKit.GOLD, 1.8)


func quest_done(text: String, reward: int) -> void:
	toast("✔ %s%s" % [text, ("    +%d 灵石" % reward) if reward > 0 else ""], Color(0.6, 1.0, 0.7), 4.0)
	update_quest()


## shard：这是第几块天枢碎片（0 = 不写）；shards：一共夺回了几块
func boss_defeated(name: String, money: int, bone: String, ring_age := 2, shard := 0, shards := 0) -> void:
	# 只写拿到了什么，不解释（用户：描述得太详细）
	var sub := "+%d 灵石" % money
	if bone != "":
		sub += "    灵骨【%s】" % Data.bone_name(bone)
	if shard > 0:
		sub += "\n天枢碎片 %d / 5" % shards
	_show_banner("击败 %s" % name, sub, Color(1.0, 0.85, 0.4), 6.0)


func skill_callout(slot: int, sid: String) -> void:
	_callout.text = "第%s神通 · %s" % [Data.RING_NAMES[slot], Data.SKILLS[sid]["name"]]
	_callout_t = 1.4


func absorb_start(age: int, _species: String) -> void:
	_absorb.text = "正在吸收%s灵环……" % Data.age_name(age)
	_absorb.add_theme_color_override("font_color", Data.AGES[age]["glow"] if age > 0 else Color.WHITE)
	_absorb_t = 3.0


func toast(text: String, color := Color.WHITE, time := 2.8) -> void:
	text = UiKit.keys(text)
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	_toast.custom_minimum_size.x = minf(Data.font_ui.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 4.0, 900.0)
	_toast_t = time


func hitmarker(headshot: bool, kill: bool) -> void:
	crosshair.hit(headshot, kill)


func hurt(amount: float, dir: Vector3) -> void:
	_vig_t = clampf(_vig_t + 0.35 + amount * 0.02, 0.0, 1.0)
	_hurt_dirs.append({"dir": dir, "t": 1.0})


## 被月光蛾 / 彩鳞鱼晃瞎：全屏发白，慢慢褪掉
func blind(dur: float, c: Color) -> void:
	var r := ColorRect.new()
	r.color = Color(c.r, c.g, c.b, 0.93)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(r)
	UiKit.fill(r)
	var tw := r.create_tween()
	tw.tween_interval(dur * 0.45)
	tw.tween_property(r, "color:a", 0.0, dur * 0.55).set_ease(Tween.EASE_IN)
	tw.tween_callback(r.queue_free)


## 全屏闪一下（灵环突破）
## 危险预警（用户："要砸哪里我也没看到什么提示"）：灵主的招会打到你站的地方时，屏幕四边红光一跳一跳 + 准星上方一个「！」，
## 越到砸下来那一刻跳得越快；翻滚 / 跑出去就行。BossArts 收到招式时判断会不会打到自己再调
var _danger: ColorRect
var _danger_mark: Label
var _danger_t := 0.0
var _danger_dur := 0.0


func danger(sec: float) -> void:
	if sec <= 0.05:
		return
	if _danger == null:
		_danger = ColorRect.new()
		_danger.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := ShaderMaterial.new()
		m.shader = Shader.new()
		m.shader.code = """shader_type canvas_item;
uniform float amount = 0.0;
uniform float rate = 3.0;
void fragment() {
	vec2 d = abs(UV - 0.5) * 2.0;
	float e = pow(max(d.x, d.y * 0.9), 3.5);
	float beat = 0.55 + 0.45 * sin(TIME * rate * 6.2832);
	COLOR = vec4(1.0, 0.08, 0.04, e * amount * beat * 0.75);
}"""
		_danger.material = m
		_root.add_child(_danger)
		UiKit.fill(_danger)
		_root.move_child(_danger, 1)
		_danger_mark = UiKit.label("！", 46, Color(1.0, 0.25, 0.15))
		_danger_mark.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		_danger_mark.add_theme_constant_override("outline_size", 8)
		_danger_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UiKit.place(_danger_mark, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-40, -118, 40, -56))
		_root.add_child(_danger_mark)
	# 同时好几招：按最先砸下来的那一下算
	if _danger_t <= 0.0 or sec < _danger_t:
		_danger_t = sec
		_danger_dur = sec
		Sfx.play("low_ammo", -2.0, 0.0, 0.55)


func _update_danger(dt: float) -> void:
	if _danger == null:
		return
	_danger_t -= dt
	var on := _danger_t > -0.15
	_danger.visible = on
	_danger_mark.visible = on
	if not on:
		return
	var k := clampf(1.0 - _danger_t / maxf(_danger_dur, 0.01), 0.0, 1.0)
	var m := _danger.material as ShaderMaterial
	m.set_shader_parameter("amount", 0.5 + 0.5 * k)
	m.set_shader_parameter("rate", 1.5 + 4.5 * k)
	_danger_mark.modulate.a = 0.6 + 0.4 * sin(Time.get_ticks_msec() / 1000.0 * (8.0 + 16.0 * k))
	_danger_mark.scale = Vector2.ONE * (1.0 + 0.25 * k)
	_danger_mark.pivot_offset = _danger_mark.size * 0.5


func flash(c: Color) -> void:
	var r := ColorRect.new()
	r.color = Color(c.r, c.g, c.b, 0.55)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(r)
	UiKit.fill(r)
	var tw := r.create_tween()
	tw.tween_property(r, "color:a", 0.0, 0.9).set_ease(Tween.EASE_OUT)
	tw.tween_callback(r.queue_free)


# ------------------------------------------------------------------ 猎灵连击、灵相真身

var _combo_box: Control
var _combo_rank: Label
var _combo_hits: Label
var _combo_mult: Label
var _combo_bar: ProgressBar
var _combo_shown := -1
var _tb_box: HBoxContainer
var _tb_bar: ProgressBar
var _tb_key: Control
var _tb_edge: ColorRect


func _build_combo() -> void:
	# 左边中间：评级大字母 + 连击数 + 奖励倍数 + 快断了的条
	_combo_box = HBoxContainer.new()
	_combo_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combo_box.add_theme_constant_override("separation", 12)
	UiKit.place(_combo_box, Vector4(0, 0.5, 0, 0.5), Vector4(30, -30, 380, 70))
	_combo_box.modulate.a = 0.0
	_root.add_child(_combo_box)
	_combo_rank = UiKit.title("D", 64, Color.WHITE)
	UiKit._text_style(_combo_rank, 4)
	_combo_rank.custom_minimum_size.x = 96
	_combo_rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo_box.add_child(_combo_rank)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_combo_box.add_child(v)
	_combo_hits = UiKit.num("", 30, Color.WHITE, 3)
	v.add_child(_combo_hits)
	_combo_mult = UiKit.bold("", 14, UiKit.GOLD, 3)
	v.add_child(_combo_mult)
	_combo_bar = UiKit.bar(Color.WHITE, 150, 3)
	v.add_child(_combo_bar)
	# 灵相真身充能条：神通格子上面
	_tb_box = HBoxContainer.new()
	_tb_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tb_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_tb_box.add_theme_constant_override("separation", 8)
	UiKit.place(_tb_box, Vector4(0.5, 1, 0.5, 1), Vector4(-180, -130, 180, -108))
	_root.add_child(_tb_box)
	var tl := UiKit.kicker("灵相真身", UiKit.GOLD, 12)
	UiKit._text_style(tl, 3)
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tb_box.add_child(tl)
	_tb_bar = UiKit.bar(UiKit.GOLD, 200, 5)
	_tb_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tb_box.add_child(_tb_bar)
	_tb_key = UiKit.keycap("Z", 12)
	_tb_box.add_child(_tb_key)
	# 变身时屏幕四边一圈灵相颜色的光
	_tb_edge = ColorRect.new()
	_tb_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = """shader_type canvas_item;
uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.3, 1.0);
uniform float amount = 0.0;
void fragment() {
	vec2 d = abs(UV - 0.5) * 2.0;
	float e = pow(max(d.x, d.y), 6.0);
	float wave = 0.75 + 0.25 * sin(TIME * 4.0 + (UV.x + UV.y) * 8.0);
	COLOR = vec4(tint.rgb, e * amount * wave * 0.55);
}"""
	_tb_edge.material = m
	_tb_edge.visible = false
	_root.add_child(_tb_edge)
	UiKit.fill(_tb_edge)
	_root.move_child(_tb_edge, 1)


func _update_combo(dt: float) -> void:
	var c: Combo = world.combo
	if c == null:
		return
	var on := c.hits > 0
	_combo_box.modulate.a = move_toward(_combo_box.modulate.a, 1.0 if on else 0.0, dt * (6.0 if on else 2.0))
	if on:
		var r := c.rank()
		var col: Color = Combo.RANKS[r][3]
		if r != _combo_shown:
			_combo_shown = r
			_combo_rank.text = str(Combo.RANKS[r][0])
			_combo_rank.add_theme_color_override("font_color", col)
			(_combo_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = col
		_combo_hits.text = "连击 %d" % c.hits
		_combo_mult.text = ("奖励 ×%.2f" % c.mult()) if c.mult() > 1.0 else ""
		_combo_bar.value = c.decay_left()
	# 灵相真身（第十版关掉了）
	_tb_box.visible = Combo.TRUE_BODY
	if not Combo.TRUE_BODY:
		return
	_tb_bar.value = c.meter
	var ready := c.meter >= 1.0 and not c.active()
	_tb_key.visible = ready
	if ready:
		_tb_box.modulate = Color(1, 1, 1, 0.75 + 0.25 * sin(Time.get_ticks_msec() / 150.0))
	else:
		_tb_box.modulate = Color(1, 1, 1, 0.85 if c.meter > 0.0 else 0.4)
	if _tb_edge.visible:
		(_tb_edge.material as ShaderMaterial).set_shader_parameter("amount", clampf(c.tb_t / 1.0, 0.0, 1.0))


## 连击升了一个评级：字母弹一下，S 以上屏幕闪一下
func combo_rank_up(r: int) -> void:
	_combo_shown = -1
	_combo_rank.pivot_offset = _combo_rank.size * 0.5
	_combo_rank.scale = Vector2.ONE * 1.8
	var tw := _combo_rank.create_tween()
	tw.tween_property(_combo_rank, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if r >= 4:
		var col: Color = Combo.RANKS[r][3]
		flash(Color(col.r, col.g, col.b, 0.25))


func true_body(on: bool) -> void:
	_tb_edge.visible = on
	if on:
		var col: Color = world.caster_color(Net.my_id)
		(_tb_edge.material as ShaderMaterial).set_shader_parameter("tint", col)
		(_tb_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = col
	else:
		(_tb_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = UiKit.GOLD


# ------------------------------------------------------------------ 倒地、Boss 出场

func _build_death() -> void:
	_death = Control.new()
	_death.visible = false
	_death.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_death)
	UiKit.fill(_death)
	# 画面变灰、四角压暗
	var gray := ColorRect.new()
	gray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 1.0).rgb;
	float g = dot(c, vec3(0.3, 0.59, 0.11));
	float v = smoothstep(0.2, 0.9, length(UV - 0.5) * 1.4);
	vec3 o = mix(vec3(g), c, 0.15) * (0.55 - v * 0.35);
	COLOR = vec4(o + vec3(0.12, 0.0, 0.0) * v, 1.0);
}"""
	gray.material = m
	_death.add_child(gray)
	UiKit.fill(gray)
	var c := CenterContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death.add_child(c)
	UiKit.place(c, Vector4(0, 0.5, 1, 0.5), Vector4(0, -140, 0, 180))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(v)
	var k := UiKit.kicker("倒地", UiKit.RED, 15)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(k)
	_death_title = UiKit.title("你倒下了", 52, Color.WHITE)
	_death_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_death_title)
	_death_text = UiKit.label("", 18, Color(0.85, 0.87, 0.9))
	_death_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_text.custom_minimum_size.x = 640
	_death_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_death_text)
	_death_bar = UiKit.bar(UiKit.RED, 360, 3)
	_death_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(_death_bar)
	var kc := CenterContainer.new()
	kc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(kc)
	_death_key = UiKit.key_hint("跳跃键" if Settings.touch_active() else "空格", "回码头复活", 17)
	kc.add_child(_death_key)


func death_countdown(t: float, team := false) -> void:
	_death.visible = t >= 0.0 or t <= -2.0
	_death_key.visible = t >= 0.0
	_death_bar.visible = t >= 0.0
	if t <= -2.0:
		_death_title.text = "被海鸥叼走了"
		_death_text.text = "马上在码头复活"
	elif t >= 0.0:
		_death_title.text = "你倒下了"
		if team:
			_death_text.text = "海鸥把你叼到了天上！队友把海鸥打下来，你掉到地上就能站起来\n%d 秒后自动回码头" % ceili(t)
		else:
			_death_text.text = "海鸥来叼你了……%d 秒后自动回码头" % ceili(t)
		_death_bar.value = clampf(t / (World.CARRY_MAX_TEAM if team else World.CARRY_MAX_SOLO), 0.0, 1.0)


func _build_intro() -> void:
	_intro = Control.new()
	_intro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro.visible = false
	_root.add_child(_intro)
	UiKit.fill(_intro)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 0.92)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if top:
			UiKit.place(bar, Vector4(0, 0, 1, 0), Vector4(0, 0, 0, 100))
		else:
			UiKit.place(bar, Vector4(0, 1, 1, 1), Vector4(0, -100, 0, 0))
		_intro.add_child(bar)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 4)
	UiKit.place(v, Vector4(0, 0.5, 1, 0.5), Vector4(0, 110, 0, 260))
	_intro.add_child(v)
	_intro_sub = UiKit.kicker("", Color(1.0, 0.75, 0.45), 16)
	_intro_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiKit._text_style(_intro_sub, 3)
	v.add_child(_intro_sub)
	_intro_title = UiKit.title("", 72, Color.WHITE)
	_intro_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiKit._text_style(_intro_title, 4)
	v.add_child(_intro_title)
	var line := ColorRect.new()
	line.color = Color(1.0, 0.75, 0.45, 0.8)
	line.custom_minimum_size = Vector2(260, 2)
	line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(line)


func boss_intro(name: String, lore := "") -> void:
	var parts := name.split(" · ")
	_intro_title.text = parts[parts.size() - 1]
	_intro_sub.text = (parts[0] if parts.size() > 1 else "灵兽") + (("  ——  " + lore) if lore != "" else "")
	_intro.visible = true
	_intro.modulate.a = 0.0
	_intro_title.scale = Vector2.ONE * 1.25
	_intro_title.pivot_offset = Vector2(get_viewport().get_visible_rect().size.x * 0.5, 50)
	var tw := _intro.create_tween()
	tw.tween_property(_intro, "modulate:a", 1.0, 0.5)
	tw.parallel().tween_property(_intro_title, "scale", Vector2.ONE, 1.2).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_interval(2.6)
	tw.tween_property(_intro, "modulate:a", 0.0, 0.8)
	tw.tween_callback(func(): _intro.visible = false)


# ------------------------------------------------------------------ 修士榜（Tab）

func _build_scores() -> void:
	_scores = PanelContainer.new()
	_scores.add_theme_stylebox_override("panel", UiKit.panel_style(Color(0.03, 0.04, 0.06, 0.88)))
	UiKit.place(_scores, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-360, -220, 360, -220))
	_scores.visible = false
	_scores.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_scores)
	_scores_list = VBoxContainer.new()
	_scores_list.add_theme_constant_override("separation", 4)
	_scores.add_child(_scores_list)


func _fill_scores() -> void:
	for c in _scores_list.get_children():
		c.queue_free()
	_scores_list.add_child(UiKit.header(("房间 %s" % Net.room_code) if Net.is_online() else "单人", "修士榜", UiKit.MOON, 34))
	var sp := Control.new()
	sp.custom_minimum_size.y = 8
	_scores_list.add_child(sp)
	var cols := [["修士", 300], ["等级", 90], ["击杀", 90], ["赚取", 120]]
	var header := HBoxContainer.new()
	for t in cols:
		var l := UiKit.kicker(str(t[0]), UiKit.MIST, 13)
		l.custom_minimum_size.x = t[1]
		header.add_child(l)
	_scores_list.add_child(header)
	var ids: Array = world.stats.keys()
	ids.sort_custom(func(a, b): return world.stats[a]["earned"] > world.stats[b]["earned"])
	for id in ids:
		var s: Dictionary = world.stats[id]
		var info: Dictionary = world.peer_info.get(id, {})
		var me: bool = id == Net.my_id
		var row := PanelContainer.new()
		var st := UiKit.row_style(UiKit.GOLD if me else Color(0, 0, 0, 0))
		st.content_margin_top = 8
		st.content_margin_bottom = 8
		st.content_margin_left = 12
		row.add_theme_stylebox_override("panel", st)
		_scores_list.add_child(row)
		var h := HBoxContainer.new()
		row.add_child(h)
		var nm: String = world.peer_name(id) + ("（你）" if me else "") + ("  房主" if id == 1 and Net.is_online() else "")
		var vals := [nm, str(info.get("level", 1)), str(s["kills"]), str(s["earned"])]
		for i in cols.size():
			var l: Label = UiKit.bold(vals[i], 18, UiKit.GOLD if me and i == 0 else UiKit.MOON) if i == 0 else UiKit.num(vals[i], 22, UiKit.MOON, 0)
			l.custom_minimum_size.x = cols[i][1] - (12 if i == 0 else 0)
			h.add_child(l)
	# 悬赏（HUD 上不常驻，在这里看）
	if not Profile.bounties.is_empty():
		var gap := Control.new()
		gap.custom_minimum_size.y = 10
		_scores_list.add_child(gap)
		update_bounties()
		for c in _bounty.get_children():
			c.reparent(_scores_list)


# ------------------------------------------------------------------ 暂停（Valorant 那样：左边一列大字菜单，右边按键说明）

func _build_pause() -> void:
	_pause = UiKit.backdrop(0.66)
	_pause.visible = false
	add_child(_pause)
	UiKit.fill(_pause)
	_pause_menu = Control.new()
	_pause_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause.add_child(_pause_menu)
	UiKit.fill(_pause_menu)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	UiKit.place(left, Vector4(0, 0.5, 0, 0.5), Vector4(110, -300, 560, 320))
	_pause_menu.add_child(left)
	left.add_child(UiKit.header("暂停", "苍墟 · 猎灵", UiKit.MOON, 46))
	_pause_code = UiKit.label("", 17, UiKit.MIST)
	_pause_code.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_pause_code)
	var sp := Control.new()
	sp.custom_minimum_size.y = 22
	left.add_child(sp)
	var items := [
		["继续游戏", true, func(): world.set_paused(false)],
		["灵相与灵环", false, func(): world.set_paused(false); toggle_wuhun()],
		["成就", false, func(): world.set_paused(false); toggle_achievements()],
		["设置", false, func(): _pause_menu.visible = false; _settings.visible = true],
		["返回主菜单", false, func(): world.leave()],
	]
	for it in items:
		var b := UiKit.menu_item(str(it[0]), bool(it[1]), 28)
		b.pressed.connect(it[2])
		left.add_child(b)
	# 右边：操作说明
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	UiKit.place(right, Vector4(1, 0.5, 1, 0.5), Vector4(-700, -300, -110, 320))
	_pause_menu.add_child(right)
	right.add_child(UiKit.section("操作", UiKit.GOLD))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 34)
	grid.add_theme_constant_override("v_separation", 9)
	right.add_child(grid)
	var keys := [
		["WASD", "移动"], ["空格", "跳 / 挣脱定身"],
		["Shift", "冲刺 · 开镜时屏息"], ["C / Ctrl", "蹲 · 轻点翻滚"],
		["左键", "射击 / 出拳"], ["右键", "瞄准"],
		["R", "换弹"], ["1-5", "物品栏（滚轮也行）"],
		["G", "引魂索（中键也行）"], ["B", "换鱼饵"],
		["Q E F", "三个神通"], ["F", "交互 · 按住救队友"],
		["T", "丢出手上的东西"], ["H", "回血丹"],
		["X", "收起暗器（跑得快）"], ["V", "检视暗器"],
		["K", "灵相和灵骨"], ["J", "成就"],
		["M", "地图"], ["Tab", "修士榜"],
		["L", "猎灵榜（挑灵兽去猎）"],
	]
	if Combo.TRUE_BODY:
		keys.append(["Z", "灵相真身（连击充满）"])
	if Settings.touch_active():
		keys = [
			["左半屏", "按住拖动走路，推到头冲刺"], ["右半屏", "滑动转视角"],
			["大圆圈", "开火（里面是子弹数）"], ["准星圈", "开镜（点一下开 / 关）"],
			["上箭头", "跳 · 往上游 · 挣脱"], ["下箭头", "蹲 · 轻点翻滚 · 往下潜"],
			["钩子", "引魂索：按住蓄力，松开甩"], ["Q E F", "三个神通"],
			["交互", "旁边有东西才出现 · 按住救人"], ["回血", "吃回血丹"],
			["物品栏", "底部直接点 · 「丢」丢出去"], ["小地图", "点一下开大地图"],
			["菜单", "灵相、成就、猎灵榜、鱼饵、排名"], ["屏息", "开镜时出现，按住镜头稳"],
		]
	for k in keys:
		grid.add_child(UiKit.key_hint(str(k[0]), str(k[1]), 15, Color(0.85, 0.88, 0.92)))
	var sc := CenterContainer.new()
	sc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause.add_child(sc)
	UiKit.fill(sc)
	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.closed.connect(func(): _settings.visible = false; _pause_menu.visible = true)
	sc.add_child(_settings)


func show_pause(on: bool) -> void:
	_pause.visible = on
	_pause_menu.visible = true
	_settings.visible = false
	if Net.is_online():
		_pause_code.text = "房间码  %s  ·  发给朋友，在主菜单输入就能加入" % Net.room_code
		_pause_code.add_theme_color_override("font_color", UiKit.GOLD)
	else:
		_pause_code.text = "单人模式 · %s" % Data.CHAPTERS[world.chapter]["name"]
		_pause_code.add_theme_color_override("font_color", UiKit.MIST)


# ------------------------------------------------------------------ 面板：暗器铺、灵相、成就、神通二选一、渡船

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


## 全屏面板的底：毛玻璃 + 居中的内容区
func _fullscreen(width := 1200.0, height := 760.0) -> Array:
	var bg := UiKit.backdrop(0.66)
	add_child(bg)
	UiKit.fill(bg)
	var c := CenterContainer.new()
	bg.add_child(c)
	UiKit.fill(c)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(width, height)
	v.add_theme_constant_override("separation", 14)
	c.add_child(v)
	return [bg, v]


## 标题栏：左边眉题 + 标题，右边"Esc 关闭"
func _panel_head(v: VBoxContainer, kick: String, title: String, close_key: String, on_close: Callable) -> HBoxContainer:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	v.add_child(head)
	var sk := kick if kick != "" else title
	if sk != "":
		head.add_child(UiKit.seal(sk.substr(0, 1), 26))
	var t := UiKit.header(kick, title)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := UiKit.button("关闭  %s" % close_key, 16)
	close.size_flags_vertical = Control.SIZE_SHRINK_END
	close.pressed.connect(on_close)
	head.add_child(close)
	return head


## 成就面板（J）：三列卡片，完成的金色，没完成的显示进度条
func toggle_achievements() -> void:
	if _ach_panel and is_instance_valid(_ach_panel):
		_ach_panel.queue_free()
		_ach_panel = null
		world.set_ui_open(false)
		return
	if world.ui_open:
		return
	var fs := _fullscreen(1240, 780)
	_ach_panel = fs[0]
	var v: VBoxContainer = fs[1]
	var done := 0
	for a in Data.ACHIEVEMENTS:
		if Profile.achieved.has(a["id"]):
			done += 1
	var head := _panel_head(v, "成就", "%d / %d" % [done, Data.ACHIEVEMENTS.size()], "J / Esc", toggle_achievements)
	var pb := UiKit.bar(UiKit.GOLD, 260, 4)
	pb.value = float(done) / maxf(1.0, Data.ACHIEVEMENTS.size())
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(pb)
	head.move_child(pb, 1)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	# 完成的排前面，没完成的按进度排
	var order: Array = Data.ACHIEVEMENTS.duplicate()
	order.sort_custom(func(x, y): return _ach_rank(x) > _ach_rank(y))
	for a in order:
		var got := Profile.achieved.has(a["id"])
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(398, 96)
		card.add_theme_stylebox_override("panel", UiKit.card_style(UiKit.GOLD if got else Color(0, 0, 0, 0), Color(1, 1, 1, 0.06) if got else UiKit.ROW))
		grid.add_child(card)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		card.add_child(h)
		h.add_child(UiKit.icon("quest", 34, UiKit.GOLD if got else UiKit.DIM))
		var rv := VBoxContainer.new()
		rv.add_theme_constant_override("separation", 3)
		rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(rv)
		rv.add_child(UiKit.bold(str(a["name"]), 18, UiKit.GOLD if got else UiKit.MOON))
		var d := UiKit.label(str(a["desc"]), 13, UiKit.MIST)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rv.add_child(d)
		var br := HBoxContainer.new()
		br.add_theme_constant_override("separation", 8)
		rv.add_child(br)
		if not got and a.has("stat"):
			var n := int(a["n"])
			var cur := mini(Profile.stat(str(a["stat"])), n)
			var b := UiKit.bar(UiKit.JADE, 150, 3)
			b.value = float(cur) / maxf(1.0, n)
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			br.add_child(b)
			br.add_child(UiKit.num("%d / %d" % [cur, n], 15, UiKit.MIST, 0))
		elif got:
			br.add_child(UiKit.chip("已完成", UiKit.GOLD, 12))
		br.add_child(UiKit.label("+%d" % int(a["reward"]), 13, UiKit.GOLD))
	world.set_ui_open(true)


func _ach_rank(a: Dictionary) -> float:
	if Profile.achieved.has(a["id"]):
		return 2.0
	if a.has("stat"):
		return clampf(float(Profile.stat(str(a["stat"]))) / maxf(1.0, float(a["n"])), 0.0, 0.99)
	return 0.0


func close_panels() -> void:
	if _choice and is_instance_valid(_choice):
		return   # 神通必须选一个
	if _ach_panel and is_instance_valid(_ach_panel):
		toggle_achievements()
		return
	if _boat_picker and is_instance_valid(_boat_picker):
		_close_boat_picker()
		return
	if _trial_picker and is_instance_valid(_trial_picker):
		_close_trial_picker()
		return
	if _board and is_instance_valid(_board):
		_close_board()
		return
	_shop.visible = false
	_wuhun.visible = false
	world.set_ui_open(false)


## 吸收完灵环：从两个神通里选一个（两张大卡，整张都能点）
func choose_skill(age: int, species: String) -> void:
	var slot := Profile.rings.size()
	var tree: Array = Data.SKILL_TREE[Data.wuhun_id(Settings.wuhun)]
	if slot >= tree.size():
		return
	var opts: Array = tree[slot]
	_absorb.text = ""
	var fs := _fullscreen(900, 0)
	_choice = fs[0]
	var v: VBoxContainer = fs[1]
	v.add_theme_constant_override("separation", 10)
	var ring_c: Color = Data.AGES[age]["glow"]
	var k := UiKit.kicker("第%s灵环 · %s · %s" % [Data.RING_NAMES[slot], Data.age_name(age), Data.BEASTS.get(species, {"name": "灵兽"})["name"]], ring_c, 16)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(k)
	var t := UiKit.title("领悟神通", 52, Color.WHITE)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var sub := UiKit.label("二选一，选了就不能换 · 选好以后在 K 面板里把它装到 Q / E / F", 17, UiKit.MIST)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size.y = 14
	v.add_child(gap)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	v.add_child(row)
	for sid in opts:
		var s: Dictionary = Data.SKILLS[sid]
		var card := UiKit.card_button(ring_c)
		card.custom_minimum_size = Vector2(420, 400)
		row.add_child(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 12)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(cv)
		UiKit.place(cv, Vector4(0, 0, 1, 1), Vector4(30, 30, -30, -26))
		var ic := _painter(Vector2(96, 96), func(c: Control):
			c.draw_circle(Vector2(48, 48), 46.0, Color(ring_c.r, ring_c.g, ring_c.b, 0.14))
			c.draw_arc(Vector2(48, 48), 45.0, 0.0, TAU, 48, ring_c, 3.0, true))
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cv.add_child(ic)
		var icon := UiKit.icon(UiKit.skill_icon(sid), 52, Color.WHITE)
		ic.add_child(icon)
		UiKit.place(icon, Vector4(0, 0, 1, 1), Vector4(22, 22, -22, -22))
		var n := UiKit.title(str(s["name"]), 34, UiKit.GOLD)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(n)
		var chips := HBoxContainer.new()
		chips.alignment = BoxContainer.ALIGNMENT_CENTER
		chips.add_theme_constant_override("separation", 8)
		chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.add_child(chips)
		chips.add_child(UiKit.chip("灵力 %d" % int(s["cost"]), Color(0.55, 0.72, 1.0), 13))
		chips.add_child(UiKit.chip("冷却 %d 秒" % int(s["cd"]), UiKit.MIST, 13))
		if bool(s.get("shen", false)):
			chips.add_child(UiKit.chip("神技", UiKit.GOLD, 13))
		var d := UiKit.label(str(s["desc"]), 17, Color(0.88, 0.9, 0.94))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cv.add_child(d)
		var pick := UiKit.kicker("点击选择", ring_c, 14)
		pick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(pick)
		var sid2 := str(sid)
		card.pressed.connect(func():
			world.finish_absorb(age, species, sid2)
			_choice.queue_free()
			_choice = null
			world.set_ui_open(false)
			_refresh_skills())
	world.set_ui_open(true)


## 渡船：一张卡一个目的地
func open_boat_picker(dests: Array) -> void:
	if _boat_picker and is_instance_valid(_boat_picker):
		_boat_picker.queue_free()
	var fs := _fullscreen(1000, 0)
	_boat_picker = fs[0]
	var v: VBoxContainer = fs[1]
	_panel_head(v, "渡船", "去哪里", "Esc", _close_boat_picker)
	v.add_child(UiKit.label("人齐了一起出发", 16, UiKit.MIST))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 14)
	row.add_theme_constant_override("v_separation", 14)
	v.add_child(row)
	for ch in dests:
		var d: Dictionary = Data.CHAPTERS[int(ch)]
		var lv: Array = d.get("levels", [1, 20])
		var fwd: bool = int(ch) > int(world.chapter)
		var accent := UiKit.GOLD if fwd else UiKit.JADE
		var card := UiKit.card_button(accent)
		card.custom_minimum_size = Vector2(320, 150)
		row.add_child(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 6)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(cv)
		UiKit.place(cv, Vector4(0, 0, 1, 1), Vector4(22, 20, -22, -18))
		cv.add_child(UiKit.kicker("下一站" if fwd else "回去", accent, 13))
		cv.add_child(UiKit.title(str(d["name"]), 28, Color.WHITE))
		cv.add_child(UiKit.label("推荐 %d ~ %d 级" % [int(lv[0]), int(lv[1])], 15, UiKit.MIST))
		var c2 := int(ch)
		card.pressed.connect(func():
			world.board(c2)
			_close_boat_picker())
	world.set_ui_open(true)


## 猎灵榜（L）：这座岛能猎的灵兽，每只写明它的灵环给你哪个神通；每只有两个年份可选（年份高的更难打、神通更强）
var _board: Control


func toggle_board() -> void:
	if _board and is_instance_valid(_board):
		_close_board()
	elif not world.ui_open:
		# 猎场里 L 是"回岛"（猎完了才行）
		if world.island.hunting:
			if world.trip:
				world.trip.key_return()
			return
		open_board()


func open_board() -> void:
	if _board and is_instance_valid(_board):
		_board.queue_free()
	var fs := _fullscreen(1260, 0)
	_board = fs[0]
	var v: VBoxContainer = fs[1]
	_panel_head(v, "猎灵榜", "挑一只灵兽，全队去猎场猎它", "L / Esc", _close_board)
	var nr := Profile.next_ring_index()
	var tip := ""
	if Profile.rings.size() >= Data.MAX_RINGS:
		tip = "十个灵环都齐了：猎到的灵环会炼成修为"
	elif Profile.ring_hole >= 0:
		tip = "第%s灵环散掉了：猎一只补上（至少%s）。卡片上写的就是你会领悟的神通" % [Data.RING_NAMES[nr], Data.age_name(int(Data.RING_MIN_AGE[nr]))]
	elif Profile.at_bottleneck():
		tip = "你卡在 %d 级瓶颈：要吸收第%s灵环（至少%s）。卡片上写的就是你会领悟的神通——想要哪个就猎哪只" % [Profile.level, Data.RING_NAMES[nr], Data.age_name(int(Data.RING_MIN_AGE[nr]))]
	else:
		tip = "第%s灵环要到 %d 级才能吸收（去秘境刷修为）。现在猎到的灵环会炼成修为；卡片上是到时候你会领悟的神通" % [Data.RING_NAMES[nr], (nr + 1) * 10]
	var tl := UiKit.label(tip, 17, Color(0.9, 0.92, 0.96))
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tl.custom_minimum_size.x = 1200
	v.add_child(tl)
	var hunt: Hunt = world.hunt
	var cur: Beast = world.beasts.get(hunt.target_id) if hunt.target_id != 0 else null
	v.add_child(UiKit.label("猎场比岛大四倍：跟着爪痕、脚印、吼声找它 · 重伤了会逃回巢穴睡觉（偷袭 ×2.5）· 虚弱了用引魂索活捉（报酬 ×1.5）· 限时 25 分钟，全队倒下 3 次失败", 15, Color(1.0, 0.75, 0.45)))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	v.add_child(grid)
	var base := hunt.base_age()
	for sp in hunt.species_list():
		var bd: Dictionary = Data.BEASTS[sp]
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiKit.card_style(Color(1.0, 0.62, 0.3, 0.5), Color(0.05, 0.06, 0.085, 0.9)))
		card.custom_minimum_size = Vector2(396, 0)
		grid.add_child(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 8)
		card.add_child(cv)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 10)
		cv.add_child(head)
		var nm := UiKit.title(str(bd["name"]), 28, Color.WHITE)
		head.add_child(nm)
		var hab := UiKit.chip(str(Data.HABITATS.get(str(bd["habitat"]), {"name": ""})["name"]), UiKit.MIST, 12)
		hab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(hab)
		# 这一章的年份和再高一档（最高十万年；百万年只有第五章三层秘境的秘境之主）
		var ages: Array = [base]
		if base < 4:
			ages.append(base + 1)
		for age in ages:
			var sid := hunt.skill_preview(str(sp), int(age))
			var s: Dictionary = Data.SKILLS.get(sid, {})
			var col: Color = Data.AGES[int(age)]["glow"]
			var box := PanelContainer.new()
			box.add_theme_stylebox_override("panel", UiKit.glass_style(0.35, 10, 8))
			cv.add_child(box)
			var bv := VBoxContainer.new()
			bv.add_theme_constant_override("separation", 4)
			box.add_child(bv)
			var r1 := HBoxContainer.new()
			r1.add_theme_constant_override("separation", 8)
			bv.add_child(r1)
			var ic := UiKit.icon(UiKit.skill_icon(sid), 26, col)
			ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			r1.add_child(ic)
			r1.add_child(UiKit.chip(Data.age_name(int(age)), col, 13, int(age) != 3))
			var sn := UiKit.bold(str(s.get("name", "")), 19, UiKit.GOLD, 0)
			sn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			r1.add_child(sn)
			if int(age) > base:
				r1.add_child(UiKit.chip("更难 · 更强", Color(1.0, 0.5, 0.4), 12))
			var d := UiKit.label(str(s.get("desc", "")), 14, Color(0.82, 0.85, 0.9))
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			d.custom_minimum_size.x = 350
			bv.add_child(d)
			var go := UiKit.button("去猎场猎%s%s王" % [Data.age_name(int(age)), bd["name"]], 16, int(age) == base)
			var sp2 := str(sp)
			var a2 := int(age)
			go.pressed.connect(func():
				hunt.request(sp2, a2)
				_close_board())
			bv.add_child(go)
	world.set_ui_open(true)
	Sfx.play("ui_click", -4.0)


func _close_board() -> void:
	if _board and is_instance_valid(_board):
		_board.queue_free()
	_board = null
	world.set_ui_open(false)


## 试炼碑：选尸潮守关还是万兽割草（两张大卡）
var _trial_picker: Control


func open_trial_picker() -> void:
	if _trial_picker and is_instance_valid(_trial_picker):
		_trial_picker.queue_free()
	var fs := _fullscreen(900, 0)
	_trial_picker = fs[0]
	var v: VBoxContainer = fs[1]
	_panel_head(v, "试炼", "选一种玩法", "Esc", _close_trial_picker)
	v.add_child(UiKit.label("队友可以随时从试炼碑加入；出了试炼，捡的暗器还回去", 16, UiKit.MIST))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	v.add_child(row)
	for m in ["chase", "musou"]:
		var md: Dictionary = Trial.MODES[m]
		var card := UiKit.card_button(md["color"])
		card.custom_minimum_size = Vector2(440, 250)
		row.add_child(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 8)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(cv)
		UiKit.place(cv, Vector4(0, 0, 1, 1), Vector4(24, 22, -24, -20))
		cv.add_child(UiKit.kicker(str(md["kick"]), md["color"], 14))
		cv.add_child(UiKit.title(str(md["name"]), 34, Color.WHITE))
		var dl := UiKit.label(str(md["desc"]), 16, UiKit.MOON)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(dl)
		var b: int = world.trial.best(m)
		var rec: String = world.trial.best_text(m)
		cv.add_child(UiKit.label(rec if b > 0 else "还没玩过", 15, UiKit.GOLD if b > 0 else UiKit.MIST))
		var mm: String = m
		card.pressed.connect(func():
			_close_trial_picker()
			world.trial.request(mm))
	world.set_ui_open(true)


func _close_trial_picker() -> void:
	if _trial_picker and is_instance_valid(_trial_picker):
		_trial_picker.queue_free()
	_trial_picker = null
	world.set_ui_open(false)


func _close_boat_picker() -> void:
	if _boat_picker and is_instance_valid(_boat_picker):
		_boat_picker.queue_free()
	_boat_picker = null
	world.set_ui_open(false)


# ------------------------------------------------------------------ 旧的神通轮盘已经不用了（玩家脚本还会问一下）

func wheel_open() -> bool:
	return false


func open_wheel(_cur: int) -> void:
	pass


func wheel_mouse(_d: Vector2) -> void:
	pass


func close_wheel() -> int:
	return 0


# ------------------------------------------------------------------ 每帧

func _process(dt: float) -> void:
	var p: Player = world.player
	_money_shown = move_toward(_money_shown, Profile.money, maxf(absf(Profile.money - _money_shown) * dt * 6.0, dt * 20.0))
	_money.text = "%d" % roundi(_money_shown)
	_room.text = ("房间 %s · %d 人" % [Net.room_code, Net.peers.size() + 1]) if Net.is_online() else ""
	_fps.text = ("%d FPS" % Engine.get_frames_per_second()) if Settings.show_fps else ""

	# 体力 / 灵力 / 修为
	var mhp := Profile.max_hp()
	_hp.value = p.hp / mhp
	var hp_fill: StyleBoxFlat = _hp.get_theme_stylebox("fill")
	hp_fill.bg_color = Color(0.95, 0.95, 0.95) if p.hp > mhp * 0.3 else Color(1.0, 0.35, 0.3)
	_shield.value = clampf(p.shield / mhp, 0.0, 1.0)
	_hp_text.text = "%d%s" % [ceili(p.hp), ("+%d" % ceili(p.shield)) if p.shield > 0.0 else ""]
	_soul.value = p.soul / Profile.max_soul()
	_soul_text.text = "%d" % int(p.soul)
	_xp.value = float(Profile.xp) / float(Data.xp_to_next(Profile.level))
	_title.text = "%s · %s" % [Data.titles(Profile.level), Settings.display_name()]
	_badge.queue_redraw()
	_update_status(p)

	# 神通
	if Profile.rings.size() != _skills_n:
		_refresh_skills()
	_update_skill_slot(p, dt)

	var g := p.gun
	if p.slot < 2:
		if g.reloading:
			_reload.text = "装针中…" if g.d["per_shell"] else "换弹中…"
		elif g.cycling > 0.0:
			_reload.text = "拉栓…"
		elif g.ammo == 0:
			_reload.text = "按 R 换弹"
		else:
			_reload.text = ""

	_toast_t -= dt
	_toast_box.modulate.a = clampf(_toast_t / 0.4, 0.0, 1.0)
	_popup_t -= dt
	_popup.modulate.a = clampf(_popup_t / 0.5, 0.0, 1.0)
	_banner_t -= dt
	# 横幅：淡入 0.4 秒，最后 0.6 秒淡出
	_banner.modulate.a = minf(clampf(_banner_t / 0.6, 0.0, 1.0), minf(_banner.modulate.a + dt * 2.5, 1.0))
	_callout_t -= dt
	_callout.modulate.a = clampf(_callout_t / 0.4, 0.0, 1.0)
	_update_say(dt)
	_update_danger(dt)
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
	_plates.queue_redraw()
	_compass.queue_redraw()
	# 水下、憋气
	_water.visible = p.under
	if p.under:
		(_water.material as ShaderMaterial).set_shader_parameter("t", Time.get_ticks_msec() / 1000.0)
	_breath_box.visible = p.air < p.max_air() - 0.05 and not p.dead
	_breath.value = p.air / p.max_air()
	_update_hotbar(p)
	_update_kings(dt)
	_update_combo(dt)

	# Boss / 正在打的灵兽王：顶上的血条
	var bk := -1.0
	if world.boss:
		bk = world.boss.hp / world.boss.max_hp
	else:
		var kb: Beast = world.focus_king()
		if kb:
			if not _boss_box.visible:
				_boss_box.visible = true
				_boss_trail = kb.hp / kb.max_hp
			_boss_kick.text = "灵兽王"
			_boss_name.text = kb.display_name()
			_boss_state.text = "逃回巢穴了" if kb._retreat else ("捆住了" if kb.root_t > 0.0 else ("暴怒" if kb._phase2 else ""))
			_boss_state.add_theme_color_override("font_color", UiKit.JADE if kb._retreat else (UiKit.GREEN if kb.root_t > 0.0 else UiKit.RED))
			bk = kb.hp / kb.max_hp
		elif _boss_box.visible:
			_boss_box.visible = false
	if bk >= 0.0:
		_boss_k = bk
		_boss_trail = bk if bk > _boss_trail else move_toward(_boss_trail, bk, dt * 0.25)
		_boss_draw.queue_redraw()

	_scope.visible = p.scoped
	if p.scoped:
		_scope.kind = "scope" if bool(p.gun.d.get("variable", false)) else "x2"
		_scope.zoom = Settings.scope_zoom if bool(p.gun.d.get("variable", false)) else float(p.gun.d.get("zoom", 2.0))
		_scope.fade = clampf((p.ads - 0.6) / 0.15, 0.0, 1.0)
	crosshair.visible = (not p.scoped and (p.ads < 0.7 or p.gun.d["mode"] == "melee")) or p.gun.charge > 0.0

	var it: Dictionary = world.nearest_interactable() if not p.dead else {}
	_set_interact(str(it.get("text", "")))

	_update_lure_ui(p)

	if Input.is_action_just_pressed("map") and not world.paused and not world.ui_open:
		_bigmap.visible = not _bigmap.visible
		Sfx.play("ui_click", -6.0)
	# 秘境场地在地图外面：小地图、大地图都不显示
	var in_dg: bool = world.away()
	if in_dg:
		_bigmap.visible = false
	_minimap.visible = not _bigmap.visible and not in_dg
	var show_scores: bool = Input.is_action_pressed("scoreboard") and not world.paused
	if show_scores != _scores.visible:
		_scores.visible = show_scores
		if show_scores:
			_fill_scores()


# ------------------------------------------------------------------ 受伤方向、任务目标标记、灵兽头顶的名字和血条

## 受伤方向：准星外面一圈红色的弧
func _draw_hurt() -> void:
	var p: Player = world.player
	var c := _hurt_layer.size * 0.5
	for h in _hurt_dirs:
		var d: Vector3 = h["dir"]
		var local := p.cam.global_basis.inverse() * d
		var a := atan2(local.x, -local.z) - PI * 0.5
		var k := float(h["t"])
		_hurt_layer.draw_arc(c, 118.0, a - 0.32, a + 0.32, 24, Color(1, 0.18, 0.12, k * 0.9), 7.0, true)
		_hurt_layer.draw_arc(c, 128.0, a - 0.18, a + 0.18, 16, Color(1, 0.3, 0.2, k * 0.5), 3.0, true)


func _quest_target() -> Variant:
	var q: Dictionary = Data.quest(world.chapter, world.quest_idx)
	if world.hunt:
		var hm: Variant = world.hunt.marker()
		if hm != null:
			return hm
	# 猎场里不标主线任务（只标能吸收的灵环）
	var inside: bool = (world.away()) or world.island.hunting
	if world.island.hunting:
		q = {}
	match "" if inside else str(q.get("target", "")):
		"dungeon":
			if not world.dungeon.portals.is_empty():
				return (world.dungeon.portals[0]["pos"] as Vector3) + Vector3(0, 3.0, 0)
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
	# 地上有能吸收的灵环：标出来
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
	var clamped := Vector2(clampf(sp.x, margin, size.x - margin), clampf(sp.y, margin + 80, size.y - margin - 140))
	if behind:
		clamped.y = size.y - margin - 140
	# 离准星太近就淡一点，不挡着打
	var near := clampf(clamped.distance_to(size * 0.5) / 160.0, 0.35, 1.0)
	var col := Color(1.0, 0.82, 0.35, 0.95 * near)
	var s := 9.0
	var dia := PackedVector2Array([clamped + Vector2(0, -s), clamped + Vector2(s, 0), clamped + Vector2(0, s), clamped + Vector2(-s, 0)])
	_marker.draw_colored_polygon(dia, Color(0, 0, 0, 0.35 * near))
	dia.append(dia[0])
	_marker.draw_polyline(dia, col, 2.0, true)
	_marker.draw_circle(clamped, 2.5, col)
	var dist := p.global_position.distance_to(tp)
	var font: Font = Data.font_num
	var t := "%dm" % roundi(dist)
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	_marker.draw_string_outline(font, clamped + Vector2(-w * 0.5, s + 18), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color(0, 0, 0, 0.5 * near))
	_marker.draw_string(font, clamped + Vector2(-w * 0.5, s + 18), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)


## 灵兽头顶：名字（年份颜色）、血条、性格 / 词缀 / 状态小字。近的、挨过打的、灵兽王才显示
func _draw_plates() -> void:
	var p: Player = world.player
	if not p or p.scoped:
		return
	var cam := p.cam
	var me := cam.global_position
	var font: Font = Data.font_bold
	for b: Beast in world.beasts.values():
		if not b.alive() or b._dead_t >= 0.0 or b.hp <= 0.0:
			continue
		var elite := b.temper == "elite"
		var top: Vector3 = b._hp_label.global_position
		var d := me.distance_to(top)
		var hurt := b.hp < b.max_hp - 0.5
		# 字少一点：灵兽王一直显示；普通灵兽只有准星对着它、或者挨过打又离得近才显示
		var max_d := 75.0 if elite else (60.0 if hurt else 45.0)
		if d > max_d or cam.is_position_behind(top):
			continue
		var sp := cam.unproject_position(top)
		if not sp.is_finite() or absf(sp.x) > 1.0e5 or absf(sp.y) > 1.0e5:
			continue
		var aimed := sp.distance_to(_plates.size * 0.5) < 140.0
		if not elite and not aimed and not (hurt and d < 18.0):
			continue
		var a := clampf((max_d - d) / 8.0, 0.0, 1.0)
		var k := clampf(1.15 - d / 90.0, 0.75, 1.1)
		var w := (170.0 if elite else 96.0) * k
		var col: Color = Data.AGES[b.age]["glow"]
		# 名字
		var nm := b.display_name() if elite else "%s %s" % [Data.age_name(b.age), b.display_name()]
		var fs := int((17.0 if elite else 14.0) * k)
		var tw := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var np := sp + Vector2(-tw * 0.5, -8.0)
		if elite:
			np.x += 9.0
			var cp := np + Vector2(-14, -fs * 0.35)
			_plates.draw_colored_polygon(PackedVector2Array([cp + Vector2(0, -6), cp + Vector2(6, 0), cp + Vector2(0, 6), cp + Vector2(-6, 0)]), Color(1.0, 0.6, 0.25, a))
		_plates.draw_string_outline(font, np, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.55 * a))
		_plates.draw_string(font, np, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col.r, col.g, col.b, a) if b.age > 0 else Color(1, 1, 1, a))
		# 血条
		var bh := 7.0 if elite else 5.0
		var r := Rect2(sp + Vector2(-w * 0.5, 0.0), Vector2(w, bh))
		_plates.draw_rect(r.grow(1.0), Color(0, 0, 0, 0.6 * a))
		var fill := Color(1.0, 0.45, 0.25) if elite else (Color(1.0, 0.32, 0.28) if b.temper == "fierce" else Color(0.95, 0.95, 0.95))
		_plates.draw_rect(Rect2(r.position, Vector2(w * clampf(b.hp / b.max_hp, 0.0, 1.0), bh)), Color(fill.r, fill.g, fill.b, a))
		# 性格、词缀、状态
		var tags: Array = []
		var tn: String = Data.TEMPERS[b.temper]["name"]
		if tn != "" and not elite:
			tags.append([tn, Data.TEMPERS[b.temper]["color"]])
		for af in b.affixes:
			tags.append([str(Data.AFFIXES.get(af, {"name": af})["name"]) + ("！" if af == "frenzy" and b._frenzy_on else ""), Color(1.0, 0.7, 0.4)])
		if b.flags & Beast.FLAG_MARK:
			tags.append(["易伤", Color(1.0, 0.5, 0.9)])
		if b.flags & Beast.FLAG_ROOT or b.root_t > 0.0:
			tags.append(["缠绕", UiKit.GREEN])
		if b.flags & Beast.FLAG_BURN:
			tags.append(["灼烧", Color(1.0, 0.55, 0.2)])
		if tags.is_empty() or not (aimed or elite):
			continue
		var ts := int(12.0 * k)
		var total := 0.0
		for t in tags:
			total += font.get_string_size(str(t[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, ts).x + 8.0
		var x := sp.x - total * 0.5
		for t in tags:
			var tt := str(t[0])
			var tc: Color = t[1]
			var tw2 := font.get_string_size(tt, HORIZONTAL_ALIGNMENT_LEFT, -1, ts).x
			_plates.draw_string_outline(font, Vector2(x, sp.y + bh + ts + 4), tt, HORIZONTAL_ALIGNMENT_LEFT, -1, ts, 3, Color(0, 0, 0, 0.55 * a))
			_plates.draw_string(font, Vector2(x, sp.y + bh + ts + 4), tt, HORIZONTAL_ALIGNMENT_LEFT, -1, ts, Color(tc.r, tc.g, tc.b, a))
			x += tw2 + 8.0
