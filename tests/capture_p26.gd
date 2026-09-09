extends SceneTree
## P26 screenshot capture: the front-end journey.
##
## Run: xvfb-run -a godot --path <project> --resolution 1280x720 \
##        --script res://tests/capture_p26.gd -- <out_dir>
##
## Captures: name entry, journey, gecko select, map select, polished run.

var _out_dir: String = "/tmp/p26_shots"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(_out_dir)
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png(_out_dir + "/" + name)
	print("shot: ", name)


func _run() -> void:
	# Fresh first-launch profile on the autoload GameState.
	var gs: Node = root.get_node_or_null("GameState")
	var cap_profile := "user://cap_p26_profile.json"
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

	# 1: name entry on first launch.
	await _shot("p26_name_entry.png")

	# 2: journey / world tour.
	(fe.get("_name_input") as LineEdit).text = "CAP"
	fe.call("_on_name_confirmed", false)
	await _frames(5)
	fe.call("show_journey")
	await _frames(10)
	await _shot("p26_journey.png")

	# 3: gecko select with the 3D hero preview.
	fe.call("show_geckos")
	await _frames(30)
	await _shot("p26_geckos.png")

	# 4: map select.
	fe.call("_on_world_pressed", "florida")
	await _frames(10)
	await _shot("p26_maps.png")

	# 5: the run itself — new atmosphere, real models, HUD. Shot early in the
	# sprint (before the pergola), while the gecko is alive and the camera
	# has settled. xvfb runs at ~2fps, so game time outruns wall frames.
	fe.call("start_map", "florida_backyard")
	await _frames(7)
	await _shot("p26_run.png")

	print("P26 capture done")
	quit()
