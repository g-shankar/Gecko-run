extends SceneTree
## P6 headless acceptance test: the gecko runs into the climbable test wall,
## adheres, then CLIMBS (auto up the surface, steerable across it) while the
## camera banks so the wall reads as ground.
##
## Run: godot --headless --path <project> --script res://tests/test_p6.gd

var _gecko: Node
var _rig: Node
var _checks: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	# P14: the GameState autoload starts in READY (start screen). Tests
	# bypass it: wait a beat for it to load, then remove it so the gecko
	# runs immediately (gs==null means "just run").
	for _i in 10:
		await process_frame
		if root.has_node("GameState"):
			break
	var _gs: Node = root.get_node_or_null("GameState")
	if _gs != null:
		_gs.queue_free()
	_gecko = scene.get_node("Gecko")
	var level: Node3D = scene.get_node("Level")
	# Park every hazard: these suites test wall movement, not dodging.
	for hz in level.get("spawned"):
		(hz as Area3D).set_physics_process(false)
		(hz as Node3D).position = Vector3(100, 0, 100)
	# P21: the fence is the finish gate at the route's end — the gecko
	# starts just before it instead of running the whole route.
	var fence_z: float = float(level.get("level_data").get("fence_z"))
	_gecko.global_position = Vector3(0, 0.2, fence_z + 10.0)
	_rig = scene.get_node("CameraRig")
	# Wait for the wall run to start (adhesion from P5).
	var adhered := false
	for i in range(600):
		await physics_frame
		if _gecko.get("state") == 2: # ADHERE_WALL
			adhered = true
			break
	_check("gecko adhered to the wall", adhered)
	if not adhered:
		_finish()
		return
	# Climb check: a second of wall-running should gain ~4 m of height.
	var y0: float = _gecko.global_position.y
	for i in range(30):
		await physics_frame
	# Camera bank check (while safely mid-wall): the rig's smoothed up-vector
	# should have rolled toward the wall normal (0,0,1).
	var bank_up: Vector3 = _rig.get("_bank_up")
	_check("camera banked to the wall (up ~= wall normal)",
		bank_up.distance_to(Vector3(0.0, 0.0, 1.0)) < 0.25)
	print("  camera up: %s" % str(bank_up))
	for i in range(30):
		await physics_frame
	var climb: float = _gecko.global_position.y - y0
	_check("gecko climbs the wall (gained > 2.5 m in 1 s)", climb > 2.5)
	print("  climb measured: %.2f m" % climb)
	# Steering check: hold steer_right, the gecko should move across (+x).
	var x0: float = _gecko.global_position.x
	Input.action_press("steer_right")
	for i in range(45):
		await physics_frame
	Input.action_release("steer_right")
	var strafe: float = _gecko.global_position.x - x0
	_check("steering moves the gecko across the wall (dx > 0.5 m)", strafe > 0.5)
	print("  strafe measured: %.2f m" % strafe)
	_finish()


func _check(label: String, ok: bool) -> void:
	_checks.append([label, ok])


func _finish() -> void:
	var failed := 0
	for c in _checks:
		print(("PASS " if c[1] else "FAIL ") + c[0])
		if not c[1]:
			failed += 1
	print("P6_RESULT: %d/%d passed" % [_checks.size() - failed, _checks.size()])
	quit(1 if failed > 0 else 0)
