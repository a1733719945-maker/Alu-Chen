class_name ShopPanel
extends ColorRect
## 唐门暗器铺：买暗器、升级、买道具。

signal closed

var world: Node
var _tab := "weapons"
var _money: Label
var _list: VBoxContainer
var _tabs := {}


func _ready() -> void:
	color = Color(0, 0, 0, 0.55)
	UiKit.fill(self)
	var center := CenterContainer.new()
	add_child(center)
	UiKit.fill(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.panel_style())
	panel.custom_minimum_size = Vector2(980, 660)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := UiKit.title("唐门 · 暗器铺", 44, UiKit.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_money = UiKit.label("", 26, UiKit.GOLD)
	head.add_child(_money)
	var close := UiKit.button("关闭（Esc）", 18)
	close.pressed.connect(func(): closed.emit())
	head.add_child(close)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	v.add_child(tabs)
	for t in [["weapons", "暗器"], ["upgrades", "升级"], ["items", "道具"]]:
		var b := UiKit.button(t[1], 20)
		b.custom_minimum_size.x = 130
		b.pressed.connect(func(): _tab = t[0]; refresh())
		tabs.add_child(b)
		_tabs[t[0]] = b
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)


func open() -> void:
	visible = true
	Sfx.play("ui_click", -6.0)
	refresh()


func refresh() -> void:
	_money.text = "金魂币 %d    " % Profile.money
	for k in _tabs:
		_tabs[k].add_theme_color_override("font_color", UiKit.GOLD if k == _tab else UiKit.MOON)
	for c in _list.get_children():
		c.queue_free()
	match _tab:
		"weapons":
			for id in Data.WEAPON_ORDER:
				_weapon_row(id)
		"upgrades":
			for id in Profile.loadout:
				_upgrade_block(id)
		"items":
			for id in Data.ITEMS:
				_item_row(id)


func _row() -> HBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.row_style())
	_list.add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	p.add_child(h)
	return h


func _weapon_row(id: String) -> void:
	var w: Dictionary = Data.WEAPONS[id]
	var h := _row()
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var t := HBoxContainer.new()
	t.add_child(UiKit.title(str(w["name"]), 30, UiKit.MOON))
	t.add_child(UiKit.label("  " + str(w["cat"]), 17, UiKit.JADE))
	v.add_child(t)
	var d := UiKit.label(str(w["desc"]), 16, UiKit.MIST)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	var pellets := int(w["pellets"])
	var dmg := ("%d×%d" % [int(w["damage"]), pellets]) if pellets > 1 else str(int(w["damage"]))
	v.add_child(UiKit.label("伤害 %s · 射速 %d/分 · 弹匣 %d · 爆头 ×%.1f" % [dmg, int(w["rpm"]), int(w["mag"]), float(w["headshot"])], 15, UiKit.MOON))
	if Profile.has_weapon(id):
		h.add_child(UiKit.label("已拥有", 20, UiKit.JADE))
	else:
		var b := UiKit.button("%d 金魂币 购买" % int(w["price"]), 20, true)
		b.disabled = Profile.money < int(w["price"])
		b.pressed.connect(func():
			if Profile.buy_weapon(id):
				Sfx.play("coin", -2.0)
				world.on_bought_weapon(id)
				world.hud.toast("买到了%s！按数字键切换" % w["name"], UiKit.GOLD)
			refresh())
		h.add_child(b)


func _upgrade_block(id: String) -> void:
	var w: Dictionary = Data.WEAPONS[id]
	var title := UiKit.title(str(w["name"]), 30, UiKit.GOLD)
	_list.add_child(title)
	for key in Data.UPGRADES:
		var u: Dictionary = Data.UPGRADES[key]
		var lv := Profile.upgrade_level(id, key)
		var h := _row()
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		var dots := ""
		for i in Data.UPGRADE_COST.size():
			dots += "●" if i < lv else "○"
		v.add_child(UiKit.label("%s  %s" % [u["name"], dots], 20, UiKit.MOON))
		v.add_child(UiKit.label("每级 %s" % u["desc"], 15, UiKit.MIST))
		if lv >= Data.UPGRADE_COST.size():
			h.add_child(UiKit.label("已满级", 18, UiKit.JADE))
		else:
			var price := Data.upgrade_price(id, lv)
			var b := UiKit.button("%d 金魂币" % price, 18, true)
			b.disabled = Profile.money < price
			b.pressed.connect(func():
				if Profile.buy_upgrade(id, key):
					Sfx.play("coin", -2.0)
					world.on_upgraded(id)
				refresh())
			h.add_child(b)


func _item_row(id: String) -> void:
	var it: Dictionary = Data.ITEMS[id]
	var h := _row()
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var have := Profile.item_count("gold_bites") if id == "lure_gold" else Profile.item_count(id)
	v.add_child(UiKit.label("%s   （按键 %s）  已有 %d" % [it["name"], it["key"], have], 20, UiKit.MOON))
	var d := UiKit.label(str(it["desc"]), 15, UiKit.MIST)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	var b := UiKit.button("%d 金魂币" % int(it["price"]), 18, true)
	b.disabled = Profile.money < int(it["price"])
	b.pressed.connect(func():
		if Profile.buy_item(id):
			Sfx.play("coin", -2.0)
		else:
			world.hud.toast("带不了更多了", Color(1, 0.8, 0.6))
		refresh())
	h.add_child(b)
