extends SceneTree
## P8 headless acceptance test: Shift triggers a dash burst (12 m/s), the
## camera FOV kicks, and the cooldown blocks spam.
##
## Run: godot --headless --path <project> --script res://tests/test_p8.gd

var _gecko: Node
var _camera: Camera3D
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
	_camera = scene.get_node("CameraRig/Boom/Camera3D") as Camera3D
	# Settle into RUN.
	var running := false
	for i in range(60):
		await physics_frame
		if _gecko.get("state") == 0:
			running = true
			break
	_check("gecko running before dash", running)
	if not running:
		_finish()
		return
	# Dash via the real input path.
	Input.action_press("dash")
	await physics_frame
	Input.action_release("dash")
	await physics_frame
	_check("dash triggers (state == DASH)", _gecko.get("state") == 4)
	var vel: Vector3 = _gecko.get("velocity")
	var dash_speed: float = Vector2(vel.x, vel.z).length()
	_check("dash hits ~12 m/s", dash_speed > 10.0)
	print("  dash speed: %.1f m/s" % dash_speed)
	# FOV kick: let the camera ease, then read it mid-dash.
	# P28.5: macro base FOV is 50 (was 70) — assert relative to the rig's
	# base_fov so the kick itself is what's verified, not the old number.
	var _rig: Node = scene.get_node("CameraRig")
	var _base_fov: float = float(_rig.get("base_fov"))
	for i in range(6):
		await process_frame
	_check("FOV kicks up (fov > base+5)", _camera.fov > _base_fov + 5.0)
	print("  fov mid-dash: %.1f" % _camera.fov)
	# Let the dash end; spam should be blocked by the cooldown.
	for i in range(30):
		await physics_frame
	Input.action_press("dash")
	await physics_frame
	Input.action_release("dash")
	await physics_frame
	_check("cooldown blocks immediate re-dash (state != DASH)", _gecko.get("state") != 4)
	# FOV should relax back toward base_fov after the dash.
	for i in range(60):
		await process_frame
	_check("FOV relaxes after dash (fov < base+5)", _camera.fov < _base_fov + 5.0)
	print("  fov after: %.1f" % _camera.fov)
	_finish()


func _check(label: String, ok: bool) -> void:
	_checks.append([label, ok])


func _finish() -> void:
	var failed := 0
	for c in _checks:
		print(("PASS " if c[1] else "FAIL ") + c[0])
		if not c[1]:
			failed += 1
	print("P8_RESULT: %d/%d passed" % [_checks.size() - failed, _checks.size()])
	quit(1 if failed > 0 else 0)
