class_name SkillSystem
extends Node
## 魂技：每个魂环一个魂技。Q / E / F 三个槽各装一个（Profile.skill_slots，K 面板里换），见 cast_slot。
##
## 放技能的人：扣魂力、算目标、处理自己身上的效果（增益、冲刺、跳跃），把"对魂兽的效果"发给房主。
## 房主：对魂兽 / Boss 生效（炸飞、定身、易伤、牵引、光束……），再广播特效。
## 威力 = 魂环年份倍率（十年 1.0 / 百年 1.3 / 千年 1.7 / 万年 2.3 / 十万年 3.2）× (1 + 等级 × 2%)

var world: Node
var cooldowns := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var current := 0                # 当前魂技是第几个魂环的
var _leap := {}                  # 凤翼天翔 / 天使之翼 落地时触发
var _projectiles: Array = []     # 本地模拟的飞弹 {sid, pos, vel, power, caster, life, mi}
var _rains: Array = []           # 房主排队的连击 {sid, center, power, caster, waves, t}
var _summons: Array = []         # 房主：召唤出来的魂灵 {sid, pos, t, next, heal_t, power, caster}
var _orbits: Array = []          # 房主：绕身的刀刃 {sid, caster, t, next, power}
var _domains: Array = []         # 房主：领域 {sid, center, t, next, root_next, power, caster}
var _delayed: Array = []         # 房主：黑洞到时间炸开 {sid, center, power, caster, t}
const FOLLOW_KINDS := ["tiger", "cat", "phoenix", "scythe", "hammer", "angel"]


func slot_skill(slot: int) -> String:
	if slot >= Profile.rings.size():
		return ""
	return str(Profile.rings[slot]["skill"])


func slot_power(slot: int) -> float:
	var r: Dictionary = Profile.rings[slot]
	return float(Data.AGES[int(r["age"])]["ring_power"]) * (1.0 + Profile.level * 0.02)


func _process(dt: float) -> void:
	for i in cooldowns.size():
		cooldowns[i] = maxf(cooldowns[i] - dt, 0.0)
	_update_leap()
	_update_projectiles(dt)
	if Net.is_host():
		_update_rains(dt)
		_update_summons(dt)
		_update_orbits(dt)
		_update_domains(dt)
		_update_delayed(dt)


# ------------------------------------------------------------------ 魂技槽：Q / E / F 放的是哪个魂环的魂技（Profile.skill_slots，K 面板里换）

func slot_ring(k: int) -> int:
	if k < 0 or k >= Profile.skill_slots.size():
		return -1
	var r := int(Profile.skill_slots[k])
	return r if r >= 0 and r < Profile.rings.size() else -1


func cast_slot(k: int) -> void:
	var r := slot_ring(k)
	if r < 0:
		if Profile.rings.is_empty():
			world.hud.toast("还没有魂技。到 10 级瓶颈后吸收魂环就能获得", Color(0.9, 0.9, 0.9))
		else:
			world.hud.toast("这个魂技槽空着：按 K 打开武魂面板，把魂技装到 Q / E / F", Color(0.9, 0.9, 0.9))
		return
	current = r
	cast(r)


# ------------------------------------------------------------------ 按类别放魂技（旧版，留着兼容）
# Q 攻击 / F 辅助 / 双击 Shift 位移。同一类有好几个：放冷却好、魂力够、魂环最高的那个，连按就轮着放
const CATS := {
	"attack": ["launch", "beam", "projectile", "rain", "root", "mark", "pull"],
	"support": ["buff", "heal", "shield", "giant", "invis"],
	"move": ["dash", "blink", "grapple", "fly", "leap"],
}
const CAT_NAMES := {"attack": "攻击", "support": "辅助", "move": "位移"}


func slots_of(cat: String) -> Array:
	var out: Array = []
	for i in Profile.rings.size():
		var s: Dictionary = Data.SKILLS.get(slot_skill(i), {})
		if not s.is_empty() and str(s["type"]) in CATS[cat]:
			out.append(i)
	return out


## 这一类现在该放哪个：能放的里面魂环最高的；都在冷却就返回冷却最快好的那个；没有返回 -1
func pick(cat: String) -> int:
	var ss := slots_of(cat)
	if ss.is_empty():
		return -1
	var p: Player = world.player
	var best := -1
	for i in ss:
		if cooldowns[i] <= 0.0 and p.soul >= float(Data.SKILLS[slot_skill(i)]["cost"]):
			best = i
	if best >= 0:
		return best
	best = ss[0]
	for i in ss:
		if cooldowns[i] < cooldowns[best]:
			best = i
	return best


func cast_cat(cat: String) -> void:
	var i := pick(cat)
	if i < 0:
		world.hud.toast("还没有%s类魂技（吸收魂环时选）" % CAT_NAMES[cat], Color(0.85, 0.85, 0.85), 1.6)
		return
	if cooldowns[i] > 0.0:
		world.hud.toast("%s还要 %.1f 秒" % [Data.SKILLS[slot_skill(i)]["name"], cooldowns[i]], Color(0.8, 0.85, 1.0), 1.0)
		Sfx.play("dry", -8.0)
		return
	current = i
	cast(i)


# ------------------------------------------------------------------ 本地：放技能

func cast(slot: int) -> void:
	var p: Player = world.player
	var sid := slot_skill(slot)
	if sid == "":
		world.hud.toast("还没有魂技。到 10 级瓶颈后吸收魂环就能获得", Color(0.9, 0.9, 0.9))
		return
	var s: Dictionary = Data.SKILLS[sid]
	if p.silence_t > 0.0:
		world.hud.toast("被电麻了，%.1f 秒内放不了魂技" % p.silence_t, Color(0.5, 0.8, 1.0), 1.0)
		Sfx.play("dry", -8.0)
		return
	if cooldowns[slot] > 0.0:
		Sfx.play("dry", -8.0)
		return
	if p.soul < float(s["cost"]):
		world.hud.toast("魂力不够（需要 %d）" % int(s["cost"]), Color(0.6, 0.8, 1.0))
		Sfx.play("dry", -8.0)
		return
	p.soul -= float(s["cost"])
	cooldowns[slot] = float(s["cd"])
	var power := slot_power(slot)
	var origin := p.cam.global_position
	var dir := p.aim_dir()
	var center := p.global_position
	match str(s.get("target", "self")):
		"aim":
			center = _aim_point(origin, dir, 60.0)
		"dir":
			center = origin
	# 放在原地的召唤物（宝塔、香肠）摆在身前，不然镜头在它身体里面，满屏都是光
	if str(s["type"]) == "summon" and str(s.get("target", "self")) == "self" and not str(s.get("kind", "")) in FOLLOW_KINDS:
		var fl := Vector3(dir.x, 0, dir.z).normalized()
		center = p.global_position + fl * 4.0 + fl.cross(Vector3.UP) * 3.5
		center.y = world.island.height_at(center.x, center.z)
	world.hud.skill_callout(slot, sid)
	world.remote_ring_flash(Net.my_id, slot)
	Net.send(0, "ringflash", [slot])
	Sfx.play("skill_cast", -2.0, 0.04)
	var t: String = s["type"]
	match t:
		"buff":
			p.add_buff(str(s["stat"]), float(s["amount"]) * lerpf(1.0, power, 0.5), float(s["dur"]))
			if s.has("stat2"):
				p.add_buff(str(s["stat2"]), float(s["amount2"]) * lerpf(1.0, power, 0.5), float(s["dur"]))
			if s.get("team", false):
				Net.send(0, "buff", [str(s["stat"]), float(s["amount"]) * lerpf(1.0, power, 0.5), float(s["dur"]), p.global_position, float(s.get("radius", 15.0))])
		"giant":
			# 变大：体型、减伤、伤害
			var dur := float(s["dur"])
			p.start_giant(float(s["scale"]), dur)
			p.add_buff("dr", float(s["dr"]), dur)
			p.add_buff("dmg", float(s["dmg"]) * lerpf(1.0, power, 0.5), dur)
		"blink":
			# 瞬移：沿准星方向（水平）闪过去，撞墙就停在墙前
			var flat := Vector3(dir.x, 0, dir.z).normalized()
			var start := p.global_position
			p.blink(flat, float(s["dist"]))
			if s.has("stat"):
				p.add_buff(str(s["stat"]), float(s["amount"]), float(s["dur"]))
			if float(s.get("damage", 0.0)) > 0.0:
				Net.send_host("skill", [sid, power, start + Vector3.UP, flat, Net.my_id])
			center = start + Vector3.UP
		"grapple":
			# 蓝银飞索：打到哪儿把自己拉过去
			var hit: Dictionary = world.raycast(origin, origin + dir * float(s["range"]), U.LAYER_WORLD | U.LAYER_BEAST, [p.get_rid()])
			if hit.is_empty():
				world.hud.toast("太远了，飞索够不着", Color(0.8, 0.9, 1.0))
				cooldowns[slot] = 0.5
				p.soul += float(s["cost"])
				return
			p.grapple_to(hit["position"])
		"fly":
			p.start_fly(float(s["dur"]))
			if s.has("stat") and s.get("team", false):
				p.add_buff(str(s["stat"]), float(s["amount"]), float(s["dur"]))
				Net.send(0, "buff", [str(s["stat"]), float(s["amount"]), float(s["dur"]), p.global_position, float(s.get("radius", 15.0))])
			if float(s.get("damage", 0.0)) > 0.0:
				_leap = {"sid": sid, "power": power, "t": -float(s["dur"])}
		"invis":
			p.add_buff("invis", 1.0, float(s["dur"]))
			if s.has("stat"):
				p.add_buff(str(s["stat"]), float(s["amount"]), float(s["dur"]))
		"heal":
			p.heal(float(s["amount"]) * power)
			Net.send(0, "heal", [float(s["amount"]) * power, p.global_position, float(s.get("radius", 15.0))])
		"shield":
			p.add_shield(float(s["amount"]) * power, float(s["dur"]))
			if s.get("team", false):
				Net.send(0, "shield", [float(s["amount"]) * power, float(s["dur"]), p.global_position, float(s.get("radius", 15.0))])
		"dash":
			var flat := Vector3(dir.x, 0, dir.z).normalized()
			var dist := float(s["dist"])
			var start := p.global_position
			p.velocity = flat * dist * 5.0 + Vector3.UP * 2.0
			Net.send_host("skill", [sid, power, start + Vector3.UP, flat, Net.my_id])
		"leap":
			p.velocity.y = sqrt(2.0 * Player.GRAVITY * float(s["height"]))
			_leap = {"sid": sid, "power": power, "t": 0.0}
		"projectile":
			_spawn_projectile(sid, origin + dir * 0.8, dir * float(s["speed"]), power, Net.my_id, true)
			Net.send(0, "skproj", [sid, origin + dir * 0.8, dir * float(s["speed"])])
		"empower":
			# 武魂附体：一段时间内暗器命中带额外效果（World.local_fire 里处理）
			p.empower = {"sid": sid, "kind": str(s["kind"]), "frac": float(s["frac"]) * lerpf(1.0, power, 0.5), "t": float(s["dur"])}
			p.add_buff("dmg", 0.1, float(s["dur"]))
		"domain":
			if s.has("ally_stat"):
				p.add_buff(str(s["ally_stat"]), float(s["ally_amount"]), float(s["dur"]))
				Net.send(0, "buff", [str(s["ally_stat"]), float(s["ally_amount"]), float(s["dur"]), center, float(s["radius"])])
			Net.send_host("skill", [sid, power, center, dir, Net.my_id])
		_:
			Net.send_host("skill", [sid, power, center, dir, Net.my_id])
	world.skill_fx(sid, center, dir, Net.my_id, origin)
	Net.send(0, "skfx", [sid, center, dir, origin])


func _aim_point(origin: Vector3, dir: Vector3, dist: float) -> Vector3:
	var hit: Dictionary = world.raycast(origin, origin + dir * dist, U.LAYER_WORLD | U.LAYER_BEAST, [world.player.get_rid()])
	if not hit.is_empty():
		return hit["position"]
	var p := origin + dir * dist
	return Vector3(p.x, world.island.height_at(p.x, p.z), p.z)


func _update_leap() -> void:
	if _leap.is_empty():
		return
	var p: Player = world.player
	_leap["t"] += get_process_delta_time()
	if _leap["t"] > 0.3 and p.is_on_floor() and p.fly_t <= 0.0:
		var sid: String = _leap["sid"]
		Net.send_host("skill", [sid, _leap["power"], p.global_position, Vector3.DOWN, Net.my_id])
		world.skill_fx(sid, p.global_position, Vector3.DOWN, Net.my_id, p.global_position)
		Net.send(0, "skfx", [sid, p.global_position, Vector3.DOWN, p.global_position])
		p.trauma = minf(p.trauma + 0.5, 1.0)
		_leap = {}


# ------------------------------------------------------------------ 飞弹（本地模拟，放技能的人负责判定命中）

func _spawn_projectile(sid: String, pos: Vector3, vel: Vector3, power: float, caster: int, authoritative: bool) -> void:
	var col: Color = world.caster_color(caster)
	var mi := MeshInstance3D.new()
	mi.mesh = U.sphere(0.45, 12, 8)
	mi.material_override = U.glow(col, 6.0)
	world.fx.add_child(mi)
	mi.global_position = pos
	U.part(mi, U.sphere(0.8, 12, 8), world.fx._spirit_mat(col, 2.0), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
	var tail := CPUParticles3D.new()
	tail.amount = 80
	tail.lifetime = 0.5
	tail.mesh = world.fx._spark_mesh
	tail.material_override = world.fx._particle_mat(true)
	tail.gravity = Vector3.ZERO
	tail.scale_amount_min = 2.0
	tail.scale_amount_max = 3.5
	tail.color = col
	tail.local_coords = false
	mi.add_child(tail)
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 2.0
	light.omni_range = 5.0
	mi.add_child(light)
	_projectiles.append({"sid": sid, "pos": pos, "vel": vel, "power": power, "caster": caster, "life": 0.0, "mi": mi, "auth": authoritative})


func remote_projectile(sid: String, pos: Vector3, vel: Vector3, caster: int) -> void:
	_spawn_projectile(sid, pos, vel, 1.0, caster, false)


func _update_projectiles(dt: float) -> void:
	for pr in _projectiles.duplicate():
		var p0: Vector3 = pr["pos"]
		var v: Vector3 = pr["vel"]
		v.y -= 4.0 * dt
		var p1 := p0 + v * dt
		pr["vel"] = v
		pr["life"] += dt
		var hit: Dictionary = world.raycast(p0, p1, U.LAYER_WORLD | U.LAYER_BEAST, [world.player.get_rid()])
		var done: bool = pr["life"] > 3.0
		var at := p1
		if not hit.is_empty():
			done = true
			at = hit["position"]
		elif p1.y < Island.WATER_Y and not world.island.is_land(p1.x, p1.z):
			done = true
		pr["pos"] = p1
		var mi: MeshInstance3D = pr["mi"]
		if is_instance_valid(mi):
			mi.global_position = p1
		if done:
			_projectiles.erase(pr)
			if is_instance_valid(mi):
				mi.queue_free()
			var s: Dictionary = Data.SKILLS[pr["sid"]]
			world.fx.explosion(at, float(s["radius"]), world.caster_color(pr["caster"]))
			Sfx.play_at("boom", at, 0.0, 0.06)
			if pr["auth"]:
				Net.send_host("skillhit", [pr["sid"], pr["power"], at, pr["caster"]])


# ------------------------------------------------------------------ 房主：对魂兽生效

func host_apply(sid: String, power: float, center: Vector3, dir: Vector3, caster: int) -> void:
	var s: Dictionary = Data.SKILLS.get(sid, {})
	if s.is_empty():
		return
	power = clampf(power, 0.5, 12.0)
	var dmg := float(s.get("damage", 0.0)) * power
	match str(s["type"]):
		"launch":
			_launch(center, float(s["radius"]), dmg, float(s.get("impulse", 8.0)), caster, float(s.get("burn", 0.0)) * power)
		"root":
			for b in _beasts_in(center, float(s["radius"])):
				b.root_t = float(s["dur"])
				b.root_pos = b.global_position + (Vector3.UP * 1.2 if b.state != Beast.State.AIR else Vector3.ZERO)
				b.gravity_scale = 0.0
				if dmg > 0.0:
					_sdmg(b, dmg, Vector3.ZERO, caster)
			var boss: Boss = world.boss
			if boss and not boss.dead and boss.surface_dist(center) < float(s["radius"]):
				boss.root(float(s["dur"]))
				if dmg > 0.0:
					_boss_hit(dmg, false, caster)
		"mark":
			for b in _beasts_in(center, float(s["radius"])):
				b.mark_t = float(s["dur"])
				b.mark_mult = float(s["mult"])
				if sid == "ht_break":
					b.armor_break = true
			var boss2: Boss = world.boss
			if boss2 and not boss2.dead and boss2.surface_dist(center) < float(s["radius"]):
				boss2.mark(float(s["dur"]), float(s["mult"]))
		"pull":
			for b in _beasts_in(center, float(s["radius"])):
				b.pull_t = float(s["dur"])
				b.pull_center = center
				b.pull_force = float(s["force"])
				b.root_t = 0.0
		"beam":
			_beam(center, dir, float(s["range"]), dmg, int(s.get("pierce", 3)), caster)
		"rain":
			_rains.append({"sid": sid, "center": center, "power": power, "caster": caster, "waves": int(s["waves"]), "t": 0.0})
		"dash":
			_beam(center, dir, float(s["dist"]), dmg, 8, caster, float(s.get("radius", 3.0)))
			if s.has("impulse"):
				_launch(center + dir * float(s["dist"]), float(s.get("radius", 3.0)), 0.0, float(s["impulse"]), caster)
		"blink":
			if dmg > 0.0:
				_beam(center, dir, float(s["dist"]), dmg, 8, caster, float(s.get("radius", 3.0)))
		"fly":
			_launch(center, float(s.get("radius", 5.0)), dmg, float(s.get("impulse", 7.0)), caster)
		"leap":
			_launch(center, float(s["radius"]), dmg, float(s.get("impulse", 8.0)), caster)
		"summon", "orbit", "chain", "blackhole", "domain":
			_new_skill_host(sid, s, power, center, caster)


# ------------------------------------------------------------------ 房主：新魂技（召唤、环绕、连锁、黑洞、领域、附体）

func _caster_pos(caster: int) -> Vector3:
	for pl in world.all_players():
		if int(pl["peer"]) == caster:
			return pl["pos"]
	return Vector3.INF


## 离 pos 最近的活魂兽（range 以内），没有返回 null
func _nearest_beast(pos: Vector3, range_m: float, skip: Dictionary = {}) -> Beast:
	var best: Beast = null
	var bd := range_m
	for b: Beast in world.beasts.values():
		if not b.alive() or skip.has(b.id):
			continue
		var d := b.global_position.distance_to(pos)
		if d < bd:
			bd = d
			best = b
	return best


func _new_skill_host(sid: String, s: Dictionary, power: float, center: Vector3, caster: int) -> void:
	match str(s["type"]):
		"summon":
			_summons.append({"sid": sid, "pos": center, "t": 0.0, "next": 0.6, "heal_t": 0.0, "power": power, "caster": caster})
		"orbit":
			_orbits.append({"sid": sid, "caster": caster, "t": 0.0, "next": 0.0, "power": power})
		"chain":
			_chain(sid, s, center, power, caster)
		"blackhole":
			var r := float(s["radius"])
			for b in _beasts_in(center, r):
				b.pull_t = float(s["pull_t"])
				b.pull_center = center + Vector3.UP * 1.5
				b.pull_force = float(s["force"])
				b.root_t = 0.0
			_delayed.append({"sid": sid, "center": center, "power": power, "caster": caster, "t": float(s["pull_t"])})
		"domain":
			_domains.append({"sid": sid, "center": center, "t": 0.0, "next": 0.0, "root_next": 0.0, "power": power, "caster": caster})


func _update_summons(dt: float) -> void:
	for sm in _summons.duplicate():
		var s: Dictionary = Data.SKILLS[sm["sid"]]
		sm["t"] += dt
		if float(sm["t"]) > float(s["dur"]):
			_summons.erase(sm)
			continue
		var pos: Vector3 = sm["pos"]
		if str(s.get("kind", "")) in FOLLOW_KINDS:
			var cp := _caster_pos(int(sm["caster"]))
			if cp != Vector3.INF:
				pos = cp
				sm["pos"] = cp
		var power := float(sm["power"])
		# 回血型（香肠补给站、琉璃宝塔）：每秒给附近队友回血
		if s.has("heal"):
			sm["heal_t"] = float(sm["heal_t"]) - dt
			if float(sm["heal_t"]) <= 0.0:
				sm["heal_t"] = 1.0
				var amt := float(s["heal"]) * power
				Net.send(0, "heal", [amt, pos, 10.0])
				if world.player.global_position.distance_to(pos) <= 10.0:
					world.player.heal(amt)
		sm["next"] = float(sm["next"]) - dt
		if float(sm["next"]) > 0.0:
			continue
		sm["next"] = float(s["rate"])
		var from := pos + Vector3(0, 2.0, 0)
		var b := _nearest_beast(pos, float(s["range"]))
		var dmg := float(s["damage"]) * power
		var to := Vector3.INF
		if b:
			to = b.global_position
			if float(s.get("radius", 0.0)) > 0.0:
				_launch(to, float(s["radius"]), dmg, float(s.get("impulse", 8.0)), int(sm["caster"]), float(s.get("burn", 0.0)) * power)
			else:
				var imp: Vector3 = ((to - pos).normalized() * 2.0 + Vector3.UP * float(s.get("impulse", 3.0))) * b.mass
				_sdmg(b, dmg, imp, int(sm["caster"]))
				if s.has("root") and b.alive():
					b.root_t = float(s["root"])
					b.root_pos = b.global_position
				if s.has("burn") and b.alive():
					b.burn_t = 3.0
					b.burn_dps = float(s["burn"]) * power * _dk()
					b.burn_by = int(sm["caster"])
		elif world.boss and not world.boss.dead and world.boss.surface_dist(pos) < float(s["range"]):
			to = world.boss.center()
			_boss_hit(dmg, false, int(sm["caster"]))
		if to != Vector3.INF:
			var msg := [sm["sid"], from, to, sm["caster"]]
			Net.send(0, "sumhit", msg)
			world.on_summon_hit(msg)


func _update_orbits(dt: float) -> void:
	for ob in _orbits.duplicate():
		var s: Dictionary = Data.SKILLS[ob["sid"]]
		ob["t"] += dt
		if float(ob["t"]) > float(s["dur"]):
			_orbits.erase(ob)
			continue
		ob["next"] = float(ob["next"]) - dt
		if float(ob["next"]) > 0.0:
			continue
		ob["next"] = 0.35
		var cp := _caster_pos(int(ob["caster"]))
		if cp == Vector3.INF:
			continue
		var r := float(s["radius"]) + 1.2
		var dmg := float(s["damage"]) * float(ob["power"]) * 0.35
		for b in _beasts_in(cp, r):
			var away: Vector3 = b.global_position - cp
			away.y = 0.0
			_sdmg(b, dmg, (away.normalized() * 3.0 + Vector3.UP * 2.0) * b.mass, int(ob["caster"]))
			if s.has("burn") and b.alive():
				b.burn_t = 3.0
				b.burn_dps = float(s["burn"]) * float(ob["power"]) * _dk()
				b.burn_by = int(ob["caster"])
		if world.boss and not world.boss.dead and world.boss.surface_dist(cp) < r:
			_boss_hit(dmg, false, int(ob["caster"]))


func _chain(sid: String, s: Dictionary, center: Vector3, power: float, caster: int) -> void:
	var pts: Array = [center + Vector3.UP]
	var hit := {}
	var cur := center
	var dmg := float(s["damage"]) * power
	for j in int(s["jumps"]) + 1:
		var b := _nearest_beast(cur, 8.0 if j == 0 else float(s["range"]), hit)
		if b == null:
			break
		hit[b.id] = true
		pts.append(b.global_position + Vector3.UP * 0.5)
		cur = b.global_position
		_sdmg(b, dmg, Vector3.UP * 3.0 * b.mass, caster)
		if b.alive():
			if s.has("root"):
				b.root_t = float(s["root"])
				b.root_pos = b.global_position
			if s.has("mult"):
				b.mark_t = 8.0
				b.mark_mult = float(s["mult"])
		dmg *= 0.92
	var boss: Boss = world.boss
	if boss and not boss.dead and boss.surface_dist(center) < 12.0:
		_boss_hit(float(s["damage"]) * power * 2.0, false, caster)
		pts.append(boss.center())
	if pts.size() > 1:
		var msg := [pts, caster]
		Net.send(0, "chainfx", msg)
		world.on_chain_fx(msg)


func _update_domains(dt: float) -> void:
	for dm in _domains.duplicate():
		var s: Dictionary = Data.SKILLS[dm["sid"]]
		dm["t"] += dt
		if float(dm["t"]) > float(s["dur"]):
			_domains.erase(dm)
			continue
		dm["next"] = float(dm["next"]) - dt
		dm["root_next"] = float(dm["root_next"]) - dt
		if float(dm["next"]) > 0.0:
			continue
		dm["next"] = 0.5
		var c: Vector3 = dm["center"]
		var r := float(s["radius"])
		var power := float(dm["power"])
		var do_root: bool = s.has("root_every") and float(dm["root_next"]) <= 0.0
		if do_root:
			dm["root_next"] = float(s["root_every"])
		for b in _beasts_in(c, r):
			_sdmg(b, float(s["dps"]) * power * 0.5, Vector3.ZERO, int(dm["caster"]))
			if not b.alive():
				continue
			if s.has("mult"):
				b.mark_t = maxf(b.mark_t, 1.0)
				b.mark_mult = float(s["mult"])
			if do_root:
				b.root_t = 1.2
				b.root_pos = b.global_position
			if s.has("burn"):
				b.burn_t = 2.0
				b.burn_dps = float(s["burn"]) * power * _dk()
				b.burn_by = int(dm["caster"])
		var boss: Boss = world.boss
		if boss and not boss.dead and boss.surface_dist(c) < r:
			_boss_hit(float(s["dps"]) * power * 0.5, false, int(dm["caster"]))
			if s.has("mult"):
				boss.mark(1.0, float(s["mult"]))


func _update_delayed(dt: float) -> void:
	for d in _delayed.duplicate():
		d["t"] = float(d["t"]) - dt
		if float(d["t"]) > 0.0:
			continue
		_delayed.erase(d)
		var s: Dictionary = Data.SKILLS[d["sid"]]
		var power := float(d["power"])
		_launch(d["center"], float(s["radius"]), float(s["damage"]) * power, float(s.get("impulse", 12.0)), int(d["caster"]), float(s.get("burn", 0.0)) * power)


## 武魂附体：暗器打中魂兽以后的额外效果（放技能的人报给房主）
func host_empower(kind: String, pos: Vector3, dmg: float, caster: int, bid: int) -> void:
	var b: Beast = world.beasts.get(bid)
	match kind:
		"explode":
			_launch(pos, 3.5, dmg, 4.0, caster)
		"quake":
			_launch(pos, 4.5, dmg, 7.0, caster)
		"root":
			if b and b.alive():
				world.host_skill_damage(b, dmg, Vector3.ZERO, caster)
				if b.alive():
					b.root_t = 1.0
					b.root_pos = b.global_position
		"bleed", "burn":
			var targets: Array = [b] if kind == "bleed" else _beasts_in(pos, 2.8)
			for t in targets:
				if t and (t as Beast).alive():
					(t as Beast).burn_t = 3.0
					(t as Beast).burn_dps = dmg / 3.0
					(t as Beast).burn_by = caster
			if kind == "burn":
				_launch(pos, 2.8, dmg * 0.5, 3.0, caster)
		"chain":
			var hit := {bid: true}
			var pts: Array = [pos]
			var cur := pos
			for j in 2:
				var nb := _nearest_beast(cur, 10.0, hit)
				if nb == null:
					break
				hit[nb.id] = true
				pts.append(nb.global_position + Vector3.UP * 0.5)
				cur = nb.global_position
				world.host_skill_damage(nb, dmg, Vector3.UP * 2.0 * nb.mass, caster)
			if pts.size() > 1:
				var msg := [pts, caster]
				Net.send(0, "chainfx", msg)
				world.on_chain_fx(msg)


func host_projectile_hit(sid: String, power: float, at: Vector3, caster: int) -> void:
	var s: Dictionary = Data.SKILLS.get(sid, {})
	if s.is_empty():
		return
	power = clampf(power, 0.5, 12.0)
	_launch(at, float(s["radius"]), float(s["damage"]) * power, float(s.get("impulse", 6.0)), caster, float(s.get("burn", 0.0)) * power)


func _update_rains(dt: float) -> void:
	for r in _rains.duplicate():
		r["t"] -= dt
		if r["t"] <= 0.0:
			r["t"] = 0.4
			r["waves"] -= 1
			var s: Dictionary = Data.SKILLS[r["sid"]]
			var rad := float(s["radius"])
			var c: Vector3 = r["center"] + Vector3(randf_range(-rad, rad) * 0.35, 0, randf_range(-rad, rad) * 0.35)
			_launch(c, rad * 0.75, float(s["damage"]) * float(r["power"]), float(s.get("impulse", 5.0)), int(r["caster"]), float(s.get("burn", 0.0)) * float(r["power"]))
			world.broadcast_fx("wave", c, rad * 0.75, int(r["caster"]))
			if r["waves"] <= 0:
				_rains.erase(r)


func _beasts_in(center: Vector3, radius: float) -> Array:
	var out := []
	for b: Beast in world.beasts.values():
		if not b.alive():
			continue
		var d: Vector3 = b.global_position - center
		# 竖直方向放宽，空中的魂兽也能打到
		if Vector2(d.x, d.z).length() <= radius and d.y > -3.0 and d.y < radius + 6.0:
			out.append(b)
	return out


func _hit(b: Beast, dmg: float, imp: Vector3, caster: int) -> void:
	var dead: bool = _sdmg(b, dmg, imp, caster)
	if not dead and imp != Vector3.ZERO:
		pass


func _launch(center: Vector3, radius: float, dmg: float, up: float, caster: int, burn := 0.0) -> void:
	for b in _beasts_in(center, radius):
		if burn > 0.0:
			b.burn_t = 3.0
			b.burn_dps = burn * _dk()
			b.burn_by = caster
		var away: Vector3 = b.global_position - center
		away.y = 0
		var imp: Vector3 = (away.normalized() * up * 0.25 + Vector3.UP * up) * b.mass
		b.root_t = 0.0
		b.gravity_scale = Beast.G_RISE
		_sdmg(b, dmg, imp, caster)
	# Boss 按身体表面算距离（它很大，按中心算会打不到）
	var boss: Boss = world.boss
	if boss and not boss.dead and dmg > 0.0 and boss.surface_dist(center) < radius:
		_boss_hit(dmg, false, caster)
	if dmg > 0.0:
		world.nests.host_area_damage(center, radius, dmg, caster)


func _beam(origin: Vector3, dir: Vector3, length: float, dmg: float, pierce: int, caster: int, width := 1.3) -> void:
	dir = dir.normalized()
	var hits := []
	for b: Beast in world.beasts.values():
		if not b.alive():
			continue
		var rel: Vector3 = b.global_position - origin
		var along := rel.dot(dir)
		if along < 0.0 or along > length:
			continue
		if (rel - dir * along).length() <= width * Data.AGES[b.age]["scale"]:
			hits.append([along, b])
	hits.sort_custom(func(a, c): return a[0] < c[0])
	for i in mini(pierce, hits.size()):
		_sdmg(hits[i][1], dmg, dir * 3.0 + Vector3.UP * 3.0, caster)
	var boss: Boss = world.boss
	if boss and not boss.dead and dmg > 0.0 and boss.segment_hit(origin, dir, length, width):
		_boss_hit(dmg, true, caster)


## 魂技伤害跟着章节的魂兽血量一起涨（魂兽血量每章翻倍，魂技不涨的话后面的章节刮痧；用户反馈"很多魂技基本打不动后面的怪物"）
func _dk() -> float:
	if Data.autotest:
		return 1.0
	return float(Data.CH_HP.get(int(world.chapter), 1.0)) * Profile.rebirth_hard() * world.exp_hp_k()


func _sdmg(b: Beast, dmg: float, imp: Vector3, caster: int) -> bool:
	return world.host_skill_damage(b, dmg * _dk(), imp, caster)


func _boss_hit(dmg: float, weak: bool, caster: int) -> void:
	world.host_boss_damage(dmg * _dk(), weak, caster)