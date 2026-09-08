extends SceneTree
## P5 headless acceptance test: the gecko auto-runs straight down the track
## into the tinted climbable test wall. Acceptance: it ADHEREs (sticks) with
## its up-axis aligned to the wall normal, instead of stopping dead.
##
## Run: godot --headless --path <project> --script res://tests/test_p5.gd
## Exit code 0 = all checks passed.

var _gecko: Node
var _checks: Array = []


func _init() -> void:
	# The tree isn't fully ready inside _init; defer the real work.
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	_gecko = scene.get_node("Gecko")
	# Park every hazard: these suites test wall movement, not dodging.
	for hn in ["FootstepA", "FootstepB", "Bicycle", "BackingCar"]:
		var hz: Area3D = scene.get_node(hn)
		hz.set_physics_process(false)
		hz.position = Vector3(100, 0, 100)
	# Let _ready() hooks run and the physics settle. The gecko spawns a hair
	# above the ground, so give it up to a second to land and enter RUN.
	var settled := false
	for i in range(60):
		await physics_frame
		if _gecko.get("state") == 0:
			settled = true
			break
	_check("starts on ground in RUN", settled)
	# Run until the wall grab happens (P6 climbs afterward, so capture the
	# attach moment itself, not the end of the run).
	var attached := false
	for i in range(600):
		await physics_frame
		if _gecko.get("state") == 2: # ADHERE_WALL
			attached = true
			break
	_check("adhered to wall (state == ADHERE_WALL)", attached)
	_report()


func _report() -> void:
	var state: int = _gecko.get("state")
	var up: Vector3 = _gecko.get("up_direction")
	var n: Vector3 = _gecko.get("wall_normal")
	var basis_y: Vector3 = _gecko.global_transform.basis.y
	var pos: Vector3 = _gecko.global_position
	# Enum order: RUN=0, AIR=1, ADHERE_WALL=2.
	_check("up_direction is the wall normal (0,0,1)",
			up.distance_to(Vector3(0.0, 0.0, 1.0)) < 0.05)
	_check("wall_normal recorded", n.distance_to(Vector3(0.0, 0.0, 1.0)) < 0.05)
	_check("capsule reoriented upright on wall (basis.y ~= 0,0,1)",
			basis_y.distance_to(Vector3(0.0, 0.0, 1.0)) < 0.05)
	_check("gecko parked at the wall face (z < -18)", pos.z < -18.0)
	_check("gecko did not tunnel through (z > -20.5)", pos.z > -20.5)
	# NOTE: "still glued at end of run" is P6's territory now — the gecko
	# climbs after attaching, so end-of-run state is covered by test_p6.
	var failed := 0
	for c in _checks:
		print(("PASS " if c[1] else "FAIL ") + c[0])
		if not c[1]:
			failed += 1
	print("P5_RESULT: %d/%d passed" % [_checks.size() - failed, _checks.size()])
	quit(1 if failed > 0 else 0)


func _check(label: String, ok: bool) -> void:
	_checks.append([label, ok])
