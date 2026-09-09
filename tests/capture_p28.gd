extends SceneTree
## P28 screenshot capture: dog bark/lunge + mower crossing, in a real run.
## (Follows the proven capture_p28_5.gd frontend flow so the viewport
## texture is valid for screenshots.)
##
## Run: xvfb-run -a godot --path <project> --resolution 1280x720 \
##        --script res://tests/capture_p28.gd -- <out_dir> <shot_name>
##   or: xvfb-run -a godot --path <project> --resolution 720x1280 \
##        --script res://tests/capture_p28.gd -- <out_dir> <shot_name>
##
## shot_name: "dog_bark" | "dog_lunge" | "mower_cross"

var _out_dir: String = "/tmp/p28_shots"
var _shot_name: String = "dog_bark.png"


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
	var cap_profile := "user://cap_p28_profile.json"
	if FileAccess.file_exists(cap_profile):
		DirAccess.remove_absolute(cap_profile)
	gs.set("profile_path", cap_profile)
	gs.call("_load_profile")

	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node = packed.instantiate()
	root.add_child(main)
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
	var level: Node = main.get_node("Level")
	# Framing: hide the footstep shoes — their timer loop photobombs the
	# dog/mower compositions. (Capture-only; the game is untouched.)
	for c in level.get_children():
		if (c as Node).name.begins_with("Footstep"):
			(c as Node3D).hide()

	if _shot_name.begins_with("dog"):
		# First dog (Dog) at (4, -283). Park the gecko behind it (x=5) so the
		# retriever is centered and the footstep shoe at (0,-281) stays out
		# of frame. Frozen: the bark composition shouldn't drift.
		var dog: Node = level.get_node("Dog")
		gecko.set("run_speed", 0.0)
		gecko.global_position = Vector3(4.0, 0.2, -276.5)
		if "bark" in _shot_name:
			for i in range(900):
				await physics_frame
				if int(dog.get("phase")) == 1: # TELEGRAPH
					break
			await _frames(6) # mid wind-up: "!" pulsing, dog reared
		else:
			var rest_x: float = (dog.get("_rest_pos") as Vector3).x
			for i in range(900):
				await physics_frame
				# Freeze mid-lunge: the dog has left its rest spot but the
				# hit is still live. Pausing stops the fast 0.45 s lunge dead
				# so xvfb's slow frames can't miss it.
				if int(dog.get("phase")) == 2 \
						and absf(dog.global_position.x - rest_x) > 0.8:
					paused = true
					break
			await _frames(3) # let the paused frame render
			paused = false
	elif _shot_name.begins_with("mower"):
		var mower: Node3D = level.get_node("Mower")
		gecko.set("run_speed", 0.0) # freeze the runner: the camera must not
		gecko.global_position = Vector3(0.0, 0.2, -294.0) # drift past -303
		for i in range(3000):
			await physics_frame
			# Freeze the frame the instant the mower is mid-lane: pausing
			# the tree stops the crossing dead so xvfb's slow frames can't
			# carry it out of view before the capture.
			if int(mower.get("phase")) == 2 \
					and absf(mower.global_position.x) < 1.0:
				paused = true
				break
		var st: MeshInstance3D = mower.get("_stripes")
			" in_tree=", st.is_inside_tree() if st else false,
			" pos=", st.global_position if st else Vector3.ZERO)
		await _frames(3) # let the paused frame render
		paused = false

	# The viewport texture can be momentarily null under xvfb; retry.
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
	print("P28 capture done")
	quit()
