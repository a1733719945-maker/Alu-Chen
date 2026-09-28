class_name UiKit
extends RefCounted
## 界面的统一样式（参考 Apex / 命运2 / Valorant 的做法）：
##   打开的面板铺满全屏，背后的游戏画面虚化压暗（毛玻璃）；直角细边，不用粗黑描边；
##   标题上面一行小字做"眉题"；分页用下划线；数值用属性条，少写长句。
##   颜色：金色 = 主操作 / 灵环 / 灵石，青色 = 信息强调，红色 = 危险，其余都是白和灰。
##   字体：标题思源黑体 Black，正文 Medium，数字 Barlow Condensed。

const BG := Color(0.03, 0.04, 0.06, 0.92)
const PANEL := Color(0.045, 0.055, 0.075, 0.9)
const GLASS := Color(0.02, 0.03, 0.045, 0.5)     # HUD 上的半透明底
const ROW := Color(1, 1, 1, 0.045)
const ROW_HI := Color(1, 1, 1, 0.09)
const LINE := Color(1, 1, 1, 0.12)
const GOLD := Color(1.0, 0.78, 0.3)
const JADE := Color(0.4, 0.8, 1.0)
const RED := Color(1.0, 0.38, 0.32)
const GREEN := Color(0.45, 0.95, 0.6)
const MOON := Color(0.95, 0.96, 0.98)
const MIST := Color(0.62, 0.67, 0.75)
const DIM := Color(0.4, 0.44, 0.5)


## 按锚点和偏移定位：anchor = (左, 上, 右, 下) 的 0..1 比例，off = 像素偏移
static func place(c: Control, anchor: Vector4, off: Vector4) -> void:
	c.anchor_left = anchor.x
	c.anchor_top = anchor.y
	c.anchor_right = anchor.z
	c.anchor_bottom = anchor.w
	c.offset_left = off.x
	c.offset_top = off.y
	c.offset_right = off.z
	c.offset_bottom = off.w


static func fill(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


static func _flat(bg: Color, margin_x := 0, margin_y := 0, radius := 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin_x
	s.content_margin_right = margin_x
	s.content_margin_top = margin_y
	s.content_margin_bottom = margin_y
	return s


static func panel_style(color := PANEL) -> StyleBoxFlat:
	var s := _flat(color, 28, 24, 3)
	s.border_color = LINE
	s.set_border_width_all(1)
	s.shadow_color = Color(0, 0, 0, 0.4)
	s.shadow_size = 24
	return s


## HUD 上的半透明底（没有边框）
static func glass_style(alpha := 0.5, mx := 12, my := 8) -> StyleBoxFlat:
	return _flat(Color(GLASS.r, GLASS.g, GLASS.b, alpha), mx, my, 2)


## 列表里的一行（商店、灵环）：左边一条彩色竖线
static func row_style(border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var st := _flat(ROW, 18, 12, 2)
	if border.a > 0.0:
		st.border_color = border
		st.border_width_left = 3
	return st


## 卡片：顶上一条彩色线
static func card_style(accent := Color(0, 0, 0, 0), bg := ROW) -> StyleBoxFlat:
	var st := _flat(bg, 20, 16, 2)
	st.border_color = accent if accent.a > 0.0 else LINE
	st.border_width_top = 2 if accent.a > 0.0 else 1
	if accent.a <= 0.0:
		st.set_border_width_all(1)
	return st


static func _text_style(l: Label, outline: int) -> void:
	if outline <= 0:
		return
	# 画在游戏画面上的字：细描边 + 往下一点的投影，比粗黑边干净
	l.add_theme_constant_override("outline_size", mini(outline, 4))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", mini(outline, 4) + 3)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.38))


static func label(text: String, size := 20, color := MOON, outline := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text_style(l, outline)
	return l


static func bold(text: String, size := 20, color := MOON, outline := 0) -> Label:
	var l := label(text, size, color, outline)
	l.add_theme_font_override("font", Data.font_bold)
	return l


static func title(text: String, size := 48, color := MOON) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", Data.font_title)
	return l


## 大数字（弹药、灵石）：窄体
static func num(text: String, size := 40, color := MOON, outline := 4) -> Label:
	var l := label(text, size, color, outline)
	l.add_theme_font_override("font", Data.font_num)
	return l


## 眉题：标题上面的一行小字（灰色、字距拉开）
static func kicker(text: String, color := MIST, size := 14) -> Label:
	var l := bold(text, size, color)
	var f := FontVariation.new()
	f.base_font = Data.font_bold
	f.spacing_glyph = 3
	l.add_theme_font_override("font", f)
	return l


## 面板标题：眉题 + 大标题
static func header(kick: String, text: String, color := MOON, size := 44) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if kick != "":
		v.add_child(kicker(kick, GOLD))
	v.add_child(title(text, size, color))
	return v


## 小标题 + 右边一条细线
static func section(text: String, color := MIST, outline := 0) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var k := kicker(text, color, 13)
	_text_style(k, outline)
	h.add_child(k)
	var line := ColorRect.new()
	line.color = LINE if outline == 0 else Color(color.r, color.g, color.b, 0.35)
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(line)
	return h


## 小标签（"在身上"、"灵力 60"）
static func chip(text: String, color := MIST, size := 13, filled := false) -> PanelContainer:
	var p := PanelContainer.new()
	var st := _flat(Color(color.r, color.g, color.b, 0.9 if filled else 0.12), 8, 2, 2)
	st.border_color = Color(color.r, color.g, color.b, 0.5)
	st.set_border_width_all(0 if filled else 1)
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := bold(text, size, Color(0.06, 0.06, 0.08) if filled else color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


## 属性条：名字、条、数值（暗器铺比较暗器）
static func stat_bar(name: String, k: float, value: String, color := MOON, width := 150.0) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := label(name, 13, MIST)
	n.custom_minimum_size.x = 40
	h.add_child(n)
	var b := bar(color, width, 4)
	b.value = clampf(k, 0.0, 1.0)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(b)
	h.add_child(num(value, 17, MOON, 0))
	return h


## 细长的进度条
static func bar(color: Color, w := 200.0, h := 6.0) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(w, h)
	b.show_percentage = false
	b.max_value = 1.0
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_theme_stylebox_override("background", _flat(Color(1, 1, 1, 0.1), 0, 0, 1))
	b.add_theme_stylebox_override("fill", _flat(color, 0, 0, 1))
	return b


## 分页：一排字，选中的下面一条金线
static func tabs(items: Array, current: String, on_pick: Callable) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	for it in items:
		var id := str(it[0])
		var on := id == current
		var b := Button.new()
		b.text = str(it[1])
		b.add_theme_font_override("font", Data.font_bold)
		b.add_theme_font_size_override("font_size", 19)
		b.custom_minimum_size = Vector2(0, 44)
		var n := _flat(Color(0, 0, 0, 0), 18, 6, 0)
		n.border_color = GOLD if on else Color(1, 1, 1, 0.0)
		n.border_width_bottom = 3
		var hv := n.duplicate() as StyleBoxFlat
		hv.bg_color = Color(1, 1, 1, 0.05)
		if not on:
			hv.border_color = Color(1, 1, 1, 0.25)
		b.add_theme_stylebox_override("normal", n)
		b.add_theme_stylebox_override("hover", hv)
		b.add_theme_stylebox_override("pressed", hv)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var fc := MOON if on else MIST
		b.add_theme_color_override("font_color", fc)
		b.add_theme_color_override("font_hover_color", MOON)
		b.add_theme_color_override("font_pressed_color", MOON)
		b.pressed.connect(func():
			Sfx.play("ui_click", -8.0)
			on_pick.call(id))
		h.add_child(b)
	return h


## 全屏打开的面板背后：把游戏画面虚化、压暗（毛玻璃）
const BLUR_SHADER := """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float lod = 3.2;
uniform vec4 tint : source_color = vec4(0.02, 0.03, 0.05, 0.62);
void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, lod).rgb;
	float v = smoothstep(0.2, 0.95, length(UV - 0.5) * 1.35);
	COLOR = vec4(mix(c, tint.rgb, clamp(tint.a + v * 0.25, 0.0, 1.0)), 1.0);
}"""
static var _blur: Shader


static func blur_material(alpha := 0.62) -> ShaderMaterial:
	if not _blur:
		_blur = Shader.new()
		_blur.code = BLUR_SHADER
	var m := ShaderMaterial.new()
	m.shader = _blur
	m.set_shader_parameter("tint", Color(0.02, 0.03, 0.05, alpha))
	return m


static func backdrop(alpha := 0.62) -> ColorRect:
	var r := ColorRect.new()
	r.material = blur_material(alpha)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r


## 面板标题栏：左边眉题 + 标题，右边"关闭"按钮
static func panel_head(kick: String, text: String, close_text: String, on_close: Callable) -> HBoxContainer:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	var t := header(kick, text)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := button("关闭  %s" % close_text, 16)
	close.size_flags_vertical = Control.SIZE_SHRINK_END
	close.pressed.connect(on_close)
	head.add_child(close)
	return head


## 图标：game-icons.net 的白色剪影（assets/icons），用 color 着色
const ICONS := "res://assets/icons/"


## 手机触屏时，把提示里的键盘按键换成触屏按钮的说法（先换"按住 X"再换"按 X"）
const TOUCH_KEYS := [
	["按住 G", "按住钩子键"], ["松开 G", "松开钩子键"], ["按 G", "点钩子键"], ["· G 收回", "· 点钩子键收回"],
	["按住 F", "按住交互键"], ["按 F", "点交互键"], ["按住 Shift", "按住屏息键"], ["按住 Tab", "按住菜单里的排名"],
	["按住 Q", "按住神通键"], ["按 K", "点菜单→灵相"], ["按 L", "点菜单→猎灵榜"], ["按 T", "点「丢」"],
	["按 H", "点回血键"], ["按 Esc", "点暂停键"], ["按 M", "点小地图"], ["按 B", "点菜单→换鱼饵"], ["按 R", "点换弹键"],
	["左键", "开火键"], ["右键", "开镜键"], ["空格", "跳跃键"],
]


static func keys(t: String) -> String:
	if not Settings.touch_active() or t == "":
		return t
	for k in TOUCH_KEYS:
		t = t.replace(k[0], k[1])
	return t


static func icon(name: String, size := 24.0, color := MOON) -> TextureRect:
	var t := TextureRect.new()
	if ResourceLoader.exists(ICONS + name + ".svg"):
		t.texture = load(ICONS + name + ".svg")
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(size, size)
	t.modulate = color
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## 神通的图标名（按神通类型）
static func skill_icon(sid: String) -> String:
	var t := str(Data.SKILLS.get(sid, {}).get("type", "buff"))
	t = {"blink": "dash", "grapple": "pull", "giant": "shield", "fly": "leap", "invis": "buff", "summon": "soul", "orbit": "launch", "chain": "beam", "blackhole": "pull", "domain": "mark", "empower": "buff"}.get(t, t)
	return t if ResourceLoader.exists(ICONS + t + ".svg") else "buff"


## 灵环颜色的小圆环
static func ring_dot(age: int, size := 18.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(size, size)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var col: Color = Data.AGES[clampi(age, 0, Data.AGES.size() - 1)]["glow"]
	c.draw.connect(func():
		var r := size * 0.5
		c.draw_circle(Vector2(r, r), r, Color(col.r, col.g, col.b, 0.25))
		c.draw_arc(Vector2(r, r), r - 2.0, 0.0, TAU, 32, col, 3.0, true))
	return c


## 键帽：小方框里写按键
static func keycap(k: String, size := 14) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(22, 22)
	var st := _flat(Color(0.06, 0.07, 0.1, 0.85), 6, 0, 3)
	st.border_color = Color(1, 1, 1, 0.4)
	st.set_border_width_all(1)
	st.border_width_bottom = 2
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := bold(k, size, MOON)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p


## 键帽 + 说明，横排（"[F] 救人"）
static func key_hint(k: String, text: String, size := 15, color := MOON) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 7)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(keycap(k, size - 2))
	h.add_child(label(text, size, color, 3))
	return h


## 图标 + 文字横排
static func icon_row(name: String, text: String, size := 18, color := MOON, icon_color := MOON) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(icon(name, size * 1.2, icon_color))
	var l := label(text, size, color, 3)
	l.name = "Text"
	h.add_child(l)
	return h


## 按钮。main = 金色主按钮（黑字），否则是透明底细边
static func button(text: String, size := 20, main := false) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_font_override("font", Data.font_bold)
	b.custom_minimum_size = Vector2(0, size * 2.1)
	var n := _flat(GOLD if main else Color(1, 1, 1, 0.05), 18, 4, 2)
	n.border_color = GOLD if main else Color(1, 1, 1, 0.16)
	n.set_border_width_all(1)
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(1.0, 0.86, 0.48) if main else Color(1, 1, 1, 0.12)
	h.border_color = Color(1.0, 0.92, 0.65) if main else Color(1, 1, 1, 0.4)
	var p := n.duplicate() as StyleBoxFlat
	p.bg_color = Color(0.88, 0.66, 0.2) if main else Color(1, 1, 1, 0.03)
	var d := n.duplicate() as StyleBoxFlat
	d.bg_color = Color(1, 1, 1, 0.03)
	d.border_color = Color(1, 1, 1, 0.06)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("disabled", d)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var fc := Color(0.1, 0.08, 0.03) if main else MOON
	b.add_theme_color_override("font_color", fc)
	b.add_theme_color_override("font_hover_color", fc)
	b.add_theme_color_override("font_pressed_color", fc)
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.48, 0.53))
	b.pressed.connect(func(): Sfx.play("ui_click", -8.0))
	return b


## 大号菜单项（主菜单、暂停）：左对齐大字，没有底；鼠标移上去左边出现金条、底变亮
static func menu_item(text: String, main := false, size := 30) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", Data.font_title)
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(0, size * 1.9)
	var n := _flat(Color(0, 0, 0, 0), 22, 2, 0)
	n.border_color = GOLD if main else Color(1, 1, 1, 0)
	n.border_width_left = 4
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(1, 1, 1, 0.07)
	h.border_color = GOLD
	var d := n.duplicate() as StyleBoxFlat
	d.border_color = Color(1, 1, 1, 0)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("disabled", d)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", GOLD if main else MOON)
	b.add_theme_color_override("font_hover_color", GOLD if main else Color.WHITE)
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.add_theme_color_override("font_disabled_color", DIM)
	b.pressed.connect(func(): Sfx.play("ui_click", -8.0))
	return b


## 可以点的卡片（神通二选一、渡船目的地）：整块是一个按钮，鼠标移上去边框变成 accent 色
static func card_button(accent: Color) -> Button:
	var b := Button.new()
	var n := card_style(Color(accent.r, accent.g, accent.b, 0.6), Color(0.05, 0.06, 0.085, 0.92))
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(0.08, 0.09, 0.12, 0.96)
	h.border_color = accent
	h.set_border_width_all(2)
	h.border_width_top = 3
	h.shadow_color = Color(accent.r, accent.g, accent.b, 0.25)
	h.shadow_size = 18
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(func(): Sfx.play("ui_click", -6.0))
	return b


# ------------------------------------------------------------------ 全局主题（输入框、滑条、勾选框、下拉框、滚动条、提示）

static func _dot_tex(r: int, col: Color, ring := Color(0, 0, 0, 0)) -> ImageTexture:
	var s := r * 2 + 2
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s, s) * 0.5
	for y in s:
		for x in s:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var a := clampf(r + 0.5 - d, 0.0, 1.0)
			var px := col
			if ring.a > 0.0 and d > r - 2.5:
				px = ring
			img.set_pixel(x, y, Color(px.r, px.g, px.b, px.a * a))
	return ImageTexture.create_from_image(img)


static func _box_tex(s: int, fill_c: Color, border: Color, inner := Color(0, 0, 0, 0)) -> ImageTexture:
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var edge := x < 2 or y < 2 or x >= s - 2 or y >= s - 2
			var core := x >= 6 and y >= 6 and x < s - 6 and y < s - 6
			var c := border if edge else fill_c
			if core and inner.a > 0.0:
				c = inner
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


static func make_theme() -> Theme:
	var th := Theme.new()
	# 按钮（没单独设样式的）
	var bn := _flat(Color(1, 1, 1, 0.05), 14, 4, 2)
	bn.border_color = Color(1, 1, 1, 0.16)
	bn.set_border_width_all(1)
	var bh := bn.duplicate() as StyleBoxFlat
	bh.bg_color = Color(1, 1, 1, 0.12)
	bh.border_color = Color(1, 1, 1, 0.4)
	for t in ["Button", "OptionButton"]:
		th.set_stylebox("normal", t, bn)
		th.set_stylebox("hover", t, bh)
		th.set_stylebox("pressed", t, bh)
		th.set_stylebox("focus", t, StyleBoxEmpty.new())
		th.set_stylebox("disabled", t, _flat(Color(1, 1, 1, 0.02), 14, 4, 2))
		th.set_color("font_color", t, MOON)
		th.set_color("font_hover_color", t, Color.WHITE)
		th.set_color("font_pressed_color", t, GOLD)
	# 输入框：暗底，下面一条线，选中时变金
	var le := _flat(Color(1, 1, 1, 0.05), 12, 6, 2)
	le.border_color = Color(1, 1, 1, 0.25)
	le.border_width_bottom = 2
	var lf := le.duplicate() as StyleBoxFlat
	lf.border_color = GOLD
	lf.bg_color = Color(1, 1, 1, 0.08)
	th.set_stylebox("normal", "LineEdit", le)
	th.set_stylebox("focus", "LineEdit", lf)
	th.set_stylebox("read_only", "LineEdit", le)
	th.set_color("font_color", "LineEdit", MOON)
	th.set_color("font_placeholder_color", "LineEdit", DIM)
	th.set_color("caret_color", "LineEdit", GOLD)
	th.set_color("selection_color", "LineEdit", Color(GOLD.r, GOLD.g, GOLD.b, 0.35))
	# 滑条：细轨道，走过的部分金色，圆形把手
	var track := _flat(Color(1, 1, 1, 0.14), 0, 2, 2)
	var done := _flat(GOLD, 0, 2, 2)
	th.set_stylebox("slider", "HSlider", track)
	th.set_stylebox("grabber_area", "HSlider", done)
	th.set_stylebox("grabber_area_highlight", "HSlider", done)
	th.set_icon("grabber", "HSlider", _dot_tex(8, MOON, GOLD))
	th.set_icon("grabber_highlight", "HSlider", _dot_tex(9, Color.WHITE, GOLD))
	# 勾选框
	var off := _box_tex(22, Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.45))
	var on := _box_tex(22, Color(GOLD.r, GOLD.g, GOLD.b, 0.25), GOLD, GOLD)
	for t in ["CheckBox", "CheckButton"]:
		th.set_icon("unchecked", t, off)
		th.set_icon("checked", t, on)
		th.set_color("font_color", t, MOON)
		th.set_color("font_hover_color", t, Color.WHITE)
		th.set_color("font_pressed_color", t, MOON)
		th.set_color("font_hover_pressed_color", t, Color.WHITE)
		th.set_stylebox("normal", t, _flat(Color(0, 0, 0, 0), 4, 4, 2))
		th.set_stylebox("hover", t, _flat(Color(1, 1, 1, 0.05), 4, 4, 2))
		th.set_stylebox("pressed", t, _flat(Color(0, 0, 0, 0), 4, 4, 2))
		th.set_stylebox("hover_pressed", t, _flat(Color(1, 1, 1, 0.05), 4, 4, 2))
		th.set_stylebox("focus", t, StyleBoxEmpty.new())
		th.set_constant("h_separation", t, 12)
	# 下拉菜单
	var pm := _flat(Color(0.06, 0.07, 0.1, 0.98), 6, 6, 2)
	pm.border_color = LINE
	pm.set_border_width_all(1)
	th.set_stylebox("panel", "PopupMenu", pm)
	th.set_stylebox("hover", "PopupMenu", _flat(Color(GOLD.r, GOLD.g, GOLD.b, 0.22), 8, 4, 2))
	th.set_color("font_color", "PopupMenu", MOON)
	th.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	th.set_font_size("font_size", "PopupMenu", 17)
	# 滚动条：细
	for t in ["VScrollBar", "HScrollBar"]:
		var sc := _flat(Color(1, 1, 1, 0.05), 3, 3, 3)
		th.set_stylebox("scroll", t, sc)
		th.set_stylebox("scroll_focus", t, sc)
		th.set_stylebox("grabber", t, _flat(Color(1, 1, 1, 0.25), 3, 3, 3))
		th.set_stylebox("grabber_highlight", t, _flat(Color(1, 1, 1, 0.45), 3, 3, 3))
		th.set_stylebox("grabber_pressed", t, _flat(GOLD, 3, 3, 3))
	# 鼠标提示
	var tp := _flat(Color(0.05, 0.06, 0.09, 0.96), 10, 6, 2)
	tp.border_color = LINE
	tp.set_border_width_all(1)
	th.set_stylebox("panel", "TooltipPanel", tp)
	th.set_color("font_color", "TooltipLabel", MOON)
	return th
