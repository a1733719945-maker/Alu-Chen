class_name BossArts
extends Node
## Boss 的招式零件（第十三版。用户："最后的 Boss 和第一个用的技能一样、特效也一样，完全就是数值；
## 借鉴鬼泣，每个 Boss 好几个机制，最牛的操作加一点运气能无伤过，特效要炫"）。
##
## 房主算好发 "ba" 消息，每台电脑自己画预警和特效、自己判断打没打到自己
## （翻滚的无敌时间能躲；刚好躲过去算"极限闪避"，见 Player.take_damage）。
##   lane   直线带：冲锋、俯冲、吐息。预警条从起点往前填满，然后一道冲击沿着走过去（travel > 0）或者一下全砸（travel = 0）
##   sweep  旋转扫射：从一边扫到另一边的毒雾 / 冰息 / 光束。贴地的能跳过去，也能翻滚穿过去
##   rain   弹幕雨：一片小圈按顺序砸下来（冰锥、落石、蛛网、水柱）
##   circle 单个圈（带风格的砸地）；追身连爆 = 房主隔一会儿在你脚下放一个
##   wall   海啸墙：一堵墙推过整片地，只有缺口能躲（跳不过去）
##   vortex 漩涡：把人往中间吸，中间疼
## style 决定颜色和砸下去的样子：poison 毒 / silk 蛛丝 / rock 岩石 / ice 冰 / water 水 / fire 火

const STYLE := {
	"poison": [Color(0.5, 1.0, 0.3), Color(0.75, 0.3, 1.0)],
	"silk": [Color(0.95, 0.95, 1.0), Color(1.0, 0.25, 0.35)],
	"rock": [Color(1.0, 0.5, 0.18), Color(0.55, 0.45, 0.35)],
	"ice": [Color(0.5, 0.9, 1.0), Color(0.92, 0.98, 1.0)],
	"water": [Color(0.25, 0.65, 1.0), Color(0.85, 0.97, 1.0)],
	"fire": [Color(1.0, 0.42, 0.12), Color(1.0, 0.85, 0.4)],
}

var world: World
var _lanes: Array = []
var _sweeps: Array = []
var _circles: Array = []
var _walls: Array = []
var _vortexes: Array = []
static var _tex_edge: ImageTexture
static var _tex_fill: ImageTexture
var _plane: PlaneMesh


func _ready() -> void:
	_plane = PlaneMesh.new()
	_plane.size = Vector2(1, 1)
	_plane.orientation = PlaneMesh.FACE_Y
	_rect_textures()


static func col(style: String, i := 0) -> Color:
	return (STYLE.get(style, STYLE["fire"]) as Array)[i]


# ------------------------------------------------------------------ 房主发招（伤害在这里乘章节和 Boss 重数）

func _k() -> float:
	return float(Data.BOSS_DMG_CH.get(world.chapter, 1.0)) * world._boss_k


func _send(type: String, args: Array) -> void:
	Net.send(0, "ba", [type, args])
	_on(type, args)


func _g(p: Vector3) -> Vector3:
	return Vector3(p.x, maxf(world.island.height_at(p.x, p.z), Island.WATER_Y), p.z)


## 直线带：origin 起点，dir 方向，length 长，width 宽；delay 秒后打；travel 冲击走多快（米/秒，0 = 一下全砸）
func lane(origin: Vector3, dir: Vector3, length: float, width: float, delay: float, dmg: float, style: String, travel := 0.0) -> void:
	dir.y = 0.0
	_send("lane", [_g(origin), dir.normalized(), length, width, delay, dmg * _k(), style, travel])


## 旋转扫射：从 a0 扫到 a1（弧度，atan2(x, z)），windup 秒预警后用 dur 秒扫过去；thick 扫到的角度宽（弧度）
func sweep(origin: Vector3, a0: float, a1: float, length: float, thick: float, windup: float, dur: float, dmg: float, style: String) -> void:
	_send("sweep", [_g(origin), a0, a1, length, thick, windup, dur, dmg * _k(), style])


## 单个圈；late = 圈只在最后 0.4 秒才出来（要看起手）
func circle(center: Vector3, radius: float, delay: float, dmg: float, style: String, late := false) -> void:
	_send("circle", [_g(center), radius, delay, dmg * _k(), style, late])


## 弹幕雨：pts = [[位置, 多久后砸], ...]
func rain(pts: Array, radius: float, dmg: float, style: String) -> void:
	var out: Array = []
	for e in pts:
		out.append([_g(e[0]), float(e[1])])
	_send("rain", [out, radius, dmg * _k(), style])


## 海啸墙：从 start 往 dir 推 dist 米，墙宽 half*2，缺口在墙上 gap_off（左右偏移）、宽 gap_w
func wall(start: Vector3, dir: Vector3, half: float, speed: float, dist: float, gap_off: float, gap_w: float, dmg: float, style: String, delay := 1.5) -> void:
	dir.y = 0.0
	_send("wall", [_g(start), dir.normalized(), half, speed, dist, gap_off, gap_w, dmg * _k(), style, delay])


## 漩涡：radius 内往中间吸（pull 米/秒²），inner 内每秒 dps
func vortex(center: Vector3, radius: float, dur: float, pull: float, inner: float, dps: float, style: String) -> void:
	_send("vortex", [_g(center), radius, dur, pull, inner, dps * _k(), style])


## 追身连爆：n 个圈，每 gap 秒在 peer 脚下（往前预判一点）放一个
func chase(peer: int, n: int, gap: float, radius: float, delay: float, dmg: float, style: String) -> void:
	var tw := create_tween()
	for i in n:
		tw.tween_callback(func():
			var p := _peer_pos(peer)
			if p != Vector3.INF:
				circle(p, radius, delay, dmg, style))
		tw.tween_interval(gap)


func _peer_pos(peer: int) -> Vector3:
	if peer == Net.my_id:
		return world.player.global_position if not world.player.dead else Vector3.INF
	if world.remotes.has(peer):
		var r: Node3D = world.remotes[peer]
		return r.global_position
	return Vector3.INF


## Boss 露出破绽（房主调）：大家都看到，打弱点伤害翻倍
func stun(b: Boss, dur: float) -> void:
	b.stun_t = dur
	Net.send(0, "bstun", [dur])
	on_stun([dur])


func on_stun(d: Array) -> void:
	var b := world.boss
	if b == null or b.dead:
		return
	var dur := float(d[0])
	b.stun_vis = dur
	var p := b.weak_point()
	world.fx._flash(p, Color(1.0, 0.9, 0.5), 6.0, 0.3, "flare", 3.0)
	world.fx._sparks(p, Vector3.UP, Color(1.0, 0.85, 0.3), 40, 10.0, 0.8, 0.09, -6.0, 180.0)
	world.fx._air_ring(p + Vector3.UP * 1.5, Color(1.0, 0.85, 0.4), 1.0, 4.0, 0.6, 1.0, "ring", 3.0)
	Sfx.play_at("snap", p, 4.0, 0.0, 0.8)
	# 头上一个一闪一闪的"破绽"
	var l := U.label3d("破绽", 90, Color(1.0, 0.85, 0.35), 14)
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0013
	world.fx.add_child(l)
	l.global_position = p + Vector3.UP * 3.0
	var tw := l.create_tween().set_loops(int(ceil(dur / 0.5)))
	tw.tween_property(l, "modulate:a", 0.35, 0.25)
	tw.tween_property(l, "modulate:a", 1.0, 0.25)
	var tf := l.create_tween()
	tf.tween_interval(dur)
	tf.tween_callback(l.queue_free)
	if b.center().distance_to(world.player.global_position) < 90.0:
		world.hud._show_banner("破绽！", "打它的头：伤害 ×2（%.0f 秒）" % dur, Color(1.0, 0.85, 0.35), 1.6)


# ------------------------------------------------------------------ 每台电脑：画出来、判断打没打到自己

func on_message(data: Array) -> void:
	_on(str(data[0]), data[1])


func _on(type: String, a: Array) -> void:
	match type:
		"lane":
			_on_lane(a)
		"sweep":
			_on_sweep(a)
		"circle":
			_on_circle(a[0], float(a[1]), float(a[2]), float(a[3]), str(a[4]), bool(a[5]))
		"rain":
			for e in a[0]:
				_on_circle(e[0], float(a[1]), float(e[1]), float(a[2]), str(a[3]), false)
			Sfx.play_at("boss_roar", (a[0][0] as Array)[0], -4.0, 0.05, 1.4)
		"wall":
			_on_wall(a)
		"vortex":
			_on_vortex(a)


## 打到自己：翻滚的无敌时间里不算（Player.take_damage 里记"极限闪避"）
func _hurt(dmg: float, from: Vector3, knock: Vector3, tick := false) -> void:
	var p := world.player
	if p.dead:
		return
	var hp0 := p.hp
	p.take_damage(dmg, from, tick)
	if p.hp < hp0:
		p.velocity += knock


func _me() -> Vector3:
	return world.player.global_position


func _my_ground() -> float:
	var m := _me()
	return maxf(world.island.height_at(m.x, m.z), Island.WATER_Y)


# ---- 直线带

func _rect_textures() -> void:
	if _tex_edge:
		return
	var w := 64
	var h := 256
	var ie := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var i_f := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var ex := minf(x, w - 1 - x)
			var ey := minf(y, h - 1 - y)
			var edge := 1.0 if (ex < 4 or ey < 4) else 0.0
			var stripe := 0.12 if int((x + y) / 10) % 2 == 0 else 0.04
			var v := maxf(edge, stripe)
			ie.set_pixel(x, y, Color(v, v, v, v))
			var fv := 0.55 * (1.0 - absf(float(x) / w - 0.5) * 0.8)
			i_f.set_pixel(x, y, Color(fv, fv, fv, fv))
	_tex_edge = ImageTexture.create_from_image(ie)
	_tex_fill = ImageTexture.create_from_image(i_f)


## 贴在地上的长方形（跟着地形起伏）
func _rect_decal(center: Vector3, dir: Vector3, width: float, length: float, c: Color, tex: Texture2D, emission: float) -> Decal:
	_rect_textures()
	var d := Decal.new()
	d.texture_albedo = tex
	d.texture_emission = tex
	d.emission_energy = emission
	d.modulate = c
	d.albedo_mix = 0.7
	d.size = Vector3(width, 10.0, length)
	d.upper_fade = 0.2
	d.lower_fade = 0.4
	d.cull_mask = 1
	world.fx.add_child(d)
	d.global_position = center
	d.rotation.y = atan2(dir.x, dir.z)
	return d


func _on_lane(a: Array) -> void:
	var o: Vector3 = a[0]
	var dir: Vector3 = a[1]
	var length := float(a[2])
	var width := float(a[3])
	var delay := float(a[4])
	var style := str(a[6])
	var c := col(style)
	var edge := _rect_decal(o + dir * length * 0.5, dir, width, length, c, _tex_edge, 2.2)
	var fill := _rect_decal(o, dir, width, 0.1, c, _tex_fill, 1.6)
	# 填满的那一截从起点往前长
	var grow := func(v: float) -> void:
		if is_instance_valid(fill):
			fill.size.z = maxf(length * v, 0.1)
			fill.global_position = o + dir * length * v * 0.5
	var tw := fill.create_tween()
	tw.tween_method(grow, 0.0, 1.0, maxf(delay, 0.05)).set_ease(Tween.EASE_IN)
	_lanes.append({"o": o, "dir": dir, "len": length, "w": width, "t": delay, "dmg": float(a[5]), "style": style,
		"travel": float(a[7]), "front": -1.0, "hit": false, "fx_at": 0.0, "nodes": [edge, fill]})
	Sfx.play_at("boss_roar", o, -2.0, 0.05, 1.25)


func _tick_lanes(dt: float) -> void:
	var me := _me()
	for L in _lanes.duplicate():
		var o: Vector3 = L["o"]
		var dir: Vector3 = L["dir"]
		var length := float(L["len"])
		var style := str(L["style"])
		if float(L["t"]) > 0.0:
			L["t"] = float(L["t"]) - dt
			if float(L["t"]) > 0.0:
				continue
			for n in L["nodes"]:
				if is_instance_valid(n):
					(n as Node).queue_free()
			L["front"] = 0.0 if float(L["travel"]) > 0.0 else length
			if float(L["travel"]) <= 0.0:
				# 一下全砸：沿着带子一串爆
				var k := 0.0
				while k <= length:
					_impact(style, o + dir * k, float(L["w"]) * 0.5, k / length * 0.25)
					k += 3.0
				_lane_check(L, me, true)
				_lanes.erase(L)
				continue
			world.fx._flash(o + Vector3.UP, col(style, 1), float(L["w"]) * 1.5, 0.2)
		# 冲击沿着带子往前走
		var f0 := float(L["front"])
		var f1 := minf(f0 + float(L["travel"]) * dt, length)
		L["front"] = f1
		while float(L["fx_at"]) <= f1:
			_trail(style, o + dir * float(L["fx_at"]), float(L["w"]))
			L["fx_at"] = float(L["fx_at"]) + 2.5
		if not L["hit"]:
			var rel := me - o
			var along := rel.dot(dir)
			if along >= f0 - 1.2 and along <= f1 + 1.2:
				_lane_check(L, me, false)
		if f1 >= length:
			_lanes.erase(L)


func _lane_check(L: Dictionary, me: Vector3, whole: bool) -> void:
	var o: Vector3 = L["o"]
	var dir: Vector3 = L["dir"]
	var rel := me - o
	var along := rel.dot(dir)
	var side := (rel - dir * along)
	side.y = 0.0
	if along < -1.0 or along > float(L["len"]) + 1.0 or side.length() > float(L["w"]) * 0.5 + 0.4:
		return
	if me.y - _my_ground() > 3.5:
		return
	L["hit"] = true
	var knock := dir * 9.0 + side.normalized() * 4.0 + Vector3.UP * 5.0
	_hurt(float(L["dmg"]), o, knock)


# ---- 旋转扫射

func _on_sweep(a: Array) -> void:
	var o: Vector3 = a[0]
	var a0 := float(a[1])
	var a1 := float(a[2])
	var length := float(a[3])
	var style := str(a[8])
	var c := col(style)
	# 预警：整个扇形淡淡的，起点那一边亮一条
	var lo := minf(a0, a1)
	var hi := maxf(a0, a1)
	var fan := _fan(o, lo, hi, length, c)
	var start_dir := Vector3(sin(a0), 0, cos(a0))
	var mark := _rect_decal(o + start_dir * length * 0.5, start_dir, 1.4, length, c, _tex_fill, 3.0)
	# 扫的那一道：朝镜头的光带，扫的时候跟着转
	var beam := MeshInstance3D.new()
	beam.mesh = _plane
	var bm := FxLib.smat("beam", {"color": Color(c.r, c.g, c.b, 1.0), "width": 0.0, "hdr": 2.6, "len_m": length})
	beam.material_override = bm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.extra_cull_margin = length
	world.fx.add_child(beam)
	beam.visible = false
	_sweeps.append({"o": o, "a0": a0, "a1": a1, "len": length, "thick": float(a[4]), "t": float(a[5]), "dur": float(a[6]),
		"dmg": float(a[7]), "style": style, "k": 0.0, "hit": false, "fan": fan, "mark": mark, "beam": beam, "bm": bm, "fx_t": 0.0, "prev": a0})
	Sfx.play_at("boss_roar", o, 0.0, 0.05, 1.1)


## 地上的扇形（淡色、边亮）
func _fan(o: Vector3, lo: float, hi: float, reach: float, c: Color) -> MeshInstance3D:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 24
	for i in seg:
		var b0 := lo + (hi - lo) * i / seg
		var b1 := lo + (hi - lo) * (i + 1) / seg
		im.surface_set_uv(Vector2((i + 0.5) / seg, 0.0))
		im.surface_add_vertex(Vector3.ZERO)
		im.surface_set_uv(Vector2(float(i) / seg, 1.0))
		im.surface_add_vertex(Vector3(sin(b0), 0, cos(b0)) * reach)
		im.surface_set_uv(Vector2(float(i + 1) / seg, 1.0))
		im.surface_add_vertex(Vector3(sin(b1), 0, cos(b1)) * reach)
	im.surface_end()
	var n := MeshInstance3D.new()
	n.mesh = im
	var m := ShaderMaterial.new()
	m.shader = World._cone_shader()
	m.set_shader_parameter("color", Color(c.r, c.g, c.b, 1.0))
	m.set_shader_parameter("fill", 0.0)
	n.material_override = m
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.fx.add_child(n)
	n.global_position = o + Vector3(0, 0.25, 0)
	return n


func _tick_sweeps(dt: float) -> void:
	var me := _me()
	for S in _sweeps.duplicate():
		var o: Vector3 = S["o"]
		if float(S["t"]) > 0.0:
			S["t"] = float(S["t"]) - dt
			var fan: MeshInstance3D = S["fan"]
			if is_instance_valid(fan):
				(fan.material_override as ShaderMaterial).set_shader_parameter("fill", 0.0)
			if float(S["t"]) > 0.0:
				continue
			for key in ["fan", "mark"]:
				if is_instance_valid(S[key]):
					(S[key] as Node).queue_free()
			(S["beam"] as Node3D).visible = true
			Sfx.play_at("skill_beam", o, 4.0, 0.0, 0.7)
		S["k"] = minf(float(S["k"]) + dt / maxf(float(S["dur"]), 0.05), 1.0)
		var ang := lerpf(float(S["a0"]), float(S["a1"]), float(S["k"]))
		var dir := Vector3(sin(ang), 0, cos(ang))
		var length := float(S["len"])
		var beam: MeshInstance3D = S["beam"]
		var origin := o + Vector3.UP * 1.0
		var basis := Basis.looking_at(dir, Vector3.UP)
		beam.global_transform = Transform3D(basis * Basis.from_scale(Vector3(1, 1, length)), origin + dir * length * 0.5)
		var bm: ShaderMaterial = S["bm"]
		bm.set_shader_parameter("width", 2.6 * sin(float(S["k"]) * PI * 0.5 + 0.35))
		S["fx_t"] = float(S["fx_t"]) - dt
		if float(S["fx_t"]) <= 0.0:
			S["fx_t"] = 0.07
			_sweep_fx(str(S["style"]), origin, dir, length)
		# 打到：扫过人所在的方向（这一帧和上一帧之间），人在射程里、贴着地
		if not S["hit"]:
			var rel := Vector3(me.x - o.x, 0, me.z - o.z)
			var bear := atan2(rel.x, rel.z)
			var prev := float(S["prev"])
			var lo := minf(prev, ang) - float(S["thick"])
			var hi := maxf(prev, ang) + float(S["thick"])
			var b2 := bear
			while b2 < lo - PI:
				b2 += TAU
			while b2 > hi + PI:
				b2 -= TAU
			if b2 >= lo and b2 <= hi and rel.length() < length and me.y - _my_ground() < 1.3:
				S["hit"] = true
				_hurt(float(S["dmg"]), o, rel.normalized() * 7.0 + Vector3.UP * 4.0)
		S["prev"] = ang
		if float(S["k"]) >= 1.0:
			_sweeps.erase(S)
			var tw := beam.create_tween()
			tw.tween_method(func(v: float): bm.set_shader_parameter("width", v), 2.6, 0.0, 0.25)
			tw.tween_callback(beam.queue_free)


## 扫射一路的特效：毒雾一团团、冰霜碎屑、水花
func _sweep_fx(style: String, origin: Vector3, dir: Vector3, length: float) -> void:
	var c := col(style)
	var c2 := col(style, 1)
	var fx: Fx = world.fx
	var p := origin + dir * randf_range(length * 0.3, length)
	p.y = maxf(world.island.height_at(p.x, p.z), Island.WATER_Y) + 0.6
	match style:
		"poison":
			fx._smoke(p, Color(c.r, c.g, c.b, 0.55), 3, 2.0, 1.6, 3.0, 0.4)
			fx._glows(p, Vector3.UP, c2, 4, 2.0, 1.0, 0.25, 0.5)
		"ice":
			fx._sparks(p, Vector3.UP, c2, 6, 6.0, 0.6, 0.06, -8.0, 90.0)
			fx._smoke(p, Color(0.85, 0.95, 1.0, 0.5), 2, 2.5, 1.2, 2.2, 0.2)
		"water":
			fx._smoke(p, Color(0.8, 0.92, 1.0, 0.55), 2, 3.0, 1.0, 2.4, 0.2)
			fx._sparks(p, Vector3.UP, c, 6, 7.0, 0.7, 0.06, -9.0, 60.0)
		_:
			fx._sparks(p, Vector3.UP, c, 5, 6.0, 0.5, 0.06, -6.0, 90.0)
			fx._glows(p, Vector3.UP, c2, 3, 2.0, 0.6, 0.2, 0.5)


# ---- 圈、弹幕雨

func _on_circle(center: Vector3, radius: float, delay: float, dmg: float, style: String, late: bool) -> void:
	var e := {"c": center, "r": radius, "t": delay, "dmg": dmg, "style": style, "node": null}
	var c := col(style)
	if late and delay > 0.5:
		Sfx.play_at("boss_roar", center, -6.0, 0.05, 1.5)
		var tw := create_tween()
		tw.tween_interval(delay - 0.4)
		tw.tween_callback(func():
			if _circles.has(e):
				e["node"] = world.fx.telegraph(center, radius, 0.4, c))
	else:
		e["node"] = world.fx.telegraph(center, radius, delay, c)
	_circles.append(e)


func _tick_circles(dt: float) -> void:
	var me := _me()
	for e in _circles.duplicate():
		e["t"] = float(e["t"]) - dt
		if float(e["t"]) > 0.0:
			continue
		_circles.erase(e)
		if is_instance_valid(e["node"]):
			(e["node"] as Node).queue_free()
		var c: Vector3 = e["c"]
		_impact(str(e["style"]), c, float(e["r"]), 0.0)
		if Vector2(me.x - c.x, me.z - c.z).length() < float(e["r"]) and absf(me.y - c.y) < 4.0:
			var push := Vector3(me.x - c.x, 0, me.z - c.z).normalized()
			_hurt(float(e["dmg"]), c, push * 6.0 + Vector3.UP * 5.0)
			if str(e["style"]) == "silk" and not world.player.dead:
				world.player.slow(0.5, 2.5)
				world.hud.toast("被蛛丝粘住了，走不快", Color(0.9, 0.9, 0.95), 1.5)
			elif str(e["style"]) == "ice" and not world.player.dead:
				world.player.slow(0.4, 2.0)


# ---- 砸下去的样子（按风格）

func _impact(style: String, pos: Vector3, r: float, delay: float) -> void:
	if delay > 0.0:
		var tw := create_tween()
		tw.tween_interval(delay)
		tw.tween_callback(func(): _impact(style, pos, r, 0.0))
		return
	var fx: Fx = world.fx
	var c := col(style)
	var c2 := col(style, 1)
	var near := pos.distance_to(_me()) < 70.0
	match style:
		"rock":
			fx.slam(pos, r)
		"ice":
			_ice_spikes(pos, r)
			fx._flash(pos + Vector3.UP, c2, r * 1.6, 0.18)
			fx._sparks(pos + Vector3.UP * 0.5, Vector3.UP, c, 24, 11.0, 0.8, 0.08, -12.0, 70.0)
			fx._smoke(pos + Vector3.UP * 0.4, Color(0.9, 0.97, 1.0, 0.6), 6, 3.0, 1.4, r * 0.9, 0.3)
			fx._ground(pos, "crack", Color(0.7, 0.95, 1.0, 0.9), r * 2.2, 2.0, 1.5, 2.0, 0.0, 0.5)
			Sfx.play_at("snap", pos, 2.0, 0.1, 1.4)
		"water":
			fx.splash(pos, true)
			fx._pillar(pos, c, maxf(r * 0.45, 0.8), 9.0 + r, 0.25)
			fx._smoke(pos + Vector3.UP, Color(0.85, 0.95, 1.0, 0.6), 8, 4.0, 1.6, r * 1.1, 0.8)
			fx._sparks(pos + Vector3.UP * 0.5, Vector3.UP, c2, 30, 14.0, 1.0, 0.08, -14.0, 25.0)
			Sfx.play_at("splash_big", pos, 2.0, 0.1)
		"poison":
			fx._ground(pos, "scorch", Color(0.4, 1.0, 0.25, 0.9), r * 2.2, 2.5, 1.5, 1.5, 0.3, 0.6)
			fx._smoke(pos + Vector3.UP * 0.5, Color(c.r, c.g, c.b, 0.6), 10, 4.0, 2.0, r * 1.2, 0.6)
			fx._glows(pos + Vector3.UP * 0.5, Vector3.UP, c2, 20, 5.0, 1.2, 0.3, 1.0)
			fx.shockwave(pos, r, c)
			Sfx.play_at("splash_small", pos, 2.0, 0.1, 0.7)
		"silk":
			fx.web_burst(pos)
			fx._ground(pos, "swirl", Color(0.95, 0.95, 1.0, 0.8), r * 2.2, 3.0, 1.5, 1.0, 0.0, 0.8)
			fx._sparks(pos + Vector3.UP * 0.5, Vector3.UP, c2, 14, 7.0, 0.6, 0.05, -6.0, 90.0)
			Sfx.play_at("snap", pos, 0.0, 0.1, 0.8)
		_:
			fx.explosion(pos + Vector3.UP * 0.5, r, c)
	if near:
		fx._shake(pos, 0.35, 35.0)


## 冰锥从地里冒出来，停一下再碎掉
func _ice_spikes(pos: Vector3, r: float) -> void:
	var n := Node3D.new()
	world.fx.add_child(n)
	n.global_position = pos
	var m := U.glow(Color(0.6, 0.92, 1.0), 1.6)
	var core := U.mat(Color(0.75, 0.93, 1.0), 0.05, 0.4, 0.0)
	var cnt := clampi(int(r * 2.2), 4, 12)
	for i in cnt:
		var a := TAU * i / cnt + randf() * 0.4
		var d := randf_range(0.2, r * 0.85)
		var h := randf_range(1.2, 2.2) + r * 0.25
		var q := Vector3(cos(a) * d, 0, sin(a) * d)
		var sp := U.part(n, U.cyl(0.0, randf_range(0.18, 0.35) * (1.0 + r * 0.08), h, 6), core if i % 2 == 0 else m, q + Vector3(0, h * 0.5, 0), Vector3(randf_range(-0.35, 0.35), 0, randf_range(-0.35, 0.35)), Vector3(1, 0.05, 1), false)
		var tw := sp.create_tween()
		tw.tween_interval(randf() * 0.08)
		tw.tween_property(sp, "scale", Vector3.ONE, 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	var t2 := n.create_tween()
	t2.tween_interval(1.1)
	t2.tween_callback(func():
		world.fx._sparks(pos + Vector3.UP, Vector3.UP, Color(0.8, 0.95, 1.0), 20, 6.0, 0.7, 0.07, -10.0, 120.0)
		n.queue_free())


## 冲击 / 水浪一路过去留下的
func _trail(style: String, p: Vector3, w: float) -> void:
	var fx: Fx = world.fx
	var g := Vector3(p.x, maxf(world.island.height_at(p.x, p.z), Island.WATER_Y), p.z)
	var c := col(style)
	match style:
		"rock":
			fx._smoke(g + Vector3.UP * 0.5, Color(0.6, 0.5, 0.4, 0.7), 5, 4.0, 1.4, w * 0.5, 0.4)
			fx._bits(g + Vector3.UP * 0.3, Vector3.UP, Color(0.5, 0.42, 0.33), 6, 7.0, 0.14)
			fx._ground(g, "crack", Color(0.12, 0.08, 0.05, 0.85), w * 1.1, 3.0, 1.5, 0.0, 0.0, 1.0)
		"ice":
			_ice_spikes(g, w * 0.45)
		"water":
			fx.splash(g, true)
			fx._sparks(g + Vector3.UP, Vector3.UP, col(style, 1), 12, 10.0, 0.8, 0.07, -12.0, 40.0)
		"poison":
			fx._smoke(g + Vector3.UP * 0.5, Color(c.r, c.g, c.b, 0.55), 4, 3.0, 1.6, w * 0.6, 0.4)
		"silk":
			fx._sparks(g + Vector3.UP * 0.5, Vector3.UP, c, 8, 5.0, 0.5, 0.05, -6.0, 90.0)
		_:
			fx._glows(g + Vector3.UP * 0.5, Vector3.UP, c, 8, 4.0, 0.8, 0.3, 0.5)
	fx._shake(g, 0.12, 25.0)


# ---- 海啸墙

func _on_wall(a: Array) -> void:
	var start: Vector3 = a[0]
	var dir: Vector3 = a[1]
	var half := float(a[2])
	var style := str(a[8])
	var c := col(style)
	var side := Vector3(dir.z, 0, -dir.x)
	var gap_off := float(a[5])
	var gap_w := float(a[6])
	# 两段墙（缺口两边），用光柱着色器画成一面往前推的水墙
	var root := Node3D.new()
	world.fx.add_child(root)
	root.global_position = start
	root.rotation.y = atan2(dir.x, dir.z)
	var segs: Array = [[-half, gap_off - gap_w * 0.5], [gap_off + gap_w * 0.5, half]]
	for s in segs:
		var w := float(s[1]) - float(s[0])
		if w <= 0.5:
			continue
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(w, 7.0, 1.6)
		mi.mesh = bm
		mi.material_override = FxLib.smat("pillar", {"color": Color(c.r, c.g, c.b, 1.0), "hdr": 1.8, "half_h": 3.5, "speed": 3.0, "top": 0.15, "rim_k": 0.4})
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3((float(s[0]) + float(s[1])) * 0.5, 3.5, 0)
		root.add_child(mi)
	# 缺口标出来：地上一条绿光 + 两根亮柱
	var gp := start + side * gap_off
	var mark := _rect_decal(gp + dir * 20.0, dir, gap_w, 40.0, Color(0.3, 1.0, 0.45), _tex_fill, 2.0)
	root.visible = false
	_walls.append({"o": start, "dir": dir, "side": side, "half": half, "spd": float(a[3]), "dist": float(a[4]), "gap": gap_off, "gw": gap_w,
		"dmg": float(a[7]), "style": style, "t": float(a[9]), "s": 0.0, "hit": false, "node": root, "mark": mark, "fx_t": 0.0})
	if start.distance_to(_me()) < 160.0:
		world.hud._show_banner("海啸！", "找墙上的缺口（地上的绿光）", Color(0.5, 0.85, 1.0), 2.5)
	Sfx.play("boss_roar", 2.0, 0.0, 0.6)


func _tick_walls(dt: float) -> void:
	var me := _me()
	for W in _walls.duplicate():
		var root: Node3D = W["node"]
		if float(W["t"]) > 0.0:
			W["t"] = float(W["t"]) - dt
			if float(W["t"]) <= 0.0 and is_instance_valid(root):
				root.visible = true
				Sfx.play_at("splash_big", W["o"], 6.0, 0.0, 0.6)
			continue
		var s0 := float(W["s"])
		var s1 := s0 + float(W["spd"]) * dt
		W["s"] = s1
		var o: Vector3 = W["o"]
		var dir: Vector3 = W["dir"]
		var side: Vector3 = W["side"]
		var pos := o + dir * s1
		if is_instance_valid(root):
			root.global_position = Vector3(pos.x, maxf(world.island.height_at(pos.x, pos.z), Island.WATER_Y) - 0.5, pos.z)
		W["fx_t"] = float(W["fx_t"]) - dt
		if float(W["fx_t"]) <= 0.0:
			W["fx_t"] = 0.12
			var lat := randf_range(-float(W["half"]), float(W["half"]))
			if absf(lat - float(W["gap"])) > float(W["gw"]) * 0.5:
				var q := pos + side * lat
				q.y = maxf(world.island.height_at(q.x, q.z), Island.WATER_Y)
				world.fx._sparks(q + Vector3.UP * 5.0, Vector3.UP + dir, col(str(W["style"]), 1), 10, 9.0, 0.9, 0.08, -12.0, 40.0)
				world.fx._smoke(q + Vector3.UP * 3.0, Color(0.85, 0.95, 1.0, 0.5), 2, 3.0, 1.2, 3.0, 0.2)
		if not W["hit"]:
			var rel := me - o
			var along := rel.dot(dir)
			var lat2 := rel.dot(side)
			if along >= s0 - 1.0 and along <= s1 + 1.0 and absf(lat2) < float(W["half"]) and absf(lat2 - float(W["gap"])) > float(W["gw"]) * 0.5:
				W["hit"] = true
				_hurt(float(W["dmg"]), pos, dir * 14.0 + Vector3.UP * 6.0)
		if s1 >= float(W["dist"]):
			_walls.erase(W)
			if is_instance_valid(root):
				var tw := root.create_tween()
				tw.tween_property(root, "scale", Vector3(1, 0.01, 1), 0.5)
				tw.tween_callback(root.queue_free)
			if is_instance_valid(W["mark"]):
				(W["mark"] as Node).queue_free()


# ---- 漩涡

func _on_vortex(a: Array) -> void:
	var c: Vector3 = a[0]
	var radius := float(a[1])
	var dur := float(a[2])
	var style := str(a[6])
	world.fx.blackhole_fx(c, radius * 0.5, dur, col(style))
	var g := world.fx._ground(c, "swirl", col(style), radius * 2.0, dur, 0.6, 2.0, -2.5, 0.6)
	_vortexes.append({"c": c, "r": radius, "t": dur, "pull": float(a[3]), "inner": float(a[4]), "dps": float(a[5]), "tick": 0.0, "node": g})
	if c.distance_to(_me()) < radius + 20.0:
		world.hud.toast("漩涡把人往中间吸——往外跑！", Color(0.5, 0.85, 1.0), 2.5)
	Sfx.play_at("skill_pull", c, 6.0, 0.0, 0.6)


func _tick_vortexes(dt: float) -> void:
	var me := _me()
	var p := world.player
	for V in _vortexes.duplicate():
		V["t"] = float(V["t"]) - dt
		if float(V["t"]) <= 0.0:
			_vortexes.erase(V)
			continue
		var c: Vector3 = V["c"]
		var to := Vector3(c.x - me.x, 0, c.z - me.z)
		var d := to.length()
		if d < float(V["r"]) and not p.dead:
			var k := 1.0 - d / float(V["r"]) * 0.5
			p.velocity += to.normalized() * float(V["pull"]) * k * dt
			V["tick"] = float(V["tick"]) - dt
			if d < float(V["inner"]) and float(V["tick"]) <= 0.0:
				V["tick"] = 0.5
				_hurt(float(V["dps"]) * 0.5, c, Vector3.ZERO, true)


func _process(dt: float) -> void:
	_tick_lanes(dt)
	_tick_sweeps(dt)
	_tick_circles(dt)
	_tick_walls(dt)
	_tick_vortexes(dt)


## Boss 死了 / 换地图：还没砸下来的预警都收掉
func clear_all() -> void:
	for L in _lanes:
		for n in L["nodes"]:
			if is_instance_valid(n):
				(n as Node).queue_free()
	for S in _sweeps:
		for key in ["fan", "mark", "beam"]:
			if is_instance_valid(S[key]):
				(S[key] as Node).queue_free()
	for e in _circles:
		if is_instance_valid(e["node"]):
			(e["node"] as Node).queue_free()
	for W in _walls:
		for key in ["node", "mark"]:
			if is_instance_valid(W[key]):
				(W[key] as Node).queue_free()
	_lanes.clear()
	_sweeps.clear()
	_circles.clear()
	_walls.clear()
	_vortexes.clear()
