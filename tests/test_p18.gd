extends SceneTree
## Gecko Run — P18 tests: missions system (retention layer).
##
## 1. Three missions exist, none done at run start.
## 2. Collecting 15 bugs completes the bug mission, fires the signal, pays bonus.
## 3. 3 near-misses complete the near-miss mission.
## 4. 45 s of run time completes the survive mission.
## 5. Missions reset on a new run.
## 6. HUD shows a mission tracker label; completion shows the popup.

var _pass := 0
var _fail := 0
var _completed: Array = []


func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("PASS: ", label)
	else:
		_fail += 1
		print("FAIL: ", label)


func _on_mission_completed(mission_id: String) -> void:
	_completed.append(mission_id)


func _initialize() -> void:
	# --script quirk: an autoload's _process never fires under the script
	# main-loop (its _ready runs, but idle processing doesn't). Follow the
	# P13 pattern: free the autoload and use a manual GameState, whose
	# _process ticks normally. Await a frame after each step so queue_free
	# lands and _ready() runs before we touch state.
	var auto: Node = root.get_node_or_null("GameState")
	if auto != null:
		auto.queue_free()
		await process_frame
	var gs: Node = (load("res://scripts/systems/game_state.gd") as Script).new()
	gs.name = "GameState"
	root.add_child(gs)
	await process_frame
	gs.mission_completed.connect(_on_mission_completed)
	gs.start_run()

	# --- 1: three missions, fresh ---
	var missions: Array = gs.get("missions")
	check(missions.size() == 3, "three missions defined (found %d)" % missions.size())
	var any_done := false
	for m in missions:
		if bool(m["done"]):
			any_done = true
	check(not any_done, "no mission done at run start")

	# --- 2: bug mission ---
	var score_before: int = gs.score
	for i in 14:
		gs.collect_bug()
	check(not bool((gs.get("missions") as Array)[0]["done"]),
		"14 bugs: mission not yet done")
	gs.collect_bug() # 15th
	check(bool((gs.get("missions") as Array)[0]["done"]),
		"15 bugs: bug mission done")
	check(_completed.has("bugs"), "mission_completed fired for 'bugs'")
	check(gs.score >= score_before + 100,
		"mission pays +100 bonus (score=%d)" % gs.score)

	# --- 3: near-miss mission ---
	gs.register_near_miss()
	gs.register_near_miss()
	check(not bool((gs.get("missions") as Array)[1]["done"]),
		"2 near-misses: mission not yet done")
	gs.register_near_miss()
	check(bool((gs.get("missions") as Array)[1]["done"]),
		"3 near-misses: near-miss mission done")
	check(_completed.has("near_miss"), "mission_completed fired for 'near_miss'")

	# --- 4: survive mission (45 s) ---
	gs.set("run_time", 44.0)
	for i in 3:
		await process_frame
	check(not bool((gs.get("missions") as Array)[2]["done"]),
		"44 s: survive mission not yet done")
	gs.set("run_time", 44.95)
	for i in 10:
		await process_frame
	check(bool((gs.get("missions") as Array)[2]["done"]),
		"45 s: survive mission done")
	check(_completed.has("survive"), "mission_completed fired for 'survive'")

	# --- 5: reset on new run ---
	gs.start_run()
	var fresh: Array = gs.get("missions")
	var all_fresh := true
	for m in fresh:
		if bool(m["done"]):
			all_fresh = false
	check(all_fresh, "missions reset on new run")

	# --- 6: HUD tracker + popup ---
	var ui := CanvasLayer.new()
	ui.set_script(load("res://scripts/ui/game_ui.gd"))
	root.add_child(ui)
	gs.current_state = gs.State.RUNNING
	for i in 5:
		await process_frame
	var tracker: Label = ui.get("_mission_label")
	check(tracker != null, "HUD mission tracker label exists")
	if tracker != null:
		check(tracker.text.begins_with("BUGS"),
			"tracker shows first incomplete mission (text='%s')" % tracker.text)
	# Complete the bug mission and watch for the popup.
	_completed.clear()
	for i in 15:
		gs.collect_bug()
	for i in 5:
		await process_frame
	var popup: Label = ui.get("_mission_popup_label")
	check(popup != null and popup.visible,
		"MISSION COMPLETE popup shows on completion")

	print("--- P18: %d passed, %d failed ---" % [_pass, _fail])
	quit(_fail)
