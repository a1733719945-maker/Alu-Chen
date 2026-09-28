class_name SelfPreview
extends SubViewportContainer
## 自己的 3D 人物预览（灵相面板左上角，站在灵相立绘前面）。用户："人模型你弄得更好了吗，我单机目前看不到"——
## 单机是第一人称，看不到自己；队友看到的就是这个模型（RemotePlayer，穿着自己的装扮、拿着手里的暗器）。
## 慢慢转；鼠标按住拖动可以自己转着看。

var vp: SubViewport
var cam: Camera3D
var mate: RemotePlayer
var world: Node
var _yaw := 0.4
var _drag := false
var _idle := 0.0


func _init(p_world: Node, p_size := Vector2i(300, 280)) -> void:
	world = p_world
	stretch = true
	custom_minimum_size = Vector2(p_size)
	mouse_filter = Control.MOUSE_FILTER_STOP
	vp = SubViewport.new()
	vp.size = Vector2i(16, 16)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(vp)
	var we := WorldEnvironment.new()
	we.environment = GunPreview._env()
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-35), deg_to_rad(30), 0)
	key.light_energy = 1.5
	key.light_color = Color(1.0, 0.95, 0.88)
	key.shadow_enabled = false
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation = Vector3(deg_to_rad(-15), deg_to_rad(200), 0)
	rim.light_energy = 1.3
	rim.light_color = Color(1.0, 0.8, 0.55)
	vp.add_child(rim)
	cam = Camera3D.new()
	cam.fov = 32.0
	var cp := Vector3(0, 1.15, 4.6)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, 1.0, 0) - cp, Vector3.UP), cp)
	vp.add_child(cam)
	mate = RemotePlayer.new()
	mate.setup(world, -1, world._my_info())
	vp.add_child(mate)
	mate.label.visible = false


func _process(dt: float) -> void:
	if not is_visible_in_tree() or not is_instance_valid(mate):
		return
	_idle += dt
	if not _drag and _idle > 1.5:
		_yaw += dt * 0.45
	var gid: String = world.player.gun.id if world.player and world.player.gun else "fist"
	# 喂一个原地站着的"网络快照"：RemotePlayer 就按平时的样子摆姿势（呼吸、衣摆、拿着暗器）
	mate.push_snapshot([Vector3.ZERO, _yaw, 0.0, gid, 1, 0, Vector3.ZERO, 1.0, 1.0])


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_drag = (e as InputEventMouseButton).pressed
		_idle = 0.0
		accept_event()
	elif e is InputEventMouseMotion and _drag:
		_yaw += (e as InputEventMouseMotion).relative.x * 0.01
		accept_event()
