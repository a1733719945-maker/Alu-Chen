class_name Combo
extends Node
## 猎魂连击 + 武魂真身（第九版，用户说"单纯打打打刷怪，很容易疲倦"）。
##
## 连击：打得漂亮就拿得多，不是比谁刷得多。
##   空中命中 +1（爆头再 +1），地上命中只 +0.25，空中击杀 +4，地上击杀 +1.5。
##   3 秒没加分就断（武魂真身时 5 秒）。评级 D → C → B → A → S → SS → SSS，
##   评级越高金魂币和修为越多（最高 ×2.5），命中音调跟着连击往上走，升评级屏幕一闪；S 以上队友也看得到。
## 武魂真身（原著的大招）：连击给它充能，满了按 Z 变身 12 秒——伤害 +120%、子弹不耗、跑得快，
##   天上显现武魂法相，身边 25 米的队友伤害 +30%。结束时一圈冲击波。

const RANKS := [
	["D", 0.0, 1.0, Color(0.7, 0.72, 0.78)],
	["C", 8.0, 1.15, Color(0.55, 0.85, 1.0)],
	["B", 20.0, 1.35, Color(0.45, 1.0, 0.6)],
	["A", 40.0, 1.6, Color(1.0, 0.85, 0.35)],
	["S", 70.0, 1.9, Color(1.0, 0.55, 0.2)],
	["SS", 110.0, 2.2, Color(1.0, 0.3, 0.3)],
	["SSS", 160.0, 2.5, Color(1.0, 0.35, 0.85)],
]
const DECAY := 3.0
const DECAY_TB := 5.0
const TB_TIME := 12.0
const TB_PER_POINT := 0.012        # 大约 85 分充满
const TB_PER_KILL := 0.04
const TB_DMG := 1.2
const TB_SPEED := 0.25
const TB_ALLY_DMG := 0.3
const TB_ALLY_RANGE := 25.0

var world: Node
var points := 0.0                  # 连击分
var hits := 0                      # 连击数（显示用）
var since := 99.0                  # 离上次加分多久
var best_rank := 0                 # 这一串到过的最高评级
var meter := 0.0                   # 武魂真身充能 0..1
var tb_t := 0.0                    # 武魂真身剩余时间
var _ready_told := false


func rank() -> int:
	var r := 0
	for i in RANKS.size():
		if points >= float(RANKS[i][1]):
			r = i
	return r if hits > 0 else 0


func mult() -> float:
	return float(RANKS[rank()][2]) if hits > 0 else 1.0


func active() -> bool:
	return tb_t > 0.0


func decay_left() -> float:
	var lim := DECAY_TB if active() else DECAY
	return clampf(1.0 - since / lim, 0.0, 1.0) if hits > 0 else 0.0


func _add(p: float, count := true) -> void:
	var before := rank()
	points += p
	if count:
		hits += 1
	since = 0.0
	if not active():
		meter = minf(meter + p * TB_PER_POINT, 1.0)
		if meter >= 1.0 and not _ready_told:
			_ready_told = true
			world.hud.toast("武魂真身 · 充能完毕，按 Z 变身", UiKit.GOLD, 3.5)
			Sfx.play("level_up", -6.0, 0.0, 1.3)
	var r := rank()
	if r > before:
		best_rank = maxi(best_rank, r)
		world.hud.combo_rank_up(r)
		Sfx.play("rare", -4.0, 0.0, 0.9 + r * 0.08)
		if r >= 4 and Net.is_online():
			Net.send(0, "crank", [Settings.display_name(), r])


## 暗器 / 拳头打中魂兽
func hit(air: bool, head: bool) -> void:
	_add((1.0 + (1.0 if head else 0.0)) if air else (0.25 + (0.25 if head else 0.0)))


## 自己打死了一只
func kill(air: bool) -> void:
	_add(4.0 if air else 1.5, false)
	if not active():
		meter = minf(meter + TB_PER_KILL, 1.0)


## 命中音调：连击越高越尖
func pitch() -> float:
	return 1.0 + minf(points, 90.0) * 0.006


func _process(dt: float) -> void:
	since += dt
	if hits > 0 and since > (DECAY_TB if active() else DECAY):
		if rank() >= 2:
			world.hud.toast("连击中断 · 最高 %s" % RANKS[best_rank][0], Color(0.8, 0.82, 0.88), 1.6)
		points = 0.0
		hits = 0
		best_rank = 0
	if tb_t > 0.0:
		tb_t -= dt
		meter = maxf(tb_t / TB_TIME, 0.0)
		var p: Player = world.player
		if tb_t <= 0.0:
			_end()
		elif p:
			# 变身期间子弹不耗（打出去的那一发补回来）
			var g: Gun = p.gun
			if g and g.ammo < int(g.d["mag"]) and int(g.d["mag"]) > 0:
				g.ammo = int(g.d["mag"])
				world.hud.on_ammo(g)
	elif Input.is_action_just_pressed("true_body") and world.player and world.player.input_enabled:
		activate()


func activate() -> void:
	var p: Player = world.player
	if meter < 1.0 or active() or p == null or p.dead:
		if meter < 1.0 and not active():
			world.hud.toast("武魂真身还没充满：连击越高充得越快", Color(0.85, 0.85, 0.9), 2.0)
		return
	tb_t = TB_TIME
	_ready_told = false
	p.add_buff("dmg", TB_DMG, TB_TIME)
	p.add_buff("speed", TB_SPEED, TB_TIME)
	p.trauma = minf(p.trauma + 0.6, 1.0)
	world.on_true_body(Net.my_id)
	Net.send(0, "tb", [Net.my_id])


func _end() -> void:
	tb_t = 0.0
	meter = 0.0
	var p: Player = world.player
	if p:
		world.fx.shockwave(p.global_position, 9.0, world.caster_color(Net.my_id))
	world.hud.true_body(false)
