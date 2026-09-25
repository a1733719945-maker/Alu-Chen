class_name Crosshair
extends Control
## 准星：四条线的间距跟着散布变化；命中时出现 ✕（爆头黄色、击杀红色）。

var player: Player
var _hit_t := 0.0
var _hit_kind := 0     # 0 普通 1 爆头 2 击杀


func hit(headshot: bool, kill: bool) -> void:
	if kill:
		_hit_kind = 2
		_hit_t = 0.4
	elif _hit_kind != 2 or _hit_t <= 0.0:
		# 击杀标记还在显示时，普通命中不覆盖它
		_hit_kind = 1 if headshot else 0
		_hit_t = 0.22


func _process(dt: float) -> void:
	_hit_t = maxf(_hit_t - dt, 0.0)
	if _hit_t <= 0.0:
		_hit_kind = 0
	queue_redraw()


func _draw() -> void:
	if not player:
		return
	var c := size * 0.5
	var col := Color(1, 1, 1, 0.92)
	var shadow := Color(0, 0, 0, 0.55)
	var vh := get_viewport_rect().size.y
	var spread := deg_to_rad(player.current_spread())
	var fov := deg_to_rad(player.cam.fov)
	var gap := tan(spread) / tan(fov * 0.5) * vh * 0.5 + 4.0
	var len := 9.0
	var ads := player.ads
	var line_a := 1.0 - ads * 0.85
	if player.lure.state == Lure.S.CHARGING:
		# 蓄力圈
		var k := clampf(player.lure.charge / float(Data.LURE["charge_time"]), 0.0, 1.0)
		draw_arc(c, 22.0, -PI / 2, -PI / 2 + TAU * k, 48, Color(0.55, 0.85, 1.0, 0.95), 4.0, true)
	if line_a > 0.05:
		var cl := Color(col.r, col.g, col.b, col.a * line_a)
		var sl := Color(0, 0, 0, shadow.a * line_a)
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			var a: Vector2 = c + d * gap
			var b: Vector2 = c + d * (gap + len)
			draw_line(a + Vector2(1, 1), b + Vector2(1, 1), sl, 2.0)
			draw_line(a, b, cl, 2.0)
	draw_circle(c + Vector2(0.5, 0.5), 2.2, shadow)
	draw_circle(c, 1.6, col)
	if _hit_t > 0.0:
		var hc := Color(1, 1, 1)
		if _hit_kind == 1:
			hc = Color(1.0, 0.85, 0.25)
		elif _hit_kind == 2:
			hc = Color(1.0, 0.3, 0.25)
		var t := _hit_t / (0.22 if _hit_kind != 2 else 0.4)
		var s := 6.0 + (1.0 - t) * 4.0 + (4.0 if _hit_kind == 2 else 0.0)
		var inner := 5.0
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var dn: Vector2 = d.normalized()
			draw_line(c + dn * inner, c + dn * (inner + s), Color(hc.r, hc.g, hc.b, t), 3.0 if _hit_kind == 2 else 2.2, true)
