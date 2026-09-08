extends SceneTree
## P11 headless acceptance test: the bicycle crosses on rhythm and kills on
## contact; the backing car telegraphs, parks across the track (one-shot),
## and stays dangerous.
##
## Run: godot --headless --path <project> --script res://tests/test_p11.gd

var _gecko: Node
var _checks: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	_gecko = scene.get_node("Gecko")
	# Park the footsteps out of the way: this test is about bike + car.
	for fn in ["FootstepA", "FootstepB"]:
		var fs: Area3D = scene.get_node(fn)
		fs.set_physics_process(false)
		fs.position.x = 100.0
	var bike: Area3D = scene.get_node("Bicycle")
	var car: Area3D = scene.get_node("BackingCar")
	# Bicycle: wait for the crossing, verify it sweeps the track.
	var crossed := false
	var x_start: float = 0.0
	for i in range(600):
		await physics_frame
		if bike.phase == 2: # ACTIVE
			x_start = bike.position.x
			for j in range(70):
				await physics_frame
			var x_end: float = bike.position.x
			crossed = absf(x_end - x_start) > 6.0
			break
	_check("bicycle crosses the track during ACTIVE", crossed)
	# Bicycle kill: freeze it mid-crossing, put the gecko on it.
	bike._enter_phase(2)
	bike.set_physics_process(false)
	bike.position.x = 0.0
	_gecko.global_position = Vector3(0, 0.2, -9)
	await physics_frame # Let the physics server register the overlap.
	bike._check_overlaps()
	for i in range(10):
		await physics_frame
	_check("bicycle kills on contact (state == DEAD)", _gecko.get("state") == 6)
	bike.set_physics_process(true)
	_await_respawn()
	# Car: one-shot cycle ends parked and finished.
	var parked := false
	for i in range(600):
		await physics_frame
		if car.get("_finished"):
			parked = absf(car.position.x - -0.5) < 0.3
			break
	_check("car backs into the track and stops (one-shot)", parked)
	_check("car telegraphed (reverse lights flared)",
		car.get("_light_mat").emission_energy_multiplier > 0.1)
	# Parked car still kills (hits_always).
	_gecko.global_position = Vector3(car.position.x, 0.2, -17)
	for i in range(10):
		await physics_frame
	_check("parked car still kills on touch", _gecko.get("state") == 6)
	_finish()


func _await_respawn() -> void:
	for i in range(90):
		await physics_frame
		if _gecko.get("state") == 0:
			break


func _check(label: String, ok: bool) -> void:
	_checks.append([label, ok])


func _finish() -> void:
	var failed := 0
	for c in _checks:
		print(("PASS " if c[1] else "FAIL ") + c[0])
		if not c[1]:
			failed += 1
	print("P11_RESULT: %d/%d passed" % [_checks.size() - failed, _checks.size()])
	quit(1 if failed > 0 else 0)
