class_name ShopPanel
extends ColorRect
## 千机阁暗器铺：买 / 卖暗器、买配件、升级、附魔、买道具和鱼饵、买外观（暗器皮肤、装扮）。
## 暗器卖了、丢了、送人了都能再买；升级和买过的配件记在存档里，买回来还在。
## 样子：全屏毛玻璃，上面标题 + 灵石，下划线分页；暗器是两列卡片，用属性条比较（使命召唤改枪界面那样）。

signal closed

const TABS := [["weapons", "暗器"], ["attach", "配件"], ["upgrades", "升级"], ["stars", "升星"], ["forge", "锻造"], ["pets", "灵宠"], ["enchant", "附魔"], ["items", "道具 · 鱼饵"], ["looks", "外观"], ["decor", "装饰"]]

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
	var head := UiKit.panel_head("千机阁", "暗器铺", "Esc", func(): closed.emit())
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
	# 3D 预览留着重用（每次刷新都重建会闪一下）
	if _preview and _preview.get_parent():
		_preview.get_parent().remove_child(_preview)
	for c in _list.get_children():
		c.queue_free()
	match _tab:
		"weapons":
			_weapons_tab()
		"attach":
			if Profile.loadout.is_empty():
				_list.add_child(UiKit.label("身上没有暗器。先买一把", 18, UiKit.MIST))
			else:
				_weapon_picker()
				_attach_block(_pick_weapon)
		"enchant":
			_enchant_tab()
		"stars":
			_stars_tab()
		"forge":
			_forge_tab()
		"pets":
			_pets_tab()
		"upgrades":
			if Profile.loadout.is_empty():
				_list.add_child(UiKit.label("身上没有暗器。先买一把", 18, UiKit.MIST))
			for id in Profile.loadout:
				_upgrade_block(id)
		"items":
			for id in Data.ITEMS:
				if not bool(Data.ITEMS[id].get("hidden", false)):
					_item_row(id)
		"looks":
			_looks_tab()
		"decor":
			_decor_tab()


func _row(accent := Color(0, 0, 0, 0)) -> HBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.row_style(accent))
	_list.add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	p.add_child(h)
	return h


func _price_button(price: int, main := true, text := "") -> Button:
	var b := UiKit.button(text if text != "" else "%d 灵石" % price, 17, main)
	b.custom_minimum_size.x = 150
	b.disabled = Profile.money < price
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


# ------------------------------------------------------------------ 暗器：两列卡片

func _weapons_tab() -> void:
	var mx := {"dmg": 1.0, "rpm": 1.0, "mag": 1.0, "hs": 1.0}
	for id in Data.WEAPON_ORDER:
		# 按这一章的档次拉平过的数值（Data.weapon_stats 第三个参数；暗器各有打法，没有最强）
		var w: Dictionary = Data.weapon_stats(id, {}, Profile.chapter)
		# 伤害条按一发算（天心泪按半蓄，不然别的暗器全是短条）
		mx["dmg"] = maxf(mx["dmg"], float(w["damage"]) * int(w["pellets"]) * (float(w.get("charge_k", 1.0)) * 0.5 if w["mode"] == "charge" else 1.0))
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
	var w: Dictionary = Data.weapon_stats(id, {}, Profile.chapter)
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
	var mode_name := str(Data.MODE_NAME.get(str(w["mode"]), ""))
	if w.has("splash"):
		mode_name = "爆炸"
	elif w.has("spinup"):
		mode_name = "越打越快"
	if mode_name != "":
		top.add_child(UiKit.chip(mode_name, UiKit.MIST, 12))
	if GunArts.NAME.has(id):
		top.add_child(UiKit.chip(str(GunArts.NAME[id]), UiKit.GOLD, 12))
	if have:
		top.add_child(UiKit.chip("在身上", UiKit.JADE))
		var ench := str(Profile.enchant.get(id, ""))
		if Data.ENCHANTS.has(ench):
			top.add_child(UiKit.chip(str(Data.ENCHANTS[ench]["name"]), Data.ENCHANTS[ench]["color"]))
	var d := UiKit.label(str(w["desc"]), 14, UiKit.MIST)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size.x = 380
	v.add_child(d)
	# 熟练度（买过、用过的才有）
	var mxp := Profile.mastery_xp(id)
	if have or mxp > 0:
		var ml := Profile.mastery_level(id)
		var mrow := HBoxContainer.new()
		mrow.add_theme_constant_override("separation", 10)
		v.add_child(mrow)
		mrow.add_child(UiKit.label("熟练度", 14, UiKit.MIST))
		mrow.add_child(UiKit.num("%d" % ml, 18, UiKit.GOLD if ml > 0 else UiKit.MIST, 0))
		var mb := UiKit.bar(UiKit.GOLD, 150, 5)
		mb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if ml >= Data.MASTERY_MAX:
			mb.value = 1.0
		else:
			var lo := int(Data.MASTERY_XP[ml])
			mb.value = float(mxp - lo) / float(int(Data.MASTERY_XP[ml + 1]) - lo)
		mrow.add_child(mb)
		var nxt: Dictionary = Data.MASTERY_PERKS.get(ml + 1, {})
		if not nxt.is_empty():
			mrow.add_child(UiKit.label("下一级：%s" % nxt["text"], 13, UiKit.DIM))
	var pellets := int(w["pellets"])
	var dmg := float(w["damage"]) * pellets
	var stats := GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override("h_separation", 24)
	stats.add_theme_constant_override("v_separation", 2)
	v.add_child(stats)
	var sc := UiKit.DIM if locked else UiKit.MOON
	var dtext := ("%d×%d" % [int(w["damage"]), pellets]) if pellets > 1 else str(int(w["damage"]))
	match str(w["mode"]):
		"burst":
			dtext = "%d×%d" % [int(w["damage"]), int(w["burst"])]
			dmg *= float(w["burst"])
		"charge":
			dtext = "%d~%d" % [int(w["damage"]), int(float(w["damage"]) * float(w["charge_k"]))]
			dmg *= float(w["charge_k"]) * 0.5
	if w.has("splash_dmg"):
		dtext = "%d+%d" % [int(w["damage"]), int(w["splash_dmg"])]
		dmg += float(w["splash_dmg"])
	stats.add_child(UiKit.stat_bar("伤害", minf(dmg / mx["dmg"], 1.0), dtext, sc, 120))
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
				world.hud.toast("卖掉了%s，得到 %d 灵石（想要可以再买）" % [w["name"], sp], UiKit.GOLD)
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


# ------------------------------------------------------------------ 附魔：用灵兽王掉的王魄（一把暗器一个附魔，重新附魔会替换）

var _ench_weapon := ""


# ------------------------------------------------------------------ 升星：赌一把（Profile.star_try）

var _star_ward := false
var _star_busy := false
var _star_labels: Array = []
var _star_roll: Label
var _star_msg: Label
var _star_card: Control


func _stars_tab() -> void:
	if Profile.loadout.is_empty():
		_list.add_child(UiKit.label("身上没有暗器。先买一把", 18, UiKit.MIST))
		return
	_list.add_child(UiKit.section("升星：一颗比一颗难；失败攒祝福（下次 +5%）；3 / 6 / 9 星突破，突破过的不会掉回去", UiKit.GOLD))
	_weapon_picker()
	var id := _pick_weapon
	var s := Profile.star_of(id)
	var col := Data.star_color(s) if s >= 3 else UiKit.GOLD
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.card_style(col))
	_list.add_child(card)
	_star_card = card
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	v.add_child(top)
	top.add_child(UiKit.title(str(Data.WEAPONS[id]["name"]), 34, Color.WHITE))
	var brk := ""
	for b in Data.STAR_BREAK:
		if s >= int(b):
			brk = str(Data.STAR_BREAK[b][1])
	if brk != "":
		top.add_child(UiKit.chip("突破 · " + brk, col, 15, true))
	# 十颗星
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	_star_labels.clear()
	for i in Data.STAR_MAX:
		var lit := i < s
		var c: Color = (Data.star_color(i + 1) if i + 1 >= 3 else UiKit.GOLD) if lit else Color(1, 1, 1, 0.16)
		var l := UiKit.bold("★", 46, c, 3)
		l.pivot_offset = Vector2(20, 28)
		row.add_child(l)
		_star_labels.append(l)
		if Data.STAR_BREAK.has(i + 1) and i + 1 < Data.STAR_MAX:
			var sep := ColorRect.new()
			sep.color = Color(1, 1, 1, 0.12)
			sep.custom_minimum_size = Vector2(2, 40)
			row.add_child(sep)
	_star_roll = UiKit.num("", 26, UiKit.MOON, 3)
	row.add_child(_star_roll)
	v.add_child(UiKit.label("伤害 ×%.2f%s" % [Data.star_mult(s), ("  →  下一颗 ×%.2f" % Data.star_mult(s + 1)) if s < Data.STAR_MAX else ""], 18, UiKit.MOON))
	_star_msg = UiKit.bold("", 24, UiKit.GOLD, 3)
	v.add_child(_star_msg)
	if s >= Data.STAR_MAX:
		_star_msg.text = "满星 · 金身"
		return
	var inf := Profile.star_try_info(id, _star_ward)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 8)
	v.add_child(chips)
	var bless := float(Profile.star_bless.get(id, 0.0))
	chips.add_child(UiKit.chip("成功率 %d%%%s" % [roundi(float(inf["rate"]) * 100.0), ("（祝福 +%d%%）" % roundi(bless * 100.0)) if bless > 0.0 else ""], UiKit.GREEN if float(inf["rate"]) >= 0.6 else (UiKit.GOLD if float(inf["rate"]) >= 0.4 else UiKit.RED), 15))
	chips.add_child(UiKit.chip("%d 灵石" % int(inf["price"]), UiKit.GOLD, 15))
	if int(inf["mats"]) > 0:
		chips.add_child(UiKit.chip("突破要王魄 %d / %d" % [mini(Profile.all_mats(), int(inf["mats"])), int(inf["mats"])], UiKit.GREEN if Profile.all_mats() >= int(inf["mats"]) else UiKit.RED, 15))
	if bool(inf["can_drop"]):
		chips.add_child(UiKit.chip("失败一半几率掉一颗（最低 ★%d）" % Data.star_floor(s), UiKit.RED, 15))
	var act := HBoxContainer.new()
	act.add_theme_constant_override("separation", 14)
	v.add_child(act)
	if bool(inf["can_drop"]):
		var ward := CheckBox.new()
		ward.text = "贴护星符（失败不掉星，多花 %d%%）" % roundi(Data.STAR_WARD_K * 100.0)
		ward.button_pressed = _star_ward
		ward.toggled.connect(func(on: bool):
			_star_ward = on
			refresh())
		act.add_child(ward)
	var go := UiKit.button("升星", 22, true)
	go.custom_minimum_size = Vector2(200, 52)
	go.disabled = not Profile.can_star(id, _star_ward) or _star_busy
	go.pressed.connect(func(): _do_star(id))
	act.add_child(go)


## 按下升星：星星闪一阵（越来越慢，像开奖），再揭晓
func _do_star(id: String) -> void:
	if _star_busy:
		return
	var res := Profile.star_try(id, _star_ward)
	if res.is_empty():
		return
	_star_busy = true
	_money.text = "%d" % Profile.money
	var target: Label = _star_labels[mini(int(res["from"]), _star_labels.size() - 1)]
	var tw := create_tween()
	var gaps := [0.05, 0.05, 0.05, 0.06, 0.06, 0.07, 0.08, 0.09, 0.1, 0.12, 0.14, 0.17, 0.2, 0.25]
	for i in gaps.size():
		tw.tween_callback(func():
			if not is_instance_valid(target):
				return
			target.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7) if i % 2 == 0 else Color(1, 1, 1, 0.25))
			_star_roll.text = "%d%%" % randi_range(1, 99)
			Sfx.play("ui_click", -6.0, 0.0, 0.8 + i * 0.06))
		tw.tween_interval(float(gaps[i]))
	tw.tween_callback(func(): _star_reveal(id, res))
	tw.tween_interval(1.4)
	tw.tween_callback(func():
		_star_busy = false
		world.on_upgraded(id)
		world.player.viewmodel.apply_look()
		world.hud.on_weapon(world.player.gun)
		refresh())


func _star_reveal(id: String, res: Dictionary) -> void:
	if not is_instance_valid(_star_msg):
		return
	var from := int(res["from"])
	var to := int(res["to"])
	_star_roll.text = "%d%%" % roundi(float(res["rate"]) * 100.0)
	var target: Label = _star_labels[mini(from, _star_labels.size() - 1)]
	if bool(res["ok"]):
		var c: Color = Data.star_color(to) if to >= 3 else UiKit.GOLD
		target.add_theme_color_override("font_color", c)
		target.scale = Vector2.ONE * 1.9
		target.create_tween().tween_property(target, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if Data.STAR_BREAK.has(to):
			_star_msg.text = "突破 · %s！%s ★%d" % [Data.STAR_BREAK[to][1], Data.WEAPONS[id]["name"], to]
			world.hud.flash(Color(c.r, c.g, c.b, 0.45))
			Sfx.play("rare", 0.0)
		else:
			_star_msg.text = "升星成功！★%d" % to
		_star_msg.add_theme_color_override("font_color", c)
		Sfx.play("level_up", -2.0)
		Sfx.play("coin", -4.0)
	else:
		target.add_theme_color_override("font_color", Color(1, 1, 1, 0.16))
		var t2 := "失败……祝福 +%d%%（下次更容易）" % roundi(Data.STAR_BLESS * 100.0)
		if to < from:
			var lost: Label = _star_labels[to]
			lost.add_theme_color_override("font_color", UiKit.RED)
			lost.create_tween().tween_property(lost, "modulate:a", 0.15, 0.6)
			t2 = "失败，掉了一颗星（★%d）……祝福 +%d%%" % [to, roundi(Data.STAR_BLESS * 100.0)]
			Sfx.play("snap", 0.0, 0.0, 0.7)
		_star_msg.text = t2
		_star_msg.add_theme_color_override("font_color", UiKit.RED)
		Sfx.play("dry", -2.0, 0.0, 0.8)
		# 卡片抖一下
		if is_instance_valid(_star_card):
			var tw := _star_card.create_tween()
			for k in 6:
				tw.tween_property(_star_card, "position:x", _star_card.position.x + (8.0 if k % 2 == 0 else -8.0), 0.04)
			tw.tween_property(_star_card, "position:x", _star_card.position.x, 0.04)


# ------------------------------------------------------------------ 装饰：码头、船、暗器铺、营地（Decor）

# ------------------------------------------------------------------ 灵宠（Pet）：活捉过的灵兽王，挑一只带着

func _pets_tab() -> void:
	_list.add_child(UiKit.section("灵宠：一个人的时候最有用——打架帮你咬、隔一阵放一次本事，倒下时会把海鸥撞下来；人多了它只跟着跑", UiKit.GOLD))
	if Profile.pets.is_empty():
		var l := UiKit.label("还没有灵宠。猎场里把灵兽王打累了、血也不多了，用引魂索捆住它活捉，它就跟你回来", 16, UiKit.MIST)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(l)
		return
	for sp in Profile.pets:
		var sk := Pet.skill_of(str(sp))
		var on := Profile.pet == str(sp)
		var col: Color = Gear.SKILLS[Pet.kind(str(sp))]["color"]
		var h := _row(col if on else Color(0, 0, 0, 0))
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 3)
		h.add_child(v)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 10)
		v.add_child(top)
		top.add_child(UiKit.bold("%s%s" % [Data.age_name(int(Profile.pets[sp])), str(Data.BEASTS[sp]["name"])], 20, UiKit.MOON))
		top.add_child(UiKit.chip(str(sk["name"]), col, 13, true))
		if on:
			top.add_child(UiKit.chip("带着", UiKit.JADE, 12))
		v.add_child(UiKit.label(str(sk["desc"]), 14, UiKit.MIST))
		var spid := str(sp)
		var b := UiKit.button("让它回去" if on else "带上", 17, not on)
		b.custom_minimum_size.x = 150
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(func():
			Profile.pet = "" if Profile.pet == spid else spid
			Profile.mark_dirty()
			Sfx.play("switch", -4.0)
			world.refresh_pet()
			world._broadcast_prog()
			refresh())
		h.add_child(b)


# ------------------------------------------------------------------ 锻造（装备树 Gear）：护具 + 暗器锻造

var _gear_sp := ""


func _forge_tab() -> void:
	# 穿着的套装
	var worn := Gear.worn()
	_list.add_child(UiKit.section("身上的套装：同一类混穿也算件数，两件一个小加成，四件改打法", UiKit.GOLD))
	var wrow := HFlowContainer.new()
	wrow.add_theme_constant_override("h_separation", 8)
	wrow.add_theme_constant_override("v_separation", 6)
	_list.add_child(wrow)
	if worn.is_empty():
		wrow.add_child(UiKit.label("还没穿护具。猎场里打断灵兽王的角、尾、背甲，就有材料做", 15, UiKit.MIST))
	for kind in Gear.KIND_ORDER:
		var c := int(worn.get(kind, 0))
		if c <= 0:
			continue
		var s: Dictionary = Gear.SKILLS[kind]
		var txt := "%s %d/4" % [str(s["name"]), c]
		if c >= 2:
			txt += "  ·  " + str(s["two"])
		if c >= 4:
			txt += "  ·  " + str(s["four"])
		wrow.add_child(UiKit.chip(txt, s["color"], 15, c >= 4))
	# 选一种灵兽王看它的一套
	var sps := Gear.species()
	if not _gear_sp in sps:
		_gear_sp = ""
		for sp in sps:
			if _has_mats(sp) or int(Data.SPECIES_CH[sp]) == int(Profile.chapter):
				_gear_sp = str(sp)
				break
		if _gear_sp == "":
			_gear_sp = str(sps[0])
	_list.add_child(UiKit.section("护具", UiKit.GOLD))
	var pick := HFlowContainer.new()
	pick.add_theme_constant_override("h_separation", 8)
	pick.add_theme_constant_override("v_separation", 6)
	_list.add_child(pick)
	for sp in sps:
		var ch := int(Data.SPECIES_CH[sp])
		if ch > int(Profile.max_chapter) and not _has_mats(sp):
			continue
		var spid := str(sp)
		var b := UiKit.button(str(Data.BEASTS[sp]["name"]) + ("  ·" if _has_mats(sp) else ""), 15, spid == _gear_sp)
		b.pressed.connect(func():
			_gear_sp = spid
			refresh())
		pick.add_child(b)
	_gear_block(_gear_sp)
	_forge_block()


func _has_mats(sp: String) -> bool:
	if int(Profile.materials.get(sp, 0)) > 0:
		return true
	for k in Profile.parts:
		if str(k).get_slice("|", 0) == sp and int(Profile.parts[k]) > 0:
			return true
	return false


func _gear_block(sp: String) -> void:
	var kind := str(Gear.KIND[sp])
	var s: Dictionary = Gear.SKILLS[kind]
	# 这只王的材料
	var mats := HFlowContainer.new()
	mats.add_theme_constant_override("h_separation", 8)
	_list.add_child(mats)
	mats.add_child(UiKit.chip("%s套 · 两件：%s · 四件：%s" % [str(s["name"]), str(s["two"]), str(s["four"])], s["color"], 15, true))
	for part in ["head", "back", "wing", "tail", "core"]:
		var n := int(Profile.parts.get("%s|%s" % [sp, part], 0))
		if n > 0 or (part in ["head", "tail"]) or (part == ("wing" if Gear.fly(sp) else "back")):
			var nm: String = "灵核" if part == "core" else str(KingFeel.PART_NAME.get(part, part))
			mats.add_child(UiKit.chip("%s ×%d" % [nm, n], UiKit.MOON if n > 0 else UiKit.DIM, 14))
	mats.add_child(UiKit.chip("王魄 ×%d" % int(Profile.materials.get(sp, 0)), UiKit.GOLD if int(Profile.materials.get(sp, 0)) > 0 else UiKit.DIM, 14))
	for slot in Gear.SLOTS:
		var owned := Gear.owns(sp, slot)
		var on := str(Profile.gear_on.get(slot, "")) == sp
		var h := _row(s["color"] if on else Color(0, 0, 0, 0))
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 3)
		h.add_child(v)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 10)
		v.add_child(top)
		top.add_child(UiKit.bold(Gear.piece_name(sp, slot), 19, UiKit.MOON))
		if on:
			top.add_child(UiKit.chip("穿着", s["color"], 12))
		var cur := str(Profile.gear_on.get(slot, ""))
		if cur != "" and cur != sp:
			top.add_child(UiKit.chip("现在穿：%s" % Gear.piece_name(cur, slot), UiKit.DIM, 12))
		var need := HFlowContainer.new()
		need.add_theme_constant_override("h_separation", 6)
		v.add_child(need)
		need.add_child(UiKit.label("护体 +%d%%" % roundi(Gear.piece_armor(sp) * 100.0), 14, UiKit.MIST))
		var sl := str(slot)
		if owned:
			var b := UiKit.button("脱下" if on else "穿上", 17, not on)
			b.custom_minimum_size.x = 150
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			b.pressed.connect(func():
				Gear.toggle(sp, sl)
				Sfx.play("switch", -4.0)
				world._broadcast_prog()
				refresh())
			h.add_child(b)
			continue
		var c := Gear.cost(sp, slot)
		for k in c["parts"]:
			var have := int(Profile.parts.get(k, 0))
			var want := int(c["parts"][k])
			need.add_child(UiKit.chip("%s %d/%d" % [str(KingFeel.PART_NAME.get(str(k).get_slice("|", 1), "")), have, want], UiKit.GREEN if have >= want else UiKit.RED, 13))
		var hm := int(Profile.materials.get(sp, 0))
		need.add_child(UiKit.chip("王魄 %d/%d" % [hm, int(c["mat"])], UiKit.GREEN if hm >= int(c["mat"]) else UiKit.RED, 13))
		var b2 := _price_button(int(c["money"]), true, "做 · %d 灵石" % int(c["money"]))
		b2.disabled = not Gear.can_craft(sp, slot)
		b2.pressed.connect(func():
			if Gear.craft(sp, sl):
				Sfx.play("coin", -2.0)
				Sfx.play("level_up", -6.0, 0.0, 1.2)
				world.hud.toast("做好了【%s】，穿上了" % Gear.piece_name(sp, sl), s["color"])
				world._broadcast_prog()
			refresh())
		h.add_child(b2)


func _forge_block() -> void:
	_list.add_child(UiKit.section("锻造暗器：第几品用第几章灵兽王的材料，第五品要一颗灵核", UiKit.GOLD))
	if Profile.loadout.is_empty():
		_list.add_child(UiKit.label("身上没有暗器。先买一把", 18, UiKit.MIST))
		return
	_weapon_picker()
	var id := _pick_weapon
	var g := Gear.grade(id)
	var h := _row(UiKit.GOLD if g > 0 else Color(0, 0, 0, 0))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	h.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	v.add_child(top)
	top.add_child(UiKit.bold(Gear.forged_name(id), 22, UiKit.MOON))
	top.add_child(UiKit.chip("第 %d 品 / %d" % [g, Gear.FORGE_MAX], UiKit.GOLD if g > 0 else UiKit.DIM, 13))
	var c := Gear.forge_cost(id)
	if c.is_empty():
		v.add_child(UiKit.label("锻满了", 15, UiKit.GOLD))
		return
	var ng := int(c["grade"])
	v.add_child(UiKit.label("下一品：%s·%s（伤害更高）" % [str(Data.WEAPONS[id]["name"]), str(Gear.FORGE_NAME[ng])], 15, UiKit.MIST))
	var need := HFlowContainer.new()
	need.add_theme_constant_override("h_separation", 6)
	v.add_child(need)
	var hp := Gear.ch_parts(ng)
	need.add_child(UiKit.chip("第%d章灵兽王的部位 %d/%d" % [ng, hp, int(c["parts"])], UiKit.GREEN if hp >= int(c["parts"]) else UiKit.RED, 13))
	var hm := Gear.ch_mats(ng)
	need.add_child(UiKit.chip("第%d章王魄 %d/%d" % [ng, hm, int(c["mats"])], UiKit.GREEN if hm >= int(c["mats"]) else UiKit.RED, 13))
	if int(c["core"]) > 0:
		need.add_child(UiKit.chip("灵核 %d/%d" % [Gear.cores(), int(c["core"])], UiKit.GREEN if Gear.cores() >= int(c["core"]) else UiKit.RED, 13))
	var b := _price_button(int(c["money"]), true, "锻造 · %d 灵石" % int(c["money"]))
	b.disabled = not Gear.can_forge(id)
	b.pressed.connect(func():
		if Gear.forge(id):
			Sfx.play("coin", -2.0)
			Sfx.play("level_up", -4.0, 0.0, 1.0)
			world.hud.toast("锻成了【%s】" % Gear.forged_name(id), UiKit.GOLD)
			world.on_attach_changed()
		refresh())
	h.add_child(b)


func _decor_tab() -> void:
	_list.add_child(UiKit.section("装饰码头、渡船、暗器铺和猎场营地；联机时队友买的也会摆出来", UiKit.GOLD))
	var where_name := {"dock": "码头", "boat": "渡船", "shop": "暗器铺", "camp": "猎场营地"}
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_list.add_child(grid)
	for id in Data.DECOR_ORDER:
		var d: Dictionary = Data.DECOR[id]
		var owned := Profile.decor.has(id)
		var on := owned and bool(Profile.decor[id])
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiKit.card_style(d["color"] if on else Color(0, 0, 0, 0)))
		card.custom_minimum_size = Vector2(610, 0)
		grid.add_child(card)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		card.add_child(h)
		var sw := ColorRect.new()
		sw.color = d["color"]
		sw.custom_minimum_size = Vector2(10, 64)
		h.add_child(sw)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 3)
		h.add_child(v)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 10)
		v.add_child(top)
		top.add_child(UiKit.bold(str(d["name"]), 20, UiKit.MOON))
		top.add_child(UiKit.chip(str(where_name.get(str(d["where"]), "")), UiKit.MIST, 12))
		if on:
			top.add_child(UiKit.chip("摆着", UiKit.JADE, 12))
		var dl := UiKit.label(str(d["desc"]), 14, UiKit.MIST)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(dl)
		var did := str(id)
		if owned:
			var b := UiKit.button("收起" if on else "摆上", 17, not on)
			b.custom_minimum_size.x = 120
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			b.pressed.connect(func():
				Profile.toggle_decor(did)
				Sfx.play("switch", -4.0)
				world.decor.refresh()
				world._broadcast_prog()
				refresh())
			h.add_child(b)
		else:
			var b2 := _price_button(int(d["price"]))
			b2.custom_minimum_size.x = 120
			b2.pressed.connect(func():
				if Profile.buy_decor(did):
					Sfx.play("coin", -2.0)
					Sfx.play("level_up", -8.0, 0.0, 1.3)
					world.hud.toast("摆上了【%s】" % Data.DECOR[did]["name"], Data.DECOR[did]["color"])
					world.decor.refresh()
					world._broadcast_prog()
				refresh())
			h.add_child(b2)


func _enchant_tab() -> void:
	_list.add_child(UiKit.section("你的王魄（打地图上的灵兽王「王」，每只必掉）", UiKit.GOLD))
	var mats := HFlowContainer.new()
	mats.add_theme_constant_override("h_separation", 8)
	mats.add_theme_constant_override("v_separation", 6)
	_list.add_child(mats)
	for sp in Profile.materials:
		if int(Profile.materials[sp]) > 0:
			mats.add_child(UiKit.chip("%s王魄  ×%d" % [Data.BEASTS[sp]["name"], int(Profile.materials[sp])], UiKit.GOLD, 15))
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
		req.add_child(UiKit.chip("王魄 %d / %d" % [mini(have, need), need], UiKit.GREEN if have >= need else UiKit.RED, 12))
		req.add_child(UiKit.label("%s 王都行 · 另加 %d 灵石" % [" / ".join(names), int(e["price"])], 13, UiKit.MIST))
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

var _pick_weapon := ""


## 上面一排：选哪把暗器（配件、外观页用）
func _weapon_picker() -> void:
	var owned: Array = Profile.loadout
	if not _pick_weapon in owned:
		_pick_weapon = str(world.player.gun.id) if world.player.gun.id in owned else str(owned[0])
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 6)
	_list.add_child(row)
	for w in owned:
		var b := UiKit.button(str(Data.WEAPONS[w]["name"]), 16, w == _pick_weapon)
		var ww := str(w)
		b.pressed.connect(func():
			_pick_weapon = ww
			_look_skin = ""
			_look_charm = null
			refresh())
		row.add_child(b)


func _attach_block(id: String) -> void:
	var cur_slot := ""
	for a in _attach_sorted(id):
		var at: Dictionary = Data.ATTACH[a]
		if str(at["slot"]) != cur_slot:
			cur_slot = str(at["slot"])
			for s in Data.ATTACH_SLOTS:
				if s[0] == cur_slot:
					_list.add_child(UiKit.section(str(s[1]), UiKit.GOLD))
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


## 这把暗器能装的配件，按部位排（瞄具、枪口、枪管下、弹匣、枪托）
func _attach_sorted(id: String) -> Array:
	var out: Array = []
	for s in Data.ATTACH_SLOTS:
		for a in Data.ATTACH_OK.get(id, []):
			if str(Data.ATTACH[a]["slot"]) == str(s[0]):
				out.append(a)
	return out


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

var _preview: GunPreview
var _look_skin := ""             # 正在预览的皮肤（点卡片先看，不用先买）
var _look_charm: Variant = null  # 正在预览的挂件（null = 这把暗器挂着的）
var _paint: PaintPanel


func _looks_tab() -> void:
	if Profile.loadout.is_empty():
		_list.add_child(UiKit.label("身上没有暗器。先买一把", 18, UiKit.MIST))
	else:
		_list.add_child(UiKit.section("给哪把暗器换外观（每把可以穿不同的皮肤、挂不同的挂件）", UiKit.JADE))
		_weapon_picker()
		_gun_looks(_pick_weapon)
	_list.add_child(UiKit.section("装扮（长袍和帽子，第一人称能看到袖子）", UiKit.JADE))
	var g2 := GridContainer.new()
	g2.columns = 3
	g2.add_theme_constant_override("h_separation", 10)
	g2.add_theme_constant_override("v_separation", 10)
	_list.add_child(g2)
	for id in Data.OUTFIT_ORDER:
		g2.add_child(_look_card("outfit", id))


## 一把暗器的外观：左边 3D 预览（可以拖着转），右边正在看的皮肤 / 挂件和按钮；下面皮肤、挂件卡片、熟练度
func _gun_looks(w: String) -> void:
	var worn := Profile.skin_for(w)
	if _look_skin == "" or not Data.GUN_SKINS.has(_look_skin):
		_look_skin = worn
	var charm_now := Profile.charm_for(w)
	var charm_show: String = charm_now if _look_charm == null else str(_look_charm)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	_list.add_child(top)
	if _preview == null:
		_preview = GunPreview.new(Vector2i(720, 330))
	top.add_child(_preview)
	_preview.show_gun(w, _look_skin, null, charm_show)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 8)
	top.add_child(info)
	var sk: Dictionary = Data.GUN_SKINS[_look_skin]
	info.add_child(UiKit.kicker("皮肤", UiKit.GOLD))
	info.add_child(UiKit.title(str(sk["name"]), 34))
	var ds := UiKit.label(str(sk.get("desc", "")), 15, UiKit.MIST)
	ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ds.custom_minimum_size.x = 380
	info.add_child(ds)
	var tags := HBoxContainer.new()
	tags.add_theme_constant_override("separation", 6)
	info.add_child(tags)
	for t in _skin_tags(sk):
		tags.add_child(UiKit.chip(t, UiKit.MIST, 12))
	var acts := HFlowContainer.new()
	acts.add_theme_constant_override("h_separation", 8)
	acts.add_theme_constant_override("v_separation", 6)
	info.add_child(acts)
	var id := _look_skin
	if id == worn:
		acts.add_child(UiKit.chip("这把正穿着", UiKit.GOLD, 14))
	if Profile.owns_skin(w, id):
		if id != worn:
			var b := UiKit.button("装到%s" % Data.WEAPONS[w]["name"], 16, true)
			b.pressed.connect(func():
				Profile.wear_skin(w, id)
				Sfx.play("switch", -4.0)
				world.on_look_changed()
				refresh())
			acts.add_child(b)
		if id in Profile.skins and not Data.GUN_SKINS[id].has("mastery"):
			var ba := UiKit.button("所有暗器都用", 16)
			ba.pressed.connect(func():
				Profile.wear_skin("", id)
				Sfx.play("switch", -4.0)
				world.on_look_changed()
				world.hud.toast("所有暗器都换上了【%s】" % sk["name"], UiKit.GOLD)
				refresh())
			acts.add_child(ba)
	elif sk.has("mastery"):
		acts.add_child(UiKit.chip("%s熟练度 %d 级解锁（现在 %d 级）" % [Data.WEAPONS[w]["name"], int(sk["mastery"]), Profile.mastery_level(w)], UiKit.DIM, 14))
	elif bool(sk.get("paint", false)):
		acts.add_child(UiKit.chip("还没画", UiKit.DIM, 14))
	elif sk.has("boss"):
		acts.add_child(UiKit.chip("打 Boss 解锁", UiKit.DIM, 14))
	elif sk.has("codex"):
		acts.add_child(UiKit.chip("集齐猎灵录解锁", UiKit.DIM, 14))
	else:
		var bb := _price_button(int(sk["price"]), true, "%d  购买" % int(sk["price"]))
		bb.pressed.connect(func():
			if Profile.buy_look("skin", id):
				Profile.wear_skin(w, id)
				Sfx.play("coin", -2.0)
				world.on_look_changed()
				world.hud.toast("买到了【%s】，已经装到%s上（别的暗器也能用）" % [sk["name"], Data.WEAPONS[w]["name"]], UiKit.GOLD)
			refresh())
		acts.add_child(bb)
	var pb := UiKit.button("自己画" if not GunSkin.has_paint(w) else "接着画", 16)
	pb.pressed.connect(func(): _open_paint(w))
	acts.add_child(pb)
	info.add_child(UiKit.label("按住预览拖动可以转着看", 13, UiKit.DIM))

	# 皮肤卡片
	_list.add_child(UiKit.section("皮肤（点一下先在上面看效果）", UiKit.MIST))
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	_list.add_child(g)
	for sid in Data.GUN_SKIN_ORDER:
		g.add_child(_skin_card(w, sid, worn))
	# 挂件
	_list.add_child(UiKit.section("挂件（挂在暗器上，跑起来会晃）", UiKit.MIST))
	var cg := HFlowContainer.new()
	cg.add_theme_constant_override("h_separation", 8)
	cg.add_theme_constant_override("v_separation", 8)
	_list.add_child(cg)
	cg.add_child(_charm_card(w, "", charm_now, charm_show))
	for cid in Data.CHARM_ORDER:
		cg.add_child(_charm_card(w, cid, charm_now, charm_show))
	# 熟练度
	var ml := Profile.mastery_level(w)
	_list.add_child(UiKit.section("%s 熟练度 %d / %d（用它打死灵兽涨）" % [Data.WEAPONS[w]["name"], ml, Data.MASTERY_MAX], UiKit.MIST))
	var pr := HFlowContainer.new()
	pr.add_theme_constant_override("h_separation", 8)
	pr.add_theme_constant_override("v_separation", 6)
	_list.add_child(pr)
	for lv in range(2, Data.MASTERY_MAX + 1):
		var perk: Dictionary = Data.MASTERY_PERKS.get(lv, {})
		if perk.is_empty():
			continue
		pr.add_child(UiKit.chip("%d 级 · %s" % [lv, perk["text"]], UiKit.GOLD if ml >= lv else UiKit.DIM, 13, ml >= lv))


## 皮肤是什么质感（卡片、预览旁边的小标签）
func _skin_tags(sk: Dictionary) -> Array:
	var out: Array = []
	var pat := str(sk.get("pat", "plain"))
	var names := {"wood": "木纹", "fade": "渐变", "damascus": "折叠钢纹", "carbon": "碳纤维编织", "marble": "玉脉", "flow": "流光", "lava": "熔岩裂纹",
		"galaxy": "星云", "scales": "龙鳞", "pearl": "珠光变色", "circuit": "回路", "ice": "冰晶", "smoke": "流烟", "caustic": "水纹", "aurora": "极光", "brushed": "拉丝", "web": "蛛网"}
	if names.has(pat):
		out.append(str(names[pat]))
	if float(sk.get("body_metal", float(sk.get("metal", 0.0)) * 0.6)) >= 0.8:
		out.append("金属反光" if float(sk.get("body_rough", 0.3)) > 0.1 else "镜面")
	if float(sk.get("coat", 0.0)) > 0.5:
		out.append("清漆")
	if pat in ["flow", "lava", "galaxy", "circuit", "ice", "smoke", "caustic", "aurora", "web"]:
		out.append("会动")
	if bool(sk.get("paint", false)):
		out.append("自己画")
	return out


func _skin_card(w: String, sid: String, worn: String) -> Control:
	var sk: Dictionary = Data.GUN_SKINS[sid]
	var owned := Profile.owns_skin(w, sid)
	var accent := UiKit.GOLD if sid == worn else (UiKit.JADE if sid == _look_skin else Color(0, 0, 0, 0))
	var b := UiKit.card_button(accent if accent.a > 0.0 else Color(1, 1, 1, 0.2))
	b.custom_minimum_size = Vector2(300, 74)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.fill(h)
	h.offset_left = 10
	h.offset_right = -10
	b.add_child(h)
	h.add_child(_swatch(sk))
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	h.add_child(v)
	v.add_child(UiKit.bold(str(sk["name"]), 17, UiKit.MOON if owned else UiKit.MIST))
	var st := ""
	if sid == worn:
		st = "穿着"
	elif owned:
		st = "已有"
	elif sk.has("mastery"):
		st = "熟练度 %d 级" % int(sk["mastery"])
	elif bool(sk.get("paint", false)):
		st = "自己画"
	elif sk.has("boss"):
		st = "Boss 解锁"
	elif sk.has("codex"):
		st = "猎灵录解锁"
	else:
		st = "%d 灵石" % int(sk["price"])
	v.add_child(UiKit.label(st, 13, UiKit.GOLD if sid == worn else (UiKit.JADE if owned else UiKit.DIM)))
	b.pressed.connect(func():
		_look_skin = sid
		refresh())
	return b


## 皮肤色块：几条颜色（底色、第二色、发光色）
func _swatch(sk: Dictionary) -> Control:
	var pal: Dictionary = sk.get("pal", {})
	var cols: Array = [pal.get("lacquer", WeaponModels.BASE_PAL["lacquer"]), pal.get("wood", WeaponModels.BASE_PAL["wood"]),
		sk.get("c2", pal.get("gold", WeaponModels.BASE_PAL["gold"])), sk.get("c3", sk.get("glow", Color(0.35, 0.95, 0.8))), pal.get("gold", WeaponModels.BASE_PAL["gold"])]
	var sw := Control.new()
	sw.custom_minimum_size = Vector2(52, 52)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var metal := float(sk.get("body_metal", float(sk.get("metal", 0.0)) * 0.6)) >= 0.8
	sw.draw.connect(func():
		if bool(sk.get("paint", false)):
			for i in 5:
				sw.draw_rect(Rect2(i * 10.4, 0, 10.4, 52), Color.from_hsv(i / 5.0, 0.7, 0.95))
		else:
			sw.draw_rect(Rect2(0, 0, 52, 30), cols[0])
			sw.draw_rect(Rect2(0, 30, 26, 22), cols[1])
			sw.draw_rect(Rect2(26, 30, 26, 22), cols[2])
			sw.draw_rect(Rect2(0, 27, 52, 3), cols[4])
			sw.draw_circle(Vector2(40, 14), 6.0, cols[3])
		if metal:
			# 金属：一道斜着的高光
			sw.draw_colored_polygon(PackedVector2Array([Vector2(8, 0), Vector2(18, 0), Vector2(0, 30), Vector2(0, 16)]), Color(1, 1, 1, 0.35))
		sw.draw_rect(Rect2(0, 0, 52, 52), Color(1, 1, 1, 0.25), false, 1.0))
	return sw


func _charm_card(w: String, cid: String, now: String, showing: String) -> Control:
	var d: Dictionary = Data.CHARMS.get(cid, {"name": "不挂", "price": 0, "desc": "什么都不挂"})
	var owned := cid == "" or cid in Profile.charms
	var accent := UiKit.GOLD if cid == now else (UiKit.JADE if cid == showing else Color(1, 1, 1, 0.2))
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiKit.card_style(accent))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.custom_minimum_size.x = 190
	box.add_child(v)
	v.add_child(UiKit.bold(str(d["name"]), 17))
	var ds := UiKit.label(str(d["desc"]), 12, UiKit.MIST)
	ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ds.custom_minimum_size.x = 170
	v.add_child(ds)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	var look := UiKit.button("看看", 13)
	look.pressed.connect(func():
		_look_charm = cid
		refresh())
	row.add_child(look)
	if cid == now:
		row.add_child(UiKit.chip("挂着", UiKit.GOLD, 12))
	elif owned:
		var b := UiKit.button("挂上" if cid != "" else "摘下", 13, true)
		b.pressed.connect(func():
			Profile.set_charm(w, cid)
			_look_charm = null
			Sfx.play("switch", -4.0)
			world.on_look_changed()
			refresh())
		row.add_child(b)
	else:
		var b2 := UiKit.button("%d" % int(d["price"]), 13, true)
		b2.disabled = Profile.money < int(d["price"])
		b2.pressed.connect(func():
			if Profile.buy_charm(cid):
				Profile.set_charm(w, cid)
				_look_charm = null
				Sfx.play("coin", -2.0)
				world.on_look_changed()
			refresh())
		row.add_child(b2)
	return box


## 自己画皮肤：打开画板（全屏，关掉回到外观页）
func _open_paint(w: String) -> void:
	if _paint == null:
		_paint = PaintPanel.new()
		add_child(_paint)
		_paint.closed.connect(func():
			_paint.visible = false
			_look_skin = Profile.skin_for(_pick_weapon)
			world.on_look_changed()
			refresh())
	_paint.open(w)


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
		act.add_child(UiKit.chip("集齐猎灵录解锁", UiKit.DIM, 13))
	else:
		var b2 := UiKit.button("%d 灵石" % int(d["price"]), 15, true)
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
