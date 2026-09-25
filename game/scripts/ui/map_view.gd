class_name MapView
extends Control
## 地图：右上角的小地图（跟着自己走），按 M 打开的大地图（整张图）。
## 标出：自己（箭头）、队友、暗器铺、收购箱、祭坛、渡船、Boss、精英魂兽、魂环、任务目标；大地图还写栖息地名字。
## 地形图用 Island.heights 画一张图：水按深浅、陆地按高低上色。北（-Z）朝上。

var world: Node
var big := false
var _tex: ImageTexture
var _zoom := 1.6          # 小地图：1 米 = 多少像素


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_texture()


func _build_texture() -> void:
	var isl: Island = world.island
	var n := Island.SIZE
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var biome := str(isl.map_id)
	var low := Color(0.36, 0.5, 0.28)
	var high := Color(0.62, 0.62, 0.5)
	match biome:
		"forest":
			low = Color(0.3, 0.38, 0.2)
			high = Color(0.5, 0.42, 0.3)
		"deepforest":
			low = Color(0.14, 0.26, 0.22)
			high = Color(0.3, 0.34, 0.36)
		"snow":
			low = Color(0.78, 0.82, 0.86)
			high = Color(0.95, 0.96, 0.98)
		"sea":
			low = Color(0.82, 0.74, 0.5)
			high = Color(0.45, 0.58, 0.35)
	for j in n:
		for i in n:
			var h: float = isl.heights[i + j * n]
			var c: Color
			if h < Island.WATER_Y + 0.25:
				var depth := clampf((Island.WATER_Y - h) / 10.0, 0.0, 1.0)
				c = Color(0.35, 0.62, 0.78).lerp(Color(0.06, 0.18, 0.34), depth)
			else:
				c = low.lerp(high, clampf((h - 1.0) / 16.0, 0.0, 1.0))
			img.set_pixel(i, j, c)
	# 小路画浅一点
	for p in isl.paths:
		for k in p.size():
			var q: Vector2 = p[k]
			var x := int(q.x) + Island.HALF
			var y := int(q.y) + Island.HALF
			if x >= 0 and y >= 0 and x < n and y < n:
				img.set_pixel(x, y, img.get_pixel(x, y).lightened(0.3))
	_tex = ImageTexture.create_from_image(img)


func _process(_dt: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


## 世界坐标 → 这个控件里的像素
func _to_px(p: Vector3, center: Vector2, scale: float) -> Vector2:
	return size * 0.5 + (Vector2(p.x, p.z) - center) * scale


func _draw() -> void:
	if not _tex or not world or not world.player:
		return
	var me: Player = world.player
	var mp := Vector2(me.global_position.x, me.global_position.z)
	var scale: float
	var center: Vector2
	if big:
		scale = minf(size.x, size.y) / float(Island.SIZE)
		center = Vector2.ZERO
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
	else:
		scale = _zoom
		center = mp
	# 地形
	var tl := size * 0.5 + (Vector2(-Island.HALF, -Island.HALF) - center) * scale
	var rect := Rect2(tl, Vector2(Island.SIZE, Island.SIZE) * scale)
	if not big:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.15, 0.28))
	draw_texture_rect(_tex, rect, false)
	var font: Font = Data.font_bold
	# 大地图：栖息地名字
	if big:
		for h in world.island.habitats:
			var type := str(h["type"])
			if Data.HABITATS.has(type):
				var c: Vector2 = h["center"]
				var at := _to_px(Vector3(c.x, 0, c.y), center, scale)
				draw_string(font, at + Vector2(-40, 0), str(Data.HABITATS[type]["name"]), HORIZONTAL_ALIGNMENT_CENTER, 80, 14, Color(1, 1, 1, 0.75))
	# 地点
	_poi(world.builder.shop_door, "铺", Color(1.0, 0.8, 0.3), center, scale, font, "唐门暗器铺")
	if world.loot:
		_poi(world.loot.box_pos, "收", Color(1.0, 0.65, 0.25), center, scale, font, "收购箱")
	_poi(world.island.altar_pos, "坛", Color(1.0, 0.4, 0.35), center, scale, font, "祭坛")
	if int(Data.CHAPTERS[world.chapter].get("next", 0)) > 0:
		_poi(world.builder.boat_pos, "船", Color(0.6, 0.85, 1.0), center, scale, font, "渡船")
	for rid in world.rings:
		_dot(world.rings[rid]["pos"], Data.age_color(int(world.rings[rid]["age"])), 5.0, center, scale)
	for b: Beast in world.beasts.values():
		if b.alive() and b.temper == "elite":
			_poi(b.global_position, "王", Color(1.0, 0.55, 0.15), center, scale, font, b.display_name() if big else "")
	if world.boss and not world.boss.dead:
		_poi(world.boss.center(), "主", Color(1.0, 0.25, 0.3), center, scale, font, "Boss")
	var qt: Variant = world.hud._quest_target()
	if qt != null:
		var qp := _to_px(qt, center, scale)
		qp = _clamp_edge(qp)
		draw_colored_polygon(PackedVector2Array([qp + Vector2(0, -8), qp + Vector2(6, 0), qp + Vector2(0, 8), qp + Vector2(-6, 0)]), UiKit.GOLD)
	# 队友
	for id in world.remotes:
		var r: RemotePlayer = world.remotes[id]
		var rp := _clamp_edge(_to_px(r.global_position, center, scale))
		var col := Color(1, 0.4, 0.35) if r.is_dead() else Color(0.45, 0.8, 1.0)
		draw_circle(rp, 6.0, Color(0, 0, 0, 0.6))
		draw_circle(rp, 4.5, col)
		draw_string(font, rp + Vector2(-50, -10), world.peer_name(id) + ("（倒地）" if r.is_dead() else ""), HORIZONTAL_ALIGNMENT_CENTER, 100, 13 if not big else 15, col)
	# 自己：箭头，尖朝面对的方向
	var pp := _to_px(me.global_position, center, scale)
	var fwd := Vector2(-sin(me.yaw), -cos(me.yaw))
	var side := Vector2(-fwd.y, fwd.x)
	draw_colored_polygon(PackedVector2Array([pp + fwd * 10.0, pp - fwd * 6.0 + side * 6.0, pp - fwd * 3.0, pp - fwd * 6.0 - side * 6.0]), Color(1, 1, 1))
	# 边框
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.35), false, 2.0)
	if big:
		draw_string(font, Vector2(16, 30), "地图（M 关闭）   铺 暗器铺  收 收购箱  坛 祭坛  船 渡船  王 精英魂兽  主 Boss  ◆ 任务目标  蓝点 队友", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.MOON)
	else:
		draw_string(font, Vector2(8, size.y - 8), "M 大地图", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6))


## 小地图上超出范围的点贴在边上
func _clamp_edge(p: Vector2) -> Vector2:
	if big:
		return p
	return Vector2(clampf(p.x, 6.0, size.x - 6.0), clampf(p.y, 6.0, size.y - 6.0))


func _dot(p: Vector3, col: Color, r: float, center: Vector2, scale: float) -> void:
	var q := _clamp_edge(_to_px(p, center, scale))
	draw_circle(q, r + 1.5, Color(0, 0, 0, 0.6))
	draw_circle(q, r, col)


func _poi(p: Vector3, ch: String, col: Color, center: Vector2, scale: float, font: Font, label: String) -> void:
	var q := _clamp_edge(_to_px(p, center, scale))
	var r := 10.0 if big else 8.0
	draw_circle(q, r + 1.5, Color(0, 0, 0, 0.7))
	draw_circle(q, r, col.darkened(0.35))
	draw_string(font, q + Vector2(-r, r * 0.5), ch, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, int(r * 1.3), Color(1, 1, 1))
	if big and label != "":
		draw_string(font, q + Vector2(-60, r + 16), label, HORIZONTAL_ALIGNMENT_CENTER, 120, 14, col)
