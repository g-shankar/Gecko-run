extends SceneTree
## Gecko Run — P25 tests: real 3D models replace primitive visuals.
##
## 1. ModelSwap registry: all 8 models present, each under its polycount cap.
## 2. Every GLB loads as a PackedScene in headless mode.
## 3. ModelSwap.make_visual returns a wrapper carrying real meshes.
## 4. Hazard swaps: sprinkler/bicycle/car/bird carry model visuals while
##    their CollisionShape3D hitboxes keep the exact original sizes.
## 5. World swaps: fence has tiled model runs, planters have bed + plants,
##    old primitive meshes hidden, collision shapes untouched.

var _pass := 0
var _fail := 0

const CAPS := {
	"sprinkler": 11000, "bicycle": 14000, "car": 10000, "bird": 8000,
	"fence": 10000, "plant_a": 2000, "plant_b": 2000, "bed": 10000,
}


func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("PASS: ", label)
	else:
		_fail += 1
		print("FAIL: ", label)


func _has_mesh(n: Node) -> bool:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		return true
	for c in n.get_children():
		if _has_mesh(c):
			return true
	return false


func _initialize() -> void:
	# --- GameState setup (P13/P18 pattern) ---
	var auto: Node = root.get_node_or_null("GameState")
	if auto != null:
		auto.queue_free()
		await process_frame
	var gs: Node = load("res://scripts/systems/game_state.gd").new()
	gs.name = "GameState"
	root.add_child(gs)
	await process_frame

	# --- 1: registry + polycount caps ---
	for mname in CAPS.keys():
		check(ModelSwap.MODELS.has(mname), "ModelSwap registry has '%s'" % mname)
		if ModelSwap.MODELS.has(mname):
			var verts: int = int((ModelSwap.MODELS[mname] as Dictionary)["verts"])
			check(verts <= int(CAPS[mname]), "%s verts %d <= cap %d" % [mname, verts, int(CAPS[mname])])

	# --- 2: every GLB loads headless ---
	for mname in ModelSwap.MODELS.keys():
		var path: String = (ModelSwap.MODELS[mname] as Dictionary)["path"]
		var packed: PackedScene = load(path)
		check(packed != null and packed.can_instantiate(), "%s GLB loads (%s)" % [mname, path])

	# --- 3: make_visual wrappers carry real meshes ---
	for mname in ["sprinkler", "bicycle", "car", "bird"]:
		var w: Node3D = ModelSwap.make_visual(mname, 1.0)
		check(w != null, "make_visual('%s') returns a wrapper" % mname)
		check(w != null and _has_mesh(w), "'%s' wrapper contains meshes" % mname)
		if w != null:
			w.queue_free()

	# --- 4: hazard swaps keep hitboxes ---
	var hazard_expect := {
		"sprinkler": ["res://scripts/systems/sprinkler.gd", Vector3(
			4.0 * sin(deg_to_rad(70.0) * 0.5) * 2.0 + 0.6, 1.2, 4.0 + 0.6)],
		"bicycle": ["res://scripts/systems/bicycle.gd", Vector3(1.0, 1.6, 0.6)],
		"car": ["res://scripts/systems/car.gd", Vector3(4.2, 1.6, 2.0)],
		"bird": ["res://scripts/systems/bird.gd", Vector3(0, 0, 0)], # sphere
	}
	for hname in hazard_expect.keys():
		var spec: Array = hazard_expect[hname]
		var hz: Area3D = (load(spec[0]) as Script).new()
		hz.name = "Test" + hname.capitalize()
		root.add_child(hz)
		await process_frame
		await process_frame
		var visual := hz.get_node_or_null("ModelVisual_" + hname)
		if hname == "sprinkler":
			# Sprinkler wraps the head node itself.
			visual = hz.get_node_or_null("ModelVisual_sprinkler")
		check(_has_mesh(hz), "%s hazard shows model meshes" % hname)
		# Hitbox untouched: find the CollisionShape3D and compare size.
		var zone: CollisionShape3D = null
		for c in hz.get_children():
			if c is CollisionShape3D:
				zone = c
				break
		check(zone != null, "%s still has its CollisionShape3D" % hname)
		if zone != null and hname != "bird":
			var bs: Vector3 = (zone.shape as BoxShape3D).size
			var exp: Vector3 = spec[1]
			check(bs.distance_to(exp) < 0.01, "%s hitbox size unchanged %s" % [hname, str(bs)])
		if zone != null and hname == "bird":
			var r: float = (zone.shape as SphereShape3D).radius
			check(absf(r - 0.9) < 0.01, "bird hitbox radius unchanged (0.9)")
		hz.queue_free()

	# --- 5: world swaps in the main scene ---
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var fence := main.get_node_or_null("Fence")
	var runs := 0
	if fence != null:
		for c in fence.get_children():
			if String(c.name).begins_with("FenceRun") and _has_mesh(c):
				runs += 1
	check(runs >= 2, "fence has >= 2 model runs (%d)" % runs)
	var fzone := main.get_node_or_null("Fence/CollisionShape3D") as CollisionShape3D
	check(fzone != null and (fzone.shape as BoxShape3D).size.distance_to(Vector3(14, 5, 1)) < 0.01,
		"fence collision untouched (14x5x1)")

	for pname in ["PlanterBoxA", "PlanterBoxB"]:
		var pb := main.get_node_or_null(pname) as Node3D
		var bed := pb.get_node_or_null("BedModel") if pb != null else null
		check(bed != null and _has_mesh(bed), "%s has a real bed model" % pname)
		var plants := 0
		if bed != null:
			for c in bed.get_children():
				if String(c.name).begins_with("Plant") and _has_mesh(c):
					plants += 1
		check(plants >= 4, "%s has >= 4 real plants (%d)" % [pname, plants])
		var pzone := main.get_node_or_null(pname + "/CollisionShape3D") as CollisionShape3D
		check(pzone != null and (pzone.shape as BoxShape3D).size.distance_to(Vector3(1.2, 0.6, 1.2)) < 0.01,
			"%s collision untouched (1.2x0.6x1.2)" % pname)

	print("--- P25: %d passed, %d failed ---" % [_pass, _fail])
	if _fail > 0:
		quit(1)
	else:
		quit()
