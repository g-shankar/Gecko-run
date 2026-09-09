extends SceneTree
## Gecko Run — P20 tests: ceiling routes (the gecko fantasy).
##
## 1. Level builds the pergola: two posts + a slab, all climbable.
## 2. Gecko can adhere to the ceiling (up_direction flips to DOWN).
## 3. Gecko moves along the ceiling.
## 4. Past the slab end it detaches and lands back on the ground cleanly.
## 5. Wall-running into the slab transitions onto the ceiling.
## 6. LevelData carries a bug trail under the slab (risk-reward).

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
	gecko.set("run_speed", 0.0) # Stay put; we place the gecko by hand.

	# --- 1: pergola ---
	var pergola: Node3D = level.get_node_or_null("Pergola")
	check(pergola != null, "Pergola built under Level")
	var top: Node3D = null
	if pergola != null:
		top = pergola.get_node_or_null("PergolaTop")
		check(top != null, "PergolaTop slab exists")
		check(top != null and top.is_in_group("climbable"),
			"slab is climbable")
		check(pergola.get_node_or_null("PergolaPostL") != null
			and pergola.get_node_or_null("PergolaPostR") != null,
			"both climbable posts exist")

	# --- 2: adhere to ceiling ---
	gecko.global_position = Vector3(2.2, 2.0, -16.0)
	gecko.set("velocity", Vector3.ZERO)
	gecko.call("_attach_to_ceiling", Vector3(0, -1, 0))
	check(int(gecko.get("state")) == 3, "gecko enters ADHERE_CEILING")
	check((gecko.get("up_direction") as Vector3).distance_to(Vector3(0, -1, 0)) < 0.01,
		"up_direction flips to DOWN on the ceiling")

	# --- 3: move along the ceiling ---
	var p0: Vector3 = gecko.global_position
	for i in 30:
		await process_frame
	var moved: float = (gecko.global_position - p0).length()
	check(moved > 0.5, "gecko travels along the ceiling (%.2f m)" % moved)
	check(int(gecko.get("state")) == 3, "still adhered mid-slab")

	# --- 4: past the slab end -> detach -> land cleanly ---
	gecko.global_position = Vector3(2.2, 2.4, -30.0) # open air past the fence
	gecko.set("_adhere_grace", 0.0)
	for i in 180:
		await process_frame
		if gecko.get("up_direction") == Vector3.UP and (gecko as CharacterBody3D).is_on_floor():
			break
	check((gecko.get("up_direction") as Vector3) == Vector3.UP,
		"up_direction restored after leaving the ceiling")
	check((gecko as CharacterBody3D).is_on_floor(), "gecko lands on the ground")
	check(gecko.global_position.y < 0.5, "landed at ground height (y=%.2f)" % gecko.global_position.y)

	# --- 5: wall -> ceiling transition ---
	gecko.global_position = Vector3(2.2, 1.5, -15.2) # in front of PergolaPostR
	gecko.set("velocity", Vector3.ZERO)
	gecko.call("_attach_to_wall", Vector3(0, 0, 1))
	gecko.set("_adhere_grace", 0.0)
	for i in 10:
		await process_frame
	check(int(gecko.get("state")) == 3,
		"wall-running under the slab transitions to the ceiling")

	# --- 6: ceiling bug trail in the data ---
	var ceiling_bugs := 0
	for spawn in (level.get("level_data").get("spawns") as Array):
		if String(spawn["type"]) == "bug" and absf((spawn["pos"] as Vector3).y - 1.8) < 0.01:
			ceiling_bugs += 1
	check(ceiling_bugs >= 4, "bug trail under the slab (%d bugs)" % ceiling_bugs)

	print("--- P20: %d passed, %d failed ---" % [_pass, _fail])
	quit(_fail)
