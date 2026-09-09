extends SceneTree
## P29 screenshot capture: wet driveway, dense planting, golden-hour grade.
##
## Run: xvfb-run -a godot --path <project> --resolution 1280x720 \
##        --script res://tests/capture_p29.gd -- <out_dir> <shot_name>
##   or: xvfb-run -a godot --path <project> --resolution 720x1280 \
##        --script res://tests/capture_p29.gd -- <out_dir> <shot_name>
##
## shot_name: "wet_driveway" | "planting" | "golden" | "portrait"

var _out_dir: String = "/tmp/p29_shots"
var _shot_name: String = "wet_driveway.png"


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
	var cap_profile := "user://cap_p29_profile.json"
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
	await _frames(10)
	var gecko: Node = main.get_node("Gecko")
	gecko.call("give_shield") # keep the shot clean of death flashes
	gecko.set("run_speed", 0.0) # frozen compositions

	if _shot_name.begins_with("wet_driveway"):
		# Mid-driveway (z -40..-110): the gecko sits on wet concrete,
		# puddles and sun glint ahead.
		gecko.global_position = Vector3(0.0, 0.2, -68.0)
	elif _shot_name.begins_with("planting"):
		# A planted stretch: hibiscus mid-line, palm sentinels behind.
		gecko.global_position = Vector3(0.0, 0.2, -120.0)
	elif _shot_name.begins_with("golden"):
		# The dog guard (z -283): long raking shadows, warm grade.
		gecko.global_position = Vector3(2.5, 0.2, -276.0)
	elif _shot_name.begins_with("portrait"):
		gecko.global_position = Vector3(0.0, 0.2, -70.0)
	await _frames(18) # let the camera rig ease onto the teleport

	var tex = null
	for retry in 120:
		await process_frame
		tex = root.get_texture()
		if tex != null:
			break
	if tex == null:
		print("shot FAILED (null viewport texture): ", _shot_name)
		quit(1)
		return
	var img: Image = tex.get_image()
	img.save_png(_out_dir + "/" + _shot_name)
	print("shot: ", _shot_name)
	print("P29 capture done")
	quit()
