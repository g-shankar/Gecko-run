extends SceneTree
## Gecko Run — P15 tests: sprinkler hazard + near-miss rewards.
##
## 1. Level spawns a Sprinkler from LevelData.
## 2. Sprinkler cycles IDLE->TELEGRAPH->ACTIVE->RECOVERY.
## 3. Sprinkler head pops up during TELEGRAPH.
## 4. Near-miss: gecko close during ACTIVE but survives = +50, count=1.
## 5. No near-miss if the gecko dies during ACTIVE.

var _pass := 0
var _fail := 0


func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("PASS: ", label)
	else:
		_fail += 1
		print("FAIL: ", label)


func wait_for_phase(hazard: Area3D, phase: int, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		await process_frame
		t += 1.0 / 60.0
		if hazard.phase == phase:
			return true
	return false


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		_fail += 1
		print("FAIL: main.tscn failed to load")
		quit(1)
		return
	var main: Node = packed.instantiate()
	root.add_child(main)
	# Bypass P14's READY state like other tests.
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
	var sprinkler: Area3D = null
	for child in main.get_node("Level").get_children():
		if child.name.begins_with("Sprinkler"):
			sprinkler = child
			break
	check(gecko != null, "gecko present")
	check(sprinkler != null, "Level spawns a Sprinkler from LevelData")
	if sprinkler == null:
		print("--- P15: %d passed, %d failed ---" % [_pass, _fail])
		quit(_fail)
		return
	gecko.run_speed = 0.0 # Freeze for deterministic test.

	# Speed up the cycle for the test.
	sprinkler.idle_time = 0.2
	sprinkler.warn_time = 0.3
	sprinkler.active_time = 0.3
	sprinkler.recovery_time = 0.2

	# --- 2: lifecycle ---
	check(await wait_for_phase(sprinkler, 1, 5.0), "sprinkler enters TELEGRAPH")
	check(await wait_for_phase(sprinkler, 2, 5.0), "sprinkler enters ACTIVE")
	check(await wait_for_phase(sprinkler, 3, 5.0), "sprinkler enters RECOVERY")

	# --- 3: head pops up ---
	# Wait for next TELEGRAPH, then let the pop-up animate.
	check(await wait_for_phase(sprinkler, 1, 5.0), "sprinkler re-enters TELEGRAPH")
	for i in 20: # ~0.33s into the 0.3s telegraph (clamped by phase).
		await process_frame
		if sprinkler.phase != 1:
			break
	var head: MeshInstance3D = sprinkler.get("_head")
	check(head != null and head.position.y > 0.2, "sprinkler head pops up during TELEGRAPH")

	# --- 4: near-miss ---
	# We need a real GameState for scoring. Create one.
	var gs_script: Script = load("res://scripts/systems/game_state.gd")
	var gs2: Node = gs_script.new()
	gs2.name = "GameState"
	root.add_child(gs2)
	gs2.start_run()
	# Reconnect the sprinkler's near_miss to the new GameState.
	# (The original connected to the freed one.)
	if not sprinkler.near_miss.is_connected(gs2.register_near_miss):
		sprinkler.near_miss.connect(gs2.register_near_miss)
	# Park gecko within near-miss range (2.5m) but outside the hit zone.
	# Sprinkler at (-1.5, 0, -8), fan extends -Z with a 70-degree sweep: the
	# kill box spans x -4.1..1.1, z -12.3..-7.7. Two meters behind it (-6.0)
	# is close (2.0m) but clear of the fan — and clear of the footstep at
	# (0, 0, -6), whose shoe only spans x +-0.8.
	# (P22: the old spot (0,0,-8) was INSIDE the fan; the near-miss only
	# counted because the old die() never set GameState to DEAD.)
	gecko.global_position = Vector3(-1.5, 0, -6.0)
	var score_before: int = gs2.score
	# Wait for ACTIVE to complete (RECOVERY means ACTIVE just ended).
	check(await wait_for_phase(sprinkler, 2, 5.0), "sprinkler ACTIVE for near-miss test")
	check(await wait_for_phase(sprinkler, 3, 5.0), "sprinkler RECOVERY after ACTIVE")
	await process_frame
	await process_frame
	check(gs2.near_miss_count == 1, "near-miss counted (count=%d)" % gs2.near_miss_count)
	# Score = 50 (near-miss) + distance traveled. At least 50 from the bonus.
	check(gs2.score >= score_before + 50, "near-miss awards 50 points (score=%d)" % gs2.score)

	print("--- P15: %d passed, %d failed ---" % [_pass, _fail])
	quit(_fail)
