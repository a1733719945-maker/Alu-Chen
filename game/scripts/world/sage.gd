class_name Sage
extends Node3D
## 青崖子：守天坛的独眼老猎人（真身是三万年前领兵叩天的沈青崖，剧本见 docs/世界观.md）。
## 他跟着你坐船换岛，站在每座岛的天坛边；走近按 F 和他说话，说的话跟着主线走（Sage.lines）。
## 每台电脑自己放一个（跟着自己的存档说话），不走联机同步。
##
## 样子：程序拼的——斗笠、白发白须、左眼罩、蓑衣（草披肩 + 旧袍子）、背着长弓和箭囊，手里拄着一根猎叉。
## 站着的时候微微起伏；你走近了他会转过头来看你。

var world: Node
var head: Node3D
var _body: Node3D
var _t := 0.0
var _yaw := 0.0
var _line_i := 0
var _last_state := ""


func setup(p_world: Node, pos: Vector3, face: Vector3) -> void:
	world = p_world
	name = "Sage"
	global_position = pos
	_yaw = atan2(face.x - pos.x, face.z - pos.z) + PI
	rotation.y = _yaw
	_build()


const MODEL := "res://assets/models/npc/sage.glb"
var _model: Node3D


func _build() -> void:
	# 混元生成的老将军（独眼、白须、青铜发冠、乌铁鱼鳞甲，带待机动作）：有就用它
	if ResourceLoader.exists(MODEL):
		_body = Node3D.new()
		add_child(_body)
		_model = BeastModels.instance_custom(MODEL, {"fit": "h", "size": 1.95})
		_model.position.y = 0.975
		_body.add_child(_model)
		FxLib.no_decals(_body)
		head = Node3D.new()
		_body.add_child(head)
		var l0 := U.label3d("青崖子", 34, Color(1.0, 0.9, 0.7), 8)
		l0.position = Vector3(0, 2.4, 0)
		l0.pixel_size = 0.004
		l0.visibility_range_end = 18.0
		add_child(l0)
		return
	var straw := U.mat(Color(0.62, 0.52, 0.32), 0.95)
	var straw_dark := U.mat(Color(0.42, 0.34, 0.2), 0.95)
	var robe := U.mat(Color(0.3, 0.27, 0.24), 0.9)
	var under := U.mat(Color(0.55, 0.52, 0.46), 0.9)
	var skin := U.mat(Color(0.82, 0.66, 0.54), 0.8)
	var white := U.mat(Color(0.92, 0.91, 0.88), 0.7)
	var dark := U.mat(Color(0.08, 0.07, 0.07), 0.6)
	var leather := U.mat(Color(0.24, 0.15, 0.09), 0.65)
	var wood := U.mat(Color(0.35, 0.24, 0.14), 0.7)
	var red := U.mat(Color(0.6, 0.12, 0.08), 0.6)
	_body = Node3D.new()
	add_child(_body)
	FxLib.no_decals(_body)
	# 身子：旧袍子（有点驼）+ 蓑衣草披肩（一层层往下）
	U.part(_body, U.capsule(0.24, 0.8), robe, Vector3(0, 1.12, 0.03), Vector3(0.12, 0, 0), Vector3(1.0, 1.0, 0.8))
	U.part(_body, U.cyl(0.26, 0.34, 0.75, 14), robe, Vector3(0, 0.55, 0.02))
	for i in 3:
		var r := 0.3 + i * 0.04
		U.part(_body, U.cyl(r - 0.1, r + 0.06, 0.22, 16), straw if i % 2 == 0 else straw_dark, Vector3(0, 1.5 - i * 0.17, 0.05), Vector3(0.14, 0, 0), Vector3(1.0, 1.0, 0.85))
	U.part(_body, U.cyl(0.25, 0.25, 0.08, 14), red, Vector3(0, 0.95, 0.02), Vector3.ZERO, Vector3(1.0, 1.0, 0.82))
	# 腿和草鞋
	for sx in [-0.1, 0.1]:
		U.part(_body, U.cyl(0.07, 0.065, 0.5, 8), under, Vector3(sx, 0.28, 0))
		U.part(_body, U.box(Vector3(0.12, 0.05, 0.24)), straw_dark, Vector3(sx, 0.03, -0.04))
	# 胳膊：右手拄着猎叉
	U.part(_body, U.capsule(0.06, 0.55), robe, Vector3(-0.3, 1.18, -0.02), Vector3(0, 0, -0.18))
	U.part(_body, U.capsule(0.06, 0.55), robe, Vector3(0.3, 1.16, -0.08), Vector3(-0.5, 0, 0.2))
	U.part(_body, U.sphere(0.055, 8, 6), skin, Vector3(0.36, 0.92, -0.26))
	U.part(_body, U.cyl(0.022, 0.022, 1.9, 6), wood, Vector3(0.37, 0.95, -0.28))
	U.part(_body, U.cyl(0.0, 0.035, 0.18, 6), U.mat(Color(0.5, 0.5, 0.52), 0.35, 0.0, 0.8), Vector3(0.37, 1.97, -0.28))
	# 背上：长弓（一段段拼成的弧）+ 箭囊
	var bow := Node3D.new()
	bow.position = Vector3(0.02, 1.2, 0.3)
	bow.rotation = Vector3(0, 0, 0.5)
	_body.add_child(bow)
	for k in 7:
		var a := -0.9 + k * 0.3
		U.part(bow, U.cyl(0.018, 0.018, 0.26, 6), wood, Vector3(0, sin(a) * 0.72, cos(a) * 0.14 - 0.1), Vector3(-a * 0.45, 0, 0))
	U.part(bow, U.cyl(0.004, 0.004, 1.35, 4), white, Vector3(0, 0, -0.1))
	U.part(_body, U.cyl(0.07, 0.08, 0.55, 10), leather, Vector3(-0.16, 1.25, 0.26), Vector3(0, 0, 0.35))
	for k in 3:
		U.part(_body, U.cyl(0.008, 0.008, 0.22, 4), wood, Vector3(-0.26 + k * 0.03, 1.55 + k * 0.01, 0.27), Vector3(0, 0, 0.35))
	# 头：脸、白发、白胡子、左眼罩（带子）、右眼
	head = Node3D.new()
	head.position = Vector3(0, 1.72, -0.05)
	_body.add_child(head)
	U.part(head, U.sphere(0.13, 16, 12), skin, Vector3.ZERO, Vector3.ZERO, Vector3(0.92, 1.05, 0.95))
	U.part(head, U.sphere(0.135, 14, 10), white, Vector3(0, 0.03, 0.03), Vector3.ZERO, Vector3(0.96, 0.9, 0.96))
	U.part(head, U.cyl(0.1, 0.03, 0.26, 10), white, Vector3(0, -0.15, -0.07), Vector3(0.25, 0, 0))
	U.part(head, U.box(Vector3(0.07, 0.012, 0.03)), white, Vector3(-0.05, 0.05, -0.12))
	U.part(head, U.box(Vector3(0.07, 0.012, 0.03)), white, Vector3(0.05, 0.05, -0.12))
	U.part(head, U.sphere(0.018, 6, 4), dark, Vector3(-0.045, 0.01, -0.118))
	U.part(head, U.box(Vector3(0.06, 0.05, 0.02)), dark, Vector3(0.045, 0.012, -0.122))
	U.part(head, U.torus(0.125, 0.135, 24, 4), dark, Vector3(0, 0.02, 0), Vector3(0.15, 0, 0.25))
	# 斗笠：宽边的尖顶草帽
	U.part(head, U.cyl(0.02, 0.36, 0.2, 20), straw, Vector3(0, 0.17, 0), Vector3(0.08, 0, 0))
	U.part(head, U.cyl(0.36, 0.37, 0.015, 20), straw_dark, Vector3(0, 0.07, 0.008), Vector3(0.08, 0, 0))
	U.part(head, U.sphere(0.025, 6, 4), red, Vector3(0, 0.28, 0))
	# 头顶上一个小小的名字（走近才看得见）
	var l := U.label3d("青崖子", 34, Color(1.0, 0.9, 0.7), 8)
	l.position = Vector3(0, 2.35, 0)
	l.pixel_size = 0.004
	l.visibility_range_end = 18.0
	add_child(l)


func _process(dt: float) -> void:
	_t += dt
	# 呼吸：身子微微起伏（模型自己有待机动作，不用）
	if _model == null:
		_body.position.y = sin(_t * 1.3) * 0.012
	# 你走近了，他转过头来看你
	var p: Node3D = world.player
	if not is_instance_valid(p):
		return
	var to := p.global_position - global_position
	var want := 0.0
	if to.length() < 10.0:
		want = clampf(wrapf(atan2(-to.x, -to.z) - _yaw, -PI, PI), -1.0, 1.0)
	head.rotation.y = lerp_angle(head.rotation.y, want, 1.0 - exp(-4.0 * dt))
	if _model:
		# 模型没有单独的头可以转：整个人慢慢侧过身来看你
		_body.rotation.y = lerp_angle(_body.rotation.y, want * 0.7, 1.0 - exp(-2.0 * dt))


## 按 F 说的话：跟着主线走（到了哪一章、灵主打没打、有没有轮回过）。每按一次说下一句
func talk() -> void:
	var lines := lines_now()
	var state := "|".join(lines)
	if state != _last_state:
		_last_state = state
		_line_i = 0
	world.hud.say_clear()
	world.hud.say(Story.SAGE, str(lines[_line_i % lines.size()]))
	_line_i += 1


func lines_now() -> Array:
	var ch: int = world.chapter
	var kind := str(Data.CHAPTERS[ch]["boss"])
	var out: Array = []
	if Profile.rebirth > 0 and _line_i == 0:
		out.append("你身上……有前世的灵识。又是一轮了。")
	if world.boss_cleared():
		out.append(Story.lord(kind, "after"))
		out.append_array(Story.sage_idle(ch, true))
		if ch < 5:
			out.append("渡船在码头。人齐了，一起走。")
	else:
		out.append(Story.lord(kind, "arrive"))
		out.append(Story.sage_hint(str(world._cur_quest().get("type", ""))))
		out.append_array(Story.sage_idle(ch, false))
	return out
