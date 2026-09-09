extends Node3D
class_name GrassField
## P29: real-3D grass — thousands of instanced Tripo grass tufts with a
## wind-sway vertex shader, one draw call. This is the single biggest
## "flat world" killer: at gecko height the lawn becomes geometry.
##
## VISUALS ONLY. Builds once at scene start; never touches gameplay.

const TUFT_COUNT := 3200      ## Tufts along the route edges (kept off the dirt path).
const TUFT_PATCH := 260       ## Extra tufts clustered in lawn patches.
const MAX_VERTS := 12000      ## Safety cap for the merged tuft mesh.

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 20260911
	# Blade cards are the grass: the Tripo tuft (293k verts) can never be
	# instanced, so the merged-mesh path is retired for grass.
	_build_blade_cards()


## Wrap an imported StandardMaterial3D's albedo texture in a wind-sway
## spatial shader. Blades bend with height (UV.y is unreliable on Tripo
## geometry, so sway scales with local Y over the tuft height).
static func _make_sway_material(src: Material) -> ShaderMaterial:
	var albedo: Texture2D = null
	var tint := Color(0.45, 0.75, 0.3)
	if src is StandardMaterial3D:
		var sm := src as StandardMaterial3D
		albedo = sm.albedo_texture
		if albedo == null:
			tint = sm.albedo_color
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float has_albedo = 0.0;
uniform vec4 tint : source_color = vec4(0.45, 0.75, 0.3, 1.0);
uniform float tuft_height = 0.25;
void vertex() {
	float h = clamp(VERTEX.y / tuft_height, 0.0, 1.0);
	float ph = MODEL_MATRIX[3].x * 1.7 + MODEL_MATRIX[3].z * 2.3;
	float sway = sin(TIME * 2.2 + ph) * 0.045 + sin(TIME * 3.7 + ph * 1.3) * 0.02;
	VERTEX.x += sway * h;
	VERTEX.z += cos(TIME * 1.7 + ph) * 0.03 * h;
}
void fragment() {
	vec4 c = vec4(tint.rgb, 1.0);
	if (has_albedo > 0.5) {
		vec4 t = texture(albedo_tex, UV);
		if (t.a < 0.5) discard;
		c.rgb = t.rgb * tint.rgb * 2.0;
	}
	ALBEDO = c.rgb;
	ROUGHNESS = 0.95;
}
"""
	var smat := ShaderMaterial.new()
	smat.shader = sh
	if albedo != null:
		smat.set_shader_parameter("albedo_tex", albedo)
		smat.set_shader_parameter("has_albedo", 1.0)
	smat.set_shader_parameter("tint", Color(tint.r, tint.g, tint.b, 1.0))
	var spec: Dictionary = ModelSwap.MODELS["grass_tuft"]
	var size: Vector3 = spec["size"]
	smat.set_shader_parameter("tuft_height", maxf(size.y, 0.1))
	return smat


## Scatter tufts: dense along both route edges, sparse on the open lawn,
## never on the dirt path (|x| < 1.8). Two MultiMeshes, one material set.
## P29: real 3D grass via crossed blade-cards — the industry-standard
## approach. Three alpha-cutout quads per tuft with painted blades and the
## wind-sway shader: 18 tris per tuft, ~62k tris for the whole lawn.
## (The Tripo tuft GLB is 293k verts — unusable for instancing.)
func _build_field(_mesh: ArrayMesh) -> void:
	_build_blade_cards()


## Back-compat: old call path when the tuft GLB is present but tiny.
## Unused in practice — blade cards are always better here.
func _build_quad_fallback() -> void:
	_build_blade_cards()


func _build_blade_cards() -> void:
	var parent := get_parent()
	var blade_tex := _make_blade_texture()
	var blade_mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
uniform sampler2D blade_tex : source_color, filter_linear_mipmap;
void vertex() {
	float h = UV.y;
	float ph = MODEL_MATRIX[3].x * 1.7 + MODEL_MATRIX[3].z * 2.3;
	VERTEX.x += (sin(TIME * 2.2 + ph) * 0.05 + sin(TIME * 3.9 + ph * 1.3) * 0.02) * h;
	VERTEX.z += cos(TIME * 1.6 + ph) * 0.03 * h;
}
void fragment() {
	vec4 t = texture(blade_tex, UV);
	if (t.a < 0.45) discard;
	ALBEDO = t.rgb;
	ROUGHNESS = 0.95;
}
"""
	blade_mat.shader = sh
	blade_mat.set_shader_parameter("blade_tex", blade_tex)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.24, 0.20)
	quad.material = blade_mat
	var cards_per_tuft := 3
	var total := TUFT_COUNT + TUFT_PATCH
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = total * cards_per_tuft
	var idx := 0
	for i in total:
		var x: float
		var z: float
		if i < TUFT_COUNT:
			var side := 1.0 if i % 2 == 0 else -1.0
			x = side * _rng.randf_range(1.9, 11.0)
			z = _rng.randf_range(-488.0, 60.0)
		else:
			var p := (i - TUFT_COUNT) / 10
			var side := 1.0 if p % 2 == 0 else -1.0
			x = side * _rng.randf_range(3.0, 10.0) + _rng.randf_range(-0.8, 0.8)
			z = _rng.randf_range(-480.0, 50.0) + _rng.randf_range(-0.8, 0.8)
		if absf(x) < 1.8:
			x = signf(x if x != 0.0 else 1.0) * 1.8
		var s := _rng.randf_range(0.7, 1.6)
		var base_yaw := _rng.randf() * TAU
		for r in cards_per_tuft:
			var basis := Basis(Vector3.UP, base_yaw + r * PI / 3.0)
			var t := Transform3D(basis.scaled(Vector3(s, s, s)),
				Vector3(x, 0.10 * s, z))
			mm.set_instance_transform(idx, t)
			var tint := _rng.randf_range(0.8, 1.15)
			mm.set_instance_color(idx, Color(tint, tint, tint))
			idx += 1
	var field := MultiMeshInstance3D.new()
	field.name = "GrassFieldMesh" ## P29: "GrassField" is taken by our own
	## container node — same name would auto-rename to @MultiMeshInstance3D@N.
	field.multimesh = mm
	field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.call_deferred("add_child", field)


## Painted grass blades on transparency: 9 tapered blades fanning out,
## light at the tip, dark at the root — the close-up lawn detail.
func _make_blade_texture() -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for b in 9:
		var base_x := 6.0 + b * 6.0 + _rng.randf_range(-2.0, 2.0)
		var lean := _rng.randf_range(-10.0, 10.0)
		var w := _rng.randf_range(2.2, 3.4)
		var h := _rng.randf_range(38.0, 58.0)
		var shade := _rng.randf_range(0.75, 1.1)
		for y in range(int(h)):
			var yy := n - 1 - y
			if yy < 0:
				break
			var taper := 1.0 - float(y) / h
			var cx := base_x + lean * (float(y) / h)
			var half_w := w * 0.5 * (0.35 + 0.65 * taper)
			for xx in range(int(cx - half_w), int(cx + half_w) + 1):
				if xx < 0 or xx >= n:
					continue
				var v := 0.55 + 0.45 * (float(y) / h) # Dark root, light tip.
				img.set_pixel(xx, yy, Color(0.30 * v * shade, 0.58 * v * shade,
					0.20 * v * shade, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
