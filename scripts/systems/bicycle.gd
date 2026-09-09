extends "res://scripts/systems/hazard_base.gd"
## Gecko Run — bicycle hazard (spec P11).
##
## A bike crosses the track every few seconds. TELEGRAPH: a yellow lane
## glows across the track (plus the bike edges into view, ringing its bell).
## ACTIVE: the bike crosses at speed. The timing is periodic, so after one
## pass you can learn the rhythm and thread it or wait it out.
##
## The Area3D node itself crosses; the lane telegraph is added as a sibling
## so it stays put at the crossing.

@export var cross_distance: float = 12.0 ## From x=-6 to x=+6.
@export var cross_speed: float = 12.0 ## Crossing speed (m/s).

var _lane: MeshInstance3D
var _lane_mat: StandardMaterial3D
var _direction: float = 1.0
var _start_x: float = 0.0
var _visual: Node3D ## P25: Tripo bike+rider model wrapper (or primitive group).


func _ready() -> void:
	idle_time = 3.0
	warn_time = 1.0
	active_time = cross_distance / cross_speed
	recovery_time = 0.5
	one_shot = false
	_start_x = position.x
	_build()
	super._ready()


func _build() -> void:
	# Hitbox: direct child of the Area3D, covers bike + rider.
	var zone := CollisionShape3D.new()
	var zone_shape := BoxShape3D.new()
	zone_shape.size = Vector3(1.0, 1.6, 0.6)
	zone.shape = zone_shape
	zone.position = Vector3(0, 0.8, 0)
	add_child(zone)
	# Bike visual: P25 real model (rider on a city bike). Falls back to the
	# primitive frame/wheels/rider if the GLB fails to load.
	_visual = Node3D.new()
	_visual.name = "BikeVisual"
	add_child(_visual)
	var model := ModelSwap.make_visual("bicycle", 1.9)
	if model == null:
		_build_primitive_bike()
	else:
		_visual.add_child(model)
	_face_travel_direction()
	# Lane telegraph: yellow strip across the track. A sibling so it stays
	# at the crossing while the bike itself moves.
	_lane = MeshInstance3D.new()
	var lane_mesh := PlaneMesh.new()
	lane_mesh.size = Vector2(cross_distance + 2.0, 1.6)
	_lane.mesh = lane_mesh
	_lane_mat = StandardMaterial3D.new()
	_lane_mat.albedo_color = Color(1.0, 0.85, 0.1, 0.0)
	_lane_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_lane_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lane.material_override = _lane_mat
	add_sibling(_lane)
	_lane.global_position = global_position + Vector3(0, 0.03, 0)
	_lane.visible = false


## P25: the Tripo bike model faces -Z natively; rotate the wrapper so it
## faces the travel direction (+X when _direction is +1). Called whenever the
## direction flips so the rider never rides backwards.
func _face_travel_direction() -> void:
	if _visual == null:
		return
	_visual.rotation.y = -PI / 2.0 if _direction > 0.0 else PI / 2.0


## P25: the old primitive bike, kept as a fallback if the model is missing.
func _build_primitive_bike() -> void:
	# Frame: red box.
	var frame := MeshInstance3D.new()
	var frame_mesh := BoxMesh.new()
	frame_mesh.size = Vector3(1.6, 0.25, 0.25)
	frame.mesh = frame_mesh
	frame.position = Vector3(0, 0.7, 0)
	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.8, 0.1, 0.1, 1.0)
	frame.material_override = frame_mat
	_visual.add_child(frame)
	# Wheels: two dark cylinders.
	for wx in [-0.6, 0.6]:
		var wheel := MeshInstance3D.new()
		var wheel_mesh := CylinderMesh.new()
		wheel_mesh.top_radius = 0.35
		wheel_mesh.bottom_radius = 0.35
		wheel_mesh.height = 0.12
		wheel.mesh = wheel_mesh
		wheel.rotation_degrees.x = 90.0
		wheel.position = Vector3(wx, 0.35, 0)
		var wheel_mat := StandardMaterial3D.new()
		wheel_mat.albedo_color = Color(0.08, 0.08, 0.08, 1.0)
		wheel.material_override = wheel_mat
		_visual.add_child(wheel)
	# Rider: simple capsule silhouette.
	var rider := MeshInstance3D.new()
	var rider_mesh := CapsuleMesh.new()
	rider_mesh.radius = 0.22
	rider_mesh.height = 0.9
	rider.mesh = rider_mesh
	rider.position = Vector3(0, 1.25, 0)
	var rider_mat := StandardMaterial3D.new()
	rider_mat.albedo_color = Color(0.15, 0.25, 0.6, 1.0)
	rider.material_override = rider_mat
	_visual.add_child(rider)


func _on_telegraph() -> void:
	_lane.visible = true
	_face_travel_direction() # P25: rider faces the travel direction.


func _on_idle() -> void:
	_lane.visible = false
	_direction = -_direction # Alternate crossing direction each pass.
	position.x = _start_x - _direction * cross_distance * 0.5


func _on_recover() -> void:
	_lane.visible = false


func _tick_phase(_delta: float) -> void:
	if phase == Phase.TELEGRAPH:
		var t: float = 1.0 - (_phase_timer / warn_time)
		_lane_mat.albedo_color.a = lerpf(0.0, 0.5, t)
		# Bell: creep into view before the crossing.
		position.x = lerpf(
			_start_x - _direction * (cross_distance * 0.5 + 1.0),
			_start_x - _direction * cross_distance * 0.5, t)
	elif phase == Phase.ACTIVE:
		var t: float = 1.0 - (_phase_timer / active_time)
		position.x = lerpf(
			_start_x - _direction * cross_distance * 0.5,
			_start_x + _direction * cross_distance * 0.5, t)
		_lane_mat.albedo_color.a = 0.5
