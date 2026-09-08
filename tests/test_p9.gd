extends SceneTree
## P9 headless acceptance test: HazardBase cycles
## IDLE -> TELEGRAPH -> ACTIVE -> RECOVERY -> IDLE with the configured
## timings, and one_shot stops after one cycle.
##
## Run: godot --headless --path <project> --script res://tests/test_p9.gd

const HazardBaseScript := preload("res://scripts/systems/hazard_base.gd")

var _checks: Array = []
var _phases: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# Build a bare HazardBase (no visuals needed for the machine test).
	var hz: Area3D = Area3D.new()
	hz.set_script(HazardBaseScript)
	hz.idle_time = 0.2
	hz.warn_time = 0.2
	hz.active_time = 0.2
	hz.recovery_time = 0.2
	hz.one_shot = false
	root.add_child(hz)
	hz.phase_changed.connect(func(p: int) -> void: _phases.append(p))
	await physics_frame # _ready runs, enters IDLE.
	_check("starts in IDLE", hz.phase == 0)
	# One full loop = 0.8 s = 48 physics frames. Give it 60.
	for i in range(60):
		await physics_frame
	# Expect: IDLE(0) -> TELEGRAPH(1) -> ACTIVE(2) -> RECOVERY(3) -> IDLE(0).
	var seq: Array = []
	for p in _phases:
		if seq.is_empty() or seq[seq.size() - 1] != p:
			seq.append(p)
	_check("cycles IDLE->TELEGRAPH->ACTIVE->RECOVERY->IDLE",
		seq == [1, 2, 3, 0] or seq == [1, 2, 3, 0, 1])
	print("  phase sequence: %s" % str(seq))
	hz.queue_free()
	# One-shot: should stop after RECOVERY.
	var hz2: Area3D = Area3D.new()
	hz2.set_script(HazardBaseScript)
	hz2.idle_time = 0.1
	hz2.warn_time = 0.1
	hz2.active_time = 0.1
	hz2.recovery_time = 0.1
	hz2.one_shot = true
	root.add_child(hz2)
	var phases2: Array = []
	hz2.phase_changed.connect(func(p: int) -> void: phases2.append(p))
	for i in range(60):
		await physics_frame
	_check("one_shot stops after RECOVERY", hz2.get("_finished") == true)
	_check("one_shot saw all four phases", phases2 == [1, 2, 3])
	print("  one-shot phases: %s" % str(phases2))
	_finish()


func _check(label: String, ok: bool) -> void:
	_checks.append([label, ok])


func _finish() -> void:
	var failed := 0
	for c in _checks:
		print(("PASS " if c[1] else "FAIL ") + c[0])
		if not c[1]:
			failed += 1
	print("P9_RESULT: %d/%d passed" % [_checks.size() - failed, _checks.size()])
	quit(1 if failed > 0 else 0)
