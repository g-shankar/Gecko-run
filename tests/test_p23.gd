extends SceneTree
## Gecko Run — P23 tests: hero gecko model + 5 selectable skins.
##
## 1. Decimated hero GLB exists and is mobile-sized (<= 10k verts).
## 2. Five skins defined, distinct names and distinct tints.
## 3. apply_skin tints the material and keeps the PBR textures.
## 4. Skin choice persists across save/load (user://gecko_run.cfg).
## 5. set_skin clamps out-of-range indices.
## 6. Player scene keeps CharacterBody3D + capsule collision + controller
##    after the mesh swap, and the visual is the hero (not the capsule).
## 7. The hero visual faces -Z (rotation.y ~= PI/2).

var _pass := 0
var _fail := 0


func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("PASS: ", label)
	else:
		_fail += 1
		print("FAIL: ", label)


func _glb_vert_count(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	var data := f.get_buffer(f.get_length())
	f.close()
	if data.size() < 20:
		return -1
	var clen := data.decode_u32(12)
	var js := data.slice(20, 20 + clen).get_string_from_utf8()
	var gltf: Dictionary = JSON.parse_string(js)
	if gltf.is_empty():
		return -1
	var total := 0
	for m in gltf["meshes"]:
		for p in m["primitives"]:
			var ai: int = p["attributes"]["POSITION"]
			total += int(gltf["accessors"][ai]["count"])
	return total


func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var found := _find_mesh(c)
		if found != null:
			return found
	return null


func _initialize() -> void:
	# --- 1: decimated mesh is mobile-sized ---
	var verts := _glb_vert_count("res://assets/gecko/hero_gecko.glb")
	check(verts > 0, "hero_gecko.glb parses (verts=%d)" % verts)
	check(verts <= 10000, "hero mesh <= 10k verts (verts=%d)" % verts)

	# --- 2: five distinct skins ---
	check(GeckoSkins.count() == 5, "5 skins defined")
	var names := {}
	var tints := {}
	for i in GeckoSkins.count():
		names[GeckoSkins.skin_name(i)] = true
		tints[GeckoSkins.skin_tint(i).to_html()] = true
	check(names.size() == 5, "5 distinct skin names")
	check(tints.size() == 5, "5 distinct skin tints")

	# --- 3: apply_skin tints, keeps textures ---
	var hero_ps: PackedScene = load("res://assets/gecko/hero_gecko.glb")
	var hero_mi := _find_mesh(hero_ps.instantiate())
	var probe := MeshInstance3D.new()
	probe.mesh = hero_mi.mesh
	hero_mi.queue_free()
	GeckoSkins.apply_skin(probe, 0)
	var m0 := probe.get_surface_override_material(0) as StandardMaterial3D
	check(m0 != null, "apply_skin creates an override material")
	check(m0.albedo_color.is_equal_approx(Color(1, 1, 1)), "skin 0 = Classic Green (untinted)")
	GeckoSkins.apply_skin(probe, 2)
	var m2 := probe.get_surface_override_material(0) as StandardMaterial3D
	check(m2 == m0, "re-apply reuses the cached material (no leak)")
	check(m2.albedo_color.is_equal_approx(GeckoSkins.skin_tint(2)), "skin 2 tint applied (Blue Stripe)")
	check(m2.albedo_texture != null, "tint keeps the PBR textures")
	probe.queue_free()

	# --- GameState setup (P13/P18 pattern) ---
	var auto: Node = root.get_node_or_null("GameState")
	if auto != null:
		auto.queue_free()
		await process_frame
	var gs: Node = load("res://scripts/systems/game_state.gd").new()
	gs.name = "GameState"
	root.add_child(gs)
	await process_frame

	# --- 4: persistence (P26: versioned JSON profile replaced the cfg) ---
	gs.set_skin(3)
	check(int(gs.selected_skin) == 3, "set_skin(3) sticks")
	var pf := FileAccess.open("user://gecko_run_profile.json", FileAccess.READ)
	check(pf != null, "profile written")
	var pdata: Dictionary = JSON.parse_string(pf.get_as_text())
	pf.close()
	check(int(pdata.get("selected_skin", -1)) == 3, "selected_skin persisted as 3")

	# --- 5: clamping ---
	gs.set_skin(99)
	check(int(gs.selected_skin) == 4, "set_skin(99) clamps to 4")
	gs.set_skin(-5)
	check(int(gs.selected_skin) == 0, "set_skin(-5) clamps to 0")

	# --- 6+7: player scene after the mesh swap ---
	gs.set_skin(2) # Blue Stripe applied at _ready.
	var gecko_ps: PackedScene = load("res://scenes/player/gecko.tscn")
	var gecko: CharacterBody3D = gecko_ps.instantiate()
	root.add_child(gecko)
	await process_frame
	check(gecko is CharacterBody3D, "player is still a CharacterBody3D")
	var col := gecko.get_node_or_null("CollisionShape3D")
	check(col != null and col.shape is CapsuleShape3D, "capsule collision untouched")
	check(gecko.get_script() != null, "gecko_controller still attached")
	var visual := gecko.get_node_or_null("MeshInstance3D") as MeshInstance3D
	check(visual != null, "visual node keeps its name")
	check(not (visual.mesh is CapsuleMesh), "capsule mesh replaced")
	check(visual.mesh.get_surface_count() > 0, "hero mesh assigned")
	var hero_verts := 0
	for s in visual.mesh.get_surface_count():
		hero_verts += visual.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size()
	check(hero_verts > 5000, "visual carries the hero mesh (verts=%d)" % hero_verts)
	check(absf(visual.rotation.y - PI / 2.0) < 0.01, "hero faces -Z (rot.y ~= PI/2)")
	var skin_mat := visual.get_surface_override_material(0) as StandardMaterial3D
	check(skin_mat != null and skin_mat.albedo_color.is_equal_approx(GeckoSkins.skin_tint(2)),
		"persisted skin applied at run start (Blue Stripe)")
	gecko.queue_free()

	print("--- P23: %d passed, %d failed ---" % [_pass, _fail])
	quit(_fail)
