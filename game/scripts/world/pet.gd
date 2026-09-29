class_name Pet
extends Node3D
## 灵宠（第 7.5 节第四根柱子，2026-09-29）：活捉的灵兽王驯成灵宠，跟着你走。
## 用户定的硬规矩："单人必须完整好玩，多人是锦上添花"——灵宠是给单人的帮手：
##   打架时扑上去咬（按你手里暗器的持续输出算 DPS_K），每 SKILL_CD 秒放一次它这一类的本事（按 Gear.KIND 分八类）；
##   单人倒下被海鸥叼走时，它会扑上去把海鸥撞下来（REVIVE_CD 一次）
##   人越多越弱：两个人伤害减半，三个人以上只跟着跑
## 只有自己的灵宠会打（local）；队友看到的是跟着那个人跑的样子（peer_info.pet）

const FOLLOW_DIST := 3.2
const SPEED := 9.0
const ATK_CD := 1.6
const ATK_RANGE := 20.0
const SKILL_CD := 18.0
const DPS_K := 0.16
const REVIVE_CD := 180.0
const REVIVE_AFTER := 4.0
const LEN := 1.3                 # 灵宠身长（米）

const SKILLS := {
	"swift": {"name": "扑咬", "desc": "扑上去狠狠咬一口"},
	"iron": {"name": "护主", "desc": "给你挡一层护盾"},
	"breaker": {"name": "撼", "desc": "撞它的头，帮你把它撞晕"},
	"bind": {"name": "缠", "desc": "缠住它一会儿"},
	"sky": {"name": "啄目", "desc": "啄它的眼睛，全队打它更痛"},
	"hunter": {"name": "追咬", "desc": "咬住它的腿，让它跑不快"},
	"counter": {"name": "麻", "desc": "一口下去它慢下来"},
	"renew": {"name": "回春", "desc": "给你回一截血"},
}

static var _revive_ready := 0.0

var world: Node
var owner_node: Node3D
var species := ""
var local := false
var model: Node3D
var _t := 0.0
var _vel := Vector3.ZERO
var _atk_t := 1.0
var _skill_t := 6.0
var _lunge_to := Vector3.INF
var _lunge_t := 0.0
var _carried_t := 0.0
var _fly := false


static func spawn(p_world: Node, p_owner: Node3D, sp: String, is_local: bool) -> Pet:
	var p := Pet.new()
	p.name = "Pet"
	p.world = p_world
	p.owner_node = p_owner
	p.species = sp
	p.local = is_local
	p_world.add_child(p)
	p.global_position = p_owner.global_position + Vector3(2.0, 0.0, 2.0)
	return p


static func kind(sp: String) -> String:
	return str(Gear.KIND.get(sp, "swift"))


static func skill_of(sp: String) -> Dictionary:
	return SKILLS.get(kind(sp), SKILLS["swift"])


func _ready() -> void:
	_fly = str(Data.BEASTS[species].get("motion", "")) in ["fly", "flutter"]
	model = BeastModels.build(species, 1)
	var bs := BeastModels.body_size(species)
	model.scale = Vector3.ONE * (LEN / maxf(maxf(bs.z, bs.x), 0.2))
	add_child(model)
	# 一圈淡淡的灵光，认得出是自己的灵宠
	var l := OmniLight3D.new()
	l.light_color = Color(0.6, 0.9, 1.0)
	l.omni_range = 2.2
	l.light_energy = 0.5
	l.position.y = 0.8
	add_child(l)


## 人越多越弱：一个人 1，两个人 0.5，三个人以上 0（只跟着跑）
func _team_k() -> float:
	var n: int = world._all_peers().size()
	return 1.0 if n <= 1 else (0.5 if n == 2 else 0.0)


func _process(dt: float) -> void:
	if not is_instance_valid(owner_node):
		queue_free()
		return
	_t += dt
	var op := owner_node.global_position
	var fwd := -owner_node.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.FORWARD
	var goal := op - fwd * FOLLOW_DIST + fwd.cross(Vector3.UP) * 1.2
	if _lunge_t > 0.0:
		_lunge_t -= dt
		goal = _lunge_to
	var to := goal - global_position
	to.y = 0.0
	if to.length() > 45.0:
		# 离得太远（传送、坐船）：直接跟过来
		global_position = goal
		to = Vector3.ZERO
	var want := Vector3.ZERO
	if to.length() > 0.6:
		var spd := SPEED * (1.8 if _lunge_t > 0.0 else clampf(to.length() / 4.0, 0.4, 1.6))
		want = to.normalized() * spd
	_vel = _vel.lerp(want, 1.0 - exp(-6.0 * dt))
	var p := global_position + _vel * dt
	var gy: float = world.island.height_at(p.x, p.z)
	p.y = maxf(gy, Island.WATER_Y) + (1.8 + sin(_t * 2.0) * 0.2 if _fly else 0.02)
	global_position = p
	var hv := Vector2(_vel.x, _vel.z)
	if hv.length() > 0.3:
		var yaw := atan2(-_vel.x, -_vel.z)
		rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-8.0 * dt))
	BeastModels.animate(model, _t, _fly, hv.length())
	if local:
		_combat(dt)
		_rescue(dt)


# ------------------------------------------------------------------ 自己的灵宠：打架、放本事、救人

func _target() -> Beast:
	var best: Beast = null
	var bd := ATK_RANGE
	var op := owner_node.global_position
	for b: Beast in world.beasts.values():
		if not b.alive():
			continue
		# 只咬灵兽王（猎物、守宝王）和秘境里的灵兽；野外胆小的不管
		if b.temper != "elite" and b.hunt_role == "":
			continue
		var d := op.distance_to(b.global_position)
		if d < bd:
			bd = d
			best = b
	return best


func _combat(dt: float) -> void:
	var k := _team_k()
	if k <= 0.0 or world.player.dead:
		return
	_atk_t -= dt
	_skill_t -= dt
	var b := _target()
	if b == null:
		return
	if _atk_t <= 0.0:
		_atk_t = ATK_CD
		_lunge(b)
		world.pet_hit(b, _dps() * ATK_CD * k, "")
	if _skill_t <= 0.0:
		_skill_t = SKILL_CD
		_skill(b, k)


## 按主人手里暗器的持续输出算（空手、道具时按一把袖箭算）
func _dps() -> float:
	var g: Gun = world.player.gun
	var d: Dictionary = g.d if g and g.id != "fist" else Profile.weapon_stats("xiujian")
	return Data.weapon_output(d).y * world.player.damage_mult() * DPS_K


func _lunge(b: Beast) -> void:
	var to := b.global_position - global_position
	to.y = 0.0
	_lunge_to = b.global_position - to.normalized() * (1.0 + BeastModels.body_size(b.species).z * 0.3)
	_lunge_t = 0.5
	BeastModels.play_attack(model)
	Sfx.play_at("bite", global_position, -6.0, 0.1, 1.3)


func _skill(b: Beast, k: float) -> void:
	var p: Node = world.player
	var pos := b.global_position + Vector3.UP * 0.8
	match kind(species):
		"swift":
			_lunge(b)
			world.pet_hit(b, _dps() * ATK_CD * 4.0 * k, "")
			world.fx._sparks(pos, Vector3.UP, Color(1.0, 0.6, 0.4), 16, 6.0, 0.5, 0.06, -6.0, 120.0)
		"iron":
			p.shield = maxf(p.shield, Profile.max_hp() * 0.15)
			p.shield_t = maxf(p.shield_t, 8.0)
			world.fx.shield_bubble(p, 1.2, Color(0.7, 0.85, 1.0))
		"breaker":
			_lunge(b)
			world.pet_hit(b, _dps() * ATK_CD * k, "pet_stun")
		"bind":
			world.pet_hit(b, _dps() * k, "pet_bind")
			world.fx._air_ring(pos, Color(0.5, 0.95, 0.55), 0.4, 2.5, 0.5, 0.8, "ring", 2.0)
		"sky", "hunter":
			_lunge(b)
			world.pet_hit(b, _dps() * ATK_CD * k, "pet_mark" if kind(species) == "sky" else "pet_slow")
		"counter":
			_lunge(b)
			world.pet_hit(b, _dps() * ATK_CD * k, "pet_slow")
		"renew":
			p.heal(Profile.max_hp() * 0.12)
			world.fx._sparks(p.global_position + Vector3.UP, Vector3.UP, Color(0.6, 1.0, 0.6), 18, 3.0, 0.8, 0.06, 1.0, 180.0)
	Sfx.play_at("skill_cast", global_position, -4.0, 0.05, 1.4)


## 单人倒下被海鸥叼走：过一会儿扑上去把海鸥撞下来（REVIVE_CD 一次）
func _rescue(dt: float) -> void:
	var p: Node = world.player
	if not (p.dead and p.carried) or _team_k() < 1.0:
		_carried_t = 0.0
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _revive_ready:
		return
	_carried_t += dt
	if _carried_t < REVIVE_AFTER:
		return
	_carried_t = 0.0
	_revive_ready = now + REVIVE_CD
	world.fx._flash(p.global_position, Color(0.6, 0.9, 1.0), 3.0, 0.2)
	Sfx.play("skill_leap", -2.0, 0.0, 1.2)
	world.hud.toast("%s把海鸥撞了下来" % str(Data.BEASTS[species]["name"]), Color(0.6, 0.9, 1.0), 3.0)
	if Net.is_host():
		world.loot._host_gull_hit(-Net.my_id, Net.my_id)
	else:
		Net.send_host("gullhit", [-Net.my_id])
