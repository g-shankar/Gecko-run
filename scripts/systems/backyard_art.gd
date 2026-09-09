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
## Four more instanced systems along the route edges, one draw call each:
## layered shrubs at multiple heights, bright flowers, fallen leaves, mulch.
## Reuses the leaf/soil materials; per-instance tint for variety. Shadows off.
func _dress_route_edges() -> void:
	_rng.seed = 20260910
	var parent := get_parent()
	# Shrubs: single quads with the leaf-cluster texture, random yaw, heights
	# 0.4-1.7 m — a ragged layered wall of green both sides of the track.
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
	# Flowers: small blossom quads, per-instance petal color.
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
	# Fallen leaves: flat quads on the lawn, autumn browns/oranges.
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
	# Mulch: dark soil patches breaking the lawn's green.
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
