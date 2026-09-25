class_name SkillSystem
extends Node
## 魂技：按 Q / C / X 放第一、二、三魂环的魂技。
##
## 放技能的人：扣魂力、算目标、处理自己身上的效果（增益、冲刺、跳跃），把"对魂兽的效果"发给房主。
## 房主：对魂兽 / Boss 生效（炸飞、定身、易伤、牵引、光束……），再广播特效。
## 威力 = 魂环年份倍率（十年 1.0 / 百年 1.3 / 千年 1.7 / 万年 2.2）× (1 + 等级 × 1%)

var world: Node
var cooldowns := [0.0, 0.0, 0.0]
var _leap := {}                  # 凤翼天翔 / 天使之翼 落地时触发
var _projectiles: Array = []     # 本地模拟的飞弹 {sid, pos, vel, power, caster, life, mi}
var _rains: Array = []           # 房主排队的连击 {sid, center, power, caster, waves, t}


func slot_skill(slot: int) -> String:
	if slot >= Profile.rings.size():
		return ""
	return str(Profile.rings[slot]["skill"])


func slot_power(slot: int) -> float:
	var r: Dictionary = Profile.rings[slot]
	return float(Data.AGES[int(r["age"])]["ring_power"]) * (1.0 + Profile.level * 0.01)


func _process(dt: float) -> void:
	for i in cooldowns.size():
		cooldowns[i] = maxf(cooldowns[i] - dt, 0.0)
	_update_leap()
	_update_projectiles(dt)
	if Net.is_host():
		_update_rains(dt)


# ------------------------------------------------------------------ 本地：放技能

func cast(slot: int) -> void:
	var p: Player = world.player
	var sid := slot_skill(slot)
	if sid == "":
		world.hud.toast("第%d魂环还没有。到 %d 级瓶颈后吸收魂环就能获得魂技" % [slot + 1, (slot + 1) * 10], Color(0.9, 0.9, 0.9))
		return
	var s: Dictionary = Data.SKILLS[sid]
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
			if s.get("team", false):
				Net.send(0, "buff", [str(s["stat"]), float(s["amount"]) * lerpf(1.0, power, 0.5), float(s["dur"]), p.global_position, float(s.get("radius", 15.0))])
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
	if _leap["t"] > 0.3 and p.is_on_floor():
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
	power = clampf(power, 0.5, 3.0)
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
			if boss and boss.center().distance_to(center) < float(s["radius"]) + 4.0:
				boss.root(float(s["dur"]))
		"mark":
			for b in _beasts_in(center, float(s["radius"])):
				b.mark_t = float(s["dur"])
				b.mark_mult = float(s["mult"])
				if sid == "ht_break":
					b.armor_break = true
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
		"leap":
			_launch(center, float(s["radius"]), dmg, float(s.get("impulse", 8.0)), caster)


func host_projectile_hit(sid: String, power: float, at: Vector3, caster: int) -> void:
	var s: Dictionary = Data.SKILLS.get(sid, {})
	if s.is_empty():
		return
	power = clampf(power, 0.5, 3.0)
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
		b.gravity_scale = Data.BEASTS[b.species]["gravity"]
		world.host_skill_damage(b, dmg, imp, caster)
	var boss: Boss = world.boss
	if boss and dmg > 0.0 and boss.center().distance_to(center) < radius + 3.0:
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
	if boss and dmg > 0.0:
		var rel := boss.center() - origin
		var along := rel.dot(dir)
		if along > 0.0 and along < length and (rel - dir * along).length() < 3.0:
			world.host_boss_damage(dmg, true, caster)
