class_name WeakGlint
extends Node3D
## 弱点金光（破绽）：头上一团一闪一闪的金光 + 一圈往里收的光环 + 暖光，跟着头走，dur 秒后淡掉。
## 用户看了以前头上飘的「破绽」两个字："不是很搞笑么"——好游戏不写字，让怪物自己露出来：
## 踉跄的动作（KingFeel / Boss 里做）+ 发光的弱点（这里）+ 一声闷响。第一次出现时提示一句怎么打（stats.tip_open）

var follow: Callable            # 每帧问它头在哪（返回 Vector3.INF 就收掉）
var dur := 1.0
var size := 1.0
var _age := 0.0
var _flare: MeshInstance3D
var _ring: MeshInstance3D
var _light: OmniLight3D


static func spawn(parent: Node, follow_fn: Callable, t: float, sz: float) -> WeakGlint:
	var g := WeakGlint.new()
	g.follow = follow_fn
	g.dur = t
	g.size = sz
	parent.add_child(g)
	g._build()
	var p: Variant = follow_fn.call() if follow_fn.is_valid() else Vector3.INF
	if p is Vector3 and p != Vector3.INF:
		g.global_position = p
	return g


## 已经在闪：再露一次破绽就接着闪
func extend(t: float) -> void:
	dur = maxf(dur, _age + t)


static func tip_once(world: Node) -> void:
	KingFeel.tip(world, "open", "打它发光的头")


func _build() -> void:
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	_flare = MeshInstance3D.new()
	_flare.mesh = q
	_flare.material_override = FxLib.bill_mat("flare", Color(1.0, 0.82, 0.35), 3.0)
	_flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flare)
	_ring = MeshInstance3D.new()
	_ring.mesh = q
	_ring.material_override = FxLib.bill_mat("ring", Color(1.0, 0.72, 0.28), 2.2)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.75, 0.35)
	_light.omni_range = 4.0 * size
	_light.light_energy = 0.0
	add_child(_light)
	_flare.scale = Vector3.ZERO
	_ring.scale = Vector3.ZERO


func _process(dt: float) -> void:
	_age += dt
	if not follow.is_valid():
		queue_free()
		return
	var p: Variant = follow.call()
	if not (p is Vector3) or p == Vector3.INF:
		queue_free()
		return
	global_position = p
	var fade := clampf((dur - _age) / 0.4, 0.0, 1.0) * clampf(_age / 0.15, 0.0, 1.0)
	var pulse := 0.75 + 0.25 * sin(_age * 9.0)
	_flare.scale = Vector3.ONE * size * 1.5 * pulse * fade
	# 光圈一下一下往里收："打这里"
	var k := fmod(_age * 1.3, 1.0)
	_ring.scale = Vector3.ONE * size * lerpf(3.2, 0.7, k) * fade
	_ring.transparency = k * 0.8
	_light.light_energy = 2.2 * pulse * fade
	if _age >= dur:
		queue_free()
