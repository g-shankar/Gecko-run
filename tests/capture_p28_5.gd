extends SceneTree
## P28.5 screenshot capture: the real-3D pass in a real run.
##
## Run: xvfb-run -a godot --path <project> --resolution 1280x720 \
##        --script res://tests/capture_p28_5.gd -- <out_dir> <shot_name>
##   or: xvfb-run -a godot --path <project> --resolution 720x1280 \
##        --script res://tests/capture_p28_5.gd -- <out_dir> <shot_name>
##
## If <shot_name> contains "dash", the gecko dashes right before the shot.
## If <shot_name> contains "boost", the gecko gets a speed boost (speed-lines
## overlay). Captures settled gameplay: animated gecko, macro camera, new
## ground.

var _out_dir: String = "/tmp/p28_5_shots"
var _shot_name: String = "p28_5_run.png"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_out_dir = args[0]
	if args.size() >= 2:
		_shot_name = args[1]
	DirAccess.make_dir_recursive_absolute(_out_dir)
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	# Fresh first-launch profile on the autoload GameState.
	var gs: Node = root.get_node_or_null("GameState")
	var cap_profile := "user://cap_p28_5_profile.json"
	if FileAccess.file_exists(cap_profile):
		DirAccess.remove_absolute(cap_profile)
	gs.set("profile_path", cap_profile)
	gs.call("_load_profile")

	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node = packed.instantiate()
	root.add_child(main)
	# Clean screenshots: the dev HUD is a debug tool, not part of the game.
	for c in (main.get_node("Gecko") as Node).get_children():
		if c is DebugHUD:
			(c as CanvasLayer).hide()
	await _frames(30)
	var fe: CanvasLayer = main.get_node("FrontendUI")

	# Skip the journey: name + straight into the backyard run.
	(fe.get("_name_input") as LineEdit).text = "CAP"
	fe.call("_on_name_confirmed", false)
	await _frames(5)
	fe.call("start_map", "florida_backyard")
	# Let the run settle: camera rig eases in, gecko starts sprinting.
	# xvfb runs at ~2fps, so game time outruns wall frames — a few frames
	# is several seconds of run time.
	await _frames(10)
	var gecko: Node = main.get_node("Gecko")
	gecko.call("give_shield") # keep the shot clean of death flashes
	if "dash" in _shot_name:
		gecko.call("request_dash")
		await _frames(4)
	elif "boost" in _shot_name: ## P28.5+: verify the speed-lines overlay.
		gecko.call("give_speed_boost")
		await _frames(4)
	else:
		await _frames(6)

	var img := root.get_texture().get_image()
	img.save_png(_out_dir + "/" + _shot_name)
	print("shot: ", _shot_name)

	print("P28.5 capture done")
	quit()
