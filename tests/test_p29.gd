extends SceneTree
## Gecko Run — P29 tests: real-world environment pass.
##
## 1. Model registry has sneaker/grass_tuft/bush_round/bush_tall/flowers/tree.
## 2. GrassField node exists in main.tscn and builds a MultiMesh (or the
##    quad fallback) with the expected instance count.
## 3. Footstep shoe is a model wrapper when the sneaker GLB loads.
## 4. Sprinkler spray is a GPUParticles3D that emits only during ACTIVE.
## 5. Route-edge bushes/flowers use merged GLB meshes (or quad fallbacks).

var _checks: Array = []


func _check(label: String, ok: bool) -> void:
	_checks.append([label, ok])


func _finish() -> void:
	var failed := 0
	for c in _checks:
		print(("PASS " if c[1] else "FAIL ") + c[0])
		if not c[1]:
			failed += 1
	print("P29_RESULT: %d/%d passed" % [_checks.size() - failed, _checks.size()])
	quit(1 if failed > 0 else 0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## P29 (environment half): count nodes under `root` whose name starts with
## `prefix`, searching the whole subtree.
func _count_prefix(n: Node, prefix: String) -> int:
	var count := 0
	var stack: Array = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if String(cur.name).begins_with(prefix):
			count += 1
		for c in cur.get_children():
			stack.append(c)
	return count


## P29 (environment half): PBR rule — normal + ORM maps, all <= 2048 px
## (Tripo's standard texture size; fine for the desktop web target).
func _check_pbr_env(wrapper: Node3D, label: String) -> void:
	var mats := {}
	var stack: Array = [wrapper]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var mesh := mi.mesh
			if mesh != null:
				for si in mesh.get_surface_count():
					var m := mi.get_active_material(si) as StandardMaterial3D
					if m != null:
						mats[m] = true
		for c in n.get_children():
			stack.append(c)
	_check("%s has PBR materials" % label, mats.size() > 0)
	for m in mats.keys():
		var sm := m as StandardMaterial3D
		_check("%s normal map present" % label, sm.normal_texture != null)
		_check("%s roughness (ORM) map present" % label, sm.metallic_texture != null)
		for t in [sm.normal_texture, sm.metallic_texture, sm.albedo_texture]:
			if t != null:
				_check("%s texture <= 2048px (%dx%d)" % [label, t.get_width(), t.get_height()],
					t.get_width() <= 2048 and t.get_height() <= 2048)


## P29 (environment half): worst metallic across a model wrapper's surfaces.
func _max_metallic(n: Node) -> float:
	var worst := 0.0
	var stack: Array = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			var mi := cur as MeshInstance3D
			var mesh := mi.mesh
			if mesh != null:
				for si in mesh.get_surface_count():
					var m := mi.get_active_material(si) as StandardMaterial3D
					if m != null:
						worst = maxf(worst, m.metallic)
		for c in cur.get_children():
			stack.append(c)
	return worst


func _run() -> void:
	# 1. Registry.
	for key in ["sneaker", "grass_tuft", "bush_round", "bush_tall",
			"flowers", "tree"]:
		_check("registry has " + key, ModelSwap.MODELS.has(key))
	# 2. Merge helper on a known-good existing model.
	var merged := ModelSwap.merge_model_mesh("dog", 60000)
	_check("merge_model_mesh returns ArrayMesh", merged is ArrayMesh)
	_check("merged dog has surfaces",
		merged != null and merged.get_surface_count() > 0)
	# 3. Full scene: GrassField builds, footstep has a shoe, sprinkler sprays.
	var gs: Node = root.get_node_or_null("GameState")
	gs.set("profile_path", "user://cap_p29.json")
	gs.call("_load_profile")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(10)
	var gf := main.get_node_or_null("GrassField")
	_check("GrassField node in main.tscn", gf != null)
	await _frames(10) # Deferred adds land.
	var field_found := false
	var field_count := 0
	for c in main.get_children():
		if c is MultiMeshInstance3D and (c.name == "GrassField"
				or c.name == "GrassFieldMesh" or c.name == "GrassFieldFallback"):
			field_found = true
			field_count = (c as MultiMeshInstance3D).multimesh.instance_count
	_check("grass field MultiMesh built", field_found)
	_check("grass instance count >= 9000 (3 cards/tuft)", field_count >= 9000)
	# Bushes: two variants or the quad fallback.
	var bush_variants := 0
	var shrub_fallback := false
	for c in main.get_children():
		if c is MultiMeshInstance3D:
			if String(c.name).begins_with("RouteEdgeBush"):
				bush_variants += 1
			if c.name == "RouteEdgeShrubs":
				shrub_fallback = true
	_check("two bush variants or quad fallback",
		bush_variants == 2 or shrub_fallback)
	# Clouds.
	var clouds := 0
	for c in main.get_children():
		if c is MeshInstance3D and String(c.name).begins_with("Cloud"):
			clouds += 1
	_check("six billboard clouds", clouds == 6)

	# --- P29 (environment half): wet driveway on Backyard Dash ---
	var wet := main.get_node_or_null("WetDriveway")
	_check("WetDriveway node exists on Backyard Dash", wet != null)
	if wet != null:
		var slab := wet.get_node_or_null("DrivewaySlab") as MeshInstance3D
		_check("DrivewaySlab present", slab != null)
		if slab != null:
			var smat := slab.material_override as StandardMaterial3D
			_check("slab glossy (roughness %.2f <= 0.15)" % (smat.roughness if smat != null else -1.0),
				smat != null and smat.roughness <= 0.15)
		var puddles := _count_prefix(wet, "Puddle")
		_check(">= 6 puddles on the driveway (%d)" % puddles, puddles >= 6)
		var p1 := wet.get_node_or_null("Puddle1") as MeshInstance3D
		if p1 != null:
			var pmat := p1.material_override as StandardMaterial3D
			_check("puddle near-mirror (roughness %.3f <= 0.08)" % (pmat.roughness if pmat != null else -1.0),
				pmat != null and pmat.roughness <= 0.08)
			# P29: Godot 4 has no specular property — the baked sky gradient
			# on a near-zero-roughness dielectric IS the mirror reflection.
			_check("puddle has baked sky-gradient reflection texture",
				pmat != null and pmat.albedo_texture != null)

	# --- P29 (environment half): Tripo palm + hibiscus models ---
	for mname in ["palm", "hibiscus"]:
		_check("ModelSwap has '%s'" % mname, ModelSwap.MODELS.has(mname))
		if ModelSwap.MODELS.has(mname):
			var spec: Dictionary = ModelSwap.MODELS[mname]
			var verts: int = int(spec["verts"])
			_check("%s verts %d <= 10000" % [mname, verts], verts <= 10000)
			var packed: PackedScene = load(String(spec["path"]))
			_check("%s GLB loads headless" % mname,
				packed != null and packed.can_instantiate())
	var palm_vis: Node3D = ModelSwap.make_visual("palm", 3.4)
	if palm_vis != null:
		_check_pbr_env(palm_vis, "palm")
		palm_vis.queue_free()
	else:
		_check("palm make_visual returns a wrapper", false)
	var hib_vis: Node3D = ModelSwap.make_visual("hibiscus", 1.15)
	if hib_vis != null:
		_check_pbr_env(hib_vis, "hibiscus")
		hib_vis.queue_free()
	else:
		_check("hibiscus make_visual returns a wrapper", false)

	# --- P29 (environment half): planting density along the route ---
	_check(">= 6 palm sentinels (%d)" % _count_prefix(main, "PalmPlant"),
		_count_prefix(main, "PalmPlant") >= 6)
	_check(">= 10 hibiscus bushes (%d)" % _count_prefix(main, "Hibiscus"),
		_count_prefix(main, "Hibiscus") >= 10)
	_check(">= 12 extra edge plants (%d)" % _count_prefix(main, "EdgePlant"),
		_count_prefix(main, "EdgePlant") >= 12)

	# --- P29 (environment half): warm low sun ---
	var sun := main.get_node_or_null("Sun") as DirectionalLight3D
	_check("Sun exists", sun != null)
	if sun != null:
		var sc: Color = sun.light_color
		_check("sun warm (1.0, <=0.75, <=0.5): %s" % str(sc),
			is_equal_approx(sc.r, 1.0) and sc.g <= 0.75 and sc.b <= 0.5)
		var elev: float = sun.rotation_degrees.x
		_check("sun low (elevation -26..-16 deg): %.1f" % elev,
			elev <= -16.0 and elev >= -26.0)
		_check("sun shadows on", sun.shadow_enabled)

	# --- P29 (environment half): pollen small / sparse / subtle / additive ---
	var rig := get_first_node_in_group("camera_rig") as Node3D
	_check("camera rig found", rig != null)
	var pollen: GPUParticles3D = null
	if rig != null:
		pollen = rig.get_node_or_null("Pollen") as GPUParticles3D
	_check("Pollen particles exist", pollen != null)
	if pollen != null:
		_check("pollen sparse (amount %d <= 20)" % pollen.amount, pollen.amount <= 20)
		var pquad := pollen.draw_pass_1 as QuadMesh
		_check("pollen small (quad %.3f m <= 0.02)" % (pquad.size.x if pquad != null else -1.0),
			pquad != null and pquad.size.x <= 0.02)
		var ppmat := pquad.material as StandardMaterial3D if pquad != null else null
		_check("pollen additive",
			ppmat != null and ppmat.blend_mode == BaseMaterial3D.BLEND_MODE_ADD)
		_check("pollen subtle (alpha %.2f <= 0.2)" % (ppmat.albedo_color.a if ppmat != null else -1.0),
			ppmat != null and ppmat.albedo_color.a <= 0.2)

	# --- P29 (environment half): swaying grass tufts ---
	var tufts := main.get_node_or_null("GrassTufts") as MultiMeshInstance3D
	_check("GrassTufts exists", tufts != null)
	if tufts != null:
		var tmat: Material = tufts.multimesh.mesh.material
		_check("grass tufts use a sway ShaderMaterial", tmat is ShaderMaterial)

	# --- P29 (environment half): SHIELD label no longer clips ---
	var ui: Node = get_first_node_in_group("game_ui")
	_check("GameUI found", ui != null)
	if ui != null:
		var buttons: Dictionary = ui.get("_ability_buttons")
		var slot := buttons.get("shield") as Button
		_check("shield slot exists", slot != null)
		if slot != null:
			var sfont := slot.get_theme_font("font")
			var ssize := slot.get_theme_font_size("font_size")
			var tw := sfont.get_string_size("SHIELD",
				HORIZONTAL_ALIGNMENT_LEFT, -1, ssize).x
			var budget: float = slot.custom_minimum_size.x - 36.0 # badge 32 + margin
			_check("SHIELD text %.0fpx fits slot clear of badge (budget %.0f)" % [tw, budget],
				tw <= budget)

	# --- P29 (environment half): blue-artifact regression (tamed metals) ---
	for mname in ModelSwap.MODELS.keys():
		var vis: Node3D = ModelSwap.make_visual(String(mname), 1.0)
		if vis == null:
			continue # Missing GLB: the fallback path, not a metal bug.
		var worst := _max_metallic(vis)
		_check("%s tamed (metallic %.2f <= 0.25)" % [mname, worst], worst <= 0.25)
		vis.queue_free()

	# --- P29 (environment half): Fence Line route unchanged ---
	var fence_data: Resource = (load("res://scripts/systems/level_data_fenceline.gd") as Script).new()
	var fence_spawns: int = (fence_data.get("spawns") as Array).size()
	_check("Fence Line spawn count unchanged (66, got %d)" % fence_spawns,
		fence_spawns == 66)
	# Footstep shoe.
	var fe: CanvasLayer = main.get_node("FrontendUI")
	(fe.get("_name_input") as LineEdit).text = "T29"
	fe.call("_on_name_confirmed", false)
	await _frames(5)
	fe.call("start_map", "florida_backyard")
	await _frames(10)
	var level: Node = main.get_node("Level")
	var fs: Node = null
	for h in level.get_children():
		if h.get_script() != null and String(h.get_script().resource_path).ends_with("footstep.gd"):
			fs = h
			break
	_check("footstep hazard exists", fs != null)
	if fs != null:
		var shoe: Node = fs.get("_shoe")
		_check("shoe node built", shoe != null)
		var is_wrapper: bool = shoe != null and shoe.name == "SneakerShoe"
		var has_glb: bool = ResourceLoader.exists("res://assets/models/sneaker.glb")
		_check("sneaker model used when GLB present", (not has_glb) or is_wrapper)
	# Sprinkler spray.
	var sp: Node = null
	for h in level.get_children():
		if h.get_script() != null and String(h.get_script().resource_path).ends_with("sprinkler.gd"):
			sp = h
			break
	_check("sprinkler hazard exists", sp != null)
	if sp != null:
		var spray: GPUParticles3D = sp.get("_spray")
		_check("spray is GPUParticles3D", spray is GPUParticles3D)
		_check("spray idle-off initially", spray != null and not spray.emitting)
	# --- P29 (environment half): no wet segment on Fence Line ---
	main.queue_free()
	await _frames(6)
	gs.set("current_map_id", "florida_fenceline")
	var main2: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main2)
	await _frames(12) # Deferred adds land.
	_check("no WetDriveway on Fence Line",
		main2.get_node_or_null("WetDriveway") == null)
	gs.set("current_map_id", "florida_backyard")
	main2.queue_free()
	_finish()


func _init() -> void:
	call_deferred("_run")
