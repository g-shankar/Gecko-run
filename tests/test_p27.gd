extends SceneTree
## Gecko Run — P27 tests: the pitch-deck HUD.
##
## 1. HUD nodes exist: two-tone wordmark, bug counter, timer, Minimap,
##    mission panel, 4 ability slots, DASH + pause buttons.
## 2. Run start resets the 2/1/1/2 charge loadout.
## 3. Ability taps spend charges and fire the real mechanics on the gecko
##    (shield, boost, camo timer, tongue eating bugs in radius).
## 4. Camo makes hazards blind: hazard_base skips the hit; bird holds dive.
## 5. Every 15 bugs grants +1 random charge (capped).
## 6. Minimap progress math: 364 m backyard vs 196 m fence line.
## 7. Bug totals come from the route's spawns, per map.
## 8. Mission panel shows the first incomplete mission and advances.
## 9. DebugHUD is hidden by default, toggleable.

var _pass := 0
var _fail := 0

const TEST_PROFILE := "user://test_p27_profile.json"


func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("PASS: ", label)
	else:
		_fail += 1
		print("FAIL: ", label)


func _find_label_text(node: Node, text: String) -> Label:
	if node is Label and (node as Label).text == text:
		return node as Label
	for c in node.get_children():
		var hit := _find_label_text(c, text)
		if hit != null:
			return hit
	return null


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node as Button
	for c in node.get_children():
		var hit := _find_button(c, text)
		if hit != null:
			return hit
	return null


func _charge_sum(ui: CanvasLayer) -> int:
	var total := 0
	for v in (ui.get("_charges") as Dictionary).values():
		total += int(v)
	return total


func _initialize() -> void:
	# --- GameState setup (P13/P18 pattern), isolated profile ---
	var auto: Node = root.get_node_or_null("GameState")
	if auto != null:
		auto.queue_free()
		await process_frame
	if FileAccess.file_exists(TEST_PROFILE):
		DirAccess.remove_absolute(TEST_PROFILE)
	var gs: Node = load("res://scripts/systems/game_state.gd").new()
	gs.name = "GameState"
	gs.set("profile_path", TEST_PROFILE)
	root.add_child(gs)
	await process_frame

	# --- The UI under test ---
	var ui: CanvasLayer = load("res://scripts/ui/game_ui.gd").new()
	root.add_child(ui)
	await process_frame
	var hud: Control = ui.get("_hud")

	# --- 1: pitch-deck HUD nodes exist ---
	check(_find_label_text(hud, "GECKO") != null, "wordmark GECKO label exists")
	check(_find_label_text(hud, "RUN") != null, "wordmark RUN label exists")
	check(_find_label_text(hud, "SMALL GECKO. BIG ADVENTURES.") != null,
		"tagline exists")
	var bug_label := ui.get("_bug_label") as Label
	check(bug_label != null and bug_label.text.begins_with("🪲"),
		"bug counter label exists")
	check(ui.get("_timer_label") != null, "run timer label exists")
	check(ui.get("_minimap") is Minimap, "circular minimap exists")
	check(ui.get("_mission_body") != null, "mission panel body exists")
	var buttons := ui.get("_ability_buttons") as Dictionary
	var want := { "boost": false, "shield": false, "camo": false, "tongue": false }
	for id in buttons.keys():
		if want.has(id):
			want[id] = true
	var all_four := true
	for id in want.keys():
		all_four = all_four and bool(want[id])
	check(all_four, "4 ability slots: BOOST/SHIELD/CAMO/TONGUE")
	check(_find_button(hud, "DASH") != null, "DASH touch button exists")
	check(_find_button(hud, "II") != null, "pause button exists")

	# --- 2: run start = key-art loadout 2/1/1/2 ---
	gs.set("current_state", gs.State.RUNNING)
	var charges := ui.get("_charges") as Dictionary
	check(int(charges.get("boost")) == 2 and int(charges.get("shield")) == 1 \
		and int(charges.get("camo")) == 1 and int(charges.get("tongue")) == 2,
		"charges reset to 2/1/1/2 on run start")

	# --- The gecko under test ---
	var gecko: CharacterBody3D = \
		(load("res://scenes/player/gecko.tscn") as PackedScene).instantiate()
	root.add_child(gecko)
	await process_frame
	await process_frame

	# --- 9: DebugHUD hidden by default, F1-toggled ---
	var dbg: CanvasLayer = null
	for c in gecko.get_children():
		if c is DebugHUD:
			dbg = c
	check(dbg != null, "DebugHUD child exists on the gecko")
	check(dbg != null and not dbg.visible, "DebugHUD hidden by default")
	if dbg != null:
		gecko.call("set_debug_hud", true)
		check(dbg.visible, "debug HUD toggle shows it")
		gecko.call("set_debug_hud", false)
		check(not dbg.visible, "debug HUD toggle hides it again")

	# --- 3: ability taps spend charges and fire real mechanics ---
	ui.call("_on_ability_pressed", "shield")
	check(int((ui.get("_charges") as Dictionary).get("shield")) == 0,
		"SHIELD tap spends its charge")
	check(int(gecko.get("shield_charges")) == 1, "SHIELD grants a real shield")
	ui.call("_on_ability_pressed", "boost")
	check(int((ui.get("_charges") as Dictionary).get("boost")) == 1,
		"BOOST tap spends a charge")
	check(float(gecko.get("_speed_boost_timer")) > 0.0,
		"BOOST starts the real speed boost")
	ui.call("_on_ability_pressed", "camo")
	check(int((ui.get("_charges") as Dictionary).get("camo")) == 0,
		"CAMO tap spends its charge")
	check(bool(gecko.call("is_camouflaged")), "CAMO starts the camo timer")
	var before := _charge_sum(ui)
	ui.call("_on_ability_pressed", "shield") # 0 charges left: no-op.
	check(_charge_sum(ui) == before, "tapping an empty slot does nothing")

	# --- 4: camo blinds hazards ---
	var hb := HazardBase.new()
	root.add_child(hb)
	await process_frame
	check(hb._gecko_camouflaged(), "hazard_base sees the camouflaged gecko")
	var hits := 0
	hb.player_hit.connect(func() -> void: hits += 1)
	hb._on_body_entered(gecko)
	check(hits == 0, "camo: hazard body_entered does not hit")
	hb._check_overlaps()
	check(hits == 0, "camo: hazard overlap check does not hit")
	gecko.set("_camo_timer", 0.01)
	for i in 4:
		await physics_frame
	check(not bool(gecko.call("is_camouflaged")), "camo timer expires")
	check(not hb._gecko_camouflaged(), "hazard sees the gecko again after camo")
	hb.queue_free()

	# --- 3b: tongue eats bugs in radius, spares distant ones ---
	var near1 := BugPickup.new()
	var near2 := BugPickup.new()
	var far := BugPickup.new()
	for b in [near1, near2, far]:
		root.add_child(b)
	await process_frame
	var gp: Vector3 = gecko.global_position
	near1.global_position = gp + Vector3(2, 0, -2)
	near2.global_position = gp + Vector3(-3, 0, 1)
	far.global_position = gp + Vector3(0, 0, -30)
	var bugs_before := int(gs.get("bug_count"))
	ui.call("_on_ability_pressed", "tongue")
	check(int((ui.get("_charges") as Dictionary).get("tongue")) == 1,
		"TONGUE tap spends a charge")
	check(not is_instance_valid(near1) or near1.is_queued_for_deletion(),
		"tongue eats bug within 6 m (1)")
	check(not is_instance_valid(near2) or near2.is_queued_for_deletion(),
		"tongue eats bug within 6 m (2)")
	check(is_instance_valid(far) and not far.is_queued_for_deletion(),
		"tongue spares the bug 30 m away")
	check(int(gs.get("bug_count")) == bugs_before + 2,
		"eaten bugs feed the bug counter")
	far.queue_free()

	# --- 5: every 15 bugs = +1 random charge ---
	var sum_before := _charge_sum(ui)
	for i in 15:
		gs.call("collect_bug")
	check(_charge_sum(ui) == sum_before + 1, "15-bug streak grants one charge")
	check(int(ui.get("_next_streak_at")) == 30, "streak counter re-arms at 30")

	# --- 6: minimap progress math, per map length ---
	var half_backyard: float = ui.call("route_progress", 6.0 - 182.0, 6.0, -358.0)
	check(absf(half_backyard - 0.5) < 0.001, "backyard: halfway = 0.5")
	var half_fence: float = ui.call("route_progress", 6.0 - 98.0, 6.0, -190.0)
	check(absf(half_fence - 0.5) < 0.001, "fence line: halfway = 0.5")
	check(absf((6.0 - -358.0) - 364.0) < 0.01, "backyard route is 364 m")
	check(absf((6.0 - -190.0) - 196.0) < 0.01, "fence line route is 196 m")
	check(float(ui.call("route_progress", -400.0, 6.0, -358.0)) == 1.0,
		"progress clamps at the finish")
	check(float(ui.call("route_progress", 6.0, 6.0, -358.0)) == 0.0,
		"progress is 0 at the start line")

	# --- 7: bug totals come from the route's spawns ---
	var back_data: Resource = \
		(load("res://scripts/systems/level_data.gd") as Script).new()
	var level := Level.new()
	level.level_data = back_data
	level.add_to_group("level")
	root.add_child(level)
	await process_frame
	ui.call("_compute_bug_total")
	var expect_back := 0
	for s in (back_data.get("spawns") as Array):
		if String((s as Dictionary).get("type", "")) == "bug":
			expect_back += 1
	check(int(ui.get("_bug_total")) == expect_back and expect_back > 0,
		"bug total = backyard bug spawns (%d)" % expect_back)
	var fence_data: Resource = \
		(load("res://scripts/systems/level_data_fenceline.gd") as Script).new()
	level.level_data = fence_data
	ui.call("_compute_bug_total")
	var expect_fence := 0
	for s in (fence_data.get("spawns") as Array):
		if String((s as Dictionary).get("type", "")) == "bug":
			expect_fence += 1
	check(int(ui.get("_bug_total")) == expect_fence,
		"bug total follows the active map (%d)" % expect_fence)
	level.queue_free()

	# --- 8: mission panel shows the first incomplete mission, then advances ---
	gs.call("reset_run")
	ui.call("_update_mission_tracker")
	var body := (ui.get("_mission_body") as Label).text
	check(body.contains("Eat bugs") and body.contains("0/15"),
		"mission panel shows the BUGS objective")
	for m in (gs.get("missions") as Array):
		if String((m as Dictionary)["id"]) == "bugs":
			(m as Dictionary)["done"] = true
			(m as Dictionary)["progress"] = 15
	ui.call("_update_mission_tracker")
	body = (ui.get("_mission_body") as Label).text
	check(body.contains("Near-miss"), "mission panel advances after completion")

	print("P27: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
