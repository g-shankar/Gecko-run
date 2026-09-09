extends SceneTree
## Gecko Run — P14 acceptance: start, pause, game over, restart from UI alone.

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
	# The --script runner doesn't load autoloads; instance GameState manually.
	var gs_script: Script = load("res://scripts/systems/game_state.gd")
	var gs: Node = gs_script.new()
	gs.name = "GameState"
	root.add_child(gs)
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

	var ui: CanvasLayer = main.get_node("GameUI")
	check(ui != null, "GameUI present")
	var gecko: CharacterBody3D = main.get_node("Gecko")
	gecko.run_speed = 0.0

	# 1. Boots to the start screen.
	check(gs.current_state == gs.State.READY, "boots to READY")
	check((ui.get("_start_screen") as Control).visible, "start screen visible")

	# 2. Start button -> RUNNING + HUD.
	(ui as Node).call("_on_start_pressed")
	for i in 10:
		await process_frame
	check(gs.current_state == gs.State.RUNNING, "start -> RUNNING")
	check((ui.get("_hud") as Control).visible, "HUD visible after start")
	# Gecko actually runs now (was idling on the start screen).
	var z0: float = gecko.global_position.z
	gecko.run_speed = 6.0
	for i in 30:
		await process_frame
	check(gecko.global_position.z < z0, "gecko runs once the run starts")
	gecko.run_speed = 0.0

	# 3. Pause button -> paused + pause menu.
	(ui as Node).call("_on_pause_pressed")
	check(paused, "tree paused")
	check((ui.get("_pause_menu") as Control).visible, "pause menu visible")

	# 4. Resume -> unpaused + HUD.
	(ui as Node).call("_on_resume_pressed")
	check(not paused, "tree unpaused")
	check((ui.get("_hud") as Control).visible, "HUD visible after resume")

	# 5. Three deaths -> game over screen.
	gecko.set("shield_charges", 0)
	for d in 3:
		# Wait until alive (respawn from the previous death).
		for i in int(4.0 * 60.0):
			await process_frame
			if int(gecko.get("state")) != 6:
				break
		gecko.die()
		for i in 10:
			await process_frame
	check(gs.current_state == gs.State.FINISHED,
		"3 deaths -> FINISHED (game over)")
	check((ui.get("_game_over") as Control).visible, "game over screen visible")

	# 6. RUN AGAIN -> fresh run.
	(ui as Node).call("_on_restart_pressed")
	for i in 10:
		await process_frame
	check(gs.current_state == gs.State.RUNNING, "restart -> RUNNING")
	check(gs.deaths == 0, "deaths reset for the new run")
	check(int(gecko.get("state")) != 6, "gecko alive after restart")

	print("P14_RESULT: %d/%d passed" % [passes, passes + failures])
	quit(1 if failures > 0 else 0)
