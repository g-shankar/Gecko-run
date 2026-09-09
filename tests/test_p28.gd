extends SceneTree
## Gecko Run — P28 tests: dog + lawn mower deck hazards.
##
## 1. Level.HAZARD_SCRIPTS registers "dog" and "mower".
## 2. Backyard Dash spawns both (dogs near the end, z -270..-340); Fence Line has neither.
## 3. Models: registry, <= 10k verts, GLB loads, PBR (normal + ORM textures <= 1024).
## 4. Dog: stays IDLE while the gecko is far; IDLE->TELEGRAPH->ACTIVE order;
##    bark "!" visible during TELEGRAPH; hitbox dead during TELEGRAPH, live in ACTIVE.
## 5. Dog near-miss registers via GameState.
## 6. Mower: warning stripes + engine cue on TELEGRAPH; crosses the lane in ACTIVE;
##    hitbox live only while crossing.

var _checks: Array = []
var _dog_hits: int = 0 ## player_hit count for the dog ACTIVE test.
var _mower_hits: int = 0 ## player_hit count for the mower ACTIVE test.


func _on_dog_hit() -> void:
	_dog_hits += 1


func _on_mower_hit() -> void:
	_mower_hits += 1


func _check(label: String, ok: bool) -> void:
	_checks.append([label, ok])


func _finish() -> void:
	var failed := 0
	for c in _checks:
		print(("PASS " if c[1] else "FAIL ") + c[0])
		if not c[1]:
			failed += 1
	print("P28_RESULT: %d/%d passed" % [_checks.size() - failed, _checks.size()])
	quit(1 if failed > 0 else 0)


func _wait_phase(hz: Node, phase: int, timeout_s: float) -> bool:
	var t := 0.0
	while t < timeout_s:
		await physics_frame
		t += 1.0 / 60.0
		if int(hz.get("phase")) == phase:
			return true
	return false


func _has_mesh(n: Node) -> bool:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		return true
	for c in n.get_children():
		if _has_mesh(c):
			return true
	return false


## PBR: every surface material carries a normal map and an ORM
## (metallic/roughness) map, all <= 1024 px — the P28.5 rule.
func _check_pbr(wrapper: Node3D, label: String) -> void:
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
				_check("%s texture <= 1024px (%dx%d)" % [label, t.get_width(), t.get_height()],
					t.get_width() <= 1024 and t.get_height() <= 1024)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# --- 1: registration ---
	_check("Level registers 'dog'", Level.HAZARD_SCRIPTS.has("dog"))
	_check("Level registers 'mower'", Level.HAZARD_SCRIPTS.has("mower"))
	var dog_script: Script = load(Level.HAZARD_SCRIPTS.get("dog", ""))
	var mower_script: Script = load(Level.HAZARD_SCRIPTS.get("mower", ""))
	_check("dog script loads", dog_script != null)
	_check("mower script loads", mower_script != null)

	# --- 2: route data ---
	var data: Resource = (load("res://scripts/systems/level_data.gd") as Script).new()
	var dogs := 0
	var mowers := 0
	var dogs_near_end := true
	for spawn in (data.get("spawns") as Array):
		var t: String = String(spawn["type"])
		var z: float = (spawn["pos"] as Vector3).z
		if t == "dog":
			dogs += 1
			if z > -270.0 or z < -340.0:
				dogs_near_end = false
		if t == "mower":
			mowers += 1
	_check("Backyard Dash spawns >= 1 dog (%d)" % dogs, dogs >= 1)
	_check("dogs sit near the end (z -270..-340)", dogs_near_end)
	_check("Backyard Dash spawns >= 1 mower (%d)" % mowers, mowers >= 1)
	var fence_data: Resource = (load("res://scripts/systems/level_data_fenceline.gd") as Script).new()
	var fence_clean := true
	for spawn in (fence_data.get("spawns") as Array):
		var t: String = String(spawn["type"])
		if t == "dog" or t == "mower":
			fence_clean = false
	_check("Fence Line spawns contain neither dog nor mower", fence_clean)

	# --- 3: models ---
	for mname in ["dog", "mower"]:
		_check("ModelSwap has '%s'" % mname, ModelSwap.MODELS.has(mname))
		if ModelSwap.MODELS.has(mname):
			var verts: int = int((ModelSwap.MODELS[mname] as Dictionary)["verts"])
			_check("%s verts %d <= 10000" % [mname, verts], verts <= 10000)
			var path: String = (ModelSwap.MODELS[mname] as Dictionary)["path"]
			var packed: PackedScene = load(path)
			_check("%s GLB loads headless" % mname, packed != null and packed.can_instantiate())
	var dog_vis: Node3D = ModelSwap.make_visual("dog", 1.3)
	_check("dog make_visual returns wrapper with meshes", dog_vis != null and _has_mesh(dog_vis))
	if dog_vis != null:
		_check_pbr(dog_vis, "dog")
		dog_vis.queue_free()
	var mower_vis: Node3D = ModelSwap.make_visual("mower", 1.7)
	_check("mower make_visual returns wrapper with meshes", mower_vis != null and _has_mesh(mower_vis))
	if mower_vis != null:
		_check_pbr(mower_vis, "mower")
		mower_vis.queue_free()

	# --- scene setup ---
	var packed_main: PackedScene = load("res://scenes/main.tscn")
	var main: Node = packed_main.instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	var auto_gs: Node = root.get_node_or_null("GameState")
	if auto_gs != null:
		auto_gs.queue_free()
	await process_frame
	var gecko: Node = main.get_node("Gecko")
	var level: Node = main.get_node("Level")
	gecko.set("run_speed", 0.0) # Frozen: deterministic tests.
	var dog: Node = level.get_node("Dog")
	var dog_b: Node = level.get_node("DogB")
	var mower: Node = level.get_node("Mower")
	_check("Level spawns Dog", dog != null)
	_check("Level spawns DogB", dog_b != null)
	_check("Level spawns Mower", mower != null)
	if dog == null or mower == null:
		_finish()
		return
	# Hitbox sizes (gameplay numbers, must not drift).
	var dzone: CollisionShape3D = null
	for c in dog.get_children():
		if c is CollisionShape3D:
			dzone = c
	_check("dog hitbox is 1.3x1.1x1.7",
		dzone != null and (dzone.shape as BoxShape3D).size.distance_to(Vector3(1.3, 1.1, 1.7)) < 0.01)
	var mzone: CollisionShape3D = null
	for c in mower.get_children():
		if c is CollisionShape3D:
			mzone = c
	_check("mower hitbox is 1.6x1.1x1.2",
		mzone != null and (mzone.shape as BoxShape3D).size.distance_to(Vector3(1.6, 1.1, 1.2)) < 0.01)

	# --- 4: dog trigger + phase order + bark + hitbox discipline ---
	gecko.global_position = Vector3(0, 0.2, -200) # Far: 83 m from Dog.
	for i in 90:
		await physics_frame
	_check("dog stays IDLE while gecko is far", int(dog.get("phase")) == 0)
	gecko.global_position = Vector3(2.0, 0.2, -276.0) # 7.3 m: inside trigger.
	var saw_telegraph := false
	var active_before_telegraph := false
	var reached_active := false
	for i in 600:
		await physics_frame
		var p: int = int(dog.get("phase"))
		if p == 1:
			saw_telegraph = true
		if p == 2:
			reached_active = true
			if not saw_telegraph:
				active_before_telegraph = true
			break
	_check("dog enters TELEGRAPH when gecko closes in", saw_telegraph)
	_check("dog reaches ACTIVE", reached_active)
	_check("no ACTIVE before TELEGRAPH (warning always first)", not active_before_telegraph)
	# Catch the next telegraph for the bark + dead-hitbox checks.
	_check("dog re-enters TELEGRAPH (looper)", await _wait_phase(dog, 1, 8.0))
	var bark: Label3D = dog.get("_bark")
	_check("bark '!' popup visible during TELEGRAPH", bark != null and bark.visible)
	# Hitbox dead during TELEGRAPH: park the gecko on the dog, count hits.
	# (Counter is a member: GDScript lambdas capture locals by value.)
	_dog_hits = 0
	dog.player_hit.connect(_on_dog_hit)
	gecko.global_position = dog.global_position + Vector3(0, 0.2, 0)
	for i in 40:
		await physics_frame
		if int(dog.get("phase")) != 1:
			break
	_check("no hit during TELEGRAPH (hits=%d)" % _dog_hits, _dog_hits == 0)
	# ACTIVE with the gecko in the lunge path: the hit lands. Shield the
	# gecko so the hit is absorbed (no death/respawn moves it mid-test) —
	# player_hit still fires, which is what we count.
	gecko.call("give_shield")
	_check("dog reaches ACTIVE with gecko in the zone", await _wait_phase(dog, 2, 8.0))
	for i in 40:
		await physics_frame
		if _dog_hits > 0:
			break
	_check("dog hits during ACTIVE (hits=%d)" % _dog_hits, _dog_hits > 0)

	# --- 5: near-miss on DogB ---
	var gs2: Node = (load("res://scripts/systems/game_state.gd") as Script).new()
	gs2.name = "GameState"
	root.add_child(gs2)
	gs2.call("start_run")
	if not dog_b.get("near_miss").is_connected(Callable(gs2, "register_near_miss")):
		dog_b.connect("near_miss", Callable(gs2, "register_near_miss"))
	# Park the gecko just behind DogB's rest spot: inside the 10 m trigger
	# and within near-miss range (2.5 m) when the lunge starts, but the lunge
	# travels +z (away), so the 1.3-wide hitbox never touches the gecko.
	# Shielded: a stray hit can't kill the gecko (and move it) mid-test.
	gecko.call("give_shield")
	gecko.global_position = Vector3(-4.0, 0.2, -329.5)
	var nm_before: int = int(gs2.get("near_miss_count"))
	_check("DogB enters ACTIVE", await _wait_phase(dog_b, 2, 10.0))
	_check("DogB finishes ACTIVE", await _wait_phase(dog_b, 3, 10.0))
	await process_frame
	await process_frame
	_check("near-miss registered (count %d -> %d)" % [nm_before, int(gs2.get("near_miss_count"))],
		int(gs2.get("near_miss_count")) > nm_before)

	# --- 6: mower telegraph, crossing, hitbox discipline ---
	# Freeze the neighboring sprinkler so it can't kill the parked gecko.
	var sprinkler: Node = null
	for c in level.get_children():
		if String(c.name).begins_with("Sprinkler"):
			var cz: float = (c as Node3D).position.z
			if absf(cz - -302.0) < 2.0:
				sprinkler = c
	if sprinkler != null:
		sprinkler.set_physics_process(false)
	mower.set("idle_time", 0.3)
	mower.set("warn_time", 0.6)
	mower.set("active_time", 1.0)
	mower.set("recovery_time", 0.4)
	mower.call("_enter_phase", 0) # Restart IDLE with the test timings.
	var stripes: MeshInstance3D = mower.get("_stripes")
	var engine: AudioStreamPlayer3D = mower.get_node_or_null("Engine")
	_check("mower has warning-stripes decal", stripes != null)
	_check("stripes hidden in IDLE", stripes != null and not stripes.visible)
	_check("mower has engine sound node", engine != null)
	_check("engine has a loopable stream", engine != null and engine.stream != null)
	_check("mower enters TELEGRAPH", await _wait_phase(mower, 1, 8.0))
	_check("stripes visible during TELEGRAPH", stripes != null and stripes.visible)
	_check("engine buzzing during TELEGRAPH", engine != null and engine.playing)
	# Hitbox dead during TELEGRAPH: gecko sits at the crossing center.
	# Shielded so the ACTIVE hit doesn't relocate the gecko mid-test.
	_mower_hits = 0
	mower.player_hit.connect(_on_mower_hit)
	gecko.call("give_shield")
	gecko.global_position = Vector3(0, 0.2, -303.0)
	for i in 30:
		await physics_frame
		if int(mower.get("phase")) != 1:
			break
	_check("mower: no hit during TELEGRAPH (hits=%d)" % _mower_hits, _mower_hits == 0)
	_check("mower enters ACTIVE", await _wait_phase(mower, 2, 8.0))
	var mx0: float = mower.position.x
	for i in 30:
		await physics_frame
	var mx1: float = mower.position.x
	_check("mower crosses the lane (|dx|=%.1f)" % absf(mx1 - mx0), absf(mx1 - mx0) > 2.0)
	for i in 60:
		await physics_frame
		if _mower_hits > 0:
			break
	_check("mower hits while crossing (hits=%d)" % _mower_hits, _mower_hits > 0)
	_check("mower enters RECOVERY", await _wait_phase(mower, 3, 8.0))
	_check("stripes hidden after the pass", stripes != null and not stripes.visible)
	_check("engine stops after the pass", engine != null and not engine.playing)

	_finish()
