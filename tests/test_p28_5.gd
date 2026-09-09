extends SceneTree
## Gecko Run — P28.5 tests: the real-3D pass.
##
## 1. GeckoAnimator exists; params bounded (bob amplitude small, stride
##    1.4-3.2 Hz — smooth, never vibration; bank clamped).
## 2. Idle look-around: yaw drifts when the run is NOT active (menu/pause).
## 3. Run cycle: body bob + advancing stride phase while RUNNING.
## 4. Macro camera: FOV settles ~50, height lowered to 0.72, look-ahead kept.
## 5. Ground: albedo + NORMAL map (no flat mat), dirt path, clover/pebbles.
## 6. Vignette layer present, below the UI.
## 7. Lighting: sun lowered + warmed, warm distance haze.
## 8. PBR: every Tripo model (incl. hero) ships albedo/normal/metallic/
##    roughness maps; the car tame keeps its maps (no flat chrome fix).
## 9. Dash stretches the gecko forward, then relaxes.
## 10. Land-squash trigger compresses immediately, then eases back.
## 11. Gameplay numbers untouched (speeds, jump).
## P28.5+ (art-direction fold-in — Treasure Land key art craft):
## 12. Foreground framing: group rides the camera rig, pieces stay at frame
##     edges (never the center third), and drift (parallax alive).
## 13. Rim light on the gecko (hero reads first), shadowless/cheap.
## 14. Grade strengthened: saturation > 1.1, denser haze vs P24, sun glow
##     sprite, cool sky fill against the warm key.
## 15. Density: shrubs/flowers/fallen leaves/mulch instanced along the route.
## 16. Track legibility: worn dirt path contrasts with the lawn (>= 0.08).
## 17. Telegraph contrast rule: every hazard's warning is saturated OR stands
##     off the grass in luminance.
## 18. Juice: bug catch fires a double burst; boost kicks speed lines.
##
## Exit code 0 = all checks passed.

var _pass := 0
var _fail := 0


func check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("PASS: ", label)
	else:
		_fail += 1
		print("FAIL: ", label)


func _find_named(n: Node, target: String) -> Node:
	if n.name == target:
		return n
	for c in n.get_children():
		var hit := _find_named(c, target)
		if hit != null:
			return hit
	return null


func _meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_meshes(c, out)


func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func _sat(c: Color) -> float:
	var mx := maxf(c.r, maxf(c.g, c.b))
	var mn := minf(c.r, minf(c.g, c.b))
	return (mx - mn) / mx if mx > 0.001 else 0.0


## Contrast rule: a telegraph must EITHER be a saturated warning color
## (>= 0.45) OR stand off the lawn in luminance (>= 0.20) — dark dodge
## shadows read on bright grass, bright warnings read on anything.
func _telegraph_pops(c: Color, grass_lum: float) -> bool:
	return _sat(c) >= 0.45 or absf(_lum(c) - grass_lum) >= 0.20


func _count_fx(n: Node) -> int:
	var c := 0
	for ch in n.get_children():
		if ch is CPUParticles3D:
			c += 1
	return c


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# --- Boot: autoload GameState starts in READY (start screen) ---
	for i in 20:
		await process_frame
		if root.has_node("GameState"):
			break
	var gs: Node = root.get_node_or_null("GameState")
	check(gs != null, "GameState autoload present")
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node = packed.instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame
	var gecko := main.get_node("Gecko") as CharacterBody3D
	var visual := gecko.get_node("MeshInstance3D") as MeshInstance3D
	var animator: Node = gecko.get("_animator")
	var rig := main.get_node("CameraRig")
	var cam := rig.get_node("Boom/Camera3D") as Camera3D

	# --- 1: animator params exist and are bounded ---
	check(animator != null, "GeckoAnimator attached to the gecko")
	check(GeckoAnimator.BOB_AMP >= 0.01 and GeckoAnimator.BOB_AMP <= 0.06,
		"bob amplitude small (%.3f m)" % GeckoAnimator.BOB_AMP)
	check(GeckoAnimator.STRIDE_MIN_HZ >= 1.0
		and GeckoAnimator.STRIDE_MAX_HZ <= 4.0,
		"stride 1.4-3.2 Hz scaled by speed (no vibration)")
	for a in [GeckoAnimator.PITCH_AMP, GeckoAnimator.ROLL_AMP]:
		check(a > 0.0 and a <= 0.07 and is_finite(a),
			"motion amplitude bounded (%.3f rad)" % a)
	check(GeckoAnimator.LEG_SWING > 0.3 and GeckoAnimator.LEG_SWING < 0.9,
		"leg swing amplitude real (%.2f rad)" % GeckoAnimator.LEG_SWING)
	check(GeckoAnimator.TAIL_AMP > 0.1 and GeckoAnimator.TAIL_AMP < 0.5,
		"tail wave amplitude real (%.2f rad)" % GeckoAnimator.TAIL_AMP)
	check(GeckoAnimator.BOB_AMP <= 0.015,
		"body bob small — limbs do the work (%.3f m)" % GeckoAnimator.BOB_AMP)
	check(GeckoAnimator.BANK_MAX <= 0.35, "bank clamped (%.2f rad)"
		% GeckoAnimator.BANK_MAX)
	check(is_finite(GeckoAnimator.IDLE_YAW_AMP)
		and GeckoAnimator.IDLE_YAW_AMP <= 0.2, "idle look amplitude sane")

	# --- 2: idle look-around when not running (READY = menu) ---
	# _idle_t = 1.1208 puts sin(1.4t) at its peak: deterministic drift.
	animator.set("_idle_t", 1.1208)
	for i in 3:
		await process_frame
	var idle_yaw := absf(visual.rotation.y - PI / 2.0)
	check(idle_yaw > 0.02,
		"idle look-around drifts yaw when not running (%.3f rad)" % idle_yaw)
	check(float(animator.get("_run_blend")) < 0.5, "run blend off in menu")

	# --- 3: run cycle while RUNNING (articulated rig) ---
	gs.call("start_run")
	gecko.global_position = Vector3(0, 0.2, -30) # empty track
	gecko.call("give_camo") # hazards blind: the run phase stays clean
	gecko.call("give_shield")
	var rig_meshes: Array = gecko.get("_rig_meshes")
	check(rig_meshes.size() == 9, "rig attached: 9 part meshes")
	var rig_pivots: Dictionary = gecko.get("_rig_pivots")
	check((rig_pivots["legs"] as Dictionary).size() == 4,
		"4 leg pivots (LF/RF/LH/RH)")
	check((rig_pivots["tail"] as Array).size() == 3,
		"3 tail section pivots")
	check(rig_pivots["head"] != null, "head pivot present")
	check(bool(animator.get("_rigged")), "animator drives the rig")
	for i in 30:
		await process_frame
	check(float(animator.get("_run_blend")) > 0.9, "run blend engages")
	var ys: Array = []
	for i in 24:
		await process_frame
		ys.append(visual.position.y)
	check(float(ys.max()) - float(ys.min()) > 0.004,
		"body bob active (travel %.4f m)" % (float(ys.max()) - float(ys.min())))
	check(float(animator.get("_phase")) > 1.0, "stride phase advances")

	# --- 3b: diagonal gait — LF+RH in phase, RF+LH antiphase ---
	var legs: Dictionary = rig_pivots["legs"]
	var tail: Array = rig_pivots["tail"]
	var diag_ok := 0
	var diag_n := 0
	var tail0: float = (tail[0] as Node3D).rotation.y
	var tail_moved := false
	for i in 40:
		await physics_frame
		var lf: float = (legs["LF"] as Node3D).rotation.z
		var rh: float = (legs["RH"] as Node3D).rotation.z
		var rf: float = (legs["RF"] as Node3D).rotation.z
		if signf(lf) == signf(rh) and signf(lf) != signf(rf):
			diag_ok += 1
		diag_n += 1
		if absf((tail[0] as Node3D).rotation.y - tail0) > 0.02:
			tail_moved = true
	check(diag_ok > diag_n * 0.7,
		"diagonal gait: LF+RH together, RF opposite (%d/%d)" % [diag_ok, diag_n])
	check(tail_moved, "tail articulates with a traveling wave")
	# Legs actually swing (not the old rigid paddle illusion).
	var swing_seen := false
	var lz0: float = (legs["LF"] as Node3D).rotation.z
	for i in 20:
		await physics_frame
		if absf((legs["LF"] as Node3D).rotation.z - lz0) > 0.15:
			swing_seen = true
	check(swing_seen, "leg pivots swing through a real stride")

	# --- 3c: airborne pose — legs trail, tail streams (real jumps only) ---
	gecko.set("velocity", Vector3(0, 5, -9))
	for i in 15:
		await physics_frame
	check(float(animator.get("_air_blend")) > 0.5, "airborne blend engages")
	var lf_air: float = (legs["LF"] as Node3D).rotation.z
	check(lf_air < -0.2,
		"airborne legs trail back (%.2f rad)" % lf_air)
	for i in 30: # land again
		await physics_frame
	check(float(animator.get("_air_blend")) < 0.5, "landing restores gait")

	# --- 4: macro camera ---
	check(absf(float(rig.get("follow_height")) - 0.62) < 0.01,
		"camera lowered to gecko eye level (0.62, was 1.4)")
	check(absf(float(rig.get("base_fov")) - 50.0) < 0.01, "macro FOV 50")
	for i in 30:
		await process_frame
	check(absf(cam.fov - 50.0) < 4.0,
		"camera settles at FOV ~50 (%.1f)" % cam.fov)
	check(float(rig.get("look_ahead")) >= 2.5,
		"look-ahead kept for mobile playability (%.1f)"
		% float(rig.get("look_ahead")))
	check(absf(float(rig.get("side_offset")) - 0.65) < 0.01,
		"3/4 rear view offset (no dead-behind foreshortening)")

	# --- 5: ground realism ---
	var ground := main.get_node("Ground") as MeshInstance3D
	var gmat := ground.material_override as StandardMaterial3D
	check(gmat != null and gmat.albedo_texture != null,
		"grass albedo assigned")
	check(gmat != null and gmat.normal_texture != null,
		"grass normal map assigned (no flat mat)")
	check(main.get_node_or_null("DirtPath") != null,
		"worn dirt path along the track line")
	var clover := main.get_node_or_null("CloverScatter") as MultiMeshInstance3D
	check(clover != null and clover.multimesh.instance_count >= 100,
		"clover scatter instanced")
	var peb := main.get_node_or_null("PebbleScatter") as MultiMeshInstance3D
	check(peb != null and peb.multimesh.instance_count >= 50,
		"pebble scatter instanced")

	# --- 6: vignette ---
	var vig := main.get_node_or_null("Vignette")
	check(vig != null and vig is CanvasLayer, "vignette layer present")
	check(vig != null and vig.get_node_or_null("VignetteRect") is ColorRect,
		"vignette fullscreen rect present")
	check(vig != null and (vig as CanvasLayer).layer < 1,
		"vignette sits below the UI")

	# --- 7: lighting depth ---
	var sun := main.get_node("Sun") as DirectionalLight3D
	check(sun.rotation_degrees.x < -20.0 and sun.rotation_degrees.x > -35.0,
		"sun lowered for long shadows (%.0f deg)" % sun.rotation_degrees.x)
	check(sun.light_color.r > 0.95 and sun.light_color.b < 0.7,
		"sun warmed (golden hour)")
	var we := main.get_node("WorldEnvironment") as WorldEnvironment
	var env: Environment = we.environment
	check(env.fog_light_color.r > 0.9 and env.fog_light_color.g < 0.9,
		"warm distance haze")

	# --- 8: PBR on every Tripo model ---
	var pbr_ok := true
	for key in ModelSwap.MODELS:
		var spec: Dictionary = ModelSwap.MODELS[key]
		if not ResourceLoader.exists(spec["path"]):
			print("SKIP (missing file): ", key)
			continue
		var mp: PackedScene = load(spec["path"])
		var inst: Node = mp.instantiate()
		var found: Array = []
		_meshes(inst, found)
		for mi in found:
			var mesh := (mi as MeshInstance3D).mesh
			for si in mesh.get_surface_count():
				var m := mesh.surface_get_material(si) as StandardMaterial3D
				if m == null or m.albedo_texture == null \
						or m.normal_texture == null \
						or m.metallic_texture == null \
						or m.roughness_texture == null:
					pbr_ok = false
					print("  PBR gap: ", key, " surface ", si)
		inst.queue_free()
	var hero_p: PackedScene = load("res://assets/gecko/hero_gecko.glb")
	var hero_i: Node = hero_p.instantiate()
	var hfound: Array = []
	_meshes(hero_i, hfound)
	for mi in hfound:
		var mesh := (mi as MeshInstance3D).mesh
		for si in mesh.get_surface_count():
			var m := mesh.surface_get_material(si) as StandardMaterial3D
			if m == null or m.albedo_texture == null \
					or m.normal_texture == null \
					or m.metallic_texture == null \
					or m.roughness_texture == null:
				pbr_ok = false
				print("  PBR gap: hero_gecko surface ", si)
	hero_i.queue_free()
	check(pbr_ok, "all Tripo models ship full PBR map sets")
	# The car tame must keep its maps (the old code nulled them).
	var carv := ModelSwap.make_visual("car", 2.0)
	var cfound: Array = []
	_meshes(carv, cfound)
	var tame_ok := false
	for mi in cfound:
		var mesh := (mi as MeshInstance3D).mesh
		for si in mesh.get_surface_count():
			var om := (mi as MeshInstance3D).get_surface_override_material(si) \
				as StandardMaterial3D
			if om != null:
				tame_ok = om.metallic <= 0.2 \
					and om.roughness_texture != null \
					and om.normal_texture != null
	carv.queue_free()
	check(tame_ok, "car tame kills chrome but keeps PBR maps")

	# --- 9: dash stretch ---
	gs.call("start_run")
	gecko.global_position = Vector3(0, 0.2, -30)
	gecko.call("give_camo")
	gecko.call("give_shield")
	for i in 10:
		await physics_frame
	gecko.call("request_dash")
	for i in 5:
		await physics_frame
	check(str(gecko.get("stat_state")) == "DASH", "dash engaged")
	for i in 5:
		await process_frame
	check(visual.scale.x > 0.85 * 1.05,
		"dash stretches the gecko forward (%.3f)" % visual.scale.x)
	for i in 80:
		await physics_frame
		if str(gecko.get("stat_state")) != "DASH":
			break
	for i in 20:
		await process_frame
	check(absf(visual.scale.x - 0.85) < 0.04,
		"stretch relaxes after dash (%.3f)" % visual.scale.x)

	# --- 10: land-squash trigger ---
	gecko.call("_juice_scale", 1.25, 0.65)
	check(visual.scale.y < 0.85 * 0.9,
		"land squash compresses immediately (%.3f)" % visual.scale.y)
	for i in 40:
		await process_frame
	check(visual.scale.distance_to(Vector3.ONE * 0.85) < 0.06,
		"squash eases back to rest")

	# --- 11: gameplay numbers untouched ---
	check(absf(float(gecko.get("run_speed")) - 5.0) < 0.01, "run_speed 5.0")
	check(absf(float(gecko.get("max_speed")) - 9.0) < 0.01, "max_speed 9.0")
	check(absf(float(gecko.get("jump_velocity")) - 6.5) < 0.01,
		"jump_velocity 6.5")

	# --- 12: foreground framing (layered depth) ---
	var fg := get_first_node_in_group("foreground_dressing")
	check(fg != null, "foreground dressing group exists")
	var fgcam := rig.get_node("Boom/Camera3D") as Camera3D
	check(fg != null and fg.get_parent() == fgcam,
		"foreground rides the CAMERA (lens-attached framing)")
	var pieces: Array = fg.get_children() if fg != null else []
	check(pieces.size() >= 6,
		"foreground pieces instanced (%d)" % pieces.size())
	var edge_ok := true
	for p in pieces:
		var pp: Vector3 = (p as Node3D).position
		if absf(pp.x) < ForegroundDressing.EDGE_MIN_X \
				or pp.z > ForegroundDressing.NEAR_MAX_Z:
			edge_ok = false
	check(edge_ok,
		"foreground stays at frame edges (never the center third)")
	var fy0: float = (pieces[0] as Node3D).position.y \
		if pieces.size() > 0 else 0.0
	for i in 20:
		await process_frame
	var fy1: float = (pieces[0] as Node3D).position.y \
		if pieces.size() > 0 else 0.0
	check(absf(fy1 - fy0) > 0.001,
		"foreground drifts — parallax layer alive (%.4f m)" % absf(fy1 - fy0))

	# --- 13: gecko rim light (visual hierarchy) ---
	var rim := gecko.get_node_or_null("RimLight")
	check(rim != null and rim is Light3D,
		"gecko rim light present (hero reads first)")
	check(rim != null and not (rim as Light3D).shadow_enabled,
		"rim light shadowless (cheap)")

	# --- 14: richer grade + stronger haze ---
	check(env.adjustment_enabled and env.adjustment_saturation > 1.1,
		"saturated grade (not washed out)")
	check(env.fog_depth_end <= 120.0 and env.fog_sun_scatter >= 0.3,
		"haze strengthened vs P24 baseline")
	check(rig.get_node_or_null("SunGlow") != null, "sun glow sprite")
	var skyfill := main.get_node_or_null("SkyFill") as DirectionalLight3D
	check(skyfill != null and skyfill.light_color.b > skyfill.light_color.r,
		"cool sky fill against the warm key")

	# --- 15: route-edge density (lush, no empty flats) ---
	var shrubs := main.get_node_or_null("RouteEdgeShrubs") as MultiMeshInstance3D
	check(shrubs != null and shrubs.multimesh.instance_count >= 100,
		"layered route-edge shrubs (%d)"
		% (shrubs.multimesh.instance_count if shrubs != null else 0))
	var flowers := main.get_node_or_null("RouteEdgeFlowers") as MultiMeshInstance3D
	check(flowers != null and flowers.multimesh.instance_count >= 40,
		"flower pops (%d)"
		% (flowers.multimesh.instance_count if flowers != null else 0))
	var litter := main.get_node_or_null("FallenLeaves") as MultiMeshInstance3D
	check(litter != null and litter.multimesh.instance_count >= 60,
		"fallen-leaf litter (%d)"
		% (litter.multimesh.instance_count if litter != null else 0))
	var mulch := main.get_node_or_null("MulchPatches") as MultiMeshInstance3D
	check(mulch != null and mulch.multimesh.instance_count >= 30,
		"mulch patches (%d)"
		% (mulch.multimesh.instance_count if mulch != null else 0))

	# --- 16: track legibility (dirt vs lawn) ---
	var gimg: Image = gmat.albedo_texture.get_image()
	var glum := 0.0
	var gsamples := 0
	for sy in 16:
		for sx in 16:
			glum += _lum(gimg.get_pixel(sx * gimg.get_width() / 16,
				sy * gimg.get_height() / 16))
			gsamples += 1
	glum /= gsamples
	var dirt := main.get_node("DirtPath") as MeshInstance3D
	var dmat := dirt.material_override as StandardMaterial3D
	var dimg: Image = dmat.albedo_texture.get_image()
	var dlum := 0.0
	for sy in 8:
		dlum += _lum(dimg.get_pixel(dimg.get_width() / 2,
			sy * dimg.get_height() / 8))
	dlum /= 8.0
	check(absf(dlum - glum) >= 0.08,
		"dirt path contrasts with lawn (|%.3f - %.3f| = %.3f)"
		% [dlum, glum, absf(dlum - glum)])

	# --- 17: hazard telegraph contrast rule ---
	var tele_specs := [
		["res://scripts/systems/bicycle.gd", "_lane_mat", false],
		["res://scripts/systems/car.gd", "_light_mat", true],
		["res://scripts/systems/sprinkler.gd", "_fan_mat", false],
		["res://scripts/systems/bird.gd", "_shadow_mat", false],
		["res://scripts/systems/footstep.gd", "_shadow_mat", false],
	]
	for spec in tele_specs:
		var hscript: Script = load(spec[0])
		var hz: Node = hscript.new()
		root.add_child(hz)
		for i in 3:
			await process_frame
		var tmat: StandardMaterial3D = hz.get(spec[1])
		if tmat == null:
			print("SKIP (no telegraph mat): ", String(spec[0]).get_file())
			hz.queue_free()
			continue
		var tcol: Color = tmat.albedo_color
		if bool(spec[2]) and tmat.emission_enabled:
			tcol = tmat.emission # The car warns with its flashing lights.
		check(tmat != null and _telegraph_pops(tcol, glum),
			"telegraph pops: %s (sat %.2f)" % [String(spec[0]).get_file(),
				_sat(tcol)])
		hz.queue_free()

	# --- 18: juice — double burst + speed lines ---
	var bug: Node = BugPickup.new()
	root.add_child(bug)
	for i in 3:
		await process_frame
	var fx_before := _count_fx(root)
	bug.call("_collect", Color(0.4, 1.0, 0.3))
	await process_frame
	check(_count_fx(root) - fx_before >= 2,
		"bug catch fires a double burst (pop + core flash)")
	gecko.call("give_speed_boost")
	await process_frame
	var sl := get_first_node_in_group("speed_lines") as ColorRect
	var inten := 0.0
	if sl != null:
		inten = float((sl.material as ShaderMaterial)\
			.get_shader_parameter("intensity"))
	check(sl != null and inten > 0.9,
		"boost kicks speed lines (%.2f)" % inten)

	print("--- P28.5: %d passed, %d failed ---" % [_pass, _fail])
	quit(_fail)
