extends SceneTree
## Gecko Run — P12 acceptance: bird telegraphs + dives; shield blocks one hit.

var failures: int = 0
var passes: int = 0


func check(cond: bool, label: String) -> void:
	if cond:
		passes += 1
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func wait_for_phase(bird: Area3D, want: int, timeout_s: float) -> bool:
	# Poll until the bird reaches the wanted phase (headless physics runs
	# slower than wall-clock, so fixed sleeps are flaky).
	var frames := int(timeout_s * 60.0) + 2
	for i in frames:
		await process_frame
		if int(bird.get("phase")) == want:
			return true
	return false


func _init() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		failures += 1
		print("FAIL: main.tscn failed to load")
		quit(1)
		return
	var main: Node = packed.instantiate()
	root.add_child(main)
	for i in 32:
		await process_frame

	var gecko: CharacterBody3D = main.get_node("Gecko")
	var bird: Area3D = main.get_node("Level/Bird")
	var pickup: Area3D = main.get_node("Level/ShieldPickup")
	check(gecko != null, "gecko present")
	check(bird != null, "bird present")
	check(pickup != null, "shield pickup present")
	gecko.run_speed = 0.0 # Freeze forward motion for a deterministic test.

	# --- Bird: park the gecko in its lane, wait out IDLE (2.5 s). ---
	var deaths_before: int = gecko.stat_deaths
	gecko.global_position = Vector3(0, 0, -11)
	check(await wait_for_phase(bird, 1, 12.0), "bird enters TELEGRAPH after IDLE")
	var shadow: MeshInstance3D = bird.get("_shadow")
	check(shadow != null and shadow.visible, "bird telegraph shadow is visible")

	# --- Bird: ACTIVE dive should kill an overlapping gecko. ---
	check(await wait_for_phase(bird, 2, 12.0), "bird reaches ACTIVE (dove)")
	# The kill check runs during ACTIVE; give it a beat.
	for i in 40:
		await process_frame
	check(gecko.stat_deaths > deaths_before, "bird dive kills the gecko on contact")

	# --- Shield: walk the (respawned) gecko into the pickup. ---
	for i in 70: # Let respawn finish.
		await process_frame
	gecko.global_position = Vector3(0, 0, -4)
	for i in 32:
		await process_frame
	check(gecko.shield_charges == 1, "shield pickup grants one charge")
	check(gecko.get("_shield_bubble").visible, "shield bubble is visible")

	# --- Shield: absorbs exactly one hit. ---
	var deaths_mid: int = gecko.stat_deaths
	gecko.die()
	check(gecko.shield_charges == 0, "shield charge consumed by the hit")
	check(gecko.stat_deaths == deaths_mid, "shielded gecko does NOT die")
	check(gecko.get("state") != 4, "gecko not in DEAD state after shielded hit")

	# --- Shield: expires after 10 s. ---
	gecko.give_shield()
	gecko.set("_shield_timer", 0.05)
	for i in 20:
		await process_frame
	check(gecko.shield_charges == 0, "shield expires after its timer")
	gecko.die()
	check(gecko.stat_deaths == deaths_mid + 1, "unshielded gecko dies normally")

	print("P12: %d passed, %d failed" % [passes, failures])
	quit(1 if failures > 0 else 0)
