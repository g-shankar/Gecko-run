extends SceneTree
## Hero screenshot capture: tight framing, one subject per shot.
##
## Run: xvfb-run -a godot --path <project> --resolution 1280x720 \
##        --script res://tests/capture_shots.gd -- /tmp/shots

var _out_dir: String = "/tmp/shots"
var _gecko: Node
var _scene: Node
var _cam: Camera3D


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(_out_dir)
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	_scene = packed.instantiate()
	root.add_child(_scene)
	_gecko = _scene.get_node("Gecko")
	var rig: Node3D = _scene.get_node("CameraRig")
	rig.set_process(false)
	_cam = rig.get_node("Boom/Camera3D")
	_cam.top_level = true
	_gecko.set_physics_process(false)
	_hide_all_hazards()
	# 1: THE RUN — low behind the gecko, world stretching ahead.
	_place_gecko(Vector3(0, 0.55, 3))
	_frame_cam(Vector3(0.8, 1.6, 6.2), Vector3(0, 0.7, 0))
	await _shot("shot_1_run.png")
	# 2: FOOTSTEP — the shadow blooms, the shoe hangs overhead.
	var fs: Area3D = _scene.get_node("Level/FootstepA")
	fs.visible = true
	fs.position = Vector3(0, 0, -6)
	fs.set_physics_process(true)
	_place_gecko(Vector3(1.8, 0.55, -3.2))
	fs._enter_phase(1) # Force TELEGRAPH; natural cycle is timing-flaky here.
	await _frames(30) # Shadow mid-grow, shoe still looming.
	_frame_cam(Vector3(3.6, 1.8, -1.2), Vector3(-0.5, 1.8, -6))
	await _shot("shot_2_footstep.png")
	# 3: WALL CLIMB — belly to the orange wall, high up.
	fs.set_physics_process(false)
	fs.visible = false
	_place_gecko(Vector3(0.3, 3.2, -19.55))
	_gecko.set("up_direction", Vector3(0, 0, 1))
	var b := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))
	_gecko.set("global_transform", Transform3D(b, Vector3(0.3, 3.2, -19.55)))
	_gecko.set("scale", Vector3.ONE)
	_frame_cam(Vector3(3.2, 3.4, -16.8), Vector3(0, 3.1, -20))
	await _shot("shot_3_wallclimb.png")
	print("SHOTS_DONE")
	quit(0)


func _place_gecko(pos: Vector3) -> void:
	_gecko.set("up_direction", Vector3.UP)
	_gecko.set("global_transform", Transform3D(Basis(), pos))
	_gecko.set("scale", Vector3.ONE)


func _frame_cam(pos: Vector3, target: Vector3) -> void:
	_cam.global_position = pos
	_cam.look_at(target, Vector3.UP)


func _hide_all_hazards() -> void:
	for hn in ["Level/FootstepA", "Level/FootstepB", "Level/Bicycle", "Level/BackingCar"]:
		var hz: Area3D = _scene.get_node(hn)
		hz.set_physics_process(false)
		hz.visible = false
		hz.position = Vector3(100, 0, 100)


func _frames(n: int) -> void:
	for i in range(n):
		await physics_frame
		await process_frame


func _until(cond: Callable, max_frames: int = 600) -> void:
	for i in range(max_frames):
		await physics_frame
		if cond.call():
			break


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	var path: String = _out_dir.path_join(name)
	img.save_png(path)
	print("saved ", path)
