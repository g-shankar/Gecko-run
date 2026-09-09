extends "res://scripts/systems/hazard_base.gd"
## Gecko Run — lawn mower hazard (spec P28).
##
## A push mower crosses the track on a fixed straight path (the bicycle
## crosser pattern). TELEGRAPH: high-contrast yellow/black warning stripes
## appear along its path and the engine buzz winds up — the mower also edges
## into view. ACTIVE: it crosses at a steady walking pace. The crossing is
## periodic, so after one pass you learn the rhythm.
##
## The Area3D node itself crosses; the stripe decal is a sibling so it stays
## at the crossing.

@export var cross_distance: float = 12.0 ## From x=-6 to x=+6.
@export var cross_speed: float = 7.0 ## Walking pace — slower than the bike.

var _stripes: MeshInstance3D
var _stripe_mat: StandardMaterial3D
var _engine: AudioStreamPlayer3D
var _direction: float = 1.0
var _start_x: float = 0.0
var _visual: Node3D ## P28: Tripo push-mower model wrapper (or primitive).


func _ready() -> void:
	idle_time = 2.5
	warn_time = 1.0
	active_time = cross_distance / cross_speed
	recovery_time = 0.8
	one_shot = false
	_start_x = position.x
	_build()
	super._ready()


func _build() -> void:
	# Hitbox: covers the mower deck. Child of the Area3D, so it crosses
	# with the mower and is only live during ACTIVE (base machine).
	var zone := CollisionShape3D.new()
	var zone_shape := BoxShape3D.new()
	zone_shape.size = Vector3(1.6, 1.1, 1.2)
	zone.shape = zone_shape
	zone.position = Vector3(0, 0.55, 0)
	add_child(zone)
	# Mower visual: P28 Tripo push-mower model. Primitive fallback below.
	_visual = Node3D.new()
	_visual.name = "MowerVisual"
	add_child(_visual)
	var model := ModelSwap.make_visual("mower", 1.7)
	if model == null:
		_build_primitive_mower()
	else:
		_visual.add_child(model)
	_face_travel_direction()
	# Warning stripes: high-contrast yellow/black chevron decal along the
	# path. A sibling so it stays put while the mower moves.
	_stripes = MeshInstance3D.new()
	var stripe_mesh := PlaneMesh.new()
	stripe_mesh.size = Vector2(cross_distance, 3.0) # Wide in z: readable
	_stripes.mesh = stripe_mesh # from the low chase camera.
	_stripe_mat = StandardMaterial3D.new()
	_stripe_mat.albedo_texture = _make_stripe_texture()
	_stripe_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_stripes.material_override = _stripe_mat
	add_sibling(_stripes)
	_stripes.global_position = Vector3(_start_x, 0.12, global_position.z)
	_stripes.visible = false
	# Engine: a procedural loopable buzz (no audio assets in the project).
	_engine = AudioStreamPlayer3D.new()
	_engine.name = "Engine"
	_engine.stream = _make_engine_buzz()
	_engine.volume_db = -10.0
	_engine.max_distance = 25.0
	add_child(_engine)


## Yellow/black diagonal hazard stripes, generated — no texture file needed.
func _make_stripe_texture() -> ImageTexture:
	var w := 128
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8) # No mipmaps:
	var yellow := Color(1.0, 0.8, 0.05, 1.0) # (avoids black un-generated levels
	var black := Color(0.05, 0.05, 0.05, 1.0) # at distance).
	for y in h:
		for x in w:
			var s: int = int((float(x) + float(y) * 2.0) / 16.0) % 2
			img.set_pixel(x, y, yellow if s == 0 else black)
	return ImageTexture.create_from_image(img)


## A short loopable engine buzz: 100 Hz fundamental (loops seamlessly at
## 0.5 s) plus a harmonic and a little grit.
func _make_engine_buzz() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.5
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var v := sin(TAU * 100.0 * t) * 0.55 \
			+ sin(TAU * 200.0 * t) * 0.25 \
			+ (randf() * 2.0 - 1.0) * 0.08
		v = clampf(v, -1.0, 1.0) * 0.5
		data.encode_s16(i * 2, int(v * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	return wav


## The Tripo mower's deck faces -Z natively (checked visually at import);
## rotate the wrapper so it faces the travel direction.
func _face_travel_direction() -> void:
	if _visual == null:
		return
	_visual.rotation.y = -PI / 2.0 if _direction > 0.0 else PI / 2.0


## The old primitive mower, kept as a fallback if the model is missing.
func _build_primitive_mower() -> void:
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.75, 0.12, 0.1, 1.0)
	red.roughness = 0.6
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.08, 0.08, 1.0)
	dark.roughness = 0.9
	# Deck: red box.
	var deck := MeshInstance3D.new()
	var deck_mesh := BoxMesh.new()
	deck_mesh.size = Vector3(1.2, 0.35, 0.9)
	deck.mesh = deck_mesh
	deck.material_override = red
	deck.position = Vector3(0, 0.35, 0)
	_visual.add_child(deck)
	# Wheels: four dark cylinders.
	for wx in [-0.45, 0.45]:
		for wz in [-0.35, 0.35]:
			var wheel := MeshInstance3D.new()
			var wheel_mesh := CylinderMesh.new()
			wheel_mesh.top_radius = 0.18
			wheel_mesh.bottom_radius = 0.18
			wheel_mesh.height = 0.1
			wheel.mesh = wheel_mesh
			wheel.material_override = dark
			wheel.rotation_degrees.x = 90.0
			wheel.position = Vector3(wx, 0.18, wz)
			_visual.add_child(wheel)
	# Handle: two angled bars + a grip.
	for hx in [-0.4, 0.4]:
		var bar := MeshInstance3D.new()
		var bar_mesh := BoxMesh.new()
		bar_mesh.size = Vector3(0.07, 1.1, 0.07)
		bar.mesh = bar_mesh
		bar.material_override = dark
		bar.position = Vector3(hx, 0.85, 0.55)
		bar.rotation_degrees.x = 35.0
		_visual.add_child(bar)


func _on_telegraph() -> void:
	_stripes.visible = true
	_face_travel_direction() # Alternate direction each pass; face it.
	if not _engine.playing:
		_engine.play()


func _on_idle() -> void:
	_stripes.visible = false
	_engine.stop()
	_direction = -_direction # Alternate crossing direction each pass.
	position.x = _start_x - _direction * cross_distance * 0.5


func _on_recover() -> void:
	_stripes.visible = false
	_engine.stop()


func _tick_phase(_delta: float) -> void:
	if phase == Phase.TELEGRAPH:
		var t: float = 1.0 - (_phase_timer / warn_time)
		# Edges into view, engine already buzzing.
		position.x = lerpf(
			_start_x - _direction * (cross_distance * 0.5 + 1.0),
			_start_x - _direction * cross_distance * 0.5, t)
	elif phase == Phase.ACTIVE:
		var t: float = 1.0 - (_phase_timer / active_time)
		position.x = lerpf(
			_start_x - _direction * cross_distance * 0.5,
			_start_x + _direction * cross_distance * 0.5, t)
