class_name Nests
extends Node
## 魂兽巢穴：每张图 3 个发光的魂晶巢，守在陆地栖息地旁边。
## 有人走近就不断孵出凶暴的魂兽；用暗器、魂技、唐莲把它打爆，掉一大笔金魂币和修为，常掉魂骨；5 分钟后重新长出来。
## 巢的位置大家按同样的规则算（不用同步），血量和死活由房主算、广播。

const RESPAWN := 300.0
const HP_K := 25.0            # 血量 = 这种魂兽的血 × 这么多倍
const WAKE_R := 45.0          # 有人进这个范围就开始孵魂兽
const SPAWN_GAP := 9.0
const MAX_GUARDS := 4

var world: Node
var nests := {}               # id -> {pos, species, age, hp, max, alive, t, spawn_t, guards, node, bar, body}
var _sync_t := 0.0


func setup(p_world: Node, force := false) -> void:
	world = p_world
	# 自动测试时不放（巢的碰撞体会挡住测试里打魂兽的射线），专门的测试阶段再放
	if Data.autotest and not force:
		return
	var isl: Island = world.island
	var id := 0
	for h in isl.habitats:
		if nests.size() >= 3:
			break
		var type := str(h["type"])
		if not Data.HABITATS.has(type) or isl.is_water_habitat(type) or type == "cliff":
			continue
		var c: Vector2 = h["center"]
		var dir := (-c).normalized() if c.length() > 1.0 else Vector2.RIGHT
		var p := c + dir * (float(h["radius"]) + 5.0)
		if not isl.is_land(p.x, p.y):
			p = c
		if not isl.is_land(p.x, p.y):
			continue
		var pos := Vector3(p.x, isl.height_at(p.x, p.y), p.y)
		if Vector2(pos.x - isl.spawn.x, pos.z - isl.spawn.z).length() < 35.0:
			continue
		var species := str(Data.HABITATS[type]["beast"])
		var age: int = [1, 1, 2, 2, 3][clampi(int(world.chapter) - 1, 0, 4)]
		var mx: float = Data.beast_max_hp(species, age) * HP_K
		nests[id] = {"pos": pos, "species": species, "age": age, "hp": mx, "max": mx, "alive": true, "t": 0.0, "spawn_t": 3.0, "guards": []}
		_build(id)
		id += 1


func _build(id: int) -> void:
	var n: Dictionary = nests[id]
	var root := Node3D.new()
	world.add_child(root)
	root.global_position = n["pos"]
	var col: Color = Data.AGES[int(n["age"])]["glow"]
	var crystal := StandardMaterial3D.new()
	crystal.albedo_color = Color(col.r * 0.5, col.g * 0.5, col.b * 0.6, 0.85)
	crystal.emission_enabled = true
	crystal.emission = col
	crystal.emission_energy_multiplier = 1.8
	crystal.roughness = 0.15
	crystal.metallic_specular = 1.0
	crystal.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var rock := U.mat(Color(0.18, 0.16, 0.2), 0.9)
	U.part(root, U.cyl(1.9, 2.4, 0.8, 9), rock, Vector3(0, 0.3, 0))
	for k in 7:
		var a := TAU * k / 7.0 + 0.3
		var r := 0.2 if k == 0 else 1.1
		var hgt := 4.2 if k == 0 else randf_range(1.6, 2.8)
		var shard := U.part(root, U.cyl(0.0, 0.42 if k == 0 else 0.3, hgt, 6), crystal, Vector3(cos(a) * r, 0.6 + hgt * 0.5, sin(a) * r), Vector3(sin(a) * 0.35 * (0.0 if k == 0 else 1.0), 0, cos(a) * 0.35 * (0.0 if k == 0 else 1.0)))
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring := U.part(root, U.torus(2.6, 2.8, 64, 4), U.glow(col, 3.0, true), Vector3(0, 0.2, 0), Vector3.ZERO, Vector3(1, 0.2, 1), false)
	ring.name = "Ring"
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 2.5
	light.omni_range = 10.0
	light.position = Vector3(0, 2.5, 0)
	root.add_child(light)
	var p := CPUParticles3D.new()
	p.amount = 40
	p.lifetime = 2.5
	p.mesh = U.sphere(0.06, 4, 3)
	p.material_override = U.glow(col, 4.0, true)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.8
	p.direction = Vector3.UP
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.5
	p.gravity = Vector3(0, 0.6, 0)
	p.position = Vector3(0, 1.5, 0)
	root.add_child(p)
	# 受击体：子弹打得到（和魂兽一个碰撞层），用 meta 认出是巢
	var sb := StaticBody3D.new()
	sb.collision_layer = U.LAYER_BEAST
	sb.collision_mask = 0
	sb.set_meta("nest", id)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 1.8
	shape.height = 4.5
	cs.shape = shape
	cs.position = Vector3(0, 2.2, 0)
	sb.add_child(cs)
	root.add_child(sb)
	var bar := U.label3d("", 40, col, 8)
	bar.position = Vector3(0, 5.4, 0)
	bar.no_depth_test = true
	bar.fixed_size = true
	bar.pixel_size = 0.0009
	root.add_child(bar)
	n["node"] = root
	n["bar"] = bar
	n["body"] = sb
	_update_bar(id)


func _update_bar(id: int) -> void:
	var n: Dictionary = nests[id]
	var bar: Label3D = n["bar"]
	if not is_instance_valid(bar):
		return
	var k := clampf(float(n["hp"]) / float(n["max"]), 0.0, 1.0)
	var blocks := int(round(k * 10.0))
	bar.text = "%s魂兽巢穴\n%s" % [Data.BEASTS[n["species"]]["name"], "■".repeat(blocks) + "□".repeat(10 - blocks)]


func _process(dt: float) -> void:
	for id in nests:
		var n: Dictionary = nests[id]
		var node: Node3D = n["node"]
		if n["alive"] and is_instance_valid(node):
			var ring := node.get_node_or_null("Ring") as Node3D
			if ring:
				ring.rotation.y += dt * 0.8
	if not Net.is_host() or Data.autotest:
		return
	_sync_t -= dt
	if _sync_t <= 0.0:
		_sync_t = 20.0
		var all: Array = []
		for id in nests:
			all.append([id, nests[id]["hp"], nests[id]["alive"]])
		Net.send(0, "nestsync", all)
	for id in nests:
		var n: Dictionary = nests[id]
		if not n["alive"]:
			n["t"] = float(n["t"]) - dt
			if float(n["t"]) <= 0.0:
				var msg := [id]
				Net.send(0, "nestup", msg)
				_on_up(msg)
			continue
		# 有人靠近就孵魂兽
		var near := false
		for pl in world.alive_players():
			if (pl["pos"] as Vector3).distance_to(n["pos"]) < WAKE_R:
				near = true
		if not near:
			continue
		n["spawn_t"] = float(n["spawn_t"]) - dt
		if float(n["spawn_t"]) > 0.0:
			continue
		n["spawn_t"] = SPAWN_GAP
		var guards: Array = (n["guards"] as Array).filter(func(g): return world.beasts.has(int(g)))
		n["guards"] = guards
		if guards.size() >= MAX_GUARDS:
			continue
		var pos: Vector3 = n["pos"]
		var a := randf() * TAU
		var q := pos + Vector3(cos(a) * 3.0, 3.0, sin(a) * 3.0)
		var b: Beast = world._host_spawn_wild(q, str(n["species"]), int(n["age"]), "fierce")
		if b:
			guards.append(b.id)
			world.fx.poof(q)


## 房主：巢挨打（暗器 / 魂技 / 唐莲）
func host_damage(id: int, dmg: float, killer: int) -> void:
	if not nests.has(id) or not nests[id]["alive"] or dmg <= 0.0:
		return
	var n: Dictionary = nests[id]
	n["hp"] = maxf(float(n["hp"]) - dmg, 0.0)
	if float(n["hp"]) <= 0.0:
		var msg := [id, killer]
		Net.send(0, "nestdown", msg)
		_on_down(msg)
		_host_loot(id)
	else:
		Net.send(0, "nesthp", [id, n["hp"]])
		_update_bar(id)


## 范围伤害（魂技爆炸、唐莲）：碰到的巢都掉血
func host_area_damage(center: Vector3, radius: float, dmg: float, caster: int) -> void:
	for id in nests:
		var n: Dictionary = nests[id]
		if n["alive"] and (n["pos"] as Vector3).distance_to(center) < radius + 2.0:
			host_damage(id, dmg, caster)


func _host_loot(id: int) -> void:
	var n: Dictionary = nests[id]
	var at: Vector3 = (n["pos"] as Vector3) + Vector3(0, 2.0, 0)
	var bid: String = Data.BONE_BY_BEAST.get(str(n["species"]), "")
	if bid != "" and randf() < 0.6:
		world.loot.spawn("bone", "%s@%d" % [bid, int(n["age"])], 1, 0, at, Vector3(randf_range(-2, 2), 8.0, randf_range(-2, 2)))
	for k in 3:
		world.loot.spawn("item", "meat" if k < 2 else "pill", 1, 0, at, Vector3(randf_range(-3, 3), 6.0, randf_range(-3, 3)))


func on_message(type: String, data: Variant) -> void:
	match type:
		"nesthp":
			if nests.has(int(data[0])):
				nests[int(data[0])]["hp"] = float(data[1])
				_update_bar(int(data[0]))
		"nestdown":
			_on_down(data)
		"nestup":
			_on_up(data)
		"nestsync":
			for e in data:
				var id := int(e[0])
				if not nests.has(id):
					continue
				nests[id]["hp"] = float(e[1])
				if bool(e[2]) != bool(nests[id]["alive"]):
					if bool(e[2]):
						_on_up([id])
					else:
						_on_down([id, 0])
				_update_bar(id)


func _on_down(msg: Array) -> void:
	var id := int(msg[0])
	if not nests.has(id) or not nests[id]["alive"]:
		return
	var n: Dictionary = nests[id]
	n["alive"] = false
	n["t"] = RESPAWN
	n["hp"] = 0.0
	var node: Node3D = n["node"]
	var pos: Vector3 = n["pos"]
	var col: Color = Data.AGES[int(n["age"])]["glow"]
	if is_instance_valid(node):
		node.visible = false
		(n["body"] as StaticBody3D).collision_layer = 0
	world.fx.ring_breakthrough(pos, col, 0)
	world.fx.explosion(pos + Vector3.UP * 2.0, 8.0, col)
	Sfx.play_at("boom", pos, 4.0)
	var killer := int(msg[1]) if msg.size() > 1 else 0
	world.hud.feed("%s 打爆了%s魂兽巢穴！" % [world.peer_name(killer), Data.BEASTS[n["species"]]["name"]], UiKit.GOLD)
	# 奖励：打爆的人全拿，附近 60 米的队友拿一半
	var d: float = world.player.global_position.distance_to(pos)
	if killer == Net.my_id or d < 60.0:
		var k := 1.0 if killer == Net.my_id else 0.5
		var money := int(Data.kill_money(str(n["species"]), int(n["age"])) * 18.0 * k)
		var xp := int(Data.kill_xp(str(n["species"]), int(n["age"])) * 8.0 * k)
		world._gain(money, xp)
		world.hud.toast("魂兽巢穴打爆了！+%d 金魂币 +%d 修为" % [money, xp], UiKit.GOLD, 3.0)
		Profile.count("nests")


func _on_up(msg: Array) -> void:
	var id := int(msg[0])
	if not nests.has(id):
		return
	var n: Dictionary = nests[id]
	n["alive"] = true
	n["hp"] = n["max"]
	n["spawn_t"] = 3.0
	var node: Node3D = n["node"]
	if is_instance_valid(node):
		node.visible = true
		(n["body"] as StaticBody3D).collision_layer = U.LAYER_BEAST
	_update_bar(id)
