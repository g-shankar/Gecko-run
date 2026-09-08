extends SceneTree
## P7 headless acceptance test: while adhered, Space kicks the gecko off the
## wall (away + up into AIR), it arcs, lands upright, and resumes RUN.
##
## Run: godot --headless --path <project> --script res://tests/test_p7.gd

var _gecko: Node
var _checks: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	_gecko = scene.get_node("Gecko")
	# Ride the wall up a little first (P6).
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
	for i in range(30):
		await physics_frame
	# Kick off the wall via the real input path.
	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	await physics_frame
	var state: int = _gecko.get("state")
	var vel: Vector3 = _gecko.get("velocity")
	_check("wall kick leaves the wall (state == AIR)", state == 1)
	# Wall normal is (0,0,1): push = +Z, up along wall = +Y.
	_check("kick shoves away from the wall (vz > 2)", vel.z > 2.0)
	_check("kick boosts upward (vy > 2)", vel.y > 2.0)
	print("  kick velocity: %s" % str(vel))
	# It should arc, land upright, and resume running.
	var landed := false
	for i in range(240):
		await physics_frame
		if _gecko.get("state") == 0: # RUN
			landed = true
			break
	_check("gecko lands and resumes RUN", landed)
	var basis_y: Vector3 = _gecko.global_transform.basis.y
	_check("gecko upright after landing (basis.y ~= 0,1,0)",
		basis_y.distance_to(Vector3.UP) < 0.1)
	_finish()


func _check(label: String, ok: bool) -> void:
	_checks.append([label, ok])


func _finish() -> void:
	var failed := 0
	for c in _checks:
		print(("PASS " if c[1] else "FAIL ") + c[0])
		if not c[1]:
			failed += 1
	print("P7_RESULT: %d/%d passed" % [_checks.size() - failed, _checks.size()])
	quit(1 if failed > 0 else 0)
