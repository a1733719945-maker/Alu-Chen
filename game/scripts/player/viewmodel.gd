class_name ViewModel
extends Node3D
## 第一人称手里的东西：右手暗器、左手引魂索。
## 所有动作都是程序动画：弹簧后坐、鼠标拖拽的滞后、走路晃动、冲刺姿势、
## 换弹（拆弹匣）、拉杆 / 拉栓 / 泵动、弩臂回弹、开镜把照门对准屏幕中心。

const HIP := {
	"xiujian": Vector3(0.2, -0.19, -0.4),
	"meihua": Vector3(0.2, -0.19, -0.4),
	"zhuge": Vector3(0.16, -0.17, -0.36),
	"longxu": Vector3(0.15, -0.17, -0.36),
	"kongque": Vector3(0.15, -0.165, -0.36),
	"baoyu": Vector3(0.17, -0.17, -0.37),
	"zimu": Vector3(0.17, -0.18, -0.38),
	"hansha": Vector3(0.16, -0.19, -0.38),
	"zhuihun": Vector3(0.15, -0.175, -0.36),
	"guanyin": Vector3(0.15, -0.17, -0.36),
	"fist": Vector3.ZERO,
}
# 开镜时照门离眼睛多远
const ADS_DIST := {"xiujian": 0.22, "meihua": 0.22, "zhuge": 0.15, "longxu": 0.13, "kongque": 0.14, "baoyu": 0.2, "zimu": 0.16,
	"hansha": 0.14, "zhuihun": 0.09, "guanyin": 0.14, "fist": 0.0}

var charge := 0.0               # 天心泪蓄力（泪滴越来越亮）
var spin := 0.0                 # 流沙机弩的转速（枪管转起来）
var move_vel := Vector3.ZERO    # 人的速度（挂件跟着晃）
var _charm_a := Vector2.ZERO    # 挂件摆角（x 前后，z 左右）
var _charm_v := Vector2.ZERO
var _last_vel := Vector3.ZERO
var _rotor := 0.0
const SPRING_K := 300.0
const SPRING_C := 22.0

var models := {}
var cur := "xiujian"
var left_arm: Node3D
var left_hand: Node3D
var coil: MeshInstance3D
var scoped := false

var _kp := Vector3.ZERO      # 后坐：位置弹簧
var _kpv := Vector3.ZERO
var _kr := Vector3.ZERO      # 后坐：旋转弹簧（x 抬头，y 左右，z 翻滚）
var _krv := Vector3.ZERO
var _sway := Vector2.ZERO
var _sway_target := Vector2.ZERO
var _move_tilt := 0.0
var _switch := 0.0
var _bob_t := 0.0
var _bob_amt := 0.0
var _land := 0.0
var _left_throw := 0.0
var _left_pull := 0.0
var _left_show := 0.0
var _arm_flex := 0.0
var _lever_t := 0.0
var _lever_len := 0.0
var _idle_t := 0.0
var _item: Node3D                # 手上拿的道具（雷莲、回血丹、灵骨），拿着时暗器收起来
var _punch_t := 0.0              # 出拳进度（1 → 0）
var _inspect_t := 0.0            # 检视暗器（按 V）：把暗器翻过来看皮肤
var _punch_side := 1.0
# 切枪（参考 CoD，用户说原来"只是把枪拿出来，没手感"）：
#   收枪：手上这把往右下沉、枪口朝下、侧翻着收走（HOLSTER 秒）
#   掏枪：新的从右下斜着翻上来，稍微冲过头再落稳（按轻重 0.3~0.5 秒），落稳时一震 + 咔哒一声；
#   这局第一次掏出带机括的（连机神弩、穿云弩、千丝雨针、子母雷珠）还会拉一下栓 / 泵
const HOLSTER := 0.2
const HOL_POS := Vector3(0.07, -0.3, 0.07)
const HOL_ROT := Vector3(-0.75, 0.3, -0.85)
const RAISE_POS := Vector3(0.1, -0.3, 0.1)
const RAISE_ROT := Vector3(-0.6, 0.45, -1.0)
const HEAVY := ["hansha", "zimu", "zhuihun", "guanyin"]
var _hol_t := -1.0               # 收枪进行了多久（-1 = 没在收）
var _pending := ""               # 收完以后要掏的
var _raise_t := -1.0             # 掏枪进行了多久（-1 = 没在掏）
var _raise_len := 0.4
var _rack := false               # 这次掏枪要拉栓
var _drawn := {}                 # 这局掏过的暗器（第一次掏才拉栓）


func _ready() -> void:
	_build_models()
	_build_left_arm()
	set_weapon("xiujian", true)
	# 手里的东西不接收地上的贴花（站在法阵里暗器不会被染色）；之后换上的配件、道具也一样
	FxLib.no_decals(self)
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(n: Node) -> void:
	if n is VisualInstance3D and is_ancestor_of(n):
		(n as VisualInstance3D).layers = 2


func _build_models() -> void:
	for id in Data.WEAPON_ORDER + ["fist"]:
		var m := WeaponModels.build(id)
		m.visible = false
		add_child(m)
		models[id] = m
		var st := Profile.star_of(id)
		if st >= 3:
			_star_aura(m, Data.star_color(st), st)


## 升星突破过的暗器：身上一直飘着一层光点（灵光蓝 / 紫电 / 金身）
func _star_aura(m: Node3D, c: Color, st: int) -> void:
	var p := CPUParticles3D.new()
	p.name = "StarAura"
	p.amount = 8 + st * 2
	p.lifetime = 0.9
	p.local_coords = false
	p.mesh = U.sphere(0.006 + st * 0.0006, 6, 4)
	p.material_override = U.glow(c, 4.0 + st * 0.4, true)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.025, 0.03, 0.2)
	p.position = Vector3(0, 0.02, -0.12)
	p.direction = Vector3.UP
	p.spread = 40.0
	p.initial_velocity_min = 0.02
	p.initial_velocity_max = 0.08
	p.gravity = Vector3(0, 0.12, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.add_child(p)


## 换了暗器皮肤 / 装扮 / 配件：重建手里的模型
func apply_look() -> void:
	for k in models:
		(models[k] as Node).queue_free()
	models.clear()
	left_arm.queue_free()
	_build_models()
	_build_left_arm()
	for k in models:
		models[k].visible = k == cur and _item == null


func _build_left_arm() -> void:
	var mats := WeaponModels._mats()
	# 左手：手腕上缠着发光的引魂索
	left_arm = Node3D.new()
	left_arm.name = "LeftArm"
	add_child(left_arm)
	WeaponModels.fist(left_arm, mats, Vector3(0.0, -0.02, -0.06), Vector3(0.2, 0, -0.25), -1.0)
	WeaponModels.sleeve(left_arm, mats, Vector3(0.0, -0.022, -0.02), Vector3(-0.2, -0.4, 0.9))
	for n in left_arm.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	coil = U.part(left_arm, U.torus(0.043, 0.06, 24, 6), U.glow(Color(0.45, 0.8, 1.0), 2.5), Vector3(0.0, -0.022, 0.0), Vector3(PI / 2, 0, 0), Vector3.ONE, false)
	left_hand = Node3D.new()
	left_hand.position = Vector3(0.0, 0.0, -0.1)
	left_arm.add_child(left_hand)


## 手上换成一个道具（物品栏 3、4、5 号位）
func show_item(kind: String, key: String) -> void:
	if _item:
		_item.queue_free()
	_item = Loot.item_model(kind, key)
	add_child(_item)
	_item.scale = Vector3.ONE * (0.5 if kind == "bone" else 0.7)
	for n in _item.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for k in models:
		models[k].visible = false
	_switch = 1.0
	# 正在收枪 / 掏枪：直接结束（道具自己从下面升上来）
	if _hol_t >= 0.0:
		_hol_t = -1.0
		cur = _pending
	_raise_t = -1.0


## 换暗器。返回多久以后能开枪（Player.switch_t）
func set_weapon(id: String, instant := false) -> float:
	var had_item := _item != null
	if _item:
		_item.queue_free()
		_item = null
	_inspect_t = 0.0
	_switch = 0.0
	_kp = Vector3.ZERO
	_kr = Vector3.ZERO
	if instant:
		_hol_t = -1.0
		_raise_t = -1.0
		_drawn[id] = true
		_show_only(id)
		return 0.0
	# 正在收上一把：收完直接掏这把
	if _hol_t >= 0.0:
		_pending = id
		return (HOLSTER - _hol_t) + raise_time(id) * 0.8
	# 手上有暗器露着：先收枪
	if not had_item and models.has(cur) and (models[cur] as Node3D).visible and cur != id:
		_pending = id
		_hol_t = 0.0
		# 收枪：往右下一沉，皮套 / 布料一声
		Sfx.play("holster", -7.0, 0.06)
		return HOLSTER + raise_time(id) * 0.8
	_begin_raise(id)
	return _raise_len * 0.8


## 掏这把要多久：副手快、重的慢；第一次掏带机括的多一截（拉栓）
func raise_time(id: String) -> float:
	var t := 0.34 if (id in Data.SIDEARMS or id == "fist") else (0.6 if id in HEAVY else 0.48)
	if not _drawn.has(id) and id in ["zhuge", "zhuihun", "baoyu", "zimu"]:
		t += 0.22
	return t


func _begin_raise(id: String) -> void:
	_raise_len = raise_time(id)
	_rack = not _drawn.has(id) and id in ["zhuge", "zhuihun", "baoyu", "zimu"]
	_drawn[id] = true
	_raise_t = 0.0
	_show_only(id)
	# 掏枪：拔出来的摩擦声（轻的是皮套，重的是背带 + 金属）
	if id != "fist":
		Sfx.play("draw_heavy" if id in HEAVY or not id in Data.SIDEARMS else "draw_light", -5.0, 0.05)


func _show_only(id: String) -> void:
	cur = id
	for k in models:
		models[k].visible = k == id


## 回弹的缓动：冲过头一点再落回来（0 → 1）
static func _ease_back(t: float) -> float:
	var c1 := 1.35
	var c3 := c1 + 1.0
	var u := t - 1.0
	return 1.0 + c3 * u * u * u + c1 * u * u


## 收枪 / 掏枪的进度：返回 [收枪程度 0~1, 掏枪剩下的程度（1 = 还在最下面，负的 = 冲过头）]
func _switch_anim(dt: float) -> Vector2:
	var hk := 0.0
	if _hol_t >= 0.0:
		_hol_t += dt
		var h := clampf(_hol_t / HOLSTER, 0.0, 1.0)
		hk = h * h
		if _hol_t >= HOLSTER:
			_hol_t = -1.0
			hk = 0.0
			_begin_raise(_pending)
	var rk := 0.0
	if _raise_t >= 0.0:
		_raise_t += dt
		var t := clampf(_raise_t / _raise_len, 0.0, 1.0)
		# 要拉栓的：前七成掏上来，后面拉栓
		var up := clampf(t / (0.7 if _rack else 1.0), 0.0, 1.0)
		rk = 1.0 - _ease_back(up)
		if _rack and t >= 0.62 and _lever_t <= 0.0:
			_rack = false
			_lever_t = 0.3
			_lever_len = 0.3
			var snd := "bolt_cycle" if cur == "zhuihun" else ("pump" if cur in ["baoyu", "zimu"] else "rack")
			Sfx.play(snd, -3.0, 0.04, 1.05)
			# 拉栓那一下手上一顿
			_kpv += Vector3(0.05, -0.1, 0.4)
			_krv += Vector3(-0.5, 0.3, 0.9)
		if t >= 1.0:
			_raise_t = -1.0
			rk = 0.0
			# 落稳：往上一震、咔哒一声（重的震得更沉）
			var hv := 1.4 if cur in HEAVY else 1.0
			_krv += Vector3(1.2, randf_range(-0.3, 0.3), 0.8 * (1.0 if randf() < 0.5 else -1.0)) * hv
			_kpv += Vector3(0, 0.2, -0.45) * hv
			if cur != "fist":
				Sfx.play("settle", -6.0, 0.06, 1.0 if cur in HEAVY else 1.15)
	return Vector2(hk, rk)


func model() -> Node3D:
	return models[cur]


func muzzle_global() -> Vector3:
	var n := model().get_node_or_null("Muzzle")
	return n.global_position if n else global_position


func hand_global() -> Vector3:
	return left_hand.global_position


func two_handed() -> bool:
	return not cur in Data.SIDEARMS and cur != "fist" and _item == null


const INSPECT_TIME := 2.4


func inspect() -> void:
	_inspect_t = INSPECT_TIME


## 空手出拳：side 1 右拳、-1 左拳
func punch(side: float) -> void:
	_punch_t = 1.0
	_punch_side = side


func add_sway(mouse_delta: Vector2) -> void:
	_sway_target += mouse_delta * 0.00018


## 开火：往后顶、往上抬、随机翻滚一点；弩臂往前弹；机括动一下
func kick(back: float, up: float, lever_time := 0.0) -> void:
	_kpv += Vector3(randf_range(-0.25, 0.25), 0.2, 1.0) * back * 1.6
	_krv += Vector3(up * 1.4, randf_range(-0.35, 0.35) * up, randf_range(-0.8, 0.8) * up)
	_arm_flex = 1.0
	_inspect_t = 0.0
	if lever_time > 0.0:
		_lever_t = lever_time
		_lever_len = lever_time


## 开镜到位：贴脸那一下往前一顶、微微一沉；关镜：往下一放
func ads_settle(on: bool) -> void:
	if on:
		_kpv += Vector3(0, -0.06, 0.3)
		_krv += Vector3(-0.35, 0.0, randf_range(-0.2, 0.2))
	else:
		_kpv += Vector3(0.05, -0.12, -0.15)
		_krv += Vector3(0.3, 0.1, 0.25)


func land(amount: float) -> void:
	_land = clampf(amount, 0.0, 1.0)


func throw_anim() -> void:
	_left_throw = 1.0


func pull_anim(v: float) -> void:
	_left_pull = v


func _ads_pos(id: String) -> Vector3:
	var s := models[id].get_node_or_null("Sight") as Node3D
	var sp := s.position if s else Vector3.ZERO
	return Vector3(0, 0, -float(ADS_DIST.get(id, 0.2))) - sp


## 每帧：ads 开镜进度，speed_k 速度/走路速度，reload_k 换弹进度，strafe 左右输入
func update(dt: float, ads: float, speed_k: float, grounded: bool, reload_k: float, sprint: float, strafe: float, lure_busy: bool, per_shell: bool) -> void:
	_idle_t += dt
	# 弹簧：固定小步长积分，某一帧卡了很久（加载、切出窗口）也不会发散
	var left := minf(dt, 0.1)
	while left > 0.0:
		var h := minf(left, 1.0 / 240.0)
		var a := -_kp * SPRING_K - _kpv * SPRING_C
		_kpv += a * h
		_kp += _kpv * h
		var ar := -_kr * SPRING_K * 0.8 - _krv * SPRING_C * 0.9
		_krv += ar * h
		_kr += _krv * h
		left -= h
	# 鼠标拖拽的滞后
	_sway_target = _sway_target.lerp(Vector2.ZERO, 1.0 - exp(-10.0 * dt))
	_sway = _sway.lerp(_sway_target, 1.0 - exp(-16.0 * dt))
	_move_tilt = U.damp(_move_tilt, -strafe * 0.06, 8.0, dt)
	_switch = move_toward(_switch, 0.0, dt / 0.28)
	_land = U.damp(_land, 0.0, 8.0, dt)
	_left_throw = move_toward(_left_throw, 0.0, dt / 0.3)
	_arm_flex = move_toward(_arm_flex, 0.0, dt / 0.12)
	if _lever_t > 0.0:
		_lever_t = maxf(_lever_t - dt, 0.0)
	if grounded and speed_k > 0.1:
		_bob_t += dt * lerpf(7.5, 11.5, sprint) * clampf(speed_k, 0.4, 1.3)
		_bob_amt = U.damp(_bob_amt, clampf(speed_k, 0.0, 1.3), 8.0, dt)
	else:
		_bob_amt = U.damp(_bob_amt, 0.0, 6.0, dt)

	_punch_t = move_toward(_punch_t, 0.0, dt / 0.26)
	var sw := _switch_anim(dt)
	# 全屏瞄准镜开着时手里的东西藏起来（像 CS 的狙击镜）
	visible = not scoped
	var m := model()
	m.visible = _item == null
	if _item:
		# 拿着道具：右手托在前面，跟着走路晃
		_item.position = Vector3(0.2, -0.2 - _switch * 0.3, -0.45) + Vector3(sin(_bob_t) * 0.012, -absf(cos(_bob_t)) * 0.014, 0) * _bob_amt + Vector3(-_sway.x, _sway.y, 0)
		_item.rotation = Vector3(0.3, _idle_t * 0.8, 0.2)
	var ads_k := ads * ads * (3.0 - 2.0 * ads)
	var p: Vector3 = (HIP[cur] as Vector3).lerp(_ads_pos(cur), ads_k)
	var calm := lerpf(1.0, 0.12, ads_k)
	# 走路晃动（8 字形）、呼吸
	p += Vector3(sin(_bob_t) * 0.011, -absf(cos(_bob_t)) * 0.013, 0) * _bob_amt * calm
	p += Vector3(sin(_idle_t * 1.1) * 0.0015, sin(_idle_t * 1.7) * 0.002, 0) * calm
	p += Vector3(-_sway.x, _sway.y, 0) * lerpf(1.0, 0.25, ads_k)
	p += _kp * Vector3(0.3, 0.3, 1.0) * lerpf(1.0, 0.55, ads_k)
	p.y -= _land * 0.045 * calm
	p.y -= _switch * 0.32
	# 切枪：收的往右下沉走，掏的从右下翻上来
	p += HOL_POS * sw.x + RAISE_POS * sw.y
	# 换弹：放低、侧过来
	var rs := sin(reload_k * PI)
	if per_shell:
		rs = minf(reload_k * 6.0, 1.0) if reload_k > 0.0 else 0.0
	p += Vector3(-0.02, -0.07, 0.03) * rs
	# 冲刺：暗器斜着放低
	p += Vector3(-0.03, -0.05, 0.04) * sprint * (1.0 - ads_k)
	# 检视：举到眼前翻过来看一圈，再放回去
	var insp := Vector3.ZERO
	if _inspect_t > 0.0:
		_inspect_t = 0.0 if ads > 0.05 or reload_k > 0.0 else maxf(_inspect_t - dt, 0.0)
		var ph := 1.0 - _inspect_t / INSPECT_TIME
		var e := sin(ph * PI)
		e = e * e * (3.0 - 2.0 * e)
		p += Vector3(-0.1, 0.06, 0.06) * e
		insp = Vector3(0.25 * e + sin(ph * TAU * 1.5) * 0.12 * e, 1.3 * e * (1.0 if ph < 0.55 else lerpf(1.0, -0.4, (ph - 0.55) / 0.45)), 0.5 * sin(ph * TAU) * e)
	m.position = p
	m.rotation = Vector3(
		_kr.x + rs * 0.35 - sprint * 0.35 * (1.0 - ads_k) + _switch * 0.5 + insp.x,
		-_sway.x * 1.4 + _kr.y + sprint * 0.55 * (1.0 - ads_k) + insp.y,
		-_sway.x * 1.8 + _kr.z + rs * 0.55 + _move_tilt * calm + insp.z) + HOL_ROT * sw.x + RAISE_ROT * sw.y

	_animate_parts(m, reload_k, per_shell)
	_animate_extras(m, dt)
	if cur == "fist":
		_animate_fists(m, sprint)

	# 左手：单手暗器时一直在左下角；双手暗器平时托着暗器，甩引魂索时才伸出来
	# 左手平时收着，只有甩引魂索、扔东西时伸出来（双手暗器由模型里的左手托着）
	var show_left := lure_busy or _left_throw > 0.0
	_left_show = move_toward(_left_show, 1.0 if show_left else 0.0, dt / 0.15)
	var lh := m.get_node_or_null("LeftHand")
	if lh:
		lh.visible = _left_show < 0.5
	var lp := Vector3(-0.26, -0.22, -0.42)
	lp += Vector3(sin(_bob_t + PI) * 0.01, -absf(cos(_bob_t)) * 0.012, 0) * _bob_amt
	lp += Vector3(0.08, 0.12, -0.14) * sin(_left_throw * PI)
	lp += Vector3(0.02, 0.03, 0.1) * _left_pull
	lp.y -= ads_k * 0.14
	lp.y -= _land * 0.05
	lp.y -= (1.0 - _left_show) * 0.35
	left_arm.position = lp
	left_arm.rotation = Vector3(0.15 + 0.2 * sin(_left_throw * PI) - _left_pull * 0.3, -0.2, 0.25)
	left_arm.visible = _left_show > 0.02
	coil.rotation.y += dt * 2.0


## 流沙机弩的枪管转、天心泪的泪滴随蓄力变亮、挂件像摆一样晃
func _animate_extras(m: Node3D, dt: float) -> void:
	var rotor := m.get_node_or_null("Rotor") as Node3D
	if rotor:
		_rotor += dt * spin * 40.0
		rotor.rotation.z = _rotor
	var tear := m.get_node_or_null("Tear") as Node3D
	if tear and m.has_meta("tear_mat"):
		var tm: StandardMaterial3D = m.get_meta("tear_mat")
		tm.emission_energy_multiplier = lerpf(1.5, 7.0, charge) * (1.0 + 0.15 * sin(_idle_t * 30.0) * charge)
		tear.scale = Vector3.ONE * lerpf(1.0, 1.5, charge)
		tear.position.x = sin(_idle_t * 47.0) * 0.0015 * charge
	var ch := m.get_node_or_null("Charm") as Node3D
	if ch:
		# 摆：人加速 / 暗器后坐 / 鼠标甩动 推它，弹簧拉回来
		var acc := (move_vel - _last_vel) / maxf(dt, 0.001)
		_last_vel = move_vel
		var lb := global_basis.inverse()
		var la := lb * acc
		var push := Vector2(la.z * 0.02 + _kpv.z * 3.0, -la.x * 0.02 - _sway.x * 20.0)
		_charm_v += (push - _charm_a * 60.0 - _charm_v * 4.0) * dt
		_charm_a += _charm_v * dt
		_charm_a = _charm_a.clamp(Vector2(-1.1, -1.1), Vector2(1.1, 1.1))
		# 暗器本身会转（检视、开镜），挂件要保持往下垂：先抵消暗器的旋转，再加上摆角
		var down := (m.global_basis.inverse() * Vector3.DOWN).normalized()
		var base := Basis.looking_at(Vector3.FORWARD, -down) if absf(down.dot(Vector3.FORWARD)) < 0.95 else Basis.IDENTITY
		ch.basis = base * Basis.from_euler(Vector3(_charm_a.x, 0, _charm_a.y))


## 两只拳头：出拳的那只快速往前打再收回，另一只护在脸前
func _animate_fists(m: Node3D, sprint: float) -> void:
	var k := sin(_punch_t * PI) if _punch_t > 0.0 else 0.0
	k = k * k * (3.0 - 2.0 * k)
	for side in [1.0, -1.0]:
		var n := m.get_node_or_null("FistR" if side > 0 else "LeftHand") as Node3D
		if n == null:
			continue
		var base := Vector3(0.16 * side, -0.17, -0.33)
		var hit := k if side == _punch_side else 0.0
		var guard := (k * 0.3) if side != _punch_side else 0.0
		n.position = base + Vector3(-0.12 * side * hit, 0.07 * hit, -0.24 * hit) + Vector3(0, -0.05 * sprint, 0.04 * guard)
		n.rotation = Vector3(-0.35 * hit - sprint * 0.3, 0.3 * side * hit, 0.25 * side * hit)


func _animate_parts(m: Node3D, reload_k: float, per_shell: bool) -> void:
	# 弩臂开火往前弹
	for n in ["ArmL", "ArmR"]:
		var arm := m.get_node_or_null(n) as Node3D
		if arm:
			if not arm.has_meta("ry"):
				arm.set_meta("ry", arm.rotation.y)
			var side := -1.0 if n == "ArmL" else 1.0
			arm.rotation.y = float(arm.get_meta("ry")) + side * 0.22 * _arm_flex
	# 弹匣：前 30% 往下拆掉，中间看不见，后 30% 装回来
	var mag := m.get_node_or_null("Mag") as Node3D
	if mag:
		if not mag.has_meta("y"):
			mag.set_meta("y", mag.position.y)
			mag.set_meta("z", mag.position.z)
		var off := 0.0
		if reload_k > 0.0 and not per_shell:
			if reload_k < 0.3:
				off = reload_k / 0.3
			elif reload_k < 0.65:
				off = 1.0
			else:
				off = 1.0 - (reload_k - 0.65) / 0.35
		elif per_shell and reload_k > 0.0:
			off = sin(fmod(reload_k * 6.0, 1.0) * PI) * 0.4
		mag.position.y = float(mag.get_meta("y")) - off * 0.14
		mag.position.z = float(mag.get_meta("z")) + off * 0.05
		mag.visible = off < 0.95
	# 机括：连机神弩的拉杆、穿云弩的栓、千丝雨针的泵
	var lever := m.get_node_or_null("Lever") as Node3D
	if lever:
		if not lever.has_meta("rest"):
			lever.set_meta("rest", lever.transform)
		var rest: Transform3D = lever.get_meta("rest")
		var k := 0.0
		if _lever_len > 0.0:
			k = 1.0 - _lever_t / _lever_len
		var t := rest
		match cur:
			"zhuge":
				t = rest.rotated_local(Vector3.RIGHT, sin(k * PI) * 0.55) if _lever_t > 0.0 else rest
			"zhuihun":
				if _lever_t > 0.0:
					var up := smoothstep(0.0, 0.25, k) - smoothstep(0.75, 1.0, k)
					var back := smoothstep(0.25, 0.5, k) - smoothstep(0.5, 0.75, k)
					t = rest.rotated_local(Vector3.FORWARD, up * 1.2)
					t.origin += Vector3(0, 0, back * 0.07)
			"baoyu", "zimu":
				if _lever_t > 0.0:
					t.origin += Vector3(0, 0, sin(k * PI) * 0.07)
		lever.transform = t
