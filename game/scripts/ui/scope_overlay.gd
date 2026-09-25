class_name ScopeOverlay
extends Control
## 追魂穿心弩的铜瞄镜：圆形视野外面全黑，中间十字和刻度。


func _process(_dt: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.44
	var big := size.length()
	# 用一圈很粗的黑环盖住圆外面
	draw_arc(c, r + big * 0.5, 0, TAU, 96, Color(0, 0, 0, 1), big, true)
	# 镜筒边缘的铜色和暗角
	draw_arc(c, r + 3, 0, TAU, 96, Color(0.55, 0.38, 0.2), 6.0, true)
	for k in 6:
		draw_arc(c, r - k * 6.0, 0, TAU, 96, Color(0, 0, 0, 0.12 - k * 0.018), 6.0, true)
	var line := Color(0.05, 0.05, 0.05, 0.9)
	draw_line(c + Vector2(-r, 0), c + Vector2(-14, 0), line, 2.0)
	draw_line(c + Vector2(14, 0), c + Vector2(r, 0), line, 2.0)
	draw_line(c + Vector2(0, -r), c + Vector2(0, -14), line, 2.0)
	draw_line(c + Vector2(0, 14), c + Vector2(0, r), line, 2.0)
	# 粗的外段
	draw_line(c + Vector2(-r, 0), c + Vector2(-r * 0.55, 0), line, 5.0)
	draw_line(c + Vector2(r * 0.55, 0), c + Vector2(r, 0), line, 5.0)
	draw_line(c + Vector2(0, r * 0.55), c + Vector2(0, r), line, 5.0)
	for k in range(1, 6):
		var d := k * r * 0.09
		draw_line(c + Vector2(-5, d), c + Vector2(5, d), line, 1.5)
		draw_line(c + Vector2(d, -4), c + Vector2(d, 4), line, 1.5)
		draw_line(c + Vector2(-d, -4), c + Vector2(-d, 4), line, 1.5)
	draw_circle(c, 2.0, Color(0.9, 0.15, 0.1))
	var hint := "按住 Shift 屏息"
	draw_string(Data.font_ui, c + Vector2(-80, r * 0.72), hint, HORIZONTAL_ALIGNMENT_CENTER, 160, 16, Color(1, 1, 1, 0.5))
