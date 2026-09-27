class_name PaintPanel
extends ColorRect
## 自己画暗器皮肤（用户："甚至是玩家自己画"）。
##
## 中间是暗器的正侧面（正交视图），直接在暗器上画：画布 512×256 正好对上这个画面，画一笔暗器上马上就有。
## 画的图从右侧面投影到整把暗器上（左边是枪尾、右边是枪口；另一面是镜像的）。
## 工具：画笔、喷枪、橡皮、图章（星、圆、条纹、闪电、心、云纹）、写字；颜色、大小、不透明度；颜料质感（哑光 / 亮漆 / 金属 / 镜面）。
## 撤销 Ctrl+Z。保存后这把暗器穿上"自己画"的皮肤（GunSkin.save_paint，存在 user://paint/）。

signal closed

const W := GunSkin.PAINT_W
const H := GunSkin.PAINT_H
const VIEW := Vector2(820, 410)
const PALETTE := [Color(0.95, 0.95, 0.95), Color(0.1, 0.1, 0.11), Color(0.55, 0.56, 0.6), Color(0.85, 0.12, 0.1), Color(1.0, 0.45, 0.1), Color(1.0, 0.8, 0.2),
	Color(0.45, 0.85, 0.25), Color(0.1, 0.55, 0.3), Color(0.25, 0.8, 0.95), Color(0.15, 0.35, 0.9), Color(0.5, 0.25, 0.85), Color(1.0, 0.45, 0.75),
	Color(0.45, 0.25, 0.12), Color(0.9, 0.75, 0.55), Color(0.3, 0.05, 0.08), Color(0.05, 0.15, 0.3), Color(1.0, 0.85, 0.45), Color(0.7, 0.95, 0.85)]
const STAMPS := [["star", "星"], ["circle", "圆"], ["stripes", "条纹"], ["bolt", "闪电"], ["heart", "心"], ["cloud", "云纹"]]
const TOOLS := [["brush", "画笔"], ["air", "喷枪"], ["erase", "橡皮"], ["stamp", "图章"], ["text", "写字"]]

var weapon := ""
var img: Image
var tex: ImageTexture
var tool := "brush"
var stamp := "star"
var pcol := Color(0.85, 0.12, 0.1)
var brush := 14.0
var opacity := 1.0
var finish := "gloss"
var _undo: Array = []
var _drawing := false
var _last := Vector2.ZERO
var _brush: Image
var _brush_key := ""
var _hover := Vector2(-1, -1)
var _built := false
# 界面
var _side: GunPreview
var _persp: GunPreview
var _canvas_view: TextureRect
var _draw_area: Control
var _tool_btns := {}
var _stamp_row: HFlowContainer
var _text_row: HBoxContainer
var _text_edit: LineEdit
var _fin_btns := {}
var _swatch_now: ColorRect
var _picker: ColorPickerButton
var _title: Label
var _text_vp: SubViewport
var _text_label: Label


func _ready() -> void:
	color = Color.WHITE
	material = UiKit.blur_material(0.8)
	UiKit.fill(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func open(w: String) -> void:
	weapon = w
	if not _built:
		_build()
		_built = true
	_title.text = "给%s画皮肤" % Data.WEAPONS[w]["name"]
	# 已经画过就接着画
	var old := GunSkin.paint_texture(w)
	if old:
		img = old.get_image()
		img.clear_mipmaps()
		img.convert(Image.FORMAT_RGBA8)
	else:
		img = Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	if img.get_width() != W or img.get_height() != H:
		img.resize(W, H)
	tex = ImageTexture.create_from_image(img)
	GunSkin.set_live_paint(w, tex)
	finish = str(Profile.paint.get(w, {}).get("finish", "gloss"))
	_undo.clear()
	_canvas_view.texture = tex
	visible = true
	_refresh_models()
	_refresh_buttons()


func _refresh_models() -> void:
	_side.show_gun(weapon, "paint", {}, "")
	_persp.show_gun(weapon, "paint", {}, "")


# ------------------------------------------------------------------ 界面

func _build() -> void:
	var center := CenterContainer.new()
	add_child(center)
	UiKit.fill(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	center.add_child(v)
	var head := UiKit.panel_head("暗器铺 · 外观", "自己画", "Esc", func(): _cancel())
	v.add_child(head)
	_title = UiKit.label("", 18, UiKit.MIST)
	v.add_child(_title)
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 14)
	v.add_child(main)

	# 左：工具
	var tools := VBoxContainer.new()
	tools.custom_minimum_size.x = 230
	tools.add_theme_constant_override("separation", 8)
	main.add_child(tools)
	tools.add_child(UiKit.kicker("工具", UiKit.GOLD))
	var tg := GridContainer.new()
	tg.columns = 3
	tg.add_theme_constant_override("h_separation", 6)
	tg.add_theme_constant_override("v_separation", 6)
	tools.add_child(tg)
	for t in TOOLS:
		var b := UiKit.button(str(t[1]), 15)
		var tid := str(t[0])
		b.pressed.connect(func():
			tool = tid
			_refresh_buttons())
		tg.add_child(b)
		_tool_btns[tid] = b
	_stamp_row = HFlowContainer.new()
	_stamp_row.add_theme_constant_override("h_separation", 6)
	_stamp_row.add_theme_constant_override("v_separation", 6)
	tools.add_child(_stamp_row)
	for s in STAMPS:
		var b2 := UiKit.button(str(s[1]), 14)
		var sid := str(s[0])
		b2.set_meta("sid", sid)
		b2.pressed.connect(func():
			stamp = sid
			_refresh_buttons())
		_stamp_row.add_child(b2)
	_text_row = HBoxContainer.new()
	tools.add_child(_text_row)
	_text_edit = LineEdit.new()
	_text_edit.text = "唐门"
	_text_edit.max_length = 12
	_text_edit.placeholder_text = "要写的字"
	_text_edit.custom_minimum_size.x = 220
	_text_row.add_child(_text_edit)
	tools.add_child(UiKit.kicker("大小", UiKit.MIST))
	tools.add_child(_slider(2, 64, brush, func(x: float): brush = x))
	tools.add_child(UiKit.kicker("不透明度", UiKit.MIST))
	tools.add_child(_slider(0.05, 1.0, opacity, func(x: float): opacity = x))
	tools.add_child(UiKit.kicker("颜色", UiKit.MIST))
	var pg := GridContainer.new()
	pg.columns = 6
	pg.add_theme_constant_override("h_separation", 4)
	pg.add_theme_constant_override("v_separation", 4)
	tools.add_child(pg)
	for c in PALETTE:
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(33, 26)
		var st := StyleBoxFlat.new()
		st.bg_color = c
		st.set_border_width_all(1)
		st.border_color = Color(1, 1, 1, 0.25)
		sw.add_theme_stylebox_override("normal", st)
		var sth := st.duplicate() as StyleBoxFlat
		sth.border_color = Color.WHITE
		sw.add_theme_stylebox_override("hover", sth)
		sw.add_theme_stylebox_override("pressed", sth)
		sw.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var cc: Color = c
		sw.pressed.connect(func():
			pcol = cc
			_picker.color = cc
			_refresh_buttons())
		pg.add_child(sw)
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 8)
	tools.add_child(crow)
	_swatch_now = ColorRect.new()
	_swatch_now.custom_minimum_size = Vector2(48, 32)
	crow.add_child(_swatch_now)
	_picker = ColorPickerButton.new()
	_picker.text = "调色"
	_picker.custom_minimum_size = Vector2(120, 32)
	_picker.edit_alpha = false
	_picker.color = pcol
	_picker.color_changed.connect(func(c: Color):
		pcol = c
		_refresh_buttons())
	crow.add_child(_picker)
	tools.add_child(UiKit.kicker("颜料质感", UiKit.MIST))
	var fr := GridContainer.new()
	fr.columns = 4
	fr.add_theme_constant_override("h_separation", 4)
	fr.add_theme_constant_override("v_separation", 4)
	tools.add_child(fr)
	for f in Data.PAINT_FINISH_ORDER:
		var fb := UiKit.button(str(Data.PAINT_FINISH[f]["name"]), 14)
		var fid := str(f)
		fb.pressed.connect(func():
			finish = fid
			Profile.paint[weapon] = {"finish": finish}
			_refresh_models()
			_refresh_buttons())
		fr.add_child(fb)
		_fin_btns[fid] = fb
	var er := HBoxContainer.new()
	er.add_theme_constant_override("separation", 6)
	tools.add_child(er)
	var ub := UiKit.button("撤销", 14)
	ub.pressed.connect(_undo_step)
	er.add_child(ub)
	var fb2 := UiKit.button("铺满底色", 14)
	fb2.pressed.connect(func():
		_push_undo()
		var full := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
		full.fill(Color(pcol.r, pcol.g, pcol.b, opacity))
		img.blend_rect(full, Rect2i(0, 0, W, H), Vector2i.ZERO)
		_commit())
	er.add_child(fb2)
	var cb := UiKit.button("清空", 14)
	cb.pressed.connect(func():
		_push_undo()
		img.fill(Color(0, 0, 0, 0))
		_commit())
	er.add_child(cb)

	# 中：在暗器侧面上画
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 6)
	main.add_child(mid)
	var stack := Control.new()
	stack.custom_minimum_size = VIEW
	mid.add_child(stack)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.11, 0.14, 0.9)
	UiKit.fill(bg)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(bg)
	_side = GunPreview.new(Vector2i(VIEW), true)
	UiKit.fill(_side)
	stack.add_child(_side)
	# 画布本身淡淡地叠在上面（画到暗器外面的也看得到）
	_canvas_view = TextureRect.new()
	_canvas_view.stretch_mode = TextureRect.STRETCH_SCALE
	_canvas_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_canvas_view.modulate = Color(1, 1, 1, 0.22)
	_canvas_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.fill(_canvas_view)
	stack.add_child(_canvas_view)
	_draw_area = Control.new()
	UiKit.fill(_draw_area)
	_draw_area.mouse_filter = Control.MOUSE_FILTER_STOP
	_draw_area.gui_input.connect(_on_canvas_input)
	_draw_area.mouse_exited.connect(func():
		_hover = Vector2(-1, -1)
		_draw_area.queue_redraw())
	_draw_area.draw.connect(_draw_cursor)
	stack.add_child(_draw_area)
	mid.add_child(UiKit.label("左边是枪尾，右边是枪口。直接在暗器上画；另一面是镜像的。Ctrl+Z 撤销", 14, UiKit.DIM))

	# 右：3D 预览 + 保存
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	main.add_child(right)
	right.add_child(UiKit.kicker("效果", UiKit.GOLD))
	_persp = GunPreview.new(Vector2i(300, 200))
	right.add_child(_persp)
	right.add_child(UiKit.label("拖动转着看", 13, UiKit.DIM))
	var sv := UiKit.button("保存并穿上", 20, true)
	sv.pressed.connect(_save)
	right.add_child(sv)
	var cn := UiKit.button("不保存", 16)
	cn.pressed.connect(_cancel)
	right.add_child(cn)

	# 写字用：把字画进一张透明图
	_text_vp = SubViewport.new()
	_text_vp.transparent_bg = true
	_text_vp.size = Vector2i(512, 128)
	_text_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_text_vp)
	_text_label = Label.new()
	_text_label.add_theme_font_override("font", Data.font_bold)
	_text_vp.add_child(_text_label)


func _slider(lo: float, hi: float, val: float, on: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.01 if hi <= 1.0 else 1.0
	s.value = val
	s.custom_minimum_size.x = 220
	s.value_changed.connect(func(x: float): on.call(x))
	return s


func _refresh_buttons() -> void:
	for t in _tool_btns:
		_style_pick(_tool_btns[t], t == tool)
	for b in _stamp_row.get_children():
		_style_pick(b, str(b.get_meta("sid")) == stamp)
	for f in _fin_btns:
		_style_pick(_fin_btns[f], f == finish)
	_stamp_row.visible = tool == "stamp"
	_text_row.visible = tool == "text"
	_swatch_now.color = pcol


## 选中的按钮金色描边
func _style_pick(b: Button, on: bool) -> void:
	b.modulate = Color(1.0, 0.85, 0.45) if on else Color.WHITE


# ------------------------------------------------------------------ 画

func _to_px(p: Vector2) -> Vector2:
	return Vector2(p.x / _draw_area.size.x * W, p.y / _draw_area.size.y * H)


func _on_canvas_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		_hover = (e as InputEventMouseMotion).position
		_draw_area.queue_redraw()
		if _drawing and tool in ["brush", "air", "erase"]:
			var p := _to_px(_hover)
			_stroke(_last, p)
			_last = p
			_commit()
	elif e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := e as InputEventMouseButton
		if mb.pressed:
			var p2 := _to_px(mb.position)
			_push_undo()
			match tool:
				"stamp":
					_stamp_at(p2)
					_commit()
				"text":
					_text_at(p2)
				_:
					_drawing = true
					_last = p2
					_dab(p2)
					_commit()
		else:
			_drawing = false


func _draw_cursor() -> void:
	if _hover.x < 0.0:
		return
	var r := brush * 0.5 * _draw_area.size.x / W
	if tool == "stamp":
		r *= 3.0
	_draw_area.draw_arc(_hover, maxf(r, 2.0), 0.0, TAU, 32, Color(1, 1, 1, 0.8), 1.5)
	_draw_area.draw_arc(_hover, maxf(r, 2.0) + 1.5, 0.0, TAU, 32, Color(0, 0, 0, 0.5), 1.0)


## 圆形笔刷（画笔硬边、喷枪软边、很淡）
func _brush_img() -> Image:
	var soft := tool == "air"
	var a := opacity * (0.12 if soft else 1.0)
	var key := "%d|%s|%.3f|%s" % [int(brush), pcol.to_html(), a, soft]
	if key == _brush_key and _brush:
		return _brush
	_brush_key = key
	var r := maxf(brush * 0.5, 1.0)
	var n := int(ceil(r * 2.0)) + 2
	_brush = Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n, n) * 0.5
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var k := (1.0 - smoothstep(0.0, r, d)) if soft else clampf(r - d + 0.5, 0.0, 1.0)
			if k > 0.0:
				_brush.set_pixel(x, y, Color(pcol.r, pcol.g, pcol.b, a * k))
	return _brush


func _dab(p: Vector2) -> void:
	if tool == "erase":
		_erase(p)
		return
	var b := _brush_img()
	var n := b.get_width()
	img.blend_rect(b, Rect2i(0, 0, n, n), Vector2i(int(p.x - n * 0.5), int(p.y - n * 0.5)))


func _stroke(a: Vector2, b: Vector2) -> void:
	var step := maxf(brush * (0.35 if tool == "air" else 0.2), 1.0)
	var d := a.distance_to(b)
	var k := step
	while k <= d:
		_dab(a.lerp(b, k / d))
		k += step
	if d < step:
		_dab(b)


func _erase(p: Vector2) -> void:
	var r := maxf(brush * 0.5, 1.0)
	for y in range(int(p.y - r) - 1, int(p.y + r) + 2):
		if y < 0 or y >= H:
			continue
		for x in range(int(p.x - r) - 1, int(p.x + r) + 2):
			if x < 0 or x >= W:
				continue
			var k := clampf(r - Vector2(x + 0.5, y + 0.5).distance_to(p) + 0.5, 0.0, 1.0) * opacity
			if k > 0.0:
				var c := img.get_pixel(x, y)
				c.a = maxf(c.a - k, 0.0)
				img.set_pixel(x, y, c)


## 图章：大小是笔刷的 3 倍，按形状填颜色
func _stamp_at(p: Vector2) -> void:
	var s := int(maxf(brush * 3.0, 12.0))
	var poly := _stamp_poly(stamp)
	var st := Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var q := Vector2((x + 0.5) / s * 2.0 - 1.0, (y + 0.5) / s * 2.0 - 1.0)
			var inside := false
			match stamp:
				"circle":
					inside = q.length() < 0.95
				"stripes":
					inside = fmod(q.x + q.y + 4.0, 0.7) < 0.3 and absf(q.x) < 0.98 and absf(q.y) < 0.98
				"heart":
					var hx := q.x * 1.2
					var hy := -q.y * 1.2 + 0.25
					inside = pow(hx * hx + hy * hy - 0.5, 3.0) - hx * hx * hy * hy * hy < 0.0
				_:
					inside = Geometry2D.is_point_in_polygon(q, poly)
			if inside:
				st.set_pixel(x, y, Color(pcol.r, pcol.g, pcol.b, opacity))
	img.blend_rect(st, Rect2i(0, 0, s, s), Vector2i(int(p.x - s * 0.5), int(p.y - s * 0.5)))


func _stamp_poly(kind: String) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match kind:
		"star":
			for i in 10:
				var a := -PI / 2 + i * PI / 5.0
				var r := 0.95 if i % 2 == 0 else 0.4
				pts.append(Vector2(cos(a), sin(a)) * r)
		"bolt":
			pts = PackedVector2Array([Vector2(0.15, -0.95), Vector2(-0.45, 0.1), Vector2(-0.02, 0.1), Vector2(-0.2, 0.95), Vector2(0.5, -0.15), Vector2(0.05, -0.15), Vector2(0.35, -0.95)])
		"cloud":
			# 祥云：几个圆弧拼出来的轮廓
			for i in 24:
				var a2 := i * TAU / 24.0
				var r2 := 0.62 + 0.28 * absf(sin(a2 * 2.5))
				pts.append(Vector2(cos(a2) * r2, sin(a2) * r2 * 0.65))
	return pts


## 写字：用一个小视口把字画成透明图，再贴上去
func _text_at(p: Vector2) -> void:
	var t := _text_edit.text.strip_edges()
	if t == "":
		return
	var fs := int(maxf(brush * 2.0, 12.0))
	_text_label.text = t
	_text_label.add_theme_font_size_override("font_size", fs)
	_text_label.add_theme_color_override("font_color", Color(pcol.r, pcol.g, pcol.b, opacity))
	_text_label.reset_size()
	var ls := _text_label.get_minimum_size()
	_text_vp.size = Vector2i(maxi(int(ls.x) + 4, 8), maxi(int(ls.y) + 4, 8))
	_text_label.position = Vector2(2, 2)
	_text_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var ti := _text_vp.get_texture().get_image()
	if ti == null or ti.is_empty():
		return
	ti.convert(Image.FORMAT_RGBA8)
	img.blend_rect(ti, Rect2i(Vector2i.ZERO, ti.get_size()), Vector2i(int(p.x - ti.get_width() * 0.5), int(p.y - ti.get_height() * 0.5)))
	_commit()


func _commit() -> void:
	tex.update(img)


func _push_undo() -> void:
	_undo.append(img.duplicate())
	while _undo.size() > 25:
		_undo.pop_front()


func _undo_step() -> void:
	if _undo.is_empty():
		return
	img = _undo.pop_back()
	_commit()


func _input(e: InputEvent) -> void:
	if not visible:
		return
	if e is InputEventKey and (e as InputEventKey).pressed:
		var k := e as InputEventKey
		if k.keycode == KEY_ESCAPE:
			_cancel()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_Z and k.ctrl_pressed:
			_undo_step()
			get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ 保存 / 取消

func _save() -> void:
	var out := img.duplicate() as Image
	GunSkin.save_paint(weapon, out)
	Profile.paint[weapon] = {"finish": finish}
	Profile.wear_skin(weapon, "paint")
	Profile.mark_dirty()
	Sfx.play("level_up", -6.0, 0.0, 1.3)
	visible = false
	closed.emit()


func _cancel() -> void:
	# 没保存：扔掉编辑中的图，下次用存盘的
	GunSkin.forget_live(weapon)
	visible = false
	closed.emit()
