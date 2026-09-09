extends SceneTree
## Gecko Run — P22 tests: game-feel polish.
##
## 1. The camera rig has a trauma system (add_trauma, decay).
## 2. Death shakes the camera (trauma > 0 after die()).
## 3. Near-miss shakes it less (0.35 < death's 1.0).
## 4. Deaths route through register_death() (combo breaks — the P22 fix).
## 5. Jump stretches the visual; it eases back to normal.
## 6. Landing squashes the visual (caught mid-tween).
## 7. Bug collection fires a particle burst.
## 8. Near-miss fires a particle burst.
## 9. Squash targets the visual only — the hitbox never scales.

var _pass := 0
var _fail := 0


func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("PASS: ", label)
	else:
		_fail += 1
		print("FAIL: ", label)


func _bursts() -> Array:
	var out: Array = []
	for c in root.get_children():
		if c is CPUParticles3D:
			out.append(c)
	return out


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		_fail += 1
		print("FAIL: main.tscn failed to load")
		quit(1)
		return
	var main: Node = packed.instantiate()
	root.add_child(main)
	# P18 pattern: manual GameState so _process runs and signals work.
	var auto: Node = root.get_node_or_null("GameState")
	if auto != null:
		auto.queue_free()
	await process_frame
	var gs: Node = load("res://scripts/systems/game_state.gd").new()
	gs.name = "GameState"
	root.add_child(gs)
	await process_frame

	var gecko: CharacterBody3D = main.get_node("Gecko")
	var rig: Node3D = main.get_node("CameraRig")
	var visual: MeshInstance3D = gecko.get_node("MeshInstance3D")
	gecko.set("run_speed", 0.0)
	gs.call("start_run") # RUNNING: missions tick, deaths respawn.

	# --- 1: trauma system exists and decays ---
	check(rig.has_method("add_trauma"), "CameraRig has add_trauma()")
	rig.call("add_trauma", 1.0)
	check(absf(float(rig.get("_trauma")) - 1.0) < 0.01, "trauma hits 1.0")
	for i in 30:
		await process_frame
	check(float(rig.get("_trauma")) < 1.0, "trauma decays over time")

	# --- 2: death shakes ---
	rig.set("_trauma", 0.0)
	gecko.call("die")
	check(float(rig.get("_trauma")) > 0.5, "death kicks trauma (%.2f)" % float(rig.get("_trauma")))

	# --- 4: death breaks the combo (the P22 register_death fix) ---
	gs.set("combo", 5)
	# Respawn first (die() early-outs while DEAD). Physics frames: the
	# respawn countdown runs on physics delta (0.8 s = 48 ticks).
	for i in 90:
		await physics_frame
		if int(gecko.get("state")) == 0:
			break
	gecko.call("die")
	check(int(gs.get("combo")) == 0, "death resets the combo via register_death()")
	for i in 90:
		await physics_frame
		if int(gecko.get("state")) == 0:
			break

	# --- 3: near-miss shakes less ---
	rig.set("_trauma", 0.0)
	gs.call("register_near_miss")
	var nm_trauma: float = float(rig.get("_trauma"))
	check(nm_trauma > 0.2 and nm_trauma < 0.5,
		"near-miss trauma is small (%.2f)" % nm_trauma)

	# --- 5: jump stretches, then eases back ---
	# P23: the hero is rotated 90° about Y — local Y is up, so the takeoff
	# stretch (height 1.3) lands on scale.y; rest pose is ONE * 0.85.
	visual.scale = Vector3.ONE * 0.85
	gecko.global_position = Vector3(0, 0.2, -30) # empty track
	gecko.set("velocity", Vector3.ZERO)
	await process_frame
	gecko.call("_do_jump")
	check(visual.scale.y > 1.0, "takeoff stretches the visual (%.2f)" % visual.scale.y)
	for i in 40:
		await process_frame
	check(visual.scale.distance_to(Vector3.ONE * 0.85) < 0.05,
		"visual eases back to normal after the stretch")

	# --- 6: landing squashes (poll every frame to catch the 0.22 s tween) ---
	# P23: the landing width (1.25) lands on local Z (lateral).
	var squashed := false
	gecko.global_position = Vector3(0, 3.0, -30)
	gecko.set("velocity", Vector3.ZERO)
	gecko.set("state", 1) # AIR
	visual.scale = Vector3.ONE * 0.85
	for i in 120:
		await process_frame
		if visual.scale.z > 0.95:
			squashed = true
			break
		if (gecko as CharacterBody3D).is_on_floor() and i > 100:
			break
	check(squashed, "landing squashes the visual")

	# --- 9: the hitbox never scales ---
	var hitbox: CollisionShape3D = gecko.get_node("CollisionShape3D")
	check(hitbox.scale.distance_to(Vector3.ONE) < 0.001,
		"hitbox scale untouched by the juice")

	# --- 7: bug collect bursts particles ---
	var before: int = _bursts().size()
	gecko.global_position = Vector3(-1.0, 0.2, -5) # first bug trail
	gecko.set("velocity", Vector3.ZERO)
	for i in 20:
		await process_frame
		if _bursts().size() > before:
			break
	check(_bursts().size() > before, "bug collection fires a particle burst")

	# --- 8: near-miss bursts particles ---
	before = _bursts().size()
	gs.call("register_near_miss")
	for i in 10:
		await process_frame
	check(_bursts().size() > before, "near-miss fires a particle burst")

	print("--- P22: %d passed, %d failed ---" % [_pass, _fail])
	quit(_fail)
