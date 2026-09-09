extends SceneTree
## Gecko Run — P21 tests: longer route + difficulty curve.
##
## 1. The route carries >= 12 hazard spawns (footstep/sprinkler/bicycle/bird/car).
## 2. Warn times tighten along the route (non-increasing, first > last).
## 3. Spawn "warn" values actually land on the hazard nodes.
## 4. The fence stands at the route's end (finish gate).
## 5. The ground visual covers the long route.
## 6. Route spans ~60-90 s of run time (~300+ m).

var _pass := 0
var _fail := 0

const HAZARD_TYPES := ["footstep", "sprinkler", "bicycle", "bird", "car"]


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
	var auto: Node = root.get_node_or_null("GameState")
	if auto != null:
		auto.queue_free()
	for i in 32:
		await process_frame

	var level: Node3D = main.get_node("Level")
	var data: Resource = level.get("level_data")
	var spawns: Array = data.get("spawns")

	# --- 1: hazard count ---
	var hazards := 0
	for spawn in spawns:
		if String(spawn["type"]) in HAZARD_TYPES:
			hazards += 1
	check(hazards >= 12, "route has %d hazard spawns (>= 12)" % hazards)

	# --- 2: warn ramp ---
	var warns: Array = []
	for spawn in spawns:
		if (spawn as Dictionary).has("warn"):
			warns.append(float(spawn["warn"]))
	check(warns.size() >= 10, "warn overrides on %d hazards" % warns.size())
	var non_increasing := true
	for i in range(1, warns.size()):
		if warns[i] > warns[i - 1] + 0.001:
			non_increasing = false
	check(non_increasing, "warn_time never loosens along the route")
	check(warns[0] > warns[warns.size() - 1],
		"telegraphs tighten: %.2f s -> %.2f s" % [warns[0], warns[warns.size() - 1]])

	# --- 3: warns land on the nodes ---
	var applied := 0
	var spawned: Array = level.get("spawned")
	for h in spawned:
		var hn: String = (h as Node).name
		if hn.begins_with("Footstep") or hn.begins_with("Sprinkler") \
				or hn.begins_with("Bicycle") or hn.begins_with("Bird") \
				or hn.begins_with("BackingCar"):
			# Find this node's spawn by position.
			for spawn in spawns:
				var sp: Vector3 = spawn["pos"]
				if absf(sp.z - (h as Node3D).position.z) < 0.05 \
						and (spawn as Dictionary).has("warn"):
					if absf(float((h as Node).get("warn_time")) - float(spawn["warn"])) < 0.001:
						applied += 1
					break
	check(applied >= 10, "warn values applied to %d hazard nodes" % applied)

	# --- 4: fence at the end ---
	var fence: Node3D = main.get_node("Fence")
	var fence_z: float = float(data.get("fence_z"))
	check(absf(fence.position.z - fence_z) < 0.05,
		"fence stands at fence_z=%.0f" % fence_z)
	var last_z: float = (spawns[spawns.size() - 1]["pos"] as Vector3).z
	check(fence_z < last_z, "fence is past the last spawn (finish gate)")

	# --- 5: ground covers the route ---
	var ground := main.get_node("Ground") as MeshInstance3D
	var size: Vector2 = (ground.mesh as PlaneMesh).size
	var covers: float = ground.position.z - size.y / 2.0
	check(covers < fence_z, "ground visual reaches z=%.0f (past fence)" % covers)

	# --- 6: route length ~60-90 s of running (~300+ m at 5-9 m/s) ---
	var start_z: float = (data.get("start_position") as Vector3).z
	check(start_z - fence_z >= 300.0,
		"route is %.0f m long" % (start_z - fence_z))

	print("--- P21: %d passed, %d failed ---" % [_pass, _fail])
	quit(_fail)
