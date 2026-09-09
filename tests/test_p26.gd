extends SceneTree
## Gecko Run — P26 tests: the front-end journey.
##
## 1. WorldData: 3 worlds, Florida unlocked, 2 locked teasers, 2 maps.
## 2. LevelDataFenceLine: a real second route (denser, shorter, valid types).
## 3. Profile: versioned save/load round-trip, name, skin persist.
## 4. Frontend: name entry on first launch, journey/gecko/map screens exist,
##    gecko select carries a real 3D hero preview + 5 skins.
## 5. start_map: route swaps, fence moves, run starts on the chosen map.
## 6. finish_run records lifetime stats; game over -> map select works.

var _pass := 0
var _fail := 0

const TEST_PROFILE := "user://test_p26_profile.json"


func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("PASS: ", label)
	else:
		_fail += 1
		print("FAIL: ", label)


func _initialize() -> void:
	# --- GameState setup (P13/P18 pattern), isolated profile ---
	var auto: Node = root.get_node_or_null("GameState")
	if auto != null:
		auto.queue_free()
		await process_frame
	if FileAccess.file_exists(TEST_PROFILE):
		DirAccess.remove_absolute(TEST_PROFILE)
	if FileAccess.file_exists("user://gecko_run_profile.json"):
		DirAccess.remove_absolute("user://gecko_run_profile.json")
	var gs: Node = load("res://scripts/systems/game_state.gd").new()
	gs.name = "GameState"
	gs.set("profile_path", TEST_PROFILE)
	root.add_child(gs)
	await process_frame

	# --- 1: world data ---
	check(WorldData.world_count() == 3, "3 worlds defined")
	var fl := WorldData.get_world("florida")
	check(not fl.is_empty() and bool(fl["unlocked"]), "florida unlocked")
	var locked := 0
	for w in WorldData.WORLDS:
		if not bool(w["unlocked"]):
			locked += 1
	check(locked == 2, "2 locked teaser worlds")
	var maps := WorldData.maps_for_world("florida")
	check(maps.size() == 2, "florida has 2 maps")
	var ids := {}
	for m in maps:
		ids[String(m["id"])] = true
	check(ids.has("florida_backyard") and ids.has("florida_fenceline"),
		"map ids are backyard + fenceline")
	var route := WorldData.route_for_map("florida_fenceline")
	check(route == "res://scripts/systems/level_data_fenceline.gd",
		"fenceline route resolves")
	check(WorldData.route_for_map("nope") == "", "unknown map -> empty route")
	check(WorldData.get_map("nope").is_empty(), "unknown map -> empty dict")

	# --- 2: the Fence Line route ---
	var fl_data: Resource = (load("res://scripts/systems/level_data_fenceline.gd") as Script).new()
	var spawns: Array = fl_data.get("spawns")
	check(spawns.size() >= 40, "fenceline has >= 40 spawns (%d)" % spawns.size())
	check(String(fl_data.get("level_name")) == "Fence Line", "fenceline named")
	check(float(fl_data.get("fence_z")) == -190.0, "fenceline fence at -190")
	check((fl_data.get("start_position") as Vector3).is_equal_approx(Vector3(0, 0, 6)),
		"fenceline starts at the same start line")
	var known := Level.HAZARD_SCRIPTS.keys()
	var bad := 0
	for s in spawns:
		if not known.has(String(s.get("type", ""))):
			bad += 1
	check(bad == 0, "all fenceline spawn types are known hazards")
	var default_data: Resource = (load("res://scripts/systems/level_data.gd") as Script).new()
	check(spawns.size() != (default_data.get("spawns") as Array).size(),
		"fenceline differs from the default route")

	# --- 3: profile round-trip ---
	check(String(gs.get("player_name")) == "", "fresh profile has no name")
	gs.call("set_player_name", "  Tester  ")
	check(String(gs.get("player_name")) == "Tester", "name is stripped")
	gs.call("set_skin", 3)
	check(int(gs.get("selected_skin")) == 3, "skin set to 3")
	var gs2: Node = load("res://scripts/systems/game_state.gd").new()
	gs2.set("profile_path", TEST_PROFILE)
	gs2.call("_load_profile")
	check(String(gs2.get("player_name")) == "Tester", "name persists across loads")
	check(int(gs2.get("selected_skin")) == 3, "skin persists across loads")
	var f := FileAccess.open(TEST_PROFILE, FileAccess.READ)
	var raw: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	check(int(raw.get("version", 0)) == 1, "profile is versioned (v1)")
	gs2.free()
	gs.call("set_player_name", "")
	check(String(gs.get("player_name")) == "GECKO", "blank name falls back to GECKO")
	gs.set("player_name", "") # Back to first-launch state for the frontend checks.

	# --- 4: frontend screens ---
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node = packed.instantiate()
	root.add_child(main)
	for i in 45:
		await process_frame
	var fe: CanvasLayer = main.get_node("FrontendUI")
	check(fe != null, "FrontendUI present")
	check(fe.is_in_group("frontend_ui"), "frontend in its group")
	# First launch: no name -> name entry shows over the menu.
	var ui: CanvasLayer = main.get_node("GameUI")
	check((fe.get("_name_entry") as Control).visible, "name entry shows on first launch")
	check(not (ui.get("_start_screen") as Control).visible, "menu hides behind name entry")
	# Confirm a name -> entry hides, menu returns.
	(fe.get("_name_input") as LineEdit).text = "CAP"
	fe.call("_on_name_confirmed", false)
	await process_frame
	check(not (fe.get("_name_entry") as Control).visible, "name entry hides after confirm")
	check((ui.get("_start_screen") as Control).visible, "menu returns after confirm")
	check(String(gs.get("player_name")) == "CAP", "confirmed name saved")
	# Journey / gecko / map screens exist and show.
	fe.call("show_journey")
	check((fe.get("_journey") as Control).visible, "journey screen shows")
	fe.call("show_geckos")
	check((fe.get("_gecko_select") as Control).visible, "gecko select shows")
	check(fe.get("_preview_gecko") != null, "gecko select has a 3D hero preview")
	check((fe.get("_skin_buttons") as Array).size() == 5, "5 skin buttons")
	fe.call("_on_skin_chosen", 4)
	check(int(gs.get("selected_skin")) == 4, "skin choice persists from select screen")
	check(String(fe.get("_skin_name_label").text) == "Midnight", "skin name updates")
	fe.call("show_profile")
	check((fe.get("_profile") as Control).visible, "profile screen shows")
	check(String(fe.get("_profile_name_label").text).contains("CAP"), "profile shows the name")

	# --- 5: start_map swaps the route and starts the run ---
	var level: Node = main.get_node("Level")
	var default_count := (level.get("spawned") as Array).size()
	check(default_count > 100, "default route built (%d hazards)" % default_count)
	fe.call("start_map", "florida_fenceline")
	for i in 10:
		await process_frame
	check(gs.get("current_state") == gs.State.RUNNING, "start_map -> RUNNING")
	check(String(gs.get("current_map_id")) == "florida_fenceline", "current map recorded")
	var fl_count := (level.get("spawned") as Array).size()
	check(fl_count == spawns.size(), "route swapped to fenceline (%d)" % fl_count)
	var fence := main.get_node("Fence") as Node3D
	check(is_equal_approx(fence.position.z, -190.0), "fence moved to fenceline end")
	check((ui.get("_hud") as Control).visible, "HUD visible on the run")
	check(not (fe.get("_map_select") as Control).visible, "frontend hidden on the run")

	# --- 6: finish records stats; game over -> map select ---
	gs.set("score", 500)
	gs.set("bug_count", 7)
	gs.call("finish_run")
	check(gs.get("current_state") == gs.State.FINISHED, "finish_run -> FINISHED")
	check(int(gs.get("total_runs")) == 1, "total_runs recorded")
	check(int(gs.get("total_bugs")) == 7, "total_bugs recorded")
	check(int((gs.get("map_best") as Dictionary).get("florida_fenceline", 0)) == 500,
		"per-map best recorded")
	check((ui.get("_game_over") as Control).visible, "game over shows")
	ui.call("_on_maps_pressed")
	for i in 5:
		await process_frame
	check(gs.get("current_state") == gs.State.READY, "MAPS -> READY")
	check((fe.get("_map_select") as Control).visible, "game over lands on map select")
	check((fe.get("_map_card_box") as VBoxContainer).get_child_count() == 2,
		"map select lists 2 maps")

	# --- 7: route swaps back cleanly ---
	fe.call("start_map", "florida_backyard")
	for i in 10:
		await process_frame
	check((level.get("spawned") as Array).size() == default_count, "route swaps back cleanly")
	check(is_equal_approx((main.get_node("Fence") as Node3D).position.z, -358.0),
		"fence back at -358")

	if FileAccess.file_exists(TEST_PROFILE):
		DirAccess.remove_absolute(TEST_PROFILE)
	print("--- P26: %d passed, %d failed ---" % [_pass, _fail])
	if _fail > 0:
		quit(1)
	else:
		quit()
