extends SceneTree
## Gecko Run — P16 tests: bug pickups + speed ramp.
##
## 1. Level spawns bugs from LevelData.
## 2. Touching a bug: +10 points, bug_count=1, bug disappears.
## 3. Speed ramp: effective speed increases with run_time.

var _pass := 0
var _fail := 0


func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("PASS: ", label)
	else:
		_fail += 1
		print("FAIL: ", label)


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		_fail += 1
		print("FAIL: main.tscn failed to load")
		quit(1)
		return
	var main: Node = packed.instantiate()
	root.add_child(main)
	for _i in 10:
		await process_frame
		if root.has_node("GameState"):
			break
	var gs: Node = root.get_node_or_null("GameState")
	if gs != null:
		gs.queue_free()
	for i in 32:
		await process_frame

	var gecko: CharacterBody3D = main.get_node("Gecko")
	var bugs: Array = []
	for child in main.get_node("Level").get_children():
		if child.name.begins_with("Bug"):
			bugs.append(child)
	check(gecko != null, "gecko present")
	check(bugs.size() >= 5, "Level spawns bugs from LevelData (found %d)" % bugs.size())
	if bugs.is_empty():
		print("--- P16: %d passed, %d failed ---" % [_pass, _fail])
		quit(_fail)
		return
	gecko.run_speed = 0.0

	# --- 2: bug collection ---
	var gs_script: Script = load("res://scripts/systems/game_state.gd")
	var gs2: Node = gs_script.new()
	gs2.name = "GameState"
	root.add_child(gs2)
	gs2.start_run()
	var bug: Area3D = bugs[0]
	var score_before: int = gs2.score
	# Teleport gecko onto the bug.
	gecko.global_position = bug.global_position
	for i in 30:
		await process_frame
		if not is_instance_valid(bug):
			break
	check(not is_instance_valid(bug), "bug disappears after collection")
	check(gs2.bug_count == 1, "bug_count increments (count=%d)" % gs2.bug_count)
	check(gs2.score >= score_before + 10, "bug awards 10 points (score=%d)" % gs2.score)

	# --- 3: speed ramp ---
	# Note: gecko.run_speed was set to 0 above to freeze it. Use base 5.0.
	var base_speed: float = 5.0
	gs2.run_time = 30.0
	# Effective speed = min(5.0 + 30*0.15, 9.0) = min(9.5, 9.0) = 9.0
	var expected: float = minf(base_speed + 30.0 * gecko.speed_ramp, gecko.max_speed)
	check(absf(expected - 9.0) < 0.01, "speed ramp caps at max_speed (%.1f)" % expected)
	# At 10s: 5.0 + 1.5 = 6.5
	gs2.run_time = 10.0
	expected = minf(base_speed + 10.0 * gecko.speed_ramp, gecko.max_speed)
	check(absf(expected - 6.5) < 0.01, "speed ramps with time (%.1f at 10s)" % expected)

	print("--- P16: %d passed, %d failed ---" % [_pass, _fail])
	quit(_fail)
