extends Node3D
## Gecko Run — P26 atmosphere polish.
##
## Late-afternoon Florida: a lower warm sun, gentle depth haze that stays
## off the blue sky, drifting pollen motes that follow the camera, and
## swaying grass tufts along the track edges. Everything is one draw call
## per system (particles + one MultiMesh) — no per-pixel effects, mobile-safe.
##
## Runs AFTER BackyardArt (tree order) and re-grades its environment/sun.

const POLLEN_COUNT := 18 ## P29: was 28 — sparse, small, additive, subtle.
const TUFT_COUNT := 260


func _ready() -> void:
	add_to_group("atmosphere") ## P28.5+: the gecko kicks speed lines here.
	_grade_environment()
	_warm_the_sun()
	_add_sky_fill() ## P28.5+: cool fill against the warm key.
	_add_sun_glow() ## P28.5+: subtle sun disc sprite.
	_spawn_pollen()
	_plant_grass_tufts()
	_attach_foreground() ## P28.5+: parallax framing on the camera rig.
	_add_vignette() ## P28.5: subtle photographic vignette (+ speed lines).


## P28.5+: speed-line intensity decays after a boost kick. Brief by design.
## Tracked in a member (get_shader_parameter returns null until set).
var _speed_intensity := 0.0


func _process(delta: float) -> void:
	if _speed_mat != null and _speed_intensity > 0.0:
		_speed_intensity = maxf(0.0, _speed_intensity - delta * 1.4)
		_speed_mat.set_shader_parameter("intensity", _speed_intensity)


## P28.5+: called by the gecko on give_speed_boost. One flash, then decay.
func kick_speed_lines() -> void:
	_speed_intensity = 1.0
	if _speed_mat != null:
		_speed_mat.set_shader_parameter("intensity", 1.0)


## P28.5: faint vignette — a fullscreen ColorRect with a radial-darkening
## canvas shader on its own layer BELOW the UI (layer 0 < GameUI's 1), so
## the HUD stays crisp. Cheap: one canvas draw, no 3D cost.
## P28.5+: also hosts the SpeedLines overlay (radial streaks on boost).
var _speed_mat: ShaderMaterial


func _add_vignette() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Vignette"
	layer.layer = 0
	var rect := ColorRect.new()
	rect.name = "VignetteRect"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform float strength : hint_range(0.0, 1.0) = 0.30;
void fragment() {
	vec2 c = (UV - vec2(0.5)) * vec2(1.3, 1.0);
	float d = length(c);
	float v = smoothstep(0.42, 0.95, d) * strength;
	COLOR = vec4(0.03, 0.02, 0.015, v);
}
"""
	var smat := ShaderMaterial.new()
	smat.shader = shader
	rect.material = smat
	layer.add_child(rect)
	# P28.5+: speed lines — radial streaks from screen center, flashed by
	# kick_speed_lines() on boost and decayed in _process. Brief by design.
	var sl := ColorRect.new()
	sl.name = "SpeedLines"
	sl.set_anchors_preset(Control.PRESET_FULL_RECT)
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sl_shader := Shader.new()
	sl_shader.code = """
shader_type canvas_item;
uniform float intensity = 0.0;
float hash(float n) { return fract(sin(n) * 43758.5453123); }
void fragment() {
	vec2 uv = UV - vec2(0.5);
	float r = length(uv * vec2(1.45, 1.0));
	float ang = atan(uv.y, uv.x);
	float spokes = floor(ang * 7.6394);
	float rnd = hash(spokes + 1.0);
	float band = fract(ang * 7.6394 + rnd);
	float streak = smoothstep(0.55, 1.0,
		sin(band * 6.28318 + r * 36.0 - TIME * 26.0) * 0.5 + 0.5);
	float mask = smoothstep(0.18, 0.5, r) * (1.0 - smoothstep(0.62, 1.0, r));
	float gate = step(0.45, rnd);
	float a = streak * mask * gate * intensity * 0.55;
	COLOR = vec4(1.0, 0.96, 0.88, a);
}
"""
	_speed_mat = ShaderMaterial.new()
	_speed_mat.shader = sl_shader
	sl.material = _speed_mat
	sl.add_to_group("speed_lines")
	layer.add_child(sl)
	# Deferred: Atmosphere._ready runs while Main is still setting up
	# children (same pattern as the grass tufts).
	get_parent().call_deferred("add_child", layer)


## Re-grade the WorldEnvironment for late afternoon — IN PLACE. BackyardArt
## owns the blue sky; we only warm the light, add gentle depth haze (kept
## off the sky so the horizon never goes dusty), and a touch of glow.
func _grade_environment() -> void:
	var we := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we == null or we.environment == null:
		return
	var env := we.environment
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	# No bloom: it turned the pollen motes into giant orbs on the web build.
	env.glow_enabled = false
	# P28.5+: richer grade — saturated and contrasty, delicious not washed.
	# Adjustments are supported on the GL Compatibility renderer.
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.02
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.18
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.97, 0.82, 0.62) ## P28.5+: deeper golden haze.
	env.fog_sun_scatter = 0.35 ## P28.5+: stronger glow toward the low sun.
	env.fog_depth_begin = 25.0 ## P28.5+: haze starts closer (was 30).
	env.fog_depth_end = 115.0 ## P28.5+: denser aerial perspective (was 140).
	env.fog_depth_curve = 1.2
	env.fog_sky_affect = 0.0


## P28.5: golden-hour sun — lower (long soft shadows), warmer. Shadow
## distance capped at 60 m: crisp near the gecko (the macro view), cheap
## everywhere else. Atlas size lives in project.godot (2048, GL-safe).
## P29: pushed warmer + lower for the late-afternoon key-art grade —
## longer raking shadows, hotter rim on the gecko's flank.
func _warm_the_sun() -> void:
	var sun := get_parent().get_node_or_null("Sun") as DirectionalLight3D
	if sun == null:
		return
	sun.light_color = Color(1.0, 0.68, 0.40)
	sun.light_energy = 1.75
	# P28.5: yaw -65 rakes the low sun ACROSS the track (not from behind the
	# camera) — the gecko's flank gets modeled light/shade and shadows
	# stretch diagonally, the golden-hour look from the key art.
	# P29: elevation -28 -> -21 (lower sun, longer shadows).
	sun.rotation_degrees = Vector3(-21, -68, 0)
	sun.directional_shadow_max_distance = 60.0
	sun.shadow_enabled = true
	_add_bounce_fill()


## P28.5: soft warm bounce from below-front — lifts pitch-black undersides
## (pergola slab, fence, car underbody, the gecko's belly) that the low
## macro camera now sees. No shadows: one cheap fill light.
func _add_bounce_fill() -> void:
	var bounce := DirectionalLight3D.new()
	bounce.name = "BounceFill"
	bounce.light_color = Color(1.0, 0.86, 0.70)
	bounce.light_energy = 0.35
	bounce.rotation_degrees = Vector3(28, -65, 0)
	bounce.shadow_enabled = false
	get_parent().call_deferred("add_child", bounce)


## P28.5+: cool sky fill against the warm golden key — the reference's warm
## light / cool shadow contrast. Cheap: one more shadowless directional.
func _add_sky_fill() -> void:
	var fill := DirectionalLight3D.new()
	fill.name = "SkyFill"
	fill.light_color = Color(0.55, 0.68, 0.95)
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(-55, 115, 0)
	fill.shadow_enabled = false
	get_parent().call_deferred("add_child", fill)


## P28.5+: a subtle sun disc — one billboarded radial-gradient quad riding
## the camera rig, parked in the sky along the sun's direction. Unshaded,
## fog-exempt, no shadows: one draw call.
func _add_sun_glow() -> void:
	var rig := get_tree().get_first_node_in_group("camera_rig") as Node3D
	if rig == null:
		return
	var glow := MeshInstance3D.new()
	glow.name = "SunGlow"
	var quad := QuadMesh.new()
	quad.size = Vector2(16, 16) ## P28.5+: soft presence, not a disc.
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = _make_glow_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.disable_fog = true
	quad.material = mat
	glow.mesh = quad
	var sun_basis := Basis.from_euler(
		Vector3(deg_to_rad(-28.0), deg_to_rad(-65.0), 0.0))
	glow.position = -(sun_basis.z) * 95.0 + Vector3(0, 6, 0)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig.add_child(glow)


## Warm radial gradient: hot core fading to transparent.
func _make_glow_texture() -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, true, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var dx := (float(x) / n - 0.5) * 2.0
			var dy := (float(y) / n - 0.5) * 2.0
			var d := sqrt(dx * dx + dy * dy)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * a * 0.55 # Soft cubic falloff: glow, not a disc.
			img.set_pixel(x, y, Color(1.0, 0.88, 0.66, a))
	return ImageTexture.create_from_image(img)


## P28.5+: the parallax foreground rides the CAMERA (lens-attached), so the
## framing sits exactly at the frame's top corners whatever the camera does.
func _attach_foreground() -> void:
	var rig := get_tree().get_first_node_in_group("camera_rig") as Node3D
	if rig == null:
		return
	var cam := rig.get_node_or_null("Boom/Camera3D")
	if cam == null:
		return
	var fg := ForegroundDressing.new()
	fg.name = "ForegroundDressing"
	fg.add_to_group("foreground_dressing")
	cam.add_child(fg)


## Golden pollen motes drifting around the camera — they ride along for the
## whole route because they are parented to the camera rig, not the world.
## P29: the old motes read as oversized yellow balls in screenshots, so
## they are now small, soft, sparse, and ADDITIVE — a faint shimmer in the
## light, not floating orbs. (The golden collectible orbs are bug pickups;
## those became spinning coins in bug_pickup.gd.)
func _spawn_pollen() -> void:
	var rig := get_tree().get_first_node_in_group("camera_rig") as Node3D
	if rig == null:
		return
	var p := GPUParticles3D.new()
	p.name = "Pollen"
	p.amount = POLLEN_COUNT
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.explosiveness = 0.0
	p.randomness = 0.6
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(8, 3, 8)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.45
	pm.gravity = Vector3.ZERO
	pm.damping_min = 0.0
	pm.damping_max = 0.2
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	pm.color = Color(1.0, 0.95, 0.75, 0.16) ## P29: was 0.3 — subtle.
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.014, 0.014) ## P29: was 0.02 — small.
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.95, 0.75, 0.16)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD ## P29: additive shimmer.
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.disable_fog = true
	quad.material = mat
	p.draw_pass_1 = quad
	rig.add_child(p)


## Swaying grass tufts edging the track — one MultiMesh, one draw call.
## The vertex shader sways each blade by world position + time, so there is
## no per-instance CPU work after setup.
func _plant_grass_tufts() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.55, 0.4)
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 col_base : source_color = vec4(0.22, 0.46, 0.18, 1.0);
uniform vec4 col_tip : source_color = vec4(0.52, 0.72, 0.28, 1.0);
void vertex() {
	float phase = MODEL_MATRIX[3].x * 1.7 + MODEL_MATRIX[3].z * 2.3;
	float sway = sin(TIME * 2.2 + phase) * 0.10 * (1.0 - UV.y);
	VERTEX.x += sway;
	VERTEX.z += sway * 0.6;
}
void fragment() {
	float half_w = mix(0.05, 0.5, UV.y);
	if (abs(UV.x - 0.5) > half_w) { discard; }
	ALBEDO = mix(col_tip.rgb, col_base.rgb, UV.y);
}
"""
	var smat := ShaderMaterial.new()
	smat.shader = shader
	quad.material = smat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = TUFT_COUNT
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260909
	for i in TUFT_COUNT:
		var side := 1.0 if i % 2 == 0 else -1.0
		var x := side * rng.randf_range(2.4, 5.0)
		var z := rng.randf_range(-360.0, 8.0)
		var t := Transform3D(
			Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(
				Vector3(rng.randf_range(0.7, 1.3), rng.randf_range(0.7, 1.4), 1.0)),
			Vector3(x, 0.2, z))
		mm.set_instance_transform(i, t)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "GrassTufts"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Deferred: Atmosphere._ready runs while Main is still propagating _ready.
	get_parent().call_deferred("add_child", mmi)
