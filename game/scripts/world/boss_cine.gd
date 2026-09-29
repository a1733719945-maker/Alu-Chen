class_name BossCine
extends CanvasLayer
## 灵主出场镜头（用户："我觉得每个 boss 都可以做一个 CG"）：游戏里实时拍，不用视频。
##   0 ~ 1.3 秒：镜头压得很低，仰拍 Boss 砸下来 / 从水里升起来；电影黑边合上
##   1.3 秒：一声长啸，全场一震，地上冲出一圈气浪
##   之后：镜头绕着它转大半圈、慢慢升起来；左下角宋体大字：眉题（第几章 · 哪里之主）、朱印 + 名号、一句来历、它开口说的话
##   6.5 秒（或按空格 / 点一下）：回到自己的眼睛
## 每个灵主（每一重天）第一次出场才播，记在 Profile.stats["cine_<种类>_<重数>"]。

const DUR := 6.5
const ROAR := 1.3
var _roar_anim := false

var world: World
var boss: Boss
var cam: Camera3D
var _t := 0.0
var _a0 := 0.0
var _r := 20.0
var _roared := false
var _done := false
var _bars: Array = []
var _title: Control
var _hud_was := true
var _shake := 0.0


static func play(w: World, b: Boss, kick: String, bname: String, lore: String, line: String) -> BossCine:
	var c := BossCine.new()
	c.world = w
	c.boss = b
	c.layer = 30
	w.add_child(c)
	c._setup(kick, bname, lore, line)
	return c


func _setup(kick: String, bname: String, lore: String, line: String) -> void:
	cam = Camera3D.new()
	cam.fov = 58.0
	cam.far = world.player.cam.far
	world.add_child(cam)
	var to := world.player.global_position - boss.center()
	_a0 = atan2(to.x, to.z) - 0.6
	var s := boss.size
	_r = clampf(maxf(s.x, maxf(s.y, s.z)) * 1.15 + 8.0, 16.0, 70.0)
	cam.global_position = _cam_pos(0.0)
	cam.look_at(_look_at(), Vector3.UP)
	cam.current = true
	world.player.input_enabled = false
	_hud_was = world.hud.visible
	world.hud.visible = false
	# 电影黑边
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	UiKit.fill(root)
	for top in [true, false]:
		var b := ColorRect.new()
		b.color = Color(0, 0, 0)
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(b)
		if top:
			UiKit.place(b, Vector4(0, 0, 1, 0), Vector4(0, 0, 0, 0))
		else:
			UiKit.place(b, Vector4(0, 1, 1, 1), Vector4(0, 0, 0, 0))
		_bars.append(b)
		var tw := b.create_tween()
		if top:
			tw.tween_property(b, "offset_bottom", 110.0, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		else:
			tw.tween_property(b, "offset_top", -110.0, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# 名号：左下角
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 6)
	UiKit.place(v, Vector4(0, 1, 0, 1), Vector4(90, -330, 900, -130))
	root.add_child(v)
	v.add_child(UiKit.kicker(kick, UiKit.GOLD, 20))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(h)
	h.add_child(UiKit.seal(bname.substr(0, 1), 40))
	var tl := UiKit.title(bname, 84, Color(1.0, 0.97, 0.9))
	UiKit._text_style(tl, 4)
	h.add_child(tl)
	if lore != "":
		var ll := UiKit.label(lore, 22, UiKit.MOON, 3)
		v.add_child(ll)
	if line != "":
		var sl := UiKit.label("「%s」" % line, 24, Color(0.75, 0.9, 1.0), 3)
		sl.add_theme_font_override("font", Data.font_serif)
		v.add_child(sl)
	v.modulate.a = 0.0
	v.position.x -= 40.0
	_title = v
	var skip := UiKit.key_hint("空格", "跳过", 15, UiKit.MIST)
	UiKit.place(skip, Vector4(1, 1, 1, 1), Vector4(-170, -70, -30, -40))
	root.add_child(skip)


func _cam_pos(k: float) -> Vector3:
	var c := boss.center() if is_instance_valid(boss) else cam.global_position
	var s := boss.size if is_instance_valid(boss) else Vector3.ONE * 10.0
	var e := k * k * (3.0 - 2.0 * k)
	var a := _a0 + lerpf(0.0, 1.9, e)
	var r := lerpf(_r * 0.7, _r * 1.2, e)
	var p := c + Vector3(sin(a), 0, cos(a)) * r
	p.y = lerpf(c.y - s.y * 0.35, c.y + s.y * 0.45 + 3.0, e)
	var g := maxf(world.island.height_at(p.x, p.z), Island.WATER_Y)
	p.y = maxf(p.y, g + 1.4)
	return p


func _look_at() -> Vector3:
	if not is_instance_valid(boss):
		return cam.global_position - cam.global_basis.z
	return boss.center().lerp(boss.weak_point(), 0.55)


func _process(dt: float) -> void:
	if _done:
		return
	_t += dt
	if not is_instance_valid(boss) or boss.dead or _t >= DUR:
		finish()
		return
	var p := _cam_pos(clampf(_t / DUR, 0.0, 1.0))
	cam.global_position = cam.global_position.lerp(p, 1.0 - exp(-5.0 * dt))
	_shake = maxf(_shake - dt * 1.6, 0.0)
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.6
	cam.look_at(_look_at() + jitter, Vector3.UP)
	if _t >= ROAR - 0.5 and not _roar_anim:
		_roar_anim = true
		boss.roar_anim()
	if _t >= ROAR and not _roared:
		_roared = true
		_shake = 1.0
		var c := boss.center()
		var g := Vector3(c.x, maxf(world.island.height_at(c.x, c.z), Island.WATER_Y), c.z)
		world.fx.shockwave(g, clampf(boss.size.x * 1.2, 10.0, 30.0), Color(1.0, 0.8, 0.45))
		world.fx._flash(boss.weak_point(), Color(1.0, 0.85, 0.5), 8.0, 0.25)
		Sfx.play("boss_roar", 4.0, 0.0, 0.8)
		Sfx.play("boom", 0.0, 0.0, 0.55)
		var tw := _title.create_tween()
		tw.tween_property(_title, "modulate:a", 1.0, 0.6)
		tw.parallel().tween_property(_title, "position:x", _title.position.x + 40.0, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _input(e: InputEvent) -> void:
	if _done or _t < 0.6:
		return
	var skip: bool = (e is InputEventKey and e.pressed and not e.echo and (e.keycode == KEY_SPACE or e.keycode == KEY_ESCAPE or e.keycode == KEY_ENTER)) \
		or (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed)
	if skip:
		get_viewport().set_input_as_handled()
		finish()


func finish() -> void:
	if _done:
		return
	_done = true
	if is_instance_valid(world.player) and world.player.cam:
		world.player.cam.current = true
	if is_instance_valid(cam):
		cam.queue_free()
	world.hud.visible = _hud_was
	world._refresh_input()
	var tw := create_tween()
	for b in _bars:
		tw.parallel().tween_property(b, "modulate:a", 0.0, 0.35)
	if _title:
		tw.parallel().tween_property(_title, "modulate:a", 0.0, 0.35)
	tw.tween_callback(queue_free)
