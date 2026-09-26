class_name Voyage
extends CanvasLayer
## 过场动画：坐船换章节（6 秒，远景 → 近景 → 目的地的岛），成神结局（10 秒，video / length 换成 ending）。
## 画面是 tools/boat_anim 里用 Remotion 渲染、再用 ffmpeg 转成 Ogg Theora 的视频（assets/cutscene/voyage.ogv），
## 上面叠一行"前往 · 第几章"。按 Esc / 空格可以跳过。

signal finished

var video := "res://assets/cutscene/voyage.ogv"
var length := 6.0
var title := ""
var _player: VideoStreamPlayer
var _label: Label
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
	_label = UiKit.title(title, 54, Color(1.0, 0.9, 0.7))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_constant_override("outline_size", 12)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	UiKit.place(_label, Vector4(0, 1, 1, 1), Vector4(0, -150, 0, -80))
	_label.modulate.a = 0.0
	add_child(_label)
	Sfx.play("splash_small", -8.0)
	if not stream:
		call_deferred("_finish")


func _process(dt: float) -> void:
	if _done:
		return
	_t += dt
	_label.modulate.a = clampf((_t - 0.6) / 0.6, 0.0, 1.0) * clampf((length - _t) / 0.5, 0.0, 1.0)
	if int(_t * 1.6) != int((_t - dt) * 1.6):
		Sfx.play("splash_small", -18.0, 0.2, 0.8)
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
