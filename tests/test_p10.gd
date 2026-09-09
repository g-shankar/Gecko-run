extends SceneTree
## P10 headless acceptance test: the footstep telegraphs (shadow), its ACTIVE
## phase kills a gecko in the zone, and the gecko respawns in under a second.
##
## Run: godot --headless --path <project> --script res://tests/test_p10.gd

var _gecko: Node
var _checks: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	_gecko = scene.get_node("Gecko")
	var hz: Area3D = scene.get_node("Level/FootstepA")
	# Telegraph: the shadow should appear during the warn phase.
	var telegraphed := false
	for i in range(300):
		await physics_frame
		if hz.phase == 1: # TELEGRAPH
			telegraphed = true
			break
	_check("footstep telegraphs (enters TELEGRAPH)", telegraphed)
	_check("telegraph shadow is visible", hz.get("_shadow").visible == true)
	# Force the slam with the gecko in the zone: it should die.
	hz._enter_phase(2) # ACTIVE
	_gecko.global_position = Vector3(hz.position.x, 0.2, hz.position.z)
	hz._check_overlaps()
	for i in range(10):
		await physics_frame
	_check("gecko dies in the stomp (state == DEAD)", _gecko.get("state") == 6)
	# Respawn: under a second, back at the start, death counted.
	var respawned := false
	for i in range(90):
		await physics_frame
		if _gecko.get("state") == 0: # RUN
			respawned = true
			break
	_check("gecko respawns in under a second", respawned)
	_check("death counted (stat_deaths == 1)", _gecko.get("stat_deaths") == 1)
	_check("gecko back at spawn", _gecko.global_position.distance_to(Vector3(0, 0.2, 6)) < 1.0)
	_finish()


func _check(label: String, ok: bool) -> void:
	_checks.append([label, ok])


func _finish() -> void:
	var failed := 0
	for c in _checks:
		print(("PASS " if c[1] else "FAIL ") + c[0])
		if not c[1]:
			failed += 1
	print("P10_RESULT: %d/%d passed" % [_checks.size() - failed, _checks.size()])
	quit(1 if failed > 0 else 0)
