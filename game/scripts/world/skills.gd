class_name SkillSystem
extends Node
## 魂技：五个魂环各一个魂技。轻按 Q 放"当前魂技"，按住 Q 弹出轮盘切换（见 Player._skill_input）。
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
	mi.mesh = U.sphere(0.35, 12, 8)
	mi.material_override = U.glow(col, 5.0)
	world.fx.add_child(mi)
	mi.global_position = pos
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
			world.fx.trail(p0, p1, world.caster_color(pr["caster"]))
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
					_hit(b, dmg, Vector3.ZERO, caster)
			var boss: Boss = world.boss
			if boss and not boss.dead and boss.surface_dist(center) < float(s["radius"]):
				boss.root(float(s["dur"]))
				if dmg > 0.0:
					world.host_boss_damage(dmg, false, caster)
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
	var dead: bool = world.host_skill_damage(b, dmg, imp, caster)
	if not dead and imp != Vector3.ZERO:
		pass


func _launch(center: Vector3, radius: float, dmg: float, up: float, caster: int, burn := 0.0) -> void:
	for b in _beasts_in(center, radius):
		if burn > 0.0:
			b.burn_t = 3.0
			b.burn_dps = burn
			b.burn_by = caster
		var away: Vector3 = b.global_position - center
		away.y = 0
		var imp: Vector3 = (away.normalized() * up * 0.25 + Vector3.UP * up) * b.mass
		b.root_t = 0.0
		b.gravity_scale = Beast.G_RISE
		world.host_skill_damage(b, dmg, imp, caster)
	# Boss 按身体表面算距离（它很大，按中心算会打不到）
	var boss: Boss = world.boss
	if boss and not boss.dead and dmg > 0.0 and boss.surface_dist(center) < radius:
		world.host_boss_damage(dmg, false, caster)


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
		world.host_skill_damage(hits[i][1], dmg, dir * 3.0 + Vector3.UP * 3.0, caster)
	var boss: Boss = world.boss
	if boss and not boss.dead and dmg > 0.0 and boss.segment_hit(origin, dir, length, width):
		world.host_boss_damage(dmg, true, caster)
