class_name Hud
extends CanvasLayer
## 游戏内界面。
##   左上：金魂币、任务追踪          上中：Boss 血条、提示        右上：击杀信息
##   左下：体力 / 护盾 / 魂力 / 修为、道具
##   下中：当前魂技（轻按 Q 放，按住 Q 弹出魂技轮盘）、引魂索提示、交互提示
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
var _item_g: Label
var _item_h: Label
var _item_x: Label
var _skills_n := -1
var _sk_style: StyleBoxFlat
var _sk_icon: TextureRect
var _sk_mask: ColorRect
var _sk_cd: Label
var _sk_name: Label
var _sk_sub: Label
var _sk_pips: Array = []
var _sk_shown := ""
var _wheel: Control
var _wheel_items: Control
var _wheel_name: Label
var _wheel_info: Label
var _wheel_vec := Vector2.ZERO
var _wheel_sel := 0
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
var _water: ColorRect
var _breath: ProgressBar
var _breath_box: HBoxContainer
var _bag: VBoxContainer
var _bag_sig := ""
var _revive: ProgressBar
var _intro: Control
var _intro_t := 0.0
var _intro_title: Label
var _intro_sub: Label
var _food: ProgressBar
var _bounty: VBoxContainer
var _sk_more: Label
var _minimap: MapView
var _bigmap: MapView


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
	UiKit.place(_feed, Vector4(1, 0, 1, 0), Vector4(-640, 270, -30, 560))
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

	_build_extras()
	# 小地图（右上）和大地图（M）
	_minimap = MapView.new()
	_minimap.world = world
	_minimap.clip_contents = true
	UiKit.place(_minimap, Vector4(1, 0, 1, 0), Vector4(-262, 20, -22, 260))
	_root.add_child(_minimap)
	_bigmap = MapView.new()
	_bigmap.world = world
	_bigmap.big = true
	_bigmap.visible = false
	_bigmap.clip_contents = true
	UiKit.place(_bigmap, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-420, -420, 420, 420))
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


## 水下滤镜、憋气条、背包、救人进度、Boss 出场字幕
func _build_extras() -> void:
	_water = ColorRect.new()
	_water.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float t = 0.0;
void fragment() {
	vec2 d = UV - 0.5;
	float v = smoothstep(0.2, 0.8, length(d) * 1.2);
	float caustic = sin(UV.x * 30.0 + t * 2.0) * sin(UV.y * 24.0 - t * 1.6) * 0.03;
	COLOR = vec4(0.03, 0.22 + caustic, 0.3 + caustic, 0.42 + v * 0.4);
}"""
	var m := ShaderMaterial.new()
	m.shader = sh
	_water.material = m
	_water.visible = false
	_root.add_child(_water)
	UiKit.fill(_water)
	_root.move_child(_water, 0)
	# 憋气条：准星下面一排气泡色
	_breath_box = HBoxContainer.new()
	_breath_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_breath_box.add_theme_constant_override("separation", 8)
	UiKit.place(_breath_box, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-130, 70, 130, 96))
	_root.add_child(_breath_box)
	_breath_box.add_child(UiKit.label("憋气", 16, Color(0.7, 0.95, 1.0), 4))
	_breath = _bar(Color(0.55, 0.9, 1.0), 200, 10, true)
	_breath.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_breath_box.add_child(_breath)
	_breath_box.visible = false
	# 背包：左下，按住 T 时展开
	_bag = VBoxContainer.new()
	_bag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bag.add_theme_constant_override("separation", 2)
	UiKit.place(_bag, Vector4(0, 1, 0, 1), Vector4(24, -520, 520, -236))
	_bag.alignment = BoxContainer.ALIGNMENT_END
	_root.add_child(_bag)
	# 救人进度
	_revive = _bar(Color(0.5, 1.0, 0.6), 300, 12, true)
	UiKit.place(_revive, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-150, 40, 150, 52))
	_revive.visible = false
	_root.add_child(_revive)
	# Boss 出场：上下黑边 + 大字
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
			UiKit.place(bar, Vector4(0, 0, 1, 0), Vector4(0, 0, 0, 110))
		else:
			UiKit.place(bar, Vector4(0, 1, 1, 1), Vector4(0, -110, 0, 0))
		_intro.add_child(bar)
	_intro_title = UiKit.title("", 72, Color(1.0, 0.86, 0.5))
	_intro_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro_title.add_theme_constant_override("outline_size", 16)
	_intro_title.add_theme_color_override("font_outline_color", Color(0.15, 0.05, 0.0, 0.85))
	UiKit.place(_intro_title, Vector4(0, 0.5, 1, 0.5), Vector4(0, 130, 0, 230))
	_intro.add_child(_intro_title)
	_intro_sub = UiKit.label("", 24, Color(1, 0.95, 0.85), 8)
	_intro_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiKit.place(_intro_sub, Vector4(0, 0.5, 1, 0.5), Vector4(0, 225, 0, 265))
	_intro.add_child(_intro_sub)


func boss_intro(name: String) -> void:
	var parts := name.split(" · ")
	_intro_title.text = parts[parts.size() - 1]
	_intro_sub.text = ("—— " + parts[0] + " ——") if parts.size() > 1 else "—— 千年魂兽 ——"
	_intro.visible = true
	_intro.modulate.a = 0.0
	_intro_title.scale = Vector2.ONE * 1.3
	_intro_title.pivot_offset = Vector2(get_viewport().get_visible_rect().size.x * 0.5, 50)
	var tw := _intro.create_tween()
	tw.tween_property(_intro, "modulate:a", 1.0, 0.5)
	tw.parallel().tween_property(_intro_title, "scale", Vector2.ONE, 1.2).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_interval(2.6)
	tw.tween_property(_intro, "modulate:a", 0.0, 0.8)
	tw.tween_callback(func(): _intro.visible = false)


func update_bounties() -> void:
	if not _bounty:
		return
	for c in _bounty.get_children():
		c.queue_free()
	var head := UiKit.bold("悬赏令", 15, Color(1.0, 0.6, 0.3), 4)
	_bounty.add_child(head)
	for b in Profile.bounties:
		_bounty.add_child(UiKit.label(world.bounty_text(b), 15, UiKit.MOON, 4))


func revive_progress(k: float) -> void:
	_revive.visible = k >= 0.0
	if k >= 0.0:
		_revive.value = clampf(k, 0.0, 1.0)


## 物品栏（右下）：1 主暗器 2 袖箭 3 佛怒唐莲 4 回血丹 5 魂骨，当前的高亮
var _hot_sig := ""


func _update_hotbar(p: Player) -> void:
	var parts: Array = []
	for i in 5:
		var nm := ""
		match i:
			0:
				nm = str(p.gun.d["name"]) if p.slot == 0 else (str(Data.WEAPONS[p.primaries()[0]]["name"]) if not p.primaries().is_empty() else "")
				if p.primaries().size() > 1:
					nm += "…"
			1:
				nm = "袖箭"
			2:
				nm = "唐莲×%d" % Profile.item_count("grenade") if Profile.item_count("grenade") > 0 else ""
			3:
				nm = "回血丹×%d" % Profile.item_count("pill") if Profile.item_count("pill") > 0 else ""
			4:
				nm = "魂骨×%d" % p.spare_bones().size() if not p.spare_bones().is_empty() else ""
		if nm == "":
			nm = "—"
		parts.append(("【%d %s】" if i == p.slot else " %d %s ") % [i + 1, nm])
	var sig := "".join(parts)
	if sig != _hot_sig:
		_hot_sig = sig
		_slots.text = sig
	# 手上拿的是道具：弹药那里显示数量和用法
	if p.slot >= 2:
		match p.slot:
			2:
				_weapon.text = "佛怒唐莲"
				_ammo.text = "×%d" % Profile.item_count("grenade")
				_reload.text = "左键 扔出去炸  ·  T 丢在地上给队友"
			3:
				_weapon.text = "回血丹"
				_ammo.text = "×%d" % Profile.item_count("pill")
				_reload.text = "左键 吃掉回血  ·  T 丢给队友"
			4:
				var e := p.spare_bone()
				_weapon.text = Data.bone_name(e)
				_ammo.text = Data.BONE_SLOT_NAMES.get(str(Data.bone_data(e).get("slot", "")), "")
				_reload.text = "%s\n左键 装上  ·  T 丢出（丢进收购箱能卖）  ·  再按 5 换一块" % Data.bone_desc(e)
		_ammo.add_theme_color_override("font_color", UiKit.GOLD)
	elif _weapon.text != str(p.gun.d["name"]):
		on_weapon(p.gun)

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


func _bar(color: Color, w := 420.0, h := 14.0, slant := false) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(w, h)
	b.show_percentage = false
	b.max_value = 1.0
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	if slant:
		# 斜切的条（现代射击游戏常见）
		bg.skew = Vector2(0.35, 0)
		fg.skew = Vector2(0.35, 0)
		bg.border_color = Color(1, 1, 1, 0.12)
		bg.set_border_width_all(1)
	else:
		bg.set_corner_radius_all(int(h / 2))
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
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 8)
	tl.add_child(mrow)
	mrow.add_child(UiKit.icon("coin", 28, UiKit.GOLD))
	_money = UiKit.num("0", 32, UiKit.GOLD, 5)
	mrow.add_child(_money)
	_room = UiKit.label("", 14, UiKit.MIST, 5)
	tl.add_child(_room)
	_fps = UiKit.label("", 14, Color(0.8, 1, 0.8), 5)
	tl.add_child(_fps)
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	tl.add_child(gap)
	# 任务：左边一条金线，半透明底
	var qp := PanelContainer.new()
	var qs := StyleBoxFlat.new()
	qs.bg_color = Color(0.02, 0.03, 0.05, 0.45)
	qs.border_color = UiKit.GOLD
	qs.border_width_left = 3
	qs.content_margin_left = 14
	qs.content_margin_right = 14
	qs.content_margin_top = 8
	qs.content_margin_bottom = 10
	qp.add_theme_stylebox_override("panel", qs)
	qp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.add_child(qp)
	var qv := VBoxContainer.new()
	qv.add_theme_constant_override("separation", 2)
	qp.add_child(qv)
	var qh := HBoxContainer.new()
	qh.add_theme_constant_override("separation", 6)
	qv.add_child(qh)
	qh.add_child(UiKit.icon("quest", 16, UiKit.MIST))
	_quest_title = UiKit.label("", 14, UiKit.MIST, 4)
	qh.add_child(_quest_title)
	_quest_text = UiKit.bold("", 19, Color.WHITE, 5)
	_quest_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quest_text.custom_minimum_size.x = 400
	qv.add_child(_quest_text)
	_quest_prog = UiKit.num("", 18, UiKit.GOLD, 4)
	qv.add_child(_quest_prog)
	# 悬赏令
	_bounty = VBoxContainer.new()
	_bounty.add_theme_constant_override("separation", 0)
	_bounty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.add_child(_bounty)


func _build_bottom_left() -> void:
	# 左下一块半透明底板，和第一人称的手分开
	var holder := VBoxContainer.new()
	UiKit.place(holder, Vector4(0, 1, 0, 1), Vector4(20, -220, 470, -18))
	holder.alignment = BoxContainer.ALIGNMENT_END
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(holder)
	var bp := PanelContainer.new()
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.02, 0.03, 0.05, 0.55)
	bs.set_corner_radius_all(4)
	bs.content_margin_left = 14
	bs.content_margin_right = 18
	bs.content_margin_top = 10
	bs.content_margin_bottom = 12
	bp.add_theme_stylebox_override("panel", bs)
	bp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(bp)
	var bl := VBoxContainer.new()
	bl.add_theme_constant_override("separation", 6)
	bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bp.add_child(bl)
	# 道具：键帽 + 图标 + 数量
	var ir := HBoxContainer.new()
	ir.add_theme_constant_override("separation", 8)
	bl.add_child(ir)
	ir.add_child(UiKit.keycap("G"))
	ir.add_child(UiKit.icon("grenade", 22, Color(1.0, 0.75, 0.45)))
	_item_g = UiKit.num("0", 20, UiKit.MOON, 4)
	ir.add_child(_item_g)
	var sp := Control.new()
	sp.custom_minimum_size.x = 10
	ir.add_child(sp)
	ir.add_child(UiKit.keycap("H"))
	ir.add_child(UiKit.icon("pill", 22, Color(1.0, 0.5, 0.5)))
	_item_h = UiKit.num("0", 20, UiKit.MOON, 4)
	ir.add_child(_item_h)
	_item_x = UiKit.label("", 14, UiKit.GOLD, 4)
	ir.add_child(_item_x)
	var gap := Control.new()
	gap.custom_minimum_size.y = 4
	bl.add_child(gap)
	_level = UiKit.bold("", 16, UiKit.MIST, 4)
	bl.add_child(_level)
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 10)
	bl.add_child(hrow)
	hrow.add_child(UiKit.icon("heart", 22, Color(1.0, 0.4, 0.35)))
	var hpbox := Control.new()
	hpbox.custom_minimum_size = Vector2(360, 20)
	hrow.add_child(hpbox)
	_hp = _bar(Color(0.93, 0.3, 0.26), 360, 20, true)
	hpbox.add_child(_hp)
	_shield = _bar(Color(0.8, 0.92, 1.0, 0.85), 360, 20, true)
	(_shield.get_theme_stylebox("background") as StyleBoxFlat).bg_color = Color(0, 0, 0, 0)
	(_shield.get_theme_stylebox("background") as StyleBoxFlat).set_border_width_all(0)
	hpbox.add_child(_shield)
	_hp_text = UiKit.num("", 18, Color.WHITE, 4)
	_hp_text.position = Vector2(14, -2)
	hpbox.add_child(_hp_text)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 10)
	bl.add_child(srow)
	srow.add_child(UiKit.icon("soul", 22, Color(0.45, 0.7, 1.0)))
	_soul = _bar(Color(0.38, 0.62, 1.0), 360, 10, true)
	_soul.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	srow.add_child(_soul)
	# 饱食度
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 10)
	bl.add_child(frow)
	var fl := UiKit.bold("饱", 16, Color(1.0, 0.68, 0.3), 4)
	fl.custom_minimum_size.x = 22
	frow.add_child(fl)
	_food = _bar(Color(1.0, 0.62, 0.25), 360, 6, true)
	_food.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frow.add_child(_food)
	_xp = _bar(UiKit.GOLD, 392, 3)
	bl.add_child(_xp)


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
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	bc.add_child(row)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sk_style = StyleBoxFlat.new()
	_sk_style.bg_color = Color(0.02, 0.03, 0.05, 0.55)
	_sk_style.border_width_bottom = 2
	_sk_style.border_color = Color(1, 1, 1, 0.2)
	_sk_style.set_corner_radius_all(4)
	_sk_style.content_margin_left = 8
	_sk_style.content_margin_right = 14
	_sk_style.content_margin_top = 6
	_sk_style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", _sk_style)
	row.add_child(panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	panel.add_child(h)
	var ib := Control.new()
	ib.custom_minimum_size = Vector2(48, 48)
	ib.clip_contents = true
	h.add_child(ib)
	_sk_icon = UiKit.icon("lock", 48, UiKit.MIST)
	ib.add_child(_sk_icon)
	UiKit.fill(_sk_icon)
	_sk_mask = ColorRect.new()
	_sk_mask.color = Color(0, 0, 0, 0.6)
	_sk_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ib.add_child(_sk_mask)
	_sk_cd = UiKit.num("", 22, Color.WHITE, 4)
	_sk_cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sk_cd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ib.add_child(_sk_cd)
	UiKit.fill(_sk_cd)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	v.add_child(top)
	top.add_child(UiKit.keycap("Q"))
	_sk_name = UiKit.bold("", 18, Color.WHITE, 4)
	top.add_child(_sk_name)
	_sk_sub = UiKit.label("", 13, UiKit.MIST, 4)
	v.add_child(_sk_sub)
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 4)
	v.add_child(pips)
	for i in Data.SKILL_SLOTS:
		var d := ColorRect.new()
		d.custom_minimum_size = Vector2(14, 3)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pips.add_child(d)
		_sk_pips.append(d)
	_build_wheel()


# ------------------------------------------------------------------ 魂技轮盘（按住 Q）

const WHEEL_IN := 78.0
const WHEEL_OUT := 200.0


func _build_wheel() -> void:
	_wheel = Control.new()
	_wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wheel.visible = false
	_root.add_child(_wheel)
	UiKit.fill(_wheel)
	_wheel.draw.connect(_draw_wheel)
	_wheel_items = Control.new()
	_wheel_items.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wheel.add_child(_wheel_items)
	UiKit.fill(_wheel_items)
	var mid := VBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wheel.add_child(mid)
	UiKit.place(mid, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-70, -40, 70, 40))
	_wheel_name = UiKit.bold("", 18, Color.WHITE, 4)
	_wheel_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wheel_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mid.add_child(_wheel_name)
	_wheel_info = UiKit.label("", 13, UiKit.MIST, 4)
	_wheel_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(_wheel_info)


func wheel_open() -> bool:
	return _wheel != null and _wheel.visible


func open_wheel(cur: int) -> void:
	var n := Profile.rings.size()
	if n < 1:
		return
	_wheel_vec = Vector2.ZERO
	_wheel_sel = clampi(cur, 0, n - 1)
	for c in _wheel_items.get_children():
		c.queue_free()
	var c0 := _wheel.size * 0.5
	for i in n:
		var sid: String = world.skills.slot_skill(i)
		var dir := Vector2.from_angle(-PI * 0.5 + TAU * i / n)
		var box := VBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.size = Vector2(120, 80)
		box.position = c0 + dir * (WHEEL_IN + WHEEL_OUT) * 0.5 - box.size * 0.5
		var ic := UiKit.icon(UiKit.skill_icon(sid), 40, Data.age_color(int(Profile.rings[i]["age"])))
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(ic)
		var nm := UiKit.label(str(Data.SKILLS[sid]["name"]), 14, Color.WHITE, 4)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(nm)
		var cdl := UiKit.num("", 16, UiKit.MIST, 4)
		cdl.name = "Cd"
		cdl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(cdl)
		_wheel_items.add_child(box)
	_wheel.visible = true
	_update_wheel_text()
	_wheel.queue_redraw()
	Sfx.play("ui_click", -10.0)


## 按住 Q 时鼠标的移动用来选扇区
func wheel_mouse(d: Vector2) -> void:
	var n := Profile.rings.size()
	if n < 1:
		return
	_wheel_vec = (_wheel_vec + d).limit_length(160.0)
	if _wheel_vec.length() < 30.0:
		return
	var rel := fposmod(_wheel_vec.angle() + PI * 0.5, TAU)
	var sel := int(round(rel / (TAU / n))) % n
	if sel != _wheel_sel:
		_wheel_sel = sel
		Sfx.play("ui_click", -14.0)
		_update_wheel_text()
		_wheel.queue_redraw()


## 关掉轮盘，返回选中的魂技槽
func close_wheel() -> int:
	_wheel.visible = false
	return _wheel_sel


func _update_wheel_text() -> void:
	var sid: String = world.skills.slot_skill(_wheel_sel)
	if sid == "":
		return
	var s: Dictionary = Data.SKILLS[sid]
	_wheel_name.text = str(s["name"])
	var cd: float = world.skills.cooldowns[_wheel_sel]
	_wheel_info.text = ("冷却 %.1f 秒" % cd) if cd > 0.0 else ("魂力 %d" % int(s["cost"]))


func _draw_wheel() -> void:
	var n := Profile.rings.size()
	if n < 1:
		return
	var c := _wheel.size * 0.5
	var seg := TAU / n
	_wheel.draw_circle(c, WHEEL_OUT + 14.0, Color(0, 0, 0, 0.25))
	for i in n:
		var a0 := -PI * 0.5 + seg * i - seg * 0.5 + 0.025
		var a1 := a0 + seg - 0.05
		var pts := PackedVector2Array()
		for k in 25:
			pts.append(c + Vector2.from_angle(lerpf(a0, a1, k / 24.0)) * WHEEL_OUT)
		for k in 25:
			pts.append(c + Vector2.from_angle(lerpf(a1, a0, k / 24.0)) * WHEEL_IN)
		var on := i == _wheel_sel
		var ready: bool = world.skills.cooldowns[i] <= 0.0
		var col := Color(1.0, 0.78, 0.3, 0.32) if on else Color(0.03, 0.04, 0.06, 0.72 if ready else 0.5)
		_wheel.draw_colored_polygon(pts, col)
		pts.append(pts[0])
		_wheel.draw_polyline(pts, Color(1.0, 0.8, 0.35, 0.95) if on else Color(1, 1, 1, 0.12), 2.0 if on else 1.0, true)
	_wheel.draw_circle(c, WHEEL_IN - 8.0, Color(0.02, 0.03, 0.05, 0.8))


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
	var keys := UiKit.label("WASD 移动 · 空格 跳 · Shift 冲刺（开镜时屏息）· Ctrl 蹲\n左键 射击 · 右键 瞄准 · R 换弹 · 1-5 / 滚轮 换暗器\nE 引魂索 · Q 魂技（按住切换）· T 丢出手上的东西（按住 T 滚轮拿背包里的）\nG 佛怒唐莲 · H 回血丹 · F 交互 / 按住 F 救队友 · K 武魂和魂骨 · Tab 魂师榜", 15, UiKit.MIST)
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
	var sub := UiKit.label("选一个魂技（选了就不能换）· 轻按 Q 释放当前魂技，按住 Q 用轮盘切换", 20, UiKit.MIST)
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
	_weapon.text = str(g.d["name"])
	on_ammo(g)


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
		sub += "   获得魂骨【%s】：%s" % [Data.bone_name(bone), Data.bone_desc(bone)]
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


func death_countdown(t: float, team := false) -> void:
	_death.visible = t >= 0.0 or t <= -2.0
	if t <= -2.0:
		_death_text.text = "海鸥把你叼走了……\n马上在码头复活"
	elif t >= 0.0:
		if team:
			_death_text.text = "你倒下了！\n等队友走过来按住 F 把你拉起来\n%d 秒后海鸥会把你叼走（按空格直接放弃）" % ceili(t)
		else:
			_death_text.text = "你倒下了\n%d 秒后海鸥会把你叼回码头" % ceili(t)


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
	_sk_shown = ""
	for i in _sk_pips.size():
		var d: ColorRect = _sk_pips[i]
		d.color = Data.age_color(int(Profile.rings[i]["age"])) if i < _skills_n else Color(1, 1, 1, 0.15)


# ------------------------------------------------------------------ 每帧

func _process(dt: float) -> void:
	var p: Player = world.player
	_money_shown = move_toward(_money_shown, Profile.money, maxf(absf(Profile.money - _money_shown) * dt * 6.0, dt * 20.0))
	_money.text = "%d" % roundi(_money_shown)
	_room.text = ("房间 %s · %d 人" % [Net.room_code, Net.peers.size() + 1]) if Net.is_online() else "单人模式"
	_fps.text = ("%d FPS" % Engine.get_frames_per_second()) if Settings.show_fps else ""

	# 体力 / 魂力 / 修为
	var mhp := Profile.max_hp()
	_hp.value = p.hp / mhp
	_shield.value = clampf(p.shield / mhp, 0.0, 1.0)
	_hp_text.text = "%d%s" % [ceili(p.hp), ("  +%d" % ceili(p.shield)) if p.shield > 0.0 else ""]
	_soul.value = p.soul / Profile.max_soul()
	_food.value = Profile.food / Data.FOOD_MAX
	_food.modulate = Color(1, 0.35, 0.3) if Profile.food < 25.0 and int(Time.get_ticks_msec() / 400) % 2 == 0 else Color.WHITE
	var need := Data.xp_to_next(Profile.level)
	_xp.value = float(Profile.xp) / float(need)
	var cap := "   瓶颈 · 吸收第%s魂环" % Data.RING_NAMES[mini(Profile.rings.size(), 4)] if Profile.at_bottleneck() else ""
	_level.text = "Lv.%d  %s%s" % [Profile.level, Data.titles(Profile.level), cap]
	_level.add_theme_color_override("font_color", UiKit.GOLD if cap != "" else UiKit.MIST)
	var gold := Profile.item_count("gold_bites")
	_item_g.text = "%d" % Profile.item_count("grenade")
	_item_h.text = "%d" % Profile.item_count("pill")
	_item_x.text = ("   引兽香 %d" % gold) if gold > 0 else ""

	# 当前魂技
	_update_skill_slot(p)
	if Profile.rings.size() != _skills_n:
		_refresh_skills()

	var g := p.gun
	if g.reloading:
		_reload.text = "装针中…" if g.d["per_shell"] else "换弹中…"
	elif g.cycling > 0.0:
		_reload.text = "拉栓…"
	elif g.ammo == 0:
		_reload.text = "按 R 换弹"
	elif p.scoped:
		_reload.text = "%.1f 倍 · 滚轮调倍率 · 按住 Shift 屏息" % Settings.scope_zoom
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
	# 水下、憋气、背包
	_water.visible = p.under
	if p.under:
		(_water.material as ShaderMaterial).set_shader_parameter("t", Time.get_ticks_msec() / 1000.0)
	_breath_box.visible = p.air < p.max_air() - 0.05 and not p.dead
	_breath.value = p.air / p.max_air()
	_update_hotbar(p)

	if world.boss:
		_boss_bar.value = world.boss.hp / world.boss.max_hp
	_scope.visible = false
	crosshair.visible = not p.scoped and p.ads < 0.7

	var it: Dictionary = world.nearest_interactable() if not p.dead else {}
	_interact.text = str(it.get("text", ""))

	_update_lure_ui(p)

	if Input.is_action_just_pressed("map") and not world.paused and not world.ui_open:
		_bigmap.visible = not _bigmap.visible
		Sfx.play("ui_click", -6.0)
	_minimap.visible = not _bigmap.visible
	var show_scores: bool = Input.is_action_pressed("scoreboard") and not world.paused
	if show_scores != _scores.visible:
		_scores.visible = show_scores
		if show_scores:
			_fill_scores()


func _update_skill_slot(p: Player) -> void:
	var cur: int = world.skills.current
	var sid: String = world.skills.slot_skill(cur)
	if sid == "":
		if _sk_shown != "-":
			_sk_shown = "-"
			_sk_icon.texture = load(UiKit.ICONS + "lock.svg")
			_sk_icon.modulate = UiKit.MIST
			_sk_name.text = "魂技"
			_sk_sub.text = "10 级吸收第一魂环后解锁"
			_sk_style.border_color = Color(1, 1, 1, 0.2)
			_sk_mask.size = Vector2.ZERO
			_sk_cd.text = ""
		return
	var s: Dictionary = Data.SKILLS[sid]
	var age := int(Profile.rings[cur]["age"])
	if _sk_shown != sid:
		_sk_shown = sid
		_sk_icon.texture = load(UiKit.ICONS + UiKit.skill_icon(sid) + ".svg")
		_sk_name.text = str(s["name"])
		_sk_style.border_color = Data.age_color(age)
	var cd: float = world.skills.cooldowns[cur]
	var cost := int(s["cost"])
	var full := maxf(float(s.get("cd", 1.0)), 0.1)
	if cd > 0.0:
		var k := clampf(cd / full, 0.0, 1.0)
		_sk_mask.position = Vector2(0, 48.0 * (1.0 - k))
		_sk_mask.size = Vector2(48, 48.0 * k)
		_sk_cd.text = "%d" % ceili(cd)
		_sk_icon.modulate = Color(0.6, 0.6, 0.6)
	else:
		_sk_mask.size = Vector2.ZERO
		_sk_cd.text = ""
		_sk_icon.modulate = Color.WHITE if p.soul >= cost else Color(0.45, 0.6, 1.0)
	var more := "  ·  按住 Q 切换" if Profile.rings.size() > 1 else ""
	_sk_sub.text = "魂力 %d%s" % [cost, more]
	for i in _sk_pips.size():
		var d: ColorRect = _sk_pips[i]
		d.custom_minimum_size.y = 5.0 if i == cur else 3.0
	if _wheel.visible:
		_wheel.queue_redraw()
		var boxes := _wheel_items.get_children()
		for i in boxes.size():
			var c: float = world.skills.cooldowns[i] if i < 5 else 0.0
			(boxes[i].get_node("Cd") as Label).text = ("%.1f" % c) if c > 0.0 else ""


func _update_lure_ui(p: Player) -> void:
	var lure := p.lure
	_bar_box.visible = false
	var t := Time.get_ticks_msec() / 1000.0
	match lure.state:
		Lure.S.IDLE:
			_prompt.text = "按住 E 蓄力 · 松开甩出引魂索      B 鱼饵：%s" % p.bait_text()
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
