class_name ScopeOverlay
extends Control
## 全屏瞄准镜（像 CS / How to Fish 的狙击镜）：圆形视野外面全黑，中间细十字和密位点。
## 开镜时手里的暗器藏起来，画面整体按倍率放大，所以里外不会一边大一边小（画中画会晕）。
## kind："scope" 狙击镜（细十字 + 密位），"x2" 2 倍镜（琥珀色箭头准星）

var kind := "scope"
var zoom := 6.0
var fade := 1.0          # 刚开镜时从黑到亮（0 → 1）


func _process(_dt: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * (0.46 if kind == "scope" else 0.4)
	var big := size.length()
	# 用一圈很粗的黑环盖住圆外面
	draw_arc(c, r + big * 0.5, 0, TAU, 128, Color(0.01, 0.01, 0.012, 1), big, true)
	# 镜筒内壁：一圈渐变暗角，边缘有一点点色散
	for k in 10:
		draw_arc(c, r - k * 4.0, 0, TAU, 128, Color(0, 0, 0, 0.3 - k * 0.03), 4.0, true)
	draw_arc(c, r + 1.0, 0, TAU, 128, Color(0.25, 0.3, 0.35, 0.35), 2.0, true)
	if fade < 1.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 1.0 - fade))
	if kind == "x2":
		_draw_acog(c, r)
		return
	var line := Color(0.02, 0.02, 0.02, 0.95)
	# 细十字 + 外段粗线
	draw_line(c + Vector2(-r, 0), c + Vector2(-10, 0), line, 1.4, true)
	draw_line(c + Vector2(10, 0), c + Vector2(r, 0), line, 1.4, true)
	draw_line(c + Vector2(0, -r), c + Vector2(0, -10), line, 1.4, true)
	draw_line(c + Vector2(0, 10), c + Vector2(0, r), line, 1.4, true)
	for s in [-1.0, 1.0]:
		draw_line(c + Vector2(r * s, 0), c + Vector2(r * 0.6 * s, 0), line, 6.0)
		draw_line(c + Vector2(0, r * s), c + Vector2(0, r * 0.6 * s), line, 6.0)
	# 密位点（上下左右各 4 个）
	for k in range(1, 5):
		var d := k * r * 0.12
		for v in [Vector2(d, 0), Vector2(-d, 0), Vector2(0, d), Vector2(0, -d)]:
			draw_circle(c + v, 2.2, line)
	# 中心红点（很小，不挡目标）
	draw_circle(c, 1.8, Color(1.0, 0.18, 0.1))
	draw_string(Data.font_ui, c + Vector2(r * 0.55, r * 0.78), "%.1fx" % zoom, HORIZONTAL_ALIGNMENT_LEFT, 80, 18, Color(1, 1, 1, 0.55))
	draw_string(Data.font_ui, c + Vector2(-140, r * 0.9), "滚轮调倍率 · 按住 Shift 屏息", HORIZONTAL_ALIGNMENT_CENTER, 280, 15, Color(1, 1, 1, 0.4))


## 2 倍镜：琥珀色倒 V 箭头 + 下面一根竖线
func _draw_acog(c: Vector2, r: float) -> void:
	var amber := Color(1.0, 0.62, 0.12, 0.95)
	var s := r * 0.06
	draw_polyline(PackedVector2Array([c + Vector2(-s, s * 0.9), c, c + Vector2(s, s * 0.9)]), amber, 2.5, true)
	draw_line(c + Vector2(0, s * 1.4), c + Vector2(0, r * 0.45), Color(0.05, 0.05, 0.05, 0.9), 2.0, true)
	for k in range(1, 4):
		var y := s * 1.4 + k * r * 0.1
		draw_line(c + Vector2(-s * (1.0 - k * 0.2), y), c + Vector2(s * (1.0 - k * 0.2), y), Color(0.05, 0.05, 0.05, 0.9), 1.5, true)
	draw_circle(c, 1.6, amber)
