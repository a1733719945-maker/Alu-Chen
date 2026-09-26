class_name ShopPanel
extends ColorRect
## 唐门暗器铺：买 / 卖暗器、买配件、升级、买道具和鱼饵、买外观（暗器皮肤、装扮）。
## 暗器卖了、丢了、送人了都能再买；升级和买过的配件记在存档里，买回来还在。

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
	for t in [["weapons", "暗器"], ["attach", "配件"], ["upgrades", "升级"], ["items", "道具 · 鱼饵"], ["looks", "外观"]]:
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
		"attach":
			if Profile.loadout.is_empty():
				_list.add_child(UiKit.label("身上没有暗器。先买一把", 18, UiKit.MIST))
			for id in Profile.loadout:
				_attach_block(id)
		"upgrades":
			if Profile.loadout.is_empty():
				_list.add_child(UiKit.label("身上没有暗器。先买一把", 18, UiKit.MIST))
			for id in Profile.loadout:
				_upgrade_block(id)
		"items":
			for id in Data.ITEMS:
				_item_row(id)
		"looks":
			_list.add_child(UiKit.bold("暗器皮肤（所有暗器通用，队友也看得到）", 20, UiKit.JADE))
			for id in Data.GUN_SKIN_ORDER:
				_look_row("skin", id)
			_list.add_child(UiKit.bold("装扮（长袍和帽子，第一人称能看到袖子）", 20, UiKit.JADE))
			for id in Data.OUTFIT_ORDER:
				_look_row("outfit", id)


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
	v.add_child(t)
	var d := UiKit.label(str(w["desc"]), 16, UiKit.MIST)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	var pellets := int(w["pellets"])
	var dmg := ("%d×%d" % [int(w["damage"]), pellets]) if pellets > 1 else str(int(w["damage"]))
	v.add_child(UiKit.label("伤害 %s · 射速 %d/分 · 弹匣 %d · 爆头 ×%.1f" % [dmg, int(w["rpm"]), int(w["mag"]), float(w["headshot"])], 15, UiKit.MOON))
	var unlock := int(Data.WEAPON_UNLOCK.get(id, 1))
	if Profile.has_weapon(id):
		var sp := Profile.sell_price(id)
		var sb := UiKit.button("卖出 +%d" % sp, 18)
		sb.pressed.connect(func():
			if Profile.sell_weapon(id):
				Sfx.play("sell", -2.0)
				world.on_sold_weapon(id)
				world.hud.toast("卖掉了%s，得到 %d 金魂币（想要可以再买）" % [w["name"], sp], UiKit.GOLD)
			refresh())
		h.add_child(UiKit.label("在身上", 18, UiKit.JADE))
		h.add_child(sb)
	elif int(Profile.max_chapter) < unlock and int(world.chapter) < unlock:
		h.add_child(UiKit.label("第%s章开放" % Data.RING_NAMES[unlock - 1], 18, UiKit.MIST))
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


## 配件：每把暗器能装的配件，买一次永久有（卖了暗器再买回来还在）；同一个部位只能装一个
func _attach_block(id: String) -> void:
	var w: Dictionary = Data.WEAPONS[id]
	_list.add_child(UiKit.title(str(w["name"]), 30, UiKit.GOLD))
	for a in Data.ATTACH_OK.get(id, []):
		var at: Dictionary = Data.ATTACH[a]
		var h := _row()
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		var slot_name: String = {"sight": "瞄具", "muzzle": "枪口", "under": "枪管下"}.get(str(at["slot"]), "")
		v.add_child(UiKit.label("%s   · %s" % [at["name"], slot_name], 20, UiKit.MOON))
		v.add_child(UiKit.label(str(at["desc"]), 15, UiKit.MIST))
		var on: bool = Profile.attach_of(id, str(at["slot"])) == a
		if Profile.has_attach(id, a):
			var b := UiKit.button("卸下" if on else "装上", 18, not on)
			b.pressed.connect(func():
				Profile.toggle_attach(id, a)
				Sfx.play("switch", -4.0)
				world.on_attach_changed()
				refresh())
			if on:
				h.add_child(UiKit.label("装着", 18, UiKit.JADE))
			h.add_child(b)
		else:
			var price := Data.attach_price(id, a)
			var b2 := UiKit.button("%d 金魂币" % price, 18, true)
			b2.disabled = Profile.money < price
			b2.pressed.connect(func():
				if Profile.buy_attach(id, a):
					Sfx.play("coin", -2.0)
					world.on_attach_changed()
					world.hud.toast("装上了%s" % at["name"], UiKit.GOLD)
				refresh())
			h.add_child(b2)

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


func _look_row(kind: String, id: String) -> void:
	var d: Dictionary = (Data.GUN_SKINS if kind == "skin" else Data.OUTFITS)[id]
	var h := _row()
	# 色块预览
	var sw := ColorRect.new()
	sw.custom_minimum_size = Vector2(46, 46)
	var pal: Dictionary = d.get("pal", {})
	sw.color = (pal.get("lacquer", Color(0.32, 0.05, 0.05)) as Color) if kind == "skin" else (d["robe"] as Color)
	h.add_child(sw)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(UiKit.label(str(d["name"]), 20, UiKit.MOON))
	v.add_child(UiKit.label(str(d.get("desc", "")), 15, UiKit.MIST))
	var worn := (Profile.skin if kind == "skin" else Profile.outfit) == id
	if worn:
		h.add_child(UiKit.label("穿着", 18, UiKit.JADE))
	elif Profile.owns_look(kind, id):
		var b := UiKit.button("换上", 18, true)
		b.pressed.connect(func():
			Profile.wear(kind, id)
			Sfx.play("switch", -4.0)
			world.on_look_changed()
			refresh())
		h.add_child(b)
	elif d.has("boss"):
		h.add_child(UiKit.label("打 Boss 解锁", 16, UiKit.MIST))
	elif d.has("codex"):
		h.add_child(UiKit.label("集齐猎魂录解锁", 16, UiKit.MIST))
	else:
		var b2 := UiKit.button("%d 金魂币" % int(d["price"]), 18, true)
		b2.disabled = Profile.money < int(d["price"])
		b2.pressed.connect(func():
			if Profile.buy_look(kind, id):
				Profile.wear(kind, id)
				Sfx.play("coin", -2.0)
				world.on_look_changed()
				world.hud.toast("买到了【%s】，已经换上" % d["name"], UiKit.GOLD)
			refresh())
		h.add_child(b2)


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
	var need_ch := int(it.get("ch", 1))
	if maxi(int(Profile.max_chapter), int(world.chapter)) < need_ch:
		h.add_child(UiKit.label("第%s章开放" % Data.RING_NAMES[need_ch - 1], 18, UiKit.MIST))
		return
	var price := Data.item_price(id)
	var b := UiKit.button("%d 金魂币" % price, 18, true)
	b.disabled = Profile.money < price
	b.pressed.connect(func():
		if Profile.buy_item(id):
			Sfx.play("coin", -2.0)
		else:
			world.hud.toast("带不了更多了", Color(1, 0.8, 0.6))
		refresh())
	h.add_child(b)
