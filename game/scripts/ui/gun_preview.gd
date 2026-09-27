class_name GunPreview
extends SubViewportContainer
## 暗器的 3D 预览（暗器铺外观页、自己画皮肤）：摄影棚打光 + 天空反射（金属皮肤才看得出反光），
## 慢慢转；鼠标按住拖动可以自己转着看。side = true 时是正侧面的正交视图（画皮肤用：画面正好对上画布）。

var vp: SubViewport
var cam: Camera3D
var pivot: Node3D
var model: Node3D
var weapon := ""
var side := false
var spin := true
var _yaw := 0.6
var _pitch := 0.12
var _drag := false
var _idle := 0.0


func _init(p_size := Vector2i(640, 360), p_side := false) -> void:
	side = p_side
	stretch = true
	custom_minimum_size = Vector2(p_size)
	mouse_filter = Control.MOUSE_FILTER_STOP if not side else Control.MOUSE_FILTER_IGNORE
	vp = SubViewport.new()
	# 视口大小由容器自己撑（stretch）；这里设大了，容器的最小尺寸会按画面缩放放大，把界面撑出屏幕
	vp.size = Vector2i(16, 16)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(vp)
	var we := WorldEnvironment.new()
	we.environment = _env()
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-40), deg_to_rad(35), 0)
	key.light_energy = 1.6
	key.light_color = Color(1.0, 0.96, 0.9)
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation = Vector3(deg_to_rad(-20), deg_to_rad(200), 0)
	rim.light_energy = 1.2
	rim.light_color = Color(0.75, 0.85, 1.0)
	vp.add_child(rim)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-0.6, -0.3, 0.8)
	fill.omni_range = 4.0
	fill.light_energy = 0.6
	vp.add_child(fill)
	pivot = Node3D.new()
	vp.add_child(pivot)
	cam = Camera3D.new()
	vp.add_child(cam)
	if side:
		# 从右边看过去：屏幕左边是枪尾（+Z），右边是枪口（-Z）
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		cam.position = Vector3(2.0, 0, 0)
		cam.rotation = Vector3(0, PI / 2, 0)
		cam.near = 0.05
		cam.far = 5.0
	else:
		cam.fov = 30.0
		cam.near = 0.02
		cam.far = 10.0


static func _env() -> Environment:
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = load("res://assets/sky/sky_day.hdr")
	var sky := Sky.new()
	sky.sky_material = pano
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.7
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.1
	e.glow_enabled = true
	e.glow_hdr_threshold = 1.0
	e.glow_intensity = 0.6
	return e


## 显示一把暗器。skin 空 = 这把暗器自己穿的；on = 配件（null 用存档里装的；{} 什么都不装）；charm 同理
func show_gun(id: String, skin := "", on: Variant = null, charm: Variant = null) -> void:
	weapon = id
	if model:
		model.queue_free()
	model = WeaponModels.build(id, skin, "", on, false, charm)
	# 手和袖子不要（只看暗器）
	for n in ["LeftHand"]:
		var h := model.get_node_or_null(n)
		if h:
			h.queue_free()
	for c in model.get_children():
		if c.has_meta("hand"):
			c.queue_free()
	pivot.add_child(model)
	_frame()


## 让暗器正好在画面中间
func _frame() -> void:
	var box := WeaponModels.side_box(weapon)
	var cz := box.position.x + box.size.x * 0.5
	var cy := box.position.y + box.size.y * 0.5
	model.position = Vector3(0, -cy, -cz)
	if side:
		var b := GunSkin.box2to1(box)
		cam.size = b.w - b.y
		model.position = Vector3(0, -(b.y + b.w) * 0.5, -(b.x + b.z) * 0.5)
		pivot.rotation = Vector3.ZERO
	else:
		var span := maxf(box.size.x, 0.25)
		cam.position = Vector3(0, 0, span * 1.2)
		cam.look_at(Vector3.ZERO)


func _process(dt: float) -> void:
	if side or not is_visible_in_tree():
		return
	_idle += dt
	if spin and not _drag and _idle > 1.5:
		_yaw += dt * 0.5
	pivot.rotation = Vector3(_pitch, _yaw, 0)


func _gui_input(e: InputEvent) -> void:
	if side:
		return
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_drag = (e as InputEventMouseButton).pressed
		_idle = 0.0
		accept_event()
	elif e is InputEventMouseMotion and _drag:
		var r := (e as InputEventMouseMotion).relative
		_yaw += r.x * 0.01
		_pitch = clampf(_pitch + r.y * 0.01, -1.2, 1.2)
		_idle = 0.0
		accept_event()
