extends SceneTree
## P25 screenshot capture: show off the real 3D models in-game.
##
## Run: xvfb-run -a godot --path <project> --resolution 1280x720 \
##        --script res://tests/capture_p25.gd -- <out_dir>

var _out_dir: String = "/tmp/p25_shots"
var _scene: Node
var _gecko: Node
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
	# P25: the rig's SpringArm3D boom repositions its camera every frame, so
	# staging uses a separate free camera instead of fighting the rig.
	var rig: Node3D = _scene.get_node("CameraRig")
	rig.set_process(false)
	rig.set_physics_process(false)
	rig.get_node("Boom/Camera3D").clear_current(false)
	_cam = Camera3D.new()
	_cam.fov = 60.0
	_scene.add_child(_cam)
	_cam.make_current()
	_gecko.set_physics_process(false)
	# Park the level's own hazards out of the way; we stage our own.
	for c in _scene.get_node("Level").get_children():
		if c is Area3D:
			c.set_physics_process(false)
			c.visible = false
			c.position = Vector3(100, 0, 100)
	# Dismiss the start screen: GameUI shows the HUD once the run starts.
	var auto_gs: Node = root.get_node_or_null("GameState")
	await _frames(3)
	if auto_gs != null:
		auto_gs.set("current_state", 1) # GameState.State.RUNNING
	await _frames(3)

	# 1: SPRINKLER — head popped, fan sweeping.
	var sp: Area3D = (load("res://scripts/systems/sprinkler.gd") as Script).new()
	_scene.add_child(sp)
	sp.position = Vector3(0, 0, -6)
	await _frames(5)
	sp._enter_phase(2) # ACTIVE
	await _frames(25)
	_place_gecko(Vector3(1.8, 0.55, -3.2))
	_frame_cam(Vector3(2.4, 1.3, -3.6), Vector3(0, 0.5, -6))
	await _shot("p25_sprinkler.png")
	sp.queue_free()

	# 2: BICYCLE — mid-crossing with rider, camera tracks it.
	var bi: Area3D = (load("res://scripts/systems/bicycle.gd") as Script).new()
	_scene.add_child(bi)
	bi.position = Vector3(0, 0, -8)
	await _frames(5)
	bi._enter_phase(2) # ACTIVE
	await _frames(18)
	_place_gecko(Vector3(bi.position.x - 2.0, 0.55, -5.6))
	var bp: Vector3 = bi.global_position
	_frame_cam(bp + Vector3(2.6, 1.5, 3.0), bp + Vector3(0, 0.9, 0))
	await _shot("p25_bicycle.png")
	bi.queue_free()

	# 3: CAR — backing up, reverse lights lit.
	var ca: Area3D = (load("res://scripts/systems/car.gd") as Script).new()
	_scene.add_child(ca)
	ca.position = Vector3(6, 0, -10)
	await _frames(5)
	ca._enter_phase(2) # ACTIVE: backing into the spot
	await _frames(35)
	_place_gecko(Vector3(1.4, 0.55, -7.2))
	var cp: Vector3 = ca.global_position
	_frame_cam(cp + Vector3(-3.4, 1.8, 3.4), cp + Vector3(0, 0.8, 0))
	await _shot("p25_car.png")
	ca.queue_free()

	# 4: BIRD — diving at the shadow. Gecko sidesteps for a near-miss.
	# Fixed side-view of the dive lane; few frames so we catch it mid-dive
	# even at capture-time fps.
	var bd: Area3D = (load("res://scripts/systems/bird.gd") as Script).new()
	_scene.add_child(bd)
	bd.position = Vector3(0, 0, -12)
	await _frames(5)
	_place_gecko(Vector3(0.4, 0.55, -12))
	bd._enter_phase(2) # ACTIVE: dive
	_place_gecko(Vector3(3.0, 0.55, -11.0)) # sidestep: near-miss, not a kill.
	_frame_cam(Vector3(4.6, 2.4, -8.2), Vector3(0.2, 1.4, -12))
	await _frames(5) # mid-dive
	await _shot("p25_bird.png")
	bd.queue_free()

	# 5: FENCE — the new picket finish gate (it stands at z=-358).
	_place_gecko(Vector3(-3.0, 0.55, -350))
	_frame_cam(Vector3(-7.5, 3.6, -349.5), Vector3(2.0, 2.4, -358))
	await _shot("p25_fence.png")

	# 6: PLANTER — raised bed with real plants.
	_place_gecko(Vector3(2.9, 0.55, -4.6))
	_frame_cam(Vector3(3.4, 1.4, -3.4), Vector3(1.5, 0.35, -6))
	await _shot("p25_planter.png")

	print("P25_SHOTS_DONE")
	quit(0)


func _place_gecko(pos: Vector3) -> void:
	_gecko.set("up_direction", Vector3.UP)
	_gecko.set("global_transform", Transform3D(Basis(), pos))
	_gecko.set("scale", Vector3.ONE)


func _frame_cam(pos: Vector3, target: Vector3) -> void:
	_cam.global_position = pos
	_cam.look_at(target, Vector3.UP)
	_cam.force_update_transform()


func _frames(n: int) -> void:
	for i in range(n):
		await physics_frame
		await process_frame


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	var path: String = _out_dir.path_join(name)
	img.save_png(path)
	print("saved ", path)
