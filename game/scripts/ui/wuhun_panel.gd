class_name WuhunPanel
extends ColorRect
## 灵相面板（K）：左边灵相立绘和属性、猎灵录；中间十个灵环（装到 Q / E / F）；右边六块灵骨。
## 样子：全屏毛玻璃，像角色面板。

signal closed

var _body: HBoxContainer


func _ready() -> void:
	color = Color.WHITE
	material = UiKit.blur_material(0.7)
	UiKit.fill(self)
	var center := CenterContainer.new()
	add_child(center)
	UiKit.fill(center)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(1340, 800)
	v.add_theme_constant_override("separation", 14)
	center.add_child(v)
	v.add_child(UiKit.panel_head("修士", "灵相 · 灵环 · 灵骨", "K / Esc", func(): closed.emit()))
	_body = HBoxContainer.new()
	_body.add_theme_constant_override("separation", 26)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_body)


func open() -> void:
	visible = true
	for c in _body.get_children():
		c.queue_free()
	_left()
	_middle()
	_right()


func _left() -> void:
	var wi := Settings.wuhun
	var w: Dictionary = Data.WUHUN[wi]
	var wc := Data.wuhun_color(wi)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 300
	left.add_theme_constant_override("separation", 6)
	_body.add_child(left)
	# 立绘：底下渐渐融进背景
	var pic := TextureRect.new()
	pic.texture = load(w["img"])
	pic.custom_minimum_size = Vector2(300, 280)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.clip_contents = true
	left.add_child(pic)
	var fade := TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.03, 0.04, 0.06, 0.0))
	g.set_color(1, Color(0.03, 0.04, 0.06, 0.95))
	gt.gradient = g
	gt.fill_from = Vector2(0, 0.45)
	gt.fill_to = Vector2(0, 1)
	fade.texture = gt
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	pic.add_child(fade)
	UiKit.fill(fade)
	var nm := UiKit.title(str(w["name"]), 40, wc)
	nm.position = Vector2(18, 200)
	pic.add_child(nm)
	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", 8)
	left.add_child(info)
	info.add_child(UiKit.chip(str(w["kind"]), wc, 13))
	info.add_child(UiKit.chip(Profile.title(), UiKit.GOLD, 13))
	var gap := Control.new()
	gap.custom_minimum_size.y = 4
	left.add_child(gap)
	var need := Data.xp_to_next(Profile.level)
	left.add_child(UiKit.stat_bar("修为", float(Profile.xp) / float(need), "%d / %d" % [Profile.xp, need], UiKit.GOLD, 150))
	var st := HBoxContainer.new()
	st.add_theme_constant_override("separation", 16)
	left.add_child(st)
	st.add_child(_stat("体力", "%d" % int(Profile.max_hp()), Color(1.0, 0.5, 0.45)))
	st.add_child(_stat("灵力", "%d" % int(Profile.max_soul()), Color(0.55, 0.72, 1.0)))
	# 护体：等级（每级 0.4%）+ 灵骨的减伤
	st.add_child(_stat("护体", "%d%%" % roundi(minf(Data.level_armor(Profile.level) + Profile.bone_bonus("dr"), 0.8) * 100.0), Color(0.6, 0.9, 0.75)))
	st.add_child(_stat("灵环", "%d / %d" % [Profile.rings.size(), Data.MAX_RINGS], UiKit.GOLD))
	if Profile.at_bottleneck():
		var b := UiKit.chip("瓶颈 · 吸收第%s灵环才能继续升级" % Data.RING_NAMES[mini(Profile.next_ring_index(), Data.RING_NAMES.size() - 1)], UiKit.GOLD, 13)
		left.add_child(b)
	# 猎灵录：这张图每种灵兽三颗星
	var stars := Profile.codex_stars()
	left.add_child(UiKit.section("猎灵录  ★%d" % stars, UiKit.GOLD))
	var tip := UiKit.label("体力 +%d · 伤害 +%.1f%%。★ 杀 5 只 · ★★ 杀带词缀的 · ★★★ 杀千年或王；本图集齐送专属皮肤" % [stars * 2, stars * 0.5], 12, UiKit.MIST)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size.x = 300
	left.add_child(tip)
	var wld: Node = get_tree().get_first_node_in_group("world")
	if wld:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 16)
		grid.add_theme_constant_override("v_separation", 2)
		left.add_child(grid)
		for e in wld.codex_page():
			var n := int(e[1])
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 6)
			h.add_child(UiKit.label("★".repeat(n) + "☆".repeat(3 - n), 13, UiKit.GOLD if n > 0 else UiKit.DIM))
			h.add_child(UiKit.label(str(Data.BEASTS[e[0]]["name"]), 13, UiKit.MOON if n >= 3 else UiKit.MIST))
			grid.add_child(h)


func _stat(name: String, value: String, color: Color) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -4)
	v.add_child(UiKit.kicker(name, UiKit.MIST, 12))
	v.add_child(UiKit.num(value, 28, color, 0))
	return v


## 中间：十个灵环。有的：神通名、说明、Q / E / F 三个键（点了就装到那个键）
func _middle() -> void:
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 8)
	_body.add_child(mid)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	mid.add_child(head)
	var sec := UiKit.section("灵环 · 神通", UiKit.GOLD)
	sec.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sec)
	head.add_child(UiKit.label("点 Q / E / F 把神通装到那个键上", 13, UiKit.MIST))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mid.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	var hole := Profile.ring_hole
	for i in Data.MAX_RINGS:
		# 第 i 个位置对应的灵环（散魂丹散掉的位置空着，后面的往前挪了一格）
		var ri := i if (hole < 0 or i < hole) else i - 1
		var have := i != hole and ri < Profile.rings.size()
		var age: int = int(Profile.rings[ri]["age"]) if have else int(Data.RING_MIN_AGE[i])
		var glow: Color = Data.AGES[age]["glow"]
		var row := PanelContainer.new()
		var st := UiKit.row_style(glow if have else Color(1, 1, 1, 0.08))
		st.content_margin_top = 10
		st.content_margin_bottom = 10
		row.add_theme_stylebox_override("panel", st)
		list.add_child(row)
		var rh := HBoxContainer.new()
		rh.add_theme_constant_override("separation", 14)
		row.add_child(rh)
		var dot := UiKit.ring_dot(age, 34)
		dot.modulate.a = 1.0 if have else 0.3
		rh.add_child(dot)
		var rv := VBoxContainer.new()
		rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rv.add_theme_constant_override("separation", 2)
		rh.add_child(rv)
		if have:
			var r: Dictionary = Profile.rings[ri]
			var s: Dictionary = Data.SKILLS[r["skill"]]
			rv.add_child(UiKit.kicker("第%s灵环 · %s · %s" % [Data.RING_NAMES[i], Data.age_name(age), Data.BEASTS.get(r["beast"], {"name": "?"})["name"]], glow, 12))
			var top := HBoxContainer.new()
			top.add_theme_constant_override("separation", 10)
			rv.add_child(top)
			top.add_child(UiKit.title(str(s["name"]), 24, UiKit.GOLD))
			top.add_child(UiKit.chip("灵力 %d" % int(s["cost"]), Color(0.55, 0.72, 1.0), 12))
			top.add_child(UiKit.chip("冷却 %d 秒" % int(s["cd"]), UiKit.MIST, 12))
			var d := UiKit.label(str(s["desc"]), 14, Color(0.85, 0.88, 0.92))
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			rv.add_child(d)
			var ring_i := ri
			for k in Data.SKILL_SLOTS:
				var key: String = ["Q", "E", "F"][k]
				var on := int(Profile.skill_slots[k]) == ri
				var b := UiKit.button(key, 18, on)
				b.custom_minimum_size = Vector2(44, 44)
				b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				b.tooltip_text = "装到 %s 键" % key
				var slot_k := k
				b.pressed.connect(func():
					Profile.set_skill_slot(slot_k, ring_i)
					Sfx.play("switch", -4.0)
					open())
				rh.add_child(b)
			# 散魂丹：散掉这个灵环（点一下变成"确定？"，再点才散）
			var sb := UiKit.button("散", 16, false)
			sb.custom_minimum_size = Vector2(52, 44)
			sb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			sb.tooltip_text = "用一颗散魂丹散掉这个灵环（有 %d 颗）" % Profile.item_count("scatter_pill")
			sb.modulate = Color(1.0, 0.6, 0.55) if Profile.item_count("scatter_pill") > 0 else Color(1, 1, 1, 0.35)
			sb.pressed.connect(func():
				if Profile.item_count("scatter_pill") <= 0:
					_toast("要一颗散魂丹（暗器铺 → 道具）")
					return
				if sb.text != "确定？":
					sb.text = "确定？"
					return
				var why := Profile.remove_ring(ring_i)
				if why != "":
					_toast(why)
					return
				Sfx.play("absorb", -2.0, 0.0, 0.6)
				_toast("第%s灵环散掉了——按 L 挑一只灵兽，猎来补上这个位置" % Data.RING_NAMES[ring_i])
				var wld: Node = get_tree().get_first_node_in_group("world")
				if wld and wld.has_method("rings_changed"):
					wld.rings_changed()
				open())
			rh.add_child(sb)
		elif i == hole:
			rv.add_child(UiKit.kicker("第%s灵环 · 散掉了 · 至少%s" % [Data.RING_NAMES[i], Data.age_name(Data.RING_MIN_AGE[i])], Color(1.0, 0.6, 0.55), 12))
			rv.add_child(UiKit.label("按 L 看猎灵榜，猎一只补上这个位置（下一个吸收的灵环就是它）", 13, UiKit.MOON))
		else:
			rv.add_child(UiKit.kicker("第%s灵环 · %d 级 · 至少%s" % [Data.RING_NAMES[i], (i + 1) * 10, Data.age_name(Data.RING_MIN_AGE[i])], UiKit.DIM, 12))
			rv.add_child(UiKit.label("按 L 看猎灵榜：挑哪只灵兽就学哪个神通，年份越高越强", 13, UiKit.DIM))


func _toast(t: String) -> void:
	var wld: Node = get_tree().get_first_node_in_group("world")
	if wld:
		wld.hud.toast(t, Color(1.0, 0.8, 0.6), 3.0)


## 右边：六个部位的灵骨 + 背包里的
func _right() -> void:
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 340
	right.add_theme_constant_override("separation", 8)
	_body.add_child(right)
	right.add_child(UiKit.section("灵骨", UiKit.GOLD))
	var hint := UiKit.label("灵骨兽（金光）必掉，千年灵兽和 Boss 也会掉。按 T 能丢给队友或卖掉", 12, UiKit.MIST)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 340
	right.add_child(hint)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	right.add_child(grid)
	for slot in Data.BONE_SLOTS:
		var e := str(Profile.equipped.get(slot, ""))
		var col := UiKit.DIM
		if e != "":
			col = Data.age_color(Data.bone_age(e)) if Data.bone_age(e) > 0 else UiKit.GOLD
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(166, 82)
		card.add_theme_stylebox_override("panel", UiKit.card_style(col if e != "" else Color(0, 0, 0, 0)))
		grid.add_child(card)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		card.add_child(v)
		v.add_child(UiKit.kicker(str(Data.BONE_SLOT_NAMES[slot]), UiKit.MIST, 12))
		if e == "":
			v.add_child(UiKit.label("空", 15, UiKit.DIM))
			continue
		var n := UiKit.bold(Data.bone_name(e), 15, col)
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(n)
		var d := UiKit.label(Data.bone_desc(e), 11, Color(0.8, 0.84, 0.88))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(d)
	var spare: Array = Profile.bones.filter(func(b): return not Profile.is_equipped(str(b)))
	if spare.is_empty():
		return
	right.add_child(UiKit.section("背包里的灵骨", UiKit.MIST))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for b in spare:
		var e := str(b)
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UiKit.row_style())
		list.add_child(row)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		row.add_child(h)
		var v2 := VBoxContainer.new()
		v2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v2)
		v2.add_child(UiKit.bold("%s · %s" % [Data.bone_name(e), Data.BONE_SLOT_NAMES[Data.bone_data(e)["slot"]]], 14, UiKit.GOLD))
		var d2 := UiKit.label(Data.bone_desc(e), 12, UiKit.MIST)
		d2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v2.add_child(d2)
		var btn := UiKit.button("装上", 14, true)
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		btn.pressed.connect(func():
			Profile.equip_bone(e)
			var wn: Node = get_tree().get_first_node_in_group("world")
			if wn:
				wn.player.on_bones_changed()
			open())
		h.add_child(btn)
