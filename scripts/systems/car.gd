extends "res://scripts/systems/hazard_base.gd"
## Gecko Run — backing car set-piece (spec P11).
##
## One-shot: the car waits, then TELEGRAPH (reverse lights flash red + the
## body shudders, 1.5 s), then ACTIVE (it backs across the driveway into the
## middle of the track and parks there). It's wide — steer around the nose
## or dash past. After parking it stays dangerous (hits_always): running
## into a parked car still hurts.

@export var park_x: float = -0.5 ## Where it stops (middle-ish of the track).
@export var start_x: float = 6.0 ## Where it waits (off the track).

var _body: Node3D ## P25: was MeshInstance3D; now the car model wrapper (or primitive).
var _light_l: MeshInstance3D
var _light_r: MeshInstance3D
var _light_mat: StandardMaterial3D
var _from_x: float = 6.0


func _ready() -> void:
	idle_time = 2.0
	warn_time = 1.5
	active_time = 1.5
	recovery_time = 0.5
	one_shot = true
	hits_always = true
	_from_x = start_x
	_build()
	super._ready()
	position.x = start_x


func _build() -> void:
	# Hitbox: the whole car.
	var zone := CollisionShape3D.new()
	var zone_shape := BoxShape3D.new()
	zone_shape.size = Vector3(4.2, 1.6, 2.0)
	zone.shape = zone_shape
	zone.position = Vector3(0, 0.8, 0)
	add_child(zone)
	# Body: P25 real SUV model. Falls back to the primitive boxes if the GLB
	# fails to load. The telegraph shudder animates _body.position.x, which
	# works on the wrapper either way.
	_body = Node3D.new()
	_body.name = "CarVisual"
	add_child(_body)
	var model := ModelSwap.make_visual("car", 4.2)
	if model == null:
		_build_primitive_car()
	else:
		_body.add_child(model)
	# Reverse lights: two small red boxes on the rear (+X face). They flash
	# during TELEGRAPH and stay lit while backing up.
	_light_mat = StandardMaterial3D.new()
	_light_mat.albedo_color = Color(0.75, 0.08, 0.08, 1.0) ## P28.5+: hot red.
	_light_mat.emission_enabled = true
	_light_mat.emission = Color(1.0, 0.1, 0.1, 1.0)
	_light_mat.emission_energy_multiplier = 0.2
	for lz in [-0.6, 0.6]:
		var light := MeshInstance3D.new()
		var light_mesh := BoxMesh.new()
		light_mesh.size = Vector3(0.12, 0.25, 0.35)
		light.mesh = light_mesh
		light.position = Vector3(2.02, 0.75, lz)
		light.material_override = _light_mat
		add_child(light)
		if lz < 0.0:
			_light_l = light
		else:
			_light_r = light


## P25: the old primitive car, kept as a fallback if the model is missing.
func _build_primitive_car() -> void:
	# Body: long box, dusty blue.
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(4.0, 1.0, 1.8)
	body.mesh = body_mesh
	body.position = Vector3(0, 0.7, 0)
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.3, 0.45, 0.65, 1.0)
	body_mat.roughness = 0.4
	body_mat.metallic = 0.3
	body.material_override = body_mat
	_body.add_child(body)
	# Cabin.
	var cabin := MeshInstance3D.new()
	var cabin_mesh := BoxMesh.new()
	cabin_mesh.size = Vector3(2.0, 0.7, 1.6)
	cabin.mesh = cabin_mesh
	cabin.position = Vector3(-0.3, 1.5, 0)
	var cabin_mat := StandardMaterial3D.new()
	cabin_mat.albedo_color = Color(0.15, 0.2, 0.28, 1.0)
	cabin_mat.roughness = 0.2
	cabin_mat.metallic = 0.4
	cabin.material_override = cabin_mat
	_body.add_child(cabin)


func _on_telegraph() -> void:
	_from_x = position.x


func _tick_phase(_delta: float) -> void:
	if phase == Phase.TELEGRAPH:
		# Beep-beep: lights flash, body shudders.
		var flash: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.02)
		_light_mat.emission_energy_multiplier = lerpf(0.2, 4.0, flash) ## P28.5+: hot flash.
		_body.position.x = 0.05 * sin(Time.get_ticks_msec() * 0.05)
	elif phase == Phase.ACTIVE:
		var t: float = 1.0 - (_phase_timer / active_time)
		# Back up smoothly into the parking spot (ease-out).
		var e: float = 1.0 - (1.0 - t) * (1.0 - t)
		position.x = lerpf(_from_x, park_x, e)
		_light_mat.emission_energy_multiplier = 3.0
		_body.position.x = 0.0
	elif phase == Phase.RECOVERY or phase == Phase.IDLE:
		_light_mat.emission_energy_multiplier = 0.2
		_body.position.x = 0.0
