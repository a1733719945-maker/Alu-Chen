class_name TouchControls
extends CanvasLayer
## 手机触屏操作。
##   左半屏：按哪里哪里就是摇杆中心（浮动摇杆），推到圈外往前就是冲刺
##   右半屏空白处：滑动转视角；按住开火 / 开镜键时手指也能拖动转视角（和手机射击游戏一样）
##   右下一圈：开火、开镜（点一下开、再点关）、跳、蹲（轻点翻滚 / 按住蹲）、换弹、引魂索（按住蓄力松开甩）、三个神通
##   其他：交互（旁边有能交互的才出现，按住能救人）、回血丹、物品栏 1-5、丢出、上面一排（暂停、地图、灵相、成就、猎灵榜、鱼饵、魂师榜）
##   打开面板 / 暂停时只留右上角"返回"，面板用手指直接点
## 按钮都是发现有的输入动作，游戏逻辑里不用管是键盘还是触屏：
##   大部分直接改按键状态（Input.action_press），手指按下那一刻就生效，同一帧的物理和逻辑都能看到"刚按下"；
##   暂停、面板这几个是靠输入事件触发的，延后一帧发一个 InputEventAction。
## 每根手指（index）记住它按的是什么，多指同时操作互不影响。

const STICK_R := 70.0            # 摇杆半径（界面像素）
const LEFT_ZONE := 0.42          # 屏幕左边这么宽的地方按下去是摇杆

var world: Node
var _canvas: Control
var _close: Button
var _btns: Array[Dictionary] = []
var _fingers := {}               # 手指 index -> {kind: "stick" / "look" / "btn", id}
var _stick_idx := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _sprinting := false
var _breath := false
var _ads_on := false
var _ads_slot := -1
const EVENT_ACTIONS := ["pause", "wuhun_panel", "achievements", "hunt_board"]
var _tex := {}
var _was_active := false
var _menu_open := false
var _inset := Vector2.ZERO       # 刘海屏：左右两边要让出来的宽度（界面坐标）


func _ready() -> void:
	layer = 50                   # 在所有面板上面（"返回"键要一直点得到）
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_all)
	# 打开面板 / 暂停时右上角的"返回"（面板里的东西直接用手指点）
	_close = Button.new()
	_close.text = "返回"
	_close.focus_mode = Control.FOCUS_NONE
	_close.add_theme_font_size_override("font_size", 28)
	_close.custom_minimum_size = Vector2(150, 72)
	_close.visible = false
	_close.pressed.connect(func(): _send("pause", true); _send("pause", false))
	add_child(_close)
	# 左上角（面板自己的关闭键一般在右上角，别叠在一起）
	_close.position = Vector2(12, 12)
	_define_buttons()


# ------------------------------------------------------------------ 按钮

## anchor：屏幕上的参照点（0~1），off：相对参照点的位置（界面像素），r：半径
## kind：action 按下发动作 / toggle 点一下开再点一下关 / call 调函数
## look：按着这个键还能拖动转视角；show：什么时候显示
func _define_buttons() -> void:
	var br := Vector2(1, 1)
	_btn("fire", br, Vector2(-135, -150), 60, "action", "fire", "开火", {"look": true, "draw": "fire"})
	_btn("aim", br, Vector2(-255, -140), 40, "toggle", "aim", "开镜", {"look": true, "draw": "aim"})
	_btn("jump", br, Vector2(-50, -62), 38, "action", "jump", "跳", {"draw": "jump"})
	_btn("crouch", br, Vector2(-232, -45), 34, "action", "crouch", "蹲/滚", {"draw": "crouch"})
	_btn("reload", br, Vector2(-232, -245), 30, "action", "reload", "换弹", {"draw": "reload"})
	_btn("lure", br, Vector2(-135, -282), 42, "action", "lure", "引魂索", {"icon": "lure"})
	_btn("sk1", br, Vector2(-48, -185), 30, "action", "skill_1", "Q", {"skill": 0})
	_btn("sk2", br, Vector2(-48, -257), 30, "action", "skill_2", "E", {"skill": 1})
	_btn("sk3", br, Vector2(-48, -329), 30, "call", "", "F", {"skill": 2})
	_btn("breath", br, Vector2(-335, -140), 32, "hold_sprint", "", "屏息", {"show": "scoped"})
	_btn("interact", br, Vector2(-370, -290), 46, "action", "interact", "交互", {"show": "interact"})
	_btn("pill", Vector2(0, 1), Vector2(56, -262), 28, "action", "pill", "回血", {"icon": "pill"})
	# 物品栏 1-5：直接点 HUD 下中的格子；丢出键在物品栏右边
	for i in 5:
		_btn("slot%d" % (i + 1), Vector2(0.5, 1), Vector2.ZERO, 26, "action", "weapon_%d" % (i + 1), str(i + 1), {"slot": i})
	_btn("throw", Vector2(0.5, 1), Vector2(230, -42), 24, "action", "throw", "丢", {})
	# 点小地图 = 开大地图；大地图开着的时候点它 = 关掉
	_btn("minimap", Vector2(1, 0), Vector2.ZERO, 0, "action", "map", "", {"rect": "minimap"})
	_btn("bigmap", Vector2(0.5, 0.5), Vector2.ZERO, 0, "action", "map", "", {"rect": "bigmap"})
	# 左上角：暂停、菜单（点开一列：灵相、成就、猎灵榜、鱼饵、排名）
	_btn("pause", Vector2(0, 0), Vector2(34, 34), 24, "action", "pause", "", {"draw": "pause"})
	_btn("menu", Vector2(0, 0), Vector2(34, 96), 24, "menu", "", "菜单", {"draw": "menu"})
	var items := [["wuhun", "wuhun_panel", "灵相"], ["ach", "achievements", "成就"], ["board", "hunt_board", "猎灵榜"],
		["bait", "bait", "换鱼饵"], ["score", "scoreboard", "排名"], ["mapbtn", "map", "大地图"]]
	for i in items.size():
		_btn(items[i][0], Vector2(0, 0), Vector2(96, 150 + i * 50), 26, "action", items[i][1], items[i][2], {"small": true, "show": "menu"})


func _btn(id: String, anchor: Vector2, off: Vector2, r: float, kind: String, action: String, label: String, extra: Dictionary) -> void:
	var b := {"id": id, "anchor": anchor, "off": off, "r": r, "kind": kind, "action": action, "label": label,
		"look": false, "draw": "", "icon": "", "show": "", "small": false, "down": false}
	b.merge(extra, true)
	_btns.append(b)


## 贴在 HUD 元素上的按钮（物品栏格子、小地图、大地图）：用它们在屏幕上的矩形
func _rect(b: Dictionary) -> Rect2:
	var hud: Hud = world.hud
	if b.has("slot"):
		return hud.hotbar_rect(int(b["slot"]))
	match str(b.get("rect", "")):
		"minimap":
			return hud.minimap_rect()
		"bigmap":
			return hud.bigmap_rect()
	return Rect2()


## 刘海 / 挖孔屏横着拿时，左边或右边有一块不能放东西（安全区域以外）
func _safe_insets() -> Vector2:
	if not Settings.is_mobile():
		return Vector2.ZERO
	var safe := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	if win.x <= 0 or safe.size.x <= 0:
		return Vector2.ZERO
	var k := _canvas.size.x / float(win.x)
	return Vector2(maxf(safe.position.x * k, 0.0), maxf((win.x - safe.end.x) * k, 0.0))


func _center(b: Dictionary) -> Vector2:
	if b["id"] == "throw":
		# 丢出键跟着物品栏最后一格
		var last: Rect2 = world.hud.hotbar_rect(4)
		if last.size.x > 0.0:
			return Vector2(last.end.x + 34 * Settings.touch_size, last.get_center().y)
	var s := Settings.touch_size
	var size := _canvas.size
	var a: Vector2 = b["anchor"]
	# 离屏幕边的距离随按钮大小一起缩放；靠左 / 靠右的躲开刘海
	var p := Vector2(a.x * size.x, a.y * size.y) + (b["off"] as Vector2) * s
	if a.x == 0.0:
		p.x += _inset.x
	elif a.x == 1.0:
		p.x -= _inset.y
	return p


func _radius(b: Dictionary) -> float:
	return float(b["r"]) * Settings.touch_size


func _visible(b: Dictionary) -> bool:
	var p: Player = world.player if world else null
	if not p:
		return false
	match str(b["show"]):
		"scoped":
			return p.scoped
		"interact":
			return bool(world.nearest_interactable().get("act", false)) and not p.dead
		"menu":
			return _menu_open
	if b.has("rect"):
		return _rect(b).size.x > 0.0
	if b.has("slot"):
		return _rect(b).size.x > 0.0
	if b.has("skill"):
		return Profile.rings.size() > 0
	return true


# ------------------------------------------------------------------ 状态

## 现在该不该接管触摸：触屏模式、在游戏里、没打开面板、没暂停
func _active() -> bool:
	if not Settings.touch_active() or not world or not is_instance_valid(world) or not world.is_inside_tree():
		return false
	if world.paused or world.ui_open:
		return false
	# 播过场的时候让开（点屏幕跳过）
	if get_tree().get_first_node_in_group("cutscene"):
		return false
	var p: Player = world.player
	return p != null and p.input_enabled


func _exit_tree() -> void:
	# 回主菜单时界面缩放恢复
	if get_tree() and get_tree().root:
		get_tree().root.content_scale_factor = 1.0


func _process(_dt: float) -> void:
	var on := _active()
	# 界面缩放：玩的时候按手机屏幕放大；打开面板 / 暂停时恢复原大小，面板才放得下
	var want := Settings.hud_ui_scale() if (world and is_instance_valid(world) and not world.paused and not world.ui_open) else 1.0
	var root := get_tree().root
	if not is_equal_approx(root.content_scale_factor, want):
		root.content_scale_factor = want
	if on != _was_active:
		_was_active = on
		if not on:
			_release_all()
	var show_ui := Settings.touch_active() and world != null and is_instance_valid(world)
	_canvas.visible = show_ui and on
	_close.visible = show_ui and not on and world != null and (world.paused or world.ui_open)
	var ins := _safe_insets()
	if ins != _inset and world and is_instance_valid(world) and world.hud:
		_inset = ins
		world.hud.set_safe_insets(ins.x, ins.y)
	if on:
		# 切了暗器就退出开镜
		var p: Player = world.player
		if _ads_on and p.slot != _ads_slot:
			_ads_on = false
			_send("aim", false)
		_canvas.queue_redraw()


func _send(action: String, pressed: bool) -> void:
	if not InputMap.has_action(action):
		return
	if action in EVENT_ACTIONS:
		# 这几个是 _unhandled_input 里看事件的：延后发，别在别的输入事件里面套着发
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		ev.strength = 1.0 if pressed else 0.0
		Input.parse_input_event.call_deferred(ev)
	elif pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)


## 松开所有手指按着的东西（打开面板、暂停、切到后台时）
func _release_all() -> void:
	for b in _btns:
		if b["down"]:
			_btn_up(b)
	_fingers.clear()
	_stick_idx = -1
	_stick_pos = _stick_origin
	for a in ["move_left", "move_right", "move_forward", "move_back"]:
		Input.action_release(a)
	if _sprinting or _breath:
		Input.action_release("sprint")
	_sprinting = false
	_breath = false
	if _ads_on:
		_ads_on = false
		_send("aim", false)


# ------------------------------------------------------------------ 触摸

func _input(event: InputEvent) -> void:
	if not _active():
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_down(t.index, t.position)
		else:
			_up(t.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_drag(d.index, d.position, d.relative)
		get_viewport().set_input_as_handled()


func _down(idx: int, pos: Vector2) -> void:
	# 先看按到哪个按钮（离得最近的，按钮外面留一点余量好按）
	var hit: Dictionary = {}
	var best := INF
	for b in _btns:
		if not _visible(b) or b["down"]:
			continue
		if b.has("rect") or b.has("slot"):
			var rc := _rect(b).grow(6)
			if rc.has_point(pos):
				var d0 := pos.distance_to(rc.get_center()) * 0.5
				if d0 < best:
					best = d0
					hit = b
			continue
		var d := pos.distance_to(_center(b))
		if d < _radius(b) * 1.2 and d < best:
			best = d
			hit = b
	if not hit.is_empty():
		_fingers[idx] = {"kind": "btn", "id": hit["id"]}
		_btn_down(hit)
		return
	if pos.x < _canvas.size.x * LEFT_ZONE and _stick_idx < 0:
		_fingers[idx] = {"kind": "stick"}
		_stick_idx = idx
		_stick_origin = pos
		_stick_pos = pos
		_update_stick()
		return
	_fingers[idx] = {"kind": "look"}


func _drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	if not _fingers.has(idx):
		return
	var f: Dictionary = _fingers[idx]
	match str(f["kind"]):
		"stick":
			_stick_pos = pos
			_update_stick()
		"look":
			world.player.touch_look(rel)
		"btn":
			var b := _find(str(f["id"]))
			if not b.is_empty() and b["look"]:
				world.player.touch_look(rel)


func _up(idx: int) -> void:
	if not _fingers.has(idx):
		return
	var f: Dictionary = _fingers[idx]
	_fingers.erase(idx)
	match str(f["kind"]):
		"stick":
			_stick_idx = -1
			_stick_pos = _stick_origin
			_update_stick()
		"btn":
			var b := _find(str(f["id"]))
			if not b.is_empty():
				_btn_up(b)


func _find(id: String) -> Dictionary:
	for b in _btns:
		if b["id"] == id:
			return b
	return {}


func _btn_down(b: Dictionary) -> void:
	b["down"] = true
	match str(b["kind"]):
		"action":
			_send(b["action"], true)
		"toggle":
			_ads_on = not _ads_on
			_ads_slot = world.player.slot
			_send(b["action"], _ads_on)
		"hold_sprint":
			_breath = true
			Input.action_press("sprint")
		"call":
			if b.has("skill"):
				world.skills.cast_slot(int(b["skill"]))
		"menu":
			_menu_open = not _menu_open
	# 点了菜单里的一项就收起来（"排名"是按住看，松手再收）
	if str(b["show"]) == "menu" and b["id"] != "score":
		_menu_open = false


func _btn_up(b: Dictionary) -> void:
	b["down"] = false
	match str(b["kind"]):
		"action":
			_send(b["action"], false)
		"hold_sprint":
			_breath = false
			if not _sprinting:
				Input.action_release("sprint")
	if b["id"] == "score":
		_menu_open = false


## 摇杆 → 四个移动动作的力度；推出圈外、方向朝前就是冲刺
func _update_stick() -> void:
	var v := Vector2.ZERO
	if _stick_idx >= 0:
		v = (_stick_pos - _stick_origin) / (STICK_R * Settings.touch_size)
	var l := v.length()
	var dir := Vector2.ZERO
	if l > 0.12:
		dir = v / l * clampf((l - 0.12) / 0.88, 0.0, 1.0)
	_axis("move_left", maxf(-dir.x, 0.0))
	_axis("move_right", maxf(dir.x, 0.0))
	_axis("move_forward", maxf(-dir.y, 0.0))
	_axis("move_back", maxf(dir.y, 0.0))
	var sprint := l > 1.1 and v.y < -0.55 * l
	if sprint != _sprinting:
		_sprinting = sprint
		if sprint:
			Input.action_press("sprint")
		elif not _breath:
			Input.action_release("sprint")


func _axis(action: String, s: float) -> void:
	if s > 0.001:
		Input.action_press(action, s)
	else:
		Input.action_release(action)


# ------------------------------------------------------------------ 画

func _icon(name: String) -> Texture2D:
	if not _tex.has(name):
		var path := UiKit.ICONS + name + ".svg"
		_tex[name] = load(path) if ResourceLoader.exists(path) else null
	return _tex[name]


func _draw_all() -> void:
	var p: Player = world.player if world else null
	if not p:
		return
	var font: Font = Data.font_bold
	# 摇杆：没按的时候在左下角淡淡地画一个
	var base := _stick_origin if _stick_idx >= 0 else Vector2(170, _canvas.size.y - 170) * Vector2(1, 1)
	if _stick_idx < 0:
		base = Vector2(160 * Settings.touch_size + _inset.x, _canvas.size.y - 170 * Settings.touch_size)
	var sr := STICK_R * Settings.touch_size
	_canvas.draw_circle(base, sr, Color(0, 0, 0, 0.22 if _stick_idx >= 0 else 0.12))
	_canvas.draw_arc(base, sr, 0, TAU, 48, Color(1, 1, 1, 0.3 if _stick_idx >= 0 else 0.15), 2.0, true)
	var knob := base
	if _stick_idx >= 0:
		knob = base + (_stick_pos - _stick_origin).limit_length(sr)
	_canvas.draw_circle(knob, sr * 0.42, Color(1, 1, 1, 0.35 if _stick_idx >= 0 else 0.18))
	if _sprinting:
		_canvas.draw_string(font, base + Vector2(-sr, sr + 22), "冲刺", HORIZONTAL_ALIGNMENT_CENTER, sr * 2, 18, UiKit.GOLD)
	var bite: bool = p.lure.state == Lure.S.BITE
	var t := Time.get_ticks_msec() / 1000.0
	for b in _btns:
		if not _visible(b):
			continue
		var c := _center(b)
		var r := _radius(b)
		var down: bool = b["down"] or (b["kind"] == "toggle" and _ads_on)
		var fill := Color(1, 1, 1, 0.28) if down else Color(0.02, 0.03, 0.05, 0.38)
		var edge := Color(1, 1, 1, 0.35)
		if b["id"] == "lure" and bite:
			# 咬钩了：引魂索键闪金色，赶紧按
			var k := 0.5 + 0.5 * sin(t * 18.0)
			fill = Color(1.0, 0.78, 0.3, 0.35 + k * 0.4)
			edge = UiKit.GOLD
		if b["id"] == "fire":
			edge = Color(1, 1, 1, 0.5)
		if b["small"]:
			var rect := Rect2(c - Vector2(r * 1.35, r * 0.75), Vector2(r * 2.7, r * 1.5))
			_canvas.draw_rect(rect, fill)
			_canvas.draw_rect(rect, edge, false, 1.0)
			_canvas.draw_string(font, Vector2(rect.position.x, c.y + 7), str(b["label"]), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 18, UiKit.MOON)
			continue
		if b.has("rect") or b.has("slot"):
			if b["down"]:
				var rc := _rect(b)
				_canvas.draw_rect(rc, Color(1, 1, 1, 0.18))
			continue
		_canvas.draw_circle(c, r, fill)
		_canvas.draw_arc(c, r, 0, TAU, 40, edge, 2.0, true)
		if b.has("skill"):
			_draw_skill(b, c, r, font)
			continue
		if str(b["icon"]) != "":
			var tex := _icon(str(b["icon"]))
			if tex:
				var s := r * 1.05
				_canvas.draw_texture_rect(tex, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false, Color(1, 1, 1, 0.9))
		elif str(b["draw"]) != "":
			_draw_symbol(str(b["draw"]), c, r)
		else:
			_canvas.draw_string(font, Vector2(c.x - r, c.y + 8), str(b["label"]), HORIZONTAL_ALIGNMENT_CENTER, r * 2, 20 if r > 36 else 17, UiKit.MOON)
		if b["id"] == "fire":
			_draw_ammo_in(c, r, font)
		# 钩子、回血下面写个小字（其他按钮看图标就懂）
		if b["id"] in ["lure", "pill"]:
			_canvas.draw_string(font, Vector2(c.x - 60, c.y + r + 17), str(b["label"]), HORIZONTAL_ALIGNMENT_CENTER, 120, 14, Color(1, 1, 1, 0.7))


## 开火键里面的下半截写弹药（电脑版在右下角，触屏时那里是按钮）；换弹时写"换弹"
func _draw_ammo_in(c: Vector2, r: float, font: Font) -> void:
	var info: Array = world.hud.ammo_info()
	var line := str(info[1]) + (str(info[2]).replace(" ", "") if str(info[2]) != "" else "")
	var col := Color.WHITE
	if str(info[3]) != "":
		line = str(info[3]).replace("…", "")
		col = UiKit.GOLD
	_canvas.draw_string(font, Vector2(c.x - r, c.y + r * 0.62), line, HORIZONTAL_ALIGNMENT_CENTER, r * 2, 17, col)


func _draw_skill(b: Dictionary, c: Vector2, r: float, font: Font) -> void:
	var k := int(b["skill"])
	var ring: int = world.skills.slot_ring(k)
	if ring < 0:
		_canvas.draw_string(font, Vector2(c.x - r, c.y + 7), str(b["label"]), HORIZONTAL_ALIGNMENT_CENTER, r * 2, 18, Color(1, 1, 1, 0.35))
		return
	var sid: String = world.skills.slot_skill(ring)
	var s: Dictionary = Data.SKILLS.get(sid, {})
	var tex := _icon(UiKit.skill_icon(sid))
	var cd: float = world.skills.cooldowns[ring]
	var col := Color.WHITE
	if cd > 0.0:
		col = Color(0.55, 0.55, 0.55)
	elif world.player.soul < float(s.get("cost", 0)):
		col = Color(0.45, 0.6, 1.0)
	if tex:
		var sz := r * 1.2
		_canvas.draw_texture_rect(tex, Rect2(c - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false, col)
	if cd > 0.0:
		var full := maxf(float(s.get("cd", 1.0)), 0.1)
		var a := TAU * clampf(cd / full, 0.0, 1.0)
		_canvas.draw_arc(c, r - 3, -PI * 0.5, -PI * 0.5 + a, 32, Color(0, 0, 0, 0.6), 5.0, true)
		_canvas.draw_string(font, Vector2(c.x - r, c.y + 8), "%d" % ceili(cd), HORIZONTAL_ALIGNMENT_CENTER, r * 2, 20, Color.WHITE)
	_canvas.draw_string(font, Vector2(c.x - r - 6, c.y - r + 2), str(b["label"]), HORIZONTAL_ALIGNMENT_LEFT, 30, 13, Color(1, 1, 1, 0.8))


## 简单的线条图标（开火、开镜、跳、蹲、换弹、暂停）
func _draw_symbol(kind: String, c: Vector2, r: float) -> void:
	var col := Color(1, 1, 1, 0.9)
	var w := maxf(r * 0.07, 2.0)
	match kind:
		"fire":
			var f := c + Vector2(0, -r * 0.14)
			_canvas.draw_arc(f, r * 0.34, 0, TAU, 32, col, w, true)
			for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				_canvas.draw_line(f + d * r * 0.16, f + d * r * 0.5, col, w, true)
			_canvas.draw_circle(f, w, col)
		"aim":
			_canvas.draw_arc(c, r * 0.5, 0, TAU, 32, col, w, true)
			_canvas.draw_line(c + Vector2(-r * 0.5, 0), c + Vector2(r * 0.5, 0), col, w * 0.7, true)
			_canvas.draw_line(c + Vector2(0, -r * 0.5), c + Vector2(0, r * 0.5), col, w * 0.7, true)
		"jump":
			_canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.5), c + Vector2(r * 0.4, -r * 0.05), c + Vector2(-r * 0.4, -r * 0.05)]), col)
			_canvas.draw_line(c + Vector2(0, -r * 0.1), c + Vector2(0, r * 0.45), col, w * 1.4, true)
		"crouch":
			_canvas.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.4, -r * 0.3), c + Vector2(0, r * 0.1), c + Vector2(r * 0.4, -r * 0.3)]), col, w * 1.3, true)
			_canvas.draw_line(c + Vector2(-r * 0.45, r * 0.4), c + Vector2(r * 0.45, r * 0.4), col, w * 1.3, true)
		"reload":
			_canvas.draw_arc(c, r * 0.45, -PI * 0.2, PI * 1.3, 28, col, w, true)
			var tip := c + Vector2.from_angle(-PI * 0.2) * r * 0.45
			_canvas.draw_colored_polygon(PackedVector2Array([tip + Vector2(-r * 0.05, -r * 0.28), tip + Vector2(r * 0.22, r * 0.05), tip + Vector2(-r * 0.2, r * 0.12)]), col)
		"pause":
			_canvas.draw_rect(Rect2(c + Vector2(-r * 0.35, -r * 0.4), Vector2(r * 0.22, r * 0.8)), col)
			_canvas.draw_rect(Rect2(c + Vector2(r * 0.13, -r * 0.4), Vector2(r * 0.22, r * 0.8)), col)
		"menu":
			for k in 3:
				var y := (k - 1) * r * 0.32
				_canvas.draw_line(c + Vector2(-r * 0.42, y), c + Vector2(r * 0.42, y), col, w * 1.2, true)
