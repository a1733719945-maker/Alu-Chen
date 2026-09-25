class_name WuhunPanel
extends ColorRect
## 武魂面板（K）：武魂、等级、魂环和魂技、下一个魂环能选什么、魂骨、属性。

signal closed

var _body: HBoxContainer


func _ready() -> void:
	color = Color(0, 0, 0, 0.6)
	UiKit.fill(self)
	var center := CenterContainer.new()
	add_child(center)
	UiKit.fill(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.panel_style())
	panel.custom_minimum_size = Vector2(1100, 640)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UiKit.title("武魂 · 魂环", 44)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := UiKit.button("关闭（K / Esc）", 18)
	close.pressed.connect(func(): closed.emit())
	head.add_child(close)
	_body = HBoxContainer.new()
	_body.add_theme_constant_override("separation", 24)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_body)


func open() -> void:
	visible = true
	for c in _body.get_children():
		c.queue_free()
	var wi := Settings.wuhun
	var w: Dictionary = Data.WUHUN[wi]
	# 左：武魂
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 280
	_body.add_child(left)
	var pic := TextureRect.new()
	pic.texture = load(w["img"])
	pic.custom_minimum_size = Vector2(260, 260)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	left.add_child(pic)
	left.add_child(UiKit.title(str(w["name"]), 40, Data.wuhun_color(wi)))
	left.add_child(UiKit.label(str(w["kind"]), 18, UiKit.MIST))
	left.add_child(UiKit.label(Profile.title(), 24, UiKit.GOLD))
	left.add_child(UiKit.label("修为 %d / %d" % [Profile.xp, Data.xp_to_next(Profile.level)], 17))
	left.add_child(UiKit.label("体力 %d · 魂力 %d" % [int(Profile.max_hp()), int(Profile.max_soul())], 17))
	if Profile.at_bottleneck():
		var b := UiKit.label("瓶颈！吸收第%d魂环才能继续升级" % (Profile.rings.size() + 1), 17, Color(1, 0.8, 0.4))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		left.add_child(b)
	# 中：魂环与魂技树
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 10)
	_body.add_child(mid)
	mid.add_child(UiKit.label("魂环与魂技（这一版开放前三环，后续章节解锁更多）", 18, UiKit.JADE))
	var tree: Array = Data.SKILL_TREE[w["id"]]
	for i in tree.size():
		var row := PanelContainer.new()
		var have := i < Profile.rings.size()
		var st := UiKit.row_style(Data.age_color(int(Profile.rings[i]["age"])) if have else Color(1, 1, 1, 0.15))
		row.add_theme_stylebox_override("panel", st)
		mid.add_child(row)
		var rv := VBoxContainer.new()
		row.add_child(rv)
		var head := "第%s魂环" % Data.RING_NAMES[i]
		if have:
			var r: Dictionary = Profile.rings[i]
			var s: Dictionary = Data.SKILLS[r["skill"]]
			rv.add_child(UiKit.label("%s · %s魂环（%s）" % [head, Data.age_name(int(r["age"])), Data.BEASTS.get(r["beast"], {"name": "?"})["name"]], 17, Data.age_color(int(r["age"]))))
			rv.add_child(UiKit.title(str(s["name"]), 30, UiKit.GOLD))
			var d := UiKit.label("%s   （魂力 %d · 冷却 %d 秒）" % [s["desc"], int(s["cost"]), int(s["cd"])], 16)
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			rv.add_child(d)
		else:
			rv.add_child(UiKit.label("%s · %d 级后吸收，至少%s" % [head, (i + 1) * 10, Data.age_name(Data.RING_MIN_AGE[i])], 17, UiKit.MIST))
			for sid in tree[i]:
				var s: Dictionary = Data.SKILLS[sid]
				var d := UiKit.label("可选【%s】%s" % [s["name"], s["desc"]], 16, UiKit.MOON)
				d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				rv.add_child(d)
	# 右：魂骨（六个部位，点"装上"换）
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 330
	right.add_theme_constant_override("separation", 3)
	_body.add_child(right)
	right.add_child(UiKit.label("魂骨 · 六个部位各装一块", 18, UiKit.JADE))
	var hint := UiKit.label("魂骨兽（金光）必掉，千年魂兽和 Boss 也会掉。地上的魂骨谁都能捡，按 T 能丢给队友或卖掉", 13, UiKit.MIST)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(hint)
	for slot in Data.BONE_SLOTS:
		var row := HBoxContainer.new()
		right.add_child(row)
		row.add_child(UiKit.bold(str(Data.BONE_SLOT_NAMES[slot]), 15, UiKit.MOON))
		var e := str(Profile.equipped.get(slot, ""))
		if e == "":
			row.add_child(UiKit.label("  空", 15, UiKit.MIST))
			continue
		var l := UiKit.label("  %s" % Data.bone_name(e), 15, Data.age_color(Data.bone_age(e)) if Data.bone_age(e) > 0 else UiKit.GOLD)
		row.add_child(l)
		var d := UiKit.label("      " + Data.bone_desc(e), 13, Color(0.85, 0.9, 0.8))
		right.add_child(d)
	var spare: Array = Profile.bones.filter(func(b): return not Profile.is_equipped(str(b)))
	if not spare.is_empty():
		right.add_child(UiKit.label("背包里的魂骨", 16, UiKit.JADE))
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(320, 190)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		right.add_child(scroll)
		var list := VBoxContainer.new()
		scroll.add_child(list)
		for b in spare:
			var e := str(b)
			var row := HBoxContainer.new()
			list.add_child(row)
			var btn := UiKit.button("装上", 13)
			btn.pressed.connect(func():
				Profile.equip_bone(e)
				var wn: Node = get_tree().get_first_node_in_group("world")
				if wn:
					wn.player.on_bones_changed()
				open())
			row.add_child(btn)
			var v2 := VBoxContainer.new()
			row.add_child(v2)
			v2.add_child(UiKit.label("%s（%s）" % [Data.bone_name(e), Data.BONE_SLOT_NAMES[Data.bone_data(e)["slot"]]], 14, UiKit.GOLD))
			v2.add_child(UiKit.label(Data.bone_desc(e), 12))
