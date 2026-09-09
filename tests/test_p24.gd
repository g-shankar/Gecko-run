extends SceneTree
## Gecko Run — P24 tests: Florida backyard art pass (visuals only).
##
## 1. BackyardArt node exists in the main scene.
## 2. WorldEnvironment uses a sky background (BG_SKY) with a ProceduralSkyMaterial.
## 3. A DirectionalLight3D sun exists with shadows enabled.
## 4. Ground has a textured grass material_override.
## 5. Fence mesh has a textured wood material_override.
## 6. Planter boxes have wood material, a SoilSlab, and leafy plants
##    (alpha-cutout, no collision).
## 7. Pergola meshes got the wood material.
## 8. Collision is untouched: ground boundary shape, planter/fence box
##    shapes and sizes, planter positions.

var _pass := 0
var _fail := 0


func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("PASS: ", label)
	else:
		_fail += 1
		print("FAIL: ", label)


func _tex_of(mi: MeshInstance3D) -> Texture2D:
	if mi == null:
		return null
	var m := mi.material_override as StandardMaterial3D
	if m == null:
		return null
	return m.albedo_texture


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

	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	# --- 1: BackyardArt node ---
	var art := main.get_node_or_null("BackyardArt")
	check(art != null, "BackyardArt node exists in main scene")
	check(art != null and art.get_script() != null, "BackyardArt has its script attached")

	# --- 2: sky environment ---
	var we := main.get_node_or_null("WorldEnvironment") as WorldEnvironment
	check(we != null and we.environment != null, "WorldEnvironment has an Environment")
	var env_ok := we != null and we.environment != null \
		and we.environment.background_mode == Environment.BG_SKY \
		and we.environment.sky != null \
		and we.environment.sky.sky_material is ProceduralSkyMaterial
	check(env_ok, "environment uses BG_SKY with a ProceduralSkyMaterial")
	check(we.environment.ambient_light_energy > 0.0, "ambient light is on")

	# --- 3: sun with shadows ---
	var sun := main.get_node_or_null("Sun") as DirectionalLight3D
	check(sun != null, "Sun DirectionalLight3D exists")
	check(sun != null and sun.shadow_enabled, "sun has shadows enabled")

	# --- 4: grass ground ---
	var ground := main.get_node_or_null("Ground") as MeshInstance3D
	var grass_tex := _tex_of(ground)
	check(grass_tex != null, "Ground has a textured material_override (grass)")
	check(grass_tex != null and grass_tex.get_size().x >= 256, "grass texture is hi-res enough")

	# --- 5: wooden fence (P25: real model runs; P24 texture is the fallback) ---
	var fence_mi := main.get_node_or_null("Fence/MeshInstance3D") as MeshInstance3D
	var fence_runs := 0
	var fence := main.get_node_or_null("Fence")
	if fence != null:
		for c in fence.get_children():
			if String(c.name).begins_with("FenceRun"):
				fence_runs += 1
	if fence_runs > 0:
		check(fence_runs >= 2, "Fence has tiled model runs (%d)" % fence_runs)
		check(fence_mi == null or not fence_mi.visible, "old fence box hidden under models")
	else:
		check(_tex_of(fence_mi) != null, "Fence mesh has a wood texture (fallback)")

	# --- 6: planted garden beds (P25: real bed + plant models) ---
	for pname in ["PlanterBoxA", "PlanterBoxB"]:
		var pb := main.get_node_or_null(pname) as Node3D
		check(pb != null, "%s still exists" % pname)
		var pmi := main.get_node_or_null(pname + "/MeshInstance3D") as MeshInstance3D
		var bed := pb.get_node_or_null("BedModel") if pb != null else null
		if bed != null:
			check(pmi == null or not pmi.visible, "%s old box hidden under bed model" % pname)
			var plants := 0
			for c in bed.get_children():
				if String(c.name).begins_with("Plant"):
					plants += 1
			check(plants >= 4, "%s has real plant models (%d)" % [pname, plants])
		else:
			# P24 fallback path: wood texture + soil slab + quad plants.
			check(_tex_of(pmi) != null, "%s box has a wood texture" % pname)
			var soil := pb.get_node_or_null("SoilSlab") if pb != null else null
			check(soil is MeshInstance3D, "%s has a SoilSlab" % pname)
			var plants := 0
			var alpha_cutout := false
			if pb != null:
				for c in pb.get_children():
					if String(c.name).begins_with("Plant"):
						plants += 1
						for q in c.get_children():
							if q is MeshInstance3D:
								var qm := (q as MeshInstance3D).mesh as QuadMesh
								var lm := qm.material as StandardMaterial3D if qm != null else null
								if lm != null and lm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
									alpha_cutout = true
			check(plants >= 4, "%s has leafy plants (%d)" % [pname, plants])
			check(alpha_cutout, "%s plants use alpha cutout" % pname)

	# --- 7: pergola re-skinned ---
	var pergola := main.get_node_or_null("Level/Pergola")
	check(pergola != null, "Pergola still built by Level")
	var pergola_textured := false
	if pergola != null:
		for body in pergola.get_children():
			for c in body.get_children():
				if c is MeshInstance3D and _tex_of(c) != null:
					pergola_textured = true
	check(pergola_textured, "Pergola meshes carry the wood texture")

	# --- 8: collision untouched ---
	var gcol := main.get_node_or_null("GroundBody/CollisionShape3D") as CollisionShape3D
	check(gcol != null and gcol.shape is WorldBoundaryShape3D,
		"ground collision still an infinite WorldBoundaryShape3D")
	var pa_col := main.get_node_or_null("PlanterBoxA/CollisionShape3D") as CollisionShape3D
	check(pa_col != null and pa_col.shape is BoxShape3D \
		and (pa_col.shape as BoxShape3D).size.is_equal_approx(Vector3(1.2, 0.6, 1.2)),
		"PlanterBoxA collision box unchanged")
	var pb_col := main.get_node_or_null("PlanterBoxB/CollisionShape3D") as CollisionShape3D
	check(pb_col != null and pb_col.shape is BoxShape3D \
		and (pb_col.shape as BoxShape3D).size.is_equal_approx(Vector3(1.2, 0.6, 1.2)),
		"PlanterBoxB collision box unchanged")
	check(main.get_node_or_null("PlanterBoxA").position.is_equal_approx(Vector3(1.5, 0.3, -6)),
		"PlanterBoxA position unchanged")
	check(main.get_node_or_null("PlanterBoxB").position.is_equal_approx(Vector3(-1.2, 0.3, -14)),
		"PlanterBoxB position unchanged")
	var f_col := main.get_node_or_null("Fence/CollisionShape3D") as CollisionShape3D
	check(f_col != null and f_col.shape is BoxShape3D \
		and (f_col.shape as BoxShape3D).size.is_equal_approx(Vector3(14, 5, 1)),
		"Fence collision box unchanged")
	check(main.get_node("Fence").is_in_group("climbable"), "Fence still climbable")

	main.queue_free()
	print("--- P24: %d passed, %d failed ---" % [_pass, _fail])
	quit(_fail)
