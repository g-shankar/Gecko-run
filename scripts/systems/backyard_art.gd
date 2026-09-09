extends Node3D
class_name BackyardArt
## P24: Florida backyard art pass — VISUALS ONLY.
##
## Runs once at scene start and re-skins the gray-box world: a procedural
## grass lawn, a wooden fence, planted garden beds, a Florida sky, and a
## warm shadow-casting sun. Every texture is generated in code (no binary
## assets, no import-pipeline risk). Collision shapes, spawn positions, and
## gameplay scripts are never touched.

const GRASS_SIZE := 384
const WOOD_SIZE := 256
const SOIL_SIZE := 128
const LEAF_SIZE := 128

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 20260908
	_setup_environment()
	_setup_sun()
	_paint_ground()
	_paint_fence()
	_paint_planters()
	_paint_pergola()


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


## The lawn: mottled procedural grass tiled every ~2 m.
func _paint_ground() -> void:
	var ground := get_parent().get_node_or_null("Ground") as MeshInstance3D
	if ground == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _make_grass_texture()
	mat.roughness = 0.95
	mat.uv1_scale = Vector3(60, 280, 1)
	ground.material_override = mat


## The finish-gate fence becomes weathered vertical planks.
func _paint_fence() -> void:
	var fence := get_parent().get_node_or_null("Fence") as Node3D
	if fence == null:
		return
	var mi := fence.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mi == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _make_wood_texture()
	mat.roughness = 0.9
	mat.uv1_scale = Vector3(10, 1.6, 1)
	mi.material_override = mat


## Planter boxes become garden beds: wood sides, soil top, leafy plants.
## Plants are decoration only — no collision, inside the box footprint.
func _paint_planters() -> void:
	var wood := _make_wood_texture()
	var soil := _make_soil_texture()
	var leaf := _make_leaf_texture()
	for pname in ["PlanterBoxA", "PlanterBoxB"]:
		var pb := get_parent().get_node_or_null(pname) as Node3D
		if pb == null:
			continue
		var mi := pb.get_node_or_null("MeshInstance3D") as MeshInstance3D
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
func _paint_pergola() -> void:
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

func _make_grass_texture() -> ImageTexture:
	var n := GRASS_SIZE
	var gw := 48
	var grid := PackedFloat32Array()
	grid.resize(gw * gw)
	for gy in gw:
		for gx in gw:
			grid[gy * gw + gx] = _pvnoise(gx * 8.0 / gw, gy * 8.0 / gw, 11, 8, 8)
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var fx := float(x) / n * gw
			var fy := float(y) / n * gw
			var mottle := _sample_grid(grid, gw, fx, fy)
			var clump := _hash(x / 3, y / 3, 91)
			var grain := _hash(x, y, 37)
			var g := 0.40 + (mottle - 0.5) * 0.20 + (clump - 0.5) * 0.10 + (grain - 0.5) * 0.08
			var r := 0.22 + (mottle - 0.5) * 0.14 + (clump - 0.5) * 0.08 + (grain - 0.5) * 0.06
			var b := 0.14 + (mottle - 0.5) * 0.07 + (grain - 0.5) * 0.05
			img.set_pixel(x, y, Color(r, g, b))
	# Short blade strokes for a lawn feel at gecko height.
	for i in 700:
		var x := _rng.randi_range(0, n - 1)
		var y := _rng.randi_range(0, n - 1)
		var dark := _rng.randf() < 0.6
		for k in _rng.randi_range(2, 5):
			var yy := y + k
			if yy >= n:
				break
			var c := img.get_pixel(x, yy)
			img.set_pixel(x, yy, c * (0.82 if dark else 1.12))
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
