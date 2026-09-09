extends Node3D
class_name BackyardArt
## P24: Florida backyard art pass — VISUALS ONLY.
##
## Runs once at scene start and re-skins the gray-box world: a procedural
## grass lawn, a wooden fence, planted garden beds, a Florida sky, and a
## warm shadow-casting sun. Every texture is generated in code (no binary
## assets, no import-pipeline risk). Collision shapes, spawn positions, and
## gameplay scripts are never touched.

const GRASS_SIZE := 512
const WOOD_SIZE := 256
const SOIL_SIZE := 128
const LEAF_SIZE := 128

## P28.5+ (art-direction fold-in): route-edge dressing counts. Every inch
## dressed, one draw call per system, all capped for the 60fps mobile budget.
const SHRUB_COUNT := 120      ## Layered plants, multiple heights.
const FLOWER_COUNT := 60      ## Bright blossom pops.
const FALLEN_LEAF_COUNT := 80 ## Autumn-floor litter.
const MULCH_COUNT := 40       ## Dark soil patches.

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 20260908
	_setup_environment()
	_setup_sun()
	_paint_ground()
	_paint_dirt_path() ## P28.5: worn track down the run line.
	_scatter_ground_detail() ## P28.5: clover + pebbles, instanced.
	_dress_route_edges() ## P28.5+: lush layered edging — no empty flats.
	_paint_fence()
	_paint_planters()
	paint_pergola()
	_plant_trees() ## P29: background oaks for depth.
	_paint_clouds() ## P29: billboard clouds — the sky was empty.
	_paint_wet_driveway() ## P29: the key art's wet reflective driveway.
	_paint_lawn_patches() ## P29: large tone patches — kills the "green mat".
	_plant_palm_hibiscus() ## P29: Tripo palm + hibiscus along the edges.


## P28.5+: keep the short dirt segment under the gecko. It only spans
## 80 m, so it must travel with the run; the 4 m texture tiles hide the
## motion (the pattern repeats, only the segment origin moves).
func _process(_delta: float) -> void:
	if _dirt_path == null or not is_instance_valid(_dirt_path):
		return
	if _gecko_ref == null or not is_instance_valid(_gecko_ref):
		_gecko_ref = get_parent().get_node_or_null("Gecko") as Node3D
		if _gecko_ref == null:
			return
	_dirt_path.position.z = _gecko_ref.position.z - 20.0
	_dirt_path.position.x = 0.0


## Blue Florida sky, warm haze at the horizon, sky-sourced ambient light,
## gentle depth fog so the long route fades naturally.
func _setup_environment() -> void:
	var we := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we == null:
		return
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.20, 0.44, 0.90)
	sky_mat.sky_horizon_color = Color(0.74, 0.83, 0.93)
	sky_mat.ground_bottom_color = Color(0.14, 0.18, 0.11)
	sky_mat.ground_horizon_color = Color(0.55, 0.66, 0.55)
	sky_mat.sun_angle_max = 25.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.74, 0.83, 0.93)
	env.fog_depth_begin = 35.0
	env.fog_depth_end = 130.0
	we.environment = env


## Warm afternoon sun; shadows stay on (the gecko's shadow grounds it).
func _setup_sun() -> void:
	var sun := get_parent().get_node_or_null("Sun") as DirectionalLight3D
	if sun == null:
		return
	sun.light_color = Color(1.0, 0.94, 0.83)
	sun.light_energy = 1.3
	sun.shadow_enabled = true


## P28.5: the lawn, rebuilt. One 512px tile covers 8x8 m (uv1_scale 15/70
## over the 120x560 plane), so BOTH scales live in one texture: large patch
## mottling (1-3 m color variation that kills the "green mat" feel) plus
## fine blade detail, with a generated normal map for close-up relief.
func _paint_ground() -> void:
	var ground := get_parent().get_node_or_null("Ground") as MeshInstance3D
	if ground == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _make_grass_texture()
	mat.normal_texture = _make_grass_normal()
	mat.roughness = 0.95
	mat.uv1_scale = Vector3(15, 70, 1) # 8 m tiles across the 120x560 lawn.
	ground.material_override = mat


## P28.5: a worn dirt path down the run line — the gecko's lane reads as
## traveled ground, not a texture seam. A separate thin plane (y=0.025,
## no z-fight at these distances) with a feathered-edge dirt texture.
## P28.5+: the path is a SHORT segment (80 m) that follows the gecko.
## A 560 m transparent quad breaks depth sorting in GL Compatibility
## (it rendered as a huge amber wedge); a short segment stays sorted.
var _dirt_path: MeshInstance3D
var _gecko_ref: Node3D

func _paint_dirt_path() -> void:
	var path := MeshInstance3D.new()
	path.name = "DirtPath"
	var pm := PlaneMesh.new()
	pm.size = Vector2(3.4, 80.0)
	path.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _make_dirt_texture()
	mat.roughness = 1.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.uv1_scale = Vector3(1, 20, 1) # 4 m tiles down the 80 m segment.
	path.material_override = mat
	path.position = Vector3(0, 0.025, -20)
	path.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Deferred: BackyardArt._ready runs while Main is still setting up
	# children, so direct add_child() fails (same as Atmosphere's tufts).
	get_parent().call_deferred("add_child", path)
	_dirt_path = path


## P28.5: scattered clover tufts + pebbles along the track edges. Two
## MultiMeshes (one draw call each), capped counts, one shared material
## each, per-instance tint variation. Shadows off — they're centimeters.
func _scatter_ground_detail() -> void:
	_rng.seed = 20260909
	var parent := get_parent()
	# Clover: alpha-cutout quads with a painted 3-leaf cluster texture.
	var clover_tex := _make_clover_texture()
	var clover_mat := StandardMaterial3D.new()
	clover_mat.albedo_texture = clover_tex
	clover_mat.roughness = 1.0
	clover_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	clover_mat.alpha_scissor_threshold = 0.5
	clover_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.13)
	quad.material = clover_mat
	var clover_mm := MultiMesh.new()
	clover_mm.transform_format = MultiMesh.TRANSFORM_3D
	clover_mm.use_colors = true
	clover_mm.mesh = quad
	clover_mm.instance_count = 150
	for i in 150:
		var x := _rng.randf_range(-8.0, 8.0)
		if absf(x) < 1.9:
			x = signf(x if x != 0.0 else 1.0) * _rng.randf_range(1.9, 8.0)
		var s := _rng.randf_range(0.7, 1.4)
		var t := Transform3D(
			Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s, s)),
			Vector3(x, 0.02, _rng.randf_range(-488.0, 60.0)))
		clover_mm.set_instance_transform(i, t)
		var tint := _rng.randf_range(0.75, 1.1)
		clover_mm.set_instance_color(i, Color(0.5 * tint, 0.85 * tint, 0.35 * tint))
	var clover := MultiMeshInstance3D.new()
	clover.name = "CloverScatter"
	clover.multimesh = clover_mm
	clover.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.call_deferred("add_child", clover)
	# Pebbles: tiny flattened boxes, tinted per instance.
	var peb_mat := StandardMaterial3D.new()
	peb_mat.albedo_color = Color(0.55, 0.5, 0.42)
	peb_mat.roughness = 1.0
	var peb := BoxMesh.new()
	peb.size = Vector3(0.07, 0.035, 0.055)
	peb.material = peb_mat
	var peb_mm := MultiMesh.new()
	peb_mm.transform_format = MultiMesh.TRANSFORM_3D
	peb_mm.use_colors = true
	peb_mm.mesh = peb
	peb_mm.instance_count = 90
	for i in 90:
		var s := _rng.randf_range(0.6, 1.6)
		var t := Transform3D(
			Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s, s)),
			Vector3(_rng.randf_range(-8.0, 8.0), 0.015,
				_rng.randf_range(-488.0, 60.0)))
		peb_mm.set_instance_transform(i, t)
		var g := _rng.randf_range(0.35, 0.7)
		peb_mm.set_instance_color(i, Color(g, g * 0.94, g * 0.82))
	var pebbles := MultiMeshInstance3D.new()
	pebbles.name = "PebbleScatter"
	pebbles.multimesh = peb_mm
	pebbles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.call_deferred("add_child", pebbles)


## P28.5+ (art-direction fold-in): the reference is LUSH — every inch dressed.
## P29: the flat route-edge shrub quads are replaced by REAL instanced Tripo
## bushes (round + tall hedge variants) — actual 3D foliage, one draw call
## per variant. Falls back to the old quads if a GLB is missing.
func _dress_route_edges() -> void:
	_rng.seed = 20260910
	var parent := get_parent()
	_dress_bushes(parent)
	_dress_flowers(parent)
	_dress_litter(parent)
	_dress_mulch(parent)


## P29: real 3D bushes. Two variants alternate along both route edges;
## heights 0.5-1.8 m, a ragged layered wall of actual foliage.
## P29: real 3D bushes — a ragged layered wall of actual foliage along both
## route edges. Instance split favors the lighter hedge (bush_tall, 4k
## verts: 80) over the heavier round shrub (bush_round, 13.5k verts: 40).
func _dress_bushes(parent: Node) -> void:
	var variants := ["bush_tall", "bush_round"]
	var counts := [80, 40]
	var built := 0
	for vi in variants.size():
		var merged := ModelSwap.merge_model_mesh(variants[vi], 60000)
		if merged == null:
			continue
		var count: int = counts[vi]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = merged
		mm.instance_count = count
		for i in count:
			var side := 1.0 if (i + vi) % 2 == 0 else -1.0
			var bscale := _rng.randf_range(0.8, 1.9)
			var t := Transform3D(
				Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(bscale, bscale, bscale)),
				Vector3(side * _rng.randf_range(3.0, 9.0), 0.0,
					_rng.randf_range(-488.0, 60.0)))
			mm.set_instance_transform(i, t)
			var tint := _rng.randf_range(0.75, 1.1)
			mm.set_instance_color(i, Color(tint, tint, tint))
		var inst := MultiMeshInstance3D.new()
		inst.name = "RouteEdgeBush%d" % vi
		inst.multimesh = mm
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.call_deferred("add_child", inst)
		built += 1
	if built == 0:
		_dress_shrub_quad_fallback(parent)


## P29 fallback: the old flat leaf quads if the bush GLBs are missing.
func _dress_shrub_quad_fallback(parent: Node) -> void:
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_texture = _make_leaf_texture()
	leaf_mat.roughness = 0.9
	leaf_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	leaf_mat.alpha_scissor_threshold = 0.5
	leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var shrub_quad := QuadMesh.new()
	shrub_quad.size = Vector2(0.8, 0.9)
	shrub_quad.material = leaf_mat
	var shrub_mm := MultiMesh.new()
	shrub_mm.transform_format = MultiMesh.TRANSFORM_3D
	shrub_mm.use_colors = true
	shrub_mm.mesh = shrub_quad
	shrub_mm.instance_count = SHRUB_COUNT
	for i in SHRUB_COUNT:
		var side := 1.0 if i % 2 == 0 else -1.0
		var s := _rng.randf_range(0.8, 1.9)
		var t := Transform3D(
			Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s, s)),
			Vector3(side * _rng.randf_range(3.0, 9.0), 0.45 * s,
				_rng.randf_range(-488.0, 60.0)))
		shrub_mm.set_instance_transform(i, t)
		var tint := _rng.randf_range(0.7, 1.15)
		shrub_mm.set_instance_color(i,
			Color(0.45 * tint, 0.8 * tint, 0.3 * tint))
	var shrubs := MultiMeshInstance3D.new()
	shrubs.name = "RouteEdgeShrubs"
	shrubs.multimesh = shrub_mm
	shrubs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.call_deferred("add_child", shrubs)


## P29: real 3D flower clusters (Tripo) along the route edges; falls back
## to the painted blossom quads if the GLB is missing.
func _dress_flowers(parent: Node) -> void:
	var merged := ModelSwap.merge_model_mesh("flowers", 40000)
	if merged == null:
		_dress_flower_quad_fallback(parent)
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = merged
	mm.instance_count = FLOWER_COUNT
	for i in FLOWER_COUNT:
		var side := 1.0 if i % 2 == 0 else -1.0
		var s := _rng.randf_range(0.5, 1.0)
		var t := Transform3D(
			Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s, s)),
			Vector3(side * _rng.randf_range(2.0, 7.0), 0.0,
				_rng.randf_range(-488.0, 60.0)))
		mm.set_instance_transform(i, t)
		var tint := _rng.randf_range(0.85, 1.15)
		mm.set_instance_color(i, Color(tint, tint, tint))
	var inst := MultiMeshInstance3D.new()
	inst.name = "RouteEdgeFlowers"
	inst.multimesh = mm
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.call_deferred("add_child", inst)


## P29 fallback: the painted blossom quads.
func _dress_flower_quad_fallback(parent: Node) -> void:
	var flower_mat := StandardMaterial3D.new()
	flower_mat.albedo_texture = _make_flower_texture()
	flower_mat.roughness = 0.8
	flower_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	flower_mat.alpha_scissor_threshold = 0.5
	flower_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var flower_quad := QuadMesh.new()
	flower_quad.size = Vector2(0.2, 0.24)
	flower_quad.material = flower_mat
	var flower_mm := MultiMesh.new()
	flower_mm.transform_format = MultiMesh.TRANSFORM_3D
	flower_mm.use_colors = true
	flower_mm.mesh = flower_quad
	flower_mm.instance_count = FLOWER_COUNT
	var palette := [Color(1.0, 0.3, 0.25), Color(1.0, 0.85, 0.25),
		Color(1.0, 0.55, 0.75), Color(1.0, 1.0, 1.0)]
	for i in FLOWER_COUNT:
		var side := 1.0 if i % 2 == 0 else -1.0
		var s := _rng.randf_range(0.7, 1.3)
		var t := Transform3D(
			Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s, s)),
			Vector3(side * _rng.randf_range(2.0, 7.0), 0.12 * s,
				_rng.randf_range(-488.0, 60.0)))
		flower_mm.set_instance_transform(i, t)
		flower_mm.set_instance_color(i, palette[i % palette.size()])
	var flowers := MultiMeshInstance3D.new()
	flowers.name = "RouteEdgeFlowers"
	flowers.multimesh = flower_mm
	flowers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.call_deferred("add_child", flowers)


## Fallen leaves: flat quads on the lawn, autumn browns/oranges.
func _dress_litter(parent: Node) -> void:
	var leaf_lit_mat := StandardMaterial3D.new()
	leaf_lit_mat.albedo_texture = _make_clover_texture()
	leaf_lit_mat.roughness = 1.0
	leaf_lit_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	leaf_lit_mat.alpha_scissor_threshold = 0.5
	leaf_lit_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var flat_quad := QuadMesh.new()
	flat_quad.size = Vector2(0.14, 0.14)
	flat_quad.material = leaf_lit_mat
	var flat_mm := MultiMesh.new()
	flat_mm.transform_format = MultiMesh.TRANSFORM_3D
	flat_mm.use_colors = true
	flat_mm.mesh = flat_quad
	flat_mm.instance_count = FALLEN_LEAF_COUNT
	for i in FALLEN_LEAF_COUNT:
		var flat := Basis(Vector3.UP, _rng.randf() * TAU) \
			* Basis(Vector3.RIGHT, -PI / 2.0)
		var s := _rng.randf_range(0.7, 1.6)
		var t := Transform3D(flat.scaled(Vector3(s, s, s)),
			Vector3(_rng.randf_range(-9.0, 9.0), 0.03,
				_rng.randf_range(-488.0, 60.0)))
		flat_mm.set_instance_transform(i, t)
		flat_mm.set_instance_color(i, Color(
			_rng.randf_range(0.5, 0.72), _rng.randf_range(0.28, 0.45),
			_rng.randf_range(0.12, 0.25)))
	var litter := MultiMeshInstance3D.new()
	litter.name = "FallenLeaves"
	litter.multimesh = flat_mm
	litter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.call_deferred("add_child", litter)


## Mulch: dark soil patches breaking the lawn's green.
func _dress_mulch(parent: Node) -> void:
	var mulch_mat := StandardMaterial3D.new()
	mulch_mat.albedo_texture = _make_soil_texture()
	mulch_mat.roughness = 1.0
	var mulch_quad := QuadMesh.new()
	mulch_quad.size = Vector2(0.55, 0.55)
	mulch_quad.material = mulch_mat
	var mulch_mm := MultiMesh.new()
	mulch_mm.transform_format = MultiMesh.TRANSFORM_3D
	mulch_mm.mesh = mulch_quad
	mulch_mm.instance_count = MULCH_COUNT
	for i in MULCH_COUNT:
		var flat := Basis(Vector3.UP, _rng.randf() * TAU) \
			* Basis(Vector3.RIGHT, -PI / 2.0)
		var s := _rng.randf_range(0.8, 2.2)
		var side := 1.0 if i % 2 == 0 else -1.0
		var t := Transform3D(flat.scaled(Vector3(s, s, s)),
			Vector3(side * _rng.randf_range(2.5, 8.0), 0.02,
				_rng.randf_range(-488.0, 60.0)))
		mulch_mm.set_instance_transform(i, t)
	var mulch := MultiMeshInstance3D.new()
	mulch.name = "MulchPatches"
	mulch.multimesh = mulch_mm
	mulch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.call_deferred("add_child", mulch)


## P25: the finish-gate fence becomes REAL fence sections — two weathered
## picket runs tiled across the 14 m gate, full 5 m collision height.
## The old textured box is hidden; collision is untouched.
func _paint_fence() -> void:
	var fence := get_parent().get_node_or_null("Fence") as Node3D
	if fence == null:
		return
	var mi := fence.get_node_or_null("MeshInstance3D") as MeshInstance3D
	var spec: Dictionary = ModelSwap.MODELS["fence"]
	var packed: PackedScene = load(spec["path"])
	if packed == null:
		_paint_fence_fallback(mi)
		return
	if mi != null:
		mi.visible = false
	# Native: 1.0 m long (Z), 0.54 m tall. Scale to the 5 m gate height,
	# rotate Z-length onto X, tile two runs across the 14 m width.
	var size: Vector3 = spec["size"]
	var s: float = 5.0 / size.y
	var section_len: float = size.z * s
	for i in 2:
		var inst: Node = packed.instantiate()
		var wrap := Node3D.new()
		wrap.name = "FenceRun%d" % (i + 1)
		wrap.add_child(inst)
		inst.scale = Vector3.ONE * s
		inst.position.y = -float(spec["min_y"]) * s
		wrap.rotation.y = PI / 2.0
		wrap.position = Vector3((i - 0.5) * section_len, -2.5, 0)
		fence.add_child(wrap)


## P25 fallback: P24's wood texture if the fence model is missing.
func _paint_fence_fallback(mi: MeshInstance3D) -> void:
	if mi == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _make_wood_texture()
	mat.roughness = 0.9
	mat.uv1_scale = Vector3(10, 1.6, 1)
	mi.material_override = mat


## P25: planter boxes become REAL raised beds (Tripo timber + soil) with REAL
## plants (two variants, alternating). The old box mesh is hidden; the
## P24 soil slab + quad plants are skipped. Collision is untouched.
func _paint_planters() -> void:
	var bed_spec: Dictionary = ModelSwap.MODELS["bed"]
	var bed_packed: PackedScene = load(bed_spec["path"])
	for pname in ["PlanterBoxA", "PlanterBoxB"]:
		var pb := get_parent().get_node_or_null(pname) as Node3D
		if pb == null:
			continue
		var mi := pb.get_node_or_null("MeshInstance3D") as MeshInstance3D
		if bed_packed == null:
			_paint_planter_fallback(pb, mi)
			continue
		if mi != null:
			mi.visible = false
		# Bed model: 1.0 m long (Z). Scale to the 1.2 m planter footprint.
		var bed_size: Vector3 = bed_spec["size"]
		var bs: float = 1.2 / maxf(bed_size.x, bed_size.z)
		var bed_wrap := Node3D.new()
		bed_wrap.name = "BedModel"
		var bed_inst: Node = bed_packed.instantiate()
		bed_wrap.add_child(bed_inst)
		bed_inst.scale = Vector3.ONE * bs
		bed_inst.position.y = -float(bed_spec["min_y"]) * bs
		bed_wrap.position = Vector3(0, -0.3, 0) # Planter node sits at y=0.3.
		pb.add_child(bed_wrap)
		_add_model_plants(bed_wrap, bs)


## Four real plants per bed, alternating the two Tripo variants.
func _add_model_plants(bed_wrap: Node3D, bed_scale: float) -> void:
	var variants := ["plant_a", "plant_b"]
	var spots := [Vector3(-0.3, 0, -0.25), Vector3(0.3, 0, -0.25),
		Vector3(-0.3, 0, 0.25), Vector3(0.3, 0, 0.25)]
	var soil_top: float = 0.25 * bed_scale + 0.02
	for i in spots.size():
		var v: Node3D = ModelSwap.make_visual(variants[i % 2], 0.5)
		if v == null:
			continue
		v.name = "Plant%d" % (i + 1)
		v.position = Vector3(spots[i].x, soil_top, spots[i].z)
		v.rotation.y = _rng.randf() * TAU
		bed_wrap.add_child(v)


## P25 fallback: P24's wood box + soil slab + quad plants if models missing.
func _paint_planter_fallback(pb: Node3D, mi: MeshInstance3D) -> void:
	var wood := _make_wood_texture()
	var soil := _make_soil_texture()
	var leaf := _make_leaf_texture()
	if mi != null:
		var wmat := StandardMaterial3D.new()
		wmat.albedo_texture = wood
		wmat.roughness = 0.9
		wmat.uv1_scale = Vector3(1.5, 1, 1)
		mi.material_override = wmat
	_add_soil_and_plants(pb, soil, leaf)


func _add_soil_and_plants(pb: Node3D, soil_tex: Texture2D, leaf_tex: Texture2D) -> void:
	var soil_mat := StandardMaterial3D.new()
	soil_mat.albedo_texture = soil_tex
	soil_mat.roughness = 1.0
	var slab := MeshInstance3D.new()
	slab.name = "SoilSlab"
	var bm := BoxMesh.new()
	bm.size = Vector3(1.14, 0.1, 1.14)
	bm.material = soil_mat
	slab.mesh = bm
	slab.position = Vector3(0, 0.32, 0)
	pb.add_child(slab)
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_texture = leaf_tex
	leaf_mat.roughness = 0.9
	leaf_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	leaf_mat.alpha_scissor_threshold = 0.5
	leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 5:
		var plant := _make_plant(leaf_mat)
		plant.name = "Plant%d" % (i + 1)
		plant.position = Vector3(
			_rng.randf_range(-0.36, 0.36), 0.37, _rng.randf_range(-0.36, 0.36))
		plant.rotation.y = _rng.randf() * TAU
		var s := _rng.randf_range(0.8, 1.25)
		plant.scale = Vector3(s, s * _rng.randf_range(0.9, 1.3), s)
		pb.add_child(plant)


## One plant = two crossed alpha-cutout quads (4 tris, trivial cost).
func _make_plant(mat: Material) -> Node3D:
	var p := Node3D.new()
	p.name = "Plant"
	for r in 2:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.5, 0.55)
		qm.material = mat
		q.mesh = qm
		q.position = Vector3(0, 0.27, 0)
		q.rotation.y = r * PI / 2.0
		p.add_child(q)
	return p


## P29: three big Florida oaks at the yard's edges — background depth so
## the horizon isn't an empty gradient. Individual placements (not a
## MultiMesh): three draw calls, real models via ModelSwap.
func _plant_trees() -> void:
	var parent := get_parent()
	var spots := [
		Vector3(-14.0, 0.0, -120.0), Vector3(16.0, 0.0, -260.0),
		Vector3(-17.0, 0.0, -400.0),
	]
	for i in spots.size():
		var tree := ModelSwap.make_visual("tree", 9.0)
		if tree == null:
			continue
		tree.name = "Oak%d" % (i + 1)
		tree.position = spots[i]
		tree.rotation.y = _rng.randf() * TAU
		parent.call_deferred("add_child", tree)


## P29: soft billboard clouds drifting nowhere (static — scope control),
## one shared material, six quads high above the route. The flat blue sky
## was the other half of the "flat world" complaint.
func _paint_clouds() -> void:
	var parent := get_parent()
	var cloud_tex := _make_cloud_texture()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = cloud_tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.92)
	var spots: Array[Vector4] = [
		Vector4(-40.0, 42.0, -140.0, 34.0), Vector4(30.0, 50.0, -220.0, 44.0),
		Vector4(-25.0, 38.0, -320.0, 28.0), Vector4(45.0, 46.0, -80.0, 30.0),
		Vector4(5.0, 55.0, -420.0, 52.0), Vector4(-50.0, 44.0, -40.0, 26.0),
	]
	for i in spots.size():
		var q := MeshInstance3D.new()
		q.name = "Cloud%d" % (i + 1)
		var qm := QuadMesh.new()
		var w: float = spots[i].w
		qm.size = Vector2(w, w * 0.45)
		qm.material = mat
		q.mesh = qm
		q.position = Vector3(spots[i].x, spots[i].y, spots[i].z)
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.call_deferred("add_child", q)


## A soft multi-lobed cloud puff on transparency.
func _make_cloud_texture() -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var lobes := [
		[0.35, 0.55, 0.22], [0.5, 0.48, 0.28], [0.65, 0.55, 0.22],
		[0.45, 0.62, 0.20], [0.58, 0.62, 0.18],
	]
	for y in n:
		for x in n:
			var u := float(x) / n
			var v := float(y) / n
			var d := 1.0
			for lobe in lobes:
				var la: Array = lobe
				var dx := (u - float(la[0])) / float(la[2])
				var dy := (v - float(la[1])) / (float(la[2]) * 0.62)
				d = minf(d, sqrt(dx * dx + dy * dy))
			if d < 1.0:
				var edge := _hash(x, y, 211)
				var a := clampf((1.0 - d) * 1.6 - edge * 0.25, 0.0, 1.0)
				var shade := 0.92 + (1.0 - d) * 0.08
				img.set_pixel(x, y, Color(shade, shade, shade, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## The P20 pergola keeps its climbable boxes; they just look like wood now.
func paint_pergola() -> void:
	var level := get_parent().get_node_or_null("Level")
	if level == null:
		return
	var pergola := level.get_node_or_null("Pergola")
	if pergola == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _make_wood_texture()
	mat.roughness = 0.9
	for body in pergola.get_children():
		for c in body.get_children():
			if c is MeshInstance3D:
				(c as MeshInstance3D).material_override = mat


# ---------------------------------------------------------------- textures

## P28.5: one tile = 8x8 m of lawn. Three scales baked in: broad patch
## mottling (1-3 m, kills the flat "mat"), clump variation (~25 cm), and
## short blade strokes + grain for gecko-height close-ups.
func _make_grass_texture() -> ImageTexture:
	var n := GRASS_SIZE # 512; one tile = 8x8 m.
	# Coarse value-noise grids, sampled per pixel (cheap): broad 1-3 m
	# patch mottling + medium clumps. Fine grain stays per-pixel hash.
	var broad := PackedFloat32Array()
	broad.resize(4 * 4)
	var mid := PackedFloat32Array()
	mid.resize(8 * 8)
	for gy in 4:
		for gx in 4:
			broad[gy * 4 + gx] = _pvnoise(gx * 1.0, gy * 1.0, 11, 4, 4)
	for gy in 8:
		for gx in 8:
			mid[gy * 8 + gx] = _pvnoise(gx * 1.0 + 13.0, gy * 1.0, 23, 8, 8)
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var u := float(x) / n
			var v := float(y) / n
			var patch := _sample_grid(broad, 4, u * 4.0, v * 4.0)
			var patch2 := _sample_grid(mid, 8, u * 8.0, v * 8.0)
			var clump := _hash(x / 8, y / 8, 91) # ~12 cm clumps.
			var grain := _hash(x, y, 37)
			var tone := (patch - 0.5) * 0.44 + (patch2 - 0.5) * 0.22 \
				+ (clump - 0.5) * 0.12 + (grain - 0.5) * 0.08
			# Yellow-green dry patches vs deep green lush patches.
			# P28.5+: deepened slightly so the worn dirt path reads clearly.
			var r := (0.26 + tone * 0.55) * 0.94
			var g := (0.44 + tone * 0.42) * 0.94
			var b := (0.15 + tone * 0.18) * 0.94
			img.set_pixel(x, y, Color(r, g, b))
	# Short blade strokes for a lawn feel at gecko height.
	for i in 2600:
		var x := _rng.randi_range(0, n - 1)
		var y := _rng.randi_range(0, n - 1)
		var dark := _rng.randf() < 0.6
		for k in _rng.randi_range(2, 6):
			var yy := y + k
			if yy >= n:
				break
			var c := img.get_pixel(x, yy)
			img.set_pixel(x, yy, c * (0.80 if dark else 1.14))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## P28.5: normal map from noise — gives the lawn close-up relief under the
## low warm sun. Generated from a grayscale height field via Godot's
## bump-to-normal conversion (no shipped textures).
func _make_grass_normal() -> ImageTexture:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_R8)
	for y in n:
		for x in n:
			var u := float(x) / n
			var v := float(y) / n
			var h := _pvnoise(u * 24.0, v * 24.0, 41, 24, 24) * 0.6 \
				+ _pvnoise(u * 64.0, v * 64.0, 97, 64, 64) * 0.4
			var g8 := int(clampf(h, 0.0, 1.0) * 255.0)
			img.set_pixel(x, y, Color8(g8, g8, g8))
	img.bump_map_to_normal_map(2.0)
	return ImageTexture.create_from_image(img)


## P28.5: worn dirt — tan/brown noise with pebble speckles; horizontal
## alpha feather so the path melts into the lawn at its edges.
func _make_dirt_texture() -> ImageTexture:
	var n := 256
	var img := Image.create(n, n, true, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var edge := absf(float(x) / n - 0.5) * 2.0 # 0 center, 1 edge.
			var alpha := clampf(1.0 - (edge - 0.55) / 0.45, 0.0, 1.0)
			var mottle := _pvnoise(x / 28.0, y / 28.0, 131, 9, 9)
			var grain := _hash(x, y, 149)
			var v := 0.8 + (mottle - 0.5) * 0.5 + (grain - 0.5) * 0.35
			# Center is more worn (lighter, dustier); edges blend to grass.
			# P28.5+: sun-bleached sandy tone — the track line must read on
			# the deepened lawn (contrast rule in test_p28_5, >= 0.08).
			var wear := 1.0 - edge * 0.25
			img.set_pixel(x, y, Color(0.78 * v * wear, 0.60 * v * wear,
				0.40 * v * wear, alpha))
	# Pebble speckles.
	for i in 260:
		var x := _rng.randi_range(2, n - 3)
		var y := _rng.randi_range(2, n - 3)
		var g := _rng.randf_range(0.35, 0.75)
		img.set_pixel(x, y, Color(g, g * 0.95, g * 0.85, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## P28.5+: blossom cluster on transparency — white petals that take the
## per-instance tint (red/yellow/pink/white), yellow heart.
func _make_flower_texture() -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in 5:
		var cx := _rng.randf_range(16, n - 16)
		var cy := _rng.randf_range(16, n - 16)
		for k in 5:
			var ang := k * TAU / 5.0 + _rng.randf() * 0.5
			var px := cx + cos(ang) * 8.0
			var py := cy + sin(ang) * 8.0
			for yy in range(int(py) - 6, int(py) + 7):
				for xx in range(int(px) - 6, int(px) + 7):
					if xx < 0 or yy < 0 or xx >= n or yy >= n:
						continue
					var dx := xx - px
					var dy := yy - py
					if dx * dx + dy * dy <= 28.0:
						img.set_pixel(xx, yy, Color(0.95, 0.95, 0.95))
		for yy in range(int(cy) - 4, int(cy) + 5):
			for xx in range(int(cx) - 4, int(cx) + 5):
				if xx < 0 or yy < 0 or xx >= n or yy >= n:
					continue
				var dx := xx - cx
				var dy := yy - cy
				if dx * dx + dy * dy <= 14.0:
					img.set_pixel(xx, yy, Color(1.0, 0.85, 0.3))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## P28.5: a little 3-leaf clover cluster on transparency, alpha-scissored.
func _make_clover_texture() -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in 4:
		var cx := _rng.randf_range(14, n - 14)
		var cy := _rng.randf_range(14, n - 14)
		var shade := _rng.randf()
		var leaf := Color(0.16 + shade * 0.12, 0.42 + shade * 0.18,
			0.12 + shade * 0.08)
		for k in 3:
			var ang := _rng.randf() * TAU + k * TAU / 3.0
			var lx := cx + cos(ang) * 7.0
			var ly := cy + sin(ang) * 7.0
			for yy in range(int(ly) - 6, int(ly) + 7):
				for xx in range(int(lx) - 6, int(lx) + 7):
					if xx < 0 or yy < 0 or xx >= n or yy >= n:
						continue
					var dx := xx - lx
					var dy := yy - ly
					if dx * dx + dy * dy <= 30.0:
						img.set_pixel(xx, yy, leaf)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _make_wood_texture() -> ImageTexture:
	var n := WOOD_SIZE
	var planks := 8
	var pw := n / planks
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var plank := x / pw
			var ptone := _hash(plank, 7, 51)
			var grain := _pvnoise(x / 4.0, y / 64.0, 77, 64, 4)
			var streak := _hash(x / 2, y / 16, 63)
			var v := 0.85 + (ptone - 0.5) * 0.35 + (grain - 0.5) * 0.22 + (streak - 0.5) * 0.12
			var c := Color(0.52 * v, 0.36 * v, 0.23 * v)
			if x % pw < 2:
				c *= 0.55 # plank seam
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _make_soil_texture() -> ImageTexture:
	var n := SOIL_SIZE
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var grain := _hash(x, y, 71)
			var clump := _hash(x / 4, y / 4, 83)
			var v := 0.75 + (grain - 0.5) * 0.6 + (clump - 0.5) * 0.3
			img.set_pixel(x, y, Color(0.24 * v, 0.16 * v, 0.11 * v))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## A cluster of painted leaves on transparency; alpha-scissored in 3D.
func _make_leaf_texture() -> ImageTexture:
	var n := LEAF_SIZE
	var img := Image.create(n, n, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in 52:
		var cx := _rng.randf_range(14, n - 14)
		var cy := _rng.randf_range(20, n - 8)
		var rx := _rng.randf_range(5, 11)
		var ry := _rng.randf_range(9, 18)
		var ang := _rng.randf() * PI
		var shade := _rng.randf()
		var leaf := Color(0.16 + shade * 0.14, 0.38 + shade * 0.2, 0.12 + shade * 0.1)
		var ca := cos(ang)
		var sa := sin(ang)
		var x0 := int(max(0, cx - rx - 2))
		var x1 := int(min(n - 1, cx + rx + 2))
		var y0 := int(max(0, cy - ry - 2))
		var y1 := int(min(n - 1, cy + ry + 2))
		for yy in range(y0, y1 + 1):
			for xx in range(x0, x1 + 1):
				var dx := xx - cx
				var dy := yy - cy
				var lx := dx * ca + dy * sa
				var ly := -dx * sa + dy * ca
				if (lx * lx) / (rx * rx) + (ly * ly) / (ry * ry) <= 1.0:
					img.set_pixel(xx, yy, leaf)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ noise

func _hash(x: int, y: int, seed: int) -> float:
	var h: int = x * 374761393 + y * 668265263 + seed * 144269504088
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0x7fffffff) / 2147483647.0


## Tileable value noise: lattice wraps at (px, py) so textures tile cleanly.
func _pvnoise(x: float, y: float, seed: int, px: int, py: int) -> float:
	var xi := int(floorf(x))
	var yi := int(floorf(y))
	var xf: float = x - floorf(x)
	var yf: float = y - floorf(y)
	var u: float = xf * xf * (3.0 - 2.0 * xf)
	var v: float = yf * yf * (3.0 - 2.0 * yf)
	var x0 := posmod(xi, px)
	var y0 := posmod(yi, py)
	var x1 := posmod(xi + 1, px)
	var y1 := posmod(yi + 1, py)
	var a := _hash(x0, y0, seed)
	var b := _hash(x1, y0, seed)
	var c := _hash(x0, y1, seed)
	var d := _hash(x1, y1, seed)
	return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v


func _sample_grid(grid: PackedFloat32Array, gw: int, fx: float, fy: float) -> float:
	var x0 := posmod(int(floor(fx)), gw)
	var y0 := posmod(int(floor(fy)), gw)
	var x1 := (x0 + 1) % gw
	var y1 := (y0 + 1) % gw
	var tx: float = fx - floorf(fx)
	var ty: float = fy - floorf(fy)
	var a: float = grid[y0 * gw + x0]
	var b: float = grid[y0 * gw + x1]
	var c: float = grid[y1 * gw + x0]
	var d: float = grid[y1 * gw + x1]
	return a + (b - a) * tx + (c - a) * ty + (a - b - c + d) * tx * ty


# ------------------------------------------------- P29: wet driveway ----

## P29: the key art's WET REFLECTIVE DRIVEWAY. A stretch of Backyard Dash
## (z -40..-110, before the first dog) becomes dark wet concrete: low
## roughness + high specular so the low sun glints off it, plus glossy
## PUDDLE PATCHES whose baked sky-gradient fakes the mirror reflection
## (GL Compatibility has no real reflection probes — the gradient + sun
## glint reads as "wet" at a glance). VISUALS ONLY: no collision, no
## gameplay touch. Backyard Dash only — Fence Line never gets this node.
const WET_Z_MIN := -110.0
const WET_Z_MAX := -40.0
const PUDDLE_COUNT := 10


func _on_backyard_dash() -> bool:
	var gs := get_tree().root.get_node_or_null("GameState")
	if gs == null:
		return true ## Unit test / capture: default map is the backyard.
	return String(gs.get("current_map_id")) == "florida_backyard"


## P29: route swaps reuse the same BackyardArt node — show the wet driveway
## only on Backyard Dash, never on Fence Line.
func refresh_driveway_for_map() -> void:
	var wet := get_parent().get_node_or_null("WetDriveway")
	if wet != null:
		wet.visible = _on_backyard_dash()


func _paint_wet_driveway() -> void:
	if not _on_backyard_dash():
		return
	_rng.seed = 20260912
	var parent := get_parent()
	var wrap := Node3D.new()
	wrap.name = "WetDriveway"
	# The slab: dark wet concrete, glossy.
	var slab := MeshInstance3D.new()
	slab.name = "DrivewaySlab"
	var pm := PlaneMesh.new()
	pm.size = Vector2(14.0, WET_Z_MAX - WET_Z_MIN)
	slab.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _make_wet_concrete_texture()
	mat.roughness = 0.12 ## P29: glossy wet look.
	mat.metallic = 0.0
	## P29: Godot 4 has no specular property; the low roughness plus the
	## bright sky ambient gives the sun glint on the wet concrete.
	mat.uv1_scale = Vector3(2, 10, 1) # ~7 m tiles.
	slab.material_override = mat
	# P29: above the dirt path (y 0.025) — the driveway wins where they cross.
	slab.position = Vector3(0, 0.045, (WET_Z_MIN + WET_Z_MAX) / 2.0)
	slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wrap.add_child(slab)
	# Puddles: near-mirror discs with a baked sky gradient.
	var pud_mat := StandardMaterial3D.new()
	pud_mat.albedo_texture = _make_puddle_texture()
	pud_mat.roughness = 0.05 ## P29: near-mirror.
	pud_mat.metallic = 0.0
	## P29: Godot 4 has no specular property; near-zero roughness plus the
	## baked sky gradient IS the reflection — it reads as mirror at a glance.
	pud_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in PUDDLE_COUNT:
		var pd := MeshInstance3D.new()
		pd.name = "Puddle%d" % (i + 1)
		var qm := PlaneMesh.new()
		var w := _rng.randf_range(1.5, 4.2)
		qm.size = Vector2(w * _rng.randf_range(1.0, 1.7), w)
		pd.mesh = qm
		pd.material_override = pud_mat
		pd.position = Vector3(_rng.randf_range(-6.0, 6.0), 0.06,
			_rng.randf_range(WET_Z_MIN + 3.0, WET_Z_MAX - 3.0))
		pd.rotation.y = _rng.randf() * TAU
		pd.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wrap.add_child(pd)
	parent.call_deferred("add_child", wrap)


## Dark wet concrete: near-black blue-gray noise, expansion-joint lines,
## and damp sheen variation. Tileable via the shared value-noise helpers.
func _make_wet_concrete_texture() -> ImageTexture:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var mottle := _pvnoise(x / 34.0, y / 34.0, 311, 8, 8)
			var grain := _hash(x, y, 317)
			var v := 0.62 + (mottle - 0.5) * 0.55 + (grain - 0.5) * 0.22
			var c := Color(0.135 * v, 0.15 * v, 0.175 * v)
			# Expansion joints: dark lines every 64 px.
			if x % 64 < 2 or y % 64 < 2:
				c *= 0.55
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Puddle: an irregular blob whose albedo is a vertical sky gradient —
## pale blue at the top fading to dark water at the bottom. That gradient
## IS the fake mirror: at gecko height it reads as reflected sky, and the
## 0.05 roughness lets the low sun streak across it for real.
func _make_puddle_texture() -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := n / 2.0
	var cy := n / 2.0
	for y in n:
		for x in n:
			var dx := (x - cx) / cx
			var dy := (y - cy) / cy
			var r := sqrt(dx * dx + dy * dy)
			# Wobble the rim so it never reads as a perfect disc.
			var wob := 1.0 + (_pvnoise(x / 22.0, y / 22.0, 331, 6, 6) - 0.5) * 0.55
			var d := r / wob
			if d >= 1.0:
				continue
			var edge := clampf((1.0 - d) * 3.0, 0.0, 1.0) # Feathered rim.
			var sky := 1.0 - float(y) / n # 1 at texture top = sky.
			var c := Color(
				lerpf(0.07, 0.52, sky * sky),
				lerpf(0.09, 0.63, sky * sky),
				lerpf(0.12, 0.78, sky * sky))
			img.set_pixel(x, y, Color(c.r, c.g, c.b, edge))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# -------------------------------------------- P29: lawn tone patches ----

## P29: the honest P28 complaint — the lawn reads as a flat green "mat"
## with visible 8 m tiling. These 26 large (5-12 m) soft-edged tone patches
## sit just above the grass (y=0.015) and break the repetition with olive,
## deep-green, and sun-dried yellow variation. One MultiMesh, one draw call.
const LAWN_PATCH_COUNT := 26


func _paint_lawn_patches() -> void:
	_rng.seed = 20260913
	var parent := get_parent()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _make_soft_blob_texture()
	mat.roughness = 1.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = LAWN_PATCH_COUNT
	var tones := [
		Color(0.16, 0.34, 0.12), Color(0.42, 0.48, 0.16),
		Color(0.52, 0.52, 0.22), Color(0.20, 0.40, 0.14),
	]
	for i in LAWN_PATCH_COUNT:
		var flat := Basis(Vector3.UP, _rng.randf() * TAU) \
			* Basis(Vector3.RIGHT, -PI / 2.0)
		var s := _rng.randf_range(5.0, 12.0)
		var t := Transform3D(flat.scaled(Vector3(s, s, s)),
			Vector3(_rng.randf_range(-14.0, 14.0), 0.015,
				_rng.randf_range(-400.0, 20.0)))
		mm.set_instance_transform(i, t)
		var tone: Color = tones[i % tones.size()]
		mm.set_instance_color(i,
			Color(tone.r, tone.g, tone.b, _rng.randf_range(0.18, 0.30)))
	var patches := MultiMeshInstance3D.new()
	patches.name = "LawnPatches"
	patches.multimesh = mm
	patches.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.call_deferred("add_child", patches)


## Soft radial blob on transparency — shared by lawn patches.
func _make_soft_blob_texture() -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in n:
		for x in n:
			var dx := (float(x) / n - 0.5) * 2.0
			var dy := (float(y) / n - 0.5) * 2.0
			var d := sqrt(dx * dx + dy * dy)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a) # Smoothstep falloff.
			img.set_pixel(x, y, Color(1, 1, 1, a * 0.9))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# --------------------------------------- P29: palm + hibiscus edges ----

## P29: dense planting from the new Tripo models — palm sentinels layered
## deep at the route edges (background depth) and hibiscus bushes mid-line,
## plus extra plant_a/b so no stretch reads empty. One node per plant
## (single-surface GLBs, tamed metals via ModelSwap) — ~28 draw calls,
## capped and shadow-disciplined for the mobile budget. Missing GLBs are
## skipped silently (the quad systems underneath still dress the route).
const PALM_COUNT := 6
const HIBISCUS_COUNT := 10
const EDGE_PLANT_COUNT := 12


func _plant_palm_hibiscus() -> void:
	_rng.seed = 20260914
	var parent := get_parent()
	# Palms: tall background sentinels, well off the track.
	for i in PALM_COUNT:
		var palm := ModelSwap.make_visual("palm", 3.4)
		if palm == null:
			break
		palm.name = "PalmPlant%d" % (i + 1)
		var side := 1.0 if i % 2 == 0 else -1.0
		palm.position = Vector3(side * _rng.randf_range(9.0, 15.0), -0.06,
			_rng.randf_range(-350.0, -20.0))
		palm.scale = Vector3(0.78, 1.0, 0.78) # P29: slim the cubic Tripo palm.
		palm.rotation.y = _rng.randf() * TAU
		parent.call_deferred("add_child", palm)
	# Hibiscus: flowering bushes along the mid-line edges.
	for i in HIBISCUS_COUNT:
		var hb := ModelSwap.make_visual("hibiscus", 1.15)
		if hb == null:
			break
		hb.name = "Hibiscus%d" % (i + 1)
		var side := 1.0 if i % 2 == 0 else -1.0
		# P29: sink 0.16m to bury the Tripo pot; the bush reads as planted.
		hb.position = Vector3(side * _rng.randf_range(3.5, 8.5), -0.16,
			_rng.randf_range(-350.0, -10.0))
		hb.rotation.y = _rng.randf() * TAU
		parent.call_deferred("add_child", hb)
	# Extra real plants fill the near-edge gaps.
	var variants := ["plant_a", "plant_b"]
	for i in EDGE_PLANT_COUNT:
		var pl := ModelSwap.make_visual(variants[i % 2], 0.75)
		if pl == null:
			break
		pl.name = "EdgePlant%d" % (i + 1)
		var side := 1.0 if i % 2 == 0 else -1.0
		pl.position = Vector3(side * _rng.randf_range(2.6, 6.5), 0,
			_rng.randf_range(-350.0, -5.0))
		pl.rotation.y = _rng.randf() * TAU
		for c in pl.get_children():
			if c is Node3D:
				for m in (c as Node3D).find_children("*", "MeshInstance3D", true, false):
					(m as MeshInstance3D).cast_shadow = \
						GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.call_deferred("add_child", pl)
