class_name UiKit
extends RefCounted
## 界面的统一样式：墨绿底、金色强调，和之前"斗罗猎魂"一个色调。

const BG := Color(0.07, 0.19, 0.17, 0.92)
const PANEL := Color(0.09, 0.24, 0.21, 0.95)
const LINE := Color(0.18, 0.36, 0.32)
const GOLD := Color(0.91, 0.77, 0.4)
const JADE := Color(0.49, 0.76, 0.66)
const MOON := Color(0.91, 0.94, 0.91)
const MIST := Color(0.66, 0.74, 0.71)


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
	s.set_corner_radius_all(10)
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 18
	s.content_margin_bottom = 18
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 12
	return s


static func label(text: String, size := 20, color := MOON, outline := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	return l


static func title(text: String, size := 48, color := MOON) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", Data.font_title)
	return l


static func button(text: String, size := 22, main := false) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(0, size * 2.2)
	var n := StyleBoxFlat.new()
	n.bg_color = GOLD if main else Color(0.11, 0.27, 0.24)
	n.border_color = GOLD if main else LINE
	n.set_border_width_all(1)
	n.set_corner_radius_all(8)
	n.content_margin_left = 16
	n.content_margin_right = 16
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(0.94, 0.82, 0.49) if main else Color(0.14, 0.33, 0.29)
	var p := n.duplicate() as StyleBoxFlat
	p.bg_color = Color(0.8, 0.66, 0.3) if main else Color(0.08, 0.2, 0.18)
	var d := n.duplicate() as StyleBoxFlat
	d.bg_color = Color(0.2, 0.25, 0.24)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("disabled", d)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var fc := Color(0.17, 0.14, 0.05) if main else MOON
	b.add_theme_color_override("font_color", fc)
	b.add_theme_color_override("font_hover_color", fc)
	b.add_theme_color_override("font_pressed_color", fc)
	b.pressed.connect(func(): Sfx.play("ui_click", -8.0))
	return b
