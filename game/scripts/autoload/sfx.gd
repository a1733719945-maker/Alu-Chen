extends Node
## 音效。声音文件由 tools/gen_sfx.py 合成，放在 assets/sfx/。

const DIR := "res://assets/sfx/"
const POOL_2D := 24
const POOL_3D := 40

var _streams := {}
var _pool2d: Array[AudioStreamPlayer] = []
var _pool3d: Array[AudioStreamPlayer3D] = []
var _i2d := 0
var _i3d := 0
var _ambient: AudioStreamPlayer
var _lowpass_idx := -1


func _ready() -> void:
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool2d.append(p)
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 8.0
		p.max_distance = 140.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.panning_strength = 0.8
		add_child(p)
		_pool3d.append(p)
	_ambient = AudioStreamPlayer.new()
	add_child(_ambient)


func stream(sound: String) -> AudioStream:
	if _streams.has(sound):
		return _streams[sound]
	var path := DIR + sound + ".wav"
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	_streams[sound] = s
	return s


## 播放不带位置的声音（自己开枪、界面音效）
func play(sound: String, volume_db := 0.0, pitch_jitter := 0.0, pitch := 1.0) -> void:
	var s := stream(sound)
	if not s:
		return
	var p := _pool2d[_i2d]
	_i2d = (_i2d + 1) % _pool2d.size()
	p.stream = s
	p.volume_db = volume_db + linear_to_db(maxf(Settings.sfx_volume, 0.0001))
	p.pitch_scale = pitch * (1.0 + randf_range(-pitch_jitter, pitch_jitter))
	p.play()


## 在世界里某个位置播放（别人开枪、魂兽叫声、落水）
func play_at(sound: String, pos: Vector3, volume_db := 0.0, pitch_jitter := 0.05, pitch := 1.0) -> void:
	var s := stream(sound)
	if not s or not is_inside_tree():
		return
	var p := _pool3d[_i3d]
	_i3d = (_i3d + 1) % _pool3d.size()
	p.stream = s
	p.global_position = pos
	p.volume_db = volume_db + linear_to_db(maxf(Settings.sfx_volume, 0.0001))
	p.pitch_scale = pitch * (1.0 + randf_range(-pitch_jitter, pitch_jitter))
	p.play()


## 眼睛在水下：所有声音变闷（主总线加低通）
func set_underwater(on: bool) -> void:
	var bus := AudioServer.get_bus_index("Master")
	if _lowpass_idx < 0:
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 700.0
		lp.resonance = 0.6
		AudioServer.add_bus_effect(bus, lp)
		_lowpass_idx = AudioServer.get_bus_effect_count(bus) - 1
	AudioServer.set_bus_effect_enabled(bus, _lowpass_idx, on)
	if on:
		play("water_in", -4.0, 0.05)


func play_ambient(sound: String, volume_db := -14.0) -> void:
	var s := stream(sound)
	if not s:
		return
	if s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = int(s.get_length() * s.mix_rate)
	_ambient.stream = s
	_ambient.volume_db = volume_db
	_ambient.play()


func stop_ambient() -> void:
	_ambient.stop()
