extends "res://scripts/systems/hazard_base.gd"
## Gecko Run — bird hazard (spec P12).
##
## Death from above. IDLE: the bird circles overhead. TELEGRAPH: a dark
## ellipse (the bird's shadow) sweeps onto your lane and tracks you, 1.0 s.
## ACTIVE: the bird folds its wings and dives at the shadow, 0.5 s.
## RECOVERY: it flaps back up to circling height.
## The shadow is the dodge cue: if it's on you when the dive starts, move.

@export var circle_height: float = 8.0
@export var dive_speed: float = 16.0 ## How fast the dive falls (m/s).

var _bird: Node3D
var _shadow: MeshInstance3D
var _shadow_mat: StandardMaterial3D
var _target_x: float = 0.0
var _circle_t: float = 0.0


func _ready() -> void:
	idle_time = 2.5
	warn_time = 1.0
	active_time = 0.5
	recovery_time = 1.5
	one_shot = false
	_build()
	super._ready()


func _build() -> void:
	# Dive hit zone: at the shadow, on the ground.
	var zone := CollisionShape3D.new()
	var zone_shape := SphereShape3D.new()
	zone_shape.radius = 0.9
	zone.shape = zone_shape
	zone.position = Vector3(0, 0.6, 0)
	add_child(zone)
	# The bird: body + two wings + tail, dark silhouette.
	_bird = Node3D.new()
	_bird.position = Vector3(0, circle_height, 0)
	add_child(_bird)
	var body := MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.22
	body_mesh.height = 0.9
	body.mesh = body_mesh
	body.rotation_degrees.z = 90.0
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.1, 0.14, 1.0)
	body.material_override = dark
	_bird.add_child(body)
	for wx in [-0.55, 0.55]:
		var wing := MeshInstance3D.new()
		var wing_mesh := BoxMesh.new()
		wing_mesh.size = Vector3(0.9, 0.06, 0.45)
		wing.mesh = wing_mesh
		wing.position = Vector3(wx, 0.1, 0)
		wing.material_override = dark
		_bird.add_child(wing)
	# The telegraph shadow: dark ellipse on the grass.
	_shadow = MeshInstance3D.new()
	var shadow_mesh := PlaneMesh.new()
	shadow_mesh.size = Vector2(1.8, 1.8)
	_shadow.mesh = shadow_mesh
	_shadow_mat = StandardMaterial3D.new()
	_shadow_mat.albedo_color = Color(0.05, 0.05, 0.08, 0.0)
	_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow.material_override = _shadow_mat
	_shadow.position = Vector3(0, 0.03, 0)
	_shadow.visible = false
	add_child(_shadow)


func _on_telegraph() -> void:
	var gecko := get_tree().get_first_node_in_group("gecko") as Node3D
	if gecko != null:
		_target_x = clampf(gecko.global_position.x, -3.0, 3.0)
	_shadow.visible = true


func _on_idle() -> void:
	_shadow.visible = false


func _on_recover() -> void:
	_shadow.visible = false


func _tick_phase(delta: float) -> void:
	_circle_t += delta
	if phase == Phase.IDLE:
		# Circle overhead, waiting.
		_bird.position = Vector3(
			sin(_circle_t * 1.5) * 2.5, circle_height, cos(_circle_t * 1.1) * 2.0)
	elif phase == Phase.TELEGRAPH:
		var t: float = 1.0 - (_phase_timer / warn_time)
		# Shadow tracks you and darkens; bird holds, wings spread.
		var gecko := get_tree().get_first_node_in_group("gecko") as Node3D
		if gecko != null:
			_target_x = lerpf(_target_x, clampf(gecko.global_position.x, -3.0, 3.0), 0.06)
		position.x = _target_x
		_shadow_mat.albedo_color.a = lerpf(0.0, 0.6, t)
		var s: float = lerpf(0.5, 1.0, t)
		_shadow.scale = Vector3(s, 1.0, s)
		_bird.position = _bird.position.lerp(Vector3(_target_x, circle_height - 1.5, 0), 0.08)
	elif phase == Phase.ACTIVE:
		# Fold and dive: straight down at the shadow.
		_bird.position.y = maxf(0.5, _bird.position.y - dive_speed * delta)
		_bird.rotation_degrees.z = 45.0
		_shadow_mat.albedo_color.a = 0.6
	elif phase == Phase.RECOVERY:
		var t: float = 1.0 - (_phase_timer / recovery_time)
		_bird.position.y = lerpf(0.5, circle_height, t)
		_bird.rotation_degrees.z = 0.0
		_shadow_mat.albedo_color.a = lerpf(0.6, 0.0, t)
