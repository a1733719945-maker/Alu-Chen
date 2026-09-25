class_name Loot
extends Node3D
## 地上的东西：魂兽掉的素材、魂骨，玩家丢出去的东西，倒地时掉的暗器。
##
## 谁都能捡（走过去自动捡，自己刚丢的 1 秒内不会捡回来）。
## 按 T 把手上的东西丢出去：丢给队友，或者丢进暗器铺旁边的收购箱换金魂币（How to Fish 那样）。
## 东西在地上放太久，海鸥会飞下来叼走；有人倒地太久没人救，海鸥也会把他叼走（回码头复活）。
##
## 联机：谁丢的谁广播（gi），捡的时候问房主（gitake），房主确认后广播（gigone），不会两个人捡到同一个。

const PICK_R := 1.7
const GULL_AFTER := 50.0
const SELL_R := 1.35
const LOCK_T := 1.1
const GRAVITY := 16.0

var world: Node
var items := {}          # iid -> {kind, key, n, owner, pos, vel, rest, t, node, thrower, pending, taken}
var box_pos := Vector3.ZERO
var _next := 1
var _gulls: Array = []
var _box_glow: MeshInstance3D
var _box_pulse := 0.0


func setup(p_world: Node) -> void:
	world = p_world
	name = "Loot"
	_build_box()


# ------------------------------------------------------------------ 收购箱

func _build_box() -> void:
	var door: Vector3 = world.builder.shop_door
	var shop: Vector3 = world.island.shop_pos
	var away := door - shop
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3.BACK
	away = away.normalized()
	var side := away.cross(Vector3.UP)
	var p := door + away * 2.6 + side * 3.4
	if not world.island.is_land(p.x, p.z):
		p = door + away * 2.6 - side * 3.4
	p.y = world.island.height_at(p.x, p.z)
	box_pos = p
	var root := Node3D.new()
	root.name = "SellBox"
	add_child(root)
	root.global_position = p
	root.look_at(p - away, Vector3.UP)
	var wood := U.mat(Color(0.34, 0.2, 0.1), 0.7)
	var dark := U.mat(Color(0.12, 0.08, 0.05), 0.8)
	var gold := U.mat(Color(0.95, 0.72, 0.28), 0.3, 0.0, 0.9)
	# 敞口木箱：四面板 + 底 + 金色包边
	U.part(root, U.box(Vector3(1.9, 0.12, 1.9)), dark, Vector3(0, 0.06, 0))
	for s in [-1.0, 1.0]:
		U.part(root, U.box(Vector3(2.0, 1.0, 0.1)), wood, Vector3(0, 0.55, 0.95 * s))
		U.part(root, U.box(Vector3(0.1, 1.0, 2.0)), wood, Vector3(0.95 * s, 0.55, 0))
		U.part(root, U.box(Vector3(2.1, 0.08, 0.14)), gold, Vector3(0, 1.08, 0.98 * s))
		U.part(root, U.box(Vector3(0.14, 0.08, 2.1)), gold, Vector3(0.98 * s, 1.08, 0))
	# 箱子里一堆发光的金魂币
	for i in 14:
		var a := float(i) * 2.4
		U.part(root, U.cyl(0.11, 0.11, 0.03, 10), U.glow(Color(1.0, 0.8, 0.3), 1.2), Vector3(cos(a) * 0.12 * (i % 5), 0.16 + (i % 3) * 0.03, sin(a) * 0.12 * (i % 5)), Vector3(randf() * 0.4, 0, randf() * 0.4), Vector3.ONE, false)
	_box_glow = U.part(root, U.cyl(0.9, 0.9, 0.02, 32), U.glow(Color(1.0, 0.75, 0.3), 1.5, true), Vector3(0, 1.0, 0), Vector3.ZERO, Vector3.ONE, false)
	var gm := (_box_glow.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
	gm.albedo_color = Color(1.0, 0.75, 0.3, 0.25)
	_box_glow.material_override = gm
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.4)
	light.light_energy = 1.2
	light.omni_range = 5.0
	light.position = Vector3(0, 1.5, 0)
	root.add_child(light)
	var l := U.label3d("唐门收购箱\n拿着魂骨、道具按 T 丢进来卖", 44, Color(1.0, 0.85, 0.45), 10)
	l.position = Vector3(0, 2.2, 0)
	l.fixed_size = false
	l.pixel_size = 0.006
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(l)
	# 实体：人走不进去（也能站在边上）
	var sb := StaticBody3D.new()
	sb.collision_layer = U.LAYER_WORLD
	sb.collision_mask = 0
	for s in [-1.0, 1.0]:
		var c1 := CollisionShape3D.new()
		var b1 := BoxShape3D.new()
		b1.size = Vector3(2.0, 1.1, 0.12)
		c1.shape = b1
		c1.position = Vector3(0, 0.55, 0.95 * s)
		sb.add_child(c1)
		var c2 := CollisionShape3D.new()
		var b2 := BoxShape3D.new()
		b2.size = Vector3(0.12, 1.1, 2.0)
		c2.shape = b2
		c2.position = Vector3(0.95 * s, 0.55, 0)
		sb.add_child(c2)
	root.add_child(sb)


# ------------------------------------------------------------------ 生成 / 丢出

## 生成一件地上的东西（自己这边算，再广播给别人）
func spawn(kind: String, key: String, n: int, owner: int, pos: Vector3, vel: Vector3, thrower := 0) -> int:
	var iid := Net.my_id * 100000 + _next
	_next += 1
	var msg := [iid, kind, key, n, owner, pos, vel, thrower]
	Net.send(0, "gi", msg)
	_on_add(msg)
	return iid


func _on_add(msg: Array) -> void:
	var iid := int(msg[0])
	if items.has(iid):
		return
	var kind := str(msg[1])
	var key := str(msg[2])
	var node := _make_node(kind, key)
	add_child(node)
	node.global_position = msg[5]
	items[iid] = {"kind": kind, "key": key, "n": int(msg[3]), "owner": int(msg[4]), "pos": msg[5], "vel": msg[6],
		"rest": false, "t": 0.0, "node": node, "thrower": int(msg[7]), "pending": 0.0, "taken": false, "spin": randf() * TAU}


func _make_node(kind: String, key: String) -> Node3D:
	var n := item_model(kind, key)
	var col := Data.item_color(kind, key)
	# 脚下一圈光，远处也看得见
	var ring := U.part(n, U.torus(0.3, 0.36, 24, 4), U.glow(col, 2.0, true), Vector3(0, -0.12, 0), Vector3.ZERO, Vector3.ONE, false)
	ring.name = "Ring"
	var l := U.label3d(Data.item_name(kind, key), 30, col, 8)
	l.position = Vector3(0, 0.55, 0)
	l.fixed_size = true
	l.pixel_size = 0.0008
	l.name = "Label"
	n.add_child(l)
	return n


## 东西本身的模型（地上的、手里拿着的都用这个）
static func item_model(kind: String, key: String) -> Node3D:
	var n := Node3D.new()
	var col := Data.item_color(kind, key)
	match kind:
		"gun":
			var g := WeaponModels.build_small(key)
			g.scale = Vector3.ONE * 2.2
			g.rotation = Vector3(0, 0, PI / 2)
			n.add_child(g)
		"bone":
			# 发金光的骨头：骨干 + 两头的骨节
			var m := U.glow(Color(1.0, 0.9, 0.6), 2.5)
			U.part(n, U.capsule(0.07, 0.6), m, Vector3.ZERO, Vector3(0, 0, PI / 2), Vector3.ONE, false)
			for s in [-1.0, 1.0]:
				U.part(n, U.sphere(0.1, 10, 6), m, Vector3(0.3 * s, 0.05, 0), Vector3.ZERO, Vector3.ONE, false)
				U.part(n, U.sphere(0.1, 10, 6), m, Vector3(0.3 * s, -0.05, 0), Vector3.ZERO, Vector3.ONE, false)
			var p := CPUParticles3D.new()
			p.amount = 10
			p.lifetime = 1.0
			p.mesh = U.sphere(0.035, 5, 3)
			p.material_override = U.glow(Color(1.0, 0.85, 0.35), 5.0, true)
			p.direction = Vector3.UP
			p.initial_velocity_min = 0.4
			p.initial_velocity_max = 1.0
			p.gravity = Vector3(0, 0.6, 0)
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = 0.3
			n.add_child(p)
		"item":
			if key == "meat":
				# 烤肉：一根骨头穿着一大块焦黄的肉
				U.part(n, U.capsule(0.025, 0.42), U.mat(Color(0.92, 0.88, 0.78), 0.6), Vector3.ZERO, Vector3(0, 0, PI / 2), Vector3.ONE, false)
				U.part(n, U.sphere(0.13, 12, 8), U.mat(Color(0.55, 0.27, 0.1), 0.45), Vector3(0.06, 0, 0), Vector3.ZERO, Vector3(1.3, 1.0, 1.0), false)
				U.part(n, U.sphere(0.06, 8, 6), U.mat(Color(0.92, 0.88, 0.78), 0.6), Vector3(-0.2, 0.02, 0), Vector3.ZERO, Vector3.ONE, false)
			elif key == "grenade":
				U.part(n, U.sphere(0.16, 10, 6), U.mat(Color(0.85, 0.2, 0.25), 0.4, 0.3), Vector3.ZERO, Vector3.ZERO, Vector3(1, 0.7, 1), false)
				U.part(n, U.torus(0.1, 0.19, 16, 5), U.mat(Color(0.95, 0.75, 0.3), 0.3, 0.0, 0.9), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
			else:
				U.part(n, U.sphere(0.13, 10, 6), U.glow(Color(1.0, 0.35, 0.35), 1.5), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
		_:
			# 素材：一块发光的魂晶（颜色按年份）
			var cm := U.glow(col, 1.8)
			var crystal := U.part(n, U.sphere(0.16, 6, 3), cm, Vector3.ZERO, Vector3.ZERO, Vector3(0.8, 1.4, 0.8), false)
			crystal.name = "Crystal"
			U.part(n, U.sphere(0.1, 6, 3), cm, Vector3(0.14, -0.06, 0.05), Vector3(0.4, 0, 0.3), Vector3(0.8, 1.2, 0.8), false)
	return n


## 本地玩家丢出背包里的一件东西。entry = {kind, key, owner}
func throw_entry(entry: Dictionary, from: Vector3, dir: Vector3, extra_vel: Vector3) -> void:
	var vel := dir * 11.0 + Vector3.UP * 3.0 + extra_vel * 0.5
	spawn(str(entry["kind"]), str(entry["key"]), 1, int(entry.get("owner", Net.my_id)), from + dir * 0.7, vel, Net.my_id)
	Sfx.play("throw", -6.0, 0.1, 1.2)


# ------------------------------------------------------------------ 每帧

func _process(dt: float) -> void:
	_box_pulse = maxf(_box_pulse - dt * 2.0, 0.0)
	if is_instance_valid(_box_glow):
		_box_glow.scale = Vector3.ONE * (1.0 + _box_pulse * 0.4)
	var me: Player = world.player
	var mp := me.global_position + Vector3(0, 0.8, 0)
	for iid in items.keys():
		var it: Dictionary = items[iid]
		it["t"] += dt
		_sim(it, dt)
		var node: Node3D = it["node"]
		if is_instance_valid(node):
			it["spin"] += dt * 1.6
			var bob := sin(it["t"] * 2.5) * 0.06 if it["rest"] else 0.0
			node.global_position = it["pos"] + Vector3(0, 0.18 + bob, 0)
			node.rotation.y = it["spin"]
		if it["taken"]:
			continue
		# 自己丢的东西掉进收购箱：卖掉
		if int(it["thrower"]) == Net.my_id and it["kind"] != "gun" and _in_box(it["pos"]):
			it["taken"] = true
			var msg := [iid, Net.my_id, 1]
			Net.send(0, "gigone", msg)
			_on_gone(msg)
			continue
		# 走过去自动捡
		it["pending"] = maxf(float(it["pending"]) - dt, 0.0)
		if me.dead or it["pending"] > 0.0:
			continue
		if int(it["thrower"]) == Net.my_id and it["t"] < LOCK_T:
			continue
		if (it["pos"] as Vector3).distance_to(mp) < PICK_R * (1.0 + me.giant_k * 0.3) and _can_take(it):
			it["pending"] = 1.5
			Net.send_host("gitake", [iid])
	if Net.is_host():
		_host_gulls()
	_update_gulls(dt)


func _sim(it: Dictionary, dt: float) -> void:
	if it["rest"]:
		return
	var p0: Vector3 = it["pos"]
	var v: Vector3 = it["vel"]
	var g: float = world.island.height_at(p0.x, p0.z)
	var in_water := p0.y < Island.WATER_Y and g < Island.WATER_Y - 0.2
	if in_water:
		# 水里慢慢沉到底
		v = v.lerp(Vector3(0, -1.3, 0), 1.0 - exp(-3.0 * dt))
	else:
		v.y -= GRAVITY * dt
	var p1 := p0 + v * dt
	var hit: Dictionary = world.raycast(p0, p1 + v.normalized() * 0.1, U.LAYER_WORLD)
	if not hit.is_empty():
		var nrm: Vector3 = hit["normal"]
		p1 = hit["position"] + nrm * 0.1
		if v.length() > 2.5:
			v = v.bounce(nrm) * 0.35
		else:
			v = Vector3.ZERO
			it["rest"] = nrm.y > 0.5
	g = world.island.height_at(p1.x, p1.z)
	if p1.y < g + 0.08:
		p1.y = g + 0.08
		if v.y < -2.5:
			v = Vector3(v.x * 0.5, -v.y * 0.3, v.z * 0.5)
			if not in_water and p0.y > Island.WATER_Y:
				Sfx.play_at("thud", p1, -14.0, 0.2, 1.6)
		else:
			v = Vector3.ZERO
			it["rest"] = true
	if not in_water and p1.y < Island.WATER_Y and g < Island.WATER_Y - 0.2 and p0.y >= Island.WATER_Y:
		world.fx.splash(Vector3(p1.x, Island.WATER_Y, p1.z))
		Sfx.play_at("splash_small", p1, -6.0)
	it["pos"] = p1
	it["vel"] = v


func _in_box(p: Vector3) -> bool:
	var d := Vector2(p.x - box_pos.x, p.z - box_pos.z).length()
	return d < SELL_R and p.y < box_pos.y + 1.6 and p.y > box_pos.y - 0.5


func _can_take(it: Dictionary) -> bool:
	if it["kind"] == "gun":
		var p: Player = world.player
		return p.can_pick_gun(str(it["key"]), int(it["owner"]))
	return true


# ------------------------------------------------------------------ 捡 / 卖 / 被叼走

func host_take(iid: int, from: int) -> void:
	if not items.has(iid) or items[iid]["taken"]:
		return
	items[iid]["taken"] = true
	var msg := [iid, from, 0]
	Net.send(0, "gigone", msg)
	_on_gone(msg)


## reason：0 被捡走，1 卖掉，2 被海鸥叼走
func _on_gone(msg: Array) -> void:
	var iid := int(msg[0])
	var who := int(msg[1])
	var reason := int(msg[2])
	if not items.has(iid):
		return
	var it: Dictionary = items[iid]
	items.erase(iid)
	var node: Node3D = it["node"]
	var pos: Vector3 = it["pos"]
	if reason == 2:
		return    # 节点跟着海鸥飞走，海鸥那边负责删
	if is_instance_valid(node):
		node.queue_free()
	var kind := str(it["kind"])
	var key := str(it["key"])
	var n := int(it["n"])
	var nm := Data.item_name(kind, key)
	if reason == 1:
		world.fx.death_burst(box_pos + Vector3(0, 1.2, 0), Color(1.0, 0.8, 0.3), 0)
		_box_pulse = 1.0
		Sfx.play_at("sell", box_pos, 0.0, 0.05)
		if who == Net.my_id:
			var val := roundi(Data.item_value(kind, key) * n * (1.0 + Profile.bone_bonus("sell")))
			Profile.add_money(val)
			world.hud.toast("卖掉 %s  +%d 金魂币" % [nm, val], UiKit.GOLD, 2.5)
			world.fx.damage_number(box_pos + Vector3(0, 1.8, 0), val, true)
		else:
			world.hud.feed("%s 卖掉了 %s" % [world.peer_name(who), nm], Color(1.0, 0.85, 0.5))
		return
	# 被捡走
	if who != Net.my_id:
		return
	Sfx.play("pickup", -3.0, 0.05)
	match kind:
		"mat":
			Profile.add_mat(key, n)
			world.hud.toast("捡到 %s（按 T 丢进收购箱能卖 %d 金魂币）" % [nm, Data.item_value(kind, key)], Data.item_color(kind, key), 2.5)
		"bone":
			var had := Profile.bones.size()
			Profile.add_bone(key)
			if Profile.bones.size() > had:
				var on := Profile.is_equipped(key)
				world.hud.toast("捡到魂骨【%s】%s  %s" % [nm, Data.bone_desc(key), "已装上" if on else "（按 5 拿出来，左键装上）"], UiKit.GOLD, 5.0)
				Sfx.play("level_up", -6.0)
				world.player.on_bones_changed()
		"item":
			Profile.items[key] = Profile.item_count(key) + n
			Profile.mark_dirty()
			world.hud.toast("捡到 %s ×%d" % [nm, n], Color(1, 0.8, 0.7))
		"gun":
			world.player.pick_gun(key, int(it["owner"]))
	world.fx.poof(pos)


# ------------------------------------------------------------------ 海鸥

func _host_gulls() -> void:
	for iid in items.keys():
		var it: Dictionary = items[iid]
		if it["taken"] or not it["rest"] or it["t"] < GULL_AFTER or it["kind"] == "gun":
			continue
		if (it["pos"] as Vector3).y < Island.WATER_Y - 0.3:
			continue
		# 旁边有人就不敢下来
		var near := false
		for pl in world.all_players():
			if (pl["pos"] as Vector3).distance_to(it["pos"]) < 5.0:
				near = true
		if near:
			continue
		it["taken"] = true
		Net.send(0, "gull", [iid])
		gull_steal(iid)


## 海鸥飞下来叼走地上的东西
func gull_steal(iid: int) -> void:
	if not items.has(iid):
		return
	var it: Dictionary = items[iid]
	it["taken"] = true
	var node: Node3D = it["node"]
	var pos: Vector3 = it["pos"]
	_on_gone([iid, 0, 2])
	var gl := _start_gull(iid, pos, node, null, false)
	gl["item"] = [it["kind"], it["key"], it["n"], it["owner"]]
	world.hud.feed("海鸥叼走了 %s" % Data.item_name(str(it["kind"]), str(it["key"])), Color(0.8, 0.85, 0.9))


## 海鸥叼走倒地的人。local = true 时是叼自己（位置由这边动），否则只跟着别人的位置显示
## gid：物品的海鸥用物品 id，叼人的用 -玩家 id（大家算出来一样，打下来时对得上）
func gull_carry(target: Node3D, local: bool, gid: int) -> void:
	_start_gull(gid, target.global_position, null, target, local)


func _start_gull(gid: int, pos: Vector3, cargo: Node3D, target: Node3D, local: bool) -> Dictionary:
	var g := BeastModels.instance_model({"model": "pigeon", "fit": "w", "size": 2.6 if target else 1.8, "tint": Color(1.3, 1.3, 1.35)})
	add_child(g)
	BeastModels.play_role(g, "run")
	var away := Vector3(pos.x, 0, pos.z)
	away = away.normalized() if away.length() > 1.0 else Vector3.FORWARD
	var from := pos + away * 30.0 + Vector3(0, 26.0, 0)
	g.global_position = from
	# 海鸥也是魂兽：打得到。打下来它叼的东西 / 人会掉下来
	var sb := StaticBody3D.new()
	sb.collision_layer = U.LAYER_BEAST
	sb.collision_mask = 0
	sb.set_meta("gull", gid)
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 1.1 if target else 0.8
	cs.shape = sh
	sb.add_child(cs)
	g.add_child(sb)
	var gl := {"gid": gid, "node": g, "t": 0.0, "from": from, "pos": pos, "cargo": cargo, "target": target, "local": local, "away": away, "cried": false, "dead": false, "vy": 0.0}
	_gulls.append(gl)
	Sfx.play_at("gull_cry", pos + Vector3(0, 10, 0), 2.0, 0.1)
	return gl


const GULL_DOWN := 1.6
const GULL_UP := 3.2


func _update_gulls(dt: float) -> void:
	for gl in _gulls.duplicate():
		gl["t"] += dt
		var g: Node3D = gl["node"]
		if gl["dead"]:
			# 被打下来了：翻着跟头掉下去
			gl["vy"] = float(gl["vy"]) - 14.0 * dt
			if is_instance_valid(g):
				g.global_position += Vector3(0, float(gl["vy"]) * dt, 0)
				g.rotation.z += dt * 9.0
				var gy: float = world.island.height_at(g.global_position.x, g.global_position.z)
				if g.global_position.y < maxf(gy, Island.WATER_Y) or gl["t"] > 3.0:
					world.fx.poof(g.global_position)
					g.queue_free()
					_gulls.erase(gl)
			else:
				_gulls.erase(gl)
			continue
		var t: float = gl["t"]
		var target: Node3D = gl["target"]
		var grab: Vector3 = gl["pos"]
		if is_instance_valid(target) and t < GULL_DOWN:
			grab = target.global_position
			gl["pos"] = grab
		var p: Vector3
		if t < GULL_DOWN:
			var k := t / GULL_DOWN
			k = 1.0 - (1.0 - k) * (1.0 - k)
			p = (gl["from"] as Vector3).lerp(grab + Vector3(0, 1.4, 0), k)
		else:
			var k := minf((t - GULL_DOWN) / GULL_UP, 1.0)
			p = grab + Vector3(0, 1.4, 0) + (gl["away"] as Vector3) * -40.0 * k * k + Vector3(0, 30.0 * k, 0)
			if not gl["cried"]:
				gl["cried"] = true
				Sfx.play_at("gull_cry", p, 0.0, 0.1, 1.15)
				world.fx.poof(grab)
			var cargo: Node3D = gl["cargo"]
			if is_instance_valid(cargo):
				cargo.global_position = p + Vector3(0, -0.6, 0)
			if is_instance_valid(target):
				if gl["local"]:
					(target as Player).carry_to(p + Vector3(0, -2.0, 0))
				else:
					p = target.global_position + Vector3(0, 2.0, 0)
		if is_instance_valid(g):
			var vel: Vector3 = p - g.global_position
			g.global_position = p
			if Vector3(vel.x, 0, vel.z).length() > 0.01:
				g.look_at(p + Vector3(vel.x, 0, vel.z), Vector3.UP)
		if t > GULL_DOWN + GULL_UP:
			_gulls.erase(gl)
			if is_instance_valid(g):
				g.queue_free()
			var cargo2: Node3D = gl["cargo"]
			if is_instance_valid(cargo2):
				cargo2.queue_free()


# ------------------------------------------------------------------ 联机

func on_message(from: int, type: String, data: Variant) -> void:
	match type:
		"gi":
			_on_add(data)
		"gitake":
			if Net.is_host():
				host_take(int(data[0]), from)
		"gigone":
			var d: Array = data
			if items.has(int(d[0])):
				items[int(d[0])]["taken"] = true
			_on_gone(d)
		"gull":
			gull_steal(int(data[0]))
		"gullhit":
			if Net.is_host():
				_host_gull_hit(int(data[0]), from)
		"gulldown":
			_on_gull_down(data)


func _find_gull(gid: int) -> Dictionary:
	for gl in _gulls:
		if int(gl["gid"]) == gid and not gl["dead"]:
			return gl
	return {}


func _host_gull_hit(gid: int, from: int) -> void:
	var gl := _find_gull(gid)
	if gl.is_empty():
		return
	var g: Node3D = gl["node"]
	var pos: Vector3 = g.global_position if is_instance_valid(g) else gl["pos"]
	var msg := [gid, from, pos]
	Net.send(0, "gulldown", msg)
	_on_gull_down(msg)
	# 叼着的东西重新掉回地上（房主生成，大家都能捡）
	if gl.has("item"):
		var it: Array = gl["item"]
		spawn(str(it[0]), str(it[1]), int(it[2]), int(it[3]), pos, Vector3(0, -1.0, 0))


func _on_gull_down(msg: Array) -> void:
	var gl := _find_gull(int(msg[0]))
	var killer := int(msg[1])
	if gl.is_empty():
		return
	gl["dead"] = true
	gl["t"] = 0.0
	var g: Node3D = gl["node"]
	if is_instance_valid(g):
		for sb in g.find_children("*", "StaticBody3D", true, false):
			(sb as StaticBody3D).collision_layer = 0
		world.fx.impact_beast(g.global_position, Vector3.UP, Color(1, 1, 1), true)
	Sfx.play_at("gull_cry", msg[2], 2.0, 0.1, 1.5)
	var cargo: Node3D = gl["cargo"]
	if is_instance_valid(cargo):
		cargo.queue_free()
	if gl["local"]:
		world.gull_dropped_me()
	world.hud.feed("%s 打下了海鸥！" % world.peer_name(killer), Color(0.85, 0.95, 1.0))
	if killer == Net.my_id:
		Profile.add_money(25)
		world.hud.toast("打下了海鸥  +25 金魂币", UiKit.GOLD, 2.0)


## 客人刚进来时，房主把地上的东西发过去
func init_list() -> Array:
	var out := []
	for iid in items:
		var it: Dictionary = items[iid]
		if not it["taken"]:
			out.append([iid, it["kind"], it["key"], it["n"], it["owner"], it["pos"], Vector3.ZERO, 0])
	return out
