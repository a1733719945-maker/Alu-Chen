class_name KingFeel
extends Node
## 样板狩猎（CLAUDE.md 第 7 节第一步，2026-09-29）：猎场猎物（hunt_role == "target"）的手感——
##   部位破坏：头角 / 背甲 / 尾（会飞的：头角 / 翼 / 尾），按命中点记伤害，打够了就断——
##             模型上那截真的没了（BoneHide 把骨头缩成一点），再复制一份模型只留断下来的那截，掉在地上；王摔一跤（倒地 2.5 秒）。
##             断尾：放不出震地（甩尾扫一圈）；断角：不会咆哮、更容易打晕；断背甲：全身受伤 +25%；断翼：飞不起来。
##             每断一处，附近的人拿一份部位材料（Profile.parts，以后做装备用）
##   打晕：打头攒晕值，满了倒地 5 秒——受伤 ×1.4、打头再 ×1.6（露出弱点，全队集火）；每晕一次，下次要攒得更多
##   怒气 / 疲劳：挨打、缠斗攒怒气，满了暴怒 28 秒（更快更狠、冒红气），怒完累 18 秒
##             （变慢、不放大招、喘粗气；这时捆魂更久，三成五血以下就能活捉）
## 房主算：Beast.take_hit → host_hit，Beast._elite → host_tick；状态发 kfeel（变化时 / 每 2 秒），事件发 kfev。
## 客人收到 kfeel 时给那只灵兽挂一个（只做样子：断肢、倒地、冒气、HUD）

const PARTS_LAND := ["head", "back", "tail"]
const PARTS_FLY := ["head", "wing", "tail"]
const PART_NAME := {"head": "头角", "back": "背甲", "tail": "尾", "wing": "翼"}
const PART_HP := {"head": 0.2, "back": 0.24, "tail": 0.16, "wing": 0.2}   # 占最大血量
## 断的时候藏哪几根骨头（模型里有才藏；没有就只掉碎片）
const PART_BONES := {"tail": ["Tail2", "Tail1"], "head": ["Ear1.L", "Ear1.R"], "wing": ["Wing3.L", "Wing3.R"], "back": []}
const STUN_BASE := 0.1        # 打头攒多少伤害倒地（占最大血量），每晕一次 ×1.5
const DOWN_STUN := 5.0
const DOWN_BREAK := 2.5
const RAGE_TIME := 28.0
const TIRED_TIME := 18.0

var world: Node
var b: Beast
var host := false
var parts := {}               # 名字 -> {"hp", "max", "broken"}
var stun := 0.0
var stun_max := 1.0
var stuns := 0
var down_t := 0.0
var down_why := ""
var rage := 0.0               # 0~100
var mood := "calm"            # calm / rage / tired
var mood_t := 0.0
var _dirty := true
var _sync_t := 0.0
var _front := Vector3(0, 0, -1)   # 灵兽本地坐标里头朝哪边（按 Head / Tail1 骨头算）
var _center := Vector3.ZERO
var _half := 1.0
var _height := 1.0
var _hider: BoneHide
var _skel: Skeleton3D
var _base_rot := Vector3.ZERO
var _tilt := 0.0
var _fx_t := 0.0
var _pieces: Array = []       # 掉下来的断肢 {"n", "v", "w", "t", "g"}
## 样板狩猎第二步（KingArts）：破绽（招打空了 / 落地没站稳：受伤 ×1.3、打头再 ×1.5）、第几回合、起手的姿势
const OPEN_K := 1.3
const OPEN_HEAD := 1.5
var open_t := 0.0
var act := 1
var _pose := ""
var _pose_t := 0.0
var _pose_len := 1.0
var _glint: WeakGlint


## 房主：给猎物挂上
static func attach(p_world: Node, beast: Beast) -> KingFeel:
	if beast.feel:
		return beast.feel
	var f := KingFeel.new()
	f.world = p_world
	f.b = beast
	f.host = true
	beast.feel = f
	beast.add_child(f)
	f._init_parts()
	return f


## 客人：收到 kfeel 时挂上（只做样子）
static func ensure(p_world: Node, beast: Beast) -> KingFeel:
	if beast.feel:
		return beast.feel
	var f := KingFeel.new()
	f.world = p_world
	f.b = beast
	beast.feel = f
	beast.add_child(f)
	f._init_parts()
	return f


func _init_parts() -> void:
	name = "KingFeel"
	var fly := b.motion() in ["fly", "flutter"]
	for p in (PARTS_FLY if fly else PARTS_LAND):
		var mx: float = b.max_hp * float(PART_HP[p])
		parts[p] = {"hp": mx, "max": mx, "broken": false}
	stun_max = b.max_hp * STUN_BASE
	_base_rot = b.model.rotation
	var sks := b.model.find_children("*", "Skeleton3D", true, false)
	if sks.size() > 0:
		_skel = sks[0]
	_measure()


## 灵兽本地坐标里：身体中心、头朝哪边、多长多高（按命中点分部位用）
func _measure() -> void:
	var inv := b.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for n in b.model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var bb := inv * mi.global_transform * mi.mesh.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	if first:
		box = AABB(Vector3(-0.5, 0, -1), Vector3(1, 1, 2))
	_center = box.get_center()
	_height = maxf(box.size.y, 0.3)
	var hb := _bone_local("Head")
	var tb := _bone_local("Tail1")
	if hb != Vector3.INF and tb != Vector3.INF and hb.distance_to(tb) > 0.1:
		_front = Vector3(hb.x - tb.x, 0, hb.z - tb.z).normalized()
	elif hb != Vector3.INF:
		_front = Vector3(hb.x - _center.x, 0, hb.z - _center.z).normalized()
	_half = maxf(absf(box.size.dot(Vector3(absf(_front.x), 0, absf(_front.z)))) * 0.5, 0.3)


func _bone_local(nm: String) -> Vector3:
	if _skel == null:
		return Vector3.INF
	var i := _skel.find_bone(nm)
	if i < 0:
		return Vector3.INF
	return b.global_transform.affine_inverse() * (_skel.global_transform * _skel.get_bone_global_pose(i).origin)


func broken(p: String) -> bool:
	return parts.has(p) and bool(parts[p]["broken"])


## 命中点（灵兽本地坐标）落在哪个部位
func _part_at(lp: Vector3) -> String:
	var rel := lp - _center
	var s := rel.dot(_front) / _half
	if s > 0.45:
		return "head"
	if s < -0.5:
		return "tail"
	if parts.has("wing") and absf(rel.dot(_front.cross(Vector3.UP))) > _half * 0.45:
		return "wing"
	if parts.has("back") and rel.y > _height * 0.12:
		return "back"
	return ""


# ------------------------------------------------------------------ 房主

## Beast.take_hit 调：返回改过的伤害（倒地时更痛、断了背甲更痛），顺便记部位、晕值、怒气
func host_hit(real: float, lp: Vector3, headshot: bool) -> float:
	var k := 1.0
	if down_t > 0.0:
		k *= 1.4 * (1.6 if headshot else 1.0)
	if broken("back"):
		k *= 1.25
	if open_t > 0.0:
		k *= OPEN_K * (OPEN_HEAD if headshot else 1.0)
	real *= k
	var part := "head" if headshot else _part_at(lp)
	if part != "" and parts.has(part) and not broken(part):
		parts[part]["hp"] = float(parts[part]["hp"]) - real
		_dirty = true
		if float(parts[part]["hp"]) <= 0.0:
			_host_break(part)
	if part == "head" and down_t <= 0.0:
		stun += real * (1.5 if broken("head") else 1.0)
		_dirty = true
		if stun >= stun_max:
			stun = 0.0
			stuns += 1
			stun_max *= 1.5
			_host_down("stun", DOWN_STUN)
	if mood == "calm":
		rage = minf(rage + real / maxf(b.max_hp, 1.0) * 220.0, 100.0)
	return real


## Beast._elite 调：倒地计时、怒气 → 暴怒 → 疲劳 → 平静
func host_tick(dt: float) -> void:
	if b.arts and b.arts.act != act:
		act = b.arts.act
		_dirty = true
	if down_t > 0.0:
		down_t = maxf(down_t - dt, 0.0)
		if down_t <= 0.0:
			_dirty = true
	match mood:
		"calm":
			if b._aggro_t > 0.0:
				rage = minf(rage + dt * 1.5, 100.0)
			if rage >= 100.0:
				mood = "rage"
				mood_t = RAGE_TIME
				b.enrage_t = RAGE_TIME
				_event("rage", "")
		"rage":
			mood_t -= dt
			b.enrage_t = maxf(b.enrage_t, mood_t)
			if mood_t <= 0.0:
				mood = "tired"
				mood_t = TIRED_TIME
				b.enrage_t = 0.0
				_event("tired", "")
		"tired":
			mood_t -= dt
			if mood_t <= 0.0:
				mood = "calm"
				rage = 0.0
				_dirty = true
	_sync_t -= dt
	if _dirty or _sync_t <= 0.0:
		_send_state()


func _host_break(part: String) -> void:
	parts[part]["broken"] = true
	parts[part]["hp"] = 0.0
	_event("break", part)
	if down_t < DOWN_BREAK:
		_host_down("break", DOWN_BREAK)


func _host_down(why: String, t: float) -> void:
	down_t = t
	down_why = why
	b._king_wind = 0.0
	b._sk_wind = 0.0
	if b.arts:
		b.arts.cancel()
	if why == "stun":
		_event("down", why)
	_dirty = true


func _event(kind: String, arg: String) -> void:
	var m := [b.id, kind, arg]
	Net.send(0, "kfev", m)
	_on_event(kind, arg)
	_send_state()


func _send_state() -> void:
	_dirty = false
	_sync_t = 2.0
	var ps: Array = []
	for p in parts:
		ps.append([p, -1.0 if broken(p) else float(parts[p]["hp"]) / maxf(float(parts[p]["max"]), 1.0)])
	Net.send(0, "kfeel", [b.id, ps, stun / maxf(stun_max, 1.0), down_t, mood, mood_t, rage, act, open_t])


## 这一刻能不能放这招（Beast._king_tick 调）：累了不放大招；断尾没有震地；断角不会咆哮；倒地什么都不放
func allows(move: String) -> bool:
	if down_t > 0.0 or mood == "tired":
		return false
	if move == "slam" and broken("tail"):
		return false
	if move == "roar" and broken("head"):
		return false
	return true


## 房主（KingArts）：露破绽 t 秒
func open(t: float) -> void:
	open_t = t
	_event("open", "%.2f" % t)


## 房主（KingArts）：起手的姿势（crouch 压低 / rear 仰起来），t 秒后出招
func pose(kind: String, t: float) -> void:
	Net.send(0, "kfev", [b.id, "pose", "%s:%.2f" % [kind, t]])
	_on_event("pose", "%s:%.2f" % [kind, t])


func speed_k() -> float:
	return 0.55 if mood == "tired" else 1.0


func bind_k() -> float:
	return 1.8 if mood == "tired" else 1.0


## 累了、血少：捆住就能活捉（不用等到两成血的"虚弱"）
func capturable() -> bool:
	return (mood == "tired" and b.hp < b.max_hp * 0.35) or (down_t > 0.0 and b.hp < b.max_hp * 0.3)


func grounded() -> bool:
	return broken("wing")


# ------------------------------------------------------------------ 大家：收到的状态和事件

static func on_message(p_world: Node, type: String, d: Array) -> void:
	var beast: Beast = p_world.beasts.get(int(d[0]))
	if beast == null or not beast.alive():
		return
	var f := KingFeel.ensure(p_world, beast)
	if type == "kfeel":
		f._apply_state(d)
	else:
		f._on_event(str(d[1]), str(d[2]))


func _apply_state(d: Array) -> void:
	if host:
		return
	for e in d[1]:
		var p := str(e[0])
		if not parts.has(p):
			continue
		var r := float(e[1])
		if r < 0.0:
			parts[p]["broken"] = true
			parts[p]["hp"] = 0.0
		else:
			parts[p]["hp"] = r * float(parts[p]["max"])
	stun = float(d[2]) * stun_max
	down_t = float(d[3])
	mood = str(d[4])
	mood_t = float(d[5])
	rage = float(d[6])
	if d.size() > 8:
		act = int(d[7])
		open_t = float(d[8])


func _on_event(kind: String, arg: String) -> void:
	var hud: Hud = world.hud
	var nm := b.display_name()
	var near: bool = world.player.global_position.distance_to(b.global_position) < 120.0
	match kind:
		"break":
			parts[arg]["broken"] = true
			parts[arg]["hp"] = 0.0
			_break_visual(arg)
			var what := "%s之%s" % [str(Data.BEASTS[b.species]["name"]), str(PART_NAME[arg])]
			hud._show_banner("部位破坏", "%s断了！%s" % [str(PART_NAME[arg]), _break_effect(arg)], UiKit.GOLD, 2.6)
			if near:
				Profile.add_part(b.species, arg)
				hud.feed("获得部位材料：%s" % what, UiKit.GOLD)
			Sfx.play_at("snap", b.global_position, 8.0, 0.05, 0.7)
			Sfx.play_at("slam", b.global_position, 4.0, 0.05, 0.8)
			Sfx.play_at("boss_roar", b.global_position, 2.0, 0.1, 1.4)
		"down":
			hud._show_banner("倒地！", "打头 ×1.6 · 全力输出", Color(1.0, 0.85, 0.35), 2.2)
			Sfx.play_at("thud", b.global_position, 8.0, 0.05, 0.6)
			world.fx._shake(b.global_position, 0.5, 25.0)
		"rage":
			hud.feed("%s 暴怒了！更快、更狠——撑过去它就会累" % nm, Color(1.0, 0.35, 0.2))
			if near:
				hud.toast("%s 暴怒！" % nm, Color(1.0, 0.35, 0.2), 2.5)
			world.fx.aura_burst(b.global_position, Color(1.0, 0.25, 0.1), 5.0)
			Sfx.play_at("boss_roar", b.global_position, 6.0, 0.05, 0.9)
		"pose":
			var sp := arg.split(":")
			_pose = sp[0]
			_pose_len = maxf(float(sp[1]) if sp.size() > 1 else 0.8, 0.1)
			_pose_t = _pose_len
		"open":
			open_t = float(arg)
			_show_open(open_t)
		"tired":
			hud.feed("%s 累了——变慢、不放大招，捆住它更久（三成五血以下能活捉）" % nm, Color(0.6, 0.85, 1.0))
			if near:
				hud.toast("%s 累了：捆住它的好时机" % nm, Color(0.6, 0.85, 1.0), 3.0)


## 露破绽：不写字（用户："头上写「破绽」两个字，不是很搞笑么"）——踉跄的动作（_process）+ 头上弱点一团金光 + 一声闷响、喘气；
## 第一次出现提示一句怎么打
func _show_open(t: float) -> void:
	if _glint and is_instance_valid(_glint):
		_glint.extend(t)
	else:
		_glint = WeakGlint.spawn(world.fx, Callable(self, "_glint_pos"), t, maxf(_height * 0.35, 0.6))
	if world.player.global_position.distance_to(b.global_position) < 70.0:
		Sfx.play_at("thud", b.global_position, 4.0, 0.05, 0.8)
		Sfx.play_at("exhale", b.global_position, 2.0, 0.1, 0.7)
		WeakGlint.tip_once(world)


## 弱点金光跟着头走（灵兽没了就收掉）
func _glint_pos() -> Vector3:
	if not is_instance_valid(b) or not b.alive() or open_t <= 0.0:
		return Vector3.INF
	return _head_pos() + Vector3.UP * _height * 0.15


func _head_pos() -> Vector3:
	if _skel and _skel.find_bone("Head") >= 0:
		return _skel.global_transform * _skel.get_bone_global_pose(_skel.find_bone("Head")).origin
	return b.global_transform * (_center + _front * _half * 0.9 + Vector3.UP * _height * 0.2)


func _break_effect(p: String) -> String:
	match p:
		"tail":
			return "它再也甩不出震地"
		"head":
			return "不会咆哮了，打头更容易晕"
		"back":
			return "全身受伤 +25%"
		"wing":
			return "飞不起来了"
	return ""


# ------------------------------------------------------------------ 样子：断肢、倒地、冒气

func _break_visual(p: String) -> void:
	var keep: Array[int] = []
	if _skel:
		for nm in PART_BONES[p]:
			var i := _skel.find_bone(str(nm))
			if i < 0:
				continue
			# 尾巴只要一根（Tail2 没有才用 Tail1）；角、翼左右都要
			if p == "tail" and not keep.is_empty():
				break
			keep.append(i)
	var at := b.global_position + Vector3.UP * _height * 0.5
	if not keep.is_empty():
		if _hider == null:
			_hider = BoneHide.new()
			_skel.add_child(_hider)
		for i in keep:
			_hider.hide.append(i)
		at = _skel.global_transform * _skel.get_bone_global_pose(keep[0]).origin
		_spawn_piece(keep, at)
	else:
		_spawn_shards(at)
	var fx: Node = world.fx
	fx._flash(at, Color(1.0, 0.85, 0.5), 2.2 * b.size_k, 0.15)
	fx._sparks(at, Vector3.UP, Color(1.0, 0.7, 0.3), 18, 7.0, 0.7, 0.06, -9.0, 160.0)
	fx._smoke(at, Color(0.45, 0.4, 0.35, 0.6), 6, 2.5, 0.8, 1.4, 0.6)
	fx.shockwave(b.global_position, 5.0 * b.size_k, Color(1.0, 0.8, 0.4))


## 断下来的那截：复制整个模型，BoneHide 只留那几根骨头；从断口往外飞出去、落地弹一下、躺 10 秒再沉下去
func _spawn_piece(keep: Array[int], at: Vector3) -> void:
	var copy := b.model.duplicate() as Node3D
	var pivot := Node3D.new()
	world.fx.add_child(pivot)
	pivot.global_position = at
	pivot.add_child(copy)
	copy.global_transform = b.model.global_transform
	for ap in copy.find_children("*", "AnimationPlayer", true, false):
		(ap as AnimationPlayer).active = false
	var sks := copy.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		pivot.queue_free()
		return
	var h := BoneHide.new()
	h.keep = keep
	sks[0].add_child(h)
	var away := (at - b.global_position)
	away.y = 0.0
	away = away.normalized() if away.length() > 0.05 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	_pieces.append({"n": pivot, "v": away * 4.5 + Vector3.UP * 5.0, "w": Vector3(randf_range(-6, 6), randf_range(-4, 4), randf_range(-6, 6)), "t": 0.0, "g": false})


## 没有能藏的骨头（背甲）：崩下几块甲片（用模型自己的材质）
func _spawn_shards(at: Vector3) -> void:
	var mat: Material = null
	for n in b.model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh and mi.mesh.get_surface_count() > 0:
			mat = mi.get_active_material(0)
			break
	if mat == null:
		mat = MatLib.stone(Color(0.6, 0.55, 0.5))
	for k in 5:
		var pivot := Node3D.new()
		world.fx.add_child(pivot)
		pivot.global_position = at + Vector3(randf_range(-0.4, 0.4), randf_range(0, 0.3), randf_range(-0.4, 0.4)) * b.size_k
		var s := randf_range(0.18, 0.32) * b.size_k * float(Data.AGES[b.age]["scale"])
		U.part(pivot, Props.rbox(Vector3(s, s * 0.35, s * 0.8), s * 0.08), mat)
		var dir := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		_pieces.append({"n": pivot, "v": dir * randf_range(2.5, 5.0) + Vector3.UP * randf_range(3.0, 6.0), "w": Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9)), "t": 0.0, "g": false})


func _process(dt: float) -> void:
	if not is_instance_valid(b) or not b.alive():
		return
	if not host and down_t > 0.0:
		down_t = maxf(down_t - dt, 0.0)
	# 倒地：往一侧翻倒（绕身体前后的轴），起来的时候慢一点
	var want := 1.2 if down_t > 0.0 else 0.0
	_tilt = lerpf(_tilt, want, 1.0 - exp(-(9.0 if want > _tilt else 3.0) * dt))
	b.model.rotation = _base_rot
	if _tilt > 0.001:
		b.model.rotate(_front, _tilt)
		b.model.position.y -= _tilt * _height * 0.22
	# 起手（KingArts）：压低身子（扑、冲、跳）或者仰起来（吼、砸、飞的招），越到出招越明显
	if _pose_t > 0.0:
		_pose_t = maxf(_pose_t - dt, 0.0)
		var k := 1.0 - _pose_t / _pose_len
		k = k * k * (3.0 - 2.0 * k)
		var side := _front.cross(Vector3.UP).normalized()
		if _pose == "crouch":
			b.model.rotate(side, -0.12 * k)
			b.model.position.y -= _height * 0.12 * k
		else:
			b.model.rotate(side, 0.3 * k)
			b.model.position.y += _height * 0.04 * k
	# 破绽：踉跄——身子往一边歪、低头、左右晃（弱点的金光是 WeakGlint）
	if open_t > 0.0:
		open_t = maxf(open_t - dt, 0.0)
		var k := clampf(open_t / 0.3, 0.0, 1.0)
		var tm := Time.get_ticks_msec() / 1000.0
		b.model.rotate(_front, (0.1 + sin(tm * 2.8) * 0.07) * k)
		b.model.rotate(_front.cross(Vector3.UP).normalized(), -0.1 * k)
		b.model.position.y -= _height * 0.05 * k
	# 暴怒冒红气、累了喘白气（从头那里出来）
	_fx_t -= dt
	if _fx_t <= 0.0 and mood != "calm" and world.player.global_position.distance_to(b.global_position) < 70.0:
		var head := b.global_transform * (_center + _front * _half * 0.9 + Vector3.UP * _height * 0.2)
		if _skel and _skel.find_bone("Head") >= 0:
			head = _skel.global_transform * _skel.get_bone_global_pose(_skel.find_bone("Head")).origin
		if mood == "rage":
			_fx_t = 0.18
			world.fx._smoke(head, Color(0.9, 0.15, 0.08, 0.5), 2, 1.2, 0.5, 0.6 * b.size_k, 0.5)
		else:
			_fx_t = 0.9
			world.fx._smoke(head + b.global_basis * _front * 0.3, Color(0.92, 0.95, 1.0, 0.45), 3, 1.6, 0.6, 0.5 * b.size_k, 0.9)
			if randf() < 0.35:
				Sfx.play_at("exhale", head, -4.0, 0.1, 0.6)
	_update_pieces(dt)


func _update_pieces(dt: float) -> void:
	var i := 0
	while i < _pieces.size():
		var pc: Dictionary = _pieces[i]
		var n: Node3D = pc["n"]
		if not is_instance_valid(n):
			_pieces.remove_at(i)
			continue
		pc["t"] = float(pc["t"]) + dt
		var t := float(pc["t"])
		if t > 14.0:
			n.queue_free()
			_pieces.remove_at(i)
			continue
		if not bool(pc["g"]):
			var v: Vector3 = pc["v"]
			v.y -= 14.0 * dt
			pc["v"] = v
			n.global_position += v * dt
			var w: Vector3 = pc["w"]
			if w.length() > 0.01:
				n.rotate(w.normalized(), w.length() * dt)
			var gy: float = world.island.height_at(n.global_position.x, n.global_position.z)
			if n.global_position.y < gy + 0.1 and v.y < 0.0:
				n.global_position.y = gy + 0.1
				if absf(v.y) > 3.0:
					pc["v"] = Vector3(v.x * 0.4, -v.y * 0.3, v.z * 0.4)
					pc["w"] = w * 0.4
				else:
					pc["g"] = true
		elif t > 11.0:
			n.global_position.y -= dt * 0.4
		i += 1


func _exit_tree() -> void:
	for pc in _pieces:
		if is_instance_valid(pc["n"]):
			(pc["n"] as Node).queue_free()
	_pieces.clear()
