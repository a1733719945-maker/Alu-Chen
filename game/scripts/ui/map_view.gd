class_name MapView
extends Control
## 地图：右上角的小地图（跟着自己走），按 M 打开的大地图（整张图）。
## 标出：自己（箭头）、队友、暗器铺、收购箱、祭坛、渡船、Boss、精英灵兽、灵环、任务目标；大地图还写栖息地名字。
## 地形图用 Island.heights 画一张图，画成水墨舆图（国风）：宣纸底，陆地越高墨越浓、每 3 米一道等高线，
## 海岸一道浓墨，水面一层淡青的晕染加细细的波纹；小路是朱砂虚线；地点是朱红圆印。北（-Z）朝上。

var world: Node
var big := false
var _tex: ImageTexture
var _zoom := 1.6          # 小地图：1 米 = 多少像素


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_texture()


const PAPER := Color(0.9, 0.86, 0.76)
const INK := Color(0.1, 0.09, 0.08)
const WASH := Color(0.55, 0.64, 0.66)
const CINNABAR := Color(0.72, 0.14, 0.09)


func _build_texture() -> void:
	var isl: Island = world.island
	var n: int = isl.size
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	# 每张图纸色略有不同（雪原更白、归墟偏青、林子偏黄绿）
	var paper := PAPER
	match str(isl.map_id):
		"forest":
			paper = Color(0.9, 0.84, 0.7)
		"deepforest":
			paper = Color(0.84, 0.84, 0.72)
		"snow":
			paper = Color(0.94, 0.93, 0.9)
		"sea":
			paper = Color(0.86, 0.87, 0.8)
	var w := Island.WATER_Y + 0.25
	var hs: PackedFloat32Array = isl.heights
	for j in n:
		for i in n:
			var h: float = hs[i + j * n]
			var hr: float = hs[mini(i + 1, n - 1) + j * n]
			var hd: float = hs[i + mini(j + 1, n - 1) * n]
			var c: Color
			# 纸上一点点纤维的深浅
			var grain := (sin(i * 12.9898 + j * 78.233) * 43758.5453)
			grain = (grain - floor(grain)) * 0.035
			if h < w:
				var depth := clampf((w - h) / 10.0, 0.0, 1.0)
				c = paper.lerp(WASH, 0.35 + depth * 0.45)
				# 细细的波纹（斜的淡线）
				if fmod(float(i + j * 2) + sin(j * 0.21) * 3.0, 9.0) < 1.0:
					c = c.darkened(0.08)
			else:
				var k := clampf((h - 1.0) / 22.0, 0.0, 1.0)
				c = paper.lerp(INK, k * 0.55)
				# 等高线：每 3 米一道
				if floori(h / 3.0) != floori(hr / 3.0) or floori(h / 3.0) != floori(hd / 3.0):
					c = c.lerp(INK, 0.3)
			# 海岸：一道浓墨
			if (h < w) != (hr < w) or (h < w) != (hd < w):
				c = INK.lerp(paper, 0.15)
			img.set_pixel(i, j, c.darkened(grain))
	# 小路：朱砂虚线
	for p in isl.paths:
		for k in p.size():
			if k % 4 >= 2:
				continue
			var q: Vector2 = p[k]
			var x := int(q.x) + isl.half
			var y := int(q.y) + isl.half
			if x >= 0 and y >= 0 and x < n and y < n:
				img.set_pixel(x, y, CINNABAR.lerp(img.get_pixel(x, y), 0.35))
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
		scale = minf(size.x, size.y) / float(world.island.size)
		center = Vector2.ZERO
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.055, 0.05, 0.94))
	else:
		scale = _zoom
		center = mp
	# 地形
	var hf: int = world.island.half
	var tl := size * 0.5 + (Vector2(-hf, -hf) - center) * scale
	var rect := Rect2(tl, Vector2(world.island.size, world.island.size) * scale)
	if not big:
		draw_rect(Rect2(Vector2.ZERO, size), PAPER.lerp(WASH, 0.75))
	draw_texture_rect(_tex, rect, false)
	var font: Font = Data.font_bold
	# 大地图：栖息地名字
	if big:
		for h in world.island.habitats:
			var type := str(h["type"])
			if Data.HABITATS.has(type):
				var c: Vector2 = h["center"]
				var at := _to_px(Vector3(c.x, 0, c.y), center, scale)
				var nm := str(h.get("label", Data.HABITATS[type]["name"]))
				draw_string_outline(Data.font_serif, at + Vector2(-60, 0), nm, HORIZONTAL_ALIGNMENT_CENTER, 120, 15, 4, Color(PAPER.r, PAPER.g, PAPER.b, 0.7))
				draw_string(Data.font_serif, at + Vector2(-60, 0), nm, HORIZONTAL_ALIGNMENT_CENTER, 120, 15, Color(INK.r, INK.g, INK.b, 0.85))
	# 地点
	if world.island.hunting:
		# 猎场：营地、找到过的宝藏（没找到的不标）
		_poi(world.builder.camp_pos, "营", Color(1.0, 0.8, 0.3), center, scale, font, "营地（补给）")
		if world.trip:
			for tp in world.trip.found_list():
				_dot(tp, Color(1.0, 0.85, 0.35), 3.5, center, scale)
			# 灵兽王守着的大宝箱（王倒下了变成"箱"）
			for gm in world.trip.guard_marks():
				_poi(gm[0], str(gm[1]), gm[2], center, scale, font, str(gm[3]) if big else "")
	else:
		_poi(world.builder.shop_door, "铺", Color(1.0, 0.8, 0.3), center, scale, font, "千机阁暗器铺")
	if world.loot and not world.island.hunting:
		_poi(world.loot.box_pos, "收", Color(1.0, 0.65, 0.25), center, scale, font, "收购箱")
	if not world.island.hunting:
		_poi(world.island.altar_pos, "坛", Color(1.0, 0.4, 0.35), center, scale, font, "祭坛")
	if int(Data.CHAPTERS[world.chapter].get("next", 0)) > 0 and not world.island.hunting:
		_poi(world.builder.boat_pos, "船", Color(0.6, 0.85, 1.0), center, scale, font, "渡船")
	for rid in world.rings:
		_dot(world.rings[rid]["pos"], Data.age_color(int(world.rings[rid]["age"])), 5.0, center, scale)
	for b: Beast in world.beasts.values():
		# 猎灵榜的猎物不标在地图上（要跟着踪迹找）；猎场里守宝的王按守宝点标（上面）
		if b.alive() and b.temper == "elite" and b.hunt_role == "" and not world.island.hunting:
			_poi(b.global_position, "王", Color(1.0, 0.55, 0.15), center, scale, font, b.display_name() if big else "")
	if world.dungeon:
		for p in world.dungeon.portals:
			var t := int(p["tier"])
			_poi(p["pos"], "秘", Data.AGES[world.dungeon.tier_age(t)]["glow"], center, scale, font, world.dungeon.tier_name(t) if big else "")
	if world.builder.board_pos != Vector3.ZERO and not world.island.hunting:
		_poi(world.builder.board_pos, "榜", Color(1.0, 0.78, 0.5), center, scale, font, "猎灵榜" if big else "")
	if world.trial and world.trial.stele != Vector3.INF:
		_poi(world.trial.stele, "试", Color(0.5, 1.0, 0.6), center, scale, font, "试炼碑" if big else "")
	if world.nests:
		for nid in world.nests.nests:
			var ne: Dictionary = world.nests.nests[nid]
			if ne["alive"]:
				_poi(ne["pos"], "巢", Color(0.8, 0.45, 1.0), center, scale, font, "灵兽巢穴")
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
	var arrow := PackedVector2Array([pp + fwd * 11.0, pp - fwd * 6.0 + side * 7.0, pp - fwd * 3.0, pp - fwd * 6.0 - side * 7.0])
	draw_colored_polygon(PackedVector2Array([pp + fwd * 14.0, pp - fwd * 8.0 + side * 9.0, pp - fwd * 4.0, pp - fwd * 8.0 - side * 9.0]), Color(PAPER.r, PAPER.g, PAPER.b, 0.9))
	draw_colored_polygon(arrow, CINNABAR)
	# 边框：描金细线 + 四个角加粗（像画轴的包边）
	draw_rect(Rect2(Vector2.ZERO, size), Color(UiKit.GOLD.r, UiKit.GOLD.g, UiKit.GOLD.b, 0.35), false, 1.0)
	var cl := 14.0
	for c in [Vector2.ZERO, Vector2(size.x, 0), Vector2(0, size.y), size]:
		var sx := 1.0 if c.x == 0.0 else -1.0
		var sy := 1.0 if c.y == 0.0 else -1.0
		draw_line(c, c + Vector2(cl * sx, 0), UiKit.GOLD, 2.0)
		draw_line(c, c + Vector2(0, cl * sy), UiKit.GOLD, 2.0)
	if big:
		# 左上：章节；右上：关闭；底下一排图例
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, 44)), Color(0.02, 0.03, 0.05, 0.75))
		draw_string(font, Vector2(18, 29), str(Data.CHAPTERS[world.chapter]["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UiKit.GOLD)
		draw_string(font, Vector2(size.x - 110, 28), "M 关闭", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiKit.MIST)
		draw_rect(Rect2(Vector2(0, size.y - 40), Vector2(size.x, 40)), Color(0.02, 0.03, 0.05, 0.75))
		var x := 18.0
		var legend: Array = [["营", "营地（补给 · 旗子）", Color(1.0, 0.8, 0.3)], ["守", "守宝的灵兽王", Color(1.0, 0.55, 0.15)], ["箱", "大宝箱（能开了）", Color(1.0, 0.85, 0.35)]] if world.island.hunting else \
			[["铺", "暗器铺", Color(1.0, 0.8, 0.3)], ["收", "收购箱", Color(1.0, 0.65, 0.25)], ["坛", "祭坛", Color(1.0, 0.4, 0.35)], ["船", "渡船", Color(0.6, 0.85, 1.0)], ["王", "灵兽王", Color(1.0, 0.55, 0.15)], ["巢", "巢穴", Color(0.8, 0.45, 1.0)], ["主", "Boss", Color(1.0, 0.25, 0.3)]]
		for it in legend:
			var q := Vector2(x + 9, size.y - 20)
			draw_circle(q, 9.0, (it[2] as Color).darkened(0.35))
			draw_arc(q, 9.0, 0.0, TAU, 20, Color(1, 1, 1, 0.5), 1.0, true)
			draw_string(font, q + Vector2(-9, 4), str(it[0]), HORIZONTAL_ALIGNMENT_CENTER, 18, 11, Color.WHITE)
			draw_string(font, q + Vector2(14, 5), str(it[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiKit.MOON)
			x += 30.0 + font.get_string_size(str(it[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 16.0
		var dq := Vector2(x + 6, size.y - 20)
		draw_colored_polygon(PackedVector2Array([dq + Vector2(0, -7), dq + Vector2(6, 0), dq + Vector2(0, 7), dq + Vector2(-6, 0)]), UiKit.GOLD)
		draw_string(font, dq + Vector2(12, 5), "任务目标", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiKit.MOON)
	else:
		draw_string(Data.font_serif, Vector2(size.x * 0.5 - 7, 16), "北", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK)
		draw_string(font, Vector2(8, size.y - 8), "M", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(INK.r, INK.g, INK.b, 0.6))


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
	# 方形的印：底色按种类（暗一点，像盖在纸上的印泥），宋体字
	var rc := Rect2(q - Vector2(r, r), Vector2(r, r) * 2.0)
	draw_rect(rc.grow(1.5), Color(PAPER.r, PAPER.g, PAPER.b, 0.85))
	draw_rect(rc, col.darkened(0.45))
	draw_rect(rc.grow(-2.0), Color(1.0, 0.95, 0.85, 0.35), false, 1.0)
	draw_string(Data.font_serif, q + Vector2(-r, r * 0.45), ch, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, int(r * 1.25), Color(1.0, 0.96, 0.88))
	if big and label != "":
		draw_string_outline(Data.font_serif, q + Vector2(-70, r + 17), label, HORIZONTAL_ALIGNMENT_CENTER, 140, 14, 4, Color(PAPER.r, PAPER.g, PAPER.b, 0.8))
		draw_string(Data.font_serif, q + Vector2(-70, r + 17), label, HORIZONTAL_ALIGNMENT_CENTER, 140, 14, col.darkened(0.5))
