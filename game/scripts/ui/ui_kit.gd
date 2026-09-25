class_name UiKit
extends RefCounted
## 界面的统一样式：深蓝灰半透明面板、细边框，金色是主操作，青色是次要强调。
## 字体：标题思源黑体 Black，正文 Medium，数字 Barlow Condensed。

const BG := Color(0.035, 0.045, 0.065, 0.9)
const PANEL := Color(0.05, 0.065, 0.09, 0.9)
const ROW := Color(1, 1, 1, 0.04)
const LINE := Color(1, 1, 1, 0.1)
const GOLD := Color(1.0, 0.78, 0.3)
const JADE := Color(0.4, 0.8, 1.0)
const MOON := Color(0.95, 0.96, 0.98)
const MIST := Color(0.62, 0.67, 0.75)


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


static func panel_style(color := PANEL) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = LINE
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	s.content_margin_left = 24
	s.content_margin_right = 24
	s.content_margin_top = 20
	s.content_margin_bottom = 20
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 18
	return s


## 列表里的一行（商店、魂环）
static func row_style(border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = ROW
	st.set_corner_radius_all(4)
	st.content_margin_left = 16
	st.content_margin_right = 16
	st.content_margin_top = 10
	st.content_margin_bottom = 10
	if border.a > 0.0:
		st.border_color = border
		st.border_width_left = 3
	return st


static func label(text: String, size := 20, color := MOON, outline := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	return l


static func bold(text: String, size := 20, color := MOON, outline := 0) -> Label:
	var l := label(text, size, color, outline)
	l.add_theme_font_override("font", Data.font_bold)
	return l


static func title(text: String, size := 48, color := MOON) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", Data.font_title)
	return l


## 大数字（弹药、金魂币）：窄体
static func num(text: String, size := 40, color := MOON, outline := 6) -> Label:
	var l := label(text, size, color, outline)
	l.add_theme_font_override("font", Data.font_num)
	return l


static func button(text: String, size := 22, main := false) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_font_override("font", Data.font_bold)
	b.custom_minimum_size = Vector2(0, size * 2.2)
	var n := StyleBoxFlat.new()
	n.bg_color = GOLD if main else Color(1, 1, 1, 0.06)
	n.border_color = GOLD if main else Color(1, 1, 1, 0.14)
	n.set_border_width_all(1)
	n.set_corner_radius_all(4)
	n.content_margin_left = 18
	n.content_margin_right = 18
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(1.0, 0.85, 0.45) if main else Color(1, 1, 1, 0.12)
	h.border_color = Color(1.0, 0.9, 0.6) if main else Color(1, 1, 1, 0.3)
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
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.53, 0.58))
	b.pressed.connect(func(): Sfx.play("ui_click", -8.0))
	return b
