extends SceneTree
## Gecko Run — P13 acceptance: level built from data; death -> restart < 2 s.

var failures: int = 0
var passes: int = 0


func check(cond: bool, label: String) -> void:
	if cond:
		passes += 1
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _init() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		failures += 1
		print("FAIL: main.tscn failed to load")
		quit(1)
		return
	var main: Node = packed.instantiate()
	root.add_child(main)
	# Freeze the gecko early: it must not collect bugs before we verify spawns.
	var _gecko_early: CharacterBody3D = main.get_node("Gecko")
	_gecko_early.run_speed = 0.0
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
	for i in 32:
		await process_frame

	var level: Node3D = main.get_node("Level")
	check(level != null, "Level node present")
	var data: Resource = level.get("level_data")
	check(data != null, "LevelData present (the route is data, not scene)")

	# Every spawn in the data got built, at the right spot.
	var spawned: Array = level.get("spawned")
	check(spawned.size() == (data.get("spawns") as Array).size(),
		"all %d spawns built" % (data.get("spawns") as Array).size())
	for spawn in (data.get("spawns") as Array):
		var want: Vector3 = spawn["pos"]
		var found := false
		for h in spawned:
			var hp: Vector3 = (h as Node3D).position
			if hp.distance_to(want) < 0.05:
				found = true
			elif (h as Node).name.begins_with("Bicycle") and absf(hp.z - want.z) < 0.05:
				found = true # The bicycle crosses in x; its lane (z) is what matters.
			elif (h as Node).name.begins_with("BackingCar") and absf(hp.z - want.z) < 0.05:
				found = true # The car backs up in x; its lane (z) is what matters.
			elif (h as Node).name.begins_with("Mower") and absf(hp.z - want.z) < 0.05:
				found = true # P28: the mower crosses in x; its lane (z) is what matters.
			elif (h as Node).name.begins_with("Bug"):
				# Bugs bob in Y; check XZ only.
				var dx: float = hp.x - want.x
				var dz: float = hp.z - want.z
				if sqrt(dx * dx + dz * dz) < 0.05:
					found = true
		check(found, "hazard at %s" % str(want))

	# Route order: spawns march forward (decreasing z) — a legible run.
	var zs: Array = []
	for spawn in (data.get("spawns") as Array):
		zs.append((spawn["pos"] as Vector3).z)
	var ordered := true
	for i in range(1, zs.size()):
		if zs[i] > zs[i - 1]:
			ordered = false
	check(ordered, "route runs start -> fence without backtracking")

	check(level.get_node("StartLine") != null, "start line visual built")
	var fence: Node = main.get_node("Fence")
	check(fence != null and fence.is_in_group("climbable"),
		"fence stands at the end and is climbable")

	# Death -> restart: the design bound is under 2 s.
	var gecko: CharacterBody3D = main.get_node("Gecko")
	gecko.run_speed = 0.0
	gecko.die()
	var delay: float = gecko.get("_respawn_timer")
	check(delay > 0.0 and delay < 2.0,
		"respawn delay is %.2f s (< 2 s)" % delay)
	var respawned := false
	for i in int(6.0 * 60.0):
		await process_frame
		if int(gecko.get("state")) != 6: # 6 == MoveState.DEAD
			respawned = true
			break
	check(respawned, "gecko actually respawns after death")

	print("P13_RESULT: %d/%d passed" % [passes, passes + failures])
	quit(1 if failures > 0 else 0)
