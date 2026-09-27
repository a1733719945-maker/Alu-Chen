class_name ShopPanel
extends ColorRect
## 唐门暗器铺：买 / 卖暗器、买配件、升级、附魔、买道具和鱼饵、买外观（暗器皮肤、装扮）。
## 暗器卖了、丢了、送人了都能再买；升级和买过的配件记在存档里，买回来还在。
## 样子：全屏毛玻璃，上面标题 + 金魂币，下划线分页；暗器是两列卡片，用属性条比较（使命召唤改枪界面那样）。

signal closed

const TABS := [["weapons", "暗器"], ["attach", "配件"], ["upgrades", "升级"], ["enchant", "附魔"], ["items", "道具 · 鱼饵"], ["looks", "外观"]]

var world: Node
var _tab := "weapons"
var _money: Label
var _tabs_box: Control
var _list: VBoxContainer
var _scroll: ScrollContainer


func _ready() -> void:
	color = Color.WHITE
	material = UiKit.blur_material(0.7)
	UiKit.fill(self)
	var center := CenterContainer.new()
	add_child(center)
	UiKit.fill(center)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(1260, 790)
	v.add_theme_constant_override("separation", 10)
	center.add_child(v)
	var head := UiKit.panel_head("唐门", "暗器铺", "Esc", func(): closed.emit())
	v.add_child(head)
	var mr := HBoxContainer.new()
	mr.add_theme_constant_override("separation", 8)
	mr.size_flags_vertical = Control.SIZE_SHRINK_END
	mr.add_child(UiKit.icon("coin", 26, UiKit.GOLD))
	_money = UiKit.num("", 34, UiKit.GOLD, 0)
	mr.add_child(_money)
	var gap := Control.new()
	gap.custom_minimum_size.x = 18
	mr.add_child(gap)
	head.add_child(mr)
	head.move_child(mr, 1)
	_tabs_box = HBoxContainer.new()
	v.add_child(_tabs_box)
	var line := ColorRect.new()
	line.color = UiKit.LINE
	line.custom_minimum_size.y = 1
	v.add_child(line)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	_scroll.add_child(_list)


func open() -> void:
	visible = true
	Sfx.play("ui_click", -6.0)
	refresh()


func refresh() -> void:
	_money.text = "%d" % Profile.money
	for c in _tabs_box.get_children():
		c.queue_free()
	_tabs_box.add_child(UiKit.tabs(TABS, _tab, func(id: String):
		_tab = id
		_scroll.scroll_vertical = 0
		refresh()))
	for c in _list.get_children():
		c.queue_free()
	match _tab:
		"weapons":
			_weapons_tab()
		"attach":
			if Profile.loadout.is_empty():
				_list.add_child(UiKit.label("身上没有暗器。先买一把", 18, UiKit.MIST))
			for id in Profile.loadout:
				_attach_block(id)
		"enchant":
			_enchant_tab()
		"upgrades":
			if Profile.loadout.is_empty():
				_list.add_child(UiKit.label("身上没有暗器。先买一把", 18, UiKit.MIST))
			for id in Profile.loadout:
				_upgrade_block(id)
		"items":
			for id in Data.ITEMS:
				_item_row(id)
		"looks":
			_looks_tab()


func _row(accent := Color(0, 0, 0, 0)) -> HBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.row_style(accent))
	_list.add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	p.add_child(h)
	return h


func _price_button(price: int, main := true, text := "") -> Button:
	var b := UiKit.button(text if text != "" else "%d 金魂币" % price, 17, main)
	b.custom_minimum_size.x = 150
	b.disabled = Profile.money < price
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


# ------------------------------------------------------------------ 暗器：两列卡片

func _weapons_tab() -> void:
	var mx := {"dmg": 1.0, "rpm": 1.0, "mag": 1.0, "hs": 1.0}
	for id in Data.WEAPON_ORDER:
		var w: Dictionary = Data.WEAPONS[id]
		mx["dmg"] = maxf(mx["dmg"], float(w["damage"]) * int(w["pellets"]))
		mx["rpm"] = maxf(mx["rpm"], float(w["rpm"]))
		mx["mag"] = maxf(mx["mag"], float(w["mag"]))
		mx["hs"] = maxf(mx["hs"], float(w["headshot"]))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_list.add_child(grid)
	for id in Data.WEAPON_ORDER:
		grid.add_child(_weapon_card(id, mx))


func _weapon_card(id: String, mx: Dictionary) -> Control:
	var w: Dictionary = Data.WEAPONS[id]
	var have := Profile.has_weapon(id)
	var unlock := int(Data.WEAPON_UNLOCK.get(id, 1))
	var locked := not have and int(Profile.max_chapter) < unlock and int(world.chapter) < unlock
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(600, 0)
	card.add_theme_stylebox_override("panel", UiKit.card_style(UiKit.JADE if have else Color(0, 0, 0, 0)))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	card.add_child(h)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	v.add_child(top)
	top.add_child(UiKit.title(str(w["name"]), 28, UiKit.DIM if locked else UiKit.MOON))
	if have:
		top.add_child(UiKit.chip("在身上", UiKit.JADE))
		var ench := str(Profile.enchant.get(id, ""))
		if Data.ENCHANTS.has(ench):
			top.add_child(UiKit.chip(str(Data.ENCHANTS[ench]["name"]), Data.ENCHANTS[ench]["color"]))
	var d := UiKit.label(str(w["desc"]), 14, UiKit.MIST)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size.x = 380
	v.add_child(d)
	var pellets := int(w["pellets"])
	var dmg := float(w["damage"]) * pellets
	var stats := GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override("h_separation", 24)
	stats.add_theme_constant_override("v_separation", 2)
	v.add_child(stats)
	var sc := UiKit.DIM if locked else UiKit.MOON
	stats.add_child(UiKit.stat_bar("伤害", dmg / mx["dmg"], ("%d×%d" % [int(w["damage"]), pellets]) if pellets > 1 else str(int(w["damage"])), sc, 120))
	stats.add_child(UiKit.stat_bar("射速", float(w["rpm"]) / mx["rpm"], str(int(w["rpm"])), sc, 120))
	stats.add_child(UiKit.stat_bar("弹匣", float(w["mag"]) / mx["mag"], str(int(w["mag"])), sc, 120))
	stats.add_child(UiKit.stat_bar("爆头", float(w["headshot"]) / mx["hs"], "×%.1f" % float(w["headshot"]), sc, 120))
	var act := VBoxContainer.new()
	act.alignment = BoxContainer.ALIGNMENT_END
	act.add_theme_constant_override("separation", 6)
	h.add_child(act)
	if have:
		var sp := Profile.sell_price(id)
		var sb := UiKit.button("卖出  +%d" % sp, 16)
		sb.custom_minimum_size.x = 150
		sb.pressed.connect(func():
			if Profile.sell_weapon(id):
				Sfx.play("sell", -2.0)
				world.on_sold_weapon(id)
				world.hud.toast("卖掉了%s，得到 %d 金魂币（想要可以再买）" % [w["name"], sp], UiKit.GOLD)
			refresh())
		act.add_child(sb)
	elif locked:
		act.add_child(UiKit.chip("第%s章开放" % Data.RING_NAMES[unlock - 1], UiKit.DIM, 14))
	else:
		var b := _price_button(int(w["price"]), true, "%d  购买" % int(w["price"]))
		b.pressed.connect(func():
			if Profile.buy_weapon(id):
				Sfx.play("coin", -2.0)
				world.on_bought_weapon(id)
				world.hud.toast("买到了%s！按数字键切换" % w["name"], UiKit.GOLD)
			refresh())
		act.add_child(b)
	return card


# ------------------------------------------------------------------ 附魔：用魂兽王掉的王魂（一把暗器一个附魔，重新附魔会替换）

var _ench_weapon := ""


func _enchant_tab() -> void:
	_list.add_child(UiKit.section("你的王魂（打地图上的魂兽王「王」，每只必掉）", UiKit.GOLD))
	var mats := HFlowContainer.new()
	mats.add_theme_constant_override("h_separation", 8)
	mats.add_theme_constant_override("v_separation", 6)
	_list.add_child(mats)
	for sp in Profile.materials:
		if int(Profile.materials[sp]) > 0:
			mats.add_child(UiKit.chip("%s王魂  ×%d" % [Data.BEASTS[sp]["name"], int(Profile.materials[sp])], UiKit.GOLD, 15))
	if mats.get_child_count() == 0:
		mats.add_child(UiKit.label("还没有", 15, UiKit.MIST))
	if Profile.loadout.is_empty():
		_list.add_child(UiKit.label("身上没有暗器。先买一把", 18, UiKit.MIST))
		return
	if not _ench_weapon in Profile.loadout:
		_ench_weapon = str(Profile.loadout[0])
	_list.add_child(UiKit.section("给哪把暗器附魔", UiKit.MIST))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_list.add_child(row)
	for w in Profile.loadout:
		var cur := str(Profile.enchant.get(w, ""))
		var b := UiKit.button("%s%s" % [Data.WEAPONS[w]["name"], ("  · %s" % Data.ENCHANTS[cur]["name"]) if Data.ENCHANTS.has(cur) else ""], 16, w == _ench_weapon)
		var ww := str(w)
		b.pressed.connect(func(): _ench_weapon = ww; refresh())
		row.add_child(b)
	_list.add_child(UiKit.section("附魔（命中时有几率触发）", UiKit.MIST))
	for eid in Data.ENCHANT_ORDER:
		var e: Dictionary = Data.ENCHANTS[eid]
		var h := _row(e["color"])
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 3)
		h.add_child(v)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 10)
		v.add_child(top)
		top.add_child(UiKit.bold(str(e["name"]), 20, e["color"]))
		top.add_child(UiKit.label(str(e["desc"]), 15, UiKit.MOON))
		var names: Array = []
		for sp in e["mats"]:
			names.append(Data.BEASTS[sp]["name"])
		var have := Profile.enchant_mats(eid)
		var need := int(e["n"])
		var req := HBoxContainer.new()
		req.add_theme_constant_override("separation", 8)
		v.add_child(req)
		req.add_child(UiKit.chip("王魂 %d / %d" % [mini(have, need), need], UiKit.GREEN if have >= need else UiKit.RED, 12))
		req.add_child(UiKit.label("%s 王都行 · 另加 %d 金魂币" % [" / ".join(names), int(e["price"])], 13, UiKit.MIST))
		if str(Profile.enchant.get(_ench_weapon, "")) == eid:
			h.add_child(UiKit.chip("已附魔", UiKit.JADE, 15))
			continue
		var bt := _price_button(int(e["price"]), true, "附魔")
		bt.disabled = not Profile.can_enchant(eid)
		var id2 := str(eid)
		bt.pressed.connect(func():
			if Profile.do_enchant(_ench_weapon, id2):
				Sfx.play("level_up", -4.0)
				world.hud.toast("%s 附上了【%s】" % [Data.WEAPONS[_ench_weapon]["name"], Data.ENCHANTS[id2]["name"]], Data.ENCHANTS[id2]["color"])
				world.hud.on_weapon(world.player.gun)
			refresh())
		h.add_child(bt)


# ------------------------------------------------------------------ 配件：买一次永久有（卖了暗器再买回来还在）；同一个部位只能装一个

func _attach_block(id: String) -> void:
	var w: Dictionary = Data.WEAPONS[id]
	_list.add_child(UiKit.section(str(w["name"]), UiKit.GOLD))
	for a in Data.ATTACH_OK.get(id, []):
		var at: Dictionary = Data.ATTACH[a]
		var on: bool = Profile.attach_of(id, str(at["slot"])) == a
		var h := _row(UiKit.JADE if on else Color(0, 0, 0, 0))
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 3)
		h.add_child(v)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 10)
		v.add_child(top)
		top.add_child(UiKit.bold(str(at["name"]), 19, UiKit.MOON))
		var slot_name: String = {"sight": "瞄具", "muzzle": "枪口", "under": "枪管下"}.get(str(at["slot"]), "")
		top.add_child(UiKit.chip(slot_name, UiKit.MIST, 12))
		if on:
			top.add_child(UiKit.chip("装着", UiKit.JADE, 12))
		v.add_child(UiKit.label(str(at["desc"]), 14, UiKit.MIST))
		if Profile.has_attach(id, a):
			var b := UiKit.button("卸下" if on else "装上", 17, not on)
			b.custom_minimum_size.x = 150
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			b.pressed.connect(func():
				Profile.toggle_attach(id, a)
				Sfx.play("switch", -4.0)
				world.on_attach_changed()
				refresh())
			h.add_child(b)
		else:
			var price := Data.attach_price(id, a)
			var b2 := _price_button(price)
			b2.pressed.connect(func():
				if Profile.buy_attach(id, a):
					Sfx.play("coin", -2.0)
					world.on_attach_changed()
					world.hud.toast("装上了%s" % at["name"], UiKit.GOLD)
				refresh())
			h.add_child(b2)


func _upgrade_block(id: String) -> void:
	var w: Dictionary = Data.WEAPONS[id]
	_list.add_child(UiKit.section(str(w["name"]), UiKit.GOLD))
	for key in Data.UPGRADES:
		var u: Dictionary = Data.UPGRADES[key]
		var lv := Profile.upgrade_level(id, key)
		var mx := Data.UPGRADE_COST.size()
		var h := _row()
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 5)
		h.add_child(v)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 14)
		v.add_child(top)
		var nl := UiKit.bold(str(u["name"]), 19, UiKit.MOON)
		nl.custom_minimum_size.x = 120
		top.add_child(nl)
		# 等级格子
		var pips := HBoxContainer.new()
		pips.add_theme_constant_override("separation", 4)
		pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(pips)
		for i in mx:
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(26, 6)
			pip.color = UiKit.GOLD if i < lv else Color(1, 1, 1, 0.14)
			pips.add_child(pip)
		top.add_child(UiKit.num("%d / %d" % [lv, mx], 17, UiKit.GOLD if lv > 0 else UiKit.MIST, 0))
		v.add_child(UiKit.label("每级 %s" % u["desc"], 14, UiKit.MIST))
		if lv >= mx:
			h.add_child(UiKit.chip("已满级", UiKit.JADE, 15))
		else:
			var price := Data.upgrade_price(id, lv)
			var b := _price_button(price)
			b.pressed.connect(func():
				if Profile.buy_upgrade(id, key):
					Sfx.play("coin", -2.0)
					world.on_upgraded(id)
				refresh())
			h.add_child(b)


# ------------------------------------------------------------------ 外观：三列卡片，大色块预览

func _looks_tab() -> void:
	_list.add_child(UiKit.section("暗器皮肤（所有暗器通用，队友也看得到）", UiKit.JADE))
	var g1 := GridContainer.new()
	g1.columns = 3
	g1.add_theme_constant_override("h_separation", 10)
	g1.add_theme_constant_override("v_separation", 10)
	_list.add_child(g1)
	for id in Data.GUN_SKIN_ORDER:
		g1.add_child(_look_card("skin", id))
	_list.add_child(UiKit.section("装扮（长袍和帽子，第一人称能看到袖子）", UiKit.JADE))
	var g2 := GridContainer.new()
	g2.columns = 3
	g2.add_theme_constant_override("h_separation", 10)
	g2.add_theme_constant_override("v_separation", 10)
	_list.add_child(g2)
	for id in Data.OUTFIT_ORDER:
		g2.add_child(_look_card("outfit", id))


func _look_card(kind: String, id: String) -> Control:
	var d: Dictionary = (Data.GUN_SKINS if kind == "skin" else Data.OUTFITS)[id]
	var worn := (Profile.skin if kind == "skin" else Profile.outfit) == id
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(406, 0)
	card.add_theme_stylebox_override("panel", UiKit.card_style(UiKit.GOLD if worn else Color(0, 0, 0, 0)))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	card.add_child(h)
	var sw := ColorRect.new()
	sw.custom_minimum_size = Vector2(56, 56)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pal: Dictionary = d.get("pal", {})
	sw.color = (pal.get("lacquer", Color(0.32, 0.05, 0.05)) as Color) if kind == "skin" else (d["robe"] as Color)
	h.add_child(sw)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	h.add_child(v)
	v.add_child(UiKit.bold(str(d["name"]), 18, UiKit.MOON))
	var ds := UiKit.label(str(d.get("desc", "")), 13, UiKit.MIST)
	ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ds.custom_minimum_size.x = 200
	v.add_child(ds)
	var act := HBoxContainer.new()
	v.add_child(act)
	if worn:
		act.add_child(UiKit.chip("穿着", UiKit.GOLD, 13))
	elif Profile.owns_look(kind, id):
		var b := UiKit.button("换上", 15, true)
		b.pressed.connect(func():
			Profile.wear(kind, id)
			Sfx.play("switch", -4.0)
			world.on_look_changed()
			refresh())
		act.add_child(b)
	elif d.has("boss"):
		act.add_child(UiKit.chip("打 Boss 解锁", UiKit.DIM, 13))
	elif d.has("codex"):
		act.add_child(UiKit.chip("集齐猎魂录解锁", UiKit.DIM, 13))
	else:
		var b2 := UiKit.button("%d 金魂币" % int(d["price"]), 15, true)
		b2.disabled = Profile.money < int(d["price"])
		b2.pressed.connect(func():
			if Profile.buy_look(kind, id):
				Profile.wear(kind, id)
				Sfx.play("coin", -2.0)
				world.on_look_changed()
				world.hud.toast("买到了【%s】，已经换上" % d["name"], UiKit.GOLD)
			refresh())
		act.add_child(b2)
	return card


# ------------------------------------------------------------------ 道具、鱼饵

func _item_row(id: String) -> void:
	var it: Dictionary = Data.ITEMS[id]
	var h := _row()
	h.add_child(UiKit.keycap(str(it["key"]), 15))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 3)
	h.add_child(v)
	var have := Profile.item_count("gold_bites") if id == "lure_gold" else Profile.item_count(id)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	v.add_child(top)
	top.add_child(UiKit.bold(str(it["name"]), 19, UiKit.MOON))
	top.add_child(UiKit.chip("已有 %d" % have, UiKit.JADE if have > 0 else UiKit.DIM, 12))
	var d := UiKit.label(str(it["desc"]), 14, UiKit.MIST)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	var need_ch := int(it.get("ch", 1))
	if maxi(int(Profile.max_chapter), int(world.chapter)) < need_ch:
		h.add_child(UiKit.chip("第%s章开放" % Data.RING_NAMES[need_ch - 1], UiKit.DIM, 14))
		return
	var price := Data.item_price(id)
	var b := _price_button(price)
	b.pressed.connect(func():
		if Profile.buy_item(id):
			Sfx.play("coin", -2.0)
		else:
			world.hud.toast("带不了更多了", Color(1, 0.8, 0.6))
		refresh())
	h.add_child(b)
