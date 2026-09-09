extends SceneTree
## Gecko Run — P19 tests: speed boost power-up.
##
## 1. Level spawns a SpeedPickup from LevelData.
## 2. give_speed_boost(): timer set, multiplier 1.5, trail shows.
## 3. Boosted gecko covers ~1.5x distance (multiplier applies to motion).
## 4. Timer expiry returns multiplier to 1.0 and hides the trail.
## 5. Touching the pickup grants the boost.
## 6. Camera FOV kicks up while boosted.
## 7. HUD SPEED! indicator follows the boost.

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
	# P13 pattern: drop the autoload so the gecko runs without READY gating.
	var auto: Node = root.get_node_or_null("GameState")
	if auto != null:
		auto.queue_free()
	for i in 32:
		await process_frame

	var level: Node3D = main.get_node("Level")
	var gecko: CharacterBody3D = main.get_node("Gecko")
	var rig: Node3D = main.get_node("CameraRig")
	var ui: CanvasLayer = main.get_node("GameUI")
	gecko.set("run_speed", 5.0)

	# --- 1: pickup spawns ---
	var pickup: Node3D = null
	for h in (level.get("spawned") as Array):
		if (h as Node).name.begins_with("SpeedPickup"):
			pickup = h
	check(pickup != null, "Level spawns a SpeedPickup from LevelData")

	# --- 2: grant ---
	gecko.call("give_speed_boost")
	check(float(gecko.get("_speed_boost_timer")) > 0.0, "boost timer set")
	check(absf(float(gecko.call("boost_multiplier")) - 1.5) < 0.01,
		"multiplier is 1.5 while boosted")
	check(bool((gecko.get("_speed_trail") as MeshInstance3D).visible),
		"speed trail shows during boost")

	# --- 3: multiplier applies to motion (40 safe frames, no hazards near start) ---
	var z0: float = gecko.global_position.z
	for i in 40:
		await process_frame
	var boosted_dist: float = z0 - gecko.global_position.z
	# Reset and run unboosted over the same window.
	gecko.set("_speed_boost_timer", 0.0)
	gecko.global_position = Vector3(0, 0.2, 6)
	gecko.set("velocity", Vector3.ZERO)
	z0 = gecko.global_position.z
	for i in 40:
		await process_frame
	var plain_dist: float = z0 - gecko.global_position.z
	var ratio: float = boosted_dist / maxf(plain_dist, 0.01)
	check(ratio > 1.35 and ratio < 1.65,
		"boosted distance ~1.5x plain (ratio=%.2f)" % ratio)

	# --- 4: expiry (physics frames: the timer ticks on physics delta) ---
	gecko.call("give_speed_boost")
	gecko.set("_speed_boost_timer", 0.05)
	for i in 10:
		await physics_frame
	check(absf(float(gecko.call("boost_multiplier")) - 1.0) < 0.01,
		"multiplier back to 1.0 after expiry")
	check(not bool((gecko.get("_speed_trail") as MeshInstance3D).visible),
		"speed trail hides after expiry")

	# --- 5: touching the pickup grants the boost ---
	gecko.set("_speed_boost_timer", 0.0)
	gecko.global_position = pickup.global_position
	gecko.set("velocity", Vector3.ZERO)
	for i in 10:
		await process_frame
	check(float(gecko.get("_speed_boost_timer")) > 0.0,
		"pickup touch grants the boost")

	# --- 6: camera FOV kick ---
	gecko.set("run_speed", 0.0) # stay clear of hazards while we watch the FOV
	gecko.global_position = Vector3(0, 0.2, 6)
	gecko.set("velocity", Vector3.ZERO)
	gecko.call("give_speed_boost")
	for i in 90:
		await process_frame
	var cam: Camera3D = rig.get_node("Boom/Camera3D")
	# P28.5: macro base FOV is 50 (was 70) — assert the kick relative to it.
	check(cam.fov > float(rig.get("base_fov")) + 4.0,
		"camera FOV kicks up on boost (fov=%.1f)" % cam.fov)

	# --- 7: HUD indicator ---
	var speed_label: Label = ui.get("_speed_label")
	check(speed_label != null, "HUD SPEED! label exists") ## P27: now "⚡ SPEED!".
	if speed_label != null:
		check(speed_label.visible, "SPEED! shows while boosted")
		gecko.set("_speed_boost_timer", 0.05)
		for i in 10:
			await physics_frame
		check(not speed_label.visible, "SPEED! hides after expiry")

	print("--- P19: %d passed, %d failed ---" % [_pass, _fail])
	quit(_fail)
