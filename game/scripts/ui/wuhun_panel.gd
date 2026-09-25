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
		var head := "第%s魂环（%s）" % [Data.RING_NAMES[i], Data.SKILL_KEYS[i]]
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
	# 右：魂骨
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 250
	_body.add_child(right)
	right.add_child(UiKit.label("魂骨（打 Boss 掉落）", 18, UiKit.JADE))
	if Profile.bones.is_empty():
		right.add_child(UiKit.label("还没有", 16, UiKit.MIST))
	for bid in Profile.bones:
		var b: Dictionary = Data.BONES[bid]
		right.add_child(UiKit.label(str(b["name"]), 20, UiKit.GOLD))
		right.add_child(UiKit.label(str(b["desc"]), 15))
