extends Node3D
## Gecko Run — P26 atmosphere polish.
##
## Late-afternoon Florida: a lower warm sun, gentle depth haze that stays
## off the blue sky, drifting pollen motes that follow the camera, and
## swaying grass tufts along the track edges. Everything is one draw call
## per system (particles + one MultiMesh) — no per-pixel effects, mobile-safe.
##
## Runs AFTER BackyardArt (tree order) and re-grades its environment/sun.

const POLLEN_COUNT := 28
const TUFT_COUNT := 260


func _ready() -> void:
	_grade_environment()
	_warm_the_sun()
	_spawn_pollen()
	_plant_grass_tufts()


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
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.78, 0.84, 0.92)
	env.fog_sun_scatter = 0.1
	env.fog_depth_begin = 30.0
	env.fog_depth_end = 140.0
	env.fog_depth_curve = 1.2
	env.fog_sky_affect = 0.0


## Drop the sun lower and warm it: long late-afternoon shadows.
func _warm_the_sun() -> void:
	var sun := get_parent().get_node_or_null("Sun") as DirectionalLight3D
	if sun == null:
		return
	sun.light_color = Color(1.0, 0.88, 0.68)
	sun.light_energy = 1.5
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.shadow_enabled = true


## Golden pollen motes drifting around the camera — they ride along for the
## whole route because they are parented to the camera rig, not the world.
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
	pm.color = Color(1.0, 0.95, 0.75, 0.3)
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.02, 0.02)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.95, 0.75, 0.3)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
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
