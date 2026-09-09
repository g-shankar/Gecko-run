extends Node3D
class_name ForegroundDressing
## P28.5+ (art-direction fold-in): layered-depth foreground framing.
##
## The Treasure Land key art frames its scene with overhanging branches at
## the top corners — dark near-camera silhouettes that make everything behind
## them feel deep. This is that, cheap: a "ForegroundDressing" group parented
## to the CAMERA itself (lens-attached, like a filter), so pieces sit exactly
## at the frame's top corners no matter how the camera pitches or banks.
## Pieces drift slowly down-and-toward the lens and recycle to the top —
## foliage brushing past — which reads as parallax against the world.
##
## READABILITY RULE (testable): every piece stays at the frame edges —
## |x| >= EDGE_MIN_X and z <= NEAR_MAX_Z in camera space — so the center
## third of the frame (gecko + hazards + track) is NEVER covered. Pieces are
## small (0.22-0.38 m), sparse (10), dark (near-camera silhouette look).
##
## Cost: 10 MeshInstances x 2 quads, one shared material. No shadows.

const PIECE_COUNT := 6
const EDGE_MIN_X := 0.40  ## Corner framing: never nearer the center than this.
const NEAR_MAX_Z := -0.70 ## Never closer to the lens than this (no fill-ups).
const DRIFT_DOWN := 0.05  ## m/s downward — foliage brushing past the lens.
const DRIFT_NEAR := 0.02  ## m/s toward the lens — the "looming past" feel.
const SWAY_AMP := 0.015

var _rng := RandomNumberGenerator.new()
var _pieces: Array[Node3D] = []
var _sway_t := 0.0
var _frond_mat: StandardMaterial3D


func _ready() -> void:
	_rng.seed = 20260910
	_frond_mat = StandardMaterial3D.new()
	_frond_mat.albedo_texture = _make_frond_texture()
	_frond_mat.roughness = 1.0
	# Alpha BLEND (not scissor): the leaves are painted with feathered edges
	# so they read as soft out-of-focus foliage, not hard cutouts.
	_frond_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_frond_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Unshaded + dark paint = near-camera silhouette, like the reference's
	# backlit overhanging branches. It never catches the sun weirdly.
	_frond_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in PIECE_COUNT:
		var p := Node3D.new()
		p.name = "Frond%d" % i
		for r in 2:
			var q := MeshInstance3D.new()
			var qm := QuadMesh.new()
			var s := _rng.randf_range(0.12, 0.18) ## Small: corner sprigs.
			qm.size = Vector2(s, s * _rng.randf_range(0.8, 1.2))
			qm.material = _frond_mat
			q.mesh = qm
			q.rotation.y = r * PI / 2.0 + _rng.randf_range(-0.2, 0.2)
			q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			p.add_child(q)
		p.set_meta("phase", _rng.randf() * TAU)
		_respawn_piece(p, true)
		_pieces.append(p)
		add_child(p)


func _process(delta: float) -> void:
	_sway_t += delta
	for p in _pieces:
		var phase: float = p.get_meta("phase")
		var bx: float = p.get_meta("base_x")
		p.position.y -= DRIFT_DOWN * delta
		p.position.z += DRIFT_NEAR * delta # Toward the lens (camera -Z fwd).
		p.position.x = bx + sin(_sway_t * 0.8 + phase) * SWAY_AMP
		if p.position.y < 0.30 or p.position.z > NEAR_MAX_Z:
			_respawn_piece(p)


## Frame top corners in camera space: x at the sides, y up, z ahead.
## `scatter` spreads the initial set through the band so the first frame
## already has framing; recycled pieces re-enter at the top, far out.
func _respawn_piece(p: Node3D, scatter: bool = false) -> void:
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	var bx := side * _rng.randf_range(EDGE_MIN_X + 0.02, 0.55)
	p.set_meta("base_x", bx)
	p.position = Vector3(
		bx,
		_rng.randf_range(0.32, 0.58) if scatter \
			else _rng.randf_range(0.42, 0.60),
		_rng.randf_range(-1.05, -0.80) if scatter \
			else _rng.randf_range(-1.05, -0.85))


## Thin twig stems with sparse small leaves, painted with feathered alpha
## edges — soft out-of-focus near-camera foliage, not hard cutouts.
func _make_frond_texture() -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for s in 3:
		var x0 := _rng.randf_range(20, n - 60)
		var y0 := _rng.randf_range(70, n - 20)
		var ang := _rng.randf_range(-1.1, -0.4)
		var stem_col := Color(0.05, 0.07, 0.04, 0.9)
		# The twig itself: a thin dark line.
		for k in 70:
			var cx := x0 + cos(ang) * k * 1.2
			var cy := y0 + sin(ang) * k * 1.2
			_paint_soft(img, n, cx, cy, 1.6, stem_col)
		# Sparse small leaves along it, feathered at the rim.
		for k in 7:
			var lx := x0 + cos(ang) * k * 11.0 + _rng.randf_range(-8, 8)
			var ly := y0 + sin(ang) * k * 11.0 + _rng.randf_range(-8, 8)
			var shade := _rng.randf()
			var leaf := Color(0.05 + shade * 0.05, 0.11 + shade * 0.08,
				0.04 + shade * 0.04, 0.85)
			_paint_soft(img, n, lx, ly, _rng.randf_range(4.0, 7.0), leaf)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Paint a soft radial dab: solid core fading to transparent at the rim.
func _paint_soft(img: Image, n: int, cx: float, cy: float, r: float,
		col: Color) -> void:
	var r0 := int(maxf(0.0, cx - r - 1.0))
	var r1 := int(minf(n - 1.0, cx + r + 1.0))
	var c0 := int(maxf(0.0, cy - r - 1.0))
	var c1 := int(minf(n - 1.0, cy + r + 1.0))
	for yy in range(c0, c1 + 1):
		for xx in range(r0, r1 + 1):
			var d := sqrt((xx - cx) * (xx - cx) + (yy - cy) * (yy - cy)) / r
			if d > 1.0:
				continue
			var a := col.a * clampf(1.2 - d * 1.2, 0.0, 1.0)
			var cur := img.get_pixel(xx, yy)
			var out_a := a + cur.a * (1.0 - a)
			if out_a <= 0.001:
				continue
			img.set_pixel(xx, yy, Color(
				(col.r * a + cur.r * cur.a * (1.0 - a)) / out_a,
				(col.g * a + cur.g * cur.a * (1.0 - a)) / out_a,
				(col.b * a + cur.b * cur.a * (1.0 - a)) / out_a, out_a))
