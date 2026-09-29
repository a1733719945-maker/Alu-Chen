class_name GunArts
## 暗器各有打法（2026-09-29，用户："我们这些武器其实没太大差别，没有形成自己独有的打法，而且到最后只能选最强那个武器"）。
## 每把一个独门机制，跟猎王的系统（部位、晕、破绽、起招、怒气）挂钩，打法完全不同；输出按"这一章的暗器档次"拉平（Data.weapon_stats），没有最强：
##   袖箭      闪身：翻滚中也打得准，极限闪避后弹匣自动装满（Player）
##   寒梅袖箭  梅花印：三箭落在同一处开一朵梅花——多一截伤、这个部位多掉一截（房主，这里）
##   千丝雨针  断部位：贴近了打，部位伤害翻倍（这里）
##   连机神弩  打晕：打头攒晕值快一倍多；小灵兽连着爆头会被打懵（这里）
##   追星针    星标：打中的部位落一颗星，十秒内全队打那里更痛、部位掉得快（这里 + KingFeel.star）
##   流光翎    抓窗口：平时一般；王踉跄 / 倒地 / 睡着时一箭顶两箭多（这里）；打 Boss 弱点也更痛（World.local_fire）
##   子母雷珠  陷阱：子胆落地成雷，走近就炸；王踩上去炸翻（World._lay_mine + 这里）
##   流沙机弩  站桩：转起来以后站定开火，挨打减伤（Player.sand_guard）
##   穿云弩    打断：王起招时射中，招打断、露破绽；平时钉住它的腿（这里）
##   天心泪    蓄满一箭：打断起招、部位重创（这里）
## 房主算（Beast.take_hit 调 host_hit，要知道是哪把暗器打的："hit" 消息多带了暗器和标记）

## 暗器铺卡片 / 第一次拿到时的一句话（不写数字：用户说描述得太详细）
const LINE := {
	"xiujian": "翻滚中也打得准，极限闪避后弹匣自动装满",
	"meihua": "三箭落在同一处，开一朵梅花",
	"baoyu": "贴近了打，部位断得快",
	"zhuge": "连着打头，把王打晕",
	"longxu": "打中的部位落一颗星，全队打那里更痛",
	"kongque": "它踉跄、倒地、睡着的时候，一箭顶两箭",
	"zimu": "子胆落地成雷，王踩上去炸翻",
	"hansha": "转起来以后站定开火，挨打减伤",
	"zhuihun": "王起招时射中，把招打断；平时钉住它的腿",
	"guanyin": "蓄满一箭，打断起招、部位重创",
}
const NAME := {"xiujian": "闪身", "meihua": "梅花印", "baoyu": "断部位", "zhuge": "打晕", "longxu": "星标",
	"kongque": "抓窗口", "zimu": "布雷", "hansha": "站桩", "zhuihun": "打断", "guanyin": "蓄满一箭"}

const PLUM_WINDOW := 1.6        # 梅花印：三箭要在这么久里落在同一处
const PLUM_BONUS := 1.6         # 第三箭多打这一截（按这一箭的伤害算）
const ZHUGE_STUN := 1.3         # 连机神弩打头：晕值多加这么多（KingFeel 自己还加 1 倍）
const STAR_TIME := 10.0
const WINDOW_K := 2.2           # 流光翎：王踉跄 / 倒地 / 睡着
const WINDOW_HEAD := 1.25       # 流光翎：平时打头
const BAOYU_NEAR := 10.0
const INTERRUPT_CD := 6.0       # 同一只王被打断以后，几秒内不能再打断
const INTERRUPT_OPEN := 1.6
const PIN_TIME := 4.0
const MINE_CD := 12.0           # 同一只王被雷炸翻以后的冷却
const MINE_DOWN := 1.8

static var _plum := {}          # "灵兽:射手" -> [部位, 几箭, 最后一箭的时间]
static var _zg := {}            # 灵兽 -> [连着爆头几次, 最后一次的时间]（小灵兽）


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## 房主：Beast.take_hit 里调（real 已经算过护甲 / 标记 / 偷袭），返回改过的伤害。
## 这里只改伤害和挂状态；部位伤害、晕值的基础部分还是 KingFeel.host_hit 算
static func host_hit(b: Beast, gun: String, fl: String, real: float, lp: Vector3, head: bool, dist: float, shooter: int) -> float:
	var f: KingFeel = b.feel
	var part := ""
	if f:
		part = "head" if head else f.part_at(lp)
	# 追星针的星：谁打这个部位都更痛（部位多掉一截在 KingFeel.host_hit）
	if f and part != "" and f.starred(part):
		real *= 1.15
	# 护具（Gear）破势四件：打头把王打晕得快得多（看的是开枪那个人穿的）
	if f and head and Gear.peer_n(b.world, shooter, "breaker") >= 4:
		f.add_stun(real * Gear.BREAKER_STUN)
	match gun:
		"meihua":
			var key := "%d:%d" % [b.id, shooter]
			var now := _now()
			var p := part if part != "" else ("head" if head else "body")
			var e: Array = _plum.get(key, ["", 0, 0.0])
			if str(e[0]) == p and now - float(e[2]) < PLUM_WINDOW:
				e[1] = int(e[1]) + 1
			else:
				e = [p, 1, now]
			e[2] = now
			if int(e[1]) >= 3:
				e[1] = 0
				var extra := real * PLUM_BONUS
				real += extra
				if f and part != "":
					f.part_damage(part, extra)
				elif b.root_t <= 0.0:
					_root(b, 0.5)
				fx_event(b, "bloom", p)
			_plum[key] = e
		"baoyu":
			if f and part != "" and dist < BAOYU_NEAR:
				f.part_damage(part, real)
		"zhuge":
			if head:
				if f:
					f.add_stun(real * ZHUGE_STUN)
				else:
					var now := _now()
					var z: Array = _zg.get(b.id, [0, 0.0])
					z = [int(z[0]) + 1 if now - float(z[1]) < 1.2 else 1, now]
					if int(z[0]) >= 5:
						z[0] = 0
						_root(b, 0.9)
						fx_event(b, "daze", "")
					_zg[b.id] = z
		"longxu":
			if f and part != "":
				f.star(part, STAR_TIME)
			b.mark_t = maxf(b.mark_t, STAR_TIME)
			b.mark_mult = maxf(b.mark_mult, 1.2)
			if not f:
				fx_event(b, "star", "")
		"kongque":
			var window := b.napping or (f != null and (f.open_t > 0.0 or f.down_t > 0.0))
			if window:
				real *= WINDOW_K
				fx_event(b, "pierce", part)
			elif head:
				real *= WINDOW_HEAD
		"zhuihun":
			if not _interrupt(b):
				if f:
					f.pin(PIN_TIME)
				else:
					_root(b, 1.2)
		"guanyin":
			if "full" in fl:
				_interrupt(b)
				if f and part != "":
					f.part_damage(part, real)
		"zimu":
			if "mine" in fl and f and b.arts:
				var now := _now()
				if now >= float(b.get_meta("mine_cd", 0.0)):
					b.set_meta("mine_cd", now + MINE_CD)
					b.arts.cancel()
					b.world.arts.cancel_owner(b.id)
					f.knock("mine", MINE_DOWN)
	return real


## 穿云弩 / 天心泪：王正在起招 → 招打断（已经画出来的预警也收掉）、露破绽。返回有没有打断
static func _interrupt(b: Beast) -> bool:
	if b.feel == null or b.arts == null or not b.arts.winding():
		return false
	var now := _now()
	if now < float(b.get_meta("int_cd", 0.0)):
		return false
	b.set_meta("int_cd", now + INTERRUPT_CD)
	b.arts.cancel()
	b.world.arts.cancel_owner(b.id)
	b.feel.open(INTERRUPT_OPEN)
	fx_event(b, "interrupt", "")
	return true


## 小灵兽：定在原地一下（钉住 / 打懵）
static func _root(b: Beast, t: float) -> void:
	if b.root_t > 0.0:
		return
	b.root_t = t
	b.root_pos = b.global_position


# ------------------------------------------------------------------ 大家：看得见的样子

static func fx_event(b: Beast, kind: String, part: String) -> void:
	Net.send(0, "gart", [b.id, kind, part])
	_show(b.world, b, kind, part)


static func on_message(world: Node, d: Array) -> void:
	var b: Beast = world.beasts.get(int(d[0]))
	if b and b.alive():
		_show(world, b, str(d[1]), str(d[2]))


static func _show(world: Node, b: Beast, kind: String, part: String) -> void:
	var fx: Node = world.fx
	var pos := b.global_position + Vector3.UP * 0.6 * b.size_k
	if b.feel and part in b.feel.parts:
		pos = b.feel.part_pos(part)
	var near: bool = world.player.global_position.distance_to(pos) < 90.0
	match kind:
		"bloom":
			# 梅花：一团粉白花瓣炸开
			fx._flash(pos, Color(1.0, 0.6, 0.75), 1.6 * b.size_k, 0.15)
			fx._sparks(pos, Vector3.UP, Color(1.0, 0.72, 0.82), 26, 6.5, 0.7, 0.07, -2.5, 180.0)
			fx._air_ring(pos, Color(1.0, 0.65, 0.8), 0.3, 2.2 * b.size_k, 0.35, 0.5, "ring", 2.0)
			if near:
				Sfx.play_at("snap", pos, 0.0, 0.05, 1.45)
		"star":
			if not (b.feel and part in b.feel.parts):
				WeakGlint.spawn(fx, func() -> Vector3:
					return b.global_position + Vector3.UP * 0.9 * b.size_k if is_instance_valid(b) and b.alive() and b.mark_t > 0.0 else Vector3.INF,
					STAR_TIME, 0.5 * b.size_k, Color(0.6, 0.85, 1.0))
			if near:
				Sfx.play_at("rare", pos, -10.0, 0.05, 1.8)
		"daze":
			fx._sparks(pos + Vector3.UP * 0.4, Vector3.UP, Color(1.0, 0.95, 0.6), 12, 3.0, 0.5, 0.05, 0.0, 180.0)
		"pierce":
			# 流光翎抓住窗口：一道青光穿过去
			fx._flash(pos, Color(0.5, 1.0, 0.9), 2.4 * b.size_k, 0.12, "flare", 3.0)
			if near:
				Sfx.play_at("hit_head", pos, 2.0, 0.03, 0.7)
		"interrupt":
			fx._flash(pos, Color(1.0, 0.95, 0.8), 3.0 * b.size_k, 0.18, "flare", 3.5)
			fx._sparks(pos, Vector3.UP, Color(1.0, 0.9, 0.6), 30, 9.0, 0.6, 0.08, -6.0, 180.0)
			if near:
				Sfx.play_at("slam", pos, 4.0, 0.05, 1.3)
				KingFeel.tip(world, "interrupt", "起招时射中，招就断了")


## 第一次拿这把暗器开火时提示一句它的打法
static func tip(world: Node, gun: String) -> void:
	if LINE.has(gun):
		KingFeel.tip(world, "art_" + gun, "%s：%s" % [str(Data.WEAPONS[gun]["name"]), str(LINE[gun])])
