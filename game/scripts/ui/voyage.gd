class_name Voyage
extends CanvasLayer
## 过场动画：画面是 tools/boat_anim 里用 Remotion 画、渲染后用 ffmpeg 转成 Ogg Theora 的视频（assets/cutscene/*.ogv）。
##   voyage.ogv   渡海换岛（上面叠"前往 · 第几章"和这一章的一句故事）
##   prologue.ogv 序章：天倾、五大灵主、栖霞村、怎么玩（第一次进游戏播，主菜单"序章"能重看）
##   ascend.ogv   飞升结局 → 九重天 → 轮回
##   dungeon.ogv  进洞天秘境（叠秘境名字）
##   hunt.ogv     去猎场（叠猎物名字）
## 字幕（captions）也可以叠在视频上：[[开始秒, 结束秒, 文字], ...]。按 Esc / 空格跳过。

signal finished

var video := "res://assets/cutscene/voyage.ogv"
var length := 7.0
var title := ""
var captions: Array = []
var music := ""               # 播的时候换成哪首背景音乐（空 = 不换）
var dim := 0.0                # 视频上面再压一层黑（让字更清楚）
var _player: VideoStreamPlayer
var _label: Label
var _box: Control
var _cap: Label
var _t := 0.0
var _done := false


func _ready() -> void:
	layer = 30
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	add_child(bg)
	UiKit.fill(bg)
	var stream: VideoStream = load(video) if ResourceLoader.exists(video) else null
	if stream:
		_player = VideoStreamPlayer.new()
		_player.stream = stream
		_player.expand = true
		_player.volume_db = -80.0
		add_child(_player)
		UiKit.fill(_player)
		_player.finished.connect(_finish)
		_player.play()
	if dim > 0.0:
		var d := ColorRect.new()
		d.color = Color(0, 0, 0, dim)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(d)
		UiKit.fill(d)
	# 标题："前往 · 第二章 · 落霞林"：第一段做眉题，后面做大标题
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	UiKit.place(box, Vector4(0, 1, 1, 1), Vector4(0, -230, 0, -110))
	add_child(box)
	var cut := title.find(" · ")
	var k := UiKit.kicker(title.substr(0, cut) if cut > 0 else "", UiKit.GOLD, 16)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiKit._text_style(k, 3)
	box.add_child(k)
	_label = UiKit.title(title.substr(cut + 3) if cut > 0 else title, 54, Color.WHITE)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiKit._text_style(_label, 4)
	box.add_child(_label)
	box.modulate.a = 0.0
	box.visible = title != ""
	_box = box
	# 字幕：屏幕下方居中
	_cap = UiKit.label("", 22, Color(0.95, 0.93, 0.88))
	_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit._text_style(_cap, 4)
	UiKit.place(_cap, Vector4(0.5, 1, 0.5, 1), Vector4(-620, -104, 620, -40))
	_cap.modulate.a = 0.0
	add_child(_cap)
	var skip := UiKit.key_hint("空格", "跳过", 15, UiKit.MIST)
	UiKit.place(skip, Vector4(1, 0, 1, 0), Vector4(-160, 24, -30, 50))
	add_child(skip)
	if music != "":
		Sfx.play_music(music)
	if not stream:
		call_deferred("_finish")


func _process(dt: float) -> void:
	if _done:
		return
	_t += dt
	_box.modulate.a = clampf((_t - 0.6) / 0.6, 0.0, 1.0) * clampf((length - _t) / 0.5, 0.0, 1.0)
	# 字幕：淡入淡出
	var txt := ""
	var a := 0.0
	for c in captions:
		var t0 := float(c[0])
		var t1 := float(c[1])
		if _t >= t0 and _t <= t1:
			txt = str(c[2])
			a = clampf((_t - t0) / 0.45, 0.0, 1.0) * clampf((t1 - _t) / 0.45, 0.0, 1.0)
	if _cap.text != txt:
		_cap.text = txt
	_cap.modulate.a = a
	if _t > length + 2.0:
		_finish()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("jump"):
		get_viewport().set_input_as_handled()
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit()
	queue_free()
